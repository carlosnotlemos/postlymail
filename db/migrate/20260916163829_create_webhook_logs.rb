class CreateWebhookLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_logs do |t|
      t.integer :provedor, null: false, default: 0
      t.string :evento
      t.string :identificador_externo
      t.jsonb :payload, null: false, default: "{}"
      t.integer :status, null: false, default: 0
      t.text :mensagem_erro
      t.datetime :processado_em

      t.timestamps
    end

    add_index :webhook_logs, [ :provedor, :identificador_externo ], unique: true, where: "identificador_externo IS NOT NULL"
  end
end
