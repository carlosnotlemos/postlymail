require 'rails_helper'

RSpec.describe Plano, type: :model do
  describe 'validations' do
    subject { build(:plano, identificador: :start) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of identificador' do
      subject.identificador = nil
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of identificador' do
      create(:plano, identificador: :pro)
      duplicate = build(:plano, identificador: :pro)
      expect(duplicate).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:plano_ativo1) { create(:plano, identificador: :start, valor_mensal: 49.90, ativo: true) }
    let!(:plano_ativo2) { create(:plano, identificador: :pro, valor_mensal: 99.90, ativo: true) }
    let!(:plano_inativo) { create(:plano, identificador: :enterprise, valor_mensal: 199.90, ativo: false) }

    describe '.ativos' do
      it 'returns only active plans' do
        expect(described_class.ativos).to contain_exactly(plano_ativo1, plano_ativo2)
      end
    end

    describe '.inativos' do
      it 'returns only inactive plans' do
        expect(described_class.inativos).to contain_exactly(plano_inativo)
      end
    end

    describe '.ordenados_por_valor' do
      it 'orders plans by valor_mensal ascending' do
        expect(described_class.ordenados_por_valor.to_a).to eq([ plano_ativo1, plano_ativo2, plano_inativo ])
      end
    end
  end

  describe 'instance methods' do
    let(:plano) { build(:plano, limite_produtos: 15, limite_usuarios: 2) }

    describe '#ilimitado_produtos?' do
      it 'returns false when limite_produtos is set' do
        expect(plano.ilimitado_produtos?).to be false
      end

      it 'returns true when limite_produtos is nil' do
        plano.limite_produtos = nil
        expect(plano.ilimitado_produtos?).to be true
      end
    end

    describe '#ilimitado_usuarios?' do
      it 'returns false when limite_usuarios is set' do
        expect(plano.ilimitado_usuarios?).to be false
      end

      it 'returns true when limite_usuarios is nil' do
        plano.limite_usuarios = nil
        expect(plano.ilimitado_usuarios?).to be true
      end
    end

    describe '#possui_assinaturas? and #possui_assinaturas_ativas?' do
      let(:plano_salvo) { create(:plano, identificador: :start) }
      let(:empresa) { create(:empresa) }

      it 'returns false when there are no subscriptions' do
        expect(plano_salvo.possui_assinaturas?).to be false
        expect(plano_salvo.possui_assinaturas_ativas?).to be false
      end

      it 'detects inactive subscriptions' do
        create(:assinatura, plano: plano_salvo, empresa: empresa, status: :cancelada)
        expect(plano_salvo.possui_assinaturas?).to be true
        expect(plano_salvo.possui_assinaturas_ativas?).to be false
      end

      it 'detects active subscriptions' do
        create(:assinatura, plano: plano_salvo, empresa: empresa, status: :ativa)
        expect(plano_salvo.possui_assinaturas?).to be true
        expect(plano_salvo.possui_assinaturas_ativas?).to be true
      end
    end
  end
end
