class VendaPagamento < ApplicationRecord
  belongs_to :venda

  enum :gateway, { manual: 0, asaas: 1 }
  enum :forma_pagamento, { pix: 0, cartao_credito: 1, cartao_debito: 2, dinheiro: 3, boleto: 4 }
  enum :status, { pendente: 0, aprovado: 1, recusado: 2, estornado: 3, cancelado: 4 }

  before_validation :calcular_valor_liquido

  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :taxa_operadora, numericality: { greater_than_or_equal_to: 0 }
  validates :valor_liquido, numericality: true
  validates :parcelas, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :status, :forma_pagamento, :gateway, presence: true

  private

  def calcular_valor_liquido
    self.valor ||= 0.0
    self.taxa_operadora ||= 0.0
    self.valor_liquido = valor - taxa_operadora
  end
end
