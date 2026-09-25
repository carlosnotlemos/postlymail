# frozen_string_literal: true

module Campanhas
  class SalvarService < ApplicationService
    CAMPANHA_ATTRS = %i[
      nome
      canal
      assunto
      conteudo
      url_midia
      segmento
      status
      data_envio
    ].freeze

    def initialize(
      campanha_ou_hash = nil,
      empresa: nil,
      campanha: nil,
      atributos: nil,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if campanha_ou_hash.is_a?(Hash)
        dados.merge!(campanha_ou_hash.symbolize_keys)
      elsif campanha_ou_hash.is_a?(Campanha)
        dados[:campanha] ||= campanha_ou_hash
      elsif campanha_ou_hash.present? && !dados.key?(:campanha)
        dados[:campanha] = campanha_ou_hash
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:campanha] = campanha if campanha.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @campanha_param = dados[:campanha] || dados[:campanha_id] || dados[:id]
      @campanha = resolver_campanha(@campanha_param)
      @empresa ||= @campanha&.empresa

      @atributos_param = extrair_atributos(dados)
      normalizar_atributos
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      executar_salvamento
    end

    private

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

    def extrair_atributos(dados)
      attrs = {}
      CAMPANHA_ATTRS.each do |attr_name|
        attrs[attr_name] = dados[attr_name] if dados.key?(attr_name)
      end
      attrs
    end

    def normalizar_atributos
      if @atributos_param.key?(:canal) && @atributos_param[:canal].present?
        @atributos_param[:canal] = normalizar_canal(@atributos_param[:canal])
      end

      if @atributos_param.key?(:segmento) && @atributos_param[:segmento].present?
        @atributos_param[:segmento] = normalizar_segmento(@atributos_param[:segmento])
      end

      if @atributos_param.key?(:status) && @atributos_param[:status].present?
        @atributos_param[:status] = normalizar_status(@atributos_param[:status])
      end

      if @atributos_param.key?(:data_envio) && @atributos_param[:data_envio].present?
        @atributos_param[:data_envio] = converter_para_datetime(@atributos_param[:data_envio])
      end

      if @atributos_param.key?(:nome) && @atributos_param[:nome].is_a?(String)
        @atributos_param[:nome] = @atributos_param[:nome].strip
      end

      if @atributos_param.key?(:assunto) && @atributos_param[:assunto].is_a?(String)
        @atributos_param[:assunto] = @atributos_param[:assunto].strip
      end

      if @atributos_param[:conteudo].blank? && @atributos_param[:url_midia].present?
        @atributos_param[:conteudo] ||= ""
      end
    end

    def normalizar_canal(param)
      return param if param.is_a?(Symbol)
      if param.is_a?(Integer)
        return Campanha.canals.key(param)&.to_sym
      end

      param_str = param.to_s.strip.underscore
      Campanha.canals.key?(param_str) ? param_str.to_sym : param
    end

    def normalizar_segmento(param)
      return param if param.is_a?(Symbol)
      if param.is_a?(Integer)
        return Campanha.segmentos.key(param)&.to_sym
      end

      param_str = param.to_s.strip.underscore
      Campanha.segmentos.key?(param_str) ? param_str.to_sym : param
    end

    def normalizar_status(param)
      return param if param.is_a?(Symbol)
      if param.is_a?(Integer)
        return Campanha.statuses.key(param)&.to_sym
      end

      param_str = param.to_s.strip.underscore
      Campanha.statuses.key?(param_str) ? param_str.to_sym : param
    end

    def converter_para_datetime(valor)
      return valor if valor.is_a?(Time) || valor.is_a?(DateTime) || valor.is_a?(ActiveSupport::TimeWithZone)
      return valor.to_time if valor.respond_to?(:to_time)

      Time.zone.parse(valor.to_s) rescue nil
    end

    def validar_parametros
      if @empresa.nil?
        return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found)
      end

      unless @empresa.ativo?
        return failure("Empresa inativa", error_code: :empresa_inactive)
      end

      validacao_campanha = validar_campanha_existente
      return validacao_campanha if validacao_campanha&.failure?

      validacao_conteudo = validar_regras_conteudo
      return validacao_conteudo if validacao_conteudo&.failure?

      validar_agendamento
    end

    def validar_campanha_existente
      if @campanha.nil? && @campanha_param.present?
        if Campanha.exists?(id: @campanha_param)
          return failure("Campanha não pertence à empresa informada", error_code: :unauthorized_tenant)
        end
        return failure("Campanha não encontrada", error_code: :campaign_not_found)
      end

      if @campanha.present?
        if @campanha.empresa_id != @empresa.id
          return failure("Campanha não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        if @campanha.concluida?
          return failure("Não é permitido modificar uma campanha já concluída", error_code: :cannot_modify_completed_campaign)
        end

        if @campanha.cancelada?
          return failure("Não é permitido modificar uma campanha cancelada", error_code: :cannot_modify_cancelled_campaign)
        end

        if @campanha.enviando?
          return failure("Não é permitido modificar uma campanha que está em processo de envio", error_code: :cannot_modify_sending_campaign)
        end
      end

      nil
    end

    def validar_regras_conteudo
      conteudo_alvo = @atributos_param.key?(:conteudo) ? @atributos_param[:conteudo] : @campanha&.conteudo
      url_midia_alvo = @atributos_param.key?(:url_midia) ? @atributos_param[:url_midia] : @campanha&.url_midia

      if conteudo_alvo.blank? && url_midia_alvo.blank?
        return failure("A campanha deve possuir ao menos conteúdo em texto ou URL de mídia", error_code: :empty_content)
      end

      canal_alvo = @atributos_param[:canal] || @campanha&.canal&.to_sym || :email
      assunto_alvo = @atributos_param.key?(:assunto) ? @atributos_param[:assunto] : @campanha&.assunto

      if canal_alvo.to_s == "email" && assunto_alvo.blank?
        return failure("Assunto é obrigatório para campanhas de e-mail", error_code: :email_subject_required)
      end

      nil
    end

    def validar_agendamento
      status_alvo = @atributos_param[:status] || @campanha&.status&.to_sym
      data_alvo = @atributos_param.key?(:data_envio) ? @atributos_param[:data_envio] : @campanha&.data_envio

      if status_alvo.to_s == "agendada"
        if data_alvo.blank?
          return failure("Data de envio é obrigatória para campanhas agendadas", error_code: :scheduled_date_required)
        end

        if data_alvo <= Time.current
          return failure("Data de envio agendada deve ser futura", error_code: :scheduled_date_in_the_past)
        end
      end

      nil
    end

    def executar_salvamento
      novo_registro = @campanha.nil?

      ActiveRecord::Base.transaction do
        if novo_registro
          @campanha = @empresa.campanhas.build(@atributos_param)
        else
          @campanha.assign_attributes(@atributos_param) if @atributos_param.present?
        end

        @campanha.save!
      end

      success(
        campanha: @campanha,
        criado: novo_registro,
        atualizado: !novo_registro
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CriarService = SalvarService
  AtualizarService = SalvarService
  CadastrarService = SalvarService
end
