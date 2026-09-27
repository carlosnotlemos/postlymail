# frozen_string_literal: true

module Assinaturas
  class RotinaDiariaBillingJob < ApplicationJob
    queue_as :default

    def perform(dias_antecedencia = 7)
      processar_inadimplencia
      gerar_faturas_proximo_ciclo(dias_antecedencia)
    end

    private

    def processar_inadimplencia
      Assinaturas::ProcessarInadimplentesService.call
    rescue StandardError => e
      Rails.logger.error("[Billing] Erro ao processar rotina de inadimplência: #{e.message}")
    end

    def gerar_faturas_proximo_ciclo(dias_antecedencia)
      data_limite = Date.current + dias_antecedencia.days

      Assinatura.ativas.where("data_fim <= ?", data_limite).find_each do |assinatura|
        # 1. Isolamento individual por assinatura
        processar_faturamento_assinatura(assinatura, data_limite)
      rescue StandardError => e
        Rails.logger.error("[Billing] Falha isolada na assinatura ##{assinatura.id} (Empresa: ##{assinatura.empresa_id}): #{e.message}")
      end
    end

    def processar_faturamento_assinatura(assinatura, data_limite)
      # 2. Proteção sob concorrência via Pessimistic Lock (SELECT FOR UPDATE)
      assinatura.with_lock do
        # Revalidações atômicas sob lock
        return unless assinatura.ativa?
        return if assinatura.data_fim.present? && assinatura.data_fim > data_limite

        proxima_data_vencimento = assinatura.data_fim || Date.current

        # 3. Evita duplicar faturas se já existir fatura ativa (seja pendente ou já paga antecipadamente)
        fatura_existente = assinatura.faturas
                                     .where.not(status: :cancelada)
                                     .where(data_vencimento: proxima_data_vencimento)
                                     .exists?

        return if fatura_existente

        resultado = AssinaturaFaturas::GerarService.call(
          assinatura: assinatura,
          valor: assinatura.valor,
          data_vencimento: proxima_data_vencimento
        )

        if resultado.failure?
          Rails.logger.warn("[Billing] Falha ao gerar fatura para assinatura ##{assinatura.id}: #{resultado.error}")
        else
          Rails.logger.info("[Billing] Fatura gerada com sucesso para assinatura ##{assinatura.id} (Vencimento: #{proxima_data_vencimento})")
        end
      end
    end
  end
end
