# Requisitos P10 — Recurso Administrativo (Contestação de CIA/CIV)
## Stack Java Moderna — Sem Dependência PROCERGS

> Documento de requisitos destinado à equipe de desenvolvimento.
> Stack-alvo: **Spring Boot 3.x · Spring Security · Keycloak (OIDC/OAuth2) · PostgreSQL · MinIO · Jakarta EE 10 APIs**.
> Nenhuma dependência do SOE PROCERGS, WildFly ou Alfresco — todas as responsabilidades equivalentes
> são mapeadas para tecnologias de mercado abertas.

---

## S1 — Visão Geral do Processo

O processo P10 permite que os envolvidos em um licenciamento contestem formalmente uma decisão
desfavorável emitida pelo CBM-RS durante a análise técnica (CIA — Comunicado de Inconformidade
na Análise) ou durante a vistoria presencial (CIV — Comunicado de Inconformidade na Vistoria).

O recurso é uma via administrativa obrigatória antes de qualquer instância judicial. O sistema
prevê **duas instâncias recursais**:

| Instância | Responsável pela análise | Prazo para interposição |
|---|---|---|
| **1ª instância** | Chefe do CBM-RS (ou analista por ele designado) | 30 dias corridos após emissão da CIA/CIV |
| **2ª instância** | Comandante do CBM-RS (ou colegiado externo designado) | 15 dias corridos após a decisão de 1ª instância |

O recurso envolve dois grupos de atores:

| Ator | Papel |
|---|---|
| **Solicitante** (RT, RU ou Proprietário) | Inicia o recurso, preenche fundamentação, anexa documentos |
| **Demais envolvidos** (RT, RU, Proprietários co-signatários) | Devem aceitar formalmente antes do envio ao CBM |
| **Analista CBM** (1ª instância) | Recebe, analisa e decide sobre o recurso |
| **Comandante / Colegiado** (2ª instância) | Julgamento final, sem possibilidade de nova via recursiva interna |

### Restrições de Escopo

- Aplicável apenas a licenciamentos com CIA ou CIV emitidos e não contestados previamente.
- O campo `recurso_bloqueado` no licenciamento, quando `true`, impede qualquer novo recurso
  (sinaliza que o ciclo recursivo já foi esgotado ou que existe recurso ativo para outro CIA/CIV).
- A 2ª instância somente pode ser aberta se a 1ª instância foi concluída com `StatusRecurso.INDEFERIDO`
  ou `StatusRecurso.DEFERIDO_PARCIAL`.
- Apenas um recurso pode estar ativo (situacao != CANCELADO e != ANALISE_CONCLUIDA) por
  combinação licenciamento + arquivoCiaCiv + instancia.

### Estados do Licenciamento durante P10

| Estado do Licenciamento | Quando é atribuído |
|---|---|
| `RECURSO_EM_ANALISE_1_CIA` | Recurso de 1ª instância sobre CIA aceito por todos e enviado ao CBM |
| `RECURSO_EM_ANALISE_2_CIA` | Recurso de 2ª instância sobre CIA aceito e enviado |
| `RECURSO_EM_ANALISE_1_CIV` | Recurso de 1ª instância sobre CIV aceito e enviado |
| `RECURSO_EM_ANALISE_2_CIV` | Recurso de 2ª instância sobre CIV aceito e enviado |

---

## S2 — Modelo de Dados

### 2.1 Entidade `Recurso`

Tabela: **`sol_recurso`**

```java
@Entity
@Table(name = "sol_recurso")
public class Recurso {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Licenciamento ao qual este recurso se refere.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    /**
     * Instancia recursal: 1 = primeira instancia, 2 = segunda instancia.
     */
    @Column(name = "instancia", nullable = false)
    private Integer instancia;

    /**
     * Situacao atual do recurso no seu ciclo de vida.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false, length = 40)
    private SituacaoRecurso situacao;

    /**
     * Tipo do recurso: contestacao de analise tecnica (CIA) ou de vistoria (CIV).
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_recurso", nullable = false, length = 1)
    private TipoRecurso tipoRecurso;

    /**
     * Escopo do pedido: integral (reabertura total) ou parcial (contestacao de pontos especificos).
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_solicitacao", length = 1)
    private TipoSolicitacaoRecurso tipoSolicitacao;

    /**
     * Texto de fundamentacao legal obrigatorio — argumentacao juridica e tecnica do recorrente.
     */
    @Column(name = "fundamentacao_legal", length = 4000)
    private String fundamentacaoLegal;

    /**
     * Data e hora em que o recurso foi enviado para analise (apos todos os aceites).
     */
    @Column(name = "dth_envio_analise")
    private OffsetDateTime dataEnvioAnalise;

    /**
     * Arquivo CIA ou CIV que originou o recurso.
     * Referencia o nodeRef MinIO do documento emitido pelo CBM.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_arquivo_cia_civ", nullable = false)
    private Arquivo arquivoCiaCiv;

    /**
     * Subject do token JWT (UUID Keycloak) do usuario que abriu o recurso.
     */
    @Column(name = "id_usuario_keycloak", nullable = false, length = 36)
    private String idUsuarioKeycloak;

    /**
     * Controle de bloqueio — impede abertura de novo recurso enquanto este esta ativo.
     */
    @Column(name = "recurso_bloqueado", nullable = false)
    private Boolean recursoBloqueado = false;

    /**
     * Data/hora de criacao do registro.
     */
    @Column(name = "dth_criacao", nullable = false, updatable = false)
    private OffsetDateTime dthCriacao;

    // Colecoes de co-signatarios (envolvidos que precisam aceitar)
    @OneToMany(mappedBy = "recurso", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<SolicitacaoRtRecurso> solicitacoesRt = new ArrayList<>();

    @OneToMany(mappedBy = "recurso", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<SolicitacaoRuRecurso> solicitacoesRu = new ArrayList<>();

    @OneToMany(mappedBy = "recurso", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<SolicitacaoProprietarioRecurso> solicitacoesProprietario = new ArrayList<>();
}
```

**DDL PostgreSQL:**

