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

  describe 'callbacks' do
    it 'sanitizes email, nome and telefone before validation' do
      usuario = build(:usuario, email: '  TESTE@EXEMPLO.COM  ', nome: '  João da Silva  ', telefone: '(11) 98765-4321')
      usuario.valid?

      expect(usuario.email).to eq('teste@exemplo.com')
      expect(usuario.nome).to eq('João da Silva')
      expect(usuario.telefone).to eq('11987654321')
    end

    it 'sets telefone to nil when empty or non-numeric' do
      usuario = build(:usuario, telefone: '   ')
      usuario.valid?

      expect(usuario.telefone).to be_nil
    end
  end

  describe 'scopes' do
    let!(:usuario_ativo) { create(:usuario, ativo: true) }
    let!(:usuario_inativo) { create(:usuario, ativo: false) }

    describe '.ativos' do
      it 'returns only active users' do
        expect(Usuario.ativos).to include(usuario_ativo)
        expect(Usuario.ativos).not_to include(usuario_inativo)
      end
    end

    describe '.inativos' do
      it 'returns only inactive users' do
        expect(Usuario.inativos).to include(usuario_inativo)
        expect(Usuario.inativos).not_to include(usuario_ativo)
      end
    end
  end
end
