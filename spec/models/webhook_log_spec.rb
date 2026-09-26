require 'rails_helper'

RSpec.describe WebhookLog, type: :model do
  describe 'validations' do
    subject { build(:webhook_log) }

    it 'is valid with valid attributes' do
      expect(subject).to be_valid
    end

    it 'validates presence of provedor' do
      subject.provedor = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of status' do
      subject.status = nil
      expect(subject).not_to be_valid
    end

    it 'validates presence of payload' do
      subject.payload = nil
      expect(subject).not_to be_valid
    end

    it 'validates uniqueness of identificador_externo scoped to provedor' do
      create(:webhook_log, provedor: :asaas, identificador_externo: 'id_123')
      duplicate = build(:webhook_log, provedor: :asaas, identificador_externo: 'id_123')
      expect(duplicate).not_to be_valid

      other_provider = build(:webhook_log, provedor: :resend, identificador_externo: 'id_123')
      expect(other_provider).to be_valid
    end
  end
end
