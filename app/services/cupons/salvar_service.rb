module Cupons
  class SalvarService < ApplicationService
    CUPOM_ATTRS = %i[
      codigo
      tipo
      valor
      valor_minimo_pedido
      limite_usos
      valido_de
      valido_ate
      ativo
    ].freeze

    def initialize(
      empresa: nil,
      cupom: nil,
      atributos: nil,
      **kwargs
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @cupom_param = cupom
      @cupom = resolver_cupom(cupom)

      @atributos_param = extrair_atributos(atributos, kwargs)
      normalizar_codigo
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

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      if atributos.is_a?(Hash)
        attrs.merge!(atributos.symbolize_keys)
      end

      CUPOM_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_codigo
      if @atributos_param[:codigo].present?
        @atributos_param[:codigo] = @atributos_param[:codigo].to_s.strip.upcase
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cupom = validar_cupom
      return validacao_cupom if validacao_cupom&.failure?

      validacao_codigo = validar_codigo_duplicado
      return validacao_codigo if validacao_codigo&.failure?

      validacao_datas = validar_datas_vigencia
      return validacao_datas if validacao_datas&.failure?

      validar_limite_usos
    end

    def validar_cupom
      if @cupom.nil? && @cupom_param.present?
        if cupom_existe_em_outro_tenant?
          return failure("Cupom não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Cupom não informado ou não encontrado", error_code: :coupon_not_found)
      end

      if @cupom && @cupom.empresa_id != @empresa.id
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

    def validar_codigo_duplicado
      codigo = @atributos_param[:codigo]
      return nil if codigo.blank?

      existente = @empresa.cupons.find_by("UPPER(codigo) = ?", codigo)
      return nil unless existente

      if @cupom.present?
        if existente.id != @cupom.id
          return failure("Já existe um cupom cadastrado com este código nesta empresa", error_code: :coupon_code_already_exists)
        end
      else
        return failure("Já existe um cupom cadastrado com este código nesta empresa", error_code: :coupon_code_already_exists)
      end

      nil
    end

    def validar_datas_vigencia
      de = @atributos_param.key?(:valido_de) ? @atributos_param[:valido_de] : @cupom&.valido_de
      ate = @atributos_param.key?(:valido_ate) ? @atributos_param[:valido_ate] : @cupom&.valido_ate

      if de.present? && ate.present? && de > ate
        return failure("Data de início da vigência não pode ser posterior à data de término", error_code: :invalid_validity_dates)
      end

      nil
    end

    def validar_limite_usos
      if @cupom.present? && @atributos_param.key?(:limite_usos) && @atributos_param[:limite_usos].present?
        novo_limite = @atributos_param[:limite_usos].to_i
        if novo_limite < @cupom.usos_contagem
          return failure(
            "Limite de utilizações (#{novo_limite}) não pode ser menor que a quantidade de usos já realizados (#{@cupom.usos_contagem})",
            error_code: :limit_lower_than_usage_count
          )
        end
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @cupom.nil?
          @cupom = @empresa.cupons.build(@atributos_param)
        else
          @cupom.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @cupom.save!
      end

      success(cupom: @cupom)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
end
