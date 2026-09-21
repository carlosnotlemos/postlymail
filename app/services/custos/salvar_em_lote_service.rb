module Custos
  class SalvarEmLoteService < ApplicationService
    def initialize(
      empresa: nil,
      venda: nil,
      custos: []
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @venda_param = venda
      @venda = resolver_venda(venda)

      @custos_param = custos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento_em_lote
    end

    private

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      Empresa.find_by(id: param)
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

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_venda = validar_venda
      return validacao_venda if validacao_venda&.failure?

      validar_lista_custos
    end

    def validar_venda
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

    def validar_lista_custos
      unless @custos_param.is_a?(Array)
        return failure("O parâmetro 'custos' deve ser uma lista (Array)", error_code: :invalid_batch_format)
      end

      if @custos_param.empty?
        return failure("A lista de custos não pode estar vazia", error_code: :empty_batch)
      end

      nil
    end

    def executar_salvamento_em_lote
      custos_salvos = []
      erro_item = nil

      ActiveRecord::Base.transaction do
        @custos_param.each_with_index do |attrs, index|
          atributos_custo = attrs.is_a?(Hash) ? attrs.symbolize_keys : {}
          venda_do_item = atributos_custo.delete(:venda) || atributos_custo.delete(:venda_id) || @venda

          resultado = SalvarService.call(
            empresa: @empresa,
            venda: venda_do_item,
            atributos: atributos_custo
          )

          if resultado.failure?
            erro_item = {
              index: index,
              resultado: resultado
            }
            raise ActiveRecord::Rollback
          end

          custos_salvos << resultado.data[:custo]
        end
      end

      if erro_item
        return failure(
          "Erro no lançamento #{erro_item[:index] + 1}: #{erro_item[:resultado].error}",
          error_code: erro_item[:resultado].error_code,
          data: { item_index: erro_item[:index], erro_original: erro_item[:resultado].error }
        )
      end

      total_valor = custos_salvos.sum(&:valor)

      success(
        custos: custos_salvos,
        quantidade: custos_salvos.size,
        valor_total: total_valor
      )
    rescue StandardError => e
      failure("Erro inesperado ao salvar lote de custos: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarLoteService = SalvarEmLoteService
  RegistrarLoteService = SalvarEmLoteService
end