```sql
CREATE TABLE sol_recurso (
    id                  BIGSERIAL     PRIMARY KEY,
    id_licenciamento    BIGINT        NOT NULL REFERENCES sol_licenciamento(id),
    instancia           SMALLINT      NOT NULL CHECK (instancia IN (1, 2)),
    situacao            VARCHAR(40)   NOT NULL DEFAULT 'RASCUNHO',
    tipo_recurso        VARCHAR(1)    NOT NULL,   -- 'A' CIA, 'V' CIV
    tipo_solicitacao    VARCHAR(1),               -- 'I' integral, 'P' parcial
    fundamentacao_legal VARCHAR(4000),
    dth_envio_analise   TIMESTAMPTZ,
    id_arquivo_cia_civ  BIGINT        NOT NULL REFERENCES sol_arquivo(id),
    id_usuario_keycloak VARCHAR(36)   NOT NULL,
    recurso_bloqueado   BOOLEAN       NOT NULL DEFAULT FALSE,
    dth_criacao         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_recurso_ativo UNIQUE (id_licenciamento, id_arquivo_cia_civ, instancia)
    -- garante unicidade por licenciamento + documento + instancia
);

-- Indice parcial: apenas um recurso ativo (nao concluido) por licenciamento + instancia
CREATE UNIQUE INDEX idx_recurso_ativo
    ON sol_recurso (id_licenciamento, instancia)
    WHERE situacao NOT IN ('ANALISE_CONCLUIDA', 'CANCELADO');
```

---

### 2.2 Entidade `AnaliseRecurso`

Tabela: **`sol_analise_recurso`**

```java
@Entity
@Table(name = "sol_analise_recurso")
public class AnaliseRecurso {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Recurso ao qual esta analise pertence (relacao 1:1).
     */
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_recurso", nullable = false, unique = true)
    private Recurso recurso;

    /**
     * Resultado final da analise.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 1)
    private StatusRecurso status;

    /**
     * Texto do despacho: fundamentacao da decisao do analista CBM.
     */
    @Column(name = "despacho", length = 8000)
    private String despacho;

    /**
     * Subject JWT (UUID Keycloak) do analista CBM designado.
     * Obrigatorio — nao pode ser nulo apos distribuicao.
     */
    @Column(name = "id_analista_keycloak", nullable = false, length = 36)
    private String idAnalistaKeycloak;

    /**
     * Data/hora em que o analista deu ciencia do recurso (confirmou o recebimento).
     */
    @Column(name = "dth_ciencia_analista")
    private OffsetDateTime dthCienciaAnalista;

    /**
     * Indica se o analista confirmou ciencia. null = aguardando, true = confirmou.
     */
    @Column(name = "ind_ciencia")
    private Boolean ciencia;

    /**
     * Arquivo com a decisao formalizada (PDF assinado, armazenado no MinIO).
     */
    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_arquivo_decisao")
    private Arquivo arquivoDecisao;

    /**
     * Situacao interna da analise (controle de fluxo do analista).
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_analise", nullable = false, length = 40)
    private SituacaoAnaliseRecurso situacaoAnalise;

    /**
     * Data/hora de conclusao da analise.
     */
    @Column(name = "dth_conclusao_analise")
    private OffsetDateTime dthConclusaoAnalise;
}
```

**DDL PostgreSQL:**

```sql
CREATE TABLE sol_analise_recurso (
    id                    BIGSERIAL    PRIMARY KEY,
    id_recurso            BIGINT       NOT NULL UNIQUE REFERENCES sol_recurso(id),
    status                VARCHAR(1),              -- 'T' total, 'P' parcial, 'I' indeferido
    despacho              VARCHAR(8000),
    id_analista_keycloak  VARCHAR(36)  NOT NULL,
    dth_ciencia_analista  TIMESTAMPTZ,
    ind_ciencia           BOOLEAN,
    id_arquivo_decisao    BIGINT       REFERENCES sol_arquivo(id),
    situacao_analise      VARCHAR(40)  NOT NULL DEFAULT 'EM_ANALISE',
    dth_conclusao_analise TIMESTAMPTZ
);
```

---

### 2.3 Entidades de Co-signatarios

O recurso exige aceite formal de todos os envolvidos do licenciamento. Cada grupo tem sua
tabela de controle de aceite:

```sql
-- Co-signatarios RT
CREATE TABLE sol_solicitacao_rt_recurso (
    id            BIGSERIAL   PRIMARY KEY,
    id_recurso    BIGINT      NOT NULL REFERENCES sol_recurso(id),
    id_usuario_kc VARCHAR(36) NOT NULL,   -- Subject JWT do RT
    ind_aceite    BOOLEAN,                -- null = pendente, true = aceito, false = recusado
    dth_aceite    TIMESTAMPTZ
);

-- Co-signatarios RU
CREATE TABLE sol_solicitacao_ru_recurso (
    id            BIGSERIAL   PRIMARY KEY,
    id_recurso    BIGINT      NOT NULL REFERENCES sol_recurso(id),
    id_usuario_kc VARCHAR(36) NOT NULL,
    ind_aceite    BOOLEAN,
    dth_aceite    TIMESTAMPTZ
);

-- Co-signatarios Proprietarios
CREATE TABLE sol_solicitacao_prop_recurso (
    id            BIGSERIAL   PRIMARY KEY,
    id_recurso    BIGINT      NOT NULL REFERENCES sol_recurso(id),
    id_usuario_kc VARCHAR(36) NOT NULL,
    ind_aceite    BOOLEAN,
    dth_aceite    TIMESTAMPTZ
);
```

---

## S3 — Enumeracoes

### 3.1 `SituacaoRecurso`

Ciclo de vida do recurso do ponto de vista do cidadao:

| Valor | Codigo BD | Significado |
|---|---|---|
| `RASCUNHO` | `R` | Recurso salvo mas nao submetido (ainda editavel) |
| `AGUARDANDO_APROVACAO_ENVOLVIDOS` | `E` | Submetido — aguardando aceite de todos os envolvidos |
| `AGUARDANDO_DISTRIBUICAO` | `D` | Todos aceitaram — aguardando designacao de analista CBM |
| `EM_ANALISE` | `A` | Analista designado — em analise |
| `ANALISE_CONCLUIDA` | `C` | Decisao proferida e registrada |
| `CANCELADO` | `CA` | Cancelado pelo solicitante ou por rejeicao de envolvido |

### 3.2 `TipoRecurso`

| Valor | Codigo BD | Significado |
|---|---|---|
| `CORRECAO_DE_ANALISE` | `A` | Contestacao de CIA (inconformidade na analise tecnica) |
| `CORRECAO_DE_VISTORIA` | `V` | Contestacao de CIV (inconformidade na vistoria presencial) |

### 3.3 `TipoSolicitacaoRecurso`

| Valor | Codigo BD | Significado |
|---|---|---|
| `INTEGRAL` | `I` | Solicita reabertura total da analise/vistoria |
| `PARCIAL` | `P` | Contesta apenas pontos especificos do comunicado |

