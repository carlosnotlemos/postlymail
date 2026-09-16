class Cupom < ApplicationRecord
  belongs_to :empresa
  has_many :vendas, dependent: :nullify

  enum :tipo, { porcentagem: 0, valor_fixo: 1 }

  validates :codigo, presence: true, uniqueness: { scope: :empresa_id, message: "já cadastrado para esta empresa" }
  validates :tipo, presence: true
  validates :valor, numericality: { greater_than: 0 }
  validates :valor_minimo_pedido, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :limite_usos, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :usos_contagem, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ativo, inclusion: { in: [ true, false ] }

  def valido?
    return false unless ativo?
    return false if limite_usos.present? && usos_contagem >= limite_usos
    return false if valido_de.present? && Time.current < valido_de
    return false if valido_ate.present? && Time.current > valido_ate

    true
  end
end
