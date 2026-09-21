require 'rails_helper'

RSpec.describe Custos::SalvarEmLoteService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let(:venda) { create(:venda, empresa: empresa) }
  let(:venda_outra) { create(:venda, empresa: outra_empresa) }

  describe 'aliases de serviço' do
    it 'permite chamar através de Custos::CadastrarLoteService' do
      expect(Custos::CadastrarLoteService).to eq(Custos::SalvarEmLoteService)
    end

    it 'permite chamar através de Custos::RegistrarLoteService' do
      expect(Custos::RegistrarLoteService).to eq(Custos::SalvarEmLoteService)
    end
  end

  describe 'salvamento em lote com sucesso' do
    it 'cria múltiplos custos vinculados à mesma empresa' do
      itens = [
        { categoria: :insumos_producao, valor: 150.0, descricao: 'Fita adesiva e caixas' },
        { categoria: :frete_entrega, valor: 25.0, descricao: 'Entrega moto express' },
        { categoria: :embalagem, valor: 12.50, descricao: 'Sacolas kraft' }
      ]

      result = described_class.call(
        empresa: empresa,
        custos: itens
      )

      expect(result).to be_success
      expect(result.data[:quantidade]).to eq(3)
      expect(result.data[:valor_total]).to eq(187.50)
      expect(empresa.custos.count).to eq(3)
    end

    it 'cria múltiplos custos associando todos à mesma venda padrão' do
      itens = [
        { categoria: :frete_entrega, valor: 30.0 },
        { categoria: :embalagem, valor: 10.0 }
      ]

      result = described_class.call(
        empresa: empresa,
        venda: venda,
        custos: itens
      )

      expect(result).to be_success
      expect(result.data[:quantidade]).to eq(2)
      result.data[:custos].each do |custo|
        expect(custo.venda_id).to eq(venda.id)
      end
    end

    it 'permite sobrescrever a venda por item individual no lote' do
      cliente = create(:cliente, empresa: empresa)
      venda1 = create(:venda, empresa: empresa, cliente: cliente)
      venda2 = create(:venda, empresa: empresa, cliente: cliente)
      itens = [
        { categoria: :frete_entrega, valor: 20.0, venda: venda1 },
        { categoria: :frete_entrega, valor: 25.0, venda: venda2 },
        { categoria: :operacional_geral, valor: 50.0, venda: nil }
      ]

      result = described_class.call(
        empresa: empresa,
        custos: itens
      )

      expect(result).to be_success
      custos = result.data[:custos]
      expect(custos[0].venda_id).to eq(venda1.id)
      expect(custos[1].venda_id).to eq(venda2.id)
      expect(custos[2].venda_id).to be_nil
    end
  end

  describe 'atomicidade e rollback transacional' do
    it 'reverte todos os custos se qualquer item for inválido' do
      itens = [
        { categoria: :frete_entrega, valor: 20.0 },
        { categoria: :categoria_invalida, valor: 30.0 }, # Este falhará
        { categoria: :embalagem, valor: 15.0 }
      ]

      expect {
        result = described_class.call(
          empresa: empresa,
          custos: itens
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_category)
        expect(result.error).to include('Erro no lançamento 2')
      }.not_to change(Custo, :count)
    end

    it 'reverte todos se algum valor for negativo' do
      itens = [
        { categoria: :frete_entrega, valor: 20.0 },
        { categoria: :embalagem, valor: -10.0 }
      ]

      expect {
        result = described_class.call(
          empresa: empresa,
          custos: itens
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_amount)
      }.not_to change(Custo, :count)
    end
  end

  describe 'validações de entrada e tenant' do
    it 'falha quando empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        custos: [ { categoria: :embalagem, valor: 10.0 } ]
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha quando venda pertence a outra empresa' do
      result = described_class.call(
        empresa: empresa,
        venda: venda_outra,
        custos: [ { categoria: :embalagem, valor: 10.0 } ]
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha quando venda não existe' do
      result = described_class.call(
        empresa: empresa,
        venda: 999999,
        custos: [ { categoria: :embalagem, valor: 10.0 } ]
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:sale_not_found)
    end

    it 'falha quando a lista de custos não é um Array' do
      result = described_class.call(
        empresa: empresa,
        custos: 'invalido'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_batch_format)
    end

    it 'falha quando a lista de custos está vazia' do
      result = described_class.call(
        empresa: empresa,
        custos: []
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:empty_batch)
    end
  end
end
