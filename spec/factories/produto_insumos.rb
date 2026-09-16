FactoryBot.define do
  factory :produto_insumo do
    variacao_produto
    nome { "Malha 100% Algodão" }
    valor { 22.50 }
  end
end
