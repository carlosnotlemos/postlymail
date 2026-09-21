require 'rails_helper'

RSpec.describe ProdutoCategorias::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }

  describe 'alias de serviço' do
    it 'permite chamar através de ProdutoCategorias::CadastrarService' do
      expect(ProdutoCategorias::CadastrarService).to eq(ProdutoCategorias::SalvarService)
      result = ProdutoCategorias::CadastrarService.call(
        empresa: empresa,
        nome: 'Calçados e Tênis'
      )
      expect(result).to be_success
      expect(result.data[:categoria].nome).to eq('Calçados e Tênis')
      expect(result.data[:categoria].slug).to eq('calcados-e-tenis')
    end
  end

  describe 'criação de categoria (cadastro simples)' do
    it 'cria categoria com sucesso utilizando atributos em hash' do
      result = described_class.call(
        empresa: empresa,
        atributos: {
          nome: 'Camisas Polo',
          slug: 'camisas-polo',
          ativo: true
        }
      )

      expect(result).to be_success
      categoria = result.data[:categoria]
      expect(categoria).to be_persisted
      expect(categoria.nome).to eq('Camisas Polo')
      expect(categoria.slug).to eq('camisas-polo')
      expect(categoria.empresa).to eq(empresa)
      expect(categoria.ativo).to be true
    end

    it 'cria categoria com sucesso utilizando argumentos nomeados diretos (kwargs)' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Acessórios & Bonés',
        ativo: true
      )

      expect(result).to be_success
      categoria = result.data[:categoria]
      expect(categoria.nome).to eq('Acessórios & Bonés')
      expect(categoria.slug).to eq('acessorios-bones')
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        nome: 'Moda Praia'
      )

      expect(result).to be_success
      expect(result.data[:categoria].empresa_id).to eq(empresa.id)
      expect(result.data[:categoria].slug).to eq('moda-praia')
    end

    it 'gera slug automaticamente a partir do nome quando slug não é informado' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Vestidos de Festa 2026!'
      )

      expect(result).to be_success
      expect(result.data[:categoria].slug).to eq('vestidos-de-festa-2026')
    end

    it 'sanitiza o slug informado com espaços ou caracteres maiúsculos' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Jaquetas',
        slug: 'Jaquetas DE Inverno 2026!'
      )

      expect(result).to be_success
      expect(result.data[:categoria].slug).to eq('jaquetas-de-inverno-2026')
    end
  end

  describe 'validação de duplicidade de slug' do
    it 'retorna erro quando já existe categoria com o mesmo slug na mesma empresa' do
      create(:produto_categoria, empresa: empresa, slug: 'camisetas')

      result = described_class.call(
        empresa: empresa,
        nome: 'Camisetas Básicas',
        slug: 'camisetas'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:slug_already_exists)
      expect(result.error).to include('Já existe uma categoria cadastrada com este slug nesta empresa')
    end

    it 'permite o mesmo slug em empresas diferentes' do
      create(:produto_categoria, empresa: outra_empresa, slug: 'camisetas')

      result = described_class.call(
        empresa: empresa,
        nome: 'Camisetas',
        slug: 'camisetas'
      )

      expect(result).to be_success
      expect(result.data[:categoria].slug).to eq('camisetas')
      expect(result.data[:categoria].empresa_id).to eq(empresa.id)
    end
  end

  describe 'atualização de categoria existente' do
    let!(:categoria) { create(:produto_categoria, empresa: empresa, nome: 'Bermudas', slug: 'bermudas') }

    it 'atualiza os dados com sucesso passando a instância de categoria' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        nome: 'Bermudas Jeans',
        slug: 'bermudas-jeans'
      )

      expect(result).to be_success
      categoria.reload
      expect(categoria.nome).to eq('Bermudas Jeans')
      expect(categoria.slug).to eq('bermudas-jeans')
    end

    it 'atualiza os dados com sucesso passando o ID da categoria' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria.id,
        nome: 'Bermudas Cargo'
      )

      expect(result).to be_success
      categoria.reload
      expect(categoria.nome).to eq('Bermudas Cargo')
      # Mantém o slug anterior já que slug não foi explicitamente passado na edição
      expect(categoria.slug).to eq('bermudas')
    end

    it 'permite manter o mesmo slug na atualização da própria categoria' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        nome: 'Bermudas Masculinas',
        slug: 'bermudas'
      )

      expect(result).to be_success
      categoria.reload
      expect(categoria.nome).to eq('Bermudas Masculinas')
      expect(categoria.slug).to eq('bermudas')
    end

    it 'retorna erro se tentar atualizar para o slug de outra categoria da mesma empresa' do
      create(:produto_categoria, empresa: empresa, slug: 'calcas')

      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        slug: 'calcas'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:slug_already_exists)
    end
  end

  describe 'validação multi-tenant e parâmetros inválidos' do
    it 'retorna erro quando a empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        nome: 'Categoria Sem Empresa'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando a empresa informada por ID não existe' do
      result = described_class.call(
        empresa: 999_999,
        nome: 'Categoria Empresa Inexistente'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando a categoria informada pertence a outra empresa' do
      categoria_outra_empresa = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        categoria: categoria_outra_empresa,
        nome: 'Tentativa Invasão Tenant'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando o ID da categoria pertence a outra empresa' do
      categoria_outra_empresa = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        categoria: categoria_outra_empresa.id,
        nome: 'Tentativa ID Outra Empresa'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando a categoria informada por ID não existe' do
      result = described_class.call(
        empresa: empresa,
        categoria: 999_999,
        nome: 'Categoria Fantasma'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_not_found)
    end

    it 'retorna erro de validação do modelo (:record_invalid) quando nome está em branco' do
      result = described_class.call(
        empresa: empresa,
        nome: ''
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:record_invalid)
      expect(result.error).to match(/Nome (can't be blank|não pode ficar em branco)/i)
    end
  end
end
