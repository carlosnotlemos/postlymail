class CreateProdutoCategorias < ActiveRecord::Migration[8.1]
  def change
    create_table :produto_categorias do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: false
      t.string :nome, null: false
      t.string :slug, null: false
      t.boolean :ativo, null: false, default: true

      t.timestamps
    end

    add_index :produto_categorias, [ :empresa_id, :slug ], unique: true
  end
end
