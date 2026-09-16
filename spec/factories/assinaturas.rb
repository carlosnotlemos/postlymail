FactoryBot.define do
  factory :assinatura do
    empresa
    plano
    status { :ativa }
    ciclo { :mensal }
    valor { 49.90 }
    data_inicio { Date.current }
    data_fim { 1.month.from_now.to_date }
    data_cancelamento { nil }
  end
end
