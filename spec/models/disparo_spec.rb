require 'rails_helper'

RSpec.describe Disparo, type: :model do
  describe 'associations' do
    it 'belongs to campanha' do
      expect(described_class.reflect_on_association(:campanha).macro).to eq :belongs_to
    end

    it 'belongs to cliente' do
      expect(described_class.reflect_on_association(:cliente).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    let(:campanha) { create(:campanha) }
    let(:cliente) { create(:cliente, empresa: campanha.empresa) }
    subject { build(:disparo, campanha: campanha, cliente: cliente) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of destinatario' do
      subject.destinatario = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
    end
  end
end
