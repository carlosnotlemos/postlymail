require 'rails_helper'

RSpec.describe Cupons::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }

  describe 'alias de serviço' do
    it 'permite chamar através de Cupons::CadastrarService' do
      expect(Cupons::CadastrarService).to eq(Cupons::SalvarService)
      result = Cupons::CadastrarService.call(
        empresa: empresa,
        codigo: 'bemvindo10',
        tipo: :porcentagem,
        valor: 10.0
      )

      expect(result).to be_success
      expect(result.data[:cupom].codigo).to eq('BEMVINDO10')
      expect(result.data[:cupom].tipo).to eq('porcentagem')
      expect(result.data[:cupom].valor).to eq(10.0)
    end
  end

  describe 'criação de cupom (cadastro simples)' do
    it 'cria cupom com sucesso utilizando atributos em hash' do
      result = described_class.call(
        empresa: empresa,
        atributos: {
          codigo: 'natal25',
          tipo: :porcentagem,
          valor: 25.0,
          valor_minimo_pedido: 100.0,
          limite_usos: 50,
          valido_de: 1.day.ago,
          valido_ate: 30.days.from_now,
          ativo: true
        }
      )

      expect(result).to be_success
      cupom = result.data[:cupom]
      expect(cupom).to be_persisted
      expect(cupom.codigo).to eq('NATAL25')
      expect(cupom.empresa).to eq(empresa)
      expect(cupom.tipo).to eq('porcentagem')
      expect(cupom.valor).to eq(25.0)
      expect(cupom.valor_minimo_pedido).to eq(100.0)
      expect(cupom.limite_usos).to eq(50)
      expect(cupom.ativo).to be true
    end

    it 'cria cupom com sucesso utilizando argumentos nomeados diretos (kwargs)' do
      result = described_class.call(
        empresa: empresa,
        codigo: 'fixo30',
        tipo: :valor_fixo,
        valor: 30.0,
        valor_minimo_pedido: 60.0
      )

      expect(result).to be_success
      cupom = result.data[:cupom]
      expect(cupom).to be_persisted
      expect(cupom.codigo).to eq('FIXO30')
      expect(cupom.valor_fixo?).to be true
      expect(cupom.valor).to eq(30.0)
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        codigo: 'blackfriday',
        tipo: :porcentagem,
        valor: 50.0
      )

      expect(result).to be_success
      expect(result.data[:cupom].empresa_id).to eq(empresa.id)
      expect(result.data[:cupom].codigo).to eq('BLACKFRIDAY')
    end

    it 'normaliza o código removendo espaços e convertendo para maiúsculas' do
      result = described_class.call(
        empresa: empresa,
        codigo: '   cupom_vip_10   ',
        tipo: :porcentagem,
        valor: 10.0
      )

      expect(result).to be_success
      expect(result.data[:cupom].codigo).to eq('CUPOM_VIP_10')
    end
  end

  describe 'atualização de cupom existente' do
    let!(:cupom) do
      create(
        :cupom,
        empresa: empresa,
        codigo: 'ANTIGO10',
        tipo: :porcentagem,
        valor: 10.0,
        limite_usos: 20,
        usos_contagem: 5
      )
    end

    it 'atualiza cupom passando a instância no parâmetro cupom' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom,
        valor: 15.0,
        limite_usos: 30
      )

      expect(result).to be_success
      cupom.reload
      expect(cupom.valor).to eq(15.0)
      expect(cupom.limite_usos).to eq(30)
    end

    it 'atualiza cupom passando o ID numérico' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom.id,
        valor: 20.0
      )

      expect(result).to be_success
      expect(cupom.reload.valor).to eq(20.0)
    end

    it 'atualiza cupom passando o código alfanumérico existente' do
      result = described_class.call(
        empresa: empresa,
        cupom: 'antigo10',
        valor: 12.0
      )

      expect(result).to be_success
      expect(cupom.reload.valor).to eq(12.0)
    end

    it 'permite manter o mesmo código sem acusar duplicidade' do
      result = described_class.call(
        empresa: empresa,
        cupom: cupom,
        codigo: 'ANTIGO10',
        valor: 18.0
      )

      expect(result).to be_success
      expect(cupom.reload.valor).to eq(18.0)
    end
  end

  describe 'validações de integridade e regras de negócio' do
    describe 'duplicidade de código' do
      let!(:cupom_existente) { create(:cupom, empresa: empresa, codigo: 'DESCONTO10') }

      it 'rejeita criação com código duplicado na mesma empresa' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'desconto10',
          tipo: :porcentagem,
          valor: 10.0
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_code_already_exists)
        expect(result.error).to match(/Já existe um cupom cadastrado com este código nesta empresa/i)
      end

      it 'permite mesmo código em empresas diferentes' do
        result = described_class.call(
          empresa: outra_empresa,
          codigo: 'DESCONTO10',
          tipo: :porcentagem,
          valor: 10.0
        )

        expect(result).to be_success
        expect(result.data[:cupom].empresa).to eq(outra_empresa)
      end

      it 'rejeita alteração de código para um já existente de outro cupom' do
        outro_cupom = create(:cupom, empresa: empresa, codigo: 'OUTRO5')

        result = described_class.call(
          empresa: empresa,
          cupom: outro_cupom,
          codigo: 'DESCONTO10'
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_code_already_exists)
      end
    end

    describe 'datas de vigência' do
      it 'rejeita quando data de início é posterior à data de término' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'INVALIDODATA',
          tipo: :porcentagem,
          valor: 10.0,
          valido_de: 5.days.from_now,
          valido_ate: 1.day.from_now
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:invalid_validity_dates)
        expect(result.error).to match(/não pode ser posterior à data de término/i)
      end
    end

    describe 'coerência de limite de utilizações' do
      let!(:cupom) do
        create(
          :cupom,
          empresa: empresa,
          codigo: 'LIMITADO',
          limite_usos: 20,
          usos_contagem: 10
        )
      end

      it 'rejeita reduzir limite_usos para valor menor que usos_contagem' do
        result = described_class.call(
          empresa: empresa,
          cupom: cupom,
          limite_usos: 8
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:limit_lower_than_usage_count)
        expect(result.error).to match(/não pode ser menor que a quantidade de usos já realizados/i)
      end

      it 'permite reduzir limite_usos para valor igual a usos_contagem' do
        result = described_class.call(
          empresa: empresa,
          cupom: cupom,
          limite_usos: 10
        )

        expect(result).to be_success
        expect(cupom.reload.limite_usos).to eq(10)
      end
    end

    describe 'multi-tenancy e autorização' do
      it 'retorna erro quando empresa não é informada' do
        result = described_class.call(empresa: nil, codigo: 'TESTE')

        expect(result).to be_failure
        expect(result.error_code).to eq(:tenant_not_found)
      end

      it 'retorna erro quando empresa não existe' do
        result = described_class.call(empresa: 999_999, codigo: 'TESTE')

        expect(result).to be_failure
        expect(result.error_code).to eq(:tenant_not_found)
      end

      it 'retorna unauthorized_tenant quando cupom pertence a outra empresa' do
        cupom_alheio = create(:cupom, empresa: outra_empresa, codigo: 'ALHEIO')

        result = described_class.call(
          empresa: empresa,
          cupom: cupom_alheio,
          valor: 20.0
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:unauthorized_tenant)
      end

      it 'retorna coupon_not_found quando cupom informado para edição não existe' do
        result = described_class.call(
          empresa: empresa,
          cupom: 888_888,
          valor: 20.0
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:coupon_not_found)
      end
    end

    describe 'erros de validação do modelo' do
      it 'retorna record_invalid quando valor de porcentagem é superior a 100' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'PORCENTAGEM_ALTA',
          tipo: :porcentagem,
          valor: 150.0
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:record_invalid)
        expect(result.error).to match(/Erro de validação/i)
      end

      it 'retorna record_invalid quando valor é menor ou igual a zero' do
        result = described_class.call(
          empresa: empresa,
          codigo: 'VALOR_ZERO',
          tipo: :valor_fixo,
          valor: 0
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:record_invalid)
      end
    end
  end
end
