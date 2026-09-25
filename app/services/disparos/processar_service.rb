# frozen_string_literal: true

module Disparos
  class ProcessarService < ApplicationService
    def initialize(
      disparo_ou_hash = nil,
      disparo: nil,
      identificador_externo: nil,
      simular_falha: false,
      motivo_falha: nil,
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
      dados[:motivo_falha] = motivo_falha if motivo_falha.present?

      @disparo_param = dados[:disparo] || dados[:disparo_id] || dados[:id]
      @disparo = resolver_disparo(@disparo_param)

      @identificador_externo = dados[:identificador_externo]
      @simular_falha = simular_falha || dados[:simular_falha] || false
      @motivo_falha = dados[:motivo_falha]
      @forcar = forcar || dados[:forcar] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_processamento
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

      if (@disparo.cancelado? || @disparo.campanha&.cancelada?) && !@forcar
        return failure("Disparo ou campanha se encontra cancelado", error_code: :disparo_cancelled)
      end

      if @disparo.rejeitado? && !@forcar
        return failure("Disparo foi rejeitado e não permite retentativa", error_code: :disparo_rejected)
      end

      if (@disparo.enviado? || @disparo.entregue?) && !@forcar
        return failure("Disparo já foi enviado anteriormente", error_code: :disparo_already_processed)
      end

      nil
    end

    def validar_destinatario
      campanha = @disparo.campanha
      destinatario = @disparo.destinatario.to_s.strip

      if destinatario.blank?
        return { valido: false, erro: "Destinatário não informado" }
      end

      if campanha.email?
        unless URI::MailTo::EMAIL_REGEXP.match?(destinatario)
          return { valido: false, erro: "Endereço de e-mail inválido: #{destinatario}" }
        end
      elsif campanha.whatsapp?
        digitos = destinatario.gsub(/\D/, "")
        if digitos.length < 8
          return { valido: false, erro: "Número de telefone WhatsApp inválido: #{destinatario}" }
        end
      end

      { valido: true }
    end

    def executar_processamento
      validacao_dest = validar_destinatario

      ActiveRecord::Base.transaction do
        if !validacao_dest[:valido]
          @disparo.status = :rejeitado
          @disparo.mensagem_erro = validacao_dest[:erro]
          @disparo.save!

          return success(
            disparo: @disparo,
            enviado: false,
            status: @disparo.status.to_sym,
            mensagem_erro: @disparo.mensagem_erro
          )
        end

        if @simular_falha
          @disparo.status = :falhou
          @disparo.mensagem_erro = @motivo_falha.presence || "Simulação de falha no envio"
          @disparo.save!

          return success(
            disparo: @disparo,
            enviado: false,
            status: @disparo.status.to_sym,
            mensagem_erro: @disparo.mensagem_erro
          )
        end

        # Disparo com sucesso
        novo_identificador = @identificador_externo.presence ||
                             @disparo.identificador_externo.presence ||
                             "pst_#{SecureRandom.hex(12)}"

        @disparo.status = :enviado
        @disparo.enviado_em = Time.current
        @disparo.identificador_externo = novo_identificador
        @disparo.mensagem_erro = nil
        @disparo.save!
      end

      success(
        disparo: @disparo,
        enviado: true,
        status: @disparo.status.to_sym,
        identificador_externo: @disparo.identificador_externo,
        enviado_em: @disparo.enviado_em
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  EnviarService = ProcessarService
  ExecutarService = ProcessarService
end

module Campanhas
  ProcessarDisparoService = Disparos::ProcessarService
end
