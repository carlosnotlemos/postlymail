# frozen_string_literal: true

module Webhooks
  class ProcessarService < ApplicationService
    PROVEDORES_HANDLERS = {
      asaas: "Webhooks::Asaas::ProcessarService",
      resend: "Webhooks::Resend::ProcessarService"
    }.freeze

    def initialize(
      webhook_log_ou_hash = nil,
      webhook_log: nil,
      id: nil,
      provedor: nil,
      payload: nil,
      evento: nil,
      identificador_externo: nil,
      forcar: false,
      **kwargs
    )
      dados = kwargs.dup

      if webhook_log_ou_hash.is_a?(Hash)
        dados.merge!(webhook_log_ou_hash.symbolize_keys)
      elsif webhook_log_ou_hash.is_a?(WebhookLog)
        dados[:webhook_log] ||= webhook_log_ou_hash
      elsif webhook_log_ou_hash.present? && !dados.key?(:webhook_log)
        dados[:webhook_log] = webhook_log_ou_hash
      end

      dados[:webhook_log] = webhook_log if webhook_log.present?
      dados[:id] = id if id.present?
      dados[:provedor] = provedor if provedor.present?
      dados[:payload] = payload if payload.present?
      dados[:evento] = evento if evento.present?
      dados[:identificador_externo] = identificador_externo if identificador_externo.present?

      @webhook_log_param = dados[:webhook_log] || dados[:webhook_log_id] || dados[:id]
      @forcar = kwargs.key?(:forcar) ? kwargs[:forcar] : (forcar || dados[:forcar] || false)

      @provedor_param = dados[:provedor]
      @payload_param = dados[:payload]
      @evento_param = dados[:evento]
      @identificador_externo_param = dados[:identificador_externo]

      @webhook_log = resolver_ou_inicializar_webhook_log
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if idempotencia_atingida?
        return success(
          webhook_log: @webhook_log,
          ja_processado: true,
          status: @webhook_log.status.to_sym,
          mensagem: "Webhook já foi processado anteriormente"
        )
      end

      if duplicado_ignorado?
        return success(
          webhook_log: @webhook_log,
          ignorado: true,
          status: :duplicado_ignorado,
          mensagem: "Webhook marcado como duplicado ignorado"
        )
      end

      if duplicado_detectado?
        marcar_como_duplicado!
        return success(
          webhook_log: @webhook_log,
          duplicado: true,
          status: :duplicado_ignorado,
          mensagem: "Evento duplicado já processado anteriormente para este provedor"
        )
      end

      executar_orquestracao
    end

    private

    def resolver_ou_inicializar_webhook_log
      log = resolver_webhook_log(@webhook_log_param)
      return log if log.present?

      if @provedor_param.present? && @payload_param.present?
        WebhookLog.create(
          provedor: normalizar_provedor(@provedor_param),
          payload: normalizar_payload(@payload_param),
          evento: @evento_param,
          identificador_externo: @identificador_externo_param,
          status: :pendente
        )
      end
    end

    def resolver_webhook_log(param)
      return param if param.is_a?(WebhookLog)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        WebhookLog.find_by(id: param.to_i)
      end
    end

    def normalizar_provedor(param)
      return nil if param.blank?

      param.to_s.downcase.strip
    end

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
      if @webhook_log.nil?
        return failure("WebhookLog não informado ou não encontrado", error_code: :webhook_log_not_found)
      end

      unless @webhook_log.persisted?
        return failure(
          "Falha ao registrar WebhookLog: #{@webhook_log.errors.full_messages.join(', ')}",
          error_code: :record_invalid
        )
      end

      if @webhook_log.provedor.blank?
        return failure("Provedor do webhook não informado", error_code: :provider_missing)
      end

      if @webhook_log.payload.blank?
        return failure("Payload do webhook está vazio", error_code: :payload_missing)
      end

      nil
    end

    def idempotencia_atingida?
      return false if @forcar

      @webhook_log.processado?
    end

    def duplicado_ignorado?
      return false if @forcar

      @webhook_log.duplicado_ignorado?
    end

    def duplicado_detectado?
      return false if @forcar

      extrair_metadados_se_ausentes!
      identificador = @webhook_log.identificador_externo
      return false if identificador.blank?

      WebhookLog.where(provedor: @webhook_log.provedor, identificador_externo: identificador, status: :processado)
                .where.not(id: @webhook_log.id)
                .exists?
    end

    def marcar_como_duplicado!
      @webhook_log.update!(status: :duplicado_ignorado)
    end

    def extrair_metadados_se_ausentes!
      alterado = false
      payload = @webhook_log.payload.is_a?(Hash) ? @webhook_log.payload : {}

      if @webhook_log.evento.blank?
        evento_extraido = extrair_evento(payload, @webhook_log.provedor.to_sym)
        if evento_extraido.present?
          @webhook_log.evento = evento_extraido
          alterado = true
        end
      end

      if @webhook_log.identificador_externo.blank?
        id_extraido = extrair_identificador_externo(payload, @webhook_log.provedor.to_sym)
        if id_extraido.present?
          @webhook_log.identificador_externo = id_extraido
          alterado = true
        end
      end

      @webhook_log.save! if alterado
    end

    def extrair_evento(payload, provedor)
      case provedor
      when :asaas
        payload["event"] || payload[:event]
      when :resend
        payload["type"] || payload[:type]
      end
    end

    def extrair_identificador_externo(payload, provedor)
      case provedor
      when :asaas
        payload.dig("payment", "id") || payload.dig(:payment, :id) || payload["id"] || payload[:id]
      when :resend
        payload.dig("data", "email_id") || payload.dig(:data, :email_id) || payload.dig("data", "id") || payload.dig(:data, :id) || payload["id"] || payload[:id]
      end
    end

    def executar_orquestracao
      extrair_metadados_se_ausentes!

      handler_class_name = PROVEDORES_HANDLERS[@webhook_log.provedor.to_sym]
      handler_class = handler_class_name&.safe_constantize

      resultado = if handler_class.present?
                    handler_class.call(webhook_log: @webhook_log)
      else
                    processar_fallback_padrao
      end

      if resultado.success?
        @webhook_log.update!(
          status: :processado,
          processado_em: Time.current,
          mensagem_erro: nil
        )

        success(
          webhook_log: @webhook_log,
          status: :processado,
          provedor: @webhook_log.provedor.to_sym,
          evento: @webhook_log.evento,
          identificador_externo: @webhook_log.identificador_externo,
          processado_em: @webhook_log.processado_em,
          detalhes: resultado.data
        )
      else
        mensagem_falha = resultado.error || "Falha desconhecida no handler do webhook"
        @webhook_log.update!(
          status: :falhou,
          mensagem_erro: mensagem_falha
        )

        failure(
          mensagem_falha,
          error_code: resultado.error_code || :webhook_processing_failed,
          data: { webhook_log: @webhook_log }
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      @webhook_log.update(status: :falhou, mensagem_erro: e.message) rescue nil
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      @webhook_log.update(status: :falhou, mensagem_erro: e.message) rescue nil
      failure("Erro inesperado no processamento do webhook: #{e.message}", error_code: :unexpected_error)
    end

    def processar_fallback_padrao
      success(
        mensagem: "Webhook registrado e metadados extraídos pelo orquestrador geral (handler específico pendente)",
        provedor: @webhook_log.provedor.to_sym,
        evento: @webhook_log.evento,
        identificador_externo: @webhook_log.identificador_externo
      )
    end
  end

  OrquestradorService = ProcessarService
  ProcessarWebhookService = ProcessarService
end
