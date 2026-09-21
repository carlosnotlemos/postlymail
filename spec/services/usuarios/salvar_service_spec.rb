# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Usuarios::SalvarService, type: :service do
  describe '.call' do
    context 'quando cadastrando um novo usuário' do
      let(:parametros_validos) do
        {
          nome: 'Carlos Eduardo',
          email: 'carlos@exemplo.com.br',
          telefone: '(11) 98765-4321',
          ativo: true
        }
      end

      it 'cria o usuário com sucesso e retorna o objeto' do
        resultado = described_class.call(atributos: parametros_validos)

        expect(resultado).to be_success
        usuario = resultado.data[:usuario]
        expect(usuario).to be_persisted
        expect(usuario.nome).to eq('Carlos Eduardo')
        expect(usuario.email).to eq('carlos@exemplo.com.br')
        expect(usuario.telefone).to eq('11987654321')
        expect(usuario.ativo).to be true
        expect(usuario.data_cadastro).to be_present
      end

      it 'aceita atributos via kwargs diretamente' do
        resultado = described_class.call(
          nome: 'Mariana Costa',
          email: 'mariana@exemplo.com.br',
          telefone: '11999998888'
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].nome).to eq('Mariana Costa')
        expect(resultado.data[:usuario].email).to eq('mariana@exemplo.com.br')
      end

      it 'normaliza o nome removendo espaços extras' do
        resultado = described_class.call(
          nome: '   Ana Paula Souza   ',
          email: 'ana@exemplo.com.br'
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].nome).to eq('Ana Paula Souza')
      end

      it 'normaliza email em caixa baixa e remove espaços extras' do
        resultado = described_class.call(
          nome: 'Roberto Dias',
          email: '  ROBERTO@Exemplo.COM.BR  '
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].email).to eq('roberto@exemplo.com.br')
      end

      it 'sanitiza telefone mantendo apenas números' do
        resultado = described_class.call(
          nome: 'Lucas Lima',
          email: 'lucas@exemplo.com.br',
          telefone: '+55 (21) 97777-6666'
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].telefone).to eq('5521977776666')
      end

      it 'converte string booleana no campo ativo' do
        resultado = described_class.call(
          nome: 'Fernanda Ramos',
          email: 'fernanda@exemplo.com.br',
          ativo: 'false'
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].ativo).to be false
      end

      it 'falha ao tentar cadastrar email já existente' do
        create(:usuario, email: 'duplicado@exemplo.com')

        resultado = described_class.call(
          nome: 'Outro Usuario',
          email: 'DUPLICADO@exemplo.com'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:email_already_exists)
        expect(resultado.error).to eq('Já existe um usuário cadastrado com este e-mail')
      end

      it 'falha quando atributos obrigatórios do model são inválidos' do
        resultado = described_class.call(
          nome: '',
          email: 'invalido'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:record_invalid)
        expect(resultado.error).to include('Erro de validação')
      end
    end

    context 'quando atualizando um usuário existente' do
      let!(:usuario) { create(:usuario, nome: 'Nome Antigo', email: 'antigo@exemplo.com', telefone: '11111111111') }

      it 'atualiza por instância de Usuario' do
        resultado = described_class.call(
          usuario: usuario,
          nome: 'Nome Atualizado',
          telefone: '(11) 92222-3333'
        )

        expect(resultado).to be_success
        expect(resultado.data[:usuario].nome).to eq('Nome Atualizado')
        expect(resultado.data[:usuario].telefone).to eq('11922223333')
        expect(usuario.reload.nome).to eq('Nome Atualizado')
      end

      it 'atualiza por ID numérico' do
        resultado = described_class.call(
          usuario: usuario.id,
          nome: 'Nome via ID'
        )

        expect(resultado).to be_success
        expect(usuario.reload.nome).to eq('Nome via ID')
      end

      it 'atualiza por ID em string' do
        resultado = described_class.call(
          usuario: usuario.id.to_s,
          nome: 'Nome via String ID'
        )

        expect(resultado).to be_success
        expect(usuario.reload.nome).to eq('Nome via String ID')
      end

      it 'atualiza por email' do
        resultado = described_class.call(
          usuario: usuario.email,
          nome: 'Nome via Email'
        )

        expect(resultado).to be_success
        expect(usuario.reload.nome).to eq('Nome via Email')
      end

      it 'permite manter o mesmo email na atualização' do
        resultado = described_class.call(
          usuario: usuario,
          email: 'antigo@exemplo.com',
          nome: 'Novo Nome'
        )

        expect(resultado).to be_success
        expect(usuario.reload.nome).to eq('Novo Nome')
      end

      it 'falha ao atualizar para email que já pertence a outro usuário' do
        create(:usuario, email: 'outro@exemplo.com')

        resultado = described_class.call(
          usuario: usuario,
          email: 'outro@exemplo.com'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:email_already_exists)
      end

      it 'retorna erro quando o usuário informado não for encontrado' do
        resultado = described_class.call(
          usuario: 999_999,
          nome: 'Tentativa Invalida'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:usuario_not_found)
        expect(resultado.error).to eq('Usuário não informado ou não encontrado')
      end
    end

    context 'com aliases de classe' do
      it 'funciona com Usuarios::CadastrarService' do
        resultado = Usuarios::CadastrarService.call(
          nome: 'Alias Cadastrar',
          email: 'cadastrar@exemplo.com'
        )
        expect(resultado).to be_success
        expect(resultado.data[:usuario].nome).to eq('Alias Cadastrar')
      end

      it 'funciona com Usuarios::CriarService' do
        resultado = Usuarios::CriarService.call(
          nome: 'Alias Criar',
          email: 'criar@exemplo.com'
        )
        expect(resultado).to be_success
        expect(resultado.data[:usuario].nome).to eq('Alias Criar')
      end

      it 'funciona com Usuarios::AtualizarService' do
        usuario = create(:usuario)
        resultado = Usuarios::AtualizarService.call(
          usuario: usuario,
          nome: 'Alias Atualizar'
        )
        expect(resultado).to be_success
        expect(usuario.reload.nome).to eq('Alias Atualizar')
      end
    end
  end
end
