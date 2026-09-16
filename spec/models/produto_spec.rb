require 'rails_helper'

RSpec.describe Produto, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to produto_categoria optionally' do
      assoc = described_class.reflect_on_association(:produto_categoria)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:optional]).to be true
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:produto, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end
  end
end
