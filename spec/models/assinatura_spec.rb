require 'rails_helper'

RSpec.describe Assinatura, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      association = described_class.reflect_on_association(:empresa)
      expect(association.macro).to eq :belongs_to
    end

    it 'belongs to plano' do
      association = described_class.reflect_on_association(:plano)
      expect(association.macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:plano) { create(:plano, identificador: :start) }
    subject { build(:assinatura, empresa: empresa, plano: plano) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of ciclo' do
      subject.ciclo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor' do
      subject.valor = -1
      expect(subject).not_to be_valid
    end

    it 'prevents having more than one active subscription for the same empresa' do
      create(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      duplicate = build(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      expect(duplicate).not_to be_valid
    end

    it 'allows multiple canceled subscriptions for the same empresa' do
      create(:assinatura, empresa: empresa, plano: plano, status: :cancelada)
      another = build(:assinatura, empresa: empresa, plano: plano, status: :cancelada)
      expect(another).to be_valid
    end
  end
end
