FactoryBot.define do
  factory :estoque_movimentacao do
    empresa
    variacao_produto
    usuario { nil }
    tipo { :entrada_producao }
    quantidade { 20 }
    saldo_anterior { 10 }
    saldo_posterior { 30 }
    origem { nil }
    motivo { "Produção lote 01" }
  end
end
