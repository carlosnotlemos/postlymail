# frozen_string_literal: true

module Convites
  class AceitarService < ApplicationService
    def initialize(
      token_ou_convite = nil,
      usuario_param = nil,
      token: nil,
      convite: nil,
      usuario: nil,
      empresa: nil,
      validar_email: false,
      ignorar_limite: false,
      **kwargs
    )
      dados = kwargs.dup

      if token_ou_convite.is_a?(Hash)
        dados.merge!(token_ou_convite.symbolize_keys)
      elsif token_ou_convite.is_a?(Convite)
        dados[:convite] ||= token_ou_convite
      elsif token_ou_convite.present? && !dados.key?(:token) && !dados.key?(:convite)
        dados[:token] = token_ou_convite
      end

      if usuario_param.is_a?(Hash)
        dados.merge!(usuario_param.symbolize_keys)
      elsif usuario_param.present? && !dados.key?(:usuario)
        dados[:usuario] = usuario_param
      end

      dados[:token] = token if token.present?
      dados[:convite] = convite if convite.present?
      dados[:usuario] = usuario if usuario.present?
      dados[:empresa] = empresa if empresa.present?

      @convite_param = dados[:convite] || dados[:token] || dados[:convite_id] || dados[:id]
      @convite = resolver_convite(@convite_param)

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)
      @empresa ||= @convite&.empresa if @empresa_param.blank?

      @usuario_param = dados[:usuario] || dados[:usuario_id]
      @usuario = resolver_usuario(@usuario_param)
      # Se o usuário não foi passado, tenta resolver pelo e-mail do convite
      @usuario ||= Usuario.find_by(email: @convite.email.downcase) if @convite.present? && @usuario_param.blank?

      @validar_email = validar_email || dados[:validar_email] || false
      @ignorar_limite = ignorar_limite || dados[:ignorar_limite] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_aceite
    end

    private

    def resolver_convite(param)
      return param if param.is_a?(Convite)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Convite.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        convite = Convite.find_by(id: param_str.to_i)
        return convite if convite
      end

      Convite.find_by(token: param_str)
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

    def resolver_usuario(param)
      return param if param.is_a?(Usuario)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Usuario.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        usuario = Usuario.find_by(id: param_str.to_i)
        return usuario if usuario
      end

      Usuario.find_by(email: param_str.downcase)
    end

    def validar_parametros
      if @convite.nil?
        return failure("Convite não informado ou não encontrado", error_code: :invite_not_found)
      end

      if @empresa_param.present? && @empresa.present? && @convite.empresa_id != @empresa.id
        return failure("Convite não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @convite.aceito?
        return failure("Convite já foi aceito", error_code: :invite_already_accepted)
      end

      if @convite.cancelado?
        return failure("Convite foi cancelado", error_code: :invite_cancelled)
      end

      if @convite.expirado?
        return failure("Convite expirado", error_code: :invite_expired)
      end

      if @usuario.nil?
        return failure("Usuário não informado ou não encontrado", error_code: :usuario_not_found)
      end

      if @validar_email && (@usuario.email.to_s.downcase != @convite.email.to_s.downcase)
        return failure(
          "O e-mail do usuário não corresponde ao e-mail do convite",
          error_code: :email_mismatch
        )
      end

      validacao_membro = validar_se_ja_membro
      return validacao_membro if validacao_membro&.failure?

      validacao_limite = validar_limite_usuarios
      return validacao_limite if validacao_limite&.failure?

      nil
    end

    def validar_se_ja_membro
      membro_existente = @convite.empresa.membros.find_by(usuario_id: @usuario.id)
      if membro_existente&.ativo?
        return failure("Usuário já é membro ativo desta empresa", error_code: :member_already_exists)
      end

      nil
    end

    def validar_limite_usuarios
      return nil if @ignorar_limite

      assinatura = @convite.empresa.assinatura_ativa
      return nil if assinatura.nil?

      plano = assinatura.plano
      return nil if plano.nil? || plano.ilimitado_usuarios?

      total_membros = @convite.empresa.membros.ativos.count
      if total_membros >= plano.limite_usuarios
        return failure(
          "Limite de usuários atingido para o plano contratado (#{plano.limite_usuarios})",
          error_code: :plan_user_limit_reached
        )
      end

      nil
    end

    def executar_aceite
      membro = nil

      ActiveRecord::Base.transaction do
        @convite.aceito_em = Time.current
        @convite.save!

        membro_existente = @convite.empresa.membros.find_by(usuario_id: @usuario.id)
        if membro_existente
          membro_existente.ativo = true
          membro_existente.papel = @convite.papel
          membro_existente.convidado_por = @convite.convidado_por
          membro_existente.data_entrada = Time.current
          membro_existente.save!
          membro = membro_existente
        else
          membro = @convite.empresa.membros.create!(
            usuario: @usuario,
            papel: @convite.papel,
            convidado_por: @convite.convidado_por,
            data_entrada: Time.current,
            ativo: true
          )
        end
      end

      success(convite: @convite, membro: membro)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
