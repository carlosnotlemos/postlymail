require 'rails_helper'

RSpec.describe ProdutoCategoria, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:produto_categoria, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence and format of slug' do
      subject.slug = nil
      expect(subject).not_to be_valid

      subject.slug = 'Slug Invalido!'
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of slug scoped to empresa' do
      create(:produto_categoria, empresa: empresa, slug: 'bones')
      duplicate = build(:produto_categoria, empresa: empresa, slug: 'bones')
      expect(duplicate).not_to be_valid
    end

    it 'allows same slug in different empresas' do
      other_empresa = create(:empresa)
      create(:produto_categoria, empresa: empresa, slug: 'bones')
      other_cat = build(:produto_categoria, empresa: other_empresa, slug: 'bones')
      expect(other_cat).to be_valid
    end
  end
end
