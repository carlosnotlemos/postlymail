# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Convites::SalvarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'loja-central') }
  let!(:gestor) { create(:usuario, email: 'gestor@empresa.com') }
  let!(:membro_gestor) do
    create(:membro, empresa: empresa, usuario: gestor, papel: :gerente, ativo: true)
  end

  describe '.call' do
    context 'quando enviando um novo convite com sucesso' do
      let(:parametros_validos) do
        {
          empresa: empresa,
          convidado_por: gestor,
          email: 'novo.colaborador@exemplo.com',
          papel: :atendente
        }
      end

      it 'cria o convite com token e expiração padrão' do
        resultado = described_class.call(parametros_validos)

        expect(resultado).to be_success
        convite = resultado.data[:convite]
        expect(convite).to be_persisted
        expect(convite.empresa).to eq(empresa)
        expect(convite.convidado_por).to eq(gestor)
        expect(convite.email).to eq('novo.colaborador@exemplo.com')
        expect(convite.papel).to eq('atendente')
        expect(convite.token).to be_present
        expect(convite.expira_em).to be > Time.current
        expect(resultado.data[:reenviado]).to be false
      end

      it 'permite resolver a empresa por slug' do
        resultado = described_class.call(
          empresa: 'loja-central',
          convidado_por: gestor,
          email: 'teste.slug@exemplo.com',
          papel: :estoquista
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].empresa).to eq(empresa)
      end

      it 'permite resolver a empresa por ID' do
        resultado = described_class.call(
          empresa: empresa.id,
          convidado_por: gestor,
          email: 'teste.id@exemplo.com',
          papel: :estoquista
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].empresa).to eq(empresa)
      end

      it 'permite resolver o usuário emissor por e-mail' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: 'gestor@empresa.com',
          email: 'teste.emissor@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].convidado_por).to eq(gestor)
      end

      it 'normaliza e-mail com espaços e letras maiúsculas' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: '   Novo.Colaborador@Exemplo.COM   ',
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].email).to eq('novo.colaborador@exemplo.com')
      end

      it 'aceita papel como string ou inteiro' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'colaborador2@exemplo.com',
          papel: 'gerente'
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].papel).to eq('gerente')
      end

      it 'aceita expiração customizada' do
        prazo = 15.days.from_now
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'prazo@exemplo.com',
          papel: :atendente,
          expira_em: prazo
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].expira_em).to be_within(2.seconds).of(prazo)
      end
    end

    context 'validações de domínio' do
      it 'falha quando a empresa não é informada' do
        resultado = described_class.call(
          empresa: nil,
          convidado_por: gestor,
          email: 'teste@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha quando o usuário emissor não é informado' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: nil,
          email: 'teste@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:convidado_por_not_found)
      end

      it 'falha quando o usuário emissor não pertence à empresa' do
        outro_usuario = create(:usuario, email: 'estranho@outro.com')

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: outro_usuario,
          email: 'teste@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_inviter)
      end

      it 'falha quando o usuário emissor está inativo na empresa' do
        membro_gestor.update!(ativo: false)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'teste@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_inviter)
      end

      it 'falha quando o e-mail não é informado' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: nil,
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_email)
      end

      it 'falha quando o formato do e-mail é inválido' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'email_sem_arroba.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_email)
      end

      it 'falha quando o papel não é informado' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'teste@exemplo.com',
          papel: nil
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_role)
      end

      it 'falha quando o papel informado é inválido' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'teste@exemplo.com',
          papel: :diretor_geral
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_role)
      end

      it 'falha quando o destinatário já é membro ativo da empresa' do
        membro_existente = create(:usuario, email: 'existente@empresa.com')
        create(:membro, empresa: empresa, usuario: membro_existente, ativo: true)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'existente@empresa.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_already_exists)
      end

      it 'falha quando já existe convite pendente para o mesmo e-mail' do
        create(:convite, empresa: empresa, convidado_por: gestor, email: 'pendente@exemplo.com', expira_em: 3.days.from_now)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'pendente@exemplo.com',
          papel: :gerente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_already_pending)
      end

      it 'permite enviar novo convite para e-mail cujo convite anterior foi cancelado' do
        create(:convite, :cancelado, empresa: empresa, convidado_por: gestor, email: 'cancelado_antigo@exemplo.com')

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'cancelado_antigo@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite]).to be_persisted
        expect(resultado.data[:convite].cancelado?).to be false
      end
    end

    context 'reenvio e renovação de convite' do
      let!(:convite_pendente) do
        create(:convite, empresa: empresa, convidado_por: gestor, email: 'reenvio@exemplo.com', token: 'token-antigo', expira_em: 2.days.from_now)
      end

      it 'renova convite pendente quando solicitado explicitamente com reenviar: true' do
        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'reenvio@exemplo.com',
          papel: :gerente,
          reenviar: true
        )

        expect(resultado).to be_success
        convite = resultado.data[:convite]
        expect(convite.id).to eq(convite_pendente.id)
        expect(convite.papel).to eq('gerente')
        expect(convite.token).not_to eq('token-antigo')
        expect(resultado.data[:reenviado]).to be true
      end

      it 'renova automaticamente convite expirado anterior' do
        convite_expirado = create(
          :convite,
          :expirado,
          empresa: empresa,
          convidado_por: gestor,
          email: 'expirado@exemplo.com',
          token: 'token-expirado'
        )

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'expirado@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
        convite = resultado.data[:convite]
        expect(convite.id).to eq(convite_expirado.id)
        expect(convite.pendente?).to be true
        expect(convite.token).not_to eq('token-expirado')
        expect(resultado.data[:reenviado]).to be true
      end
    end

    context 'com limites de usuários do plano SaaS' do
      let(:plano) { create(:plano, limite_usuarios: 2) }
      let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano, status: :ativa) }

      it 'bloqueia o convite quando o limite de usuários for atingido' do
        outro_membro = create(:usuario)
        create(:membro, empresa: empresa, usuario: outro_membro, ativo: true)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'novo@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:plan_user_limit_reached)
      end

      it 'permite convidar quando ignorar_limite for true' do
        outro_membro = create(:usuario)
        create(:membro, empresa: empresa, usuario: outro_membro, ativo: true)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'novo@exemplo.com',
          papel: :atendente,
          ignorar_limite: true
        )

        expect(resultado).to be_success
      end

      it 'permite quando o plano possui limite de usuários ilimitado' do
        plano.update!(limite_usuarios: nil)
        outro_membro = create(:usuario)
        create(:membro, empresa: empresa, usuario: outro_membro, ativo: true)

        resultado = described_class.call(
          empresa: empresa,
          convidado_por: gestor,
          email: 'novo@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
      end
    end

    context 'aliases do serviço' do
      it 'funciona com CriarService, EnviarService e CadastrarService' do
        res1 = Convites::CriarService.call(empresa: empresa, convidado_por: gestor, email: 'alias1@exemplo.com', papel: :atendente)
        res2 = Convites::EnviarService.call(empresa: empresa, convidado_por: gestor, email: 'alias2@exemplo.com', papel: :atendente)
        res3 = Convites::CadastrarService.call(empresa: empresa, convidado_por: gestor, email: 'alias3@exemplo.com', papel: :atendente)

        expect(res1).to be_success
        expect(res2).to be_success
        expect(res3).to be_success
      end
    end
  end
end
