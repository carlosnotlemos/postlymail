require 'rails_helper'

RSpec.describe AssinaturaFatura, type: :model do
  describe 'associations' do
    it 'belongs to assinatura' do
      expect(described_class.reflect_on_association(:assinatura).macro).to eq :belongs_to
    end

    it 'has one empresa through assinatura' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :has_one
      expect(described_class.reflect_on_association(:empresa).options[:through]).to eq :assinatura
    end

    it 'has one plano through assinatura' do
      expect(described_class.reflect_on_association(:plano).macro).to eq :has_one
      expect(described_class.reflect_on_association(:plano).options[:through]).to eq :assinatura
    end
  end

  describe 'validations' do
    let(:assinatura) { create(:assinatura) }
    subject { build(:assinatura_fatura, assinatura: assinatura) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of data_vencimento' do
      subject.data_vencimento = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor' do
      subject.valor = -10
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of gateway_id when present' do
      create(:assinatura_fatura, gateway_id: 'gw_123')
      duplicate = build(:assinatura_fatura, gateway_id: 'gw_123')
      expect(duplicate).not_to be_valid
    end
  end

  describe 'scopes and methods' do
    let(:assinatura) { create(:assinatura) }
    let!(:fatura_pendente) { create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 2.days.from_now) }
    let!(:fatura_vencida) { create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 2.days.ago) }
    let!(:fatura_paga) { create(:assinatura_fatura, assinatura: assinatura, status: :paga, data_vencimento: 5.days.ago) }
    let!(:fatura_cancelada) { create(:assinatura_fatura, assinatura: assinatura, status: :cancelada, data_vencimento: 1.day.from_now) }

    it 'filters pendentes' do
      expect(described_class.pendentes).to contain_exactly(fatura_pendente, fatura_vencida)
    end

    it 'filters pagas' do
      expect(described_class.pagas).to contain_exactly(fatura_paga)
    end

    it 'filters canceladas' do
      expect(described_class.canceladas).to contain_exactly(fatura_cancelada)
    end

    it 'filters vencidas' do
      expect(described_class.vencidas).to contain_exactly(fatura_vencida)
    end

    it 'filters a_vencer' do
      expect(described_class.a_vencer).to contain_exactly(fatura_pendente)
    end

    it 'determines if an invoice is vencida?' do
      expect(fatura_vencida.vencida?).to be true
      expect(fatura_pendente.vencida?).to be false
      expect(fatura_paga.vencida?).to be false
    end
  end
end
