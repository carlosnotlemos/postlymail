class Convite < ApplicationRecord
  belongs_to :empresa
  belongs_to :convidado_por, class_name: "Usuario"

  enum :papel, { atendente: 0, estoquista: 1, gerente: 2, proprietario: 3 }

  singleton_class.alias_method :papels, :papeis

  has_secure_token :token

  alias_attribute :deleted_at, :cancelado_em

  before_validation :sanitizar_dados
  before_validation :set_expira_em, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :papel, presence: true
  validates :token, presence: true, uniqueness: true
  validates :expira_em, presence: true
  validates :email, uniqueness: { scope: :empresa_id, conditions: -> { where(aceito_em: nil, cancelado_em: nil) }, message: "já possui convite pendente para esta empresa" }

  scope :nao_cancelados, -> { where(cancelado_em: nil) }
  scope :cancelados, -> { where.not(cancelado_em: nil) }
  scope :pendentes, -> { nao_cancelados.where(aceito_em: nil).where("expira_em > ?", Time.current) }
  scope :aceitos, -> { where.not(aceito_em: nil) }
  scope :expirados, -> { nao_cancelados.where(aceito_em: nil).where("expira_em <= ?", Time.current) }
  scope :por_papel, ->(papel) { where(papel: papel) }

  def pendente?
    aceito_em.nil? && cancelado_em.nil? && expira_em > Time.current
  end

  def expirado?
    aceito_em.nil? && cancelado_em.nil? && expira_em <= Time.current
  end

  def aceito?
    aceito_em.present?
  end

  def cancelado?
    cancelado_em.present?
  end

  private

  def sanitizar_dados
    self.email = email.to_s.strip.downcase if email.present?
  end

  def set_expira_em
    self.expira_em ||= 7.days.from_now
  end
end
