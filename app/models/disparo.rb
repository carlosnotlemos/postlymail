class Disparo < ApplicationRecord
  belongs_to :campanha
  belongs_to :cliente

  enum :status, { na_fila: 0, enviado: 1, entregue: 2, falhou: 3, rejeitado: 4, cancelado: 5 }

  validates :destinatario, presence: true
  validates :status, presence: true
end
