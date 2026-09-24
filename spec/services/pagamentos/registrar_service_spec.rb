# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pagamentos::RegistrarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-geek') }
  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:usuario) { create(:usuario, email: 'atendente@empresa.com') }
  let!(:membro) do
    create(:membro, empresa: empresa, usuario: usuario, papel: :atendente, ativo: true)
  end

  let!(:produto) { create(:produto, empresa: empresa) }
  let!(:variacao) do
    create(:variacao_produto, empresa: empresa, produto: produto, preco_base: 100.0, ativo: true)
  end
  let!(:estoque) { create(:estoque, variacao_produto: variacao, quantidade: 20) }

  let!(:venda) do
    res = Vendas::FecharVendaService.call(
      empresa: empresa,
      cliente: cliente,
      usuario: usuario,
      tipo_entrega: :retirada,
      itens: [ { variacao_produto: variacao, quantidade: 2 } ] # valor_total = 200.00
    )
    res.data[:venda]
  end

  describe '.call' do
    context 'registro de pagamento único com sucesso' do
      it 'registra pagamento total e atualiza status da venda para paga' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :pix,
          gateway: :asaas,
          gateway_id: 'pay_123456',
          valor: 200.00,
          taxa_operadora: 2.50,
          status: :aprovado,
          metadados: { 'qr_code' => 'payload_pix' }
        )

        expect(resultado).to be_success
        expect(resultado.data[:venda_paga]).to be true
        expect(resultado.data[:total_pago]).to eq(200.00)
        expect(resultado.data[:saldo_restante]).to eq(0.0)

        pag = resultado.data[:pagamento]
        expect(pag).to be_persisted
        expect(pag.pix?).to be true
        expect(pag.asaas?).to be true
        expect(pag.gateway_id).to eq('pay_123456')
        expect(pag.valor).to eq(200.00)
        expect(pag.taxa_operadora).to eq(2.50)
        expect(pag.valor_liquido).to eq(197.50)
        expect(pag.data_liquidacao).to be_present
        expect(pag.metadados['qr_code']).to eq('payload_pix')

        expect(venda.reload.paga?).to be true
      end

      it 'assume o saldo restante da venda se o valor for omitido' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :dinheiro
        )

        expect(resultado).to be_success
        pag = resultado.data[:pagamento]
        expect(pag.valor).to eq(200.00)
        expect(venda.reload.paga?).to be true
      end
    end

    context 'pagamentos parciais e complementares' do
      it 'mantém venda pendente se o pagamento for parcial' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :pix,
          valor: 120.00
        )

        expect(resultado).to be_success
        expect(resultado.data[:venda_paga]).to be false
        expect(resultado.data[:total_pago]).to eq(120.00)
        expect(resultado.data[:saldo_restante]).to eq(80.00)
        expect(venda.reload.pendente?).to be true
      end

      it 'atualiza venda para paga quando um segundo pagamento cobre o saldo' do
        # Primeiro pagamento parcial
        described_class.call(
          venda: venda,
          forma_pagamento: :pix,
          valor: 120.00
        )
        expect(venda.reload.pendente?).to be true

        # Segundo pagamento cobrindo o restante
        resultado2 = described_class.call(
          venda: venda,
          forma_pagamento: :dinheiro,
          valor: 80.00
        )

        expect(resultado2).to be_success
        expect(resultado2.data[:venda_paga]).to be true
        expect(resultado2.data[:total_pago]).to eq(200.00)
        expect(resultado2.data[:saldo_restante]).to eq(0.0)
        expect(venda.reload.paga?).to be true
      end
    end

    context 'registro de pagamentos em lote / divididos' do
      it 'cria múltiplos pagamentos e quita a venda' do
        resultado = described_class.call(
          venda: venda,
          pagamentos: [
            { forma_pagamento: :pix, valor: 150.00, gateway: :asaas },
            { forma_pagamento: :dinheiro, valor: 50.00, gateway: :manual }
          ]
        )

        expect(resultado).to be_success
        expect(resultado.data[:pagamentos].size).to eq(2)
        expect(resultado.data[:venda_paga]).to be true
        expect(venda.reload.paga?).to be true
      end
    end

    context 'com status pendente ou recusado' do
      it 'não quita a venda quando o pagamento fica com status pendente' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :boleto,
          valor: 200.00,
          status: :pendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:venda_paga]).to be false
        expect(resultado.data[:pagamento].pendente?).to be true
        expect(venda.reload.pendente?).to be true
      end

      it 'não soma pagamento recusado ao total pago' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :cartao_credito,
          valor: 200.00,
          status: :recusado
        )

        expect(resultado).to be_success
        expect(resultado.data[:venda_paga]).to be false
        expect(resultado.data[:total_pago]).to eq(0.0)
        expect(venda.reload.pendente?).to be true
      end
    end

    context 'validações de erro e salvaguardas' do
      it 'falha quando a venda não é informada ou não encontrada' do
        resultado = described_class.call(
          venda: 999999,
          forma_pagamento: :pix
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:sale_not_found)
      end

      it 'falha quando a venda pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          empresa: outra_empresa,
          venda: venda,
          forma_pagamento: :pix
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a venda já está cancelada' do
        Vendas::CancelarVendaService.call(venda: venda, motivo: 'Cancelada')

        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :pix
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:sale_already_cancelled)
      end

      it 'falha quando a forma de pagamento é inválida' do
        resultado = described_class.call(
          venda: venda,
          forma_pagamento: :escambo_de_camelos
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_payment_method)
      end

      it 'falha quando o gateway é inválido' do
        resultado = described_class.call(
          venda: venda,
          gateway: :gateway_fantasma
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_gateway)
      end

      it 'falha quando o valor é negativo' do
        resultado = described_class.call(
          venda: venda,
          valor: -50.00
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_payment_amount)
      end

      it 'falha quando a taxa é negativa' do
        resultado = described_class.call(
          venda: venda,
          taxa_operadora: -10.00
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_fee)
      end
    end

    context 'aliases do serviço' do
      it 'funciona com SalvarService, CriarService e Vendas::RegistrarPagamentoService' do
        r1 = Pagamentos::SalvarService.call(venda: venda, valor: 10.0, forma_pagamento: :pix)
        r2 = Pagamentos::CriarService.call(venda: venda, valor: 20.0, forma_pagamento: :pix)
        r3 = Vendas::RegistrarPagamentoService.call(venda: venda, valor: 30.0, forma_pagamento: :pix)

        expect(r1).to be_success
        expect(r2).to be_success
        expect(r3).to be_success
      end
    end
  end
end
