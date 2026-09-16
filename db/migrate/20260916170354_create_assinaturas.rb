class CreateAssinaturas < ActiveRecord::Migration[8.1]
  def change
    create_table :assinaturas do |t|
      t.references :empresa, null: false, foreign_key: { on_delete: :cascade, on_update: :cascade }
      t.references :plano, null: false, foreign_key: { on_delete: :restrict, on_update: :cascade }
      t.integer :status, null: false, default: 0
      t.integer :ciclo, null: false, default: 0
      t.decimal :valor, precision: 10, scale: 2, null: false, default: 0.0
      t.date :data_inicio
      t.date :data_fim
      t.datetime :data_cancelamento

      t.timestamps
    end

    add_index :assinaturas, :empresa_id, unique: true, where: "status = 1", name: "index_assinaturas_on_empresa_ativa"
  end
end
