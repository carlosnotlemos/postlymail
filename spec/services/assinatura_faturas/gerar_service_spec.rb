# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssinaturaFaturas::GerarService, type: :service do
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

  describe '.call' do
    context 'quando os parâmetros são válidos' do
      it 'gera uma fatura pendente com valores padrões derivados da assinatura' do
        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_success
        fatura = resultado.data[:fatura]
        expect(fatura).to be_persisted
        expect(fatura.assinatura).to eq(assinatura)
        expect(fatura.valor).to eq(99.90)
        expect(fatura.pendente?).to be true
        expect(fatura.data_vencimento).to eq(assinatura.data_inicio)
        expect(fatura.metadados).to eq({})
      end

      it 'permite especificar valor customizado e data de vencimento' do
        resultado = described_class.call(
          assinatura: assinatura,
          valor: '150,50',
          data_vencimento: 10.days.from_now.to_date,
          gateway_id: 'fat_gw_100',
          metadados: { 'link_boleto' => 'https://exemplo.com/boleto.pdf' }
        )

        expect(resultado).to be_success
        fatura = resultado.data[:fatura]
        expect(fatura.valor).to eq(150.50)
        expect(fatura.data_vencimento).to eq(10.days.from_now.to_date)
        expect(fatura.gateway_id).to eq('fat_gw_100')
        expect(fatura.metadados['link_boleto']).to eq('https://exemplo.com/boleto.pdf')
      end

      it 'calcula o vencimento automaticamente baseado na última fatura' do
        create(:assinatura_fatura, assinatura: assinatura, data_vencimento: Date.current)

        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_success
        fatura = resultado.data[:fatura]
        expect(fatura.data_vencimento).to eq(Date.current + 1.month)
      end

      it 'resolve a assinatura a partir da empresa quando omitida' do
        resultado = described_class.call(empresa: empresa)

        expect(resultado).to be_success
        expect(resultado.data[:assinatura]).to eq(assinatura)
      end

      it 'resolve polimorficamente por IDs numéricos e strings' do
        resultado = described_class.call(
          assinatura: assinatura.id.to_s,
          empresa: empresa.slug
        )

        expect(resultado).to be_success
        expect(resultado.data[:fatura]).to be_persisted
      end

      it 'gera a fatura já como paga e ativa assinatura pendente' do
        assinatura.update!(status: :pendente, data_fim: nil)

        resultado = described_class.call(
          assinatura: assinatura,
          marcar_como_paga: true
        )

        expect(resultado).to be_success
        fatura = resultado.data[:fatura]
        expect(fatura.paga?).to be true
        expect(fatura.data_pagamento).to be_present

        assinatura.reload
        expect(assinatura.ativa?).to be true
        expect(assinatura.data_fim).to be_present
      end
    end

    context 'validações e casos de erro' do
      it 'retorna erro quando a assinatura não é informada nem encontrada' do
        resultado = described_class.call(assinatura: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:subscription_not_found)
      end

      it 'retorna erro quando a empresa informada não existe' do
        resultado = described_class.call(empresa: 'empresa-inexistente')

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'retorna erro quando a empresa informada não é dona da assinatura' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(assinatura: assinatura, empresa: outra_empresa)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'retorna erro quando a empresa está inativa' do
        empresa.update!(ativo: false)

        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
      end

      it 'retorna erro quando a assinatura está cancelada e não há permissão explícita' do
        assinatura.update!(status: :cancelada, data_cancelamento: Time.current)

        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:subscription_cancelled)
      end

      it 'permite gerar fatura para assinatura cancelada quando permitido explicitamente' do
        assinatura.update!(status: :cancelada, data_cancelamento: Time.current)

        resultado = described_class.call(assinatura: assinatura, permitir_assinatura_cancelada: true)

        expect(resultado).to be_success
      end

      it 'retorna erro quando o gateway_id já existe' do
        create(:assinatura_fatura, assinatura: assinatura, gateway_id: 'gw_duplicado')

        resultado = described_class.call(assinatura: assinatura, gateway_id: 'gw_duplicado')

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:gateway_id_already_exists)
      end

      it 'retorna erro quando o valor é negativo' do
        resultado = described_class.call(assinatura: assinatura, valor: -50.0)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_amount)
      end
    end

    context 'aliases do serviço' do
      it 'funciona através de AssinaturaFaturas::SalvarService' do
        res = AssinaturaFaturas::SalvarService.call(assinatura: assinatura)
        expect(res).to be_success
      end

      it 'funciona através de AssinaturaFaturas::CriarService' do
        res = AssinaturaFaturas::CriarService.call(assinatura: assinatura)
        expect(res).to be_success
      end

      it 'funciona através de Assinaturas::GerarFaturaService' do
        res = Assinaturas::GerarFaturaService.call(assinatura: assinatura)
        expect(res).to be_success
      end
    end
  end
end
