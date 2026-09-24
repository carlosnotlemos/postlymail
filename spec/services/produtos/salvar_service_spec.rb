# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Produtos::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:categoria) { create(:produto_categoria, empresa: empresa, nome: 'Roupas', slug: 'roupas') }

  describe 'aliases de serviço' do
    it 'permite chamar através de Produtos::CadastrarService' do
      expect(Produtos::CadastrarService).to eq(Produtos::SalvarService)
      result = Produtos::CadastrarService.call(
        empresa: empresa,
        nome: 'Moletom Canguru'
      )
      expect(result).to be_success
      expect(result.data[:produto].nome).to eq('Moletom Canguru')
    end

    it 'permite chamar através de Produtos::CriarService' do
      expect(Produtos::CriarService).to eq(Produtos::SalvarService)
      result = Produtos::CriarService.call(
        empresa: empresa,
        nome: 'Calça Cargo'
      )
      expect(result).to be_success
      expect(result.data[:produto].nome).to eq('Calça Cargo')
    end

    it 'permite chamar através de Produtos::AtualizarService' do
      expect(Produtos::AtualizarService).to eq(Produtos::SalvarService)
      produto = create(:produto, empresa: empresa, nome: 'Camisa Original')
      result = Produtos::AtualizarService.call(
        empresa: empresa,
        produto: produto,
        nome: 'Camisa Atualizada'
      )
      expect(result).to be_success
      expect(result.data[:produto].nome).to eq('Camisa Atualizada')
    end
  end

  describe 'criação de produto (cadastro simples)' do
    it 'cria produto com sucesso utilizando atributos em hash' do
      result = described_class.call(
        empresa: empresa,
        atributos: {
          nome: 'Camiseta Oversized Boxy',
          descricao: '100% Algodão penteado',
          ativo: true
        }
      )

      expect(result).to be_success
      produto = result.data[:produto]
      expect(produto).to be_persisted
      expect(produto.nome).to eq('Camiseta Oversized Boxy')
      expect(produto.descricao).to eq('100% Algodão penteado')
      expect(produto.empresa).to eq(empresa)
      expect(produto.ativo).to be true
      expect(produto.produto_categoria).to be_nil
    end

    it 'cria produto com sucesso utilizando argumentos nomeados diretos (kwargs)' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Boné Strapback',
        descricao: 'Aba curva',
        ativo: false
      )

      expect(result).to be_success
      produto = result.data[:produto]
      expect(produto).to be_persisted
      expect(produto.nome).to eq('Boné Strapback')
      expect(produto.descricao).to eq('Aba curva')
      expect(produto.ativo).to be false
    end

    it 'define ativo como true por padrão quando não informado' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Meia Cano Alto'
      )

      expect(result).to be_success
      expect(result.data[:produto].ativo).to be true
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        nome: 'Tênis Casual'
      )

      expect(result).to be_success
      expect(result.data[:produto].empresa_id).to eq(empresa.id)
    end

    it 'aceita empresa informada por slug' do
      result = described_class.call(
        empresa: empresa.slug,
        nome: 'Jaqueta Puffer'
      )

      expect(result).to be_success
      expect(result.data[:produto].empresa_id).to eq(empresa.id)
    end

    it 'normaliza e remove espaços em branco das extremidades de nome e descrição' do
      result = described_class.call(
        empresa: empresa,
        nome: '   Bermuda Cargo Preta   ',
        descricao: '   Sarja encorpada   '
      )

      expect(result).to be_success
      expect(result.data[:produto].nome).to eq('Bermuda Cargo Preta')
      expect(result.data[:produto].descricao).to eq('Sarja encorpada')
    end

    it 'converte tipos string para booleano no campo ativo' do
      result1 = described_class.call(
        empresa: empresa,
        nome: 'Item 1',
        ativo: 'false'
      )
      expect(result1).to be_success
      expect(result1.data[:produto].ativo).to be false

      result2 = described_class.call(
        empresa: empresa,
        nome: 'Item 2',
        ativo: 'true'
      )
      expect(result2).to be_success
      expect(result2.data[:produto].ativo).to be true
    end
  end

  describe 'associação com categoria (ProdutoCategoria)' do
    it 'associa com categoria passando a instância de ProdutoCategoria' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Camiseta Street',
        categoria: categoria
      )

      expect(result).to be_success
      produto = result.data[:produto]
      expect(produto.produto_categoria).to eq(categoria)
      expect(produto.produto_categoria_id).to eq(categoria.id)
    end

    it 'associa com categoria passando o ID numérico em categoria_id' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Camiseta Street',
        categoria_id: categoria.id
      )

      expect(result).to be_success
      expect(result.data[:produto].produto_categoria_id).to eq(categoria.id)
    end

    it 'associa com categoria passando o ID numérico em produto_categoria_id' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Camiseta Street',
        produto_categoria_id: categoria.id
      )

      expect(result).to be_success
      expect(result.data[:produto].produto_categoria_id).to eq(categoria.id)
    end

    it 'associa com categoria passando o slug da categoria' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Camiseta Street',
        categoria: 'roupas'
      )

      expect(result).to be_success
      expect(result.data[:produto].produto_categoria_id).to eq(categoria.id)
    end

    it 'permite desvincular a categoria de um produto ao passar categoria: nil' do
      produto = create(:produto, empresa: empresa, produto_categoria: categoria)

      result = described_class.call(
        empresa: empresa,
        produto: produto,
        categoria: nil
      )

      expect(result).to be_success
      produto.reload
      expect(produto.produto_categoria_id).to be_nil
    end

    it 'permite desvincular a categoria passando produto_categoria_id: nil' do
      produto = create(:produto, empresa: empresa, produto_categoria: categoria)

      result = described_class.call(
        empresa: empresa,
        produto: produto,
        produto_categoria_id: nil
      )

      expect(result).to be_success
      produto.reload
      expect(produto.produto_categoria_id).to be_nil
    end

    it 'retorna erro quando a categoria informada pertence a outra empresa' do
      categoria_outra_empresa = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        nome: 'Produto Tentativa Tenant',
        categoria: categoria_outra_empresa
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Categoria não pertence à empresa informada')
    end

    it 'retorna erro quando o ID da categoria pertence a outra empresa' do
      categoria_outra_empresa = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        nome: 'Produto Tentativa ID Tenant',
        categoria_id: categoria_outra_empresa.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando a categoria informada por ID não existe' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Produto Categoria Inexistente',
        categoria_id: 999_999
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_not_found)
      expect(result.error).to include('Categoria não informada ou não encontrada')
    end

    it 'retorna erro quando a categoria informada está inativa' do
      categoria_inativa = create(:produto_categoria, empresa: empresa, ativo: false)

      result = described_class.call(
        empresa: empresa,
        nome: 'Produto Categoria Inativa',
        categoria: categoria_inativa
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_inactive)
      expect(result.error).to include('A categoria informada está inativa')
    end

    it 'permite associar categoria inativa se permitir_categoria_inativa for true' do
      categoria_inativa = create(:produto_categoria, empresa: empresa, ativo: false)

      result = described_class.call(
        empresa: empresa,
        nome: 'Produto Categoria Inativa Permitida',
        categoria: categoria_inativa,
        permitir_categoria_inativa: true
      )

      expect(result).to be_success
      expect(result.data[:produto].produto_categoria_id).to eq(categoria_inativa.id)
    end
  end

  describe 'atualização de produto existente' do
    let!(:produto) { create(:produto, empresa: empresa, nome: 'Nome Antigo', produto_categoria: categoria) }

    it 'atualiza com sucesso passando a instância de Produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        nome: 'Nome Novo',
        descricao: 'Nova descrição'
      )

      expect(result).to be_success
      produto.reload
      expect(produto.nome).to eq('Nome Novo')
      expect(produto.descricao).to eq('Nova descrição')
      # Mantém a categoria original já que categoria não foi alterada
      expect(produto.produto_categoria_id).to eq(categoria.id)
    end

    it 'atualiza com sucesso passando o ID do produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto.id,
        nome: 'Nome Atualizado via ID'
      )

      expect(result).to be_success
      produto.reload
      expect(produto.nome).to eq('Nome Atualizado via ID')
    end

    it 'resolve a empresa automaticamente a partir do produto se a empresa não for passada' do
      result = described_class.call(
        produto: produto,
        nome: 'Atualizado Sem Empresa Explícita'
      )

      expect(result).to be_success
      produto.reload
      expect(produto.nome).to eq('Atualizado Sem Empresa Explícita')
    end
  end

  describe 'validação de limite de produtos do plano da assinatura ativa' do
    let(:plano_limitado) { create(:plano, limite_produtos: 2) }
    let(:plano_ilimitado) { create(:plano, limite_produtos: nil) }

    context 'quando a empresa possui assinatura ativa com limite' do
      before do
        create(:assinatura, empresa: empresa, plano: plano_limitado, status: :ativa)
      end

      it 'permite criar produtos se estiver abaixo do limite' do
        create(:produto, empresa: empresa, nome: 'Produto 1')

        result = described_class.call(
          empresa: empresa,
          nome: 'Produto 2'
        )

        expect(result).to be_success
        expect(result.data[:produto]).to be_persisted
      end

      it 'retorna erro quando o limite de produtos do plano é atingido' do
        create(:produto, empresa: empresa, nome: 'Produto 1')
        create(:produto, empresa: empresa, nome: 'Produto 2')

        result = described_class.call(
          empresa: empresa,
          nome: 'Produto 3 que excede limite'
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:plan_product_limit_reached)
        expect(result.error).to include('Limite de produtos atingido para o plano contratado (2)')
      end

      it 'permite criar produto se ignorar_limite for true' do
        create(:produto, empresa: empresa, nome: 'Produto 1')
        create(:produto, empresa: empresa, nome: 'Produto 2')

        result = described_class.call(
          empresa: empresa,
          nome: 'Produto Extra Forçado',
          ignorar_limite: true
        )

        expect(result).to be_success
        expect(result.data[:produto]).to be_persisted
      end

      it 'permite atualizar produto existente mesmo se a empresa já estiver no limite' do
        p1 = create(:produto, empresa: empresa, nome: 'Produto 1')
        create(:produto, empresa: empresa, nome: 'Produto 2')

        result = described_class.call(
          empresa: empresa,
          produto: p1,
          nome: 'Produto 1 Editado'
        )

        expect(result).to be_success
        expect(p1.reload.nome).to eq('Produto 1 Editado')
      end
    end

    context 'quando a empresa possui assinatura ativa com plano ilimitado' do
      before do
        create(:assinatura, empresa: empresa, plano: plano_ilimitado, status: :ativa)
      end

      it 'permite criar mais de 2 produtos sem restrição' do
        create(:produto, empresa: empresa, nome: 'P1')
        create(:produto, empresa: empresa, nome: 'P2')

        result = described_class.call(
          empresa: empresa,
          nome: 'P3 Ilimitado'
        )

        expect(result).to be_success
        expect(result.data[:produto]).to be_persisted
      end
    end

    context 'quando a empresa não possui assinatura ativa' do
      it 'permite criar produtos normalmente' do
        result = described_class.call(
          empresa: empresa,
          nome: 'Produto Sem Assinatura'
        )

        expect(result).to be_success
      end
    end
  end

  describe 'suporte à criação de variações opcionais no mesmo salvamento' do
    it 'cria produto com uma única variação' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Calça Jeans Skinny',
        variacao: {
          sku: 'JNS-SKN-38',
          preco_base: 149.90,
          preco_custo: 50.00,
          tamanho: '38',
          cor: 'Azul'
        }
      )

      expect(result).to be_success
      produto = result.data[:produto]
      expect(produto.variacoes.count).to eq(1)

      variacao = produto.variacoes.first
      expect(variacao.sku).to eq('JNS-SKN-38')
      expect(variacao.preco_base).to eq(149.90)
      expect(variacao.empresa).to eq(empresa)
    end

    it 'cria produto com múltiplas variações em array' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Camisa Social Slim',
        variacoes: [
          { sku: 'SOC-BRC-1', tamanho: '1', cor: 'Branca', preco_base: 89.90, preco_custo: 30.0 },
          { sku: 'SOC-BRC-2', tamanho: '2', cor: 'Branca', preco_base: 89.90, preco_custo: 30.0 }
        ]
      )

      expect(result).to be_success
      produto = result.data[:produto]
      expect(produto.variacoes.count).to eq(2)
      expect(produto.variacoes.pluck(:sku)).to contain_exactly('SOC-BRC-1', 'SOC-BRC-2')
    end

    it 'faz rollback de todo o salvamento se alguma variação falhar' do
      expect do
        result = described_class.call(
          empresa: empresa,
          nome: 'Produto Variação Inválida',
          variacao: {
            sku: '', # SKU obrigatório vai falhar validação
            preco_base: -10 # Preço negativo também é inválido
          }
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:record_invalid)
      end.not_to change(Produto, :count)
    end
  end

  describe 'validação multi-tenant e parâmetros inválidos' do
    it 'retorna erro quando a empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        nome: 'Produto Sem Empresa'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to include('Empresa não informada ou não encontrada')
    end

    it 'retorna erro quando a empresa informada por ID não existe' do
      result = described_class.call(
        empresa: 999_999,
        nome: 'Produto Empresa Inexistente'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando o produto informado pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        produto: produto_outro,
        nome: 'Tentativa Invasão Tenant'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Produto não pertence à empresa informada')
    end

    it 'retorna erro quando o ID do produto pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        produto: produto_outro.id,
        nome: 'Tentativa ID Outra Empresa'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando o produto informado por ID não existe' do
      result = described_class.call(
        empresa: empresa,
        produto: 999_999,
        nome: 'Produto Fantasma'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:product_not_found)
      expect(result.error).to include('Produto não informado ou não encontrado')
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
