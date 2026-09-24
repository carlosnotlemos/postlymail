# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Convites::CancelarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'filial') }
  let!(:gestor) { create(:usuario, email: 'gestor@filial.com') }
  let!(:convite) do
    create(:convite, empresa: empresa, convidado_por: gestor, email: 'cancelar@exemplo.com', papel: :atendente)
  end

  describe '.call' do
    context 'quando cancelando o convite com sucesso via soft delete' do
      it 'marca cancelado_em, preserva o registro no banco e retorna sucesso' do
        resultado = described_class.call(
          convite: convite,
          motivo: 'Colaborador desistiu da vaga'
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be true
        expect(resultado.data[:ja_estava_cancelado]).to be false
        expect(resultado.data[:motivo]).to eq('Colaborador desistiu da vaga')
        expect(resultado.data[:cancelado_em]).to be_present

        expect(convite.reload.cancelado?).to be true
        expect(convite.cancelado_em).to be_present
        expect(Convite.exists?(id: convite.id)).to be true
        expect(Convite.cancelados).to include(convite)
        expect(Convite.pendentes).not_to include(convite)
      end

      it 'permite cancelar resolvendo por token' do
        resultado = described_class.call(
          token: convite.token
        )

        expect(resultado).to be_success
        expect(convite.reload.cancelado?).to be true
      end

      it 'permite cancelar resolvendo por ID' do
        resultado = described_class.call(
          convite: convite.id
        )

        expect(resultado).to be_success
        expect(convite.reload.cancelado?).to be true
      end

      it 'permite cancelar passando empresa explícita correspondente' do
        resultado = described_class.call(
          convite: convite,
          empresa: empresa
        )

        expect(resultado).to be_success
        expect(convite.reload.cancelado?).to be true
      end

      it 'aceita data_cancelamento customizada' do
        data_passada = 2.hours.ago
        resultado = described_class.call(
          convite: convite,
          data_cancelamento: data_passada
        )

        expect(resultado).to be_success
        expect(convite.reload.cancelado_em).to be_within(2.seconds).of(data_passada)
      end
    end

    context 'validações de domínio e idempotência' do
      it 'falha quando o convite não é encontrado' do
        resultado = described_class.call(
          convite: 999_999
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_not_found)
      end

      it 'falha quando o convite pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          convite: convite,
          empresa: outra_empresa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando tenta cancelar convite já aceito' do
        convite.update!(aceito_em: 1.day.ago)

        resultado = described_class.call(
          convite: convite
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_already_accepted)
      end

      it 'falha quando o convite já está cancelado e ignorar_se_cancelado é false' do
        convite.update!(cancelado_em: 1.hour.ago)

        resultado = described_class.call(
          convite: convite
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_already_cancelled)
      end

      it 'retorna sucesso idempotente quando já cancelado e ignorar_se_cancelado é true' do
        timestamp = 1.hour.ago
        convite.update!(cancelado_em: timestamp)

        resultado = described_class.call(
          convite: convite,
          ignorar_se_cancelado: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be false
        expect(resultado.data[:ja_estava_cancelado]).to be true
        expect(resultado.data[:cancelado_em]).to be_within(1.second).of(timestamp)
      end
    end

    context 'aliases do serviço' do
      it 'funciona com RevogarService e ExcluirService' do
        c1 = create(:convite, empresa: empresa, convidado_por: gestor)
        c2 = create(:convite, empresa: empresa, convidado_por: gestor)

        res1 = Convites::RevogarService.call(convite: c1)
        res2 = Convites::ExcluirService.call(convite: c2)

        expect(res1).to be_success
        expect(res2).to be_success
        expect(c1.reload.cancelado?).to be true
        expect(c2.reload.cancelado?).to be true
      end
    end
  end
end
