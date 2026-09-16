class CreateMembros < ActiveRecord::Migration[8.1]
  def change
    create_table :membros do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: false
      t.references :usuario, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :convidado_por, foreign_key: { to_table: :usuarios, on_delete: :nullify, on_update: :cascade }
      t.integer :papel, null: false, default: 0
      t.boolean :ativo, null: false, default: true
      t.datetime :data_entrada, null: false

      t.timestamps
    end

    add_index :membros, [ :empresa_id, :usuario_id ], unique: true
  end
end
