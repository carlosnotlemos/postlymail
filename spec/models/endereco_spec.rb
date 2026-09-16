require 'rails_helper'

RSpec.describe Endereco, type: :model do
  describe 'associations' do
    it 'belongs to cliente' do
      expect(described_class.reflect_on_association(:cliente).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:cliente) { create(:cliente) }
    subject { build(:endereco, cliente: cliente) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of cep' do
      subject.cep = nil
      expect(subject).not_to be_valid
    end

    it 'validates format of cep (8 digits)' do
      subject.cep = '6000-000'
      expect(subject).not_to be_valid

      subject.cep = '60000000'
      expect(subject).to be_valid
    end

    it 'validates length of estado is 2' do
      subject.estado = 'CEARA'
      expect(subject).not_to be_valid
    end

    it 'prevents more than one default address for the same cliente' do
      create(:endereco, cliente: cliente, padrao: true)
      duplicate_default = build(:endereco, cliente: cliente, padrao: true)
      expect(duplicate_default).not_to be_valid
    end

    it 'allows multiple non-default addresses for the same cliente' do
      create(:endereco, cliente: cliente, padrao: false)
      another = build(:endereco, cliente: cliente, padrao: false)
      expect(another).to be_valid
    end
  end
end
