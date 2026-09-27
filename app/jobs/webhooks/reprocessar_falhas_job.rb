# frozen_string_literal: true

module Webhooks
  class ReprocessarFalhasJob < ApplicationJob
    queue_as :default

    MAX_TENTATIVAS_REPROCESSAMENTO = 3

    # Erros que comprovadamente nunca serão recuperados reexecutando o job
    ERROS_NAO_RECUPERAVEIS = %w[
      empty_payload
      record_invalid
      provider_missing
      empty_event
      payload_missing
    ].freeze

    def perform(horas = 24)
      limite = horas.to_i.hours.ago

      logs_elegiveis(limite).find_each do |log|
        reprocessar_registro_com_seguranca(log)
      end
    end

    private

    def logs_elegiveis(limite)
      WebhookLog.where(status: :falhou)
                .where("created_at >= ?", limite)
    end

    def reprocessar_registro_com_seguranca(log)
      payload = log.payload.is_a?(Hash) ? log.payload : {}

      # 1. Filtro: Ignora erros estruturalmente irrecuperáveis ou já descartados
      if erro_definitivo?(log, payload)
        Rails.logger.info("[Webhooks::ReprocessarFalhas] Ignorando log ##{log.id}: erro definitivo/irrecuperável.")
        return
      end

      # 2. Anti-Loop: Verifica se já estourou o limite de tentativas
      tentativas = payload["_tentativas_reprocessamento"].to_i
      if tentativas >= MAX_TENTATIVAS_REPROCESSAMENTO
        marcar_como_descarte_definitivo!(log, tentativas)
        return
      end

      # 3. Execução Isolada e Atômica: Uma exceção em um log nunca derruba o lote
      log.with_lock do
        return unless log.falhou?

        # Incrementa contador antes de tentar
        novo_payload = payload.merge(
          "_tentativas_reprocessamento" => tentativas + 1,
          "_ultimo_reprocessamento_em" => Time.current.iso8601
        )
        log.update_columns(payload: novo_payload)
        log.reload

        resultado = Webhooks::ProcessarService.call(webhook_log: log, forcar: true)

        if resultado.success?
          Rails.logger.info("[Webhooks::ReprocessarFalhas] Log ##{log.id} recuperado com sucesso.")
        else
          Rails.logger.warn("[Webhooks::ReprocessarFalhas] Log ##{log.id} falhou novamente (tentativa #{tentativas + 1}/#{MAX_TENTATIVAS_REPROCESSAMENTO}): #{resultado.error}")
        end
      end
    rescue StandardError => e
      # Garante que o lote continua executando mesmo se houver erro imprevisto
      Rails.logger.error("[Webhooks::ReprocessarFalhas] Exceção inesperada ao reprocessar log ##{log.id}: #{e.message}")
    end

    def erro_definitivo?(log, payload)
      return true if payload["_descarte_definitivo"] == true

      mensagem = log.mensagem_erro.to_s.downcase
      ERROS_NAO_RECUPERAVEIS.any? { |motivo| mensagem.include?(motivo) }
    end

    def marcar_como_descarte_definitivo!(log, tentativas)
      payload = log.payload.is_a?(Hash) ? log.payload : {}
      log.update_columns(
        payload: payload.merge("_descarte_definitivo" => true),
        mensagem_erro: "[Descarte Definitivo: #{tentativas} tentativas esgotadas] #{log.mensagem_erro}"
      )
      Rails.logger.warn("[Webhooks::ReprocessarFalhas] Log ##{log.id} marcado como descarte definitivo.")
    end
  end
end
