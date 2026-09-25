# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Assinaturas::ProcessarInadimplentesService, type: :service do
  let(:empresa) { create(:empresa, ativo: true) }
  let(:plano) { create(:plano, identificador: :start, valor_mensal: 49.90) }
  let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano, status: :ativa) }

  describe '.call' do
    context 'quando a assinatura não possui faturas vencidas' do
      it 'mantém a assinatura ativa e não realiza alterações' do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 5.days.from_now.to_date)

        resultado = described_class.call

        expect(resultado).to be_success
        expect(resultado.data[:total_alteradas]).to eq(0)
        expect(resultado.data[:marcadas_como_atrasadas]).to be_empty
        expect(resultado.data[:marcadas_como_suspensas]).to be_empty
        expect(assinatura.reload.status).to eq('ativa')
        expect(empresa.reload.ativo).to be true
      end
    end

    context 'com faturas vencidas além da carência mas dentro da tolerância de suspensão' do
      let!(:fatura_vencida) do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 3.days.ago.to_date)
      end

      it 'marca a assinatura como atrasada' do
        resultado = described_class.call(dias_carencia: 0, dias_para_suspensao: 7)

        expect(resultado).to be_success
        expect(resultado.data[:total_alteradas]).to eq(1)
        expect(resultado.data[:marcadas_como_atrasadas]).to include(assinatura)
        expect(resultado.data[:marcadas_como_suspensas]).to be_empty

        assinatura.reload
        expect(assinatura.status).to eq('atrasada')
        expect(empresa.reload.ativo).to be true
      end

      it 'respeita dias de carência quando a fatura está dentro da carência' do
        resultado = described_class.call(dias_carencia: 5, dias_para_suspensao: 10)

        expect(resultado).to be_success
        expect(resultado.data[:total_alteradas]).to eq(0)
        expect(assinatura.reload.status).to eq('ativa')
      end
    end

    context 'com faturas vencidas além do prazo de tolerância para suspensão' do
      let!(:fatura_muito_atrasada) do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 10.days.ago.to_date)
      end

      it 'marca a assinatura como suspensa e bloqueia a empresa' do
        resultado = described_class.call(dias_para_suspensao: 7, bloquear_empresa: true)

        expect(resultado).to be_success
        expect(resultado.data[:total_alteradas]).to eq(1)
        expect(resultado.data[:marcadas_como_suspensas]).to include(assinatura)
        expect(resultado.data[:empresas_bloqueadas]).to include(empresa)

        assinatura.reload
        expect(assinatura.status).to eq('suspensa')
        expect(empresa.reload.ativo).to be false
      end

      it 'não bloqueia a empresa quando bloquear_empresa for false' do
        resultado = described_class.call(dias_para_suspensao: 7, bloquear_empresa: false)

        expect(resultado).to be_success
        expect(resultado.data[:marcadas_como_suspensas]).to include(assinatura)
        expect(resultado.data[:empresas_bloqueadas]).to be_empty

        assinatura.reload
        expect(assinatura.status).to eq('suspensa')
        expect(empresa.reload.ativo).to be true
      end
    end

    context 'com cancelamento automático de inadimplentes de longo prazo' do
      let!(:fatura_antiga) do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 35.days.ago.to_date)
      end

      it 'cancela a assinatura automaticamente quando atinge dias_para_cancelamento' do
        resultado = described_class.call(
          dias_para_suspensao: 7,
          dias_para_cancelamento: 30,
          cancelar_inadimplentes: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:marcadas_como_canceladas]).to include(assinatura)

        assinatura.reload
        expect(assinatura.status).to eq('cancelada')
        expect(assinatura.data_cancelamento).to be_present
      end
    end

    context 'quando a assinatura regulariza o débito (reativar_adimplentes)' do
      before do
        assinatura.update!(status: :suspensa)
        empresa.update!(ativo: false)
      end

      it 'reativa a assinatura e a empresa quando não há faturas pendentes vencidas' do
        # Fatura já foi paga
        create(:assinatura_fatura, assinatura: assinatura, status: :paga, data_vencimento: 10.days.ago.to_date)

        resultado = described_class.call(reativar_adimplentes: true)

        expect(resultado).to be_success
        expect(resultado.data[:reativadas]).to include(assinatura)
        expect(resultado.data[:empresas_reativadas]).to include(empresa)

        assinatura.reload
        expect(assinatura.status).to eq('ativa')
        expect(empresa.reload.ativo).to be true
      end

      it 'não reativa a empresa se ela possuir outra assinatura que ainda esteja suspensa' do
        create(:assinatura_fatura, assinatura: assinatura, status: :paga, data_vencimento: 10.days.ago.to_date)

        outra_assinatura = create(:assinatura, empresa: empresa, plano: plano, status: :suspensa)
        create(:assinatura_fatura, assinatura: outra_assinatura, status: :pendente, data_vencimento: 15.days.ago.to_date)

        resultado = described_class.call(assinatura: assinatura, reativar_adimplentes: true)

        expect(resultado).to be_success
        expect(resultado.data[:reativadas]).to include(assinatura)
        expect(resultado.data[:empresas_reativadas]).to be_empty

        assinatura.reload
        expect(assinatura.status).to eq('ativa')
        expect(empresa.reload.ativo).to be false
      end
    end

    context 'com escopos de execução' do
      let(:empresa_2) { create(:empresa, slug: 'empresa-2', email: 'emp2@loja.com') }
      let!(:assinatura_2) { create(:assinatura, empresa: empresa_2, plano: plano, status: :ativa) }

      before do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 10.days.ago.to_date)
        create(:assinatura_fatura, assinatura: assinatura_2, status: :pendente, data_vencimento: 10.days.ago.to_date)
      end

      it 'avalia apenas a assinatura informada quando o argumento for uma assinatura' do
        resultado = described_class.call(assinatura: assinatura)

        expect(resultado).to be_success
        expect(resultado.data[:total_avaliadas]).to eq(1)
        expect(resultado.data[:marcadas_como_suspensas]).to contain_exactly(assinatura)

        expect(assinatura.reload.status).to eq('suspensa')
        expect(assinatura_2.reload.status).to eq('ativa')
      end

      it 'avalia apenas as assinaturas da empresa informada por slug' do
        resultado = described_class.call(empresa: empresa.slug)

        expect(resultado).to be_success
        expect(resultado.data[:total_avaliadas]).to eq(1)
        expect(resultado.data[:marcadas_como_suspensas]).to contain_exactly(assinatura)

        expect(assinatura.reload.status).to eq('suspensa')
        expect(assinatura_2.reload.status).to eq('ativa')
      end

      it 'avalia todas as assinaturas elegíveis quando nenhum escopo for passado' do
        resultado = described_class.call

        expect(resultado).to be_success
        expect(resultado.data[:total_avaliadas]).to be >= 2
        expect(resultado.data[:marcadas_como_suspensas]).to include(assinatura, assinatura_2)

        expect(assinatura.reload.status).to eq('suspensa')
        expect(assinatura_2.reload.status).to eq('suspensa')
      end
    end

    context 'em modo de simulação (dry_run: true)' do
      let!(:fatura_vencida) do
        create(:assinatura_fatura, assinatura: assinatura, status: :pendente, data_vencimento: 10.days.ago.to_date)
      end

      it 'retorna o planejamento das ações sem alterar nada no banco de dados' do
        resultado = described_class.call(dry_run: true)

        expect(resultado).to be_success
        expect(resultado.data[:dry_run]).to be true
        expect(resultado.data[:marcadas_como_suspensas]).to include(assinatura)
        expect(resultado.data[:empresas_bloqueadas]).to include(empresa)

        # Dados permanecem inalterados no banco
        assinatura.reload
        expect(assinatura.status).to eq('ativa')
        expect(empresa.reload.ativo).to be true
      end
    end

    context 'validações e erros' do
      it 'falha se a assinatura não for encontrada' do
        resultado = described_class.call(assinatura: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:subscription_not_found)
      end

      it 'falha se a empresa não for encontrada' do
        resultado = described_class.call(empresa: 'empresa-inexistente')

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha se a assinatura não pertencer à empresa informada' do
        outra_empresa = create(:empresa, slug: 'outra-empresa', email: 'outra@loja.com')

        resultado = described_class.call(assinatura: assinatura, empresa: outra_empresa)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha se os parâmetros de dias forem negativos ou inconsistentes' do
        res1 = described_class.call(dias_para_suspensao: -1)
        expect(res1).to be_failure
        expect(res1.error_code).to eq(:invalid_parameters)

        res2 = described_class.call(dias_para_suspensao: 10, dias_para_cancelamento: 5)
        expect(res2).to be_failure
        expect(res2.error_code).to eq(:invalid_parameters)
      end
    end

    context 'aliases' do
      it 'responde aos aliases configurados' do
        expect(Assinaturas::ProcessarInadimplenciaService).to eq(described_class)
        expect(Assinaturas::VerificarInadimplentesService).to eq(described_class)
        expect(AssinaturaFaturas::ProcessarInadimplentesService).to eq(described_class)
      end
    end
  end
end
