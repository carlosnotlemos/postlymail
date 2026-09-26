# frozen_string_literal: true

module Webhooks
  module Resend
    class ProcessarService < ApplicationService
      EVENTOS_MAPEADOS = {
        "email.sent" => :enviado,
        "email.delivered" => :entregue,
        "email.delivery_delayed" => :enviado,
        "email.bounced" => :falhou,
        "email.complained" => :rejeitado,
        "email.opened" => :entregue,
        "email.clicked" => :entregue
      }.freeze

      def initialize(
        webhook_log_ou_hash = nil,
        webhook_log: nil,
        payload: nil,
        evento: nil,
        desativar_marketing_em_falha: true,
        **kwargs
      )
        dados = kwargs.dup

        if webhook_log_ou_hash.is_a?(Hash)
          dados.merge!(webhook_log_ou_hash.symbolize_keys)
        elsif webhook_log_ou_hash.is_a?(WebhookLog)
          dados[:webhook_log] ||= webhook_log_ou_hash
        end

        dados[:webhook_log] = webhook_log if webhook_log.present?
        dados[:payload] = payload if payload.present?
        dados[:evento] = evento if evento.present?

        @webhook_log = dados[:webhook_log]
        @payload = normalizar_payload(dados[:payload] || @webhook_log&.payload)
        @evento = (dados[:evento] || @webhook_log&.evento || @payload["type"] || @payload[:type]).to_s.strip.downcase
        @desativar_marketing = kwargs.key?(:desativar_marketing_em_falha) ? kwargs[:desativar_marketing_em_falha] : desativar_marketing_em_falha
      end

      def call
        validacao = validar_parametros
        return validacao if validacao&.failure?

        executar_processamento
      end

      private

      def normalizar_payload(param)
        return {} if param.blank?
        param = param.to_unsafe_h if param.respond_to?(:to_unsafe_h)
        return param if param.is_a?(Hash)

        if param.is_a?(String)
          JSON.parse(param) rescue {}
        else
          param
        end
      end

      def validar_parametros
        if @payload.blank?
          return failure("Payload do Resend está vazio", error_code: :empty_payload)
        end

        if @evento.blank?
          return failure("Evento do Resend não identificado no payload", error_code: :empty_event)
        end

        nil
      end

      def extrair_dados_evento
        data = @payload["data"] || @payload[:data] || @payload
        data = data.is_a?(Hash) ? data : {}

        email_id = data["email_id"] || data[:email_id] || data["id"] || data[:id] || @payload["id"] || @payload[:id]
        destinatarios = Array(data["to"] || data[:to])
        destinatario_principal = destinatarios.first.to_s.strip.downcase.presence

        mensagem_erro = extrair_mensagem_erro(data)

        {
          email_id: email_id.to_s.strip.presence,
          destinatario: destinatario_principal,
          mensagem_erro: mensagem_erro,
          data: data
        }
      end

      def extrair_mensagem_erro(data)
        if @evento == "email.complained"
          return "Destinatário reportou o e-mail como spam (complaint)"
        end

        bounce_data = data["bounce"] || data[:bounce]
        if bounce_data.is_a?(Hash)
          msg = bounce_data["message"] || bounce_data[:message] || bounce_data["type"] || bounce_data[:type]
          return msg.to_s if msg.present?
        end

        data["message"] || data[:message] || data["error"] || data[:error] || (@evento == "email.bounced" ? "Falha na entrega do e-mail (bounce)" : nil)
      end

      def executar_processamento
        dados_evento = extrair_dados_evento
        email_id = dados_evento[:email_id]

        disparo = localizar_disparo(email_id, dados_evento[:destinatario])

        if disparo.nil?
          return success(
            recurso_localizado: false,
            evento: @evento,
            email_id: email_id,
            mensagem: "Nenhum disparo localizado para o email_id #{email_id}"
          )
        end

        novo_status = EVENTOS_MAPEADOS[@evento]

        if novo_status.nil?
          return success(
            recurso_localizado: true,
            disparo: disparo,
            evento: @evento,
            acao: :evento_ignorado,
            mensagem: "Evento '#{@evento}' não requer alteração de status"
          )
        end

        resultado_atualizacao = Disparos::AtualizarStatusService.call(
          disparo: disparo,
          status: novo_status,
          mensagem_erro: dados_evento[:mensagem_erro],
          forcar: %w[email.bounced email.complained].include?(@evento)
        )

        tratar_engajamento_ou_descadastro(disparo.cliente)

        if resultado_atualizacao.success?
          success(
            tipo_recurso: :disparo,
            disparo: disparo.reload,
            campanha: disparo.campanha,
            cliente: disparo.cliente,
            acao: acao_por_evento,
            status_disparo: disparo.status.to_sym,
            evento: @evento,
            email_id: email_id
          )
        else
          # Se a transição já foi superada (ex: entregue antes de sent), mantemos sucesso idempotente
          success(
            tipo_recurso: :disparo,
            disparo: disparo.reload,
            campanha: disparo.campanha,
            acao: :status_inalterado,
            motivo: resultado_atualizacao.error,
            evento: @evento
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure("Erro de validação no banco: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
      rescue StandardError => e
        failure("Erro inesperado ao processar webhook do Resend: #{e.message}", error_code: :unexpected_error)
      end

      def localizar_disparo(email_id, destinatario)
        if email_id.present?
          disparo = Disparo.find_by(identificador_externo: email_id)
          return disparo if disparo.present?
        end

        if destinatario.present?
          Disparo.where(destinatario: destinatario)
                 .where.not(status: %i[entregue rejeitado])
                 .order(created_at: :desc)
                 .first
        end
      end

      def tratar_engajamento_ou_descadastro(cliente)
        return if cliente.nil?

        case @evento
        when "email.complained", "email.bounced"
          if @desativar_marketing && cliente.aceita_marketing?
            cliente.update(aceita_marketing: false)
          end
        end
      end

      def acao_por_evento
        case @evento
        when "email.delivered" then :disparo_entregue
        when "email.sent" then :disparo_enviado
        when "email.bounced" then :disparo_falhou
        when "email.complained" then :disparo_rejeitado
        when "email.opened" then :disparo_aberto
        when "email.clicked" then :disparo_clicado
        else :status_atualizado
        end
      end
    end

    ProcessarWebhookService = ProcessarService
  end
end
