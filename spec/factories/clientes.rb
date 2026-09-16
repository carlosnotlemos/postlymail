FactoryBot.define do
  factory :cliente do
    empresa
    nome { "João Pereira" }
    documento { "12345678901" }
    sequence(:email) { |n| "cliente#{n}@gmail.com" }
    telefone { "85999998888" }
    ativo { true }
    aceita_marketing { true }
    data_cadastro { Time.current }
  end
end
