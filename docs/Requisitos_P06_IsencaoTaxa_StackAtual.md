# Requisitos — P06: Solicitação de Isenção de Taxa
## Stack Atual Java EE (sem alteração tecnológica)

**Versão:** 1.0
**Data:** 2026-03-10
**Projeto:** SOL — Sistema Online de Licenciamento / CBM-RS
**Processo:** P06 — Solicitação de Isenção de Taxa

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica Atual](#2-stack-tecnológica-atual)
3. [Modelo de Domínio — Enumerações](#3-modelo-de-domínio--enumerações)
4. [Modelo de Dados — Entidades ED (JPA)](#4-modelo-de-dados--entidades-ed-jpa)
5. [Camada de Dados — BDs (Repositories)](#5-camada-de-dados--bds-repositories)
6. [Regras de Negócio — RNs (EJB Stateless)](#6-regras-de-negócio--rns-ejb-stateless)
7. [Validações e Exceções](#7-validações-e-exceções)
8. [API REST — Endpoints JAX-RS](#8-api-rest--endpoints-jax-rs)
9. [Modelos de Transferência — DTOs](#9-modelos-de-transferência--dtos)
10. [Segurança — @Permissao e SOE](#10-segurança--permissao-e-soe)
11. [Integração com Alfresco — Arquivo de Comprovante](#11-integração-com-alfresco--arquivo-de-comprovante)
12. [Notificações — E-mail via SOE](#12-notificações--e-mail-via-soe)
13. [Máquinas de Estado](#13-máquinas-de-estado)
14. [Esquema do Banco de Dados](#14-esquema-do-banco-de-dados)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O Processo 06 gerencia a **solicitação, análise e concessão ou negação de isenção da taxa de análise** no sistema SOL. Existem dois sub-processos distintos, cada um com entidades, fluxos e endpoints próprios:

| Sub-processo | Objeto | Ator principal | Descrição resumida |
|---|---|---|---|
| **P06-A** | Licenciamento (PPCI/APPCI) | Cidadão/RT → ADM CBM-RS | Isenção da taxa de análise do licenciamento principal. Inclui fluxo de renovação de isenção. |
| **P06-B** | FACT (Formulário de Atendimento e Consulta Técnica) | Cidadão → ADM CBM-RS | Isenção da taxa do FACT, seja vinculado a um licenciamento ou avulso. |

Além dos dois sub-processos principais, o P06 abrange:

- **Gestão de comprovantes:** upload, listagem, remoção de documentos probatórios enviados pelo cidadão via Alfresco.
- **Justificativas NCS:** parâmetros configuráveis usados pelo ADM para fundamentar a análise.
- **Reanalise de isenção:** lógica de prazo de 30 dias e limite de primeira correção.
- **Renovação de isenção:** fluxo específico para licenciamentos em fase de vistoria de renovação.

### 1.2 Atores

| Ator | Perfil SOE | Papel no processo |
|---|---|---|
| Cidadão / RT | Qualquer usuário autenticado no SOE | Solicita isenção, envia comprovantes |
| Administrador CBM-RS | Perfil com permissão `ISENCAOTAXA:REVISAR` | Analisa documentação e decide pela concessão ou negação |
| Sistema SOL | Backend EJB | Valida estados, persiste análise, transita estados do licenciamento/FACT, envia notificações |

### 1.3 Pré-condições

**P06-A (Licenciamento):**
- O licenciamento deve estar no status `AGUARDANDO_PAGAMENTO`.
- O campo `situacaoIsencao` deve ser `SOLICITADA` ou `SOLICITADA_RENOV` no momento da análise pelo ADM.

**P06-B (FACT):**
- O FACT deve estar no status `AGUARDANDO_PAGAMENTO_ISENCAO`.
- O campo `isencao` do FACT deve ser `true` (valor `'S'` no banco).

### 1.4 Pós-condições

| Sub-processo | Decisão | Efeito no sistema |
|---|---|---|
| P06-A | Aprovado | `situacaoIsencao = APROVADA`, `indIsencao = true`, `LicenciamentoED.situacao` avança para `AGUARDANDO_DISTRIBUICAO` (ou estado intermediário conforme endereço/inviabilidade) |
| P06-A | Reprovado | `situacaoIsencao = REPROVADA`, cidadão notificado, mantém obrigação de pagamento |
| P06-B | Aprovado | `FactED.isencao = true`, `FactED.situacao = AGUARDANDO_DISTRIBUICAO`, número do FACT gerado |
| P06-B | Reprovado | `FactED.situacao = ISENCAO_REJEITADA` (ou permanece em `AGUARDANDO_PAGAMENTO_ISENCAO`), cidadão notificado |

---

## 2. Stack Tecnológica Atual

| Camada | Tecnologia |
|---|---|
| Servidor de aplicação | WildFly / JBoss (Jakarta EE 8 / Java EE 8) |
| Componentes de negócio | EJB 3.2 `@Stateless` |
| Injeção de dependências | CDI (`@Inject`) |
| Persistência | JPA 2.2 + Hibernate (`@Entity`, `@Audited` via Hibernate Envers) |
| Banco de dados | Relacional (Oracle ou PostgreSQL — via DataSource JNDI) |
| API REST | JAX-RS 2.1 (`@Path`, `@Produces`, `@Consumes`) |
| Autenticação | SOE PROCERGS — filtro `@SOEAuthRest`, sessão via `SessionMB` |
| Autorização | `@Permissao(objeto, acao)` + interceptor `AppInterceptor` |
| Segurança de recurso | `@AutorizaEnvolvido` + `SegurancaEnvolvidoInterceptor` |
| ECM / Arquivos | Alfresco — integrado via `ArquivoRN` (campo `identificadorAlfresco` = nodeRef) |
| Auditoria | Hibernate Envers (`@Audited`) → tabelas `*_AUD` |
| Validação | Bean Validation 2.0 (`@NotNull`, `@Size`, `@NotBlank`) |
| Converters JPA | `SimNaoBooleanConverter` (`Boolean` ↔ `'S'/'N'`) |
| Padrão de camadas | `RestImpl (@Path)` → `RN (@Stateless EJB)` → `BD (JPA)` → `ED (@Entity @Audited)` |
| Internacionalização | `MessageProvider` (bundle de mensagens) |

---

## 3. Modelo de Domínio — Enumerações

### 3.1 `TipoSituacaoIsencao`

Enum armazenado como `String` via `TipoSituacaoIsencaoConverter` na coluna `TP_SITUACAO_ISENCAO` de `LicenciamentoED`.

```java
public enum TipoSituacaoIsencao {
    SOLICITADA,       // Cidadão solicitou isenção — aguarda análise do ADM
    APROVADA,         // ADM concedeu a isenção — taxa isenta
    REPROVADA,        // ADM negou — cidadão deve pagar o boleto
    SOLICITADA_RENOV  // Cidadão solicitou renovação de isenção (fase de vistoria de renovação)
}
```

**Regra de negócio:** O campo `situacaoIsencao` em `LicenciamentoED` é `null` enquanto o cidadão não solicitar isenção. O ADM só pode analisar quando o valor for `SOLICITADA` ou `SOLICITADA_RENOV` — qualquer outro estado gera HTTP 406.

### 3.2 `StatusAnaliseLicenciamentoIsencao`

Enum armazenado como `String` (`@Enumerated(EnumType.STRING)`) na coluna `TP_STATUS` de `AnaliseLicenciamentoIsencaoED`.

```java
public enum StatusAnaliseLicenciamentoIsencao {
    APROVADO,   // Análise de isenção aprovada
    REPROVADO   // Análise de isenção reprovada
}
```

### 3.3 `StatusAnaliseFactIsencao`

Enum armazenado como `String` na coluna `TP_STATUS` de `AnaliseFactIsencaoED`.

```java
public enum StatusAnaliseFactIsencao {
    APROVADO("Aprovado"),
    REPROVADO("Reprovado"),
    SOLICITADA("Solicitada");

    private final String descricao;

    StatusAnaliseFactIsencao(String descricao) { this.descricao = descricao; }
    public String getDescricao() { return descricao; }
}
```

**Nota:** O valor `SOLICITADA` é gravado quando o próprio cidadão registra a solicitação (`AnaliseFactIsencaoRN.incluiCidadao()`). Os valores `APROVADO` e `REPROVADO` são gravados pelo ADM (`AnaliseFactIsencaoRN.inclui()`).

### 3.4 `StatusFact` — valores relevantes para P06-B

O enum completo pertence ao domínio do FACT. Os valores que o P06 lê ou grava são:

| Valor | Significado no contexto P06 |
|---|---|
| `AGUARDANDO_PAGAMENTO_ISENCAO` | FACT aguardando análise de isenção pelo ADM |
| `AGUARDANDO_DISTRIBUICAO` | FACT com isenção aprovada — pronto para distribuição |
| `ISENCAO_REJEITADA` | FACT com isenção reprovada (cidadão deve pagar) |

### 3.5 `SituacaoLicenciamento` — transições disparadas pelo P06-A

Estados que o P06-A escreve como destino das transições via `TrocaEstado`:

| Situação de origem | Condição adicional | Situação de destino |
|---|---|---|
| `AGUARDANDO_PAGAMENTO` | Endereço novo pendente de análise | `ANALISE_ENDERECO_PENDENTE` |
| `AGUARDANDO_PAGAMENTO` | Medida de segurança com inviabilidade técnica | `ANALISE_INVIABILIDADE_PENDENTE` |
| `AGUARDANDO_PAGAMENTO` | Nenhuma das anteriores (caso padrão) | `AGUARDANDO_DISTRIBUICAO` |
| `AGUARDANDO_PAGAMENTO_VISTORIA_RENOVACAO` | Aprovação de renovação | `AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` |

---

## 4. Modelo de Dados — Entidades ED (JPA)

Convenção de nomenclatura do projeto:
- **Tabelas:** prefixo `CBM_`, nomes em maiúsculas com underscore.
- **Sequências:** `CBM_ID_<NOME>_SEQ`.
- **Colunas de PK:** `NRO_INT_<NOME>`.
- **Auditoria automática:** colunas `CTR_DTH_INC` (data inclusão), `CTR_USR_INC` (usuário inclusão) — herdadas de `AppED`.

### 4.1 `AnaliseLicenciamentoIsencaoED`

**Tabela:** `CBM_ANALISE_LIC_ISENCAO`
**Propósito:** Registra cada análise administrativa da isenção de taxa de um licenciamento (aprovação ou reprovação).

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_ANALISE_LIC_ISENCAO` | PK, Seq: `CBM_ID_ANALISE_LIC_ISENCAO_SEQ` | Chave primária gerada por sequência |
| `licenciamento` | `LicenciamentoED` | `NRO_INT_LICENCIAMENTO` | `@ManyToOne`, LAZY, FK | Licenciamento ao qual a análise pertence |
| `vistoria` | `VistoriaED` | `NRO_INT_VISTORIA` | `@ManyToOne`, LAZY, FK, nullable | Vistoria vinculada (quando análise é de vistoria de renovação) |
| `status` | `StatusAnaliseLicenciamentoIsencao` | `TP_STATUS` | `@Enumerated(STRING)`, `@NotNull` | `APROVADO` ou `REPROVADO` |
| `justificativaAntecipacao` | `String` | `TXT_JUSTIFICATIVA_ANTECIPACAO` | max=4000, nullable | Justificativa livre fornecida pelo ADM |
| `idUsuarioSoe` | `Long` | `NRO_INT_USUARIO_SOE` | `@NotNull` | ID do usuário SOE que realizou a análise |
| `nomeUsuarioSoe` | `String` | `NOME_USUARIO_SOE` | max=64 | Nome legível do usuário ADM |
| `dthAnalise` | `Calendar` | `CTR_DTH_INC` | `insertable=false`, `updatable=false` | Data/hora da análise — populado automaticamente |

**Relacionamento inverso:** `JustificativaNcsIsencaoED` referencia `AnaliseLicenciamentoIsencaoED` (1:N de justificativas por análise).

### 4.2 `AnaliseFactIsencaoED`

**Tabela:** `CBM_ANALISE_FACT_ISENCAO`
**Propósito:** Registra cada análise administrativa da isenção de taxa de um FACT.

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_ANALISE_FACT_ISENCAO` | PK, Seq: `CBM_ID_ANALISE_FACT_ISENCAO_SEQ` | Chave primária |
| `licenciamento` | `LicenciamentoED` | `NRO_INT_LICENCIAMENTO` | `@ManyToOne`, LAZY, nullable | Licenciamento vinculado (null para FACT avulso) |
| `factED` | `FactED` | `NRO_INT_FACT` | `@OneToOne`, LAZY, FK | FACT ao qual a análise pertence |
| `status` | `StatusAnaliseFactIsencao` | `TP_STATUS` | `@Enumerated(STRING)`, `@NotNull` | `APROVADO`, `REPROVADO` ou `SOLICITADA` |
| `justificativaAntecipacao` | `String` | `TXT_JUSTIFICATIVA_ANTECIPACAO` | max=4000, nullable | Justificativa do ADM |
| `idUsuarioSoe` | `Long` | `NRO_INT_USUARIO_SOE` | nullable | ID do usuário SOE |
| `nomeUsuarioSoe` | `String` | `NOME_USUARIO_SOE` | max=64, nullable | Nome do usuário SOE |
| `dthAnalise` | `Calendar` | `CTR_DTH_INC` | `insertable=false`, `updatable=false` | Data/hora da análise |

**Relacionamento inverso:** `JustificativaNcsFactIsencaoED` referencia `AnaliseFactIsencaoED` (1:N).

### 4.3 `ComprovanteIsencaoED`

**Tabela:** `CBM_COMPROVANTE_ISENCAO`
**Propósito:** Metadados do comprovante de isenção enviado pelo cidadão. O arquivo binário reside no Alfresco; apenas o `nodeRef` é armazenado em `ArquivoED.identificadorAlfresco`.

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_COMPROVANTE_ISENCAO` | PK, Seq: `CBM_ID_COMP_ISENCAO_SEQ` | Chave primária |
| `licenciamento` | `LicenciamentoED` | `NRO_INT_LICENCIAMENTO` | `@ManyToOne`, LAZY, nullable | Licenciamento (null para comprovante de FACT) |
| `fact` | `FactED` | `NRO_INT_FACT` | `@ManyToOne`, LAZY, nullable | FACT (null para comprovante de licenciamento) |
| `vistoria` | `VistoriaED` | `NRO_INT_VISTORIA` | `@ManyToOne`, LAZY, nullable | Vistoria vinculada ao comprovante |
| `arquivo` | `ArquivoED` | `NRO_INT_ARQUIVO` | `@ManyToOne`, LAZY, FK, `@NotNull` | Metadados do arquivo no Alfresco |
| `descricao` | `String` | `TXT_DESCRICAO` | `@NotNull`, max=255 | Descrição legível do comprovante |

**Invariante:** `licenciamento` e `fact` são mutuamente exclusivos — um comprovante pertence a um licenciamento OU a um FACT, nunca a ambos simultaneamente.

### 4.4 `JustificativaNcsIsencaoED`

**Tabela:** `CBM_JUSTIFICATIVA_NCS_ISENCAO`
**Propósito:** Cada registro representa uma justificativa NCS fornecida pelo ADM ao reprovar (ou aprovar com antecipação) uma isenção de licenciamento. Uma análise pode ter N justificativas.

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_JUSTIF_NCS_ISENCAO` | PK, Seq: `CBM_ID_JUSTIF_NCS_ISENCAO_SEQ` | Chave primária |
| `justificativa` | `String` | `TXT_JUSTIFICATIVA` | max=4000, nullable | Texto livre da justificativa |
| `analiseLicenciamento` | `AnaliseLicenciamentoIsencaoED` | `NRO_INT_ANALISE_LIC_ISENCAO` | `@ManyToOne`, LAZY, FK, `@NotNull` | Análise à qual a justificativa pertence |
| `parametroNcs` | `ParametroNcsED` | `NRO_INT_PARAMETRO_NCS` | `@ManyToOne`, LAZY, FK, `@NotNull` | Parâmetro NCS selecionado pelo ADM |

### 4.5 `JustificativaNcsFactIsencaoED`

**Tabela:** `CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO`
**Propósito:** Mesmo papel que `JustificativaNcsIsencaoED`, mas para análises de FACT.

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_JUSTIF_NCS_FACT_ISENCAO` | PK, Seq: `CBM_ID_JUSTIF_NCS_FACT_ISENCAO_SEQ` | Chave primária |
| `justificativa` | `String` | `TXT_JUSTIFICATIVA` | max=4000, nullable | Texto livre |
| `analiseFactIsencao` | `AnaliseFactIsencaoED` | `NRO_INT_ANALISE_FACT_ISENCAO` | `@ManyToOne`, LAZY, FK | Análise FACT à qual pertence |
| `parametroNcs` | `ParametroNcsED` | `NRO_INT_PARAMETRO_NCS` | `@ManyToOne`, **EAGER**, FK | Parâmetro NCS — carregado eagerly para exibição imediata |

**Diferença importante:** O `parametroNcs` usa `FetchType.EAGER` nesta entidade (diferente do `JustificativaNcsIsencaoED` que usa LAZY), porque o sistema de FACT sempre exibe o parâmetro junto com a justificativa.

### 4.6 `ParametroNcsED`

**Tabela:** `CBM_PARAMETRO_NCS`
**Propósito:** Tabela de parâmetros configuráveis pelo administrador do sistema. Cada registro é uma opção de justificativa exibida ao ADM na tela de análise de isenção.

| Campo Java | Tipo Java | Coluna BD | Constraints | Descrição |
|---|---|---|---|---|
| `id` | `Long` | `NRO_INT_PARAMETRO_NCS` | PK, Seq: `CBM_ID_PARAMETRO_NCS_SEQ` | Chave primária |
| `chave` | `String` | `TXT_CHAVE` | `@NotNull`, max=60 | Chave do parâmetro (ex: `APROVA_ISENCAOTAXA_PREANALISE`) |
| `valor` | `String` | `TXT_VALOR` | `@NotNull`, max=255 | Texto exibido na tela para o ADM selecionar |
| `ativo` | `boolean` | `IND_ATIVO` | `@NotNull`, `SimNaoBooleanConverter` | `true` = parâmetro visível e selecionável |
| `ordem` | `Integer` | `NRO_ORDEM` | `@NotNull` | Ordenação dos parâmetros na tela |

**Chaves de parâmetro usadas no P06:**

| Chave | Contexto de uso |
|---|---|
| `APROVA_ISENCAOTAXA_PREANALISE` | Justificativas exibidas na tela de análise de isenção (licenciamento e FACT) |

### 4.7 Campos adicionados em entidades existentes

#### `LicenciamentoED` — campos do P06

| Campo Java | Tipo Java | Coluna BD | Converter | Descrição |
|---|---|---|---|---|
| `situacaoIsencao` | `TipoSituacaoIsencao` | `TP_SITUACAO_ISENCAO` | `TipoSituacaoIsencaoConverter` | Situação atual da solicitação de isenção (`null` = não solicitada) |
| `indIsencao` (ou `isencao`) | `Boolean` | `IND_ISENCAO` | `SimNaoBooleanConverter` | `true` = isenção concedida e ativa |
| `dthSolicitacaoIsencao` | `Calendar` | `DTH_SOLICITACAO_ISENCAO_TAXA` | — | Data/hora da solicitação de isenção pelo cidadão |

**Método utilitário:**
```java
// Em LicenciamentoED
public boolean isIsento() {
    return Boolean.TRUE.equals(this.isencao); // ou indIsencao, conforme nome real do campo
}
```

#### `FactED` — campos do P06-B

| Campo Java | Tipo Java | Coluna BD | Converter | Descrição |
|---|---|---|---|---|
| `isencao` | `Boolean` | `IND_ISENCAO` | `SimNaoBooleanConverter` | `true` = FACT solicitou isenção |
| `situacao` | `StatusFact` | `TP_SITUACAO` | `@Enumerated(STRING)` | Status atual do FACT |
| `codigoSolicitacao` | `String` | `COD_SOLICITACAO` | — | Número do FACT (gerado só após aprovação de isenção) |

---

## 5. Camada de Dados — BDs (Repositories)

Cada BD é um `@Stateless` EJB que estende `AppBD<ED, PK>` (ou similar), expondo operações JPQL para a entidade correspondente. As RNs injetam os BDs e nunca acessam o `EntityManager` diretamente.

| Classe BD | Entidade gerenciada | Operações principais |
|---|---|---|
| `AnaliseLicenciamentoIsencaoBD` | `AnaliseLicenciamentoIsencaoED` | `findByLicenciamento(Long)`, `findById(Long)`, `persist`, `merge` |
| `AnaliseFactIsencaoBD` | `AnaliseFactIsencaoED` | `findByFact(Long)`, lista paginada, `persist`, `merge` |
| `ComprovanteIsencaoBD` | `ComprovanteIsencaoED` | `findByLicenciamento(Long)`, `findByFact(Long)`, `findByLicenciamentoVistoria(Long, Long)`, `persist`, `merge`, `remove` |
| `JustificativaNcsIsencaoBD` | `JustificativaNcsIsencaoED` | `findByAnaliseLicenciamento(Long)`, `persist`, `merge` |
| `JustificativaNcsFactIsencaoBD` | `JustificativaNcsFactIsencaoED` | `findByAnaliseFactIsencao(Long)`, `persist`, `merge` |
| `ParametroNcsBD` | `ParametroNcsED` | `findByChaveAtivosOrdenados(String chave)` |

---

## 6. Regras de Negócio — RNs (EJB Stateless)

Todas as RNs são anotadas com `@Stateless @AppInterceptor @TransactionAttribute(REQUIRED)` salvo indicação contrária.

### 6.1 `AnaliseLicenciamentoIsencaoRN`

**Herança:** `AppRN<AnaliseLicenciamentoIsencaoED, Long>`
**Pacote:** `com.procergs.solcbm.analiselicenciamentoisencao`

#### Dependências injetadas

| Campo | Tipo | Uso |
|---|---|---|
| `analiseLicenciamentoIsencaoBD` | `AnaliseLicenciamentoIsencaoBD` | Persistência |
| `analiseLicenciamentoIsencaoRNVal` | `AnaliseLicenciamentoIsencaoRNVal` | Validação de estado pendente |
| `licenciamentoRN` | `LicenciamentoRN` | Consulta de licenciamento por ID |
| `licenciamentoAdmNotificacaoRN` | `LicenciamentoAdmNotificacaoRN` | Envio de notificação |
| `justificativaNcsIsencaoRN` | `JustificativaNcsIsencaoRN` | Persistência de justificativas |
| `justificativaNcsRNVal` | `JustificativaNcsRNVal` | Validação de justificativas |
| `sessionMB` | `SessionMB` | Usuário logado SOE (`idUsuarioSoe`, `nomeUsuarioSoe`) |
| `licenciamentoMarcoInclusaoRN` | `LicenciamentoMarcoInclusaoRN` (`@BOMBEIROS`) | Criação de marcos |
| `trocaEstadoLicAguardandoPagamentoParaAguardandoDistribuicaoRN` | `TrocaEstadoRN` (qualifier) | Transição → `AGUARDANDO_DISTRIBUICAO` |
| `trocaEstadoLicAguardandoPagamentoParaAnaliseEnderecoPendenteRN` | `TrocaEstadoRN` (qualifier) | Transição → `ANALISE_ENDERECO_PENDENTE` |
| `trocaEstadoLicAguardandoPagamentoParaAnaliseInviabilidadePendenteRN` | `TrocaEstadoRN` (qualifier) | Transição → `ANALISE_INVIABILIDADE_PENDENTE` |
| `trocaEstadoLicRenovacaoParaAguardandoDistribuicaoVistoriaRN` | `TrocaEstadoRN` (qualifier) | Transição renovação → `AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` |
| `medidaSegurancaRN` | `MedidaSegurancaRN` | Verifica inviabilidade técnica |

#### Método público: `inclui(AnaliseLicenciamentoIsencao)`

```
@Permissao(objeto = "ISENCAOTAXA", acao = "REVISAR")
AnaliseLicenciamentoIsencaoED inclui(AnaliseLicenciamentoIsencao analiseLicenciamentoIsencao)
```

**Fluxo:**
1. Busca `LicenciamentoED` por `analiseLicenciamentoIsencao.idLicenciamento` via `licenciamentoRN`.
2. Chama `analiseLicenciamentoIsencaoRNVal.validarPendenteIsencao(licenciamentoED)` — lança HTTP 406 se `situacaoIsencao` não for `SOLICITADA`.
3. Constrói `AnaliseLicenciamentoIsencaoED` via `buildED()` — preenche `status`, `justificativaAntecipacao`, `idUsuarioSoe`, `nomeUsuarioSoe`.
4. Se `status == REPROVADO`: chama `reprovarSolicitacaoIsencaoDeTaxaDeAnalise()`.
5. Se `status == APROVADO`: chama `aprovarSolicitacaoIsencaoDeTaxaDeAnalise()`.
6. Persiste o ED via `inclui(ed)` herdado de `AppRN`.
7. Retorna o ED persistido.

**Método privado: `reprovarSolicitacaoIsencaoDeTaxaDeAnalise()`**
1. Inclui justificativas NCS via `incluiJustificativas()`.
2. Seta `licenciamentoED.situacaoIsencao = REPROVADA`.
3. Cria marco `TipoMarco.ANALISE_ISENCAO_REPROVADO` via `licenciamentoMarcoInclusaoRN`.
4. Chama `licenciamentoAdmNotificacaoRN.notificarIsencaoDeTaxaRevisada(licenciamentoED)`.

**Método privado: `aprovarSolicitacaoIsencaoDeTaxaDeAnalise()`**
1. Seta `licenciamentoED.situacaoIsencao = APROVADA`.
2. Seta `licenciamentoED.indIsencao = true`.
3. Cria marco `TipoMarco.ANALISE_ISENCAO_APROVADO`.
4. Chama `licenciamentoAdmNotificacaoRN.notificarIsencaoDeTaxaRevisada(licenciamentoED)`.
5. Chama `trocaEstadoLicenciamento(licenciamentoED)`.

**Método privado: `trocaEstadoLicenciamento()`**
```java
private void trocaEstadoLicenciamento(LicenciamentoED licenciamentoED) {
    if (LicenciamentoEnderecoNovoHelper.isEnderecoNovo(licenciamentoED)) {
        trocaEstadoLicAguardandoPagamentoParaAnaliseEnderecoPendenteRN.trocaEstado(licenciamentoED.getId());
        return;
    }
    if (medidaSegurancaRN.existeMedidaSegurancaComInviabilidadeTecnica(licenciamentoED)) {
        trocaEstadoLicAguardandoPagamentoParaAnaliseInviabilidadePendenteRN.trocaEstado(licenciamentoED.getId());
        return;
    }
    trocaEstadoLicAguardandoPagamentoParaAguardadoDistribuicaoRN.trocaEstado(licenciamentoED.getId());
}
```

#### Método público: `incluiRenovacao(AnaliseLicenciamentoIsencao)`

```
@Permissao(objeto = "ISENCAOTAXA", acao = "REVISAR")
AnaliseLicenciamentoIsencaoED incluiRenovacao(AnaliseLicenciamentoIsencao analiseLicenciamentoIsencao)
```

**Fluxo:** Idêntico ao `inclui()`, mas:
- Valida `situacaoIsencao == SOLICITADA_RENOV` (em vez de `SOLICITADA`).
- Em caso de reprovação: cria marco `TipoMarco.ANALISE_ISENCAO_RENOV_REPROVADO`.
- Em caso de aprovação: cria marco `TipoMarco.ANALISE_ISENCAO_RENOV_APROVADO` e chama `trocaEstadoLicRenovacaoParaAguardandoDistribuicaoVistoriaRN`.

#### Método público: `listarPorLicenciamento(Long idLicenciamento)`

```
List<AnaliseLicenciamentoIsencaoED> listarPorLicenciamento(Long idLicenciamento)
```

Lista todas as análises de isenção de um licenciamento, sem restrição de permissão.

#### Método privado: `incluiJustificativas(List<JustificativaNcs>, AnaliseLicenciamentoIsencaoED)`

Para cada `JustificativaNcs` recebido:
1. Cria `JustificativaNcsIsencaoED` com `justificativa` e `parametroNcs` vinculado.
2. Seta `analiseLicenciamento` para o ED da análise atual.
3. Persiste via `justificativaNcsIsencaoRN.inclui(ed)`.

---

### 6.2 `AnaliseFactIsencaoRN`

**Herança:** `AppRN<AnaliseFactIsencaoED, Long>`
**Pacote:** `com.procergs.solcbm.analisefactisencao`

#### Dependências injetadas

| Campo | Tipo | Uso |
|---|---|---|
| `analiseFactIsencaoBD` | `AnaliseFactIsencaoBD` | Persistência |
| `factRN` | `FactRN` | Consulta e alteração do FACT |
| `geraNumeroFactRN` | `GeraNumeroFactRN` | Geração do número do FACT na aprovação |
| `licenciamentoRN` | `LicenciamentoRN` | Consulta de licenciamento vinculado |
| `justificativaNcsFactIsencaoRN` | `JustificativaNcsFactIsencaoRN` | Persistência de justificativas |
| `justificativaNcsRNVal` | `JustificativaNcsRNVal` | Validação |
| `sessionMB` | `SessionMB` | Usuário logado SOE |
| `licenciamentoMarcoInclusaoRN` | `LicenciamentoMarcoInclusaoRN` (`@BOMBEIROS`) | Criação de marcos de licenciamento |
| `factMarcoAdmRN` | `FactMarcoAdmRN` | Criação de marcos do FACT |
| `notificacaoNumeroFactRN` | `NotificacaoNumeroFactRN` | Envio de e-mail com número do FACT |
| `factAdmRN` | `FactAdmRN` | Notificações do FACT |
| `parametroNcsRN` | `ParametroNcsRN` | Listagem de justificativas NCS |
| `usuarioRN` | `UsuarioRN` | Consulta de dados do usuário |

#### Método público: `inclui(AnaliseFactIsencao)`

```
@Permissao(objeto = "ISENCAOTAXA", acao = "REVISAR")
AnaliseFactIsencaoED inclui(AnaliseFactIsencao analiseFactIsencao)
```

**Fluxo:**
1. Constrói `AnaliseFactIsencaoED` via `buildED()` — preenche `factED`, `licenciamento` (se houver), `status`, `justificativaAntecipacao`, `idUsuarioSoe`, `nomeUsuarioSoe`.
2. Se `status == REPROVADO`: chama `reprovarSolicitacaoIsencaoDeTaxaDeAnalise()`.
3. Se `status == APROVADO`: chama `aprovarSolicitacaoIsencaoDeTaxaDeAnalise()`.
4. Notifica usuários via `factAdmRN.notificaUsuarios()`.
5. Persiste e retorna.

**Método privado: `reprovarSolicitacaoIsencaoDeTaxaDeAnalise()`**
1. Inclui justificativas NCS.
2. Seta `factED.situacao = AGUARDANDO_PAGAMENTO_ISENCAO` (mantém aguardando).
3. Seta `factED.isencao = false`.
4. Cria marco `TipoMarco.ANALISE_ISENCAOFACT_REPROVADO` via `factMarcoAdmRN`.

**Método privado: `aprovarSolicitacaoIsencaoDeTaxaDeAnalise()`**
1. Gera número do FACT via `geraNumeroFactRN` — preenche `factED.codigoSolicitacao`.
2. Cria marco `TipoMarco.NRO_FACT` via `factMarcoAdmRN`.
3. Cria marco `TipoMarco.ANALISE_ISENCAOFACT_APROVADO`.
4. Seta `factED.situacao = AGUARDANDO_DISTRIBUICAO`.
5. Envia e-mail via `notificacaoNumeroFactRN.notificarPorEmail()`.

#### Método público: `incluiCidadao(FactED, UsuarioED)`

```
@Permissao(desabilitada = true)
AnaliseFactIsencaoED incluiCidadao(FactED factED, UsuarioED usuarioED)
```

Registra a solicitação de isenção feita pelo próprio cidadão. Grava `status = SOLICITADA`, `dthAnalise = now`, `ctrUsuInc = usuarioED.id`.

#### Método público: `atualizaSolicitacaoIsencao(Long idFact, Boolean solicitacaoIsencao)`

```
@Permissao(desabilitada = true)
void atualizaSolicitacaoIsencao(Long idFact, Boolean solicitacaoIsencao)
```

Atualiza o campo `isencao` do FACT. Se `solicitacaoIsencao == true`, cria marco `TipoMarco.SOLICITACAO_ISENCAO_FACT`.

#### Método público: `buscarPorFact(Long id)`

```
@Permissao(desabilitada = true)
List<RetornoSolicitacaoIsencao> buscarPorFact(Long id)
```

Retorna a lista de análises de isenção do FACT como DTOs `RetornoSolicitacaoIsencao` (campo `dataSolicitacao`, `status`, `valorJustificativaNcs`).

#### Método público: `consultaUltimaAnalisePorFact(Long id)`

```
@Permissao(desabilitada = true)
RetornoSolicitacaoIsencao consultaUltimaAnalisePorFact(Long id)
```

Retorna a análise mais recente do FACT.

#### Método público: `lista(FactAnalisePesqED)`

```
@Permissao(objeto = "ISENCAOTAXA", acao = "LISTAR")
ListaPaginadaRetorno<AnaliseIsencaoTaxa> lista(FactAnalisePesqED ped)
```

Lista paginada de FACTs pendentes de análise de isenção. Usa `FactAnalisePesqED` como objeto de pesquisa com `paginaAtual` e `tamanho`.

---

### 6.3 `ComprovanteIsencaoRN`

**Herança:** `AppRN<ComprovanteIsencaoED, Long>`
**Anotações:** `@Stateless @TransactionAttribute(REQUIRED)` (sem `@AppInterceptor` — sem interceptação de permissão)
**Pacote:** `com.procergs.solcbm.comprovanteisencao`

#### Dependências injetadas

| Campo | Tipo | Uso |
|---|---|---|
| `comprovanteIsencaoBD` | `ComprovanteIsencaoBD` | Persistência |
| `arquivoRN` | `ArquivoRN` | Upload/download Alfresco |
| `vistoriaRN` | `VistoriaRN` | Consulta de vistoria vinculada ao licenciamento |
| `bundle` | `MessageProvider` | Mensagens de erro internacionalizadas |

#### Método: `incluirOuAlterar(Long idLicenciamento, ComprovanteIsencao)`

```java
public Long incluirOuAlterar(Long idLicenciamento, ComprovanteIsencao comprovanteIsencao)
```

- Valida `idLicenciamento` (não nulo) e `descricao` (não vazia).
- Se `comprovanteIsencao.id == null` (novo): constrói ED, vincula ao licenciamento, vincula à vistoria ativa (se existir), persiste.
- Se `comprovanteIsencao.id != null` (alterar): busca ED existente, atualiza `descricao` se diferente.
- Retorna `id` do ED persistido.

#### Método: `incluirOuAlterarFact(Long idFact, ComprovanteIsencao)`

Idêntico ao anterior, mas vincula ao `FactED` em vez de `LicenciamentoED`.

#### Método: `incluirArquivo(Long id, InputStream inputStream, String nomeArquivo)`

```java
public Arquivo incluirArquivo(Long id, InputStream inputStream, String nomeArquivo)
```

1. Busca `ComprovanteIsencaoED` por `id`.
2. Se `ed.getArquivo() != null`: lança `WebApplicationRNException(bundle.getMessage("arquivo.erro.duplicado"), BAD_REQUEST)` — impede upload duplicado.
3. Chama `arquivoRN.incluirArquivo(inputStream, nomeArquivo, TipoArquivo.EDIFICACAO)` — faz upload para Alfresco e retorna `ArquivoED` com `identificadorAlfresco` preenchido.
4. Seta `ed.arquivo = arquivoED` e chama `altera(ed)`.
5. Retorna `Arquivo` (DTO) via `arquivoRN.toArquivo(arquivoED)`.

#### Método: `downloadArquivo(LicenciamentoED, Long idComprovante)`

1. Busca `ComprovanteIsencaoED` por `idComprovante`.
2. Valida que o comprovante pertence ao licenciamento.
3. Chama `arquivoRN.downloadArquivo(ed.getArquivo().getIdentificadorAlfresco())` — retorna `InputStream` do Alfresco.

#### Método: `downloadArquivoFact(FactED, Long idComprovante)`

Idêntico ao anterior, mas valida que o comprovante pertence ao FACT.

#### Método: `remover(Long idLicenciamento, Long idComprovante)`

1. Busca e valida `ComprovanteIsencaoED`.
2. Se `ed.getArquivo() != null`: chama `arquivoRN.excluir(ed.getArquivo())` — remove do Alfresco.
3. Chama `exclui(ed)` herdado — remove o registro do BD.

#### Método: `removerFact(Long idFact, Long idComprovante)`

Idêntico ao anterior, mas valida que pertence ao FACT.

#### Métodos de listagem

```java
@TransactionAttribute(SUPPORTS)
public List<ComprovanteIsencao> listaPorLicenciamento(LicenciamentoED licenciamentoED)
// Retorna lista de DTOs; lista vazia se licenciamentoED for null

@TransactionAttribute(SUPPORTS)
public List<ComprovanteIsencao> listaPorFact(FactED factED)
// Retorna lista de DTOs; lista vazia se factED for null

@TransactionAttribute(SUPPORTS)
public List<ComprovanteIsencao> listaPorLicenciamentoVistoria(Long idLicenciamento, Long idVistoria)
// Lista comprovantes vinculados a uma vistoria específica

public void excluirPorLicenciamento(Long idLicenciamento)
// Remoção em cascata de todos os comprovantes + arquivos do Alfresco

@TransactionAttribute(REQUIRED)
public void excluirPorLicenciamentoVistoria(Long idLicenciamento, Long idVistoria)
// Remoção em cascata filtrada por vistoria
```

---

### 6.4 `LicenciamentoIsencaoRN`

**Anotação:** `@Stateless` (sem `@AppInterceptor`)
**Propósito:** Lógica de determinação se a isenção está aprovada, considerando a fase do licenciamento.

```java
public boolean isIsencaoAprovada(LicenciamentoED licenciamentoED)
```

- Se fase `PROJETO`: retorna `true` se `situacaoIsencao == APROVADA` OU se o licenciamento já possui número e a taxa de reanalise é zero (verificado via `BoletoLicenciamentoRN`).
- Para outras fases: retorna `TipoSituacaoIsencao.APROVADA.equals(licenciamentoED.getSituacaoIsencao())`.

**Dependências:** `BoletoLicenciamentoRN`.

---

### 6.5 `IsencaoTaxaReanaliseRN`

**Anotações:** `@Stateless @AppInterceptor @TransactionAttribute(REQUIRED) @Permissao(desabilitada = true)`

**Constante:**
```java
private static final long PRAZO_CORRECAO = 30L; // dias
```

#### Método principal: `possuiIsencaoReanalise(Long idLicenciamento)`

```java
public boolean possuiIsencaoReanalise(Long idLicenciamento)
```

**Fluxo:**
1. Obtém lista de ciências via `getListaCiencias(idLicenciamento)`.
2. Verifica `isPrimeiraCorrecao(listaAnaliseCiencia)` — retorna `true` se `size() <= 1`.
3. Obtém `ultimaDataCiencia(lista)`.
4. Verifica `isCorrecaoDentroDoPrazo(dataCiencia, Calendar.getInstance(), idLicenciamento)`.
5. Retorna `true` apenas se for a primeira correção E estiver dentro do prazo.

**Cálculo do prazo (`isCorrecaoDentroDoPrazo`):**

O cálculo é cumulativo, somando os intervalos relevantes:
- `dataCiencia` → data da 1ª correção (análise técnica reprovada → nova submissão)
- + `data da 1ª correção` → `data da conclusão do 1º recurso` (se aplicável)
- + `data da 2ª correção` → `data da conclusão do 2º recurso` (se aplicável)

Retorna `true` se a soma de dias for `<= 30`.

**Dependências:** `AnaliseLicenciamentoTecnicaRN`, `AnaliseLicInviabilidadeRN`, `AnaliseRecursoRN`.

---

### 6.6 `AnaliseLicenciamentoIsencaoRNVal`

Classe de validação sem `@Stateless` (instanciada como CDI bean ou utilitário).

```java
public void validarPendenteIsencao(LicenciamentoED ed)
```

- Verifica: `ed.getSituacaoIsencao() == SOLICITADA || ed.getSituacaoIsencao() == SOLICITADA_RENOV`.
- Se não: lança `WebApplicationRNException(bundle.getMessage("licenciamento.isencao.naopendente"), NOT_ACCEPTABLE)` (HTTP 406).

---

### 6.7 `ParametroNcsRN`

**Herança:** `AppRN<ParametroNcsED, Long>`
**Anotação:** `@Stateless @TransactionAttribute(REQUIRED)`

```java
public List<ParametroNcs> listarParaAnalisarIsencao()
// Delega para: listarParametrosAtivosPorChave("APROVA_ISENCAOTAXA_PREANALISE")
// Retorna lista de DTOs ParametroNcs ordenados por campo `ordem`

public List<ParametroNcs> listarParametrosAtivosPorChave(String chave)
// SELECT p FROM ParametroNcsED p WHERE p.chave = :chave AND p.ativo = 'S' ORDER BY p.ordem
```

---

### 6.8 `JustificativaNcsIsencaoRN` e `JustificativaNcsFactIsencaoRN`

Ambas herdam de `AppRN`, oferecendo CRUD básico. Não possuem métodos de negócio customizados além do `buscarPorAnaliseFactIsencao(Long id)` em `JustificativaNcsFactIsencaoRN`:

```java
@TransactionAttribute(SUPPORTS)
public List<JustificativaNcsFactIsencaoED> buscarPorAnaliseFactIsencao(Long id)
// SELECT j FROM JustificativaNcsFactIsencaoED j WHERE j.analiseFactIsencao.id = :id
```

---

## 7. Validações e Exceções

### 7.1 Exceção padrão

Todas as violações de regra de negócio lançam `WebApplicationRNException`, que é mapeada pelo `ExceptionMapper` do JAX-RS para a resposta HTTP correspondente.

```java
throw new WebApplicationRNException(mensagem, Response.Status.NOT_ACCEPTABLE); // HTTP 406
throw new WebApplicationRNException(mensagem, Response.Status.BAD_REQUEST);    // HTTP 400
```

### 7.2 Tabela de validações do P06

| Validação | Condição | HTTP | Chave de mensagem |
|---|---|---|---|
| Status pendente de isenção (licenciamento) | `situacaoIsencao` não é `SOLICITADA` nem `SOLICITADA_RENOV` | 406 | `licenciamento.isencao.naopendente` |
| Arquivo duplicado em comprovante | `ComprovanteIsencaoED.arquivo != null` ao tentar novo upload | 400 | `arquivo.erro.duplicado` |
| Licenciamento nulo | `idLicenciamento == null` | 400 | (bundle) |
| FACT nulo | `idFact == null` | 400 | (bundle) |
| Descrição de comprovante vazia | `comprovanteIsencao.descricao` em branco | 400 | (bundle) |

### 7.3 Validação Bean Validation nos modelos de transferência

| Campo | Constraint | Entidade/DTO |
|---|---|---|
| `status` | `@NotNull` | `AnaliseLicenciamentoIsencaoED`, `AnaliseFactIsencaoED` |
| `descricao` | `@NotNull`, `max=255` | `ComprovanteIsencaoED` |
| `chave` | `@NotNull`, `max=60` | `ParametroNcsED` |
| `valor` | `@NotNull`, `max=255` | `ParametroNcsED` |
| `ativo` | `@NotNull` | `ParametroNcsED` |
| `ordem` | `@NotNull` | `ParametroNcsED` |
| `idUsuarioSoe` | `@NotNull` | `AnaliseLicenciamentoIsencaoED` |
| `arquivo` | `@NotNull` | `ComprovanteIsencaoED` |

---

## 8. API REST — Endpoints JAX-RS

### 8.1 Análise de Isenção de Licenciamento — ADM

**Classe:** `AnaliseLicenciamentoIsencaoRestImpl`
**Anotações:** `@Path("/adm/analise-licenciamentos-isencao") @SOEAuthRest @Produces(APPLICATION_JSON) @Consumes(APPLICATION_JSON)`

| Método HTTP | Path | Método Java | Permissão | Descrição |
|---|---|---|---|---|
| `GET` | `/{idLicenciamento}/licenciamento` | `consultarLicenciamento(idLicenciamento)` | `ISENCAOTAXA:LISTAR` | Retorna o licenciamento para a tela de análise de isenção |
| `GET` | `/justificativas` | `listarJustificativas()` | `ISENCAOTAXA:LISTAR` | Lista parâmetros NCS com chave `APROVA_ISENCAOTAXA_PREANALISE` |
| `POST` | `/` | `incluirAnalise(analiseLicenciamentoIsencao)` | `ISENCAOTAXA:REVISAR` | Registra análise (aprovação ou reprovação) |
| `GET` | `/pendentes` | `listar(paginaAtual, tamanho)` | `ISENCAOTAXA:LISTAR` | Lista licenciamentos pendentes de análise de isenção (paginado) |
| `POST` | `/renovacao` | `incluirAnaliseRenovacao(analiseLicenciamentoIsencao)` | `ISENCAOTAXA:REVISAR` | Registra análise de renovação de isenção |

**GET /pendentes — Query params:**
```
paginaAtual=0&tamanho=20
```

**GET /pendentes — Response 200:**
```json
{
  "lista": [
    {
      "id": 1001,
      "razaoSocial": "Empresa XYZ Ltda",
      "tipo": "PPCI",
      "ocupacaoPredominante": "Escritório",
      "area": 250.5,
      "dataSolicitacao": "2026-03-10T14:30:00",
      "qtdEstabelecimentosPrincipais": 1,
      "prioridade": false,
      "hora": null,
      "origem": "LICEN",
      "avulso": false
    }
  ],
  "totalRegistros": 45
}
```

**POST / — Request body:**
```json
{
  "idLicenciamento": 1001,
  "status": "APROVADO",
  "justificativaAntecipacao": "Documentação completa e válida.",
  "justificativasNcs": [
    {
      "idParametroNcs": 3,
      "justificativa": "Entidade filantrópica com documentação comprobatória."
    }
  ]
}
```

**POST / — Response:** HTTP 201 Created, corpo: `AnaliseLicenciamentoIsencaoED` serializado como JSON.

### 8.2 Análise de Isenção de FACT — ADM

**Classe:** `AnaliseFactIsencaoRestImpl`
**Anotações:** `@Path("/adm/analises-fact-isencao") @SOEAuthRest @Produces(APPLICATION_JSON) @Consumes(APPLICATION_JSON)`

| Método HTTP | Path | Método Java | Permissão | Descrição |
|---|---|---|---|---|
| `POST` | `/` | `incluirAnalise(analiseFactIsencao)` | `ISENCAOTAXA:REVISAR` | Registra análise de isenção do FACT |
| `GET` | `/` | `listar(paginaAtual, tamanho)` | `ISENCAOTAXA:LISTAR` | Lista FACTs pendentes de análise de isenção (paginado) |

**POST / — Request body:**
```json
{
  "idFact": 500,
  "idLicenciamento": 1001,
  "status": "REPROVADO",
  "justificativaAntecipacao": "Documentação insuficiente.",
  "justificativasNcs": [
    {
      "idParametroNcs": 2,
      "justificativa": "Comprovante sem validade."
    }
  ]
}
```

### 8.3 Comprovantes de Isenção — FACT

**Classe:** `ComprovanteIsencaoFactRestImpl`
**Anotações:** `@Path("/comprovantes-isencao-fact") @Produces(APPLICATION_JSON) @Consumes(APPLICATION_JSON)`

| Método HTTP | Path | Método Java | Segurança | Descrição |
|---|---|---|---|---|
| `GET` | `/{idFact}/comprovante-isencao` | `getComprovantesIsencao(idFact)` | `@AutorizaEnvolvido` | Lista comprovantes do FACT |
| `GET` | `/{idFact}/comprovante-isencao/{idComprovante}/arquivo` | `downloadArquivoComprovanteIsencao(idFact, idComprovante)` | `@AutorizaEnvolvido`, `@Produces("application/octet-stream")` | Download do arquivo do Alfresco |
| `PUT` | `/{idFact}/comprovante-isencao/` | `criarComprovanteIsencao(idFact, comprovanteIsencao)` | `@AutorizaEnvolvido` | Cria ou altera comprovante (sem arquivo) |
| `POST` | `/{idFact}/comprovante-isencao/{idComprovante}/arquivo` | `uploadArquivoComprovanteIsencao(idFact, idComprovante, formData)` | `@AutorizaEnvolvido`, `@Consumes("multipart/form-data")` | Upload do arquivo para o Alfresco |
| `DELETE` | `/{idFact}/comprovante-isencao/{idComprovante}` | `removerComprovanteIsencao(idFact, idComprovante)` | `@AutorizaEnvolvido` | Remove comprovante e arquivo do Alfresco |

### 8.4 Comprovantes de Isenção — Licenciamento

**Classe:** `LicenciamentoRestImpl` (ou classe específica de comprovantes de licenciamento)
**Base path:** `/licenciamentos/{idLicenciamento}/comprovante-isencao`

| Método HTTP | Path | Descrição |
|---|---|---|
| `GET` | `/` | Lista comprovantes do licenciamento |
| `PUT` | `/` | Cria ou altera comprovante (sem arquivo) |
| `POST` | `/{idComprovante}/arquivo` | Upload do arquivo (`multipart/form-data`) |
| `GET` | `/{idComprovante}/arquivo` | Download do arquivo (`application/octet-stream`) |
| `DELETE` | `/{idComprovante}` | Remove comprovante e arquivo do Alfresco |

### 8.5 Solicitação de Isenção — Cidadão (Licenciamento)

**Base path:** `/licenciamentos/{idLicenciamento}`

| Método HTTP | Path | Descrição |
|---|---|---|
| `PUT` | `/solicitacaoIsencao` | Cidadão solicita ou renova isenção do licenciamento |

**Request body:**
```json
{
  "solicitacao": true,
  "solicitacaoRenovacao": false
}
```

**Regras:**
- `solicitacao=true` e `solicitacaoRenovacao=false` → grava `situacaoIsencao = SOLICITADA`.
- `solicitacao=false` e `solicitacaoRenovacao=true` → grava `situacaoIsencao = SOLICITADA_RENOV`.
- Só permitido quando o licenciamento está em `AGUARDANDO_PAGAMENTO`.

### 8.6 Solicitação de Isenção — Cidadão (FACT)

**Base path:** `/facts/{idFact}`

| Método HTTP | Path | Descrição |
|---|---|---|
| `PUT` | `/solicitacaoIsencao` | Cidadão solicita isenção do FACT |

**Request body:**
```json
{
  "solicitacao": true
}
```

**Comportamento:** Chama `AnaliseFactIsencaoRN.atualizaSolicitacaoIsencao(idFact, true)` — grava `FactED.isencao = 'S'` e cria marco `SOLICITACAO_ISENCAO_FACT`.

### 8.7 Histórico de Retornos do FACT

| Método HTTP | Path | Descrição |
|---|---|---|
| `GET` | `/retornos-solicitacao-fact/fact/{idFact}` | Lista histórico de análises/retornos do FACT (DTO `RetornoSolicitacaoIsencao`) |

---

## 9. Modelos de Transferência — DTOs

Os DTOs (denominados "modelos" ou "transfer objects" no projeto) são POJOs serializados via Jackson no JAX-RS.

### 9.1 `AnaliseLicenciamentoIsencao` (entrada do POST)

```java
public class AnaliseLicenciamentoIsencao {
    private Long idLicenciamento;
    private StatusAnaliseLicenciamentoIsencao status;  // APROVADO | REPROVADO
    private String justificativaAntecipacao;           // max 4000, nullable
    private List<JustificativaNcs> justificativasNcs;  // lista de justificativas NCS
}
```

### 9.2 `AnaliseFactIsencao` (entrada do POST de FACT)

```java
public class AnaliseFactIsencao {
    private Long idFact;
    private Long idLicenciamento;                      // nullable para FACT avulso
    private StatusAnaliseFactIsencao status;           // APROVADO | REPROVADO
    private String justificativaAntecipacao;
    private List<JustificativaNcs> justificativasNcs;
}
```

### 9.3 `JustificativaNcs` (elemento da lista de justificativas)

```java
public class JustificativaNcs {
    private Long idParametroNcs;
    private String justificativa;    // max 4000, nullable
}
```

### 9.4 `ComprovanteIsencao` (entrada PUT / saída GET)

```java
public class ComprovanteIsencao {
    private Long id;                // null = novo, não-null = alterar
    private String descricao;       // @NotBlank, max 255
    private Arquivo arquivo;        // metadados do arquivo (sem binário)
    private Long idVistoria;        // nullable
    private String tipoVistoria;    // nullable
    private Calendar dataInclusao;
}
```

### 9.5 `Arquivo` (metadados do arquivo no Alfresco)

```java
public class Arquivo {
    private Long id;
    private String nome;            // nome original do arquivo
    private String contentType;
    private Long tamanho;           // bytes
    // identificadorAlfresco NÃO é exposto ao frontend
}
```

### 9.6 `AnaliseIsencaoTaxa` (item da lista paginada ADM)

```java
public class AnaliseIsencaoTaxa {
    private Long id;
    private String razaoSocial;
    private String tipo;
    private String ocupacaoPredominante;
    private BigDecimal area;
    private Calendar dataSolicitacao;
    private Integer qtdEstabelecimentosPrincipais;
    private Boolean prioridade;
    private Calendar hora;
    private String origem;            // "LIC" | "LICEN" | "RENOV" | "FACT"
    private Boolean avulso;
}
```

### 9.7 `ParametroNcs` (saída do GET /justificativas)

```java
public class ParametroNcs {
    private Long id;
    private String chave;
    private String valor;
    private Integer ordem;
}
```

### 9.8 `RetornoSolicitacaoIsencao` (saída do GET histórico FACT)

```java
public class RetornoSolicitacaoIsencao {
    private Calendar dataSolicitacao;
    private StatusAnaliseFactIsencao status;   // null = somente solicitação, sem análise
    private String valorJustificativaNcs;      // texto concatenado das justificativas
}
```

---

## 10. Segurança — @Permissao e SOE

### 10.1 Autenticação

Todos os endpoints ADM são anotados com `@SOEAuthRest` — filtro JAX-RS que valida o token de sessão do SOE PROCERGS. Endpoints do cidadão usam `@AutorizaEnvolvido` para validar que o usuário logado é envolvido no licenciamento/FACT.

A sessão do usuário logado é obtida via `SessionMB`:
```java
@Inject
private SessionMB sessionMB;

Long idUsuarioSoe = sessionMB.getIdUsuario();
String nomeUsuarioSoe = sessionMB.getNomeUsuario();
```

### 10.2 Autorização — `@Permissao`

| Permissão | Método | Descrição |
|---|---|---|
| `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")` | `AnaliseLicenciamentoIsencaoRN.inclui()`, `incluiRenovacao()` | ADM pode analisar e decidir sobre isenção |
| `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")` | `AnaliseFactIsencaoRN.inclui()` | ADM pode analisar isenção de FACT |
| `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")` | `AnaliseLicenciamentoIsencaoRN.listarPorLicenciamento()` | Consulta de análises |
| `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")` | `AnaliseFactIsencaoRN.lista()` | Listagem paginada de FACTs |
| `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")` | `LicenciamentoAdmNotificacaoRN.notificarIsencaoDeTaxaRevisada()` | Só ADM pode disparar notificação de revisão |
| `@Permissao(desabilitada=true)` | `AnaliseFactIsencaoRN.incluiCidadao()`, `atualizaSolicitacaoIsencao()`, `buscarPorFact()` | Cidadão autenticado (sem restrição de perfil) |

### 10.3 Segurança de recurso — `@AutorizaEnvolvido`

Endpoints de comprovante do FACT usam `@AutorizaEnvolvido` — interceptor que verifica se o usuário logado é RT, RU ou proprietário vinculado ao FACT. Implementado via `SegurancaEnvolvidoInterceptor`.

---

## 11. Integração com Alfresco — Arquivo de Comprovante

### 11.1 Fluxo de upload

```
ComprovanteIsencaoFactRestImpl
    → recebe MultipartFile (multipart/form-data)
    → extrai InputStream e nomeArquivo
    → chama ComprovanteIsencaoRN.incluirArquivo(idComprovante, inputStream, nomeArquivo)
        → valida não há arquivo duplicado
        → chama ArquivoRN.incluirArquivo(inputStream, nomeArquivo, TipoArquivo.EDIFICACAO)
            → faz upload para Alfresco
            → cria ArquivoED com identificadorAlfresco = nodeRef retornado pelo Alfresco
            → persiste ArquivoED
        → associa ArquivoED ao ComprovanteIsencaoED
        → persiste ComprovanteIsencaoED atualizado
        → retorna DTO Arquivo
```

### 11.2 Fluxo de download

```
ComprovanteIsencaoFactRestImpl
    → chama ComprovanteIsencaoRN.downloadArquivoFact(factED, idComprovante)
        → busca ComprovanteIsencaoED
        → valida que pertence ao FACT
        → chama ArquivoRN.downloadArquivo(ed.getArquivo().getIdentificadorAlfresco())
            → conecta ao Alfresco pelo nodeRef
            → retorna InputStream
    → REST envolve o InputStream em StreamingOutput para @Produces("application/octet-stream")
```

### 11.3 Campo `identificadorAlfresco` em `ArquivoED`

```java
@Column(name = "TXT_IDENTIFICADOR_ALFRESCO", length = 150)
@NotNull
private String identificadorAlfresco;
// Formato: workspace://SpacesStore/{UUID}
// Exemplo: workspace://SpacesStore/a3b4c5d6-e7f8-90ab-cdef-1234567890ab
```

O arquivo binário **nunca é persistido no banco de dados relacional**. Apenas o `nodeRef` do Alfresco é armazenado.

---

## 12. Notificações — E-mail via SOE

### 12.1 Notificação de análise de isenção de licenciamento

**Método:** `LicenciamentoAdmNotificacaoRN.notificarIsencaoDeTaxaRevisada(LicenciamentoED)`

**Permissão:** `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")`

**Disparo:** Chamado por `AnaliseLicenciamentoIsencaoRN` ao final de qualquer análise (aprovação ou reprovação), tanto para isenção inicial quanto para renovação.

**Comportamento interno:**
1. Obtém lista de envolvidos (RT, RU, proprietário) via `LicenciamentoEnvolvidoRN`.
2. Monta o corpo do e-mail com template `notificacao.email.template.licenciamento.isencao`.
3. Envia via serviço de notificação SOE para todos os envolvidos.

**Chaves de bundle:**
- Template: `notificacao.email.template.licenciamento.isencao`
- Assunto: `notificacao.assunto.isencao.analisada`

### 12.2 Notificação de análise de isenção de FACT

**Métodos chamados em `AnaliseFactIsencaoRN.inclui()`:**
- `factAdmRN.notificaUsuarios()` — notifica os usuários vinculados ao FACT.
- `notificacaoNumeroFactRN.notificarPorEmail()` — enviado apenas na aprovação, informa o número gerado do FACT.

**Chaves de mensagem no bundle:**
- Aprovação: `"fact.analise.isencao.aprovada"`
- Reprovação: `"fact.analise.isencao.rejeitada"`

### 12.3 Destinatários

Para **licenciamentos:** todos os envolvidos (RT, RU/proprietário) cadastrados no licenciamento.
Para **FACTs:** usuários vinculados ao FACT (conforme `factAdmRN`).

---

## 13. Máquinas de Estado

### 13.1 Campo `situacaoIsencao` em `LicenciamentoED`

```
[null] ─────────────────────────────────────────────────────────────
         Cidadão PUT /solicitacaoIsencao {solicitacao:true}
                │
                ▼
          SOLICITADA
                │
       ┌────────┴────────┐
  ADM reprova       ADM aprova
       │                 │
       ▼                 ▼
   REPROVADA          APROVADA
       │           (indIsencao=true)
       │           (transição de estado do licenciamento)
       │
       │ Cidadão solicita renovação
       │ PUT /solicitacaoIsencao {solicitacaoRenovacao:true}
       ▼
 SOLICITADA_RENOV
       │
  ┌────┴────┐
ADM reprova  ADM aprova
  │               │
  ▼               ▼
REPROVADA       APROVADA
             (AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO)
```

### 13.2 Campo `situacao` em `FactED` — transições P06-B

```
[Qualquer estado anterior]
    │
    │ Cidadão PUT /facts/{id}/solicitacaoIsencao {solicitacao:true}
    │ → FactED.isencao = 'S'
    ▼
AGUARDANDO_PAGAMENTO_ISENCAO
    │
    ├── ADM POST /adm/analises-fact-isencao {status:"APROVADO"}
    │       → GeraNumeroFact, marco NRO_FACT, marco ANALISE_ISENCAOFACT_APROVADO
    │       ▼
    │   AGUARDANDO_DISTRIBUICAO
    │
    └── ADM POST /adm/analises-fact-isencao {status:"REPROVADO"}
            → marco ANALISE_ISENCAOFACT_REPROVADO, isencao='N'
            ▼
        AGUARDANDO_PAGAMENTO_ISENCAO  (permanece — cidadão deve pagar)
        ou ISENCAO_REJEITADA
```

### 13.3 Transições de estado do `LicenciamentoED` após aprovação (P06-A)

Implementadas via padrão `TrocaEstado` — cada transição é um `@Stateless` EJB separado com qualifier CDI:

| Classe TrocaEstado | De | Para |
|---|---|---|
| `TrocaEstadoLicenciamentoAguardandoPagamentoParaAguardandoDistribuicaoRN` | `AGUARDANDO_PAGAMENTO` | `AGUARDANDO_DISTRIBUICAO` |
| `TrocaEstadoLicenciamentoAguardandoPagamentoParaAnaliseEnderecoPendenteRN` | `AGUARDANDO_PAGAMENTO` | `ANALISE_ENDERECO_PENDENTE` |
| `TrocaEstadoLicenciamentoAguardandoPagamentoParaAnaliseInviabilidadePendenteRN` | `AGUARDANDO_PAGAMENTO` | `ANALISE_INVIABILIDADE_PENDENTE` |
| `TrocaEstadoLicenciamentoRenovacaoParaAguardandoDistribuicaoVistoriaRN` | `AGUARDANDO_PAGAMENTO_VISTORIA_RENOVACAO` | `AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` |

**Ações comuns executadas pelas classes TrocaEstado:**
1. Alterar `LicenciamentoED.situacao` para o estado destino.
2. Gerar número do licenciamento via `LicenciamentoNumeroRN` (se não gerado).
3. Criar marco `TipoMarco.ENVIO_ATEC` via `LicenciamentoMarcoInclusaoRN`.
4. Persistir o `LicenciamentoED` alterado.

---

## 14. Esquema do Banco de Dados

### 14.1 DDL das tabelas do P06

```sql
-- Análise de isenção de licenciamento
CREATE TABLE CBM_ANALISE_LIC_ISENCAO (
    NRO_INT_ANALISE_LIC_ISENCAO    NUMBER(19)     NOT NULL,
    NRO_INT_LICENCIAMENTO          NUMBER(19)     NOT NULL,
    NRO_INT_VISTORIA               NUMBER(19),
    TP_STATUS                      VARCHAR2(20)   NOT NULL,
    TXT_JUSTIFICATIVA_ANTECIPACAO  VARCHAR2(4000),
    NRO_INT_USUARIO_SOE            NUMBER(19)     NOT NULL,
    NOME_USUARIO_SOE               VARCHAR2(64),
    CTR_DTH_INC                    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CTR_USR_INC                    NUMBER(19),
    CONSTRAINT PK_ANALISE_LIC_ISENCAO PRIMARY KEY (NRO_INT_ANALISE_LIC_ISENCAO),
    CONSTRAINT FK_ALI_LICENCIAMENTO FOREIGN KEY (NRO_INT_LICENCIAMENTO)
        REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO),
    CONSTRAINT FK_ALI_VISTORIA FOREIGN KEY (NRO_INT_VISTORIA)
        REFERENCES CBM_VISTORIA (NRO_INT_VISTORIA)
);
CREATE SEQUENCE CBM_ID_ANALISE_LIC_ISENCAO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Justificativas NCS para isenção de licenciamento
CREATE TABLE CBM_JUSTIFICATIVA_NCS_ISENCAO (
    NRO_INT_JUSTIF_NCS_ISENCAO     NUMBER(19)     NOT NULL,
    TXT_JUSTIFICATIVA              VARCHAR2(4000),
    NRO_INT_ANALISE_LIC_ISENCAO    NUMBER(19)     NOT NULL,
    NRO_INT_PARAMETRO_NCS          NUMBER(19)     NOT NULL,
    CONSTRAINT PK_JUSTIF_NCS_ISENCAO PRIMARY KEY (NRO_INT_JUSTIF_NCS_ISENCAO),
    CONSTRAINT FK_JNI_ANALISE FOREIGN KEY (NRO_INT_ANALISE_LIC_ISENCAO)
        REFERENCES CBM_ANALISE_LIC_ISENCAO (NRO_INT_ANALISE_LIC_ISENCAO),
    CONSTRAINT FK_JNI_PARAMETRO FOREIGN KEY (NRO_INT_PARAMETRO_NCS)
        REFERENCES CBM_PARAMETRO_NCS (NRO_INT_PARAMETRO_NCS)
);
CREATE SEQUENCE CBM_ID_JUSTIF_NCS_ISENCAO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Análise de isenção de FACT
CREATE TABLE CBM_ANALISE_FACT_ISENCAO (
    NRO_INT_ANALISE_FACT_ISENCAO   NUMBER(19)     NOT NULL,
    NRO_INT_LICENCIAMENTO          NUMBER(19),
    NRO_INT_FACT                   NUMBER(19)     NOT NULL,
    TP_STATUS                      VARCHAR2(20)   NOT NULL,
    TXT_JUSTIFICATIVA_ANTECIPACAO  VARCHAR2(4000),
    NRO_INT_USUARIO_SOE            NUMBER(19),
    NOME_USUARIO_SOE               VARCHAR2(64),
    CTR_DTH_INC                    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CTR_USR_INC                    NUMBER(19),
    CONSTRAINT PK_ANALISE_FACT_ISENCAO PRIMARY KEY (NRO_INT_ANALISE_FACT_ISENCAO),
    CONSTRAINT FK_AFI_LICENCIAMENTO FOREIGN KEY (NRO_INT_LICENCIAMENTO)
        REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO),
    CONSTRAINT FK_AFI_FACT FOREIGN KEY (NRO_INT_FACT)
        REFERENCES CBM_FACT (NRO_INT_FACT)
);
CREATE SEQUENCE CBM_ID_ANALISE_FACT_ISENCAO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Justificativas NCS para isenção de FACT
CREATE TABLE CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO (
    NRO_INT_JUSTIF_NCS_FACT_ISENCAO NUMBER(19)    NOT NULL,
    TXT_JUSTIFICATIVA               VARCHAR2(4000),
    NRO_INT_ANALISE_FACT_ISENCAO    NUMBER(19)    NOT NULL,
    NRO_INT_PARAMETRO_NCS           NUMBER(19)    NOT NULL,
    CONSTRAINT PK_JUSTIF_NCS_FACT_ISENCAO PRIMARY KEY (NRO_INT_JUSTIF_NCS_FACT_ISENCAO),
    CONSTRAINT FK_JNFI_ANALISE FOREIGN KEY (NRO_INT_ANALISE_FACT_ISENCAO)
        REFERENCES CBM_ANALISE_FACT_ISENCAO (NRO_INT_ANALISE_FACT_ISENCAO),
    CONSTRAINT FK_JNFI_PARAMETRO FOREIGN KEY (NRO_INT_PARAMETRO_NCS)
        REFERENCES CBM_PARAMETRO_NCS (NRO_INT_PARAMETRO_NCS)
);
CREATE SEQUENCE CBM_ID_JUSTIF_NCS_FACT_ISENCAO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Comprovantes de isenção
CREATE TABLE CBM_COMPROVANTE_ISENCAO (
    NRO_INT_COMPROVANTE_ISENCAO    NUMBER(19)     NOT NULL,
    NRO_INT_LICENCIAMENTO          NUMBER(19),
    NRO_INT_FACT                   NUMBER(19),
    NRO_INT_VISTORIA               NUMBER(19),
    NRO_INT_ARQUIVO                NUMBER(19)     NOT NULL,
    TXT_DESCRICAO                  VARCHAR2(255)  NOT NULL,
    CTR_DTH_INC                    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CTR_USR_INC                    NUMBER(19),
    CONSTRAINT PK_COMPROVANTE_ISENCAO PRIMARY KEY (NRO_INT_COMPROVANTE_ISENCAO),
    CONSTRAINT FK_CI_LICENCIAMENTO FOREIGN KEY (NRO_INT_LICENCIAMENTO)
        REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO),
    CONSTRAINT FK_CI_FACT FOREIGN KEY (NRO_INT_FACT)
        REFERENCES CBM_FACT (NRO_INT_FACT),
    CONSTRAINT FK_CI_VISTORIA FOREIGN KEY (NRO_INT_VISTORIA)
        REFERENCES CBM_VISTORIA (NRO_INT_VISTORIA),
    CONSTRAINT FK_CI_ARQUIVO FOREIGN KEY (NRO_INT_ARQUIVO)
        REFERENCES CBM_ARQUIVO (NRO_INT_ARQUIVO)
);
CREATE SEQUENCE CBM_ID_COMP_ISENCAO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Parâmetros NCS (já pode existir para outros processos)
CREATE TABLE CBM_PARAMETRO_NCS (
    NRO_INT_PARAMETRO_NCS    NUMBER(19)     NOT NULL,
    TXT_CHAVE                VARCHAR2(60)   NOT NULL,
    TXT_VALOR                VARCHAR2(255)  NOT NULL,
    IND_ATIVO                CHAR(1)        NOT NULL,
    NRO_ORDEM                NUMBER(10)     NOT NULL,
    CONSTRAINT PK_PARAMETRO_NCS PRIMARY KEY (NRO_INT_PARAMETRO_NCS),
    CONSTRAINT CHK_PARAMETRO_NCS_ATIVO CHECK (IND_ATIVO IN ('S', 'N'))
);
CREATE SEQUENCE CBM_ID_PARAMETRO_NCS_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;
```

### 14.2 Colunas adicionadas em tabelas existentes

```sql
-- Em CBM_LICENCIAMENTO:
ALTER TABLE CBM_LICENCIAMENTO ADD (
    TP_SITUACAO_ISENCAO       VARCHAR2(20),
    IND_ISENCAO               CHAR(1),
    DTH_SOLICITACAO_ISENCAO_TAXA  TIMESTAMP,
    CONSTRAINT CHK_LIC_IND_ISENCAO CHECK (IND_ISENCAO IN ('S', 'N') OR IND_ISENCAO IS NULL)
);

-- Em CBM_FACT (se não existirem):
ALTER TABLE CBM_FACT ADD (
    IND_ISENCAO      CHAR(1),
    CONSTRAINT CHK_FACT_IND_ISENCAO CHECK (IND_ISENCAO IN ('S', 'N') OR IND_ISENCAO IS NULL)
);
```

### 14.3 Tabelas de auditoria (Hibernate Envers)

O Envers gera automaticamente as tabelas `_AUD` para entidades anotadas com `@Audited`. As tabelas de auditoria espelham a estrutura das originais acrescidas das colunas `REV` (FK para `REVINFO`) e `REVTYPE` (0=INSERT, 1=UPDATE, 2=DELETE).

| Tabela principal | Tabela de auditoria |
|---|---|
| `CBM_ANALISE_LIC_ISENCAO` | `CBM_ANALISE_LIC_ISENCAO_AUD` |
| `CBM_ANALISE_FACT_ISENCAO` | `CBM_ANALISE_FACT_ISENCAO_AUD` |
| `CBM_COMPROVANTE_ISENCAO` | `CBM_COMPROVANTE_ISENCAO_AUD` |

### 14.4 Índices recomendados

```sql
CREATE INDEX IDX_ALI_LICENCIAMENTO ON CBM_ANALISE_LIC_ISENCAO(NRO_INT_LICENCIAMENTO);
CREATE INDEX IDX_AFI_FACT ON CBM_ANALISE_FACT_ISENCAO(NRO_INT_FACT);
CREATE INDEX IDX_CI_LICENCIAMENTO ON CBM_COMPROVANTE_ISENCAO(NRO_INT_LICENCIAMENTO);
CREATE INDEX IDX_CI_FACT ON CBM_COMPROVANTE_ISENCAO(NRO_INT_FACT);
CREATE INDEX IDX_LIC_SITUACAO_ISENCAO ON CBM_LICENCIAMENTO(TP_SITUACAO_ISENCAO);
CREATE INDEX IDX_PARAMETRO_NCS_CHAVE ON CBM_PARAMETRO_NCS(TXT_CHAVE);
```

### 14.5 Dados de configuração — `CBM_PARAMETRO_NCS`

```sql
-- Justificativas NCS para análise de isenção de taxa
INSERT INTO CBM_PARAMETRO_NCS (NRO_INT_PARAMETRO_NCS, TXT_CHAVE, TXT_VALOR, IND_ATIVO, NRO_ORDEM)
VALUES (CBM_ID_PARAMETRO_NCS_SEQ.NEXTVAL, 'APROVA_ISENCAOTAXA_PREANALISE', 'Entidade filantrópica reconhecida', 'S', 1);
INSERT INTO CBM_PARAMETRO_NCS (NRO_INT_PARAMETRO_NCS, TXT_CHAVE, TXT_VALOR, IND_ATIVO, NRO_ORDEM)
VALUES (CBM_ID_PARAMETRO_NCS_SEQ.NEXTVAL, 'APROVA_ISENCAOTAXA_PREANALISE', 'Órgão público municipal', 'S', 2);
INSERT INTO CBM_PARAMETRO_NCS (NRO_INT_PARAMETRO_NCS, TXT_CHAVE, TXT_VALOR, IND_ATIVO, NRO_ORDEM)
VALUES (CBM_ID_PARAMETRO_NCS_SEQ.NEXTVAL, 'APROVA_ISENCAOTAXA_PREANALISE', 'Entidade religiosa sem fins lucrativos', 'S', 3);
```

---

## Apêndice A — Mapa de Classes do P06

```
REST Layer (JAX-RS)
├── AnaliseLicenciamentoIsencaoRestImpl  (@Path "/adm/analise-licenciamentos-isencao", @SOEAuthRest)
├── AnaliseFactIsencaoRestImpl           (@Path "/adm/analises-fact-isencao", @SOEAuthRest)
├── ComprovanteIsencaoFactRestImpl       (@Path "/comprovantes-isencao-fact")
└── [LicenciamentoRestImpl]              (@Path "/licenciamentos", endpoints de comprovante e solicitação)

Business Rules Layer (EJB @Stateless)
├── AnaliseLicenciamentoIsencaoRN        → orchestrates P06-A approval/rejection
├── AnaliseFactIsencaoRN                 → orchestrates P06-B approval/rejection
├── ComprovanteIsencaoRN                 → manages proof documents (Alfresco)
├── LicenciamentoIsencaoRN               → exemption eligibility check
├── IsencaoTaxaReanaliseRN               → 30-day reanalysis deadline
├── AnaliseLicenciamentoIsencaoRNVal     → validates SOLICITADA/SOLICITADA_RENOV status
├── ParametroNcsRN                       → NCS justification parameters
├── JustificativaNcsIsencaoRN            → justification persistence (licensing)
└── JustificativaNcsFactIsencaoRN        → justification persistence (FACT)

Notification
└── LicenciamentoAdmNotificacaoRN        → email via SOE (notificarIsencaoDeTaxaRevisada)

State Transitions (TrocaEstado — @Stateless com CDI qualifier)
├── TrocaEstadoLicAguardandoPagamentoParaAguardandoDistribuicaoRN
├── TrocaEstadoLicAguardandoPagamentoParaAnaliseEnderecoPendenteRN
├── TrocaEstadoLicAguardandoPagamentoParaAnaliseInviabilidadePendenteRN
└── TrocaEstadoLicRenovacaoParaAguardandoDistribuicaoVistoriaRN

Data Layer (EJB @Stateless)
├── AnaliseLicenciamentoIsencaoBD
├── AnaliseFactIsencaoBD
├── ComprovanteIsencaoBD
├── JustificativaNcsIsencaoBD
├── JustificativaNcsFactIsencaoBD
└── ParametroNcsBD

Entities (@Entity @Audited)
├── AnaliseLicenciamentoIsencaoED    → CBM_ANALISE_LIC_ISENCAO
├── AnaliseFactIsencaoED             → CBM_ANALISE_FACT_ISENCAO
├── ComprovanteIsencaoED             → CBM_COMPROVANTE_ISENCAO
├── JustificativaNcsIsencaoED        → CBM_JUSTIFICATIVA_NCS_ISENCAO
├── JustificativaNcsFactIsencaoED    → CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO
└── ParametroNcsED                   → CBM_PARAMETRO_NCS

External Integrations
├── Alfresco (via ArquivoRN)         → file storage (identificadorAlfresco = nodeRef)
└── SOE PROCERGS (via SessionMB)     → user authentication & email notification
```

---

## Apêndice B — Marcos criados pelo P06

| Constante `TipoMarco` | Sub-processo | Criado quando |
|---|---|---|
| `SOLICITACAO_ISENCAO` | P06-A | Cidadão solicita isenção do licenciamento |
| `ANALISE_ISENCAO_APROVADO` | P06-A | ADM aprova isenção inicial |
| `ANALISE_ISENCAO_REPROVADO` | P06-A | ADM reprova isenção inicial |
| `ANALISE_ISENCAO_RENOV_APROVADO` | P06-A (renovação) | ADM aprova renovação de isenção |
| `ANALISE_ISENCAO_RENOV_REPROVADO` | P06-A (renovação) | ADM reprova renovação de isenção |
| `ENVIO_ATEC` | P06-A (TrocaEstado) | Após aprovação — licenciamento enviado para distribuição |
| `SOLICITACAO_ISENCAO_FACT` | P06-B | Cidadão solicita isenção do FACT |
| `NRO_FACT` | P06-B | FACT aprovado — número gerado |
| `ANALISE_ISENCAOFACT_APROVADO` | P06-B | ADM aprova isenção do FACT |
| `ANALISE_ISENCAOFACT_REPROVADO` | P06-B | ADM reprova isenção do FACT |
