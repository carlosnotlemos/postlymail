require 'rails_helper'

RSpec.describe ProdutoCategorias::ExcluirService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:categoria) { create(:produto_categoria, empresa: empresa) }

  describe 'exclusão de categoria sem produtos' do
    it 'remove a categoria com sucesso passando a instância' do
      categoria_id = categoria.id
      categoria_nome = categoria.nome

      result = described_class.call(
        empresa: empresa,
        categoria: categoria
      )

      expect(result).to be_success
      expect(result.data[:categoria_id]).to eq(categoria_id)
      expect(result.data[:categoria_nome]).to eq(categoria_nome)
      expect(result.data[:removido]).to be true
      expect(ProdutoCategoria.find_by(id: categoria_id)).to be_nil
    end

    it 'remove a categoria com sucesso passando ID numérico' do
      categoria_id = categoria.id

      result = described_class.call(
        empresa: empresa.id,
        categoria: categoria_id
      )

      expect(result).to be_success
      expect(ProdutoCategoria.find_by(id: categoria_id)).to be_nil
    end
  end

  describe 'tentativa de exclusão com produtos associados' do
    let!(:produto) { create(:produto, empresa: empresa, produto_categoria: categoria) }

    it 'bloqueia a exclusão quando há produtos vinculados e desvincular_produtos é false' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        desvincular_produtos: false
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_has_associated_products)
      expect(result.error).to include('Categoria possui produtos vinculados e não pode ser excluída')
      expect(ProdutoCategoria.exists?(categoria.id)).to be true
      expect(produto.reload.produto_categoria_id).to eq(categoria.id)
    end

    it 'permite excluir e desvincula os produtos quando desvincular_produtos é true' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        desvincular_produtos: true
      )

      expect(result).to be_success
      expect(result.data[:removido]).to be true
      expect(result.data[:produtos_desvinculados]).to eq(1)
      expect(ProdutoCategoria.find_by(id: categoria.id)).to be_nil
      expect(produto.reload.produto_categoria_id).to be_nil
    end
  end

  describe 'validação multi-tenant' do
    it 'retorna erro quando empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        categoria: categoria
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'retorna erro quando categoria pertence a outra empresa' do
      categoria_outra = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        categoria: categoria_outra
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando ID de categoria pertence a outra empresa' do
      categoria_outra = create(:produto_categoria, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        categoria: categoria_outra.id
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'retorna erro quando categoria não existe' do
      result = described_class.call(
        empresa: empresa,
        categoria: 999_999
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_not_found)
    end
  end
end
