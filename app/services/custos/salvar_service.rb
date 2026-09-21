module Custos
  class SalvarService < ApplicationService
    CUSTO_ATTRS = %i[
      categoria
      valor
      data_custo
      descricao
      venda
      venda_id
    ].freeze

    OMITIDO = Object.new.freeze

    def initialize(
      empresa: nil,
      custo: nil,
      venda: OMITIDO,
      atributos: nil,
      **kwargs
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @custo_param = custo
      @custo = resolver_custo(custo)

      @atributos_param = extrair_atributos(atributos, kwargs)

      atributos_hash = atributos.is_a?(Hash) ? atributos : {}
      @venda_informada = (venda != OMITIDO) ||
                          kwargs.key?(:venda) ||
                          kwargs.key?(:venda_id) ||
                          atributos_hash.key?(:venda) ||
                          atributos_hash.key?(:venda_id) ||
                          atributos_hash.key?("venda") ||
                          atributos_hash.key?("venda_id")

      venda_val = (venda != OMITIDO) ? venda : (@atributos_param[:venda] || @atributos_param[:venda_id])
      @venda_param = venda_val
      @venda = resolver_venda(@venda_param)

      @categoria_informada = @atributos_param.key?(:categoria)
      @valor_informado = @atributos_param.key?(:valor)
      @data_custo_informada = @atributos_param.key?(:data_custo)

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

      Empresa.find_by(id: param)
    end

    def resolver_custo(param)
      return param if param.is_a?(Custo)
      return nil if param.blank? || @empresa.nil?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        @empresa.custos.find_by(id: param)
      end
    end

    def resolver_venda(param)
      return nil if param.blank?
      return param if param.is_a?(Venda)
      return nil if @empresa.nil?

      if param.is_a?(Integer)
        return @empresa.vendas.find_by(id: param)
      end

      if param.is_a?(String)
        if param =~ /\A\d+\z/
          venda_por_id = @empresa.vendas.find_by(id: param)
          return venda_por_id if venda_por_id
        end

        codigo = param.strip.upcase
        @empresa.vendas.find_by("UPPER(codigo_pedido) = ?", codigo)
      end
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      if atributos.is_a?(Hash)
        attrs.merge!(atributos.symbolize_keys)
      end

      CUSTO_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_atributos
      if @atributos_param.key?(:descricao) && @atributos_param[:descricao].present?
        @atributos_param[:descricao] = @atributos_param[:descricao].to_s.strip
      end

      if @atributos_param.key?(:categoria) && @atributos_param[:categoria].present?
        cat = @atributos_param[:categoria]
        enums = categorias_definidas
        if cat.is_a?(Symbol) || cat.is_a?(String)
          cat_str = cat.to_s
          if enums.key?(cat_str)
            @atributos_param[:categoria] = cat_str
          end
        elsif cat.is_a?(Integer)
          cat_str = enums.key(cat)
          @atributos_param[:categoria] = cat_str if cat_str
        end
      end

      if @atributos_param.key?(:valor) && @atributos_param[:valor].present?
        val = @atributos_param[:valor]
        if val.is_a?(String)
          val_str = val.strip
          if val_str.include?(",")
            val_str = val_str.tr(".", "").tr(",", ".")
          end
          @atributos_param[:valor] = BigDecimal(val_str) rescue val
        end
      end

      if @atributos_param.key?(:data_custo) && @atributos_param[:data_custo].present?
        val = @atributos_param[:data_custo]
        if val.is_a?(String)
          begin
            @atributos_param[:data_custo] = Date.parse(val.strip)
          rescue ArgumentError, Date::Error
            # Mantém original para falhar na validação semântica
          end
        elsif val.respond_to?(:to_date)
          @atributos_param[:data_custo] = val.to_date
        end
      elsif @custo.nil? && !@atributos_param.key?(:data_custo)
        @atributos_param[:data_custo] = Date.current
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_custo = validar_custo
      return validacao_custo if validacao_custo&.failure?

      validacao_venda = validar_venda
      return validacao_venda if validacao_venda&.failure?

      validacao_categoria = validar_categoria
      return validacao_categoria if validacao_categoria&.failure?

      validacao_valor = validar_valor
      return validacao_valor if validacao_valor&.failure?

      validacao_data = validar_data_custo
      return validacao_data if validacao_data&.failure?

      nil
    end

    def validar_custo
      if @custo.nil? && @custo_param.present?
        if custo_existe_em_outro_tenant?
          return failure("Custo não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Custo não informado ou não encontrado", error_code: :cost_not_found)
      end

      return failure("Custo não informado ou não encontrado", error_code: :cost_not_found) if @custo.nil? && @custo_param.present?

      if @custo && @custo.empresa_id != @empresa.id
        return failure("Custo não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def custo_existe_em_outro_tenant?
      return true if @custo_param.is_a?(Custo) && @custo_param.empresa_id != @empresa.id

      if @custo_param.is_a?(Integer) || (@custo_param.is_a?(String) && @custo_param =~ /\A\d+\z/)
        return Custo.where.not(empresa_id: @empresa.id).exists?(id: @custo_param)
      end

      false
    end

    def validar_venda
      return nil unless @venda_informada
      return nil if @venda_param.blank?

      if @venda.nil?
        if venda_existe_em_outro_tenant?
          return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Venda não informada ou não encontrada", error_code: :sale_not_found)
      end

      if @venda.empresa_id != @empresa.id
        return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def venda_existe_em_outro_tenant?
      return true if @venda_param.is_a?(Venda) && @venda_param.empresa_id != @empresa.id

      if @venda_param.is_a?(Integer) || (@venda_param.is_a?(String) && @venda_param =~ /\A\d+\z/)
        return Venda.where.not(empresa_id: @empresa.id).exists?(id: @venda_param)
      end

      if @venda_param.is_a?(String)
        codigo = @venda_param.strip.upcase
        return Venda.where.not(empresa_id: @empresa.id).where("UPPER(codigo_pedido) = ?", codigo).exists?
      end

      false
    end

    def validar_categoria
      if @custo.nil? && !@categoria_informada
        return failure("Categoria é obrigatória", error_code: :category_blank)
      end

      if @categoria_informada
        cat = @atributos_param[:categoria]
        return failure("Categoria é obrigatória", error_code: :category_blank) if cat.blank?

        unless categorias_definidas.key?(cat.to_s)
          return failure("Categoria de custo inválida", error_code: :invalid_category)
        end
      end

      nil
    end

    def categorias_definidas
      Custo.defined_enums["categoria"] || (Custo.respond_to?(:categorias) ? Custo.categorias : Custo.categoria)
    end

    def validar_valor
      if @custo.nil? && !@valor_informado
        return failure("Valor é obrigatório", error_code: :amount_blank)
      end

      if @valor_informado
        val = @atributos_param[:valor]
        return failure("Valor é obrigatório", error_code: :amount_blank) if val.nil?

        unless val.is_a?(Numeric)
          return failure("Valor do custo deve ser numérico", error_code: :invalid_amount)
        end

        if val < 0
          return failure("Valor do custo não pode ser negativo", error_code: :invalid_amount)
        end
      end

      nil
    end

    def validar_data_custo
      if @data_custo_informada
        data = @atributos_param[:data_custo]
        return failure("Data do custo é obrigatória", error_code: :cost_date_blank) if data.blank?

        unless data.is_a?(Date)
          return failure("Data do custo em formato inválido", error_code: :invalid_cost_date)
        end
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @custo.nil?
          @custo = @empresa.custos.build
        end

        @custo.categoria = @atributos_param[:categoria] if @categoria_informada
        @custo.valor = @atributos_param[:valor] if @valor_informado
        @custo.data_custo = @atributos_param[:data_custo] if @atributos_param.key?(:data_custo)
        @custo.descricao = @atributos_param[:descricao] if @atributos_param.key?(:descricao)

        if @venda_informada
          @custo.venda = @venda
        end

        @custo.save!
      end

      success(custo: @custo)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
  CriarService = SalvarService
end
