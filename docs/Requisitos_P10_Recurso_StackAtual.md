# Requisitos P10 — Recurso Administrativo (Contestação de CIA/CIV)
## Stack Atual Java EE (JAX-RS · CDI · JPA/Hibernate · EJB · SOE PROCERGS · Alfresco · Oracle)

> Documento de requisitos baseado **exclusivamente** no código-fonte real do projeto
> `SOLCBM.BackEnd16-06`. Todos os nomes de classes, métodos, campos, tabelas e enumerações
> correspondem ao código existente sem adaptação.

---

## S1 — Visão Geral do Processo

O processo P10 — **Recurso Administrativo** — permite que os envolvidos em um licenciamento
contestem formalmente uma decisão desfavorável emitida pelo CBM-RS:

- **CIA** — Comunicado de Inconformidade na Análise (contestação do resultado do P04 — Análise Técnica).
- **CIV** — Comunicado de Inconformidade na Vistoria (contestação do resultado do P07 — Vistoria Presencial).

O sistema prevê **duas instâncias recursais**:

| Instância | Responsável pela análise | Prazo para interposição |
|---|---|---|
| **1ª instância** | Chefe do CBM-RS (analista designado) | **30 dias** corridos após emissão da CIA/CIV |
| **2ª instância** | Comandante do CBM-RS / Colegiado externo | **15 dias** corridos após conclusão da análise de 1ª instância |

As constantes de prazo estão definidas em `RecursoRN`:

```java
private static final Integer PRAZO_SOLICITAR_1_INSTANCIA         = 30;
private static final Integer PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15;
private static final Integer RECURSO_1_INSTANCIA                 = 1;
```

### Atores do Processo

| Ator | Papel |
|---|---|
| **Solicitante** (RT, RU ou Proprietário) | Cria o recurso, preenche a fundamentação, seleciona co-signatários |
| **Co-signatários** (RT, RU e/ou Proprietários do licenciamento) | Devem aceitar formalmente o recurso antes do envio ao CBM |
| **Analista CBM** (1ª instância) | Recebe, analisa e profere decisão |
| **Comandante / Colegiado** (2ª instância) | Julgamento final — sem nova via recursiva interna |

### Restrições de Escopo

- O campo `recursoBloqueado` no `LicenciamentoED`, quando `true`, impede novo recurso sobre
  qualquer CIA/CIV daquele licenciamento. O sistema lança HTTP 406 com mensagem
  `"recurso.bloqueado.para.recurso"`.
- Apenas um recurso pode estar ativo (não `CANCELADO` e não `ANALISE_CONCLUIDA`) por
  combinação `licenciamento + arquivoCiaCiv + instancia`.
- A 2ª instância somente pode ser aberta se a análise de 1ª instância foi concluída com
  `StatusRecurso.INDEFERIDO` ou `StatusRecurso.DEFERIDO_PARCIAL`.

### Transições de `SituacaoLicenciamento` durante P10

Após unanimidade de aceites, `RecursoRN.atualizarSituacaoLicenciamento()` chama
`retornaNovaSituacaoLicenciamento()` para definir o novo estado:

```java
private SituacaoLicenciamento retornaNovaSituacaoLicenciamento(RecursoED recursoED) {
    if (TipoRecurso.CORRECAO_DE_ANALISE.equals(recursoED.getTipoRecurso())) {
        return recursoED.getInstancia().equals(RECURSO_1_INSTANCIA)
            ? SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIA
            : SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIA;
    }
    return recursoED.getInstancia().equals(RECURSO_1_INSTANCIA)
        ? SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIV
        : SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIV;
}
```

| Estado do Licenciamento | Quando é atribuído |
|---|---|
| `RECURSO_EM_ANALISE_1_CIA` | Recurso de 1ª instância sobre CIA — todos aceitaram |
| `RECURSO_EM_ANALISE_2_CIA` | Recurso de 2ª instância sobre CIA — todos aceitaram |
| `RECURSO_EM_ANALISE_1_CIV` | Recurso de 1ª instância sobre CIV — todos aceitaram |
| `RECURSO_EM_ANALISE_2_CIV` | Recurso de 2ª instância sobre CIV — todos aceitaram |

---

## S2 — Entidades de Domínio (EDs)

### 2.1 RecursoED

Entidade central do recurso administrativo. Uma instância representa um pedido de contestação
de uma CIA ou CIV para uma instância específica (1ª ou 2ª).

```java
// Tabela: CBM_RECURSO
@Entity
@Table(name = "CBM_RECURSO")
@NamedQueries(value = {
    @NamedQuery(name = "RecursoED.consulta",
        query = "select r from RecursoED r join fetch r.licenciamentoED where r.id = :id")
})
public class RecursoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "Recurso_SEQ", sequenceName = "CBM_ID_RECURSO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "Recurso_SEQ")
    @Column(name = "NRO_INT_RECURSO")
    private Long id;

    /** Licenciamento contestado — relação 1:1 (um recurso por licenciamento por instância) */
    @NotNull
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO")
    @OneToOne(fetch = FetchType.LAZY)
    private LicenciamentoED licenciamentoED;

    /** Instância recursал: 1 = primeira, 2 = segunda */
    @NotNull
    @Column(name = "NRO_INSTANCIA")
    private Integer instancia;

    /** Situação atual no ciclo de vida do recurso */
    @NotNull
    @Column(name = "TP_SITUACAO")
    @Enumerated
    private SituacaoRecurso situacao;

    /** Tipo: contestação de análise (CIA) ou de vistoria (CIV) */
    @NotNull
    @Column(name = "TP_RECURSO")
    @Enumerated
    private TipoRecurso tipoRecurso;

    /** Escopo do pedido: integral ou parcial */
    @NotNull
    @Column(name = "TP_SOLICITACAO")
    @Enumerated
    private TipoSolicitacaoRecurso tipoSolicitacao;

    /** Texto de fundamentação legal — argumentação jurídica e técnica do recorrente */
    @Column(name = "TXT_FUNDAMENTACAO_LEGAL")
    private String fundamentacaoLegal;

    /** Data/hora em que o recurso foi enviado ao CBM (após todos os aceites) */
    @Column(name = "DTH_ENVIO_ANALISE")
    private LocalDateTime dataEnvioAnalise;

    /** Arquivo CIA ou CIV que originou o recurso */
    @JoinColumn(name = "NRO_INT_ARQUIVO_CIA_CIV")
    @ManyToOne(fetch = FetchType.LAZY)
    private ArquivoED arquivoCiaCivED;

    /** ID do usuário SOE PROCERGS que abriu o recurso */
    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idUsuarioSoe;

    /** Proprietários co-signatários */
    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoProprietarioED> solicitacaoProprietarios;

    /** Responsáveis Técnicos co-signatários */
    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoResponsavelTecnicoED> solicitacaoResponsaveisTecnicos;

    /** Responsáveis pelo Uso co-signatários */
    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoResponsavelUsuarioED> solicitacaoResponsaveisUso;
}
```

**Tabela CBM_RECURSO:**

