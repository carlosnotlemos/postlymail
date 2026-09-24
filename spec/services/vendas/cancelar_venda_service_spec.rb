# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendas::CancelarVendaService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-geek') }
  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:usuario) { create(:usuario, email: 'gerente@empresa.com') }
  let!(:membro_gerente) do
    create(:membro, empresa: empresa, usuario: usuario, papel: :gerente, ativo: true)
  end

  let!(:produto) { create(:produto, empresa: empresa, nome: 'Camiseta Gamer') }
  let!(:variacao) do
    create(:variacao_produto, empresa: empresa, produto: produto, sku: 'CAM-GAM-M', preco_base: 100.0, ativo: true)
  end
  let!(:estoque) { create(:estoque, variacao_produto: variacao, quantidade: 20) }

  let!(:cupom) do
    create(:cupom, empresa: empresa, codigo: 'DESC10', tipo: :valor_fixo, valor: 10.0, ativo: true, usos_contagem: 2)
  end

  # Cria venda previamente fechada com baixa de estoque
  let!(:venda) do
    res = Vendas::FecharVendaService.call(
      empresa: empresa,
      cliente: cliente,
      usuario: usuario,
      tipo_entrega: :retirada,
      cupom: cupom,
      itens: [ { variacao_produto: variacao, quantidade: 2 } ]
    )
    res.data[:venda]
  end

  describe '.call' do
    context 'cancelamento com sucesso' do
      it 'atualiza o status da venda e preenche auditoria de cancelamento' do
        resultado = described_class.call(
          venda: venda,
          motivo_cancelamento: 'Cliente solicitou desistência antes do envio',
          cancelado_por: usuario
        )

        expect(resultado).to be_success
        venda_cancelada = resultado.data[:venda].reload
        expect(venda_cancelada.cancelada?).to be true
        expect(venda_cancelada.motivo_cancelamento).to eq('Cliente solicitou desistência antes do envio')
        expect(venda_cancelada.cancelado_por).to eq(usuario)
        expect(venda_cancelada.cancelado_em).to be_present
      end

      it 'reintegra os itens ao estoque com tipo estorno_devolucao' do
        # Estoque original: 20 -> pós-venda: 18
        expect(estoque.reload.quantidade).to eq(18)

        expect {
          described_class.call(
            venda: venda,
            motivo_cancelamento: 'Desistência do pedido',
            cancelado_por: usuario
          )
        }.to change { estoque.reload.quantidade }.by(2)
         .and change { EstoqueMovimentacao.count }.by(1)

        mov = EstoqueMovimentacao.last
        expect(mov.tipo).to eq('estorno_devolucao')
        expect(mov.quantidade).to eq(2)
        expect(mov.origem).to eq(venda)
      end

      it 'reverte a contagem de usos do cupom consumido' do
        # Cupom tinha 2 usos, pós-venda subiu para 3
        expect(cupom.reload.usos_contagem).to eq(3)

        described_class.call(
          venda: venda,
          motivo_cancelamento: 'Cancelamento por falta de pagamento'
        )

        expect(cupom.reload.usos_contagem).to eq(2)
      end

      it 'permite não estornar estoque quando explicitamente solicitado' do
        expect {
          described_class.call(
            venda: venda,
            motivo_cancelamento: 'Produto extraviado/danificado',
            estornar_estoque: false
          )
        }.not_to change { estoque.reload.quantidade }
      end

      it 'permite não estornar cupom quando estornar_cupom for false' do
        expect {
          described_class.call(
            venda: venda,
            motivo_cancelamento: 'Sem devolução de cupom',
            estornar_cupom: false
          )
        }.not_to change { cupom.reload.usos_contagem }
      end

      it 'atualiza pagamentos aprovados para estornados e pendentes para cancelados' do
        pag_aprovado = venda.pagamentos.create!(
          forma_pagamento: :pix,
          gateway: :asaas,
          valor: 50.0,
          status: :aprovado,
          data_liquidacao: Time.current
        )
        pag_pendente = venda.pagamentos.create!(
          forma_pagamento: :boleto,
          gateway: :manual,
          valor: 50.0,
          status: :pendente
        )

        described_class.call(
          venda: venda,
          motivo_cancelamento: 'Desistência com pagamentos'
        )

        expect(pag_aprovado.reload.status).to eq('estornado')
        expect(pag_pendente.reload.status).to eq('cancelado')
      end

      it 'permite não estornar pagamentos quando estornar_pagamentos for false' do
        pag_aprovado = venda.pagamentos.create!(
          forma_pagamento: :pix,
          gateway: :asaas,
          valor: 50.0,
          status: :aprovado
        )

        described_class.call(
          venda: venda,
          motivo_cancelamento: 'Tratamento financeiro externo',
          estornar_pagamentos: false
        )

        expect(pag_aprovado.reload.status).to eq('aprovado')
      end

      it 'retorna erro detalhado do estoque caso a movimentação falhe' do
        allow(Estoques::MovimentarService).to receive(:call).and_return(
          ApplicationService::Result.new(success: false, error: 'Erro de auditoria de estoque', error_code: :stock_movement_failed)
        )

        resultado = described_class.call(
          venda: venda,
          motivo_cancelamento: 'Falha simulada'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:stock_movement_failed)
        expect(resultado.error).to eq('Erro de auditoria de estoque')
      end
    end

    context 'validações de erro e salvaguardas' do
      it 'falha quando a venda não é encontrada' do
        resultado = described_class.call(
          venda: 999999,
          motivo_cancelamento: 'Teste'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:sale_not_found)
      end

      it 'falha quando a venda pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          empresa: outra_empresa,
          venda: venda,
          motivo_cancelamento: 'Teste'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a venda já está cancelada' do
        described_class.call(
          venda: venda,
          motivo_cancelamento: 'Primeiro cancelamento'
        )

        resultado_duplicado = described_class.call(
          venda: venda,
          motivo_cancelamento: 'Segundo cancelamento'
        )

        expect(resultado_duplicado).to be_failure
        expect(resultado_duplicado.error_code).to eq(:sale_already_cancelled)
      end

      it 'tolera venda já cancelada quando ignorar_se_cancelada for true' do
        described_class.call(
          venda: venda,
          motivo_cancelamento: 'Primeiro cancelamento'
        )

        resultado_idempotente = described_class.call(
          venda: venda,
          motivo_cancelamento: 'Segundo cancelamento',
          ignorar_se_cancelada: true
        )

        expect(resultado_idempotente).to be_success
        expect(resultado_idempotente.data[:ja_cancelada]).to be true
      end

      it 'falha quando o motivo do cancelamento não é informado' do
        resultado = described_class.call(
          venda: venda,
          motivo_cancelamento: nil
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_cancellation_reason)
      end
    end

    context 'aliases do serviço' do
      it 'funciona com CancelarService e EstornarService' do
        venda2 = Vendas::FecharVendaService.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao, quantidade: 1 } ]
        ).data[:venda]

        res = Vendas::CancelarService.call(venda: venda2, motivo: 'Teste alias')
        expect(res).to be_success
        expect(venda2.reload.cancelada?).to be true
      end
    end
  end
end
