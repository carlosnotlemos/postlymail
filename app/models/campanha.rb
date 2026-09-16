class Campanha < ApplicationRecord
  belongs_to :empresa
  has_many :disparos, dependent: :destroy

  enum :canal, { email: 0, whatsapp: 1 }
  enum :segmento, { todos: 0, com_compras: 1, sem_compras: 2 }
  enum :status, { rascunho: 0, agendada: 1, enviando: 2, concluida: 3, cancelada: 4 }

  validates :nome, presence: true
  validates :canal, presence: true
  validates :conteudo, presence: true
  validates :segmento, presence: true
  validates :status, presence: true
  validates :assunto, presence: true, if: :email?
end
