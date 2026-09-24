# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Produtos::InativarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:produto) { create(:produto, empresa: empresa, ativo: true) }

  describe 'aliases de serviço' do
    it 'permite chamar através de Produtos::DesativarService' do
      expect(Produtos::DesativarService).to eq(Produtos::InativarService)

      result = Produtos::DesativarService.call(
        empresa: empresa,
        produto: produto,
        motivo: 'Fim de estoque permanente'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Fim de estoque permanente')
      expect(produto.reload.ativo).to be false
    end
  end

  describe 'inativação de produto ativo' do
    it 'inativa o produto com sucesso passando a instância de produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        motivo: 'Troca de fornecedor'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Troca de fornecedor')
      expect(result.data[:produto]).to eq(produto)
      expect(produto.reload.ativo).to be false
    end

    it 'inativa o produto com sucesso passando o produto como primeiro argumento posicional' do
      result = described_class.call(produto)

      expect(result).to be_success
      expect(produto.reload.ativo).to be false
    end

    it 'inativa o produto passando o ID numérico do produto' do
      result = described_class.call(
        empresa: empresa,
        produto: produto.id
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be false
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        produto: produto.id
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be false
    end

    it 'aceita empresa informada por slug' do
      result = described_class.call(
        empresa: empresa.slug,
        produto: produto
      )

      expect(result).to be_success
      expect(produto.reload.ativo).to be false
    end
  end

  describe 'idempotência e produto já inativo' do
    let!(:produto_inativo) { create(:produto, empresa: empresa, ativo: false) }

    it 'retorna erro quando o produto já está inativo e ignorar_se_inativo é false' do
      result = described_class.call(
        empresa: empresa,
        produto: produto_inativo
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:product_already_inactive)
      expect(result.error).to include('Produto já se encontra inativo')
    end

    it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
      result = described_class.call(
        empresa: empresa,
        produto: produto_inativo,
        ignorar_se_inativo: true,
        motivo: 'Chamada repetida'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be false
      expect(result.data[:ja_estava_inativo]).to be true
      expect(result.data[:motivo]).to eq('Chamada repetida')
      expect(result.data[:variacoes_inativadas]).to eq(0)
      expect(produto_inativo.reload.ativo).to be false
    end
  end

  describe 'inativação em cascata de variações vinculadas' do
    let!(:variacao_ativa1) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: true) }
    let!(:variacao_ativa2) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: true) }
    let!(:variacao_inativa) { create(:variacao_produto, produto: produto, empresa: empresa, ativo: false) }

    it 'inativa todas as variações ativas por padrão (inativar_variacoes: true)' do
      result = described_class.call(
        empresa: empresa,
        produto: produto
      )

      expect(result).to be_success
      expect(result.data[:variacoes_inativadas]).to eq(2)
      expect(produto.reload.ativo).to be false
      expect(variacao_ativa1.reload.ativo).to be false
      expect(variacao_ativa2.reload.ativo).to be false
      expect(variacao_inativa.reload.ativo).to be false
    end

    it 'mantém as variações inalteradas se inativar_variacoes for false' do
      result = described_class.call(
        empresa: empresa,
        produto: produto,
        inativar_variacoes: false
      )

      expect(result).to be_success
      expect(result.data[:variacoes_inativadas]).to eq(0)
      expect(produto.reload.ativo).to be false
      expect(variacao_ativa1.reload.ativo).to be true
      expect(variacao_ativa2.reload.ativo).to be true
      expect(variacao_inativa.reload.ativo).to be false
    end
  end

  describe 'validação multi-tenant e parâmetros inválidos' do
    it 'retorna erro quando a empresa não é informada e o produto não foi encontrado' do
      result = described_class.call(
        empresa: nil,
        produto: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to include('Empresa não informada ou não encontrada')
    end

    it 'retorna erro quando a empresa informada por ID não existe' do
      result = described_class.call(
        empresa: 999_999,
        produto: produto.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando o produto informado pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        produto: produto_outro
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Produto não pertence à empresa informada')
    end

    it 'retorna erro quando o ID do produto pertence a outra empresa' do
      produto_outro = create(:produto, empresa: outra_empresa)

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
