class Custo < ApplicationRecord
  belongs_to :empresa
  belongs_to :venda, optional: true

  enum :categoria, { insumos_producao: 0, frete_entrega: 1, trafego_pago: 2, operacional_geral: 3, embalagem: 4 }

  validates :categoria, presence: true
  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :data_custo, presence: true
end
