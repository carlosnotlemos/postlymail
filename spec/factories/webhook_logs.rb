FactoryBot.define do
  factory :webhook_log do
    provedor { :asaas }
    evento { "PAYMENT_RECEIVED" }
    sequence(:identificador_externo) { |n| "pay_#{n}" }
    payload { { "id" => "pay_123", "value" => 100.0 } }
    status { :pendente }
    mensagem_erro { nil }
    processado_em { nil }
  end
end
