module ProdutoCategorias
  class ExcluirService < ApplicationService
    def initialize(
      empresa: nil,
      categoria: nil,
      desvincular_produtos: false,
      forcar: false
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @categoria_param = categoria
      @categoria = resolver_categoria(categoria)

      @desvincular_produtos = desvincular_produtos || forcar
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

    def resolver_categoria(param)
      return param if param.is_a?(ProdutoCategoria)
      return nil if param.blank? || @empresa.nil?

      @empresa.produto_categorias.find_by(id: param)
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_categoria = validar_categoria
      return validacao_categoria if validacao_categoria&.failure?

      validar_produtos_vinculados
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

    def validar_produtos_vinculados
      unless @desvincular_produtos
        if @categoria.produtos.exists?
          return failure("Categoria possui produtos vinculados e não pode ser excluída", error_code: :category_has_associated_products)
        end
      end

      nil
    end

    def executar_exclusao
      categoria_id = @categoria.id
      categoria_nome = @categoria.nome
      produtos_desvinculados = 0

      ActiveRecord::Base.transaction do
        if @desvincular_produtos && @categoria.produtos.exists?
          produtos_desvinculados = @categoria.produtos.update_all(produto_categoria_id: nil)
        end

        @categoria.destroy!
      end

      success(
        categoria_id: categoria_id,
        categoria_nome: categoria_nome,
        removido: true,
        produtos_desvinculados: produtos_desvinculados
      )
    rescue ActiveRecord::RecordNotDestroyed => e
      failure("Erro ao excluir categoria: #{e.record.errors.full_messages.join(', ')}", error_code: :record_not_destroyed)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
