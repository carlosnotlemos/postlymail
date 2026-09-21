# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Membros::SalvarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'empresa-teste') }
  let!(:usuario) { create(:usuario, email: 'operador@exemplo.com') }
  let!(:gestor) { create(:usuario, email: 'gestor@exemplo.com') }

  describe '.call' do
    context 'quando cadastrando um novo membro' do
      let(:parametros_validos) do
        {
          empresa: empresa,
          usuario: usuario,
          papel: :gerente,
          convidado_por: gestor,
          ativo: true
        }
      end

      it 'cria o membro com sucesso e associa à empresa e ao usuário' do
        resultado = described_class.call(parametros_validos)

        expect(resultado).to be_success
        membro = resultado.data[:membro]
        expect(membro).to be_persisted
        expect(membro.empresa).to eq(empresa)
        expect(membro.usuario).to eq(usuario)
        expect(membro.convidado_por).to eq(gestor)
        expect(membro.papel).to eq('gerente')
        expect(membro.ativo).to be true
        expect(membro.data_entrada).to be_present
      end

      it 'permite resolver a empresa por slug' do
        resultado = described_class.call(
          empresa: 'empresa-teste',
          usuario: usuario,
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].empresa).to eq(empresa)
      end

      it 'permite resolver a empresa por ID numérico' do
        resultado = described_class.call(
          empresa: empresa.id,
          usuario: usuario,
          papel: :estoquista
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].empresa).to eq(empresa)
      end

      it 'permite resolver o usuário por e-mail' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: 'operador@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(usuario)
      end

      it 'permite resolver o usuário que convidou por e-mail' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: usuario,
          convidado_por: 'gestor@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].convidado_por).to eq(gestor)
      end

      it 'aceita papel como string ou inteiro' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: usuario,
          papel: 'proprietario'
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].papel).to eq('proprietario')
      end

      it 'falha quando o papel informado é inválido' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: usuario,
          papel: :astronauta
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:invalid_role)
        expect(resultado.error).to eq('Papel informado é inválido')
      end

      it 'falha quando o usuário já é membro daquela empresa' do
        create(:membro, empresa: empresa, usuario: usuario)

        resultado = described_class.call(
          empresa: empresa,
          usuario: usuario,
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_already_exists)
        expect(resultado.error).to eq('Usuário já é membro desta empresa')
      end

      it 'falha quando a empresa não é encontrada' do
        resultado = described_class.call(
          empresa: 999_999,
          usuario: usuario,
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha quando o usuário não é encontrado' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: 'inexistente@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_not_found)
      end

      it 'falha quando convidado_por informado não é encontrado' do
        resultado = described_class.call(
          empresa: empresa,
          usuario: usuario,
          convidado_por: 'inexistente@exemplo.com',
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:convidado_por_not_found)
      end
    end

    context 'quando atualizando um membro existente' do
      let!(:membro) { create(:membro, empresa: empresa, usuario: usuario, papel: :atendente, ativo: true) }

      it 'atualiza o papel do membro com sucesso' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro,
          papel: :gerente
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].papel).to eq('gerente')
        expect(membro.reload.papel).to eq('gerente')
      end

      it 'atualiza por ID numérico de membro' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro.id,
          papel: :estoquista
        )

        expect(resultado).to be_success
        expect(membro.reload.papel).to eq('estoquista')
      end

      it 'falha se o membro pertencer a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          empresa: outra_empresa,
          membro: membro,
          papel: :gerente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
        expect(resultado.error).to eq('Membro não pertence à empresa informada')
      end

      it 'falha quando o membro especificado não é encontrado' do
        resultado = described_class.call(
          empresa: empresa,
          membro: 999_999,
          papel: :gerente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_not_found)
      end
    end

    context 'com regra de proteção do último proprietário ativo' do
      let!(:proprietario) { create(:usuario) }
      let!(:membro_proprietario) { create(:membro, empresa: empresa, usuario: proprietario, papel: :proprietario, ativo: true) }

      it 'bloqueia a alteração de papel do único proprietário ativo' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro_proprietario,
          papel: :atendente
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:last_owner_cannot_change_role)
        expect(resultado.error).to eq('Não é possível alterar o papel do único proprietário ativo da empresa')
        expect(membro_proprietario.reload.papel).to eq('proprietario')
      end

      it 'bloqueia a inativação via atributos do único proprietário ativo' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro_proprietario,
          ativo: false
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:last_owner_cannot_be_inactivated)
        expect(resultado.error).to eq('Não é possível inativar o único proprietário ativo da empresa')
        expect(membro_proprietario.reload.ativo).to be true
      end

      it 'permite alterar papel se houver outro proprietário ativo na empresa' do
        outro_proprietario = create(:usuario)
        create(:membro, empresa: empresa, usuario: outro_proprietario, papel: :proprietario, ativo: true)

        resultado = described_class.call(
          empresa: empresa,
          membro: membro_proprietario,
          papel: :gerente
        )

        expect(resultado).to be_success
        expect(membro_proprietario.reload.papel).to eq('gerente')
      end
    end

    context 'com aliases de classe' do
      it 'funciona com Membros::CadastrarService' do
        outro_usuario = create(:usuario)
        resultado = Membros::CadastrarService.call(
          empresa: empresa,
          usuario: outro_usuario,
          papel: :atendente
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(outro_usuario)
      end

      it 'funciona com Membros::CriarService' do
        outro_usuario = create(:usuario)
        resultado = Membros::CriarService.call(
          empresa: empresa,
          usuario: outro_usuario,
          papel: :estoquista
        )

        expect(resultado).to be_success
        expect(resultado.data[:membro].usuario).to eq(outro_usuario)
      end

      it 'funciona com Membros::AtualizarService' do
        membro = create(:membro, empresa: empresa, usuario: usuario, papel: :atendente)
        resultado = Membros::AtualizarService.call(
          empresa: empresa,
          membro: membro,
          papel: :gerente
        )

        expect(resultado).to be_success
        expect(membro.reload.papel).to eq('gerente')
      end
    end
  end
end
