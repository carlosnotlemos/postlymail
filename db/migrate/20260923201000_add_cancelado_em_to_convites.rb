# frozen_string_literal: true

class AddCanceladoEmToConvites < ActiveRecord::Migration[8.1]
  def up
    add_column :convites, :cancelado_em, :datetime
    add_index :convites, :cancelado_em

    remove_index :convites, name: "index_convites_on_empresa_and_email_pendente"
    add_index :convites, [ :empresa_id, :email ],
              unique: true,
              where: "aceito_em IS NULL AND cancelado_em IS NULL",
              name: "index_convites_on_empresa_and_email_pendente"
  end

  def down
    remove_index :convites, name: "index_convites_on_empresa_and_email_pendente"
    add_index :convites, [ :empresa_id, :email ],
              unique: true,
              where: "aceito_em IS NULL",
              name: "index_convites_on_empresa_and_email_pendente"

    remove_index :convites, :cancelado_em
    remove_column :convites, :cancelado_em
  end
end
