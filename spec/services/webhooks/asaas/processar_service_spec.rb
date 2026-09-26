# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Asaas::ProcessarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-asaas', ativo: true) }
  let!(:plano) { create(:plano, nome: 'Pro', identificador: 1, valor_mensal: 99.0) }
  let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano, status: :atrasada, valor: 99.0, ciclo: :mensal, data_fim: Date.current) }
  let!(:fatura) do
    create(
      :assinatura_fatura,
      assinatura: assinatura,
      gateway_id: 'pay_asaas_fatura_123',
      valor: 99.0,
      status: :pendente,
      data_vencimento: Date.current
    )
  end

  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:venda) do
    create(
      :venda,
      empresa: empresa,
      cliente: cliente,
      status: :pendente,
      codigo_pedido: 'PED-999',
      valor_total: 150.00
    )
  end
  let!(:venda_pagamento) do
    create(
      :venda_pagamento,
      venda: venda,
      gateway: :asaas,
      gateway_id: 'pay_asaas_venda_456',
      valor: 150.00,
      status: :pendente
    )
  end

  describe '.call para Faturas de Assinatura' do
    context 'quando recebe PAYMENT_RECEIVED ou PAYMENT_CONFIRMED' do
      let(:payload) do
        {
          'event' => 'PAYMENT_RECEIVED',
          'payment' => {
            'id' => 'pay_asaas_fatura_123',
            'value' => 99.0,
            'netValue' => 97.0,
            'billingType' => 'PIX',
            'confirmedDate' => '2026-09-26'
          }
        }
      end

      it 'liquida a fatura e reativa a assinatura com vigência prorrogada' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:tipo_recurso]).to eq(:assinatura_fatura)
        expect(resultado.data[:acao]).to eq(:fatura_paga)

        fatura.reload
        expect(fatura.paga?).to be true
        expect(fatura.data_pagamento).to be_present

        assinatura.reload
        expect(assinatura.ativa?).to be true
        expect(assinatura.data_fim).to be > Date.current
      end
    end

    context 'quando recebe PAYMENT_DELETED' do
      let(:payload) do
        {
          'event' => 'PAYMENT_DELETED',
          'payment' => {
            'id' => 'pay_asaas_fatura_123'
          }
        }
      end

      it 'cancela a fatura pendente' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:fatura_cancelada)
        expect(fatura.reload.cancelada?).to be true
      end
    end

    context 'quando recebe PAYMENT_REFUNDED' do
      let(:payload) do
        {
          'event' => 'PAYMENT_REFUNDED',
          'payment' => {
            'id' => 'pay_asaas_fatura_123'
          }
        }
      end

      it 'atualiza o status da fatura para cancelada e registra metadados de estorno' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:fatura_estornada)
        expect(fatura.reload.cancelada?).to be true
        expect(fatura.metadados['evento_asaas']).to eq('PAYMENT_REFUNDED')
      end
    end
  end

  describe '.call para Pagamentos de Vendas' do
    context 'quando recebe PAYMENT_RECEIVED para venda existente com venda_pagamento' do
      let(:payload) do
        {
          'event' => 'PAYMENT_RECEIVED',
          'payment' => {
            'id' => 'pay_asaas_venda_456',
            'value' => 150.00,
            'netValue' => 145.00,
            'billingType' => 'PIX',
            'confirmedDate' => '2026-09-26'
          }
        }
      end

      it 'aprova o venda_pagamento e marca a venda como paga' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:tipo_recurso]).to eq(:venda)
        expect(resultado.data[:acao]).to eq(:pagamento_venda_aprovado)

        venda_pagamento.reload
        expect(venda_pagamento.aprovado?).to be true
        expect(venda_pagamento.taxa_operadora).to eq(5.00)
        expect(venda_pagamento.data_liquidacao).to be_present

        expect(venda.reload.paga?).to be true
      end
    end

    context 'quando recebe pagamento para venda localizada por externalReference (codigo_pedido)' do
      let(:payload) do
        {
          'event' => 'PAYMENT_CONFIRMED',
          'payment' => {
            'id' => 'pay_novo_avulso_789',
            'externalReference' => 'PED-999',
            'value' => 150.00,
            'netValue' => 146.50,
            'billingType' => 'CREDIT_CARD'
          }
        }
      end

      it 'cria o pagamento com gateway asaas e aprova a venda' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:tipo_recurso]).to eq(:venda)

        novo_pag = venda.pagamentos.find_by(gateway_id: 'pay_novo_avulso_789')
        expect(novo_pag).to be_present
        expect(novo_pag.aprovado?).to be true
        expect(novo_pag.cartao_credito?).to be true
        expect(venda.reload.paga?).to be true
      end
    end

    context 'quando cartão é recusado (PAYMENT_CREDIT_CARD_CAPTURE_REFUSED)' do
      let(:payload) do
        {
          'event' => 'PAYMENT_CREDIT_CARD_CAPTURE_REFUSED',
          'payment' => {
            'id' => 'pay_asaas_venda_456'
          }
        }
      end

      it 'atualiza o venda_pagamento para recusado' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:pagamento_venda_recusado)
        expect(venda_pagamento.reload.recusado?).to be true
      end
    end

    context 'quando pagamento da venda é estornado (PAYMENT_REFUNDED)' do
      let(:payload) do
        {
          'event' => 'PAYMENT_REFUNDED',
          'payment' => {
            'id' => 'pay_asaas_venda_456'
          }
        }
      end

      it 'atualiza o status para estornado' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:pagamento_venda_estornado)
        expect(venda_pagamento.reload.estornado?).to be true
      end
    end
  end

  describe 'recurso não encontrado' do
    let(:payload) do
      {
        'event' => 'PAYMENT_RECEIVED',
        'payment' => {
          'id' => 'pay_desconhecido_999'
        }
      }
    end

    it 'retorna sucesso indicando que o recurso não foi localizado no sistema' do
      resultado = described_class.call(payload: payload)

      expect(resultado).to be_success
      expect(resultado.data[:recurso_localizado]).to be false
    end
  end

  describe 'integração com Webhooks::ProcessarService' do
    it 'é invocado automaticamente pelo orquestrador geral' do
      webhook_log = create(
        :webhook_log,
        provedor: :asaas,
        payload: {
          'event' => 'PAYMENT_RECEIVED',
          'payment' => {
            'id' => 'pay_asaas_fatura_123',
            'value' => 99.0
          }
        }
      )

      resultado = Webhooks::ProcessarService.call(webhook_log: webhook_log)

      expect(resultado).to be_success
      expect(webhook_log.reload.processado?).to be true
      expect(fatura.reload.paga?).to be true
      expect(assinatura.reload.ativa?).to be true
    end
  end
end
