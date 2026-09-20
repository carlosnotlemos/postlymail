require 'rails_helper'

RSpec.describe Estoque, type: :model do
  describe 'associations' do
    it 'belongs to variacao_produto' do
      expect(described_class.reflect_on_association(:variacao_produto).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:variacao) { create(:variacao_produto) }
    subject { build(:estoque, variacao_produto: variacao) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates numericality of quantidade only integer and >= 0' do
      subject.quantidade = 1.5
      expect(subject).not_to be_valid

      subject.quantidade = -1
      expect(subject).not_to be_valid
      expect(subject.errors[:quantidade]).to be_present

      subject.quantidade = 0
      expect(subject).to be_valid
    end

    it 'validates numericality of quantidade_minima >= 0' do
      subject.quantidade_minima = -1
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of variacao_produto_id (1:1)' do
      create(:estoque, variacao_produto: variacao)
      duplicate = build(:estoque, variacao_produto: variacao)
      expect(duplicate).not_to be_valid
    end
  end
end
