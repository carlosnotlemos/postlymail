# frozen_string_literal: true

module Disparos
  class CriarService < ApplicationService
    def initialize(
      campanha_ou_hash = nil,
      cliente_ou_atributos = nil,
      campanha: nil,
      cliente: nil,
      destinatario: nil,
      status: nil,
      identificador_externo: nil,
      enviar_agora: false,
      processar_agora: false,
      permitir_duplicado: false,
      ignorar_consentimento: false,
      forcar: false,
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

      if cliente_ou_atributos.is_a?(Hash)
        dados.merge!(cliente_ou_atributos.symbolize_keys)
      elsif cliente_ou_atributos.is_a?(Cliente)
        dados[:cliente] ||= cliente_ou_atributos
      elsif cliente_ou_atributos.present? && !dados.key?(:cliente)
        dados[:cliente] = cliente_ou_atributos
      end

      dados[:campanha] = campanha if campanha.present?
      dados[:cliente] = cliente if cliente.present?
      dados[:destinatario] = destinatario if destinatario.present?
      dados[:status] = status if status.present?
      dados[:identificador_externo] = identificador_externo if identificador_externo.present?

      @campanha_param = dados[:campanha] || dados[:campanha_id]
      @campanha = resolver_campanha(@campanha_param)

      @cliente_param = dados[:cliente] || dados[:cliente_id]
      @cliente = resolver_cliente(@cliente_param)

      @destinatario_param = dados[:destinatario]
      @status_param = dados[:status] || :na_fila
      @identificador_externo = dados[:identificador_externo]

      @enviar_agora = kwargs.key?(:enviar_agora) ? kwargs[:enviar_agora] : (enviar_agora || processar_agora || dados[:processar_agora])
      @permitir_duplicado = kwargs.key?(:permitir_duplicado) ? kwargs[:permitir_duplicado] : (permitir_duplicado || dados[:permitir_duplicado])
      @forcar = kwargs.key?(:forcar) ? kwargs[:forcar] : (forcar || dados[:forcar] || false)
      @ignorar_consentimento = kwargs.key?(:ignorar_consentimento) ? kwargs[:ignorar_consentimento] : (ignorar_consentimento || dados[:ignorar_consentimento] || @forcar)
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_criacao
    end

    private

    def resolver_campanha(param)
      return param if param.is_a?(Campanha)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Campanha.find_by(id: param.to_i)
      end

      nil
    end

    def resolver_cliente(param)
      return param if param.is_a?(Cliente)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Cliente.find_by(id: param.to_i)
      end

      nil
    end

    def normalizar_status(param)
      return :na_fila if param.blank?
      return param.to_sym if param.is_a?(Symbol)

      if param.is_a?(Integer)
        return Disparo.statuses.key(param)&.to_sym || :na_fila
      end

      param_str = param.to_s.strip.underscore
      Disparo.statuses.key?(param_str) ? param_str.to_sym : :na_fila
    end

    def resolver_destinatario
      return @destinatario_param.to_s.strip if @destinatario_param.present?
      return nil if @cliente.nil? || @campanha.nil?

      if @campanha.email?
        @cliente.email.to_s.strip
      else
        @cliente.telefone.to_s.strip
      end
    end

    def validar_parametros
      if @campanha.nil?
        return failure("Campanha não informada ou não encontrada", error_code: :campaign_not_found)
      end

      if @cliente.nil?
        return failure("Cliente não informado ou não encontrado", error_code: :client_not_found)
      end

      if @campanha.empresa_id != @cliente.empresa_id
        return failure("Cliente e Campanha pertencem a empresas distintas", error_code: :unauthorized_tenant)
      end

      if @campanha.cancelada?
        return failure("Não é possível adicionar disparos a uma campanha cancelada", error_code: :campaign_cancelled)
      end

      unless @campanha.empresa&.ativo?
        return failure("Empresa inativa", error_code: :empresa_inactive)
      end

      unless @cliente.ativo? || @forcar
        return failure("Cliente encontra-se inativo", error_code: :client_inactive)
      end

      unless @cliente.aceita_marketing? || @ignorar_consentimento
        return failure("Cliente não autorizou o recebimento de comunicações de marketing", error_code: :client_marketing_opt_out)
      end

      destinatario = resolver_destinatario
      if destinatario.blank?
        return failure("Destinatário não informado para o disparo", error_code: :destination_blank)
      end

      unless @permitir_duplicado
        if @campanha.disparos.where(cliente_id: @cliente.id).exists?
          return failure("Já existe um disparo para este cliente nesta campanha", error_code: :disparo_already_exists)
        end
      end

      nil
    end

    def executar_criacao
      disparo = nil
      destinatario = resolver_destinatario
      status_inicial = normalizar_status(@status_param)

      ActiveRecord::Base.transaction do
        disparo = @campanha.disparos.build(
          cliente: @cliente,
          destinatario: destinatario,
          status: status_inicial,
          identificador_externo: @identificador_externo
        )
        disparo.save!
      end

      if @enviar_agora
        Disparos::ProcessarService.call(disparo: disparo)
      end

      disparo.reload
      success(
        disparo: disparo,
        campanha: @campanha,
        cliente: @cliente,
        enviado: disparo.enviado?,
        status: disparo.status.to_sym
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  SalvarService = CriarService
end

module Campanhas
  CriarDisparoService = Disparos::CriarService
end
