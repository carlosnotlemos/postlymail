# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Planos::SalvarService, type: :service do
  describe '.call' do
    context 'quando cadastrando um novo plano' do
      let(:parametros_validos) do
        {
          identificador: :start,
          nome: 'Plano Start',
          valor_mensal: 49.90,
          limite_produtos: 20,
          limite_disparos: 1000,
          limite_usuarios: 2,
          ativo: true
        }
      end

      it 'cria o plano com sucesso e retorna o objeto' do
        resultado = described_class.call(atributos: parametros_validos)

        expect(resultado).to be_success
        expect(resultado.data[:plano]).to be_persisted
        expect(resultado.data[:plano].nome).to eq('Plano Start')
        expect(resultado.data[:plano].identificador).to eq('start')
        expect(resultado.data[:plano].valor_mensal).to eq(49.90)
        expect(resultado.data[:plano].limite_produtos).to eq(20)
        expect(resultado.data[:plano].limite_disparos).to eq(1000)
        expect(resultado.data[:plano].limite_usuarios).to eq(2)
        expect(resultado.data[:plano].ativo).to be true
      end

      it 'aceita atributos via kwargs diretamente' do
        resultado = described_class.call(
          identificador: :pro,
          nome: 'Plano Pro',
          valor_mensal: 99.90,
          limite_produtos: 100,
          limite_disparos: 5000,
          limite_usuarios: 5
        )

        expect(resultado).to be_success
        expect(resultado.data[:plano].identificador).to eq('pro')
        expect(resultado.data[:plano].nome).to eq('Plano Pro')
      end

      it 'permite limites nulos (recursos ilimitados)' do
        resultado = described_class.call(
          identificador: :enterprise,
          nome: 'Plano Enterprise',
          valor_mensal: 299.90,
          limite_produtos: nil,
          limite_disparos: 50000,
          limite_usuarios: nil
        )

        expect(resultado).to be_success
        plano = resultado.data[:plano]
        expect(plano.limite_produtos).to be_nil
        expect(plano.limite_usuarios).to be_nil
        expect(plano.ilimitado_produtos?).to be true
        expect(plano.ilimitado_usuarios?).to be true
      end

      it 'normaliza valor_mensal formatado no padrão brasileiro' do
        resultado = described_class.call(
          identificador: :pro,
          nome: 'Plano Pro Especial',
          valor_mensal: '1.250,75',
          limite_disparos: 2000
        )

        expect(resultado).to be_success
        expect(resultado.data[:plano].valor_mensal).to eq(BigDecimal('1250.75'))
      end

      it 'normaliza identificador em string maiúscula' do
        resultado = described_class.call(
          identificador: 'PRO',
          nome: 'Plano Pro',
          valor_mensal: 89.90,
          limite_disparos: 3000
        )

        expect(resultado).to be_success
        expect(resultado.data[:plano].identificador).to eq('pro')
      end

      it 'falha ao tentar cadastrar identificador duplicado' do
        create(:plano, identificador: :start)

        resultado = described_class.call(
          identificador: :start,
          nome: 'Outro Start',
          valor_mensal: 59.90,
          limite_disparos: 500
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:identifier_already_exists)
        expect(resultado.error).to include('Já existe um plano cadastrado com este identificador')
      end

      it 'falha quando validação de modelo falhar (nome ausente)' do
        resultado = described_class.call(
          identificador: :start,
          nome: nil,
          valor_mensal: 50.00,
          limite_disparos: 100
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:record_invalid)
        expect(resultado.error).to match(/Nome (can't be blank|não pode ficar em branco)/i)
      end
    end

    context 'quando atualizando um plano existente' do
      let!(:plano) { create(:plano, identificador: :start, nome: 'Start Antigo', valor_mensal: 39.90) }

      it 'atualiza o plano passado como objeto Plano' do
        resultado = described_class.call(
          plano: plano,
          atributos: { nome: 'Start Novo', valor_mensal: 49.90 }
        )

        expect(resultado).to be_success
        expect(plano.reload.nome).to eq('Start Novo')
        expect(plano.valor_mensal).to eq(49.90)
      end

      it 'resolve o plano pelo id numérico' do
        resultado = described_class.call(
          plano: plano.id,
          atributos: { nome: 'Start via ID' }
        )

        expect(resultado).to be_success
        expect(plano.reload.nome).to eq('Start via ID')
      end

      it 'resolve o plano pelo identificador (symbol ou string)' do
        resultado = described_class.call(
          plano: :start,
          atributos: { nome: 'Start via Symbol' }
        )

        expect(resultado).to be_success
        expect(plano.reload.nome).to eq('Start via Symbol')
      end

      it 'retorna erro quando o plano informado não for encontrado' do
        resultado = described_class.call(
          plano: 999_999,
          atributos: { nome: 'Fantasma' }
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:plan_not_found)
      end

      it 'impede trocar o identificador para um já existente em outro plano' do
        create(:plano, identificador: :pro)

        resultado = described_class.call(
          plano: plano,
          atributos: { identificador: :pro }
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:identifier_already_exists)
      end
    end

    context 'aliases' do
      it 'fornece aliases CadastrarService, CriarService e AtualizarService' do
        expect(Planos::CadastrarService).to eq(described_class)
        expect(Planos::CriarService).to eq(described_class)
        expect(Planos::AtualizarService).to eq(described_class)
      end
    end
  end
end