| Coluna | Tipo Oracle | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_RECURSO` | NUMBER | PK NOT NULL | Chave primária — sequência `CBM_ID_RECURSO_SEQ` |
| `NRO_INT_LICENCIAMENTO` | NUMBER | FK NOT NULL | Licenciamento contestado |
| `NRO_INSTANCIA` | NUMBER | NOT NULL | 1 = primeira, 2 = segunda instância |
| `TP_SITUACAO` | NUMBER | NOT NULL | Enum `SituacaoRecurso` (ordinal) |
| `TP_RECURSO` | NUMBER | NOT NULL | Enum `TipoRecurso` (ordinal) |
| `TP_SOLICITACAO` | NUMBER | NOT NULL | Enum `TipoSolicitacaoRecurso` (ordinal) |
| `TXT_FUNDAMENTACAO_LEGAL` | VARCHAR2 | | Argumentação textual do recorrente |
| `DTH_ENVIO_ANALISE` | TIMESTAMP | | Data/hora do envio ao CBM |
| `NRO_INT_ARQUIVO_CIA_CIV` | NUMBER | FK NOT NULL | Arquivo CIA/CIV contestado |
| `NRO_INT_USUARIO_SOE` | NUMBER | | ID do usuário SOE que abriu o recurso |

---

### 2.2 AnaliseRecursoED

Representa a análise CBM de um recurso. Criada no momento da distribuição para um analista.
Relação 1:1 com `RecursoED`.

```java
// Tabela: CBM_ANALISE_RECURSO
@Entity
@Table(name = "CBM_ANALISE_RECURSO")
@NamedQueries(value = {
    @NamedQuery(name = "AnaliseRecursoED.consulta",
        query = "select ar from AnaliseRecursoED ar join fetch ar.recursoED where ar.id = :id")
})
public class AnaliseRecursoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "AnaliseRecurso_SEQ",
                       sequenceName = "CBM_ID_ANALISE_RECURSO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "AnaliseRecurso_SEQ")
    @Column(name = "NRO_INT_ANALISE_RECURSO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_RECURSO")
    @OneToOne(fetch = FetchType.LAZY)
    private RecursoED recursoED;

    /** Resultado da análise (preenchido ao concluir) */
    @Column(name = "TP_STATUS")
    @Enumerated
    private StatusRecurso status;

    /** Texto do despacho — fundamentação da decisão do analista CBM */
    @Column(name = "TXT_DESPACHO")
    private String despacho;

    /** ID do analista CBM no SOE PROCERGS — obrigatório após distribuição */
    @NotNull
    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idUsuarioSoe;

    /** Data/hora em que o analista deu ciência do recurso */
    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "DTH_CIENCIA_ATEC")
    private Calendar dthCienciaAtec;

    /** ID do usuário SOE que confirmou a ciência */
    @Column(name = "NRO_INT_USUARIO_CIENCIA")
    private Long idUsuarioCiencia;

    /**
     * Flag de ciência do analista.
     * null = aguardando confirmação; 'S' (true) = confirmado.
     * Persistido como 'S'/'N'/NULL via SimNaoBooleanConverter.
     */
    @Column(name = "IND_CIENCIA")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean ciencia;

    /** Arquivo com a decisão formalizada (PDF armazenado no Alfresco) */
    @OneToOne
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    private ArquivoED arquivo;

    /** Situação interna da análise (controle de fluxo do analista) */
    @NotNull
    @Column(name = "TP_SITUACAO")
    @Enumerated(EnumType.STRING)
    private SituacaoAnaliseRecursoEnum situacao;

    /** Data/hora de conclusão da análise */
    @Column(name = "CTR_DTH_CONCLUSAO_ANALISE")
    @Temporal(TemporalType.TIMESTAMP)
    private Calendar dataConclusaoAnalise;
}
```

**Tabela CBM_ANALISE_RECURSO:**

| Coluna | Tipo Oracle | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_ANALISE_RECURSO` | NUMBER | PK NOT NULL | Chave primária — sequência `CBM_ID_ANALISE_RECURSO_SEQ` |
| `NRO_INT_RECURSO` | NUMBER | FK NOT NULL UNIQUE | Recurso analisado (1:1) |
| `TP_STATUS` | NUMBER | | Enum `StatusRecurso` (ordinal) — preenchido ao concluir |
| `TXT_DESPACHO` | VARCHAR2 | | Fundamentação da decisão CBM |
| `NRO_INT_USUARIO_SOE` | NUMBER | NOT NULL | Analista CBM (SOE PROCERGS) |
| `DTH_CIENCIA_ATEC` | TIMESTAMP | | Confirmação de recebimento pelo analista |
| `NRO_INT_USUARIO_CIENCIA` | NUMBER | | Usuário que confirmou ciência |
| `IND_CIENCIA` | CHAR(1) | `'S'/'N'/NULL` | Flag `SimNaoBooleanConverter` |
| `NRO_INT_ARQUIVO` | NUMBER | FK | Arquivo da decisão (Alfresco nodeRef) |
| `TP_SITUACAO` | VARCHAR2(40) | NOT NULL | Enum `SituacaoAnaliseRecursoEnum` (STRING) |
| `CTR_DTH_CONCLUSAO_ANALISE` | TIMESTAMP | | Data/hora de conclusão |

---

### 2.3 RecursoArquivoED

Relaciona documentos adicionais (PDFs de suporte) ao recurso. Permite múltiplos arquivos
por recurso além do arquivoCiaCiv.

```java
// Tabela: CBM_RECURSO_ARQUIVO
@Entity
@Table(name = "CBM_RECURSO_ARQUIVO")
@NamedQueries(value = {
    @NamedQuery(name = "RecursoArquivoED.consulta",
        query = "select ra from RecursoArquivoED ra join fetch ra.recursoED where ra.id = :id")
})
public class RecursoArquivoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "RecursoArquivo_SEQ",
                       sequenceName = "CBM_ID_RECURSO_ARQUIVO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "RecursoArquivo_SEQ")
    @Column(name = "NRO_INT_RECURSO_ARQUIVO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_RECURSO")
    @OneToOne(fetch = FetchType.LAZY)
    private RecursoED recursoED;

    @NotNull
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    @OneToOne(fetch = FetchType.LAZY)
    private ArquivoED arquivoED;
}
```

**Tabela CBM_RECURSO_ARQUIVO:**

| Coluna | Tipo Oracle | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_RECURSO_ARQUIVO` | NUMBER | PK NOT NULL | Chave primária — sequência `CBM_ID_RECURSO_ARQUIVO_SEQ` |
| `NRO_INT_RECURSO` | NUMBER | FK NOT NULL | Recurso ao qual pertence |
| `NRO_INT_ARQUIVO` | NUMBER | FK NOT NULL | Arquivo no Alfresco (nodeRef em `CBM_ARQUIVO.IDENTIFICADOR_ALFRESCO`) |

---

### 2.4 RecursoMarcoED

Registra os eventos de auditoria do recurso ao longo do seu ciclo de vida.

```java
// Tabela: CBM_RECURSO_MARCO
@Entity
@Table(name = "CBM_RECURSO_MARCO")
@NamedQueries(value = {
    @NamedQuery(name = "RecursoMarcoED.consulta",
        query = "select r from RecursoMarcoED r " +
                "join fetch r.recursoED " +
                "left join fetch r.parametroMarco " +
                "left join fetch r.usuarioED " +
                "where r.id = :id")
})
public class RecursoMarcoED extends AppED<Long> implements Serializable {

