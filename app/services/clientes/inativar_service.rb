module Clientes
  class InativarService < ApplicationService
    STATUS_VENDAS_EM_ANDAMENTO = %w[pendente paga enviada].freeze

    def initialize(
      empresa: nil,
      cliente: nil,
      motivo: nil,
      desativar_marketing: false,
      ignorar_se_inativo: false,
      permitir_com_vendas_em_andamento: true
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @cliente_param = cliente
      @cliente = resolver_cliente(cliente)

      @motivo = motivo
      @desativar_marketing = desativar_marketing
      @ignorar_se_inativo = ignorar_se_inativo
      @permitir_com_vendas_em_andamento = permitir_com_vendas_em_andamento
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if !@cliente.ativo? && @ignorar_se_inativo
        return success(
          cliente: @cliente,
          inativado: false,
          motivo: @motivo,
          ja_estava_inativo: true
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

    def resolver_cliente(param)
      return param if param.is_a?(Cliente)
      return nil if param.blank? || @empresa.nil?

      @empresa.clientes.find_by(id: param)
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cliente = validar_cliente
      return validacao_cliente if validacao_cliente&.failure?

      validar_status_e_regras
    end

    def validar_cliente
      if @cliente.nil? && @cliente_param.present?
        if @cliente_param.is_a?(Cliente) || Cliente.exists?(id: @cliente_param)
          return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Cliente não informado ou não encontrado", error_code: :client_not_found)
      end

      return failure("Cliente não informado ou não encontrado", error_code: :client_not_found) if @cliente.nil?

      if @cliente.empresa_id != @empresa.id
        return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_status_e_regras
      if !@cliente.ativo? && !@ignorar_se_inativo
        return failure("Cliente já se encontra inativo", error_code: :client_already_inactive)
      end

      unless @permitir_com_vendas_em_andamento
        if @cliente.vendas.where(status: STATUS_VENDAS_EM_ANDAMENTO).exists?
          return failure("Cliente possui vendas em andamento e não pode ser inativado", error_code: :client_has_pending_sales)
        end
      end

      nil
    end

    def executar_inativacao
      ActiveRecord::Base.transaction do
        @cliente.ativo = false
        @cliente.aceita_marketing = false if @desativar_marketing
        @cliente.save!
      end

      success(
        cliente: @cliente,
        inativado: true,
        motivo: @motivo,
        marketing_desativado: @desativar_marketing
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end
end
