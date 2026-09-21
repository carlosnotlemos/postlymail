class Assinatura < ApplicationRecord
  belongs_to :empresa
  belongs_to :plano
  has_many :faturas, class_name: "AssinaturaFatura", dependent: :destroy

  enum :status, { pendente: 0, ativa: 1, atrasada: 2, suspensa: 3, cancelada: 4 }
  enum :ciclo, { mensal: 0, trimestral: 1, anual: 2 }

  validates :status, presence: true
  validates :ciclo, presence: true
  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :empresa_id, uniqueness: { conditions: -> { where(status: :ativa) }, message: "já possui uma assinatura ativa" }, if: :ativa?

  scope :ativas, -> { where(status: :ativa) }
  scope :canceladas, -> { where(status: :cancelada) }
  scope :suspensas, -> { where(status: :suspensa) }
  scope :pendentes, -> { where(status: :pendente) }
  scope :atrasadas, -> { where(status: :atrasada) }
  scope :vigentes, ->(data = Date.current) { where("data_inicio <= :data AND (data_fim IS NULL OR data_fim >= :data)", data: data) }
  scope :recentes, -> { order(created_at: :desc) }

  def vigente?(data = Date.current)
    return false if data_inicio.blank?

    data_inicio <= data && (data_fim.nil? || data_fim >= data)
  end

  def dias_restantes(data = Date.current)
    return nil if data_fim.blank?

    [ (data_fim - data).to_i, 0 ].max
  end
end
