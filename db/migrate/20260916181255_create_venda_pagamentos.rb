class CreateVendaPagamentos < ActiveRecord::Migration[8.1]
  def change
    create_table :venda_pagamentos do |t|
      t.references :venda, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.integer :gateway, null: false, default: 0
      t.string :gateway_id
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :taxa_operadora, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :valor_liquido, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :forma_pagamento, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :parcelas, null: false, default: 1
      t.datetime :data_liquidacao
      t.jsonb :metadados, null: false, default: "{}"

      t.timestamps
    end

    add_index :venda_pagamentos, [ :venda_id, :status ]
    add_index :venda_pagamentos, :gateway_id, where: "gateway_id IS NOT NULL"
  end
end
