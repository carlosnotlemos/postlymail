class Estoque < ApplicationRecord
  belongs_to :variacao_produto

  validates :quantidade, numericality: { only_integer: true }
  validates :quantidade_minima, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :variacao_produto_id, uniqueness: true

  def estoque_baixo?
    quantidade <= quantidade_minima
  end
end
