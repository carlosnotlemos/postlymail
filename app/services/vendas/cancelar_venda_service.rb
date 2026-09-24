# frozen_string_literal: true

module Vendas
  class CancelarVendaService < ApplicationService
    def initialize(
      venda_ou_hash = nil,
      motivo_ou_atributos = nil,
      venda: nil,
      motivo_cancelamento: nil,
      motivo: nil,
      cancelado_por: nil,
      cancelado_em: nil,
      empresa: nil,
      estornar_estoque: true,
      estornar_cupom: true,
      estornar_pagamentos: true,
      ignorar_se_cancelada: false,
      atributos: nil,
      **kwargs
    )
      dados = kwargs.dup
      dados.merge!(atributos.symbolize_keys) if atributos.is_a?(Hash)

      if venda_ou_hash.is_a?(Hash)
        dados.merge!(venda_ou_hash.symbolize_keys)
      elsif venda_ou_hash.present? && !dados.key?(:venda)
        dados[:venda] = venda_ou_hash
      end

      if motivo_ou_atributos.is_a?(Hash)
        dados.merge!(motivo_ou_atributos.symbolize_keys)
      elsif motivo_ou_atributos.present? && !dados.key?(:motivo_cancelamento)
        dados[:motivo_cancelamento] = motivo_ou_atributos
      end

      dados[:venda] = venda if venda.present?
      dados[:motivo_cancelamento] = motivo_cancelamento || motivo if (motivo_cancelamento || motivo).present?
      dados[:cancelado_por] = cancelado_por if cancelado_por.present?
      dados[:cancelado_em] = cancelado_em if cancelado_em.present?
      dados[:empresa] = empresa if empresa.present?
      dados[:estornar_estoque] = estornar_estoque unless estornar_estoque.nil?
      dados[:estornar_cupom] = estornar_cupom unless estornar_cupom.nil?
      dados[:estornar_pagamentos] = estornar_pagamentos unless estornar_pagamentos.nil?
      dados[:ignorar_se_cancelada] = ignorar_se_cancelada unless ignorar_se_cancelada.nil?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @venda_param = dados[:venda] || dados[:venda_id] || dados[:codigo_pedido]
      @venda = resolver_venda(@venda_param)

      @motivo_cancelamento = dados[:motivo_cancelamento]&.to_s&.strip
      @cancelado_por_param = dados[:cancelado_por] || dados[:cancelado_por_id] || dados[:usuario] || dados[:usuario_id]
      @cancelado_por = resolver_usuario(@cancelado_por_param)

      @cancelado_em = dados[:cancelado_em] || Time.current
      @estornar_estoque = dados.key?(:estornar_estoque) ? dados[:estornar_estoque] : true
      @estornar_cupom = dados.key?(:estornar_cupom) ? dados[:estornar_cupom] : true
      @estornar_pagamentos = dados.key?(:estornar_pagamentos) ? dados[:estornar_pagamentos] : true
      @ignorar_se_cancelada = dados[:ignorar_se_cancelada] || false
      @erro_estoque = nil
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      if @venda.cancelada? && @ignorar_se_cancelada
        return success(venda: @venda, ja_cancelada: true)
      end

      executar_cancelamento
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

    def resolver_venda(param)
      return param if param.is_a?(Venda)
      return nil if param.blank?

      if @empresa.present?
        if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
          return @empresa.vendas.find_by(id: param.to_i)
        end
        return @empresa.vendas.find_by(codigo_pedido: param.to_s.strip.upcase)
      end

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Venda.find_by(id: param.to_i)
      end

      Venda.find_by(codigo_pedido: param.to_s.strip.upcase)
    end

    def resolver_usuario(param)
      return nil if param.blank?
      return param if param.is_a?(Usuario)

      if param.is_a?(Integer) || (param.is_a?(String) && param =~ /\A\d+\z/)
        return Usuario.find_by(id: param.to_i)
      end

      Usuario.find_by(email: param.to_s.strip.downcase)
    end

    def validar_parametros
      if @venda.nil?
        if @venda_param.present? && @empresa.present?
          id_ou_cod = @venda_param.is_a?(Venda) ? @venda_param.id : @venda_param
          if Venda.where(id: id_ou_cod).or(Venda.where(codigo_pedido: id_ou_cod.to_s.strip.upcase)).exists?
            return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
        end
        return failure("Venda não informada ou não encontrada", error_code: :sale_not_found)
      end

      if @empresa.present? && @venda.empresa_id != @empresa.id
        return failure("Venda não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      if @cancelado_por_param.present? && @cancelado_por.nil?
        return failure("Usuário responsável pelo cancelamento não foi encontrado", error_code: :usuario_not_found)
      end

      if @venda.cancelada? && !@ignorar_se_cancelada
        return failure("Esta venda já foi cancelada anteriormente", error_code: :sale_already_cancelled)
      end

      if @motivo_cancelamento.blank?
        return failure("Motivo do cancelamento deve ser informado", error_code: :invalid_cancellation_reason)
      end

      nil
    end

    def executar_cancelamento
      ActiveRecord::Base.transaction do
        # 1. Estornar estoque se solicitado
        if @estornar_estoque
          @venda.itens.find_each do |item|
            movimentacao_res = Estoques::MovimentarService.call(
              empresa: @venda.empresa,
              variacao_produto: item.variacao_produto,
              tipo: "estorno_devolucao",
              quantidade: item.quantidade,
              usuario: @cancelado_por,
              origem: @venda,
              motivo: "Cancelamento da venda #{@venda.codigo_pedido}: #{@motivo_cancelamento}"
            )

            if movimentacao_res.failure?
              @erro_estoque = movimentacao_res
              raise ActiveRecord::Rollback
            end
          end
        end

        # 2. Estornar contagem de usos do cupom se aplicável
        if @estornar_cupom && @venda.cupom.present?
          cupom = @venda.cupom
          cupom.with_lock do
            novo_usos = [ cupom.usos_contagem - 1, 0 ].max
            cupom.update!(usos_contagem: novo_usos)
          end
        end

        # 3. Atualizar pagamentos se solicitado
        if @estornar_pagamentos
          @venda.pagamentos.where(status: :aprovado).find_each do |pagamento|
            pagamento.update!(status: :estornado)
          end

          @venda.pagamentos.where(status: :pendente).find_each do |pagamento|
            pagamento.update!(status: :cancelado)
          end
        end

        # 4. Atualizar status e campos de cancelamento da venda
        @venda.update!(
          status: :cancelada,
          motivo_cancelamento: @motivo_cancelamento,
          cancelado_por: @cancelado_por,
          cancelado_em: @cancelado_em
        )
      end

      if @erro_estoque.present?
        return failure(@erro_estoque.error, error_code: @erro_estoque.error_code)
      end

      unless @venda.cancelada?
        return failure("Erro ao cancelar a venda", error_code: :execution_failed)
      end

      success(venda: @venda, cancelada: true)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  CancelarService = CancelarVendaService
  EstornarService = CancelarVendaService
end
