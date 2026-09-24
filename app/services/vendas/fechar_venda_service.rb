# frozen_string_literal: true

module Vendas
  class FecharVendaService < ApplicationService
    def initialize(
      empresa_ou_hash = nil,
      cliente_ou_atributos = nil,
      empresa: nil,
      cliente: nil,
      usuario: nil,
      tipo_entrega: nil,
      endereco: nil,
      endereco_id: nil,
      itens: nil,
      cupom: nil,
      codigo_cupom: nil,
      desconto_manual: nil,
      valor_frete: nil,
      observacoes: nil,
      status: nil,
      data_venda: nil,
      codigo_pedido: nil,
      codigo_rastreio: nil,
      baixar_estoque: true,
      pagamento: nil,
      pagamentos: nil,
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

      if cliente_ou_atributos.is_a?(Hash)
        dados.merge!(cliente_ou_atributos.symbolize_keys)
      elsif cliente_ou_atributos.present? && !dados.key?(:cliente)
        dados[:cliente] = cliente_ou_atributos
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:cliente] = cliente if cliente.present?
      dados[:usuario] = usuario if usuario.present?
      dados[:tipo_entrega] = tipo_entrega if tipo_entrega.present?
      dados[:endereco] = endereco if endereco.present?
      dados[:endereco_id] = endereco_id if endereco_id.present?
      dados[:itens] = itens if itens.present?
      dados[:cupom] = cupom if cupom.present?
      dados[:codigo_cupom] = codigo_cupom if codigo_cupom.present?
      dados[:desconto_manual] = desconto_manual unless desconto_manual.nil?
      dados[:valor_frete] = valor_frete unless valor_frete.nil?
      dados[:observacoes] = observacoes if observacoes.present?
      dados[:status] = status if status.present?
      dados[:data_venda] = data_venda if data_venda.present?
      dados[:codigo_pedido] = codigo_pedido if codigo_pedido.present?
      dados[:codigo_rastreio] = codigo_rastreio if codigo_rastreio.present?
      dados[:baixar_estoque] = baixar_estoque unless baixar_estoque.nil?
      dados[:pagamento] = pagamento if pagamento.present?
      dados[:pagamentos] = pagamentos if pagamentos.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @cliente_param = dados[:cliente] || dados[:cliente_id]
      @cliente = resolver_cliente(@cliente_param)

      @usuario_param = dados[:usuario] || dados[:usuario_id]
      @usuario = resolver_usuario(@usuario_param)

      @tipo_entrega_raw = dados[:tipo_entrega]
      @tipo_entrega = normalizar_tipo_entrega(@tipo_entrega_raw)

      @endereco_param = dados[:endereco] || dados[:endereco_id]
      @itens_param = dados[:itens] || []

      @cupom_param = dados[:cupom] || dados[:codigo_cupom]
      @cupom = nil
      @cupom_resultado = nil

      @desconto_manual_param = dados[:desconto_manual] || 0.0
      @desconto_manual = 0.0

      @valor_frete_param = dados[:valor_frete] || 0.0
      @valor_frete = 0.0

      @observacoes = dados[:observacoes]
      @status_param = dados[:status] || :pendente
      @status = normalizar_status(@status_param)

      @data_venda = dados[:data_venda] || Time.current
      @codigo_pedido = dados[:codigo_pedido]
      @codigo_rastreio = dados[:codigo_rastreio]

      @baixar_estoque = dados.key?(:baixar_estoque) ? dados[:baixar_estoque] : true
      @pagamento_param = dados[:pagamento]
      @pagamentos_param = dados[:pagamentos]

      @itens_processados = []
      @subtotal_produtos = BigDecimal("0.0")
      @desconto_cupom = BigDecimal("0.0")
      @valor_desconto = BigDecimal("0.0")
      @valor_total = BigDecimal("0.0")
      @endereco_snapshot = {}
      @erro_cupom = nil
      @erro_estoque = nil
      @erro_pagamento = nil
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_fechamento
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

    def resolver_cliente(param)
      return param if param.is_a?(Cliente)
      return nil if param.blank? || @empresa.nil?

      id = param.is_a?(Hash) ? param[:id] || param["id"] : param
      @empresa.clientes.find_by(id: id)
    end

    def resolver_usuario(param)
      return nil if param.blank?
      return param if param.is_a?(Usuario)

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Usuario.find_by(id: param.to_i)
      end

      Usuario.find_by(email: param.to_s.strip.downcase)
    end

    def normalizar_tipo_entrega(param)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Venda.tipo_entregas.key(param)
      end

      param_str = param.to_s.strip.underscore
      Venda.tipo_entregas.key?(param_str) ? param_str : nil
    end

    def normalizar_status(param)
      return :pendente if param.blank?

      if param.is_a?(Integer)
        key = Venda.statuses.key(param)
        return key ? key.to_sym : nil
      end

      param_str = param.to_s.strip.underscore
      Venda.statuses.key?(param_str) ? param_str.to_sym : nil
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) if @empresa.nil?

      validacao_cliente = validar_cliente
      return validacao_cliente if validacao_cliente&.failure?

      validacao_usuario = validar_usuario
      return validacao_usuario if validacao_usuario&.failure?

      validacao_tipo = validar_tipo_entrega
      return validacao_tipo if validacao_tipo&.failure?

      validacao_status = validar_status
      return validacao_status if validacao_status&.failure?

      validacao_itens = processar_e_validar_itens
      return validacao_itens if validacao_itens&.failure?

      validacao_endereco = resolver_e_validar_endereco
      return validacao_endereco if validacao_endereco&.failure?

      validacao_valores = processar_descontos_e_totais
      return validacao_valores if validacao_valores&.failure?

      nil
    end

    def validar_cliente
      if @cliente.nil?
        if @cliente_param.present?
          id = @cliente_param.is_a?(Cliente) ? @cliente_param.id : @cliente_param
          if Cliente.exists?(id: id)
            return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
        end
        return failure("Cliente não informado ou não encontrado", error_code: :client_not_found)
      end

      if @cliente.empresa_id != @empresa.id
        return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_usuario
      return nil if @usuario_param.blank?

      if @usuario.nil?
        return failure("Usuário informado não foi encontrado", error_code: :usuario_not_found)
      end

      # Se informado, verificar se o usuário é membro ativo da empresa
      unless @empresa.membros.ativos.exists?(usuario_id: @usuario.id)
        return failure("Usuário informado não é membro ativo desta empresa", error_code: :unauthorized_user)
      end

      nil
    end

    def validar_tipo_entrega
      if @tipo_entrega.nil?
        return failure("Tipo de entrega não informado ou inválido", error_code: :invalid_delivery_type)
      end

      nil
    end

    def validar_status
      if @status.nil?
        return failure("Status da venda inválido", error_code: :invalid_status)
      end

      if @status == :cancelada
        return failure("Não é permitido criar venda diretamente com status cancelada", error_code: :invalid_initial_status)
      end

      nil
    end

    def processar_e_validar_itens
      itens_array = @itens_param.is_a?(Array) ? @itens_param : [ @itens_param ].compact
      if itens_array.empty?
        return failure("Venda deve conter ao menos um item", error_code: :empty_items)
      end

      @subtotal_produtos = BigDecimal("0.0")
      @itens_processados = []

      itens_array.each_with_index do |item_raw, index|
        dados_item = item_raw.is_a?(Hash) ? item_raw.symbolize_keys : {}

        variacao_ref = dados_item[:variacao_produto] || dados_item[:variacao_produto_id] ||
                       dados_item[:variacao] || dados_item[:variacao_id]

        variacao = resolver_variacao(variacao_ref)
        if variacao.nil?
          if variacao_ref.present? && VariacaoProduto.exists?(id: (variacao_ref.is_a?(VariacaoProduto) ? variacao_ref.id : variacao_ref))
            return failure("Item #{index + 1}: Variação de produto não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
          return failure("Item #{index + 1}: Variação de produto não informada ou não encontrada", error_code: :product_variation_not_found)
        end

        if variacao.empresa_id != @empresa.id
          return failure("Item #{index + 1}: Variação de produto não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        unless variacao.ativo?
          return failure("Item #{index + 1}: Variação #{variacao.sku} está inativa", error_code: :variation_inactive)
        end

        quantidade_raw = dados_item[:quantidade]
        unless quantidade_raw.is_a?(Integer) || (quantidade_raw.is_a?(String) && quantidade_raw =~ /\A\d+\z/)
          return failure("Item #{index + 1}: Quantidade deve ser um número inteiro maior que zero", error_code: :invalid_quantity)
        end

        quantidade = quantidade_raw.to_i
        if quantidade <= 0
          return failure("Item #{index + 1}: Quantidade deve ser maior que zero", error_code: :invalid_quantity)
        end

        valor_unitario_num = if dados_item[:valor_unitario].present?
                               parse_decimal(dados_item[:valor_unitario])
        else
                               variacao.preco_base.to_d
        end

        if valor_unitario_num.nil? || valor_unitario_num < 0
          return failure("Item #{index + 1}: Valor unitário inválido", error_code: :invalid_unit_price)
        end

        preco_custo_num = if dados_item[:preco_custo_unitario].present?
                            parse_decimal(dados_item[:preco_custo_unitario])
        else
                            variacao.preco_custo.to_d
        end

        if preco_custo_num.nil? || preco_custo_num < 0
          return failure("Item #{index + 1}: Preço de custo unitário inválido", error_code: :invalid_cost_price)
        end

        subtotal_item = (valor_unitario_num * quantidade).round(2)
        @subtotal_produtos += subtotal_item

        detalhes = {
          "produto_id" => variacao.produto_id,
          "produto_nome" => variacao.produto&.nome,
          "variacao_id" => variacao.id,
          "sku" => variacao.sku,
          "tamanho" => variacao.tamanho,
          "cor" => variacao.cor,
          "codigo_barras" => variacao.codigo_barras,
          "preco_base_tabela" => variacao.preco_base.to_f,
          "preco_custo_tabela" => variacao.preco_custo.to_f
        }.compact

        @itens_processados << {
          variacao_produto: variacao,
          quantidade: quantidade,
          valor_unitario: valor_unitario_num,
          preco_custo_unitario: preco_custo_num,
          subtotal: subtotal_item,
          detalhes_produto: detalhes,
          observacoes: dados_item[:observacoes]
        }
      end

      nil
    end

    def resolver_variacao(param)
      return param if param.is_a?(VariacaoProduto)
      return nil if param.blank? || @empresa.nil?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return @empresa.variacoes_produtos.find_by(id: param.to_i)
      end

      @empresa.variacoes_produtos.find_by(sku: param.to_s.strip.upcase)
    end

    def resolver_e_validar_endereco
      resultado_end = Clientes::ResolverEnderecoService.call(
        empresa: @empresa,
        cliente: @cliente,
        endereco: @endereco_param,
        tipo_entrega: @tipo_entrega
      )

      if resultado_end.failure?
        return failure(resultado_end.error, error_code: resultado_end.error_code)
      end

      @endereco_snapshot = resultado_end.data[:snapshot]
      nil
    end

    def parse_decimal(param)
      return BigDecimal("0.0") if param.blank?
      return param.to_d if param.is_a?(Numeric)

      cleaned = param.to_s.strip.gsub(/[R$\s]/, "")
      if cleaned =~ /\A\d{1,3}(\.\d{3})*,\d+\z/
        cleaned = cleaned.gsub(".", "").tr(",", ".")
      else
        cleaned = cleaned.tr(",", ".")
      end

      BigDecimal(cleaned)
    rescue ArgumentError
      nil
    end

    def processar_descontos_e_totais
      # Desconto manual
      desconto_manual_num = parse_decimal(@desconto_manual_param)
      if desconto_manual_num.nil? || desconto_manual_num < 0
        return failure("Desconto manual inválido", error_code: :invalid_manual_discount)
      end
      @desconto_manual = desconto_manual_num.round(2)

      # Frete
      valor_frete_num = parse_decimal(@valor_frete_param)
      if valor_frete_num.nil? || valor_frete_num < 0
        return failure("Valor do frete inválido", error_code: :invalid_freight)
      end
      @valor_frete = valor_frete_num.round(2)

      # Cupom
      if @cupom_param.present?
        resultado_cupom = Cupons::AplicarService.call(
          empresa: @empresa,
          cupom: @cupom_param,
          subtotal: @subtotal_produtos,
          consumir: false
        )

        if resultado_cupom.failure?
          return failure(resultado_cupom.error, error_code: resultado_cupom.error_code)
        end

        @cupom_resultado = resultado_cupom.data
        @cupom = @cupom_resultado[:cupom]
        @desconto_cupom = @cupom_resultado[:desconto].to_d.round(2)
      else
        @desconto_cupom = BigDecimal("0.0")
      end

      @valor_desconto = (@desconto_manual + @desconto_cupom).round(2)

      if @valor_desconto > @subtotal_produtos
        return failure("Valor total de desconto não pode ser maior que o subtotal dos produtos", error_code: :discount_exceeds_subtotal)
      end

      @valor_total = (@subtotal_produtos + @valor_frete - @valor_desconto).round(2)
      nil
    end

    def executar_fechamento
      venda = nil
      pagamentos_criados = []

      ActiveRecord::Base.transaction do
        # 1. Consumir o cupom caso informado
        if @cupom.present?
          consumo_res = Cupons::AplicarService.call(
            empresa: @empresa,
            cupom: @cupom,
            subtotal: @subtotal_produtos,
            consumir: true
          )
          if consumo_res.failure?
            @erro_cupom = consumo_res
            raise ActiveRecord::Rollback
          end
        end

        # 2. Criar registro principal de Venda
        status_inicial = @status
        if status_inicial == :pendente && @valor_total.zero? && @valor_desconto.positive?
          status_inicial = :paga
        end

        attrs_venda = {
          empresa: @empresa,
          cliente: @cliente,
          usuario: @usuario,
          tipo_entrega: @tipo_entrega,
          endereco_entrega: @endereco_snapshot,
          subtotal_produtos: @subtotal_produtos,
          valor_frete: @valor_frete,
          desconto_manual: @desconto_manual,
          desconto_cupom: @desconto_cupom,
          valor_desconto: @valor_desconto,
          valor_total: @valor_total,
          cupom: @cupom,
          codigo_cupom: @cupom&.codigo,
          status: status_inicial,
          data_venda: @data_venda,
          observacoes: @observacoes,
          codigo_rastreio: @codigo_rastreio
        }
        attrs_venda[:codigo_pedido] = @codigo_pedido if @codigo_pedido.present?

        venda = Venda.new(attrs_venda)
        venda.save!

        # 3. Criar os itens da venda
        @itens_processados.each do |item_info|
          venda.itens.create!(
            variacao_produto: item_info[:variacao_produto],
            quantidade: item_info[:quantidade],
            valor_unitario: item_info[:valor_unitario],
            preco_custo_unitario: item_info[:preco_custo_unitario],
            subtotal: item_info[:subtotal],
            detalhes_produto: item_info[:detalhes_produto],
            observacoes: item_info[:observacoes]
          )
        end

        # 4. Baixar estoque se solicitado
        if @baixar_estoque
          @itens_processados.each do |item_info|
            movimentacao_res = Estoques::MovimentarService.call(
              empresa: @empresa,
              variacao_produto: item_info[:variacao_produto],
              tipo: "saida_venda",
              quantidade: item_info[:quantidade],
              usuario: @usuario,
              origem: venda,
              motivo: "Venda #{venda.codigo_pedido}"
            )

            if movimentacao_res.failure?
              # Forçar rollback da transação e retornar o erro específico de estoque
              @erro_estoque = movimentacao_res
              raise ActiveRecord::Rollback
            end
          end
        end

        # 5. Processar pagamentos opcionais
        processar_pagamentos(venda, pagamentos_criados)
      end

      if @erro_cupom.present?
        return failure(@erro_cupom.error, error_code: @erro_cupom.error_code)
      end

      if @erro_estoque.present?
        return failure(@erro_estoque.error, error_code: @erro_estoque.error_code)
      end

      if @erro_pagamento.present?
        return failure(@erro_pagamento.error, error_code: @erro_pagamento.error_code)
      end

      unless venda&.persisted?
        return failure("Erro ao processar fechamento da venda", error_code: :execution_failed)
      end

      success(
        venda: venda,
        itens: venda.itens.to_a,
        pagamentos: pagamentos_criados,
        subtotal_produtos: @subtotal_produtos,
        valor_desconto: @valor_desconto,
        valor_total: @valor_total
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end

    def processar_pagamentos(venda, lista_pagamentos)
      pagamentos_raw = @pagamentos_param || [ @pagamento_param ].compact
      return if pagamentos_raw.blank?

      res = Pagamentos::RegistrarService.call(
        venda: venda,
        pagamento: @pagamento_param,
        pagamentos: @pagamentos_param,
        atualizar_status_venda: true
      )

      if res.success?
        lista_pagamentos.concat(res.data[:pagamentos])
      else
        @erro_pagamento = res
        raise ActiveRecord::Rollback
      end
    end
  end

  SalvarService = FecharVendaService
  CriarService = FecharVendaService
  FecharService = FecharVendaService
end
