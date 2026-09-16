require 'rails_helper'

RSpec.describe VariacaoProduto, type: :model do
  describe 'associations' do
    it 'belongs to produto' do
      expect(described_class.reflect_on_association(:produto).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:produto) { create(:produto) }
    subject { build(:variacao_produto, produto: produto) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates numericality of preco_base >= 0' do
      subject.preco_base = -1
      expect(subject).not_to be_valid
    end

    it 'validates numericality of preco_custo >= 0' do
      subject.preco_custo = -1
      expect(subject).not_to be_valid
    end
  end
end
