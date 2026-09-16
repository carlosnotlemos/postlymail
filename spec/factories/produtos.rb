FactoryBot.define do
  factory :produto do
    empresa
    produto_categoria { nil }
    nome { "Camiseta Oversized Boxy" }
    descricao { "100% Algodão penteado fio 26.1" }
    ativo { true }
  end
end
