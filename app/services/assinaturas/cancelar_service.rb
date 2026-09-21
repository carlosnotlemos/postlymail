# frozen_string_literal: true

module Assinaturas
  class CancelarService < ApplicationService
    def initialize(
      assinatura = nil,
      empresa: nil,
      motivo: nil,
      ignorar_se_cancelada: false,
      cancelar_faturas_pendentes: true,
      data_cancelamento: nil,
      **kwargs
    )
      assinatura_alvo = assinatura || kwargs[:assinatura]
      @assinatura_param = assinatura_alvo
      @assinatura = resolver_assinatura(assinatura_alvo)

      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      if @assinatura.nil? && @empresa.present?
        @assinatura = @empresa.assinaturas.find_by(status: :ativa) || @empresa.assinaturas.order(created_at: :desc).first
      end

      @motivo = motivo || kwargs[:motivo]
      @ignorar_se_cancelada = ignorar_se_cancelada || kwargs[:ignorar_se_cancelada] || false
      @cancelar_faturas_pendentes = kwargs.key?(:cancelar_faturas_pendentes) ? kwargs[:cancelar_faturas_pendentes] : cancelar_faturas_pendentes
      @data_cancelamento = data_cancelamento || kwargs[:data_cancelamento]
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @assinatura.cancelada? && @ignorar_se_cancelada
        return success(
          assinatura: @assinatura,
          cancelado: false,
          ja_estava_cancelada: true,
          motivo: @motivo,
          faturas_canceladas: 0,
          data_cancelamento: @assinatura.data_cancelamento
        )
      end

      executar_cancelamento
    end

    private

    def resolver_assinatura(param)
      return param if param.is_a?(Assinatura)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Assinatura.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        Assinatura.find_by(id: param_str.to_i)
      end
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
      if @assinatura.nil?
        return failure("Assinatura não informada ou não encontrada", error_code: :subscription_not_found)
      end

      if @empresa.present? && @assinatura.empresa_id != @empresa.id
        return failure("A assinatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @assinatura.cancelada? && !@ignorar_se_cancelada
        return failure("Assinatura já se encontra cancelada", error_code: :subscription_already_cancelled)
      end

      nil
    end

    def executar_cancelamento
      faturas_canceladas_count = 0

      ActiveRecord::Base.transaction do
        timestamp_cancelamento = @data_cancelamento || Time.current
        @assinatura.status = :cancelada
        @assinatura.data_cancelamento = timestamp_cancelamento
        @assinatura.save!

        if @cancelar_faturas_pendentes
          faturas_canceladas_count = @assinatura.faturas.where(status: :pendente).update_all(
            status: AssinaturaFatura.statuses[:cancelada],
            updated_at: Time.current
          )
        end
      end

      success(
        assinatura: @assinatura,
        cancelado: true,
        ja_estava_cancelada: false,
        motivo: @motivo,
        faturas_canceladas: faturas_canceladas_count,
        data_cancelamento: @assinatura.data_cancelamento
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  EncerrarService = CancelarService
  DesativarService = CancelarService
end
