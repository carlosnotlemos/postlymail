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
end
