require 'rails_helper'

RSpec.describe Estoques::MovimentarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:produto) { create(:produto, empresa: empresa) }
  let(:variacao) { create(:variacao_produto, produto: produto, empresa: empresa) }
  let!(:estoque) { create(:estoque, variacao_produto: variacao, quantidade: 10, quantidade_minima: 2) }
  let(:usuario) { create(:usuario) }

  describe 'entradas' do
    it 'incrementa o estoque com entrada_producao' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :entrada_producao,
        quantidade: 5,
        usuario: usuario,
        motivo: 'Produção do lote 42'
      )

      expect(result).to be_success
      expect(result.data[:estoque].quantidade).to eq(15)
      expect(estoque.reload.quantidade).to eq(15)

      movimentacao = result.data[:movimentacao]
      expect(movimentacao).to be_persisted
      expect(movimentacao.tipo).to eq('entrada_producao')
      expect(movimentacao.quantidade).to eq(5)
      expect(movimentacao.saldo_anterior).to eq(10)
      expect(movimentacao.saldo_posterior).to eq(15)
      expect(movimentacao.usuario).to eq(usuario)
      expect(movimentacao.motivo).to eq('Produção do lote 42')
    end

    it 'incrementa o estoque com estorno_devolucao' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :estorno_devolucao,
        quantidade: 2
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(12)
      expect(result.data[:movimentacao].saldo_posterior).to eq(12)
    end
  end

  describe 'saidas' do
    it 'decrementa o estoque com saida_venda' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: 4,
        usuario: usuario,
        motivo: 'Venda balcão'
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(6)

      movimentacao = result.data[:movimentacao]
      expect(movimentacao.tipo).to eq('saida_venda')
      expect(movimentacao.quantidade).to eq(4)
      expect(movimentacao.saldo_anterior).to eq(10)
      expect(movimentacao.saldo_posterior).to eq(6)
    end

    it 'decrementa o estoque com perda_avaria' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :perda_avaria,
        quantidade: 1,
        motivo: 'Peça danificada no transporte'
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(9)
      expect(result.data[:movimentacao].saldo_posterior).to eq(9)
    end

    it 'decrementa o estoque com brinde_marketing' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :brinde_marketing,
        quantidade: 3
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(7)
    end
  end

  describe 'ajuste manual' do
    it 'incrementa o estoque quando quantidade é positiva' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :ajuste_manual,
        quantidade: 5,
        motivo: 'Contagem de inventário encontrou sobra'
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(15)
      expect(result.data[:movimentacao].quantidade).to eq(5)
      expect(result.data[:movimentacao].saldo_anterior).to eq(10)
      expect(result.data[:movimentacao].saldo_posterior).to eq(15)
    end

    it 'decrementa o estoque quando quantidade é negativa' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :ajuste_manual,
        quantidade: -4,
        motivo: 'Ajuste de inventário por contagem física'
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(6)
      expect(result.data[:movimentacao].quantidade).to eq(4)
      expect(result.data[:movimentacao].saldo_anterior).to eq(10)
      expect(result.data[:movimentacao].saldo_posterior).to eq(6)
    end
  end

  describe 'referência polimórfica de origem' do
    it 'persiste origem polimórfica corretamente' do
      cliente = create(:cliente, empresa: empresa)
      venda = create(:venda, empresa: empresa, cliente: cliente)
      venda_item = create(:venda_item, venda: venda, variacao_produto: variacao, quantidade: 2)

      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: 2,
        origem: venda_item
      )

      expect(result).to be_success
      movimentacao = result.data[:movimentacao]
      expect(movimentacao.origem).to eq(venda_item)
      expect(movimentacao.origem_tipo).to eq('VendaItem')
      expect(movimentacao.origem_id).to eq(venda_item.id)
    end

    it 'persiste origem polimórfica passada como Hash explícito' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: 1,
        origem: { tipo: 'VendaItem', id: 456 }
      )

      expect(result).to be_success
      movimentacao = result.data[:movimentacao]
      expect(movimentacao.origem_tipo).to eq('VendaItem')
      expect(movimentacao.origem_id).to eq(456)
    end

    it 'persiste origem polimórfica passada via kwargs origem_tipo e origem_id' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: 1,
        origem_tipo: 'VendaItem',
        origem_id: 789
      )

      expect(result).to be_success
      movimentacao = result.data[:movimentacao]
      expect(movimentacao.origem_tipo).to eq('VendaItem')
      expect(movimentacao.origem_id).to eq(789)
    end
  end

  describe 'validações e tratamento de erros' do
    it 'rejeita saída quando saldo é insuficiente com código :insufficient_stock' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: 15
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:insufficient_stock)
      expect(result.error).to include('Saldo insuficiente')
      expect(estoque.reload.quantidade).to eq(10)
      expect(EstoqueMovimentacao.count).to eq(0)
    end

    it 'rejeita movimentação se a variação pertencer a outra empresa (:unauthorized_tenant)' do
      outra_empresa = create(:empresa)

      result = described_class.call(
        empresa: outra_empresa,
        variacao_produto: variacao,
        tipo: :entrada_producao,
        quantidade: 5
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(estoque.reload.quantidade).to eq(10)
    end

    it 'rejeita movimentação se o ID da variação pertencer a outra empresa (:unauthorized_tenant)' do
      outra_empresa = create(:empresa)

      result = described_class.call(
        empresa: outra_empresa,
        variacao_produto: variacao.id,
        tipo: :entrada_producao,
        quantidade: 5
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
      expect(estoque.reload.quantidade).to eq(10)
    end

    it 'rejeita movimentação se o estoque não existir (:stock_not_found)' do
      variacao_sem_estoque = create(:variacao_produto, produto: produto, empresa: empresa)
      variacao_sem_estoque.estoque&.destroy

      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao_sem_estoque,
        tipo: :entrada_producao,
        quantidade: 5
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:stock_not_found)
    end

    it 'rejeita tipo de movimentação inválido (:invalid_movement_type)' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :tipo_inexistente,
        quantidade: 5
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_movement_type)
    end

    it 'rejeita quantidade menor ou igual a zero em entradas e saídas (:invalid_quantity)' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :entrada_producao,
        quantidade: 0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_quantity)

      result_negativo = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :saida_venda,
        quantidade: -2
      )

      expect(result_negativo).to be_failure
      expect(result_negativo.error_code).to eq(:invalid_quantity)
    end

    it 'rejeita quantidade zero em ajuste manual (:invalid_quantity)' do
      result = described_class.call(
        empresa: empresa,
        variacao_produto: variacao,
        tipo: :ajuste_manual,
        quantidade: 0
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_quantity)
    end

    it 'aceita argumentos por IDs primitivos' do
      result = described_class.call(
        empresa: empresa.id,
        variacao_produto: variacao.id,
        tipo: :entrada_producao,
        quantidade: 2,
        usuario: usuario.id
      )

      expect(result).to be_success
      expect(estoque.reload.quantidade).to eq(12)
      expect(result.data[:movimentacao].usuario).to eq(usuario)
    end
  end

  describe 'concorrência e lock pessimista' do
    # Desativa fixtures transacionais para que conexões em threads separadas
    # acessem os mesmos registros comitados no PostgreSQL
    self.use_transactional_tests = false

    after do
      # Limpeza manual dos dados criados fora da transação de teste
      EstoqueMovimentacao.delete_all
      Estoque.delete_all
      VariacaoProduto.delete_all
      Produto.delete_all
      Empresa.delete_all
    end

    it 'impede saldos negativos e condição de corrida sob múltiplos acessos simultâneos' do
      empresa_conc = Empresa.create!(
        nome: 'Empresa Concorrente',
        slug: 'empresa-concorrente',
        email: 'conc@empresa.com'
      )
      produto_conc = Produto.create!(nome: 'Produto Concorrente', empresa: empresa_conc)
      variacao_conc = VariacaoProduto.create!(
        empresa: empresa_conc,
        produto: produto_conc,
        sku: 'CONC-SKU-01',
        preco_base: 50.0,
        preco_custo: 20.0
      )
      # Saldo inicial = 10 unidades
      estoque_conc = Estoque.create!(variacao_produto: variacao_conc, quantidade: 10, quantidade_minima: 0)

      # 10 threads concorrentes tentando retirar 2 unidades cada (demanda total = 20)
      # Como temos apenas 10 em estoque, exatamente 5 threads devem conseguir e 5 devem falhar
      num_threads = 10
      quantidade_por_thread = 2

      threads = num_threads.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(
              empresa: empresa_conc,
              variacao_produto: variacao_conc,
              tipo: :saida_venda,
              quantidade: quantidade_por_thread
            )
          end
        end
      end

      results = threads.map(&:value)

      sucessos = results.select(&:success?)
      falhas = results.select(&:failure?)

      expect(sucessos.count).to eq(5)
      expect(falhas.count).to eq(5)
      expect(falhas.map(&:error_code)).to all(eq(:insufficient_stock))

      # O saldo final deve ser exatamente 0, nunca negativo
      expect(estoque_conc.reload.quantidade).to eq(0)
      expect(EstoqueMovimentacao.where(variacao_produto: variacao_conc).count).to eq(5)
    end
  end
end
