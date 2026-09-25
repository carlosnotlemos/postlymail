# frozen_string_literal: true

module Campanhas
  class DispararService < ApplicationService
    def initialize(
      campanha_ou_hash = nil,
      campanha: nil,
      empresa: nil,
      clientes: nil,
      cliente_ids: nil,
      processar_agora: true,
      enviar_agora: nil,
      forcar: false,
      agora: false,
      simular_falha: false,
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
      dados[:clientes] = clientes if clientes.present?
      dados[:cliente_ids] = cliente_ids if cliente_ids.present?

      @empresa_param = dados[:empresa]
      @empresa = resolver_empresa(@empresa_param)

      @campanha_param = dados[:campanha] || dados[:campanha_id] || dados[:id]
      @campanha = resolver_campanha(@campanha_param)
      @empresa ||= @campanha&.empresa

      @clientes_param = dados[:clientes]
      @cliente_ids_param = dados[:cliente_ids]

      @processar_agora = if !enviar_agora.nil?
                           enviar_agora
      elsif !dados[:enviar_agora].nil?
                           dados[:enviar_agora]
      elsif !dados[:processar_agora].nil?
                           dados[:processar_agora]
      else
                           processar_agora
      end

      @forcar = forcar || dados[:forcar] || false
      @agora = agora || dados[:agora] || false
      @simular_falha = simular_falha || dados[:simular_falha] || false
    end

    def call
      validacao = validar_parametros
      return validacao if validacao&.failure?

      # Se a campanha estiver agendada para data futura e não for forçado o envio imediato
      if agendada_para_o_futuro?
        return success(
          campanha: @campanha,
          agendada: true,
          executada: false,
          total_destinatarios: 0,
          disparos: [],
          mensagem: "Campanha mantida como agendada para #{@campanha.data_envio}"
        )
      end

      executar_disparo
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

    def agendada_para_o_futuro?
      return false if @forcar || @agora
      return false unless @campanha.agendada?

      @campanha.data_envio.present? && @campanha.data_envio > Time.current
    end

    def validar_parametros
      if @campanha.nil?
        return failure("Campanha não informada ou não encontrada", error_code: :campaign_not_found)
      end

      if @empresa.nil?
        return failure("Empresa não informada ou não encontrada", error_code: :tenant_not_found)
      end

      if @campanha.empresa_id != @empresa.id
        return failure("Campanha não pertence à empresa informada", error_code: :unauthorized_tenant)
      end

      unless @empresa.ativo?
        return failure("Empresa inativa", error_code: :empresa_inactive)
      end

      if @campanha.cancelada?
        return failure("Não é possível disparar uma campanha cancelada", error_code: :campaign_cancelled)
      end

      if @campanha.concluida? && !@forcar
        return failure("Campanha já foi concluída anteriormente", error_code: :campaign_already_completed)
      end

      if @campanha.enviando? && !@forcar
        return failure("Campanha já está em processo de envio", error_code: :campaign_already_sending)
      end

      nil
    end

    def resolver_publico_alvo
      if @clientes_param.present?
        clientes_lista = Array(@clientes_param)
        return @empresa.clientes.where(id: clientes_lista.map { |c| c.is_a?(Cliente) ? c.id : c }, ativo: true, aceita_marketing: true)
      end

      if @cliente_ids_param.present?
        ids_lista = Array(@cliente_ids_param)
        return @empresa.clientes.where(id: ids_lista, ativo: true, aceita_marketing: true)
      end

      scope = @empresa.clientes.where(ativo: true, aceita_marketing: true)

      if @campanha.email?
        scope = scope.where.not(email: [ nil, "" ])
      elsif @campanha.whatsapp?
        scope = scope.where.not(telefone: [ nil, "" ])
      end

      case @campanha.segmento.to_sym
      when :com_compras
        vendas_validas = @empresa.vendas.where.not(status: :cancelada).select(:cliente_id)
        scope = scope.where(id: vendas_validas)
      when :sem_compras
        vendas_validas = @empresa.vendas.where.not(status: :cancelada).select(:cliente_id)
        scope = scope.where.not(id: vendas_validas)
      end

      scope
    end

    def executar_disparo
      destinatarios = resolver_publico_alvo.to_a
      disparos = []
      disparos_para_processar = []
      enviados_count = 0
      falhas_count = 0

      # Fase 1 (Transação Rápida): Garante atomicidade ao enfileirar no banco e libera a conexão
      ActiveRecord::Base.transaction do
        @campanha.status = :enviando
        @campanha.save!

        destinatarios.each do |cliente|
          destinatario_alvo = @campanha.email? ? cliente.email.to_s.strip : cliente.telefone.to_s.strip
          next if destinatario_alvo.blank?

          disparo = @campanha.disparos.find_or_initialize_by(cliente: cliente)

          # Se o disparo já foi enviado e não estamos forçando reenvio, pular
          if disparo.persisted? && (disparo.enviado? || disparo.entregue?) && !@forcar
            disparos << disparo
            enviados_count += 1
            next
          end

          disparo.destinatario = destinatario_alvo
          disparo.status = :na_fila if disparo.new_record? || disparo.falhou?
          disparo.save!

          disparos << disparo
          disparos_para_processar << disparo
        end
      end

      # Fase 2 (Processamento Unitário): Itera sobre os disparos isoladamente fora de transação externa
      if @processar_agora
        disparos_para_processar.each do |disparo|
          begin
            resultado_proc = Disparos::ProcessarService.call(
              disparo: disparo,
              simular_falha: @simular_falha,
              forcar: @forcar
            )

            disparo.reload
            if resultado_proc.success? && (disparo.enviado? || disparo.entregue?)
              enviados_count += 1
            else
              falhas_count += 1
            end
          rescue StandardError => e
            disparo.update(status: :falhou, mensagem_erro: e.message) rescue nil
            falhas_count += 1
          end
        end

        # Modo síncrono: ao final de todo o loop, atualiza a campanha para :concluida
        @campanha.update!(status: :concluida, data_envio: Time.current)
      end

      success(
        campanha: @campanha.reload,
        executada: @processar_agora,
        enfileirada: !@processar_agora,
        total_destinatarios: destinatarios.size,
        disparos_criados_count: disparos.size,
        enviados_count: enviados_count,
        falhas_count: falhas_count,
        disparos: disparos
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("Erro de validação: #{e.record.errors.full_messages.join(', ')}", error_code: :record_invalid)
    rescue StandardError => e
      failure("Erro inesperado: #{e.message}", error_code: :unexpected_error)
    end
  end

  EnviarService = DispararService
  ExecutarService = DispararService
end

module Disparos
  DispararCampanhaService = Campanhas::DispararService
end
