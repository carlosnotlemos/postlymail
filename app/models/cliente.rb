class Cliente < ApplicationRecord
  belongs_to :empresa
  has_many :enderecos, dependent: :destroy
  has_many :disparos, dependent: :destroy
  has_many :vendas, dependent: :restrict_with_error

  before_validation :set_data_cadastro, on: :create

  validates :nome, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :ativo, inclusion: { in: [ true, false ] }
  validates :aceita_marketing, inclusion: { in: [ true, false ] }
  validates :data_cadastro, presence: true

  private

  def set_data_cadastro
    self.data_cadastro ||= Time.current
  end
end
