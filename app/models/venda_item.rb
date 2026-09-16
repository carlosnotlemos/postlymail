class VendaItem < ApplicationRecord
  belongs_to :venda
  belongs_to :variacao_produto
  has_many :devolucao_itens, dependent: :restrict_with_error

  before_validation :set_subtotal

  validates :quantidade, numericality: { only_integer: true, greater_than: 0 }
  validates :valor_unitario, numericality: { greater_than_or_equal_to: 0 }
  validates :preco_custo_unitario, numericality: { greater_than_or_equal_to: 0 }
  validates :subtotal, numericality: { greater_than_or_equal_to: 0 }

  private

  def set_subtotal
    self.valor_unitario ||= 0.0
    self.quantidade ||= 1
    self.subtotal = valor_unitario * quantidade
  end
end
