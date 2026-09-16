FactoryBot.define do
  factory :venda do
    empresa
    cliente { association :cliente, empresa: empresa }
    usuario { association :usuario }
    cupom { nil }
    cancelado_por { nil }
    codigo_cupom { nil }
    sequence(:codigo_pedido) { |n| "FT-#{n.to_s.rjust(6, '0')}" }
    subtotal_produtos { 199.90 }
    valor_frete { 15.00 }
    desconto_cupom { 0.0 }
    desconto_manual { 0.0 }
    valor_desconto { 0.0 }
    valor_total { 214.90 }
    tipo_entrega { :motoboy_uber }
    endereco_entrega { { "cep" => "60000000", "logradouro" => "Rua A", "numero" => "10" } }
    codigo_rastreio { nil }
    status { :pendente }
    data_venda { Time.current }
    observacoes { "Entregar no período da tarde" }
    cancelado_em { nil }
    motivo_cancelamento { nil }
  end
end
