require 'rails_helper'

RSpec.describe Convite, type: :model do
  describe 'associations' do
    it 'belongs to empresa' do
      expect(described_class.reflect_on_association(:empresa).macro).to eq :belongs_to
    end

    it 'belongs to convidado_por' do
      assoc = described_class.reflect_on_association(:convidado_por)
      expect(assoc.macro).to eq :belongs_to
      expect(assoc.options[:class_name]).to eq "Usuario"
    end
  end

  describe 'validations' do
    let(:empresa) { create(:empresa) }
    let(:usuario) { create(:usuario) }
    subject { build(:convite, empresa: empresa, convidado_por: usuario) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'generates a secure token automatically' do
      subject.valid?
      expect(subject.token).to be_present
    end

    it 'sets default expiration date' do
      convite = Convite.new(empresa: empresa, convidado_por: usuario, email: 'novo@exemplo.com', papel: :atendente)
      convite.valid?
      expect(convite.expira_em).to be_present
    end

    it 'validates email format' do
      subject.email = 'invalido'
      expect(subject).not_to be_valid
    end

    it 'prevents duplicate pending invites for the same empresa and email' do
      create(:convite, empresa: empresa, email: 'mesmo@exemplo.com', aceito_em: nil)
      duplicate = build(:convite, empresa: empresa, email: 'mesmo@exemplo.com')
      expect(duplicate).not_to be_valid
    end

    it 'allows invite if previous invite was already accepted' do
      create(:convite, empresa: empresa, email: 'mesmo@exemplo.com', aceito_em: 1.day.ago)
      new_invite = build(:convite, empresa: empresa, email: 'mesmo@exemplo.com')
      expect(new_invite).to be_valid
    end
  end
end
