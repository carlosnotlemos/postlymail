# frozen_string_literal: true

module Webhooks
  module Asaas
    class ProcessarService < ApplicationService
      FORMAS_PAGAMENTO_MAP = {
        "PIX" => :pix,
        "CREDIT_CARD" => :cartao_credito,
        "DEBIT_CARD" => :cartao_debito,
        "BOLETO" => :boleto
      }.freeze

      def initialize(
        webhook_log_ou_hash = nil,
        webhook_log: nil,
        payload: nil,
        evento: nil,
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
        @evento = (dados[:evento] || @webhook_log&.evento || @payload["event"] || @payload[:event]).to_s.strip.upcase
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
          return failure("Payload do Asaas está vazio", error_code: :empty_payload)
        end

        if @evento.blank?
          return failure("Evento do Asaas não identificado no payload", error_code: :empty_event)
        end

        nil
      end

      def extrair_dados_pagamento
        payment_data = @payload["payment"] || @payload[:payment] || @payload
        payment_data = payment_data.is_a?(Hash) ? payment_data : {}

        payment_id = payment_data["id"] || payment_data[:id]
        subscription_id = payment_data["subscription"] || payment_data[:subscription]
        external_reference = payment_data["externalReference"] || payment_data[:externalReference]
        billing_type = payment_data["billingType"] || payment_data[:billingType]
        valor = payment_data["value"] || payment_data[:value]
        net_value = payment_data["netValue"] || payment_data[:netValue]
        taxa = if valor.present? && net_value.present?
                 [ (valor.to_d - net_value.to_d).round(2), BigDecimal("0.0") ].max
        else
                 BigDecimal("0.0")
        end

        data_pagamento_raw = payment_data["paymentDate"] ||
                             payment_data["confirmedDate"] ||
                             payment_data["clientPaymentDate"] ||
                             Time.current

        data_pagamento = parse_datetime(data_pagamento_raw)

        {
          payment_data: payment_data,
          payment_id: payment_id.to_s.strip.presence,
          subscription_id: subscription_id.to_s.strip.presence,
          external_reference: external_reference.to_s.strip.presence,
          billing_type: billing_type.to_s.strip.upcase.presence,
          valor: valor,
          taxa: taxa,
          data_pagamento: data_pagamento
        }
      end

      def parse_datetime(valor)
        return valor if valor.is_a?(Time) || valor.is_a?(DateTime)
        return valor.to_time if valor.is_a?(Date)

        Time.zone.parse(valor.to_s) rescue Time.current
      end

      def executar_processamento
        dados_pagamento = extrair_dados_pagamento

        # 1. Tenta identificar se o evento pertence a uma AssinaturaFatura
        fatura = localizar_fatura(dados_pagamento)
        if fatura.present?
          return processar_evento_fatura(fatura, dados_pagamento)
        end

        # 2. Tenta identificar se o evento pertence a uma Venda / VendaPagamento
        venda_ou_pagamento = localizar_venda_ou_pagamento(dados_pagamento)
        if venda_ou_pagamento.present?
          return processar_evento_venda(venda_ou_pagamento, dados_pagamento)
        end

        # 3. Recurso não localizado
        success(
          recurso_localizado: false,
          evento: @evento,
          payment_id: dados_pagamento[:payment_id],
          mensagem: "Nenhuma fatura de assinatura ou venda localizada para o identificador #{dados_pagamento[:payment_id]}"
        )
      rescue ActiveRecord::RecordInvalid => e
        failure("Erro de validação no banco: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
      rescue StandardError => e
        failure("Erro inesperado ao processar webhook do Asaas: #{e.message}", error_code: :unexpected_error)
      end

      def localizar_fatura(dados)
        payment_id = dados[:payment_id]
        subscription_id = dados[:subscription_id]
        ext_ref = dados[:external_reference]

        if payment_id.present?
          fatura = AssinaturaFatura.find_by(gateway_id: payment_id)
          return fatura if fatura.present?
        end

        if subscription_id.present?
          fatura = AssinaturaFatura.find_by(gateway_id: subscription_id)
          return fatura if fatura.present?
        end

        if ext_ref.present?
          id_candidato = ext_ref.sub(/\Afatura[_-]/i, "")
          if id_candidato =~ /\A\d+\z/
            fatura = AssinaturaFatura.find_by(id: id_candidato.to_i)
            return fatura if fatura.present?
          end
        end

        nil
      end

      def localizar_venda_ou_pagamento(dados)
        payment_id = dados[:payment_id]
        ext_ref = dados[:external_reference]

        if payment_id.present?
          venda_pag = VendaPagamento.find_by(gateway: :asaas, gateway_id: payment_id)
          return { venda_pagamento: venda_pag, venda: venda_pag.venda } if venda_pag.present?
        end

        if ext_ref.present?
          venda = Venda.find_by(codigo_pedido: ext_ref)
          if venda.nil?
            id_candidato = ext_ref.sub(/\Avenda[_-]/i, "")
            venda = Venda.find_by(id: id_candidato.to_i) if id_candidato =~ /\A\d+\z/
          end

          if venda.present?
            venda_pag = venda.pagamentos.find_by(gateway: :asaas, gateway_id: payment_id)
            return { venda_pagamento: venda_pag, venda: venda }
          end
        end

        nil
      end

      # Processamento de Faturas de Assinatura
      def processar_evento_fatura(fatura, dados)
        case @evento
        when "PAYMENT_RECEIVED", "PAYMENT_CONFIRMED"
          resultado_pagamento = AssinaturaFaturas::PagarService.call(
            fatura: fatura,
            data_pagamento: dados[:data_pagamento],
            gateway_id: dados[:payment_id],
            metadados: dados[:payment_data],
            ignorar_se_paga: true,
            reativar_assinatura: true,
            prorrogar_vigencia: true
          )

          if resultado_pagamento.success?
            success(
              tipo_recurso: :assinatura_fatura,
              fatura: fatura.reload,
              assinatura: fatura.assinatura,
              acao: :fatura_paga,
              evento: @evento,
              detalhes: resultado_pagamento.data
            )
          else
            failure(
              "Falha ao liquidar fatura: #{resultado_pagamento.error}",
              error_code: resultado_pagamento.error_code
            )
          end

        when "PAYMENT_DELETED"
          if fatura.pendente?
            resultado_cancel = AssinaturaFaturas::CancelarService.call(
              fatura: fatura,
              motivo: "Cobrança removida no Asaas (#{dados[:payment_id]})",
              ignorar_se_cancelada: true
            )

            success(
              tipo_recurso: :assinatura_fatura,
              fatura: fatura.reload,
              acao: :fatura_cancelada,
              evento: @evento,
              detalhes: resultado_cancel.data
            )
          else
            success(
              tipo_recurso: :assinatura_fatura,
              fatura: fatura,
              acao: :ignorado,
              evento: @evento,
              mensagem: "Fatura não está pendente, remoção no Asaas ignorada"
            )
          end

        when "PAYMENT_REFUNDED", "PAYMENT_PARTIALLY_REFUNDED"
          metadados_atuais = fatura.metadados || {}
          fatura.update!(
            status: :cancelada,
            metadados: metadados_atuais.merge("estornado_em" => Time.current.iso8601, "evento_asaas" => @evento)
          )

          success(
            tipo_recurso: :assinatura_fatura,
            fatura: fatura.reload,
            acao: :fatura_estornada,
            evento: @evento
          )

        else
          # Outros eventos informativos (PAYMENT_CREATED, PAYMENT_OVERDUE, etc)
          metadados_atuais = fatura.metadados || {}
          fatura.update!(metadados: metadados_atuais.merge("ultimo_evento_asaas" => @evento))

          success(
            tipo_recurso: :assinatura_fatura,
            fatura: fatura.reload,
            acao: :evento_registrado,
            evento: @evento
          )
        end
      end

      # Processamento de Vendas / Pagamentos de Vendas
      def processar_evento_venda(alvo, dados)
        venda = alvo[:venda]
        venda_pag = alvo[:venda_pagamento]
        forma = FORMAS_PAGAMENTO_MAP[dados[:billing_type]] || :pix

        case @evento
        when "PAYMENT_RECEIVED", "PAYMENT_CONFIRMED"
          ActiveRecord::Base.transaction do
            if venda_pag.present?
              venda_pag.update!(
                status: :aprovado,
                data_liquidacao: dados[:data_pagamento] || Time.current,
                taxa_operadora: dados[:taxa] || venda_pag.taxa_operadora
              )
            else
              venda_pag = venda.pagamentos.create!(
                gateway: :asaas,
                gateway_id: dados[:payment_id],
                valor: dados[:valor] || venda.valor_total,
                taxa_operadora: dados[:taxa] || 0.0,
                forma_pagamento: forma,
                status: :aprovado,
                parcelas: 1,
                data_liquidacao: dados[:data_pagamento] || Time.current,
                metadados: dados[:payment_data]
              )
            end

            total_aprovado = venda.pagamentos.where(status: :aprovado).sum(:valor)
            if total_aprovado >= venda.valor_total && !venda.paga?
              venda.update!(status: :paga)
            end
          end

          success(
            tipo_recurso: :venda,
            venda: venda.reload,
            venda_pagamento: venda_pag.reload,
            acao: :pagamento_venda_aprovado,
            evento: @evento
          )

        when "PAYMENT_CREDIT_CARD_CAPTURE_REFUSED"
          venda_pag&.update!(status: :recusado)
          success(
            tipo_recurso: :venda,
            venda: venda,
            venda_pagamento: venda_pag,
            acao: :pagamento_venda_recusado,
            evento: @evento
          )

        when "PAYMENT_REFUNDED", "PAYMENT_PARTIALLY_REFUNDED"
          venda_pag&.update!(status: :estornado)
          success(
            tipo_recurso: :venda,
            venda: venda,
            venda_pagamento: venda_pag,
            acao: :pagamento_venda_estornado,
            evento: @evento
          )

        when "PAYMENT_DELETED"
          venda_pag&.update!(status: :cancelado) if venda_pag&.pendente?
          success(
            tipo_recurso: :venda,
            venda: venda,
            venda_pagamento: venda_pag,
            acao: :pagamento_venda_cancelado,
            evento: @evento
          )

        else
          success(
            tipo_recurso: :venda,
            venda: venda,
            venda_pagamento: venda_pag,
            acao: :evento_registrado,
            evento: @evento
          )
        end
      end
    end

    ProcessarWebhookService = ProcessarService
  end
end
