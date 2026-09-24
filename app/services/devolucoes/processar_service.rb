# frozen_string_literal: true

module Devolucoes
  class ProcessarService < ApplicationService
    def initialize(
      venda_ou_hash = nil,
      tipo_ou_atributos = nil,
      venda: nil,
      empresa: nil,
      usuario: nil,
      tipo: nil,
      motivo: nil,
      valor_estornado: nil,
      data_devolucao: nil,
      itens: nil,
      atributos: nil,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if venda_ou_hash.is_a?(Hash)
        dados.merge!(venda_ou_hash.symbolize_keys)
      elsif venda_ou_hash.present? && !dados.key?(:venda)
        dados[:venda] = venda_ou_hash
      end

      if tipo_ou_atributos.is_a?(Hash)
        dados.merge!(tipo_ou_atributos.symbolize_keys)
      elsif tipo_ou_atributos.present? && !dados.key?(:tipo)
        dados[:tipo] = tipo_ou_atributos
      end

      dados[:venda] = venda if venda.present?
      dados[:empresa] = empresa if empresa.present?
      dados[:usuario] = usuario if usuario.present?
      dados[:tipo] = tipo if tipo.present?
      dados[:motivo] = motivo if motivo.present?
      dados[:valor_estornado] = valor_estornado unless valor_estornado.nil?
      dados[:data_devolucao] = data_devolucao if data_devolucao.present?
      dados[:itens] = itens if itens.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @venda_param = dados[:venda] || dados[:venda_id] || dados[:codigo_pedido]
      @venda = resolver_venda(@venda_param)
      @empresa ||= @venda&.empresa

      @usuario_param = dados[:usuario] || dados[:usuario_id]
      @usuario = resolver_usuario(@usuario_param)

      @tipo_raw = dados[:tipo]
      @tipo = normalizar_tipo(@tipo_raw)

      @motivo = dados[:motivo]
      @valor_estornado_param = dados[:valor_estornado]
      @data_devolucao = dados[:data_devolucao] || Time.current

      @itens_param = dados[:itens]
      @itens_processados = []
      @valor_estornado_calculado = BigDecimal("0.0")
      @erro_estoque = nil
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_devolucao
    end

    private

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Empresa.find_by(id: param.to_i)
      end

      Empresa.find_by(slug: param.to_s.strip.downcase)
    end

    def resolver_venda(param)
      return param if param.is_a?(Venda)
      return nil if param.blank?

      if @empresa.present?
        if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
          return @empresa.vendas.find_by(id: param.to_i)
        end
        return @empresa.vendas.find_by(codigo_pedido: param.to_s.strip.upcase)
      end

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Venda.find_by(id: param.to_i)
      end

      Venda.find_by(codigo_pedido: param.to_s.strip.upcase)
    end

    def resolver_usuario(param)
      return nil if param.blank?
      return param if param.is_a?(Usuario)

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Usuario.find_by(id: param.to_i)
      end

      Usuario.find_by(email: param.to_s.strip.downcase)
    end

    def normalizar_tipo(param)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Devolucao.tipos.key(param)
      end

      param_str = param.to_s.strip.underscore
      Devolucao.tipos.key?(param_str) ? param_str : nil
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

    def validar_parametros
      if @venda.nil?
        if @venda_param.present? && @empresa_param.present?
          id_ou_cod = @venda_param.is_a?(Venda) ? @venda_param.id : @venda_param
          if Venda.where(id: id_ou_cod).or(Venda.where(codigo_pedido: id_ou_cod.to_s.strip.upcase)).exists?
            return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
        end
        return failure("Venda não informada ou não encontrada", error_code: :sale_not_found)
      end

      if @empresa_param.present? && @empresa.present? && @venda.empresa_id != @empresa.id
        return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @venda.cancelada?
        return failure("Não é possível registrar devolução para uma venda cancelada", error_code: :cannot_return_cancelled_sale)
      end

      if @tipo.nil?
        return failure("Tipo de devolução não informado ou inválido: #{@tipo_raw}", error_code: :invalid_return_type)
      end

      validacao_itens = processar_e_validar_itens
      return validacao_itens if validacao_itens&.failure?

      validar_valor_estornado
    end

    def processar_e_validar_itens
      @itens_processados = []
      @valor_estornado_calculado = BigDecimal("0.0")

      itens_raw = @itens_param

      if itens_raw.blank?
        # Devolução padrão de todos os itens com saldo elegível
        itens_raw = @venda.itens.map do |vi|
          qtd_devolvida = DevolucaoItem.where(venda_item_id: vi.id).sum(:quantidade)
          saldo = vi.quantidade - qtd_devolvida
          next if saldo <= 0

          {
            venda_item: vi,
            quantidade: saldo,
            retornou_ao_estoque: (@tipo != "defeito_avaria")
          }
        end.compact

        if itens_raw.empty?
          return failure("Todos os itens desta venda já foram devolvidos anteriormente", error_code: :no_items_available_for_return)
        end
      end

      itens_array = itens_raw.is_a?(Array) ? itens_raw : [ itens_raw ]
      if itens_array.empty?
        return failure("Nenhum item informado para devolução", error_code: :empty_items)
      end

      itens_array.each_with_index do |item_dado, index|
        dados = item_dado.is_a?(Hash) ? item_dado.symbolize_keys : {}

        ref_item = dados[:venda_item] || dados[:venda_item_id] || dados[:item_id] || dados[:id]
        vi = resolver_venda_item(ref_item)

        if vi.nil?
          id_ref = ref_item.is_a?(Hash) ? ref_item[:id] || ref_item["id"] : ref_item
          if ref_item.present? && VendaItem.exists?(id: id_ref)
            return failure("Item #{index + 1}: Item informado não pertence a esta venda", error_code: :unauthorized_item)
          end
          return failure("Item #{index + 1}: Item da venda não encontrado", error_code: :sale_item_not_found)
        end

        if vi.venda_id != @venda.id
          return failure("Item #{index + 1}: Item informado não pertence a esta venda", error_code: :unauthorized_item)
        end

        qtd_raw = dados[:quantidade] || vi.quantidade
        unless qtd_raw.is_a?(Integer) || (qtd_raw.is_a?(String) && qtd_raw =~ /\A\d+\z/)
          return failure("Item #{index + 1}: Quantidade deve ser um número inteiro", error_code: :invalid_quantity)
        end

        qtd_int = qtd_raw.to_i
        if qtd_int <= 0
          return failure("Item #{index + 1}: Quantidade deve ser maior que zero", error_code: :invalid_quantity)
        end

        qtd_ja_devolvida = DevolucaoItem.where(venda_item_id: vi.id).sum(:quantidade)
        saldo_disponivel = vi.quantidade - qtd_ja_devolvida

        if qtd_int > saldo_disponivel
          return failure(
            "Item #{index + 1}: Quantidade a devolver (#{qtd_int}) excede a quantidade disponível (#{saldo_disponivel})",
            error_code: :quantity_exceeds_available
          )
        end

        retornar_estoque = if dados.key?(:retornou_ao_estoque)
                             ActiveModel::Type::Boolean.new.cast(dados[:retornou_ao_estoque])
        else
                             @tipo != "defeito_avaria"
        end

        @valor_estornado_calculado += (vi.valor_unitario.to_d * qtd_int).round(2)

        @itens_processados << {
          venda_item: vi,
          quantidade: qtd_int,
          retornou_ao_estoque: retornar_estoque
        }
      end

      nil
    end

    def resolver_venda_item(param)
      return param if param.is_a?(VendaItem)
      return nil if param.blank?

      id = param.is_a?(Hash) ? param[:id] || param["id"] : param
      @venda.itens.find_by(id: id)
    end

    def validar_valor_estornado
      total_ja_estornado = @venda.devolucoes.sum(:valor_estornado)
      saldo_estornavel = [ @venda.valor_total - total_ja_estornado, BigDecimal("0.0") ].max

      if saldo_estornavel.zero?
        return failure("O valor total desta venda já foi integralmente estornado em devoluções anteriores", error_code: :sale_already_fully_refunded)
      end

      if @valor_estornado_param.present?
        num = parse_decimal(@valor_estornado_param)
        if num.nil? || num < 0
          return failure("Valor estornado inválido", error_code: :invalid_refund_amount)
        end

        if num > saldo_estornavel
          return failure(
            "Valor a estornar (R$ #{'%.2f' % num}) excede o saldo disponível para estorno desta venda (R$ #{'%.2f' % saldo_estornavel})",
            error_code: :refund_amount_exceeds_available
          )
        end

        @valor_estornado_final = num.round(2)
      else
        @valor_estornado_final = [ @valor_estornado_calculado, saldo_estornavel ].min.round(2)
      end

      nil
    end

    def executar_devolucao
      devolucao = nil

      ActiveRecord::Base.transaction do
        devolucao = Devolucao.create!(
          empresa: @venda.empresa,
          venda: @venda,
          tipo: @tipo,
          motivo: @motivo,
          valor_estornado: @valor_estornado_final,
          data_devolucao: @data_devolucao
        )

        @itens_processados.each do |item_info|
          devolucao.itens.create!(
            venda_item: item_info[:venda_item],
            quantidade: item_info[:quantidade],
            retornou_ao_estoque: item_info[:retornou_ao_estoque]
          )

          if item_info[:retornou_ao_estoque]
            mov_res = Estoques::MovimentarService.call(
              empresa: @venda.empresa,
              variacao_produto: item_info[:venda_item].variacao_produto,
              tipo: "estorno_devolucao",
              quantidade: item_info[:quantidade],
              usuario: @usuario,
              origem: devolucao,
              motivo: "Devolução da venda #{@venda.codigo_pedido}: #{@motivo || @tipo}"
            )

            if mov_res.failure?
              @erro_estoque = mov_res
              raise ActiveRecord::Rollback
            end
          end
        end
      end

      if @erro_estoque.present?
        return failure(@erro_estoque.error, error_code: @erro_estoque.error_code)
      end

      unless devolucao&.persisted?
        return failure("Erro ao processar devolução", error_code: :execution_failed)
      end

      success(
        devolucao: devolucao,
        itens: devolucao.itens.to_a,
        valor_estornado: devolucao.valor_estornado,
        tipo: devolucao.tipo
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  SalvarService = ProcessarService
  CriarService = ProcessarService
end
