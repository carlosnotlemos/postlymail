require 'rails_helper'

RSpec.describe DevolucaoItem, type: :model do
  describe 'associations' do
    it 'belongs to devolucao' do
      expect(described_class.reflect_on_association(:devolucao).macro).to eq :belongs_to
    end

    it 'belongs to venda_item' do
      expect(described_class.reflect_on_association(:venda_item).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:venda) { create(:venda) }
    let(:devolucao) { create(:devolucao, venda: venda, empresa: venda.empresa) }
    let(:venda_item) { create(:venda_item, venda: venda) }
    subject { build(:devolucao_item, devolucao: devolucao, venda_item: venda_item) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates numericality of quantidade > 0' do
      subject.quantidade = 0
      expect(subject).not_to be_valid
    end
  end
end
