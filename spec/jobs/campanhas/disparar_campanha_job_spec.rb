# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::DispararCampanhaJob, type: :job do
  let!(:empresa) { create(:empresa, slug: 'loja-disparar-job', ativo: true) }
  let!(:cliente1) { create(:cliente, empresa: empresa, aceita_marketing: true, email: 'cli1@exemplo.com') }
  let!(:cliente2) { create(:cliente, empresa: empresa, aceita_marketing: true, email: 'cli2@exemplo.com') }
  let!(:campanha) { create(:campanha, empresa: empresa, canal: :email, status: :rascunho) }

  describe '#perform' do
    it 'está configurado na fila bulk' do
      expect(described_class.new.queue_name).to eq('bulk')
    end

    it 'executa com lock atômico (SELECT FOR UPDATE) na campanha' do
      expect(campanha).to receive(:with_lock).and_call_original
      allow(Campanha).to receive(:find_by).with(id: campanha.id).and_return(campanha)

      described_class.perform_now(campanha.id)

      expect(campanha.reload.enviando?).to be true
    end

    it 'enfileira os disparos gerados em lote utilizando ActiveJob.perform_all_later' do
      expect(ActiveJob).to receive(:perform_all_later) do |jobs|
        expect(jobs.size).to eq(2)
        expect(jobs).to all(be_a(Disparos::ProcessarDisparoJob))
        job_disparo_ids = jobs.map { |j| j.arguments.first }
        expect(job_disparo_ids).to match_array(campanha.disparos.pluck(:id))
      end

      described_class.perform_now(campanha.id)

      expect(campanha.reload.enviando?).to be true
      expect(campanha.disparos.count).to eq(2)
      expect(campanha.disparos.pluck(:status).uniq).to eq([ 'na_fila' ])
    end

    context 'proteção contra cliques duplos e concorrência' do
      it 'não processa se a campanha já estiver enviando' do
        campanha.update!(status: :enviando)

        expect(Campanhas::DispararService).not_to receive(:call)
        expect(ActiveJob).not_to receive(:perform_all_later)

        described_class.perform_now(campanha.id)
      end

      it 'não processa se a campanha já estiver concluída e sem forçar' do
        campanha.update!(status: :concluida)

        expect(Campanhas::DispararService).not_to receive(:call)
        expect(ActiveJob).not_to receive(:perform_all_later)

        described_class.perform_now(campanha.id)
      end

      it 'reprocessa se forçar for passado mesmo com a campanha concluída' do
        campanha.update!(status: :concluida)

        expect(Campanhas::DispararService).to receive(:call).and_call_original
        expect(ActiveJob).to receive(:perform_all_later)

        described_class.perform_now(campanha.id, forcar: true)
      end

      it 'ignora registro inexistente' do
        expect(Campanhas::DispararService).not_to receive(:call)

        expect {
          described_class.perform_now(999_999)
        }.not_to raise_error
      end
    end

    context 'campanha com zero contatos no segmento' do
      before do
        empresa.clientes.update_all(aceita_marketing: false)
      end

      it 'transiciona a campanha diretamente para concluída sem enfileirar nenhum job' do
        expect(ActiveJob).not_to receive(:perform_all_later)

        described_class.perform_now(campanha.id)

        campanha.reload
        expect(campanha.concluida?).to be true
        expect(campanha.data_envio).to be_present
        expect(campanha.disparos.count).to eq(0)
      end
    end
  end
end
