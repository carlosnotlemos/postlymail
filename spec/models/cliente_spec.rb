require 'rails_helper'

RSpec.describe Cliente, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'callbacks' do
    let(:empresa) { create(:empresa) }

    it 'sets data_cadastro automatically before validation on create' do
      cliente = Cliente.new(empresa: empresa, nome: 'Maria')
      cliente.valid?
      expect(cliente.data_cadastro).to be_present
    end

    it 'sanitizes documento by removing non-digits' do
      cliente = build(:cliente, empresa: empresa, documento: '123.456.789-00')
      cliente.valid?
      expect(cliente.documento).to eq('12345678900')
    end

    it 'sanitizes email by stripping and downcasing' do
      cliente = build(:cliente, empresa: empresa, email: '  CLIENTE@Dominio.COM  ')
      cliente.valid?
      expect(cliente.email).to eq('cliente@dominio.com')
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

    it 'validates uniqueness of documento scoped to empresa' do
      create(:cliente, empresa: empresa, documento: '12345678900')
      duplicate = build(:cliente, empresa: empresa, documento: '123.456.789-00')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:documento]).to be_present
    end

    it 'allows same documento in different empresas' do
      other_empresa = create(:empresa)
      create(:cliente, empresa: empresa, documento: '12345678900')
      other_cliente = build(:cliente, empresa: other_empresa, documento: '12345678900')
      expect(other_cliente).to be_valid
    end

    it 'allows multiple clients with blank or nil documento' do
      create(:cliente, empresa: empresa, documento: nil)
      another_nil = build(:cliente, empresa: empresa, documento: nil)
      expect(another_nil).to be_valid

      create(:cliente, empresa: empresa, documento: '')
      another_blank = build(:cliente, empresa: empresa, documento: '')
      expect(another_blank).to be_valid
    end
  end
end
