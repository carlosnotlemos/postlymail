module Clientes
  class ResolverEnderecoService < ApplicationService
    TIPOS_ENTREGA = %w[retirada motoboy_uber correios_pac correios_sedex].freeze

    def initialize(
      empresa: nil,
      cliente: nil,
      endereco: nil,
      endereco_id: nil,
      tipo_entrega: nil,
      obrigatorio: nil,
      destinatario: nil,
      telefone: nil
    )
      @empresa_param = empresa
      @empresa = resolver_empresa(empresa)

      @cliente_param = cliente
      @cliente = resolver_cliente(cliente)

      @endereco_param = endereco || endereco_id
      @tipo_entrega_raw = tipo_entrega
      @tipo_entrega = normalizar_tipo_entrega(tipo_entrega)

      @obrigatorio = obrigatorio
      @destinatario = destinatario
      @telefone = telefone

      @endereco_resolvido = nil
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      construir_resultado
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

    def normalizar_tipo_entrega(param)
      return nil if param.blank?

      if param.is_a?(Integer)
        return Venda.tipo_entregas.key(param)
      end

      param.to_s.strip.downcase
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cliente = validar_cliente
      return validacao_cliente if validacao_cliente&.failure?

      validacao_tipo_entrega = validar_tipo_entrega
      return validacao_tipo_entrega if validacao_tipo_entrega&.failure?

      validar_e_resolver_endereco
    end

    def validar_cliente
      if @cliente.nil? && @cliente_param.present?
        if @cliente_param.is_a?(Cliente) || Cliente.exists?(id: @cliente_param)
          return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
        end

        return failure("Cliente não informado ou não encontrado", error_code: :client_not_found)
      end

      return failure("Cliente não informado ou não encontrado", error_code: :client_not_found) if @cliente.nil?

      if @cliente.empresa_id != @empresa.id
        return failure("Cliente não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      nil
    end

    def validar_tipo_entrega
      return nil if @tipo_entrega.blank?

      unless TIPOS_ENTREGA.include?(@tipo_entrega)
        return failure("Tipo de entrega inválido: #{@tipo_entrega_raw}", error_code: :invalid_delivery_type)
      end

      nil
    end

    def endereco_obrigatorio?
      return @obrigatorio unless @obrigatorio.nil?

      # Se for retirada, não é obrigatório por padrão.
      # Para os demais tipos de entrega (ou se não especificado), é obrigatório.
      @tipo_entrega != "retirada"
    end

    def validar_e_resolver_endereco
      if @endereco_param.present?
        resolver_endereco_especifico
      else
        resolver_endereco_automatico
      end
    end

    def resolver_endereco_especifico
      if @endereco_param.is_a?(Endereco)
        if @endereco_param.cliente_id != @cliente.id
          return failure("Endereço informado pertence a outro cliente", error_code: :unauthorized_address)
        end
        @endereco_resolvido = @endereco_param
        return nil
      end

      id = @endereco_param.is_a?(Hash) ? @endereco_param[:id] || @endereco_param["id"] : @endereco_param
      endereco = @cliente.enderecos.find_by(id: id)

      if endereco.nil?
        if Endereco.exists?(id: id)
          return failure("Endereço informado pertence a outro cliente", error_code: :unauthorized_address)
        else
          return failure("Endereço não encontrado para este cliente", error_code: :address_not_found)
        end
      end

      @endereco_resolvido = endereco
      nil
    end

    def resolver_endereco_automatico
      @endereco_resolvido = @cliente.endereco_padrao || @cliente.enderecos.order(:id).last

      if @endereco_resolvido.nil? && endereco_obrigatorio?
        return failure("Cliente não possui nenhum endereço cadastrado", error_code: :address_not_found)
      end

      nil
    end

    def formatar_cep(cep)
      digits = cep.to_s.gsub(/\D/, "")
      if digits.length == 8
        "#{digits[0..4]}-#{digits[5..7]}"
      else
        cep.to_s
      end
    end

    def formatar_texto_endereco(end_obj)
      partes = []
      logradouro_num = [ end_obj.logradouro, end_obj.numero ].compact_blank.join(", ")
      partes << logradouro_num if logradouro_num.present?
      partes << end_obj.complemento if end_obj.complemento.present?
      partes << end_obj.bairro if end_obj.bairro.present?

      cidade_estado = [ end_obj.cidade, end_obj.estado ].compact_blank.join(" - ")
      partes << cidade_estado if cidade_estado.present?

      partes << "CEP #{formatar_cep(end_obj.cep)}" if end_obj.cep.present?
      partes.join(" - ")
    end

    def construir_resultado
      if @endereco_resolvido.nil?
        snapshot = {
          "tipo_entrega" => @tipo_entrega || "retirada",
          "retirada_na_loja" => true,
          "destinatario" => @destinatario || @cliente.nome,
          "telefone" => @telefone || @cliente.telefone,
          "texto_formatado" => "Retirada no balcão / loja física"
        }

        return success(
          endereco: nil,
          snapshot: snapshot,
          texto_formatado: snapshot["texto_formatado"],
          tipo_entrega: @tipo_entrega
        )
      end

      texto = formatar_texto_endereco(@endereco_resolvido)
      snapshot = {
        "endereco_id" => @endereco_resolvido.id,
        "titulo" => @endereco_resolvido.titulo,
        "cep" => formatar_cep(@endereco_resolvido.cep),
        "logradouro" => @endereco_resolvido.logradouro,
        "numero" => @endereco_resolvido.numero,
        "complemento" => @endereco_resolvido.complemento,
        "bairro" => @endereco_resolvido.bairro,
        "cidade" => @endereco_resolvido.cidade,
        "estado" => @endereco_resolvido.estado,
        "ponto_referencia" => @endereco_resolvido.ponto_referencia,
        "padrao" => @endereco_resolvido.padrao?,
        "destinatario" => @destinatario || @cliente.nome,
        "telefone" => @telefone || @cliente.telefone,
        "tipo_entrega" => @tipo_entrega,
        "texto_formatado" => texto
      }.compact

      success(
        endereco: @endereco_resolvido,
        snapshot: snapshot,
        texto_formatado: texto,
        tipo_entrega: @tipo_entrega
      )
    end
  end

  ResolverEnderecoEntregaService = ResolverEnderecoService
end
