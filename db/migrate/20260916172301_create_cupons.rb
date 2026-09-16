class CreateCupons < ActiveRecord::Migration[8.1]
  def change
    create_table :cupons do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: false
      t.string :codigo, null: false
      t.integer :tipo, null: false, default: 0
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :valor_minimo_pedido, precision: 10, scale: 2, default: 0.0
      t.integer :limite_usos
      t.integer :usos_contagem, null: false, default: 0
      t.datetime :valido_de
      t.datetime :valido_ate
      t.boolean :ativo, null: false, default: true

      t.timestamps
    end

    add_index :cupons, [ :empresa_id, :codigo ], unique: true
  end
end
