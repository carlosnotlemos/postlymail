# frozen_string_literal: true

module Convites
  class SalvarService < ApplicationService
    CONVITE_ATTRS = %i[
      email
      papel
      expira_em
    ].freeze

    def initialize(
      empresa_ou_hash = nil,
      convite_ou_atributos = nil,
      empresa: nil,
      convite: nil,
      convidado_por: nil,
      email: nil,
      papel: nil,
      expira_em: nil,
      reenviar: false,
      renovar: false,
      ignorar_limite: false,
      atributos: nil,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if empresa_ou_hash.is_a?(Hash)
        dados.merge!(empresa_ou_hash.symbolize_keys)
      elsif empresa_ou_hash.present? && !dados.key?(:empresa)
        dados[:empresa] = empresa_ou_hash
      end

      if convite_ou_atributos.is_a?(Hash)
        dados.merge!(convite_ou_atributos.symbolize_keys)
      elsif convite_ou_atributos.present? && !dados.key?(:convite)
        dados[:convite] = convite_ou_atributos
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:convite] = convite if convite.present?
      dados[:convidado_por] = convidado_por if convidado_por.present?
      dados[:email] = email if email.present?
      dados[:papel] = papel if papel.present?
      dados[:expira_em] = expira_em if expira_em.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @convite_param = dados[:convite] || dados[:convite_id] || dados[:token]
      @convite = resolver_convite(@convite_param)
      @empresa ||= @convite&.empresa if @empresa_param.blank?

      @convidado_por_param = dados[:convidado_por] || dados[:convidado_por_id]
      @convidado_por = resolver_convidado_por(@convidado_por_param)

      @email_param = dados[:email]
      @email = normalizar_email(@email_param)

      @papel_param = dados[:papel]
      @papel = normalizar_papel(@papel_param)

      @expira_em = dados[:expira_em]
      @reenviar = reenviar || dados[:reenviar] || dados[:renovar] || renovar || false
      @ignorar_limite = ignorar_limite || dados[:ignorar_limite] || false

      @convite_existente = nil
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento
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

    def resolver_convidado_por(param)
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

    def normalizar_email(param)
      return nil if param.blank?

      param.to_s.strip.downcase
    end

    def normalizar_papel(param)
      return nil if param.blank?

      if param.is_a?(Symbol) || param.is_a?(String)
        param.to_s.downcase.strip
      elsif param.is_a?(Integer)
        Convite.papeis.key(param)
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) if @empresa.nil?

      validacao_convidado = validar_convidado_por
      return validacao_convidado if validacao_convidado&.failure?

      validacao_papel = validar_papel
      return validacao_papel if validacao_papel&.failure?

      validacao_email = validar_email
      return validacao_email if validacao_email&.failure?

      validacao_membro = validar_se_ja_membro
      return validacao_membro if validacao_membro&.failure?

      validacao_pendente = validar_convite_existente
      return validacao_pendente if validacao_pendente&.failure?

      validacao_limite = validar_limite_usuarios
      return validacao_limite if validacao_limite&.failure?

      nil
    end

    def validar_convidado_por
      if @convidado_por_param.present? && @convidado_por.nil?
        return failure("Usuário que convidou não foi encontrado", error_code: :convidado_por_not_found)
      end

      if @convidado_por.nil?
        return failure("Usuário que convidou não foi informado ou não encontrado", error_code: :convidado_por_not_found)
      end

      # Validar se o usuário que convida é membro ativo da empresa
      unless @empresa.membros.ativos.exists?(usuario_id: @convidado_por.id)
        return failure("Usuário que convidou não é membro ativo desta empresa", error_code: :unauthorized_inviter)
      end

      nil
    end

    def validar_papel
      if @papel.blank?
        return failure("Papel não informado", error_code: :invalid_role)
      end

      unless Convite.papeis.key?(@papel.to_s)
        return failure("Papel informado é inválido", error_code: :invalid_role)
      end

      nil
    end

    def validar_email
      if @email.blank?
        return failure("E-mail não informado", error_code: :invalid_email)
      end

      unless @email =~ URI::MailTo::EMAIL_REGEXP
        return failure("Formato de e-mail inválido", error_code: :invalid_email)
      end

      nil
    end

    def validar_se_ja_membro
      usuario_existente = Usuario.find_by(email: @email)
      if usuario_existente && @empresa.membros.ativos.exists?(usuario_id: usuario_existente.id)
        return failure("Usuário já é membro ativo desta empresa", error_code: :member_already_exists)
      end

      nil
    end

    def validar_convite_existente
      # Procura convite não aceito e não cancelado para a mesma empresa e e-mail
      @convite_existente = @empresa.convites.nao_cancelados.find_by(email: @email, aceito_em: nil)

      return nil if @convite_existente.nil?

      # Se o convite existente ainda estiver pendente (não expirado) e o chamador NÃO pediu reenviar/renovar
      if @convite_existente.pendente? && !@reenviar
        return failure("Já existe um convite pendente para este e-mail nesta empresa", error_code: :invite_already_pending)
      end

      nil
    end

    def validar_limite_usuarios
      # Se estiver renovando um convite existente, não adiciona novo membro/convite
      return nil if @convite_existente.present?
      return nil if @ignorar_limite

      assinatura = @empresa.assinatura_ativa
      return nil if assinatura.nil?

      plano = assinatura.plano
      return nil if plano.nil? || plano.ilimitado_usuarios?

      total_membros = @empresa.membros.ativos.count
      total_convites_pendentes = @empresa.convites.pendentes.count

      if (total_membros + total_convites_pendentes) >= plano.limite_usuarios
        return failure(
          "Limite de usuários atingido para o plano contratado (#{plano.limite_usuarios})",
          error_code: :plan_user_limit_reached
        )
      end

      nil
    end

    def executar_salvamento
      foi_reenviado = false

      ActiveRecord::Base.transaction do
        if @convite_existente.present?
          # Renovação / reenvio de convite existente não aceito
          @convite_existente.convidado_por = @convidado_por
          @convite_existente.papel = @papel
          @convite_existente.expira_em = @expira_em || 7.days.from_now
          @convite_existente.regenerate_token
          @convite_existente.save!
          @convite = @convite_existente
          foi_reenviado = true
        else
          # Novo convite
          @convite = @empresa.convites.new(
            convidado_por: @convidado_por,
            email: @email,
            papel: @papel,
            expira_em: @expira_em || 7.days.from_now
          )
          @convite.save!
        end
      end

      success(convite: @convite, reenviado: foi_reenviado)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CriarService = SalvarService
  EnviarService = SalvarService
  CadastrarService = SalvarService
end
