class CreateVendas < ActiveRecord::Migration[8.1]
  def change
    create_table :vendas do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: false
      t.references :cliente, null: false, foreign_key: { on_delete: :restrict, on_update: :cascade }
      t.references :usuario, foreign_key: { on_delete: :nullify, on_update: :cascade }
      t.references :cupom, foreign_key: { on_delete: :nullify, on_update: :cascade }
      t.references :cancelado_por, foreign_key: { to_table: :usuarios, on_delete: :nullify, on_update: :cascade }
      t.string :codigo_cupom
      t.string :codigo_pedido, null: false
      t.decimal :subtotal_produtos, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :valor_frete, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :desconto_cupom, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :desconto_manual, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :valor_desconto, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :valor_total, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :tipo_entrega, null: false, default: 0
      t.jsonb :endereco_entrega, null: false, default: "{}"
      t.string :codigo_rastreio
      t.integer :status, null: false, default: 0
      t.datetime :data_venda, null: false
      t.text :observacoes
      t.datetime :cancelado_em
      t.text :motivo_cancelamento

      t.timestamps
    end

    add_index :vendas, [ :empresa_id, :codigo_pedido ], unique: true
    add_index :vendas, [ :empresa_id, :status ]
  end
end
