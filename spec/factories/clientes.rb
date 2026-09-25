FactoryBot.define do
  factory :cliente do
    empresa
    nome { "João Pereira" }
    sequence(:documento) { |n| sprintf("%011d", 12345678900 + n) }
    sequence(:email) { |n| "cliente#{n}@gmail.com" }
    telefone { "85999998888" }
    ativo { true }
    aceita_marketing { true }
    data_cadastro { Time.current }
  end
end