### 3.4 `StatusRecurso` (resultado da analise CBM)

| Valor | Codigo BD | Significado |
|---|---|---|
| `DEFERIDO_TOTAL` | `T` | Recurso totalmente acolhido — retorna ao fluxo P04 ou P07 |
| `DEFERIDO_PARCIAL` | `P` | Acolhido parcialmente — pode gerar 2ª instancia |
| `INDEFERIDO` | `I` | Negado — pode gerar 2ª instancia ou esgota via recursal |

### 3.5 `SituacaoAnaliseRecurso` (estado interno do analista CBM)

| Valor | Significado |
|---|---|
| `EM_ANALISE` | Analista designado, trabalhando na analise |
| `AGUARDANDO_AVALIACAO_COLEGIADO` | Apenas 2ª instancia — aguardando votacao colegiada |
| `ANALISE_CONCLUIDA` | Decisao proferida e formalizada |

---

## S4 — Regras de Negocio

### RN-073 — Tipo de Solicitacao Obrigatorio

O campo `tipoSolicitacao` (INTEGRAL ou PARCIAL) e obrigatorio no momento da submissao final
do recurso. Durante o rascunho, pode ser nulo. A API deve rejeitar com HTTP 422 se ausente
no momento de `realizarAceite`.

### RN-074 — Tipo de Recurso Obrigatorio

O campo `tipoRecurso` e obrigatorio e imutavel apos a criacao. Deve ser CORRECAO_DE_ANALISE
para contestar CIA ou CORRECAO_DE_VISTORIA para contestar CIV.

### RN-075 — Instancia Obrigatoria e Validada

O campo `instancia` deve ser 1 ou 2. Para instancia = 2, o sistema deve verificar que
existe uma AnaliseRecurso concluida (ANALISE_CONCLUIDA) para o mesmo licenciamento e
o mesmo arquivoCiaCiv na instancia 1, com status INDEFERIDO ou DEFERIDO_PARCIAL.

### RN-076 — Fundamentacao Legal Obrigatoria na Submissao

O campo `fundamentacaoLegal` pode ser salvo em rascunho como nulo, mas deve estar
preenchido com no minimo 50 caracteres no momento de `realizarAceite`. A API deve
rejeitar com HTTP 422 se vazio ou abaixo do minimo.

### RN-077 — Licenciamento Deve Existir e ser Acessivel

O `idLicenciamento` deve referenciar um licenciamento existente ao qual o usuario
autenticado tenha vinculo (RT, RU ou Proprietario).

### RN-078 — Arquivo CIA/CIV Valido

O `idArquivoCiaCiv` deve referenciar um arquivo associado ao licenciamento informado,
do tipo CIA (se tipoRecurso = CORRECAO_DE_ANALISE) ou CIV (se CORRECAO_DE_VISTORIA),
e que nao tenha sido anulado.

### RN-079 — Ao Menos Um Envolvido Co-signatario

Alem do solicitante, o recurso deve ter ao menos um co-signatario (RT, RU ou Proprietario).
A API deve rejeitar com HTTP 422 se as listas de CPF/IDs de envolvidos estiverem
todas vazias no momento da criacao.

### RN-080 — Prazo de Interposicao da 1ª Instancia

O recurso de 1ª instancia deve ser criado dentro de **30 dias corridos** da data de emissao
do arquivo CIA/CIV. O backend calcula `dataEmissaoCiaCiv + 30 dias` e rejeita com HTTP 422
se a data atual ultrapassar esse limite.

### RN-081 — Prazo de Interposicao da 2ª Instancia

O recurso de 2ª instancia deve ser criado dentro de **15 dias corridos** da data de conclusao
da analise de 1ª instancia (`AnaliseRecurso.dthConclusaoAnalise`). Rejeitar com HTTP 422
se ultrapassado.

### RN-082 — Recurso Bloqueado

Se `licenciamento.recursoBloqueado = true`, a API deve rejeitar qualquer tentativa de
criar novo recurso com HTTP 406 (Not Acceptable) e mensagem descritiva.

### RN-083 — Selecao de RT por Tipo de Recurso

Ao incluir co-signatarios RT, o sistema filtra os RTs vinculados ao licenciamento conforme
o tipo de recurso:

| TipoRecurso | Tipos de responsabilidade RT aceitos |
|---|---|
| `CORRECAO_DE_ANALISE` | `PROJETO`, `PROJETO_EXECUCAO` |
| `CORRECAO_DE_VISTORIA` | `EXECUCAO`, `PROJETO_EXECUCAO` |

Um CPF informado que nao corresponda a um RT do tipo adequado deve ser ignorado ou
gerar aviso sem bloquear a criacao.

### RN-084 — Unanimidade nos Aceites

O recurso somente avanca de `AGUARDANDO_APROVACAO_ENVOLVIDOS` para
`AGUARDANDO_DISTRIBUICAO` quando **todos** os co-signatarios (RT, RU e Proprietarios)
tiverem `ind_aceite = true`. O check deve ser atomico: apos cada aceite individual,
o servico verifica a condicao de completude.

### RN-085 — Cancelamento Antes do Envio

O solicitante pode cancelar o recurso enquanto `situacao IN (RASCUNHO, AGUARDANDO_APROVACAO_ENVOLVIDOS)`.
Apos envio ao CBM (situacao = AGUARDANDO_DISTRIBUICAO ou alem), o cancelamento so e
permitido por operadores CBM via endpoint administrativo.

### RN-086 — Immutabilidade apos Envio ao CBM

Apos transicao para `AGUARDANDO_DISTRIBUICAO`, os campos `tipoRecurso`, `instancia`,
`idArquivoCiaCiv` e a lista de co-signatarios tornam-se imutaveis.
`fundamentacaoLegal` e `tipoSolicitacao` continuam editaveis ate `EM_ANALISE`,
mediante operacao `habilitarEdicao` autorizada por operador CBM.

### RN-087 — Notificacao por E-mail nos Marcos

O sistema deve enviar notificacao por e-mail nos seguintes eventos:
- Criacao do recurso (para todos os co-signatarios, pedindo aceite).
- Aceite de um RT (notificar os demais RTs pendentes).
- Todos aceitaram (notificar todos os RTs com o termo de ciencia).
- Distribuicao para analista (notificar solicitante).
- Conclusao da analise (notificar todos os envolvidos com o resultado).

### RN-088 — Resultado da Analise e Efeito no Licenciamento

Apos o analista CBM concluir a analise (`StatusRecurso`), o sistema deve:

