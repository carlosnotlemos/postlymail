# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Disparos::CriarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'disparo-store', ativo: true) }
  let!(:campanha_email) { create(:campanha, empresa: empresa, canal: :email) }
  let!(:campanha_whatsapp) { create(:campanha, empresa: empresa, canal: :whatsapp, assunto: nil) }
  let!(:cliente) { create(:cliente, empresa: empresa, email: 'cliente@teste.com', telefone: '85988887777') }

  describe '.call' do
    context 'quando criando com sucesso' do
      it 'cria disparo usando email do cliente quando canal for email' do
        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente
        )

        expect(resultado).to be_success
        disparo = resultado.data[:disparo]
        expect(disparo).to be_persisted
        expect(disparo.destinatario).to eq('cliente@teste.com')
        expect(disparo.status).to eq('na_fila')
        expect(disparo.campanha).to eq(campanha_email)
        expect(disparo.cliente).to eq(cliente)
      end

      it 'cria disparo usando telefone do cliente quando canal for whatsapp' do
        resultado = described_class.call(
          campanha: campanha_whatsapp,
          cliente: cliente
        )

        expect(resultado).to be_success
        disparo = resultado.data[:disparo]
        expect(disparo).to be_persisted
        expect(disparo.destinatario).to eq('85988887777')
        expect(disparo.status).to eq('na_fila')
      end

      it 'permite customizar destinatário explicitamente' do
        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente,
          destinatario: 'outro_email@teste.com'
        )

        expect(resultado).to be_success
        expect(resultado.data[:disparo].destinatario).to eq('outro_email@teste.com')
      end

      it 'processa imediatamente quando enviar_agora for true' do
        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente,
          enviar_agora: true
        )

        expect(resultado).to be_success
        disparo = resultado.data[:disparo]
        expect(disparo.enviado?).to be true
        expect(disparo.enviado_em).to be_present
        expect(disparo.identificador_externo).to be_present
      end

      it 'mantém o disparo persistido com status :rejeitado quando enviar_agora for true mas o destinatário for inválido' do
        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente,
          destinatario: 'email_invalido',
          enviar_agora: true
        )

        expect(resultado).to be_success
        disparo = resultado.data[:disparo]
        expect(disparo).to be_persisted
        expect(disparo.rejeitado?).to be true
        expect(disparo.mensagem_erro).to be_present
      end

      it 'resolve entidades por ID' do
        resultado = described_class.call(
          campanha: campanha_email.id,
          cliente: cliente.id
        )

        expect(resultado).to be_success
        expect(resultado.data[:disparo]).to be_persisted
      end
    end

    context 'validações e regras de negócio' do
      it 'falha quando campanha não existe' do
        resultado = described_class.call(
          campanha: 999_999,
          cliente: cliente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_not_found)
      end

      it 'falha quando cliente não existe' do
        resultado = described_class.call(
          campanha: campanha_email,
          cliente: 999_999
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:client_not_found)
      end

      it 'falha quando cliente pertence a empresa diferente da campanha' do
        outra_empresa = create(:empresa)
        cliente_outro = create(:cliente, empresa: outra_empresa)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente_outro
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a empresa está inativa' do
        empresa.update!(ativo: false)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
      end

      it 'falha quando a campanha está cancelada' do
        campanha_cancelada = create(:campanha, empresa: empresa, status: :cancelada)

        resultado = described_class.call(
          campanha: campanha_cancelada,
          cliente: cliente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_cancelled)
      end

      it 'falha quando o cliente está inativo' do
        cliente_inativo = create(:cliente, empresa: empresa, ativo: false)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente_inativo
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:client_inactive)
      end

      it 'falha quando o cliente fez opt-out e não aceita comunicações de marketing' do
        cliente_sem_optin = create(:cliente, empresa: empresa, aceita_marketing: false)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente_sem_optin
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:client_marketing_opt_out)
      end

      it 'permite criar disparo para cliente sem opt-in quando ignorar_consentimento for true' do
        cliente_sem_optin = create(:cliente, empresa: empresa, aceita_marketing: false)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente_sem_optin,
          ignorar_consentimento: true
        )

        expect(resultado).to be_success
        expect(resultado.data[:disparo]).to be_persisted
      end

      it 'falha quando destinatário não puder ser determinado' do
        cliente_sem_email = create(:cliente, empresa: empresa, email: nil)

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente_sem_email
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:destination_blank)
      end

      it 'falha por padrão ao tentar criar disparo duplicado para o mesmo cliente na mesma campanha' do
        create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'cliente@teste.com')

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:disparo_already_exists)
      end

      it 'permite disparo duplicado quando permitir_duplicado for true' do
        create(:disparo, campanha: campanha_email, cliente: cliente, destinatario: 'cliente@teste.com')

        resultado = described_class.call(
          campanha: campanha_email,
          cliente: cliente,
          permitir_duplicado: true
        )

        expect(resultado).to be_success
        expect(campanha_email.disparos.where(cliente_id: cliente.id).count).to eq(2)
      end
    end

    context 'aliases' do
      it 'funciona através de Disparos::SalvarService e Campanhas::CriarDisparoService' do
        res1 = Disparos::SalvarService.call(campanha: campanha_email, cliente: cliente)
        expect(res1).to be_success

        cliente2 = create(:cliente, empresa: empresa, email: 'cliente2@teste.com')
        res2 = Campanhas::CriarDisparoService.call(campanha: campanha_email, cliente: cliente2)
        expect(res2).to be_success
      end
    end
  end
end
