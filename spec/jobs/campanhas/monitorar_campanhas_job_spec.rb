# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::MonitorarCampanhasJob, type: :job do
  let!(:empresa) { create(:empresa, slug: 'loja-monitor', ativo: true) }
  let!(:cliente) { create(:cliente, empresa: empresa) }

  describe '#perform' do
    it 'está configurado na fila default' do
      expect(described_class.new.queue_name).to eq('default')
    end

    context 'com campanhas agendadas prontas para envio' do
      let!(:campanha_passada) do
        create(:campanha, empresa: empresa, status: :agendada, data_envio: 5.minutes.ago)
      end
      let!(:campanha_futura) do
        create(:campanha, empresa: empresa, status: :agendada, data_envio: 1.hour.from_now)
      end

      it 'enfileira disparo apenas para a campanha cujo horário já chegou' do
        expect(Campanhas::DispararCampanhaJob).to receive(:perform_later).with(campanha_passada.id)
        expect(Campanhas::DispararCampanhaJob).not_to receive(:perform_later).with(campanha_futura.id)

        described_class.perform_now
      end
    end

    context 'com reconciliação de campanhas enviando' do
      it 'não conclui campanha recém-iniciada (proteção temporal contra condição de corrida)' do
        campanha_recente = create(
          :campanha,
          empresa: empresa,
          status: :enviando,
          updated_at: 10.seconds.ago
        )

        described_class.perform_now

        expect(campanha_recente.reload.enviando?).to be true
      end

      it 'marca como concluida se a campanha estiver estável (> 2 min) e não possuir disparos na_fila' do
        campanha_estavel = create(
          :campanha,
          empresa: empresa,
          status: :enviando,
          updated_at: 3.minutes.ago
        )
        create(:disparo, campanha: campanha_estavel, cliente: cliente, status: :entregue)

        described_class.perform_now

        expect(campanha_estavel.reload.concluida?).to be true
        expect(campanha_estavel.data_envio).to be_present
      end

      it 'preserva o data_envio original ao reconciliar e não o sobrescreve com Time.current' do
        data_original = 1.hour.ago.change(usec: 0)
        campanha_com_data = create(
          :campanha,
          empresa: empresa,
          status: :enviando,
          data_envio: data_original,
          updated_at: 5.minutes.ago
        )
        create(:disparo, campanha: campanha_com_data, cliente: cliente, status: :entregue)

        described_class.perform_now

        campanha_com_data.reload
        expect(campanha_com_data.concluida?).to be true
        expect(campanha_com_data.data_envio).to eq(data_original)
      end

      it 'mantém enviando se ainda houver disparos na_fila mesmo após a margem de estabilidade' do
        campanha_com_pendencias = create(
          :campanha,
          empresa: empresa,
          status: :enviando,
          updated_at: 10.minutes.ago
        )
        create(:disparo, campanha: campanha_com_pendencias, cliente: cliente, status: :na_fila)

        described_class.perform_now

        expect(campanha_com_pendencias.reload.enviando?).to be true
      end
    end
  end
end