| StatusRecurso | Acao no Licenciamento |
|---|---|
| `DEFERIDO_TOTAL` | Retornar situacao do licenciamento ao estado anterior ao CIA/CIV — reiniciar P04 ou P07 |
| `DEFERIDO_PARCIAL` | Manter situacao com pendencias especificas; habilitar abertura de 2ª instancia |
| `INDEFERIDO` | Manter situacao do licenciamento; habilitar abertura de 2ª instancia (se 1ª inst.) ou encerrar via recursiva (se 2ª inst.) |

### RN-089 — Bloqueio apos Exaurimento Recursivo

Apos conclusao da 2ª instancia (qualquer status), o sistema deve setar
`licenciamento.recursoBloqueado = true` para o licenciamento, impedindo novos recursos
sobre o mesmo CIA/CIV.

### RN-090 — Marcos de Auditoria do Recurso

O sistema deve registrar marcos (`RecursoMarco`) nos seguintes eventos:

| TipoMarco | Momento | Visibilidade |
|---|---|---|
| `RECURSO_SOLICITADO` | Criacao do recurso | Cidadao + CBM |
| `RECURSO_ACEITE_ENVOLVIDO` | Cada aceite individual | Cidadao + CBM |
| `RECURSO_TODOS_ACEITARAM` | Ultimo aceite (unanimidade) | Cidadao + CBM |
| `RECURSO_ENVIADO_ANALISE` | Transicao para AGUARDANDO_DISTRIBUICAO | Cidadao + CBM |
| `RECURSO_DISTRIBUIDO` | Designacao de analista | CBM |
| `RECURSO_CONCLUIDO` | Decisao registrada | Cidadao + CBM |

---

## S5 — Endpoints REST — Cidadao (publico autenticado)

Base path: `/api/v1/recursos`

Autenticacao: Bearer token JWT emitido pelo Keycloak. O subject (UUID) e extraido do token
e usado como identificador do usuario. Nenhuma dependencia do SOE PROCERGS.

### 5.1 `POST /api/v1/recursos` — Registrar Recurso

Cria um novo recurso. O estado inicial e `RASCUNHO` se `aceite = false`, ou
`AGUARDANDO_APROVACAO_ENVOLVIDOS` se `aceite = true` e todas as validacoes passarem.

**Request body:**

```json
{
  "idLicenciamento": 12345,
  "instancia": 1,
  "tipoRecurso": "CORRECAO_DE_ANALISE",
  "tipoSolicitacao": "INTEGRAL",
  "fundamentacaoLegal": "Conforme art. 5 do Decreto...",
  "idArquivoCiaCiv": 6789,
  "aceite": true,
  "cpfsRt": ["12345678901"],
  "cpfsRu": ["98765432100"],
  "cpfsProprietarios": ["11122233344"]
}
```

**Validacoes:** RN-073 a RN-083.

**Response:** HTTP 201 com `RecursoResponseDTO`.

---

### 5.2 `GET /api/v1/recursos/{recursoId}` — Consultar Recurso por ID

Retorna os dados completos do recurso, incluindo situacao, co-signatarios e historico
de aceites. O usuario autenticado deve ser solicitante ou co-signatario do recurso.

**Response:** HTTP 200 com `RecursoResponseDTO`.

---

### 5.3 `PUT /api/v1/recursos/{recursoId}` — Aceitar / Alterar Recurso

Permite ao usuario:
- Editar `fundamentacaoLegal` e `tipoSolicitacao` (se recurso editavel).
- Registrar seu aceite (`aceite: true`) se for co-signatario com aceite pendente.

**Request body:**

```json
{
  "fundamentacaoLegal": "Texto atualizado...",
  "tipoSolicitacao": "PARCIAL",
  "aceite": true
}
```

**Validacoes:** RN-076, RN-084.

**Response:** HTTP 200 com `RecursoResponseDTO` atualizado.

---

### 5.4 `PUT /api/v1/recursos/{recursoId}/salvar` — Salvar Rascunho

Salva alteracoes em rascunho sem disparar validacoes de completude.
Util para edicao incremental antes da submissao final.

**Response:** HTTP 200 com `RecursoResponseDTO`.

---

### 5.5 `GET /api/v1/recursos` — Listar Recursos do Usuario

Lista os recursos em que o usuario autenticado e solicitante ou co-signatario.
Suporta paginacao e filtros.

**Query params:**

| Parametro | Tipo | Descricao |
|---|---|---|
| `pagina` | int | Pagina atual (0-based) |
| `tamanho` | int | Itens por pagina (max 50) |
| `situacoes` | List\<String\> | Filtrar por situacao |
| `tipoRecurso` | List\<String\> | Filtrar por tipo |
| `numeroLicenciamento` | String | Filtrar por numero do licenciamento |
| `recursoId` | Long | Filtrar por ID exato |
| `ordenar` | String | Campo de ordenacao |
| `ordem` | `ASC`\|`DESC` | Direcao |

**Response:** HTTP 200 com `Page<RecursoResumoDTO>`.

---

### 5.6 `GET /api/v1/recursos/{recursoId}/historico` — Historico de Marcos

Retorna os marcos de auditoria do recurso em ordem cronologica.

**Response:** HTTP 200 com `List<RecursoMarcoDTO>`.

---

### 5.7 `DELETE /api/v1/recursos/{recursoId}/cancelar` — Cancelar Recurso

Cancela o recurso se `situacao IN (RASCUNHO, AGUARDANDO_APROVACAO_ENVOLVIDOS)`.
Apenas o solicitante original pode cancelar.
Registra marco `RECURSO_CANCELADO`.

**Response:** HTTP 204.

---

### 5.8 `PUT /api/v1/recursos/{recursoId}/recusar` — Recusar Recurso (Co-signatario)

Permite a um co-signatario recusar o aceite, cancelando o recurso imediatamente.
Registra marco e notifica todos os envolvidos.

**Response:** HTTP 200.

---

## S6 — Endpoints REST — Administracao CBM

Base path: `/api/v1/adm/recursos`

Autenticacao: Bearer token JWT com roles CBM. O sistema verifica a role `ANALISTA_CBM` ou
`ADMIN_CBM` via Spring Security. Sem dependencia do SOE PROCERGS.

### 6.1 `GET /api/v1/adm/recursos` — Listar Recursos (Visao Admin)

Lista todos os recursos com filtros avancados para a tela de gestao do CBM.

**Query params:**

