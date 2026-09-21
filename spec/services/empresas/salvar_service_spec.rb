# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Empresas::SalvarService, type: :service do
  describe '.call' do
    context 'quando cadastrando uma nova empresa' do
      let(:parametros_validos) do
        {
          nome: 'Dropwear Confecções',
          slug: 'dropwear-confeccoes',
          email: 'contato@dropwear.com.br',
          documento: '12.345.678/0001-95',
          ativo: true
        }
      end

      it 'cria a empresa com sucesso e retorna o objeto' do
        resultado = described_class.call(atributos: parametros_validos)

        expect(resultado).to be_success
        empresa = resultado.data[:empresa]
        expect(empresa).to be_persisted
        expect(empresa.nome).to eq('Dropwear Confecções')
        expect(empresa.slug).to eq('dropwear-confeccoes')
        expect(empresa.email).to eq('contato@dropwear.com.br')
        expect(empresa.documento).to eq('12345678000195')
        expect(empresa.ativo).to be true
        expect(empresa.data_cadastro).to be_present
      end

      it 'aceita atributos via kwargs diretamente' do
        resultado = described_class.call(
          nome: 'Moda Brasil',
          slug: 'moda-brasil',
          email: 'admin@modabrasil.com.br'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].nome).to eq('Moda Brasil')
        expect(resultado.data[:empresa].slug).to eq('moda-brasil')
      end

      it 'gera slug automaticamente a partir do nome quando não informado' do
        resultado = described_class.call(
          nome: 'Loja Incrível & Cia',
          email: 'sac@lojaincrivel.com.br'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].slug).to eq('loja-incrivel-cia')
      end

      it 'gera slug com sufixo incremental automaticamente quando já existir empresa com o mesmo nome e documentos diferentes' do
        emp1 = described_class.call(
          nome: 'Alpha Store',
          email: 'alpha1@loja.com',
          documento: '11111111000111'
        )
        expect(emp1).to be_success
        expect(emp1.data[:empresa].slug).to eq('alpha-store')

        emp2 = described_class.call(
          nome: 'Alpha Store',
          email: 'alpha2@loja.com',
          documento: '22222222000122'
        )
        expect(emp2).to be_success
        expect(emp2.data[:empresa].slug).to eq('alpha-store-2')

        emp3 = described_class.call(
          nome: 'Alpha Store',
          email: 'alpha3@loja.com',
          documento: '33333333000133'
        )
        expect(emp3).to be_success
        expect(emp3.data[:empresa].slug).to eq('alpha-store-3')
      end


      it 'normaliza slug fornecido com acentos, espaços ou maiúsculas' do
        resultado = described_class.call(
          nome: 'Alpha Wear',
          slug: 'Álpha Wëar Loja!',
          email: 'contato@alphawear.com'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].slug).to eq('alpha-wear-loja')
      end

      it 'normaliza email em caixa baixa e remove espaços extras' do
        resultado = described_class.call(
          nome: 'Beta Confecções',
          email: '  ADMIN@BetaStore.COM  '
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].email).to eq('admin@betastore.com')
      end

      it 'sanitiza documento removendo pontuação e caracteres especiais' do
        resultado = described_class.call(
          nome: 'Gamma Têxtil',
          email: 'contato@gammatextil.com.br',
          documento: '98.765.432/0001-10'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].documento).to eq('98765432000110')
      end

      it 'converte string booleana no campo ativo' do
        resultado = described_class.call(
          nome: 'Delta Outlet',
          email: 'sac@delta.com',
          ativo: 'false'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].ativo).to be false
      end

      it 'falha ao tentar cadastrar slug já existente' do
        create(:empresa, slug: 'empresa-duplicada')

        resultado = described_class.call(
          nome: 'Outra Empresa',
          slug: 'empresa-duplicada',
          email: 'novo@empresa.com'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:slug_already_exists)
        expect(resultado.error).to eq('Já existe uma empresa cadastrada com este slug')
      end

      it 'falha ao tentar cadastrar documento já existente em outra empresa' do
        create(:empresa, documento: '12345678000195')

        resultado = described_class.call(
          nome: 'Outra Empresa',
          email: 'novo@empresa.com',
          documento: '12.345.678/0001-95'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:document_already_exists)
        expect(resultado.error).to eq('Já existe uma empresa cadastrada com este documento')
      end

      it 'permite cadastrar empresa com documento em branco mesmo existindo outras sem documento' do
        create(:empresa, documento: nil)

        resultado = described_class.call(
          nome: 'Empresa Sem Documento',
          email: 'semdoc@empresa.com',
          documento: nil
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].documento).to be_nil
      end


      it 'falha com erro de validação quando faltam atributos obrigatórios' do
        resultado = described_class.call(
          nome: '',
          email: 'invalido'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:record_invalid)
        expect(resultado.error).to include('Erro de validação:')
      end
    end

    context 'quando atualizando uma empresa existente' do
      let!(:empresa) do
        create(
          :empresa,
          nome: 'Nome Antigo',
          slug: 'slug-original',
          email: 'antigo@empresa.com',
          documento: '11111111000111',
          ativo: true
        )
      end

      it 'atualiza via instância de Empresa' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Nome Atualizado',
          email: 'novo@empresa.com'
        )

        expect(resultado).to be_success
        empresa_atualizada = resultado.data[:empresa]
        expect(empresa_atualizada.nome).to eq('Nome Atualizado')
        expect(empresa_atualizada.email).to eq('novo@empresa.com')
        expect(empresa_atualizada.slug).to eq('slug-original')
      end

      it 'atualiza resolvendo empresa por ID numérico' do
        resultado = described_class.call(
          empresa: empresa.id,
          nome: 'Atualizada Por ID'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Atualizada Por ID')
      end

      it 'atualiza resolvendo empresa por string numérica de ID' do
        resultado = described_class.call(
          empresa: empresa.id.to_s,
          nome: 'Atualizada Por String ID'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Atualizada Por String ID')
      end

      it 'atualiza resolvendo empresa por slug' do
        resultado = described_class.call(
          empresa: 'slug-original',
          nome: 'Atualizada Por Slug'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Atualizada Por Slug')
      end

      it 'permite alterar o slug se explicitamente informado' do
        resultado = described_class.call(
          empresa: empresa,
          slug: 'novo-slug-customizado'
        )

        expect(resultado).to be_success
        expect(empresa.reload.slug).to eq('novo-slug-customizado')
      end

      it 'permite manter o mesmo slug da própria empresa na atualização' do
        resultado = described_class.call(
          empresa: empresa,
          slug: 'slug-original',
          nome: 'Nome Modificado'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Nome Modificado')
      end

      it 'falha ao atualizar informando slug pertencente a outra empresa' do
        outra = create(:empresa, slug: 'outro-slug-ocupado')

        resultado = described_class.call(
          empresa: empresa,
          slug: 'outro-slug-ocupado'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:slug_already_exists)
      end

      it 'permite manter o mesmo documento da própria empresa na atualização' do
        resultado = described_class.call(
          empresa: empresa,
          documento: '11.111.111/0001-11',
          nome: 'Nome Modificado com Mesmo Doc'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Nome Modificado com Mesmo Doc')
        expect(empresa.documento).to eq('11111111000111')
      end

      it 'falha ao atualizar informando documento pertencente a outra empresa' do
        create(:empresa, documento: '99999999000199')

        resultado = described_class.call(
          empresa: empresa,
          documento: '99.999.999/0001-99'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:document_already_exists)
        expect(resultado.error).to eq('Já existe uma empresa cadastrada com este documento')
      end


      it 'permite inativar a empresa via atributo ativo' do
        resultado = described_class.call(
          empresa: empresa,
          ativo: false
        )

        expect(resultado).to be_success
        expect(empresa.reload.ativo).to be false
      end

      it 'falha quando a empresa informada não existe' do
        resultado = described_class.call(
          empresa: 999_999_999,
          nome: 'Empresa Fantasma'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
        expect(resultado.error).to eq('Empresa não informada ou não encontrada')
      end
    end

    context 'aliases' do
      it 'permite chamar através de CadastrarService' do
        resultado = Empresas::CadastrarService.call(
          nome: 'Alias Cadastrar',
          email: 'alias1@empresa.com'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].nome).to eq('Alias Cadastrar')
      end

      it 'permite chamar através de CriarService' do
        resultado = Empresas::CriarService.call(
          nome: 'Alias Criar',
          email: 'alias2@empresa.com'
        )

        expect(resultado).to be_success
        expect(resultado.data[:empresa].nome).to eq('Alias Criar')
      end

      it 'permite chamar através de AtualizarService' do
        empresa = create(:empresa)
        resultado = Empresas::AtualizarService.call(
          empresa: empresa,
          nome: 'Nome Via Atualizar'
        )

        expect(resultado).to be_success
        expect(empresa.reload.nome).to eq('Nome Via Atualizar')
      end
    end
  end
end
