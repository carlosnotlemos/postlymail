class Usuario < ApplicationRecord
  has_many :membros, dependent: :destroy
  has_many :convites_enviados, class_name: "Convite", foreign_key: :convidado_por_id, dependent: :destroy
  has_many :vendas, dependent: :nullify
  has_many :estoque_movimentacoes, dependent: :nullify

  before_validation :set_data_cadastro, on: :create

  validates :nome, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :data_cadastro, presence: true

  private

  def set_data_cadastro
    self.data_cadastro ||= Time.current
  end
end
