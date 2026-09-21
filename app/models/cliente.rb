class Cliente < ApplicationRecord
  belongs_to :empresa
  has_many :enderecos, dependent: :destroy
  has_one :endereco_padrao, -> { where(padrao: true) }, class_name: "Endereco"
  has_many :disparos, dependent: :destroy
  has_many :vendas, dependent: :restrict_with_error

  before_validation :sanitizar_dados
  before_validation :set_data_cadastro, on: :create

  validates :nome, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :documento, uniqueness: { scope: :empresa_id, case_sensitive: false }, allow_blank: true
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :aceita_marketing, inclusion: { in: [ true, false ] }
  validates :data_cadastro, presence: true

  private

  def sanitizar_dados
    self.documento = documento.to_s.gsub(/\D/, "") if documento.present?
    self.email = email.to_s.strip.downcase if email.present?
  end

  def set_data_cadastro
    self.data_cadastro ||= Time.current
  end
end
