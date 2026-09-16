FactoryBot.define do
  factory :devolucao_item do
    devolucao
    venda_item { association :venda_item, venda: devolucao.venda }
    quantidade { 1 }
    retornou_ao_estoque { true }
  end
end
