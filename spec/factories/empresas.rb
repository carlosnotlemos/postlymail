FactoryBot.define do
  factory :empresa do
    nome { "Dropwear Confecções" }
    sequence(:slug) { |n| "dropwear-#{n}" }
    documento { "12345678000195" }
    sequence(:email) { |n| "admin#{n}@dropwear.com.br" }
    ativo { true }
    data_cadastro { Time.current }
  end
end
