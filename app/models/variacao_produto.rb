class VariacaoProduto < ApplicationRecord
  belongs_to :produto
  has_one :estoque, dependent: :destroy
  has_many :insumos, class_name: "ProdutoInsumo", dependent: :destroy
  has_many :venda_itens, dependent: :restrict_with_error
  has_many :estoque_movimentacoes, dependent: :destroy

  validates :preco_base, numericality: { greater_than_or_equal_to: 0 }
  validates :preco_custo, numericality: { greater_than_or_equal_to: 0 }
  validates :ativo, inclusion: { in: [ true, false ] }
end
