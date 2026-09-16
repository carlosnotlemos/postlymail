FactoryBot.define do
  factory :variacao_produto do
    produto
    sequence(:sku) { |n| "OVR-PRT-#{n}" }
    sequence(:codigo_barras) { |n| "789123456789#{n % 10}" }
    tamanho { "M" }
    cor { "Preta" }
    preco_base { 129.90 }
    preco_custo { 45.00 }
    ativo { true }
  end
end
