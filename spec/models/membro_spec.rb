require 'rails_helper'

RSpec.describe Membro, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to usuario' do
      expect(described_class.reflect_on_association(:usuario).macro).to eq :belongs_to
    end

    it 'belongs to convidado_por optionally' do
      assoc = described_class.reflect_on_association(:convidado_por)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:usuario) { create(:usuario) }
    subject { build(:membro, empresa: empresa, usuario: usuario) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of papel' do
      subject.papel = nil
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of usuario scoped to empresa' do
      create(:membro, empresa: empresa, usuario: usuario)
      duplicate = build(:membro, empresa: empresa, usuario: usuario)
      expect(duplicate).not_to be_valid
    end

    it 'allows same usuario in different empresas' do
      other_empresa = create(:empresa)
      create(:membro, empresa: empresa, usuario: usuario)
      other_member = build(:membro, empresa: other_empresa, usuario: usuario)
      expect(other_member).to be_valid
    end
  end

  describe 'scopes' do
    let(:empresa) { create(:empresa) }
    let!(:membro_ativo) { create(:membro, empresa: empresa, ativo: true, papel: :proprietario) }
    let!(:membro_inativo) { create(:membro, empresa: empresa, ativo: false, papel: :gerente) }
    let!(:membro_atendente) { create(:membro, empresa: empresa, papel: :atendente) }
    let!(:membro_estoquista) { create(:membro, empresa: empresa, papel: :estoquista) }

    describe '.ativos e .inativos' do
      it 'filters correctly by active status' do
        expect(described_class.ativos).to include(membro_ativo, membro_atendente, membro_estoquista)
        expect(described_class.ativos).not_to include(membro_inativo)

        expect(described_class.inativos).to include(membro_inativo)
        expect(described_class.inativos).not_to include(membro_ativo)
      end
    end

    describe 'role scopes' do
      it 'filters by role correctly' do
        expect(described_class.proprietarios).to include(membro_ativo)
        expect(described_class.gerentes).to include(membro_inativo)
        expect(described_class.atendentes).to include(membro_atendente)
        expect(described_class.estoquistas).to include(membro_estoquista)
      end
    end
  end
end
