require 'rails_helper'

RSpec.describe Venda, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to cliente' do
      expect(described_class.reflect_on_association(:cliente).macro).to eq :belongs_to
    end

    it 'belongs to usuario optionally' do
      assoc = described_class.reflect_on_association(:usuario)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end

    it 'belongs to cupom optionally' do
      assoc = described_class.reflect_on_association(:cupom)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:cliente) { create(:cliente, empresa: empresa) }
    subject { build(:venda, empresa: empresa, cliente: cliente) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'generates a codigo_pedido automatically' do
      venda = Venda.new(empresa: empresa, cliente: cliente, tipo_entrega: :retirada, status: :pendente)
      venda.valid?
      expect(venda.codigo_pedido).to be_present
    end

    it 'validates uniqueness of codigo_pedido scoped to empresa' do
      create(:venda, empresa: empresa, cliente: cliente, codigo_pedido: 'FT-PED123')
      duplicate = build(:venda, empresa: empresa, cliente: cliente, codigo_pedido: 'FT-PED123')
      expect(duplicate).not_to be_valid
    end

    it 'requires motivo_cancelamento if status is cancelada' do
      subject.status = :cancelada
      subject.motivo_cancelamento = nil
      expect(subject).not_to be_valid

      subject.motivo_cancelamento = 'Cliente desistiu da compra'
      expect(subject).to be_valid
    end

    it 'sets default 0.0 for desconto_manual and desconto_cupom when nil' do
      venda = build(:venda, empresa: empresa, cliente: cliente, desconto_manual: nil, desconto_cupom: nil)
      venda.valid?
      expect(venda.desconto_manual).to eq 0.0
      expect(venda.desconto_cupom).to eq 0.0
    end

    it 'validates numericality of desconto_manual >= 0' do
      subject.desconto_manual = -5.0
      expect(subject).not_to be_valid
      expect(subject.errors[:desconto_manual]).to be_present
    end

    it 'validates numericality of desconto_cupom >= 0' do
      subject.desconto_cupom = -10.0
      expect(subject).not_to be_valid
      expect(subject.errors[:desconto_cupom]).to be_present
    end

    it 'validates that valor_desconto does not exceed subtotal_produtos' do
      subject.subtotal_produtos = 100.0
      subject.valor_desconto = 120.0
      expect(subject).not_to be_valid
      expect(subject.errors[:valor_desconto]).to include("não pode ser maior que o subtotal dos produtos")

      subject.valor_desconto = 100.0
      expect(subject).to be_valid
    end
  end
end
