# frozen_string_literal: true

module Campanhas
  class DuplicarService < ApplicationService
    def initialize(
      campanha_ou_hash = nil,
      campanha: nil,
      empresa: nil,
      nome: nil,
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
      dados[:nome] = nome if nome.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @campanha_param = dados[:campanha] || dados[:campanha_id] || dados[:id]
      @campanha = resolver_campanha(@campanha_param)
      @empresa ||= @campanha&.empresa

      @nome = dados[:nome]
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_duplicacao
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

      empresa_alvo = @empresa || @campanha.empresa
      unless empresa_alvo&.ativo?
        return failure("Empresa inativa", error_code: :empresa_inactive)
      end

      nil
    end

    def executar_duplicacao
      novo_nome = @nome.presence || "#{@campanha.nome} (Cópia)"

      nova_campanha = @campanha.empresa.campanhas.build(
        nome: novo_nome,
        canal: @campanha.canal,
        assunto: @campanha.assunto,
        conteudo: @campanha.conteudo,
        url_midia: @campanha.url_midia,
        segmento: @campanha.segmento,
        status: :rascunho,
        data_envio: nil
      )

      nova_campanha.save!

      success(
        campanha: nova_campanha,
        original: @campanha
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  ClonarService = DuplicarService
end
