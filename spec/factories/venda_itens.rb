FactoryBot.define do
  factory :venda_item do
    venda
    variacao_produto
    detalhes_produto { { "nome" => "Camiseta Oversized", "tamanho" => "M", "cor" => "Preta" } }
    valor_unitario { 129.90 }
    preco_custo_unitario { 45.00 }
    quantidade { 1 }
    subtotal { 129.90 }
    observacoes { nil }
  end
end
