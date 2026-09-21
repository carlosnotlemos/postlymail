require 'rails_helper'

RSpec.describe Custos::ExcluirService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:custo) { create(:custo, empresa: empresa, valor: 120.0, categoria: :frete_entrega) }

  describe 'aliases de serviço' do
    it 'permite chamar através de Custos::RemoverService' do
      expect(Custos::RemoverService).to eq(Custos::ExcluirService)
      result = Custos::RemoverService.call(empresa: empresa, custo: custo)

      expect(result).to be_success
      expect(result.data[:removido]).to be true
      expect(Custo.exists?(custo.id)).to be false
    end

    it 'permite chamar através de Custos::DeletarService' do
      expect(Custos::DeletarService).to eq(Custos::ExcluirService)
    end
  end

  describe 'exclusão com sucesso' do
    it 'remove o custo passando o objeto Custo' do
      custo_id = custo.id
      result = described_class.call(
        empresa: empresa,
        custo: custo
      )

      expect(result).to be_success
      expect(result.data[:custo_id]).to eq(custo_id)
      expect(result.data[:valor]).to eq(120.0)
      expect(result.data[:categoria]).to eq('frete_entrega')
      expect(result.data[:removido]).to be true
      expect(Custo.exists?(custo_id)).to be false
    end

    it 'remove o custo passando o ID numérico' do
      custo_id = custo.id
      result = described_class.call(
        empresa: empresa,
        custo: custo_id
      )

      expect(result).to be_success
      expect(result.data[:custo_id]).to eq(custo_id)
      expect(result.data[:removido]).to be true
      expect(Custo.exists?(custo_id)).to be false
    end

    it 'aceita empresa informada por ID numérico' do
      custo_id = custo.id
      result = described_class.call(
        empresa: empresa.id,
        custo: custo
      )

      expect(result).to be_success
      expect(Custo.exists?(custo_id)).to be false
    end
  end

  describe 'salvaguardas para custo vinculado a uma venda' do
    let(:venda) { create(:venda, empresa: empresa) }
    let!(:custo_com_venda) { create(:custo, empresa: empresa, venda: venda, valor: 45.0, categoria: :frete_entrega) }

    context 'quando forcar e desvincular_venda são falsos (bloqueio padrão)' do
      it 'bloqueia a exclusão e retorna erro semântico :cost_has_associated_sale com metadados da venda' do
        result = described_class.call(
          empresa: empresa,
          custo: custo_com_venda
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:cost_has_associated_sale)
        expect(result.error).to include("Custo está vinculado à venda '#{venda.codigo_pedido}' e não pode ser excluído diretamente")
        expect(result.data[:venda_id]).to eq(venda.id)
        expect(result.data[:codigo_pedido]).to eq(venda.codigo_pedido)
        expect(Custo.exists?(custo_com_venda.id)).to be true
      end
    end

    context 'quando forcar é true (Opção A — exclusão física consciente)' do
      it 'permite a exclusão física do custo mesmo vinculado à venda' do
        custo_id = custo_com_venda.id
        result = described_class.call(
          empresa: empresa,
          custo: custo_com_venda,
          forcar: true
        )

        expect(result).to be_success
        expect(result.data[:custo_id]).to eq(custo_id)
        expect(result.data[:removido]).to be true
        expect(result.data[:forcado]).to be true
        expect(Custo.exists?(custo_id)).to be false
      end
    end

    context 'quando desvincular_venda é true (Opção B — desvinculação e preservação como despesa geral)' do
      it 'apenas desvincula a venda e preserva o custo no banco de dados' do
        result = described_class.call(
          empresa: empresa,
          custo: custo_com_venda,
          desvincular_venda: true
        )

        expect(result).to be_success
        expect(result.data[:removido]).to be false
        expect(result.data[:venda_desvinculada]).to be true
        expect(result.data[:custo_id]).to eq(custo_com_venda.id)

        custo_recarregado = custo_com_venda.reload
        expect(custo_recarregado.venda_id).to be_nil
        expect(custo_recarregado.valor).to eq(45.0)
        expect(Custo.exists?(custo_com_venda.id)).to be true
      end
    end
  end

  describe 'validações e isolamento multi-tenant' do
    it 'retorna erro quando empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        custo: custo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to include('Empresa não informada ou não encontrada')
      expect(Custo.exists?(custo.id)).to be true
    end

    it 'retorna erro quando o custo não é informado' do
      result = described_class.call(
        empresa: empresa,
        custo: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:cost_not_found)
      expect(result.error).to include('Custo não informado ou não encontrado')
    end

    it 'retorna erro quando o custo pertence a outra empresa' do
      custo_outra = create(:custo, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        custo: custo_outra
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Custo não pertence à empresa informada')
      expect(Custo.exists?(custo_outra.id)).to be true
    end

    it 'retorna erro quando o custo informado por ID pertence a outra empresa' do
      custo_outra = create(:custo, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        custo: custo_outra.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Custo não pertence à empresa informada')
      expect(Custo.exists?(custo_outra.id)).to be true
    end

    it 'retorna erro quando o custo não existe no sistema' do
      result = described_class.call(
        empresa: empresa,
        custo: 999999
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:cost_not_found)
    end
  end

  describe 'tratamento de exceções' do
    it 'trata falha inesperada em destroy!' do
      allow_any_instance_of(Custo).to receive(:destroy!).and_raise(StandardError, 'Falha de I/O no banco')

      result = described_class.call(
        empresa: empresa,
        custo: custo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unexpected_error)
      expect(result.error).to include('Falha de I/O no banco')
    end
  end
end
