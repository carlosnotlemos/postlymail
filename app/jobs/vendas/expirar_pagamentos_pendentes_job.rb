# frozen_string_literal: true

module Vendas
  class ExpirarPagamentosPendentesJob < ApplicationJob
    queue_as :default

    # Prazos padrão de tolerância por método de pagamento
    PRAZO_CHECKOUT_ABANDONADO = 2.hours
    PRAZO_PIX = 24.hours
    PRAZO_CARTAO = 2.hours
    MARGEM_COMPENSACAO_BOLETO = 3.days
    PRAZO_PADRAO_VENCIMENTO_BOLETO = 3.days

    def perform
      Venda.pendente.includes(:pagamentos).find_each do |venda|
        # Não cancela pedidos que possuam pagamentos já aprovados
        next if venda.pagamentos.any?(&:aprovado?)

        if expirada?(venda)
          motivo = motivo_expiracao(venda)
          Vendas::CancelarVendaService.call(
            venda: venda,
            motivo: motivo,
            estornar_estoque: true
          )
          Rails.logger.info("[Vendas] Pedido ##{venda.codigo_pedido} cancelado por expiração: #{motivo}")
        end
      end
    end

    private

    def expirada?(venda)
      pagamentos = venda.pagamentos.to_a

      # Cenário 1: Checkout abandonado sem nenhuma tentativa de pagamento registrada
      if pagamentos.empty?
        return venda.created_at <= PRAZO_CHECKOUT_ABANDONADO.ago
      end

      # Cenário 2: Possui pagamentos registrados.
      # O pedido só expira se TODOS os pagamentos pendentes estiverem estritamente expirados.
      # Se houver pelo menos um pagamento válido (ex: boleto dentro do prazo de compensação), NÃO expira.
      pagamentos_pendentes = pagamentos.select(&:pendente?)
      return false if pagamentos_pendentes.empty?

      pagamentos_pendentes.all? { |pagamento| pagamento_expirado?(pagamento) }
    end

    def pagamento_expirado?(pagamento)
      case pagamento.forma_pagamento.to_sym
      when :boleto
        # Vencimento do boleto + margem legal de compensação bancária (3 dias)
        data_vencimento = extrair_vencimento_boleto(pagamento)
        limite_compensacao = data_vencimento + MARGEM_COMPENSACAO_BOLETO
        Time.current > limite_compensacao

      when :pix
        # Pix: prazo padrão de 24 horas ou expiração explícita nos metadados
        data_expiracao = extrair_expiracao_pix(pagamento)
        Time.current > data_expiracao

      when :cartao_credito, :cartao_debito
        pagamento.created_at <= PRAZO_CARTAO.ago

      else
        pagamento.created_at <= PRAZO_PIX.ago
      end
    end

    def extrair_vencimento_boleto(pagamento)
      metadados = pagamento.metadados || {}
      raw_vencimento = metadados["data_vencimento"] || metadados["vencimento"] || metadados["dueDate"]

      if raw_vencimento.present?
        Time.zone.parse(raw_vencimento.to_s) rescue (pagamento.created_at + PRAZO_PADRAO_VENCIMENTO_BOLETO)
      else
        pagamento.created_at + PRAZO_PADRAO_VENCIMENTO_BOLETO
      end
    end

    def extrair_expiracao_pix(pagamento)
      metadados = pagamento.metadados || {}
      raw_expiracao = metadados["expiracao"] || metadados["expirationDate"] || metadados["data_vencimento"]

      if raw_expiracao.present?
        Time.zone.parse(raw_expiracao.to_s) rescue (pagamento.created_at + PRAZO_PIX)
      else
        pagamento.created_at + PRAZO_PIX
      end
    end

    def motivo_expiracao(venda)
      if venda.pagamentos.empty?
        "Cancelamento automático: checkout abandonado após 2 horas sem pagamento"
      else
        "Cancelamento automático: prazo limite de pagamento e compensação bancária expirado"
      end
    end
  end
end
