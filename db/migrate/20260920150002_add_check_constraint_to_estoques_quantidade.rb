class AddCheckConstraintToEstoquesQuantidade < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :estoques, "quantidade >= 0", name: "check_estoques_quantidade_non_negative"
  end
end
