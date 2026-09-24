# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_201000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "assinatura_faturas", force: :cascade do |t|
    t.bigint "assinatura_id", null: false
    t.datetime "created_at", null: false
    t.datetime "data_pagamento"
    t.date "data_vencimento", null: false
    t.string "gateway_id"
    t.jsonb "metadados", default: "{}", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["assinatura_id"], name: "index_assinatura_faturas_on_assinatura_id"
    t.index ["gateway_id"], name: "index_assinatura_faturas_on_gateway_id", unique: true, where: "(gateway_id IS NOT NULL)"
  end

  create_table "assinaturas", force: :cascade do |t|
    t.integer "ciclo", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "data_cancelamento"
    t.date "data_fim"
    t.date "data_inicio"
    t.bigint "empresa_id", null: false
    t.bigint "plano_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["empresa_id"], name: "index_assinaturas_on_empresa_ativa", unique: true, where: "(status = 1)"
    t.index ["empresa_id"], name: "index_assinaturas_on_empresa_id"
    t.index ["plano_id"], name: "index_assinaturas_on_plano_id"
  end

  create_table "campanhas", force: :cascade do |t|
    t.string "assunto"
    t.integer "canal", default: 0, null: false
    t.text "conteudo", null: false
    t.datetime "created_at", null: false
    t.datetime "data_envio"
    t.bigint "empresa_id", null: false
    t.string "nome", null: false
    t.integer "segmento", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url_midia"
    t.index ["empresa_id", "status"], name: "index_campanhas_on_empresa_id_and_status"
    t.index ["empresa_id"], name: "index_campanhas_on_empresa_id"
  end

  create_table "clientes", force: :cascade do |t|
    t.boolean "aceita_marketing", default: true, null: false
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "data_cadastro", null: false
    t.string "documento"
    t.string "email"
    t.bigint "empresa_id", null: false
    t.string "nome", null: false
    t.string "telefone"
    t.datetime "updated_at", null: false
    t.index ["empresa_id", "documento"], name: "index_clientes_on_empresa_id_and_documento", unique: true, where: "((documento IS NOT NULL) AND ((documento)::text <> ''::text))"
    t.index ["empresa_id", "email"], name: "index_clientes_on_empresa_id_and_email"
    t.index ["empresa_id"], name: "index_clientes_on_empresa_id"
  end

  create_table "convites", force: :cascade do |t|
    t.datetime "aceito_em"
    t.datetime "cancelado_em"
    t.bigint "convidado_por_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "empresa_id", null: false
    t.datetime "expira_em", null: false
    t.integer "papel", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["cancelado_em"], name: "index_convites_on_cancelado_em"
    t.index ["convidado_por_id"], name: "index_convites_on_convidado_por_id"
    t.index ["empresa_id", "email"], name: "index_convites_on_empresa_and_email_pendente", unique: true, where: "((aceito_em IS NULL) AND (cancelado_em IS NULL))"
    t.index ["token"], name: "index_convites_on_token", unique: true
  end

  create_table "cupons", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.string "codigo", null: false
    t.datetime "created_at", null: false
    t.bigint "empresa_id", null: false
    t.integer "limite_usos"
    t.integer "tipo", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "usos_contagem", default: 0, null: false
    t.datetime "valido_ate"
    t.datetime "valido_de"
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "valor_minimo_pedido", precision: 10, scale: 2, default: "0.0"
    t.index ["empresa_id", "codigo"], name: "index_cupons_on_empresa_id_and_codigo", unique: true
  end

  create_table "custos", force: :cascade do |t|
    t.integer "categoria", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "data_custo", null: false
    t.string "descricao"
    t.bigint "empresa_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "venda_id"
    t.index ["empresa_id", "categoria"], name: "index_custos_on_empresa_id_and_categoria"
    t.index ["empresa_id", "data_custo"], name: "index_custos_on_empresa_id_and_data_custo"
    t.index ["empresa_id"], name: "index_custos_on_empresa_id"
    t.index ["venda_id"], name: "index_custos_on_venda_id"
  end

  create_table "devolucao_itens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "devolucao_id", null: false
    t.integer "quantidade", default: 1, null: false
    t.boolean "retornou_ao_estoque", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "venda_item_id", null: false
    t.index ["devolucao_id"], name: "index_devolucao_itens_on_devolucao_id"
    t.index ["venda_item_id"], name: "index_devolucao_itens_on_venda_item_id"
  end

  create_table "devolucoes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "data_devolucao", null: false
    t.bigint "empresa_id", null: false
    t.text "motivo"
    t.integer "tipo", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "valor_estornado", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "venda_id", null: false
    t.index ["empresa_id", "data_devolucao"], name: "index_devolucoes_on_empresa_id_and_data_devolucao"
    t.index ["empresa_id"], name: "index_devolucoes_on_empresa_id"
    t.index ["venda_id"], name: "index_devolucoes_on_venda_id"
  end

  create_table "disparos", force: :cascade do |t|
    t.bigint "campanha_id", null: false
    t.bigint "cliente_id", null: false
    t.datetime "created_at", null: false
    t.string "destinatario", null: false
    t.datetime "enviado_em"
    t.string "identificador_externo"
    t.text "mensagem_erro"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["campanha_id", "status"], name: "index_disparos_on_campanha_id_and_status"
    t.index ["campanha_id"], name: "index_disparos_on_campanha_id"
    t.index ["cliente_id"], name: "index_disparos_on_cliente_id"
    t.index ["identificador_externo"], name: "index_disparos_on_identificador_externo", where: "(identificador_externo IS NOT NULL)"
  end

  create_table "empresas", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "data_cadastro", null: false
    t.string "documento"
    t.string "email", null: false
    t.string "nome", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_empresas_on_slug", unique: true
  end

  create_table "enderecos", force: :cascade do |t|
    t.string "bairro", null: false
    t.string "cep", limit: 10, null: false
    t.string "cidade", null: false
    t.bigint "cliente_id", null: false
    t.string "complemento"
    t.datetime "created_at", null: false
    t.string "estado", limit: 2, null: false
    t.string "logradouro", null: false
    t.string "numero", limit: 50, null: false
    t.boolean "padrao", default: false, null: false
    t.text "ponto_referencia"
    t.string "titulo", default: "Principal"
    t.datetime "updated_at", null: false
    t.index ["cliente_id"], name: "index_enderecos_on_cliente_id"
    t.index ["cliente_id"], name: "index_enderecos_on_cliente_id_padrao", unique: true, where: "(padrao = true)"
  end

  create_table "estoque_movimentacoes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "empresa_id", null: false
    t.string "motivo"
    t.bigint "origem_id"
    t.string "origem_tipo"
    t.integer "quantidade", null: false
    t.integer "saldo_anterior", null: false
    t.integer "saldo_posterior", null: false
    t.integer "tipo", null: false
    t.datetime "updated_at", null: false
    t.bigint "usuario_id"
    t.bigint "variacao_produto_id", null: false
    t.index ["empresa_id", "created_at"], name: "index_estoque_movimentacoes_on_empresa_id_and_created_at"
    t.index ["empresa_id"], name: "index_estoque_movimentacoes_on_empresa_id"
    t.index ["origem_tipo", "origem_id"], name: "index_estoque_movimentacoes_on_origem_tipo_and_origem_id"
    t.index ["usuario_id"], name: "index_estoque_movimentacoes_on_usuario_id"
    t.index ["variacao_produto_id"], name: "index_estoque_movimentacoes_on_variacao_produto_id"
  end

  create_table "estoques", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "quantidade", default: 0, null: false
    t.integer "quantidade_minima", default: 5, null: false
    t.datetime "updated_at", null: false
    t.bigint "variacao_produto_id", null: false
    t.index ["variacao_produto_id"], name: "index_estoques_on_variacao_produto_id", unique: true
    t.check_constraint "quantidade >= 0", name: "check_estoques_quantidade_non_negative"
  end

  create_table "membros", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.bigint "convidado_por_id"
    t.datetime "created_at", null: false
    t.datetime "data_entrada", null: false
    t.bigint "empresa_id", null: false
    t.integer "papel", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "usuario_id", null: false
    t.index ["convidado_por_id"], name: "index_membros_on_convidado_por_id"
    t.index ["empresa_id", "usuario_id"], name: "index_membros_on_empresa_id_and_usuario_id", unique: true
    t.index ["usuario_id"], name: "index_membros_on_usuario_id"
  end

  create_table "planos", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "identificador", null: false
    t.integer "limite_disparos", default: 0, null: false
    t.integer "limite_produtos", default: 15
    t.integer "limite_usuarios", default: 2
    t.string "nome", null: false
    t.datetime "updated_at", null: false
    t.decimal "valor_mensal", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["identificador"], name: "index_planos_on_identificador", unique: true
  end

  create_table "produto_categorias", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "empresa_id", null: false
    t.string "nome", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["empresa_id", "slug"], name: "index_produto_categorias_on_empresa_id_and_slug", unique: true
  end

  create_table "produto_insumos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "nome", null: false
    t.datetime "updated_at", null: false
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "variacao_produto_id", null: false
    t.index ["variacao_produto_id"], name: "index_produto_insumos_on_variacao_produto_id"
  end

  create_table "produtos", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.text "descricao"
    t.bigint "empresa_id", null: false
    t.string "nome", null: false
    t.bigint "produto_categoria_id"
    t.datetime "updated_at", null: false
    t.index ["empresa_id", "ativo"], name: "index_produtos_on_empresa_id_and_ativo"
    t.index ["empresa_id"], name: "index_produtos_on_empresa_id"
    t.index ["produto_categoria_id"], name: "index_produtos_on_produto_categoria_id"
  end

  create_table "usuarios", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "data_cadastro", null: false
    t.string "email", null: false
    t.string "nome", null: false
    t.string "telefone"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_usuarios_on_email", unique: true
  end

  create_table "variacoes_produtos", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.string "codigo_barras"
    t.string "cor"
    t.datetime "created_at", null: false
    t.bigint "empresa_id", null: false
    t.decimal "preco_base", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "preco_custo", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "produto_id", null: false
    t.string "sku", null: false
    t.string "tamanho"
    t.datetime "updated_at", null: false
    t.index ["codigo_barras"], name: "index_variacoes_produtos_on_codigo_barras"
    t.index ["empresa_id", "sku"], name: "index_variacoes_produtos_on_empresa_id_and_sku", unique: true
    t.index ["empresa_id"], name: "index_variacoes_produtos_on_empresa_id"
    t.index ["produto_id"], name: "index_variacoes_produtos_on_produto_id"
  end

  create_table "venda_itens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "detalhes_produto", default: "{}", null: false
    t.text "observacoes"
    t.decimal "preco_custo_unitario", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "quantidade", default: 1, null: false
    t.decimal "subtotal", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.decimal "valor_unitario", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "variacao_produto_id", null: false
    t.bigint "venda_id", null: false
    t.index ["variacao_produto_id"], name: "index_venda_itens_on_variacao_produto_id"
    t.index ["venda_id"], name: "index_venda_itens_on_venda_id"
  end

  create_table "venda_pagamentos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "data_liquidacao"
    t.integer "forma_pagamento", default: 0, null: false
    t.integer "gateway", default: 0, null: false
    t.string "gateway_id"
    t.jsonb "metadados", default: "{}", null: false
    t.integer "parcelas", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.decimal "taxa_operadora", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.decimal "valor", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "valor_liquido", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "venda_id", null: false
    t.index ["gateway_id"], name: "index_venda_pagamentos_on_gateway_id", where: "(gateway_id IS NOT NULL)"
    t.index ["venda_id", "status"], name: "index_venda_pagamentos_on_venda_id_and_status"
    t.index ["venda_id"], name: "index_venda_pagamentos_on_venda_id"
  end

  create_table "vendas", force: :cascade do |t|
    t.datetime "cancelado_em"
    t.bigint "cancelado_por_id"
    t.bigint "cliente_id", null: false
    t.string "codigo_cupom"
    t.string "codigo_pedido", null: false
    t.string "codigo_rastreio"
    t.datetime "created_at", null: false
    t.bigint "cupom_id"
    t.datetime "data_venda", null: false
    t.decimal "desconto_cupom", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "desconto_manual", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "empresa_id", null: false
    t.jsonb "endereco_entrega", default: "{}", null: false
    t.text "motivo_cancelamento"
    t.text "observacoes"
    t.integer "status", default: 0, null: false
    t.decimal "subtotal_produtos", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "tipo_entrega", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "usuario_id"
    t.decimal "valor_desconto", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "valor_frete", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "valor_total", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["cancelado_por_id"], name: "index_vendas_on_cancelado_por_id"
    t.index ["cliente_id"], name: "index_vendas_on_cliente_id"
    t.index ["cupom_id"], name: "index_vendas_on_cupom_id"
    t.index ["empresa_id", "codigo_pedido"], name: "index_vendas_on_empresa_id_and_codigo_pedido", unique: true
    t.index ["empresa_id", "status"], name: "index_vendas_on_empresa_id_and_status"
    t.index ["usuario_id"], name: "index_vendas_on_usuario_id"
  end

  create_table "webhook_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "evento"
    t.string "identificador_externo"
    t.text "mensagem_erro"
    t.jsonb "payload", default: {}, null: false
    t.datetime "processado_em"
    t.integer "provedor", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["provedor", "identificador_externo"], name: "index_webhook_logs_on_provedor_and_identificador_externo", unique: true, where: "(identificador_externo IS NOT NULL)"
  end

  add_foreign_key "assinatura_faturas", "assinaturas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "assinaturas", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "assinaturas", "planos", on_update: :cascade, on_delete: :restrict
  add_foreign_key "campanhas", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "clientes", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "convites", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "convites", "usuarios", column: "convidado_por_id", on_update: :cascade, on_delete: :cascade
  add_foreign_key "cupons", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "custos", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "custos", "vendas", on_update: :cascade, on_delete: :nullify
  add_foreign_key "devolucao_itens", "devolucoes", on_update: :cascade, on_delete: :cascade
  add_foreign_key "devolucao_itens", "venda_itens", on_update: :cascade, on_delete: :restrict
  add_foreign_key "devolucoes", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "devolucoes", "vendas", on_update: :cascade, on_delete: :restrict
  add_foreign_key "disparos", "campanhas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "disparos", "clientes", on_update: :cascade, on_delete: :cascade
  add_foreign_key "enderecos", "clientes", on_update: :cascade, on_delete: :cascade
  add_foreign_key "estoque_movimentacoes", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "estoque_movimentacoes", "usuarios", on_update: :cascade, on_delete: :nullify
  add_foreign_key "estoque_movimentacoes", "variacoes_produtos", on_update: :cascade, on_delete: :cascade
  add_foreign_key "estoques", "variacoes_produtos", on_update: :cascade, on_delete: :cascade
  add_foreign_key "membros", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "membros", "usuarios", column: "convidado_por_id", on_update: :cascade, on_delete: :nullify
  add_foreign_key "membros", "usuarios", on_update: :cascade, on_delete: :cascade
  add_foreign_key "produto_categorias", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "produto_insumos", "variacoes_produtos", on_update: :cascade, on_delete: :cascade
  add_foreign_key "produtos", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "produtos", "produto_categorias", on_update: :cascade, on_delete: :nullify
  add_foreign_key "variacoes_produtos", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "variacoes_produtos", "produtos", on_update: :cascade, on_delete: :cascade
  add_foreign_key "venda_itens", "variacoes_produtos", on_update: :cascade, on_delete: :restrict
  add_foreign_key "venda_itens", "vendas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "venda_pagamentos", "vendas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "vendas", "clientes", on_update: :cascade, on_delete: :restrict
  add_foreign_key "vendas", "cupons", on_update: :cascade, on_delete: :nullify
  add_foreign_key "vendas", "empresas", on_update: :cascade, on_delete: :cascade
  add_foreign_key "vendas", "usuarios", column: "cancelado_por_id", on_update: :cascade, on_delete: :nullify
  add_foreign_key "vendas", "usuarios", on_update: :cascade, on_delete: :nullify
end
