class AssinaturaFatura < ApplicationRecord
  belongs_to :assinatura
  has_one :empresa, through: :assinatura
  has_one :plano, through: :assinatura

  enum :status, { pendente: 0, paga: 1, cancelada: 2 }

  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :data_vencimento, presence: true
  validates :status, presence: true
  validates :gateway_id, uniqueness: true, allow_nil: true

  scope :pendentes, -> { where(status: :pendente) }
  scope :pagas, -> { where(status: :paga) }
  scope :canceladas, -> { where(status: :cancelada) }
  scope :vencidas, ->(data = Date.current) { where(status: :pendente).where("data_vencimento < ?", data) }
  scope :a_vencer, ->(data = Date.current) { where(status: :pendente).where("data_vencimento >= ?", data) }
  scope :recentes, -> { order(data_vencimento: :desc, created_at: :desc) }

  def vencida?(data = Date.current)
    pendente? && data_vencimento.present? && data_vencimento < data
  end
end
