module ProdutoCategorias
  class InativarService < ApplicationService
    def initialize(
      empresa: nil,
      categoria: nil,
      motivo: nil,
      ignorar_se_inativo: false,
      permitir_com_produtos_ativos: true,
      desvincular_produtos: false
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @categoria_param = categoria
      @categoria = resolver_categoria(categoria)

      @motivo = motivo
      @ignorar_se_inativo = ignorar_se_inativo
      @permitir_com_produtos_ativos = permitir_com_produtos_ativos
      @desvincular_produtos = desvincular_produtos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@categoria.ativo? && @ignorar_se_inativo
        return success(
          categoria: @categoria,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true,
          produtos_desvinculados: 0
        )
      end

      executar_inativacao
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

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_categoria = validar_categoria
      return validacao_categoria if validacao_categoria&.failure?

      validar_status_e_regras
    end

    def validar_categoria
      if @categoria.nil? && @categoria_param.present?
        if @categoria_param.is_a?(ProdutoCategoria) || ProdutoCategoria.exists?(id: @categoria_param)
          return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Categoria não informada ou não encontrada", error_code: :category_not_found)
      end

      return failure("Categoria não informada ou não encontrada", error_code: :category_not_found) if @categoria.nil?

      if @categoria.empresa_id != @empresa.id
        return failure("Categoria não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_status_e_regras
      if !@categoria.ativo? && !@ignorar_se_inativo
        return failure("Categoria já se encontra inativa", error_code: :category_already_inactive)
      end

      unless @permitir_com_produtos_ativos
        if @categoria.produtos.where(ativo: true).exists?
          return failure("Categoria possui produtos ativos vinculados e não pode ser inativada", error_code: :category_has_active_products)
        end
      end

      nil
    end

    def executar_inativacao
      produtos_afetados = 0

      ActiveRecord::Base.transaction do
        @categoria.ativo = false
        @categoria.save!

        if @desvincular_produtos
          produtos_afetados = @categoria.produtos.update_all(produto_categoria_id: nil)
        end
      end

      success(
        categoria: @categoria,
        inativado: true,
        motivo: @motivo,
        produtos_desvinculados: produtos_afetados
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
