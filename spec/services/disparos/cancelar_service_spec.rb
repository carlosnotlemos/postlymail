# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Disparos::CancelarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'canc-store', ativo: true) }
  let!(:campanha) { create(:campanha, empresa: empresa) }
  let!(:cliente) { create(:cliente, empresa: empresa) }

  describe '.call' do
    context 'quando cancelando com sucesso' do
      it 'marca disparo pendente como cancelado com motivo' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :na_fila)

        resultado = described_class.call(
          disparo: disparo,
          motivo: 'Cliente solicitou opt-out antes do envio'
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be true
        expect(resultado.data[:ja_estava_cancelado]).to be false
        expect(disparo.reload.cancelado?).to be true
        expect(disparo.mensagem_erro).to eq('Cliente solicitou opt-out antes do envio')
      end

      it 'resolve o disparo por ID' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :na_fila)

        resultado = described_class.call(disparo: disparo.id)

        expect(resultado).to be_success
        expect(disparo.reload.cancelado?).to be true
      end

      it 'é idempotente quando ignorar_se_cancelado é true' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :cancelado)

        resultado = described_class.call(
          disparo: disparo,
          ignorar_se_cancelado: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be false
        expect(resultado.data[:ja_estava_cancelado]).to be true
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando o disparo não existe' do
        resultado = described_class.call(disparo: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_not_found)
      end

      it 'falha ao tentar cancelar um disparo já enviado' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :enviado)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_cancel_sent_disparo)
      end

      it 'falha ao tentar cancelar um disparo já entregue' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :entregue)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_cancel_sent_disparo)
      end

      it 'falha quando já cancelado e ignorar_se_cancelado é false' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :cancelado)

        resultado = described_class.call(disparo: disparo)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_already_cancelled)
      end
    end

    context 'aliases' do
      it 'funciona através de Disparos::AnularService' do
        disparo = create(:disparo, campanha: campanha, cliente: cliente, status: :na_fila)

        resultado = Disparos::AnularService.call(disparo: disparo)

        expect(resultado).to be_success
        expect(disparo.reload.cancelado?).to be true
      end
    end
  end
end
