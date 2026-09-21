module Cupons
  class AplicarService < ApplicationService
    def initialize(
      empresa: nil,
      cupom: nil,
      codigo: nil,
      subtotal: nil,
      valor_pedido: nil,
      venda: nil,
      consumir: false,
      registrar_uso: false,
      efetivar: false
    )
      @venda = venda
      @empresa_param = empresa || @venda&.empresa
      @empresa = resolver_empresa(@empresa_param)

      @cupom_param = cupom || codigo || (@venda&.cupom || @venda&.codigo_cupom)
      @cupom = resolver_cupom(@cupom_param)

      @subtotal_param = subtotal || valor_pedido || @venda&.subtotal_produtos
      @consumir = consumir || registrar_uso || efetivar
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      processar_cupom
    end

    private

    def resolver_empresa(param)
      return param if param.is_a?(Empresa)
      return nil if param.blank?

      Empresa.find_by(id: param)
    end

    def resolver_cupom(param)
      return param if param.is_a?(Cupom)
      return nil if param.blank? || @empresa.nil?

      if param.is_a?(Integer)
        return @empresa.cupons.find_by(id: param)
      end

      codigo_normalizado = param.to_s.strip.upcase
      cupom_por_codigo = @empresa.cupons.find_by("UPPER(codigo) = ?", codigo_normalizado)
      return cupom_por_codigo if cupom_por_codigo

      if param.is_a?(String) && param =~ /\A\d+\z/
        @empresa.cupons.find_by(id: param)
      end
    end

    def validar_parametros
      return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found) unless @empresa

      validacao_cupom = validar_cupom
      return validacao_cupom if validacao_cupom&.failure?

      validar_subtotal
    end

    def validar_cupom
      if @cupom.nil?
        if @cupom_param.present?
          if cupom_existe_em_outro_tenant?
            return failure("Cupom não pertence à empresa informada", error_code: :unauthorized_tenant)
          end
        end
        return failure("Cupom não informado ou não encontrado", error_code: :coupon_not_found)
      end

      if @cupom.empresa_id != @empresa.id
        return failure("Cupom não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      unless @cupom.ativo?
        return failure("Cupom inativo", error_code: :coupon_inactive)
      end

      if @cupom.valido_de.present? && Time.current < @cupom.valido_de
        return failure("Cupom ainda não está vigente", error_code: :coupon_not_yet_valid)
      end

      if @cupom.valido_ate.present? && Time.current > @cupom.valido_ate
        return failure("Cupom expirado", error_code: :coupon_expired)
      end

      if @cupom.limite_usos.present? && @cupom.usos_contagem >= @cupom.limite_usos
        return failure("Limite de utilizações do cupom atingido", error_code: :coupon_limit_reached)
      end

      nil
    end

    def cupom_existe_em_outro_tenant?
      return true if @cupom_param.is_a?(Cupom)

      if @cupom_param.is_a?(Integer)
        return Cupom.exists?(id: @cupom_param)
      end

      norm = @cupom_param.to_s.strip.upcase
      Cupom.where("UPPER(codigo) = ?", norm).exists? || (@cupom_param.is_a?(String) && @cupom_param =~ /\A\d+\z/ && Cupom.exists?(id: @cupom_param))
    end

    def validar_subtotal
      if @subtotal_param.nil?
        return failure("Subtotal do pedido não informado", error_code: :invalid_subtotal)
      end

      unless @subtotal_param.is_a?(Numeric) || (@subtotal_param.is_a?(String) && @subtotal_param =~ /\A\d+(\.\d+)?\z/)
        return failure("Subtotal do pedido deve ser um valor numérico válido", error_code: :invalid_subtotal)
      end

      subtotal_num = BigDecimal(@subtotal_param.to_s)
      if subtotal_num < 0
        return failure("Subtotal do pedido deve ser maior ou igual a zero", error_code: :invalid_subtotal)
      end

      if @cupom.valor_minimo_pedido.present? && subtotal_num < @cupom.valor_minimo_pedido
        return failure(
          "Valor do pedido (R$ #{'%.2f' % subtotal_num}) é inferior ao valor mínimo exigido pelo cupom (R$ #{'%.2f' % @cupom.valor_minimo_pedido})",
          error_code: :minimum_order_value_not_met
        )
      end

      nil
    end

    def calcular_desconto(subtotal_num)
      desconto_bruto = if @cupom.porcentagem?
                         (subtotal_num * (@cupom.valor / BigDecimal("100"))).round(2)
      else
                         @cupom.valor.to_d.round(2)
      end

      desconto_aplicado = [ desconto_bruto, subtotal_num ].min.round(2)
      total_com_desconto = (subtotal_num - desconto_aplicado).round(2)

      [ desconto_bruto, desconto_aplicado, total_com_desconto ]
    end

    def processar_cupom
      subtotal_num = BigDecimal(@subtotal_param.to_s).round(2)
      desconto_bruto, desconto_aplicado, total_com_desconto = calcular_desconto(subtotal_num)

      if @consumir
        executar_consumo(subtotal_num, desconto_bruto, desconto_aplicado, total_com_desconto)
      else
        payload = build_payload(subtotal_num, desconto_bruto, desconto_aplicado, total_com_desconto, consumido: false)
        success(payload)
      end
    end

    def executar_consumo(subtotal_num, desconto_bruto, desconto_aplicado, total_com_desconto)
      result = nil

      @cupom.with_lock do
        unless @cupom.ativo?
          result = failure("Cupom inativo", error_code: :coupon_inactive)
          raise ActiveRecord::Rollback
        end

        if @cupom.limite_usos.present? && @cupom.usos_contagem >= @cupom.limite_usos
          result = failure("Limite de utilizações do cupom atingido", error_code: :coupon_limit_reached)
          raise ActiveRecord::Rollback
        end

        @cupom.update!(usos_contagem: @cupom.usos_contagem + 1)

        payload = build_payload(subtotal_num, desconto_bruto, desconto_aplicado, total_com_desconto, consumido: true)
        result = success(payload)
      end

      if result&.failure?
        @cupom.reload
      end

      result || failure("Erro ao processar cupom", error_code: :execution_failed)
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end

    def build_payload(subtotal_num, desconto_bruto, desconto_aplicado, total_com_desconto, consumido:)
      {
        cupom: @cupom,
        codigo: @cupom.codigo,
        tipo: @cupom.tipo,
        valor: @cupom.valor,
        subtotal: subtotal_num,
        desconto: desconto_aplicado,
        desconto_original: desconto_bruto,
        total_com_desconto: total_com_desconto,
        consumido: consumido,
        usos_contagem: @cupom.usos_contagem
      }
    end
  end
end
