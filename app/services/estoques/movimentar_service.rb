module Estoques
  class MovimentarService < ApplicationService
    ENTRADAS = %w[entrada_producao estorno_devolucao].freeze
    SAIDAS = %w[saida_venda perda_avaria brinde_marketing].freeze
    AJUSTE = "ajuste_manual".freeze
    ALL_TYPES = (ENTRADAS + SAIDAS + [ AJUSTE ]).freeze

    def initialize(empresa:, variacao_produto:, tipo:, quantidade:, usuario: nil, origem: nil, origem_tipo: nil, origem_id: nil, motivo: nil)
      @empresa = empresa.is_a?(Empresa) ? empresa : Empresa.find_by(id: empresa)
      @variacao_produto_param = variacao_produto
      @variacao_produto = resolver_variacao_produto(variacao_produto)
      @tipo = tipo.to_s
      @quantidade = quantidade
      @usuario = resolver_usuario(usuario)
      @origem = origem
      @origem_tipo = origem_tipo
      @origem_id = origem_id
      @motivo = motivo
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_movimentacao
    end

    private

    def resolver_variacao_produto(param)
      if param.is_a?(VariacaoProduto)
        param
      elsif @empresa
        @empresa.variacoes_produtos.find_by(id: param)
      end
    end

    def resolver_usuario(param)
      return nil if param.blank?
      return param if param.is_a?(Usuario)

      Usuario.find_by(id: param)
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      if @variacao_produto.nil?
        if @variacao_produto_param.present? && VariacaoProduto.exists?(id: @variacao_produto_param)
          return failure("Variação do produto não pertence à empresa informada", error_code: :unauthorized_tenant)
        end
        return failure("Variação do produto não informada ou não encontrada", error_code: :product_variation_not_found)
      end

      if @variacao_produto.empresa_id != @empresa.id
        return failure("Variação do produto não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      unless ALL_TYPES.include?(@tipo)
        return failure("Tipo de movimentação inválido: #{@tipo}", error_code: :invalid_movement_type)
      end

      validar_quantidade
    end

    def validar_quantidade
      unless @quantidade.is_a?(Integer) || (@quantidade.is_a?(String) && @quantidade =~ /\A-?\d+\z/)
        return failure("Quantidade deve ser um número inteiro", error_code: :invalid_quantity)
      end

      qtd_int = @quantidade.to_i

      if @tipo == AJUSTE
        if qtd_int == 0
          return failure("Quantidade para ajuste manual não pode ser zero", error_code: :invalid_quantity)
        end
      elsif qtd_int <= 0
        return failure("Quantidade deve ser maior que zero", error_code: :invalid_quantity)
      end

      nil
    end

    def calcular_delta
      qtd_int = @quantidade.to_i

      if ENTRADAS.include?(@tipo)
        qtd_int
      elsif SAIDAS.include?(@tipo)
        -qtd_int
      elsif @tipo == AJUSTE
        qtd_int
      end
    end

    def extrair_origem_attrs
      if @origem.is_a?(ActiveRecord::Base)
        { origem_tipo: @origem.class.name, origem_id: @origem.id }
      elsif @origem.is_a?(Hash)
        tipo = @origem[:tipo] || @origem[:origem_tipo]
        id   = @origem[:id]   || @origem[:origem_id]
        { origem_tipo: tipo&.to_s, origem_id: id }
      else
        { origem_tipo: @origem_tipo&.to_s, origem_id: @origem_id }
      end
    end

    def executar_movimentacao
      estoque = @variacao_produto.estoque
      if estoque.nil?
        return failure("Estoque não encontrado para esta variação", error_code: :stock_not_found)
      end

      result = nil

      estoque.with_lock do
        saldo_anterior = estoque.quantidade
        delta = calcular_delta
        saldo_posterior = saldo_anterior + delta

        if saldo_posterior < 0
          result = failure("Saldo insuficiente em estoque", error_code: :insufficient_stock)
          raise ActiveRecord::Rollback
        end

        estoque.update!(quantidade: saldo_posterior)

        origem_attrs = extrair_origem_attrs

        movimentacao = EstoqueMovimentacao.create!(
          empresa: @empresa,
          variacao_produto: @variacao_produto,
          tipo: @tipo,
          quantidade: @quantidade.to_i.abs,
          saldo_anterior: saldo_anterior,
          saldo_posterior: saldo_posterior,
          usuario: @usuario,
          motivo: @motivo,
          **origem_attrs
        )

        result = success(movimentacao: movimentacao, estoque: estoque)
      end

      if result&.failure?
        estoque.reload
      end

      result || failure("Erro ao processar movimentação de estoque", error_code: :execution_failed)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
