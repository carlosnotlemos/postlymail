require 'rails_helper'

RSpec.describe Cupons::InativarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:cupom) { create(:cupom, empresa: empresa, codigo: 'ATIVO10', ativo: true) }

  describe 'inativação de cupom ativo' do
    it 'inativa o cupom com sucesso passando a instância' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom,
        motivo: 'Campanha encerrada antecipadamente'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Campanha encerrada antecipadamente')
      expect(cupom.reload.ativo).to be false
    end

    it 'inativa o cupom com sucesso passando o ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        cupom: cupom.id
      )

      expect(result).to be_success
      expect(cupom.reload.ativo).to be false
    end

    it 'inativa o cupom com sucesso passando o código alfanumérico' do
      result = described_class.call(
        empresa: empresa,
        cupom: 'ativo10'
      )

      expect(result).to be_success
      expect(cupom.reload.ativo).to be false
    end
  end

  describe 'idempotência e cupom já inativo' do
    let!(:cupom_inativo) { create(:cupom, empresa: empresa, codigo: 'DESATIVADO', ativo: false) }

    it 'retorna erro quando o cupom já está inativo e ignorar_se_inativo é false' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom_inativo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:coupon_already_inactive)
      expect(result.error).to include('Cupom já se encontra inativo')
    end

    it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom_inativo,
        ignorar_se_inativo: true
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be false
      expect(result.data[:ja_estava_inativo]).to be true
      expect(cupom_inativo.reload.ativo).to be false
    end
  end

  describe 'multi-tenancy e autorização' do
    it 'retorna erro quando empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        cupom: cupom
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna unauthorized_tenant quando cupom pertence a outra empresa' do
      cupom_alheio = create(:cupom, empresa: outra_empresa, codigo: 'ALHEIO')

      result = described_class.call(
        empresa: empresa,
        cupom: cupom_alheio
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna coupon_not_found quando cupom não é encontrado' do
      result = described_class.call(
        empresa: empresa,
        cupom: 'INEXISTENTE'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:coupon_not_found)
    end
  end
end
