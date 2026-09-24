# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Convites::AceitarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'matriz') }
  let!(:gestor) { create(:usuario, email: 'gestor@empresa.com') }
  let!(:convite) do
    create(:convite, empresa: empresa, convidado_por: gestor, email: 'convidado@exemplo.com', papel: :atendente)
  end
  let!(:usuario_convidado) { create(:usuario, email: 'convidado@exemplo.com') }

  describe '.call' do
    context 'quando aceitando o convite com sucesso' do
      it 'marca o convite como aceito e cria o membro na empresa' do
        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_success
        expect(resultado.data[:convite].reload.aceito_em).to be_present
        membro = resultado.data[:membro]
        expect(membro).to be_persisted
        expect(membro.empresa).to eq(empresa)
        expect(membro.usuario).to eq(usuario_convidado)
        expect(membro.papel).to eq('atendente')
        expect(membro.convidado_por).to eq(gestor)
        expect(membro.ativo).to be true
        expect(membro.data_entrada).to be_present
      end

      it 'permite aceitar passando a instância do convite' do
        resultado = described_class.call(
          convite: convite,
          usuario: usuario_convidado
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(usuario_convidado)
      end

      it 'resolve o usuário automaticamente pelo e-mail do convite se omitido' do
        resultado = described_class.call(token: convite.token)

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(usuario_convidado)
      end

      it 'reativa membro se o usuário já tiver registro inativo na mesma empresa' do
        membro_antigo = create(
          :membro,
          empresa: empresa,
          usuario: usuario_convidado,
          papel: :estoquista,
          ativo: false
        )

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_success
        membro = resultado.data[:membro]
        expect(membro.id).to eq(membro_antigo.id)
        expect(membro.ativo).to be true
        expect(membro.papel).to eq('atendente')
        expect(membro.convidado_por).to eq(gestor)
      end
    end

    context 'validações de domínio' do
      it 'falha quando o convite não é encontrado' do
        resultado = described_class.call(
          token: 'token-inexistente',
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_not_found)
      end

      it 'falha quando o convite não pertence à empresa informada' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado,
          empresa: outra_empresa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando o convite já foi aceito' do
        convite.update!(aceito_em: 1.day.ago)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_already_accepted)
      end

      it 'falha quando o convite foi cancelado' do
        convite.update!(cancelado_em: 1.hour.ago)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_cancelled)
      end

      it 'falha quando o convite está expirado' do
        convite.update!(expira_em: 1.day.ago)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invite_expired)
      end

      it 'falha quando o usuário não é encontrado' do
        resultado = described_class.call(
          token: convite.token,
          usuario: 'inexistente@exemplo.com'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_not_found)
      end

      it 'falha quando o usuário já é membro ativo da empresa' do
        create(:membro, empresa: empresa, usuario: usuario_convidado, ativo: true)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_already_exists)
      end

      it 'falha quando validar_email é true e o e-mail do usuário diverge do convite' do
        outro_usuario = create(:usuario, email: 'diferente@exemplo.com')

        resultado = described_class.call(
          token: convite.token,
          usuario: outro_usuario,
          validar_email: true
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:email_mismatch)
      end

      it 'permite aceitar com outro e-mail quando validar_email não é exigido' do
        outro_usuario = create(:usuario, email: 'diferente@exemplo.com')

        resultado = described_class.call(
          token: convite.token,
          usuario: outro_usuario,
          validar_email: false
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(outro_usuario)
      end
    end

    context 'com limites de usuários do plano SaaS' do
      let(:plano) { create(:plano, limite_usuarios: 1) }
      let!(:assinatura) { create(:assinatura, empresa: empresa, plano: plano, status: :ativa) }

      it 'bloqueia o aceite se o limite de usuários ativos do plano foi atingido' do
        create(:membro, empresa: empresa, usuario: gestor, ativo: true)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:plan_user_limit_reached)
      end

      it 'permite o aceite quando ignorar_limite for true' do
        create(:membro, empresa: empresa, usuario: gestor, ativo: true)

        resultado = described_class.call(
          token: convite.token,
          usuario: usuario_convidado,
          ignorar_limite: true
        )

        expect(resultado).to be_success
      end
    end
  end
end
