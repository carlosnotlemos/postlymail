class Empresa < ApplicationRecord
  has_many :assinaturas, dependent: :destroy
  has_many :membros, dependent: :destroy
  has_many :convites, dependent: :destroy
  has_many :clientes, dependent: :destroy
  has_many :produto_categorias, dependent: :destroy
  has_many :cupons, dependent: :destroy
  has_many :campanhas, dependent: :destroy
  has_many :produtos, dependent: :destroy
  has_many :vendas, dependent: :destroy
  has_many :custos, dependent: :destroy
  has_many :estoque_movimentacoes, dependent: :destroy
  has_many :devolucoes, dependent: :destroy
  has_many :variacoes_produtos, class_name: "VariacaoProduto", dependent: :destroy

  before_validation :set_data_cadastro, on: :create

  validates :nome, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "deve conter apenas letras minúsculas, números e hífens" }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :data_cadastro, presence: true

  private

  def set_data_cadastro
    self.data_cadastro ||= Time.current
  end
end
