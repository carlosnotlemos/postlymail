class CreateCampanhas < ActiveRecord::Migration[8.1]
  def change
    create_table :campanhas do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.string :nome, null: false
      t.integer :canal, null: false, default: 0
      t.string :assunto
      t.text :conteudo, null: false
      t.string :url_midia
      t.integer :segmento, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.datetime :data_envio

      t.timestamps
    end

    add_index :campanhas, [ :empresa_id, :status ]
  end
end
