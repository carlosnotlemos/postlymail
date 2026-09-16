class Devolucao < ApplicationRecord
  belongs_to :venda
  belongs_to :empresa
  has_many :itens, class_name: "DevolucaoItem", dependent: :destroy

  enum :tipo, { estorno_dinheiro: 0, credito_troca: 1, defeito_avaria: 2 }

  before_validation :set_data_devolucao, on: :create

  validates :tipo, presence: true
  validates :valor_estornado, numericality: { greater_than_or_equal_to: 0 }
  validates :data_devolucao, presence: true

  private

  def set_data_devolucao
    self.data_devolucao ||= Time.current
  end
end
