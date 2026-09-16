FactoryBot.define do
  factory :disparo do
    campanha
    cliente
    sequence(:identificador_externo) { |n| "msg_#{n}" }
    destinatario { "85999998888" }
    status { :enviado }
    enviado_em { Time.current }
    mensagem_erro { nil }
  end
end
