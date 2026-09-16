class Produto < ApplicationRecord
  belongs_to :empresa
  belongs_to :produto_categoria, optional: true
  has_many :variacoes, class_name: "VariacaoProduto", dependent: :destroy

  validates :nome, presence: true
  validates :ativo, inclusion: { in: [ true, false ] }
end
