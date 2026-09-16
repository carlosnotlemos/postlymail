class Convite < ApplicationRecord
  belongs_to :empresa
  belongs_to :convidado_por, class_name: "Usuario"

  enum :papel, { atendente: 0, estoquista: 1, gerente: 2, proprietario: 3 }

  has_secure_token :token

  before_validation :set_expira_em, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :papel, presence: true
  validates :token, presence: true, uniqueness: true
  validates :expira_em, presence: true
  validates :email, uniqueness: { scope: :empresa_id, conditions: -> { where(aceito_em: nil) }, message: "já possui convite pendente para esta empresa" }

  def pendente?
    aceito_em.nil? && expira_em > Time.current
  end

  def expirado?
    expira_em <= Time.current
  end

  private

  def set_expira_em
    self.expira_em ||= 7.days.from_now
  end
end
