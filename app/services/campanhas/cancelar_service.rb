# frozen_string_literal: true

module Campanhas
  class CancelarService < ApplicationService
    def initialize(
      campanha_ou_hash = nil,
      campanha: nil,
      empresa: nil,
      motivo: nil,
      ignorar_se_cancelada: false,
      cancelar_disparos_pendentes: true,
      **kwargs
    )
      dados = kwargs.dup

      if campanha_ou_hash.is_a?(Hash)
        dados.merge!(campanha_ou_hash.symbolize_keys)
      elsif campanha_ou_hash.is_a?(Campanha)
        dados[:campanha] ||= campanha_ou_hash
      elsif campanha_ou_hash.present? && !dados.key?(:campanha)
        dados[:campanha] = campanha_ou_hash
      end

      dados[:campanha] = campanha if campanha.present?
      dados[:empresa] = empresa if empresa.present?
      dados[:motivo] = motivo if motivo.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @campanha_param = dados[:campanha] || dados[:campanha_id] || dados[:id]
      @campanha = resolver_campanha(@campanha_param)
      @empresa ||= @campanha&.empresa

      @motivo = dados[:motivo]
      @ignorar_se_cancelada = ignorar_se_cancelada || dados[:ignorar_se_cancelada] || false
      @cancelar_disparos_pendentes = kwargs.key?(:cancelar_disparos_pendentes) ? kwargs[:cancelar_disparos_pendentes] : cancelar_disparos_pendentes
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @campanha.cancelada? && @ignorar_se_cancelada
        return success(
          campanha: @campanha,
          cancelada: false,
          ja_estava_cancelada: true,
          motivo: @motivo,
          disparos_cancelados_count: 0
        )
      end

      executar_cancelamento
    end

    private

    def resolver_campanha(param)
      return param if param.is_a?(Campanha)
      return nil if param.blank?

      id = if param.is_a?(Integer)
             param
      elsif param.is_a?(String) && param =~ /\A\d+\z/
             param.to_i
      end

      return nil if id.nil?

      if @empresa.present?
        campanha_empresa = @empresa.campanhas.find_by(id: id)
        return campanha_empresa if campanha_empresa
      end

      Campanha.find_by(id: id)
    end

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Empresa.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        empresa = Empresa.find_by(id: param_str.to_i)
        return empresa if empresa
      end

      Empresa.find_by(slug: param_str.downcase)
    end

    def validar_parametros
      if @campanha.nil?
        return failure("Campanha não informada ou não encontrada", error_code: :campaign_not_found)
      end

      if @empresa.present? && @campanha.empresa_id != @empresa.id
        return failure("Campanha não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @campanha.cancelada? && !@ignorar_se_cancelada
        return failure("Campanha já se encontra cancelada", error_code: :campaign_already_cancelled)
      end

      if @campanha.concluida?
        return failure("Não é possível cancelar uma campanha já concluída", error_code: :cannot_cancel_completed_campaign)
      end

      nil
    end

    def executar_cancelamento
      disparos_afetados = 0

      ActiveRecord::Base.transaction do
        @campanha.status = :cancelada
        @campanha.save!

        if @cancelar_disparos_pendentes
          disparos_pendentes = @campanha.disparos.where(status: :na_fila)
          disparos_afetados = disparos_pendentes.count

          motivo_cancelamento = @motivo.present? ? "Campanha cancelada: #{@motivo}" : "Campanha cancelada"
          disparos_pendentes.update_all(
            status: Disparo.statuses[:cancelado],
            mensagem_erro: motivo_cancelamento,
            updated_at: Time.current
          )
        end
      end

      success(
        campanha: @campanha,
        cancelada: true,
        ja_estava_cancelada: false,
        motivo: @motivo,
        disparos_cancelados_count: disparos_afetados
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  AnularService = CancelarService
end
