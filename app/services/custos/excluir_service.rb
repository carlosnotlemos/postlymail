module Custos
  class ExcluirService < ApplicationService
    def initialize(
      empresa: nil,
      custo: nil,
      desvincular_venda: false,
      forcar: false
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @custo_param = custo
      @custo = resolver_custo(custo)

      @desvincular_venda = desvincular_venda
      @forcar = forcar
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_exclusao
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

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_custo = validar_custo
      return validacao_custo if validacao_custo&.failure?

      validar_venda_vinculada
    end

    def validar_custo
      if @custo.nil? && @custo_param.present?
        if custo_existe_em_outro_tenant?
          return failure("Custo não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Custo não informado ou não encontrado", error_code: :cost_not_found)
      end

      return failure("Custo não informado ou não encontrado", error_code: :cost_not_found) if @custo.nil?

      if @custo.empresa_id != @empresa.id
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

    def validar_venda_vinculada
      return nil if @forcar || @desvincular_venda
      return nil if @custo.venda_id.blank?

      codigo = @custo.venda&.codigo_pedido || "ID #{@custo.venda_id}"
      failure(
        "Custo está vinculado à venda '#{codigo}' e não pode ser excluído diretamente",
        error_code: :cost_has_associated_sale,
        data: {
          venda_id: @custo.venda_id,
          codigo_pedido: @custo.venda&.codigo_pedido
        }
      )
    end

    def executar_exclusao
      if @desvincular_venda && !@forcar
        return executar_desvinculacao
      end

      custo_id = @custo.id
      valor = @custo.valor
      categoria = @custo.categoria
      venda_id = @custo.venda_id

      ActiveRecord::Base.transaction do
        @custo.destroy!
      end

      success(
        custo_id: custo_id,
        valor: valor,
        categoria: categoria,
        venda_id: venda_id,
        removido: true,
        forcado: @forcar
      )
    rescue ActiveRecord::RecordNotDestroyed => e
      failure("Erro ao excluir custo: #{e.record.errors.full_messages.join(', ')}", error_code: :record_not_destroyed)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end

    def executar_desvinculacao
      ActiveRecord::Base.transaction do
        @custo.venda = nil
        @custo.save!
      end

      success(
        custo: @custo,
        custo_id: @custo.id,
        valor: @custo.valor,
        categoria: @custo.categoria,
        removido: false,
        venda_desvinculada: true
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro ao desvincular venda do custo: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado ao desvincular venda: #{e.message}", error_code: :unexpected_error)
    end
  end

  RemoverService = ExcluirService
  DeletarService = ExcluirService
end
