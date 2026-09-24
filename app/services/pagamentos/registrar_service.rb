# frozen_string_literal: true

module Pagamentos
  class RegistrarService < ApplicationService
    def initialize(
      venda_ou_hash = nil,
      pagamento_ou_atributos = nil,
      venda: nil,
      empresa: nil,
      pagamento: nil,
      pagamentos: nil,
      forma_pagamento: nil,
      gateway: nil,
      gateway_id: nil,
      valor: nil,
      taxa_operadora: nil,
      parcelas: nil,
      status: nil,
      data_liquidacao: nil,
      metadados: nil,
      atualizar_status_venda: true,
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

      if pagamento_ou_atributos.is_a?(Hash)
        dados.merge!(pagamento_ou_atributos.symbolize_keys)
      elsif pagamento_ou_atributos.present? && !dados.key?(:pagamento)
        dados[:pagamento] = pagamento_ou_atributos
      end

      dados[:venda] = venda if venda.present?
      dados[:empresa] = empresa if empresa.present?
      dados[:pagamento] = pagamento if pagamento.present?
      dados[:pagamentos] = pagamentos if pagamentos.present?
      dados[:forma_pagamento] = forma_pagamento if forma_pagamento.present?
      dados[:gateway] = gateway if gateway.present?
      dados[:gateway_id] = gateway_id if gateway_id.present?
      dados[:valor] = valor unless valor.nil?
      dados[:taxa_operadora] = taxa_operadora unless taxa_operadora.nil?
      dados[:parcelas] = parcelas unless parcelas.nil?
      dados[:status] = status if status.present?
      dados[:data_liquidacao] = data_liquidacao if data_liquidacao.present?
      dados[:metadados] = metadados if metadados.present?
      dados[:atualizar_status_venda] = atualizar_status_venda unless atualizar_status_venda.nil?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @venda_param = dados[:venda] || dados[:venda_id] || dados[:codigo_pedido]
      @venda = resolver_venda(@venda_param)

      @pagamento_param = dados[:pagamento]
      @pagamentos_param = dados[:pagamentos]
      @dados_avulsos = dados

      @atualizar_status_venda = dados.key?(:atualizar_status_venda) ? dados[:atualizar_status_venda] : true
      @pagamentos_processados = []
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_registro
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

    def normalizar_forma_pagamento(param)
      return nil if param.blank?

      if param.is_a?(Integer)
        return VendaPagamento.forma_pagamentos.key(param)
      end

      param_str = param.to_s.strip.underscore
      VendaPagamento.forma_pagamentos.key?(param_str) ? param_str : nil
    end

    def normalizar_gateway(param)
      return :manual if param.blank?

      if param.is_a?(Integer)
        key = VendaPagamento.gateways.key(param)
        return key ? key.to_sym : nil
      end

      param_str = param.to_s.strip.underscore
      VendaPagamento.gateways.key?(param_str) ? param_str.to_sym : nil
    end

    def normalizar_status(param)
      return :aprovado if param.blank?

      if param.is_a?(Integer)
        key = VendaPagamento.statuses.key(param)
        return key ? key.to_sym : nil
      end

      param_str = param.to_s.strip.underscore
      VendaPagamento.statuses.key?(param_str) ? param_str.to_sym : nil
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
        if @venda_param.present? && @empresa.present?
          id_ou_cod = @venda_param.is_a?(Venda) ? @venda_param.id : @venda_param
          if Venda.where(id: id_ou_cod).or(Venda.where(codigo_pedido: id_ou_cod.to_s.strip.upcase)).exists?
            return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
        end
        return failure("Venda não informada ou não encontrada", error_code: :sale_not_found)
      end

      if @empresa.present? && @venda.empresa_id != @empresa.id
        return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @venda.cancelada?
        return failure("Não é permitido registrar pagamentos para uma venda cancelada", error_code: :sale_already_cancelled)
      end

      validacao_itens = processar_e_validar_pagamentos
      return validacao_itens if validacao_itens&.failure?

      nil
    end

    CHAVES_PAGAMENTO = %i[
      forma_pagamento gateway gateway_id valor taxa_operadora
      parcelas status data_liquidacao metadados
    ].freeze

    def montar_lista_pagamentos
      if @pagamentos_param.is_a?(Array) && @pagamentos_param.any?
        return @pagamentos_param
      end

      if @pagamento_param.present?
        return @pagamento_param.is_a?(Array) ? @pagamento_param : [ @pagamento_param ]
      end

      # Pagamento passado diretamente no payload raiz
      if @dados_avulsos.keys.any? { |k| CHAVES_PAGAMENTO.include?(k) }
        return [ @dados_avulsos ]
      end

      # Caso omitido, gera pagamento padrão no valor restante da venda
      [ {} ]
    end

    def processar_e_validar_pagamentos
      lista = montar_lista_pagamentos
      @pagamentos_processados = []

      total_aprovado_existente = @venda.pagamentos.where(status: :aprovado).sum(:valor)
      saldo_restante = [ @venda.valor_total - total_aprovado_existente, BigDecimal("0.0") ].max

      lista.each_with_index do |item_raw, index|
        dados = item_raw.is_a?(Hash) ? item_raw.symbolize_keys : {}

        forma_raw = dados[:forma_pagamento] || :pix
        forma = normalizar_forma_pagamento(forma_raw)
        if forma.nil?
          return failure("Pagamento #{index + 1}: Forma de pagamento inválida: #{forma_raw}", error_code: :invalid_payment_method)
        end

        gateway_raw = dados[:gateway] || :manual
        gateway = normalizar_gateway(gateway_raw)
        if gateway.nil?
          return failure("Pagamento #{index + 1}: Gateway de pagamento inválido: #{gateway_raw}", error_code: :invalid_gateway)
        end

        status_raw = dados[:status] || :aprovado
        status_pag = normalizar_status(status_raw)
        if status_pag.nil?
          return failure("Pagamento #{index + 1}: Status de pagamento inválido: #{status_raw}", error_code: :invalid_payment_status)
        end

        valor_num = if dados[:valor].present?
                      parse_decimal(dados[:valor])
        elsif lista.size == 1
                      saldo_restante
        else
                      BigDecimal("0.0")
        end

        if valor_num.nil? || valor_num < 0
          return failure("Pagamento #{index + 1}: Valor do pagamento inválido", error_code: :invalid_payment_amount)
        end

        taxa_num = parse_decimal(dados[:taxa_operadora] || 0.0)
        if taxa_num.nil? || taxa_num < 0
          return failure("Pagamento #{index + 1}: Taxa de operadora inválida", error_code: :invalid_fee)
        end

        parcelas_raw = dados[:parcelas] || 1
        parcelas_int = parcelas_raw.to_i
        if parcelas_int < 1
          return failure("Pagamento #{index + 1}: Parcelas deve ser maior ou igual a 1", error_code: :invalid_installments)
        end

        data_liq = dados[:data_liquidacao]
        data_liq = Time.current if data_liq.blank? && status_pag == :aprovado

        @pagamentos_processados << {
          forma_pagamento: forma,
          gateway: gateway,
          gateway_id: dados[:gateway_id],
          valor: valor_num.round(2),
          taxa_operadora: taxa_num.round(2),
          parcelas: parcelas_int,
          status: status_pag,
          data_liquidacao: data_liq,
          metadados: dados[:metadados] || {}
        }
      end

      nil
    end

    def executar_registro
      pagamentos_salvos = []

      ActiveRecord::Base.transaction do
        @pagamentos_processados.each do |item_attrs|
          pag = @venda.pagamentos.create!(item_attrs)
          pagamentos_salvos << pag
        end

        if @atualizar_status_venda
          total_aprovado = @venda.pagamentos.where(status: :aprovado).sum(:valor)
          if @venda.pendente? && total_aprovado >= @venda.valor_total
            @venda.update!(status: :paga)
          end
        end
      end

      total_aprovado_atual = @venda.pagamentos.where(status: :aprovado).sum(:valor)
      saldo_restante = [ @venda.valor_total - total_aprovado_atual, BigDecimal("0.0") ].max

      success(
        venda: @venda,
        pagamentos: pagamentos_salvos,
        pagamento: pagamentos_salvos.first,
        total_pago: total_aprovado_atual,
        saldo_restante: saldo_restante,
        venda_paga: @venda.paga?
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  SalvarService = RegistrarService
  CriarService = RegistrarService
end

module Vendas
  RegistrarPagamentoService = Pagamentos::RegistrarService
end
