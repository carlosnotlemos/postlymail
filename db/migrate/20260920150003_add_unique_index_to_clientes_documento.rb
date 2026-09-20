class AddUniqueIndexToClientesDocumento < ActiveRecord::Migration[8.1]
  def up
    remove_index :clientes, column: [ :empresa_id, :documento ], if_exists: true
    add_index :clientes, [ :empresa_id, :documento ], unique: true, where: "documento IS NOT NULL AND documento != ''", name: "index_clientes_on_empresa_id_and_documento"
  end

  def down
    remove_index :clientes, name: "index_clientes_on_empresa_id_and_documento"
    add_index :clientes, [ :empresa_id, :documento ], name: "index_clientes_on_empresa_id_and_documento"
  end
end
