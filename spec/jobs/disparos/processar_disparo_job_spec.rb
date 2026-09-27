# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Disparos::ProcessarDisparoJob, type: :job do
  let!(:empresa) { create(:empresa, slug: 'loja-disparo-proc', ativo: true) }
  let!(:cliente) { create(:cliente, empresa: empresa, email: 'alvo@exemplo.com') }
  let!(:campanha) { create(:campanha, empresa: empresa, canal: :email, status: :enviando) }
  let!(:disparo) do
    create(
      :disparo,
      campanha: campanha,
      cliente: cliente,
      destinatario: 'alvo@exemplo.com',
      status: :na_fila
    )
  end

  describe '#perform' do
    it 'está configurado na fila bulk' do
      expect(described_class.new.queue_name).to eq('bulk')
    end

    it 'processa o disparo unitário com lock atômico (SELECT FOR UPDATE)' do
      expect(disparo).to receive(:with_lock).and_call_original
      allow(Disparo).to receive(:find_by).with(id: disparo.id).and_return(disparo)

      expect(Disparos::ProcessarService).to receive(:call).with(disparo: disparo).and_call_original

      described_class.perform_now(disparo.id)

      expect(disparo.reload.enviado?).to be true
      expect(disparo.enviado_em).to be_present
    end

    it 'ignora registro inexistente' do
      expect(Disparos::ProcessarService).not_to receive(:call)

      expect {
        described_class.perform_now(999_999)
      }.not_to raise_error
    end

    it 'ignora disparos já enviados, entregues, rejeitados ou cancelados (idempotência atômica)' do
      %i[enviado entregue rejeitado cancelado].each do |status_final|
        disparo.update_columns(status: Disparo.statuses[status_final])

        expect(Disparos::ProcessarService).not_to receive(:call)

        described_class.perform_now(disparo.id)
      end
    end

    context 'tratamento diferenciado de falhas (transitórias vs definitivas)' do
      it 'levanta TransientError para disparar retries automáticos quando a falha for temporária de rede/gateway' do
        resultado_transitorio = ApplicationService::Result.new(
          success: false,
          error: 'Rate limit do provedor excedido',
          error_code: :rate_limit_exceeded
        )

        expect(Disparos::ProcessarService).to receive(:call).with(disparo: disparo).and_return(resultado_transitorio)

        expect {
          described_class.perform_now(disparo.id)
        }.to raise_error(Disparos::TransientError, /Erro transitório no disparo/)
      end

      it 'conclui sem levantar exceção quando a falha for definitiva (destinatário malformado, hard bounce)' do
        resultado_definitivo = ApplicationService::Result.new(
          success: false,
          error: 'E-mail inexistente / hard bounce',
          error_code: :invalid_email
        )

        expect(Disparos::ProcessarService).to receive(:call).with(disparo: disparo).and_return(resultado_definitivo)
        expect(Rails.logger).to receive(:warn).with(/Falha definitiva no disparo/)

        expect {
          described_class.perform_now(disparo.id)
        }.not_to raise_error
      end
    end

    context 'conclusão da campanha pai em tempo real' do
      it 'marca a campanha como concluída quando o último disparo em fila for processado' do
        described_class.perform_now(disparo.id)

        campanha.reload
        expect(campanha.concluida?).to be true
        expect(campanha.data_envio).to be_present
      end

      it 'mantém a campanha como enviando se ainda existirem outros disparos na fila' do
        outro_cliente = create(:cliente, empresa: empresa, email: 'outro@exemplo.com')
        create(
          :disparo,
          campanha: campanha,
          cliente: outro_cliente,
          destinatario: 'outro@exemplo.com',
          status: :na_fila
        )

        described_class.perform_now(disparo.id)

        campanha.reload
        expect(campanha.enviando?).to be true
      end
    end
  end
end
