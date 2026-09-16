require 'rails_helper'

RSpec.describe VendaItem, type: :model do
  describe 'associations' do
    it 'belongs to venda' do
      expect(described_class.reflect_on_association(:venda).macro).to eq :belongs_to
    end

    it 'belongs to variacao_produto' do
      expect(described_class.reflect_on_association(:variacao_produto).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:venda) { create(:venda) }
    let(:variacao) { create(:variacao_produto) }
    subject { build(:venda_item, venda: venda, variacao_produto: variacao, valor_unitario: 50.0, quantidade: 2) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'calculates subtotal automatically' do
      subject.valid?
      expect(subject.subtotal).to eq 100.0
    end

    it 'validates numericality of quantidade > 0' do
      subject.quantidade = 0
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor_unitario >= 0' do
      subject.valor_unitario = -5
      expect(subject).not_to be_valid
    end
  end
end
