# Requisitos P04 — Análise Técnica de Licenciamento (ATEC)
## Stack Java Moderna — Sem dependência PROCERGS

**Processo:** P04 — Análise Técnica Administrativa (ATEC)
**Entrada:** Licenciamento na situação `AGUARDANDO_DISTRIBUICAO`
**Saída A (aprovação):** Situação `CA` (PPCI) ou `ALVARA_VIGENTE` (PSPCIM) — documento CA/APPCI emitido
**Saída B (reprovação):** Situação `AGUARDANDO_CIENCIA` — documento CIA emitido
**Versão:** 1.0 — 2026-03-09

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica Adotada](#2-stack-tecnológica-adotada)
3. [Modelo de Dados](#3-modelo-de-dados)
4. [Enumerações](#4-enumerações)
5. [Regras de Negócio por Etapa](#5-regras-de-negócio-por-etapa)
   - 5.1 Distribuição da Análise
   - 5.2 Registro de Resultados por Item
   - 5.3 Emissão de CIA (Reprovação)
   - 5.4 Emissão de CA (Aprovação — envio para homologação)
   - 5.5 Homologação pelo Coordenador
   - 5.6 Cancelamento Administrativo
6. [Padrão Strategy de Resultados](#6-padrão-strategy-de-resultados)
7. [Geração de Documentos PDF](#7-geração-de-documentos-pdf)
8. [API REST](#8-api-rest)
9. [Segurança e Controle de Acesso](#9-segurança-e-controle-de-acesso)
10. [Notificações e Marcos (TipoMarco)](#10-notificações-e-marcos-tipomarcoo)
11. [Auditoria](#11-auditoria)
12. [Tratamento de Erros](#12-tratamento-de-erros)

---

## 1. Visão Geral do Processo

O Processo P04 representa a **Análise Técnica de Licenciamento (ATEC)** realizada pelos analistas do CBM-RS. É o processo central de avaliação do PPCI (Plano de Prevenção e Proteção Contra Incêndio) ou PSPCIM submetido pelo Responsável Técnico (RT) no P03.

### 1.1 Fluxo resumido

```
[AGUARDANDO_DISTRIBUICAO]
         |
         v
[Coordenador distribui para Analista]
         |
         v
    [EM_ANALISE]
         |
         v
[Analista registra resultado por item]
         |
         +----> CIA (algum item reprovado ou "outraInconformidade" preenchida)
         |           |
         |           v
         |      [Gera CIA PDF] --> [AGUARDANDO_CIENCIA] --> (P05 — Ciência/Recurso)
         |
         +----> CA (todos os itens aprovados, sem outraInconformidade)
                     |
                     v
               [EM_APROVACAO]
                     |
                     v
         [Coordenador homologa]
                     |
                     +----> Deferir --> [Gera CA/APPCI PDF] --> [CA] ou [ALVARA_VIGENTE]
                     |
                     +----> Indeferir (volta para EM_ANALISE com justificativa)

[Cancelamento Administrativo] --> CANCELADA --> [AGUARDANDO_DISTRIBUICAO]
```

### 1.2 Atores envolvidos

| Ator | Papel |
|---|---|
| Coordenador CBM-RS | Distribui análises, cancela distribuições, homologa resultado |
| Analista CBM-RS | Executa a análise técnica, registra resultados por item, emite CIA ou CA |
| Sistema | Transições de estado, geração de documentos PDF, registro de marcos |

### 1.3 Tipos de licenciamento suportados

| Tipo | Descrição | Documento gerado na aprovação |
|---|---|---|
| `PPCI` | Plano de Prevenção e Proteção Contra Incêndio | CA (Certificado de Aprovação) |
| `PSPCIM` | Plano Simplificado de Proteção Contra Incêndio em Meios | APPCI + Documento Complementar |

---

## 2. Stack Tecnológica Adotada

| Camada | Tecnologia |
|---|---|
| Linguagem | Java 21 |
| Framework principal | Spring Boot 3.3.x |
| API REST | Spring MVC (JAX-RS substituído) |
| Segurança / autenticação | Spring Security 6 + Keycloak 24 (substitui SOE PROCERGS) |
| Persistência | Spring Data JPA + Hibernate 6 |
| Banco de dados | PostgreSQL 16 |
| Migrações de BD | Flyway |
| Geração de PDF | JasperReports 6.x ou Apache PDFBox 3.x |
| Armazenamento de arquivos | MinIO (substitui Alfresco) |
| Auditoria | Hibernate Envers |
| Validação | Jakarta Bean Validation 3 (Hibernate Validator) |
| Build | Maven 3.9 |
| Testes | JUnit 5 + Mockito + Testcontainers |

### 2.1 Mapeamento de substituições PROCERGS

| Componente PROCERGS (legado) | Substituto moderno |
|---|---|
| `SessionMB.getUser()` (SOE) | `SecurityContextHolder` + `Authentication` do Keycloak JWT |
| `UsuarioSoeRN` (consulta SOE) | Serviço interno `UsuarioService` com dados do JWT/Keycloak |
| Alfresco (nodeRef `identificadorAlfresco`) | MinIO — `ObjectStorageService` retorna `objectKey` (UUID) |
| `AppBD` + `AppRN` (infra PROCERGS) | `JpaRepository` + classes `@Service` Spring |
| `@Stateless` EJB | `@Service` + `@Transactional` Spring |
| `@AppInterceptor` | `@Aspect` AOP (logging/auditoria customizado) |
| `@Permissao(objeto, acao)` | `@PreAuthorize("hasAuthority('OBJETO:ACAO')")` Spring Security |
| `MessageProvider` (bundle) | `MessageSource` Spring (i18n) |
| `WebApplicationRNException` | `ResponseStatusException` Spring ou exceções de domínio customizadas |

---

## 3. Modelo de Dados

### 3.1 Entidade principal — `AnaliseTecnica`

Tabela: `CBM_ANALISE_LIC_TECNICA`

| Coluna | Tipo | Nulidade | Descrição |
|---|---|---|---|
| `id` | BIGSERIAL | NOT NULL PK | Identificador sequencial |
| `id_licenciamento` | BIGINT | NOT NULL FK | Referência ao licenciamento |
| `numero_analise` | INTEGER | NOT NULL | Número ordinal da análise para o licenciamento (1, 2, 3…) |
| `status` | VARCHAR(32) | NOT NULL | `StatusAnaliseTecnica` enum |
| `id_usuario_analista` | BIGINT | NOT NULL | ID do analista (subject do JWT) |
| `nome_usuario_analista` | VARCHAR(64) | NOT NULL | Nome do analista (snapshot do JWT) |
| `dth_status` | TIMESTAMPTZ | NOT NULL | Timestamp da última mudança de status |
| `outra_inconformidade` | TEXT | NULL | Texto livre de inconformidade não enquadrada |
| `justificativa_antecipacao` | TEXT | NULL | Justificativa de antecipação de análise |
| `id_arquivo` | BIGINT | NULL FK | Referência ao documento gerado (CIA ou CA) |
| `ciencia` | BOOLEAN | NOT NULL DEFAULT FALSE | Se o envolvido tomou ciência do resultado |
| `dth_ciencia` | TIMESTAMPTZ | NULL | Timestamp da ciência |
| `id_usuario_ciencia` | BIGINT | NULL | ID do usuário que tomou ciência |
| `id_usuario_homologador` | BIGINT | NULL | ID do coordenador que homologou |
| `nome_usuario_homologador` | VARCHAR(64) | NULL | Nome do homologador |
| `dth_homologacao` | TIMESTAMPTZ | NULL | Timestamp da homologação |
| `indeferimento_homolog` | TEXT | NULL | Justificativa de indeferimento da homologação |
| `recurso_bloqueado` | BOOLEAN | NOT NULL DEFAULT TRUE | Bloqueia interposição de recurso durante análise |

**Constraints:**
- `UQ_ANALISE_LIC_NUMERO`: `(id_licenciamento, numero_analise)` — unicidade por licenciamento
- `FK_ANALISE_LICENCIAMENTO`: `id_licenciamento` → `CBM_LICENCIAMENTO(id)`
- `FK_ANALISE_ARQUIVO`: `id_arquivo` → `CBM_ARQUIVO(id)`

**Auditoria:** tabela `CBM_ANALISE_LIC_TECNICA_AUD` via Hibernate Envers.

---

### 3.2 Entidade abstrata — `ResultadoAtec` (base)

Classe abstrata mapeada com `@MappedSuperclass`. Todas as 10 entidades de resultado herdam dela.

| Coluna | Tipo | Nulidade | Descrição |
|---|---|---|---|
| `id` | BIGSERIAL | NOT NULL PK | Identificador sequencial |
| `id_analise_tecnica` | BIGINT | NOT NULL FK | Referência à `AnaliseTecnica` |
| `status` | VARCHAR(16) | NOT NULL | `StatusResultadoAtec` (`APROVADO` / `REPROVADO`) |

---

### 3.3 Entidades de resultado por tipo de item

Cada entidade abaixo herda `ResultadoAtec` e possui tabela própria. Todos têm relacionamento `@ManyToOne` com `AnaliseTecnica` e coleção `@OneToMany` de `JustificativaNcs` (apenas quando `status = REPROVADO`).

| Entidade | Tabela | Tipo de item |
|---|---|---|
| `ResultadoAtecRT` | `CBM_RESULTADO_ATEC_RT` | Dados do Responsável Técnico |
| `ResultadoAtecRU` | `CBM_RESULTADO_ATEC_RU` | Dados do Responsável pelo Uso |
| `ResultadoAtecProprietario` | `CBM_RESULTADO_ATEC_PROPRIETARIO` | Dados do Proprietário |
| `ResultadoAtecIsolamentoRisco` | `CBM_RESULTADO_ATEC_ISOL_RISCO` | Isolamento de risco entre ocupações |
| `ResultadoAtecTipoEdificacao` | `CBM_RESULTADO_ATEC_TIPO_EDIF` | Tipo e altura da edificação |
| `ResultadoAtecOcupacao` | `CBM_RESULTADO_ATEC_OCUPACAO` | Ocupação predominante (CNAE) |
| `ResultadoAtecGeral` | `CBM_RESULTADO_ATEC_GERAL` | Itens gerais do PPCI |
| `ResultadoAtecMedidaSeguranca` | `CBM_RESULTADO_ATEC_MED_SEG` | Medidas de segurança padrão |
| `ResultadoAtecMedidaSegurancaOutra` | (via `JustificativaAtecOutraMedSeg`) | Outras medidas (texto livre) |
| `ResultadoAtecRiscoEspecifico` | `CBM_RESULTADO_ATEC_RISCO_ESP` | Riscos específicos |
| `ResultadoAtecElementoGrafico` | `CBM_RESULTADO_ATEC_ELEM_GRAF` | Elementos gráficos do projeto |

---

### 3.4 Entidade — `JustificativaNcs`

Armazena as justificativas de inconformidade por item reprovado.

Tabela: `CBM_JUSTIFICATIVA_NCS`

| Coluna | Tipo | Nulidade | Descrição |
|---|---|---|---|
| `id` | BIGSERIAL | NOT NULL PK | Identificador |
| `id_resultado_atec` | BIGINT | NOT NULL FK | Referência ao ResultadoAtec pai |
| `tipo_resultado` | VARCHAR(32) | NOT NULL | Discriminador do tipo de item (`TipoItemAnaliseTecnica`) |
| `descricao` | TEXT | NOT NULL | Texto da justificativa de reprovação |

---

### 3.5 Entidade — `JustificativaAtecOutraMedidaSeguranca`

Tabela: `CBM_JUSTIF_ATEC_OUTRA_MED_SEG`

| Coluna | Tipo | Nulidade | Descrição |
|---|---|---|---|
| `id` | BIGSERIAL | NOT NULL PK | Identificador |
| `id_analise_tecnica` | BIGINT | NOT NULL FK | Referência à `AnaliseTecnica` |
| `descricao` | TEXT | NOT NULL | Texto da justificativa de outra medida de segurança |

---

### 3.6 Entidade — `Arquivo`

Tabela: `CBM_ARQUIVO`

| Coluna | Tipo | Nulidade | Descrição |
|---|---|---|---|
| `id` | BIGSERIAL | NOT NULL PK | Identificador |
| `nome_arquivo` | VARCHAR(255) | NOT NULL | Nome lógico do arquivo (ex.: `cia_analise_tecnica.pdf`) |
| `object_key` | VARCHAR(512) | NOT NULL | Chave no MinIO (substitui `identificadorAlfresco`) |
| `tipo_arquivo` | VARCHAR(32) | NOT NULL | `TipoArquivo` enum (ex.: `EDIFICACAO`) |
| `codigo_autenticacao` | VARCHAR(64) | NULL | Código de autenticidade do documento |
| `dth_inclusao` | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | Timestamp de criação |

> **Nota de arquitetura:** o binário do arquivo NUNCA é armazenado no banco relacional. O campo `object_key` referencia o objeto no MinIO. A classe `ObjectStorageService` é responsável por todas as operações de upload/download.

---

### 3.7 Relacionamentos resumidos

```
Licenciamento (1) ----< (N) AnaliseTecnica
AnaliseTecnica (1) ----< (N) ResultadoAtecRT
AnaliseTecnica (1) ----< (N) ResultadoAtecRU
AnaliseTecnica (1) ----< (N) ResultadoAtecProprietario
AnaliseTecnica (1) ----< (N) ResultadoAtecIsolamentoRisco
AnaliseTecnica (1) ----< (N) ResultadoAtecTipoEdificacao
AnaliseTecnica (1) ----< (N) ResultadoAtecOcupacao
AnaliseTecnica (1) ----< (N) ResultadoAtecGeral
AnaliseTecnica (1) ----< (N) ResultadoAtecMedidaSeguranca
AnaliseTecnica (1) ----< (N) ResultadoAtecRiscoEspecifico
AnaliseTecnica (1) ----< (N) ResultadoAtecElementoGrafico
AnaliseTecnica (1) ----< (N) JustificativaAtecOutraMedidaSeguranca
ResultadoAtecXxx (1) ----< (N) JustificativaNcs  [apenas quando status = REPROVADO]
AnaliseTecnica (1) ----> (1) Arquivo [nullable — CIA ou CA gerado]
```

---

## 4. Enumerações

### 4.1 `StatusAnaliseTecnica`

| Valor | Descrição | Transições permitidas |
|---|---|---|
| `EM_ANALISE` | Análise em progresso pelo analista designado | → `EM_APROVACAO` (CA), → `REPROVADO` (CIA), → `CANCELADA` |
| `EM_APROVACAO` | Aguardando homologação pelo coordenador | → `APROVADO` (deferir), → `EM_ANALISE` (indeferir) |
| `APROVADO` | Homologação deferida — CA/APPCI emitido | Estado terminal |
| `REPROVADO` | CIA emitido — aguardando ciência do RT | Estado terminal (desta análise) |
| `CANCELADA` | Cancelada administrativamente | Estado terminal |
| `EM_REDISTRIBUICAO` | Redistribuída a outro analista (reservado) | → `EM_ANALISE` |

### 4.2 `StatusResultadoAtec`

| Valor | Descrição |
|---|---|
| `APROVADO` | Item analisado está em conformidade |
| `REPROVADO` | Item analisado possui inconformidade — exige justificativa |

### 4.3 `TipoItemAnaliseTecnica`

| Valor | Descrição | Obrigatório analisar? |
|---|---|---|
| `RT` | Responsável Técnico | Sim |
| `RU` | Responsável pelo Uso | Sim |
| `PROPRIETARIO` | Proprietário | Sim |
| `TIPO_EDIFICACAO` | Tipo de edificação | Sim |
| `OCUPACAO` | Ocupação predominante | Sim |
| `ISOLAMENTO_RISCO` | Isolamento de risco entre unidades | Sim |
| `GERAL` | Itens gerais do PPCI | Sim |
| `MEDIDA_SEGURANCA` | Medidas de segurança previstas em norma | Sim |
| `MEDIDA_SEGURANCA_OUTRA` | Outras medidas de segurança (texto livre) | Condicional |
| `RISCO_ESPECIFICO` | Riscos específicos da edificação | Condicional |
| `ELEMENTO_GRAFICO` | Elementos gráficos do projeto | Sim |

### 4.4 `SituacaoLicenciamento` — situações relevantes ao P04

| Valor | Descrição |
|---|---|
| `AGUARDANDO_DISTRIBUICAO` | Pré-condição de entrada no P04 |
| `EM_ANALISE` | Durante a análise técnica |
| `AGUARDANDO_CIENCIA` | Pós-CIA — aguardando ciência do RT |
| `CA` | Certificado de Aprovação emitido (PPCI) |
| `ALVARA_VIGENTE` | APPCI emitido e vigente (PSPCIM) |

### 4.5 `TipoMarco` — marcos gerados no P04

| Valor | Momento de geração |
|---|---|
| `DISTRIBUICAO_ANALISE` | Ao distribuir o licenciamento para um analista |
| `ATEC_CIA` | Ao emitir CIA (análise reprovada) |
| `ATEC_CA` | Ao emitir CA (análise aprovada — PPCI) |
| `ATEC_APPCI` | Ao emitir APPCI (análise aprovada — PSPCIM) |
| `HOMOLOG_ATEC_DEFERIDO` | Ao deferir a homologação (PPCI) |
| `HOMOLOG_ATEC_APPCI` | Ao deferir a homologação (PSPCIM) |
| `HOMOLOG_ATEC_INDEFERIDO` | Ao indeferir a homologação |
| `CANCELA_DISTRIBUICAO_ANALISE` | Ao cancelar a distribuição |
| `EMISSAO_DOC_COMPLEMENTAR` | Ao emitir o documento complementar (PSPCIM) |

### 4.6 `TipoEdificacao`

| Valor | Impacto no P04 |
|---|---|
| `A_CONSTRUIR` | Gera CA novo (`ca_nova_analise_tecnica.pdf`) |
| `EXISTENTE` | Gera CA existente (`ca_existente_analise_tecnica.pdf`) |

### 4.7 `TipoLicenciamento`

| Valor | Documento gerado na aprovação |
|---|---|
| `PPCI` | CA (Certificado de Aprovação) |
| `PSPCIM` | APPCI + Documento Complementar |

---

## 5. Regras de Negócio por Etapa

### 5.1 Distribuição da Análise

**Descrição:** O coordenador CBM-RS seleciona licenciamentos em `AGUARDANDO_DISTRIBUICAO` e os atribui a analistas do mesmo batalhão.

**Endpoint:** `POST /api/v1/analises-tecnicas/distribuicao`

**Permissão exigida:** `DISTRIBUICAOANALISE:DISTRIBUIR`

**Payload de entrada:** lista de objetos `DistribuicaoAnaliseTecnicaRequest`:
```json
[
  { "idLicenciamento": 1234, "idUsuarioAnalista": 567 }
]
```

**Regras de validação (lançam `400 Bad Request` ou `406 Not Acceptable`):**

| Código | Regra |
|---|---|
| RN-P04-D01 | O licenciamento deve estar na situação `AGUARDANDO_DISTRIBUICAO` ou `AGUARDANDO_DISTRIBUICAO_RENOV`. Caso contrário, rejeitar com mensagem `licenciamento.distribuicao.status`. |
| RN-P04-D02 | O analista designado deve ter um batalhão CBM-RS associado ao seu perfil. Se ausente, rejeitar com `analisetecnica.usuario.batalhao.naoencontrado`. |
| RN-P04-D03 | O batalhão do analista deve cobrir a cidade do licenciamento (verificação via tabela `cidade_batalhao`). Se a cidade não pertence ao batalhão do analista, rejeitar com `licenciamento.distribuicao.batalhao`. |

**Regras de execução (em transação):**

| Código | Regra |
|---|---|
| RN-P04-D04 | Calcular o próximo `numeroAnalise` consultando a última análise não cancelada do licenciamento. Se não houver análise anterior, `numeroAnalise = 1`. |
| RN-P04-D05 | Criar registro em `AnaliseTecnica` com: `status = EM_ANALISE`, `ciencia = false`, `id_usuario_analista` e `nome_usuario_analista` copiados do perfil Keycloak, `dth_status = now()`. |
| RN-P04-D06 | Transitar o `Licenciamento` de `AGUARDANDO_DISTRIBUICAO` para `EM_ANALISE`. |
| RN-P04-D07 | Registrar marco `DISTRIBUICAO_ANALISE` no histórico do licenciamento. |

**Consultas de apoio disponíveis:**

| Endpoint | Permissão | Descrição |
|---|---|---|
| `GET /api/v1/analises-tecnicas/distribuicao/pendentes` | `DISTRIBUICAOANALISE:LISTAR` | Lista paginada de licenciamentos em `AGUARDANDO_DISTRIBUICAO`. Retorna: número PPCI, razão social, ocupação predominante, área construída, dias na fila, nome do último analista (se houve análise anterior). |
| `GET /api/v1/analises-tecnicas/distribuicao/analistas` | `DISTRIBUICAOANALISE:LISTAR` | Lista analistas do batalhão do coordenador logado, com total de licenciamentos em análise e área total em m² por analista. Ordenado por `areaEmAnalise ASC` (permite balanceamento de carga). |
| `GET /api/v1/analises-tecnicas/distribuicao/analistas-por-usuario/{idUsuario}` | `DISTRIBUICAOANALISE:CONSULTAR` | Lista os licenciamentos atribuídos a um analista específico. |

---

### 5.2 Registro de Resultados por Item

**Descrição:** O analista examina a documentação do PPCI e registra o resultado (APROVADO ou REPROVADO) para cada um dos 11 tipos de item. Quando o item é reprovado, deve informar ao menos uma justificativa de NCS.

**Endpoint salvar resultado:** `PUT /api/v1/analises-tecnicas/{idAnalise}/resultados`

**Permissão exigida:** `ANALISETECNICA:ANALISAR`

**Payload de entrada:** `ResultadoAtecRequest`:
```json
{
  "idAnaliseTecnica": 100,
  "tipoItemAnaliseTecnica": "MEDIDA_SEGURANCA",
  "idItemAnalisado": 42,
  "statusResultadoAtec": "REPROVADO",
  "justificativas": [
    { "descricao": "Saída de emergência com largura insuficiente conforme IN-009." }
  ]
}
```

**Regras de validação:**

| Código | Regra |
|---|---|
| RN-P04-R01 | O analista logado deve ser o mesmo que foi designado para a análise (`id_usuario_analista`). Caso contrário, HTTP 403 com mensagem `analisetecnica.usuario.naoautorizado`. |
| RN-P04-R02 | A análise deve estar com `status = EM_ANALISE`. Caso contrário, HTTP 406. |
| RN-P04-R03 | O `idItemAnalisado` informado deve pertencer ao licenciamento da análise em questão (verificação via subquery específica por `TipoItemAnaliseTecnica`). |
| RN-P04-R04 | Se `statusResultadoAtec = REPROVADO`, a lista `justificativas` não pode ser nula nem vazia. Ao menos uma justificativa é obrigatória. |

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-R05 | Se já existe um `ResultadoAtec` para o par `(idAnaliseTecnica, idItemAnalisado)`, realizar **alteração**: excluir as justificativas anteriores e incluir as novas. |
| RN-P04-R06 | Se não existe resultado anterior, **incluir** novo `ResultadoAtec` com as justificativas informadas. |
| RN-P04-R07 | Justificativas só são persistidas quando `statusResultadoAtec = REPROVADO`. Se o item é aprovado, nenhuma justificativa é salva. |

**Endpoint excluir resultado:** `DELETE /api/v1/analises-tecnicas/{idAnalise}/resultados/{idResultado}`

**Permissão exigida:** `ANALISETECNICA:ANALISAR`

| Código | Regra |
|---|---|
| RN-P04-R08 | Validar que a análise pertence ao usuário logado (RN-P04-R01). |
| RN-P04-R09 | Validar que a análise está em `EM_ANALISE` (RN-P04-R02). |
| RN-P04-R10 | Excluir todas as `JustificativaNcs` vinculadas ao resultado e então excluir o `ResultadoAtec`. |

**Endpoint salvar outra inconformidade (texto livre):**
`PUT /api/v1/analises-tecnicas/{idAnalise}/outra-inconformidade`

Body: `{ "outraInconformidade": "Texto descritivo da inconformidade não enquadrada." }`

| Código | Regra |
|---|---|
| RN-P04-R11 | Validar que a análise pertence ao usuário logado. |
| RN-P04-R12 | Atualizar o campo `outra_inconformidade` na entidade `AnaliseTecnica`. |

**Endpoint salvar outras medidas de segurança:**
`PUT /api/v1/analises-tecnicas/{idAnalise}/outras-medidas-seguranca`

| Código | Regra |
|---|---|
| RN-P04-R13 | Validar que a análise pertence ao usuário logado e está em `EM_ANALISE`. |
| RN-P04-R14 | Excluir todas as `JustificativaAtecOutraMedidaSeguranca` existentes para a análise e incluir as novas informadas. |

---

### 5.3 Emissão de CIA (Reprovação)

**Descrição:** O analista conclui a análise com resultado negativo — ao menos um item está reprovado ou o campo `outra_inconformidade` foi preenchido. O sistema gera o documento CIA autenticado e transita o licenciamento.

**Endpoint:** `POST /api/v1/analises-tecnicas/{idAnalise}/cia`

**Permissão exigida:** `ANALISETECNICA:ANALISAR`

**Regras de validação:**

| Código | Regra |
|---|---|
| RN-P04-CIA01 | Validar que a análise pertence ao usuário logado (RN-P04-R01). |
| RN-P04-CIA02 | Todos os 11 tipos de item devem ter pelo menos um resultado registrado. A validação percorre cada `TipoItemAnaliseTecnica` e verifica a quantidade de itens analisados via strategy. Caso algum tipo não possua nenhum item analisado, rejeitar com mensagem de itens pendentes. |
| RN-P04-CIA03 | Se `outra_inconformidade` estiver em branco, deve existir ao menos um `ResultadoAtec` com `status = REPROVADO`. Caso contrário, rejeitar com `analisetecnica.status.naoreprovada`. |

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-CIA04 | Gerar código de autenticação único para o documento (UUID ou sequencial único da tabela `CBM_ARQUIVO`). |
| RN-P04-CIA05 | Gerar PDF do CIA com a lista de inconformidades ordenada por `TipoItemAnaliseTecnica` (ordem: RT, RU, PROPRIETARIO, TIPO_EDIFICACAO, OCUPACAO, ISOLAMENTO_RISCO, GERAL, MEDIDA_SEGURANCA, MEDIDA_SEGURANCA_OUTRA, RISCO_ESPECIFICO, ELEMENTO_GRAFICO). Se `outra_inconformidade` não for nulo, incluir ao final como "Demais inconformidades". |
| RN-P04-CIA06 | Armazenar o PDF gerado no MinIO. Criar registro em `CBM_ARQUIVO` com `nome_arquivo = 'cia_analise_tecnica.pdf'` e `tipo_arquivo = EDIFICACAO`. |
| RN-P04-CIA07 | Atualizar `AnaliseTecnica`: `status = REPROVADO`, `dth_status = now()`, `id_arquivo` = arquivo CIA recém-criado. |
| RN-P04-CIA08 | Registrar marco `ATEC_CIA` no histórico do licenciamento, vinculado ao arquivo gerado. |
| RN-P04-CIA09 | Transitar o `Licenciamento` de `EM_ANALISE` para `AGUARDANDO_CIENCIA`. |
| RN-P04-CIA10 | Definir `recurso_bloqueado = false` no licenciamento (libera interposição de recurso após ciência). |
| RN-P04-CIA11 | Persistir histórico dos elementos gráficos analisados via `ElementoGraficoHistoricoService` (para rastreabilidade de versões do projeto gráfico). |

**Endpoint download rascunho CIA (sem autenticação, apenas preview):**
`GET /api/v1/analises-tecnicas/{idAnalise}/rascunho-cia`

Permissão: `ANALISETECNICA:ANALISAR`

Retorna o PDF da CIA gerado com base nos resultados registrados até o momento, SEM persistir nada. Útil para o analista revisar antes de confirmar.

---

### 5.4 Emissão de CA — Envio para Homologação

**Descrição:** O analista conclui a análise com resultado positivo — todos os itens estão aprovados e `outra_inconformidade` está em branco. O sistema coloca a análise em `EM_APROVACAO` para revisão do coordenador. O CA definitivo ainda NÃO é emitido nesta etapa — ele é gerado apenas após a homologação.

**Endpoint:** `POST /api/v1/analises-tecnicas/{idAnalise}/ca`

**Permissão exigida:** `ANALISETECNICA:ANALISAR`

**Regras de validação:**

| Código | Regra |
|---|---|
| RN-P04-CA01 | Validar que a análise pertence ao usuário logado. |
| RN-P04-CA02 | O campo `outra_inconformidade` deve estar em branco. Se preenchido, rejeitar com `analisetecnica.status.inconformidades`. |
| RN-P04-CA03 | Todos os 11 tipos de item devem ter resultados registrados. |
| RN-P04-CA04 | Todos os itens devem estar com `status = APROVADO`. Se houver qualquer item `REPROVADO`, rejeitar (não é possível emitir CA com inconformidades). |

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-CA05 | Atualizar `AnaliseTecnica`: `status = EM_APROVACAO`, `dth_status = now()`, limpar `outra_inconformidade = null`. |
| RN-P04-CA06 | Concluir a nota de trabalho associada ao licenciamento (`NotaService.concluirNota(idLicenciamento)`). |
| RN-P04-CA07 | Registrar marco no licenciamento: `ATEC_CA` (se `TipoLicenciamento = PPCI`) ou `ATEC_APPCI` (se `TipoLicenciamento = PSPCIM`). |
| RN-P04-CA08 | Persistir histórico dos elementos gráficos via `ElementoGraficoHistoricoService`. |

**Endpoint download rascunho CA (sem autenticação, apenas preview):**
`GET /api/v1/analises-tecnicas/{idAnalise}/rascunho-ca`

Permissão: controlada internamente (analista ou coordenador logado no batalhão competente).

Gera e retorna o PDF de rascunho do CA (sem código de autenticação). O tipo de CA depende de `TipoEdificacao`:
- `A_CONSTRUIR` → template `ca_nova_analise_tecnica.pdf`
- qualquer outro → template `ca_existente_analise_tecnica.pdf`

---

### 5.5 Homologação pelo Coordenador

**Descrição:** O coordenador (ou chefe) revisa a análise aprovada pelo analista e decide entre Deferir (confirmar o CA) ou Indeferir (devolver para o analista revisar).

#### 5.5.1 Consulta de análises pendentes de homologação

**Endpoint:** `GET /api/v1/analises-tecnicas/homologacao`

**Permissão:** `ANALISETECNICA:HOMOLOGAR`

Retorna lista paginada de `AnaliseTecnica` com `status = EM_APROVACAO`, filtrada pelas cidades do batalhão do coordenador logado. Ordenação: sem prioridade específica (padrão: data de status ASC).

**Endpoint consultar análise com resultados completos:**
`GET /api/v1/analises-tecnicas/{idAnalise}/homologacao`

Permissão: `ANALISETECNICA:HOMOLOGAR`

Retorna `AnaliseTecnicaDetalheResponse` com:
- Dados da análise (analista, datas, status)
- Todos os resultados por tipo de item
- Nome do analista anterior (se análise de revisão)
- ID do arquivo CIA anterior (se houve reprovação anterior)
- Justificativa de indeferimento anterior (se homologação foi indeferida antes)

#### 5.5.2 Deferir homologação

**Endpoint:** `POST /api/v1/analises-tecnicas/{idAnalise}/homologacao/deferir`

**Permissão:** `ANALISETECNICA:HOMOLOGAR`

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-H01 | Atualizar `AnaliseTecnica`: `status = APROVADO`, `indeferimento_homolog = null`, `dth_homologacao = now()`, `id_usuario_homologador` e `nome_usuario_homologador` do JWT do coordenador. |
| RN-P04-H02 | **Para `TipoLicenciamento = PPCI`:** gerar o PDF do CA autenticado. O tipo do CA depende de `TipoEdificacao` (`A_CONSTRUIR` → `ca_nova_analise_tecnica.pdf`; caso contrário → `ca_existente_analise_tecnica.pdf`). Armazenar no MinIO. Vincular o `Arquivo` gerado ao campo `id_arquivo` da `AnaliseTecnica`. |
| RN-P04-H03 | **Para `TipoLicenciamento = PSPCIM`:** gerar PDF do APPCI autenticado (`appci_analise_tecnica.pdf`) e também o documento complementar (`DocComplementar.pdf`). Armazenar ambos no MinIO. Criar registro `Appci` com `ciencia = false` e prazo de validade calculado por `CalculoValidadeAppciService`. Criar registro `AppciDocComplementar`. |
| RN-P04-H04 | Excluir todos os resultados temporários da análise via `ResultadoAnaliseTecnicaExclusaoService.excluirResultados()`. |
| RN-P04-H05 | Registrar marco no licenciamento: `HOMOLOG_ATEC_DEFERIDO` vinculado ao arquivo CA (PPCI) ou `HOMOLOG_ATEC_APPCI` vinculado ao arquivo APPCI (PSPCIM). Para PSPCIM, registrar também marco `EMISSAO_DOC_COMPLEMENTAR`. |
| RN-P04-H06 | **Para PPCI:** transitar licenciamento para `CA` via `TrocaEstadoService`. |
| RN-P04-H07 | **Para PSPCIM:** transitar licenciamento para `ALVARA_VIGENTE` via `TrocaEstadoService`. |
| RN-P04-H08 | Ativar recurso no licenciamento: `LicenciamentoService.ativarRecurso(licenciamento)`. |
| RN-P04-H09 | Se a situação do licenciamento após a transição for `CA`, realizar integração com LAI (Lei de Acesso à Informação): `IntegracaoLaiService.cadastrarDemandaUnicaAnalise(licenciamento)`. |

#### 5.5.3 Indeferir homologação

**Endpoint:** `POST /api/v1/analises-tecnicas/{idAnalise}/homologacao/indeferir`

**Permissão:** `ANALISETECNICA:HOMOLOGAR`

**Payload:** `{ "justificativa": "Faltou verificar item X da IN-010." }`

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-H10 | Atualizar `AnaliseTecnica`: `status = EM_ANALISE` (devolve ao analista), `indeferimento_homolog = justificativa`, `dth_homologacao = now()`, preencher dados do homologador. |
| RN-P04-H11 | Registrar marco `HOMOLOG_ATEC_INDEFERIDO` no licenciamento. |
| RN-P04-H12 | Concluir nota associada ao licenciamento. |

> O licenciamento permanece em `EM_ANALISE` (não há mudança de situação). O analista volta a enxergar a análise na sua fila com a justificativa de indeferimento visível.

---

### 5.6 Cancelamento Administrativo

**Descrição:** O coordenador cancela uma análise em progresso (`EM_ANALISE`) para redistribuí-la a outro analista ou remover do fluxo.

**Endpoint:** `DELETE /api/v1/analises-tecnicas/{idAnalise}/distribuicao`

**Permissão:** `DISTRIBUICAOANALISE:CANCELAR`

**Regras de execução:**

| Código | Regra |
|---|---|
| RN-P04-C01 | Validar que o coordenador logado tem competência sobre a cidade do licenciamento (mesmo batalhão). |
| RN-P04-C02 | Atualizar `AnaliseTecnica`: `status = CANCELADA`, `dth_status = now()`. |
| RN-P04-C03 | Excluir todos os resultados da análise cancelada via `ResultadoAnaliseTecnicaExclusaoService.excluirResultados()`. |
| RN-P04-C04 | Concluir nota de trabalho associada ao licenciamento. |
| RN-P04-C05 | Transitar o licenciamento de `EM_ANALISE` para `AGUARDANDO_DISTRIBUICAO`, disponibilizando-o novamente para redistribuição. |
| RN-P04-C06 | Registrar marco `CANCELA_DISTRIBUICAO_ANALISE` no histórico. |

---

## 6. Padrão Strategy de Resultados

O sistema usa o padrão de projeto **Strategy** para desacoplar as operações de análise por tipo de item. Cada `TipoItemAnaliseTecnica` possui uma implementação concreta da interface `ResultadoAnaliseTecnicaStrategy`.

### 6.1 Interface `ResultadoAnaliseTecnicaStrategy`

```java
public interface ResultadoAnaliseTecnicaStrategy {

    TipoItemAnaliseTecnica getTipoItem();

    // Subquery JPQL que retorna o id do licenciamento a partir do id do item analisado
    String getSubqueryLicenciamento();

    // Valida regras específicas do item (ex.: existência, integridade)
    void validar(ResultadoAtecRequest request);

    // Consulta resultado existente para (idAnaliseTecnica, idItemAnalisado)
    ResultadoAtec consultar(ResultadoAtecRequest request);

    // Inclui novo resultado
    ResultadoAtec incluir(ResultadoAtecRequest request);

    // Edita resultado existente
    ResultadoAtec editar(ResultadoAtecRequest request);

    // Inclui justificativas de NCS vinculadas ao resultado
    void incluirJustificativas(List<JustificativaNcsRequest> justificativas, ResultadoAtec resultado);

    // Exclui justificativas vinculadas ao resultado
    void excluirJustificativas(Long idResultado);

    // Remove o resultado (e suas justificativas)
    void excluir(ResultadoAtecRequest request);

    // Valida que a quantidade de itens analisados está correta para emissão de CA ou CIA
    void validarQuantidadeItensAnalisados(AnaliseTecnica analise);

    // Valida que todos os itens estão aprovados (para CA)
    void validarItensAprovados(AnaliseTecnica analise);

    // Verifica se existe pelo menos um item reprovado (para CIA)
    boolean possuiItensReprovado(AnaliseTecnica analise);

    // Lista as inconformidades para compor o documento CIA
    List<InconformidadeDTO> listarInconformidades(AnaliseTecnica analise);

    // Popula os resultados no DTO de consulta
    void popularResultados(AnaliseTecnica analise, AnaliseTecnicaDetalheResponse response);
}
```

### 6.2 `ResultadoAnaliseTecnicaStrategyResolver`

Componente Spring (`@Component`) que centraliza a resolução da strategy correta:

```java
@Component
public class ResultadoAnaliseTecnicaStrategyResolver {

    private final Map<TipoItemAnaliseTecnica, ResultadoAnaliseTecnicaStrategy> strategies;

    public ResultadoAnaliseTecnicaStrategyResolver(List<ResultadoAnaliseTecnicaStrategy> strategyList) {
        this.strategies = strategyList.stream()
            .collect(Collectors.toMap(ResultadoAnaliseTecnicaStrategy::getTipoItem, Function.identity()));
    }

    public ResultadoAnaliseTecnicaStrategy getStrategy(TipoItemAnaliseTecnica tipo) {
        return Optional.ofNullable(strategies.get(tipo))
            .orElseThrow(() -> new IllegalArgumentException("Strategy não encontrada: " + tipo));
    }
}
```

### 6.3 Implementações esperadas (uma por tipo de item)

| Classe | Tipo |
|---|---|
| `ResultadoAtecRTStrategy` | `RT` |
| `ResultadoAtecRUStrategy` | `RU` |
| `ResultadoAtecProprietarioStrategy` | `PROPRIETARIO` |
| `ResultadoAtecTipoEdificacaoStrategy` | `TIPO_EDIFICACAO` |
| `ResultadoAtecOcupacaoStrategy` | `OCUPACAO` |
| `ResultadoAtecIsolamentoRiscoStrategy` | `ISOLAMENTO_RISCO` |
| `ResultadoAtecGeralStrategy` | `GERAL` |
| `ResultadoAtecMedidaSegurancaStrategy` | `MEDIDA_SEGURANCA` |
| `ResultadoAtecMedidaSegurancaOutraStrategy` | `MEDIDA_SEGURANCA_OUTRA` |
| `ResultadoAtecRiscoEspecificoStrategy` | `RISCO_ESPECIFICO` |
| `ResultadoAtecElementoGraficoStrategy` | `ELEMENTO_GRAFICO` |

---

## 7. Geração de Documentos PDF

### 7.1 Documentos gerados no P04

| Documento | Nome do arquivo | Momento de geração | Autenticado? |
|---|---|---|---|
| Rascunho CIA | (em memória, não persistido) | `GET /rascunho-cia` | Não |
| CIA definitivo | `cia_analise_tecnica.pdf` | `POST /cia` | Sim |
| Rascunho CA | (em memória, não persistido) | `GET /rascunho-ca` | Não |
| CA novo (edificação a construir) | `ca_nova_analise_tecnica.pdf` | `POST /homologacao/deferir` (PPCI) | Sim |
| CA existente (edificação existente) | `ca_existente_analise_tecnica.pdf` | `POST /homologacao/deferir` (PPCI) | Sim |
| APPCI | `appci_analise_tecnica.pdf` | `POST /homologacao/deferir` (PSPCIM) | Sim |
| Documento Complementar | `DocComplementar.pdf` | `POST /homologacao/deferir` (PSPCIM) | Sim |

### 7.2 Código de autenticação

Todo documento autenticado possui um código único gerado pelo `ArquivoService.gerarCodigoAutenticacao()`. Este código é impresso no rodapé do PDF e permite verificação de autenticidade em portal público. Implementação sugerida: UUID v4 ou código alfanumérico de 16 caracteres.

### 7.3 Conteúdo mínimo do CIA

- Número do PPCI
- Dados do licenciamento (endereço, estabelecimento, tipo de edificação)
- Nome do Responsável Técnico
- Data da análise
- Lista de inconformidades por categoria (`TipoItemAnaliseTecnica`), na ordem definida em `TIPO_ITENS_ORDENADOS`
- Campo "Demais inconformidades" (se `outra_inconformidade` preenchida)
- Código de autenticidade
- Assinatura/identificação do analista

### 7.4 Conteúdo mínimo do CA

- Número do PPCI
- Dados do estabelecimento e edificação
- Declaração de conformidade
- Validade do certificado
- Código de autenticidade
- Assinatura do coordenador homologador

### 7.5 Conteúdo mínimo do APPCI

- Número do APPCI
- Dados do estabelecimento (PSPCIM)
- Prazo de validade (calculado por `CalculoValidadeAppciService`)
- Código de autenticidade

### 7.6 Armazenamento (MinIO)

Todos os PDFs autenticados são armazenados no MinIO via `ObjectStorageService`:

```java
public interface ObjectStorageService {
    String store(InputStream content, String bucketName, String objectName);
    InputStream retrieve(String bucketName, String objectKey);
    void delete(String bucketName, String objectKey);
}
```

O `objectKey` retornado é persistido no campo `object_key` da tabela `CBM_ARQUIVO`.

Bucket sugerido: `solcbm-documentos-analise`.

---

## 8. API REST

### 8.1 Tabela completa de endpoints

| Método | Endpoint | Permissão | Descrição |
|---|---|---|---|
| `POST` | `/api/v1/analises-tecnicas/distribuicao` | `DISTRIBUICAOANALISE:DISTRIBUIR` | Distribui licenciamentos para analistas |
| `DELETE` | `/api/v1/analises-tecnicas/{idAnalise}/distribuicao` | `DISTRIBUICAOANALISE:CANCELAR` | Cancela distribuição (análise volta a AGUARDANDO_DISTRIBUICAO) |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/pendentes` | `DISTRIBUICAOANALISE:LISTAR` | Lista licenciamentos pendentes de distribuição (paginado) |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/analistas` | `DISTRIBUICAOANALISE:LISTAR` | Lista analistas disponíveis do batalhão do coordenador |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/analistas-por-usuario/{idUsuario}` | `DISTRIBUICAOANALISE:CONSULTAR` | Lista análises de um analista específico |
| `GET` | `/api/v1/analises-tecnicas` | `ANALISETECNICA:LISTAR` | Lista análises em `EM_ANALISE` do analista logado (paginado) |
| `GET` | `/api/v1/analises-tecnicas/{idAnalise}` | `ANALISETECNICA:ANALISAR` | Consulta análise com todos os resultados por item |
| `PUT` | `/api/v1/analises-tecnicas/{idAnalise}/resultados` | `ANALISETECNICA:ANALISAR` | Salva (inclui ou altera) resultado de um item |
| `DELETE` | `/api/v1/analises-tecnicas/{idAnalise}/resultados/{idResultado}` | `ANALISETECNICA:ANALISAR` | Remove resultado de um item |
| `PUT` | `/api/v1/analises-tecnicas/{idAnalise}/outra-inconformidade` | `ANALISETECNICA:ANALISAR` | Salva texto de inconformidade não padronizada |
| `PUT` | `/api/v1/analises-tecnicas/{idAnalise}/outras-medidas-seguranca` | `ANALISETECNICA:ANALISAR` | Salva justificativas de outras medidas de segurança |
| `DELETE` | `/api/v1/analises-tecnicas/{idAnalise}/outras-medidas-seguranca` | `ANALISETECNICA:ANALISAR` | Remove justificativas de outras medidas de segurança |
| `GET` | `/api/v1/analises-tecnicas/{idAnalise}/rascunho-cia` | `ANALISETECNICA:ANALISAR` | Gera e retorna (sem persistir) o rascunho do CIA em PDF |
| `GET` | `/api/v1/analises-tecnicas/{idAnalise}/rascunho-ca` | interno | Gera e retorna (sem persistir) o rascunho do CA em PDF |
| `POST` | `/api/v1/analises-tecnicas/{idAnalise}/cia` | `ANALISETECNICA:ANALISAR` | Emite CIA definitivo — análise vai para REPROVADO |
| `POST` | `/api/v1/analises-tecnicas/{idAnalise}/ca` | `ANALISETECNICA:ANALISAR` | Envia análise para homologação (EM_APROVACAO) |
| `GET` | `/api/v1/analises-tecnicas/homologacao` | `ANALISETECNICA:HOMOLOGAR` | Lista análises em EM_APROVACAO pendentes de homologação |
| `GET` | `/api/v1/analises-tecnicas/{idAnalise}/homologacao` | `ANALISETECNICA:HOMOLOGAR` | Consulta análise completa para revisão do coordenador |
| `POST` | `/api/v1/analises-tecnicas/{idAnalise}/homologacao/deferir` | `ANALISETECNICA:HOMOLOGAR` | Defere homologação — gera CA/APPCI definitivo |
| `POST` | `/api/v1/analises-tecnicas/{idAnalise}/homologacao/indeferir` | `ANALISETECNICA:HOMOLOGAR` | Indefere homologação — devolve ao analista |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/analistas-vistoria` | `VISTORIA:VISTORIAR` | Lista analistas disponíveis para vistoria (uso de processo P07) |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/analistas-fact` | `DISTRIBUICAOANALISE:LISTAR` | Lista analistas de FACT do batalhão |
| `GET` | `/api/v1/analises-tecnicas/distribuicao/analistas-recurso` | `DISTRIBUICAOANALISE:LISTAR` | Lista analistas para análise de recurso |

### 8.2 Padrão de respostas

**Sucesso (operações de escrita):** HTTP 200 com body `{ "id": <idAnaliseTecnica> }`

**Erros de validação de negócio:** HTTP 406 `Not Acceptable` com body:
```json
{ "mensagem": "licenciamento.distribuicao.batalhao", "timestamp": "2026-03-09T10:30:00Z" }
```

**Não autorizado (analista errado):** HTTP 403 `Forbidden`

**Não encontrado:** HTTP 404 `Not Found`

---

## 9. Segurança e Controle de Acesso

### 9.1 Autenticação

Toda requisição ao backend deve conter o Bearer Token JWT emitido pelo Keycloak. O Spring Security valida a assinatura e extrai as claims automaticamente via `JwtAuthenticationConverter`.

Substituição direta do `SessionMB.getUser()` do legado:

```java
// Legado (PROCERGS)
String idUsuario = sessionMB.getUser().getId();
String nomeUsuario = sessionMB.getUser().getNome();

// Moderno (Spring Security + Keycloak)
Authentication auth = SecurityContextHolder.getContext().getAuthentication();
Jwt jwt = (Jwt) auth.getPrincipal();
String idUsuario = jwt.getSubject();                    // claim "sub"
String nomeUsuario = jwt.getClaimAsString("name");      // claim "name"
```

### 9.2 Autorização por permissão

Substituição do `@Permissao(objeto, acao)` por `@PreAuthorize`:

```java
// Legado
@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")

// Moderno
@PreAuthorize("hasAuthority('ANALISETECNICA:ANALISAR')")
```

As autoridades são mapeadas dos roles Keycloak via `JwtAuthenticationConverter` customizado. O Keycloak deve ter os seguintes roles configurados:

| Role Keycloak | Authorities Spring Security |
|---|---|
| `cbm_analista` | `ANALISETECNICA:ANALISAR`, `ANALISETECNICA:LISTAR` |
| `cbm_coordenador` | `DISTRIBUICAOANALISE:DISTRIBUIR`, `DISTRIBUICAOANALISE:LISTAR`, `DISTRIBUICAOANALISE:CONSULTAR`, `DISTRIBUICAOANALISE:CANCELAR`, `ANALISETECNICA:HOMOLOGAR` |
| `cbm_admin` | Todos os anteriores |

### 9.3 Validação de ownership (analista vs. análise)

Regra crítica de segurança: **somente o analista designado para a análise pode registrar resultados, emitir CIA ou emitir CA**. Esta validação é realizada na camada de serviço, não apenas na camada de controle de acesso:

```java
private void validarAnalistaLogado(AnaliseTecnica analise) {
    String idLogado = getCurrentUserId(); // do JWT
    if (!analise.getIdUsuarioAnalista().equals(idLogado)) {
        throw new ResponseStatusException(HttpStatus.FORBIDDEN,
            messageSource.getMessage("analisetecnica.usuario.naoautorizado", null, locale));
    }
}
```

### 9.4 Validação de competência territorial (coordenador)

O coordenador só pode visualizar ou agir sobre licenciamentos cujas cidades pertencem ao seu batalhão. Esta validação é feita consultando a tabela `cidade_batalhao` com o batalhão extraído do perfil do coordenador no Keycloak (`batalhao` claim customizada).

---

## 10. Notificações e Marcos (TipoMarco)

### 10.1 Registro de marcos

Todo marco é registrado via `LicenciamentoMarcoService` que cria um registro em `CBM_LICENCIAMENTO_MARCO`:

```java
public interface LicenciamentoMarcoService {
    void incluir(TipoMarco tipoMarco, Licenciamento licenciamento);
    void incluirComArquivo(TipoMarco tipoMarco, Licenciamento licenciamento, Arquivo arquivo);
}
```

### 10.2 Marcos gerados por etapa

| Etapa | Marco registrado | Arquivo vinculado? |
|---|---|---|
| Distribuição | `DISTRIBUICAO_ANALISE` | Não |
| Cancelamento de distribuição | `CANCELA_DISTRIBUICAO_ANALISE` | Não |
| CA (envio homologação) — PPCI | `ATEC_CA` | Não |
| CA (envio homologação) — PSPCIM | `ATEC_APPCI` | Não |
| CIA emitida | `ATEC_CIA` | Sim (CIA PDF) |
| Homologação deferida — PPCI | `HOMOLOG_ATEC_DEFERIDO` | Sim (CA PDF) |
| Homologação deferida — PSPCIM | `HOMOLOG_ATEC_APPCI` | Sim (APPCI PDF) |
| Doc. complementar — PSPCIM | `EMISSAO_DOC_COMPLEMENTAR` | Sim (PDF complementar) |
| Homologação indeferida | `HOMOLOG_ATEC_INDEFERIDO` | Não |

### 10.3 Notificações por e-mail / portal (recomendado)

Eventos que devem disparar notificação ao RT/RU/proprietário:

| Evento | Destinatário | Assunto sugerido |
|---|---|---|
| CIA emitida | RT, RU, Proprietário | "Resultado de análise — Comunicado de Inconformidade emitido" |
| CA emitido (homologação deferida) | RT, RU, Proprietário | "Análise técnica aprovada — Certificado disponível" |

---

## 11. Auditoria

### 11.1 Hibernate Envers

As seguintes entidades devem ser anotadas com `@Audited` (Hibernate Envers):

- `AnaliseTecnica`
- `ResultadoAtecRT`, `ResultadoAtecRU`, `ResultadoAtecProprietario`, e demais subclasses
- `JustificativaNcs`
- `JustificativaAtecOutraMedidaSeguranca`

Cada entidade auditada terá uma tabela espelho com sufixo `_AUD` e os campos padrão do Envers: `REV`, `REVTYPE`, `REVEND`.

### 11.2 Histórico de elementos gráficos

O serviço `ElementoGraficoHistoricoService.incluirHistoricoElementoGrafico()` deve ser chamado ao finalizar uma CIA ou CA. Ele persiste o estado dos elementos gráficos do projeto analisado, permitindo rastrear quais versões do desenho foram avaliadas em cada análise.

---

## 12. Tratamento de Erros

### 12.1 Exceções de domínio

Criar hierarquia de exceções de domínio para substituir `WebApplicationRNException`:

```java
// Exceção base de domínio
public class SolCbmException extends RuntimeException {
    private final String mensagemChave;
    public SolCbmException(String mensagemChave) { this.mensagemChave = mensagemChave; }
    public String getMensagemChave() { return mensagemChave; }
}

// Variantes específicas
public class ValidacaoNegocioException extends SolCbmException { ... }   // → HTTP 406
public class RecursoNaoEncontradoException extends SolCbmException { ... } // → HTTP 404
public class AcessoNegadoException extends SolCbmException { ... }        // → HTTP 403
```

### 12.2 Handler global

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ValidacaoNegocioException.class)
    public ResponseEntity<ErroResponse> handleValidacao(ValidacaoNegocioException ex) {
        String mensagem = messageSource.getMessage(ex.getMensagemChave(), null, locale);
        return ResponseEntity.status(HttpStatus.NOT_ACCEPTABLE)
            .body(new ErroResponse(mensagem));
    }

    @ExceptionHandler(AcessoNegadoException.class)
    public ResponseEntity<ErroResponse> handleAcesso(AcessoNegadoException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
            .body(new ErroResponse("Acesso não autorizado."));
    }

    @ExceptionHandler(RecursoNaoEncontradoException.class)
    public ResponseEntity<ErroResponse> handleNaoEncontrado(RecursoNaoEncontradoException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
}
```

### 12.3 Mensagens de validação mapeadas

| Chave da mensagem | Situação |
|---|---|
| `licenciamento.distribuicao.status` | Licenciamento não está em situação distribuível |
| `licenciamento.distribuicao.batalhao` | Cidade do licenciamento não pertence ao batalhão do analista |
| `analisetecnica.usuario.batalhao.naoencontrado` | Analista não possui batalhão cadastrado |
| `analisetecnica.usuario.naoautorizado` | Analista logado não é o designado para a análise |
| `analisetecnica.status.inconformidades` | Tentativa de emitir CA com `outra_inconformidade` preenchida |
| `analisetecnica.status.naoreprovada` | CIA sem itens reprovados nem `outra_inconformidade` |
| `analisetecnica.itens.pendentes` | Não foram analisados todos os itens obrigatórios |
| `analisetecnica.itens.reprovados` | Tentativa de emitir CA com itens reprovados |
| `justificativa.ncs.obrigatoria` | Item reprovado sem justificativa de NCS |
| `operador.sem.batalhao` | Coordenador logado não possui batalhão associado |

---

## Apêndice A — Diagrama de transições de estado

### `AnaliseTecnica.status`

```
                [Distribuição]
                      |
                      v
              [ EM_ANALISE ] <------ (Indeferimento de homologação)
              /           \
  [Emitir CIA]             [Emitir CA]
      |                        |
      v                        v
 [ REPROVADO ]          [ EM_APROVACAO ]
  (terminal)            /             \
                  [Deferir]         [Indeferir]
                      |
                      v
                 [ APROVADO ]
                  (terminal)

  [ EM_ANALISE ] --[Cancelamento Adm.]--> [ CANCELADA ] (terminal)
```

### `Licenciamento.situacao` no contexto P04

```
[AGUARDANDO_DISTRIBUICAO]
         |
         v (Distribuição)
    [EM_ANALISE]
         |
         +---> CIA --> [AGUARDANDO_CIENCIA] (P05)
         |
         +---> CA + Deferir --> [CA] (PPCI) ou [ALVARA_VIGENTE] (PSPCIM)
         |
         +---> Cancelamento --> [AGUARDANDO_DISTRIBUICAO]
```

---

## Apêndice B — Estrutura de pacotes recomendada

```
com.cbmrs.sol
└── analise
    └── tecnica
        ├── controller
        │   ├── AnaliseTecnicaDistribuicaoController.java
        │   ├── AnaliseTecnicaAnaliseController.java
        │   └── AnaliseTecnicaHomologacaoController.java
        ├── service
        │   ├── AnaliseTecnicaDistribuicaoService.java
        │   ├── AnaliseTecnicaResultadoService.java
        │   ├── AnaliseTecnicaCiaService.java
        │   ├── AnaliseTecnicaCaService.java
        │   ├── AnaliseTecnicaHomologacaoService.java
        │   ├── AnaliseTecnicaCancelamentoService.java
        │   ├── AnaliseTecnicaConsultaService.java
        │   └── ResultadoAnaliseTecnicaExclusaoService.java
        ├── strategy
        │   ├── ResultadoAnaliseTecnicaStrategy.java          (interface)
        │   ├── ResultadoAnaliseTecnicaStrategyResolver.java
        │   ├── ResultadoAtecRTStrategy.java
        │   ├── ResultadoAtecRUStrategy.java
        │   ├── ResultadoAtecProprietarioStrategy.java
        │   ├── ResultadoAtecTipoEdificacaoStrategy.java
        │   ├── ResultadoAtecOcupacaoStrategy.java
        │   ├── ResultadoAtecIsolamentoRiscoStrategy.java
        │   ├── ResultadoAtecGeralStrategy.java
        │   ├── ResultadoAtecMedidaSegurancaStrategy.java
        │   ├── ResultadoAtecMedidaSegurancaOutraStrategy.java
        │   ├── ResultadoAtecRiscoEspecificoStrategy.java
        │   └── ResultadoAtecElementoGraficoStrategy.java
        ├── documento
        │   ├── CiaDocumentoService.java
        │   ├── CaNovoDocumentoService.java
        │   ├── CaExistenteDocumentoService.java
        │   ├── AppciDocumentoService.java
        │   └── DocComplementarService.java
        ├── domain
        │   ├── AnaliseTecnica.java                  (@Entity)
        │   ├── ResultadoAtec.java                   (@MappedSuperclass)
        │   ├── ResultadoAtecRT.java                 (@Entity)
        │   ├── ResultadoAtecRU.java
        │   ├── ResultadoAtecProprietario.java
        │   ├── ResultadoAtecTipoEdificacao.java
        │   ├── ResultadoAtecOcupacao.java
        │   ├── ResultadoAtecIsolamentoRisco.java
        │   ├── ResultadoAtecGeral.java
        │   ├── ResultadoAtecMedidaSeguranca.java
        │   ├── ResultadoAtecRiscoEspecifico.java
        │   ├── ResultadoAtecElementoGrafico.java
        │   ├── JustificativaNcs.java
        │   └── JustificativaAtecOutraMedidaSeguranca.java
        ├── repository
        │   ├── AnaliseTecnicaRepository.java
        │   └── ResultadoAtec*Repository.java (um por tipo)
        ├── dto
        │   ├── request
        │   │   ├── DistribuicaoAnaliseTecnicaRequest.java
        │   │   ├── ResultadoAtecRequest.java
        │   │   ├── JustificativaNcsRequest.java
        │   │   └── IndeferirHomologacaoRequest.java
        │   └── response
        │       ├── AnaliseTecnicaListagemResponse.java
        │       ├── AnaliseTecnicaDetalheResponse.java
        │       ├── LicenciamentoDistribuicaoResponse.java
        │       ├── AnalistaDisponivelResponse.java
        │       └── InconformidadeResponse.java
        └── enumeration
            ├── StatusAnaliseTecnica.java
            ├── TipoItemAnaliseTecnica.java
            └── StatusResultadoAtec.java
```


---

## 13. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprints 01–04 (ID1301, Demandas 6, 13, 14, 24) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022.  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P04.

---

### RN-P04-N1 — Exibir Nome do Analista Responsável nos Marcos do Licenciamento 🟠 P04-M1

**Prioridade:** Alta  
**Origem:** ID1301 / Demanda 13 — Sprint 03 Hammer

**Descrição:** Após a distribuição da análise técnica a um bombeiro analista, a coluna **"Complemento"** na consulta de Marcos do licenciamento deve exibir o nome completo do bombeiro alocado, além da data/hora já exibida.

**Mudança na Service Task de distribuição (`P04_ST_Distribuir`):**

```java
// TrocaEstadoMarcoRN.java — método registrarDistribuicao()
public void registrarDistribuicao(Licenciamento lic, Usuario analista) {
    Marco marco = new Marco();
    marco.setTipoMarco(TipoMarco.DISTRIBUICAO_ANALISE_TECNICA);
    marco.setDtRegistro(LocalDateTime.now());
    marco.setDsComplemento(
        "Analista responsável: " + analista.getNomeCompleto() +
        " | Matrícula: " + analista.getMatricula()
    );
    marco.setIdLicenciamento(lic.getId());
    marcoRepository.save(marco);
}
```

**Atualização do endpoint `GET /licenciamentos/{id}/marcos`:**

```json
{
  "marcos": [
    {
      "tipo": "DISTRIBUICAO_ANALISE_TECNICA",
      "dtRegistro": "2026-03-20T10:30:00",
      "dsComplemento": "Analista responsável: Cap. João da Silva | Matrícula: 12345"
    }
  ]
}
```

**DDL — garantir campo `ds_complemento` existe:**
```sql
ALTER TABLE cbm_marco_processo
    ADD COLUMN IF NOT EXISTS ds_complemento VARCHAR(500);
```

**Critérios de Aceitação:**
- [ ] CA-P04-N1a: Marco `DISTRIBUICAO_ANALISE_TECNICA` exibe nome do analista no campo `dsComplemento`
- [ ] CA-P04-N1b: Endpoint `GET /licenciamentos/{id}/marcos` retorna o campo `complemento` populado
- [ ] CA-P04-N1c: Nome formatado com matrícula: "Analista responsável: {nome} | Matrícula: {matricula}"

---

### RN-P04-N2 — Inviabilidade Técnica para Edificações do Grupo M-5 🟠 P04-M2

**Prioridade:** Alta  
**Origem:** Demanda 6 — Sprint 02 Hammer

**Descrição:** O processo de análise deve aceitar alegação de **inviabilidade técnica** especificamente para itens do **grupo M-5**, com validações próprias desse grupo (diferentes das validações dos demais grupos).

**Novo gateway no fluxo de análise — após decisão pós-checklist:**

```
[GW] Item com inviabilidade técnica?
        │
   ┌────┴──────────────────────┐
   │ SIM — Grupo M-5            │ SIM — Outros grupos
   │                            │
   ▼                            ▼
Validações específicas M-5    Validações padrão de
(RRT/ART obrigatório,         inviabilidade técnica
 laudo técnico específico)
        │                           │
        └──────────────┬────────────┘
                       ▼
              Gerar CIA de inviabilidade
              técnica com grupo indicado
```

**Enum atualizado:**
```java
public enum GrupoInviabilidade {
    PADRAO,         // demais grupos
    GRUPO_M5        // validações específicas para M-5
}
```

**Validações específicas M-5:**
```java
public void validarInviabilidadeM5(InviabilidadeTecnicaRequest req) {
    // RRT/ART obrigatório para M-5
    if (req.getIdRrtArt() == null) {
        throw new ValidationException("RRT/ART é obrigatório para inviabilidade técnica Grupo M-5");
    }
    // Laudo técnico específico obrigatório
    if (req.getIdLaudoTecnicoM5() == null) {
        throw new ValidationException("Laudo técnico específico é obrigatório para Grupo M-5");
    }
}
```

**Critérios de Aceitação:**
- [ ] CA-P04-N2a: Item Grupo M-5 pode ter inviabilidade técnica declarada com validações específicas
- [ ] CA-P04-N2b: RRT/ART e laudo técnico específico são obrigatórios para M-5
- [ ] CA-P04-N2c: CIA gerada registra o grupo de inviabilidade (M-5 ou padrão)
- [ ] CA-P04-N2d: Inviabilidade M-5 sem RRT/ART retorna erro 422

---

### RN-P04-N3 — Reanálise Restrita aos Itens Reprovados na CIA Anterior 🔴 P04-M3

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C2 / RT de Implantação SOL-CBMRS item 6.3.7.2.2

**Descrição:** A partir da **2ª análise**, o analista deve verificar apenas os itens **reprovados na CIA anterior**. O sistema deve carregar automaticamente a lista filtrada e impedir avaliação de itens não presentes na CIA vigente.

**Novo endpoint para listar itens da CIA vigente:**
```
GET /api/v1/analises/{id}/itens-cia
```

Retorna apenas os itens reprovados na CIA mais recente daquela análise.

**Gateway após distribuição:**

```java
// AnaliseTecnicaService.java — carregarItensParaAnalise()
public List<ItemAnaliseTecnica> carregarItens(AnaliseTecnica analise) {
    if (analise.getLicenciamento().getNrAnalise() > 1) {
        // Reanálise: filtrar apenas itens da CIA vigente
        return itemAnaliseTecnicaRepository
            .findItensCiaVigente(analise.getLicenciamento().getIdCiaVigente());
    }
    // Primeira análise: todos os itens aplicáveis
    return itemAnaliseTecnicaRepository
        .findAllByTipoOcupacao(analise.getLicenciamento().getTpGrupoOcupacao());
}
```

**Proteção via API:**
```java
@PostMapping("/{idAnalise}/itens/{idItem}/avaliar")
public ResponseEntity<Void> avaliarItem(@PathVariable UUID idAnalise, @PathVariable UUID idItem, ...) {
    if (!analiseTecnicaService.isItemPermitido(idAnalise, idItem)) {
        throw new BusinessException("Item não consta na CIA vigente desta reanálise");
    }
    ...
}
```

**Critérios de Aceitação:**
- [ ] CA-P04-N3a: Reanálise (nr_analise > 1) exibe apenas itens da CIA vigente para o analista
- [ ] CA-P04-N3b: `GET /analises/{id}/itens-cia` retorna apenas itens reprovados da CIA
- [ ] CA-P04-N3c: Tentativa de avaliar item não listado na CIA via API retorna 422
- [ ] CA-P04-N3d: Primeira análise não é afetada — todos os itens aplicáveis são exibidos

---

### RN-P04-N4 — Distribuição Automática com Critério FIFO (Ordem Cronológica de Protocolo) 🔴 P04-M4

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma A2 / RT de Implantação SOL-CBMRS item 13.2

**Descrição:** A RT de Implantação exige que licenciamentos sejam analisados em **ordem cronológica de protocolo (FIFO)**. A distribuição manual pura deve ser substituída por um sistema de sugestão automática FIFO, com o coordenador confirmando ou substituindo com justificativa obrigatória.

**Mudança no fluxo — antes da UserTask de distribuição manual:**

```
[Service Task] SugerirDistribuicaoFIFO
        │
        ├── Query: próximo licenciamento da fila (FIFO por dt_protocolo)
        ├── Query: analista com menor carga ativa (critério de desempate)
        │
        ▼
[User Task — Coordenador] Confirmar ou substituir sugestão
        │
   ┌────┴────────────────────────────────────────┐
   │ Confirma sugestão                           │ Substitui sugestão
   │                                             │
   ▼                                             ▼
Distribuir conforme sugerido              Exigir justificativa obrigatória
                                          Registrar em CBM_HISTORICO_PRIORIZACAO
```

**Query FIFO:**
```sql
-- Próximo licenciamento na fila FIFO
SELECT l.id, l.nr_protocolo, l.dt_protocolo
FROM cbm_licenciamento l
WHERE l.tp_status = 'AGUARDANDO_DISTRIBUICAO'
  AND l.tp_tipo_analise = :tipoAnalise
ORDER BY l.dt_protocolo ASC
LIMIT 1;
```

**Query menor carga:**
```sql
-- Analista com menor carga ativa
SELECT u.id, u.nm_usuario, COUNT(a.id) as qtd_analises_ativas
FROM cbm_usuario u
LEFT JOIN cbm_analise_tecnica a ON a.id_analista = u.id 
    AND a.tp_status IN ('EM_ANALISE', 'DISTRIBUIDA')
WHERE u.tp_perfil = 'FISCAL'
  AND u.fg_ativo = TRUE
GROUP BY u.id, u.nm_usuario
ORDER BY qtd_analises_ativas ASC
LIMIT 1;
```

**Nova tabela de histórico de priorização:**
```sql
CREATE TABLE cbm_historico_priorizacao (
    id BIGSERIAL PRIMARY KEY,
    id_licenciamento BIGINT NOT NULL REFERENCES cbm_licenciamento(id),
    id_usuario_coordenador BIGINT NOT NULL REFERENCES cbm_usuario(id),
    dt_alteracao TIMESTAMP NOT NULL DEFAULT NOW(),
    nr_protocolo_priorizado VARCHAR(30) NOT NULL,
    nr_protocolo_sugerido VARCHAR(30) NOT NULL,
    ds_justificativa TEXT NOT NULL
);
```

**Autorização:** Somente perfil `CHEFE_SSEG_BBM` pode alterar a ordem de prioridade.

**Critérios de Aceitação:**
- [ ] CA-P04-N4a: Sistema sugere automaticamente o próximo licenciamento por ordem de `dt_protocolo`
- [ ] CA-P04-N4b: Coordenador pode confirmar a sugestão com um clique
- [ ] CA-P04-N4c: Coordenador pode substituir a sugestão, mas deve fornecer justificativa obrigatória
- [ ] CA-P04-N4d: Justificativa registrada em `cbm_historico_priorizacao` com data/hora e usuário
- [ ] CA-P04-N4e: Tentativa de alterar ordem por perfil diferente de `CHEFE_SSEG_BBM` retorna 403

---

### RN-P04-N5 — Cobrança de Medida de Segurança com Inviabilidade Técnica Aprovada 🟡 P04-M5

**Prioridade:** Média  
**Origem:** Demanda 14 — Sprint 02 Hammer

**Descrição:** O fluxo de cobrança de taxa para medida de segurança **não deve cobrar** a taxa correspondente quando houve aprovação de inviabilidade técnica para aquela medida específica.

**Regra:**
```java
// MedidaSegurancaTaxaRN.java
public BigDecimal calcularTaxaMedidaSeguranca(ItemAnaliseTecnica item) {
    if (item.getFgInviabilidadeTecnicaAprovada()) {
        return BigDecimal.ZERO; // isento por inviabilidade aprovada
    }
    return tabelaTaxas.getValor(item.getTpMedidaSeguranca());
}
```

**Critérios de Aceitação:**
- [ ] CA-P04-N5a: Medida com inviabilidade técnica aprovada não gera cobrança de taxa
- [ ] CA-P04-N5b: Relatório financeiro indica "Isenção por inviabilidade técnica aprovada" para essas medidas

---

### RN-P04-N6 — Coluna "Descrição" no Histórico de Documentos 🟢 P04-M6

**Prioridade:** Baixa  
**Origem:** Demanda 24 — Sprint 04 Hammer

**Descrição:** Adicionar coluna **"Descrição"** na tabela de histórico de documentos do licenciamento para maior clareza sobre cada entrada.

**DDL:**
```sql
ALTER TABLE cbm_documento_licenciamento
    ADD COLUMN IF NOT EXISTS ds_descricao VARCHAR(255);
```

**Response atualizado — endpoint `GET /licenciamentos/{id}/documentos`:**
```json
{
  "documentos": [
    {
      "id": "uuid",
      "tipo": "APPCI",
      "dtEmissao": "2026-03-20",
      "dsDescricao": "APPCI emitido após análise aprovada em 1ª instância",
      "urlDownload": "/documentos/uuid/download"
    }
  ]
}
```

**Critérios de Aceitação:**
- [ ] CA-P04-N6a: Coluna "Descrição" aparece na tela de histórico de documentos
- [ ] CA-P04-N6b: Coluna exibe descrição legível para cada tipo de documento

---

### Resumo das Mudanças P04 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P04-M3 | RN-P04-N3 | Reanálise restrita aos itens da CIA anterior (OBRIGATÓRIO) | 🔴 Crítica |
| P04-M4 | RN-P04-N4 | Distribuição FIFO com sugestão automática (OBRIGATÓRIO) | 🔴 Crítica |
| P04-M1 | RN-P04-N1 | Nome do analista na coluna Complemento dos marcos | 🟠 Alta |
| P04-M2 | RN-P04-N2 | Inviabilidade técnica para Grupo M-5 com validações específicas | 🟠 Alta |
| P04-M5 | RN-P04-N5 | Sem cobrança de taxa em medida com inviabilidade aprovada | 🟡 Média |
| P04-M6 | RN-P04-N6 | Coluna "Descrição" no histórico de documentos | 🟢 Baixa |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 01–04 + Normas RTCBMRS*
