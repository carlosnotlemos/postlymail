# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ProcessarService, type: :service do
  describe '.call' do
    let(:payload_resend) do
      {
        'type' => 'email.delivered',
        'data' => {
          'email_id' => 're_test_999'
        }
      }
    end

    let!(:webhook_log) do
      create(
        :webhook_log,
        provedor: :resend,
        payload: payload_resend,
        status: :pendente,
        evento: nil,
        identificador_externo: nil
      )
    end

    context 'com fallback padrão do orquestrador (provedor sem handler especializado ainda)' do
      it 'processa com sucesso, extrai metadados e atualiza o status para processado' do
        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(resultado.data[:status]).to eq(:processado)
        expect(resultado.data[:evento]).to eq('email.delivered')
        expect(resultado.data[:identificador_externo]).to eq('re_test_999')

        webhook_log.reload
        expect(webhook_log.processado?).to be true
        expect(webhook_log.evento).to eq('email.delivered')
        expect(webhook_log.identificador_externo).to eq('re_test_999')
        expect(webhook_log.processado_em).to be_present
        expect(webhook_log.mensagem_erro).to be_nil
      end

      it 'resolve o webhook log por ID numérico' do
        resultado = described_class.call(id: webhook_log.id)

        expect(resultado).to be_success
        expect(webhook_log.reload.processado?).to be true
      end

      it 'cria e processa o webhook_log a partir de provedor e payload' do
        resultado = described_class.call(
          provedor: :resend,
          payload: { 'type' => 'email.bounced', 'data' => { 'email_id' => 're_bounce_123' } }
        )

        expect(resultado).to be_success
        novo_log = resultado.data[:webhook_log]
        expect(novo_log).to be_persisted
        expect(novo_log.provedor).to eq('resend')
        expect(novo_log.evento).to eq('email.bounced')
        expect(novo_log.identificador_externo).to eq('re_bounce_123')
        expect(novo_log.processado?).to be true
      end

      it 'executa fallback padrão quando a classe do handler não está definida' do
        allow_any_instance_of(String).to receive(:safe_constantize).and_return(nil)

        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(resultado.data[:status]).to eq(:processado)
        expect(webhook_log.reload.processado?).to be true
      end
    end

    context 'quando há handler especializado para o provedor (como Asaas)' do
      let(:fake_handler) { double('AsaasHandler') }
      let!(:webhook_log_asaas) do
        create(
          :webhook_log,
          provedor: :asaas,
          payload: { 'event' => 'PAYMENT_RECEIVED', 'payment' => { 'id' => 'pay_123' } },
          status: :pendente
        )
      end

      before do
        stub_const('Webhooks::Asaas::ProcessarService', fake_handler)
      end

      it 'delega para o handler específico do provedor quando ele existe' do
        expect(fake_handler).to receive(:call).with(webhook_log: webhook_log_asaas).and_return(
          ApplicationService::Result.new(success: true, data: { acao: :pagamento_confirmado })
        )

        resultado = described_class.call(webhook_log: webhook_log_asaas)

        expect(resultado).to be_success
        expect(resultado.data[:status]).to eq(:processado)
        expect(resultado.data[:detalhes]).to eq({ acao: :pagamento_confirmado })
        expect(webhook_log_asaas.reload.processado?).to be true
      end

      it 'marca como falhou quando o handler retorna falha' do
        expect(fake_handler).to receive(:call).with(webhook_log: webhook_log_asaas).and_return(
          ApplicationService::Result.new(success: false, error: 'Fatura não encontrada no banco', error_code: :invoice_not_found)
        )

        resultado = described_class.call(webhook_log: webhook_log_asaas)

        expect(resultado).to be_failure
        expect(resultado.error).to eq('Fatura não encontrada no banco')

        webhook_log_asaas.reload
        expect(webhook_log_asaas.falhou?).to be true
        expect(webhook_log_asaas.mensagem_erro).to eq('Fatura não encontrada no banco')
      end

      it 'captura exceções e marca o webhook como falhou' do
        allow(fake_handler).to receive(:call).and_raise(StandardError.new('Falha de conexão com gateway'))

        resultado = described_class.call(webhook_log: webhook_log_asaas)

        expect(resultado).to be_failure
        expect(resultado.error).to include('Falha de conexão com gateway')

        webhook_log_asaas.reload
        expect(webhook_log_asaas.falhou?).to be true
        expect(webhook_log_asaas.mensagem_erro).to include('Falha de conexão com gateway')
      end
    end

    context 'idempotência e detecção de duplicidade' do
      it 'não processa novamente se já estiver com status processado' do
        webhook_log.update!(status: :processado, processado_em: 1.hour.ago)

        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(resultado.data[:ja_processado]).to be true
        expect(resultado.data[:mensagem]).to include('já foi processado')
      end

      it 'processa novamente se forçar for true' do
        webhook_log.update!(status: :processado, processado_em: 1.hour.ago)

        resultado = described_class.call(webhook_log: webhook_log, forcar: true)

        expect(resultado).to be_success
        expect(resultado.data[:ja_processado]).to be_nil
        expect(resultado.data[:status]).to eq(:processado)
      end

      it 'marca como duplicado_ignorado se outro webhook com mesmo identificador já foi processado' do
        create(
          :webhook_log,
          provedor: :resend,
          identificador_externo: 're_test_999',
          status: :processado,
          payload: { 'id' => 're_test_999' }
        )

        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(resultado.data[:duplicado]).to be true
        expect(resultado.data[:status]).to eq(:duplicado_ignorado)
        expect(webhook_log.reload.duplicado_ignorado?).to be true
      end

      it 'retorna sucesso imediatamente se o webhook_log já estiver como duplicado_ignorado' do
        webhook_log.update!(status: :duplicado_ignorado)

        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(resultado.data[:ignorado]).to be true
        expect(resultado.data[:status]).to eq(:duplicado_ignorado)
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando o webhook_log não é encontrado' do
        resultado = described_class.call(webhook_log: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:webhook_log_not_found)
      end

      it 'falha quando o payload está vazio' do
        webhook_log.update_column(:payload, {})

        resultado = described_class.call(webhook_log: webhook_log)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:payload_missing)
      end
    end
  end
end
