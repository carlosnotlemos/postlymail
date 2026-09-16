class CreatePlanos < ActiveRecord::Migration[8.1]
  def change
    create_table :planos do |t|
      t.integer :identificador, null: false
      t.string :nome, null: false
      t.decimal :valor_mensal, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :limite_produtos, default: 15
      t.integer :limite_disparos, null: false, default: 0
      t.integer :limite_usuarios, default: 2
      t.boolean :ativo, null: false, default: true

      t.timestamps
    end

    add_index :planos, :identificador, unique: true
  end
end
