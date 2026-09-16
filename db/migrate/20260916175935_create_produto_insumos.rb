class CreateProdutoInsumos < ActiveRecord::Migration[8.1]
  def change
    create_table :produto_insumos do |t|
      t.references :variacao_produto, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :nome, null: false
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0

      t.timestamps
    end
  end
end
