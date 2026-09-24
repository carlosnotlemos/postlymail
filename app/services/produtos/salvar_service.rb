# frozen_string_literal: true

module Produtos
  class SalvarService < ApplicationService
    PRODUTO_ATTRS = %i[
      nome
      descricao
      ativo
      produto_categoria_id
    ].freeze

    OMITIDO = Object.new.freeze

    def initialize(
      empresa_ou_hash = nil,
      produto_ou_atributos = nil,
      empresa: nil,
      produto: nil,
      categoria: OMITIDO,
      produto_categoria: OMITIDO,
      categoria_id: OMITIDO,
      produto_categoria_id: OMITIDO,
      atributos: nil,
      variacao: nil,
      variacoes: nil,
      ignorar_limite: false,
      permitir_categoria_inativa: false,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if empresa_ou_hash.is_a?(Hash)
        dados.merge!(empresa_ou_hash.symbolize_keys)
      elsif empresa_ou_hash.present? && !dados.key?(:empresa)
        dados[:empresa] = empresa_ou_hash
      end

      if produto_ou_atributos.is_a?(Hash)
        dados.merge!(produto_ou_atributos.symbolize_keys)
      elsif produto_ou_atributos.present? && !dados.key?(:produto)
        dados[:produto] = produto_ou_atributos
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:produto] = produto if produto.present?

      @empresa_param = dados[:empresa]
      @produto_param = dados[:produto] || dados[:produto_id] || dados[:id]

      # Resolução de empresa e produto
      @empresa = resolver_empresa(@empresa_param)
      @produto = resolver_produto(@produto_param)
      @empresa ||= @produto&.empresa if @empresa_param.blank?

      @ignorar_limite = ignorar_limite || dados[:ignorar_limite] || false
      @permitir_categoria_inativa = permitir_categoria_inativa || dados[:permitir_categoria_inativa] || false

      # Extração e detecção de categoria
      @categoria_informada, @categoria_param = detectar_categoria(
        categoria, produto_categoria, categoria_id, produto_categoria_id, dados
      )
      @categoria = resolver_categoria(@categoria_param) if @categoria_informada

      # Variações opcionais
      @variacoes_param = extrair_variacoes(variacao, variacoes, dados)

      # Atributos do produto
      @atributos_param = extrair_atributos(dados)
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

    def resolver_produto(param)
      return param if param.is_a?(Produto)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param.strip =~ /\A\d+\z/)
        id_num = param.to_i
        return @empresa.produtos.find_by(id: id_num) if @empresa
        return Produto.find_by(id: id_num) if @empresa_param.blank?
      end

      nil
    end

    def detectar_categoria(categoria, produto_categoria, categoria_id, produto_categoria_id, dados)
      informada = false
      param = nil

      if categoria != OMITIDO
        informada = true
        param = categoria
      elsif produto_categoria != OMITIDO
        informada = true
        param = produto_categoria
      elsif categoria_id != OMITIDO
        informada = true
        param = categoria_id
      elsif produto_categoria_id != OMITIDO
        informada = true
        param = produto_categoria_id
      elsif dados.key?(:categoria)
        informada = true
        param = dados[:categoria]
      elsif dados.key?(:produto_categoria)
        informada = true
        param = dados[:produto_categoria]
      elsif dados.key?(:categoria_id)
        informada = true
        param = dados[:categoria_id]
      elsif dados.key?(:produto_categoria_id)
        informada = true
        param = dados[:produto_categoria_id]
      end

      [ informada, param ]
    end

    def resolver_categoria(param)
      return nil if param.nil? || param == ""
      return param if param.is_a?(ProdutoCategoria)
      return nil if @empresa.nil?

      if param.is_a?(Integer) || (param.is_a?(String) && param.strip =~ /\A\d+\z/)
        return @empresa.produto_categorias.find_by(id: param.to_i)
      end

      if param.is_a?(String) || param.is_a?(Symbol)
        slug = param.to_s.strip.downcase
        return @empresa.produto_categorias.find_by(slug: slug)
      end

      nil
    end

    def extrair_atributos(dados)
      attrs = {}

      PRODUTO_ATTRS.each do |attr_name|
        attrs[attr_name] = dados[attr_name] if dados.key?(attr_name)
      end

      attrs
    end

    def extrair_variacoes(variacao, variacoes, dados)
      lista = []
      vars = variacoes || dados[:variacoes]
      if vars.is_a?(Array)
        lista.concat(vars.select { |v| v.is_a?(Hash) })
      end

      var_unica = variacao || dados[:variacao]
      if var_unica.is_a?(Hash)
        lista << var_unica
      end

      lista
    end

    def normalizar_atributos
      if @atributos_param.key?(:nome) && @atributos_param[:nome].present?
        @atributos_param[:nome] = @atributos_param[:nome].to_s.strip
      end

      if @atributos_param.key?(:descricao) && @atributos_param[:descricao].present?
        @atributos_param[:descricao] = @atributos_param[:descricao].to_s.strip
      end

      if @atributos_param.key?(:ativo)
        valor = @atributos_param[:ativo]
        @atributos_param[:ativo] = ActiveModel::Type::Boolean.new.cast(valor) unless valor.nil?
      elsif @produto.nil?
        @atributos_param[:ativo] = true
      end

      if @categoria_informada
        @atributos_param[:produto_categoria_id] = @categoria&.id
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_produto = validar_produto
      return validacao_produto if validacao_produto&.failure?

      validacao_categoria = validar_categoria
      return validacao_categoria if validacao_categoria&.failure?

      validacao_limite = validar_limite_produtos
      return validacao_limite if validacao_limite&.failure?

      nil
    end

    def validar_produto
      if @produto.nil? && @produto_param.present?
        if produto_existe_em_outro_tenant?
          return failure("Produto não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Produto não informado ou não encontrado", error_code: :product_not_found)
      end

      if @produto && @produto.empresa_id != @empresa.id
        return failure("Produto não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def produto_existe_em_outro_tenant?
      return true if @produto_param.is_a?(Produto) && @produto_param.empresa_id != @empresa.id

      if @produto_param.is_a?(Integer) || (@produto_param.is_a?(String) && @produto_param.strip =~ /\A\d+\z/)
        return Produto.where.not(empresa_id: @empresa.id).exists?(id: @produto_param.to_i)
      end

      false
    end

    def validar_categoria
      return nil unless @categoria_informada
      return nil if @categoria_param.blank?

      if @categoria.nil?
        if categoria_existe_em_outro_tenant?
          return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Categoria não informada ou não encontrada", error_code: :category_not_found)
      end

      if @categoria.empresa_id != @empresa.id
        return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if !@categoria.ativo? && !@permitir_categoria_inativa
        categoria_alterada = @produto.nil? || @produto.produto_categoria_id != @categoria.id
        if categoria_alterada
          return failure("A categoria informada está inativa", error_code: :category_inactive)
        end
      end

      nil
    end

    def categoria_existe_em_outro_tenant?
      return true if @categoria_param.is_a?(ProdutoCategoria) && @categoria_param.empresa_id != @empresa.id

      if @categoria_param.is_a?(Integer) || (@categoria_param.is_a?(String) && @categoria_param.strip =~ /\A\d+\z/)
        return ProdutoCategoria.where.not(empresa_id: @empresa.id).exists?(id: @categoria_param.to_i)
      end

      if @categoria_param.is_a?(String) || @categoria_param.is_a?(Symbol)
        slug = @categoria_param.to_s.strip.downcase
        return ProdutoCategoria.where.not(empresa_id: @empresa.id).where(slug: slug).exists?
      end

      false
    end

    def validar_limite_produtos
      return nil if @produto.present?
      return nil if @ignorar_limite

      assinatura = @empresa.assinatura_ativa
      return nil if assinatura.nil?

      plano = assinatura.plano
      return nil if plano.nil? || plano.ilimitado_produtos?

      total_produtos = @empresa.produtos.count
      if total_produtos >= plano.limite_produtos
        return failure(
          "Limite de produtos atingido para o plano contratado (#{plano.limite_produtos})",
          error_code: :plan_product_limit_reached
        )
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @produto.nil?
          @produto = @empresa.produtos.build(@atributos_param)
        else
          @produto.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        if @categoria_informada
          @produto.produto_categoria = @categoria
        end

        @produto.save!

        if @variacoes_param.present?
          @variacoes_param.each do |v_attrs|
            attrs = v_attrs.is_a?(Hash) ? v_attrs.symbolize_keys : {}
            var_id = attrs[:id]
            variacao_rec = if var_id.present?
                             @produto.variacoes.find(var_id)
            else
                             @produto.variacoes.build
            end

            variacao_rec.empresa = @empresa
            variacao_rec.assign_attributes(attrs.except(:id))
            variacao_rec.save!
          end
        end
      end

      @produto.reload
      success(produto: @produto)
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
