# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Disparos::AtualizarStatusService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'status-store', ativo: true) }
  let!(:campanha) { create(:campanha, empresa: empresa) }
  let!(:cliente) { create(:cliente, empresa: empresa) }
  let!(:disparo) { create(:disparo, campanha: campanha, cliente: cliente, status: :enviado, identificador_externo: 'ext_track_123') }

  describe '.call' do
    context 'quando atualizando status com sucesso' do
      it 'atualiza para entregue' do
        resultado = described_class.call(
          disparo: disparo,
          status: :entregue
        )

        expect(resultado).to be_success
        expect(disparo.reload.entregue?).to be true
        expect(disparo.status).to eq('entregue')
      end

      it 'atualiza para falhou com mensagem de erro' do
        resultado = described_class.call(
          disparo: disparo,
          status: :falhou,
          mensagem_erro: 'Caixa de entrada cheia'
        )

        expect(resultado).to be_success
        expect(disparo.reload.falhou?).to be true
        expect(disparo.mensagem_erro).to eq('Caixa de entrada cheia')
      end

      it 'localiza o disparo pelo identificador_externo' do
        resultado = described_class.call(
          identificador_externo: 'ext_track_123',
          status: :entregue
        )

        expect(resultado).to be_success
        expect(disparo.reload.entregue?).to be true
      end

      it 'resolve o disparo por ID numérico' do
        resultado = described_class.call(
          disparo: disparo.id,
          status: :entregue
        )

        expect(resultado).to be_success
        expect(disparo.reload.entregue?).to be true
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando o disparo não é encontrado' do
        resultado = described_class.call(
          disparo: 999_999,
          status: :entregue
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_not_found)
      end

      it 'falha quando o status informado é inválido' do
        resultado = described_class.call(
          disparo: disparo,
          status: :status_inventado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_status)
      end

      it 'impede transição inválida de entregue para falhou ou cancelado' do
        disparo.update!(status: :entregue)

        res_falhou = described_class.call(disparo: disparo, status: :falhou)
        expect(res_falhou).to be_failure
        expect(res_falhou.error_code).to eq(:invalid_status_transition)

        res_cancelado = described_class.call(disparo: disparo, status: :cancelado)
        expect(res_cancelado).to be_failure
        expect(res_cancelado.error_code).to eq(:invalid_status_transition)
      end

      it 'impede transição de cancelado para enviado' do
        disparo.update!(status: :cancelado)

        resultado = described_class.call(disparo: disparo, status: :enviado)
        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_status_transition)
      end

      it 'permite transição idêntica por idempotência' do
        disparo.update!(status: :entregue)

        resultado = described_class.call(disparo: disparo, status: :entregue)
        expect(resultado).to be_success
        expect(disparo.reload.entregue?).to be true
      end

      it 'permite qualquer transição quando forcar for true' do
        disparo.update!(status: :entregue)

        resultado = described_class.call(
          disparo: disparo,
          status: :na_fila,
          forcar: true
        )

        expect(resultado).to be_success
        expect(disparo.reload.na_fila?).to be true
      end
    end

    context 'aliases' do
      it 'funciona através de Disparos::AtualizarStatusWebhookService' do
        resultado = Disparos::AtualizarStatusWebhookService.call(
          identificador_externo: 'ext_track_123',
          status: :entregue
        )

        expect(resultado).to be_success
        expect(disparo.reload.entregue?).to be true
      end
    end
  end
end
