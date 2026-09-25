# frozen_string_literal: true

module Disparos
  class CancelarService < ApplicationService
    def initialize(
      disparo_ou_hash = nil,
      disparo: nil,
      motivo: nil,
      ignorar_se_cancelado: false,
      **kwargs
    )
      dados = kwargs.dup

      if disparo_ou_hash.is_a?(Hash)
        dados.merge!(disparo_ou_hash.symbolize_keys)
      elsif disparo_ou_hash.is_a?(Disparo)
        dados[:disparo] ||= disparo_ou_hash
      elsif disparo_ou_hash.present? && !dados.key?(:disparo)
        dados[:disparo] = disparo_ou_hash
      end

      dados[:disparo] = disparo if disparo.present?
      dados[:motivo] = motivo if motivo.present?

      @disparo_param = dados[:disparo] || dados[:disparo_id] || dados[:id]
      @disparo = resolver_disparo(@disparo_param)
      @motivo = dados[:motivo]
      @ignorar_se_cancelado = ignorar_se_cancelado || dados[:ignorar_se_cancelado] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @disparo.cancelado? && @ignorar_se_cancelado
        return success(
          disparo: @disparo,
          cancelado: false,
          ja_estava_cancelado: true,
          motivo: @motivo
        )
      end

      executar_cancelamento
    end

    private

    def resolver_disparo(param)
      return param if param.is_a?(Disparo)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Disparo.find_by(id: param.to_i)
      end

      Disparo.find_by(identificador_externo: param.to_s.strip)
    end

    def validar_parametros
      if @disparo.nil?
        return failure("Disparo não informado ou não encontrado", error_code: :disparo_not_found)
      end

      if @disparo.enviado? || @disparo.entregue?
        return failure("Não é possível cancelar um disparo já enviado ou entregue", error_code: :cannot_cancel_sent_disparo)
      end

      if @disparo.cancelado? && !@ignorar_se_cancelado
        return failure("Disparo já se encontra cancelado", error_code: :disparo_already_cancelled)
      end

      nil
    end

    def executar_cancelamento
      ActiveRecord::Base.transaction do
        @disparo.status = :cancelado
        @disparo.mensagem_erro = @motivo.presence || "Disparo cancelado"
        @disparo.save!
      end

      success(
        disparo: @disparo,
        cancelado: true,
        ja_estava_cancelado: false,
        motivo: @motivo
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  AnularService = CancelarService
end
