class CreateEstoques < ActiveRecord::Migration[8.1]
  def change
    create_table :estoques do |t|
      t.references :variacao_produto, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: { unique: true }
      t.integer :quantidade, null: false, default: 0
      t.integer :quantidade_minima, null: false, default: 5

      t.timestamps
    end
  end
end
