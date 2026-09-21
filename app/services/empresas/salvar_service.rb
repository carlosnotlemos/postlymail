# frozen_string_literal: true

module Empresas
  class SalvarService < ApplicationService
    EMPRESA_ATTRS = %i[
      nome
      slug
      email
      documento
      ativo
      data_cadastro
    ].freeze

    def initialize(
      empresa: nil,
      atributos: nil,
      **kwargs
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @atributos_param = extrair_atributos(atributos, kwargs)
      @slug_informado_explicitamente = @atributos_param.key?(:slug) && @atributos_param[:slug].present?
      normalizar_atributos
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

      # Busca por ID numérico
      if param.is_a?(Integer)
        return Empresa.find_by(id: param)
      end

      param_str = param.to_s.strip

      # Se string puramente numérica, tenta primeiro por ID
      if param_str =~ /\A\d+\z/
        empresa = Empresa.find_by(id: param_str.to_i)
        return empresa if empresa
      end

      # Busca por slug
      Empresa.find_by(slug: param_str.downcase)
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      attrs.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      EMPRESA_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_atributos
      normalizar_nome
      normalizar_slug
      normalizar_email
      normalizar_documento
      normalizar_ativo
    end

    def normalizar_nome
      return unless @atributos_param.key?(:nome)

      nome = @atributos_param[:nome]
      @atributos_param[:nome] = nome.to_s.strip if nome.is_a?(String)
    end

    def normalizar_slug
      if @slug_informado_explicitamente
        @atributos_param[:slug] = @atributos_param[:slug].to_s.strip.parameterize
      elsif @atributos_param[:nome].present? && (@atributos_param[:slug].blank? || !@atributos_param.key?(:slug))
        # Gera slug automaticamente a partir do nome apenas em novo registro ou se o slug foi informado em branco
        if @empresa.nil? || @atributos_param.key?(:slug)
          base_slug = @atributos_param[:nome].to_s.strip.parameterize
          @atributos_param[:slug] = gerar_slug_unico(base_slug) if base_slug.present?
        end
      end
    end

    def gerar_slug_unico(base_slug)
      return base_slug if slug_disponivel?(base_slug)

      escopo = Empresa.where("slug LIKE ?", "#{base_slug}-%")
      escopo = escopo.where.not(id: @empresa.id) if @empresa.present?
      slugs_ocupados = escopo.pluck(:slug).to_set

      sufixo = 2
      loop do
        candidato = "#{base_slug}-#{sufixo}"
        return candidato unless slugs_ocupados.include?(candidato) || (!@empresa && Empresa.exists?(slug: candidato))

        sufixo += 1
      end
    end

    def slug_disponivel?(slug)
      existente = Empresa.find_by(slug: slug)
      return true if existente.nil?
      return true if @empresa.present? && existente.id == @empresa.id

      false
    end


    def normalizar_email
      return unless @atributos_param.key?(:email)

      email = @atributos_param[:email]
      @atributos_param[:email] = email.to_s.strip.downcase if email.present?
    end

    def normalizar_documento
      return unless @atributos_param.key?(:documento)

      doc = @atributos_param[:documento]
      if doc.present?
        sanitizado = doc.to_s.gsub(/\D/, "")
        @atributos_param[:documento] = sanitizado.presence || doc.to_s.strip
      elsif doc.is_a?(String) && doc.blank?
        @atributos_param[:documento] = nil
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
      if @empresa.nil? && @empresa_param.present?
        return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found)
      end

      validacao_slug = validar_slug_duplicado
      return validacao_slug if validacao_slug&.failure?

      validacao_documento = validar_documento_duplicado
      return validacao_documento if validacao_documento&.failure?

      nil
    end

    def validar_slug_duplicado
      slug = @atributos_param[:slug]
      return nil if slug.blank?

      existente = Empresa.find_by(slug: slug)
      return nil unless existente

      if @empresa.present?
        if existente.id != @empresa.id
          return failure("Já existe uma empresa cadastrada com este slug", error_code: :slug_already_exists)
        end
      else
        return failure("Já existe uma empresa cadastrada com este slug", error_code: :slug_already_exists)
      end

      nil
    end

    def validar_documento_duplicado
      documento = @atributos_param[:documento]
      return nil if documento.blank?

      existente = Empresa.find_by(documento: documento)
      return nil unless existente

      if @empresa.present?
        if existente.id != @empresa.id
          return failure("Já existe uma empresa cadastrada com este documento", error_code: :document_already_exists)
        end
      else
        return failure("Já existe uma empresa cadastrada com este documento", error_code: :document_already_exists)
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @empresa.nil?
          @empresa = Empresa.new(@atributos_param)
        else
          @empresa.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @empresa.save!
      end

      success(empresa: @empresa)
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
