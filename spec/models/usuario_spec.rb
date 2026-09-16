require 'rails_helper'

RSpec.describe Usuario, type: :model do
  describe 'validations' do
    subject { build(:usuario) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence and uniqueness of email' do
      subject.email = nil
      expect(subject).not_to be_valid

      create(:usuario, email: 'teste@exemplo.com')
      duplicate = build(:usuario, email: 'TESTE@exemplo.com')
      expect(duplicate).not_to be_valid
    end

    it 'validates email format' do
      subject.email = 'invalido'
      expect(subject).not_to be_valid
    end

    it 'sets data_cadastro automatically before validation on create' do
      usuario = Usuario.new(nome: 'Teste', email: 'novo@exemplo.com')
      usuario.valid?
      expect(usuario.data_cadastro).to be_present
    end
  end
end
