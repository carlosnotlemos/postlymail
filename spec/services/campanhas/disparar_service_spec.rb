# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::DispararService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'disparo-camp-store', ativo: true) }

  let!(:cliente_com_compra) do
    create(:cliente, empresa: empresa, nome: 'Com Compra', email: 'compra@email.com', telefone: '85999991111', aceita_marketing: true, ativo: true)
  end

  let!(:cliente_sem_compra) do
    create(:cliente, empresa: empresa, nome: 'Sem Compra', email: 'sem_compra@email.com', telefone: '85999992222', aceita_marketing: true, ativo: true)
  end

  let!(:cliente_sem_opt_in) do
    create(:cliente, empresa: empresa, nome: 'Sem Optin', email: 'no_opt@email.com', telefone: '85999993333', aceita_marketing: false, ativo: true)
  end

  let!(:cliente_inativo) do
    create(:cliente, empresa: empresa, nome: 'Inativo', email: 'inativo@email.com', telefone: '85999994444', aceita_marketing: true, ativo: false)
  end

  # Cria venda para o cliente_com_compra
  let!(:venda) do
    create(
      :venda,
      empresa: empresa,
      cliente: cliente_com_compra,
      status: :paga
    )
  end

  describe '.call' do
    context 'com segmentação :todos' do
      let!(:campanha) do
        create(
          :campanha,
          empresa: empresa,
          canal: :email,
          assunto: 'Assunto Todos',
          conteudo: 'Conteudo',
          segmento: :todos,
          status: :rascunho
        )
      end

      it 'dispara para todos os clientes ativos que aceitam marketing' do
        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_success
        expect(resultado.data[:executada]).to be true
        expect(resultado.data[:total_destinatarios]).to eq(2) # cliente_com_compra e cliente_sem_compra
        expect(resultado.data[:enviados_count]).to eq(2)
        expect(resultado.data[:falhas_count]).to eq(0)

        campanha.reload
        expect(campanha.concluida?).to be true
        expect(campanha.data_envio).to be_present

        destinatarios_enviados = campanha.disparos.pluck(:destinatario)
        expect(destinatarios_enviados).to contain_exactly('compra@email.com', 'sem_compra@email.com')
      end

      it 'respeita processar_agora: false deixando disparos na fila e campanha em status enviando' do
        resultado = described_class.call(
          campanha: campanha,
          processar_agora: false
        )

        expect(resultado).to be_success
        expect(resultado.data[:executada]).to be false
        expect(resultado.data[:enfileirada]).to be true

        # Não marca a campanha como concluída pois os disparos ainda estão na fila para um worker assíncrono
        expect(campanha.reload.enviando?).to be true
        expect(campanha.concluida?).to be false
        expect(campanha.disparos.where(status: :na_fila).count).to eq(2)
      end

      it 'isola falhas individuais de processamento sem realizar rollback dos disparos bem-sucedidos' do
        cliente_sem_compra.update_column(:email, 'email_invalido')

        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_success
        expect(resultado.data[:total_destinatarios]).to eq(2)
        expect(resultado.data[:enviados_count]).to eq(1)
        expect(resultado.data[:falhas_count]).to eq(1)

        disparo_sucesso = campanha.disparos.find_by(cliente: cliente_com_compra)
        expect(disparo_sucesso.enviado?).to be true

        disparo_falha = campanha.disparos.find_by(cliente: cliente_sem_compra)
        expect(disparo_falha.rejeitado?).to be true
      end
    end

    context 'com segmentação :com_compras' do
      let!(:campanha) do
        create(
          :campanha,
          empresa: empresa,
          canal: :email,
          assunto: 'Clientes VIP',
          conteudo: 'Obrigado por comprar conosco!',
          segmento: :com_compras,
          status: :rascunho
        )
      end

      it 'dispara exclusivamente para clientes que possuem compras não canceladas' do
        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_success
        expect(resultado.data[:total_destinatarios]).to eq(1)

        destinatarios = campanha.disparos.pluck(:destinatario)
        expect(destinatarios).to eq([ 'compra@email.com' ])
      end

      it 'não inclui cliente se a venda dele foi cancelada' do
        venda.update!(status: :cancelada, motivo_cancelamento: 'Teste')

        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_success
        expect(resultado.data[:total_destinatarios]).to eq(0)
        expect(campanha.disparos.count).to eq(0)
      end
    end

    context 'com segmentação :sem_compras' do
      let!(:campanha) do
        create(
          :campanha,
          empresa: empresa,
          canal: :whatsapp,
          conteudo: 'Cupom de 1ª compra: PRIMEIRA10',
          segmento: :sem_compras,
          status: :rascunho
        )
      end

      it 'dispara exclusivamente para clientes sem compras' do
        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_success
        expect(resultado.data[:total_destinatarios]).to eq(1)

        destinatarios = campanha.disparos.pluck(:destinatario)
        expect(destinatarios).to eq([ '85999992222' ])
      end
    end

    context 'com agendamento futuro' do
      let!(:campanha_agendada) do
        create(
          :campanha,
          empresa: empresa,
          canal: :email,
          status: :agendada,
          data_envio: 2.days.from_now
        )
      end

      it 'mantém agendada e não dispara imediatamente por padrão' do
        resultado = described_class.call(campanha: campanha_agendada)

        expect(resultado).to be_success
        expect(resultado.data[:agendada]).to be true
        expect(resultado.data[:executada]).to be false
        expect(campanha_agendada.reload.agendada?).to be true
        expect(campanha_agendada.disparos.count).to eq(0)
      end

      it 'força disparo imediato quando agora: true' do
        resultado = described_class.call(campanha: campanha_agendada, agora: true)

        expect(resultado).to be_success
        expect(resultado.data[:executada]).to be true
        expect(campanha_agendada.reload.concluida?).to be true
      end
    end

    context 'com público-alvo explícito' do
      let!(:campanha) { create(:campanha, empresa: empresa, status: :rascunho) }

      it 'dispara apenas para os clientes especificados no parâmetro clientes' do
        resultado = described_class.call(
          campanha: campanha,
          clientes: [ cliente_com_compra ]
        )

        expect(resultado).to be_success
        expect(resultado.data[:total_destinatarios]).to eq(1)
        expect(campanha.disparos.pluck(:cliente_id)).to eq([ cliente_com_compra.id ])
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando campanha não é informada' do
        resultado = described_class.call(campanha: nil)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_not_found)
      end

      it 'falha quando empresa informada não corresponde à campanha' do
        campanha = create(:campanha, empresa: empresa)
        outra_empresa = create(:empresa)

        resultado = described_class.call(campanha: campanha, empresa: outra_empresa)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a empresa está inativa' do
        campanha = create(:campanha, empresa: empresa)
        empresa.update!(ativo: false)

        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
      end

      it 'falha ao disparar campanha cancelada' do
        campanha = create(:campanha, empresa: empresa, status: :cancelada)

        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_cancelled)
      end

      it 'falha ao disparar campanha já concluída sem forçar' do
        campanha = create(:campanha, empresa: empresa, status: :concluida)

        resultado = described_class.call(campanha: campanha)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_already_completed)
      end
    end

    context 'aliases' do
      let!(:campanha) { create(:campanha, empresa: empresa, status: :rascunho) }

      it 'funciona através de Campanhas::EnviarService e Disparos::DispararCampanhaService' do
        res1 = Campanhas::EnviarService.call(campanha: campanha)
        expect(res1).to be_success

        campanha2 = create(:campanha, empresa: empresa, status: :rascunho)
        res2 = Disparos::DispararCampanhaService.call(campanha: campanha2)
        expect(res2).to be_success
      end
    end
  end
end
