class CreateEstoqueMovimentacoes < ActiveRecord::Migration[8.1]
  def change
    create_table :estoque_movimentacoes do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :variacao_produto, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :usuario, foreign_key: { on_delete: :nullify, on_update: :cascade }
      t.integer :tipo, null: false
      t.integer :quantidade, null: false
      t.integer :saldo_anterior, null: false
      t.integer :saldo_posterior, null: false
      t.string :origem_tipo
      t.bigint :origem_id
      t.string :motivo

      t.timestamps
    end

    add_index :estoque_movimentacoes, [ :origem_tipo, :origem_id ]
    add_index :estoque_movimentacoes, [ :empresa_id, :created_at ]
  end
end
