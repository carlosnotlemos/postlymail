class CreateVariacoesProdutos < ActiveRecord::Migration[8.1]
  def change
    create_table :variacoes_produtos do |t|
      t.references :produto, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :sku
      t.string :codigo_barras
      t.string :tamanho
      t.string :cor
      t.decimal :preco_base, precision: 10, scale: 2, null: false, default: 0.0
      t.decimal :preco_custo, precision: 10, scale: 2, null: false, default: 0.0
      t.boolean :ativo, null: false, default: true

      t.timestamps
    end

    add_index :variacoes_produtos, :sku
    add_index :variacoes_produtos, :codigo_barras
  end
end
