require 'rails_helper'

RSpec.describe AssinaturaFatura, type: :model do
  describe 'associations' do
    it 'belongs to assinatura' do
      expect(described_class.reflect_on_association(:assinatura).macro).to eq :belongs_to
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
end
