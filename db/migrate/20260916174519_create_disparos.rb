class CreateDisparos < ActiveRecord::Migration[8.1]
  def change
    create_table :disparos do |t|
      t.references :campanha, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :cliente, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :identificador_externo
      t.string :destinatario, null: false
      t.integer :status, null: false, default: 0
      t.datetime :enviado_em
      t.text :mensagem_erro

      t.timestamps
    end

    add_index :disparos, [ :campanha_id, :status ]
    add_index :disparos, :identificador_externo, where: "identificador_externo IS NOT NULL"
  end
end
