require 'rails_helper'

RSpec.describe Devolucao, type: :model do
  describe 'associations' do
    it 'belongs to venda' do
      expect(described_class.reflect_on_association(:venda).macro).to eq :belongs_to
    end

    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:venda) { create(:venda) }
    subject { build(:devolucao, venda: venda, empresa: venda.empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of tipo' do
      subject.tipo = nil
      expect(subject).not_to be_valid
    end

    it 'validates numericality of valor_estornado >= 0' do
      subject.valor_estornado = -10
      expect(subject).not_to be_valid
    end

    it 'sets data_devolucao automatically before validation on create' do
      dev = Devolucao.new(venda: venda, empresa: venda.empresa, tipo: :estorno_dinheiro)
      dev.valid?
      expect(dev.data_devolucao).to be_present
    end
  end
end
