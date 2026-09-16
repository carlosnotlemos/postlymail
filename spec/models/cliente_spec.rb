require 'rails_helper'

RSpec.describe Cliente, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:cliente, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates email format when present' do
      subject.email = 'invalido'
      expect(subject).not_to be_valid

      subject.email = nil
      expect(subject).to be_valid
    end

    it 'sets data_cadastro automatically before validation on create' do
      cliente = Cliente.new(empresa: empresa, nome: 'Maria')
      cliente.valid?
      expect(cliente.data_cadastro).to be_present
    end
  end
end
