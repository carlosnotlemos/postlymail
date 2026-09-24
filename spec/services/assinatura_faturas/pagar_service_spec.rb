# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssinaturaFaturas::PagarService, type: :service do
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
      gateway_id: 'gw_fat_123',
      metadados: { 'pix_code' => '12345' }
    )
  end

  describe '.call' do
    context 'quando a fatura é liquidada com sucesso' do
      it 'atualiza o status para paga e registra o timestamp de pagamento' do
        resultado = described_class.call(fatura: fatura)

        expect(resultado).to be_success
        fatura_atualizada = resultado.data[:fatura]
        expect(fatura_atualizada.paga?).to be true
        expect(fatura_atualizada.data_pagamento).to be_present
        expect(resultado.data[:ja_estava_paga]).to be false
      end

      it 'permite informar data de pagamento customizada e mesclar novos metadados' do
        data_custom = 1.hour.ago.change(usec: 0)

        resultado = described_class.call(
          fatura: fatura,
          data_pagamento: data_custom,
          metadados: { 'transacao_bancaria' => 'tx_987654' }
        )

        expect(resultado).to be_success
        fatura_atualizada = resultado.data[:fatura]
        expect(fatura_atualizada.data_pagamento).to be_within(1.second).of(data_custom)
        expect(fatura_atualizada.metadados['pix_code']).to eq('12345')
        expect(fatura_atualizada.metadados['transacao_bancaria']).to eq('tx_987654')
      end

      it 'mescla metadados com segurança mesmo quando a fatura tiver metadados nil' do
        fatura.metadados = nil

        resultado = described_class.call(
          fatura: fatura,
          metadados: { 'transacao_bancaria' => 'tx_987654' }
        )

        expect(resultado).to be_success
        expect(resultado.data[:fatura].metadados['transacao_bancaria']).to eq('tx_987654')
      end

      it 'resolve a fatura por ID e por gateway_id' do
        res_id = described_class.call(fatura: fatura.id)
        expect(res_id).to be_success

        fatura2 = create(:assinatura_fatura, assinatura: assinatura, gateway_id: 'gw_busca_direta')
        res_gw = described_class.call(gateway_id: 'gw_busca_direta')
        expect(res_gw).to be_success
        expect(res_gw.data[:fatura].id).to eq(fatura2.id)
      end

      it 'reativa assinatura suspensa ou atrasada' do
        assinatura.update!(status: :atrasada)

        resultado = described_class.call(fatura: fatura)

        expect(resultado).to be_success
        expect(resultado.data[:assinatura_reativada]).to be true
        expect(assinatura.reload.ativa?).to be true
      end

      it 'prorroga a vigência da assinatura com base no ciclo' do
        data_fim_original = assinatura.data_fim

        resultado = described_class.call(fatura: fatura, prorrogar_vigencia: true)

        expect(resultado).to be_success
        expect(resultado.data[:vigencia_prorrogada]).to be true
        expect(assinatura.reload.data_fim).to eq(data_fim_original + 1.month)
      end

      it 'permite desativar prorrogação de vigência' do
        data_fim_original = assinatura.data_fim

        resultado = described_class.call(fatura: fatura, prorrogar_vigencia: false)

        expect(resultado).to be_success
        expect(resultado.data[:vigencia_prorrogada]).to be false
        expect(assinatura.reload.data_fim).to eq(data_fim_original)
      end
    end

    context 'idempotência' do
      before do
        fatura.update!(status: :paga, data_pagamento: 1.day.ago)
      end

      it 'retorna sucesso quando ignorar_se_paga é true' do
        resultado = described_class.call(fatura: fatura, ignorar_se_paga: true)

        expect(resultado).to be_success
        expect(resultado.data[:ja_estava_paga]).to be true
      end

      it 'retorna erro quando ignorar_se_paga é false' do
        resultado = described_class.call(fatura: fatura, ignorar_se_paga: false)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invoice_already_paid)
      end
    end

    context 'validações e casos de erro' do
      it 'retorna erro quando a fatura não é encontrada' do
        resultado = described_class.call(fatura: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invoice_not_found)
      end

      it 'retorna erro quando a fatura está cancelada' do
        fatura.update!(status: :cancelada)

        resultado = described_class.call(fatura: fatura)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invoice_cancelled)
      end

      it 'retorna erro quando a fatura pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(fatura: fatura, empresa: outra_empresa)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end
    end

    context 'aliases do serviço' do
      it 'funciona através de AssinaturaFaturas::LiquidarService' do
        res = AssinaturaFaturas::LiquidarService.call(fatura: fatura)
        expect(res).to be_success
      end

      it 'funciona através de AssinaturaFaturas::ConfirmarPagamentoService' do
        fatura.update!(status: :pendente)
        res = AssinaturaFaturas::ConfirmarPagamentoService.call(fatura: fatura)
        expect(res).to be_success
      end

      it 'funciona através de AssinaturaFaturas::RegistrarPagamentoService' do
        fatura.update!(status: :pendente)
        res = AssinaturaFaturas::RegistrarPagamentoService.call(fatura: fatura)
        expect(res).to be_success
      end

      it 'funciona através de Assinaturas::PagarFaturaService' do
        fatura.update!(status: :pendente)
        res = Assinaturas::PagarFaturaService.call(fatura: fatura)
        expect(res).to be_success
      end
    end
  end
end
