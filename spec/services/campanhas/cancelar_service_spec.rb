# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::CancelarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'promo-store', ativo: true) }
  let!(:campanha) { create(:campanha, empresa: empresa, status: :rascunho) }
  let!(:cliente) { create(:cliente, empresa: empresa) }

  describe '.call' do
    context 'quando cancelando com sucesso' do
      it 'cancela a campanha e marca disparos pendentes na fila como cancelados' do
        disparo1 = create(:disparo, campanha: campanha, cliente: cliente, status: :na_fila)
        disparo2 = create(:disparo, campanha: campanha, cliente: cliente, status: :enviado)

        resultado = described_class.call(
          campanha: campanha,
          motivo: 'Planejamento comercial alterado'
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelada]).to be true
        expect(resultado.data[:ja_estava_cancelada]).to be false
        expect(resultado.data[:motivo]).to eq('Planejamento comercial alterado')
        expect(resultado.data[:disparos_cancelados_count]).to eq(1)

        expect(campanha.reload.cancelada?).to be true
        expect(disparo1.reload.status).to eq('cancelado')
        expect(disparo1.reload.cancelado?).to be true
        expect(disparo1.mensagem_erro).to include('Planejamento comercial alterado')
        expect(disparo2.reload.status).to eq('enviado')
      end

      it 'permite resolver a campanha por ID' do
        resultado = described_class.call(
          campanha: campanha.id
        )

        expect(resultado).to be_success
        expect(campanha.reload.cancelada?).to be true
      end

      it 'permite manter disparos pendentes se cancelar_disparos_pendentes for false' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :na_fila)

        resultado = described_class.call(
          campanha: campanha,
          cancelar_disparos_pendentes: false
        )

        expect(resultado).to be_success
        expect(campanha.reload.cancelada?).to be true
        expect(disparo.reload.status).to eq('na_fila')
      end

      it 'é idempotente quando já cancelada e ignorar_se_cancelada é true' do
        campanha.update!(status: :cancelada)

        resultado = described_class.call(
          campanha: campanha,
          ignorar_se_cancelada: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelada]).to be false
        expect(resultado.data[:ja_estava_cancelada]).to be true
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando campanha não é encontrada' do
        resultado = described_class.call(
          campanha: 999_999
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_not_found)
      end

      it 'falha quando a campanha pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          campanha: campanha,
          empresa: outra_empresa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando tenta cancelar uma campanha já concluída' do
        campanha.update!(status: :concluida)

        resultado = described_class.call(
          campanha: campanha
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_cancel_completed_campaign)
      end

      it 'falha quando a campanha já está cancelada e ignorar_se_cancelada é false' do
        campanha.update!(status: :cancelada)

        resultado = described_class.call(
          campanha: campanha
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_already_cancelled)
      end
    end

    context 'aliases' do
      it 'funciona através de Campanhas::AnularService' do
        resultado = Campanhas::AnularService.call(campanha: campanha)
        expect(resultado).to be_success
        expect(campanha.reload.cancelada?).to be true
      end
    end
  end
end
