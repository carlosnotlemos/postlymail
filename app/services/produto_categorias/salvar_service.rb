module ProdutoCategorias
  class SalvarService < ApplicationService
    CATEGORIA_ATTRS = %i[nome slug ativo].freeze

    def initialize(
      empresa: nil,
      categoria: nil,
      atributos: nil,
      **kwargs
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @categoria_param = categoria
      @categoria = resolver_categoria(categoria)

      @atributos_param = extrair_atributos(atributos, kwargs)
      processar_slug
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

    def resolver_categoria(param)
      return param if param.is_a?(ProdutoCategoria)
      return nil if param.blank? || @empresa.nil?

      @empresa.produto_categorias.find_by(id: param)
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      if atributos.is_a?(Hash)
        attrs.merge!(atributos.symbolize_keys)
      end

      CATEGORIA_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def processar_slug
      if @atributos_param.key?(:slug) && @atributos_param[:slug].present?
        @atributos_param[:slug] = @atributos_param[:slug].to_s.strip.parameterize
      elsif @atributos_param[:nome].present? && (@atributos_param[:slug].blank? || !@atributos_param.key?(:slug))
        # Gera slug automaticamente a partir do nome apenas em novo registro ou se o nome foi alterado e slug não informado
        if @categoria.nil? || @atributos_param.key?(:slug)
          @atributos_param[:slug] = @atributos_param[:nome].to_s.strip.parameterize
        end
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_categoria = validar_categoria
      return validacao_categoria if validacao_categoria&.failure?

      validacao_slug = validar_slug_duplicado
      return validacao_slug if validacao_slug&.failure?

      nil
    end

    def validar_categoria
      if @categoria.nil? && @categoria_param.present?
        if @categoria_param.is_a?(ProdutoCategoria) || ProdutoCategoria.exists?(id: @categoria_param)
          return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Categoria não informada ou não encontrada", error_code: :category_not_found)
      end

      if @categoria && @categoria.empresa_id != @empresa.id
        return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_slug_duplicado
      slug = @atributos_param[:slug]
      return nil if slug.blank?

      existente = @empresa.produto_categorias.find_by(slug: slug)
      return nil unless existente

      if @categoria.present?
        if existente.id != @categoria.id
          return failure("Já existe uma categoria cadastrada com este slug nesta empresa", error_code: :slug_already_exists)
        end
      else
        return failure("Já existe uma categoria cadastrada com este slug nesta empresa", error_code: :slug_already_exists)
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @categoria.nil?
          @categoria = @empresa.produto_categorias.build(@atributos_param)
        else
          @categoria.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @categoria.save!
      end

      success(categoria: @categoria)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
end
