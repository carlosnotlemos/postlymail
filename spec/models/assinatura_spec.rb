require 'rails_helper'

RSpec.describe Assinatura, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      association = described_class.reflect_on_association(:empresa)
      expect(association.macro).to eq :belongs_to
    end

    it 'belongs to plano' do
      association = described_class.reflect_on_association(:plano)
      expect(association.macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:plano) { create(:plano, identificador: :start) }
    subject { build(:assinatura, empresa: empresa, plano: plano) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of ciclo' do
      subject.ciclo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor' do
      subject.valor = -1
      expect(subject).not_to be_valid
    end

    it 'prevents having more than one active subscription for the same empresa' do
      create(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      duplicate = build(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      expect(duplicate).not_to be_valid
    end

    it 'allows multiple canceled subscriptions for the same empresa' do
      create(:assinatura, empresa: empresa, plano: plano, status: :cancelada)
      another = build(:assinatura, empresa: empresa, plano: plano, status: :cancelada)
      expect(another).to be_valid
    end
  end

  describe 'scopes' do
    let(:empresa) { create(:empresa) }
    let(:plano) { create(:plano, identificador: :start) }

    it 'filters by status correctly' do
      ass_ativa = create(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      empresa2 = create(:empresa, slug: 'empresa-2', email: 'emp2@loja.com')
      ass_cancelada = create(:assinatura, empresa: empresa2, plano: plano, status: :cancelada)
      empresa3 = create(:empresa, slug: 'empresa-3', email: 'emp3@loja.com')
      ass_suspensa = create(:assinatura, empresa: empresa3, plano: plano, status: :suspensa)

      expect(described_class.ativas).to include(ass_ativa)
      expect(described_class.ativas).not_to include(ass_cancelada)
      expect(described_class.canceladas).to include(ass_cancelada)
      expect(described_class.suspensas).to include(ass_suspensa)
    end

    it 'filters by inadimplentes and passiveis_de_cobranca correctly' do
      ass_ativa = create(:assinatura, empresa: empresa, plano: plano, status: :ativa)
      empresa2 = create(:empresa, slug: 'empresa-2', email: 'emp2@loja.com')
      ass_atrasada = create(:assinatura, empresa: empresa2, plano: plano, status: :atrasada)
      empresa3 = create(:empresa, slug: 'empresa-3', email: 'emp3@loja.com')
      ass_suspensa = create(:assinatura, empresa: empresa3, plano: plano, status: :suspensa)
      empresa4 = create(:empresa, slug: 'empresa-4', email: 'emp4@loja.com')
      ass_cancelada = create(:assinatura, empresa: empresa4, plano: plano, status: :cancelada)

      expect(described_class.inadimplentes).to contain_exactly(ass_atrasada, ass_suspensa)
      expect(described_class.passiveis_de_cobranca).to contain_exactly(ass_ativa, ass_atrasada, ass_suspensa)
    end

    it 'filters by vigentes correctly' do
      vigente = create(:assinatura, empresa: empresa, plano: plano, data_inicio: 5.days.ago.to_date, data_fim: 25.days.from_now.to_date)
      empresa2 = create(:empresa, slug: 'empresa-antiga', email: 'antiga@loja.com')
      vencida = create(:assinatura, empresa: empresa2, plano: plano, status: :cancelada, data_inicio: 40.days.ago.to_date, data_fim: 10.days.ago.to_date)

      expect(described_class.vigentes).to include(vigente)
      expect(described_class.vigentes).not_to include(vencida)
    end
  end

  describe 'helper methods' do
    let(:empresa) { create(:empresa) }
    let(:plano) { create(:plano, identificador: :start) }

    describe '#vigente?' do
      it 'returns true if within dates' do
        assinatura = build(:assinatura, empresa: empresa, plano: plano, data_inicio: 1.day.ago.to_date, data_fim: 10.days.from_now.to_date)
        expect(assinatura.vigente?).to be true
      end

      it 'returns false if expired' do
        assinatura = build(:assinatura, empresa: empresa, plano: plano, data_inicio: 20.days.ago.to_date, data_fim: 5.days.ago.to_date)
        expect(assinatura.vigente?).to be false
      end
    end

    describe '#inadimplente?' do
      it 'returns true when status is atrasada or suspensa' do
        ass1 = build(:assinatura, status: :atrasada)
        ass2 = build(:assinatura, status: :suspensa)
        ass3 = build(:assinatura, status: :ativa)

        expect(ass1.inadimplente?).to be true
        expect(ass2.inadimplente?).to be true
        expect(ass3.inadimplente?).to be false
      end
    end

    describe '#dias_restantes' do
      it 'calculates days remaining until data_fim' do
        assinatura = build(:assinatura, empresa: empresa, plano: plano, data_fim: 15.days.from_now.to_date)
        expect(assinatura.dias_restantes).to eq(15)
      end

      it 'returns 0 if already passed data_fim' do
        assinatura = build(:assinatura, empresa: empresa, plano: plano, data_fim: 5.days.ago.to_date)
        expect(assinatura.dias_restantes).to eq(0)
      end
    end
  end
end
