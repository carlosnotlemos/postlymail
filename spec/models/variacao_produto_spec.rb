require 'rails_helper'

RSpec.describe VariacaoProduto, type: :model do
  describe 'associations' do
    it 'belongs to produto' do
      expect(described_class.reflect_on_association(:produto).macro).to eq :belongs_to
    end

    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'callbacks' do
    let(:empresa) { create(:empresa) }
    let(:produto) { create(:produto, empresa: empresa) }

    it 'sets empresa_id automatically from produto' do
      variacao = build(:variacao_produto, produto: produto, empresa: nil)
      variacao.valid?
      expect(variacao.empresa_id).to eq(empresa.id)
    end

    it 'sanitizes sku by stripping and upcasing' do
      variacao = build(:variacao_produto, produto: produto, sku: '  cam-ovr-g  ')
      variacao.valid?
      expect(variacao.sku).to eq('CAM-OVR-G')
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:produto) { create(:produto, empresa: empresa) }
    subject { build(:variacao_produto, produto: produto, empresa: empresa) }

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

    it 'validates uniqueness of sku scoped to empresa case-insensitively' do
      create(:variacao_produto, produto: produto, empresa: empresa, sku: 'SKU-123')
      duplicate = build(:variacao_produto, produto: produto, empresa: empresa, sku: 'sku-123')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:sku]).to be_present
    end

    it 'allows same sku in different empresas' do
      other_empresa = create(:empresa)
      other_produto = create(:produto, empresa: other_empresa)
      create(:variacao_produto, produto: produto, empresa: empresa, sku: 'SKU-123')

      other_variacao = build(:variacao_produto, produto: other_produto, empresa: other_empresa, sku: 'SKU-123')
      expect(other_variacao).to be_valid
    end

    it 'validates presence of sku' do
      subject.sku = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:sku]).to be_present

      subject.sku = ''
      expect(subject).not_to be_valid
      expect(subject.errors[:sku]).to be_present
    end
  end
end
