# frozen_string_literal: true

module Usuarios
  class SalvarService < ApplicationService
    USUARIO_ATTRS = %i[
      nome
      email
      telefone
      ativo
      data_cadastro
    ].freeze

    def initialize(
      usuario: nil,
      atributos: nil,
      **kwargs
    )
      @usuario_param = usuario
      @usuario = resolver_usuario(usuario)

      @atributos_param = extrair_atributos(atributos, kwargs)
      normalizar_atributos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento
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

      # Se string puramente numérica, tenta primeiro por ID
      if param_str =~ /\A\d+\z/
        usuario = Usuario.find_by(id: param_str.to_i)
        return usuario if usuario
      end

      # Busca por e-mail
      Usuario.find_by(email: param_str.downcase)
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      attrs.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      USUARIO_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_atributos
      normalizar_nome
      normalizar_email
      normalizar_telefone
      normalizar_ativo
    end

    def normalizar_nome
      return unless @atributos_param.key?(:nome)

      nome = @atributos_param[:nome]
      @atributos_param[:nome] = nome.to_s.strip if nome.is_a?(String)
    end

    def normalizar_email
      return unless @atributos_param.key?(:email)

      email = @atributos_param[:email]
      @atributos_param[:email] = email.to_s.strip.downcase if email.present?
    end

    def normalizar_telefone
      return unless @atributos_param.key?(:telefone)

      tel = @atributos_param[:telefone]
      if tel.present?
        sanitizado = tel.to_s.gsub(/\D/, "")
        @atributos_param[:telefone] = sanitizado.presence || tel.to_s.strip
      elsif tel.is_a?(String) && tel.blank?
        @atributos_param[:telefone] = nil
      end
    end

    def normalizar_ativo
      return unless @atributos_param.key?(:ativo)

      valor = @atributos_param[:ativo]
      return if valor.nil?

      if valor.is_a?(String)
        @atributos_param[:ativo] = ActiveModel::Type::Boolean.new.cast(valor)
      end
    end

    def validar_parametros
      if @usuario.nil? && @usuario_param.present?
        return failure("Usuário não informado ou não encontrado", error_code: :usuario_not_found)
      end

      validacao_email = validar_email_duplicado
      return validacao_email if validacao_email&.failure?

      nil
    end

    def validar_email_duplicado
      email = @atributos_param[:email]
      return nil if email.blank?

      existente = Usuario.find_by(email: email)
      return nil unless existente

      if @usuario.present?
        if existente.id != @usuario.id
          return failure("Já existe um usuário cadastrado com este e-mail", error_code: :email_already_exists)
        end
      else
        return failure("Já existe um usuário cadastrado com este e-mail", error_code: :email_already_exists)
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @usuario.nil?
          @usuario = Usuario.new(@atributos_param)
        else
          @usuario.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @usuario.save!
      end

      success(usuario: @usuario)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
  CriarService = SalvarService
  AtualizarService = SalvarService
end
