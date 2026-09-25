# Histórico de Desenvolvimento — Arquitetura e Esteira de Implementação

> Documento de referência para registrar a evolução estrutural do ERP, suas dependências e a ordem planejada de implementação dos Service Objects.

---

## 1. Classificação das Tabelas por Complexidade Operacional

### 1.1 Tabelas Simples — Cadastros Base e Folhas Independentes

Estas tabelas possuem poucas dependências de regras operacionais externas. Elas existem como cadastros fundamentais ou fornecem suporte estático para o restante do ERP.

| Tabela | Responsabilidade |
|---|---|
| `Empresas` | Tenant raiz da aplicação; praticamente todas as outras tabelas dependem dela. |
| `Usuarios` | Identidades dos operadores, atendentes e proprietários. |
| `Planos` | Tabela estática de planos SaaS (`start`, `pro`, `enterprise`), precificação e limites de recursos. |
| `Produto_categorias` | Agrupamento taxonômico com `slug` e `empresa_id`. |
| `Clientes` | Cadastro de compradores: contato, documento e consentimento de marketing. |
| `Enderecos` | Endereços vinculados aos clientes, com flag de endereço principal (`padrao`). |
| `Cupons` | Regras de desconto promocional (`porcentagem` ou `valor_fixo`), vigência e tetos de uso. |
| `Custos` | Lançamentos financeiros avulsos de insumos, frete, tráfego ou operações. |
| `Webhook_logs` | Tabela técnica para armazenamento de requisições brutas recebidas de gateways e mensageria. |

### 1.2 Tabelas Complexas — Transacionais, Concorrentes e Orquestradas

Estas tabelas concentram validações de estado, concorrência, locks pessimistas, integridade referencial estrita e snapshots de auditoria.

| Tabelas | Responsabilidade |
|---|---|
| `Produtos` e `Variacoes_produtos` | Catálogo estruturado em grade, incluindo SKUs, tamanhos, cores, custos e preços. |
| `Produto_insumos` | Composição da ficha técnica de custo de cada variação: malha, estampa, costura, tags etc. |
| `Estoques` | Ponto crítico de concorrência, com `CHECK quantidade >= 0` e lock pessimista. |
| `Estoque_movimentacoes` | Ledger imutável de auditoria, com rastreamento polimórfico da origem e saldos anterior/posterior. |
| `Vendas` e `Venda_itens` | Orquestrador central com snapshots imutáveis em JSONB (`endereco_entrega`, `detalhes_produto`), frete, cupons e totalizadores. |
| `Venda_pagamentos` | Divisão de parcelas, conciliação com gateways, retenção de taxa e cálculo de valor líquido. |
| `Devolucoes` e `Devolucao_itens` | Estornos financeiros ou créditos de troca, com decisão de retorno ou descarte físico em estoque (`retornou_ao_estoque`). |
| `Assinaturas` e `Assinatura_faturas` | Cobrança recorrente do SaaS, incluindo ciclo de vida, vigência e faturamento. |
| `Membros` e `Convites` | Permissões de equipe por tenant, com controle de papéis (`papel`) e expiração de tokens. |
| `Campanhas` e `Disparos` | Automação de marketing, com rastreio de entrega por e-mail/WhatsApp e segmentação da base de clientes. |

---

# 2. Sequência Recomendada de Implementação

A implementação dos Service Objects deve seguir uma ordem que respeite as dependências entre os domínios e evite dependências circulares.

## Visão Geral

```text
┌─────────────────────────────────────────────────────────────────┐
│ FASE 1: FUNDAÇÃO MULTI-TENANT & EQUIPE                          │
│ Empresas ──► Usuarios ──► Membros ──► Convites                  │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│ FASE 2: CATÁLOGO, FICHA TÉCNICA & ESTOQUE (CONCLUÍDO)           │
│ Categorias ──► Produtos ──► Variações ──► Insumos ──► Estoques  │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│ FASE 3: CLIENTES & SERVIÇOS DE SUPORTE À VENDA                  │
│ Clientes ──► Endereços ──► Cupons (Validar/Aplicar)             │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│ FASE 4: O NÚCLEO TRANSACIONAL DE VENDAS & FINANCEIRO            │
│ Vendas ──► Venda_itens ──► Venda_pagamentos ──► Devoluções      │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│ FASE 5: SAAS RECORRENTE & MARKETING                             │
│ Planos ──► Assinaturas ──► Faturas │ Campanhas ──► Disparos    │
└─────────────────────────────────────────────────────────────────┘
```

---

# 3. Detalhamento das Fases

## Fase 1 — Fundação Multi-tenant e Gestão de Acesso

### Objetivo

Estabelecer a estrutura básica de empresas, usuários e controle de acesso da aplicação.

### Ordem

1. `Empresas` e `Usuarios`
   - Cadastros estruturais.
2. `Convites` e `Membros`
   - Convites para atendentes, estoquistas e demais integrantes da equipe.
   - Controle de papéis.
   - Aceitação e expiração de convites.

### Service Objects concluídos

```ruby
Empresas::SalvarService (aliases: Empresas::CadastrarService, Empresas::CriarService, Empresas::AtualizarService)
Empresas::InativarService (alias: Empresas::DesativarService)
Usuarios::SalvarService (aliases: Usuarios::CadastrarService, Usuarios::CriarService, Usuarios::AtualizarService)
Usuarios::InativarService (aliases: Usuarios::DesativarService, Usuarios::BloquearService)
Membros::SalvarService (aliases: Membros::CadastrarService, Membros::CriarService, Membros::AtualizarService)
Membros::InativarService (aliases: Membros::DesativarService, Membros::RemoverService)
Convites::SalvarService (aliases: Convites::CadastrarService, Convites::CriarService, Convites::EnviarService)
Convites::AceitarService
Convites::CancelarService (aliases: Convites::RevogarService, Convites::ExcluirService)
```

### Estado

**CONCLUÍDO (Empresas, Usuários, Membros e Convites concluídos).**

---

## Fase 2 — Catálogo e Inventário

### Objetivo

Construir a estrutura responsável pelos produtos, suas variações, composição de custos e controle físico do estoque.

### Ordem

1. `Produto_categorias` e `Produtos`
2. `Variacoes_produtos` e `Produto_insumos`
   - Definição de preço base.
   - Definição do custo de confecção.
3. `Estoques` e `Estoque_movimentacoes`
   - Controle de quantidade.
   - Auditoria das movimentações.
   - Concorrência e locks.
   - Proteção contra estoque negativo.

### Service Object concluído

```ruby
Estoques::MovimentarService
```

### Estado

**CONCLUÍDO.**

---

## Fase 3 — Suporte Prévio à Venda

### Objetivo

Disponibilizar os dados necessários para que uma venda possa ser criada e validada.

### Ordem

1. `Clientes` e `Enderecos`
   - Criação e manutenção dos clientes.
   - Cadastro de endereços.
   - Identificação do endereço padrão.
   - Resolução e validação do endereço de entrega.

2. `Cupons`
   - Validação da vigência.
   - Controle da quantidade de utilizações.
   - Cálculo do desconto.
   - Suporte a desconto percentual ou valor fixo.

### Service Objects concluídos

```ruby
Cupons::AplicarService
Cupons::SalvarService (alias: Cupons::CadastrarService)
Cupons::InativarService
Clientes::SalvarService (alias: Clientes::CadastrarService)
Clientes::ResolverEnderecoService (alias: Clientes::ResolverEnderecoEntregaService)
Clientes::InativarService
```

### Estado

**CONCLUÍDO.**

---

# 4. Fase 4 — Núcleo de Vendas e Pós-venda

### Objetivo

Implementar o fluxo transacional principal do ERP: fechamento da venda, baixa de estoque, pagamento, cancelamento e devolução.

## 4.1 Fechamento da Venda

Tabelas:

```text
Vendas
  └── Venda_itens
```

Service Object:

```ruby
Vendas::FecharVendaService
```

Responsabilidades principais:

- Consumir produtos e variações cadastrados.
- Validar disponibilidade em estoque.
- Aplicar regras da venda.
- Aplicar cupons quando aplicável.
- Calcular frete.
- Calcular totalizadores.
- Congelar o endereço de entrega em snapshot JSONB.
- Congelar os detalhes dos produtos em snapshot JSONB.
- Debitar o estoque.
- Registrar a operação de maneira transacional.

---

## 4.2 Registro de Pagamentos

Tabela:

```text
Venda_pagamentos
```

Service Object:

```ruby
Pagamentos::RegistrarService
```

Responsabilidades:

- Registrar parcelas.
- Integrar/consolidar informações de gateways.
- Calcular taxas.
- Calcular valor líquido.
- Registrar a liquidação financeira.

---

## 4.3 Cancelamento da Venda

Service Object:

```ruby
Vendas::CancelarVendaService
```

Responsabilidades:

- Validar se a venda pode ser cancelada.
- Reverter o fluxo financeiro quando necessário.
- Estornar os itens.
- Reintegrar os produtos ao estoque quando aplicável.
- Preservar o histórico da operação.

---

## 4.4 Devoluções

Tabelas:

```text
Devolucoes
  └── Devolucao_itens
```

Service Object:

```ruby
Devolucoes::ProcessarService
```

Responsabilidades:

- Processar devolução.
- Definir se haverá estorno financeiro ou crédito de troca.
- Avaliar o destino físico do produto.
- Reintegrar ao estoque quando:

```ruby
retornou_ao_estoque == true
```

Quando houver retorno ao estoque, a movimentação deverá utilizar:

