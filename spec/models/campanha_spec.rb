require 'rails_helper'

RSpec.describe Campanha, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    subject { build(:campanha, empresa: empresa) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of conteudo' do
      subject.conteudo = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of assunto for email channel' do
      subject.canal = :email
      subject.assunto = nil
      expect(subject).not_to be_valid
    end

    it 'allows empty assunto for whatsapp channel' do
      subject.canal = :whatsapp
      subject.assunto = nil
      expect(subject).to be_valid
    end
  end
end
