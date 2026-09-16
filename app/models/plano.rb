class Plano < ApplicationRecord
  enum :identificador, { start: 0, pro: 1, enterprise: 2 }

  has_many :assinaturas, dependent: :restrict_with_error

  validates :identificador, presence: true, uniqueness: true
  validates :nome, presence: true
  validates :valor_mensal, numericality: { greater_than_or_equal_to: 0 }
  validates :limite_disparos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :limite_produtos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :limite_usuarios, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validates :ativo, inclusion: { in: [ true, false ] }
end
