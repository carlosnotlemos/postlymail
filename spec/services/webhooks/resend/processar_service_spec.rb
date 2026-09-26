# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Resend::ProcessarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-resend', ativo: true) }
  let!(:campanha) { create(:campanha, empresa: empresa, canal: :email) }
  let!(:cliente) { create(:cliente, empresa: empresa, email: 'cliente@exemplo.com', aceita_marketing: true) }
  let!(:disparo) do
    create(
      :disparo,
      campanha: campanha,
      cliente: cliente,
      destinatario: 'cliente@exemplo.com',
      identificador_externo: 're_msg_123',
      status: :enviado
    )
  end

  describe '.call para eventos do Resend' do
    context 'quando recebe email.delivered' do
      let(:payload) do
        {
          'type' => 'email.delivered',
          'created_at' => '2026-09-26T17:00:00.000Z',
          'data' => {
            'email_id' => 're_msg_123',
            'to' => [ 'cliente@exemplo.com' ]
          }
        }
      end

      it 'atualiza o disparo para entregue' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:disparo_entregue)
        expect(disparo.reload.entregue?).to be true
      end
    end

    context 'quando recebe email.bounced' do
      let(:payload) do
        {
          'type' => 'email.bounced',
          'data' => {
            'email_id' => 're_msg_123',
            'to' => [ 'cliente@exemplo.com' ],
            'bounce' => {
              'message' => 'Caixa postal do destinatário cheia'
            }
          }
        }
      end

      it 'atualiza o disparo para falhou, registra o motivo e desativa marketing do cliente' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:disparo_falhou)

        disparo.reload
        expect(disparo.falhou?).to be true
        expect(disparo.mensagem_erro).to eq('Caixa postal do destinatário cheia')

        expect(cliente.reload.aceita_marketing?).to be false
      end
    end

    context 'quando recebe email.complained (reclamação de spam)' do
      let(:payload) do
        {
          'type' => 'email.complained',
          'data' => {
            'email_id' => 're_msg_123',
            'to' => [ 'cliente@exemplo.com' ]
          }
        }
      end

      it 'atualiza o disparo para rejeitado e desativa marketing do cliente' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:disparo_rejeitado)

        disparo.reload
        expect(disparo.rejeitado?).to be true
        expect(disparo.mensagem_erro).to include('spam')

        expect(cliente.reload.aceita_marketing?).to be false
      end
    end

    context 'quando recebe email.sent com disparo ainda na fila' do
      before do
        disparo.update!(status: :na_fila)
      end

      let(:payload) do
        {
          'type' => 'email.sent',
          'data' => {
            'email_id' => 're_msg_123',
            'to' => [ 'cliente@exemplo.com' ]
          }
        }
      end

      it 'atualiza o disparo para enviado' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:disparo_enviado)
        expect(disparo.reload.enviado?).to be true
      end
    end

    context 'quando recebe email.opened ou email.clicked' do
      let(:payload) do
        {
          'type' => 'email.opened',
          'data' => {
            'email_id' => 're_msg_123'
          }
        }
      end

      it 'confirma o disparo como entregue e reporta o engajamento' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:acao]).to eq(:disparo_aberto)
        expect(disparo.reload.entregue?).to be true
      end
    end

    context 'quando o disparo não é localizado' do
      let(:payload) do
        {
          'type' => 'email.delivered',
          'data' => {
            'email_id' => 're_inexistente_999'
          }
        }
      end

      it 'retorna sucesso indicando que o disparo não foi localizado' do
        resultado = described_class.call(payload: payload)

        expect(resultado).to be_success
        expect(resultado.data[:recurso_localizado]).to be false
      end
    end

    context 'integração com Webhooks::ProcessarService' do
      it 'é invocado automaticamente pelo orquestrador geral para provedor resend' do
        webhook_log = create(
          :webhook_log,
          provedor: :resend,
          payload: {
            'type' => 'email.delivered',
            'data' => {
              'email_id' => 're_msg_123'
            }
          }
        )

        resultado = Webhooks::ProcessarService.call(webhook_log: webhook_log)

        expect(resultado).to be_success
        expect(webhook_log.reload.processado?).to be true
        expect(disparo.reload.entregue?).to be true
      end
    end
  end
end
