class CreateCustos < ActiveRecord::Migration[8.1]
  def change
    create_table :custos do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :venda, foreign_key: { on_delete: :nullify, on_update: :cascade }
      t.integer :categoria, null: false, default: 0
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0
      t.date :data_custo, null: false
      t.string :descricao

      t.timestamps
    end

    add_index :custos, [ :empresa_id, :categoria ]
    add_index :custos, [ :empresa_id, :data_custo ]
  end
end
