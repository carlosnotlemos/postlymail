require 'rails_helper'

RSpec.describe ProdutoInsumo, type: :model do
  describe 'associations' do
    it 'belongs to variacao_produto' do
      expect(described_class.reflect_on_association(:variacao_produto).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:variacao) { create(:variacao_produto) }
    subject { build(:produto_insumo, variacao_produto: variacao) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor >= 0' do
      subject.valor = -1
      expect(subject).not_to be_valid
    end
  end
end