| Parametro | Tipo | Descricao |
|---|---|---|
| `pagina` / `tamanho` | int | Paginacao |
| `instancia` | int | Filtrar por instancia (1 ou 2) |
| `tipoRecurso` | String | CORRECAO_DE_ANALISE ou CORRECAO_DE_VISTORIA |
| `numeroLicenciamento` | String | Numero do licenciamento |
| `situacaoRecurso` | List\<String\> | Filtrar por situacao |
| `logradouro` | String | Endereco do estabelecimento |
| `cidade` | String | Cidade do estabelecimento |
| `nomeSolicitante` | String | Nome do solicitante |
| `dataInicioSolicitacao` | Date | Intervalo de datas de solicitacao |
| `dataFimSolicitacao` | Date | Intervalo de datas |
| `ordenar` / `ordem` | String | Ordenacao |

**Response:** HTTP 200 com `Page<RecursoAdmResumoDTO>`.

---

### 6.2 `GET /api/v1/adm/recursos/{recursoId}/marcos` — Marcos do Recurso (Admin)

Retorna todos os marcos de auditoria do recurso (inclusive os invisiveis ao cidadao).

**Response:** HTTP 200 com `List<RecursoMarcoDTO>`.

---

### 6.3 `PUT /api/v1/adm/recursos/{licenciamentoId}/reserva` — Bloquear/Desbloquear Recurso

Alterna o flag `recursoBloqueado` do licenciamento. Operacao administrativa para
situacoes excepcionais (decisao judicial, erro administrativo).

**Response:** HTTP 200.

---

### 6.4 `GET /api/v1/adm/recurso-analise/distribuicao` — Listar para Distribuicao

Lista recursos em `AGUARDANDO_DISTRIBUICAO` que ainda nao possuem analista designado.

**Response:** HTTP 200 com `Page<RecursoAdmResumoDTO>`.

---

### 6.5 `GET /api/v1/adm/recurso-analise/pendentes` — Listar Analises Pendentes

Lista recursos em `EM_ANALISE` com analista designado porem sem conclusao.

**Response:** HTTP 200 com `Page<RecursoAdmResumoDTO>`.

---

### 6.6 `GET /api/v1/adm/recurso-analise/analistas` — Listar Analistas Disponiveis

Retorna lista de analistas CBM cadastrados no Keycloak (role `ANALISTA_CBM`),
com indicador de carga de trabalho (quantidade de recursos em analise).

**Response:** HTTP 200 com `List<AnalistaDTO>`.

---

### 6.7 `PUT /api/v1/adm/recurso-analise/distribuir` — Distribuir Recurso para Analista

Designa um analista para um recurso em `AGUARDANDO_DISTRIBUICAO`.
Transiciona o recurso para `EM_ANALISE` e cria a entidade `AnaliseRecurso`.
Registra marco `RECURSO_DISTRIBUIDO` e notifica o analista por e-mail.

**Request body:**

```json
{
  "recursoId": 456,
  "idAnalistaKeycloak": "uuid-do-analista-no-keycloak"
}
```

**Response:** HTTP 200.

---

### 6.8 `PUT /api/v1/adm/recurso-analise/{recursoId}/cancelar-distribuicao` — Cancelar Designacao

Remove a designacao do analista e retorna o recurso para `AGUARDANDO_DISTRIBUICAO`.
Util em casos de impedimento ou conflito de interesse.

**Response:** HTTP 200.

---

### 6.9 `GET /api/v1/adm/recurso-analise/{recursoId}` — Consultar Recurso (Analista)

Retorna os dados completos do recurso incluindo a AnaliseRecurso em andamento,
todos os documentos e o historico de marcos.

**Response:** HTTP 200 com `RecursoAdmDetalheDTO`.

---

### 6.10 `GET /api/v1/adm/recurso-analise/analise/{recursoId}` — Consultar Analise

Retorna apenas a entidade `AnaliseRecurso` do recurso informado.

**Response:** HTTP 200 com `AnaliseRecursoDTO`.

---

### 6.11 `POST /api/v1/adm/recurso-analise` — Analisar Recurso (1ª Instancia)

O analista CBM registra a decisao da 1ª instancia. Transiciona:
- `AnaliseRecurso.situacaoAnalise` para `ANALISE_CONCLUIDA`
- `Recurso.situacao` para `ANALISE_CONCLUIDA`
- `AnaliseRecurso.status` para o valor informado (DEFERIDO_TOTAL / DEFERIDO_PARCIAL / INDEFERIDO)
- Executa RN-088 (efeito no licenciamento)
- Executa RN-089 se instancia = 2

**Request body:**

```json
{
  "recursoId": 456,
  "status": "DEFERIDO_TOTAL",
  "despacho": "Apos analise, constata-se que...",
  "idArquivoDecisao": 9999
}
```

**Response:** HTTP 200.

---

### 6.12 `POST /api/v1/adm/recurso-analise/segunda-instancia` — Analisar Recurso (2ª Instancia)

Identico ao 6.11, porem com logica adicional de colegiado:
- Pode transitar por `AGUARDANDO_AVALIACAO_COLEGIADO` antes da conclusao.
- Ao concluir, executa RN-089 (bloqueio definitivo).

**Response:** HTTP 200.

---

### 6.13 `PUT /api/v1/adm/recurso-analise/{recursoId}/habilitar-edicao` — Habilitar Edicao

Permite ao analista reabrir a edicao de `fundamentacaoLegal` e `tipoSolicitacao`
pelo cidadao, mesmo apos envio ao CBM. Usado em casos excepcionais de complementacao.

**Response:** HTTP 200.

---

## S7 — Maquina de Estados

### 7.1 Ciclo de Vida do Recurso (`SituacaoRecurso`)

```
[Cidadao] POST /recursos
    |
    v
RASCUNHO ──salvar (sem aceite)──> RASCUNHO (loop)
    |
    | aceite=true, validacoes OK
    v
AGUARDANDO_APROVACAO_ENVOLVIDOS
    |                             |
    | todos aceitaram             | qualquer envolvido recusou
    v                             v
AGUARDANDO_DISTRIBUICAO        CANCELADO
    |
    | analista designado
    v
EM_ANALISE
    |
    | decisao registrada
    v
ANALISE_CONCLUIDA
    |
    | (resultado DEFERIDO_PARCIAL ou INDEFERIDO e instancia=1)
    v
[Possibilidade de abertura de 2ª instancia — novo Recurso com instancia=2]
```

### 7.2 Ciclo de Vida da AnaliseRecurso (`SituacaoAnaliseRecurso`)

