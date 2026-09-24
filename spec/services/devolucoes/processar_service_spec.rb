# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devolucoes::ProcessarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-geek') }
  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:usuario) { create(:usuario, email: 'atendente@empresa.com') }
  let!(:membro) do
    create(:membro, empresa: empresa, usuario: usuario, papel: :atendente, ativo: true)
  end

  let!(:produto) { create(:produto, empresa: empresa, nome: 'Camiseta Gamer') }
  let!(:variacao_m) do
    create(:variacao_produto, empresa: empresa, produto: produto, sku: 'CAM-M', preco_base: 80.0, ativo: true)
  end
  let!(:estoque_m) { create(:estoque, variacao_produto: variacao_m, quantidade: 20) }

  let!(:variacao_g) do
    create(:variacao_produto, empresa: empresa, produto: produto, sku: 'CAM-G', preco_base: 100.0, ativo: true)
  end
  let!(:estoque_g) { create(:estoque, variacao_produto: variacao_g, quantidade: 15) }

  # Cria venda com 2 itens:
  # Item 1: 3x variacao_m (3 * 80 = 240)
  # Item 2: 2x variacao_g (2 * 100 = 200)
  # Total: 440.00
  let!(:venda) do
    res = Vendas::FecharVendaService.call(
      empresa: empresa,
      cliente: cliente,
      usuario: usuario,
      tipo_entrega: :retirada,
      itens: [
        { variacao_produto: variacao_m, quantidade: 3 },
        { variacao_produto: variacao_g, quantidade: 2 }
      ]
    )
    res.data[:venda]
  end

  let(:item_m) { venda.itens.find_by(variacao_produto: variacao_m) }
  let(:item_g) { venda.itens.find_by(variacao_produto: variacao_g) }

  describe '.call' do
    context 'processamento de devolução com sucesso' do
      it 'processa devolução parcial e reintegra itens ao estoque' do
        # Estoque M após a venda: 20 - 3 = 17
        expect(estoque_m.reload.quantidade).to eq(17)

        expect {
          resultado = described_class.call(
            venda: venda,
            tipo: :estorno_dinheiro,
            motivo: 'Tamanho ficou grande',
            usuario: usuario,
            itens: [
              { venda_item: item_m, quantidade: 2 } # Devolve 2 de 3
            ]
          )

          expect(resultado).to be_success
          devolucao = resultado.data[:devolucao]
          expect(devolucao).to be_persisted
          expect(devolucao.estorno_dinheiro?).to be true
          expect(devolucao.motivo).to eq('Tamanho ficou grande')
          expect(devolucao.valor_estornado).to eq(160.00) # 2 * 80.00
          expect(devolucao.itens.count).to eq(1)

          item_dev = devolucao.itens.first
          expect(item_dev.venda_item).to eq(item_m)
          expect(item_dev.quantidade).to eq(2)
          expect(item_dev.retornou_ao_estoque).to be true
        }.to change { estoque_m.reload.quantidade }.by(2)
         .and change { EstoqueMovimentacao.count }.by(1)

        mov = EstoqueMovimentacao.last
        expect(mov.tipo).to eq('estorno_devolucao')
        expect(mov.quantidade).to eq(2)
        expect(mov.origem).to eq(Devolucao.last)
      end

      it 'processa devolução total automática quando itens for omitido' do
        expect {
          resultado = described_class.call(
            venda: venda,
            tipo: :credito_troca,
            motivo: 'Troca de pedido completo'
          )

          expect(resultado).to be_success
          devolucao = resultado.data[:devolucao]
          expect(devolucao.credito_troca?).to be true
          expect(devolucao.valor_estornado).to eq(440.00)
          expect(devolucao.itens.count).to eq(2)
        }.to change { estoque_m.reload.quantidade }.by(3)
         .and change { estoque_g.reload.quantidade }.by(2)
      end

      it 'não reintegra ao estoque quando tipo for defeito_avaria por padrão' do
        expect {
          resultado = described_class.call(
            venda: venda,
            tipo: :defeito_avaria,
            motivo: 'Costura rasgada no zíper',
            itens: [ { venda_item: item_m, quantidade: 1 } ]
          )

          expect(resultado).to be_success
          item_dev = resultado.data[:devolucao].itens.first
          expect(item_dev.retornou_ao_estoque).to be false
        }.not_to change { estoque_m.reload.quantidade }
      end

      it 'permite customizar valor_estornado e forçar retorno ao estoque em defeito_avaria' do
        resultado = described_class.call(
          venda: venda,
          tipo: :defeito_avaria,
          motivo: 'Defeito simples reparável',
          valor_estornado: 50.00,
          itens: [ { venda_item: item_m, quantidade: 1, retornou_ao_estoque: true } ]
        )

        expect(resultado).to be_success
        devolucao = resultado.data[:devolucao]
        expect(devolucao.valor_estornado).to eq(50.00)
        expect(devolucao.itens.first.retornou_ao_estoque).to be true
        expect(estoque_m.reload.quantidade).to eq(18)
      end
    end

    context 'controle de saldo por item em devoluções sucessivas' do
      it 'permite múltiplas devoluções parciais até esgotar o saldo' do
        # 1ª devolução: 1 unidade de item_m
        res1 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res1).to be_success

        # 2ª devolução: mais 2 unidades de item_m (totalizando 3)
        res2 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: item_m, quantidade: 2 } ]
        )
        expect(res2).to be_success

        # 3ª devolução: tentar devolver mais 1 unidade deve falhar
        res3 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res3).to be_failure
        expect(res3.error_code).to eq(:quantity_exceeds_available)
      end

      it 'falha quando a quantidade solicitada excede o saldo da compra' do
        resultado = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: item_m, quantidade: 4 } ] # Comprou 3
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:quantity_exceeds_available)
      end

      it 'bloqueia devolução quando o valor estornado cumulativo excede o saldo da venda' do
        # Venda total: R$ 440.00
        # 1ª devolução estorna R$ 300.00
        res1 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          valor_estornado: 300.00,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res1).to be_success

        # 2ª devolução tenta estornar R$ 200.00 (saldo restante é R$ 140.00)
        res2 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          valor_estornado: 200.00,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res2).to be_failure
        expect(res2.error_code).to eq(:refund_amount_exceeds_available)
        expect(res2.error).to include('excede o saldo disponível para estorno')
      end

      it 'bloqueia novas devoluções quando o valor total da venda já foi integralmente estornado' do
        # 1ª devolução estorna os 440.00 totais
        res1 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          valor_estornado: 440.00,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res1).to be_success

        # 2ª devolução com qualquer valor
        res2 = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: item_m, quantidade: 1 } ]
        )
        expect(res2).to be_failure
        expect(res2.error_code).to eq(:sale_already_fully_refunded)
      end
    end

    context 'validações de erro e salvaguardas' do
      it 'falha quando a venda não é encontrada' do
        resultado = described_class.call(
          venda: 999999,
          tipo: :estorno_dinheiro
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:sale_not_found)
      end

      it 'falha quando a venda pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          empresa: outra_empresa,
          venda: venda,
          tipo: :estorno_dinheiro
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a venda está cancelada' do
        Vendas::CancelarVendaService.call(venda: venda, motivo: 'Cancelamento total')

        resultado = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_return_cancelled_sale)
      end

      it 'falha quando o item pertence a outra venda' do
        outra_venda = create(:venda, empresa: empresa, cliente: cliente)
        outro_item = create(:venda_item, venda: outra_venda, variacao_produto: variacao_m, quantidade: 1)

        resultado = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item: outro_item, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_item)
      end

      it 'falha quando o item é referenciado por ID de outra venda' do
        outra_venda = create(:venda, empresa: empresa, cliente: cliente)
        outro_item = create(:venda_item, venda: outra_venda, variacao_produto: variacao_m, quantidade: 1)

        resultado = described_class.call(
          venda: venda,
          tipo: :estorno_dinheiro,
          itens: [ { venda_item_id: outro_item.id, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_item)
      end

      it 'falha quando o tipo de devolução é inválido' do
        resultado = described_class.call(
          venda: venda,
          tipo: :tipo_inexistente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_return_type)
      end

      it 'falha e faz rollback caso a movimentação de estoque falhe' do
        allow(Estoques::MovimentarService).to receive(:call).and_return(
          ApplicationService::Result.new(success: false, error: 'Erro de estoque', error_code: :stock_error)
        )

        resultado = nil
        expect {
          resultado = described_class.call(
            venda: venda,
            tipo: :estorno_dinheiro,
            itens: [ { venda_item: item_m, quantidade: 1 } ]
          )
        }.not_to change { Devolucao.count }

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:stock_error)
      end
    end

    context 'aliases do serviço' do
      it 'funciona com SalvarService e CriarService' do
        r1 = Devolucoes::SalvarService.call(venda: venda, tipo: :estorno_dinheiro, itens: [ { venda_item: item_g, quantidade: 1 } ])
        r2 = Devolucoes::CriarService.call(venda: venda, tipo: :credito_troca, itens: [ { venda_item: item_g, quantidade: 1 } ])

        expect(r1).to be_success
        expect(r2).to be_success
      end
    end
  end
end
