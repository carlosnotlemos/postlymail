class Cupom < ApplicationRecord
  belongs_to :empresa
  has_many :vendas, dependent: :nullify

  enum :tipo, { porcentagem: 0, valor_fixo: 1 }

  before_validation :normalizar_codigo

  validates :codigo, presence: true, uniqueness: { scope: :empresa_id, case_sensitive: false, message: "já cadastrado para esta empresa" }
  validates :tipo, presence: true
  validates :valor, numericality: { greater_than: 0 }
  validates :valor, numericality: { less_than_or_equal_to: 100 }, if: :porcentagem?
  validates :valor_minimo_pedido, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :limite_usos, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :usos_contagem, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ativo, inclusion: { in: [ true, false ] }

  private

  def normalizar_codigo
    self.codigo = codigo.to_s.strip.upcase if codigo.present?
  end

  public

  def valido?
    return false unless ativo?
    return false if limite_usos.present? && usos_contagem >= limite_usos
    return false if valido_de.present? && Time.current < valido_de
    return false if valido_ate.present? && Time.current > valido_ate

    true
  end
end