```
[criada na distribuicao]
    |
    v
EM_ANALISE
    |                             |
    | 1ª instancia                | 2ª instancia (opcional)
    v                             v
ANALISE_CONCLUIDA     AGUARDANDO_AVALIACAO_COLEGIADO
                                  |
                                  | votacao concluida
                                  v
                            ANALISE_CONCLUIDA
```

---

## S8 — Seguranca e Controle de Acesso

### 8.1 Roles Keycloak

| Role | Descricao | Permissoes |
|---|---|---|
| `CIDADAO` | Qualquer usuario autenticado | Criar, consultar, aceitar e cancelar seus proprios recursos |
| `ANALISTA_CBM` | Analista tecnico do corpo de bombeiros | Distribuicao, analise, conclusao, habilitacao de edicao |
| `ADMIN_CBM` | Administrador do sistema CBM | Todas as operacoes, inclusive bloqueio de recurso |

### 8.2 Regras de Autorizacao por Endpoint

| Endpoint | Role minima | Regra adicional |
|---|---|---|
| `POST /recursos` | `CIDADAO` | Usuario autenticado deve ter vinculo com o licenciamento |
| `GET /recursos/{id}` | `CIDADAO` | Deve ser solicitante ou co-signatario |
| `PUT /recursos/{id}` | `CIDADAO` | Idem — e co-signatario com aceite pendente |
| `DELETE /recursos/{id}/cancelar` | `CIDADAO` | Deve ser o solicitante original |
| `GET /adm/recursos/**` | `ANALISTA_CBM` | — |
| `PUT /adm/recurso-analise/distribuir` | `ADMIN_CBM` | — |
| `POST /adm/recurso-analise` | `ANALISTA_CBM` | Deve ser o analista designado para o recurso |
| `POST /adm/recurso-analise/segunda-instancia` | `ANALISTA_CBM` | Idem |
| `PUT /adm/recursos/{id}/reserva` | `ADMIN_CBM` | — |

### 8.3 Extracao de Identidade

O JWT emitido pelo Keycloak contem o campo `sub` (subject UUID) que identifica
univocamente o usuario. Substituicao direta do `idUsuarioSoe` da stack legada.

```java
// Spring Security — extrair subject do token
@AuthenticationPrincipal Jwt jwt
String userUuid = jwt.getSubject(); // equivalente ao idUsuarioSoe
```

Todos os registros de auditoria, marcos e co-signatarios usam o UUID Keycloak
como identificador persistente do usuario.

---

## S9 — Integracao com MinIO (substituto do Alfresco)

O campo `arquivoCiaCiv` referencia um documento de CIA ou CIV previamente armazenado
no MinIO. Os documentos de decisao produzidos durante a analise tambem sao armazenados
no MinIO.

### 9.1 Upload do Documento de Fundamentacao

O cidadao pode anexar documentos adicionais de suporte ao recurso. Fluxo:

```
1. POST /api/v1/arquivos/upload        -- retorna { arquivoId, bucketPath }
2. POST /api/v1/recursos               -- inclui idArquivoCiaCiv no body
```

### 9.2 Upload do Documento de Decisao (Analista CBM)

```
1. POST /api/v1/adm/arquivos/upload    -- analista sobe o PDF da decisao
2. POST /api/v1/adm/recurso-analise    -- inclui idArquivoDecisao no body
```

### 9.3 Configuracao do MinIO

```yaml
# application.yml
minio:
  endpoint: http://minio:9000
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket-documentos: sol-documentos
```

---

## S10 — Notificacoes por E-mail

O sistema deve enviar e-mails transacionais nos eventos a seguir, substituindo o modulo
de notificacao do SOE PROCERGS por um servico proprio baseado em Spring Mail / SES.

| Evento | Destinatarios | Template |
|---|---|---|
| Recurso criado | Todos os co-signatarios | Pedido de aceite com link para o portal |
| Aceite de RT realizado | Demais RTs ainda pendentes | Lembrete de aceite pendente |
| Unanimidade atingida | Todos os RTs (termo de ciencia) | Confirmacao de participacao |
| Distribuicao para analista | Solicitante | Recurso enviado para analise |
| Conclusao da analise | Todos os envolvidos | Resultado com link para consultar decisao |
| Cancelamento | Todos os co-signatarios | Informativo de cancelamento |

Templates devem ser gerenciados por arquivo `.html` no classpath, sem hardcode de
strings no codigo Java. Configurar variaveis de ambiente para remetente e URLs do portal.

---

## S11 — DTOs Principais

### 11.1 `RecursoRequestDTO` (request de criacao/edicao)

```java
public record RecursoRequestDTO(
    Long idLicenciamento,
    Integer instancia,
    TipoRecurso tipoRecurso,
    TipoSolicitacaoRecurso tipoSolicitacao,
    String fundamentacaoLegal,
    Long idArquivoCiaCiv,
    boolean aceite,
    List<String> cpfsRt,
    List<String> cpfsRu,
    List<String> cpfsProprietarios
) {}
```

### 11.2 `RecursoResponseDTO` (response para o cidadao)

```java
public record RecursoResponseDTO(
    Long id,
    Long idLicenciamento,
    String numeroLicenciamento,
    Integer instancia,
    SituacaoRecurso situacao,
    TipoRecurso tipoRecurso,
    TipoSolicitacaoRecurso tipoSolicitacao,
    String fundamentacaoLegal,
    OffsetDateTime dataEnvioAnalise,
    Long idArquivoCiaCiv,
    List<SolicitanteDTO> coSignatariosRt,
    List<SolicitanteDTO> coSignatariosRu,
    List<SolicitanteDTO> coSignatariosProprietario,
    boolean editavel
) {}
```

### 11.3 `AnaliseRecursoRequestDTO` (request de conclusao pelo analista)

```java
public record AnaliseRecursoRequestDTO(
    Long recursoId,
    StatusRecurso status,
    String despacho,
    Long idArquivoDecisao
) {}
```

### 11.4 `DistribuicaoRecursoDTO` (request de designacao de analista)

```java
public record DistribuicaoRecursoDTO(
    Long recursoId,
    String idAnalistaKeycloak
) {}
```

---

## S12 — Rastreabilidade