```text
tipo = estorno_devolucao
```

A movimentação deve utilizar o mecanismo centralizado:

```ruby
Estoques::MovimentarService
```

### Estado

**Planejada.**

---

# 5. Fase 5 — SaaS Recorrente e Automação de Marketing

## 5.1 Assinaturas

Tabelas:

```text
Planos
  └── Assinaturas
        └── Assinatura_faturas
```

### Objetivo

Implementar o ciclo financeiro recorrente do próprio SaaS.

Responsabilidades:

- Cadastro de planos.
- Associação do plano ao tenant.
- Controle do ciclo de vida da assinatura.
- Controle da vigência.
- Geração de faturas.
- Controle de cobrança recorrente.

### Estado

**Planejada.**

---

## 5.2 Campanhas e Disparos

Tabelas:

```text
Campanhas
  └── Disparos
```

### Objetivo

Implementar automação de marketing baseada no histórico e no comportamento dos clientes.

Canais previstos:

- WhatsApp
- E-mail

Possíveis critérios de segmentação:

- Histórico de compras.
- Produtos adquiridos.
- Perfil do cliente.
- Frequência de compras.
- Outros critérios derivados dos dados transacionais.

### Estado

**Planejada.**

---

# 6. Mapa Geral de Dependências

```text
EMPRESAS
   │
   ├──► USUARIOS
   │      │
   │      ├──► MEMBROS
   │      │      └──► CONVITES
   │      │
   │      └──► operações do tenant
   │
   ├──► PRODUTO_CATEGORIAS
   │      │
   │      └──► PRODUTOS
   │             │
   │             └──► VARIACOES_PRODUTOS
   │                    │
   │                    ├──► PRODUTO_INSUMOS
   │                    │
   │                    └──► ESTOQUES
   │                           │
   │                           └──► ESTOQUE_MOVIMENTACOES
   │
   ├──► CLIENTES
   │      │
   │      └──► ENDERECOS
   │
   ├──► CUPONS
   │
   ├──► VENDAS
   │      │
   │      ├──► VENDA_ITENS
   │      │
   │      ├──► VENDA_PAGAMENTOS
   │      │
   │      └──► DEVOLUCOES
   │             └──► DEVOLUCAO_ITENS
   │
   ├──► PLANOS
   │      │
   │      └──► ASSINATURAS
   │             └──► ASSINATURA_FATURAS
   │
   └──► CAMPANHAS
          └──► DISPAROS
```

---

# 7. Service Objects — Mapa Atual

| Service Object | Domínio | Estado |
|---|---|---|
| `Estoques::MovimentarService` | Estoque | ✅ Concluído |
| `Cupons::AplicarService` | Cupons | ✅ Concluído |
| `Cupons::SalvarService` (alias: `CadastrarService`) | Cupons | ✅ Concluído |
| `Cupons::InativarService` | Cupons | ✅ Concluído |
| `Clientes::SalvarService` | Clientes | ✅ Concluído |
| `Clientes::ResolverEnderecoService` | Clientes | ✅ Concluído |
| `Clientes::InativarService` | Clientes | ✅ Concluído |
| `ProdutoCategorias::SalvarService` (alias: `CadastrarService`) | Catálogo | ✅ Concluído |
| `ProdutoCategorias::InativarService` | Catálogo | ✅ Concluído |
| `ProdutoCategorias::ExcluirService` | Catálogo | ✅ Concluído |
| `Produtos::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`) | Catálogo / Produtos | ✅ Concluído |
| `Produtos::InativarService` (alias: `DesativarService`) | Catálogo / Produtos | ✅ Concluído |
| `Produtos::ReativarService` (alias: `AtivarService`) | Catálogo / Produtos | ✅ Concluído |
| `Custos::SalvarService` (alias: `CadastrarService`, `CriarService`) | Financeiro / Custos | ✅ Concluído |
| `Custos::ExcluirService` (alias: `RemoverService`, `DeletarService`) | Financeiro / Custos | ✅ Concluído |
| `Custos::SalvarEmLoteService` (alias: `CadastrarLoteService`, `RegistrarLoteService`) | Financeiro / Custos | ✅ Concluído |
| `Planos::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`) | Planos SaaS | ✅ Concluído |
| `Assinaturas::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`, `ContratarService`) | SaaS Recorrente | ✅ Concluído |
| `Assinaturas::CancelarService` (alias: `EncerrarService`, `DesativarService`) | SaaS Recorrente | ✅ Concluído |
| `Empresas::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`) | Multi-tenant / Empresas | ✅ Concluído |
| `Empresas::InativarService` (alias: `DesativarService`) | Multi-tenant / Empresas | ✅ Concluído |
| `Usuarios::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`) | Gestão de Acesso / Usuários | ✅ Concluído |
| `Usuarios::InativarService` (alias: `DesativarService`, `BloquearService`) | Gestão de Acesso / Usuários | ✅ Concluído |
| `Membros::SalvarService` (alias: `CadastrarService`, `CriarService`, `AtualizarService`) | Equipe / Membros | ✅ Concluído |
| `Membros::InativarService` (alias: `DesativarService`, `RemoverService`) | Equipe / Membros | ✅ Concluído |
| `Convites::SalvarService` (alias: `CadastrarService`, `CriarService`, `EnviarService`) | Equipe / Convites | ✅ Concluído |
| `Convites::AceitarService` | Equipe / Convites | ✅ Concluído |
| `Convites::CancelarService` (alias: `RevogarService`, `ExcluirService`) | Equipe / Convites | ✅ Concluído |
| `Vendas::FecharVendaService` (aliases: `SalvarService`, `CriarService`, `FecharService`) | Vendas | ✅ Concluído |
| `Vendas::CancelarVendaService` (aliases: `CancelarService`, `EstornarService`) | Vendas | ✅ Concluído |
| `Pagamentos::RegistrarService` (aliases: `SalvarService`, `CriarService`, `Vendas::RegistrarPagamentoService`) | Pagamentos | ✅ Concluído |
| `Devolucoes::ProcessarService` (aliases: `SalvarService`, `CriarService`) | Devoluções | ✅ Concluído |
| `AssinaturaFaturas::GerarService` (aliases: `SalvarService`, `CriarService`, `Assinaturas::GerarFaturaService`) | SaaS Recorrente / Faturas | ✅ Concluído |
| `AssinaturaFaturas::PagarService` (aliases: `LiquidarService`, `ConfirmarPagamentoService`, `RegistrarPagamentoService`, `Assinaturas::PagarFaturaService`) | SaaS Recorrente / Faturas | ✅ Concluído |
| `AssinaturaFaturas::CancelarService` (aliases: `AnularService`, `EstornarService`, `Assinaturas::CancelarFaturaService`) | SaaS Recorrente / Faturas | ✅ Concluído |
| `Assinaturas::ProcessarInadimplentesService` (aliases: `ProcessarInadimplenciaService`, `VerificarInadimplentesService`, `AssinaturaFaturas::ProcessarInadimplentesService`) | SaaS Recorrente | ✅ Concluído |

---

## 8. Marcos Históricos

Esta seção deve ser atualizada conforme o desenvolvimento avançar.

## Marco 01 — Estrutura Inicial

**Data:** 2026-09-20

Foi definida a classificação das tabelas do ERP em dois grandes níveis:

- Tabelas simples, responsáveis por cadastros e estruturas de apoio.
- Tabelas complexas, responsáveis por transações, concorrência, auditoria e orquestração.

Também foi definida uma esteira de implementação em cinco fases.

---

## Marco 02 — Estoque

**Status:** ✅ Concluído

Implementado o fluxo central de movimentação de estoque através de:

```ruby
Estoques::MovimentarService
```

O estoque passou a ser tratado como uma operação transacional crítica, considerando:

- Concorrência.
- Lock pessimista.
- Proteção contra quantidade negativa.
- Registro de movimentações.
- Rastreabilidade da origem.
- Saldo anterior e posterior.

---

## Marco 03 — Cupons

**Status:** ✅ Concluído

**Data:** 2026-09-21

Implementado o ecossistema completo de cupons promocionais através de:

```ruby
Cupons::AplicarService
Cupons::SalvarService (alias: Cupons::CadastrarService)
Cupons::InativarService
```

Principais responsabilidades consolidadas:

- Criação e atualização de cupons com validação de duplicidade por tenant e normalização automática de códigos (`SalvarService`).
- Coerência de datas de vigência (`valido_de <= valido_ate`) e proteção contra redução do teto de utilizações abaixo do histórico já consumido (`limite_usos >= usos_contagem`).
- Inativação lógica com suporte a idempotência e registro de motivo (`InativarService`).
- Suporte prévio à venda com cálculo de desconto percentual ou fixo e lock pessimista para consumo concorrente (`AplicarService`).
- Isolamento multi-tenant estrito em todos os serviços (`unauthorized_tenant`).

---

## Marco 04 — Clientes e Endereços

**Status:** ✅ Concluído

**Data:** 2026-09-21

Implementados os serviços de gerenciamento, cadastro, resolução de endereço e ciclo de vida de clientes:

```ruby
Clientes::SalvarService (alias: Clientes::CadastrarService)
Clientes::ResolverEnderecoService (alias: Clientes::ResolverEnderecoEntregaService)
Clientes::InativarService
```

Principais responsabilidades consolidadas:

