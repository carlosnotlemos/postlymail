class ProdutoInsumo < ApplicationRecord
  belongs_to :variacao_produto

  validates :nome, presence: true
  validates :valor, numericality: { greater_than_or_equal_to: 0 }
end
