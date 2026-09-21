# frozen_string_literal: true

module Planos
  class SalvarService < ApplicationService
    PLANO_ATTRS = %i[
      identificador
      nome
      valor_mensal
      limite_produtos
      limite_disparos
      limite_usuarios
      ativo
    ].freeze

    def initialize(
      plano: nil,
      atributos: nil,
      **kwargs
    )
      @plano_param = plano
      @plano = resolver_plano(plano)

      @atributos_param = extrair_atributos(atributos, kwargs)
      normalizar_atributos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento
    end

    private

    def resolver_plano(param)
      return param if param.is_a?(Plano)
      return nil if param.blank?

      # Busca por ID numérico
      if param.is_a?(Integer)
        plano = Plano.find_by(id: param)
        return plano if plano

        # Se não encontrou por ID, tenta por identificador numérico caso válido
        return Plano.find_by(identificador: param) if Plano.identificadores.value?(param)
      end

      # Busca por identificador (symbol ou string)
      param_str = param.to_s.strip.downcase
      if Plano.identificadores.key?(param_str)
        plano = Plano.find_by(identificador: param_str)
        return plano if plano
      end

      # Se string puramente numérica, tenta por ID
      if param.is_a?(String) && param.strip =~ /\A\d+\z/
        return Plano.find_by(id: param.strip.to_i)
      end

      nil
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      attrs.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      PLANO_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_atributos
      normalizar_identificador
      normalizar_valor_mensal
      normalizar_limites
    end

    def normalizar_identificador
      return unless @atributos_param.key?(:identificador)

      identificador = @atributos_param[:identificador]
      return if identificador.blank?

      if identificador.is_a?(Symbol) || identificador.is_a?(String)
        str = identificador.to_s.strip.downcase
        @atributos_param[:identificador] = str if Plano.identificadores.key?(str)
      end
    end

    def normalizar_valor_mensal
      return unless @atributos_param.key?(:valor_mensal)

      valor = @atributos_param[:valor_mensal]
      return if valor.nil?

      if valor.is_a?(String)
        cleaned = valor.strip.gsub(/[R$\s]/, "")
        if cleaned.include?(",")
          cleaned = cleaned.gsub(".", "").tr(",", ".")
        end
        @atributos_param[:valor_mensal] = BigDecimal(cleaned) rescue valor
      end
    end

    def normalizar_limites
      %i[limite_produtos limite_usuarios limite_disparos].each do |campo|
        next unless @atributos_param.key?(campo)

        valor = @atributos_param[campo]
        if valor.is_a?(String) && valor.strip.blank?
          @atributos_param[campo] = nil
        elsif valor.present? && valor.to_s =~ /\A\d+\z/
          @atributos_param[campo] = valor.to_i
        end
      end
    end

    def validar_parametros
      if @plano.nil? && @plano_param.present?
        return failure("Plano não informado ou não encontrado", error_code: :plan_not_found)
      end

      validacao_duplicidade = validar_identificador_duplicado
      return validacao_duplicidade if validacao_duplicidade&.failure?

      nil
    end

    def validar_identificador_duplicado
      identificador = @atributos_param[:identificador]
      return nil if identificador.blank?

      existente = Plano.find_by(identificador: identificador)
      return nil unless existente

      if @plano.present?
        if existente.id != @plano.id
          return failure("Já existe um plano cadastrado com este identificador", error_code: :identifier_already_exists)
        end
      else
        return failure("Já existe um plano cadastrado com este identificador", error_code: :identifier_already_exists)
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @plano.nil?
          @plano = Plano.new(@atributos_param)
        else
          @plano.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @plano.save!
      end

      success(plano: @plano)
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
