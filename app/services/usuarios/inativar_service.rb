# frozen_string_literal: true

module Usuarios
  class InativarService < ApplicationService
    def initialize(
      usuario = nil,
      motivo: nil,
      ignorar_se_inativo: false,
      desativar_membros: false,
      **kwargs
    )
      usuario_alvo = usuario || kwargs[:usuario]
      @usuario_param = usuario_alvo
      @usuario = resolver_usuario(usuario_alvo)

      @motivo = motivo || kwargs[:motivo]
      @ignorar_se_inativo = ignorar_se_inativo || kwargs[:ignorar_se_inativo] || false
      @desativar_membros = desativar_membros || kwargs[:desativar_membros] || kwargs[:inativar_membros] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@usuario.ativo? && @ignorar_se_inativo
        return success(
          usuario: @usuario,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true,
          membros_inativados: 0
        )
      end

      executar_inativacao
    end

    private

    def resolver_usuario(param)
      return param if param.is_a?(Usuario)
      return nil if param.blank?

      # Busca por ID numérico
      if param.is_a?(Integer)
        return Usuario.find_by(id: param)
      end

      param_str = param.to_s.strip

      # Se for puramente numérica, busca primeiro por ID
      if param_str =~ /\A\d+\z/
        usuario = Usuario.find_by(id: param_str.to_i)
        return usuario if usuario
      end

      # Busca por e-mail
      Usuario.find_by(email: param_str.downcase)
    end

    def validar_parametros
      return failure("Usuário não informado ou não encontrado", error_code: :usuario_not_found) if @usuario.nil?

      if !@usuario.ativo? && !@ignorar_se_inativo
        return failure("Usuário já se encontra inativo", error_code: :usuario_already_inactive)
      end

      nil
    end

    def executar_inativacao
      membros_inativados = 0

      ActiveRecord::Base.transaction do
        @usuario.ativo = false
        @usuario.save!

        if @desativar_membros
          membros_inativados = @usuario.membros.where(ativo: true).update_all(ativo: false)
        end
      end

      success(
        usuario: @usuario,
        inativado: true,
        motivo: @motivo,
        membros_inativados: membros_inativados
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  DesativarService = InativarService
  BloquearService = InativarService
end
