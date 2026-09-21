class Custo < ApplicationRecord
  belongs_to :empresa
  belongs_to :venda, optional: true

  enum :categoria, { insumos_producao: 0, frete_entrega: 1, trafego_pago: 2, operacional_geral: 3, embalagem: 4 }

  def self.categorias
    categoria
  end

  validates :categoria, presence: true
  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  validates :data_custo, presence: true
  validate :venda_mesma_empresa

  scope :por_categoria, ->(categoria) { where(categoria: categoria) }
  scope :por_periodo, ->(inicio, fim) { where(data_custo: inicio..fim) }
  scope :sem_venda, -> { where(venda_id: nil) }
  scope :com_venda, -> { where.not(venda_id: nil) }
  scope :recentes, -> { order(data_custo: :desc, created_at: :desc) }

  private

  def venda_mesma_empresa
    return unless venda_id.present? && empresa_id.present?

    if venda && venda.empresa_id != empresa_id
      errors.add(:venda, "deve pertencer à mesma empresa do custo")
    end
  end
end
