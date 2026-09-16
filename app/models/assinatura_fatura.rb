class AssinaturaFatura < ApplicationRecord
  belongs_to :assinatura

  enum :status, { pendente: 0, paga: 1, cancelada: 2 }

  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :data_vencimento, presence: true
  validates :status, presence: true
  validates :gateway_id, uniqueness: true, allow_nil: true
end
