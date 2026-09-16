FactoryBot.define do
  factory :assinatura_fatura do
    assinatura
    valor { 49.90 }
    data_vencimento { 5.days.from_now.to_date }
    data_pagamento { nil }
    status { :pendente }
    sequence(:gateway_id) { |n| "fat_#{n}" }
    metadados { { "linha_digitavel" => "123456" } }
  end
end
