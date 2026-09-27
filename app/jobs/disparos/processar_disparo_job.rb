# frozen_string_literal: true

module Disparos
  class TransientError < StandardError; end

  class ProcessarDisparoJob < ApplicationJob
    queue_as :bulk

    # Retenta apenas em problemas temporários de rede ou deadlock
    retry_on ActiveRecord::Deadlocked, wait: 2.seconds, attempts: 3
    retry_on Disparos::TransientError, wait: :exponentially_longer, attempts: 3

    discard_on ActiveJob::DeserializationError

    # Códigos que indicam indisponibilidade temporária de rede ou rate limit do provedor
    ERROS_TRANSITORIOS = %i[
      network_timeout
      connection_error
      gateway_unavailable
      rate_limit_exceeded
      service_unavailable
    ].freeze

    def perform(disparo_id)
      disparo = Disparo.find_by(id: disparo_id)
      return if disparo.nil?

      # 1. Idempotência Atômica via Pessimistic Lock (SELECT FOR UPDATE)
      # Impede que duas workers enviem a mesma mensagem em paralelo
      disparo.with_lock do
        return if disparo.enviado? || disparo.entregue? || disparo.rejeitado? || disparo.cancelado?

        resultado = Disparos::ProcessarService.call(disparo: disparo)

        # 2. Tratamento Diferenciado de Falhas (Transitórias vs Definitivas)
        if resultado.failure?
          if transitivo?(resultado.error_code)
            # Erro temporário de infraestrutura: entra na política de retries do Solid Queue
            raise TransientError, "Erro transitório no disparo ##{disparo_id}: #{resultado.error}"
          else
            # Erro definitivo (e-mail inválido, destinatário malformado, etc.):
            # O service já marcou o disparo como :rejeitado ou :falhou no banco.
            # Não lançamos erro para não queimar tentativas nem gerar custos com a API externa.
            Rails.logger.warn("[Disparos] Falha definitiva no disparo ##{disparo_id}: #{resultado.error} (Code: #{resultado.error_code})")
          end
        end

        # 3. Atualização Atômica da Campanha Pai sem enfileirar jobs redundantes
        verificar_conclusao_campanha(disparo.campanha)
      end
    end

    private

    def transitivo?(error_code)
      ERROS_TRANSITORIOS.include?(error_code.to_s.to_sym)
    end

    def verificar_conclusao_campanha(campanha)
      return if campanha.nil? || !campanha.enviando?

      # Checagem ultrarrápida: se ainda houver mensagens na fila, não faz nada
      return if campanha.disparos.where(status: :na_fila).exists?

      # Se esta foi a última mensagem, faz o lock na campanha e marca como concluída
      campanha.with_lock do
        if campanha.enviando? && !campanha.disparos.where(status: :na_fila).exists?
          campanha.update!(status: :concluida, data_envio: Time.current)
          Rails.logger.info("[Campanhas] Campanha ##{campanha.id} finalizada com sucesso em tempo real.")
        end
      end
    end
  end
end
