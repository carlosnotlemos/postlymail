class Usuario < ApplicationRecord
  has_many :membros, dependent: :destroy
  has_many :convites_enviados, class_name: "Convite", foreign_key: :convidado_por_id, dependent: :destroy
  has_many :vendas, dependent: :nullify
  has_many :estoque_movimentacoes, dependent: :nullify

  before_validation :sanitizar_dados
  before_validation :set_data_cadastro, on: :create

  validates :nome, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :data_cadastro, presence: true

  scope :ativos, -> { where(ativo: true) }
  scope :inativos, -> { where(ativo: false) }

  private

  def sanitizar_dados
    self.email = email.to_s.strip.downcase if email.present?
    self.nome = nome.to_s.strip if nome.present?
    if telefone.present?
      self.telefone = telefone.to_s.gsub(/\D/, "").presence
    elsif telefone.is_a?(String) && telefone.blank?
      self.telefone = nil
    end
  end

  def set_data_cadastro
    self.data_cadastro ||= Time.current
  end
end
