# frozen_string_literal: true

module Membros
  class InativarService < ApplicationService
    def initialize(
      empresa = nil,
      membro = nil,
      motivo: nil,
      ignorar_se_inativo: false,
      **kwargs
    )
      empresa_alvo = empresa || kwargs[:empresa]
      @empresa_param = empresa_alvo
      @empresa = resolver_empresa(empresa_alvo)

      membro_alvo = membro || kwargs[:membro]
      @membro_param = membro_alvo
      @membro = resolver_membro(membro_alvo)

      @motivo = motivo || kwargs[:motivo]
      @ignorar_se_inativo = ignorar_se_inativo || kwargs[:ignorar_se_inativo] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@membro.ativo? && @ignorar_se_inativo
        return success(
          membro: @membro,
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

    def resolver_membro(param)
      return param if param.is_a?(Membro)
      return nil if param.blank?

      # Se for ID de membro
      if param.is_a?(Integer) || param.to_s =~ /\A\d+\z/
        membro = Membro.find_by(id: param.to_i)
        return membro if membro
      end

      # Se for uma instância de Usuario
      if param.is_a?(Usuario) && @empresa.present?
        return @empresa.membros.find_by(usuario_id: param.id)
      end

      # Tenta buscar por e-mail de usuário vinculado se a empresa estiver resolvida
      if @empresa.present?
        usuario = Usuario.find_by(email: param.to_s.strip.downcase)
        return @empresa.membros.find_by(usuario_id: usuario.id) if usuario
      end

      nil
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) if @empresa.nil?

      validacao_membro = validar_membro
      return validacao_membro if validacao_membro&.failure?

      validacao_status = validar_status_e_regras
      return validacao_status if validacao_status&.failure?

      nil
    end

    def validar_membro
      if @membro.nil? && @membro_param.present?
        if @membro_param.is_a?(Membro) || Membro.exists?(id: @membro_param)
          return failure("Membro não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Membro não informado ou não encontrado", error_code: :member_not_found)
      end

      return failure("Membro não informado ou não encontrado", error_code: :member_not_found) if @membro.nil?

      if @membro.empresa_id != @empresa.id
        return failure("Membro não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_status_e_regras
      if !@membro.ativo? && !@ignorar_se_inativo
        return failure("Membro já se encontra inativo nesta empresa", error_code: :member_already_inactive)
      end

      if @membro.proprietario? && @membro.ativo?
        proprietarios_ativos = @empresa.membros.ativos.proprietarios.where.not(id: @membro.id).count
        if proprietarios_ativos.zero?
          return failure("Não é possível inativar o único proprietário ativo da empresa", error_code: :last_owner_cannot_be_inactivated)
        end
      end

      nil
    end

    def executar_inativacao
      ActiveRecord::Base.transaction do
        @membro.ativo = false
        @membro.save!
      end

      success(
        membro: @membro,
        inativado: true,
        motivo: @motivo
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  DesativarService = InativarService
  RemoverService = InativarService
end