- Isolamento multi-tenant rigoroso (`:tenant_not_found`, `:unauthorized_tenant`, `:client_not_found`).
- Validação e garantia de unicidade de `documento` por tenant (`:document_already_exists`), com suporte opcional a `upsert_por_documento: true`.
- Criação e atualização aninhada de endereço (`endereco`), com sanitização de CEP e validações completas de endereço.
- Gestão atômica de endereço padrão (`padrao: true`), alternando o padrão anterior de forma transacional para evitar conflitos de unicidade com o índice único parcial.
- Definição automática de endereço como padrão caso seja o primeiro endereço vinculado ao cliente.
- Rollback transacional completo caso os dados de endereço contenham erros de validação (`:record_invalid`).
- Validação semântica e prévia de permissões e existência de endereços (`:unauthorized_address`, `:address_not_found`, `:invalid_address_operation`).
- Associação `has_one :endereco_padrao` exposta diretamente no model `Cliente`.
- Resolução e validação inteligente de endereço de entrega (`Clientes::ResolverEnderecoService`), selecionando o endereço padrão ou mais recente caso omitido.
- Suporte a `tipo_entrega` (retirada, motoboy, correios), não obrigando endereço para retiradas e exigindo para envios.
- Geração de snapshot imutável em JSONB (`vendas.endereco_entrega`) com destinatário, telefone de contato, detalhes de logradouro e texto formatado.
- Inativação segura e preservação do histórico transacional (`Clientes::InativarService`), suportando revogação de marketing (`desativar_marketing: true`), controle de pedidos em aberto (`:client_has_pending_sales`) e idempotência (`ignorar_se_inativo: true`).

---

## Marco 05 — Categorias de Produtos

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do ciclo de vida de `ProdutoCategoria` através de Service Objects dedicados.
- Tratamento inteligente de slugs (geração automática a partir do nome via `.parameterize` e sanitização de formatos customizados).
- Isolamento multi-tenant estrito com checagem de tenant (`:tenant_not_found`, `:unauthorized_tenant`, `:category_not_found`).
- Validação e prevenção de duplicidade de `slug` dentro da mesma empresa (`:slug_already_exists`), permitindo slugs idênticos em empresas distintas.
- Inativação lógica e segura de categorias (`ativo: false`), com suporte a idempotência (`ignorar_se_inativo: true`), bloqueio por produtos ativos vinculados (`:category_has_active_products`) e opção de desvinculação em lote (`desvincular_produtos: true`).
- Exclusão física controlada (`ProdutoCategorias::ExcluirService`) com proteção contra exclusão com produtos órfãos (`:category_has_associated_products`) e desvinculação em lote segura.
- Cobertura de 100% dos cenários em 38 exemplos de testes com RSpec.

### Service Objects criados

```ruby
ProdutoCategorias::SalvarService (alias: ProdutoCategorias::CadastrarService)
ProdutoCategorias::InativarService
ProdutoCategorias::ExcluirService
```

### Tabelas envolvidas

- `produto_categorias`
- `produtos`
- `empresas`

### Decisões arquiteturais

- **Geração e Sanitização de Slugs:** O service gera o slug automaticamente a partir do nome caso omitido ou vazio, e sanitiza qualquer entrada manual garantindo conformidade com a expressão regular `/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/`.
- **Integridade com Produtos Vinculados:** O modelo possui `dependent: :nullify`, porém os services implementam salvaguardas explícitas para impedir inativação ou exclusão acidental de categorias com produtos ativos, exigindo parametrização explícita (`desvincular_produtos: true` ou `permitir_com_produtos_ativos: true`).
- **Idempotência:** A inativação segue o padrão de tolerar requisições repetidas sem erro quando `ignorar_se_inativo: true`.

---

## Marco 06 — Custos Operacionais e Financeiros

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do ciclo de vida de `Custo` através de Service Objects dedicados.
- Isolamento multi-tenant estrito com checagem de tenant tanto para a empresa do custo quanto para a empresa da venda vinculada (`:tenant_not_found`, `:unauthorized_tenant`, `:cost_not_found`, `:sale_not_found`).
- Validação no model `Custo` (`venda_mesma_empresa`) garantindo integridade referencial cruzada em banco e aplicação.
- Associação flexível com `Venda` (por instância, ID numérico ou `codigo_pedido` alfanumérico), com suporte a dissociação explícita (`venda: nil`) ou preservação em atualizações parciais.
- Normalização inteligente de dados: conversão de categorias (`insumos_producao`, `frete_entrega`, `trafego_pago`, `operacional_geral`, `embalagem`) a partir de símbolos, strings ou inteiros do enum; normalização de valores monetários no padrão brasileiro (e.g. `'1.250,75'`); e preenchimento automático de `data_custo` com `Date.current` quando omitida no cadastro.
- Exclusão física controlada com salvaguarda de vendas vinculadas (`Custos::ExcluirService`): bloqueio preventivo padrão (`:cost_has_associated_sale` com metadados do `codigo_pedido` e `venda_id`), opção de exclusão física consciente (`forcar: true`) e opção de desvinculação (`desvincular_venda: true`), mantendo o custo como despesa geral sem deletar o registro.
- Registro em lote (`Custos::SalvarEmLoteService`), ideal para integração com fechamento de vendas (`FecharVendaService`) ou lançamentos avulsos em massa, com garantia de atomicidade total (rollback de todos os itens se qualquer lançamento falhar).
- Implementação de escopos úteis no model `Custo` (`por_categoria`, `por_periodo`, `sem_venda`, `com_venda`, `recentes`).
- Cobertura de 100% com 65 novos testes no RSpec (11 no model e 54 nos services), totalizando 398 testes sem falhas na suíte completa.

### Service Objects criados

```ruby
Custos::SalvarService (aliases: Custos::CadastrarService, Custos::CriarService)
Custos::ExcluirService (aliases: Custos::RemoverService, Custos::DeletarService)
Custos::SalvarEmLoteService (aliases: Custos::CadastrarLoteService, Custos::RegistrarLoteService)
```

### Tabelas envolvidas

- `custos`
- `empresas`
- `vendas`

### Decisões arquiteturais

- **Sem inativação lógica:** Diferente de clientes e categorias, custos representam registros contábeis/financeiros avulsos. Logo, a tabela `custos` não possui coluna `ativo`, operando com persistência, edição e exclusão controlada.
- **Salvaguarda de Venda Vinculada:** Deletar um custo associado a uma venda altera a margem de contribuição do pedido. Por isso, a exclusão direta é bloqueada (`:cost_has_associated_sale`), exigindo confirmação explícita (`forcar: true`) ou permitindo a conversão para despesa geral desvinculada (`desvincular_venda: true`).
- **Atomicidade em Lote:** `SalvarEmLoteService` roda dentro de uma transação única. Em caso de falha em qualquer lançamento, todas as inserções anteriores sofrem rollback e o erro detalhado com o índice do item é retornado.
- **Proteção Cross-Tenant na Venda:** Valida explicitamente que um custo nunca aponte para uma venda de outro tenant, tanto na camada de Service quanto na validação de modelo `validate :venda_mesma_empresa`.

---

## Marco 07 — Planos SaaS

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do Service Object dedicado `Planos::SalvarService` para criação, atualização e gerenciamento de status/atributos de `Plano`.
- Resolução polimórfica e inteligente do plano por instância do ActiveRecord, `id` numérico ou `identificador` do enum (`:start`, `'pro'`, `1`, etc.).
- Normalização de atributos monetários no formato brasileiro (e.g. `'1.250,75'`), normalização de enums e suporte explícito a planos ilimitados (`nil` para `limite_produtos` e `limite_usuarios`).
- Controle de ativação/inativação diretamente pelos atributos do plano (`ativo: true/false`).
- Prevenção e validação de unicidade de `identificador` (`:identifier_already_exists`), com detecção precisa em cadastros e atualizações.
- Adição de escopos (`.ativos`, `.inativos`, `.ordenados_por_valor`) e métodos utilitários (`#ilimitado_produtos?`, `#ilimitado_usuarios?`, `#possui_assinaturas?`, `#possui_assinaturas_ativas?`) no model `Plano`.
- Cobertura de 100% no RSpec com 27 exemplos de testes (14 no model e 13 no service), mantendo a suíte completa com 421 exemplos sem falhas.

### Service Object criado

```ruby
Planos::SalvarService (aliases: Planos::CadastrarService, Planos::CriarService, Planos::AtualizarService)
```

### Tabelas envolvidas

- `planos`
- `assinaturas`

### Decisões arquiteturais

- **Entidade Global SaaS (Sem Tenant):** Ao contrário dos cadastros operacionais do ERP, os planos pertencem ao núcleo SaaS da plataforma e são globais. Por isso, o service de planos não requer parâmetro de `empresa`.
- **Centralização no SalvarService:** A persistência, atualização de valores/limites e alternância do status ativo/inativo são orquestradas pelo `SalvarService`, mantendo uma interface enxuta e unificada.

---

