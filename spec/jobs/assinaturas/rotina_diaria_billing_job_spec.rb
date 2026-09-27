# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Assinaturas::RotinaDiariaBillingJob, type: :job do
  let!(:empresa) { create(:empresa, slug: 'loja-billing-job', ativo: true) }
  let!(:plano) { create(:plano, nome: 'Premium', identificador: 10, valor_mensal: 199.0) }
  let!(:assinatura) do
    create(
      :assinatura,
      empresa: empresa,
      plano: plano,
      status: :ativa,
      valor: 199.0,
      ciclo: :mensal,
      data_fim: 3.days.from_now.to_date
    )
  end

  describe '#perform' do
    it 'está configurado na fila default' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'executa com lock atômico (SELECT FOR UPDATE) na assinatura' do
      expect(assinatura).to receive(:with_lock).and_call_original
      allow(Assinatura).to receive_message_chain(:ativas, :where).and_return([ assinatura ])

      described_class.perform_now
    end

    it 'executa a rotina de inadimplência e gera faturas para quem expira em até 7 dias' do
      expect(Assinaturas::ProcessarInadimplentesService).to receive(:call).and_call_original

      expect {
        described_class.perform_now
      }.to change(AssinaturaFatura, :count).by(1)

      nova_fatura = assinatura.faturas.last
      expect(nova_fatura.pendente?).to be true
      expect(nova_fatura.valor).to eq(199.0)
      expect(nova_fatura.data_vencimento).to eq(assinatura.data_fim)
    end

    it 'não duplica fatura se já existir fatura pendente para a data' do
      create(
        :assinatura_fatura,
        assinatura: assinatura,
        status: :pendente,
        data_vencimento: assinatura.data_fim,
        valor: 199.0
      )

      expect {
        described_class.perform_now
      }.not_to change(AssinaturaFatura, :count)
    end

    it 'não duplica fatura se o cliente já pagou o ciclo adiantado (fatura com status :paga)' do
      create(
        :assinatura_fatura,
        assinatura: assinatura,
        status: :paga,
        data_vencimento: assinatura.data_fim,
        valor: 199.0
      )

      expect {
        described_class.perform_now
      }.not_to change(AssinaturaFatura, :count)
    end

    it 'isola erros individuais por assinatura garantindo que uma falha não aborte o faturamento das demais' do
      empresa2 = create(:empresa, slug: 'loja-billing-job-2', ativo: true)
      assinatura2 = create(
        :assinatura,
        empresa: empresa2,
        plano: plano,
        status: :ativa,
        valor: 299.0,
        ciclo: :mensal,
        data_fim: 3.days.from_now.to_date
      )

      # Simula erro fatal ao gerar a fatura da primeira assinatura
      allow(AssinaturaFaturas::GerarService).to receive(:call).with(
        hash_including(assinatura: assinatura)
      ).and_raise(StandardError, 'Falha de comunicação com gateway de pagamento')

      # A segunda assinatura deve ser gerada normalmente
      expect(AssinaturaFaturas::GerarService).to receive(:call).with(
        hash_including(assinatura: assinatura2)
      ).and_call_original

      expect(Rails.logger).to receive(:error).with(/Falha isolada na assinatura ##{assinatura.id}/)

      expect {
        described_class.perform_now
      }.to change(AssinaturaFatura, :count).by(1)

      expect(assinatura2.faturas.count).to eq(1)
    end

    it 'isola exceções no processar_inadimplencia sem interromper a geração de faturas' do
      allow(Assinaturas::ProcessarInadimplentesService).to receive(:call).and_raise(
        StandardError, 'Timeout no banco de dados durante checagem de inadimplência'
      )

      expect(Rails.logger).to receive(:error).with(/Erro ao processar rotina de inadimplência/)

      expect {
        described_class.perform_now
      }.to change(AssinaturaFatura, :count).by(1)
    end
  end
end
