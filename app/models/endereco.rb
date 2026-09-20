class Endereco < ApplicationRecord
  belongs_to :cliente

  before_validation :sanitizar_cep

  validates :cep, presence: true, format: { with: /\A\d{8}\z/, message: "deve conter 8 dígitos numéricos" }
  validates :logradouro, presence: true
  validates :numero, presence: true
  validates :bairro, presence: true
  validates :cidade, presence: true
  validates :estado, presence: true, length: { is: 2 }
  validates :padrao, inclusion: { in: [ true, false ] }
  validates :cliente_id, uniqueness: { conditions: -> { where(padrao: true) }, message: "já possui um endereço padrão" }, if: :padrao?

  private

  def sanitizar_cep
    self.cep = cep.to_s.gsub(/\D/, "") if cep.present?
  end
end
