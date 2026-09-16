class CreateEmpresas < ActiveRecord::Migration[8.1]
  def change
    create_table :empresas do |t|
      t.string :nome, null: false
      t.string :slug, null: false
      t.string :documento
      t.string :email, null: false
      t.boolean :ativo, null: false, default: true
      t.datetime :data_cadastro, null: false

      t.timestamps
    end

    add_index :empresas, :slug, unique: true
  end
end
