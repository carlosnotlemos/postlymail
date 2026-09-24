# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Produtos::ReativarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:produto) { create(:produto, empresa: empresa, ativo: false) }

  describe 'aliases de serviço' do
    it 'permite chamar através de Produtos::AtivarService' do
      expect(Produtos::AtivarService).to eq(Produtos::ReativarService)

      result = Produtos::AtivarService.call(
        empresa: empresa,
        produto: produto,
        motivo: 'Estoque reposto'
      )

      expect(result).to be_success
      expect(result.data[:reativado]).to be true
      expect(result.data[:motivo]).to eq('Estoque reposto')
      expect(produto.reload.ativo).to be true
    end
  end

  describe 'reativação de produto inativo' do
    it 'reativa o produto com sucesso passando a instância de produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        motivo: 'Nova remessa recebida'
      )

      expect(result).to be_success
      expect(result.data[:reativado]).to be true
      expect(result.data[:motivo]).to eq('Nova remessa recebida')
      expect(result.data[:produto]).to eq(produto)
      expect(produto.reload.ativo).to be true
    end

    it 'reativa o produto passando o produto como primeiro argumento posicional' do
      result = described_class.call(produto)

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end

    it 'reativa o produto passando o ID numérico do produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto.id
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        produto: produto.id
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end

    it 'aceita empresa informada por slug' do
      result = described_class.call(
        empresa: empresa.slug,
        produto: produto
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end
  end

  describe 'idempotência e produto já ativo' do
    let!(:produto_ativo) { create(:produto, empresa: empresa, ativo: true) }

    it 'retorna erro quando o produto já está ativo e ignorar_se_ativo é false' do
      result = described_class.call(
        empresa: empresa,
        produto: produto_ativo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:product_already_active)
      expect(result.error).to include('Produto já se encontra ativo')
    end

    it 'retorna sucesso idempotente quando ignorar_se_ativo é true' do
      result = described_class.call(
        empresa: empresa,
        produto: produto_ativo,
        ignorar_se_ativo: true,
        motivo: 'Chamada idempotente'
      )

      expect(result).to be_success
      expect(result.data[:reativado]).to be false
      expect(result.data[:ja_estava_ativo]).to be true
      expect(result.data[:motivo]).to eq('Chamada idempotente')
      expect(result.data[:variacoes_reativadas]).to eq(0)
      expect(produto_ativo.reload.ativo).to be true
    end
  end

  describe 'regras com categoria inativa' do
    let(:categoria_inativa) { create(:produto_categoria, empresa: empresa, ativo: false) }

    before do
      produto.update!(produto_categoria: categoria_inativa)
    end

    it 'bloqueia a reativação se a categoria do produto estiver inativa' do
      result = described_class.call(
        empresa: empresa,
        produto: produto
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_inactive)
      expect(result.error).to include('A categoria do produto encontra-se inativa')
      expect(produto.reload.ativo).to be false
    end

    it 'permite reativar com categoria inativa se permitir_categoria_inativa for true' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        permitir_categoria_inativa: true
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
      expect(produto.produto_categoria_id).to eq(categoria_inativa.id)
    end

    it 'desvincula a categoria inativa automaticamente se desvincular_categoria_inativa for true' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        desvincular_categoria_inativa: true
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
      expect(produto.produto_categoria_id).to be_nil
    end
  end

  describe 'validação de limite de produtos do plano' do
    let(:plano_limitado) { create(:plano, limite_produtos: 2) }

    before do
      create(:assinatura, empresa: empresa, plano: plano_limitado, status: :ativa)
    end

    it 'permite reativar se os produtos ativos estiverem abaixo do limite' do
      create(:produto, empresa: empresa, ativo: true, nome: 'P1 Ativo')

      result = described_class.call(
        empresa: empresa,
        produto: produto
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end

    it 'bloqueia reativação se o limite de produtos ativos já estiver atingido' do
      create(:produto, empresa: empresa, ativo: true, nome: 'P1 Ativo')
      create(:produto, empresa: empresa, ativo: true, nome: 'P2 Ativo')

      result = described_class.call(
        empresa: empresa,
        produto: produto
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:plan_product_limit_reached)
      expect(result.error).to include('Limite de produtos ativos atingido para o plano contratado (2)')
      expect(produto.reload.ativo).to be false
    end

    it 'permite reativar se ignorar_limite for true' do
      create(:produto, empresa: empresa, ativo: true, nome: 'P1 Ativo')
      create(:produto, empresa: empresa, ativo: true, nome: 'P2 Ativo')

      result = described_class.call(
        empresa: empresa,
        produto: produto,
        ignorar_limite: true
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be true
    end
  end

  describe 'reativação de variações vinculadas' do
    let!(:var_inativa1) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: false) }
    let!(:var_inativa2) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: false) }
    let!(:var_ja_ativa) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: true) }

    it 'não reativa variações por padrão (reativar_variacoes: false)' do
      result = described_class.call(
        empresa: empresa,
        produto: produto
      )

      expect(result).to be_success
      expect(result.data[:variacoes_reativadas]).to eq(0)
      expect(produto.reload.ativo).to be true
      expect(var_inativa1.reload.ativo).to be false
      expect(var_inativa2.reload.ativo).to be false
      expect(var_ja_ativa.reload.ativo).to be true
    end

    it 'reativa todas as variações inativas quando reativar_variacoes for true' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        reativar_variacoes: true
      )

      expect(result).to be_success
      expect(result.data[:variacoes_reativadas]).to eq(2)
      expect(produto.reload.ativo).to be true
      expect(var_inativa1.reload.ativo).to be true
      expect(var_inativa2.reload.ativo).to be true
      expect(var_ja_ativa.reload.ativo).to be true
    end
  end

  describe 'validação multi-tenant e parâmetros inválidos' do
    it 'retorna erro quando empresa não é informada e produto não foi encontrado' do
      result = described_class.call(
        empresa: nil,
        produto: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to include('Empresa não informada ou não encontrada')
    end

    it 'retorna erro quando empresa informada por ID não existe' do
      result = described_class.call(
        empresa: 999_999,
        produto: produto.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando o produto pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa, ativo: false)

      result = described_class.call(
        empresa: empresa,
        produto: produto_outro
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Produto não pertence à empresa informada')
    end

    it 'retorna erro quando o ID do produto pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa, ativo: false)

      result = described_class.call(
        empresa: empresa,
        produto: produto_outro.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando o produto não existe' do
      result = described_class.call(
        empresa: empresa,
        produto: 999_999
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:product_not_found)
      expect(result.error).to include('Produto não informado ou não encontrado')
    end

    it 'retorna erro quando o produto é nulo' do
      result = described_class.call(
        empresa: empresa,
        produto: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:product_not_found)
    end
  end
end
