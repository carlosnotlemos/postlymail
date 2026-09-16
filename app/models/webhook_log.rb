class WebhookLog < ApplicationRecord
  enum :provedor, { asaas: 0, stripe: 1, mercadopago: 2, resend: 3, twilio: 4, zapi: 5 }
  enum :status, { pendente: 0, processado: 1, falhou: 2, duplicado_ignorado: 3 }

  validates :provedor, presence: true
  validates :status, presence: true
  validates :payload, presence: true
  validates :identificador_externo, uniqueness: { scope: :provedor }, allow_nil: true
end
