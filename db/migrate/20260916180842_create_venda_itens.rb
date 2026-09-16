class CreateVendaItens < ActiveRecord::Migration[8.1]
  def change
    create_table :venda_itens do |t|
      t.references :venda, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :variacao_produto, null: false, foreign_key: { on_delete: :restrict, on_update: :cascade }
      t.jsonb :detalhes_produto, null: false, default: "{}"
      t.decimal :valor_unitario, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :preco_custo_unitario, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :quantidade, null: false, default: 1
      t.decimal :subtotal, precision: 10, scale: 2, null: false, default: 0.0
      t.text :observacoes

      t.timestamps
    end
  end
end
