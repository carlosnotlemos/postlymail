require 'rails_helper'

RSpec.describe Custos::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let(:venda) { create(:venda, empresa: empresa) }
  let(:venda_outra_empresa) { create(:venda, empresa: outra_empresa) }

  describe 'aliases de serviço' do
    it 'permite chamar através de Custos::CadastrarService' do
      expect(Custos::CadastrarService).to eq(Custos::SalvarService)
      result = Custos::CadastrarService.call(
        empresa: empresa,
        categoria: :frete_entrega,
        valor: 35.50
      )

      expect(result).to be_success
      expect(result.data[:custo].categoria).to eq('frete_entrega')
      expect(result.data[:custo].valor).to eq(35.50)
    end

    it 'permite chamar através de Custos::CriarService' do
      expect(Custos::CriarService).to eq(Custos::SalvarService)
    end
  end

  describe 'criação de custo (cadastro simples)' do
    it 'cria custo com sucesso utilizando atributos em hash' do
      result = described_class.call(
        empresa: empresa,
        atributos: {
          categoria: :insumos_producao,
          valor: 180.00,
          data_custo: '2026-09-15',
          descricao: 'Tintas têxteis e filmes DTF'
        }
      )

      expect(result).to be_success
      custo = result.data[:custo]
      expect(custo).to be_persisted
      expect(custo.empresa).to eq(empresa)
      expect(custo.categoria).to eq('insumos_producao')
      expect(custo.valor).to eq(180.00)
      expect(custo.data_custo).to eq(Date.parse('2026-09-15'))
      expect(custo.descricao).to eq('Tintas têxteis e filmes DTF')
      expect(custo.venda).to be_nil
    end

    it 'cria custo com sucesso utilizando argumentos diretos (kwargs)' do
      result = described_class.call(
        empresa: empresa,
        categoria: :trafego_pago,
        valor: 500.0,
        descricao: 'Campanha Meta Ads - Coleção Primavera'
      )

      expect(result).to be_success
      custo = result.data[:custo]
      expect(custo.categoria).to eq('trafego_pago')
      expect(custo.valor).to eq(500.0)
      expect(custo.data_custo).to eq(Date.current)
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        categoria: :embalagem,
        valor: 45.00
      )

      expect(result).to be_success
      expect(result.data[:custo].empresa_id).to eq(empresa.id)
    end

    it 'define data_custo automaticamente como Date.current quando não informada na criação' do
      result = described_class.call(
        empresa: empresa,
        categoria: :operacional_geral,
        valor: 80.00
      )

      expect(result).to be_success
      expect(result.data[:custo].data_custo).to eq(Date.current)
    end

    it 'normaliza valor informado em formato brasileiro com vírgula (string)' do
      result = described_class.call(
        empresa: empresa,
        categoria: :frete_entrega,
        valor: '1.250,75'
      )

      expect(result).to be_success
      expect(result.data[:custo].valor).to eq(1250.75)
    end

    it 'aceita categoria informada como número inteiro de enum' do
      result = described_class.call(
        empresa: empresa,
        categoria: 1, # frete_entrega
        valor: 20.0
      )

      expect(result).to be_success
      expect(result.data[:custo].categoria).to eq('frete_entrega')
    end
  end

  describe 'vínculo opcional com venda' do
    it 'cria custo vinculado a uma venda passando a instância de Venda' do
      result = described_class.call(
        empresa: empresa,
        venda: venda,
        categoria: :frete_entrega,
        valor: 22.90
      )

      expect(result).to be_success
      expect(result.data[:custo].venda).to eq(venda)
    end

    it 'cria custo vinculado a uma venda passando o ID da venda' do
      result = described_class.call(
        empresa: empresa,
        venda: venda.id,
        categoria: :embalagem,
        valor: 6.50
      )

      expect(result).to be_success
      expect(result.data[:custo].venda_id).to eq(venda.id)
    end

    it 'cria custo vinculado a uma venda passando o codigo_pedido da venda' do
      result = described_class.call(
        empresa: empresa,
        venda: venda.codigo_pedido.downcase,
        categoria: :embalagem,
        valor: 8.00
      )

      expect(result).to be_success
      expect(result.data[:custo].venda_id).to eq(venda.id)
    end

    it 'permite desvincular venda em uma edição passando venda: nil' do
      custo = create(:custo, empresa: empresa, venda: venda)

      result = described_class.call(
        empresa: empresa,
        custo: custo,
        venda: nil
      )

      expect(result).to be_success
      expect(custo.reload.venda_id).to be_nil
    end

    it 'preserva a venda associada se venda não for informada na atualização' do
      custo = create(:custo, empresa: empresa, venda: venda, valor: 50.0)

      result = described_class.call(
        empresa: empresa,
        custo: custo,
        valor: 75.0
      )

      expect(result).to be_success
      expect(custo.reload.valor).to eq(75.0)
      expect(custo.venda_id).to eq(venda.id)
    end
  end

  describe 'atualização de custo' do
    let(:custo) { create(:custo, empresa: empresa, valor: 100.0, categoria: :insumos_producao, descricao: 'Antiga') }

    it 'atualiza atributos com sucesso' do
      result = described_class.call(
        empresa: empresa,
        custo: custo,
        valor: 135.0,
        descricao: 'Nova descrição'
      )

      expect(result).to be_success
      expect(custo.reload.valor).to eq(135.0)
      expect(custo.descricao).to eq('Nova descrição')
      expect(custo.categoria).to eq('insumos_producao')
    end

    it 'localiza custo por ID numérico' do
      result = described_class.call(
        empresa: empresa,
        custo: custo.id,
        valor: 200.0
      )

      expect(result).to be_success
      expect(custo.reload.valor).to eq(200.0)
    end
  end

  describe 'validações multi-tenant e segurança' do
    it 'falha quando empresa não é informada' do
      result = described_class.call(
        empresa: nil,
        categoria: :embalagem,
        valor: 10.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to include('Empresa não informada ou não encontrada')
    end

    it 'falha quando custo pertence a outra empresa' do
      custo_outro = create(:custo, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        custo: custo_outro,
        valor: 99.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Custo não pertence à empresa informada')
    end

    it 'falha quando custo informado por ID pertence a outra empresa' do
      custo_outro = create(:custo, empresa: outra_empresa)

      result = described_class.call(
        empresa: empresa,
        custo: custo_outro.id,
        valor: 99.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha quando custo não existe' do
      result = described_class.call(
        empresa: empresa,
        custo: 999999,
        valor: 99.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:cost_not_found)
    end

    it 'falha quando venda vinculada pertence a outra empresa' do
      result = described_class.call(
        empresa: empresa,
        venda: venda_outra_empresa,
        categoria: :frete_entrega,
        valor: 30.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(result.error).to include('Venda não pertence à empresa informada')
    end

    it 'falha quando venda informada por ID pertence a outra empresa' do
      result = described_class.call(
        empresa: empresa,
        venda: venda_outra_empresa.id,
        categoria: :frete_entrega,
        valor: 30.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha quando venda informada não existe' do
      result = described_class.call(
        empresa: empresa,
        venda: 999999,
        categoria: :frete_entrega,
        valor: 30.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:sale_not_found)
    end
  end

  describe 'validações de atributos' do
    it 'falha quando categoria não é informada na criação' do
      result = described_class.call(
        empresa: empresa,
        valor: 50.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:category_blank)
    end

    it 'falha quando categoria é inválida' do
      result = described_class.call(
        empresa: empresa,
        categoria: :categoria_inexistente,
        valor: 50.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_category)
      expect(result.error).to include('Categoria de custo inválida')
    end

    it 'falha quando valor não é informado na criação' do
      result = described_class.call(
        empresa: empresa,
        categoria: :embalagem
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:amount_blank)
    end

    it 'falha quando valor é negativo' do
      result = described_class.call(
        empresa: empresa,
        categoria: :embalagem,
        valor: -15.0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_amount)
      expect(result.error).to include('não pode ser negativo')
    end

    it 'falha quando valor não é numérico' do
      result = described_class.call(
        empresa: empresa,
        categoria: :embalagem,
        valor: 'abc'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_amount)
    end

    it 'falha quando formato de data é inválido' do
      result = described_class.call(
        empresa: empresa,
        categoria: :embalagem,
        valor: 10.0,
        data_custo: 'data-invalida'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_cost_date)
      expect(result.error).to include('formato inválido')
    end
  end
end
