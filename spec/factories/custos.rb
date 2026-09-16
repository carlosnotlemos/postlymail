FactoryBot.define do
  factory :custo do
    empresa
    venda { nil }
    categoria { :insumos_producao }
    valor { 150.00 }
    data_custo { Date.current }
    descricao { "DTF CST Lote 1" }
  end
end
