# frozen_string_literal: true

module Webhooks
  class TransientError < StandardError; end

  class ProcessarWebhookJob < ApplicationJob
    queue_as :urgent

    retry_on ActiveRecord::Deadlocked, wait: 2.seconds, attempts: 3
    retry_on Webhooks::TransientError, wait: :exponentially_longer, attempts: 5

    discard_on ActiveJob::DeserializationError

    ERROS_TRANSITORIOS = %i[
      network_timeout
      connection_error
      gateway_unavailable
      rate_limit_exceeded
      database_locked
      service_unavailable
    ].freeze

    def perform(webhook_log_id)
      log = WebhookLog.find_by(id: webhook_log_id)
      return if log.nil?

      # Idempotência atômica no nível do banco via Row-Level Lock (SELECT FOR UPDATE)
      log.with_lock do
        return if log.processado? || log.duplicado_ignorado?

        resultado = Webhooks::ProcessarService.call(webhook_log: log)

        if resultado.failure?
          if transitivo?(resultado.error_code)
            # Falha de infraestrutura/transitória: entra na política de retry do Solid Queue
            raise TransientError, "Erro transitório no webhook ##{webhook_log_id}: #{resultado.error}"
          else
            # Falha definitiva de payload ou regra de negócio:
            # O service já atualizou o status para :falhou com a mensagem_erro no banco.
            # Não lançamos exceção para desobstruir a fila urgent imediatamente.
            Rails.logger.warn("[Webhooks] Falha definitiva no WebhookLog ##{webhook_log_id}: #{resultado.error} (Code: #{resultado.error_code})")
          end
        end
      end
    end

    private

    def transitivo?(error_code)
      ERROS_TRANSITORIOS.include?(error_code.to_s.to_sym)
    end
  end
end
