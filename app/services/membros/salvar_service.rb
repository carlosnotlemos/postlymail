# frozen_string_literal: true

module Membros
  class SalvarService < ApplicationService
    MEMBRO_ATTRS = %i[
      papel
      ativo
      data_entrada
    ].freeze

    def initialize(
      empresa_ou_hash = nil,
      membro_ou_atributos = nil,
      empresa: nil,
      membro: nil,
      usuario: nil,
      convidado_por: nil,
      atributos: nil,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if empresa_ou_hash.is_a?(Hash)
        dados.merge!(empresa_ou_hash.symbolize_keys)
      elsif empresa_ou_hash.present? && !dados.key?(:empresa)
        dados[:empresa] = empresa_ou_hash
      end

      if membro_ou_atributos.is_a?(Hash)
        dados.merge!(membro_ou_atributos.symbolize_keys)
      elsif membro_ou_atributos.present? && !dados.key?(:membro)
        dados[:membro] = membro_ou_atributos
      end

      dados[:empresa] = empresa if empresa.present?
      dados[:membro] = membro if membro.present?
      dados[:usuario] = usuario if usuario.present?
      dados[:convidado_por] = convidado_por if convidado_por.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @membro_param = dados[:membro]
      @membro = resolver_membro(@membro_param)

      @usuario_param = dados[:usuario] || dados[:usuario_id]
      @usuario = resolver_usuario(@usuario_param)

      @convidado_por_param = dados[:convidado_por] || dados[:convidado_por_id]
      @convidado_por = resolver_convidado_por(@convidado_por_param)

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

    def resolver_usuario(param)
      return param if param.is_a?(Usuario)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Usuario.find_by(id: param)
      end

      param_str = param.to_s.strip
      if param_str =~ /\A\d+\z/
        usuario = Usuario.find_by(id: param_str.to_i)
        return usuario if usuario
      end

      Usuario.find_by(email: param_str.downcase)
    end

    def resolver_convidado_por(param)
      resolver_usuario(param)
    end

    def resolver_membro(param)
      return param if param.is_a?(Membro)
      return nil if param.blank?

      if param.is_a?(Integer) || param.to_s =~ /\A\d+\z/
        return Membro.find_by(id: param.to_i)
      end

      nil
    end

    def extrair_atributos(dados)
      attrs = {}

      MEMBRO_ATTRS.each do |attr_name|
        attrs[attr_name] = dados[attr_name] if dados.key?(attr_name)
      end

      attrs[:papel] = dados[:papel] if dados.key?(:papel)
      attrs[:ativo] = dados[:ativo] if dados.key?(:ativo)

      attrs
    end

    def normalizar_atributos
      normalizar_papel
      normalizar_ativo
    end

    def normalizar_papel
      return unless @atributos_param.key?(:papel)

      valor = @atributos_param[:papel]
      return if valor.nil?

      if valor.is_a?(Symbol) || valor.is_a?(String)
        @atributos_param[:papel] = valor.to_s.downcase.strip
      elsif valor.is_a?(Integer)
        nome_papel = Membro.papels.key(valor)
        @atributos_param[:papel] = nome_papel if nome_papel
      end
    end

    def normalizar_ativo
      return unless @atributos_param.key?(:ativo)

      valor = @atributos_param[:ativo]
      return if valor.nil?

      if valor.is_a?(String)
        @atributos_param[:ativo] = ActiveModel::Type::Boolean.new.cast(valor)
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) if @empresa.nil?

      validacao_membro = validar_membro_e_usuario
      return validacao_membro if validacao_membro&.failure?

      validacao_convidado = validar_convidado_por
      return validacao_convidado if validacao_convidado&.failure?

      validacao_papel = validar_papel
      return validacao_papel if validacao_papel&.failure?

      validacao_proprietario = validar_protecao_ultimo_proprietario
      return validacao_proprietario if validacao_proprietario&.failure?

      nil
    end

    def validar_membro_e_usuario
      if @membro_param.present? && @membro.nil?
        return failure("Membro não informado ou não encontrado", error_code: :member_not_found)
      end

      if @membro.present?
        if @membro.empresa_id != @empresa.id
          return failure("Membro não pertence à empresa informada", error_code: :unauthorized_tenant)
        end
      else
        # Criação de novo membro
        if @usuario_param.present? && @usuario.nil?
          return failure("Usuário não informado ou não encontrado", error_code: :usuario_not_found)
        end

        return failure("Usuário não informado ou não encontrado", error_code: :usuario_not_found) if @usuario.nil?

        if @empresa.membros.exists?(usuario_id: @usuario.id)
          return failure("Usuário já é membro desta empresa", error_code: :member_already_exists)
        end
      end

      nil
    end

    def validar_convidado_por
      if @convidado_por_param.present? && @convidado_por.nil?
        return failure("Usuário que convidou não foi encontrado", error_code: :convidado_por_not_found)
      end

      nil
    end

    def validar_papel
      if @atributos_param.key?(:papel)
        papel = @atributos_param[:papel]
        unless Membro.papels.key?(papel.to_s)
          return failure("Papel informado é inválido", error_code: :invalid_role)
        end
      end

      nil
    end

    def validar_protecao_ultimo_proprietario
      return nil if @membro.nil?

      # Se o membro atual é um proprietário ativo
      if @membro.proprietario? && @membro.ativo?
        proprietarios_ativos = @empresa.membros.ativos.proprietarios.where.not(id: @membro.id).count

        # Tentativa de alterar o papel para outro que não seja proprietário
        if @atributos_param.key?(:papel) && @atributos_param[:papel].to_s != "proprietario" && proprietarios_ativos.zero?
          return failure(
            "Não é possível alterar o papel do único proprietário ativo da empresa",
            error_code: :last_owner_cannot_change_role
          )
        end

        # Tentativa de inativar via atributos
        if @atributos_param.key?(:ativo) && @atributos_param[:ativo] == false && proprietarios_ativos.zero?
          return failure(
            "Não é possível inativar o único proprietário ativo da empresa",
            error_code: :last_owner_cannot_be_inactivated
          )
        end
      end

      nil
    end

    def executar_salvamento
      ActiveRecord::Base.transaction do
        if @membro.nil?
          dados = @atributos_param.merge(usuario: @usuario)
          dados[:convidado_por] = @convidado_por if @convidado_por
          @membro = @empresa.membros.new(dados)
        else
          @membro.assign_attributes(@atributos_param) if @atributos_param.present?
          @membro.convidado_por = @convidado_por if @convidado_por_param.present?
        end

        @membro.save!
      end

      success(membro: @membro)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CadastrarService = SalvarService
  CriarService = SalvarService
  AtualizarService = SalvarService
end
