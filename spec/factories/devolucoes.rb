FactoryBot.define do
  factory :devolucao do
    venda
    empresa { venda.empresa }
    tipo { :estorno_dinheiro }
    valor_estornado { 129.90 }
    motivo { "Tamanho ficou pequeno" }
    data_devolucao { Time.current }
  end
end
