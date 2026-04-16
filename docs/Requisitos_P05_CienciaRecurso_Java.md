# Requisitos — P05: Ciência do CIA/CIV e Recurso Administrativo
## Sistema SOL — CBM-RS | Stack Moderna Java (sem dependência PROCERGS)

---

## Sumário

1. [Visão geral e escopo do P05](#1-visão-geral-e-escopo-do-p05)
2. [Stack tecnológica recomendada](#2-stack-tecnológica-recomendada)
3. [Modelo de domínio e entidades](#3-modelo-de-domínio-e-entidades)
4. [Enumerações](#4-enumerações)
5. [Regras de negócio — Ciência do CIA/CIV](#5-regras-de-negócio--ciência-do-ciaciv)
6. [Regras de negócio — Recurso administrativo](#6-regras-de-negócio--recurso-administrativo)
7. [Regras de negócio — Análise do recurso pelo colegiado](#7-regras-de-negócio--análise-do-recurso-pelo-colegiado)
8. [Job de ciência automática](#8-job-de-ciência-automática)
9. [API REST — endpoints completos](#9-api-rest--endpoints-completos)
10. [Segurança e controle de acesso](#10-segurança-e-controle-de-acesso)
11. [Geração e armazenamento de documentos](#11-geração-e-armazenamento-de-documentos)
12. [Notificações](#12-notificações)
13. [Transições de estado](#13-transições-de-estado)
14. [Marcos (audit trail)](#14-marcos-audit-trail)
15. [Persistência e estrutura de banco](#15-persistência-e-estrutura-de-banco)
16. [Estrutura de pacotes recomendada](#16-estrutura-de-pacotes-recomendada)

---

## 1. Visão geral e escopo do P05

O processo P05 compreende duas sub-jornadas interdependentes que ocorrem após a emissão de um **CIA** (Comunicado de Inconformidade na Análise, gerado no P04) ou de um **CIV** (Comunicado de Inconformidade na Vistoria, gerado em processo posterior de vistoria):

### Sub-jornada A — Ciência do CIA/CIV

Após a emissão de um CIA ou CIV, o sistema aguarda que o **RT (Responsável Técnico)**, o **RU (Responsável pelo Uso)** e/ou o **Proprietário** tomem **ciência formal** do documento. A ciência pode ocorrer de duas formas:

- **Ciência manual (cidadão):** o RT ou proprietário acessa o sistema e confirma que leu e compreendeu o comunicado.
- **Ciência automática (sistema):** se o cidadão não agir dentro do prazo configurado, o sistema registra a ciência automaticamente por meio de um job agendado.

### Sub-jornada B — Recurso Administrativo

Após tomar ciência do CIA/CIV, o RT pode discordar da decisão técnica e solicitar um **recurso administrativo** em até **30 dias** (1ª instância) ou **15 dias** (2ª instância). O recurso passa por:

1. Solicitação e confirmação de aceite pelos envolvidos.
2. Análise pelo colegiado do CBM-RS.
3. Emissão de resposta (despacho) com decisão: deferido total, deferido parcial ou indeferido.
4. Ciência da resposta pelo RT.
5. Possibilidade de recurso à 2ª instância se indeferido na 1ª.

### Tipos de ciência suportados

| Tipo | Origem | Entidade | Próximo estado (reprovado) |
|---|---|---|---|
| ATEC | CIA da Análise Técnica (P04) | `AnaliseTecnicaEntity` | `NCA` |
| INVIABILIDADE | CIA de Análise de Inviabilidade | `AnaliseInviabilidadeEntity` | `NCA` |
| CIV | CIV da Vistoria | `VistoriaEntity` | `CIV` |
| APPCI | Ciência do APPCI (automática) | `AppciEntity` | — (sempre aprovado) |

**Pré-condição:** `SituacaoLicenciamento.AGUARDANDO_CIENCIA` ou `AGUARDANDO_CIENCIA_CIV`.

---

## 2. Stack tecnológica recomendada

| Camada | Tecnologia |
|---|---|
| Framework principal | Spring Boot 3.x |
| Linguagem | Java 21 (LTS) |
| Segurança / IdP | Keycloak 24+ (OpenID Connect, JWT) |
| Persistência | Spring Data JPA + Hibernate 6.x |
| Banco de dados | PostgreSQL 16+ |
| Migrações | Flyway |
| Armazenamento de arquivos | MinIO (compatível com S3) |
| Geração de PDF | Apache PDFBox 3.x ou iText 7 |
| Jobs agendados | Spring Scheduler (`@Scheduled`) ou Quartz |
| Mensageria / Notificação | Spring Mail (SMTP) + templates Thymeleaf |
| Auditoria | Spring Data Envers ou tabelas `*_AUD` customizadas |
| API | Spring MVC (REST) — JSON |
| Validação | Jakarta Bean Validation (Hibernate Validator) |
| Testes | JUnit 5 + Mockito + Testcontainers |
| Build | Maven 3.9+ |

### Substituições em relação à stack atual

| Stack atual (Java EE) | Stack moderna (Spring Boot) |
|---|---|
| `@Stateless EJB` | `@Service` Spring |
| `@Inject` CDI | `@Autowired` / construtor Spring |
| `SessionMB` (PROCERGS) | JWT Claims (`SecurityContextHolder`) |
| `@Permissao` PROCERGS | `@PreAuthorize` Spring Security |
| `@AutorizaEnvolvido` | Interceptor Spring / `@PreAuthorize` com SpEL |
| Alfresco ECM | MinIO S3-compatible |
| `AppBD` / `AppRN` (AppBD PROCERGS) | `JpaRepository` Spring Data |
| EJB Timer | `@Scheduled` Spring Scheduler / Quartz |
| `SimNaoBooleanConverter` (Oracle) | `@Convert` Jakarta + `BooleanConverter` PostgreSQL |
| Hibernate Envers `@Audited` | Spring Data Envers ou colunas de auditoria manuais |

---

## 3. Modelo de domínio e entidades

### 3.1 Interface Ciencia

```java
package br.gov.cbmrs.sol.ciencia.domain;

public interface Ciencia {
    Boolean getCiencia();
    void setCiencia(Boolean ciencia);
    Instant getDthCiencia();
    void setDthCiencia(Instant dthCiencia);
    Long getIdUsuarioCiencia();
    void setIdUsuarioCiencia(Long idUsuarioCiencia);
    String getNomeUsuarioCiencia();
    void setNomeUsuarioCiencia(String nomeUsuarioCiencia);

    default boolean possuiCiencia() {
        return Boolean.TRUE.equals(getCiencia());
    }
}
```

### 3.2 Interface LicenciamentoCiencia

```java
package br.gov.cbmrs.sol.ciencia.domain;

public interface LicenciamentoCiencia extends Ciencia {
    Long getIdLicenciamento();
    ArquivoEntity getArquivo();       // CIA ou CIV associado
    TipoCiencia getTipoCiencia();     // ATEC, CIV, INVIABILIDADE, APPCI
}
```

### 3.3 RecursoEntity

```java
@Entity
@Table(name = "sol_recurso")
@EntityListeners(AuditingEntityListener.class)
public class RecursoEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_recurso")
    @SequenceGenerator(name = "seq_recurso", sequenceName = "sol_recurso_seq", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false, length = 50)
    private SituacaoRecurso situacao;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_recurso", nullable = false, length = 30)
    private TipoRecurso tipoRecurso;                // CORRECAO_DE_ANALISE | CORRECAO_DE_VISTORIA

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_solicitacao", length = 20)
    private TipoSolicitacaoRecurso tipoSolicitacao; // INTEGRAL | PARCIAL

    @Column(name = "instancia", nullable = false)
    private Integer instancia;                       // 1 ou 2

    @Column(name = "fundamentacao_legal", columnDefinition = "TEXT")
    private String fundamentacaoLegal;

    @Column(name = "dth_envio_analise")
    private Instant dthEnvioAnalise;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_arquivo_cia_civ")
    private ArquivoEntity arquivoCiaCiv;             // CIA/CIV contestado

    @OneToMany(mappedBy = "recurso", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<AceiteRecursoEntity> aceites = new ArrayList<>();

    @OneToOne(mappedBy = "recurso", cascade = CascadeType.ALL)
    private AnaliseRecursoEntity analise;

    @OneToMany(mappedBy = "recurso", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<RecursoMarcoEntity> marcos = new ArrayList<>();

    @CreatedDate
    @Column(name = "dth_criacao", nullable = false, updatable = false)
    private Instant dthCriacao;

    @LastModifiedDate
    @Column(name = "dth_atualizacao")
    private Instant dthAtualizacao;

    @Column(name = "id_usuario_criacao", nullable = false, updatable = false)
    private Long idUsuarioCriacao;

    @Column(name = "nome_usuario_criacao", nullable = false, updatable = false)
    private String nomeUsuarioCriacao;
}
```

### 3.4 AceiteRecursoEntity

```java
@Entity
@Table(name = "sol_aceite_recurso")
public class AceiteRecursoEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_aceite_recurso")
    @SequenceGenerator(name = "seq_aceite_recurso", sequenceName = "sol_aceite_recurso_seq", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_recurso", nullable = false)
    private RecursoEntity recurso;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_envolvido", nullable = false, length = 30)
    private TipoEnvolvido tipoEnvolvido;             // RT, RU, PROPRIETARIO

    @Column(name = "cpf_envolvido", nullable = false, length = 14)
    private String cpfEnvolvido;

    @Column(name = "nome_envolvido", length = 200)
    private String nomeEnvolvido;

    @Column(name = "ind_aceite")
    private Boolean aceite;                          // null=pendente, true=confirmado

    @Column(name = "dth_aceite")
    private Instant dthAceite;

    @Column(name = "id_usuario_aceite")
    private Long idUsuarioAceite;
}
```

### 3.5 AnaliseRecursoEntity

```java
@Entity
@Table(name = "sol_analise_recurso")
@EntityListeners(AuditingEntityListener.class)
public class AnaliseRecursoEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_analise_recurso")
    @SequenceGenerator(name = "seq_analise_recurso", sequenceName = "sol_analise_recurso_seq", allocationSize = 1)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_recurso", nullable = false, unique = true)
    private RecursoEntity recurso;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false, length = 40)
    private SituacaoAnaliseRecurso situacao;         // EM_ANALISE, AGUARDANDO_COLEGIADO, CONCLUIDA

    @Enumerated(EnumType.STRING)
    @Column(name = "status_resultado", length = 20)
    private StatusResultadoRecurso statusResultado;  // DEFERIDO_TOTAL, DEFERIDO_PARCIAL, INDEFERIDO

    @Column(name = "despacho", columnDefinition = "TEXT")
    private String despacho;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_arquivo_resposta")
    private ArquivoEntity arquivoResposta;           // Documento decisório no MinIO

    @Column(name = "id_usuario_analista", nullable = false)
    private Long idUsuarioAnalista;

    @Column(name = "nome_usuario_analista")
    private String nomeUsuarioAnalista;

    // Campos de ciência da resposta
    @Column(name = "ind_ciencia")
    private Boolean ciencia;

    @Column(name = "dth_ciencia")
    private Instant dthCiencia;

    @Column(name = "id_usuario_ciencia")
    private Long idUsuarioCiencia;

    @Column(name = "nome_usuario_ciencia")
    private String nomeUsuarioCiencia;

    @CreatedDate
    @Column(name = "dth_criacao", nullable = false, updatable = false)
    private Instant dthCriacao;

    @LastModifiedDate
    @Column(name = "dth_atualizacao")
    private Instant dthAtualizacao;
}
```

### 3.6 RecursoMarcoEntity

```java
@Entity
@Table(name = "sol_recurso_marco")
public class RecursoMarcoEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_recurso_marco")
    @SequenceGenerator(name = "seq_recurso_marco", sequenceName = "sol_recurso_marco_seq", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_recurso", nullable = false)
    private RecursoEntity recurso;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_marco", nullable = false, length = 80)
    private TipoMarcoRecurso tipoMarco;

    @Column(name = "dth_marco", nullable = false)
    private Instant dthMarco;

    @Column(name = "descricao", length = 200)
    private String descricao;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_responsavel", length = 20)
    private TipoResponsavelMarco tipoResponsavel;    // CIDADAO, SISTEMA, ANALISTA

    @Column(name = "id_usuario_responsavel")
    private Long idUsuarioResponsavel;

    @Column(name = "nome_usuario_responsavel", length = 200)
    private String nomeUsuarioResponsavel;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_arquivo")
    private ArquivoEntity arquivo;
}
```

### 3.7 CienciaDocumentoEntity (tabela de ciência manual e automática)

```java
@Entity
@Table(name = "sol_ciencia_documento")
public class CienciaDocumentoEntity {
    // Tabela que registra a ciência de qualquer documento CIA/CIV/APPCI
    // independentemente do tipo. Alternativa ao campo inline nas entidades de análise.

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_ciencia_doc")
    @SequenceGenerator(name = "seq_ciencia_doc", sequenceName = "sol_ciencia_doc_seq", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_arquivo", nullable = false)
    private ArquivoEntity arquivo;                   // Documento que recebeu ciência

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_ciencia", nullable = false, length = 30)
    private TipoCiencia tipoCiencia;                 // ATEC, CIV, INVIABILIDADE, APPCI

    @Column(name = "ind_automatica", nullable = false)
    private boolean automatica;                      // true = ciência pelo sistema

    @Column(name = "ind_ciencia", nullable = false)
    private Boolean ciencia;

    @Column(name = "dth_ciencia")
    private Instant dthCiencia;

    @Column(name = "id_usuario_ciencia")
    private Long idUsuarioCiencia;

    @Column(name = "nome_usuario_ciencia")
    private String nomeUsuarioCiencia;

    @Column(name = "dth_limite_prazo")
    private Instant dthLimitePrazo;                  // Data limite para ciência automática
}
```

---

## 4. Enumerações

### 4.1 TipoCiencia

```java
public enum TipoCiencia {
    ATEC,           // Análise Técnica (CIA)
    INVIABILIDADE,  // Análise de Inviabilidade (CIA)
    CIV,            // Vistoria (CIV)
    APPCI,          // APPCI vigente
    APPCI_RENOV     // APPCI renovação
}
```

### 4.2 SituacaoRecurso

```java
public enum SituacaoRecurso {
    RASCUNHO,                       // Criado mas não enviado
    AGUARDANDO_APROVACAO_ENVOLVIDOS, // Aguardando aceite de RT/RU/Proprietário
    AGUARDANDO_DISTRIBUICAO,        // Aceites completos, aguardando analista
    EM_ANALISE,                     // Analista analisando
    ANALISE_CONCLUIDA,              // Decisão emitida, aguardando ciência
    CANCELADO                       // Cancelado
}
```

### 4.3 SituacaoAnaliseRecurso

```java
public enum SituacaoAnaliseRecurso {
    EM_ANALISE,
    AGUARDANDO_AVALIACAO_COLEGIADO,
    ANALISE_CONCLUIDA
}
```

### 4.4 TipoRecurso

```java
public enum TipoRecurso {
    CORRECAO_DE_ANALISE,   // Recurso contra CIA (análise técnica)
    CORRECAO_DE_VISTORIA   // Recurso contra CIV (vistoria)
}
```

### 4.5 TipoSolicitacaoRecurso

```java
public enum TipoSolicitacaoRecurso {
    INTEGRAL,  // Revisão de toda a análise/vistoria
    PARCIAL    // Revisão de itens específicos
}
```

### 4.6 StatusResultadoRecurso

```java
public enum StatusResultadoRecurso {
    DEFERIDO_TOTAL,   // Recurso totalmente aceito pelo colegiado
    DEFERIDO_PARCIAL, // Recurso parcialmente aceito
    INDEFERIDO        // Recurso negado
}
```

### 4.7 TipoMarcoRecurso

```java
public enum TipoMarcoRecurso {
    // Aceites
    ACEITE_RECURSO_ANALISE,
    FIM_ACEITES_RECURSO_ANALISE,

    // Envio e distribuição
    ENVIO_RECURSO_ANALISE,
    DISTRIBUICAO_ANALISE_RECURSO,
    CANCELA_DISTRIBUICAO_ANALISE_RECURSO,

    // Colegiado
    ANALISE_RECURSO_COLEGIADO,
    FIM_ANALISE_RECURSO_COLEGIADO,
    ENVIO_PARA_COLEGIADO,

    // Resposta
    RESPOSTA_RECURSO,               // 1ª instância
    RESPOSTA_RECURSO_2,             // 2ª instância

    // Ciência
    CIENCIA_RECURSO,

    // Cancelamento
    CANCELAMENTO_RECURSO_CIA,
    CANCELAMENTO_RECURSO_CIV,
    CANCELAMENTO_RECURSO,
    RECURSO_CANCELADO,
    RECURSO_RECUSADO,
    RECURSO_EDITADO
}
```

### 4.8 TipoMarco (para marcos de licenciamento relacionados a ciência)

```java
// Marcos de licenciamento gerados no P05
CIENCIA_CIA_ATEC,           // Cidadão confirma ciência de CIA de análise técnica
CIENCIA_CA_ATEC,            // Cidadão confirma ciência de CA de análise técnica
CIENCIA_AUTO_CIA_ATEC,      // Sistema registra ciência automática de CIA
CIENCIA_CIA_INVIABILIDADE,  // Cidadão confirma ciência de CIA de inviabilidade
CIENCIA_CA_INVIABILIDADE,   // Cidadão confirma ciência de CA de inviabilidade
CIENCIA_CIV,                // Cidadão confirma ciência de CIV
CIENCIA_CIV_RENOVACAO,      // Cidadão confirma ciência de CIV (renovação)
CIENCIA_AUTO_CIV,           // Sistema registra ciência automática de CIV
CIENCIA_APPCI,              // Cidadão confirma ciência de APPCI
```

---

## 5. Regras de negócio — Ciência do CIA/CIV

### 5.1 Arquitetura do serviço de ciência

Adota-se o padrão **Strategy** para polimorfismo entre os tipos de ciência:

```java
// Interface comum
public interface CienciaService {
    TipoCiencia getTipo();
    void efetuarCienciaCidadao(Long idLicenciamento, Long idUsuario, String nomeUsuario);
    List<PendenteCienciaProjection> listarPendentesCienciaAutomatica(Instant dataLimite);
    void efetuarCienciaAutomatica(Long idLicenciamento);
    boolean isAprovado(Long idLicenciamento);  // define se vai para CA ou NCA/CIV
}

// Seletor por tipo (substitui CDI qualifier)
@Component
public class CienciaServiceResolver {
    private final Map<TipoCiencia, CienciaService> strategies;

    public CienciaServiceResolver(List<CienciaService> services) {
        this.strategies = services.stream()
            .collect(Collectors.toMap(CienciaService::getTipo, Function.identity()));
    }

    public CienciaService resolve(TipoCiencia tipo) {
        return Optional.ofNullable(strategies.get(tipo))
            .orElseThrow(() -> new IllegalArgumentException("Tipo de ciência não suportado: " + tipo));
    }
}
```

### 5.2 Implementação: Ciência de CIA de Análise Técnica (ATEC)

```java
@Service
public class AnaliseTecnicaCienciaService implements CienciaService {

    @Override
    public TipoCiencia getTipo() { return TipoCiencia.ATEC; }

    // RN-P05-C01: Validações antes de registrar ciência
    @Transactional
    public void efetuarCienciaCidadao(Long idLicenciamento, Long idUsuario, String nomeUsuario) {
        // 1. Carregar análise associada ao licenciamento
        AnaliseTecnicaEntity analise = analiseTecnicaRepository
            .findByLicenciamentoIdAndStatusIn(idLicenciamento,
                List.of(StatusAnalise.REPROVADO, StatusAnalise.APROVADO))
            .orElseThrow(() -> new BusinessException("Análise não encontrada para ciência"));

        // 2. RN-P05-C01: Licenciamento deve estar em AGUARDANDO_CIENCIA
        if (!licenciamento.getSituacao().equals(SituacaoLicenciamento.AGUARDANDO_CIENCIA)) {
            throw new BusinessException("Licenciamento não está aguardando ciência");
        }

        // 3. RN-P05-C02: Verificar se ciência já foi registrada
        if (Boolean.TRUE.equals(analise.getCiencia())) {
            throw new BusinessException("Ciência já foi registrada para esta análise");
        }

        // 4. Registrar ciência na entidade
        analise.setCiencia(true);
        analise.setDthCiencia(Instant.now());
        analise.setIdUsuarioCiencia(idUsuario);
        analise.setNomeUsuarioCiencia(nomeUsuario);
        analiseTecnicaRepository.save(analise);

        // 5. Determinar próximo estado do licenciamento
        SituacaoLicenciamento proximaSituacao = isAprovado(idLicenciamento)
            ? SituacaoLicenciamento.CA        // Análise aprovada → CA
            : SituacaoLicenciamento.NCA;      // Análise reprovada → NCA (aguarda correção)

        // 6. Transitar estado do licenciamento
        licenciamentoStateService.transitar(idLicenciamento, proximaSituacao);

        // 7. Registrar marco
        TipoMarco tipoMarco = isAprovado(idLicenciamento)
            ? TipoMarco.CIENCIA_CA_ATEC
            : TipoMarco.CIENCIA_CIA_ATEC;

        licenciamentoMarcoService.incluir(tipoMarco, idLicenciamento,
            TipoResponsavelMarco.CIDADAO, idUsuario, nomeUsuario,
            analise.getArquivo());
    }

    // RN-P05-C03: Verificar se análise está aprovada
    @Override
    public boolean isAprovado(Long idLicenciamento) {
        return analiseTecnicaRepository
            .findLatestByLicenciamentoId(idLicenciamento)
            .map(a -> StatusAnalise.APROVADO.equals(a.getStatus()))
            .orElse(false);
    }
}
```

### 5.3 Regras específicas por tipo de ciência

| Tipo | Próximo estado (reprovado) | Próximo estado (aprovado) | TipoMarco cidadão | TipoMarco automático |
|---|---|---|---|---|
| ATEC | `NCA` | `CA` | `CIENCIA_CIA_ATEC` | `CIENCIA_AUTO_CIA_ATEC` |
| INVIABILIDADE | `NCA` | `CA` | `CIENCIA_CIA_INVIABILIDADE` | `CIENCIA_AUTO_CIA_INVIABILIDADE` |
| CIV | `CIV` | `ALVARA_VIGENTE` | `CIENCIA_CIV` | `CIENCIA_AUTO_CIV` |
| CIV (renovação) | `CIV` | `ALVARA_VIGENTE` | `CIENCIA_CIV_RENOVACAO` | `CIENCIA_AUTO_CIV` |
| APPCI | — (sempre aprovado) | `ALVARA_VIGENTE` | `CIENCIA_APPCI` | `CIENCIA_AUTO_APPCI` |

### 5.4 Regras de negócio consolidadas — Ciência

| Código | Regra |
|---|---|
| RN-P05-C01 | Licenciamento deve estar em `AGUARDANDO_CIENCIA` ou `AGUARDANDO_CIENCIA_CIV` para que ciência seja registrada |
| RN-P05-C02 | Se ciência já foi registrada (campo `ciencia == true`), a operação é rejeitada com HTTP 409 |
| RN-P05-C03 | Apenas o RT cadastrado, o RU ou o Proprietário do licenciamento podem registrar ciência manual |
| RN-P05-C04 | A ciência automática só pode ser executada pelo job agendado do sistema, nunca por usuário autenticado |
| RN-P05-C05 | Para APPCI, `isAprovado()` SEMPRE retorna `true` — não há CIA de APPCI; a ciência sempre leva a `ALVARA_VIGENTE` |
| RN-P05-C06 | O TipoMarco registrado deve diferenciar a via (manual pelo cidadão ou automática pelo sistema) |
| RN-P05-C07 | A ciência deve ser registrada na entidade da análise correspondente (AnaliseTecnicaEntity, VistoriaEntity, etc.) E na tabela `sol_licenciamento_marco` |

---

## 6. Regras de negócio — Recurso administrativo

### 6.1 Visão geral do fluxo de recurso

```
NCA ou CIV
  → RT solicita recurso (POST /recursos)
  → Envolvidos confirmam aceites (PUT /recursos/{id})
  → Sistema transita licenciamento → RECURSO_EM_ANALISE_1_CIA (ou CIV)
  → Colegiado analisa
  → Emite resposta (despacho + documento)
  → Cidadão toma ciência da resposta
  → Se indeferido e dentro do prazo → pode recorrer à 2ª instância
```

### 6.2 Regras de validação — Registro do recurso

| Código | Regra |
|---|---|
| RN-P05-R01 | Licenciamento deve estar em `NCA` (1ª instância CIA) ou `CIV` (1ª instância CIV) ou em estado equivalente de 2ª instância para novo recurso |
| RN-P05-R02 | Para 1ª instância: prazo máximo de **30 dias** após a data de ciência do CIA/CIV (`dthCiencia`). Se `Instant.now()` ultrapassa `dthCiencia + 30 dias`, lança `BusinessException("Prazo para recurso de 1ª instância esgotado")` |
| RN-P05-R03 | Para 2ª instância: prazo máximo de **15 dias** após a data de ciência da resposta da 1ª instância |
| RN-P05-R04 | Recurso de 2ª instância só pode ser solicitado se o recurso de 1ª instância foi `INDEFERIDO` (total ou parcialmente). Se `DEFERIDO_TOTAL`, não cabe 2ª instância |
| RN-P05-R05 | Não pode existir recurso ativo (situação diferente de `CANCELADO`) para o mesmo licenciamento e instância |
| RN-P05-R06 | O campo `fundamentacaoLegal` é obrigatório e deve ter no mínimo 50 caracteres |
| RN-P05-R07 | Pelo menos um dos envolvidos (RT, RU ou Proprietário) deve ser incluído no recurso via CPF |
| RN-P05-R08 | O arquivo `idArquivoCiaCiv` deve corresponder a um CIA/CIV válido associado ao licenciamento informado |

### 6.3 Serviço de registro de recurso

```java
@Service
@Transactional
public class RecursoService {

    // RN-P05-R01 a R08
    public RecursoResponseDTO registrar(RecursoRequestDTO dto, Long idUsuario, String nomeUsuario) {

        LicenciamentoEntity licenciamento = licenciamentoRepository.findById(dto.idLicenciamento())
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento não encontrado"));

        // RN-P05-R01: Validar situação do licenciamento
        validarSituacaoParaRecurso(licenciamento, dto.instancia());

        // RN-P05-R02/R03: Validar prazo
        validarPrazo(licenciamento, dto.instancia(), dto.tipoRecurso());

        // RN-P05-R04: 2ª instância só se 1ª foi indeferida
        if (dto.instancia() == 2) {
            validarRecurso1aInstanciaIndeferido(dto.idLicenciamento());
        }

        // RN-P05-R05: Não pode existir recurso ativo
        if (recursoRepository.existsAtivoByLicenciamento(dto.idLicenciamento(), dto.instancia())) {
            throw new BusinessException("Já existe recurso ativo para este licenciamento e instância");
        }

        // Criar RecursoEntity
        RecursoEntity recurso = new RecursoEntity();
        recurso.setLicenciamento(licenciamento);
        recurso.setSituacao(SituacaoRecurso.AGUARDANDO_APROVACAO_ENVOLVIDOS);
        recurso.setTipoRecurso(dto.tipoRecurso());
        recurso.setTipoSolicitacao(dto.tipoSolicitacao());
        recurso.setInstancia(dto.instancia());
        recurso.setFundamentacaoLegal(dto.fundamentacaoLegal());
        recurso.setArquivoCiaCiv(arquivoRepository.findById(dto.idArquivoCiaCiv())
            .orElseThrow(() -> new ResourceNotFoundException("Arquivo CIA/CIV não encontrado")));
        recurso.setIdUsuarioCriacao(idUsuario);
        recurso.setNomeUsuarioCriacao(nomeUsuario);

        // Criar aceites para os envolvidos
        criarAceites(recurso, dto.cpfsEnvolvidos(), licenciamento);

        recursoRepository.save(recurso);

        // Notificar envolvidos para confirmar aceite
        notificacaoService.notificarEnvolvidosParaAceiteRecurso(recurso);

        return recursoMapper.toResponseDTO(recurso);
    }

    private void validarPrazo(LicenciamentoEntity lic, int instancia, TipoRecurso tipo) {
        int prazoDias = instancia == 1
            ? RecursoConstants.PRAZO_1_INSTANCIA    // 30
            : RecursoConstants.PRAZO_2_INSTANCIA;   // 15

        Instant dataCiencia = obterDataCiencia(lic, instancia, tipo);

        if (Instant.now().isAfter(dataCiencia.plus(prazoDias, ChronoUnit.DAYS))) {
            throw new BusinessException(
                "Prazo para recurso de " + instancia + "ª instância esgotado. " +
                "Data limite: " + dataCiencia.plus(prazoDias, ChronoUnit.DAYS));
        }
    }
}
```

### 6.4 Regras de negócio — Aceites dos envolvidos

| Código | Regra |
|---|---|
| RN-P05-A01 | Apenas os envolvidos listados no recurso (por CPF) podem confirmar aceite |
| RN-P05-A02 | Cada envolvido confirma seu aceite individualmente via `PUT /recursos/{id}` com `{ "aceite": true }` |
| RN-P05-A03 | Um aceite confirmado não pode ser desfeito |
| RN-P05-A04 | Quando **todos** os aceites estiverem confirmados: (a) `recurso.situacao = AGUARDANDO_DISTRIBUICAO`; (b) `recurso.dthEnvioAnalise = Instant.now()`; (c) registra marcos `FIM_ACEITES_RECURSO_ANALISE` e `ENVIO_RECURSO_ANALISE`; (d) transita `LicenciamentoEntity.situacao` conforme tipo/instância |
| RN-P05-A05 | Se qualquer envolvido recusar (`false`): `recurso.situacao = CANCELADO`, marco `RECURSO_RECUSADO` |

### 6.5 Serviço de aceite

```java
@Transactional
public RecursoResponseDTO efetuarAceite(Long idRecurso, boolean aceiteConfirmado,
                                         Long idUsuario, String cpfUsuario) {

    RecursoEntity recurso = recursoRepository.findById(idRecurso)
        .orElseThrow(() -> new ResourceNotFoundException("Recurso não encontrado"));

    // RN-P05-A01: Verificar se usuário é envolvido do recurso
    AceiteRecursoEntity aceiteEntity = recurso.getAceites().stream()
        .filter(a -> a.getCpfEnvolvido().equals(cpfUsuario) && a.getAceite() == null)
        .findFirst()
        .orElseThrow(() -> new BusinessException("Usuário não é envolvido pendente neste recurso"));

    if (!aceiteConfirmado) {
        // RN-P05-A05: Recusa — cancela o recurso
        aceiteEntity.setAceite(false);
        aceiteEntity.setDthAceite(Instant.now());
        recurso.setSituacao(SituacaoRecurso.CANCELADO);
        recursoMarcoService.incluir(TipoMarcoRecurso.RECURSO_RECUSADO, recurso,
            TipoResponsavelMarco.CIDADAO, idUsuario);
        return recursoMapper.toResponseDTO(recursoRepository.save(recurso));
    }

    // Confirmar aceite individual
    aceiteEntity.setAceite(true);
    aceiteEntity.setDthAceite(Instant.now());
    aceiteEntity.setIdUsuarioAceite(idUsuario);

    recursoMarcoService.incluir(TipoMarcoRecurso.ACEITE_RECURSO_ANALISE, recurso,
        TipoResponsavelMarco.CIDADAO, idUsuario);

    // RN-P05-A04: Verificar se todos aceitaram
    boolean todosAceitaram = recurso.getAceites().stream()
        .allMatch(a -> Boolean.TRUE.equals(a.getAceite()));

    if (todosAceitaram) {
        recurso.setSituacao(SituacaoRecurso.AGUARDANDO_DISTRIBUICAO);
        recurso.setDthEnvioAnalise(Instant.now());

        recursoMarcoService.incluir(TipoMarcoRecurso.FIM_ACEITES_RECURSO_ANALISE, recurso,
            TipoResponsavelMarco.SISTEMA, null);
        recursoMarcoService.incluir(TipoMarcoRecurso.ENVIO_RECURSO_ANALISE, recurso,
            TipoResponsavelMarco.SISTEMA, null);

        // Transitar situação do licenciamento
        SituacaoLicenciamento novaSituacao = calcularNovaSituacaoLicenciamento(recurso);
        licenciamentoStateService.transitar(
            recurso.getLicenciamento().getId(), novaSituacao);

        notificacaoService.notificarRecursoEnviadoParaAnalise(recurso);
    }

    return recursoMapper.toResponseDTO(recursoRepository.save(recurso));
}

private SituacaoLicenciamento calcularNovaSituacaoLicenciamento(RecursoEntity recurso) {
    boolean ehAnalise = TipoRecurso.CORRECAO_DE_ANALISE.equals(recurso.getTipoRecurso());
    boolean eh1aInstancia = recurso.getInstancia() == 1;

    if (ehAnalise && eh1aInstancia)  return SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIA;
    if (ehAnalise && !eh1aInstancia) return SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIA;
    if (!ehAnalise && eh1aInstancia) return SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIV;
    return SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIV;
}
```

### 6.6 Cancelamento do recurso

| Código | Regra |
|---|---|
| RN-P05-RC01 | Recurso pode ser cancelado pelo RT enquanto em `AGUARDANDO_APROVACAO_ENVOLVIDOS` ou `AGUARDANDO_DISTRIBUICAO` |
| RN-P05-RC02 | Após distribuição para analista (`EM_ANALISE`), o cancelamento requer perfil de coordenador/administrador |
| RN-P05-RC03 | Ao cancelar: `situacao = CANCELADO`, marco `CANCELAMENTO_RECURSO_CIA` ou `CANCELAMENTO_RECURSO_CIV`, notificar envolvidos |
| RN-P05-RC04 | O licenciamento retorna à situação anterior ao recurso (`NCA` ou `CIV`) |

---

## 7. Regras de negócio — Análise do recurso pelo colegiado

### 7.1 Distribuição para analista

| Código | Regra |
|---|---|
| RN-P05-G01 | Apenas coordenador ou administrador pode distribuir um recurso para análise |
| RN-P05-G02 | O recurso deve estar em `AGUARDANDO_DISTRIBUICAO` para ser distribuído |
| RN-P05-G03 | Ao distribuir: cria `AnaliseRecursoEntity` com `situacao = EM_ANALISE`, registra marco `DISTRIBUICAO_ANALISE_RECURSO`, transita `RecursoEntity.situacao = EM_ANALISE` |

### 7.2 Análise pelo colegiado

| Código | Regra |
|---|---|
| RN-P05-G04 | Analista pode submeter ao colegiado: `situacao = AGUARDANDO_AVALIACAO_COLEGIADO`, marco `ENVIO_PARA_COLEGIADO` |
| RN-P05-G05 | Colegiado pode devolver ao analista ou aprovar e registrar marcos `ANALISE_RECURSO_COLEGIADO` e `FIM_ANALISE_RECURSO_COLEGIADO` |
| RN-P05-G06 | A resposta do recurso deve conter: `statusResultado` (DEFERIDO_TOTAL / DEFERIDO_PARCIAL / INDEFERIDO) e `despacho` (texto obrigatório, mínimo 100 caracteres) |
| RN-P05-G07 | Se incluído documento de resposta: gerar PDF autenticado, armazenar no MinIO, criar `ArquivoEntity` com `storageKey` |
| RN-P05-G08 | Ao concluir análise: `analise.situacao = ANALISE_CONCLUIDA`, `recurso.situacao = ANALISE_CONCLUIDA`, marco `RESPOSTA_RECURSO` (1ª) ou `RESPOSTA_RECURSO_2` (2ª) |
| RN-P05-G09 | Notificar RT/RU/Proprietário sobre a resposta disponível |

### 7.3 Serviço de conclusão da análise do recurso

```java
@Service
@Transactional
public class AnaliseRecursoService {

    public AnaliseRecursoResponseDTO concluirAnalise(Long idAnalise,
                                                      AnaliseRecursoRequestDTO dto,
                                                      Long idUsuario) {

        AnaliseRecursoEntity analise = analiseRecursoRepository.findById(idAnalise)
            .orElseThrow(() -> new ResourceNotFoundException("Análise de recurso não encontrada"));

        // RN-P05-G06: Validar campos obrigatórios
        if (dto.statusResultado() == null) {
            throw new BusinessException("Status do resultado é obrigatório");
        }
        if (dto.despacho() == null || dto.despacho().length() < 100) {
            throw new BusinessException("Despacho deve ter no mínimo 100 caracteres");
        }

        analise.setStatusResultado(dto.statusResultado());
        analise.setDespacho(dto.despacho());
        analise.setSituacao(SituacaoAnaliseRecurso.ANALISE_CONCLUIDA);
        analise.setIdUsuarioAnalista(idUsuario);

        // RN-P05-G07: Upload documento de resposta se fornecido
        if (dto.arquivoResposta() != null) {
            ArquivoEntity arquivo = documentoService.armazenarDocumentoResposta(
                dto.arquivoResposta(),
                analise.getRecurso().getLicenciamento().getId());
            analise.setArquivoResposta(arquivo);
        }

        // RN-P05-G08: Concluir recurso
        RecursoEntity recurso = analise.getRecurso();
        recurso.setSituacao(SituacaoRecurso.ANALISE_CONCLUIDA);

        TipoMarcoRecurso tipoMarcoResposta = recurso.getInstancia() == 1
            ? TipoMarcoRecurso.RESPOSTA_RECURSO
            : TipoMarcoRecurso.RESPOSTA_RECURSO_2;

        recursoMarcoService.incluir(tipoMarcoResposta, recurso,
            TipoResponsavelMarco.ANALISTA, idUsuario, analise.getArquivoResposta());

        analiseRecursoRepository.save(analise);
        recursoRepository.save(recurso);

        // RN-P05-G09: Notificar envolvidos
        notificacaoService.notificarRespostaRecurso(recurso);

        return analiseRecursoMapper.toResponseDTO(analise);
    }
}
```

### 7.4 Ciência da resposta do recurso

| Código | Regra |
|---|---|
| RN-P05-CR01 | Após a emissão da resposta, o RT deve tomar ciência (`PUT /recursos/{id}/ciencia`) |
| RN-P05-CR02 | Se não houver ciência dentro do prazo configurado, o job automático registra ciência |
| RN-P05-CR03 | Ao registrar ciência: `analise.ciencia = true`, `analise.dthCiencia = Instant.now()`, marco `CIENCIA_RECURSO` |
| RN-P05-CR04 | Após ciência, avaliar se cabe recurso de 2ª instância: `DEFERIDO_TOTAL` → não cabe; `INDEFERIDO` ou `DEFERIDO_PARCIAL` → cabe se dentro do prazo de 15 dias |

---

## 8. Job de ciência automática

### 8.1 Especificação do job

O sistema deve executar um **job agendado diário** que verifica licenciamentos cujo prazo de ciência expirou e registra a ciência automaticamente em nome do sistema.

```java
@Component
public class CienciaAutomaticaJob {

    private final CienciaServiceResolver resolver;
    private final CienciaAutomaticaConfigProperties config;

    // Executa diariamente às 02:00
    @Scheduled(cron = "0 0 2 * * *", zone = "America/Sao_Paulo")
    @Transactional
    public void executar() {
        log.info("Iniciando job de ciência automática");

        Instant dataLimite = Instant.now();

        for (TipoCiencia tipo : TipoCiencia.values()) {
            CienciaService service = resolver.resolve(tipo);
            List<PendenteCienciaProjection> pendentes =
                service.listarPendentesCienciaAutomatica(dataLimite);

            for (PendenteCienciaProjection pendente : pendentes) {
                try {
                    service.efetuarCienciaAutomatica(pendente.idLicenciamento());
                    log.info("Ciência automática registrada: tipo={}, licenciamento={}",
                        tipo, pendente.idLicenciamento());
                } catch (Exception e) {
                    log.error("Erro ao registrar ciência automática: tipo={}, lic={}, erro={}",
                        tipo, pendente.idLicenciamento(), e.getMessage());
                }
            }
        }

        log.info("Job de ciência automática finalizado");
    }
}
```

### 8.2 Configuração do prazo de ciência automática

```yaml
# application.yml
sol:
  ciencia:
    prazo-automatico-dias: 30   # Dias após situacao=AGUARDANDO_CIENCIA para ciência automática
    prazo-recurso-1-instancia: 30
    prazo-recurso-2-instancia: 15
  jobs:
    ciencia-automatica:
      cron: "0 0 2 * * *"
      enabled: true
```

### 8.3 Regras do job de ciência automática

| Código | Regra |
|---|---|
| RN-P05-J01 | O job busca licenciamentos em `AGUARDANDO_CIENCIA` ou `AGUARDANDO_CIENCIA_CIV` cuja data de entrada na situação ultrapassou o prazo configurado (`sol.ciencia.prazo-automatico-dias`) |
| RN-P05-J02 | A ciência automática registra `ciencia = true`, `dthCiencia = now()`, `nomeUsuarioCiencia = "SISTEMA"` |
| RN-P05-J03 | O TipoMarco registrado deve ser o correspondente ao tipo automático (ex: `CIENCIA_AUTO_CIA_ATEC`) com `tipoResponsavel = SISTEMA` |
| RN-P05-J04 | Erros em um licenciamento específico não devem interromper o processamento dos demais (try-catch por item, log de erro) |
| RN-P05-J05 | O job deve ser idempotente: se executado duas vezes no mesmo dia, não deve duplicar ciências |
| RN-P05-J06 | O job de ciência de resposta de recurso (`RecursoCienciaAutomaticaJob`) opera separadamente: busca `AnaliseRecursoEntity` com `situacao = ANALISE_CONCLUIDA` e `ciencia = null`, cujo prazo de ciência expirou |

---

## 9. API REST — endpoints completos

### 9.1 Ciência de CIA/CIV

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/v1/ciencia/{idLicenciamento}` | Consultar situação de ciência do licenciamento | RT, RU, Proprietário |
| `POST` | `/api/v1/ciencia/{idLicenciamento}/confirmar` | Registrar ciência manual do cidadão | RT, RU, Proprietário |
| `GET` | `/api/v1/ciencia/{idLicenciamento}/documento` | Download do CIA/CIV para leitura | RT, RU, Proprietário |

**POST /api/v1/ciencia/{idLicenciamento}/confirmar — Request:**
```json
{
  "tipoCiencia": "ATEC"
}
```

**POST /api/v1/ciencia/{idLicenciamento}/confirmar — Response (200):**
```json
{
  "idLicenciamento": 12345,
  "tipoCiencia": "ATEC",
  "cienciaRegistrada": true,
  "dthCiencia": "2026-03-10T14:30:00Z",
  "proximaSituacaoLicenciamento": "NCA",
  "mensagem": "Ciência registrada com sucesso. O licenciamento está disponível para correção."
}
```

### 9.2 Recursos

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `POST` | `/api/v1/recursos` | Registrar novo recurso (1ª ou 2ª instância) | RT |
| `GET` | `/api/v1/recursos/{id}` | Consultar recurso por ID | RT, RU, Proprietário, Coordenador |
| `GET` | `/api/v1/recursos` | Listar recursos (com filtros) | RT, Coordenador |
| `PUT` | `/api/v1/recursos/{id}/aceite` | Confirmar ou recusar aceite do envolvido | RT, RU, Proprietário |
| `PUT` | `/api/v1/recursos/{id}/salvar` | Salvar rascunho sem aceite | RT |
| `DELETE` | `/api/v1/recursos/{id}` | Cancelar recurso | RT, Coordenador |
| `GET` | `/api/v1/recursos/{id}/historico` | Listar marcos do recurso | RT, Coordenador |
| `PUT` | `/api/v1/recursos/{id}/habilitar-edicao` | Reabrir para edição (admin) | Administrador |
| `POST` | `/api/v1/recursos/{id}/ciencia-resposta` | Registrar ciência da resposta do recurso | RT |

**POST /api/v1/recursos — Request:**
```json
{
  "idLicenciamento": 12345,
  "idArquivoCiaCiv": 67890,
  "instancia": 1,
  "tipoRecurso": "CORRECAO_DE_ANALISE",
  "tipoSolicitacao": "INTEGRAL",
  "fundamentacaoLegal": "O laudo técnico apresentado pelo RT está em conformidade com a NBR 17240...",
  "cpfsEnvolvidos": [
    { "cpf": "123.456.789-00", "tipoEnvolvido": "RT" },
    { "cpf": "987.654.321-00", "tipoEnvolvido": "PROPRIETARIO" }
  ]
}
```

**POST /api/v1/recursos — Response (201):**
```json
{
  "id": 555,
  "idLicenciamento": 12345,
  "situacao": "AGUARDANDO_APROVACAO_ENVOLVIDOS",
  "tipoRecurso": "CORRECAO_DE_ANALISE",
  "instancia": 1,
  "dthCriacao": "2026-03-10T14:30:00Z",
  "aceitesPendentes": [
    { "cpf": "123.456.789-00", "tipoEnvolvido": "RT", "aceite": null },
    { "cpf": "987.654.321-00", "tipoEnvolvido": "PROPRIETARIO", "aceite": null }
  ]
}
```

**PUT /api/v1/recursos/{id}/aceite — Request:**
```json
{
  "aceite": true
}
```

### 9.3 Análise do recurso (colegiado / coordenador)

| Método | Endpoint | Descrição | Perfil |
|---|---|---|---|
| `GET` | `/api/v1/adm/recursos/pendentes` | Listar recursos aguardando distribuição | Coordenador |
| `POST` | `/api/v1/adm/recursos/{id}/distribuir` | Distribuir recurso para analista | Coordenador |
| `GET` | `/api/v1/adm/analise-recurso/{id}` | Consultar análise de recurso | Analista, Coordenador |
| `PUT` | `/api/v1/adm/analise-recurso/{id}` | Salvar andamento da análise | Analista |
| `POST` | `/api/v1/adm/analise-recurso/{id}/submeter-colegiado` | Submeter ao colegiado | Analista |
| `POST` | `/api/v1/adm/analise-recurso/{id}/concluir` | Concluir e emitir resposta | Analista, Coordenador |
| `DELETE` | `/api/v1/adm/recursos/{id}/cancelar-distribuicao` | Cancelar distribuição | Coordenador |

**POST /api/v1/adm/analise-recurso/{id}/concluir — Request:**
```json
{
  "statusResultado": "INDEFERIDO",
  "despacho": "Após análise técnica detalhada pelo colegiado do CBM-RS, verificou-se que os itens apontados na CIA estão em conformidade com o Decreto Estadual nº 53.280/2016...",
  "arquivoResposta": "base64encodedPDF..."
}
```

### 9.4 Parâmetros de filtro (GET /api/v1/recursos)

```
situacao: SituacaoRecurso (opcional)
tipoRecurso: TipoRecurso (opcional)
instancia: Integer (1 ou 2, opcional)
idLicenciamento: Long (opcional)
dataInicio: LocalDate (opcional)
dataFim: LocalDate (opcional)
pagina: Integer (default 0)
tamanho: Integer (default 20)
ordenacao: String (default "dthCriacao,desc")
```

---

## 10. Segurança e controle de acesso

### 10.1 Configuração Spring Security com Keycloak

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/ciencia/**").hasAnyRole("CIDADAO", "RT", "RU", "PROPRIETARIO")
                .requestMatchers("/api/v1/recursos/**").hasAnyRole("CIDADAO", "RT", "RU", "PROPRIETARIO")
                .requestMatchers("/api/v1/adm/**").hasAnyRole("ANALISTA_CBM", "COORDENADOR_CBM", "ADMIN")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtGrantedAuthoritiesConverter converter = new JwtGrantedAuthoritiesConverter();
        converter.setAuthorityPrefix("ROLE_");
        converter.setAuthoritiesClaimName("realm_access.roles");
        JwtAuthenticationConverter jwtConverter = new JwtAuthenticationConverter();
        jwtConverter.setJwtGrantedAuthoritiesConverter(converter);
        return jwtConverter;
    }
}
```

### 10.2 Anotações de autorização por método

```java
// Ciência: apenas envolvidos do licenciamento
@PreAuthorize("@licenciamentoSecurityService.isEnvolvido(#idLicenciamento, authentication)")
public void efetuarCienciaCidadao(Long idLicenciamento, ...) { ... }

// Aceite: apenas envolvido listado no recurso
@PreAuthorize("@recursoSecurityService.isEnvolvidoPendente(#idRecurso, authentication)")
public RecursoResponseDTO efetuarAceite(Long idRecurso, ...) { ... }

// Análise do recurso: apenas analista designado ou coordenador
@PreAuthorize("hasRole('COORDENADOR_CBM') or @recursoSecurityService.isAnalistaDesignado(#idAnalise, authentication)")
public AnaliseRecursoResponseDTO concluirAnalise(Long idAnalise, ...) { ... }

// Cancelamento: RT (rascunho/aguardando) ou coordenador (qualquer estado)
@PreAuthorize("hasRole('COORDENADOR_CBM') or @recursoSecurityService.podeRTCancelar(#idRecurso, authentication)")
public void cancelarRecurso(Long idRecurso) { ... }
```

### 10.3 Extração de dados do usuário autenticado (substitui SessionMB)

```java
@Component
public class UsuarioAutenticadoService {

    public Long getIdUsuario() {
        return Long.parseLong(getAuthentication().getName());  // subject do JWT = ID do usuário
    }

    public String getNomeUsuario() {
        return (String) ((JwtAuthenticationToken) getAuthentication())
            .getTokenAttributes().get("name");
    }

    public String getCpfUsuario() {
        return (String) ((JwtAuthenticationToken) getAuthentication())
            .getTokenAttributes().get("preferred_username"); // ou CPF no claim customizado
    }

    private Authentication getAuthentication() {
        return SecurityContextHolder.getContext().getAuthentication();
    }
}
```

---

## 11. Geração e armazenamento de documentos

### 11.1 Documento de resposta do recurso

```java
@Service
public class DocumentoRecursoService {

    private final MinioClient minioClient;
    private final ArquivoRepository arquivoRepository;

    @Transactional
    public ArquivoEntity armazenarDocumentoResposta(byte[] conteudo, Long idLicenciamento) {

        String nomeArquivo = "resposta_recurso_" + idLicenciamento + "_" +
            Instant.now().toEpochMilli() + ".pdf";

        String codigoAutenticacao = gerarCodigoAutenticacao();

        // Upload para MinIO (substitui Alfresco)
        String storageKey = "licenciamentos/" + idLicenciamento + "/recursos/" + nomeArquivo;
        minioClient.putObject(PutObjectArgs.builder()
            .bucket("sol-documentos")
            .object(storageKey)
            .stream(new ByteArrayInputStream(conteudo), conteudo.length, -1)
            .contentType("application/pdf")
            .build());

        // Persistir referência (substitui identificadorAlfresco)
        ArquivoEntity arquivo = new ArquivoEntity();
        arquivo.setNomeArquivo(nomeArquivo);
        arquivo.setStorageKey(storageKey);       // equivalente a identificadorAlfresco
        arquivo.setTipoArquivo(TipoArquivo.RESPOSTA_RECURSO);
        arquivo.setCodigoAutenticacao(codigoAutenticacao);
        arquivo.setIdLicenciamento(idLicenciamento);
        arquivo.setDthCriacao(Instant.now());

        return arquivoRepository.save(arquivo);
    }

    private String gerarCodigoAutenticacao() {
        return UUID.randomUUID().toString().toUpperCase().replace("-", "").substring(0, 20);
    }
}
```

### 11.2 Download de documento CIA/CIV para leitura pelo cidadão

```java
@GetMapping("/{idLicenciamento}/documento")
public ResponseEntity<Resource> downloadDocumentoCiaCiv(
        @PathVariable Long idLicenciamento) {

    ArquivoEntity arquivo = cienciaService.obterArquivoCiaCiv(idLicenciamento);
    InputStream stream = minioClient.getObject(GetObjectArgs.builder()
        .bucket("sol-documentos")
        .object(arquivo.getStorageKey())
        .build());

    return ResponseEntity.ok()
        .header(HttpHeaders.CONTENT_DISPOSITION,
            "attachment; filename=\"" + arquivo.getNomeArquivo() + "\"")
        .contentType(MediaType.APPLICATION_PDF)
        .body(new InputStreamResource(stream));
}
```

---

## 12. Notificações

### 12.1 Eventos que disparam notificações

| Evento | Destinatários | Canal |
|---|---|---|
| Licenciamento em `AGUARDANDO_CIENCIA` | RT, RU, Proprietário | E-mail |
| Recurso registrado (para aceite) | Todos os envolvidos listados no recurso | E-mail |
| Todos os aceites confirmados | RT (solicitante do recurso) | E-mail |
| Resposta do recurso disponível | RT, RU, Proprietário | E-mail |
| Ciência automática registrada | RT (notificação informativa) | E-mail |

### 12.2 Serviço de notificação

```java
@Service
public class NotificacaoP05Service {

    @Async
    public void notificarAguardandoCiencia(LicenciamentoEntity licenciamento, ArquivoEntity arquivoCia) {
        List<String> destinatarios = obterEmailsEnvolvidos(licenciamento);
        String assunto = "CBM-RS | Licenciamento " + licenciamento.getNumeroPPCI() +
            " — CIA disponível para ciência";
        Map<String, Object> modelo = Map.of(
            "numeroPPCI", licenciamento.getNumeroPPCI(),
            "linkCia", gerarLinkDocumento(arquivoCia),
            "prazo", "30 dias a partir desta data"
        );
        emailService.enviar(destinatarios, assunto, "templates/email/ciencia-cia.html", modelo);
    }

    @Async
    public void notificarEnvolvidosParaAceiteRecurso(RecursoEntity recurso) {
        recurso.getAceites().forEach(aceite -> {
            String assunto = "CBM-RS | Confirme seu aceite no recurso do licenciamento " +
                recurso.getLicenciamento().getNumeroPPCI();
            emailService.enviar(
                List.of(buscarEmail(aceite.getCpfEnvolvido())),
                assunto,
                "templates/email/aceite-recurso.html",
                Map.of("recurso", recurso, "aceite", aceite)
            );
        });
    }
}
```

---

## 13. Transições de estado

### 13.1 Transições de SituacaoLicenciamento no P05

| De | Para | Gatilho | Condição |
|---|---|---|---|
| `AGUARDANDO_CIENCIA` | `NCA` | Ciência de CIA registrada (manual ou auto) | `AnaliseTecnicaEntity.status == REPROVADO` |
| `AGUARDANDO_CIENCIA` | `CA` | Ciência de CA registrada | `AnaliseTecnicaEntity.status == APROVADO` |
| `AGUARDANDO_CIENCIA_CIV` | `CIV` | Ciência de CIV registrada | `VistoriaEntity.status == REPROVADO` |
| `AGUARDANDO_CIENCIA_CIV` | `ALVARA_VIGENTE` | Ciência de CIV aprovada | `VistoriaEntity.status == APROVADO` |
| `NCA` | `RECURSO_EM_ANALISE_1_CIA` | Todos os aceites do recurso confirmados | `instancia == 1 AND tipoRecurso == ANALISE` |
| `CIV` | `RECURSO_EM_ANALISE_1_CIV` | Todos os aceites do recurso confirmados | `instancia == 1 AND tipoRecurso == VISTORIA` |
| `RECURSO_EM_ANALISE_1_CIA` | `RECURSO_EM_ANALISE_2_CIA` | Aceites 2ª instância confirmados | `instancia == 2 AND tipo == ANALISE` |
| `RECURSO_EM_ANALISE_1_CIV` | `RECURSO_EM_ANALISE_2_CIV` | Aceites 2ª instância confirmados | `instancia == 2 AND tipo == VISTORIA` |

### 13.2 Transições de SituacaoRecurso

```
RASCUNHO → AGUARDANDO_APROVACAO_ENVOLVIDOS  [ao registrar]
AGUARDANDO_APROVACAO_ENVOLVIDOS → AGUARDANDO_DISTRIBUICAO  [todos aceitaram]
AGUARDANDO_APROVACAO_ENVOLVIDOS → CANCELADO  [qualquer recusou]
AGUARDANDO_DISTRIBUICAO → EM_ANALISE  [coordenador distribuiu]
EM_ANALISE → ANALISE_CONCLUIDA  [resposta emitida]
* → CANCELADO  [cancelamento administrativo]
```

### 13.3 Implementação do serviço de transição de estado

```java
@Service
@Transactional
public class LicenciamentoStateService {

    public void transitar(Long idLicenciamento, SituacaoLicenciamento novaSituacao) {

        LicenciamentoEntity licenciamento = licenciamentoRepository.findById(idLicenciamento)
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento não encontrado"));

        SituacaoLicenciamento situacaoAtual = licenciamento.getSituacao();

        // Validar transição permitida
        if (!transicaoPermitida(situacaoAtual, novaSituacao)) {
            throw new BusinessException(
                "Transição de estado inválida: " + situacaoAtual + " → " + novaSituacao);
        }

        licenciamento.setSituacao(novaSituacao);
        licenciamento.setDthUltimaAtualizacao(Instant.now());
        licenciamentoRepository.save(licenciamento);

        // Log de auditoria
        licenciamentoAuditService.registrarTransicao(idLicenciamento, situacaoAtual, novaSituacao);
    }

    private boolean transicaoPermitida(SituacaoLicenciamento de, SituacaoLicenciamento para) {
        return TRANSICOES_PERMITIDAS.getOrDefault(de, Set.of()).contains(para);
    }

    private static final Map<SituacaoLicenciamento, Set<SituacaoLicenciamento>> TRANSICOES_PERMITIDAS =
        Map.of(
            AGUARDANDO_CIENCIA, Set.of(NCA, CA),
            AGUARDANDO_CIENCIA_CIV, Set.of(CIV, ALVARA_VIGENTE),
            NCA, Set.of(RECURSO_EM_ANALISE_1_CIA),
            CIV, Set.of(RECURSO_EM_ANALISE_1_CIV),
            RECURSO_EM_ANALISE_1_CIA, Set.of(RECURSO_EM_ANALISE_2_CIA),
            RECURSO_EM_ANALISE_1_CIV, Set.of(RECURSO_EM_ANALISE_2_CIV)
        );
}
```

---

## 14. Marcos (audit trail)

### 14.1 Responsabilidade

Cada operação significativa deve registrar um marco com:
- `TipoMarco` (ou `TipoMarcoRecurso`)
- `TipoResponsavelMarco` (CIDADAO, SISTEMA, ANALISTA)
- Identificação do usuário responsável
- Timestamp
- Referência ao arquivo gerado (quando aplicável)

### 14.2 Serviço unificado de marcos de recurso

```java
@Service
@Transactional
public class RecursoMarcoService {

    public void incluir(TipoMarcoRecurso tipo, RecursoEntity recurso,
                        TipoResponsavelMarco tipoResponsavel, Long idUsuario) {
        incluir(tipo, recurso, tipoResponsavel, idUsuario, null, null);
    }

    public void incluir(TipoMarcoRecurso tipo, RecursoEntity recurso,
                        TipoResponsavelMarco tipoResponsavel, Long idUsuario,
                        String nomeUsuario, ArquivoEntity arquivo) {
        RecursoMarcoEntity marco = new RecursoMarcoEntity();
        marco.setRecurso(recurso);
        marco.setTipoMarco(tipo);
        marco.setDthMarco(Instant.now());
        marco.setTipoResponsavel(tipoResponsavel);
        marco.setIdUsuarioResponsavel(idUsuario);
        marco.setNomeUsuarioResponsavel(
            tipoResponsavel == TipoResponsavelMarco.SISTEMA ? "SISTEMA" : nomeUsuario);
        marco.setArquivo(arquivo);
        marco.setDescricao(tipo.getDescricao());
        recursoMarcoRepository.save(marco);
    }
}
```

---

## 15. Persistência e estrutura de banco

### 15.1 Tabelas principais do P05

| Tabela | Sequência | Descrição |
|---|---|---|
| `sol_recurso` | `sol_recurso_seq` | Recurso (CIA/CIV) |
| `sol_aceite_recurso` | `sol_aceite_recurso_seq` | Aceites individuais por envolvido |
| `sol_analise_recurso` | `sol_analise_recurso_seq` | Análise/resposta do colegiado |
| `sol_recurso_marco` | `sol_recurso_marco_seq` | Histórico de eventos do recurso |
| `sol_ciencia_documento` | `sol_ciencia_doc_seq` | Registro de ciências (manual e automática) |
| `sol_licenciamento_marco` | (existente) | Marcos de licenciamento (ciência registrada) |
| `sol_arquivo` | (existente) | Documentos com referência ao MinIO (`storage_key`) |

### 15.2 Script de migração Flyway (exemplo)

```sql
-- V005__create_p05_tables.sql

CREATE SEQUENCE sol_recurso_seq START 1 INCREMENT 1;
CREATE TABLE sol_recurso (
    id                  BIGINT PRIMARY KEY DEFAULT NEXTVAL('sol_recurso_seq'),
    id_licenciamento    BIGINT NOT NULL REFERENCES sol_licenciamento(id),
    situacao            VARCHAR(50) NOT NULL,
    tipo_recurso        VARCHAR(30) NOT NULL,
    tipo_solicitacao    VARCHAR(20),
    instancia           INTEGER NOT NULL CHECK (instancia IN (1, 2)),
    fundamentacao_legal TEXT,
    dth_envio_analise   TIMESTAMP WITH TIME ZONE,
    id_arquivo_cia_civ  BIGINT REFERENCES sol_arquivo(id),
    id_usuario_criacao  BIGINT NOT NULL,
    nome_usuario_criacao VARCHAR(200) NOT NULL,
    dth_criacao         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    dth_atualizacao     TIMESTAMP WITH TIME ZONE
);

CREATE SEQUENCE sol_aceite_recurso_seq START 1 INCREMENT 1;
CREATE TABLE sol_aceite_recurso (
    id              BIGINT PRIMARY KEY DEFAULT NEXTVAL('sol_aceite_recurso_seq'),
    id_recurso      BIGINT NOT NULL REFERENCES sol_recurso(id),
    tipo_envolvido  VARCHAR(30) NOT NULL,
    cpf_envolvido   VARCHAR(14) NOT NULL,
    nome_envolvido  VARCHAR(200),
    ind_aceite      BOOLEAN,
    dth_aceite      TIMESTAMP WITH TIME ZONE,
    id_usuario_aceite BIGINT,
    UNIQUE (id_recurso, cpf_envolvido)
);

CREATE SEQUENCE sol_analise_recurso_seq START 1 INCREMENT 1;
CREATE TABLE sol_analise_recurso (
    id                    BIGINT PRIMARY KEY DEFAULT NEXTVAL('sol_analise_recurso_seq'),
    id_recurso            BIGINT NOT NULL REFERENCES sol_recurso(id) UNIQUE,
    situacao              VARCHAR(40) NOT NULL,
    status_resultado      VARCHAR(20),
    despacho              TEXT,
    id_arquivo_resposta   BIGINT REFERENCES sol_arquivo(id),
    id_usuario_analista   BIGINT NOT NULL,
    nome_usuario_analista VARCHAR(200),
    ind_ciencia           BOOLEAN,
    dth_ciencia           TIMESTAMP WITH TIME ZONE,
    id_usuario_ciencia    BIGINT,
    nome_usuario_ciencia  VARCHAR(200),
    dth_criacao           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    dth_atualizacao       TIMESTAMP WITH TIME ZONE
);

CREATE SEQUENCE sol_recurso_marco_seq START 1 INCREMENT 1;
CREATE TABLE sol_recurso_marco (
    id                      BIGINT PRIMARY KEY DEFAULT NEXTVAL('sol_recurso_marco_seq'),
    id_recurso              BIGINT NOT NULL REFERENCES sol_recurso(id),
    tipo_marco              VARCHAR(80) NOT NULL,
    dth_marco               TIMESTAMP WITH TIME ZONE NOT NULL,
    descricao               VARCHAR(200),
    tipo_responsavel        VARCHAR(20),
    id_usuario_responsavel  BIGINT,
    nome_usuario_responsavel VARCHAR(200),
    id_arquivo              BIGINT REFERENCES sol_arquivo(id)
);

CREATE INDEX idx_recurso_licenciamento ON sol_recurso(id_licenciamento);
CREATE INDEX idx_recurso_situacao ON sol_recurso(situacao);
CREATE INDEX idx_recurso_marco_recurso ON sol_recurso_marco(id_recurso);
```

### 15.3 Repositories Spring Data JPA

```java
public interface RecursoRepository extends JpaRepository<RecursoEntity, Long> {

    boolean existsByLicenciamentoIdAndInstanciaAndSituacaoNot(
        Long idLicenciamento, Integer instancia, SituacaoRecurso situacao);

    List<RecursoEntity> findByLicenciamentoIdAndInstanciaAndSituacao(
        Long idLicenciamento, Integer instancia, SituacaoRecurso situacao);

    Page<RecursoEntity> findBySituacaoAndLicenciamento_Situacao(
        SituacaoRecurso situacaoRecurso,
        SituacaoLicenciamento situacaoLic,
        Pageable pageable);
}

public interface AnaliseRecursoRepository extends JpaRepository<AnaliseRecursoEntity, Long> {

    // Para job de ciência automática de resposta de recurso
    @Query("""
        SELECT ar FROM AnaliseRecursoEntity ar
        WHERE ar.situacao = :situacao
          AND ar.ciencia IS NULL
          AND ar.dthAtualizacao < :dataLimite
        """)
    List<AnaliseRecursoEntity> findPendentesCienciaAutomatica(
        @Param("situacao") SituacaoAnaliseRecurso situacao,
        @Param("dataLimite") Instant dataLimite);
}
```

---

## 16. Estrutura de pacotes recomendada

```
br.gov.cbmrs.sol
├── ciencia
│   ├── api
│   │   └── CienciaController.java
│   ├── application
│   │   ├── CienciaApplicationService.java
│   │   └── CienciaAutomaticaJob.java
│   ├── domain
│   │   ├── Ciencia.java                          (interface)
│   │   ├── LicenciamentoCiencia.java             (interface)
│   │   ├── TipoCiencia.java                      (enum)
│   │   ├── CienciaService.java                   (interface Strategy)
│   │   ├── CienciaServiceResolver.java
│   │   ├── impl
│   │   │   ├── AnaliseTecnicaCienciaService.java
│   │   │   ├── AnaliseInviabilidadeCienciaService.java
│   │   │   ├── VistoriaCienciaService.java
│   │   │   └── AppciCienciaService.java
│   │   └── CienciaDocumentoEntity.java
│   └── infrastructure
│       └── CienciaDocumentoRepository.java
│
├── recurso
│   ├── api
│   │   ├── RecursoController.java
│   │   └── AnaliseRecursoAdmController.java
│   ├── application
│   │   ├── RecursoService.java
│   │   ├── AnaliseRecursoService.java
│   │   ├── RecursoMarcoService.java
│   │   └── RecursoCienciaAutomaticaJob.java
│   ├── domain
│   │   ├── RecursoEntity.java
│   │   ├── AceiteRecursoEntity.java
│   │   ├── AnaliseRecursoEntity.java
│   │   ├── RecursoMarcoEntity.java
│   │   ├── SituacaoRecurso.java
│   │   ├── SituacaoAnaliseRecurso.java
│   │   ├── TipoRecurso.java
│   │   ├── TipoSolicitacaoRecurso.java
│   │   ├── StatusResultadoRecurso.java
│   │   └── TipoMarcoRecurso.java
│   ├── dto
│   │   ├── RecursoRequestDTO.java
│   │   ├── RecursoResponseDTO.java
│   │   ├── AnaliseRecursoRequestDTO.java
│   │   └── AnaliseRecursoResponseDTO.java
│   └── infrastructure
│       ├── RecursoRepository.java
│       ├── AceiteRecursoRepository.java
│       ├── AnaliseRecursoRepository.java
│       └── RecursoMarcoRepository.java
│
├── notificacao
│   └── NotificacaoP05Service.java
│
└── documento
    ├── DocumentoRecursoService.java
    └── MinioStorageService.java
```

---



---

## 17. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 02 (Demandas 5, 10, 31) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (itens 6.3.7.1, 12.1).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P05.

---

### RN-P05-N1 — Lembretes Automáticos de Ciência do CIA/CIV (D+7, D+20, D+27) 🔴 P05-M1

**Prioridade:** CRÍTICA  
**Origem:** Norma / Correção 1 — RT de Implantação SOL-CBMRS item 6.3.7.1

**Descrição:** O prazo de 30 dias para ciência automática do CIA/CIV está corretamente modelado. Porém, o sistema deve enviar **lembretes proativos** ao RT, RU e Proprietário nos dias D+7, D+20 e D+27 após a emissão do CIA/CIV, alertando sobre o prazo restante.

**Novos jobs agendados — `CienciaLembreteScheduler`:**

```java
@Component
public class CienciaLembreteScheduler {

    // Executa diariamente às 08h
    @Scheduled(cron = "0 0 8 * * *")
    public void enviarLembretes() {
        LocalDate hoje = LocalDate.now();
        
        // D+7: Lembrete inicial
        List<Licenciamento> d7 = licenciamentoRepo.findComCiaPendenteNoDia(hoje.minusDays(7));
        d7.forEach(l -> notificacaoService.enviarLembreCiencia(l, 23)); // 23 dias restantes
        
        // D+20: Lembrete de atenção
        List<Licenciamento> d20 = licenciamentoRepo.findComCiaPendenteNoDia(hoje.minusDays(20));
        d20.forEach(l -> notificacaoService.enviarLembreCiencia(l, 10)); // 10 dias restantes
        
        // D+27: Último lembrete — urgente
        List<Licenciamento> d27 = licenciamentoRepo.findComCiaPendenteNoDia(hoje.minusDays(27));
        d27.forEach(l -> notificacaoService.enviarLembreUrgenteCiencia(l, 3)); // 3 dias restantes
    }
}
```

**Query para licenciamentos com CIA pendente:**
```sql
SELECT l.* FROM cbm_licenciamento l
JOIN cbm_cia c ON c.id_licenciamento = l.id
WHERE l.tp_status IN ('AGUARDANDO_CIENCIA_CIA','AGUARDANDO_CIENCIA_CIV')
  AND DATE(c.dt_emissao) = :dataEmissao
  AND c.fg_ciencia_dada = FALSE;
```

**Templates de e-mail:**
- **D+7:** "Lembrete: você tem 23 dias para dar ciência do CIA/CIV N.º {nr} do processo {protocolo}."
- **D+20:** "Atenção: restam 10 dias para dar ciência do CIA/CIV N.º {nr}. Após o prazo, a ciência será registrada automaticamente."
- **D+27:** "⚠️ URGENTE: restam apenas 3 dias para dar ciência do CIA/CIV. Acesse o sistema agora."

**Critérios de Aceitação:**
- [ ] CA-P05-N1a: Job envia lembrete D+7 para todos os CIA/CIV com ciência pendente emitidos há 7 dias
- [ ] CA-P05-N1b: Job envia lembrete D+20 para CIA/CIV emitidos há 20 dias
- [ ] CA-P05-N1c: Job envia lembrete urgente D+27 para CIA/CIV emitidos há 27 dias
- [ ] CA-P05-N1d: Lembretes são enviados para RT, RU e Proprietário do licenciamento
- [ ] CA-P05-N1e: CIA/CIV com ciência já dada não recebe lembretes

---

### RN-P05-N2 — Prazo do Recurso Calculado em Dias ÚTEIS (Tabela de Feriados) 🔴 P05-M2

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma / Correção 2 — RT de Implantação SOL-CBMRS item 12.1

**Descrição:** O prazo para interposição de recurso deve ser calculado em **dias úteis**, não corridos:
- **1ª instância:** 30 dias úteis (≈ 6 semanas de calendário)
- **2ª instância:** 15 dias úteis (≈ 3 semanas de calendário)

**Nova tabela de feriados:**
```sql
CREATE TABLE sol.feriado (
    id BIGSERIAL PRIMARY KEY,
    dt_feriado DATE NOT NULL UNIQUE,
    ds_descricao VARCHAR(100) NOT NULL,
    tp_ambito VARCHAR(20) NOT NULL
        CHECK (tp_ambito IN ('FEDERAL','ESTADUAL_RS','MUNICIPAL_POA'))
);

-- Índice para consultas de intervalo de datas
CREATE INDEX idx_feriado_dt ON sol.feriado(dt_feriado);
```

**Função utilitária de cálculo:**
```java
@Service
public class CalendarioUtilService {

    public LocalDate calcularDataLimiteUtil(LocalDate dataInicio, int nrDiasUteis) {
        LocalDate data = dataInicio;
        int diasContados = 0;
        while (diasContados < nrDiasUteis) {
            data = data.plusDays(1);
            if (isDiaUtil(data)) {
                diasContados++;
            }
        }
        return data;
    }

    public boolean isDiaUtil(LocalDate data) {
        DayOfWeek diaSemana = data.getDayOfWeek();
        if (diaSemana == DayOfWeek.SATURDAY || diaSemana == DayOfWeek.SUNDAY) {
            return false;
        }
        return !feriadoRepository.existsByDtFeriado(data);
    }
    
    public long calcularDiasUteisRestantes(LocalDate dataInicio, LocalDate dataFim) {
        return dataInicio.datesUntil(dataFim)
            .filter(this::isDiaUtil)
            .count();
    }
}
```

**Integração com `RecursoRN`:**
```java
// ANTES — errado:
LocalDate dtLimite = dtCiencia.plusDays(30);

// DEPOIS — correto:
LocalDate dtLimite = calendarioUtilService.calcularDataLimiteUtil(dtCiencia, 30);
```

**Impacto compartilhado com P10:** Esta implementação é compartilhada — deve ser desenvolvida uma única vez no módulo `calendario` e reutilizada em P05 e P10.

**Critérios de Aceitação:**
- [ ] CA-P05-N2a: Prazo de recurso de 1ª instância calculado com 30 dias **úteis** a partir da ciência
- [ ] CA-P05-N2b: Prazo de recurso de 2ª instância calculado com 15 dias **úteis**
- [ ] CA-P05-N2c: Sábados, domingos e feriados federais/estaduais do RS são excluídos do cálculo
- [ ] CA-P05-N2d: Tabela `sol.feriado` existe e está populada com feriados federais e estaduais do RS
- [ ] CA-P05-N2e: Tela do recurso exibe a data limite calculada em dias úteis

---

### RN-P05-N3 — Modal de Alerta ao Tentar Editar Recurso na 2ª Instância 🟠 P05-M3

**Prioridade:** Alta  
**Origem:** Demanda 10 — Sprint 02 Hammer

**Descrição:** Quando o usuário tenta editar o recurso enquanto ele está em fase de **julgamento pela 2ª instância**, o sistema deve exibir modal de alerta informando que alterações podem não ser apreciadas.

**Texto do modal:**
> *"Atenção: seu recurso está em fase de julgamento de 2ª instância. Alterações realizadas agora podem não ser apreciadas pelo julgador. Deseja continuar a edição mesmo assim?"*

Botões: **"Continuar editando"** / **"Cancelar"**

**Implementação Angular:**
```typescript
// recurso-detalhe.component.ts
onEditarRecurso(): void {
    if (this.recurso.status === StatusRecurso.EM_ANALISE_2A_INSTANCIA) {
        this.dialog.open(AlertaEdicao2aInstanciaComponent)
            .afterClosed()
            .pipe(filter(confirmado => confirmado))
            .subscribe(() => this.habilitarEdicao());
        return;
    }
    this.habilitarEdicao();
}
```

**Critérios de Aceitação:**
- [ ] CA-P05-N3a: Tentativa de edição em `EM_ANALISE_2A_INSTANCIA` exibe modal de alerta
- [ ] CA-P05-N3b: "Continuar editando" permite a edição (usuário ciente do risco)
- [ ] CA-P05-N3c: "Cancelar" fecha o modal sem habilitar edição
- [ ] CA-P05-N3d: Em outros estados, edição não exibe modal

---

### RN-P05-N4 — Bloquear Novo Recurso Quando Já Existe um em Aberto 🟠 P05-M4

**Prioridade:** Alta  
**Origem:** Demanda 31 — Sprint 04 Hammer

**Descrição:** Se o usuário tentar abrir um novo recurso quando **já existe um em andamento** para o mesmo licenciamento, o sistema deve exibir alerta com a situação do recurso existente e bloquear a abertura de novo.

**Verificação no backend:**
```java
// RecursoService.java
public void validarAberturadeRecurso(UUID idLicenciamento) {
    Optional<Recurso> recursoAberto = recursoRepository
        .findByIdLicenciamentoAndStatusNotIn(
            idLicenciamento,
            List.of(StatusRecurso.CONCLUIDO, StatusRecurso.ARQUIVADO)
        );
    if (recursoAberto.isPresent()) {
        throw new BusinessException(
            String.format("Já existe um recurso em andamento para este licenciamento. " +
                "Situação atual: %s. Protocolo: %s",
                recursoAberto.get().getStatus().getDescricao(),
                recursoAberto.get().getNrProtocolo())
        );
    }
}
```

**Critérios de Aceitação:**
- [ ] CA-P05-N4a: Tentativa de abrir recurso com um já existente em andamento retorna erro 422
- [ ] CA-P05-N4b: Mensagem de erro exibe status e protocolo do recurso existente
- [ ] CA-P05-N4c: Novo recurso pode ser aberto após o anterior ser `CONCLUIDO` ou `ARQUIVADO`

---

### RN-P05-N5 — Cancelamento de Aceite na Fase AGUARDANDO_ACEITE 🟠 P05-M5

**Prioridade:** Alta  
**Origem:** Demanda 5 — Sprint 02 Hammer

**Descrição:** O cidadão ou RT deve poder **cancelar seu próprio aceite** de uma solicitação de análise enquanto o licenciamento estiver em `AGUARDANDO_ACEITE`. Ao cancelar, o licenciamento retorna ao estado anterior e todos os aceites são invalidados.

**Novo endpoint:**
```
DELETE /api/v1/licenciamentos/{id}/aceites/meu-aceite
Authorization: Bearer {jwt}
```

**Regras:**
```java
public void cancelarAceite(UUID idLicenciamento, UUID idUsuario) {
    Licenciamento lic = buscarOuLancar(idLicenciamento);
    if (!StatusLicenciamento.AGUARDANDO_ACEITE.equals(lic.getStatus())) {
        throw new BusinessException("Aceite só pode ser cancelado em AGUARDANDO_ACEITE");
    }
    // Invalidar todos os aceites
    aceiteRepository.invalidarTodosPorLicenciamento(idLicenciamento);
    // Retornar ao estado anterior
    lic.setStatus(StatusLicenciamento.RASCUNHO);
    // Notificar demais envolvidos
    notificacaoService.notificarCancelamentoAceite(lic, idUsuario);
    licenciamentoRepository.save(lic);
}
```

**Critérios de Aceitação:**
- [ ] CA-P05-N5a: RT pode cancelar aceite quando licenciamento está em `AGUARDANDO_ACEITE`
- [ ] CA-P05-N5b: Após cancelamento, todos os aceites são invalidados e o status retorna para `RASCUNHO`
- [ ] CA-P05-N5c: Os demais envolvidos recebem notificação do cancelamento
- [ ] CA-P05-N5d: Cancelamento em status diferente de `AGUARDANDO_ACEITE` retorna 422

---

### Resumo das Mudanças P05 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P05-M1 | RN-P05-N1 | Lembretes de ciência D+7, D+20, D+27 (OBRIGATÓRIO) | 🔴 Crítica |
| P05-M2 | RN-P05-N2 | Prazo do recurso em dias ÚTEIS — tabela de feriados (OBRIGATÓRIO) | 🔴 Crítica |
| P05-M3 | RN-P05-N3 | Modal de alerta ao editar recurso em 2ª instância | 🟠 Alta |
| P05-M4 | RN-P05-N4 | Bloquear abertura de novo recurso quando já existe um em andamento | 🟠 Alta |
| P05-M5 | RN-P05-N5 | Cancelamento de aceite em AGUARDANDO_ACEITE | 🟠 Alta |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 02–04 + Normas RTCBMRS*

*Documento gerado em 2026-03-09*
*Referência: código-fonte SOLCBM.BackEnd16-06 — processo P05*
*Projeto: Licitação SOL — CBM-RS*
