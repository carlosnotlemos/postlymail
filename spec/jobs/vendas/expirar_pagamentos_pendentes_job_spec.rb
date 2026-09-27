# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendas::ExpirarPagamentosPendentesJob, type: :job do
  let!(:empresa) { create(:empresa, slug: 'loja-expiracao-job', ativo: true) }
  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:produto) { create(:produto, empresa: empresa) }
  let!(:variacao) { create(:variacao_produto, produto: produto, empresa: empresa) }
  let!(:estoque) { create(:estoque, variacao_produto: variacao, quantidade: 10) }

  describe '#perform' do
    it 'está configurado na fila default' do
      expect(described_class.new.queue_name).to eq('default')
    end

    context 'checkout abandonado (sem nenhum pagamento criado)' do
      it 'cancela o pedido após 2 horas sem pagamento e devolve ao estoque' do
        venda_abandonada = create(
          :venda,
          empresa: empresa,
          cliente: cliente,
          status: :pendente,
          created_at: 3.hours.ago
        )
        create(:venda_item, venda: venda_abandonada, variacao_produto: variacao, quantidade: 2)

        venda_recente = create(
          :venda,
          empresa: empresa,
          cliente: cliente,
          status: :pendente,
          created_at: 1.hour.ago
        )
        create(:venda_item, venda: venda_recente, variacao_produto: variacao, quantidade: 1)

        expect {
          described_class.perform_now
        }.to change { estoque.reload.quantidade }.by(2)

        expect(venda_abandonada.reload.cancelada?).to be true
        expect(venda_abandonada.motivo_cancelamento).to include('checkout abandonado')

        expect(venda_recente.reload.pendente?).to be true
      end
    end

    context 'pagamento via Pix' do
      it 'cancela pedido com Pix pendente criado há mais de 24 horas' do
        venda_pix_antiga = create(:venda, empresa: empresa, cliente: cliente, status: :pendente, created_at: 26.hours.ago)
        create(:venda_item, venda: venda_pix_antiga, variacao_produto: variacao, quantidade: 1)
        create(:venda_pagamento, venda: venda_pix_antiga, forma_pagamento: :pix, status: :pendente, created_at: 26.hours.ago)

        venda_pix_recente = create(:venda, empresa: empresa, cliente: cliente, status: :pendente, created_at: 5.hours.ago)
        create(:venda_item, venda: venda_pix_recente, variacao_produto: variacao, quantidade: 1)
        create(:venda_pagamento, venda: venda_pix_recente, forma_pagamento: :pix, status: :pendente, created_at: 5.hours.ago)

        described_class.perform_now

        expect(venda_pix_antiga.reload.cancelada?).to be true
        expect(venda_pix_recente.reload.pendente?).to be true
      end
    end

    context 'pagamento via Boleto Bancário (respeito à margem de compensação)' do
      it 'não cancela boleto vencido há 1 dia que ainda está dentro da margem de compensação de 3 dias' do
        venda_boleto = create(:venda, empresa: empresa, cliente: cliente, status: :pendente, created_at: 4.days.ago)
        create(:venda_item, venda: venda_boleto, variacao_produto: variacao, quantidade: 1)
        create(
          :venda_pagamento,
          venda: venda_boleto,
          forma_pagamento: :boleto,
          status: :pendente,
          metadados: { "data_vencimento" => 1.day.ago.to_date.iso8601 }
        )

        described_class.perform_now

        expect(venda_boleto.reload.pendente?).to be true
      end

      it 'cancela boleto quando o vencimento somado à margem de 3 dias é ultrapassado' do
        venda_boleto_expirada = create(:venda, empresa: empresa, cliente: cliente, status: :pendente, created_at: 8.days.ago)
        create(:venda_item, venda: venda_boleto_expirada, variacao_produto: variacao, quantidade: 1)
        create(
          :venda_pagamento,
          venda: venda_boleto_expirada,
          forma_pagamento: :boleto,
          status: :pendente,
          metadados: { "data_vencimento" => 4.days.ago.to_date.iso8601 }
        )

        described_class.perform_now

        expect(venda_boleto_expirada.reload.cancelada?).to be true
      end
    end

    context 'proteção multimétodos (ex: Pix expirado + Boleto em compensação)' do
      it 'não cancela pedido se houver pelo menos um pagamento pendente ainda válido' do
        venda_mista = create(:venda, empresa: empresa, cliente: cliente, status: :pendente, created_at: 2.days.ago)
        create(:venda_item, venda: venda_mista, variacao_produto: variacao, quantidade: 1)
        # Pix expirado
        create(:venda_pagamento, venda: venda_mista, forma_pagamento: :pix, status: :pendente, created_at: 30.hours.ago)
        # Boleto com vencimento ainda em compensação
        create(
          :venda_pagamento,
          venda: venda_mista,
          forma_pagamento: :boleto,
          status: :pendente,
          metadados: { "data_vencimento" => 1.day.ago.to_date.iso8601 }
        )

        described_class.perform_now

        expect(venda_mista.reload.pendente?).to be true
      end
    end
  end
end
