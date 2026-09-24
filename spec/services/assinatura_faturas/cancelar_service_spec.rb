# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssinaturaFaturas::CancelarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'minha-empresa', ativo: true) }
  let!(:plano) { create(:plano, identificador: :pro, valor_mensal: 99.90, ativo: true) }
  let!(:assinatura) do
    create(
      :assinatura,
      empresa: empresa,
      plano: plano,
      status: :ativa,
      ciclo: :mensal,
      valor: 99.90,
      data_inicio: Date.current,
      data_fim: 1.month.from_now.to_date
    )
  end
  let!(:fatura) do
    create(
      :assinatura_fatura,
      assinatura: assinatura,
      status: :pendente,
      valor: 99.90,
      data_vencimento: 5.days.from_now.to_date,
      gateway_id: 'gw_fat_999'
    )
  end

  describe '.call' do
    context 'quando o cancelamento é realizado com sucesso' do
      it 'atualiza o status para cancelada e registra metadados de cancelamento' do
        resultado = described_class.call(
          fatura: fatura,
          motivo: 'Solicitação do cliente'
        )

        expect(resultado).to be_success
        fatura_atualizada = resultado.data[:fatura]
        expect(fatura_atualizada.cancelada?).to be true
        expect(fatura_atualizada.metadados['motivo_cancelamento']).to eq('Solicitação do cliente')
        expect(fatura_atualizada.metadados['cancelado_em']).to be_present
        expect(resultado.data[:cancelado]).to be true
        expect(resultado.data[:ja_estava_cancelada]).to be false
      end

      it 'cancela com segurança mesmo quando a fatura tiver metadados nil' do
        fatura.metadados = nil

        resultado = described_class.call(
          fatura: fatura,
          motivo: 'Fatura nula cancelada'
        )

        expect(resultado).to be_success
        expect(resultado.data[:fatura].metadados['motivo_cancelamento']).to eq('Fatura nula cancelada')
        expect(resultado.data[:fatura].metadados['cancelado_em']).to be_present
      end

      it 'resolve a fatura por ID e por gateway_id' do
        res_id = described_class.call(fatura: fatura.id)
        expect(res_id).to be_success

        fatura2 = create(:assinatura_fatura, assinatura: assinatura, gateway_id: 'gw_cancelar_gw')
        res_gw = described_class.call(gateway_id: 'gw_cancelar_gw')
        expect(res_gw).to be_success
        expect(res_gw.data[:fatura].id).to eq(fatura2.id)
      end
    end

    context 'idempotência' do
      before do
        fatura.update!(status: :cancelada)
      end

      it 'retorna sucesso quando ignorar_se_cancelada é true' do
        resultado = described_class.call(fatura: fatura, ignorar_se_cancelada: true)

        expect(resultado).to be_success
        expect(resultado.data[:cancelado]).to be false
        expect(resultado.data[:ja_estava_cancelada]).to be true
      end

      it 'retorna erro quando ignorar_se_cancelada é false' do
        resultado = described_class.call(fatura: fatura, ignorar_se_cancelada: false)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invoice_already_cancelled)
      end
    end

    context 'proteção contra cancelamento de fatura já paga' do
      before do
        fatura.update!(status: :paga, data_pagamento: Time.current)
      end

      it 'bloqueia o cancelamento por padrão' do
        resultado = described_class.call(fatura: fatura)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_cancel_paid_invoice)
      end

      it 'permite o cancelamento/estorno quando explicitamente autorizado' do
        resultado = described_class.call(fatura: fatura, permitir_se_paga: true, motivo: 'Estorno aprovado')

        expect(resultado).to be_success
        expect(fatura.reload.cancelada?).to be true
        expect(fatura.metadados['motivo_cancelamento']).to eq('Estorno aprovado')
      end
    end

    context 'validações e casos de erro' do
      it 'retorna erro quando a fatura não é encontrada' do
        resultado = described_class.call(fatura: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invoice_not_found)
      end

      it 'retorna erro quando a fatura pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(fatura: fatura, empresa: outra_empresa)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end
    end

    context 'aliases do serviço' do
      it 'funciona através de AssinaturaFaturas::AnularService' do
        res = AssinaturaFaturas::AnularService.call(fatura: fatura)
        expect(res).to be_success
      end

      it 'funciona através de AssinaturaFaturas::EstornarService' do
        fatura.update!(status: :pendente)
        res = AssinaturaFaturas::EstornarService.call(fatura: fatura)
        expect(res).to be_success
      end

      it 'funciona através de Assinaturas::CancelarFaturaService' do
        fatura.update!(status: :pendente)
        res = Assinaturas::CancelarFaturaService.call(fatura: fatura)
        expect(res).to be_success
      end
    end
  end
end
