# frozen_string_literal: true

module AssinaturaFaturas
  class PagarService < ApplicationService
    def initialize(
      fatura = nil,
      empresa: nil,
      data_pagamento: nil,
      gateway_id: nil,
      metadados: nil,
      ignorar_se_paga: false,
      reativar_assinatura: true,
      prorrogar_vigencia: true,
      **kwargs
    )
      fatura_alvo = fatura || kwargs[:fatura]
      @gateway_id_param = gateway_id || kwargs[:gateway_id]
      @fatura = resolver_fatura(fatura_alvo) || resolver_por_gateway_id(@gateway_id_param)

      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @data_pagamento = data_pagamento || kwargs[:data_pagamento]
      @metadados = metadados || kwargs[:metadados] || {}
      @ignorar_se_paga = ignorar_se_paga || kwargs[:ignorar_se_paga] || false
      @reativar_assinatura = kwargs.key?(:reativar_assinatura) ? kwargs[:reativar_assinatura] : reativar_assinatura
      @prorrogar_vigencia = kwargs.key?(:prorrogar_vigencia) ? kwargs[:prorrogar_vigencia] : prorrogar_vigencia
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @fatura.paga? && @ignorar_se_paga
        return success(
          fatura: @fatura,
          assinatura: @fatura.assinatura,
          empresa: @fatura.empresa,
          ja_estava_paga: true,
          assinatura_reativada: false,
          vigencia_prorrogada: false,
          data_pagamento: @fatura.data_pagamento
        )
      end

      executar_pagamento
    end

    private

    def resolver_fatura(param)
      return param if param.is_a?(AssinaturaFatura)
      return nil if param.blank?

      if param.is_a?(Integer)
        return AssinaturaFatura.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        fatura = AssinaturaFatura.find_by(id: param_str.to_i)
        return fatura if fatura
      end

      AssinaturaFatura.find_by(gateway_id: param_str)
    end

    def resolver_por_gateway_id(gateway_id)
      return nil if gateway_id.blank?

      AssinaturaFatura.find_by(gateway_id: gateway_id.to_s.strip)
    end

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Empresa.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        empresa = Empresa.find_by(id: param_str.to_i)
        return empresa if empresa
      end

      Empresa.find_by(slug: param_str.downcase)
    end

    def converter_para_datetime(valor)
      return valor if valor.is_a?(Time) || valor.is_a?(DateTime) || valor.is_a?(ActiveSupport::TimeWithZone)
      return valor.to_time if valor.respond_to?(:to_time)

      Time.zone.parse(valor.to_s) rescue nil
    end

    def validar_parametros
      if @fatura.nil?
        return failure("Fatura não informada ou não encontrada", error_code: :invoice_not_found)
      end

      if @empresa.present? && @fatura.assinatura.empresa_id != @empresa.id
        return failure("A fatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @fatura.cancelada?
        return failure("Fatura encontra-se cancelada e não pode ser paga", error_code: :invoice_cancelled)
      end

      if @fatura.paga? && !@ignorar_se_paga
        return failure("Fatura já se encontra paga", error_code: :invoice_already_paid)
      end

      nil
    end

    def executar_pagamento
      assinatura = @fatura.assinatura
      assinatura_reativada = false
      vigencia_prorrogada = false
      timestamp_pagamento = converter_para_datetime(@data_pagamento) || Time.current

      ActiveRecord::Base.transaction do
        @fatura.status = :paga
        @fatura.data_pagamento = timestamp_pagamento
        @fatura.gateway_id = @gateway_id_param.to_s.strip if @gateway_id_param.present?

        if @metadados.present? && @metadados.is_a?(Hash)
          metadados_atuais = @fatura.metadados || {}
          @fatura.metadados = metadados_atuais.merge(@metadados.stringify_keys)
        end

        @fatura.save!

        if @reativar_assinatura && assinatura.status.in?(%w[pendente atrasada suspensa])
          assinatura.status = :ativa
          assinatura_reativada = true
        end

        if @prorrogar_vigencia && !assinatura.cancelada?
          data_base = [ assinatura.data_fim || Date.current, Date.current ].max
          periodo = case assinatura.ciclo.to_s
          when "trimestral" then 3.months
          when "anual" then 1.year
          else 1.month
          end

          assinatura.data_fim = data_base + periodo
          vigencia_prorrogada = true
        end

        assinatura.save! if assinatura.changed?
      end

      success(
        fatura: @fatura,
        assinatura: assinatura,
        empresa: @fatura.empresa,
        ja_estava_paga: false,
        assinatura_reativada: assinatura_reativada,
        vigencia_prorrogada: vigencia_prorrogada,
        data_pagamento: @fatura.data_pagamento,
        nova_data_fim: assinatura.data_fim
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  LiquidarService = PagarService
  ConfirmarPagamentoService = PagarService
  RegistrarPagamentoService = PagarService
end

module Assinaturas
  PagarFaturaService = AssinaturaFaturas::PagarService
end
