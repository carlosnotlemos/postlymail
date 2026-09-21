require 'rails_helper'

RSpec.describe Clientes::InativarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let(:cliente) { create(:cliente, empresa: empresa, ativo: true, aceita_marketing: true) }

  describe 'inativação com sucesso' do
    it 'inativa o cliente passando a instância' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        motivo: 'Solicitação pelo titular'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Solicitação pelo titular')
      expect(cliente.reload.ativo).to be false
      expect(cliente.aceita_marketing).to be true # preservado por padrão
    end

    it 'inativa o cliente passando o ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        cliente: cliente.id
      )

      expect(result).to be_success
      expect(cliente.reload.ativo).to be false
    end

    it 'também revoga o aceite de marketing quando desativar_marketing: true' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        desativar_marketing: true
      )

      expect(result).to be_success
      cliente.reload
      expect(cliente.ativo).to be false
      expect(cliente.aceita_marketing).to be false
      expect(result.data[:marketing_desativado]).to be true
    end
  end

  describe 'tratamento de cliente já inativo' do
    let(:cliente_inativo) { create(:cliente, empresa: empresa, ativo: false, documento: '88899900011') }

    it 'falha por padrão quando o cliente já se encontra inativo (:client_already_inactive)' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente_inativo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:client_already_inactive)
      expect(result.error).to include('Cliente já se encontra inativo')
    end

    it 'sucede de forma idempotente quando ignorar_se_inativo: true' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente_inativo,
        ignorar_se_inativo: true
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be false
      expect(result.data[:ja_estava_inativo]).to be true
    end
  end

  describe 'regra de vendas em andamento' do
    it 'permite inativar por padrão mesmo possuindo vendas pendentes' do
      create(:venda, empresa: empresa, cliente: cliente, status: :pendente)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente
      )

      expect(result).to be_success
      expect(cliente.reload.ativo).to be false
    end

    it 'falha com :client_has_pending_sales quando permitir_com_vendas_em_andamento: false e houver venda em aberto' do
      create(:venda, empresa: empresa, cliente: cliente, status: :paga)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        permitir_com_vendas_em_andamento: false
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:client_has_pending_sales)
      expect(result.error).to include('Cliente possui vendas em andamento')
      expect(cliente.reload.ativo).to be true
    end

    it 'permite inativar quando permitir_com_vendas_em_andamento: false mas as vendas estiverem concluídas ou canceladas' do
      create(:venda, empresa: empresa, cliente: cliente, status: :concluida)
      create(:venda, empresa: empresa, cliente: cliente, status: :cancelada, motivo_cancelamento: 'Desistência')

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        permitir_com_vendas_em_andamento: false
      )

      expect(result).to be_success
      expect(cliente.reload.ativo).to be false
    end
  end

  describe 'validações e isolamento multi-tenant' do
    it 'falha se empresa for nula (:tenant_not_found)' do
      result = described_class.call(
        empresa: nil,
        cliente: cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha se empresa não existir (:tenant_not_found)' do
      result = described_class.call(
        empresa: 999_999,
        cliente: cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha se cliente for nulo (:client_not_found)' do
      result = described_class.call(
        empresa: empresa,
        cliente: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:client_not_found)
    end

    it 'falha se cliente pertencer a outra empresa (:unauthorized_tenant)' do
      cliente_outro_tenant = create(:cliente, empresa: outra_empresa, documento: '55566677788')

      result = described_class.call(
        empresa: empresa,
        cliente: cliente_outro_tenant
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end
  end
end
