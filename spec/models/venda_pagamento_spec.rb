require 'rails_helper'

RSpec.describe VendaPagamento, type: :model do
  describe 'associations' do
    it 'belongs to venda' do
      expect(described_class.reflect_on_association(:venda).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:venda) { create(:venda) }
    subject { build(:venda_pagamento, venda: venda, valor: 100.0, taxa_operadora: 2.5) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'calculates valor_liquido automatically' do
      subject.valid?
      expect(subject.valor_liquido).to eq 97.5
    end

    it 'validates numericality of parcelas >= 1' do
      subject.parcelas = 0
      expect(subject).not_to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:status]).to be_present
    end

    it 'validates presence of forma_pagamento' do
      subject.forma_pagamento = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:forma_pagamento]).to be_present
    end

    it 'validates presence of gateway' do
      subject.gateway = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:gateway]).to be_present
    end
  end
end
