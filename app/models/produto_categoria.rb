class ProdutoCategoria < ApplicationRecord
  belongs_to :empresa
  has_many :produtos, dependent: :nullify

  validates :nome, presence: true
  validates :slug, presence: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "deve conter apenas letras minúsculas, números e hífens" }
  validates :slug, uniqueness: { scope: :empresa_id, message: "já existe nesta empresa" }
  validates :ativo, inclusion: { in: [ true, false ] }
end
