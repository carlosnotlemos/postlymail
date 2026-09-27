# frozen_string_literal: true

module Campanhas
  class DispararCampanhaJob < ApplicationJob
    queue_as :bulk

    retry_on ActiveRecord::Deadlocked, wait: 2.seconds, attempts: 3
    discard_on ActiveJob::DeserializationError

    def perform(campanha_id, forcar: false)
      campanha = Campanha.find_by(id: campanha_id)
      return if campanha.nil?

      # 1. Proteção atômica contra cliques duplos e concorrência via Pessimistic Lock
      campanha.with_lock do
        # Impede reprocessamento caso outro processo/worker já tenha iniciado ou concluído
        return if (campanha.concluida? || campanha.enviando?) && !forcar

        resultado = Campanhas::DispararService.call(
          campanha: campanha,
          processar_agora: false,
          forcar: forcar
        )

        return unless resultado.success?

        # 2. Transição de estado para campanhas que resultem em zero contatos
        disparos_pendentes = campanha.disparos.na_fila
        if disparos_pendentes.none?
          campanha.update!(status: :concluida, data_envio: Time.current)
          Rails.logger.info("[Campanhas] Campanha ##{campanha.id} finalizada imediatamente (zero contatos elegíveis no público-alvo).")
          return
        end

        # 3. Otimização em lote dos jobs de disparo com ActiveJob.perform_all_later
        disparos_pendentes.select(:id).find_in_batches(batch_size: 1000) do |lote|
          jobs = lote.map { |disparo| Disparos::ProcessarDisparoJob.new(disparo.id) }
          ActiveJob.perform_all_later(jobs)
        end

        Rails.logger.info("[Campanhas] Campanha ##{campanha.id} disparada com sucesso (#{disparos_pendentes.count} disparos enfileirados em lote).")
      end
    end
  end
end