## Marco 08 — Empresas (Fundação Multi-tenant)

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do Service Object central `Empresas::SalvarService` (com aliases `CadastrarService`, `CriarService` e `AtualizarService`) para criação, edição, ativação/inativação e manutenção do tenant raiz da plataforma.
- Resolução polimórfica da empresa por instância de `Empresa`, `id` numérico, string numérica ou `slug`.
- Geração automática inteligente de `slug` a partir do `nome` via `parameterize` em novos cadastros quando omitido, incluindo **desambiguação automática incremental** (`alpha-store`, `alpha-store-2`, `alpha-store-3`) permitindo o cadastro transparente de múltiplas empresas com o mesmo nome e documentos distintos.
- Sanitização de slugs customizados para adequação estrita ao formato aceito pelo subdomínio (`[a-z0-9]+(?:-[a-z0-9]+)*`).
- Normalização de e-mails (`strip` e `downcase`), sanitização de documentos fiscais (`documento`, removendo pontuações e mantendo apenas números) e conversão flexível de booleanos (`ativo`).
- Prevenção rigorosa e tratamento amigável de duplicidade de `slug` (`:slug_already_exists`), diferenciando tentativas de colisão entre empresas distintas e preservando o slug na edição da própria empresa.
- Validação semântica de unicidade de documento fiscal (`validar_documento_duplicado`), retornando `:document_already_exists` caso o documento já pertença a outra empresa, permitindo múltiplos cadastros com documento em branco/nulo e preservando o documento na atualização da mesma empresa.
- Implementação do Service Object `Empresas::InativarService` (alias: `Empresas::DesativarService`) para desativação segura do tenant, suporte a motivo textual de bloqueio/cancelamento, controle de idempotência (`ignorar_se_inativo`) e opções para suspensão (`suspender_assinaturas: true`) ou cancelamento (`cancelar_assinaturas: true`) de assinaturas SaaS vinculadas.
- Adição de scopes (`.ativas`, `.inativas`) e callbacks de sanitização (`sanitizar_dados`) no model `Empresa`.
- Cobertura de 100% de testes no RSpec com 47 exemplos cobrindo o model (8), o salvar service (26) e o inativar service (13).

### Service Objects criados

```ruby
Empresas::SalvarService (aliases: Empresas::CadastrarService, Empresas::CriarService, Empresas::AtualizarService)
Empresas::InativarService (alias: Empresas::DesativarService)
```

### Tabelas envolvidas

- `empresas`
- `assinaturas`

### Decisões arquiteturais

- **Tenant Raiz Multi-tenant:** Como a `Empresa` é a entidade proprietária de todos os dados do tenant no ERP, seu service não recebe parâmetro de tenant externo. Na atualização ou inativação, aceita o parâmetro `empresa` por instância, ID ou slug.
- **Desambiguação Automática de Slugs em Empresas Homônimas:** Quando duas empresas possuem o mesmo nome e não informam slug explicitamente, o service adiciona sufixos incrementais (`-2`, `-3`), viabilizando a coexistência de empresas com o mesmo nome fantasia/razão social e documentos fiscais diferentes.
- **Preservação de Slug na Atualização:** Ao atualizar o nome de uma empresa sem explicitar alteração de slug, o slug original é preservado para evitar quebras em subdomínios, links e integrações existentes.
- **Tratamento de Conflito de Slug e Documento:** Colisões com slugs (`:slug_already_exists`) informados explicitamente e documentos fiscais (`:document_already_exists`) já cadastrados retornam erro negocial limpo antes de atingir ou sobrecarregar a camada de banco de dados.
- **Inativação e Gestão de Assinaturas:** O processo de inativação protege contra execuções redundantes (`:empresa_already_inactive`) e permite opcionalmente cascatear a suspensão ou cancelamento do ciclo de vida das assinaturas da empresa.


---

## Marco 09 — Usuários (Gestão de Identidade e Acesso)

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do Service Object central `Usuarios::SalvarService` (com aliases `CadastrarService`, `CriarService` e `AtualizarService`) para cadastro e atualização de operadores, atendentes e proprietários.
- Resolução polimórfica do usuário por instância de `Usuario`, `id` numérico, string numérica ou `email`.
- Normalização de atributos: limpeza de espaços em `nome`, sanitização e conversão de `email` para minúsculas, extração estrita de dígitos em `telefone` (convertendo valores vazios em `nil`) e coerção de booleanos em `ativo`.
- Prevenção semântica de duplicação de e-mail (`:email_already_exists`), diferenciando tentativas de colisão entre contas distintas e permitindo a preservação do e-mail ao atualizar o próprio usuário.
- Tratamento de usuário não encontrado (`:usuario_not_found`) e validação prévia de integridade.
- Implementação do Service Object `Usuarios::InativarService` (com aliases `DesativarService` e `BloquearService`) para inativação segura da identidade.
- Suporte a motivo textual, controle rigoroso de idempotência (`ignorar_se_inativo` / `:usuario_already_inactive`) e desativação opcional em cascata dos vínculos de membro ativos nas empresas (`desativar_membros: true`).
- Adição de scopes (`.ativos`, `.inativos`) e callback de sanitização (`sanitizar_dados`) no model `Usuario`.
- Cobertura de 100% de testes no RSpec com 40 exemplos cobrindo o model (9), o salvar service (18) e o inativar service (13), elevando a suíte do projeto para 497 testes sem falhas.

### Service Objects criados

```ruby
Usuarios::SalvarService (aliases: Usuarios::CadastrarService, Usuarios::CriarService, Usuarios::AtualizarService)
Usuarios::InativarService (aliases: Usuarios::DesativarService, Usuarios::BloquearService)
```

### Tabelas envolvidas

- `usuarios`
- `membros`

### Decisões arquiteturais

- **Identidade Global:** Usuários são entidades globais de autenticação e identificação que participam das empresas via relação com `membros`. Assim, a unicidade do e-mail é avaliada em escopo global.
- **Resolução Polimórfica Amigável:** Tanto no salvamento quanto na inativação, o usuário pode ser referenciado diretamente por instância, ID ou e-mail, facilitando chamadas a partir de controladores, jobs ou consoles.
- **Desativação em Cascata de Membros:** O `InativarService` disponibiliza o parâmetro `desativar_membros: true` para revogar imediatamente o acesso operacional do usuário em todas as empresas em que atua.

---

## Marco 10 — Membros (Gestão de Equipe e Papéis)

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Implementação do Service Object central `Membros::SalvarService` (com aliases `CadastrarService`, `CriarService` e `AtualizarService`) para vinculação de operadores a tenants e gestão de papéis (`atendente`, `estoquista`, `gerente`, `proprietario`).
- Resolução polimórfica completa:
  - `empresa` por instância, ID numérico ou `slug`.
  - `usuario` e `convidado_por` por instância, ID numérico ou `email`.
  - `membro` por instância ou ID numérico.
- Validações de domínio robustas:
  - Verificação de tenant existente (`:tenant_not_found`).
  - Verificação de usuário existente (`:usuario_not_found`).
  - Verificação de usuário que convidou (`:convidado_por_not_found`).
  - Validação estrita de papéis válidos (`:invalid_role`).
  - Prevenção de duplicidade de vínculo do mesmo usuário na mesma empresa (`:member_already_exists`).
  - Verificação de autorização multi-tenant impedindo atualização cruzada de membros de outras empresas (`:unauthorized_tenant`).
- **Regra de Proteção do Último Proprietário Ativo:**
  - Bloqueio de alteração de papel (`:last_owner_cannot_change_role`) se for o único proprietário ativo da empresa.
  - Bloqueio de inativação via atributos (`:last_owner_cannot_be_inactivated`) se for o único proprietário ativo da empresa.
- Implementação do Service Object `Membros::InativarService` (com aliases `DesativarService` e `RemoverService`) para desativação segura do operador na empresa.
- Suporte a resolução do membro por instância, ID, objeto `Usuario` ou e-mail vinculado.
- Suporte a motivo textual e controle rigoroso de idempotência (`ignorar_se_inativo` / `:member_already_inactive`).
- Proteção contra inativação do último proprietário ativo no `InativarService` (`:last_owner_cannot_be_inactivated`).
- Enriquecimento do model `Membro` com scopes de status (`.ativos`, `.inativos`) e por papéis (`.proprietarios`, `.gerentes`, `.atendentes`, `.estoquistas`).
- Cobertura de 100% de testes no RSpec com 44 exemplos cobrindo o model (9), o salvar service (21) e o inativar service (14), elevando a suíte total do ERP para 534 testes sem falhas.

### Service Objects criados

```ruby
Membros::SalvarService (aliases: Membros::CadastrarService, Membros::CriarService, Membros::AtualizarService)
Membros::InativarService (aliases: Membros::DesativarService, Membros::RemoverService)
```

### Tabelas envolvidas

- `membros`
- `empresas`
- `usuarios`

### Decisões arquiteturais

- **Associação Multi-tenant com Papéis:** O vínculo entre a identidade (`Usuario`) e o tenant (`Empresa`) é concentrado em `Membro`, permitindo que um mesmo usuário opere com diferentes níveis de permissão em empresas distintas.
- **Proteção do Último Proprietário:** Garantia de integridade para que nenhum tenant se torne órfão de governança, impedindo o rebaixamento de papel ou a inativação do último proprietário ativo.
- **Flexibilidade de Entrada:** Suporte transparente a argumentos posicionais ou nomeados (`kwargs`), viabilizando chamadas concisas a partir de controladores Rails, APIs e tarefas agendadas.

---

## Marco 11 — Assinaturas (SaaS Recorrente)

**Status:** ✅ Concluído

**Data:** 2026-09-21

### O que foi feito

- Análise arquitetural e decisão sobre a suficiência do `SalvarService`: verificado que **apenas o `SalvarService` não é suficiente**, dada a máquina de estados complexa de `Assinatura` (`pendente`, `ativa`, `atrasada`, `suspensa`, `cancelada`), auditoria de timestamp (`data_cancelamento`) e efeitos de offboarding (como cancelamento de faturas pendentes).
- Implementação de `Assinaturas::SalvarService` (com aliases `CadastrarService`, `CriarService`, `AtualizarService` e `ContratarService`) para contratação, atualização e upgrade/downgrade de planos.
- Implementação de cálculo automático inteligente de `valor` e datas de vigência (`data_fim`) conforme o plano e o ciclo selecionado (`mensal: x1 / +1 mês`, `trimestral: x3 / +3 meses`, `anual: x12 / +1 ano`).
- Resolução polimórfica flexível:
  - `empresa` por instância, ID numérico ou `slug`.
  - `plano` por instância, ID numérico ou `identificador` do enum (`:start`, `:pro`, `:enterprise`).
  - `assinatura` por instância ou ID numérico.
