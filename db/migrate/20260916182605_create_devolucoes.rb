class CreateDevolucoes < ActiveRecord::Migration[8.1]
  def change
    create_table :devolucoes do |t|
      t.references :venda, null: false, foreign_key: { on_delete: :restrict, on_update: :cascade }
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.integer :tipo, null: false, default: 0
      t.decimal :valor_estornado, precision: 10, scale: 2, null: false, default: 0.0
      t.text :motivo
      t.datetime :data_devolucao, null: false

      t.timestamps
    end

    add_index :devolucoes, [ :empresa_id, :data_devolucao ]
  end
end
