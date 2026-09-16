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
  end
end
