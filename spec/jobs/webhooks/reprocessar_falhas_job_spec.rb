# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ReprocessarFalhasJob, type: :job do
  let!(:log_falho_recente) do
    create(
      :webhook_log,
      provedor: :asaas,
      status: :falhou,
      created_at: 2.hours.ago,
      mensagem_erro: 'Timeout de conexao com gateway',
      payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_falho_1' } }
    )
  end

  let!(:log_falho_antigo) do
    create(
      :webhook_log,
      provedor: :asaas,
      status: :falhou,
      created_at: 48.hours.ago,
      mensagem_erro: 'Erro de conexao',
      payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_falho_2' } }
    )
  end

  let!(:log_processado) do
    create(
      :webhook_log,
      provedor: :asaas,
      status: :processado,
      created_at: 1.hour.ago,
      payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_proc' } }
    )
  end

  describe '#perform' do
    it 'está configurado na fila default' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'reprocessa logs falhos recentes e incrementa o contador de tentativas' do
      expect(Webhooks::ProcessarService).to receive(:call).with(webhook_log: log_falho_recente, forcar: true).and_return(
        ApplicationService::Result.new(success: true, data: { status: :processado })
      )

      described_class.perform_now(24)

      expect(log_falho_recente.reload.payload['_tentativas_reprocessamento']).to eq(1)
      expect(log_falho_recente.payload['_ultimo_reprocessamento_em']).to be_present
    end

    it 'marca como descarte definitivo quando atinge o limite máximo de tentativas (3x)' do
      log_falho_recente.update_columns(
        payload: log_falho_recente.payload.merge('_tentativas_reprocessamento' => 3)
      )

      expect(Webhooks::ProcessarService).not_to receive(:call)

      described_class.perform_now(24)

      log_falho_recente.reload
      expect(log_falho_recente.payload['_descarte_definitivo']).to be true
      expect(log_falho_recente.mensagem_erro).to include('Descarte Definitivo: 3 tentativas esgotadas')
    end

    it 'ignora logs com erros estruturais não recuperáveis' do
      log_irrecuperavel = create(
        :webhook_log,
        provedor: :asaas,
        status: :falhou,
        created_at: 1.hour.ago,
        mensagem_erro: 'Payload do webhook está vazio (empty_payload)',
        payload: {}
      )

      expect(Webhooks::ProcessarService).not_to receive(:call).with(webhook_log: log_irrecuperavel, forcar: true)

      described_class.perform_now(24)
    end

    it 'não interrompe o lote se um dos registros levantar exceção inesperada' do
      segundo_log_falho = create(
        :webhook_log,
        provedor: :asaas,
        status: :falhou,
        created_at: 30.minutes.ago,
        mensagem_erro: 'Erro transitório',
        payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_segundo' } }
      )

      # Simula erro no primeiro log
      allow(Webhooks::ProcessarService).to receive(:call).with(webhook_log: log_falho_recente, forcar: true).and_raise(StandardError.new('Crash inesperado'))

      # Garante que o segundo log ainda seja processado
      expect(Webhooks::ProcessarService).to receive(:call).with(webhook_log: segundo_log_falho, forcar: true).and_return(
        ApplicationService::Result.new(success: true, data: { status: :processado })
      )

      expect {
        described_class.perform_now(24)
      }.not_to raise_error
    end
  end
end
