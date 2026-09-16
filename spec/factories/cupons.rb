FactoryBot.define do
  factory :cupom do
    empresa
    sequence(:codigo) { |n| "PROMO#{n}" }
    tipo { :porcentagem }
    valor { 10.0 }
    valor_minimo_pedido { 50.0 }
    limite_usos { 100 }
    usos_contagem { 0 }
    valido_de { 1.day.ago }
    valido_ate { 30.days.from_now }
    ativo { true }
  end
end