| Elemento BPMN / Componente | Classe / Entidade Legada | Equivalente Java Moderna |
|---|---|---|
| StartEvent_P10 | — | `POST /api/v1/recursos` |
| Task_PreencherFormulario | `RecursoRest.registra()` | `RecursoController.criar()` |
| Task_ValidarSolicitacao | `RecursoRNVal.valida()` | `RecursoValidator.validate()` |
| Task_NotificarEnvolvidos | `NotificacaoRN.notificar()` | `NotificacaoService.notificar()` |
| Task_EfetuarAceite | `RecursoRN.efetuarAceites()` | `RecursoService.registrarAceite()` |
| GW_TodosAceitaram | `RecursoRN.validaTodosRealizaramAceite()` | `RecursoService.verificarUnanimidade()` |
| Task_AtualizarSituacaoLic | `RecursoRN.atualizarSituacaoLicenciamento()` | `LicenciamentoService.atualizarSituacao()` |
| Task_DistribuirRecurso | `RecursoAnaliseRestImpl.distribuirRecurso()` | `AnaliseRecursoService.distribuir()` |
| Task_AnalisarRecurso | `RecursoAnaliseRestImpl.analisarRecurso()` | `AnaliseRecursoService.concluir()` |
| Task_AnalisarSegundaInstancia | `RecursoAnaliseRestImpl.analisarSegundaInstancia()` | `AnaliseRecursoService.concluirSegundaInstancia()` |
| EndEvent_Deferido | `SituacaoLicenciamento.*` | `LicenciamentoService.reverterParaAnalise()` |
| EndEvent_Indeferido | `SituacaoLicenciamento.*` | `LicenciamentoService.manterSituacao()` |
| RecursoED | `CBM_RECURSO` | `sol_recurso` |
| AnaliseRecursoED | `CBM_ANALISE_RECURSO` | `sol_analise_recurso` |
| RecursoMarcoED | `CBM_RECURSO_MARCO` | `sol_recurso_marco` |
| SituacaoRecurso enum | 6 valores com codigo BD | Manter os mesmos valores |
| StatusRecurso enum | T/P/I | Manter os mesmos valores |
| TipoRecurso enum | A/V | Manter os mesmos valores |
| `idUsuarioSoe` (Long) | SOE PROCERGS user ID | `idUsuarioKeycloak` (UUID String) |
| Alfresco nodeRef | `CBM_ARQUIVO.IDENTIFICADOR_ALFRESCO` | MinIO bucket path em `sol_arquivo` |

---

## S13 — Configuracao da Aplicacao (Spring Boot)

```yaml
# application.yml (producao)
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:5432/sol
    username: ${DB_USER}
    password: ${DB_PASS}
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        default_schema: public

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${KEYCLOAK_URL}/realms/sol
          jwk-set-uri: ${KEYCLOAK_URL}/realms/sol/protocol/openid-connect/certs

  mail:
    host: ${SMTP_HOST}
    port: 587
    username: ${SMTP_USER}
    password: ${SMTP_PASS}

minio:
  endpoint: ${MINIO_ENDPOINT}
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket-documentos: sol-documentos

sol:
  recurso:
    prazo-primeira-instancia-dias: 30
    prazo-segunda-instancia-dias: 15
```

---

## S14 — Diferencas em Relacao a Stack Legada

| Aspecto | Stack Legada (Java EE / SOE) | Stack Moderna (Spring Boot / Keycloak) |
|---|---|---|
| Autenticacao | SOE PROCERGS (idUsuarioSoe Long) | Keycloak JWT (sub UUID String) |
| Servidor de aplicacao | WildFly + EJB Stateless | Spring Boot + Spring Service + @Transactional |
| Injecao de dependencia | CDI (`@Inject`) | Spring IoC (`@Autowired` / constructor injection) |
| Persistencia | JPA/Hibernate + Oracle Sequences | Spring Data JPA + PostgreSQL BIGSERIAL |
| Armazenamento de documentos | Alfresco ECM (nodeRef) | MinIO S3-compatible (bucket/key) |
| Notificacao | Modulo SOE PROCERGS | Spring Mail / Amazon SES |
| Transacoes | `@TransactionAttribute(REQUIRED)` | `@Transactional` |
| Validacao | Codigo imperativo em RNVal | Bean Validation + `@Valid` + `ControllerAdvice` |
| Configuracao | `web.xml`, `persistence.xml`, `beans.xml` | `application.yml` + Spring Auto-Configuration |

---

## S15 — Checklist de Implementacao

- [ ] Criar entidades JPA: `Recurso`, `AnaliseRecurso`, `SolicitacaoRtRecurso`, `SolicitacaoRuRecurso`, `SolicitacaoProprietarioRecurso`, `RecursoMarco`
- [ ] Criar migrations Flyway com DDL das tabelas S2
- [ ] Implementar enums: `SituacaoRecurso`, `TipoRecurso`, `TipoSolicitacaoRecurso`, `StatusRecurso`, `SituacaoAnaliseRecurso`
- [ ] Implementar repositories Spring Data JPA para cada entidade
- [ ] Implementar `RecursoService` com metodos: `criar`, `salvar`, `registrarAceite`, `recusar`, `cancelar`, `verificarUnanimidade`, `atualizarSituacaoLicenciamento`
- [ ] Implementar `AnaliseRecursoService` com metodos: `distribuir`, `cancelarDistribuicao`, `concluir`, `concluirSegundaInstancia`, `habilitarEdicao`
- [ ] Implementar `RecursoController` (endpoints cidadao S5)
- [ ] Implementar `RecursoAdmController` (endpoints admin S6)
- [ ] Implementar `RecursoValidator` com RN-073 a RN-083
- [ ] Implementar `NotificacaoService` (templates S10)
- [ ] Implementar `RecursoMarcoService` (marcos S4, RN-090)
- [ ] Configurar Spring Security com roles Keycloak (S8)
- [ ] Configurar MinIO client (S9)
- [ ] Configurar Spring Mail (S10)
- [ ] Escrever testes de integracao para o fluxo completo (criacao → aceite unanime → distribuicao → analise → conclusao)
- [ ] Escrever testes unitarios para `RecursoValidator` cobrindo todos os RN


---

## Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (Demanda 30) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (item 12.1, 12.2).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P10.

---

### RN-P10-N1 — Prazo do Recurso em Dias ÚTEIS (Compartilhado com P05) 🔴 P10-M1

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma / Correção 2 — RT de Implantação SOL-CBMRS item 12.1

**Descrição:** O prazo para análise do recurso deve ser calculado em **dias úteis**:
- **1ª instância:** 30 dias úteis
- **2ª instância:** 15 dias úteis

Esta implementação é **compartilhada com P05-N2**. O componente `CalendarioUtilService` desenvolvido em P05 deve ser reutilizado aqui.

**Integração no P10:**
```java
// RecursoService.java
public LocalDate calcularPrazoAnalise(Recurso recurso) {
    int diasUteis = recurso.getInstancia() == 1 ? 30 : 15;
    return calendarioUtilService.calcularDataLimiteUtil(
        recurso.getDtDistribuicao(), diasUteis
    );
}
```

