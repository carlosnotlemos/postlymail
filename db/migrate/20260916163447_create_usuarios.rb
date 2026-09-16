class CreateUsuarios < ActiveRecord::Migration[8.1]
  def change
    create_table :usuarios do |t|
      t.string :nome, null: false
      t.string :email, null: false
      t.string :telefone
      t.boolean :ativo, null: false, default: true
      t.datetime :data_cadastro, null: false

      t.timestamps
    end

    add_index :usuarios, :email, unique: true
  end
end
