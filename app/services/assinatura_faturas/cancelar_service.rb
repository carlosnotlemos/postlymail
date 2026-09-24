# frozen_string_literal: true

module AssinaturaFaturas
  class CancelarService < ApplicationService
    def initialize(
      fatura = nil,
      empresa: nil,
      motivo: nil,
      ignorar_se_cancelada: false,
      permitir_se_paga: false,
      **kwargs
    )
      fatura_alvo = fatura || kwargs[:fatura]
      @gateway_id_param = kwargs[:gateway_id]
      @fatura = resolver_fatura(fatura_alvo) || resolver_por_gateway_id(@gateway_id_param)

      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @motivo = motivo || kwargs[:motivo]
      @ignorar_se_cancelada = ignorar_se_cancelada || kwargs[:ignorar_se_cancelada] || false
      @permitir_se_paga = permitir_se_paga || kwargs[:permitir_se_paga] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @fatura.cancelada? && @ignorar_se_cancelada
        return success(
          fatura: @fatura,
          assinatura: @fatura.assinatura,
          empresa: @fatura.empresa,
          cancelado: false,
          ja_estava_cancelada: true,
          motivo: @motivo
        )
      end

      executar_cancelamento
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

    def validar_parametros
      if @fatura.nil?
        return failure("Fatura não informada ou não encontrada", error_code: :invoice_not_found)
      end

      if @empresa.present? && @fatura.assinatura.empresa_id != @empresa.id
        return failure("A fatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @fatura.cancelada? && !@ignorar_se_cancelada
        return failure("Fatura já se encontra cancelada", error_code: :invoice_already_cancelled)
      end

      if @fatura.paga? && !@permitir_se_paga
        return failure("Não é possível cancelar uma fatura já paga", error_code: :cannot_cancel_paid_invoice)
      end

      nil
    end

    def executar_cancelamento
      ActiveRecord::Base.transaction do
        @fatura.status = :cancelada

        novos_metadados = (@fatura.metadados || {}).dup
        novos_metadados["cancelado_em"] = Time.current.iso8601
        novos_metadados["motivo_cancelamento"] = @motivo if @motivo.present?
        @fatura.metadados = novos_metadados

        @fatura.save!
      end

      success(
        fatura: @fatura,
        assinatura: @fatura.assinatura,
        empresa: @fatura.empresa,
        cancelado: true,
        ja_estava_cancelada: false,
        motivo: @motivo
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  AnularService = CancelarService
  EstornarService = CancelarService
end

module Assinaturas
  CancelarFaturaService = AssinaturaFaturas::CancelarService
end
