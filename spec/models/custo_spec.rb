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

    it 'validates that venda belongs to the same empresa' do
      outra_empresa = create(:empresa)
      venda_outra_empresa = create(:venda, empresa: outra_empresa)
      subject.venda = venda_outra_empresa

      expect(subject).not_to be_valid
      expect(subject.errors[:venda]).to include('deve pertencer à mesma empresa do custo')
    end

    it 'allows venda belonging to the same empresa' do
      venda_mesma_empresa = create(:venda, empresa: empresa)
      subject.venda = venda_mesma_empresa

      expect(subject).to be_valid
    end
  end

  describe 'scopes' do
    let(:empresa) { create(:empresa) }
    let(:venda) { create(:venda, empresa: empresa) }
    let!(:custo1) { create(:custo, empresa: empresa, categoria: :frete_entrega, valor: 50.0, data_custo: Date.current, venda: venda) }
    let!(:custo2) { create(:custo, empresa: empresa, categoria: :insumos_producao, valor: 100.0, data_custo: 5.days.ago, venda: nil) }

    it 'filters by por_categoria' do
      expect(described_class.por_categoria(:frete_entrega)).to contain_exactly(custo1)
    end

    it 'filters by por_periodo' do
      expect(described_class.por_periodo(1.day.ago, Date.current)).to contain_exactly(custo1)
    end

    it 'filters by com_venda and sem_venda' do
      expect(described_class.com_venda).to contain_exactly(custo1)
      expect(described_class.sem_venda).to contain_exactly(custo2)
    end
  end
end
