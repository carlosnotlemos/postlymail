class AddEmpresaAndUniqueSkuToVariacoesProdutos < ActiveRecord::Migration[8.1]
  def change
    add_reference :variacoes_produtos, :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
    change_column_null :variacoes_produtos, :sku, false

    # Remove o índice antigo criado na primeira migration
    remove_index :variacoes_produtos, column: :sku, name: "index_variacoes_produtos_on_sku"

    # Cria o índice composto limpo
    add_index :variacoes_produtos, [ :empresa_id, :sku ], unique: true, name: "index_variacoes_produtos_on_empresa_id_and_sku"
  end
end
