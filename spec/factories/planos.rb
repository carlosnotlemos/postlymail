FactoryBot.define do
  factory :plano do
    sequence(:identificador) { |n| Plano.identificadors.values[n % Plano.identificadors.size] }
    nome { "Start" }
    valor_mensal { 49.90 }
    limite_produtos { 15 }
    limite_disparos { 500 }
    limite_usuarios { 2 }
    ativo { true }
  end
end
