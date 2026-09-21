# frozen_string_literal: true

module Assinaturas
  class SalvarService < ApplicationService
    ASSINATURA_ATTRS = %i[
      ciclo
      status
      valor
      data_inicio
      data_fim
      data_cancelamento
    ].freeze

    def initialize(
      empresa: nil,
      plano: nil,
      assinatura: nil,
      atributos: nil,
      substituir_atual: false,
      cancelar_anterior: false,
      gerar_fatura_inicial: false,
      **kwargs
    )
      @assinatura_param = assinatura || kwargs[:assinatura]
      @assinatura = resolver_assinatura(@assinatura_param)

      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param) || @assinatura&.empresa

      @plano_param = plano || kwargs[:plano]
      @plano = resolver_plano(@plano_param) || @assinatura&.plano

      @substituir_atual = substituir_atual || cancelar_anterior || kwargs[:substituir_atual] || kwargs[:cancelar_anterior] || false
      @gerar_fatura_inicial = gerar_fatura_inicial || kwargs[:gerar_fatura_inicial] || false

      @atributos_param = extrair_atributos(atributos, kwargs)
      normalizar_atributos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento
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

    def resolver_plano(param)
      return param if param.is_a?(Plano)
      return nil if param.blank?

      if param.is_a?(Integer)
        plano = Plano.find_by(id: param)
        return plano if plano

        return Plano.find_by(identificador: param) if Plano.identificadores.value?(param)
      end

      param_str = param.to_s.strip.downcase
      if Plano.identificadores.key?(param_str)
        plano = Plano.find_by(identificador: param_str)
        return plano if plano
      end

      if param.is_a?(String) && param.strip =~ /\A\d+\z/
        Plano.find_by(id: param.strip.to_i)
      end
    end

    def extrair_atributos(atributos, kwargs)
      attrs = {}
      attrs.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      ASSINATURA_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def normalizar_atributos
      normalizar_ciclo
      normalizar_status
      normalizar_valor
      normalizar_datas
      normalizar_data_cancelamento
    end

    def normalizar_ciclo
      if @atributos_param.key?(:ciclo)
        valor = @atributos_param[:ciclo]
        if valor.present?
          str = valor.to_s.strip.downcase
          @atributos_param[:ciclo] = str if Assinatura.ciclos.key?(str)
        end
      elsif @assinatura.nil?
        @atributos_param[:ciclo] = "mensal"
      end
    end

    def normalizar_status
      if @atributos_param.key?(:status)
        valor = @atributos_param[:status]
        if valor.present?
          str = valor.to_s.strip.downcase
          @atributos_param[:status] = str if Assinatura.statuses.key?(str)
        end
      elsif @assinatura.nil?
        @atributos_param[:status] = "ativa"
      end
    end

    def normalizar_valor
      if @atributos_param.key?(:valor)
        valor = @atributos_param[:valor]
        if valor.is_a?(String)
          cleaned = valor.strip.gsub(/[R$\s]/, "")
          if cleaned.include?(",")
            cleaned = cleaned.gsub(".", "").tr(",", ".")
          end
          @atributos_param[:valor] = BigDecimal(cleaned) rescue valor
        end
      elsif @assinatura.nil? && @plano.present?
        # Cálculo automático baseado no plano e ciclo
        @atributos_param[:valor] = calcular_valor_por_ciclo
      end
    end

    def calcular_valor_por_ciclo
      return BigDecimal("0.0") if @plano.nil? || @plano.valor_mensal.nil?

      ciclo_atual = @atributos_param[:ciclo] || "mensal"
      multiplicador = case ciclo_atual.to_s
      when "trimestral" then 3
      when "anual" then 12
      else 1
      end

      @plano.valor_mensal * multiplicador
    end

    def normalizar_datas
      if @atributos_param.key?(:data_inicio)
        @atributos_param[:data_inicio] = converter_para_data(@atributos_param[:data_inicio])
      elsif @assinatura.nil?
        @atributos_param[:data_inicio] = Date.current
      end

      if @atributos_param.key?(:data_fim)
        @atributos_param[:data_fim] = converter_para_data(@atributos_param[:data_fim])
      elsif @assinatura.nil? && @atributos_param[:data_inicio].present?
        data_ini = @atributos_param[:data_inicio]
        ciclo_atual = @atributos_param[:ciclo] || "mensal"
        @atributos_param[:data_fim] = case ciclo_atual.to_s
        when "trimestral" then data_ini + 3.months
        when "anual" then data_ini + 1.year
        else data_ini + 1.month
        end
      end
    end

    def converter_para_data(valor)
      return valor if valor.is_a?(Date)
      return valor.to_date if valor.respond_to?(:to_date)

      Date.parse(valor.to_s) rescue valor
    end

    def normalizar_data_cancelamento
      if @atributos_param[:status] == "cancelada"
        @atributos_param[:data_cancelamento] ||= Time.current
      end
    end

    def validar_parametros
      if @assinatura.nil? && @assinatura_param.present?
        return failure("Assinatura não informada ou não encontrada", error_code: :subscription_not_found)
      end

      if @empresa.nil?
        return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found)
      end

      if !@empresa.ativo?
        return failure("A empresa encontra-se inativa", error_code: :empresa_inactive)
      end

      if @assinatura.present? && @assinatura.empresa_id != @empresa.id
        return failure("A assinatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @plano.nil?
        return failure("Plano não informado ou não encontrado", error_code: :plan_not_found)
      end

      if !@plano.ativo? && (@assinatura.nil? || @assinatura.plano_id != @plano.id)
        return failure("O plano selecionado não está ativo para contratação", error_code: :plan_inactive)
      end

      validacao_datas = validar_coerencia_datas
      return validacao_datas if validacao_datas&.failure?

      validacao_assinatura_ativa = validar_conflito_assinatura_ativa
      return validacao_assinatura_ativa if validacao_assinatura_ativa&.failure?

      nil
    end

    def validar_coerencia_datas
      data_ini = @atributos_param[:data_inicio] || @assinatura&.data_inicio
      data_fim = @atributos_param[:data_fim] || @assinatura&.data_fim

      return nil if data_ini.blank? || data_fim.blank?

      if data_fim < data_ini
        return failure("A data final não pode ser anterior à data de início", error_code: :invalid_dates)
      end

      nil
    end

    def validar_conflito_assinatura_ativa
      status_alvo = @atributos_param[:status] || @assinatura&.status
      return nil unless status_alvo == "ativa"

      outras_ativas = @empresa.assinaturas.where(status: :ativa)
      outras_ativas = outras_ativas.where.not(id: @assinatura.id) if @assinatura.present?
      @assinatura_ativa_conflitante = outras_ativas.first

      if @assinatura_ativa_conflitante.present? && !@substituir_atual
        return failure("Empresa já possui uma assinatura ativa", error_code: :company_already_has_active_subscription)
      end

      nil
    end

    def executar_salvamento
      fatura_gerada = nil
      assinatura_substituida = nil

      ActiveRecord::Base.transaction do
        if @assinatura_ativa_conflitante.present? && @substituir_atual
          @assinatura_ativa_conflitante.update!(
            status: :cancelada,
            data_cancelamento: Time.current
          )
          assinatura_substituida = @assinatura_ativa_conflitante
        end

        if @assinatura.nil?
          @assinatura = Assinatura.new(@atributos_param.merge(empresa: @empresa, plano: @plano))
        else
          @assinatura.assign_attributes(@atributos_param)
          @assinatura.empresa = @empresa if @empresa
          @assinatura.plano = @plano if @plano
        end

        @assinatura.save!

        if @gerar_fatura_inicial
          fatura_gerada = AssinaturaFatura.create!(
            assinatura: @assinatura,
            valor: @assinatura.valor,
            data_vencimento: @assinatura.data_inicio || Date.current,
            status: :pendente
          )
        end
      end

      dados_retorno = {
        assinatura: @assinatura,
        empresa: @empresa,
        plano: @plano
      }
      dados_retorno[:fatura] = fatura_gerada if fatura_gerada.present?
      dados_retorno[:assinatura_substituida] = assinatura_substituida if assinatura_substituida.present?

      success(dados_retorno)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
  CriarService = SalvarService
  AtualizarService = SalvarService
  ContratarService = SalvarService
end