- Validação e prevenção de conflitos com a regra de assinatura ativa única por empresa (`index_assinaturas_on_empresa_ativa`), com suporte a substituição atômica de plano (`substituir_atual: true` ou `cancelar_anterior: true`).
- Geração opcional da fatura inicial associada (`gerar_fatura_inicial: true`).
- Implementação de `Assinaturas::CancelarService` (com aliases `EncerrarService` e `DesativarService`) para encerramento de assinaturas.
- Resolução da assinatura por instância, ID ou diretamente a partir do tenant (`empresa`), cancelando sua assinatura ativa.
- Preenchimento do timestamp de auditoria `data_cancelamento: Time.current` e liberação da constraint de assinatura ativa.
- Cancelamento em cascata de faturas pendentes em aberto (`cancelar_faturas_pendentes: true`), prevenindo cobranças indevidas de clientes cancelados.
- Tratamento de idempotência com `ignorar_se_cancelada: true` e bloqueio com `:subscription_already_cancelled`.
- Enriquecimento dos models:
  - `Assinatura`: scopes (`.ativas`, `.canceladas`, `.suspensas`, `.pendentes`, `.atrasadas`, `.vigentes`, `.recentes`) e métodos (`#vigente?`, `#dias_restantes`).
  - `Empresa`: associação direta `has_one :assinatura_ativa` e método utilitário `#possui_assinatura_ativa?`.
- Cobertura de 100% de testes no RSpec com 53 exemplos cobrindo o model `Assinatura` (15), `SalvarService` (26) e `CancelarService` (13), elevando a suíte completa da aplicação para 582 testes sem nenhuma falha.

### Service Objects criados

```ruby
Assinaturas::SalvarService (aliases: Assinaturas::CadastrarService, Assinaturas::CriarService, Assinaturas::AtualizarService, Assinaturas::ContratarService)
Assinaturas::CancelarService (aliases: Assinaturas::EncerrarService, Assinaturas::DesativarService)
```

### Tabelas envolvidas

- `assinaturas`
- `assinatura_faturas`
- `planos`
- `empresas`

### Decisões arquiteturais

- **Cancelamento como Evento de Domínio de Primeira Classe:** Em vez de tratar cancelamento como um simples `update(status: 4)`, `CancelarService` orquestra a auditoria temporal (`data_cancelamento`), idempotência e cancelamento de cobranças em aberto (`cancelar_faturas_pendentes`), espelhando a mesma robustez de `InativarService` dos outros módulos.
- **Troca Atômica de Plano:** Upgrades e downgrades podem ser executados transparentemente via `SalvarService` com `substituir_atual: true`, cancelando a assinatura anterior e persistindo a nova na mesma transação de banco.
- **Cálculo de Ciclos Automático:** Ao omitir o valor ou a data de vencimento na contratação, o serviço projeta os multiplicadores e períodos corretos com base no `valor_mensal` do plano e no ciclo contratado.

---

## Marco 12 — Produtos (Catálogo de Produtos)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Implementação do Service Object central `Produtos::SalvarService` (com aliases `CadastrarService`, `CriarService` e `AtualizarService`) para criação e manutenção de produtos no catálogo do tenant.
- Resolução polimórfica flexível:
  - `empresa` por instância de `Empresa`, `id` numérico ou `slug`.
  - `produto` por instância de `Produto` ou `id` numérico.
  - `categoria` / `produto_categoria` por instância de `ProdutoCategoria`, `id` numérico ou `slug` da categoria.
- Resolução automática de tenant (`empresa`) a partir do próprio produto na edição quando a empresa for omitida.
- Normalização e sanitização automática de atributos (`nome` e `descricao` com trim, conversão de booleano em `ativo` com padrão `true` para novos registros).
- Suporte a vinculação e desvinculação de categoria (`categoria: nil` ou `produto_categoria_id: nil`).
- Validação e isolamento multi-tenant estrito:
  - Verificação de tenant existente (`:tenant_not_found`).
  - Verificação de produto existente (`:product_not_found`).
  - Prevenção de invasão multi-tenant para produto pertencente a outra empresa (`:unauthorized_tenant`).
  - Prevenção de associação com categoria pertencente a outra empresa (`:unauthorized_tenant`).
  - Tratamento de categoria inexistente (`:category_not_found`).
  - Proteção contra vinculação de categoria inativa (`:category_inactive`), com opção de liberação consciente (`permitir_categoria_inativa: true`).
- **Validação de Limites de Produtos do Plano SaaS:**
  - Verificação de limites contratados pelo plano da empresa na assinatura ativa (`:plan_product_limit_reached`).
  - Suporte a planos ilimitados (`limite_produtos: nil`).
  - Parâmetro para ignorar limites quando necessário (`ignorar_limite: true`).
  - Não bloqueia atualização de produtos existentes quando a empresa já atingiu o limite.
- **Suporte a Variações Opcionais no mesmo Salvamento:**
  - Capacidade de criar produto com uma ou múltiplas variações (`variacao: {...}` ou `variacoes: [...]`) atomicamente dentro da mesma transação de banco.
  - Rollback transacional completo caso alguma variação falhe nas validações (`:record_invalid`).
- **Inativação Lógica e Segura de Produtos:**
  - Implementação de `Produtos::InativarService` (com alias `Produtos::DesativarService`) para inativação de produtos no tenant.
  - Suporte a motivo textual (`motivo`) e controle rigoroso de idempotência (`ignorar_se_inativo: true` / `:product_already_inactive`).
  - **Inativação em Cascata de Variações:** por padrão (`inativar_variacoes: true`), inativa todas as variações ativas vinculadas ao produto de forma transacional, retornando o total de variações inativadas, com opção de desativar esse comportamento (`inativar_variacoes: false`).
- **Reativação Controlada de Produtos:**
  - Implementação de `Produtos::ReativarService` (com alias `Produtos::AtivarService`) para restaurar produtos inativos no catálogo.
  - Controle de idempotência (`ignorar_se_ativo: true` / `:product_already_active`).
  - **Validação de Categoria Inativa:** bloqueia a reativação de produtos vinculados a categorias inativas (`:category_inactive`), com opção de liberação explícita (`permitir_categoria_inativa: true`) ou desvinculação automática (`desvincular_categoria_inativa: true`).
  - **Validação de Limites de Plano na Reativação:** impede reativação caso a cota de produtos ativos do plano SaaS já tenha sido atingida (`:plan_product_limit_reached`), com suporte a `ignorar_limite: true`.
  - **Reativação Opcional de Variações:** permite reativar as variações inativas do produto em cascata (`reativar_variacoes: true`), mantendo-as inalteradas por padrão.
- Cobertura de 100% de testes no RSpec com 77 exemplos cobrindo o catálogo de produtos (`spec/services/produtos/salvar_service_spec.rb` com 39 exemplos, `spec/services/produtos/inativar_service_spec.rb` com 16 exemplos e `spec/services/produtos/reativar_service_spec.rb` com 22 exemplos), elevando a suíte total da aplicação para 659 testes sem nenhuma falha.

### Service Objects criados

```ruby
Produtos::SalvarService (aliases: Produtos::CadastrarService, Produtos::CriarService, Produtos::AtualizarService)
Produtos::InativarService (alias: Produtos::DesativarService)
Produtos::ReativarService (alias: Produtos::AtivarService)
```

### Tabelas envolvidas

- `produtos`
- `produto_categorias`
- `empresas`
- `variacoes_produtos`
- `assinaturas`
- `planos`

### Decisões arquiteturais

- **Associação com Categoria Flexível e Segura:** Suporta instâncias, IDs e slugs da categoria, impedindo associações entre tenants distintos e bloqueando por padrão categorias desativadas.
- **Respeito ao Limite de Produtos do Plano:** O serviço consulta a assinatura ativa da empresa e respeita o teto de `limite_produtos` definido no plano, integrando o catálogo às regras contratuais do SaaS no cadastro e na reativação.
- **Criação Atômica de Variações:** Permite ao cliente da API/controlador cadastrar o produto juntamente com suas variações iniciais sem necessidade de chamadas separadas, garantindo integridade transacional.
- **Inativação Consistente com Variações:** Ao desativar um produto pai, suas variações ativas são desativadas em cascata na mesma transação para evitar que SKUs continuem operacionais para vendas de um produto inativo.
- **Reativação com Salvaguardas de Domínio:** A reativação valida tanto a coerência com a taxonomia (categorias inativas) quanto o teto de produtos ativos da assinatura do tenant antes de persistir a alteração.

---

## Marco 13 — Convites (Gestão de Acesso e Convites de Equipe)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Implementação do ecossistema completo de gestão de convites da equipe (`Convite`) para a plataforma multi-tenant.
- Implementação de `Convites::SalvarService` (com aliases `CadastrarService`, `CriarService` e `EnviarService`) para criação e renovação de convites para membros da equipe (`atendente`, `estoquista`, `gerente`, `proprietario`).
- Resolução polimórfica flexível:
  - `empresa` por instância de `Empresa`, `id` numérico ou `slug`.
  - `convidado_por` por instância de `Usuario`, `id` numérico ou `email`.
  - `convite` por instância de `Convite`, `id` numérico ou `token`.
