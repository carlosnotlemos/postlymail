class EstoqueMovimentacao < ApplicationRecord
  belongs_to :empresa
  belongs_to :variacao_produto
  belongs_to :usuario, optional: true
  belongs_to :origem, polymorphic: true, foreign_type: :origem_tipo, optional: true

  enum :tipo, { entrada_producao: 0, saida_venda: 1, estorno_devolucao: 2, ajuste_manual: 3, perda_avaria: 4, brinde_marketing: 5 }

  validates :tipo, presence: true
  validates :quantidade, numericality: { only_integer: true, greater_than: 0 }
  validates :saldo_anterior, numericality: { only_integer: true }
  validates :saldo_posterior, numericality: { only_integer: true }
end
