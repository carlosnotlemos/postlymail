FactoryBot.define do
  factory :venda_pagamento do
    venda
    gateway { :asaas }
    sequence(:gateway_id) { |n| "pay_#{n}" }
    valor { 214.90 }
    taxa_operadora { 4.90 }
    valor_liquido { 210.00 }
    forma_pagamento { :pix }
    status { :aprovado }
    parcelas { 1 }
    data_liquidacao { Time.current }
    metadados { { "qr_code" => "payload_pix" } }
  end
end
