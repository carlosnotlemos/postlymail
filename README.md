# Especificação Técnica e Roadmap: CRM Desktop Java

Este documento serve como guia central para o desenvolvimento de um sistema CRM multiplataforma (Windows/Linux), focado em gestão de vendas, segmentação de clientes e automação de marketing.

## 1. Visão Geral do Projeto

- **Objetivo:** Criar uma aplicação desktop para gerir clientes, produtos e vendas, com foco em inteligência de dados para marketing direto.
- **Plataformas:** Windows e Linux.
- **Principais Pilares:** Cadastro (CRUD), Segmentação Dinâmica, E-mail Marketing e Dashboard Analítico.

## 2. Stack Tecnológica (Definição)

- **Linguagem:** Java 21 (LTS).
- **Interface Gráfica:** JavaFX (layouts via FXML e estilos em CSS).
- **Banco de Dados:** SQLite (local, sem necessidade de servidor externo).
- **Persistência de Dados:** Hibernate ou Spring Data JPA.
- **Gerenciamento de Dependências:** Maven.
- **Comunicação:** Jakarta Mail para envio de e-mails via SMTP.

## 3. Arquitetura de Dados (Modelagem)

O banco de dados será composto pelas seguintes entidades principais:

- **Clientes:** `id`, `nome`, `email`, `telefone`, `data_cadastro`.
- **Produtos:** `id`, `nome`, `preco`, `categoria`, `estoque`.
- **Vendas:** `id`, `cliente_id` (FK), `data_venda`, `valor_total`.
- **ItensVenda:** `id`, `venda_id` (FK), `produto_id` (FK), `quantidade`, `preco_unitario`.

## 4. Módulos e Requisitos

### 4.1. Gestão de Entidades

- Cadastro completo de clientes e catálogo de produtos.
- Fluxo de registro de compras vinculando clientes a itens específicos.

### 4.2. Segmentação e E-mail Marketing

- Filtros avançados para identificar perfis de compra (ex: clientes que compraram o Produto X, ou que não compram há 60 dias).
- Integração SMTP para disparos segmentados.
- Suporte a templates em HTML.

### 4.3. Dashboard de Vendas

- Visualização de faturamento mensal.
- Gráficos de categorias mais vendidas.
- Ranking de clientes por volume de compras.

## 5. Checklist de Desenvolvimento

### Fase 1: Setup e Estrutura [x] 100%

- [x] Configuração do projeto Maven.
- [x] Definição das classes de Modelo (Entities).
- [x] Configuração da conexão SQLite com Hibernate.
- [x] Refatoração para estrutura de pacotes sólida (`br.com.postlymail`).

### Fase 2: Interface e CRUDs [x] 100%

- [x] Layout principal com menu de navegação.
- [x] Aplicação de design premium (CSS Customizado).
- [x] CRUD de Clientes (Listagem, Criação, Edição, Exclusão).
- [x] CRUD de Produtos (Listagem, Criação, Edição, Exclusão).
- [x] Tela de registro de novas Vendas (Fluxo de PDV completo).
- [x] Otimização de performance (Async loading & Hibernate Pre-warming).

### Fase 3: Inteligência e Comunicação [ ] 0%

- [ ] Implementação do motor de busca para segmentação.
- [ ] Módulo de configuração SMTP.
- [ ] Interface de envio de e-mail em massa (execução em background).

### Fase 4: Dashboard e Finalização [ ] 0%

- [ ] Implementação dos gráficos JavaFX.
- [ ] Geração do instalador via `jpackage`.

## 6. Orientações para IA de Codificação

1. **Padrão MVC:** Manter a separação entre lógica de negócio (Model), Interface (View) e Controle (Controller).
2. **Não Travamento:** Todas as operações pesadas (Banco de dados e E-mail) devem usar `Task` ou `Service` para não congelar a interface.
3. **Persistência:** Priorizar consultas otimizadas para a geração do dashboard.
