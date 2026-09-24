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

    it 'defines papeis enum mapping with papels alias' do
      expect(described_class.papeis).to eq({ 'atendente' => 0, 'estoquista' => 1, 'gerente' => 2, 'proprietario' => 3 })
      expect(described_class.papels).to eq(described_class.papeis)
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

    it 'allows invite if previous invite was cancelled (soft deleted)' do
      create(:convite, :cancelado, empresa: empresa, email: 'mesmo@exemplo.com')
      new_invite = build(:convite, empresa: empresa, email: 'mesmo@exemplo.com')
      expect(new_invite).to be_valid
    end

    it 'aliases deleted_at to cancelado_em' do
      convite = build(:convite, cancelado_em: 2.hours.ago)
      expect(convite.deleted_at).to eq(convite.cancelado_em)
      convite.deleted_at = 1.hour.ago
      expect(convite.cancelado_em).to eq(convite.deleted_at)
    end

    it 'sanitizes email by stripping and downcasing' do
      convite = build(:convite, empresa: empresa, convidado_por: usuario, email: '  Teste.Convite@Exemplo.COM  ')
      convite.valid?
      expect(convite.email).to eq('teste.convite@exemplo.com')
    end
  end

  describe 'scopes and status methods' do
    let(:empresa) { create(:empresa) }
    let(:usuario) { create(:usuario) }

    let!(:convite_pendente) do
      create(:convite, empresa: empresa, convidado_por: usuario, papel: :atendente, expira_em: 5.days.from_now, aceito_em: nil, cancelado_em: nil)
    end
    let!(:convite_aceito) do
      create(:convite, :aceito, empresa: empresa, convidado_por: usuario, papel: :gerente)
    end
    let!(:convite_expirado) do
      create(:convite, :expirado, empresa: empresa, convidado_por: usuario, papel: :estoquista)
    end
    let!(:convite_cancelado) do
      create(:convite, :cancelado, empresa: empresa, convidado_por: usuario, papel: :proprietario)
    end

    it 'filters pending invites correctly' do
      expect(described_class.pendentes).to include(convite_pendente)
      expect(described_class.pendentes).not_to include(convite_aceito, convite_expirado, convite_cancelado)
    end

    it 'filters accepted invites correctly' do
      expect(described_class.aceitos).to include(convite_aceito)
      expect(described_class.aceitos).not_to include(convite_pendente, convite_expirado, convite_cancelado)
    end

    it 'filters expired invites correctly' do
      expect(described_class.expirados).to include(convite_expirado)
      expect(described_class.expirados).not_to include(convite_pendente, convite_aceito, convite_cancelado)
    end

    it 'filters cancelled invites correctly' do
      expect(described_class.cancelados).to include(convite_cancelado)
      expect(described_class.cancelados).not_to include(convite_pendente, convite_aceito, convite_expirado)
    end

    it 'filters non-cancelled invites correctly' do
      expect(described_class.nao_cancelados).to include(convite_pendente, convite_aceito, convite_expirado)
      expect(described_class.nao_cancelados).not_to include(convite_cancelado)
    end

    it 'filters by role correctly' do
      expect(described_class.por_papel(:atendente)).to include(convite_pendente)
      expect(described_class.por_papel(:gerente)).to include(convite_aceito)
      expect(described_class.por_papel(:proprietario)).to include(convite_cancelado)
    end

    it 'evaluates helper methods accurately' do
      expect(convite_pendente.pendente?).to be true
      expect(convite_pendente.expirado?).to be false
      expect(convite_pendente.aceito?).to be false
      expect(convite_pendente.cancelado?).to be false

      expect(convite_aceito.pendente?).to be false
      expect(convite_aceito.expirado?).to be false
      expect(convite_aceito.aceito?).to be true
      expect(convite_aceito.cancelado?).to be false

      expect(convite_expirado.pendente?).to be false
      expect(convite_expirado.expirado?).to be true
      expect(convite_expirado.aceito?).to be false
      expect(convite_expirado.cancelado?).to be false

      expect(convite_cancelado.pendente?).to be false
      expect(convite_cancelado.expirado?).to be false
      expect(convite_cancelado.aceito?).to be false
      expect(convite_cancelado.cancelado?).to be true
    end
  end
end
