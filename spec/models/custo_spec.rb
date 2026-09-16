require 'rails_helper'

RSpec.describe Custo, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to venda optionally' do
      assoc = described_class.reflect_on_association(:venda)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:custo, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of categoria' do
      subject.categoria = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of data_custo' do
      subject.data_custo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor >= 0' do
      subject.valor = -1
      expect(subject).not_to be_valid
    end
  end
end
