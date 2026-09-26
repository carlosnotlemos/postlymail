# frozen_string_literal: true

class WebhookLog < ApplicationRecord
  enum :provedor, { asaas: 0, resend: 1 }
  enum :status, { pendente: 0, processado: 1, falhou: 2, duplicado_ignorado: 3 }

  validates :provedor, presence: true
  validates :status, presence: true
  validates :payload, presence: true
  validates :identificador_externo, uniqueness: { scope: :provedor }, allow_nil: true
end