**Impacto na tela do analista:** Exibir prazo restante em dias úteis, não corridos.

**Critérios de Aceitação:**
- [ ] CA-P10-N1a: Prazo de análise de 1ª instância calculado com 30 dias **úteis** a partir da distribuição
- [ ] CA-P10-N1b: Prazo de análise de 2ª instância calculado com 15 dias **úteis**
- [ ] CA-P10-N1c: Tela do analista exibe prazo em dias úteis restantes
- [ ] CA-P10-N1d: Utiliza o mesmo `CalendarioUtilService` do P05 (sem duplicação)

---

### RN-P10-N2 — Rascunho do Recurso e Aceite Formal do Proprietário 🟠 P10-M2

**Prioridade:** Alta  
**Origem:** Demanda 30 — Sprint 04 Hammer

**Descrição:** O preenchimento do recurso deve suportar **modo de rascunho**: o usuário pode salvar e retornar em outro momento. O **Proprietário** deve ter um fluxo específico de aceite do recurso antes do envio formal.

**Novo campo de status do recurso:**
```sql
ALTER TABLE cbm_recurso
    ADD COLUMN tp_status_recurso VARCHAR(30) NOT NULL DEFAULT 'RASCUNHO'
        CHECK (tp_status_recurso IN ('RASCUNHO','AGUARDANDO_ACEITE','ENVIADO','EM_ANALISE','CONCLUIDO'));
```

**Mudança na UserTask `P10_T02_Preenchimento`:**

A tela de preenchimento do recurso deve ter dois botões:
- **"Salvar Rascunho"** — persiste sem mudar o status do licenciamento
- **"Enviar para Aceite"** — aciona o ciclo de aceites dos envolvidos (análogo ao P03)

```java
// RecursoService.java
public void salvarRascunho(UUID idRecurso, RecursoConteudoRequest req, UUID idUsuario) {
    Recurso recurso = buscarOuLancar(idRecurso);
    if (!recurso.getIdUsuarioCriador().equals(idUsuario)) {
        throw new ForbiddenException("Somente o criador pode salvar o rascunho");
    }
    recurso.setConteudo(req.getConteudo());
    recurso.setStatus(StatusRecurso.RASCUNHO);
    recursoRepository.save(recurso);
    // NÃO muda o status do licenciamento
}

public void enviarParaAceite(UUID idRecurso) {
    Recurso recurso = buscarOuLancar(idRecurso);
    recurso.setStatus(StatusRecurso.AGUARDANDO_ACEITE);
    recursoRepository.save(recurso);
    // Aciona ciclo de aceites dos envolvidos (incluindo Proprietário)
    aceiteRecursoService.iniciarCicloAceites(recurso);
}
```

**Aceite do Proprietário:**
- O Proprietário deve receber notificação e ter link para aceitar/recusar o recurso
- Após aceite unânime dos envolvidos, o recurso muda para `ENVIADO` e é protocolado
- Interface análoga ao ciclo de aceites do P03

**Critérios de Aceitação:**
- [ ] CA-P10-N2a: Usuário pode salvar rascunho do recurso e retornar para editar
- [ ] CA-P10-N2b: Status `RASCUNHO` não altera o estado do licenciamento
- [ ] CA-P10-N2c: "Enviar para Aceite" aciona notificações para todos os envolvidos (incluindo Proprietário)
- [ ] CA-P10-N2d: Proprietário pode aceitar ou recusar formalmente o recurso
- [ ] CA-P10-N2e: Após aceite unânime, recurso muda para `ENVIADO` e é protocolado

---

### RN-P10-N3 — Bloqueio Automático de Recursos Intempestivos 🔴 P10-M3

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C4 / RT de Implantação SOL-CBMRS item 12.2

**Descrição:** Recursos fora do prazo (intempestivos) devem ser **automaticamente bloqueados** pelo sistema. O botão "Abrir Recurso" deve ser desabilitado e uma mensagem de prazo expirado deve ser exibida.

**Gateway no início do módulo de recurso:**

```java
// RecursoService.java — validarAbertura()
public void validarAbertura(UUID idLicenciamento) {
    Licenciamento lic = licenciamentoRepository.findById(idLicenciamento).orElseThrow();
    LocalDate dtCiencia = lic.getDtCienciaCiaOuCiv();
    if (dtCiencia == null) {
        throw new BusinessException("Não há CIA/CIV com ciência registrada para este licenciamento");
    }
    LocalDate dtLimite = calendarioUtilService.calcularDataLimiteUtil(dtCiencia, 30);
    if (LocalDate.now().isAfter(dtLimite)) {
        throw new RecursoIntempestivoException(
            "O prazo para interposição de recurso expirou em " +
            dtLimite.format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) +
            ". Recursos intempestivos não são aceitos pelo sistema " +
            "(RT de Implantação SOL, item 12.2)."
        );
    }
}
```

**Frontend — desabilitar botão com mensagem:**
```typescript
get podeAbrirRecurso(): boolean {
    return this.licenciamento.diasUteisRestantesRecurso > 0;
}

get mensagemPrazoRecurso(): string {
    if (this.podeAbrirRecurso) {
        return `Prazo para recurso: ${this.licenciamento.diasUteisRestantesRecurso} dias úteis restantes`;
    }
    return `Prazo expirado em ${this.licenciamento.dtLimiteRecurso}. Recurso intempestivo não é aceito.`;
}
```

**Critérios de Aceitação:**
- [ ] CA-P10-N3a: Botão "Abrir Recurso" desabilitado após expiração do prazo de 30 dias úteis
- [ ] CA-P10-N3b: Mensagem exibe a data de expiração e referência à norma (item 12.2)
- [ ] CA-P10-N3c: API retorna HTTP 422 com mensagem de recurso intempestivo ao tentar abrir após prazo
- [ ] CA-P10-N3d: Portal exibe contagem de dias úteis restantes enquanto o prazo está vigente

---

### Resumo das Mudanças P10 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P10-M1 | RN-P10-N1 | Prazo do recurso em dias ÚTEIS — compartilhado com P05 (OBRIGATÓRIO) | 🔴 Crítica |
| P10-M3 | RN-P10-N3 | Bloqueio automático de recursos intempestivos (OBRIGATÓRIO) | 🔴 Crítica |
| P10-M2 | RN-P10-N2 | Rascunho do recurso + aceite formal do Proprietário | 🟠 Alta |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprint 04 (Demanda 30) + Normas RTCBMRS*
