# frozen_string_literal: true

module AssinaturaFaturas
  class GerarService < ApplicationService
    FATURA_ATTRS = %i[
      valor
      data_vencimento
      data_pagamento
      status
      gateway_id
      metadados
    ].freeze

    def initialize(
      assinatura = nil,
      empresa: nil,
      valor: nil,
      data_vencimento: nil,
      data_pagamento: nil,
      status: nil,
      gateway_id: nil,
      metadados: nil,
      marcar_como_paga: false,
      permitir_assinatura_cancelada: false,
      atualizar_assinatura: true,
      atributos: nil,
      **kwargs
    )
      assinatura_alvo = assinatura || kwargs[:assinatura]
      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @assinatura_param = assinatura_alvo
      @assinatura = resolver_assinatura(assinatura_alvo) || resolver_assinatura_da_empresa(@empresa)
      @empresa ||= @assinatura&.empresa

      @marcar_como_paga = marcar_como_paga || kwargs[:marcar_como_paga] || false
      @permitir_assinatura_cancelada = permitir_assinatura_cancelada || kwargs[:permitir_assinatura_cancelada] || false
      @atualizar_assinatura = kwargs.key?(:atualizar_assinatura) ? kwargs[:atualizar_assinatura] : atualizar_assinatura

      @atributos_param = extrair_atributos(
        atributos,
        kwargs.merge(
          valor: valor,
          data_vencimento: data_vencimento,
          data_pagamento: data_pagamento,
          status: status,
          gateway_id: gateway_id,
          metadados: metadados
        )
      )

      normalizar_atributos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_geracao
    end

    private

    def resolver_assinatura(param)
      return param if param.is_a?(Assinatura)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Assinatura.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        Assinatura.find_by(id: param_str.to_i)
      end
    end

    def resolver_assinatura_da_empresa(empresa)
      return nil if empresa.nil?

      empresa.assinaturas.where(status: :ativa).first || empresa.assinaturas.order(created_at: :desc).first
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

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      attrs.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      FATURA_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name) && !kwargs[attr_name].nil?
      end

      attrs
    end

    def normalizar_atributos
      normalizar_valor
      normalizar_data_vencimento
      normalizar_status_e_pagamento
      normalizar_metadados
    end

    def normalizar_valor
      if @atributos_param.key?(:valor)
        valor = @atributos_param[:valor]
        if valor.is_a?(String)
          cleaned = valor.strip.gsub(/[R$\s]/, "")
          cleaned = cleaned.gsub(".", "").tr(",", ".") if cleaned.include?(",")
          @atributos_param[:valor] = BigDecimal(cleaned) rescue valor
        elsif valor.present?
          @atributos_param[:valor] = BigDecimal(valor.to_s) rescue valor
        end
      elsif @assinatura.present?
        @atributos_param[:valor] = @assinatura.valor
      end
    end

    def normalizar_data_vencimento
      if @atributos_param.key?(:data_vencimento)
        @atributos_param[:data_vencimento] = converter_para_data(@atributos_param[:data_vencimento])
      elsif @assinatura.present?
        ultima_fatura = @assinatura.faturas.order(data_vencimento: :desc).first
        if ultima_fatura&.data_vencimento.present?
          @atributos_param[:data_vencimento] = calcular_proximo_vencimento(ultima_fatura.data_vencimento)
        else
          @atributos_param[:data_vencimento] = @assinatura.data_inicio || Date.current
        end
      else
        @atributos_param[:data_vencimento] = Date.current
      end
    end

    def calcular_proximo_vencimento(data_base)
      ciclo = @assinatura&.ciclo || "mensal"
      case ciclo.to_s
      when "trimestral" then data_base + 3.months
      when "anual" then data_base + 1.year
      else data_base + 1.month
      end
    end

    def normalizar_status_e_pagamento
      if @marcar_como_paga
        @atributos_param[:status] = "paga"
        @atributos_param[:data_pagamento] ||= Time.current
      elsif @atributos_param.key?(:status)
        str = @atributos_param[:status].to_s.strip.downcase
        @atributos_param[:status] = str if AssinaturaFatura.statuses.key?(str)
      else
        @atributos_param[:status] = "pendente"
      end

      if @atributos_param[:status] == "paga"
        @atributos_param[:data_pagamento] ||= Time.current
      end

      if @atributos_param.key?(:data_pagamento) && @atributos_param[:data_pagamento].present?
        @atributos_param[:data_pagamento] = converter_para_datetime(@atributos_param[:data_pagamento])
      end
    end

    def normalizar_metadados
      @atributos_param[:metadados] = if @atributos_param[:metadados].is_a?(Hash)
                                       @atributos_param[:metadados].stringify_keys
      else
                                       {}
      end
    end

    def converter_para_data(valor)
      return valor if valor.is_a?(Date)
      return valor.to_date if valor.respond_to?(:to_date)

      Date.parse(valor.to_s) rescue nil
    end

    def converter_para_datetime(valor)
      return valor if valor.is_a?(Time) || valor.is_a?(DateTime) || valor.is_a?(ActiveSupport::TimeWithZone)
      return valor.to_time if valor.respond_to?(:to_time)

      Time.zone.parse(valor.to_s) rescue valor
    end

    def validar_parametros
      if @empresa_param.present? && @empresa.nil?
        return failure("Empresa não encontrada", error_code: :tenant_not_found)
      end

      if @assinatura.nil?
        return failure("Assinatura não informada ou não encontrada", error_code: :subscription_not_found)
      end

      if @empresa.present? && @assinatura.empresa_id != @empresa.id
        return failure("A assinatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @empresa.present? && !@empresa.ativo?
        return failure("A empresa encontra-se inativa", error_code: :empresa_inactive)
      end

      if @assinatura.cancelada? && !@permitir_assinatura_cancelada
        return failure("Não é possível gerar faturas para uma assinatura cancelada", error_code: :subscription_cancelled)
      end

      gateway_id = @atributos_param[:gateway_id]
      if gateway_id.present? && AssinaturaFatura.where(gateway_id: gateway_id).exists?
        return failure("Já existe uma fatura com este identificador de gateway", error_code: :gateway_id_already_exists)
      end

      valor = @atributos_param[:valor]
      if valor.nil? || valor < 0
        return failure("O valor da fatura deve ser maior ou igual a zero", error_code: :invalid_amount)
      end

      if @atributos_param[:data_vencimento].blank?
        return failure("Data de vencimento inválida", error_code: :invalid_due_date)
      end

      nil
    end

    def executar_geracao
      fatura = nil

      ActiveRecord::Base.transaction do
        fatura = AssinaturaFatura.create!(
          assinatura: @assinatura,
          valor: @atributos_param[:valor],
          data_vencimento: @atributos_param[:data_vencimento],
          data_pagamento: @atributos_param[:data_pagamento],
          status: @atributos_param[:status],
          gateway_id: @atributos_param[:gateway_id],
          metadados: @atributos_param[:metadados]
        )

        if fatura.paga? && @atualizar_assinatura
          ajustar_assinatura_apos_pagamento
        end
      end

      success(
        fatura: fatura,
        assinatura: @assinatura,
        empresa: @empresa || @assinatura.empresa
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end

    def ajustar_assinatura_apos_pagamento
      if @assinatura.status.in?(%w[pendente atrasada suspensa])
        @assinatura.status = :ativa
      end

      if !@assinatura.cancelada?
        data_base = [ @assinatura.data_fim || Date.current, Date.current ].max
        periodo = case @assinatura.ciclo.to_s
        when "trimestral" then 3.months
        when "anual" then 1.year
        else 1.month
        end

        @assinatura.data_fim = data_base + periodo
      end

      @assinatura.save! if @assinatura.changed?
    end
  end

  SalvarService = GerarService
  CriarService = GerarService
end

module Assinaturas
  GerarFaturaService = AssinaturaFaturas::GerarService
end
