# frozen_string_literal: true

module Convites
  class CancelarService < ApplicationService
    def initialize(
      convite_ou_hash = nil,
      empresa: nil,
      convite: nil,
      motivo: nil,
      ignorar_se_cancelado: false,
      data_cancelamento: nil,
      **kwargs
    )
      dados = kwargs.dup

      if convite_ou_hash.is_a?(Hash)
        dados.merge!(convite_ou_hash.symbolize_keys)
      elsif convite_ou_hash.is_a?(Convite)
        dados[:convite] ||= convite_ou_hash
      elsif convite_ou_hash.present? && !dados.key?(:convite)
        dados[:convite] = convite_ou_hash
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:convite] = convite if convite.present?
      dados[:motivo] = motivo if motivo.present?

      @convite_param = dados[:convite] || dados[:token] || dados[:convite_id] || dados[:id]
      @convite = resolver_convite(@convite_param)

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)
      @empresa ||= @convite&.empresa if @empresa_param.blank?

      @motivo = dados[:motivo]
      @ignorar_se_cancelado = ignorar_se_cancelado || dados[:ignorar_se_cancelado] || false
      @data_cancelamento = data_cancelamento || dados[:data_cancelamento]
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @convite.cancelado? && @ignorar_se_cancelado
        return success(
          convite: @convite,
          cancelado: false,
          ja_estava_cancelado: true,
          motivo: @motivo,
          cancelado_em: @convite.cancelado_em
        )
      end

      executar_cancelamento
    end

    private

    def resolver_convite(param)
      return param if param.is_a?(Convite)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Convite.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        convite = Convite.find_by(id: param_str.to_i)
        return convite if convite
      end

      Convite.find_by(token: param_str)
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
      if @convite.nil?
        return failure("Convite não informado ou não encontrado", error_code: :invite_not_found)
      end

      if @empresa_param.present? && @empresa.present? && @convite.empresa_id != @empresa.id
        return failure("Convite não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @convite.aceito?
        return failure("Não é possível cancelar um convite que já foi aceito", error_code: :invite_already_accepted)
      end

      if @convite.cancelado? && !@ignorar_se_cancelado
        return failure("Convite já se encontra cancelado", error_code: :invite_already_cancelled)
      end

      nil
    end

    def executar_cancelamento
      ActiveRecord::Base.transaction do
        @convite.cancelado_em = @data_cancelamento || Time.current
        @convite.save!
      end

      success(
        convite: @convite,
        cancelado: true,
        ja_estava_cancelado: false,
        motivo: @motivo,
        cancelado_em: @convite.cancelado_em
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  RevogarService = CancelarService
  ExcluirService = CancelarService
end
