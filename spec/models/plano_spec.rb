require 'rails_helper'

RSpec.describe Plano, type: :model do
  describe 'validations' do
    subject { build(:plano, identificador: :start) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of nome' do
      subject.nome = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of identificador' do
      subject.identificador = nil
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of identificador' do
      create(:plano, identificador: :pro)
      duplicate = build(:plano, identificador: :pro)
      expect(duplicate).not_to be_valid
    end
  end
end
