# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Assinaturas::CancelarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:plano) { create(:plano, identificador: :start) }
  let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano, status: :ativa) }

  describe '.call' do
    context 'quando cancelando uma assinatura ativa' do
      it 'cancela a assinatura com sucesso e preenche data_cancelamento' do
        resultado = described_class.call(
          assinatura: assinatura,
          motivo: 'Cliente solicitou encerramento'
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be true
        expect(resultado.data[:motivo]).to eq('Cliente solicitou encerramento')
        expect(resultado.data[:data_cancelamento]).to be_present

        assinatura.reload
        expect(assinatura.status).to eq('cancelada')
        expect(assinatura.data_cancelamento).to be_present
      end

      it 'aceita a assinatura como argumento posicional' do
        resultado = described_class.call(assinatura)

        expect(resultado).to be_success
        expect(assinatura.reload.status).to eq('cancelada')
      end

      it 'resolve a assinatura por ID numérico' do
        resultado = described_class.call(assinatura: assinatura.id)

        expect(resultado).to be_success
        expect(assinatura.reload.status).to eq('cancelada')
      end

      it 'libera a empresa para contratar uma nova assinatura ativa após o cancelamento' do
        described_class.call(assinatura: assinatura)

        nova_assinatura = build(:assinatura, empresa: empresa, plano: plano, status: :ativa)
        expect(nova_assinatura).to be_valid
      end
    end

    context 'quando resolvendo a assinatura a partir da empresa' do
      it 'cancela a assinatura ativa da empresa informada por instância' do
        resultado = described_class.call(empresa: empresa)

        expect(resultado).to be_success
        expect(resultado.data[:assinatura]).to eq(assinatura)
        expect(assinatura.reload.status).to eq('cancelada')
      end

      it 'cancela a assinatura ativa da empresa informada por slug' do
        resultado = described_class.call(empresa: empresa.slug)

        expect(resultado).to be_success
        expect(assinatura.reload.status).to eq('cancelada')
      end
    end

    context 'com cancelamento de faturas pendentes' do
      let!(:fatura_pendente) do
        AssinaturaFatura.create!(
          assinatura: assinatura,
          valor: 49.90,
          data_vencimento: 5.days.from_now.to_date,
          status: :pendente
        )
      end

      let!(:fatura_paga) do
        AssinaturaFatura.create!(
          assinatura: assinatura,
          valor: 49.90,
          data_vencimento: 25.days.ago.to_date,
          status: :paga,
          data_pagamento: 25.days.ago
        )
      end

      it 'cancela faturas pendentes por padrão' do
        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_success
        expect(resultado.data[:faturas_canceladas]).to eq(1)

        expect(fatura_pendente.reload.status).to eq('cancelada')
        expect(fatura_paga.reload.status).to eq('paga')
      end

      it 'não cancela faturas pendentes quando cancelar_faturas_pendentes for false' do
        resultado = described_class.call(
          assinatura: assinatura,
          cancelar_faturas_pendentes: false
        )

        expect(resultado).to be_success
        expect(resultado.data[:faturas_canceladas]).to eq(0)
        expect(fatura_pendente.reload.status).to eq('pendente')
      end
    end

    context 'quando a assinatura já se encontra cancelada' do
      before do
        assinatura.update!(status: :cancelada, data_cancelamento: 1.day.ago)
      end

      it 'falha por padrão indicando que a assinatura já está cancelada' do
        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:subscription_already_cancelled)
        expect(resultado.error).to include('já se encontra cancelada')
      end

      it 'retorna sucesso de forma idempotente quando ignorar_se_cancelada for true' do
        resultado = described_class.call(
          assinatura: assinatura,
          ignorar_se_cancelada: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be false
        expect(resultado.data[:ja_estava_cancelada]).to be true
      end
    end

    context 'validações e tratamento de erros' do
      it 'falha se a assinatura não for informada nem encontrada' do
        resultado = described_class.call(assinatura: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:subscription_not_found)
      end

      it 'falha se a assinatura não pertencer à empresa informada' do
        outra_empresa = create(:empresa, slug: 'outra-loja', email: 'outra@loja.com')

        resultado = described_class.call(
          assinatura: assinatura,
          empresa: outra_empresa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
        expect(resultado.error).to include('não pertence à empresa informada')
      end
    end

    context 'aliases' do
      it 'responde aos aliases EncerrarService e DesativarService' do
        expect(Assinaturas::EncerrarService).to eq(described_class)
        expect(Assinaturas::DesativarService).to eq(described_class)
      end
    end
  end
end
