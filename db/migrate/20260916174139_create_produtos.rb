class CreateProdutos < ActiveRecord::Migration[8.1]
  def change
    create_table :produtos do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :produto_categoria, foreign_key: { on_delete: :nullify, on_update: :cascade }
      t.string :nome, null: false
      t.text :descricao
      t.boolean :ativo, null: false, default: true

      t.timestamps
    end

    add_index :produtos, [ :empresa_id, :ativo ]
  end
end
