class CreateClientes < ActiveRecord::Migration[8.1]
  def change
    create_table :clientes do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :nome, null: false
      t.string :documento
      t.string :email
      t.string :telefone
      t.boolean :ativo, null: false, default: true
      t.boolean :aceita_marketing, null: false, default: true
      t.datetime :data_cadastro, null: false

      t.timestamps
    end

    add_index :clientes, [ :empresa_id, :email ]
    add_index :clientes, [ :empresa_id, :documento ]
  end
end
