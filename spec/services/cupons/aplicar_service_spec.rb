require 'rails_helper'

RSpec.describe Cupons::AplicarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:cliente) { create(:cliente, empresa: empresa) }

  let!(:cupom_porcentagem) do
    create(
      :cupom,
      empresa: empresa,
      codigo: 'PROMO10',
      tipo: :porcentagem,
      valor: 10.0,
      valor_minimo_pedido: 50.0,
      limite_usos: 5,
      usos_contagem: 0,
      valido_de: 1.day.ago,
      valido_ate: 10.days.from_now,
      ativo: true
    )
  end

  let!(:cupom_fixo) do
    create(
      :cupom,
      empresa: empresa,
      codigo: 'FIXO25',
      tipo: :valor_fixo,
      valor: 25.0,
      valor_minimo_pedido: 30.0,
      limite_usos: 10,
      usos_contagem: 0,
      valido_de: 1.day.ago,
      valido_ate: 10.days.from_now,
      ativo: true
    )
  end

  describe 'validação e cálculo de desconto sem consumo (modo padrão / simulação)' do
    context 'com cupom de porcentagem' do
      it 'calcula o desconto proporcional corretamente' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'PROMO10',
          subtotal: 200.0
        )

        expect(result).to be_success
        expect(result.data[:desconto]).to eq(20.0)
        expect(result.data[:total_com_desconto]).to eq(180.0)
        expect(result.data[:subtotal]).to eq(200.0)
        expect(result.data[:consumido]).to be false
        expect(cupom_porcentagem.reload.usos_contagem).to eq(0)
      end

      it 'arredonda as casas decimais adequadamente' do
        cupom_quebrado = create(
          :cupom,
          empresa: empresa,
          codigo: 'DESC15',
          tipo: :porcentagem,
          valor: 15.0,
          valor_minimo_pedido: 0
        )

        result = described_class.call(
          empresa: empresa,
          cupom: cupom_quebrado,
          subtotal: 33.33
        )

        expect(result).to be_success
        expect(result.data[:desconto]).to eq(5.0) # 33.33 * 0.15 = 4.9995 -> 5.0
        expect(result.data[:total_com_desconto]).to eq(28.33)
      end
    end

    context 'com cupom de valor fixo' do
      it 'aplica o valor fixo integral quando subtotal é superior' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'FIXO25',
          subtotal: 100.0
        )

        expect(result).to be_success
        expect(result.data[:desconto]).to eq(25.0)
        expect(result.data[:total_com_desconto]).to eq(75.0)
        expect(result.data[:consumido]).to be false
        expect(cupom_fixo.reload.usos_contagem).to eq(0)
      end

      it 'limita o desconto ao valor do subtotal se o cupom for maior que o pedido' do
        cupom_alto = create(
          :cupom,
          empresa: empresa,
          codigo: 'SUPER50',
          tipo: :valor_fixo,
          valor: 50.0,
          valor_minimo_pedido: 0
        )

        result = described_class.call(
          empresa: empresa,
          codigo: 'SUPER50',
          subtotal: 30.0
        )

        expect(result).to be_success
        expect(result.data[:desconto]).to eq(30.0)
        expect(result.data[:desconto_original]).to eq(50.0)
        expect(result.data[:total_com_desconto]).to eq(0.0)
      end
    end
  end

  describe 'efetivação do cupom (consumir: true)' do
    it 'incrementa a contagem de usos no banco sob lock pessimista' do
      expect do
        result = described_class.call(
          empresa: empresa,
          cupom: cupom_porcentagem,
          subtotal: 100.0,
          consumir: true
        )

        expect(result).to be_success
        expect(result.data[:consumido]).to be true
        expect(result.data[:usos_contagem]).to eq(1)
      end.to change { cupom_porcentagem.reload.usos_contagem }.by(1)
    end

    it 'aceita aliases registrar_uso e efetivar' do
      res1 = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0, registrar_uso: true)
      expect(res1).to be_success
      expect(cupom_porcentagem.reload.usos_contagem).to eq(1)

      res2 = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0, efetivar: true)
      expect(res2).to be_success
      expect(cupom_porcentagem.reload.usos_contagem).to eq(2)
    end

    it 'impede consumo se o limite de usos for atingido concorrentemente' do
      cupom_porcentagem.update!(usos_contagem: 4, limite_usos: 5)

      # 5º uso: deve ter sucesso
      res1 = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0, consumir: true)
      expect(res1).to be_success
      expect(cupom_porcentagem.reload.usos_contagem).to eq(5)

      # 6º uso: deve falhar por limite atingido
      res2 = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0, consumir: true)
      expect(res2).to be_failure
      expect(res2.error_code).to eq(:coupon_limit_reached)
      expect(cupom_porcentagem.reload.usos_contagem).to eq(5)
    end
  end

  describe 'flexibilidade na resolução de parâmetros' do
    it 'normaliza código com espaços e caracteres em minúsculo' do
      result = described_class.call(
        empresa: empresa,
        codigo: '  promo10  ',
        subtotal: 100.0
      )

      expect(result).to be_success
      expect(result.data[:cupom]).to eq(cupom_porcentagem)
    end

    it 'aceita ID numérico ou string numérica como cupom' do
      result_int = described_class.call(empresa: empresa, cupom: cupom_porcentagem.id, subtotal: 100.0)
      expect(result_int).to be_success
      expect(result_int.data[:cupom]).to eq(cupom_porcentagem)

      result_str = described_class.call(empresa: empresa, cupom: cupom_porcentagem.id.to_s, subtotal: 100.0)
      expect(result_str).to be_success
      expect(result_str.data[:cupom]).to eq(cupom_porcentagem)
    end

    it 'aceita valor_pedido como alias para subtotal' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom_porcentagem,
        valor_pedido: 150.0
      )

      expect(result).to be_success
      expect(result.data[:subtotal]).to eq(150.0)
      expect(result.data[:desconto]).to eq(15.0)
    end

    it 'aceita instância de Venda e resolve empresa, subtotal e cupom automaticamente' do
      venda = create(
        :venda,
        empresa: empresa,
        cliente: cliente,
        subtotal_produtos: 200.0,
        cupom: cupom_porcentagem,
        codigo_cupom: cupom_porcentagem.codigo
      )

      result = described_class.call(venda: venda)

      expect(result).to be_success
      expect(result.data[:cupom]).to eq(cupom_porcentagem)
      expect(result.data[:subtotal]).to eq(200.0)
      expect(result.data[:desconto]).to eq(20.0)
    end
  end

  describe 'validações e regras de negócio' do
    describe 'empresa (multi-tenancy)' do
      it 'retorna erro quando empresa não é informada' do
        result = described_class.call(empresa: nil, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:tenant_not_found)
        expect(result.error).to match(/Empresa não informada ou não encontrada/i)
      end

      it 'retorna erro quando empresa por ID não existe' do
        result = described_class.call(empresa: 999_999, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:tenant_not_found)
      end

      it 'retorna erro de autorização quando cupom pertence a outra empresa (passando instância)' do
        outra_empresa = create(:empresa)
        cupom_outro = create(:cupom, empresa: outra_empresa, codigo: 'OUTRO10')

        result = described_class.call(empresa: empresa, cupom: cupom_outro, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:unauthorized_tenant)
        expect(result.error).to match(/não pertence à empresa/i)
      end

      it 'retorna erro de autorização quando código existe apenas em outra empresa' do
        outra_empresa = create(:empresa)
        create(:cupom, empresa: outra_empresa, codigo: 'ALHEIO20')

        result = described_class.call(empresa: empresa, codigo: 'ALHEIO20', subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:unauthorized_tenant)
        expect(result.error).to match(/não pertence à empresa/i)
      end
    end

    describe 'cupom' do
      it 'retorna erro quando cupom não é informado' do
        result = described_class.call(empresa: empresa, cupom: nil, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_not_found)
      end

      it 'retorna erro quando cupom não é encontrado no sistema' do
        result = described_class.call(empresa: empresa, codigo: 'INEXISTENTE', subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_not_found)
      end

      it 'retorna erro quando cupom está inativo' do
        cupom_porcentagem.update!(ativo: false)

        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_inactive)
        expect(result.error).to match(/Cupom inativo/i)
      end

      it 'retorna erro quando cupom ainda não está vigente (valido_de no futuro)' do
        cupom_porcentagem.update!(valido_de: 2.days.from_now)

        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_not_yet_valid)
        expect(result.error).to match(/ainda não está vigente/i)
      end

      it 'retorna erro quando cupom expirou (valido_ate no passado)' do
        cupom_porcentagem.update!(valido_ate: 1.day.ago)

        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_expired)
        expect(result.error).to match(/Cupom expirado/i)
      end

      it 'retorna erro quando limite de utilizações já foi atingido' do
        cupom_porcentagem.update!(limite_usos: 3, usos_contagem: 3)

        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 100.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_limit_reached)
        expect(result.error).to match(/Limite de utilizações/i)
      end
    end

    describe 'subtotal / valor do pedido' do
      it 'retorna erro quando subtotal não é informado' do
        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: nil)

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_subtotal)
      end

      it 'retorna erro quando subtotal não é numérico' do
        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: 'cem_reais')

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_subtotal)
      end

      it 'retorna erro quando subtotal é negativo' do
        result = described_class.call(empresa: empresa, cupom: cupom_porcentagem, subtotal: -10.0)

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_subtotal)
      end

      it 'retorna erro quando subtotal é inferior ao valor mínimo exigido pelo cupom' do
        # cupom_porcentagem exige valor_minimo_pedido = 50.0
        result = described_class.call(
          empresa: empresa,
          cupom: cupom_porcentagem,
          subtotal: 49.99
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:minimum_order_value_not_met)
        expect(result.error).to match(/inferior ao valor mínimo/i)
      end

      it 'permite aplicação quando subtotal é exatamente igual ao valor mínimo' do
        result = described_class.call(
          empresa: empresa,
          cupom: cupom_porcentagem,
          subtotal: 50.0
        )

        expect(result).to be_success
        expect(result.data[:desconto]).to eq(5.0)
      end
    end
  end
end