- Validações de integridade e isolamento multi-tenant:
  - Verificação de tenant existente (`:tenant_not_found`).
  - Verificação de usuário que convida (`:convidado_por_not_found`).
  - Exigência de que o usuário emissor seja membro ativo da empresa (`:unauthorized_inviter`).
  - Validação estrita de papéis válidos (`:invalid_role`).
  - Validação de presença e formato do e-mail com sanitização automática (`:invalid_email`).
  - Bloqueio se o destinatário já for membro ativo da empresa (`:member_already_exists`).
  - Prevenção de duplicidade de convites pendentes para o mesmo e-mail na empresa (`:invite_already_pending`).
  - Validação de limite de usuários do plano SaaS da assinatura ativa (`:plan_user_limit_reached`), com suporte a `ignorar_limite: true`.
- **Reenvio e Renovação Inteligente de Convites:**
  - Suporte a reenvio explícito (`reenviar: true` ou `renovar: true`), regenerando token único com `has_secure_token`, redefinindo data de expiração e atualizando o papel.
  - Renovação automática transparente de convites expirados anteriores, respeitando o índice parcial de unicidade do banco (`index_convites_on_empresa_and_email_pendente`).
- Implementação de `Convites::AceitarService` para aceite do convite:
  - Resolução por `token`, `id` ou objeto `Convite`.
  - Validações de convite existente (`:invite_not_found`), isolamento multi-tenant (`:unauthorized_tenant`), convite já aceito (`:invite_already_accepted`) e convite expirado (`:invite_expired`).
  - Resolução automática do usuário a partir do e-mail do convite caso omitido.
  - Validação opcional de correspondência estrita de e-mail (`validar_email: true` / `:email_mismatch`).
  - Revalidação do limite de usuários ativos do plano SaaS no momento do aceite (`:plan_user_limit_reached`).
  - Criação atômica de `Membro` na empresa (`data_entrada: Time.current`, `ativo: true`) e registro do timestamp de aceite (`aceito_em: Time.current`).
  - Suporte a reativação transparente caso o usuário já possua registro anterior inativo de membro na empresa.
- Implementação de `Convites::CancelarService` (com aliases `RevogarService` e `ExcluirService`):
  - **Soft delete inteligente:** cancelamento lógico via timestamp `cancelado_em: Time.current` (com alias `deleted_at`), preservando histórico de convites enviados para auditoria.
  - Suporte a idempotência (`ignorar_se_cancelado: true`) e bloqueio amigável (`:invite_already_cancelled`).
  - Suporte a data de cancelamento customizada (`data_cancelamento`) e motivo textual (`motivo`).
  - Bloqueio preventivo contra cancelamento de convites já aceitos (`:invite_already_accepted`).
  - Bloqueio de aceite em `AceitarService` caso o convite esteja cancelado (`:invite_cancelled`).
  - Liberação transparente para novos convites ao mesmo e-mail após cancelamento, respeitando o índice parcial de unicidade `index_convites_on_empresa_and_email_pendente`.
- Enriquecimento do model `Convite`:
  - Callback de sanitização `sanitizar_dados` (`strip` e `downcase` de e-mail).
  - Coluna e alias `alias_attribute :deleted_at, :cancelado_em`.
  - Escopos: `.pendentes`, `.aceitos`, `.expirados`, `.cancelados`, `.nao_cancelados`, `.por_papel`.
  - Métodos utilitários: `#aceito?`, `#cancelado?`.
- Migration `AddCanceladoEmToConvites` adicionando coluna `cancelado_em`, índice dedicado e reestruturando o índice parcial de unicidade para `WHERE aceito_em IS NULL AND cancelado_em IS NULL`.
- Cobertura de 100% de testes no RSpec com 70 testes cobrindo o model (16) e os services (24 no salvar, 15 no aceitar, 15 no cancelar), elevando a suíte total do ERP para 721 testes sem nenhuma falha.

### Service Objects criados

```ruby
Convites::SalvarService (aliases: Convites::CadastrarService, Convites::CriarService, Convites::EnviarService)
Convites::AceitarService
Convites::CancelarService (aliases: Convites::RevogarService, Convites::ExcluirService)
```

### Tabelas envolvidas

- `convites`
- `empresas`
- `usuarios`
- `membros`
- `assinaturas`
- `planos`

### Decisões arquiteturais

- **Soft Delete e Preservação de Histórico de Convites:** Em vez de remover fisicamente o registro do banco com `destroy`, o convite cancelado é preservado com `cancelado_em` (`deleted_at`), permitindo auditoria de tentativas de convite e quem efetuou a revogação.
- **Respeito ao Índice Único Parcial:** A tabela `convites` restringe duplicidade através do índice `[empresa_id, email] WHERE aceito_em IS NULL AND cancelado_em IS NULL`. Isso permite que novos convites sejam emitidos para o mesmo e-mail caso o anterior tenha sido cancelado ou aceito.
- **Aceite Atômico e Idempotente de Membros:** O `AceitarService` opera dentro de transação única: se o usuário já fez parte da empresa no passado com registro inativo, o registro é reativado com os novos dados do convite, prevenindo colisão com o índice único `[empresa_id, usuario_id]`.
- **Salvaguarda de Limites de Usuários do SaaS:** A criação e o aceite de convites verificam o teto `limite_usuarios` da assinatura ativa da empresa, garantindo conformidade contratual com o plano contratado.

---

## Marco 14 — Vendas (Núcleo Transacional de Pedidos)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Implementação do núcleo transacional principal da **Fase 4 do ERP** através de `Vendas::FecharVendaService` (com aliases `SalvarService`, `CriarService` e `FecharService`) e `Vendas::CancelarVendaService` (com aliases `CancelarService` e `EstornarService`).
- **Orquestração e Fechamento de Vendas (`FecharVendaService`):**
  - Isolamento multi-tenant estrito para todas as entidades relacionadas (`empresa`, `cliente`, `usuario`, `variacao_produto`, `cupom`).
  - Resolução polimórfica flexível de empresa (instância, ID ou slug), cliente (instância ou ID) e usuário operador (instância, ID ou e-mail, exigindo membro ativo da empresa).
  - Composição de itens de venda com snapshot imutável em JSONB (`detalhes_produto`), gravando nome do produto, SKU, tamanho, cor, código de barras e preços de tabela vigentes no fechamento.
  - Resolução inteligente de entrega (`Clientes::ResolverEnderecoService`): suporte a entrega presencial (`retirada`) e frete com endereço congelado em snapshot JSONB (`endereco_entrega`).
  - Aplicação atômica e consumo de cupons de desconto (`Cupons::AplicarService` com `consumir: true`), calculando descontos percentuais ou fixos e garantindo que o desconto não exceda o subtotal dos produtos (`:discount_exceeds_subtotal`).
  - Suporte a `desconto_manual` cumulativo e cálculo preciso de frete e totalizadores.
  - Baixa física transacional e concorrente de estoque via `Estoques::MovimentarService` com tipo `saida_venda`, revertendo toda a venda em caso de saldo insuficiente de estoque (`:insufficient_stock`).
  - Suporte a pagamentos opcionais acoplados (`VendaPagamento`), marcando a venda automaticamente como `paga` quando o pagamento for aprovado.
- **Cancelamento e Reversão Transacional (`CancelarVendaService`):**
  - Validação de integridade: bloqueio para vendas já canceladas (`:sale_already_cancelled`) com suporte a idempotência (`ignorar_se_cancelada: true`), exigência de motivo textual de cancelamento (`motivo_cancelamento`) e auditoria de cancelador (`cancelado_por`) e data (`cancelado_em`).
  - Estorno automático de estoque: reintegração dos itens ao estoque das respectivas variações através de `Estoques::MovimentarService` com tipo `estorno_devolucao`.
  - Estorno de cupom promocional: decremento atômico de `usos_contagem` com lock pessimista no cupom utilizado.
- Cobertura de 100% de testes no RSpec com 33 novos exemplos dedicados (`spec/services/vendas/fechar_venda_service_spec.rb` com 23 exemplos e `spec/services/vendas/cancelar_venda_service_spec.rb` com 10 exemplos), elevando a suíte completa da aplicação para 754 testes sem nenhuma falha.

### Service Objects criados

```ruby
Vendas::FecharVendaService (aliases: Vendas::SalvarService, Vendas::CriarService, Vendas::FecharService)
Vendas::CancelarVendaService (aliases: Vendas::CancelarService, Vendas::EstornarService)
```

### Tabelas envolvidas

- `vendas`
- `venda_itens`
- `venda_pagamentos`
- `variacoes_produtos`
- `estoques`
- `estoque_movimentacoes`
- `cupons`
- `clientes`
- `enderecos`
- `empresas`
- `usuarios`

### Decisões arquiteturais

- **Transacionalidade e Atomicidade Plena:** Todas as etapas do fechamento de venda (persistência do pedido, itens, baixa concorrente de estoque, consumo de cupom e registro de pagamento) ocorrem dentro do mesmo bloco `ActiveRecord::Base.transaction`. Qualquer inconsistência ou falta de saldo gera rollback completo, prevenindo estados corrompidos.
- **Snapshots Imutáveis em JSONB:** Para evitar inconsistências históricas caso o produto sofra alteração de preço/nome ou o cliente altere seu endereço padrão, tanto os detalhes dos produtos (`detalhes_produto`) quanto o endereço (`endereco_entrega`) são congelados como documentos JSONB no ato da venda.
- **Reversão Consistente no Cancelamento:** O cancelamento fecha o ciclo do pedido de forma auditada, devolvendo mercadorias ao inventário via `estorno_devolucao` e liberando o teto de utilização de cupom.

