require 'rails_helper'

RSpec.describe Cupom, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
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

    it 'validates uniqueness of codigo scoped to empresa' do
      create(:cupom, empresa: empresa, codigo: 'DESC10')
      duplicate = build(:cupom, empresa: empresa, codigo: 'DESC10')
      expect(duplicate).not_to be_valid
    end

    it 'allows same codigo in different empresas' do
      other_empresa = create(:empresa)
      create(:cupom, empresa: empresa, codigo: 'DESC10')
      other_coupon = build(:cupom, empresa: other_empresa, codigo: 'DESC10')
      expect(other_coupon).to be_valid
    end
  end
end
