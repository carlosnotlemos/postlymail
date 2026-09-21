module Cupons
  class InativarService < ApplicationService
    def initialize(
      empresa: nil,
      cupom: nil,
      motivo: nil,
      ignorar_se_inativo: false
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @cupom_param = cupom
      @cupom = resolver_cupom(cupom)

      @motivo = motivo
      @ignorar_se_inativo = ignorar_se_inativo
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@cupom.ativo? && @ignorar_se_inativo
        return success(
          cupom: @cupom,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true
        )
      end

      executar_inativacao
    end

    private

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      Empresa.find_by(id: param)
    end

    def resolver_cupom(param)
      return param if param.is_a?(Cupom)
      return nil if param.blank? || @empresa.nil?

      if param.is_a?(Integer)
        return @empresa.cupons.find_by(id: param)
      end

      codigo_normalizado = param.to_s.strip.upcase
      cupom_por_codigo = @empresa.cupons.find_by("UPPER(codigo) = ?", codigo_normalizado)
      return cupom_por_codigo if cupom_por_codigo

      if param.is_a?(String) && param =~ /\A\d+\z/
        @empresa.cupons.find_by(id: param)
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cupom = validar_cupom
      return validacao_cupom if validacao_cupom&.failure?

      validar_status_e_regras
    end

    def validar_cupom
      if @cupom.nil? && @cupom_param.present?
        if cupom_existe_em_outro_tenant?
          return failure("Cupom não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Cupom não informado ou não encontrado", error_code: :coupon_not_found)
      end

      return failure("Cupom não informado ou não encontrado", error_code: :coupon_not_found) if @cupom.nil?

      if @cupom.empresa_id != @empresa.id
        return failure("Cupom não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def cupom_existe_em_outro_tenant?
      return true if @cupom_param.is_a?(Cupom)

      if @cupom_param.is_a?(Integer)
        return Cupom.exists?(id: @cupom_param)
      end

      norm = @cupom_param.to_s.strip.upcase
      Cupom.where("UPPER(codigo) = ?", norm).exists? || (@cupom_param.is_a?(String) && @cupom_param =~ /\A\d+\z/ && Cupom.exists?(id: @cupom_param))
    end

    def validar_status_e_regras
      if !@cupom.ativo? && !@ignorar_se_inativo
        return failure("Cupom já se encontra inativo", error_code: :coupon_already_inactive)
      end

      nil
    end

    def executar_inativacao
      ActiveRecord::Base.transaction do
        @cupom.ativo = false
        @cupom.save!
      end

      success(
        cupom: @cupom,
        inativado: true,
        motivo: @motivo
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