---

## Marco 15 — Pagamentos (Registro de Liquidação e Parcelas)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Extração e implementação do Service Object dedicado `Pagamentos::RegistrarService` (com aliases `Pagamentos::SalvarService`, `Pagamentos::CriarService` e `Vendas::RegistrarPagamentoService`) para gerenciamento do ciclo de pagamentos e liquidação de vendas.
- **Registro Flexível e Transacional de Pagamentos:**
  - Suporte a pagamentos individuais ou em lote/divididos (`pagamentos: [...]`, ex: Pix + Dinheiro, múltiplos cartões).
  - Normalização flexível de formas de pagamento (`pix`, `cartao_credito`, `cartao_debito`, `dinheiro`, `boleto`) e gateways (`manual`, `asaas`, `stripe`, `mercadopago`).
  - Cálculo automático de valor líquido (`valor - taxa_operadora`) e retenção de taxa financeira da operadora.
  - Associação automática com o saldo devedor restante caso o valor seja omitido em pagamentos individuais.
  - Liquidação temporal automática (`data_liquidacao: Time.current`) para pagamentos aprovados.
  - Armazenamento estruturado de metadados em JSONB (payloads de gateways, QR codes, chaves externas).
- **Atualização Automática do Status da Venda:**
  - Recálculo atômico do somatório dos pagamentos aprovados da venda.
  - Transição automática da venda para status `:paga` assim que a soma dos pagamentos aprovados cobrir o `valor_total`.
  - Suporte a pagamentos com status `:pendente` (ex: boleto ou Pix aguardando pagamento) e `:recusado` sem alterar indevidamente o status da venda.
- **Liquidação Automática para Vendas 100% Descontadas:**
  - Implementação da regra negocial no `FecharVendaService`: vendas criadas com `valor_total == 0` decorrente de cupom ou desconto manual (`@valor_desconto.positive?`) nascem diretamente com status `:paga`.
- **Desacoplamento em `Vendas::FecharVendaService`:**
  - O método `processar_pagamentos` em `FecharVendaService` delega a criação e liquidação para `Pagamentos::RegistrarService`, mantendo isolamento e reutilização.
- Cobertura de 100% de testes no RSpec com 17 novos exemplos dedicados (`spec/services/pagamentos/registrar_service_spec.rb`), elevando a suíte completa da aplicação para 771 testes sem nenhuma falha.

### Service Objects criados

```ruby
Pagamentos::RegistrarService (aliases: Pagamentos::SalvarService, Pagamentos::CriarService, Vendas::RegistrarPagamentoService)
```

### Tabelas envolvidas

- `venda_pagamentos`
- `vendas`
- `empresas`

### Decisões arquiteturais

- **Desacoplamento do Ciclo de Vida do Pagamento:** Separar pagamentos de vendas permite que o ERP receba conciliações tardias, retornos assíncronos de webhooks de adquirentes e quitações parciais no balcão sem depender do fluxo de fechamento da venda.
- **Transição Atômica de Status:** A verificação do saldo quitado ocorre de forma atômica no banco, garantindo que o status `:paga` reflita fielmente o total consolidado dos registros aprovados em `venda_pagamentos`.

---

## Marco 16 — Devoluções e Trocas (Conclusão da Fase 4)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Implementação do Service Object central `Devolucoes::ProcessarService` (com aliases `Devolucoes::SalvarService` e `Devolucoes::CriarService`), **concluindo com sucesso a Fase 4 do ERP** (Núcleo de Vendas e Pós-venda).
- **Orquestração e Processamento de Devoluções:**
  - Isolamento multi-tenant estrito com checagem de tenant para venda e itens.
  - Bloqueio preventivo contra registro de devolução em vendas já canceladas (`:cannot_return_cancelled_sale`).
  - Suporte aos tipos de devolução (`estorno_dinheiro: 0`, `credito_troca: 1`, `defeito_avaria: 2`).
  - Suporte a devolução total (automática quando `itens` for omitido) ou devolução parcial de itens específicos.
  - **Controle Rigoroso de Saldos Elegíveis por Item:**
    - Validação de saldo cumulativo por `venda_item`, impedindo que a quantidade devolvida exceda a quantidade comprada (`:quantity_exceeds_available`).
    - Bloqueio amigável quando todos os itens da venda já tiverem sido previamente devolvidos (`:no_items_available_for_return`).
  - **Destino Físico e Reintegração ao Estoque:**
    - Para devoluções comuns (`estorno_dinheiro`, `credito_troca`): os itens retornam ao estoque por padrão (`retornou_ao_estoque: true`) utilizando `Estoques::MovimentarService` com tipo `estorno_devolucao`.
    - Para produtos com defeito (`defeito_avaria`): por padrão `retornou_ao_estoque: false` (o item avariado não volta para venda), com possibilidade de sobrescrever caso seja reparável.
    - Rollback transacional atômico e captura de `@erro_estoque` em caso de falha física no inventário.
  - **Cálculo de Estorno Financeiro:**
    - Projeção automática proporcional com base no valor unitário de cada item ou aceitação de valor explícito validado (`valor_estornado <= venda.valor_total`).
- Cobertura de 100% de testes no RSpec com 13 novos exemplos dedicados (`spec/services/devolucoes/processar_service_spec.rb`), elevando a suíte completa da aplicação para 788 testes sem nenhuma falha.

### Service Objects criados

```ruby
Devolucoes::ProcessarService (aliases: Devolucoes::SalvarService, Devolucoes::CriarService)
```

### Tabelas envolvidas

- `devolucoes`
- `devolucao_itens`
- `vendas`
- `venda_itens`
- `variacoes_produtos`
- `estoques`
- `estoque_movimentacoes`
- `empresas`
- `usuarios`

### Decisões arquiteturais

- **Conclusão da Esteira Transacional de Vendas (Fase 4):** O ERP agora possui o ciclo completo de fechamento de pedidos (`FecharVendaService`), liquidação e parcelas (`RegistrarService`), cancelamento e estorno total (`CancelarVendaService`) e devolução física/parcial (`ProcessarService`).
- **Segregação de Destino Físico do Produto:** Itens defeituosos não são automaticamente reinseridos na prateleira física, prevenindo que produtos avariados sejam vendidos novamente.
- **Rastreabilidade Polimórfica:** As movimentações de inventário decorrentes de devolução apontam diretamente para a instância de `Devolucao` como origem auditável.

---

## Marco 17 — Faturas de Assinatura (SaaS Recorrente)

**Status:** ✅ Concluído

**Data:** 2026-09-23

### O que foi feito

- Implementação do ciclo completo de cobrança e liquidação financeira de faturas do SaaS recorrente (`AssinaturaFatura`) através de uma suíte de Service Objects dedicados:
  - `AssinaturaFaturas::GerarService` (com aliases `SalvarService`, `CriarService` e `Assinaturas::GerarFaturaService`).
  - `AssinaturaFaturas::PagarService` (com aliases `LiquidarService`, `ConfirmarPagamentoService`, `RegistrarPagamentoService` e `Assinaturas::PagarFaturaService`).
  - `AssinaturaFaturas::CancelarService` (com aliases `AnularService`, `EstornarService` e `Assinaturas::CancelarFaturaService`).
- **Geração e Faturamento Recorrente (`GerarService`):**
  - Resolução polimórfica flexível de empresa (instância, ID ou slug) e assinatura (instância, ID numérico ou obtenção automática da assinatura ativa/recente do tenant).
  - Normalização inteligente de valores monetários (suporte a strings com pontuação pt-BR, e.g. `'149,90'`) e default automático a partir do `valor` da assinatura.
  - Projeção automática inteligente da `data_vencimento`: calcula o próximo vencimento com base na última fatura emitida e ciclo da assinatura (`mensal: +1 mês`, `trimestral: +3 meses`, `anual: +1 ano`), ou a data de início da assinatura.
  - Validações de integridade e isolamento multi-tenant:
    - Verificação de assinatura existente (`:subscription_not_found`).
    - Verificação de empresa ativa (`:empresa_inactive`).
    - Verificação de tenant cruzado (`:unauthorized_tenant`).
    - Prevenção de faturas para assinaturas canceladas (`:subscription_cancelled`), com override consciente via `permitir_assinatura_cancelada: true`.
    - Garantia de unicidade de `gateway_id` antes da persistência (`:gateway_id_already_exists`).
  - Suporte a geração direta de fatura quitada (`marcar_como_paga: true` ou `status: :paga`), sincronizando atômica e automaticamente a assinatura para `:ativa` e estendendo a vigência (`data_fim`).
- **Liquidação e Baixa Financeira (`PagarService`):**
  - Resolução flexível da fatura por instância, ID ou `gateway_id` do adquirente (Asaas, Stripe, etc.).
  - Registro de data de liquidação (`data_pagamento: Time.current` por padrão ou data customizada) e mesclagem estruturada de metadados em JSONB (payloads de webhooks, identificadores de transação bancária).
  - **Reativação Automática da Assinatura:** transiciona assinaturas com status `:pendente`, `:atrasada` ou `:suspensa` diretamente para `:ativa` com `assinatura_reativada: true`.
  - **Prorrogação de Vigência Recorrente:** estende a `data_fim` da assinatura com base no ciclo contratado (`mensal: +1 mês`, `trimestral: +3 meses`, `anual: +1 ano`), acumulando a partir da vigência atual ou a partir de `Date.current` se vencida.
  - Suporte estrito a idempotência: com `ignorar_se_paga: true`, tolera chamadas duplicadas de webhooks retornando sucesso com `ja_estava_paga: true`; caso contrário, bloqueia com `:invoice_already_paid`.
  - Bloqueio de liquidação de faturas canceladas (`:invoice_cancelled`).
