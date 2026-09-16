FactoryBot.define do
  factory :produto_categoria do
    empresa
    nome { "Camisetas Oversized" }
    sequence(:slug) { |n| "camisetas-oversized-#{n}" }
    ativo { true }
  end
end
