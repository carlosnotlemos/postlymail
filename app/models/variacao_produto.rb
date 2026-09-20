class VariacaoProduto < ApplicationRecord
  belongs_to :empresa
  belongs_to :produto
  has_one :estoque, dependent: :destroy
  has_many :insumos, class_name: "ProdutoInsumo", dependent: :destroy
  has_many :venda_itens, dependent: :restrict_with_error
  has_many :estoque_movimentacoes, dependent: :destroy

  before_validation :set_empresa_e_sanitizar_sku

  validates :preco_base, numericality: { greater_than_or_equal_to: 0 }
  validates :preco_custo, numericality: { greater_than_or_equal_to: 0 }
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :sku, presence: true, uniqueness: { scope: :empresa_id, case_sensitive: false }

  private

  def set_empresa_e_sanitizar_sku
    self.empresa_id ||= produto&.empresa_id
    self.sku = sku.to_s.strip.upcase if sku.present?
  end
end
