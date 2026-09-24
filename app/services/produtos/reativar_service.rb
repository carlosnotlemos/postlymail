# frozen_string_literal: true

module Produtos
  class ReativarService < ApplicationService
    def initialize(
      empresa_ou_produto = nil,
      produto_param = nil,
      empresa: nil,
      produto: nil,
      motivo: nil,
      ignorar_se_ativo: false,
      reativar_variacoes: false,
      ativar_variacoes: nil,
      permitir_categoria_inativa: false,
      desvincular_categoria_inativa: false,
      ignorar_limite: false,
      **kwargs
    )
      dados = kwargs.dup
      dados[:empresa] = empresa if empresa.present?
      dados[:produto] = produto if produto.present?

      if empresa_ou_produto.is_a?(Produto)
        dados[:produto] ||= empresa_ou_produto
      elsif empresa_ou_produto.present? && !dados.key?(:empresa)
        dados[:empresa] = empresa_ou_produto
      end

      if produto_param.present? && !dados.key?(:produto)
        dados[:produto] = produto_param
      end

      @empresa_param = dados[:empresa]
      @produto_param = dados[:produto] || dados[:produto_id] || dados[:id]

      @empresa = resolver_empresa(@empresa_param)
      @produto = resolver_produto(@produto_param)
      @empresa ||= @produto&.empresa if @empresa_param.blank?

      @motivo = motivo || dados[:motivo]
      @ignorar_se_ativo = ignorar_se_ativo || dados[:ignorar_se_ativo] || false
      @permitir_categoria_inativa = permitir_categoria_inativa || dados[:permitir_categoria_inativa] || false
      @desvincular_categoria_inativa = desvincular_categoria_inativa || dados[:desvincular_categoria_inativa] || false
      @ignorar_limite = ignorar_limite || dados[:ignorar_limite] || false

      @reativar_variacoes = if !ativar_variacoes.nil?
                              ativar_variacoes
      elsif dados.key?(:ativar_variacoes)
                              dados[:ativar_variacoes]
      elsif !reativar_variacoes.nil?
                              reativar_variacoes
      elsif dados.key?(:reativar_variacoes)
                              dados[:reativar_variacoes]
      else
                              false
      end
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @produto.ativo? && @ignorar_se_ativo
        return success(
          produto: @produto,
          reativado: false,
          motivo: @motivo,
          ja_estava_ativo: true,
          variacoes_reativadas: 0
        )
      end

      executar_reativacao
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

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_produto = validar_produto
      return validacao_produto if validacao_produto&.failure?

      validacao_status = validar_status
      return validacao_status if validacao_status&.failure?

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

      return failure("Produto não informado ou não encontrado", error_code: :product_not_found) if @produto.nil?

      if @produto.empresa_id != @empresa.id
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

    def validar_status
      if @produto.ativo? && !@ignorar_se_ativo
        return failure("Produto já se encontra ativo", error_code: :product_already_active)
      end

      nil
    end

    def validar_categoria
      categoria = @produto.produto_categoria
      return nil if categoria.nil?
      return nil if categoria.ativo?
      return nil if @permitir_categoria_inativa || @desvincular_categoria_inativa

      failure("A categoria do produto encontra-se inativa", error_code: :category_inactive)
    end

    def validar_limite_produtos
      return nil if @ignorar_limite

      assinatura = @empresa.assinatura_ativa
      return nil if assinatura.nil?

      plano = assinatura.plano
      return nil if plano.nil? || plano.ilimitado_produtos?

      # Produtos ativos na empresa (o produto a ser reativado ainda é inativo)
      total_ativos = @empresa.produtos.where(ativo: true).count
      if total_ativos >= plano.limite_produtos
        return failure(
          "Limite de produtos ativos atingido para o plano contratado (#{plano.limite_produtos})",
          error_code: :plan_product_limit_reached
        )
      end

      nil
    end

    def executar_reativacao
      variacoes_afetadas = 0

      ActiveRecord::Base.transaction do
        @produto.ativo = true

        if @desvincular_categoria_inativa && @produto.produto_categoria.present? && !@produto.produto_categoria.ativo?
          @produto.produto_categoria = nil
        end

        @produto.save!

        if @reativar_variacoes
          variacoes_afetadas = @produto.variacoes.where(ativo: false).update_all(ativo: true, updated_at: Time.current)
        end
      end

      @produto.reload
      success(
        produto: @produto,
        reativado: true,
        motivo: @motivo,
        variacoes_reativadas: variacoes_afetadas
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  AtivarService = ReativarService
end
