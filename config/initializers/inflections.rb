# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "cupom", "cupons"
  inflect.irregular "devolucao", "devolucoes"
  inflect.irregular "devolucao_item", "devolucao_itens"
  inflect.irregular "variacao_produto", "variacoes_produtos"
  inflect.irregular "estoque_movimentacao", "estoque_movimentacoes"
  inflect.irregular "produto_categoria", "produto_categorias"
  inflect.irregular "produto_insumo", "produto_insumos"
  inflect.irregular "venda_item", "venda_itens"
  inflect.irregular "venda_pagamento", "venda_pagamentos"
  inflect.irregular "assinatura_fatura", "assinatura_faturas"
  inflect.irregular "webhook_log", "webhook_logs"
  inflect.irregular "identificador", "identificadores"
  inflect.irregular "papel", "papeis"
end
