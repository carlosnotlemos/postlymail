# frozen_string_literal: true

module Campanhas
  class MonitorarCampanhasJob < ApplicationJob
    queue_as :default

    # Margem de tolerância temporal: campanhas que entraram em :enviando
    # há menos de 2 minutos ainda podem estar gerando lotes de disparos
    BUFFER_ESTABILIDADE_ENVIO = 2.minutes

    def perform
      processar_campanhas_agendadas
      reconciliar_campanhas_concluidas
    end

    private

    def processar_campanhas_agendadas
      Campanha.agendada.where("data_envio <= ?", Time.current).find_each do |campanha|
        Campanhas::DispararCampanhaJob.perform_later(campanha.id)
      end
    end

    def reconciliar_campanhas_concluidas
      campanhas_elegiveis_para_conclusao.find_each do |campanha|
        campanha.with_lock do
          # Revalidação atômica sob lock pessimista
          next unless campanha.enviando?
          next if campanha.disparos.where(status: :na_fila).exists?

          # Preserva o data_envio original caso já preenchido
          campanha.update!(
            status: :concluida,
            data_envio: campanha.data_envio.presence || Time.current
          )

          Rails.logger.info("[Campanhas] Campanha ##{campanha.id} reconciliada para :concluida com sucesso.")
        end
      end
    end

    def campanhas_elegiveis_para_conclusao
      status_na_fila = Disparo.statuses[:na_fila]

      # 1. Anti-join via NOT EXISTS aproveitando index_disparos_on_campanha_id_and_status
      # 2. Margem de estabilidade temporal para evitar condição de corrida
      Campanha.enviando
        .where("campanhas.updated_at <= ?", BUFFER_ESTABILIDADE_ENVIO.ago)
        .where(
          "NOT EXISTS (
            SELECT 1 FROM disparos
            WHERE disparos.campanha_id = campanhas.id
              AND disparos.status = :status_na_fila
          )",
          status_na_fila: status_na_fila
        )
    end
  end
end
