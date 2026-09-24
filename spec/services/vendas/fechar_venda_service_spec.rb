# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendas::FecharVendaService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-geek') }
  let!(:cliente) { create(:cliente, empresa: empresa, nome: 'Fulano de Tal', telefone: '11999998888') }
  let!(:endereco) do
    create(
      :endereco,
      cliente: cliente,
      padrao: true,
      logradouro: 'Av Paulista',
      numero: '1000',
      bairro: 'Bela Vista',
      cidade: 'São Paulo',
      estado: 'SP',
      cep: '01310-100'
    )
  end

  let!(:usuario) { create(:usuario, email: 'vendedor@empresa.com') }
  let!(:membro_vendedor) do
    create(:membro, empresa: empresa, usuario: usuario, papel: :atendente, ativo: true)
  end

  let!(:produto) { create(:produto, empresa: empresa, nome: 'Camiseta Gamer') }
  let!(:variacao_m) do
    create(
      :variacao_produto,
      empresa: empresa,
      produto: produto,
      sku: 'CAM-GAM-M',
      tamanho: 'M',
      cor: 'Preta',
      preco_base: 89.90,
      preco_custo: 35.00,
      ativo: true
    )
  end
  let!(:estoque_m) { create(:estoque, variacao_produto: variacao_m, quantidade: 20) }

  let!(:variacao_g) do
    create(
      :variacao_produto,
      empresa: empresa,
      produto: produto,
      sku: 'CAM-GAM-G',
      tamanho: 'G',
      cor: 'Branca',
      preco_base: 99.90,
      preco_custo: 40.00,
      ativo: true
    )
  end
  let!(:estoque_g) { create(:estoque, variacao_produto: variacao_g, quantidade: 15) }

  describe '.call' do
    context 'fechamento básico de venda com sucesso' do
      let(:parametros_validos) do
        {
          empresa: empresa,
          cliente: cliente,
          usuario: usuario,
          tipo_entrega: :motoboy_uber,
          valor_frete: 15.00,
          itens: [
            { variacao_produto: variacao_m, quantidade: 2 },
            { variacao_produto: variacao_g, quantidade: 1 }
          ]
        }
      end

      it 'cria a venda e os itens calculando totais corretamente' do
        resultado = described_class.call(parametros_validos)

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda).to be_persisted
        expect(venda.codigo_pedido).to be_present
        expect(venda.empresa).to eq(empresa)
        expect(venda.cliente).to eq(cliente)
        expect(venda.usuario).to eq(usuario)
        expect(venda.tipo_entrega).to eq('motoboy_uber')
        expect(venda.status).to eq('pendente')

        # Subtotal: (2 * 89.90 = 179.80) + (1 * 99.90 = 99.90) = 279.70
        expect(venda.subtotal_produtos).to eq(279.70)
        expect(venda.valor_frete).to eq(15.00)
        expect(venda.valor_desconto).to eq(0.0)
        expect(venda.valor_total).to eq(294.70)

        expect(venda.itens.count).to eq(2)
        item1 = venda.itens.find_by(variacao_produto: variacao_m)
        expect(item1.quantidade).to eq(2)
        expect(item1.valor_unitario).to eq(89.90)
        expect(item1.preco_custo_unitario).to eq(35.00)
        expect(item1.subtotal).to eq(179.80)
        expect(item1.detalhes_produto['sku']).to eq('CAM-GAM-M')
        expect(item1.detalhes_produto['produto_nome']).to eq('Camiseta Gamer')
        expect(item1.detalhes_produto['tamanho']).to eq('M')
        expect(item1.detalhes_produto['cor']).to eq('Preta')
      end

      it 'congela o snapshot do endereço de entrega' do
        resultado = described_class.call(parametros_validos)

        venda = resultado.data[:venda]
        snapshot = venda.endereco_entrega
        expect(snapshot['logradouro']).to eq('Av Paulista')
        expect(snapshot['numero']).to eq('1000')
        expect(snapshot['bairro']).to eq('Bela Vista')
        expect(snapshot['cidade']).to eq('São Paulo')
        expect(snapshot['estado']).to eq('SP')
        expect(snapshot['cep']).to eq('01310-100')
        expect(snapshot['destinatario']).to eq('Fulano de Tal')
      end

      it 'debita o estoque e registra movimentações de saída' do
        expect {
          described_class.call(parametros_validos)
        }.to change { estoque_m.reload.quantidade }.by(-2)
         .and change { estoque_g.reload.quantidade }.by(-1)
         .and change { EstoqueMovimentacao.count }.by(2)

        venda = Venda.last
        mov = EstoqueMovimentacao.find_by(variacao_produto: variacao_m, origem: venda)
        expect(mov.tipo).to eq('saida_venda')
        expect(mov.quantidade).to eq(2)
        expect(mov.usuario).to eq(usuario)
      end

      it 'permite venda para retirada sem exigir endereço cadastrado' do
        outro_cliente = create(:cliente, empresa: empresa, documento: '11122233344') # sem endereços

        resultado = described_class.call(
          empresa: empresa,
          cliente: outro_cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda.tipo_entrega).to eq('retirada')
        expect(venda.endereco_entrega['retirada_na_loja']).to be true
      end

      it 'permite customizar valor_unitario e preco_custo_unitario' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [
            {
              variacao_produto: variacao_m,
              quantidade: 1,
              valor_unitario: 75.00,
              preco_custo_unitario: 30.00,
              observacoes: 'Desconto promocional de balcão'
            }
          ]
        )

        expect(resultado).to be_success
        item = resultado.data[:venda].itens.first
        expect(item.valor_unitario).to eq(75.00)
        expect(item.preco_custo_unitario).to eq(30.00)
        expect(item.subtotal).to eq(75.00)
        expect(item.observacoes).to eq('Desconto promocional de balcão')
      end

      it 'permite não baixar estoque se baixar_estoque for false' do
        expect {
          described_class.call(
            empresa: empresa,
            cliente: cliente,
            tipo_entrega: :retirada,
            baixar_estoque: false,
            itens: [ { variacao_produto: variacao_m, quantidade: 2 } ]
          )
        }.not_to change { estoque_m.reload.quantidade }
      end
    end

    context 'com aplicação de cupons e descontos' do
      let!(:cupom_dez_porcento) do
        create(
          :cupom,
          empresa: empresa,
          codigo: 'DESC10',
          tipo: :porcentagem,
          valor: 10.0,
          ativo: true,
          limite_usos: 5,
          usos_contagem: 0
        )
      end

      it 'aplica cupom percentual com sucesso e incrementa contagem de usos' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          cupom: 'DESC10',
          itens: [ { variacao_produto: variacao_m, quantidade: 2 } ] # subtotal = 179.80
        )

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda.cupom).to eq(cupom_dez_porcento)
        expect(venda.codigo_cupom).to eq('DESC10')
        expect(venda.desconto_cupom).to eq(17.98)
        expect(venda.valor_desconto).to eq(17.98)
        expect(venda.valor_total).to eq(161.82)
        expect(cupom_dez_porcento.reload.usos_contagem).to eq(1)
      end

      it 'aplica desconto manual cumulativo' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          cupom: 'DESC10',
          desconto_manual: 10.00,
          itens: [ { variacao_produto: variacao_m, quantidade: 2 } ] # subtotal = 179.80
        )

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda.desconto_manual).to eq(10.00)
        expect(venda.desconto_cupom).to eq(17.98)
        expect(venda.valor_desconto).to eq(27.98)
        expect(venda.valor_total).to eq(151.82)
      end

      it 'falha quando o desconto total excede o subtotal dos produtos' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          desconto_manual: 200.00,
          itens: [ { variacao_produto: variacao_m, quantidade: 2 } ] # subtotal = 179.80
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:discount_exceeds_subtotal)
      end

      it 'retorna erro detalhado do cupom quando o consumo falha dentro da transação' do
        allow(Cupons::AplicarService).to receive(:call).and_call_original
        allow(Cupons::AplicarService).to receive(:call).with(hash_including(consumir: true)).and_return(
          ApplicationService::Result.new(success: false, error: 'Limite de utilizações do cupom atingido', error_code: :coupon_limit_reached)
        )

        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          cupom: 'DESC10',
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:coupon_limit_reached)
        expect(resultado.error).to eq('Limite de utilizações do cupom atingido')
      end

      it 'marca a venda diretamente como paga quando o valor total for zero decorrente de desconto' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          desconto_manual: 89.90,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ] # subtotal = 89.90
        )

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda.valor_total).to eq(0.0)
        expect(venda.valor_desconto).to eq(89.90)
        expect(venda.status).to eq('paga')
      end
    end

    context 'com processamento de pagamentos' do
      it 'cria pagamento e atualiza status da venda para paga quando total é coberto' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ], # 89.90
          pagamento: {
            forma_pagamento: :pix,
            gateway: :asaas,
            valor: 89.90,
            taxa_operadora: 1.50,
            status: :aprovado
          }
        )

        expect(resultado).to be_success
        venda = resultado.data[:venda]
        expect(venda.status).to eq('paga')
        expect(venda.pagamentos.count).to eq(1)
        pag = venda.pagamentos.first
        expect(pag.pix?).to be true
        expect(pag.valor).to eq(89.90)
        expect(pag.taxa_operadora).to eq(1.50)
        expect(pag.valor_liquido).to eq(88.40)
        expect(pag.aprovado?).to be true
      end
    end

    context 'validações de estoque e rollback transacional' do
      it 'falha e faz rollback se o estoque for insuficiente' do
        estoque_m.update!(quantidade: 1)

        resultado = nil
        expect {
          resultado = described_class.call(
            empresa: empresa,
            cliente: cliente,
            tipo_entrega: :retirada,
            itens: [ { variacao_produto: variacao_m, quantidade: 5 } ]
          )
        }.not_to change { Venda.count }

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:insufficient_stock)
        expect(estoque_m.reload.quantidade).to eq(1)
      end

      it 'reverte cupom caso ocorra erro no estoque' do
        cupom = create(:cupom, empresa: empresa, codigo: 'PROMO', valor: 10.0, tipo: :valor_fixo, usos_contagem: 0)
        estoque_m.update!(quantidade: 1)

        described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          cupom: 'PROMO',
          itens: [ { variacao_produto: variacao_m, quantidade: 5 } ]
        )

        expect(cupom.reload.usos_contagem).to eq(0)
      end
    end

    context 'isolamento multi-tenant e validações de integridade' do
      it 'falha quando a empresa não é encontrada' do
        resultado = described_class.call(
          empresa: nil,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha quando o cliente pertence a outro tenant' do
        outra_empresa = create(:empresa)
        cliente_estranho = create(:cliente, empresa: outra_empresa)

        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente_estranho,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando uma das variações pertence a outro tenant' do
        outra_empresa = create(:empresa)
        outro_prod = create(:produto, empresa: outra_empresa)
        var_estranha = create(:variacao_produto, empresa: outra_empresa, produto: outro_prod)

        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: var_estranha, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando uma variação está inativa' do
        variacao_m.update!(ativo: false)

        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:variation_inactive)
      end

      it 'falha quando a lista de itens está vazia' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: []
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empty_items)
      end

      it 'falha quando a quantidade é inválida' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 0 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_quantity)
      end

      it 'falha quando o usuário não é membro ativo da empresa' do
        estranho = create(:usuario)

        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          usuario: estranho,
          tipo_entrega: :retirada,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_user)
      end

      it 'falha quando o tipo de entrega é inválido' do
        resultado = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: :drone_espacial,
          itens: [ { variacao_produto: variacao_m, quantidade: 1 } ]
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_delivery_type)
      end
    end

    context 'resolução flexível de identificadores e aliases' do
      it 'resolve empresa por slug e cliente por id' do
        resultado = described_class.call(
          empresa: 'loja-geek',
          cliente: cliente.id,
          tipo_entrega: 'retirada',
          itens: [ { variacao_produto: variacao_m.id, quantidade: 1 } ]
        )

        expect(resultado).to be_success
        expect(resultado.data[:venda].empresa).to eq(empresa)
      end

      it 'funciona com aliases SalvarService, CriarService e FecharService' do
        r1 = Vendas::SalvarService.call(empresa: empresa, cliente: cliente, tipo_entrega: :retirada, itens: [ { variacao_produto: variacao_m, quantidade: 1 } ])
        r2 = Vendas::CriarService.call(empresa: empresa, cliente: cliente, tipo_entrega: :retirada, itens: [ { variacao_produto: variacao_m, quantidade: 1 } ])
        r3 = Vendas::FecharService.call(empresa: empresa, cliente: cliente, tipo_entrega: :retirada, itens: [ { variacao_produto: variacao_m, quantidade: 1 } ])

        expect(r1).to be_success
        expect(r2).to be_success
        expect(r3).to be_success
      end
    end
  end
end
