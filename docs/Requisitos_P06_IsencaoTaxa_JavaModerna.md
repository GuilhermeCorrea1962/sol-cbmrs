# Requisitos — P06: Solicitação de Isenção de Taxa
## Stack Java Moderna (sem dependência PROCERGS)

**Versão:** 1.0
**Data:** 2026-03-10
**Projeto:** SOL — Sistema Online de Licenciamento / CBM-RS
**Processo:** P06 — Solicitação de Isenção de Taxa

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica Alvo](#2-stack-tecnológica-alvo)
3. [Modelo de Domínio — Enumerações](#3-modelo-de-domínio--enumerações)
4. [Modelo de Dados — Entidades JPA](#4-modelo-de-dados--entidades-jpa)
5. [Regras de Negócio — Services](#5-regras-de-negócio--services)
6. [Validações e Restrições](#6-validações-e-restrições)
7. [API REST — Endpoints](#7-api-rest--endpoints)
8. [DTOs — Contratos de Entrada e Saída](#8-dtos--contratos-de-entrada-e-saída)
9. [Modelo de Segurança — Roles e Permissões](#9-modelo-de-segurança--roles-e-permissões)
10. [Armazenamento de Arquivos — MinIO](#10-armazenamento-de-arquivos--minio)
11. [Notificações — E-mail](#11-notificações--e-mail)
12. [Máquinas de Estado](#12-máquinas-de-estado)
13. [Esquema do Banco de Dados — PostgreSQL](#13-esquema-do-banco-de-dados--postgresql)
14. [Integração com Processos Adjacentes](#14-integração-com-processos-adjacentes)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O Processo 06 gerencia a **solicitação, análise e concessão (ou negação) de isenção da taxa de análise** por parte do cidadão / Responsável Técnico (RT) para dois tipos distintos de objeto:

| Sub-processo | Objeto | Descrição |
|---|---|---|
| **P06-A** | Licenciamento (PPCI/APPCI) | Isenção da taxa de análise do licenciamento principal |
| **P06-B** | FACT (Formulário de Atendimento e Consulta Técnica) | Isenção da taxa do FACT (avulso ou vinculado a licenciamento) |

Ambos os sub-processos compartilham a mesma lógica de análise administrativa, mas divergem nas entidades envolvidas, nas transições de estado e nos endpoints REST.

### 1.2 Atores

| Ator | Perfil | Papel no processo |
|---|---|---|
| Cidadão / RT | Usuário autenticado (cidadão ou responsável técnico) | Solicita isenção, envia comprovantes |
| Administrador CBM-RS | Perfil `ADM` com role `ISENCAOTAXA:REVISAR` | Analisa documentação, aprova ou reprova |
| Sistema SOL | Backend | Valida estados, persiste análise, envia notificações, transita estados |

### 1.3 Pré-condições

- **P06-A:** O licenciamento deve estar no status `AGUARDANDO_PAGAMENTO` e com `situacaoIsencao` igual a `SOLICITADA` ou `SOLICITADA_RENOV`.
- **P06-B:** O FACT deve estar no status `AGUARDANDO_PAGAMENTO_ISENCAO` e o campo `isencao` deve ser `true`.
- O cidadão deve ter enviado pelo menos um comprovante de isenção com arquivo e descrição válidos.

### 1.4 Pós-condições

| Decisão | P06-A | P06-B |
|---|---|---|
| **Aprovado** | `situacaoIsencao = APROVADA`, `indIsencao = true`, licenciamento avança para `AGUARDANDO_DISTRIBUICAO` (ou estado de análise conforme tipo PPCI) | FACT avança para `AGUARDANDO_DISTRIBUICAO`, `isencao = true` |
| **Reprovado** | `situacaoIsencao = REPROVADA`, cidadão notificado, mantém obrigação de pagamento | FACT avança para `ISENCAO_REJEITADA`, cidadão notificado |

### 1.5 Funcionalidades incluídas no P06

1. Solicitação de isenção (inicial e renovação) — P06-A
2. Solicitação de isenção de FACT (vinculado e avulso) — P06-B
3. Gestão de comprovantes (upload, listagem, remoção) — ambos
4. Análise administrativa com justificativas NCS — ambos
5. Parâmetros configuráveis NCS (chave `APROVA_ISENCAOTAXA_PREANALISE`)
6. Reanalise de isenção com prazo de 30 dias para correção

---

## 2. Stack Tecnológica Alvo

| Camada | Tecnologia |
|---|---|
| Framework principal | Spring Boot 3.3.x (Jakarta EE 10) |
| Persistência | Spring Data JPA + Hibernate 6.x |
| Banco de dados | PostgreSQL 16.x |
| Segurança / Identity | Spring Security 6.x + Keycloak 24.x (OIDC/OAuth2) |
| Armazenamento de arquivos | MinIO (S3-compatible) |
| Auditoria | Hibernate Envers (anotação `@Audited`) |
| Validação | Jakarta Bean Validation 3.0 (Hibernate Validator) |
| Mapeamento de DTOs | MapStruct 1.6.x |
| Redução de boilerplate | Lombok 1.18.x |
| Documentação API | SpringDoc OpenAPI 3 (Swagger UI) |
| Testes | JUnit 5 + Mockito + Testcontainers |
| Build | Maven 3.9.x ou Gradle 8.x |

### 2.1 Substituições em relação à stack atual

| Stack Atual (PROCERGS) | Stack Nova (independente) |
|---|---|
| SOE PROCERGS (autenticação) | Keycloak 24.x — Resource Server configurado como `spring.security.oauth2.resourceserver.jwt.*` |
| `@SOEAuthRest` (filtro JAX-RS) | `@PreAuthorize("hasRole('...')")` ou SecurityConfig com `requestMatchers` |
| `@Permissao(objeto, acao)` (interceptor CDI) | `@PreAuthorize("hasAuthority('ISENCAOTAXA:REVISAR')")` |
| Alfresco (ECM) | MinIO — bucket `sol-comprovantes-isencao` |
| `arqjava4` (lib arquivo PROCERGS) | `io.minio.MinioClient` |
| WildFly/JBoss + EJB `@Stateless` | Spring Boot embedded Tomcat + `@Service` + `@Transactional` |
| JAX-RS `@Path` | Spring MVC `@RestController` + `@RequestMapping` |
| CDI `@Inject` | Spring `@Autowired` / constructor injection |
| `ListaPaginada<T>` (PROCERGS) | `org.springframework.data.domain.Page<T>` |

---

## 3. Modelo de Domínio — Enumerações

### 3.1 `TipoSituacaoIsencao`

Armazenado como `String` no banco (coluna `VARCHAR(30)`).

```java
public enum TipoSituacaoIsencao {
    SOLICITADA,       // Cidadão solicitou isenção — aguarda análise ADM
    APROVADA,         // ADM aprovou — taxa isenta
    REPROVADA,        // ADM reprovou — cidadão deve pagar
    SOLICITADA_RENOV  // Cidadão solicitou renovação de isenção já aprovada anteriormente
}
```

**Regra:** O campo `situacaoIsencao` em `Licenciamento` só pode ser não-nulo quando o cidadão solicita isenção. Antes da solicitação, o campo é `null`.

### 3.2 `StatusAnaliseLicenciamentoIsencao`

Armazenado como `String` no banco.

```java
public enum StatusAnaliseLicenciamentoIsencao {
    APROVADO,   // ADM aprovou a análise de isenção do licenciamento
    REPROVADO   // ADM reprovou
}
```

### 3.3 `StatusAnaliseFactIsencao`

Armazenado como `String` no banco.

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

### 3.4 `StatusFact` (valores relevantes para P06)

O enum completo pertence ao domínio do FACT (P06-B). Abaixo, apenas os valores que o P06 lê ou grava:

```java
// Valores do StatusFact relevantes para P06-B:
AGUARDANDO_PAGAMENTO_ISENCAO,  // FACT aguardando decisão de isenção
AGUARDANDO_DISTRIBUICAO,       // FACT com isenção aprovada — pronto para distribuição
ISENCAO_REJEITADA              // FACT com isenção reprovada — cidadão deve pagar
```

### 3.5 `SituacaoLicenciamento` (valores relevantes para P06-A)

```java
// Transições de estado desencadeadas pela aprovação de isenção:
AGUARDANDO_PAGAMENTO       → AGUARDANDO_DISTRIBUICAO   // aprovação simples
AGUARDANDO_PAGAMENTO       → ANALISE_ENDERECO_PENDENTE // quando endereço está pendente
AGUARDANDO_PAGAMENTO       → ANALISE_INVIABILIDADE_PENDENTE // quando inviabilidade pendente
```

---

## 4. Modelo de Dados — Entidades JPA

### 4.1 `AnaliseLicenciamentoIsencao`

**Tabela:** `CBM_ANALISE_LIC_ISENCAO`
**Propósito:** Registra cada análise administrativa de isenção de taxa de um licenciamento.

```java
@Entity
@Table(name = "CBM_ANALISE_LIC_ISENCAO")
@Audited
@Getter @Setter @NoArgsConstructor
public class AnaliseLicenciamentoIsencao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_analise_lic_isencao")
    @SequenceGenerator(name = "seq_analise_lic_isencao",
                       sequenceName = "CBM_SEQ_ANALISE_LIC_ISENCAO", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    // FK opcional para vistoria (quando a isenção está vinculada a uma vistoria específica)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_VISTORIA")
    private Vistoria vistoria;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", nullable = false, length = 20)
    private StatusAnaliseLicenciamentoIsencao status;

    @Column(name = "JUSTIFICATIVA_ANTECIPACAO", length = 4000)
    private String justificativaAntecipacao;

    // Identificador do usuário no Keycloak (sub do JWT) — substitui idUsuarioSoe
    @Column(name = "ID_USUARIO", nullable = false, length = 64)
    private String idUsuario;

    // Nome legível do usuário ADM que realizou a análise
    @Column(name = "NOME_USUARIO", nullable = false, length = 64)
    private String nomeUsuario;

    @Column(name = "DTH_ANALISE")
    private LocalDateTime dthAnalise;

    @OneToMany(mappedBy = "analiseLicenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<JustificativaNcsIsencao> justificativasNcs = new ArrayList<>();
}
```

### 4.2 `AnaliseFactIsencao`

**Tabela:** `CBM_ANALISE_FACT_ISENCAO`
**Propósito:** Registra cada análise administrativa de isenção de taxa de um FACT.

```java
@Entity
@Table(name = "CBM_ANALISE_FACT_ISENCAO")
@Audited
@Getter @Setter @NoArgsConstructor
public class AnaliseFactIsencao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_analise_fact_isencao")
    @SequenceGenerator(name = "seq_analise_fact_isencao",
                       sequenceName = "CBM_SEQ_ANALISE_FACT_ISENCAO", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO")
    private Licenciamento licenciamento; // Pode ser null para FACT avulso

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_FACT", nullable = false)
    private Fact fact;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", nullable = false, length = 20)
    private StatusAnaliseFactIsencao status;

    @Column(name = "JUSTIFICATIVA_ANTECIPACAO", length = 4000)
    private String justificativaAntecipacao;

    @Column(name = "ID_USUARIO", nullable = false, length = 64)
    private String idUsuario;

    @Column(name = "NOME_USUARIO", nullable = false, length = 64)
    private String nomeUsuario;

    @Column(name = "DTH_ANALISE")
    private LocalDateTime dthAnalise;

    @OneToMany(mappedBy = "analiseFactIsencao", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<JustificativaNcsFactIsencao> justificativasNcs = new ArrayList<>();
}
```

### 4.3 `ComprovanteIsencao`

**Tabela:** `CBM_COMPROVANTE_ISENCAO`
**Propósito:** Armazena metadados do comprovante enviado pelo cidadão como evidência para solicitar isenção. O arquivo binário reside no MinIO.

```java
@Entity
@Table(name = "CBM_COMPROVANTE_ISENCAO")
@Audited
@Getter @Setter @NoArgsConstructor
public class ComprovanteIsencao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_comprovante_isencao")
    @SequenceGenerator(name = "seq_comprovante_isencao",
                       sequenceName = "CBM_SEQ_COMPROVANTE_ISENCAO", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO")
    private Licenciamento licenciamento; // Null para comprovante de FACT avulso

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_FACT")
    private Fact fact; // Null para comprovante de licenciamento

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_VISTORIA")
    private Vistoria vistoria; // Null quando não vinculado a vistoria específica

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ARQUIVO", nullable = false)
    @NotNull
    private Arquivo arquivo; // Metadados do arquivo — binário no MinIO

    @Column(name = "DESCRICAO", nullable = false, length = 255)
    @NotBlank
    @Size(max = 255)
    private String descricao;

    @Column(name = "DTH_INCLUSAO", nullable = false)
    private LocalDateTime dthInclusao;
}
```

**Nota:** A entidade `Arquivo` contém o campo `identificadorMinIO` (String, max 150) que referencia o `objectName` no bucket MinIO `sol-comprovantes-isencao`. Este campo substitui o `identificadorAlfresco` da stack atual.

### 4.4 `JustificativaNcsIsencao`

**Tabela:** `CBM_JUSTIFICATIVA_NCS_ISENCAO`
**Propósito:** Armazena a justificativa textual que o ADM fornece para cada parâmetro NCS no ato da análise de isenção de licenciamento.

```java
@Entity
@Table(name = "CBM_JUSTIFICATIVA_NCS_ISENCAO")
@Getter @Setter @NoArgsConstructor
public class JustificativaNcsIsencao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_justif_ncs_isencao")
    @SequenceGenerator(name = "seq_justif_ncs_isencao",
                       sequenceName = "CBM_SEQ_JUSTIF_NCS_ISENCAO", allocationSize = 1)
    private Long id;

    @Column(name = "JUSTIFICATIVA", length = 4000)
    private String justificativa;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ANALISE_LIC_ISENCAO", nullable = false)
    private AnaliseLicenciamentoIsencao analiseLicenciamento;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "ID_PARAMETRO_NCS", nullable = false)
    private ParametroNcs parametroNcs;
}
```

### 4.5 `JustificativaNcsFactIsencao`

**Tabela:** `CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO`
**Propósito:** Mesmo papel que `JustificativaNcsIsencao`, mas para análises de FACT.

```java
@Entity
@Table(name = "CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO")
@Getter @Setter @NoArgsConstructor
public class JustificativaNcsFactIsencao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_justif_ncs_fact_isencao")
    @SequenceGenerator(name = "seq_justif_ncs_fact_isencao",
                       sequenceName = "CBM_SEQ_JUSTIF_NCS_FACT_ISENCAO", allocationSize = 1)
    private Long id;

    @Column(name = "JUSTIFICATIVA", length = 4000)
    private String justificativa;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ANALISE_FACT_ISENCAO", nullable = false)
    private AnaliseFactIsencao analiseFactIsencao;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "ID_PARAMETRO_NCS", nullable = false)
    private ParametroNcs parametroNcs;
}
```

### 4.6 `ParametroNcs`

**Tabela:** `CBM_PARAMETRO_NCS`
**Propósito:** Tabela de parâmetros configuráveis pelo administrador do sistema para as justificativas NCS. A chave `APROVA_ISENCAOTAXA_PREANALISE` filtra os parâmetros apresentados na tela de análise de isenção.

```java
@Entity
@Table(name = "CBM_PARAMETRO_NCS")
@Getter @Setter @NoArgsConstructor
public class ParametroNcs {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_parametro_ncs")
    @SequenceGenerator(name = "seq_parametro_ncs",
                       sequenceName = "CBM_SEQ_PARAMETRO_NCS", allocationSize = 1)
    private Long id;

    @Column(name = "CHAVE", nullable = false, length = 60)
    @NotBlank
    @Size(max = 60)
    private String chave;

    @Column(name = "VALOR", nullable = false, length = 255)
    @NotBlank
    @Size(max = 255)
    private String valor;

    @Column(name = "ATIVO")
    private Boolean ativo;

    @Column(name = "ORDEM")
    private Integer ordem;
}
```

**Chaves de parâmetro conhecidas:**

| Chave | Uso |
|---|---|
| `APROVA_ISENCAOTAXA_PREANALISE` | Lista as justificativas NCS exibidas na tela de análise de isenção (licenciamento e FACT) |

### 4.7 Campos relevantes em entidades existentes

#### `Licenciamento` (campos adicionados/modificados para P06)

```java
// Campo de situação da isenção — null quando não há solicitação ativa
@Enumerated(EnumType.STRING)
@Column(name = "SITUACAO_ISENCAO", length = 20)
private TipoSituacaoIsencao situacaoIsencao;

// Indicador booleano de isenção concedida — armazenado como 'S'/'N' no BD
@Convert(converter = SimNaoBooleanConverter.class)
@Column(name = "IND_ISENCAO", length = 1)
private Boolean indIsencao;

// Método utilitário
public boolean isIsento() {
    return Boolean.TRUE.equals(indIsencao);
}
```

**`SimNaoBooleanConverter`** — converter reutilizado de P03:

```java
@Converter
public class SimNaoBooleanConverter implements AttributeConverter<Boolean, String> {
    @Override
    public String convertToDatabaseColumn(Boolean attribute) {
        return Boolean.TRUE.equals(attribute) ? "S" : "N";
    }
    @Override
    public Boolean convertToEntityAttribute(String dbData) {
        return "S".equalsIgnoreCase(dbData);
    }
}
```

#### `Fact` (campos relevantes para P06-B)

```java
// Indica se o FACT solicitou isenção
@Convert(converter = SimNaoBooleanConverter.class)
@Column(name = "ISENCAO", length = 1)
private Boolean isencao;

// Status atual do FACT (enum StatusFact)
@Enumerated(EnumType.STRING)
@Column(name = "SITUACAO", length = 40)
private StatusFact situacao;
```

---

## 5. Regras de Negócio — Services

Todos os services são anotados com `@Service` e `@Transactional`. Métodos que requerem autorização usam `@PreAuthorize`.

### 5.1 `AnaliseLicenciamentoIsencaoService`

**Responsabilidade:** Análise administrativa da isenção de taxa para licenciamentos (P06-A).

```java
@Service
@Transactional
public class AnaliseLicenciamentoIsencaoService {

    /**
     * Registra uma análise de isenção (inicial ou renovação).
     * Permissão exigida: ISENCAOTAXA:REVISAR
     *
     * Regras:
     * - Valida que o licenciamento está com situacaoIsencao == SOLICITADA ou SOLICITADA_RENOV (HTTP 406 caso contrário).
     * - Salva AnaliseLicenciamentoIsencao com status APROVADO ou REPROVADO.
     * - Se APROVADO: seta indIsencao=true, chama transição de estado AGUARDANDO_PAGAMENTO → próximo estado.
     * - Se REPROVADO: seta situacaoIsencao=REPROVADA, envia notificação ao cidadão.
     * - Salva justificativas NCS vinculadas.
     * - Registra marco TipoMarco.SOLICITACAO_ISENCAO (se ainda não existir).
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:REVISAR')")
    public AnaliseLicenciamentoIsencaoDTO incluir(Long idLicenciamento,
                                                  AnaliseLicenciamentoIsencaoRequest request,
                                                  UserDetails currentUser);

    /**
     * Registra análise de renovação de isenção.
     * Mesma lógica de incluir(), mas com situacaoIsencao esperada = SOLICITADA_RENOV.
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:REVISAR')")
    public AnaliseLicenciamentoIsencaoDTO incluirRenovacao(Long idLicenciamento,
                                                           AnaliseLicenciamentoIsencaoRequest request,
                                                           UserDetails currentUser);

    /**
     * Reprova explicitamente — método de conveniência chamado internamente.
     */
    public void reprovarSolicitacao(Licenciamento licenciamento, String idUsuario, String nomeUsuario);

    /**
     * Aprova explicitamente — método de conveniência chamado internamente.
     * Chama transição de estado e gera número do licenciamento se necessário.
     */
    public void aprovarSolicitacao(Licenciamento licenciamento, String idUsuario, String nomeUsuario);

    /**
     * Lista todas as análises de isenção de um licenciamento.
     * Permissão exigida: ISENCAOTAXA:LISTAR
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:LISTAR')")
    public List<AnaliseLicenciamentoIsencaoDTO> listarPorLicenciamento(Long idLicenciamento);

    /**
     * Lista licenciamentos pendentes de análise de isenção (paginado).
     * Permissão exigida: ISENCAOTAXA:LISTAR
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:LISTAR')")
    public Page<LicenciamentoAnaliseIsencaoDTO> listarPendentes(Pageable pageable);
}
```

### 5.2 `AnaliseFactIsencaoService`

**Responsabilidade:** Análise administrativa da isenção de taxa para FACTs (P06-B).

```java
@Service
@Transactional
public class AnaliseFactIsencaoService {

    /**
     * Registra análise de isenção de FACT (realizada pelo ADM).
     * Permissão: ISENCAOTAXA:REVISAR
     *
     * Regras:
     * - Valida que o FACT está com situacao == AGUARDANDO_PAGAMENTO_ISENCAO.
     * - Salva AnaliseFactIsencao com status APROVADO ou REPROVADO.
     * - Se APROVADO: FACT.isencao=true, FACT.situacao=AGUARDANDO_DISTRIBUICAO.
     * - Se REPROVADO: FACT.situacao=ISENCAO_REJEITADA, envia notificação ao cidadão.
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:REVISAR')")
    public AnaliseFactIsencaoDTO incluir(Long idFact,
                                         AnaliseFactIsencaoRequest request,
                                         UserDetails currentUser);

    /**
     * Solicitação de isenção pelo cidadão para um FACT.
     * Sem permissão especial (cidadão autenticado).
     *
     * Regras:
     * - Valida que o FACT pertence ao cidadão autenticado.
     * - Seta FACT.isencao=true, FACT.situacao=AGUARDANDO_PAGAMENTO_ISENCAO.
     */
    public void incluirCidadao(Long idFact, UserDetails currentUser);

    /**
     * Busca a análise de isenção de um FACT específico.
     */
    public Optional<AnaliseFactIsencaoDTO> buscarPorFact(Long idFact);

    /**
     * Lista análises de isenção de FACTs (paginado).
     * Permissão: ISENCAOTAXA:LISTAR
     */
    @PreAuthorize("hasAuthority('ISENCAOTAXA:LISTAR')")
    public Page<AnaliseIsencaoTaxaDTO> lista(Pageable pageable);
}
```

### 5.3 `ComprovanteIsencaoService`

**Responsabilidade:** CRUD de comprovantes de isenção (licenciamento e FACT).

```java
@Service
@Transactional
public class ComprovanteIsencaoService {

    /**
     * Inclui ou altera comprovante vinculado a licenciamento.
     * Regras:
     * - Cidadão só pode gerenciar comprovantes do próprio licenciamento.
     * - Um comprovante sem arquivo (sem binário no MinIO) é inválido.
     */
    public ComprovanteIsencaoDTO incluirOuAlterar(Long idLicenciamento,
                                                   ComprovanteIsencaoRequest request,
                                                   UserDetails currentUser);

    /**
     * Inclui ou altera comprovante vinculado a FACT.
     */
    public ComprovanteIsencaoDTO incluirOuAlterarFact(Long idFact,
                                                       ComprovanteIsencaoRequest request,
                                                       UserDetails currentUser);

    /**
     * Faz upload do arquivo binário para o MinIO e associa ao comprovante.
     * O campo Arquivo.identificadorMinIO é preenchido com o objectName gerado.
     */
    public void incluirArquivo(Long idComprovante, MultipartFile arquivo, UserDetails currentUser);

    /**
     * Retorna o arquivo binário do comprovante a partir do MinIO.
     * Retorna Resource (InputStreamResource) para streaming da resposta HTTP.
     */
    public Resource downloadArquivo(Long idComprovante, UserDetails currentUser);

    /**
     * Remove um comprovante (metadados + arquivo no MinIO).
     */
    public void remover(Long idLicenciamento, Long idComprovante, UserDetails currentUser);

    /**
     * Remove comprovante de FACT.
     */
    public void removerFact(Long idFact, Long idComprovante, UserDetails currentUser);

    /**
     * Lista comprovantes de um licenciamento.
     */
    public List<ComprovanteIsencaoDTO> listaPorLicenciamento(Long idLicenciamento,
                                                              UserDetails currentUser);

    /**
     * Lista comprovantes de um FACT.
     */
    public List<ComprovanteIsencaoDTO> listaPorFact(Long idFact, UserDetails currentUser);
}
```

### 5.4 `LicenciamentoIsencaoService`

**Responsabilidade:** Lógica de determinação se a isenção está aprovada, considerando a fase do licenciamento.

```java
@Service
public class LicenciamentoIsencaoService {

    /**
     * Verifica se a isenção está aprovada para o licenciamento.
     * Diferencia fase PROJETO x EXECUÇÃO:
     * - Fase PROJETO: verifica indIsencao == true E situacaoIsencao == APROVADA
     * - Fase EXECUÇÃO: pode ter lógica distinta conforme tipo de licenciamento
     */
    public boolean isIsencaoAprovada(Licenciamento licenciamento);
}
```

### 5.5 `IsencaoTaxaReanaliseService`

**Responsabilidade:** Controle de reanalise e prazo de correção para isenção.

```java
@Service
public class IsencaoTaxaReanaliseService {

    public static final long PRAZO_CORRECAO = 30L; // dias

    /**
     * Verifica se o licenciamento já passou por uma reanalise de isenção.
     * Quando verdadeiro, o cidadão não pode mais corrigir e reenviar — a isenção
     * é definitivamente negada após o prazo.
     */
    public boolean possuiIsencaoReanalise(Long idLicenciamento);

    /**
     * Verifica se o prazo de 30 dias para correção ainda está dentro do limite.
     * Conta a partir da data da primeira reprovação.
     */
    public boolean estaDentroDoPrazoDeCorrecao(Long idLicenciamento);
}
```

### 5.6 `AnaliseLicenciamentoIsencaoValidacaoService`

**Responsabilidade:** Validações de pré-condição para análise de isenção de licenciamento.

```java
@Service
public class AnaliseLicenciamentoIsencaoValidacaoService {

    /**
     * Valida que o licenciamento está com situacaoIsencao SOLICITADA ou SOLICITADA_RENOV.
     * Lança ResponseStatusException(HttpStatus.NOT_ACCEPTABLE, "Status inválido para análise")
     * caso a condição não seja satisfeita.
     */
    public void validarPendenteIsencao(Licenciamento licenciamento);
}
```

### 5.7 `ParametroNcsService`

**Responsabilidade:** Listagem dos parâmetros NCS para análise de isenção.

```java
@Service
@Transactional(readOnly = true)
public class ParametroNcsService {

    /**
     * Retorna a lista de parâmetros NCS ativos com chave APROVA_ISENCAOTAXA_PREANALISE,
     * ordenada pelo campo `ordem`.
     */
    public List<ParametroNcsDTO> listarParaAnalisarIsencao();
}
```

---

## 6. Validações e Restrições

### 6.1 Validações de estado (pré-análise)

| Condição verificada | Resposta em caso de violação |
|---|---|
| `situacaoIsencao` é `SOLICITADA` ou `SOLICITADA_RENOV` | HTTP 406 — "Solicitação não está em estado pendente de análise" |
| FACT com `situacao == AGUARDANDO_PAGAMENTO_ISENCAO` | HTTP 406 — "FACT não está aguardando análise de isenção" |
| Comprovante com arquivo anexado | HTTP 400 — "Comprovante sem arquivo não pode ser submetido" |
| Cidadão é o proprietário do licenciamento/FACT | HTTP 403 — "Acesso negado" |

### 6.2 Validações de Bean Validation nos DTOs

```java
// AnaliseLicenciamentoIsencaoRequest
public record AnaliseLicenciamentoIsencaoRequest(
    @NotNull StatusAnaliseLicenciamentoIsencao status,
    @Size(max = 4000) String justificativaAntecipacao,
    @NotNull @Valid List<JustificativaNcsIsencaoRequest> justificativasNcs
) {}

// JustificativaNcsIsencaoRequest
public record JustificativaNcsIsencaoRequest(
    @NotNull Long idParametroNcs,
    @Size(max = 4000) String justificativa
) {}

// ComprovanteIsencaoRequest
public record ComprovanteIsencaoRequest(
    Long id, // null para novo
    @NotBlank @Size(max = 255) String descricao
) {}
```

### 6.3 Restrições de negócio para comprovantes

- Cada licenciamento/FACT pode ter múltiplos comprovantes.
- O comprovante deve ter `descricao` preenchida (max 255) e arquivo anexado para ser válido.
- A remoção de comprovante só é permitida enquanto a solicitação estiver com `situacaoIsencao == SOLICITADA` (não após análise).

---

## 7. API REST — Endpoints

Todos os endpoints são prefixados com `/api/v1` e protegidos por JWT (Bearer token emitido pelo Keycloak). Os endpoints administrativos requerem roles específicas.

### 7.1 Análise de Isenção de Licenciamento (ADM)

**Base:** `/api/v1/adm/analise-licenciamentos-isencao`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `GET` | `/pendentes` | `ISENCAOTAXA:LISTAR` | Lista licenciamentos pendentes de análise (paginado) |
| `GET` | `/{id}/licenciamento` | `ISENCAOTAXA:LISTAR` | Retorna detalhes do licenciamento para análise |
| `GET` | `/justificativas` | `ISENCAOTAXA:LISTAR` | Retorna parâmetros NCS para isenção |
| `POST` | `/` | `ISENCAOTAXA:REVISAR` | Registra análise de isenção (aprovação ou reprovação) |
| `POST` | `/renovacao` | `ISENCAOTAXA:REVISAR` | Registra análise de renovação de isenção |

**GET /pendentes — Query Params:**
```
page=0&size=20&sort=dataSolicitacao,asc
```

**GET /pendentes — Response 200:**
```json
{
  "content": [
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
  "totalElements": 45,
  "totalPages": 3,
  "size": 20,
  "number": 0
}
```

**POST / — Request Body:**
```json
{
  "idLicenciamento": 1001,
  "status": "APROVADO",
  "justificativaAntecipacao": "Documentação completa e válida.",
  "justificativasNcs": [
    {
      "idParametroNcs": 3,
      "justificativa": "Isenção concedida por critério social."
    }
  ]
}
```

**POST / — Response 201 Created:** `Location: /api/v1/adm/analise-licenciamentos-isencao/{id}`

### 7.2 Análise de Isenção de FACT (ADM)

**Base:** `/api/v1/adm/analises-fact-isencao`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `GET` | `/` | `ISENCAOTAXA:LISTAR` | Lista análises de FACT (paginado) |
| `POST` | `/` | `ISENCAOTAXA:REVISAR` | Registra análise de isenção de FACT |

**POST / — Request Body:**
```json
{
  "idFact": 500,
  "status": "REPROVADO",
  "justificativaAntecipacao": "Documentação insuficiente.",
  "justificativasNcs": []
}
```

### 7.3 Solicitação de Isenção pelo Cidadão — Licenciamento

**Base:** `/api/v1/licenciamentos/{idLicenciamento}`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `PUT` | `/solicitacao-isencao` | Cidadão autenticado (dono do lic.) | Solicita ou renova isenção |

**PUT /solicitacao-isencao — Request Body:**
```json
{
  "solicitacao": true,
  "solicitacaoRenovacao": false
}
```

**Regras:**
- Se `solicitacao=true` e `solicitacaoRenovacao=false`: seta `situacaoIsencao=SOLICITADA`
- Se `solicitacao=false` e `solicitacaoRenovacao=true`: seta `situacaoIsencao=SOLICITADA_RENOV`
- Só permitido quando `situacaoIsencao` é `null`, `REPROVADA` (nova tentativa) ou `APROVADA` (renovação)

### 7.4 Solicitação de Isenção pelo Cidadão — FACT

**Base:** `/api/v1/facts/{idFact}`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `PUT` | `/solicitacao-isencao` | Cidadão autenticado (dono do FACT) | Solicita isenção de FACT |

**PUT /solicitacao-isencao — Request Body:**
```json
{
  "solicitacao": true
}
```

### 7.5 Comprovantes de Isenção — Licenciamento

**Base:** `/api/v1/licenciamentos/{idLicenciamento}/comprovante-isencao`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `GET` | `/` | Cidadão (dono) ou ADM | Lista comprovantes do licenciamento |
| `PUT` | `/` | Cidadão (dono) | Inclui ou altera comprovante (sem arquivo) |
| `POST` | `/{idComprovante}/arquivo` | Cidadão (dono) | Upload do arquivo do comprovante (multipart) |
| `GET` | `/{idComprovante}/arquivo` | Cidadão (dono) ou ADM | Download do arquivo do comprovante |
| `DELETE` | `/{idComprovante}` | Cidadão (dono) | Remove comprovante |

**POST /{idComprovante}/arquivo — Content-Type:** `multipart/form-data`
**Campo:** `arquivo` (binário do PDF/imagem — extensões permitidas: `pdf`, `jpg`, `jpeg`, `png`)
**Tamanho máximo:** 10 MB por arquivo

**GET /{idComprovante}/arquivo — Response:**
`Content-Type: application/octet-stream`
`Content-Disposition: attachment; filename="comprovante_{id}.pdf"`

### 7.6 Comprovantes de Isenção — FACT

**Base:** `/api/v1/facts/{idFact}/comprovante-isencao`

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `GET` | `/` | Cidadão (dono) ou ADM | Lista comprovantes do FACT |
| `PUT` | `/` | Cidadão (dono) | Inclui ou altera comprovante |
| `POST` | `/{idComprovante}/arquivo` | Cidadão (dono) | Upload do arquivo |
| `GET` | `/{idComprovante}/arquivo` | Cidadão (dono) ou ADM | Download do arquivo |
| `DELETE` | `/{idComprovante}` | Cidadão (dono) | Remove comprovante |

### 7.7 Retornos e histórico de FACT

| Método | Path | Permissão | Descrição |
|---|---|---|---|
| `GET` | `/api/v1/retornos-solicitacao-fact/fact/{idFact}` | Cidadão (dono) | Retorna histórico de análises/retornos do FACT |

---

## 8. DTOs — Contratos de Entrada e Saída

### 8.1 `LicenciamentoAnaliseIsencaoDTO` (item da lista paginada de pendentes)

```java
public record LicenciamentoAnaliseIsencaoDTO(
    Long id,
    String razaoSocial,
    String tipo,                 // "PPCI", "APPCI" etc.
    String ocupacaoPredominante,
    BigDecimal area,
    LocalDateTime dataSolicitacao,
    Integer qtdEstabelecimentosPrincipais,
    Boolean prioridade,
    LocalTime hora,
    String origem,               // "LIC" / "LICEN" / "RENOV" / "FACT"
    Boolean avulso
) {}
```

### 8.2 `AnaliseLicenciamentoIsencaoDTO`

```java
public record AnaliseLicenciamentoIsencaoDTO(
    Long id,
    Long idLicenciamento,
    StatusAnaliseLicenciamentoIsencao status,
    String justificativaAntecipacao,
    String nomeUsuario,
    LocalDateTime dthAnalise,
    List<JustificativaNcsIsencaoDTO> justificativasNcs
) {}
```

### 8.3 `AnaliseFactIsencaoDTO`

```java
public record AnaliseFactIsencaoDTO(
    Long id,
    Long idLicenciamento,
    Long idFact,
    StatusAnaliseFactIsencao status,
    String justificativaAntecipacao,
    String nomeUsuario,
    LocalDateTime dthAnalise,
    List<JustificativaNcsFactIsencaoDTO> justificativasNcs
) {}
```

### 8.4 `ComprovanteIsencaoDTO`

```java
public record ComprovanteIsencaoDTO(
    Long id,
    String descricao,
    ArquivoDTO arquivo,
    Long idVistoria,
    String tipoVistoria,
    LocalDateTime dataInclusao
) {}
```

### 8.5 `ParametroNcsDTO`

```java
public record ParametroNcsDTO(
    Long id,
    String chave,
    String valor,
    Integer ordem
) {}
```

### 8.6 `ArquivoDTO`

```java
public record ArquivoDTO(
    Long id,
    String nomeOriginal,
    String contentType,
    Long tamanho,        // bytes
    LocalDateTime dthInclusao
    // identificadorMinIO NÃO é exposto ao frontend por segurança
) {}
```

---

## 9. Modelo de Segurança — Roles e Permissões

### 9.1 Configuração do Resource Server (Spring Security)

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/adm/**").hasRole("ADM")
                .requestMatchers("/api/v1/**").authenticated()
                .anyRequest().permitAll()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
            );
        return http.build();
    }

    private JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtGrantedAuthoritiesConverter conv = new JwtGrantedAuthoritiesConverter();
        conv.setAuthoritiesClaimName("realm_access.roles");
        conv.setAuthorityPrefix("ROLE_");
        JwtAuthenticationConverter jwtConv = new JwtAuthenticationConverter();
        jwtConv.setJwtGrantedAuthoritiesConverter(conv);
        return jwtConv;
    }
}
```

### 9.2 Mapeamento de permissões — stack atual → nova stack

| Permissão stack atual | Role Keycloak equivalente | Uso no código |
|---|---|---|
| `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")` | `ISENCAOTAXA:REVISAR` | `@PreAuthorize("hasAuthority('ISENCAOTAXA:REVISAR')")` |
| `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")` | `ISENCAOTAXA:LISTAR` | `@PreAuthorize("hasAuthority('ISENCAOTAXA:LISTAR')")` |
| `@SOEAuthRest` (qualquer usuário autenticado SOE) | `AUTHENTICATED` / `USER` | `authenticated()` no SecurityConfig |

### 9.3 Extração do usuário autenticado

```java
// Utilitário para obter dados do usuário do JWT
@Component
public class SecurityContextHelper {

    public String getIdUsuario(Authentication auth) {
        return ((Jwt) auth.getPrincipal()).getSubject(); // claim "sub"
    }

    public String getNomeUsuario(Authentication auth) {
        return ((Jwt) auth.getPrincipal()).getClaimAsString("name"); // claim "name"
    }

    public String getEmailUsuario(Authentication auth) {
        return ((Jwt) auth.getPrincipal()).getClaimAsString("email");
    }
}
```

---

## 10. Armazenamento de Arquivos — MinIO

### 10.1 Configuração

```yaml
# application.yml
minio:
  endpoint: http://minio:9000
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket-comprovantes: sol-comprovantes-isencao
```

```java
@Configuration
public class MinioConfig {

    @Bean
    public MinioClient minioClient(
            @Value("${minio.endpoint}") String endpoint,
            @Value("${minio.access-key}") String accessKey,
            @Value("${minio.secret-key}") String secretKey) {
        return MinioClient.builder()
            .endpoint(endpoint)
            .credentials(accessKey, secretKey)
            .build();
    }
}
```

### 10.2 `MinioComprovanteIsencaoService`

```java
@Service
public class MinioComprovanteIsencaoService {

    @Value("${minio.bucket-comprovantes}")
    private String bucket;

    /**
     * Faz upload do arquivo e retorna o objectName gerado.
     * O objectName segue o padrão: comprovantes/{idComprovante}/{uuid}_{nomeOriginal}
     */
    public String upload(Long idComprovante, MultipartFile arquivo) throws Exception {
        String objectName = "comprovantes/" + idComprovante + "/"
                          + UUID.randomUUID() + "_" + arquivo.getOriginalFilename();
        minioClient.putObject(
            PutObjectArgs.builder()
                .bucket(bucket)
                .object(objectName)
                .stream(arquivo.getInputStream(), arquivo.getSize(), -1)
                .contentType(arquivo.getContentType())
                .build()
        );
        return objectName;
    }

    /**
     * Retorna InputStream do arquivo para streaming.
     */
    public InputStream download(String objectName) throws Exception {
        return minioClient.getObject(
            GetObjectArgs.builder().bucket(bucket).object(objectName).build()
        );
    }

    /**
     * Remove o arquivo do MinIO.
     */
    public void remove(String objectName) throws Exception {
        minioClient.removeObject(
            RemoveObjectArgs.builder().bucket(bucket).object(objectName).build()
        );
    }
}
```

### 10.3 Estratégia de nomeação de objetos

| Contexto | Padrão do objectName |
|---|---|
| Comprovante de licenciamento | `comprovantes/lic/{idLicenciamento}/{uuid}_{nomeOriginal}` |
| Comprovante de FACT | `comprovantes/fact/{idFact}/{uuid}_{nomeOriginal}` |

O `objectName` gerado é armazenado em `Arquivo.identificadorMinIO` (VARCHAR 150) — substitui o `identificadorAlfresco` da stack atual.

---

## 11. Notificações — E-mail

### 11.1 Notificação de análise de isenção concluída (licenciamento)

**Disparada em:** `AnaliseLicenciamentoIsencaoService.incluir()` após persistência.

**Template:** `notificacao-isencao-analisada.html` (Thymeleaf)

**Assunto:**
- Aprovação: `"CBM-RS SOL — Sua solicitação de isenção de taxa foi APROVADA"`
- Reprovação: `"CBM-RS SOL — Sua solicitação de isenção de taxa foi REPROVADA"`

**Variáveis do template:**

| Variável | Descrição |
|---|---|
| `nomeDestinatario` | Nome do cidadão/RT responsável |
| `numeroLicenciamento` | Número formatado do licenciamento |
| `statusIsencao` | "APROVADA" ou "REPROVADA" |
| `justificativaAntecipacao` | Texto livre fornecido pelo ADM (pode ser null) |
| `dthAnalise` | Data/hora da análise |
| `linkAcesso` | URL do sistema para o cidadão acompanhar |

### 11.2 Notificação de análise de isenção de FACT

**Disparada em:** `AnaliseFactIsencaoService.incluir()` após persistência.

**Template:** `notificacao-fact-isencao-analisada.html`

**Assunto:**
- Aprovação: `"CBM-RS SOL — Isenção de taxa do FACT APROVADA"`
- Reprovação: `"CBM-RS SOL — Isenção de taxa do FACT REPROVADA"`

### 11.3 `IsencaoEmailService`

```java
@Service
public class IsencaoEmailService {

    /**
     * Notifica o cidadão sobre o resultado da análise do licenciamento.
     * Usa o e-mail do claim JWT do cidadão responsável pelo licenciamento.
     */
    public void notificarIsencaoLicenciamentoAnalisada(Licenciamento licenciamento,
                                                        AnaliseLicenciamentoIsencao analise);

    /**
     * Notifica o cidadão sobre o resultado da análise do FACT.
     */
    public void notificarIsencaoFactAnalisada(Fact fact,
                                               AnaliseFactIsencao analise);
}
```

**Implementação de e-mail (Spring Mail):**

```yaml
spring:
  mail:
    host: ${SMTP_HOST}
    port: ${SMTP_PORT:587}
    username: ${SMTP_USER}
    password: ${SMTP_PASS}
    properties:
      mail.smtp.auth: true
      mail.smtp.starttls.enable: true
```

---

## 12. Máquinas de Estado

### 12.1 Máquina de estado — `TipoSituacaoIsencao` (campo `situacaoIsencao` em `Licenciamento`)

```
[null]
  │
  │  Cidadão solicita isenção
  ▼
SOLICITADA ──────────────────────────────────► APROVADA
  │                                              │
  │  ADM reprova                                 │  (indIsencao=true)
  ▼                                              │
REPROVADA                                        ▼
  │                                          Licenciamento avança de estado
  │  Cidadão solicita renovação
  ▼
SOLICITADA_RENOV ──────────────────────────► APROVADA
  │                                              │
  │  ADM reprova renovação                       │
  ▼                                              │
REPROVADA                              (ciclo encerrado)
```

### 12.2 Máquina de estado — `StatusFact` (valores relevantes P06-B)

```
AGUARDANDO_PAGAMENTO_ISENCAO
        │
        ├── ADM aprova ──► AGUARDANDO_DISTRIBUICAO
        │                   (isencao=true)
        │
        └── ADM reprova ──► ISENCAO_REJEITADA
                            (cidadão deve pagar)
```

### 12.3 Transição de estado do Licenciamento após aprovação (P06-A)

A transição é implementada como um `@Service` específico para cada par de estados (padrão Strategy, substituindo o `TrocaEstado` EJB da stack atual):

```java
@Service
public class LicenciamentoAguardandoPagamentoParaAguardandoDistribuicaoService
        implements TransicaoEstadoLicenciamento {

    /**
     * Pré-condição: situacao == AGUARDANDO_PAGAMENTO && indIsencao == true
     * Pós-condição: situacao == AGUARDANDO_DISTRIBUICAO
     *
     * Ações:
     * 1. Gerar número do licenciamento (se ainda não gerado)
     * 2. Criar marco ENVIO_ATEC
     * 3. Persistir nova situação
     */
    @Transactional
    public void executar(Licenciamento licenciamento);
}
```

**Tabela de transições disparadas pela isenção aprovada:**

| Situação atual | Condição adicional | Próxima situação |
|---|---|---|
| `AGUARDANDO_PAGAMENTO` | Endereço regular | `AGUARDANDO_DISTRIBUICAO` |
| `AGUARDANDO_PAGAMENTO` | Endereço pendente de análise | `ANALISE_ENDERECO_PENDENTE` |
| `AGUARDANDO_PAGAMENTO` | Inviabilidade técnica pendente | `ANALISE_INVIABILIDADE_PENDENTE` |

---

## 13. Esquema do Banco de Dados — PostgreSQL

### 13.1 DDL das novas tabelas

```sql
-- Sequências
CREATE SEQUENCE CBM_SEQ_ANALISE_LIC_ISENCAO START 1 INCREMENT 1;
CREATE SEQUENCE CBM_SEQ_ANALISE_FACT_ISENCAO START 1 INCREMENT 1;
CREATE SEQUENCE CBM_SEQ_COMPROVANTE_ISENCAO START 1 INCREMENT 1;
CREATE SEQUENCE CBM_SEQ_JUSTIF_NCS_ISENCAO START 1 INCREMENT 1;
CREATE SEQUENCE CBM_SEQ_JUSTIF_NCS_FACT_ISENCAO START 1 INCREMENT 1;
CREATE SEQUENCE CBM_SEQ_PARAMETRO_NCS START 1 INCREMENT 1;

-- Parâmetros NCS
CREATE TABLE CBM_PARAMETRO_NCS (
    ID          BIGINT      PRIMARY KEY DEFAULT nextval('CBM_SEQ_PARAMETRO_NCS'),
    CHAVE       VARCHAR(60) NOT NULL,
    VALOR       VARCHAR(255) NOT NULL,
    ATIVO       BOOLEAN,
    ORDEM       INTEGER
);

-- Análise de isenção de licenciamento
CREATE TABLE CBM_ANALISE_LIC_ISENCAO (
    ID                          BIGINT       PRIMARY KEY DEFAULT nextval('CBM_SEQ_ANALISE_LIC_ISENCAO'),
    ID_LICENCIAMENTO            BIGINT       NOT NULL REFERENCES CBM_LICENCIAMENTO(ID),
    ID_VISTORIA                 BIGINT       REFERENCES CBM_VISTORIA(ID),
    STATUS                      VARCHAR(20)  NOT NULL,
    JUSTIFICATIVA_ANTECIPACAO   VARCHAR(4000),
    ID_USUARIO                  VARCHAR(64)  NOT NULL,
    NOME_USUARIO                VARCHAR(64)  NOT NULL,
    DTH_ANALISE                 TIMESTAMP
);

-- Justificativas NCS para isenção de licenciamento
CREATE TABLE CBM_JUSTIFICATIVA_NCS_ISENCAO (
    ID                      BIGINT       PRIMARY KEY DEFAULT nextval('CBM_SEQ_JUSTIF_NCS_ISENCAO'),
    JUSTIFICATIVA           VARCHAR(4000),
    ID_ANALISE_LIC_ISENCAO  BIGINT       NOT NULL REFERENCES CBM_ANALISE_LIC_ISENCAO(ID),
    ID_PARAMETRO_NCS        BIGINT       NOT NULL REFERENCES CBM_PARAMETRO_NCS(ID)
);

-- Análise de isenção de FACT
CREATE TABLE CBM_ANALISE_FACT_ISENCAO (
    ID                          BIGINT       PRIMARY KEY DEFAULT nextval('CBM_SEQ_ANALISE_FACT_ISENCAO'),
    ID_LICENCIAMENTO            BIGINT       REFERENCES CBM_LICENCIAMENTO(ID),
    ID_FACT                     BIGINT       NOT NULL REFERENCES CBM_FACT(ID),
    STATUS                      VARCHAR(20)  NOT NULL,
    JUSTIFICATIVA_ANTECIPACAO   VARCHAR(4000),
    ID_USUARIO                  VARCHAR(64)  NOT NULL,
    NOME_USUARIO                VARCHAR(64)  NOT NULL,
    DTH_ANALISE                 TIMESTAMP
);

-- Justificativas NCS para isenção de FACT
CREATE TABLE CBM_JUSTIFICATIVA_NCS_FACT_ISENCAO (
    ID                        BIGINT       PRIMARY KEY DEFAULT nextval('CBM_SEQ_JUSTIF_NCS_FACT_ISENCAO'),
    JUSTIFICATIVA             VARCHAR(4000),
    ID_ANALISE_FACT_ISENCAO   BIGINT       NOT NULL REFERENCES CBM_ANALISE_FACT_ISENCAO(ID),
    ID_PARAMETRO_NCS          BIGINT       NOT NULL REFERENCES CBM_PARAMETRO_NCS(ID)
);

-- Comprovantes de isenção
CREATE TABLE CBM_COMPROVANTE_ISENCAO (
    ID                BIGINT       PRIMARY KEY DEFAULT nextval('CBM_SEQ_COMPROVANTE_ISENCAO'),
    ID_LICENCIAMENTO  BIGINT       REFERENCES CBM_LICENCIAMENTO(ID),
    ID_FACT           BIGINT       REFERENCES CBM_FACT(ID),
    ID_VISTORIA       BIGINT       REFERENCES CBM_VISTORIA(ID),
    ID_ARQUIVO        BIGINT       NOT NULL REFERENCES CBM_ARQUIVO(ID),
    DESCRICAO         VARCHAR(255) NOT NULL,
    DTH_INCLUSAO      TIMESTAMP    NOT NULL
);
```

### 13.2 Colunas adicionadas em tabelas existentes

```sql
-- Em CBM_LICENCIAMENTO:
ALTER TABLE CBM_LICENCIAMENTO ADD COLUMN SITUACAO_ISENCAO VARCHAR(20);
ALTER TABLE CBM_LICENCIAMENTO ADD COLUMN IND_ISENCAO CHAR(1);

-- Constraint check para IND_ISENCAO:
ALTER TABLE CBM_LICENCIAMENTO
    ADD CONSTRAINT CHK_IND_ISENCAO CHECK (IND_ISENCAO IN ('S', 'N') OR IND_ISENCAO IS NULL);

-- Em CBM_FACT (se não existirem):
ALTER TABLE CBM_FACT ADD COLUMN IF NOT EXISTS ISENCAO CHAR(1);
ALTER TABLE CBM_FACT
    ADD CONSTRAINT CHK_FACT_ISENCAO CHECK (ISENCAO IN ('S', 'N') OR ISENCAO IS NULL);
```

### 13.3 Tabelas de auditoria (Hibernate Envers)

O Envers gera automaticamente as tabelas `_AUD` para entidades anotadas com `@Audited`:

| Tabela principal | Tabela de auditoria gerada |
|---|---|
| `CBM_ANALISE_LIC_ISENCAO` | `CBM_ANALISE_LIC_ISENCAO_AUD` |
| `CBM_ANALISE_FACT_ISENCAO` | `CBM_ANALISE_FACT_ISENCAO_AUD` |
| `CBM_COMPROVANTE_ISENCAO` | `CBM_COMPROVANTE_ISENCAO_AUD` |

Todas as tabelas AUD incluem as colunas `REV` (FK para tabela `REVINFO`) e `REVTYPE` (`0=INSERT`, `1=UPDATE`, `2=DELETE`).

### 13.4 Índices recomendados

```sql
CREATE INDEX IDX_ANALISE_LIC_ISENCAO_LIC ON CBM_ANALISE_LIC_ISENCAO(ID_LICENCIAMENTO);
CREATE INDEX IDX_ANALISE_FACT_ISENCAO_FACT ON CBM_ANALISE_FACT_ISENCAO(ID_FACT);
CREATE INDEX IDX_COMPROVANTE_ISENCAO_LIC ON CBM_COMPROVANTE_ISENCAO(ID_LICENCIAMENTO);
CREATE INDEX IDX_COMPROVANTE_ISENCAO_FACT ON CBM_COMPROVANTE_ISENCAO(ID_FACT);
CREATE INDEX IDX_LICENCIAMENTO_SITUACAO_ISENCAO ON CBM_LICENCIAMENTO(SITUACAO_ISENCAO)
    WHERE SITUACAO_ISENCAO IS NOT NULL;
CREATE INDEX IDX_PARAMETRO_NCS_CHAVE ON CBM_PARAMETRO_NCS(CHAVE);
```

### 13.5 Dados iniciais (INSERT de parâmetros NCS)

```sql
-- Parâmetros NCS para análise de isenção (exemplos baseados no sistema atual)
INSERT INTO CBM_PARAMETRO_NCS (CHAVE, VALOR, ATIVO, ORDEM) VALUES
('APROVA_ISENCAOTAXA_PREANALISE', 'Entidade filantrópica reconhecida', true, 1),
('APROVA_ISENCAOTAXA_PREANALISE', 'Órgão público municipal',           true, 2),
('APROVA_ISENCAOTAXA_PREANALISE', 'Entidade religiosa sem fins lucrativos', true, 3),
('APROVA_ISENCAOTAXA_PREANALISE', 'Microempresa (ME) — critério social', true, 4);
```

---

## 14. Integração com Processos Adjacentes

### 14.1 P03 — Wizard de Nova Solicitação

O P06-A é iniciado durante o fluxo do P03 (Wizard), na etapa de pagamento. O cidadão visualiza o boleto e pode optar por solicitar isenção em vez de pagar. A integração ocorre via campo `situacaoIsencao` na entidade `Licenciamento` — o P06 grava esse campo, e o P03 o verifica para decidir se o licenciamento deve aguardar análise de isenção ou prosseguir para pagamento direto.

**Ponto de integração:**
- `GET /api/v1/licenciamentos/{id}` — o frontend verifica `situacaoIsencao` para renderizar o estado do pagamento.
- `PUT /api/v1/licenciamentos/{id}/solicitacao-isencao` — inicia o P06-A.

### 14.2 P07 — Análise Técnica

Após aprovação de isenção (`AGUARDANDO_DISTRIBUICAO`), o licenciamento entra no fluxo de distribuição para análise técnica (P07). O P06 é pré-requisito para que o licenciamento chegue ao estado de distribuição sem pagamento de taxa.

### 14.3 FACT — Formulário de Atendimento e Consulta Técnica

O P06-B é integrado ao módulo FACT. O campo `isencao` do FACT é controlado pelo P06. FACTs em estado `AGUARDANDO_PAGAMENTO_ISENCAO` ficam na fila de análise de isenção do ADM (endpoint `/adm/analises-fact-isencao`).

### 14.4 Diagrama de dependências de módulos

```
P03 Wizard ──────────────────────────────────────────┐
                                                      │ cria Licenciamento
                                                      ▼
                                              CBM_LICENCIAMENTO
                                                      │ situacaoIsencao
                                                      │ indIsencao
                                                      ▼
P06-A Isenção Licenciamento ──────────────────► AnaliseLicenciamentoIsencao
        │                                             │ aprovação
        │                                             ▼
        │                                     P07 Análise Técnica
        │
        └── ComprovanteIsencao (MinIO)

FACT Module ──────────────────────────────────────────┐
                                                      │ isencao=true
                                                      ▼
                                              CBM_FACT
                                                      │ AGUARDANDO_PAGAMENTO_ISENCAO
                                                      ▼
P06-B Isenção FACT ────────────────────────────► AnaliseFactIsencao
        │                                             │ aprovação
        │                                             ▼
        │                                     AGUARDANDO_DISTRIBUICAO
        │
        └── ComprovanteIsencao (MinIO)
```

---

## Apêndice A — Estrutura de Pacotes Recomendada

```
br.gov.rs.cbm.sol.isencao/
├── api/
│   ├── controller/
│   │   ├── AnaliseLicenciamentoIsencaoController.java
│   │   ├── AnaliseFactIsencaoController.java
│   │   ├── ComprovanteIsencaoLicenciamentoController.java
│   │   └── ComprovanteIsencaoFactController.java
│   └── dto/
│       ├── request/
│       │   ├── AnaliseLicenciamentoIsencaoRequest.java
│       │   ├── AnaliseFactIsencaoRequest.java
│       │   ├── ComprovanteIsencaoRequest.java
│       │   └── JustificativaNcsIsencaoRequest.java
│       └── response/
│           ├── AnaliseLicenciamentoIsencaoDTO.java
│           ├── AnaliseFactIsencaoDTO.java
│           ├── ComprovanteIsencaoDTO.java
│           ├── LicenciamentoAnaliseIsencaoDTO.java
│           ├── AnaliseIsencaoTaxaDTO.java
│           └── ParametroNcsDTO.java
├── domain/
│   ├── entity/
│   │   ├── AnaliseLicenciamentoIsencao.java
│   │   ├── AnaliseFactIsencao.java
│   │   ├── ComprovanteIsencao.java
│   │   ├── JustificativaNcsIsencao.java
│   │   ├── JustificativaNcsFactIsencao.java
│   │   └── ParametroNcs.java
│   └── enums/
│       ├── TipoSituacaoIsencao.java
│       ├── StatusAnaliseLicenciamentoIsencao.java
│       └── StatusAnaliseFactIsencao.java
├── repository/
│   ├── AnaliseLicenciamentoIsencaoRepository.java
│   ├── AnaliseFactIsencaoRepository.java
│   ├── ComprovanteIsencaoRepository.java
│   └── ParametroNcsRepository.java
├── service/
│   ├── AnaliseLicenciamentoIsencaoService.java
│   ├── AnaliseFactIsencaoService.java
│   ├── ComprovanteIsencaoService.java
│   ├── LicenciamentoIsencaoService.java
│   ├── IsencaoTaxaReanaliseService.java
│   ├── AnaliseLicenciamentoIsencaoValidacaoService.java
│   └── ParametroNcsService.java
├── notification/
│   └── IsencaoEmailService.java
├── storage/
│   └── MinioComprovanteIsencaoService.java
└── mapper/
    ├── AnaliseLicenciamentoIsencaoMapper.java
    ├── AnaliseFactIsencaoMapper.java
    └── ComprovanteIsencaoMapper.java
```

---

## Apêndice B — Checklist de Implementação

| # | Item | Prioridade |
|---|---|---|
| 1 | Criar enums `TipoSituacaoIsencao`, `StatusAnaliseLicenciamentoIsencao`, `StatusAnaliseFactIsencao` | Alta |
| 2 | Implementar `SimNaoBooleanConverter` (já existe em P03 — reutilizar) | Alta |
| 3 | Criar entidade `ParametroNcs` + repository + service | Alta |
| 4 | Criar entidade `AnaliseLicenciamentoIsencao` + repository | Alta |
| 5 | Criar entidade `AnaliseFactIsencao` + repository | Alta |
| 6 | Criar entidade `ComprovanteIsencao` + repository | Alta |
| 7 | Criar entidades `JustificativaNcsIsencao` e `JustificativaNcsFactIsencao` | Alta |
| 8 | Adicionar colunas `situacaoIsencao` e `indIsencao` em `Licenciamento` | Alta |
| 9 | Adicionar coluna `isencao` em `Fact` | Alta |
| 10 | Implementar `AnaliseLicenciamentoIsencaoService` com lógica de aprovação/reprovação | Alta |
| 11 | Implementar `AnaliseFactIsencaoService` | Alta |
| 12 | Implementar `ComprovanteIsencaoService` com integração MinIO | Alta |
| 13 | Implementar `MinioComprovanteIsencaoService` | Alta |
| 14 | Criar controllers REST com validação e tratamento de erros | Alta |
| 15 | Configurar Spring Security + Keycloak Resource Server | Alta |
| 16 | Implementar `IsencaoEmailService` com Thymeleaf + Spring Mail | Média |
| 17 | Criar MapStruct mappers para todos os DTOs | Média |
| 18 | Implementar `LicenciamentoIsencaoService` | Média |
| 19 | Implementar `IsencaoTaxaReanaliseService` com lógica de prazo 30 dias | Média |
| 20 | Implementar transições de estado (Strategy pattern) | Média |
| 21 | Criar migrations Flyway/Liquibase com DDL das novas tabelas | Alta |
| 22 | Inserir dados iniciais de parâmetros NCS | Média |
| 23 | Configurar Hibernate Envers para auditoria | Baixa |
| 24 | Criar índices no PostgreSQL | Baixa |
| 25 | Escrever testes unitários para services | Alta |
| 26 | Escrever testes de integração com Testcontainers (PostgreSQL + MinIO + Keycloak) | Média |
| 27 | Documentar API com SpringDoc OpenAPI 3 | Média |


---

## 15. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 01 (ID102, ID103, ID104, ID105) e Sprint 02 (ID3501, ID3502, ID3601) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022.  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P06.
>
> ⚠️ **IMPACTO ALTO — Este processo sofre reescrita parcial significativa.** O P06-A passa de um único tipo de isenção (total) para 5 tipos granularizados por fase. Isso impacta o modelo de dados, o BPMN e as notificações.

---

### RN-P06-N1 — Granularização da Isenção em 5 Tipos por Fase do Processo 🔴 P06-M1

**Prioridade:** CRÍTICA — reescrita do modelo de isenção  
**Origem:** ID102, ID103, ID104, ID105 — Sprint 01 Hammer

**Descrição:** O P06-A atualmente opera com um único tipo de isenção ("total"). Os novos requisitos definem **5 tipos distintos** de isenção, cada um com escopo e regras diferentes:

| Tipo (enum) | Escopo | Situação pós-aprovação |
|---|---|---|
| `PARCIAL_ANALISE` | Apenas a análise corrente | Cidadão deve solicitar nova isenção na revistoria |
| `PARCIAL_FASE_ANALISE` | Toda a fase de análise até o CA | Cidadão deve solicitar nova isenção na vistoria |
| `TOTAL_LICENCIAMENTO` | Todo o processo até o APPCI | Isento de todas as taxas |
| `PARCIAL_VISTORIA` | Apenas a vistoria corrente | Cidadão deve solicitar nova isenção na revistoria |
| `PARCIAL_FASE_VISTORIA` | Toda a fase de vistoria até o APPCI | Isento de todas as taxas de vistoria |

**Mudança no modelo de dados — substituição do campo booleano:**

```sql
-- ANTES
ALTER TABLE cbm_analise_isencao DROP COLUMN IF EXISTS fg_isenta;

-- DEPOIS
ALTER TABLE cbm_analise_isencao
    ADD COLUMN tp_isenção_aprovada VARCHAR(30)
        CHECK (tp_isenção_aprovada IN (
            'PARCIAL_ANALISE','PARCIAL_FASE_ANALISE','TOTAL_LICENCIAMENTO',
            'PARCIAL_VISTORIA','PARCIAL_FASE_VISTORIA'
        )),
    ADD COLUMN tp_fase_solicitacao VARCHAR(30)
        CHECK (tp_fase_solicitacao IN (
            'ANALISE','REANALISE','VISTORIA','REVISTORIA','RENOVACAO'
        ));
```

**Enum Java:**
```java
public enum TipoIsencao {
    PARCIAL_ANALISE         ("Isenção Parcial — Análise",          FaseIsencao.ANALISE),
    PARCIAL_FASE_ANALISE    ("Isenção Parcial — Fase Análise",     FaseIsencao.ANALISE),
    TOTAL_LICENCIAMENTO     ("Isenção Total — Licenciamento",      null),
    PARCIAL_VISTORIA        ("Isenção Parcial — Vistoria",         FaseIsencao.VISTORIA),
    PARCIAL_FASE_VISTORIA   ("Isenção Parcial — Fase Vistoria",    FaseIsencao.VISTORIA);

    private final String descricao;
    private final FaseIsencao faseAplicavel;
    // constructor + getters
}
```

**Mudança no fluxo P06-A:**
1. Cidadão solicita isenção em qualquer etapa (análise, reanálise, vistoria, revistoria)
2. Sistema identifica e registra a fase da solicitação no campo `tp_fase_solicitacao`
3. ADM CBM visualiza apenas os **tipos de isenção disponíveis para aquela fase** e escolhe qual aprovar
4. Sistema registra o tipo aprovado em `tp_isenção_aprovada` no marco do processo
5. Verificação de elegibilidade para nova solicitação considera o último tipo aprovado

**Regra de disponibilidade por fase:**
```java
public List<TipoIsencao> getIsencoesDisponiveisPorFase(FaseProcesso fase) {
    switch (fase) {
        case ANALISE:
        case REANALISE:
            return List.of(TipoIsencao.PARCIAL_ANALISE, TipoIsencao.PARCIAL_FASE_ANALISE, TipoIsencao.TOTAL_LICENCIAMENTO);
        case VISTORIA:
        case REVISTORIA:
            return List.of(TipoIsencao.PARCIAL_VISTORIA, TipoIsencao.PARCIAL_FASE_VISTORIA, TipoIsencao.TOTAL_LICENCIAMENTO);
        default:
            return List.of(TipoIsencao.TOTAL_LICENCIAMENTO);
    }
}
```

**Marcos atualizados:**
- `ISENCAO_SOLICITADA` → dsComplemento: *"Isenção solicitada — Fase Análise"*
- `ISENCAO_APROVADA` → dsComplemento: *"Isenção aprovada — Parcial Análise (somente esta análise)"*

**Critérios de Aceitação:**
- [ ] CA-P06-N1a: Modelo de dados usa `tp_isenção_aprovada` (enum 5 valores) em vez de booleano
- [ ] CA-P06-N1b: ADM vê apenas os tipos de isenção disponíveis para a fase atual do processo
- [ ] CA-P06-N1c: Marco de aprovação registra o tipo e a fase da isenção aprovada
- [ ] CA-P06-N1d: Cidadão com `PARCIAL_ANALISE` aprovada pode solicitar nova isenção na vistoria
- [ ] CA-P06-N1e: Cidadão com `TOTAL_LICENCIAMENTO` aprovada não pode solicitar nova isenção no mesmo processo

---

### RN-P06-N2 — Regras de Isenção Atualizadas para FACT Vinculado (P06-B) 🟠 P06-M2

**Prioridade:** Alta  
**Origem:** ID3501, ID3502 — Sprint 02 Hammer

**Descrição:** O P06-B (isenção de FACT vinculado) deve reconhecer os 5 tipos de isenção do licenciamento vinculado e aplicar regras específicas. As **6 mensagens de bloqueio** definidas no ID3502 devem ser implementadas.

**6 cenários de bloqueio do FACT:**

| # | Condição | Mensagem exibida |
|---|----------|-----------------|
| 1 | PPCI com CBM — em análise | "O envio do FACT está bloqueado pois o PPCI vinculado está em análise pelo CBMRS." |
| 2 | PPCI com CBM — aguardando pagamento | "O envio do FACT está bloqueado pois o PPCI vinculado aguarda confirmação de pagamento." |
| 3 | PPCI com CBM — em vistoria | "O envio do FACT está bloqueado pois o PPCI vinculado está em processo de vistoria pelo CBMRS." |
| 4 | Isenção FACT negada | "A isenção de taxa do FACT foi negada. Efetue o pagamento da taxa para prosseguir." |
| 5 | Isenção FACT pendente de análise | "A solicitação de isenção do FACT está em análise pelo CBMRS. Aguarde a resposta." |
| 6 | FACT com isenção aprovada | Exibir tipo de isenção aprovado e prosseguir normalmente. |

**Implementação:**
```java
// FactIsencaoValidador.java
public FactIsencaoStatus validarEnvioFact(Fact fact) {
    Licenciamento ppci = licenciamentoRepository.findById(fact.getIdLicenciamentoVinculado())
        .orElseThrow();
    
    if (ppci.getStatus() == StatusLicenciamento.EM_ANALISE) {
        return FactIsencaoStatus.BLOQUEADO_PPCI_EM_ANALISE;
    }
    if (ppci.getStatus() == StatusLicenciamento.AGUARDANDO_PAGAMENTO) {
        return FactIsencaoStatus.BLOQUEADO_PPCI_AGUARDANDO_PAGAMENTO;
    }
    // ... demais cenários
}
```

**Critérios de Aceitação:**
- [ ] CA-P06-N2a: Cada um dos 6 cenários exibe a mensagem correta definida no ID3502
- [ ] CA-P06-N2b: FACT não pode ser enviado quando PPCI está com o CBM (cenários 1, 2, 3)
- [ ] CA-P06-N2c: Isenção aprovada no FACT é registrada com o tipo correto (não apenas booleano)

---

### RN-P06-N3 — Novo Fluxo P06-C: Isenção de Taxa na Renovação de Alvará 🟠 P06-M3

**Prioridade:** Alta  
**Origem:** ID3601 — Sprint 03 Hammer

**Descrição:** Criar uma **terceira variante do P06** — P06-C — para tratar isenção de taxa no contexto de renovação de APPCI. Os tipos disponíveis na renovação são:
- `PARCIAL_VISTORIA`: isenção somente da vistoria de renovação corrente
- `PARCIAL_FASE_VISTORIA`: isenção de toda a fase de vistoria até a emissão do APPCI de renovação

**Integração com P14:**
- No P14, Fase 3 (Pagamento ou Isenção), o botão "Solicitar Isenção" dispara o P06-C
- P06-C retorna ao P14 com o `TipoIsencao` definido para prosseguir no fluxo de renovação

**Pool BPMN P06-C:**
```
[P14: Fase 3] → [P06-C: Início]
                    → [Cidadão solicita tipo de isenção: PARCIAL_VISTORIA ou PARCIAL_FASE_VISTORIA]
                    → [ADM CBM analisa e aprova/nega]
                    → [Notifica cidadão com texto específico]
                    → [Retorna ao P14 com resultado]
```

**Critérios de Aceitação:**
- [ ] CA-P06-N3a: P14 exibe opção "Solicitar Isenção" que dispara o fluxo P06-C
- [ ] CA-P06-N3b: P06-C oferece apenas os tipos `PARCIAL_VISTORIA` e `PARCIAL_FASE_VISTORIA`
- [ ] CA-P06-N3c: Após aprovação/negação, o P14 retoma no ponto correto com o resultado da isenção

---

### RN-P06-N4 — Bloquear Nova Solicitação de Vistoria Após 30 Dias da Ciência do CIV 🔴 P06-M4

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C3 / Correção 3 — RT de Implantação SOL-CBMRS item 6.4.8.1

**Descrição:** Após a ciência do CIV, o cidadão tem **30 dias corridos** para protocolar nova vistoria. Após esse prazo, o PPCI deve ser suspenso automaticamente e o botão "Solicitar Nova Vistoria" deve ser desabilitado.

**Campo necessário no banco:**
```sql
ALTER TABLE cbm_vistoria
    ADD COLUMN dt_ciencia_civ DATE;
```

**Exibição no portal do cidadão:**
```
Prazo para solicitar nova vistoria: DD/MM/AAAA (X dias restantes)
```

**Bloqueio no backend:**
```java
public void validarSolicitacaoNovaVistoria(Licenciamento lic) {
    if (lic.getDtCienciaCiv() != null) {
        LocalDate prazoLimite = lic.getDtCienciaCiv().plusDays(30);
        if (LocalDate.now().isAfter(prazoLimite)) {
            throw new BusinessException(
                "O prazo de 30 dias para solicitar nova vistoria encerrou em " +
                prazoLimite.format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) +
                ". O processo será suspenso automaticamente.");
        }
    }
}
```

**Nota:** O job de suspensão automática está especificado em P13-N1 e P07-N3.

**Critérios de Aceitação:**
- [ ] CA-P06-N4a: Portal exibe contador "X dias restantes para solicitar nova vistoria"
- [ ] CA-P06-N4b: Botão "Solicitar Nova Vistoria" desabilitado após 30 dias da ciência do CIV
- [ ] CA-P06-N4c: API retorna 422 ao tentar solicitar vistoria após o prazo

---

### RN-P06-N5 — Tipo de Isenção Registrado nos Marcos e nas Notificações ao Cidadão 🟠 P06-M5

**Prioridade:** Alta  
**Origem:** ID104, ID105 — Sprint 01 Hammer

**Descrição:** Os marcos de solicitação e aprovação de isenção devem descrever o tipo e a fase. As mensagens enviadas ao cidadão devem descrever o tipo de isenção aprovado com **texto específico para cada tipo** (definido no ID105).

**Textos das notificações por tipo (ID105):**

| Tipo | Mensagem ao cidadão |
|---|---|
| `PARCIAL_ANALISE` | "Sua solicitação de isenção foi aprovada para a análise atual. Para as próximas etapas (vistoria), será necessário solicitar nova isenção." |
| `PARCIAL_FASE_ANALISE` | "Sua solicitação de isenção foi aprovada para toda a fase de análise até a emissão do Certificado de Aprovação." |
| `TOTAL_LICENCIAMENTO` | "Sua solicitação de isenção total foi aprovada. Você está isento de todas as taxas deste processo de licenciamento." |
| `PARCIAL_VISTORIA` | "Sua solicitação de isenção foi aprovada para a vistoria atual. Para a próxima vistoria, será necessário solicitar nova isenção." |
| `PARCIAL_FASE_VISTORIA` | "Sua solicitação de isenção foi aprovada para toda a fase de vistoria até a emissão do APPCI." |

**Critérios de Aceitação:**
- [ ] CA-P06-N5a: E-mail enviado ao cidadão contém o texto específico para o tipo de isenção aprovado
- [ ] CA-P06-N5b: Marco de aprovação registra: "Isenção aprovada — {tipo} ({fase})"
- [ ] CA-P06-N5c: Marco de solicitação registra: "Isenção solicitada — Fase {fase}"

---

### Resumo das Mudanças P06 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P06-M1 | RN-P06-N1 | Granularizar P06-A em 5 tipos de isenção por fase (REESCRITA PARCIAL) | 🔴 Crítica |
| P06-M4 | RN-P06-N4 | Bloquear nova vistoria após 30 dias da ciência do CIV (OBRIGATÓRIO) | 🔴 Crítica |
| P06-M2 | RN-P06-N2 | P06-B: 5 tipos de isenção no FACT vinculado + 6 mensagens de bloqueio | 🟠 Alta |
| P06-M3 | RN-P06-N3 | P06-C: Novo fluxo de isenção para renovação de alvará | 🟠 Alta |
| P06-M5 | RN-P06-N5 | Tipo de isenção registrado nos marcos e notificações | 🟠 Alta |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprint 01 (ID102–ID105, ID3501–ID3502, ID3601) + Normas RTCBMRS*
