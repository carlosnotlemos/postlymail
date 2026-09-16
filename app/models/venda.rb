class Venda < ApplicationRecord
  belongs_to :empresa
  belongs_to :cliente
  belongs_to :usuario, optional: true
  belongs_to :cupom, optional: true
  belongs_to :cancelado_por, class_name: "Usuario", optional: true
  has_many :itens, class_name: "VendaItem", dependent: :destroy
  has_many :pagamentos, class_name: "VendaPagamento", dependent: :destroy
  has_many :custos, dependent: :nullify
  has_many :devolucoes, dependent: :restrict_with_error

  enum :tipo_entrega, { retirada: 0, motoboy_uber: 1, correios_pac: 2, correios_sedex: 3 }
  enum :status, { pendente: 0, paga: 1, enviada: 2, concluida: 3, cancelada: 4 }

  before_validation :set_data_venda, on: :create
  before_validation :generate_codigo_pedido, on: :create

  validates :codigo_pedido, presence: true, uniqueness: { scope: :empresa_id }
  validates :subtotal_produtos, numericality: { greater_than_or_equal_to: 0 }
  validates :valor_frete, numericality: { greater_than_or_equal_to: 0 }
  validates :valor_desconto, numericality: { greater_than_or_equal_to: 0 }
  validates :valor_total, numericality: { greater_than_or_equal_to: 0 }
  validates :tipo_entrega, presence: true
  validates :status, presence: true
  validates :data_venda, presence: true
  validates :motivo_cancelamento, presence: true, if: :cancelada?

  private

  def set_data_venda
    self.data_venda ||= Time.current
  end

  def generate_codigo_pedido
    self.codigo_pedido ||= "FT-#{SecureRandom.alphanumeric(6).upcase}"
  end
end
