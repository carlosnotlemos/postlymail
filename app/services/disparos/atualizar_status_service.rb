# frozen_string_literal: true

module Disparos
  class AtualizarStatusService < ApplicationService
    TRANSICOES_VALIDAS = {
      na_fila:   %i[enviado entregue falhou rejeitado cancelado],
      enviado:   %i[entregue falhou rejeitado],
      entregue:  %i[],
      falhou:    %i[na_fila enviado],
      rejeitado: %i[],
      cancelado: %i[]
    }.freeze

    def initialize(
      disparo_ou_hash = nil,
      disparo: nil,
      identificador_externo: nil,
      status: nil,
      mensagem_erro: nil,
      enviado_em: nil,
      forcar: false,
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
      dados[:identificador_externo] = identificador_externo if identificador_externo.present?
      dados[:status] = status if status.present?
      dados[:mensagem_erro] = mensagem_erro if mensagem_erro.present?
      dados[:enviado_em] = enviado_em if enviado_em.present?

      @disparo_param = dados[:disparo] || dados[:disparo_id] || dados[:id]
      @identificador_externo_param = dados[:identificador_externo]

      @disparo = resolver_disparo(@disparo_param) || resolver_por_identificador(@identificador_externo_param)
      @status_raw = dados[:status]
      @status = normalizar_status(@status_raw)
      @mensagem_erro = dados[:mensagem_erro]
      @enviado_em = dados[:enviado_em]
      @forcar = kwargs.key?(:forcar) ? kwargs[:forcar] : (forcar || dados[:forcar] || false)
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_atualizacao
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

    def resolver_por_identificador(identificador)
      return nil if identificador.blank?

      Disparo.find_by(identificador_externo: identificador.to_s.strip)
    end

    def normalizar_status(param)
      return nil if param.blank?
      return param.to_sym if param.is_a?(Symbol) && Disparo.statuses.key?(param.to_s)

      if param.is_a?(Integer)
        return Disparo.statuses.key(param)&.to_sym
      end

      param_str = param.to_s.strip.underscore
      Disparo.statuses.key?(param_str) ? param_str.to_sym : nil
    end

    def converter_para_datetime(valor)
      return valor if valor.is_a?(Time) || valor.is_a?(DateTime) || valor.is_a?(ActiveSupport::TimeWithZone)
      return valor.to_time if valor.respond_to?(:to_time)

      Time.zone.parse(valor.to_s) rescue nil
    end

    def validar_parametros
      if @disparo.nil?
        return failure("Disparo não informado ou não encontrado", error_code: :disparo_not_found)
      end

      if @status_raw.present? && @status.nil?
        return failure("Status informado inválido", error_code: :invalid_status)
      end

      if @status.present? && !status_pode_avancar?(@status)
        return failure(
          "Transição de status inválida de '#{@disparo.status}' para '#{@status}'",
          error_code: :invalid_status_transition
        )
      end

      nil
    end

    def status_pode_avancar?(novo_status)
      return true if @forcar
      return true if novo_status.nil?

      status_atual = @disparo.status.to_sym
      destino = novo_status.to_sym

      return true if status_atual == destino

      permitidos = TRANSICOES_VALIDAS[status_atual] || []
      permitidos.include?(destino)
    end

    def executar_atualizacao
      ActiveRecord::Base.transaction do
        @disparo.status = @status if @status.present?

        if @mensagem_erro.present?
          @disparo.mensagem_erro = @mensagem_erro
        elsif @status.in?(%i[enviado entregue])
          @disparo.mensagem_erro = nil
        end

        if @enviado_em.present?
          @disparo.enviado_em = converter_para_datetime(@enviado_em)
        elsif @status.in?(%i[enviado entregue]) && @disparo.enviado_em.blank?
          @disparo.enviado_em = Time.current
        end

        @disparo.save!
      end

      success(
        disparo: @disparo,
        status: @disparo.status,
        enviado_em: @disparo.enviado_em,
        mensagem_erro: @disparo.mensagem_erro
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  AtualizarStatusWebhookService = AtualizarStatusService
end
