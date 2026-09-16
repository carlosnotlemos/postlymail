FactoryBot.define do
  factory :usuario do
    nome { "Carlos Silva" }
    sequence(:email) { |n| "usuario#{n}@exemplo.com" }
    telefone { "11987654321" }
    ativo { true }
    data_cadastro { Time.current }
  end
end
