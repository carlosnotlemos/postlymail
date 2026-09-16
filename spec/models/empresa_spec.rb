require 'rails_helper'

RSpec.describe Empresa, type: :model do
  describe 'validations' do
    subject { build(:empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence and uniqueness of slug' do
      subject.slug = nil
      expect(subject).not_to be_valid

      create(:empresa, slug: 'marca-x')
      duplicate = build(:empresa, slug: 'marca-x')
      expect(duplicate).not_to be_valid
    end

    it 'validates email format' do
      subject.email = 'invalido'
      expect(subject).not_to be_valid
    end

    it 'sets data_cadastro automatically before validation on create' do
      empresa = Empresa.new(nome: 'Teste', slug: 'empresa-teste', email: 'contato@teste.com')
      empresa.valid?
      expect(empresa.data_cadastro).to be_present
    end
  end
end
