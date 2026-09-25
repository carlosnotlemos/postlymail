# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Assinaturas::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let!(:plano_start) { create(:plano, identificador: :start, valor_mensal: 49.90, ativo: true) }
  let!(:plano_pro) { create(:plano, identificador: :pro, valor_mensal: 99.90, ativo: true) }

  describe '.call' do
    context 'quando contratando uma nova assinatura' do
      let(:parametros_validos) do
        {
          ciclo: :mensal,
          status: :ativa,
          valor: 49.90,
          data_inicio: Date.current,
          data_fim: 1.month.from_now.to_date
        }
      end

      it 'cria a assinatura com sucesso vinculada à empresa e plano' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          atributos: parametros_validos
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        expect(assinatura).to be_persisted
        expect(assinatura.empresa).to eq(empresa)
        expect(assinatura.plano).to eq(plano_start)
        expect(assinatura.ciclo).to eq('mensal')
        expect(assinatura.status).to eq('ativa')
        expect(assinatura.valor).to eq(49.90)
        expect(assinatura.data_inicio).to eq(Date.current)
      end

      it 'aceita atributos diretamente via kwargs' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          ciclo: 'trimestral',
          status: 'ativa',
          valor: 140.00
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        expect(assinatura.ciclo).to eq('trimestral')
        expect(assinatura.valor).to eq(140.00)
      end

      it 'calcula valor e datas automaticamente quando omitidos para ciclo mensal' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          ciclo: :mensal
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        expect(assinatura.valor).to eq(49.90)
        expect(assinatura.data_inicio).to eq(Date.current)
        expect(assinatura.data_fim).to eq(Date.current + 1.month)
      end

      it 'calcula valor multiplicado por 3 e data final em 3 meses para ciclo trimestral' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          ciclo: :trimestral
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        expect(assinatura.valor).to eq(49.90 * 3)
        expect(assinatura.data_fim).to eq(Date.current + 3.months)
      end

      it 'calcula valor multiplicado por 12 e data final em 1 ano para ciclo anual' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          ciclo: :anual
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        expect(assinatura.valor).to eq(49.90 * 12)
        expect(assinatura.data_fim).to eq(Date.current + 1.year)
      end

      it 'normaliza valor monetário no formato brasileiro' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          valor: 'R$ 1.250,50'
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].valor).to eq(1250.50)
      end

      it 'gera fatura inicial quando gerar_fatura_inicial for true' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          gerar_fatura_inicial: true
        )

        expect(resultado).to be_success
        assinatura = resultado.data[:assinatura]
        fatura = resultado.data[:fatura]

        expect(fatura).to be_present
        expect(fatura).to be_persisted
        expect(fatura.assinatura).to eq(assinatura)
        expect(fatura.valor).to eq(assinatura.valor)
        expect(fatura.status).to eq('pendente')
        expect(fatura.data_vencimento).to eq(assinatura.data_inicio)
      end
    end

    context 'com resolução polimórfica de empresa e plano' do
      it 'resolve empresa por ID numérico' do
        resultado = described_class.call(
          empresa: empresa.id,
          plano: plano_start
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].empresa).to eq(empresa)
      end

      it 'resolve empresa por slug' do
        resultado = described_class.call(
          empresa: empresa.slug,
          plano: plano_start
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].empresa).to eq(empresa)
      end

      it 'resolve plano por ID numérico' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start.id
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].plano).to eq(plano_start)
      end

      it 'resolve plano por identificador em symbol ou string' do
        resultado = described_class.call(
          empresa: empresa,
          plano: :pro
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].plano).to eq(plano_pro)
      end
    end

    context 'quando a empresa já possui uma assinatura ativa' do
      let!(:assinatura_ativa_atual) do
        create(:assinatura, empresa: empresa, plano: plano_start, status: :ativa)
      end

      it 'bloqueia a criação de uma segunda assinatura ativa retornando erro amigável' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          status: :ativa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:company_already_has_active_subscription)
        expect(resultado.error).to include('já possui uma assinatura ativa')
        expect(Assinatura.ativas.where(empresa: empresa).count).to eq(1)
      end

      it 'permite criar uma nova assinatura com status pendente mesmo já tendo uma ativa' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          status: :pendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:assinatura].status).to eq('pendente')
        expect(Assinatura.ativas.where(empresa: empresa).count).to eq(1)
      end

      it 'substitui a assinatura anterior com substituir_atual: true cancelando a antiga' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          substituir_atual: true
        )

        expect(resultado).to be_success
        nova_assinatura = resultado.data[:assinatura]
        expect(nova_assinatura).to be_persisted
        expect(nova_assinatura.plano).to eq(plano_pro)
        expect(nova_assinatura.status).to eq('ativa')

        assinatura_ativa_atual.reload
        expect(assinatura_ativa_atual.status).to eq('cancelada')
        expect(assinatura_ativa_atual.data_cancelamento).to be_present

        expect(resultado.data[:assinatura_substituida]).to eq(assinatura_ativa_atual)
        expect(Assinatura.ativas.where(empresa: empresa).count).to eq(1)
      end

      it 'aceita cancelar_anterior como alias para substituir_atual' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          cancelar_anterior: true
        )

        expect(resultado).to be_success
        expect(assinatura_ativa_atual.reload.status).to eq('cancelada')
      end
    end

    context 'quando a empresa possui assinatura atrasada ou suspensa (migração de inadimplente)' do
      let!(:assinatura_atrasada) do
        create(:assinatura, empresa: empresa, plano: plano_start, status: :atrasada)
      end

      let!(:fatura_pendente_antiga) do
        create(:assinatura_fatura, assinatura: assinatura_atrasada, status: :pendente, data_vencimento: 5.days.ago.to_date)
      end

      it 'permite migrar substituindo a assinatura atrasada e cancelando faturas pendentes por padrão' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          substituir_atual: true
        )

        expect(resultado).to be_success
        nova = resultado.data[:assinatura]
        expect(nova.status).to eq('ativa')
        expect(nova.plano).to eq(plano_pro)

        assinatura_atrasada.reload
        expect(assinatura_atrasada.status).to eq('cancelada')
        expect(assinatura_atrasada.data_cancelamento).to be_present
        expect(fatura_pendente_antiga.reload.status).to eq('cancelada')
      end

      it 'permite manter faturas anteriores abertas se cancelar_faturas_anteriores for false' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          substituir_atual: true,
          cancelar_faturas_anteriores: false
        )

        expect(resultado).to be_success
        expect(fatura_pendente_antiga.reload.status).to eq('pendente')
      end

      it 'permite migrar quando a assinatura estiver suspensa e a empresa inativa, reativando a empresa' do
        assinatura_atrasada.update!(status: :suspensa)
        empresa.update!(ativo: false)

        resultado = described_class.call(
          empresa: empresa,
          plano: plano_pro,
          substituir_atual: true
        )

        expect(resultado).to be_success
        nova = resultado.data[:assinatura]
        expect(nova.status).to eq('ativa')
        expect(assinatura_atrasada.reload.status).to eq('cancelada')
        expect(empresa.reload.ativo).to be true
      end
    end

    context 'quando atualizando uma assinatura existente' do
      let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano_start, valor: 49.90, ciclo: :mensal) }

      it 'atualiza plano e valor da assinatura' do
        resultado = described_class.call(
          assinatura: assinatura,
          plano: plano_pro,
          valor: 89.90
        )

        expect(resultado).to be_success
        assinatura.reload
        expect(assinatura.plano).to eq(plano_pro)
        expect(assinatura.valor).to eq(89.90)
      end

      it 'resolve assinatura por ID numérico' do
        resultado = described_class.call(
          assinatura: assinatura.id,
          valor: 55.00
        )

        expect(resultado).to be_success
        expect(assinatura.reload.valor).to eq(55.00)
      end

      it 'preenche data_cancelamento automaticamente ao alterar status para cancelada' do
        resultado = described_class.call(
          assinatura: assinatura,
          status: :cancelada
        )

        expect(resultado).to be_success
        assinatura.reload
        expect(assinatura.status).to eq('cancelada')
        expect(assinatura.data_cancelamento).to be_present
      end
    end

    context 'validações e erros de domínio' do
      it 'falha se a empresa não for encontrada' do
        resultado = described_class.call(
          empresa: 999_999,
          plano: plano_start
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha se a empresa estiver inativa' do
        empresa_inativa = create(:empresa, ativo: false, slug: 'emp-inativa')

        resultado = described_class.call(
          empresa: empresa_inativa,
          plano: plano_start
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
        expect(resultado.error).to include('inativa')
      end

      it 'falha se o plano não for encontrado' do
        resultado = described_class.call(
          empresa: empresa,
          plano: 999_999
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:plan_not_found)
      end

      it 'falha se o plano estiver inativo para nova contratação' do
        plano_inativo = create(:plano, identificador: :enterprise, ativo: false)

        resultado = described_class.call(
          empresa: empresa,
          plano: plano_inativo
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:plan_inactive)
        expect(resultado.error).to include('não está ativo')
      end

      it 'falha se a assinatura a ser atualizada pertencer a outra empresa' do
        empresa_outra = create(:empresa, slug: 'outra-empresa')
        assinatura = create(:assinatura, empresa: empresa_outra, plano: plano_start)

        resultado = described_class.call(
          assinatura: assinatura,
          empresa: empresa,
          valor: 99.00
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha se a data final for anterior à data de início' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          data_inicio: Date.current,
          data_fim: 5.days.ago.to_date
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_dates)
      end

      it 'falha de validação do ActiveRecord se valor for negativo' do
        resultado = described_class.call(
          empresa: empresa,
          plano: plano_start,
          valor: -10
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:record_invalid)
      end
    end

    context 'aliases' do
      it 'responde aos aliases CadastrarService, CriarService, AtualizarService e ContratarService' do
        expect(Assinaturas::CadastrarService).to eq(described_class)
        expect(Assinaturas::CriarService).to eq(described_class)
        expect(Assinaturas::AtualizarService).to eq(described_class)
        expect(Assinaturas::ContratarService).to eq(described_class)
      end
    end
  end
end
