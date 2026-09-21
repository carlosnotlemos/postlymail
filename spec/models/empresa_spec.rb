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

    it 'sanitiza email e documento antes da validação' do
      empresa = build(:empresa, email: '  CONTATO@EMPRESA.COM  ', documento: '12.345.678/0001-95')
      empresa.valid?
      expect(empresa.email).to eq('contato@empresa.com')
      expect(empresa.documento).to eq('12345678000195')
    end
  end

  describe 'scopes' do
    let!(:ativa) { create(:empresa, ativo: true) }
    let!(:inativa) { create(:empresa, ativo: false) }

    it '.ativas retorna apenas empresas ativas' do
      expect(described_class.ativas).to include(ativa)
      expect(described_class.ativas).not_to include(inativa)
    end

    it '.inativas retorna apenas empresas inativas' do
      expect(described_class.inativas).to include(inativa)
      expect(described_class.inativas).not_to include(ativa)
    end
  end

  describe 'assinaturas associations and methods' do
    let(:empresa) { create(:empresa) }
    let(:plano) { create(:plano, identificador: :start) }

    it 'has_one :assinatura_ativa returns the active subscription' do
      ass_ativa = create(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      expect(empresa.assinatura_ativa).to eq(ass_ativa)
      expect(empresa.possui_assinatura_ativa?).to be true
    end

    it 'possui_assinatura_ativa? returns false when there is only a cancelled subscription' do
      create(:assinatura, empresa: empresa, plano: plano, status: :cancelada)
      expect(empresa.assinatura_ativa).to be_nil
      expect(empresa.possui_assinatura_ativa?).to be false
    end
  end
end
