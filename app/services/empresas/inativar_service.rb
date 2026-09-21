# frozen_string_literal: true

module Empresas
  class InativarService < ApplicationService
    def initialize(
      empresa = nil,
      motivo: nil,
      ignorar_se_inativo: false,
      suspender_assinaturas: false,
      cancelar_assinaturas: false,
      **kwargs
    )
      empresa_alvo = empresa || kwargs[:empresa]
      @empresa_param = empresa_alvo
      @empresa = resolver_empresa(empresa_alvo)

      @motivo = motivo || kwargs[:motivo]
      @ignorar_se_inativo = ignorar_se_inativo || kwargs[:ignorar_se_inativo] || false
      @suspender_assinaturas = suspender_assinaturas || kwargs[:suspender_assinaturas] || false
      @cancelar_assinaturas = cancelar_assinaturas || kwargs[:cancelar_assinaturas] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@empresa.ativo? && @ignorar_se_inativo
        return success(
          empresa: @empresa,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true,
          assinaturas_suspensas: 0,
          assinaturas_canceladas: 0
        )
      end

      executar_inativacao
    end

    private

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      # Busca por ID numérico
      if param.is_a?(Integer)
        return Empresa.find_by(id: param)
      end

      param_str = param.to_s.strip

      # Se for puramente numérica, busca primeiro por ID
      if param_str =~ /\A\d+\z/
        empresa = Empresa.find_by(id: param_str.to_i)
        return empresa if empresa
      end

      # Busca por slug
      Empresa.find_by(slug: param_str.downcase)
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) if @empresa.nil?

      if !@empresa.ativo? && !@ignorar_se_inativo
        return failure("Empresa já se encontra inativa", error_code: :empresa_already_inactive)
      end

      nil
    end

    def executar_inativacao
      assinaturas_suspensas = 0
      assinaturas_canceladas = 0

      ActiveRecord::Base.transaction do
        @empresa.ativo = false
        @empresa.save!

        if @cancelar_assinaturas
          status_cancelaveis = Assinatura.statuses.values_at("pendente", "ativa", "atrasada", "suspensa").compact
          assinaturas_canceladas = @empresa.assinaturas.where(status: status_cancelaveis).update_all(status: Assinatura.statuses[:cancelada])
        elsif @suspender_assinaturas
          assinaturas_suspensas = @empresa.assinaturas.where(status: Assinatura.statuses[:ativa]).update_all(status: Assinatura.statuses[:suspensa])
        end
      end

      success(
        empresa: @empresa,
        inativado: true,
        motivo: @motivo,
        assinaturas_suspensas: assinaturas_suspensas,
        assinaturas_canceladas: assinaturas_canceladas
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  DesativarService = InativarService
  SuspenderService = InativarService
end
