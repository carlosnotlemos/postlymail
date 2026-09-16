class CreateDevolucaoItens < ActiveRecord::Migration[8.1]
  def change
    create_table :devolucao_itens do |t|
      t.references :devolucao, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :venda_item, null: false, foreign_key: { on_delete: :restrict, on_update: :cascade }
      t.integer :quantidade, null: false, default: 1
      t.boolean :retornou_ao_estoque, null: false, default: true

      t.timestamps
    end
  end
end
