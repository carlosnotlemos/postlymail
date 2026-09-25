# frozen_string_literal: true

module Assinaturas
  class ProcessarInadimplentesService < ApplicationService
    DEFAULT_DIAS_CARENCIA = 0
    DEFAULT_DIAS_SUSPENSAO = 7

    def initialize(
      assinatura = nil,
      empresa: nil,
      data_referencia: nil,
      dias_carencia: DEFAULT_DIAS_CARENCIA,
      dias_para_suspensao: DEFAULT_DIAS_SUSPENSAO,
      dias_para_cancelamento: nil,
      cancelar_inadimplentes: false,
      bloquear_empresa: true,
      reativar_adimplentes: true,
      dry_run: false,
      **kwargs
    )
      assinatura_alvo = assinatura || kwargs[:assinatura]
      @assinatura_param = assinatura_alvo
      @assinatura = resolver_assinatura(assinatura_alvo)

      @empresa_param = empresa || kwargs[:empresa]
      @empresa = resolver_empresa(@empresa_param)
      @empresa ||= @assinatura&.empresa

      @data_referencia = converter_para_data(data_referencia || kwargs[:data_referencia]) || Date.current
      @dias_carencia = (dias_carencia || kwargs[:dias_carencia] || DEFAULT_DIAS_CARENCIA).to_i
      @dias_para_suspensao = (dias_para_suspensao || kwargs[:dias_para_suspensao] || DEFAULT_DIAS_SUSPENSAO).to_i
      @dias_para_cancelamento = (dias_para_cancelamento || kwargs[:dias_para_cancelamento])&.to_i

      @cancelar_inadimplentes = kwargs.key?(:cancelar_inadimplentes) ? kwargs[:cancelar_inadimplentes] : cancelar_inadimplentes
      @cancelar_inadimplentes = true if @dias_para_cancelamento.present? && !kwargs.key?(:cancelar_inadimplentes)

      @bloquear_empresa = kwargs.key?(:bloquear_empresa) ? kwargs[:bloquear_empresa] : bloquear_empresa
      @reativar_adimplentes = kwargs.key?(:reativar_adimplentes) ? kwargs[:reativar_adimplentes] : reativar_adimplentes
      @dry_run = dry_run || kwargs[:dry_run] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_processamento
    end

    private

    def resolver_assinatura(param)
      return param if param.is_a?(Assinatura)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Assinatura.find_by(id: param.to_i)
      end

      nil
    end

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        empresa = Empresa.find_by(id: param.to_i)
        return empresa if empresa
      end

      Empresa.find_by(slug: param.to_s.strip.downcase)
    end

    def converter_para_data(valor)
      return valor if valor.is_a?(Date)
      return valor.to_date if valor.respond_to?(:to_date)

      Date.parse(valor.to_s) rescue nil
    end

    def validar_parametros
      if @assinatura_param.present? && @assinatura.nil?
        return failure("Assinatura não informada ou não encontrada", error_code: :subscription_not_found)
      end

      if @empresa_param.present? && @empresa.nil?
        return failure("Empresa não encontrada", error_code: :tenant_not_found)
      end

      if @assinatura.present? && @empresa.present? && @assinatura.empresa_id != @empresa.id
        return failure("A assinatura não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @dias_carencia < 0 || @dias_para_suspensao < 0
        return failure("Os dias de carência e suspensão devem ser maiores ou iguais a zero", error_code: :invalid_parameters)
      end

      if @dias_para_cancelamento.present? && @dias_para_cancelamento <= @dias_para_suspensao
        return failure("Os dias para cancelamento devem ser maiores que os dias para suspensão", error_code: :invalid_parameters)
      end

      nil
    end

    def assinaturas_elegiveis
      if @assinatura.present?
        return [@assinatura]
      end

      if @empresa.present?
        return @empresa.assinaturas.where.not(status: :cancelada).includes(:faturas, :empresa)
      end

      Assinatura.where.not(status: :cancelada).includes(:faturas, :empresa)
    end

    def executar_processamento
      marcadas_como_atrasadas = []
      marcadas_como_suspensas = []
      marcadas_como_canceladas = []
      reativadas = []
      empresas_bloqueadas = []
      empresas_reativadas = []
      detalhes = []

      alvos = assinaturas_elegiveis

      ActiveRecord::Base.transaction do
        alvos.each do |assinatura|
          resultado_assinatura = avaliar_assinatura(assinatura)
          next if resultado_assinatura.nil?

          detalhes << resultado_assinatura

          case resultado_assinatura[:acao]
          when :cancelar
            marcadas_como_canceladas << assinatura
          when :suspender
            marcadas_como_suspensas << assinatura
            if resultado_assinatura[:empresa_bloqueada]
              empresas_bloqueadas << assinatura.empresa
            end
          when :atrasar
            marcadas_como_atrasadas << assinatura
          when :reativar
            reativadas << assinatura
            if resultado_assinatura[:empresa_reativada]
              empresas_reativadas << assinatura.empresa
            end
          end
        end

        raise ActiveRecord::Rollback if @dry_run
      end

      total_alteradas = marcadas_como_atrasadas.size +
                        marcadas_como_suspensas.size +
                        marcadas_como_canceladas.size +
                        reativadas.size

      success(
        total_avaliadas: alvos.size,
        total_alteradas: total_alteradas,
        marcadas_como_atrasadas: marcadas_como_atrasadas,
        marcadas_como_suspensas: marcadas_como_suspensas,
        marcadas_como_canceladas: marcadas_como_canceladas,
        reativadas: reativadas,
        empresas_bloqueadas: empresas_bloqueadas.uniq,
        empresas_reativadas: empresas_reativadas.uniq,
        detalhes: detalhes,
        dry_run: @dry_run,
        data_referencia: @data_referencia
      )
    rescue StandardError => e
      failure("Erro inesperado ao processar inadimplentes: #{e.message}", error_code: :unexpected_error)
    end

    def avaliar_assinatura(assinatura)
      faturas_pendentes = assinatura.faturas.where(status: :pendente)
      faturas_vencidas = faturas_pendentes.where("data_vencimento < ?", @data_referencia).order(:data_vencimento)

      if faturas_vencidas.exists?
        fatura_mais_antiga = faturas_vencidas.first
        dias_atraso = (@data_referencia - fatura_mais_antiga.data_vencimento).to_i

        processar_inadimplencia(assinatura, dias_atraso, fatura_mais_antiga)
      else
        processar_adimplencia(assinatura)
      end
    end

    def processar_inadimplencia(assinatura, dias_atraso, fatura_mais_antiga)
      status_original = assinatura.status

      if @cancelar_inadimplentes && @dias_para_cancelamento.present? && dias_atraso >= @dias_para_cancelamento
        return nil if status_original == "cancelada"

        unless @dry_run
          assinatura.update!(status: :cancelada, data_cancelamento: Time.current)
        end

        {
          assinatura_id: assinatura.id,
          empresa_id: assinatura.empresa_id,
          acao: :cancelar,
          status_anterior: status_original,
          novo_status: "cancelada",
          dias_atraso: dias_atraso,
          fatura_id: fatura_mais_antiga.id
        }
      elsif dias_atraso >= @dias_para_suspensao
        empresa_foi_bloqueada = false
        assinatura_foi_suspensa = false

        if status_original != "suspensa"
          unless @dry_run
            assinatura.update!(status: :suspensa)
          end
          assinatura_foi_suspensa = true
        end

        if @bloquear_empresa && assinatura.empresa.ativo?
          unless @dry_run
            assinatura.empresa.update!(ativo: false)
          end
          empresa_foi_bloqueada = true
        end

        return nil unless assinatura_foi_suspensa || empresa_foi_bloqueada

        {
          assinatura_id: assinatura.id,
          empresa_id: assinatura.empresa_id,
          acao: :suspender,
          status_anterior: status_original,
          novo_status: "suspensa",
          dias_atraso: dias_atraso,
          empresa_bloqueada: empresa_foi_bloqueada,
          fatura_id: fatura_mais_antiga.id
        }
      elsif dias_atraso > @dias_carencia || (@dias_carencia.zero? && dias_atraso >= 1)
        return nil if status_original == "atrasada" || status_original == "suspensa"

        unless @dry_run
          assinatura.update!(status: :atrasada)
        end

        {
          assinatura_id: assinatura.id,
          empresa_id: assinatura.empresa_id,
          acao: :atrasar,
          status_anterior: status_original,
          novo_status: "atrasada",
          dias_atraso: dias_atraso,
          fatura_id: fatura_mais_antiga.id
        }
      end
    end

    def processar_adimplencia(assinatura)
      return nil unless @reativar_adimplentes
      return nil unless assinatura.inadimplente?

      status_original = assinatura.status
      empresa_foi_reativada = false

      unless @dry_run
        assinatura.update!(status: :ativa)

        if @bloquear_empresa && !assinatura.empresa.ativo?
          # Só reativa a empresa se não houver outras assinaturas inadimplentes na empresa
          outras_inadimplentes = assinatura.empresa.assinaturas
                                           .where.not(id: assinatura.id)
                                           .where(status: %i[atrasada suspensa])
                                           .exists?

          unless outras_inadimplentes
            assinatura.empresa.update!(ativo: true)
            empresa_foi_reativada = true
          end
        end
      end

      {
        assinatura_id: assinatura.id,
        empresa_id: assinatura.empresa_id,
        acao: :reativar,
        status_anterior: status_original,
        novo_status: "ativa",
        empresa_reativada: empresa_foi_reativada
      }
    end
  end

  ProcessarInadimplenciaService = ProcessarInadimplentesService
  VerificarInadimplentesService = ProcessarInadimplentesService
end

module AssinaturaFaturas
  ProcessarInadimplentesService = Assinaturas::ProcessarInadimplentesService
end
