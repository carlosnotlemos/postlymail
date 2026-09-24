# frozen_string_literal: true

module Produtos
  class InativarService < ApplicationService
    def initialize(
      empresa_ou_produto = nil,
      produto_param = nil,
      empresa: nil,
      produto: nil,
      motivo: nil,
      ignorar_se_inativo: false,
      inativar_variacoes: true,
      desativar_variacoes: nil,
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
      @ignorar_se_inativo = ignorar_se_inativo || dados[:ignorar_se_inativo] || false

      # Flag de inativação em cascata das variações
      @inativar_variacoes = if !desativar_variacoes.nil?
                              desativar_variacoes
      elsif dados.key?(:desativar_variacoes)
                              dados[:desativar_variacoes]
      elsif !inativar_variacoes.nil?
                              inativar_variacoes
      else
                              true
      end
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@produto.ativo? && @ignorar_se_inativo
        return success(
          produto: @produto,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true,
          variacoes_inativadas: 0
        )
      end

      executar_inativacao
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

      validar_status_e_regras
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

    def validar_status_e_regras
      if !@produto.ativo? && !@ignorar_se_inativo
        return failure("Produto já se encontra inativo", error_code: :product_already_inactive)
      end

      nil
    end

    def executar_inativacao
      variacoes_afetadas = 0

      ActiveRecord::Base.transaction do
        @produto.ativo = false
        @produto.save!

        if @inativar_variacoes
          variacoes_afetadas = @produto.variacoes.where(ativo: true).update_all(ativo: false, updated_at: Time.current)
        end
      end

      @produto.reload
      success(
        produto: @produto,
        inativado: true,
        motivo: @motivo,
        variacoes_inativadas: variacoes_afetadas
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  DesativarService = InativarService
end
