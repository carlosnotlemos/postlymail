class CreateEnderecos < ActiveRecord::Migration[8.1]
  def change
    create_table :enderecos do |t|
      t.references :cliente, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :titulo, default: "Principal"
      t.string :cep, limit: 10, null: false
      t.string :logradouro, null: false
      t.string :numero, limit: 50, null: false
      t.string :complemento
      t.string :bairro, null: false
      t.string :cidade, null: false
      t.string :estado, limit: 2, null: false
      t.text :ponto_referencia
      t.boolean :padrao, null: false, default: false

      t.timestamps
    end

    add_index :enderecos, :cliente_id, unique: true, where: "padrao = true", name: "index_enderecos_on_cliente_id_padrao"
  end
end
