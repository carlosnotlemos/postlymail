# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ProcessarWebhookJob, type: :job do
  let!(:webhook_log) do
    create(
      :webhook_log,
      provedor: :asaas,
      status: :pendente,
      payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_123' } }
    )
  end

  describe '#perform' do
    it 'processa o log pendente na fila urgent com lock de linha' do
      expect(described_class.new.queue_name).to eq('urgent')

      expect(webhook_log).to receive(:with_lock).and_call_original
      allow(WebhookLog).to receive(:find_by).with(id: webhook_log.id).and_return(webhook_log)

      expect(Webhooks::ProcessarService).to receive(:call).with(webhook_log: webhook_log).and_call_original

      described_class.perform_now(webhook_log.id)

      expect(webhook_log.reload.processado?).to be true
    end

    it 'ignora logs inexistentes ou já processados' do
      webhook_log.update!(status: :processado)

      expect(Webhooks::ProcessarService).not_to receive(:call)

      described_class.perform_now(webhook_log.id)
      described_class.perform_now(999_999)
    end

    it 'ignora logs marcados como duplicado_ignorado dentro do lock' do
      webhook_log.update!(status: :duplicado_ignorado)

      expect(Webhooks::ProcessarService).not_to receive(:call)

      described_class.perform_now(webhook_log.id)
    end

    context 'tratamento de falhas definitivas vs transitórias' do
      it 'conclui sem levantar exceção quando a falha é definitiva de payload/negócio' do
        resultado_falha = ApplicationService::Result.new(
          success: false,
          error: 'Payload corrompido',
          error_code: :payload_missing
        )

        expect(Webhooks::ProcessarService).to receive(:call).with(webhook_log: webhook_log).and_return(resultado_falha)
        expect(Rails.logger).to receive(:warn).with(/Falha definitiva no WebhookLog/)

        expect {
          described_class.perform_now(webhook_log.id)
        }.not_to raise_error
      end

      it 'levanta TransientError para disparar retry quando a falha for temporária de infraestrutura' do
        resultado_transitório = ApplicationService::Result.new(
          success: false,
          error: 'Gateway Asaas fora do ar momentaneamente',
          error_code: :gateway_unavailable
        )

        expect(Webhooks::ProcessarService).to receive(:call).with(webhook_log: webhook_log).and_return(resultado_transitório)

        expect {
          described_class.perform_now(webhook_log.id)
        }.to raise_error(Webhooks::TransientError, /Erro transitório no webhook/)
      end
    end
  end
end
