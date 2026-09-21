# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Membros::InativarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'empresa-equipe') }
  let!(:usuario) { create(:usuario, email: 'funcionario@exemplo.com') }
  let!(:membro) { create(:membro, empresa: empresa, usuario: usuario, papel: :atendente, ativo: true) }

  describe '.call' do
    context 'quando os parâmetros são válidos' do
      it 'inativa o membro com sucesso por instância' do
        resultado = described_class.call(empresa: empresa, membro: membro)

        expect(resultado).to be_success
        expect(resultado.data[:inativado]).to be true
        expect(resultado.data[:membro].id).to eq(membro.id)
        expect(resultado.data[:membro].ativo).to be false
        expect(membro.reload.ativo).to be false
      end

      it 'inativa por ID numérico de membro' do
        resultado = described_class.call(empresa: empresa, membro: membro.id)

        expect(resultado).to be_success
        expect(membro.reload.ativo).to be false
      end

      it 'inativa localizando pelo usuário vinculado' do
        resultado = described_class.call(empresa: empresa, membro: usuario)

        expect(resultado).to be_success
        expect(membro.reload.ativo).to be false
      end

      it 'inativa localizando pelo e-mail do usuário vinculado' do
        resultado = described_class.call(empresa: empresa, membro: 'funcionario@exemplo.com')

        expect(resultado).to be_success
        expect(membro.reload.ativo).to be false
      end

      it 'registra o motivo da inativação' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro,
          motivo: 'Fim do contrato de trabalho'
        )

        expect(resultado).to be_success
        expect(resultado.data[:motivo]).to eq('Fim do contrato de trabalho')
      end
    end

    context 'quando o membro já está inativo' do
      before do
        membro.update!(ativo: false)
      end

      it 'retorna erro indicando que já se encontra inativo por padrão' do
        resultado = described_class.call(empresa: empresa, membro: membro)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_already_inactive)
        expect(resultado.error).to eq('Membro já se encontra inativo nesta empresa')
      end

      it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
        resultado = described_class.call(
          empresa: empresa,
          membro: membro,
          ignorar_se_inativo: true,
          motivo: 'Tentativa redundante'
        )

        expect(resultado).to be_success
        expect(resultado.data[:inativado]).to be false
        expect(resultado.data[:ja_estava_inativo]).to be true
        expect(resultado.data[:motivo]).to eq('Tentativa redundante')
      end
    end

    context 'com regra de proteção do último proprietário ativo' do
      let!(:proprietario) { create(:usuario) }
      let!(:membro_proprietario) { create(:membro, empresa: empresa, usuario: proprietario, papel: :proprietario, ativo: true) }

      it 'bloqueia a inativação do único proprietário ativo da empresa' do
        resultado = described_class.call(empresa: empresa, membro: membro_proprietario)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:last_owner_cannot_be_inactivated)
        expect(resultado.error).to eq('Não é possível inativar o único proprietário ativo da empresa')
        expect(membro_proprietario.reload.ativo).to be true
      end

      it 'permite inativação quando existe outro proprietário ativo na empresa' do
        outro_proprietario = create(:usuario)
        create(:membro, empresa: empresa, usuario: outro_proprietario, papel: :proprietario, ativo: true)

        resultado = described_class.call(empresa: empresa, membro: membro_proprietario)

        expect(resultado).to be_success
        expect(membro_proprietario.reload.ativo).to be false
      end
    end

    context 'quando ocorrem erros de autorização ou localização' do
      it 'retorna erro quando a empresa não é encontrada' do
        resultado = described_class.call(empresa: 999_999, membro: membro)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'retorna erro quando o membro não pertence à empresa informada' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(empresa: outra_empresa, membro: membro)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
        expect(resultado.error).to eq('Membro não pertence à empresa informada')
      end

      it 'retorna erro quando o membro não é encontrado' do
        resultado = described_class.call(empresa: empresa, membro: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:member_not_found)
      end
    end

    context 'com aliases de classe' do
      it 'funciona com Membros::DesativarService' do
        resultado = Membros::DesativarService.call(empresa: empresa, membro: membro)
        expect(resultado).to be_success
        expect(membro.reload.ativo).to be false
      end

      it 'funciona com Membros::RemoverService' do
        outro_membro = create(:membro, empresa: empresa, ativo: true)
        resultado = Membros::RemoverService.call(empresa: empresa, membro: outro_membro)
        expect(resultado).to be_success
        expect(outro_membro.reload.ativo).to be false
      end
    end
  end
end