    @Id
    @SequenceGenerator(name = "RECURSO_MARCO_SEQ",
                       sequenceName = "CBM_ID_RECURSO_MARCO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "RECURSO_MARCO_SEQ")
    @Column(name = "NRO_INT_RECURSO_MARCO")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_RECURSO")
    private RecursoED recursoED;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_PARAMETRO_MARCO")
    private ParametroMarcoED parametroMarco;

    @NotNull
    @Column(name = "DTH_MARCO")
    private Calendar dthMarco;

    @NotNull
    @Size(max = 100)
    @Column(name = "TXT_DESCRICAO")
    private String descricao;

    @NotNull
    @Enumerated(EnumType.ORDINAL)
    @Column(name = "COD_TP_VISIBILIDADE")
    private TipoVisibilidadeMarco visibilidade;

    @Column(name = "NRO_INT_ARQUIVO")
    private Long arquivoId;

    @Column(name = "TXT_TITULO_ARQUIVO")
    private String tituloArquivo;

    @NotNull
    @Enumerated(EnumType.STRING)
    @Column(name = "TP_RESPONSAVEL")
    private TipoResponsavelMarco tipoResponsavel;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO_RESP")
    private UsuarioED usuarioED;

    @Column(name = "NRO_INT_USUARIO_SOE_RESP")
    private Long usuarioSoeId;

    @Column(name = "NOME_RESPONSAVEL")
    private String usuarioSoeNome;

    @Column(name = "VALOR_NOMINAL")
    private BigDecimal valorNominal;

    @Size(max = 255)
    @Column(name = "TXT_COMPLEMENTAR")
    private String textoComplementar;
}
```

**Tabela CBM_RECURSO_MARCO:**

| Coluna | Tipo Oracle | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_RECURSO_MARCO` | NUMBER | PK NOT NULL | Chave primária — sequência `CBM_ID_RECURSO_MARCO_SEQ` |
| `NRO_INT_RECURSO` | NUMBER | FK NOT NULL | Recurso ao qual o marco pertence |
| `NRO_INT_PARAMETRO_MARCO` | NUMBER | FK | Parâmetro de marco configurado no sistema |
| `DTH_MARCO` | TIMESTAMP | NOT NULL | Data/hora do evento |
| `TXT_DESCRICAO` | VARCHAR2(100) | NOT NULL | Texto descritivo do marco |
| `COD_TP_VISIBILIDADE` | NUMBER | NOT NULL | `TipoVisibilidadeMarco` ordinal (0=PUBLICO, 1=PRIVADO) |
| `NRO_INT_ARQUIVO` | NUMBER | | Arquivo associado ao marco |
| `TXT_TITULO_ARQUIVO` | VARCHAR2 | | Título do arquivo |
| `TP_RESPONSAVEL` | VARCHAR2 | NOT NULL | `TipoResponsavelMarco` — CIDADAO, SISTEMA, BOMBEIROS |
| `NRO_INT_USUARIO_RESP` | NUMBER | FK | Usuário SOL responsável pelo evento |
| `NRO_INT_USUARIO_SOE_RESP` | NUMBER | | ID SOE PROCERGS do responsável |
| `NOME_RESPONSAVEL` | VARCHAR2 | | Nome do responsável (denormalizado) |
| `VALOR_NOMINAL` | NUMBER | | Valor nominal (para marcos financeiros) |
| `TXT_COMPLEMENTAR` | VARCHAR2(255) | | Texto adicional contextual |

---

### 2.5 ArquivoED — campos relevantes ao P10

Todo documento (CIA/CIV, PDF de fundamentação, decisão CBM) referenciado pelo recurso
é persistido como metadados no Oracle e armazenado fisicamente no **Alfresco ECM**.

```java
// Campo fundamental para o P10:
@NotNull
@Size(max = 150)
@Column(name = "IDENTIFICADOR_ALFRESCO", nullable = false)
private String identificadorAlfresco;
// Formato: workspace://SpacesStore/{UUID}
// O binário (PDF) reside inteiramente no Alfresco — nunca no Oracle.
```

---

## S3 — Enumerações

### 3.1 `SituacaoRecurso`

Ciclo de vida do recurso do ponto de vista do cidadão. Persistida como ordinal na coluna `TP_SITUACAO`.

```java
public enum SituacaoRecurso {
    AGUARDANDO_APROVACAO_ENVOLVIDOS("E"), // cidadão submeteu — aguarda aceites
    AGUARDANDO_DISTRIBUICAO("D"),         // todos aceitaram — aguarda designação de analista CBM
    ANALISE_CONCLUIDA("C"),               // decisão proferida
    EM_ANALISE("A"),                      // analista designado — em análise
    CANCELADO("CA"),                      // cancelado
    RASCUNHO("R");                        // rascunho — editável
}
```

| Valor | Código | Descrição |
|---|---|---|
| `RASCUNHO` | R | Salvo mas não submetido — editável pelo solicitante |
| `AGUARDANDO_APROVACAO_ENVOLVIDOS` | E | Aguardando aceite dos co-signatários |
| `AGUARDANDO_DISTRIBUICAO` | D | Todos aceitaram — aguardando designação de analista CBM |
| `EM_ANALISE` | A | Analista CBM designado — em análise |
| `ANALISE_CONCLUIDA` | C | Decisão proferida |
| `CANCELADO` | CA | Cancelado |

### 3.2 `TipoRecurso`

```java
public enum TipoRecurso {
    CORRECAO_DE_ANALISE("A"),  // contestação de CIA
    CORRECAO_DE_VISTORIA("V"); // contestação de CIV
}
```

| Valor | Código BD | Significado |
|---|---|---|
| `CORRECAO_DE_ANALISE` | A | Contesta CIA — inconformidade na análise técnica (P04) |
| `CORRECAO_DE_VISTORIA` | V | Contesta CIV — inconformidade na vistoria presencial (P07) |

### 3.3 `TipoSolicitacaoRecurso`

```java
public enum TipoSolicitacaoRecurso {
    INTEGRAL("I"), // reabertura total da análise/vistoria
    PARCIAL("P");  // contestação de pontos específicos
}
```

### 3.4 `StatusRecurso` (resultado da análise CBM)

```java
public enum StatusRecurso {
    DEFERIDO_TOTAL("T"),   // recurso totalmente acolhido
    DEFERIDO_PARCIAL("P"), // acolhido parcialmente
    INDEFERIDO("I");       // negado
}
```

| Valor | Código BD | Efeito no Licenciamento |
|---|---|---|
| `DEFERIDO_TOTAL` | T | Retorna ao fluxo P04 ou P07 — análise/vistoria reaberta |
| `DEFERIDO_PARCIAL` | P | Mantém pendências específicas; habilita abertura de 2ª instância |
| `INDEFERIDO` | I | Mantém decisão; habilita 2ª instância (se 1ª) ou encerra via recursiva (se 2ª) |

### 3.5 `SituacaoAnaliseRecursoEnum` (estado interno do analista CBM)

```java
public enum SituacaoAnaliseRecursoEnum {
    EM_ANALISE,
    AGUARDANDO_AVALIACAO_COLEGIADO, // exclusivo para 2ª instância
    ANALISE_CONCLUIDA;
}
```

---

## S4 — Regras de Negócio

### RN-073 — `tipoSolicitacao` Obrigatório

Validado em `RecursoRNVal.valida()`. O campo `tipoSolicitacao` (INTEGRAL ou PARCIAL) é
obrigatório e não pode ser nulo no momento da chamada `POST /recursos` com `aceite=true`.
O sistema lança `WebApplicationRNException` com HTTP 422 se ausente.

### RN-074 — `tipoRecurso` Obrigatório e Imutável

O campo `tipoRecurso` é obrigatório e deve ser fornecido na criação. Após persistido, o
valor não deve ser alterado (não há método de alteração de `tipoRecurso` nas RNs).

### RN-075 — `instancia` Obrigatória e Validada

O campo `instancia` deve ser 1 ou 2. Para `instancia = 2`, o backend verifica em
`RecursoRN` que existe uma `AnaliseRecursoED` concluída (`ANALISE_CONCLUIDA`) para o
mesmo `licenciamento + arquivoCiaCiv + instancia=1` com `status` `INDEFERIDO` ou
`DEFERIDO_PARCIAL`.

### RN-076 — `fundamentacaoLegal` Obrigatória na Submissão

Validado em `RecursoRNVal.valida()`. O campo `fundamentacaoLegal` pode ser nulo durante
o rascunho, mas deve estar preenchido no momento de `aceite=true`. HTTP 422 se ausente.

### RN-077 — Licenciamento Deve Existir e Ser Acessível

O `idLicenciamento` deve referenciar um licenciamento existente no qual o usuário
autenticado (por `idUsuarioSoe` do token SOE) seja RT, RU ou Proprietário.

### RN-078 — Arquivo CIA/CIV Válido

O `idArquivoCiaCiv` deve referenciar um `ArquivoED` associado ao licenciamento informado,
do tipo correspondente ao `tipoRecurso` (CIA para `CORRECAO_DE_ANALISE`, CIV para
`CORRECAO_DE_VISTORIA`), e que não tenha sido anulado. O método `validarTermoCiencia()`
em `RecursoRN.registra()` executa esta validação.

### RN-079 — Ao Menos Um Co-signatário

Validado em `RecursoRNVal.valida()`. Ao menos uma das listas `cpfRts`, `cpfRus` ou
`cpfProprietarios` deve ter ao menos um elemento. HTTP 422 se todas estiverem vazias.

### RN-080 — Prazo de Interposição da 1ª Instância

O recurso de 1ª instância deve ser registrado dentro de **30 dias** corridos da data de
emissão do arquivo CIA/CIV (`ArquivoED.ctrDthInc`). A constante `PRAZO_SOLICITAR_1_INSTANCIA = 30`
em `RecursoRN` é usada no cálculo. HTTP 422 se prazo esgotado.

### RN-081 — Prazo de Interposição da 2ª Instância

Deve ser registrado dentro de **15 dias** corridos da data de conclusão da análise de
1ª instância (`AnaliseRecursoED.dataConclusaoAnalise`). A constante
`PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15` é usada. HTTP 422 se prazo esgotado.

### RN-082 — Recurso Bloqueado

Se `LicenciamentoED.recursoBloqueado = true`, `RecursoRN.registra()` lança HTTP 406:

```java
if (licenciamentoED.getRecursoBloqueado()) {
    throw new WebApplicationRNException(
        bundle.getMessage("recurso.bloqueado.para.recurso"), Response.Status.NOT_ACCEPTABLE);
}
```

### RN-083 — Filtragem de RTs por Tipo de Recurso

Ao incluir co-signatários RT, `RecursoRN.registra()` filtra os `ResponsavelTecnicoED`
vinculados ao licenciamento conforme o tipo de recurso:

```java
List<ResponsavelTecnicoED> rts = licenciamentoED.getResponsaveisTecnicos().stream()
    .filter(r ->
        (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.EXECUCAO)
            && recursoDTO.getTipoRecurso() == TipoRecurso.CORRECAO_DE_VISTORIA)
        || (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.PROJETO)
            && recursoDTO.getTipoRecurso() == TipoRecurso.CORRECAO_DE_ANALISE)
        || (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.PROJETO_EXECUCAO))
    ).collect(Collectors.toList());
```

| TipoRecurso | Tipos de responsabilidade RT aceitos |
|---|---|
| `CORRECAO_DE_ANALISE` | `PROJETO`, `PROJETO_EXECUCAO` |
| `CORRECAO_DE_VISTORIA` | `EXECUCAO`, `PROJETO_EXECUCAO` |

### RN-084 — Unanimidade nos Aceites

`RecursoRN.validaTodosRealizaramAceite()` verifica que **todos** os co-signatários (RT, RU e
Proprietários) possuem `indAceite = "S"` (via `SimNaoBooleanConverter`). Se qualquer
`indAceite` for `"N"` ou `null`, o recurso permanece em
`AGUARDANDO_APROVACAO_ENVOLVIDOS`. Ao atingir unanimidade:

```java
recursoED.setSituacao(SituacaoRecurso.AGUARDANDO_DISTRIBUICAO);
recursoED.setDataEnvioAnalise(LocalDateTime.now());
altera(recursoED);
incluirMarcoEnvioAnalise(recursoED);
atualizarSituacaoLicenciamento(recursoED);
```

### RN-085 — Cancelamento Restrito por Situação

`RecursoRN.cancelarRecurso()` e `RecursoRN.cancelar()` só permitem cancelamento quando
`situacao IN (RASCUNHO, AGUARDANDO_APROVACAO_ENVOLVIDOS)`. Para qualquer outro estado,
lançam HTTP 400 com `"recurso.status.invalido"`.

### RN-086 — Recusa de Co-signatário Retorna para Rascunho

`RecursoRN.recusar()` retorna o recurso para `RASCUNHO` (não cancela) e registra o marco
`TipoMarco.RECURSO_RECUSADO`. O método `efetuarRecusas()` reinicia os aceites dos demais
co-signatários. Notificação é enviada a todos os envolvidos.

### RN-087 — Habilitação de Edição Retorna para Rascunho

`RecursoRN.habilitarEdicao()` retorna o recurso de `AGUARDANDO_APROVACAO_ENVOLVIDOS`
para `RASCUNHO` e registra marco `TipoMarco.RECURSO_EDITADO`. Permite ao solicitante
corrigir a fundamentação sem cancelar o processo.

### RN-088 — Notificação por E-mail em Marcos Específicos

`RecursoRN` aciona `NotificacaoRN.notificar()` via `ContextoNotificacaoEnum.RECURSO` nos
seguintes eventos:
- Aceite de RT → notifica os demais RTs pendentes (`notificarOutrosRTs()`).
- Unanimidade atingida → notifica todos os RTs com o termo de ciência.
- Cancelamento (`cancelar()`) → notifica todos os envolvidos.
- Recusa (`recusar()`) → notifica todos os envolvidos.

### RN-089 — Marcos de Auditoria por Tipo

O `RecursoMarcoRN.inclui(TipoMarco, RecursoMarcoED)` registra marcos específicos por evento.
Os `TipoMarco` usados pelo processo P10 identificados no código são:

| TipoMarco | Evento | Responsável |
|---|---|---|
| `ACEITE_RECURSO_ANALISE` | Cada aceite individual de co-signatário | CIDADAO |
| `FIM_ACEITES_RECURSO_ANALISE` | Unanimidade atingida | CIDADAO |
| `ENVIO_RECURSO_ANALISE` | Transição para AGUARDANDO_DISTRIBUICAO | SISTEMA |
| `CANCELAMENTO_RECURSO_CIA` | Cancelamento de recurso do tipo CIA | SISTEMA |
| `CANCELAMENTO_RECURSO_CIV` | Cancelamento de recurso do tipo CIV | SISTEMA |
| `RECURSO_CANCELADO` | Cancelamento pelo cidadão (`cancelar()`) | CIDADAO |
| `RECURSO_RECUSADO` | Recusa de co-signatário | CIDADAO |
| `RECURSO_EDITADO` | Habilitação de edição (`habilitarEdicao()`) | CIDADAO |

Em paralelo aos marcos do recurso, `LicenciamentoMarcoInclusaoRN` registra os marcos
correspondentes no licenciamento (visíveis na timeline principal do processo).

---

## S5 — Endpoints REST — Cidadão

Base path: `/recursos` · Implementação: `RecursoRest` · Autenticação: SOE PROCERGS
(escopo `openid`). O `idUsuarioSoe` é extraído do token pela infra `LoginCidadao`.

### 5.1 `POST /recursos` — Registrar Recurso

Chama `RecursoRN.registra(RecursoDTO)`. Cria o recurso, valida via `RecursoRNVal.valida()`,
carrega o licenciamento, valida o arquivo CIA/CIV, inclui co-signatários e retorna o DTO.

**Request body (`RecursoDTO`):**

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `idLicenciamento` | Long | Sim | ID do licenciamento contestado |
| `instancia` | Integer | Sim | 1 ou 2 |
| `tipoRecurso` | TipoRecurso | Sim | CORRECAO_DE_ANALISE ou CORRECAO_DE_VISTORIA |
| `tipoSolicitacao` | TipoSolicitacaoRecurso | Sim | INTEGRAL ou PARCIAL |
| `fundamentacaoLegal` | String | Sim | Argumentação jurídica e técnica |
| `idArquivoCiaCiv` | Long | Sim | ID do ArquivoED do CIA/CIV contestado |
| `aceite` | Boolean | Sim | true = submeter; false = salvar como rascunho |
| `cpfRts` | List\<String\> | Cond. | CPFs dos RTs co-signatários (filtrados por RN-083) |
| `cpfRus` | List\<String\> | Cond. | CPFs dos RUs co-signatários |
| `cpfProprietarios` | List\<String\> | Cond. | CPFs dos Proprietários co-signatários |

Ao menos um dos três grupos de CPF deve ter elementos (RN-079).

**Response:** HTTP 201 com `RecursoResponseDTO`.

---

### 5.2 `GET /recursos/{recursoId}` — Consultar Recurso por ID

Chama `RecursoRN.consultarPorId(recursoId)`. Retorna a versão cidadão do DTO via
`toCidadaoDTO()`, que inclui o campo `podeAceitarTermo` e flags de papel do usuário
(`isRt`, `isRu`, `isProprietario`).

**Response:** HTTP 200 com `RecursoResponseDTO`.

---

### 5.3 `PUT /recursos/{recursoId}` — Aceitar / Alterar Recurso

Chama `RecursoRN.alterarRecurso(recursoId, RecursoDTO)`. Se `aceite = true` na
`RecursoDTO`, aciona `efetuarAceites()` que registra o aceite do usuário logado e
verifica unanimidade via `validaTodosRealizaramAceite()`.

**Response:** HTTP 200 com `RecursoResponseDTO` atualizado.

---

### 5.4 `PUT /recursos/{recursoId}/salvar` — Salvar Rascunho

Chama `RecursoRN.salvarRecurso(recursoId, RecursoDTO)`. Salva `fundamentacaoLegal` e
`tipoSolicitacao` sem disparar o fluxo de aceite. Usado para edição incremental.

**Response:** HTTP 200 com `RecursoResponseDTO`.

---

### 5.5 `GET /recursos/listar` — Listar Recursos do Usuário Logado

Chama `RecursoRN.listarMinhasSolicitacoes()` / `RecursoRN.lista()` com paginação.
Retorna apenas recursos em que o usuário SOE logado é solicitante ou co-signatário.

**Query params:**

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `ordenar` | String | Campo de ordenação |
| `ordem` | String | ASC / DESC |
| `paginaAtual` | int | Página atual (0-based) |
| `tamanho` | int | Itens por página |
| `numeroLicenciamento` | String | Filtro por número |
| `situacoes` | List\<SituacaoRecurso\> | Filtro por situação |
| `tipoRecurso` | List\<TipoRecurso\> | Filtro por tipo |
| `recursoId` | Long | Filtro por ID |
| `termo` | String | Busca textual livre |

**Response:** HTTP 200 com `ListaPaginadaRetorno<RecursoResponseDTO>`.

---

### 5.6 `GET /recursos/historico/{recursoId}` — Histórico do Recurso

Retorna os marcos de auditoria do recurso em ordem cronológica.

**Response:** HTTP 200 com `List<RetornoHistoricoComRecursoDTO>`.

---

### 5.7 `DELETE /recursos/cancelar-recurso/{recursoId}` — Cancelar (via Recurso)

Chama `RecursoRN.cancelarRecurso(recursoId)`. Registra marcos
`CANCELAMENTO_RECURSO_CIA` ou `CANCELAMENTO_RECURSO_CIV` dependendo do `tipoRecurso`.
`TipoResponsavelMarco.SISTEMA` — chamado por fluxos automáticos.

**Response:** HTTP 200 com `boolean`.

---

### 5.8 `DELETE /recursos/{recursoId}/cancelar` — Cancelar (pelo Cidadão)

Chama `RecursoRN.cancelar(recursoId)`. Registra marco `RECURSO_CANCELADO` com
`TipoResponsavelMarco.CIDADAO`. Envia notificação a todos os envolvidos.

**Response:** HTTP 200 com `boolean`.

---

### 5.9 `PUT /recursos/{recursoId}/recusar` — Recusar Aceite

Chama `RecursoRN.recusar(recursoId)`. Retorna recurso para `RASCUNHO`. Registra marco
`RECURSO_RECUSADO`. Aciona `efetuarRecusas()` para resetar aceites pendentes.
Envia notificação.

**Response:** HTTP 200 com `boolean`.

---

### 5.10 `PUT /recursos/{recursoId}/habilitar-edicao` — Habilitar Edição

Chama `RecursoRN.habilitarEdicao(recursoId)`. Retorna recurso para `RASCUNHO`. Registra
marco `RECURSO_EDITADO`. Aciona `efetuarRecusas()` para resetar aceites.

**Response:** HTTP 200 com `boolean`.

---

## S6 — Endpoints REST — Administração CBM

Base path `/adm/recursos` · Implementação: `RecursoAdmRestImpl` · Autenticação: SOEAuthRest
(role CBM / analista — verificada pela infra SOE PROCERGS).

### 6.1 `GET /adm/recursos/listar` — Listar Recursos (Visão Admin)

Chama `RecursoAdmRN.buscarFiltrato()` / `RecursoBD.listaRecursos()`. Retorna lista paginada
com filtros avançados.

**Query params:**

| Parâmetro | Tipo | Descrição |
|---|---|---|
| `ordenar` / `ordem` | String | Ordenação |
| `paginaAtual` / `tamanho` | int | Paginação |
| `instancia` | Integer | 1 ou 2 |
| `tipoRecurso` | TipoRecurso | Tipo do recurso |
| `numeroLicenciamento` | String | Número do licenciamento |
| `situacaoRecurso` | List\<SituacaoRecurso\> | Filtro de situação |
| `logradouro` | String | Endereço do estabelecimento |
| `cidade` | String | Cidade |
| `nomeSolicitante` | String | Nome do solicitante |
| `dataInicioSolicitacao` | Date | Intervalo de datas |
| `dataFimSolicitacao` | Date | Intervalo de datas |

**Response:** HTTP 200 com `ListaPaginadaRetorno<RecursoResponseDTO>`.

---

### 6.2 `GET /adm/recursos/marcos/{recursoId}` — Marcos do Recurso

Retorna todos os marcos de auditoria do recurso, incluindo os de visibilidade privada
(invisíveis ao cidadão).

**Response:** HTTP 200 com `List<RecursoMarcoED>`.

---

### 6.3 `PUT /adm/recursos/reserva/{idLic}` — Bloquear/Desbloquear Recurso

Aciona `RecursoRN.alterarReservaLicenciamento()` que alterna o flag `recursoBloqueado`
do `LicenciamentoED`. Operação administrativa para situações excepcionais.

**Response:** HTTP 200.

---

### 6.4 `GET /adm/recurso-analise/distribuicao-listar` — Listar para Distribuição

Implementação: `RecursoAnaliseRestImpl`. Chama `RecursoAdmRN` para listar recursos em
`AGUARDANDO_DISTRIBUICAO` sem analista designado.

**Response:** HTTP 200 com `ListaPaginadaRetorno`.

---

### 6.5 `GET /adm/recurso-analise/pendentes-listar` — Listar Análises Pendentes

Lista recursos em `EM_ANALISE` com analista designado mas sem conclusão.

**Response:** HTTP 200 com `ListaPaginadaRetorno`.

---

### 6.6 `GET /adm/recurso-analise/recurso-analistas` — Listar Analistas por Área

Retorna analistas CBM cadastrados no SOE PROCERGS, por área/batalhão.

**Response:** HTTP 200 com `List<AnalistaDTO>`.

---

### 6.7 `PUT /adm/recurso-analise/distribuicoes-recurso` — Distribuir para Analista

Chama `AnaliseRecursoAdmRN.distribuirRecurso()`. Cria a entidade `AnaliseRecursoED`,
transiciona recurso de `AGUARDANDO_DISTRIBUICAO` para `EM_ANALISE`. Notifica analista.

**Request body:**

| Campo | Tipo | Descrição |
|---|---|---|
| `recursoId` | Long | ID do recurso |
| `idUsuarioSoeAnalista` | Long | ID SOE PROCERGS do analista designado |

---

### 6.8 `PUT /adm/recurso-analise/{recursoId}/cancelar-distribuicao` — Cancelar Designação

Remove a designação do analista e retorna o recurso para `AGUARDANDO_DISTRIBUICAO`.

**Response:** HTTP 200.

---

### 6.9 `GET /adm/recurso-analise/{recursoId}` — Consultar Recurso (Analista)

Retorna dados completos incluindo `AnaliseRecursoED`, documentos e histórico de marcos.

**Response:** HTTP 200 com `RecursoAdmDetalheDTO`.

---

### 6.10 `GET /adm/recurso-analise/consulta-analise/{recursoId}` — Consultar Análise

Retorna apenas a entidade `AnaliseRecursoED` do recurso informado.

**Response:** HTTP 200 com `AnaliseRecursoED` ou DTO.

---

### 6.11 `GET /adm/recurso-analise/busca-analista/{usuarioSoeID}` — Análises por Analista

Lista `AnaliseRecursoED` de um analista específico.

**Response:** HTTP 200 com lista paginada.

---

### 6.12 `POST /adm/recurso-analise` — Analisar Recurso (1ª Instância)

Chama `AnaliseRecursoAdmRN.analisarRecurso()`. Registra o resultado final da análise.
Transiciona:
- `AnaliseRecursoED.situacao` → `ANALISE_CONCLUIDA`
- `RecursoED.situacao` → `ANALISE_CONCLUIDA`
- `AnaliseRecursoED.status` → valor informado (DEFERIDO_TOTAL / DEFERIDO_PARCIAL / INDEFERIDO)
- Executa efeito no licenciamento conforme RN-090.

---

### 6.13 `POST /adm/recurso-analise/segunda-instancia` — Analisar (2ª Instância)

Chama `AnaliseRecursoAdmRN.analisarSegundaInstancia()`. Idêntico ao 6.12, com lógica
adicional de colegiado (`AGUARDANDO_AVALIACAO_COLEGIADO`) e bloqueio definitivo do recurso
ao concluir (seta `recursoBloqueado = true` no licenciamento).

---

### 6.14 `GET /adm/recurso-analise/analistas-disponivel` — Analistas Disponíveis

Lista analistas CBM disponíveis por batalhão para designação.

**Response:** HTTP 200 com `List<AnalistaDTO>`.

---

## S7 — Máquina de Estados

### 7.1 Ciclo de Vida — `SituacaoRecurso`

```
POST /recursos (aceite=false)
    |
    v
RASCUNHO <──────────────────────────── recusar() / habilitarEdicao()
    |                                    (co-signatário recusa)
    | aceite=true, todos os aceites pendentes
    v
AGUARDANDO_APROVACAO_ENVOLVIDOS
    |                             |
    | validaTodosRealizaramAceite()    | cancelar() / cancelarRecurso()
    | (unanimidade)               v
    v                          CANCELADO
AGUARDANDO_DISTRIBUICAO
    |
    | distribuirRecurso() — cria AnaliseRecursoED
    v
EM_ANALISE
    |
    | analisarRecurso() / analisarSegundaInstancia()
    v
ANALISE_CONCLUIDA
    |
    | (StatusRecurso = DEFERIDO_PARCIAL ou INDEFERIDO e instancia=1)
    v
[Possibilidade de novo Recurso com instancia=2]
```

### 7.2 Ciclo de Vida — `SituacaoAnaliseRecursoEnum`

```
[criada em distribuirRecurso()]
    |
    v
EM_ANALISE
    |                             |
    | 1ª instância                | 2ª instância (colegiado)
    v                             v
ANALISE_CONCLUIDA    AGUARDANDO_AVALIACAO_COLEGIADO
                                  |
                                  | votação concluída
                                  v
                             ANALISE_CONCLUIDA
```

### 7.3 Efeito no `SituacaoLicenciamento` após Conclusão

| StatusRecurso | Ação no Licenciamento |
|---|---|
| `DEFERIDO_TOTAL` | Retorna situação ao estado anterior ao CIA/CIV — reinicia P04 (CIA) ou P07 (CIV) |
| `DEFERIDO_PARCIAL` | Mantém situação com pendências; habilita 2ª instância |
| `INDEFERIDO` (1ª inst.) | Mantém situação; habilita 2ª instância |
| `INDEFERIDO` (2ª inst.) | Mantém situação; seta `recursoBloqueado = true` |

---

## S8 — Segurança e Integração SOE PROCERGS

### 8.1 Autenticação

Todo endpoint do P10 é protegido pelo interceptor SOE PROCERGS (`LoginCidadao` para
`/recursos` e `SOEAuthRest` para `/adm/`). O `idUsuarioSoe` (Long) é extraído do token
JWT do SOE e usado como identificador do usuário em todos os registros.

### 8.2 Extração de Identidade

```java
// Dentro das RNs — acesso ao usuário logado via CDI/EJB
UsuarioED usuarioED = usuarioRN.getUsuarioLogado();
Long idSoe = usuarioED.getId(); // = idUsuarioSoe na tabela
```

O campo `NRO_INT_USUARIO_SOE` em `RecursoED` e `AnaliseRecursoED` armazena este valor.

### 8.3 Permissões por Endpoint

| Endpoint | Autenticação | Restrição adicional |
|---|---|---|
| `POST /recursos` | LoginCidadao (openid) | Usuário deve ter vínculo com o licenciamento |
| `GET /recursos/{id}` | LoginCidadao | Deve ser solicitante ou co-signatário |
| `PUT /recursos/{id}` | LoginCidadao | Deve ser co-signatário com aceite pendente |
| `DELETE /recursos/{id}/cancelar` | LoginCidadao | Deve ser o solicitante original |
| `PUT /recursos/{id}/recusar` | LoginCidadao | Deve ser co-signatário |
| `GET /adm/recursos/**` | SOEAuthRest | Role analista/admin CBM no SOE |
| `POST /adm/recurso-analise` | SOEAuthRest | Deve ser o analista designado |
| `PUT /adm/recursos/{id}/reserva` | SOEAuthRest | Role admin CBM |

---

## S9 — Integração Alfresco

Todo documento referenciado pelo processo P10 (CIA/CIV original, PDFs de fundamentação,
decisão CBM) é armazenado no **Alfresco ECM**. O Oracle armazena apenas metadados.

### 9.1 Estrutura `ArquivoED`

```java
// CBM_ARQUIVO
@Column(name = "IDENTIFICADOR_ALFRESCO", nullable = false, length = 150)
private String identificadorAlfresco; // workspace://SpacesStore/{UUID}
```

### 9.2 Documentos Referenciados pelo P10

| Documento | Entidade | Campo FK |
|---|---|---|
| CIA ou CIV contestado | `RecursoED.arquivoCiaCivED` | `NRO_INT_ARQUIVO_CIA_CIV` |
| PDFs de suporte do recurso | `RecursoArquivoED.arquivoED` | `NRO_INT_ARQUIVO` |
| Decisão CBM (1ª ou 2ª inst.) | `AnaliseRecursoED.arquivo` | `NRO_INT_ARQUIVO` |

### 9.3 Fluxo de Upload

O upload de documentos ao Alfresco é executado **antes** do `POST /recursos`. O cliente
Angular:
1. Faz upload do arquivo para o endpoint `/arquivos` → recebe `idArquivo`.
2. Inclui o `idArquivoCiaCiv` (e outros IDs de arquivo) no body do `POST /recursos`.

O backend nunca recebe o binário junto com o recurso — apenas os IDs de `ArquivoED`.

---

## S10 — Notificações por E-mail

As notificações são enviadas por `NotificacaoRN.notificar()` usando
`ContextoNotificacaoEnum.RECURSO`. Os templates são gerenciados pelo módulo de mensagens
do SOE PROCERGS (`bundle.getMessage()`).

| Evento | Destinatários | Chave do Template |
|---|---|---|
| Aceite de RT | Demais RTs pendentes | `notificacao.email.assunto.recurso.termo` |
| Unanimidade atingida | Todos os RTs | `notificacao.email.template.recurso.termo` |
| Cancelamento | Todos os envolvidos | Template de cancelamento |
| Recusa | Todos os envolvidos | Template de recusa |

As chaves de template são resolvidas pelo `MessageProvider` injetado via CDI.

---

## S11 — Classes Principais da Camada de Negócio

### 11.1 `RecursoRN` — Lógica de Negócio Cidadão

`@Stateless` `@TransactionAttribute(REQUIRED)` · Principal EJB do P10.

| Método | Transação | Descrição |
|---|---|---|
| `registra(RecursoDTO)` | REQUIRED | Criação do recurso com validação, co-signatários e marco inicial |
| `alterarRecurso(Long, RecursoDTO)` | REQUIRED | Edição e/ou aceite do usuário logado |
| `salvarRecurso(Long, RecursoDTO)` | REQUIRED | Salva rascunho sem disparar aceite |
| `consultarPorId(Long)` | SUPPORTS | Retorna DTO cidadão com `podeAceitarTermo` |
| `efetuarAceites(RecursoED, Long)` | — (privado) | Registra aceite e verifica unanimidade |
| `validaTodosRealizaramAceite(RecursoED)` | — (privado) | Verifica unanimidade e transiciona estado |
| `atualizarSituacaoLicenciamento(RecursoED)` | — (privado) | Atualiza `SituacaoLicenciamento` do licenciamento |
| `cancelarRecurso(Long)` | REQUIRED | Cancela com marco SISTEMA (fluxos automáticos) |
| `cancelar(Long)` | REQUIRED | Cancela com marco CIDADAO e notificação |
| `recusar(Long)` | REQUIRED | Retorna para RASCUNHO — co-signatário recusou |
| `habilitarEdicao(Long)` | REQUIRED | Retorna para RASCUNHO para correção |
| `listarMinhasSolicitacoes()` | SUPPORTS | Lista com filtros para o usuário logado |
| `getPossuiRecursoPendente(Long)` | SUPPORTS | Verifica se licenciamento tem recurso em RASCUNHO ou AGUARDANDO_APROVACAO |
| `toDTO(RecursoED)` | REQUIRED | Monta `RecursoResponseDTO` completo (visão admin/sistema) |
| `toCidadaoDTO(RecursoED)` | — | Monta `RecursoResponseDTO` para cidadão com flags de papel |

### 11.2 `RecursoRNVal` — Validação

Classe CDI injetada em `RecursoRN`. Método `valida(RecursoDTO)` executa RN-073 a RN-079.

### 11.3 `RecursoAdmRN` / `AnaliseRecursoAdmRN` / `AvalistaRecursoAdmRN`

EJBs da camada administrativa (CBM), injetados em `RecursoAdmRestImpl` e
`RecursoAnaliseRestImpl`. Gerenciam distribuição, análise de 1ª e 2ª instância e
consulta colegiada.

### 11.4 `RecursoBD` — Acesso a Dados

`@Stateless` · Usa `DetachedCriteria` do Hibernate para consultas dinâmicas com múltiplos
filtros opcionais, paginação por `DISTINCT_ROOT_ENTITY`, `LEFT_OUTER_JOIN` e
`INNER_JOIN` para entidades relacionadas.

---

## S12 — DTOs Principais

### 12.1 `RecursoDTO` (request de criação/edição)

| Campo | Tipo | Descrição |
|---|---|---|
| `idLicenciamento` | Long | ID do licenciamento |
| `instancia` | Integer | 1 ou 2 |
| `tipoRecurso` | TipoRecurso | Tipo do recurso |
| `tipoSolicitacao` | TipoSolicitacaoRecurso | Integral ou parcial |
| `fundamentacaoLegal` | String | Argumentação |
| `idArquivoCiaCiv` | Long | ID do arquivo CIA/CIV |
| `aceite` | boolean | Se deve submeter imediatamente |
| `cpfRts` | List\<String\> | CPFs dos RTs co-signatários |
| `cpfRus` | List\<String\> | CPFs dos RUs co-signatários |
| `cpfProprietarios` | List\<String\> | CPFs dos Proprietários co-signatários |

### 12.2 `RecursoResponseDTO` (response ao cliente)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do recurso |
| `situacaoRecurso` | SituacaoRecurso | Situação atual |
| `tipoRecurso` | TipoRecurso | Tipo |
| `tipoSolicitacao` | TipoSolicitacaoRecurso | Escopo |
| `fundamentacaoLegal` | String | Texto de fundamentação |
| `instancia` | Integer | Instância |
| `dataEnvioAnalise` | LocalDateTime | Data de envio ao CBM |
| `dataSolicitacaoRecurso` | LocalDateTime | Data de criação (`ctrDthInc`) |
| `licenciamento` | LicenciamentoDTO | Dados completos do licenciamento |
| `rts` | List\<Solicitante\> | RTs co-signatários |
| `rus` | List\<Solicitante\> | RUs co-signatários |
| `proprietarios` | List\<Solicitante\> | Proprietários co-signatários |
| `arquivoCiaCiv` | Arquivo | Documento CIA/CIV contestado |
| `arquivosRecurso` | List\<Arquivo\> | Documentos de suporte |
| `arquivoRecursoPrimeiraInstancia` | Arquivo | Decisão de 1ª instância (se 2ª instância) |
| `recursoDecisao` | RecursoDecisaoDTO | Decisão da análise (status + despacho) |
| `editavel` | boolean | Se o usuário logado pode editar |
| `podeAceitarTermo` | boolean | Se o usuário logado tem aceite pendente |
| `isRt` / `isRu` / `isProprietario` | boolean | Papel do usuário logado neste recurso |
| `vistoria` | ConsultaVistoriaAdmDTO | Dados da última vistoria (quando aplicável) |
| `qtdDiasRecurso` | Long | Dias desde envio ao CBM |
| `numeroAnalise` | String | Número da análise técnica (P04) |
| `ultimaAnalisePor` | String | Nome do último analista do P04 |

### 12.3 `RecursoPendenteDTO`

```java
public class RecursoPendenteDTO {
    private boolean possuiRecursoPendente; // true se há recurso em RASCUNHO ou AGUARDANDO_APROVACAO
    private Long recursoID;               // ID do recurso pendente
}
```

---

## S13 — Rastreabilidade

| Elemento do Processo | Classe EJB / Entidade | Tabela Oracle | Sequência |
|---|---|---|---|
| Criar recurso | `RecursoRN.registra()` | `CBM_RECURSO` | `CBM_ID_RECURSO_SEQ` |
| Validar recurso | `RecursoRNVal.valida()` | — | — |
| Registrar co-signatário RT | `SolicitacaoResponsavelTecnicoRN` | `CBM_SOLICITACAO_RT` | — |
| Registrar co-signatário RU | `SolicitacaoResponsavelUsuarioRN` | `CBM_SOLICITACAO_RU` | — |
| Registrar co-signatário Proprietário | `SolicitacaoProprietarioRN` | `CBM_SOLICITACAO_PROPRIETARIO` | — |
| Aceite de co-signatário | `RecursoRN.efetuarAceites()` | `CBM_SOLICITACAO_*` | — |
| Verificar unanimidade | `RecursoRN.validaTodosRealizaramAceite()` | `CBM_RECURSO` | — |
| Atualizar situação licenciamento | `RecursoRN.atualizarSituacaoLicenciamento()` | `CBM_LICENCIAMENTO` | — |
| Marco do recurso | `RecursoMarcoRN.inclui()` | `CBM_RECURSO_MARCO` | `CBM_ID_RECURSO_MARCO_SEQ` |
| Marco do licenciamento | `LicenciamentoMarcoInclusaoRN.incluiComUsuario()` | `CBM_LICENCIAMENTO_MARCO` | — |
| Arquivos de suporte | `RecursoArquivoRN` | `CBM_RECURSO_ARQUIVO` | `CBM_ID_RECURSO_ARQUIVO_SEQ` |
| Notificação por e-mail | `NotificacaoRN.notificar()` | — | — |
| Distribuir para analista | `AnaliseRecursoAdmRN.distribuirRecurso()` | `CBM_ANALISE_RECURSO` | `CBM_ID_ANALISE_RECURSO_SEQ` |
| Registrar decisão | `AnaliseRecursoAdmRN.analisarRecurso()` | `CBM_ANALISE_RECURSO` | — |
| Cancelar recurso (cidadão) | `RecursoRN.cancelar()` | `CBM_RECURSO` | — |
| Cancelar recurso (sistema) | `RecursoRN.cancelarRecurso()` | `CBM_RECURSO` | — |
| Recusar aceite | `RecursoRN.recusar()` | `CBM_RECURSO` | — |
| Habilitar edição | `RecursoRN.habilitarEdicao()` | `CBM_RECURSO` | — |
| Verificar recurso pendente | `RecursoRN.getPossuiRecursoPendente()` | `CBM_RECURSO` | — |
| Documento CIA/CIV | `ArquivoED.identificadorAlfresco` | `CBM_ARQUIVO` | — |

---

## S14 — Dependências e Configuração de Infraestrutura

### 14.1 Servidor de Aplicação

WildFly / JBoss com deployment `.ear` ou `.war`. Os EJBs são `@Stateless` com
`@TransactionAttribute(TransactionAttributeType.REQUIRED)` (padrão).

### 14.2 Banco de Dados

Oracle. Sequências Oracle para geração de PKs (`allocationSize = 1`). Dialect JPA/Hibernate
configurado para Oracle no `persistence.xml`.

### 14.3 SOE PROCERGS

- **Autenticação cidadão:** OAuth2 OIDC via `meu.rs.gov.br` — escopo `openid`.
- **Autenticação admin CBM:** `SOEAuthRest` — role específica do SOE.
- **Identificação do usuário:** `idUsuarioSoe` (Long) extraído do token.

### 14.4 Alfresco ECM

Todos os documentos são armazenados no Alfresco. O campo
`CBM_ARQUIVO.IDENTIFICADOR_ALFRESCO` (VARCHAR2 150, NOT NULL) contém o nodeRef
`workspace://SpacesStore/{UUID}`. O binário nunca é persistido no Oracle.

### 14.5 Injeção de Dependência

CDI 1.x (`@Inject`). Os EJBs `@Stateless` são injetados via CDI ou EJB `@EJB`.
O `@PostConstruct initBD()` em `RecursoRN` configura o BD base:

```java
@PostConstruct
public void initBD() {
    setBD(recursoBD);
}
```

---

## S15 — Complementos Normativos (RTCBMRS N.º 01/2024 · RT de Implantação SOL-CBMRS 4ª Ed./2022)

Esta seção acrescenta regras de negócio e correções derivadas da leitura direta da RT de Implantação SOL-CBMRS 4ª Edição/2022 e da RTCBMRS N.º 01/2024. Nenhuma regra anterior é revogada; estas regras complementam ou refinam o que estava documentado nas seções S1–S14.

---

### CORREÇÃO — Prazo do Recurso em Dias ÚTEIS

**Base normativa:** item 12.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

A tabela apresentada em S1 indicava prazos em dias **corridos**. A norma estabelece prazos em dias **úteis**:

| Instância | Prazo (correto) | Evento de início da contagem |
|---|---|---|
| **1ª instância** | **30 (trinta) dias úteis** | Ciência formal da CIA, CIV ou decisão administrativa |
| **2ª instância** | **15 (quinze) dias úteis** | Ciência da decisão de 1ª instância |

**Impacto no sistema:**

- As constantes `PRAZO_SOLICITAR_1_INSTANCIA = 30` e `PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15` devem ser interpretadas como **dias úteis**, não corridos.
- O cálculo de prazos deve utilizar a tabela `sol.feriado` (feriados federais e estaduais do RS) para excluir dias não úteis e finais de semana.
- A data-limite exibida ao cidadão e ao analista deve ser calculada em dias úteis e apresentada no formato `DD/MM/AAAA`.
- O cálculo de dias úteis deve ser implementado em um serviço utilitário reutilizável (ex.: `DiasUteisService` / `DiasUteisRN`) consultando a tabela de feriados.

---

### RN-P10-N1 — PPCI Bloqueado para Edição durante o Recurso

**Base normativa:** item 12.5 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

Durante toda a fase de recurso (situações `RECURSO_EM_ANALISE_1_CIA`, `RECURSO_EM_ANALISE_2_CIA`, `RECURSO_EM_ANALISE_1_CIV`, `RECURSO_EM_ANALISE_2_CIV` no licenciamento), o PPCI não pode sofrer qualquer alteração pelo proprietário, responsável pelo uso ou RT.

**Requisitos de implementação:**

- O sistema bloqueia todos os campos de edição do licenciamento (dados cadastrais, responsáveis, documentos) enquanto houver recurso em análise.
- Todos os botões de upload de arquivo e de edição de dados do PPCI ficam desabilitados na interface.
- Qualquer tentativa de alteração via API retorna HTTP 409 com mensagem `"recurso.ativo.ppci.bloqueado.para.edicao"`.
- Se o proprietário, RU ou RT efetuar qualquer alteração durante o recurso (por meio de operação administrativa excepcional), o recurso é **encerrado automaticamente** com `StatusRecurso.CANCELADO` e marco `RECURSO_CANCELADO_POR_ALTERACAO_PPCI`.
- Após o encerramento automático, nova CIA ou CIV deve ser emitida pelo CBM-RS para que novo recurso possa ser interposto sobre a mesma inconformidade.

---

### RN-P10-N2 — Recurso Isento de Taxa

**Base normativa:** item 12.4 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

A apresentação de recurso administrativo é **isenta de pagamento de taxa** em todas as fases e instâncias.

**Requisitos de implementação:**

- O sistema **não deve gerar boleto** em nenhuma fase do processo de recurso (P10).
- O sistema **não deve exigir pagamento** nem exibir tela de pagamento em nenhum momento do fluxo do recurso.
- A criação de `RecursoED` não deve acionar o processo P11 (Pagamento de Boleto).
- A integração com o Banrisul (CNAB 240) não é invocada para o processo de recurso.
- Qualquer consulta ao endpoint de responsáveis para pagamento (`/responsaveis-pagamento`) deve retornar lista vazia ou erro 404 quando invocada no contexto de um recurso, sinalizando que não há cobrança.

---

### RN-P10-N3 — Bloqueio Automático de Recurso Intempestivo

**Base normativa:** item 12.2 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

Recursos apresentados fora do prazo estabelecido (30 dias úteis para 1ª instância; 15 dias úteis para 2ª instância) não são aceitos pelo sistema.

**Requisitos de implementação:**

- O botão "Interpor Recurso" é desabilitado na interface do cidadão após o decurso do prazo em dias úteis.
- O botão desabilitado exibe a mensagem: `"Prazo encerrado em DD/MM/AAAA"` (data da expiração calculada em dias úteis).
- O endpoint `POST /recursos` deve validar o prazo no backend (`RecursoRNVal`). Se o prazo estiver encerrado, retorna HTTP 422 com mensagem `"recurso.prazo.encerrado"`.
- O bloqueio definitivo é registrado pelo job automático `RN-P13-N5` (ver documento de jobs P13), que registra o marco `PRAZO_RECURSO_ENCERRADO` no licenciamento.
- Uma vez bloqueado, nenhuma ação de qualquer ator pode reabrir o prazo — apenas ação administrativa excepcional documentada em Boletim Interno ou Geral do CBM-RS.

---

### RN-P10-N4 — Autoridade Julgadora de 1ª Instância

**Base normativa:** item 12.1.4 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

A autoridade competente de 1ª instância é o **Chefe da Seção de Segurança Contra Incêndio (SSeg) do BBM** onde foram emitidas a CIA, CIV ou decisão administrativa, ou Oficial do Corpo Técnico do CBM-RS nomeado em Boletim Interno ou Geral.

**Requisitos de implementação:**

- O perfil `CHEFE_SSEG_BBM` no sistema tem acesso exclusivo à funcionalidade de julgamento de recurso de 1ª instância para processos de seu BBM de atuação.
- O sistema deve filtrar, na distribuição de recursos de 1ª instância, apenas analistas com perfil `CHEFE_SSEG_BBM` vinculados ao BBM do licenciamento.
- Se o Chefe SSeg for o mesmo analista que emitiu a CIA ou CIV contestada, o sistema deve alertar o administrador e sugerir a designação de Oficial do Corpo Técnico nomeado por Boletim Interno, para preservar a imparcialidade.
- O campo `nomeacaoBoletin` (VARCHAR2 100) deve ser registrado em `AnaliseRecursoED` quando a autoridade julgadora foi nomeada por Boletim, para fins de rastreabilidade.

---

### RN-P10-N5 — Autoridade Julgadora de 2ª Instância — Junta de 3 Oficiais

**Base normativa:** item 12.1.5 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

A autoridade de 2ª instância é uma **Junta composta por 3 Oficiais do Corpo Técnico do CBM-RS**, nomeados em Boletim Interno ou Geral, presidida pelo mais antigo em posto e antiguidade.

**Requisitos de implementação:**

- O sistema deve permitir o registro da composição da Junta com os 3 membros (nome, posto, matrícula e referência ao Boletim de nomeação).
- Cada membro da Junta deve registrar seu **voto individualmente** na interface administrativa, com campo obrigatório de justificativa textual.
- O presidente da Junta (membro mais antigo) possui **voto de minerva** em caso de empate (2×1 ou situação de impasse). O sistema deve identificar o presidente com base no campo `antiguidadeOrdem` registrado.
- A decisão final registrada em `AnaliseRecursoED.status` reflete o resultado da votação da Junta.
- O campo `composicaoJunta` deve ser adicionado à entidade `AnaliseRecursoED` (ou em tabela filha `CBM_JUNTA_RECURSO`) para armazenar a composição e os votos individuais.
- O campo `recursoBloqueado = true` é setado no `LicenciamentoED` após a conclusão da análise de 2ª instância pela Junta (comportamento já existente — confirmado pela norma).

**Estrutura de dados sugerida para a Junta:**

| Campo | Coluna (Oracle) | Tipo | Descrição |
|---|---|---|---|
| `idAnaliseRecurso` | `NRO_INT_ANALISE_RECURSO` | FK | Análise de 2ª instância associada |
| `idMembroSoe` | `NRO_INT_USUARIO_SOE_MEMBRO` | NUMBER | ID SOE PROCERGS do membro |
| `isPresidente` | `IND_PRESIDENTE` | CHAR(1) | `'S'` = presidente da Junta |
| `voto` | `TP_VOTO` | VARCHAR2(30) | `DEFERIDO`, `DEFERIDO_PARCIAL`, `INDEFERIDO` |
| `justificativaVoto` | `TXT_JUSTIFICATIVA_VOTO` | VARCHAR2(4000) | Fundamentação do voto |
| `boletimNomeacao` | `TXT_BOLETIM_NOMEACAO` | VARCHAR2(100) | Referência ao Boletim de nomeação |

---

### RN-P10-N6 — Documentação do Recurso Apensada ao PPCI

**Base normativa:** item 12.3 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

Toda a documentação produzida durante o julgamento dos recursos de 1ª e 2ª instâncias deve ser **apensada ao PPCI** via upload no SOL-CBMRS.

**Requisitos de implementação:**

- Os documentos produzidos no julgamento (despachos, pareceres, atas da Junta, votos individuais formalizados) devem ser carregados por meio do endpoint de upload de arquivos do sistema (`/arquivos`) e vinculados ao `AnaliseRecursoED` através de `AnaliseRecursoED.arquivo` (já existente) ou de uma lista de arquivos apensos (`CBM_ANALISE_RECURSO_ARQUIVO`).
- O analista de 1ª instância e o presidente da Junta de 2ª instância são os responsáveis por realizar o upload da decisão formalizada antes de concluir a análise.
- O sistema deve **bloquear a conclusão da análise** (`POST /adm/recurso-analise` e `POST /adm/recurso-analise/segunda-instancia`) se nenhum arquivo de decisão foi carregado (`AnaliseRecursoED.arquivo == null`). Retorna HTTP 422 com mensagem `"recurso.analise.documento.obrigatorio"`.
- Os arquivos ficam associados ao `RecursoED` e, por consequência, ao `LicenciamentoED`, podendo ser visualizados na timeline do processo por todos os envolvidos.

---

*Seção S15 adicionada em 2026-03-20. Base normativa: RT de Implantação SOL-CBMRS 4ª Edição/2022 (itens 12.1 a 12.5) e RTCBMRS N.º 01/2024.*
