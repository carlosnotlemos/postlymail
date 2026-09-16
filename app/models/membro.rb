class Membro < ApplicationRecord
  belongs_to :empresa
  belongs_to :usuario
  belongs_to :convidado_por, class_name: "Usuario", optional: true

  enum :papel, { atendente: 0, estoquista: 1, gerente: 2, proprietario: 3 }

  before_validation :set_data_entrada, on: :create

  validates :papel, presence: true
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :data_entrada, presence: true
  validates :usuario_id, uniqueness: { scope: :empresa_id, message: "já é membro desta empresa" }

  private

  def set_data_entrada
    self.data_entrada ||= Time.current
  end
end
