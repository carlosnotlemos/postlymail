require 'rails_helper'

RSpec.describe EstoqueMovimentacao, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to variacao_produto' do
      expect(described_class.reflect_on_association(:variacao_produto).macro).to eq :belongs_to
    end

    it 'belongs to usuario optionally' do
      assoc = described_class.reflect_on_association(:usuario)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end

    it 'belongs to origem polymorphically and optionally' do
      assoc = described_class.reflect_on_association(:origem)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:polymorphic]).to be true
      expect(assoc.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:variacao) { create(:variacao_produto) }
    subject { build(:estoque_movimentacao, empresa: empresa, variacao_produto: variacao) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of tipo' do
      subject.tipo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of quantidade > 0' do
      subject.quantidade = 0
      expect(subject).not_to be_valid
    end
  end
end
