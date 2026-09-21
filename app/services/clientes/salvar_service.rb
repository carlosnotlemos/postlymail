module Clientes
  class SalvarService < ApplicationService
    CLIENTE_ATTRS = %i[nome email telefone documento ativo aceita_marketing].freeze

    def initialize(
      empresa: nil,
      cliente: nil,
      atributos: nil,
      endereco: nil,
      definir_endereco_padrao: nil,
      upsert_por_documento: false,
      **kwargs
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @cliente_param = cliente
      @cliente = resolver_cliente(cliente)

      @atributos_param = extrair_atributos_cliente(atributos, kwargs)
      @endereco_param = endereco
      @definir_endereco_padrao = definir_endereco_padrao
      @upsert_por_documento = upsert_por_documento
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

      Empresa.find_by(id: param)
    end

    def resolver_cliente(param)
      return param if param.is_a?(Cliente)
      return nil if param.blank? || @empresa.nil?

      @empresa.clientes.find_by(id: param)
    end

    def extrair_atributos_cliente(atributos, kwargs)
      attrs = {}
      if atributos.is_a?(Hash)
        attrs.merge!(atributos.symbolize_keys)
      end

      CLIENTE_ATTRS.each do |attr_name|
        attrs[attr_name] = kwargs[attr_name] if kwargs.key?(attr_name)
      end

      attrs
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cliente = validar_cliente
      return validacao_cliente if validacao_cliente&.failure?

      validacao_documento = validar_documento_duplicado
      return validacao_documento if validacao_documento&.failure?

      validar_endereco
    end

    def validar_cliente
      if @cliente.nil? && @cliente_param.present?
        if @cliente_param.is_a?(Cliente)
          return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        if Cliente.exists?(id: @cliente_param)
          return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Cliente não informado ou não encontrado", error_code: :client_not_found)
      end

      if @cliente && @cliente.empresa_id != @empresa.id
        return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_documento_duplicado
      doc = @atributos_param[:documento]
      return nil if doc.blank?

      doc_sanitizado = doc.to_s.gsub(/\D/, "")
      return nil if doc_sanitizado.blank?

      existente = @empresa.clientes.find_by(documento: doc_sanitizado)
      return nil unless existente

      if @cliente.present?
        if existente.id != @cliente.id
          return failure("Já existe um cliente cadastrado com este documento nesta empresa", error_code: :document_already_exists)
        end
      else
        if @upsert_por_documento
          @cliente = existente
        else
          return failure("Já existe um cliente cadastrado com este documento nesta empresa", error_code: :document_already_exists)
        end
      end

      nil
    end

    def validar_endereco
      return nil if @endereco_param.blank?

      if @endereco_param.is_a?(Endereco)
        if @endereco_param.cliente_id.present?
          if @cliente.present? && @endereco_param.cliente_id != @cliente.id
            return failure("Endereço informado pertence a outro cliente", error_code: :unauthorized_address)
          elsif @cliente.nil?
            return failure("Endereço informado pertence a outro cliente", error_code: :unauthorized_address)
          end
        end
        return nil
      end

      if @endereco_param.is_a?(Hash)
        endereco_attrs = @endereco_param.symbolize_keys
        endereco_id = endereco_attrs[:id]

        if endereco_id.present?
          if @cliente.nil?
            return failure("Não é possível associar um endereço existente a um novo cliente", error_code: :invalid_address_operation)
          end

          endereco = @cliente.enderecos.find_by(id: endereco_id)
          if endereco.nil?
            if Endereco.exists?(id: endereco_id)
              return failure("Endereço informado pertence a outro cliente", error_code: :unauthorized_address)
            else
              return failure("Endereço não encontrado para este cliente", error_code: :address_not_found)
            end
          end
        end
      end

      nil
    end

    def executar_salvamento
      endereco_salvo = nil

      ActiveRecord::Base.transaction do
        salvar_cliente!
        endereco_salvo = processar_endereco! if @endereco_param.present?
      end

      @cliente.reload
      success(
        cliente: @cliente,
        endereco: endereco_salvo,
        endereco_padrao: @cliente.endereco_padrao
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end

    def salvar_cliente!
      if @cliente.nil?
        @cliente = @empresa.clientes.build(@atributos_param)
      else
        @cliente.assign_attributes(@atributos_param) if @atributos_param.present?
      end

      @cliente.save!
    end

    def processar_endereco!
      if @endereco_param.is_a?(Endereco)
        endereco = @endereco_param
        endereco.cliente = @cliente
        tratar_padrao_para_objeto!(endereco)
        endereco.save!
        return endereco
      end

      endereco_attrs = @endereco_param.is_a?(Hash) ? @endereco_param.symbolize_keys : {}
      endereco_id = endereco_attrs[:id]

      endereco = if endereco_id.present?
                   @cliente.enderecos.find(endereco_id)
      else
                   @cliente.enderecos.build
      end

      endereco.assign_attributes(endereco_attrs.except(:id))
      tratar_padrao_para_hash!(endereco, endereco_attrs)
      endereco.save!
      endereco
    end

    def tratar_padrao_para_objeto!(endereco)
      deve_ser_padrao = if @definir_endereco_padrao.nil?
                          endereco.padrao? || @cliente.enderecos.where.not(id: endereco.id).none?
      else
                          @definir_endereco_padrao
      end

      if deve_ser_padrao
        desmarcar_enderecos_padrao_existentes!(exceto_id: endereco.id)
        endereco.padrao = true
      end
    end

    def tratar_padrao_para_hash!(endereco, attrs)
      deve_ser_padrao = if !@definir_endereco_padrao.nil?
                          @definir_endereco_padrao
      elsif attrs.key?(:padrao)
                          attrs[:padrao]
      else
                          @cliente.enderecos.where.not(id: endereco.id).none?
      end

      if deve_ser_padrao
        desmarcar_enderecos_padrao_existentes!(exceto_id: endereco.id)
        endereco.padrao = true
      elsif attrs.key?(:padrao)
        endereco.padrao = false
      end
    end

    def desmarcar_enderecos_padrao_existentes!(exceto_id: nil)
      scope = @cliente.enderecos.where(padrao: true)
      scope = scope.where.not(id: exceto_id) if exceto_id.present?
      scope.update_all(padrao: false)
    end
  end

  CadastrarService = SalvarService
end
