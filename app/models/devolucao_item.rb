class DevolucaoItem < ApplicationRecord
  belongs_to :devolucao
  belongs_to :venda_item

  validates :quantidade, numericality: { only_integer: true, greater_than: 0 }
  validates :retornou_ao_estoque, inclusion: { in: [ true, false ] }
end
