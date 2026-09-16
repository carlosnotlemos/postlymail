class CreateAssinaturaFaturas < ActiveRecord::Migration[8.1]
  def change
    create_table :assinatura_faturas do |t|
      t.references :assinatura, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0
      t.date :data_vencimento, null: false
      t.datetime :data_pagamento
      t.integer :status, null: false, default: 0
      t.string :gateway_id
      t.jsonb :metadados, null: false, default: "{}"

      t.timestamps
    end

    add_index :assinatura_faturas, :gateway_id, unique: true, where: "gateway_id IS NOT NULL"
  end
end
