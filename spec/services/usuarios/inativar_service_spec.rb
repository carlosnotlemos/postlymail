# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Usuarios::InativarService, type: :service do
  let!(:usuario) { create(:usuario, ativo: true) }

  describe '.call' do
    context 'quando os parâmetros são válidos' do
      it 'inativa o usuário com sucesso' do
        resultado = described_class.call(usuario)

        expect(resultado).to be_success
        expect(resultado.data[:inativado]).to be true
        expect(resultado.data[:usuario].id).to eq(usuario.id)
        expect(resultado.data[:usuario].ativo).to be false
        expect(usuario.reload.ativo).to be false
      end

      it 'permite resolver o usuário por ID numérico' do
        resultado = described_class.call(usuario.id)

        expect(resultado).to be_success
        expect(usuario.reload.ativo).to be false
      end

      it 'permite resolver o usuário por string numérica' do
        resultado = described_class.call(usuario.id.to_s)

        expect(resultado).to be_success
        expect(usuario.reload.ativo).to be false
      end

      it 'permite resolver o usuário por e-mail' do
        resultado = described_class.call(usuario.email)

        expect(resultado).to be_success
        expect(usuario.reload.ativo).to be false
      end

      it 'aceita parâmetro nomeado usuario: e registra o motivo' do
        resultado = described_class.call(usuario: usuario, motivo: 'Desligamento da empresa')

        expect(resultado).to be_success
        expect(resultado.data[:motivo]).to eq('Desligamento da empresa')
        expect(usuario.reload.ativo).to be false
      end
    end

    context 'com controle de membros vinculados' do
      let!(:empresa1) { create(:empresa) }
      let!(:empresa2) { create(:empresa) }
      let!(:membro1) { create(:membro, usuario: usuario, empresa: empresa1, ativo: true) }
      let!(:membro2) { create(:membro, usuario: usuario, empresa: empresa2, ativo: true) }
      let!(:membro_ja_inativo) { create(:membro, usuario: usuario, empresa: create(:empresa), ativo: false) }

      it 'não desativa membros por padrão' do
        resultado = described_class.call(usuario)

        expect(resultado).to be_success
        expect(resultado.data[:membros_inativados]).to eq(0)
        expect(membro1.reload.ativo).to be true
        expect(membro2.reload.ativo).to be true
      end

      it 'desativa vínculos de membros ativos quando desativar_membros é true' do
        resultado = described_class.call(usuario, desativar_membros: true)

        expect(resultado).to be_success
        expect(resultado.data[:membros_inativados]).to eq(2)
        expect(membro1.reload.ativo).to be false
        expect(membro2.reload.ativo).to be false
        expect(membro_ja_inativo.reload.ativo).to be false
      end
    end

    context 'quando o usuário já está inativo' do
      before do
        usuario.update!(ativo: false)
      end

      it 'retorna erro indicando que já se encontra inativo por padrão' do
        resultado = described_class.call(usuario)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_already_inactive)
        expect(resultado.error).to eq('Usuário já se encontra inativo')
      end

      it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
        resultado = described_class.call(usuario, ignorar_se_inativo: true, motivo: 'Tentativa redundante')

        expect(resultado).to be_success
        expect(resultado.data[:inativado]).to be false
        expect(resultado.data[:ja_estava_inativo]).to be true
        expect(resultado.data[:motivo]).to eq('Tentativa redundante')
      end
    end

    context 'quando o usuário não é encontrado' do
      it 'retorna erro :usuario_not_found com ID inexistente' do
        resultado = described_class.call(999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_not_found)
      end

      it 'retorna erro :usuario_not_found com parâmetro nulo' do
        resultado = described_class.call(nil)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_not_found)
      end
    end

    context 'com aliases de classe' do
      it 'funciona com Usuarios::DesativarService' do
        resultado = Usuarios::DesativarService.call(usuario)
        expect(resultado).to be_success
        expect(usuario.reload.ativo).to be false
      end

      it 'funciona com Usuarios::BloquearService' do
        outro_usuario = create(:usuario, ativo: true)
        resultado = Usuarios::BloquearService.call(outro_usuario)
        expect(resultado).to be_success
        expect(outro_usuario.reload.ativo).to be false
      end
    end
  end
end
