require 'rails_helper'

RSpec.describe Endereco, type: :model do
  describe 'associations' do
    it 'belongs to cliente' do
      expect(described_class.reflect_on_association(:cliente).macro).to eq :belongs_to
    end
  end

  describe 'callbacks' do
    let(:cliente) { create(:cliente) }

    it 'sanitizes cep by stripping non-digit characters' do
      endereco = build(:endereco, cliente: cliente, cep: '60.000-000')
      endereco.valid?
      expect(endereco.cep).to eq('60000000')
      expect(endereco).to be_valid
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

    it 'validates format of cep (must have 8 digits)' do
      subject.cep = '1234'
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