- **Cancelamento e Estorno de Faturas (`CancelarService`):**
  - Cancelamento seguro e auditado com gravação de timestamp `cancelado_em` e justificativa textual `motivo_cancelamento` no JSONB de metadados.
  - Bloqueio preventivo contra cancelamento indevido de faturas já quitadas (`:cannot_cancel_paid_invoice`), com liberação para casos de estorno explícito (`permitir_se_paga: true`).
  - Suporte a idempotência (`ignorar_se_cancelada: true` / `:invoice_already_cancelled`).
- **Enriquecimento do Model `AssinaturaFatura`:**
  - Associações diretas: `has_one :empresa, through: :assinatura` e `has_one :plano, through: :assinatura`.
  - Escopos: `.pendentes`, `.pagas`, `.canceladas`, `.vencidas`, `.a_vencer`, `.recentes`.
  - Método utilitário `#vencida?`.
- Cobertura de 100% de testes no RSpec com 51 novos testes dedicados (14 no model, 17 no GerarService, 15 no PagarService e 11 no CancelarService), elevando a suíte completa do ERP para 842 testes sem nenhuma falha.

### Service Objects criados

```ruby
AssinaturaFaturas::GerarService (aliases: AssinaturaFaturas::SalvarService, AssinaturaFaturas::CriarService, Assinaturas::GerarFaturaService)
AssinaturaFaturas::PagarService (aliases: AssinaturaFaturas::LiquidarService, AssinaturaFaturas::ConfirmarPagamentoService, AssinaturaFaturas::RegistrarPagamentoService, Assinaturas::PagarFaturaService)
AssinaturaFaturas::CancelarService (aliases: AssinaturaFaturas::AnularService, AssinaturaFaturas::EstornarService, Assinaturas::CancelarFaturaService)
```

### Tabelas envolvidas

- `assinatura_faturas`
- `assinaturas`
- `planos`
- `empresas`

### Decisões arquiteturais

- **Desacoplamento do Ciclo de Faturas do SaaS:** O módulo `AssinaturaFaturas` opera em sincronia com `Assinaturas`, garantindo que eventos de pagamento (e.g. webhooks de gateways de pagamento) reativem automaticamente a assinatura do tenant e calculem as novas datas de vigência (`data_fim`).
- **Prorrogação Proporcional de Ciclos:** Ao liquidar uma fatura, o serviço analisa o ciclo contratado (`mensal`, `trimestral`, `anual`) e amplia a vigência sem sobrescrever dias remanescentes não usufruídos caso a fatura seja quitada antecipadamente.
- **Idempotência para Webhooks e Mensageria:** Tanto o `PagarService` quanto o `CancelarService` oferecem flags de idempotência (`ignorar_se_paga: true`, `ignorar_se_cancelada: true`), tornando a arquitetura resiliente a reentregas de webhooks e retentativas automáticas de filas assíncronas.

---

## Marco 18 — Processamento de Inadimplentes e Régua de Cobrança (SaaS Recorrente)

**Status:** ✅ Concluído

**Data:** 2026-09-25

### O que foi feito

- Implementação do Service Object `Assinaturas::ProcessarInadimplentesService` (com aliases `ProcessarInadimplenciaService`, `VerificarInadimplentesService` e `AssinaturaFaturas::ProcessarInadimplentesService`) para gestão e execução da régua de cobrança/inadimplência do SaaS.
- **Régua de Inadimplência e Escalonamento de Sanções:**
  - **Identificação de Débito:** Detecção de faturas em aberto (`status: :pendente`) com `data_vencimento < data_referencia`.
  - **Atrasada (`status: :atrasada`):** Transição de assinaturas com faturas vencidas além do período de carência (`dias_carencia`, padrão: `0`).
  - **Suspensa (`status: :suspensa`):** Transição de assinaturas com débitos que excedem a tolerância (`dias_para_suspensao`, padrão: `7` dias).
  - **Bloqueio do Tenant:** Bloqueio preventivo da empresa (`empresa.update!(ativo: false)`) quando sua assinatura é suspensa, refletindo a regra de domínio registrada em `Empresas.ativo: 'Bloqueio de inadimplência ou cancelamento'`.
  - **Cancelamento Automático:** Suporte a encerramento compulsório para inadimplência prolongada (`cancelar_inadimplentes: true` e `dias_para_cancelamento`, e.g. 30 dias), preenchendo `data_cancelamento: Time.current`.
- **Reconciliação e Reativação Automática (`reativar_adimplentes: true`):**
  - Assinaturas marcadas como `atrasada` ou `suspensa` que regularizam seus débitos (faturas quitadas ou canceladas) retornam automaticamente para `status: :ativa`.
  - Desbloqueio e reativação da empresa (`empresa.update!(ativo: true)`) caso não haja outras assinaturas inadimplentes atreladas ao tenant.
- **Flexibilidade Operacional e Escopos de Execução:**
  - Suporte a execução em lote (varredura geral para rotinas de Cron/Background Jobs).
  - Suporte a execução restrita por tenant (`empresa`) ou assinatura individual (`assinatura`).
  - Modo de simulação (`dry_run: true`) para relatórios prévios sem alteração de banco de dados.
- **Enriquecimento do Model `Assinatura`:**
  - Escopos: `.inadimplentes` (atrasadas ou suspensas) e `.passiveis_de_cobranca`.
  - Método utilitário `#inadimplente?`.
- Cobertura de 100% de testes no RSpec com 17 novos testes no `ProcessarInadimplentesService` e testes adicionais no model `Assinatura`, mantendo a suíte completa da aplicação com 964 testes sem nenhuma falha.

### Service Object criado

```ruby
Assinaturas::ProcessarInadimplentesService (aliases: Assinaturas::ProcessarInadimplenciaService, Assinaturas::VerificarInadimplentesService, AssinaturaFaturas::ProcessarInadimplentesService)
```

### Tabelas envolvidas

- `assinaturas`
- `assinatura_faturas`
- `empresas`

### Decisões arquiteturais

- **Régua de Cobrança Unificada e Bidirecional:** O service não apenas aplica sanções com base no tempo de atraso da fatura mais antiga, como também atua como reconciliador, reativando clientes adimplentes automaticamente caso seus débitos tenham sido sanados.
- **Bloqueio Transacional do Tenant:** A inativação da empresa (`ativo: false`) ocorre em perfeita sintonia com a suspensão da assinatura, garantindo que o tenant inadimplente tenha seu acesso bloqueado de acordo com a política de governança da plataforma.
- **Migração e Regularização de Assinaturas Inadimplentes (`SalvarService`):** O `SalvarService` suporta a substituição e migração de assinaturas `atrasadas` ou `suspensas` (`substituir_atual: true`), cancelando automaticamente as faturas pendentes da assinatura anterior (`cancelar_faturas_anteriores: true`) e reativando o tenant no banco (`reativar_empresa: true`), viabilizando a regularização imediata de clientes inadimplentes.

---

# 9. Registro de Alterações Futuras


Use esta seção para manter o histórico cronológico do projeto.

### Template

```markdown
## Marco XX — Nome da Implementação

**Data:** YYYY-MM-DD

### O que foi feito

- Item 1
- Item 2
- Item 3

### Service Objects criados

```ruby
NomeDoService
```

### Tabelas envolvidas

- `tabela_1`
- `tabela_2`

### Decisões arquiteturais

- Decisão importante tomada durante a implementação.

### Problemas encontrados

- Problema encontrado.
- Como foi resolvido.

### Próximo passo

- Próxima implementação planejada.
```

---

# 10. Princípios Arquiteturais Registrados

Os seguintes princípios devem orientar a implementação dos próximos módulos:

1. **Operações financeiras e de estoque devem ser transacionais.**
2. **Movimentações de estoque devem possuir histórico imutável.**
3. **Operações concorrentes de estoque devem utilizar locks apropriados.**
4. **Vendas devem preservar snapshots dos dados relevantes no momento da operação.**
5. **A lógica de negócio complexa deve ficar concentrada em Service Objects.**
6. **Operações de domínio não devem depender diretamente de detalhes da interface.**
7. **A integridade dos dados deve ser protegida tanto pela aplicação quanto pelo banco quando possível.**
8. **Novos módulos devem respeitar a ordem de dependências definida neste documento.**
9. **Cada marco importante deve ser registrado neste arquivo para preservar o histórico de evolução do sistema.**

---

# 11. Estado Atual do Projeto

**Última atualização:** 2026-09-23

### Fases

- [x] Fase 1 — Fundação Multi-tenant e Gestão de Acesso
- [x] Fase 2 — Catálogo e Inventário
- [x] Fase 3 — Suporte Prévio à Venda
- [x] Fase 4 — Núcleo de Vendas e Pós-venda (Concluído: Vendas, Pagamentos e Devoluções)
- [ ] Fase 5 — SaaS Recorrente e Marketing

### Próximo foco

```text
Campanhas
   ↓
Disparos
   ↓
Campanhas::SalvarService / Campanhas::DispararService
```

Este documento deve ser tratado como um **registro histórico vivo da arquitetura e do desenvolvimento**, sendo atualizado a cada marco relevante do projeto.
