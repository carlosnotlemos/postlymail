require 'rails_helper'

RSpec.describe Cupom, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'callbacks' do
    let(:empresa) { create(:empresa) }

    it 'normalizes codigo to stripped uppercase' do
      cupom = build(:cupom, empresa: empresa, codigo: '  desc20off  ')
      cupom.valid?
      expect(cupom.codigo).to eq('DESC20OFF')
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:cupom, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of codigo' do
      subject.codigo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor' do
      subject.valor = 0
      expect(subject).not_to be_valid
    end

    it 'validates valor <= 100 when tipo is porcentagem' do
      subject.tipo = :porcentagem
      subject.valor = 101
      expect(subject).not_to be_valid
      expect(subject.errors[:valor]).to be_present

      subject.valor = 100
      expect(subject).to be_valid
    end

    it 'allows valor > 100 when tipo is valor_fixo' do
      subject.tipo = :valor_fixo
      subject.valor = 250
      expect(subject).to be_valid
    end

    it 'validates uniqueness of codigo scoped to empresa case-insensitively' do
      create(:cupom, empresa: empresa, codigo: 'DESC10')
      duplicate = build(:cupom, empresa: empresa, codigo: 'desc10')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:codigo]).to be_present
    end

    it 'allows same codigo in different empresas' do
      other_empresa = create(:empresa)
      create(:cupom, empresa: empresa, codigo: 'DESC10')
      other_coupon = build(:cupom, empresa: other_empresa, codigo: 'DESC10')
      expect(other_coupon).to be_valid
    end
  end
end
