FactoryBot.define do
  factory :estoque do
    variacao_produto
    quantidade { 50 }
    quantidade_minima { 5 }
  end
end
