class CreateConvites < ActiveRecord::Migration[8.1]
  def change
    create_table :convites do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }, index: false
      t.references :convidado_por, null: false, foreign_key: { to_table: :usuarios, on_delete: :cascade, on_update: :cascade }
      t.string :email, null: false
      t.integer :papel, null: false, default: 0
      t.string :token, null: false
      t.datetime :expira_em, null: false
      t.datetime :aceito_em

      t.timestamps
    end

    add_index :convites, :token, unique: true
    add_index :convites, [ :empresa_id, :email ], unique: true, where: "aceito_em IS NULL", name: "index_convites_on_empresa_and_email_pendente"
  end
end
