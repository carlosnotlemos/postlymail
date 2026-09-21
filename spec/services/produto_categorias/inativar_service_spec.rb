require 'rails_helper'

RSpec.describe ProdutoCategorias::InativarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let!(:categoria) { create(:produto_categoria, empresa: empresa, ativo: true) }

  describe 'inativação de categoria ativa' do
    it 'inativa a categoria com sucesso passando instância' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        motivo: 'Fim de coleção'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Fim de coleção')
      expect(categoria.reload.ativo).to be false
    end

    it 'inativa a categoria com sucesso passando ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        categoria: categoria.id
      )

      expect(result).to be_success
      expect(categoria.reload.ativo).to be false
    end
  end

  describe 'idempotência e categoria já inativa' do
    let!(:categoria_inativa) { create(:produto_categoria, empresa: empresa, ativo: false) }

    it 'retorna erro quando a categoria já está inativa e ignorar_se_inativo é false' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria_inativa
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_already_inactive)
      expect(result.error).to include('Categoria já se encontra inativa')
    end

    it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria_inativa,
        ignorar_se_inativo: true
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be false
      expect(result.data[:ja_estava_inativo]).to be true
      expect(categoria_inativa.reload.ativo).to be false
    end
  end

  describe 'regras com produtos vinculados' do
    let!(:produto_ativo) { create(:produto, empresa: empresa, produto_categoria: categoria, ativo: true) }
    let!(:produto_inativo) { create(:produto, empresa: empresa, produto_categoria: categoria, ativo: false) }

    it 'permite inativar mesmo com produtos ativos por padrão (permitir_com_produtos_ativos: true)' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria
      )

      expect(result).to be_success
      expect(categoria.reload.ativo).to be false
      expect(produto_ativo.reload.produto_categoria_id).to eq(categoria.id)
    end

    it 'bloqueia inativação se permitir_com_produtos_ativos for false e houver produtos ativos' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        permitir_com_produtos_ativos: false
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_has_active_products)
      expect(result.error).to include('Categoria possui produtos ativos vinculados')
      expect(categoria.reload.ativo).to be true
    end

    it 'permite inativar se permitir_com_produtos_ativos for false mas todos os produtos vinculados forem inativos' do
      produto_ativo.update!(ativo: false)

      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        permitir_com_produtos_ativos: false
      )

      expect(result).to be_success
      expect(categoria.reload.ativo).to be false
    end

    it 'desvincula os produtos quando desvincular_produtos: true é informado' do
      result = described_class.call(
        empresa: empresa,
        categoria: categoria,
        desvincular_produtos: true
      )

      expect(result).to be_success
      expect(result.data[:produtos_desvinculados]).to eq(2)
      expect(categoria.reload.ativo).to be false
      expect(produto_ativo.reload.produto_categoria_id).to be_nil
      expect(produto_inativo.reload.produto_categoria_id).to be_nil
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
