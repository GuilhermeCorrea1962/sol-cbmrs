# Requisitos — P07 Vistoria Presencial (Stack Java Moderna)

**Processo:** P07 — Vistoria Presencial
**Versão:** 1.0
**Data:** 2026-03-10
**Stack alvo:** Spring Boot 3.x · Spring Security + Keycloak · Spring Data JPA · PostgreSQL · MinIO · Spring Mail
**Referência:** código-fonte `SOLCBM.BackEnd16-06` (VistoriaRN, VistoriaConclusaoRN, VistoriaHomologacaoAdmRN, LaudoVistoriaRN, LicenciamentoDistribuicaoVistoriaRN, AppciRN, CivCienciaCidadaoRN)

---

## 1. Visão Geral

O processo P07 representa a **vistoria presencial** realizada pelo Corpo de Bombeiros após a aprovação da análise técnica (P04) ou após a concessão de isenção de taxa (P06). O processo inicia com o licenciamento no estado `AGUARDA_DISTRIBUICAO_VISTORIA` e termina em um de três caminhos:

| Caminho | Condição | Estado final do licenciamento | Artefato gerado |
|---|---|---|---|
| **Aprovado** | Vistoria aprovada e homologada pelo ADM | `AGUARDANDO_PRPCI` | APPCI (Alvará de Prevenção e Proteção Contra Incêndio) |
| **Reprovado** | Laudo de reprovação + homologação ADM | `CIV` | CIV (Comunicado de Inconformidade na Vistoria) |
| **Inviável** | Vistoria tecnicamente inviável | `ANALISE_INVIABILIDADE_PENDENTE` | Encaminhamento para P11 |

O fluxo contempla ainda:

- **Distribuição:** atribuição do(s) fiscal(is) responsável(is) pela vistoria (`VistorianteED`).
- **Ciência:** confirmação do cidadão/RT sobre a data prevista da vistoria.
- **Laudo:** upload de laudo técnico (obrigatório para aprovação ou reprovação) e de laudos complementares (AVCB parciais, laudos de especialidade).
- **Redistribuição:** troca de fiscal(is) antes do início da vistoria efetiva.
- **Integração LAI:** cadastro de demanda no sistema LAI quando a vistoria é distribuída.

---

## 2. Stack Tecnológica Moderna

| Camada | Tecnologia | Equivalência com stack atual |
|---|---|---|
| Framework web | Spring Boot 3.x (Spring Web MVC) | JAX-RS + WildFly |
| Segurança / IdP | Spring Security 6 + Keycloak (OIDC/JWT) | SOE PROCERGS (`@SOEAuthRest`) |
| Persistência | Spring Data JPA 3 + Hibernate 6 + PostgreSQL | JPA/Hibernate + Oracle/PG |
| Armazenamento de arquivos | MinIO (S3-compatible) | Alfresco ECM |
| Migração de schema | Liquibase | DDL manual |
| Auditoria | Hibernate Envers (`@Audited`) | Hibernate Envers |
| Notificações | Spring Mail + Thymeleaf (templates HTML) | `NotificacaoRN` + SOE email |
| Build | Maven 3 ou Gradle 8 | Maven |
| Java | Java 21 (LTS) | Java 8/11 |

**Dependência PROCERGS eliminada:** toda autenticação e autorização passa pelo Keycloak. Os perfis de acesso (`ROLE_RT`, `ROLE_ADM_CBM`, `ROLE_FISCAL`) são mapeados como realm roles ou client roles no Keycloak e propagados via JWT Bearer Token.

---

## 3. Enumerações

### 3.1 StatusVistoria

Estado interno do registro de vistoria (`CBM_VISTORIA.status`).

```java
public enum StatusVistoria {
    SOLICITADA,          // Vistoria criada, aguardando distribuição
    EM_VISTORIA,         // Fiscal(is) distribuído(s), vistoria em andamento
    EM_APROVACAO,        // Fiscal concluiu com laudo de aprovação; aguarda homologação ADM
    APROVADO,            // ADM homologou aprovação; APPCI emitido
    REPROVADO,           // ADM homologou reprovação; CIV gerado
    EM_REDISTRIBUICAO,   // Redistribuição solicitada antes do início
    EM_RASCUNHO,         // Vistoria salva parcialmente pelo fiscal (não concluída)
    CANCELADA            // Vistoria cancelada administrativamente
}
```

### 3.2 TipoLaudo

Especialidade técnica do laudo complementar.

```java
public enum TipoLaudo {
    COMPARTIMENTACAO_DE_AREAS,
    CONTROLE_DE_MATERIAS,
    SEGURANCA_ESTRUTURAL,
    ISOLAMENTO_RISCO,
    EQUIPAMENTO_DE_UTILIZACAO
}
```

### 3.3 TipoVistoria

```java
public enum TipoVistoria {
    VISTORIA_DEFINITIVA,   // Primeira vistoria do ciclo de licenciamento
    VISTORIA_RENOVACAO     // Vistoria de renovação do APPCI
}
```

### 3.4 TipoTurnoVistoria

```java
public enum TipoTurnoVistoria {
    MATUTINO,   // Período da manhã
    VESPERTINO  // Período da tarde
}
```

### 3.5 SituacaoLicenciamento (estados relevantes para P07)

Estes valores fazem parte do enum maior `SituacaoLicenciamento` compartilhado por todos os processos. Os relevantes para P07:

```java
AGUARDA_DISTRIBUICAO_VISTORIA,   // Entrada do P07 — aguardando atribuição de fiscal
EM_VISTORIA,                     // Fiscal distribuído, vistoria em andamento
AGUARDANDO_PRPCI,                // Saída aprovado — aguardando APPCI
CIV,                             // Saída reprovado — Comunicado de Inconformidade na Vistoria
ANALISE_INVIABILIDADE_PENDENTE   // Saída inviável — encaminha para P11
```

---

## 4. Entidades JPA

### 4.1 Vistoria

```java
@Entity
@Table(name = "CBM_VISTORIA")
@Audited
public class Vistoria {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_vistoria")
    @SequenceGenerator(name = "seq_vistoria", sequenceName = "SEQ_CBM_VISTORIA", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "NRO_VISTORIA", length = 30)
    private String numeroVistoria;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", nullable = false, length = 30)
    private StatusVistoria status;

    @Column(name = "DTH_STATUS")
    private LocalDateTime dthStatus;

    // Arquivo do laudo principal (armazenado no MinIO)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ARQUIVO")
    private Arquivo arquivo;

    // Observações em texto formatado (campo CLOB/TEXT)
    @OneToOne(cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_TEXTO_OBSERVACOES")
    private TextoFormatado observacoes;

    @Column(name = "DTH_SOLICITACAO", nullable = false)
    private LocalDateTime dthSolicitacao;

    @Column(name = "DTH_REALIZACAO_VISTORIA")
    private LocalDate dthRealizacaoVistoria;

    @Column(name = "DTH_CIENCIA")
    private LocalDateTime dthCiencia;

    // Mapeia 'S'/'N' no banco → Boolean Java (SimNaoBooleanConverter)
    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_CIENCIA", length = 1)
    private Boolean ciencia;

    @Enumerated(EnumType.STRING)
    @Column(name = "TIPO_VISTORIA", length = 30)
    private TipoVistoria tipoVistoria;

    @OneToMany(mappedBy = "vistoria", cascade = CascadeType.ALL, orphanRemoval = true)
    private Set<Vistoriante> vistoriantes = new HashSet<>();

    @Column(name = "DTH_PREVISTA_VISTORIA")
    private LocalDate dthPrevistaVistoria;

    @Enumerated(EnumType.STRING)
    @Column(name = "TURNO_PREVISTO", length = 20)
    private TipoTurnoVistoria turnoPrevisto;

    @Column(name = "DTH_DISTRIBUICAO")
    private LocalDateTime dthDistribuicao;

    @OneToOne(cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_APPCI")
    private Appci appci;

    // getters e setters omitidos
}
```

### 4.2 LaudoVistoria

```java
@Entity
@Table(name = "CBM_LAUDO_VISTORIA")
@Audited
public class LaudoVistoria {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_laudo_vistoria")
    @SequenceGenerator(name = "seq_laudo_vistoria", sequenceName = "SEQ_CBM_LAUDO_VISTORIA", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "TP_LAUDO", length = 30)
    private TipoLaudo tpLaudo;

    // Arquivo principal do laudo (MinIO)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ARQUIVO")
    private Arquivo arquivo;

    // ARTs/RRTs vinculados ao laudo (tabela associativa CBM_LAUDO_ART_RRT)
    @ManyToMany(cascade = {CascadeType.PERSIST, CascadeType.MERGE})
    @JoinTable(
        name = "CBM_LAUDO_ART_RRT",
        joinColumns = @JoinColumn(name = "ID_LAUDO"),
        inverseJoinColumns = @JoinColumn(name = "ID_ARQUIVO")
    )
    private Set<Arquivo> artRrts = new HashSet<>();

    // Documentos complementares (tabela associativa CBM_LAUDO_COMPLEMENTAR)
    @ManyToMany(cascade = {CascadeType.PERSIST, CascadeType.MERGE})
    @JoinTable(
        name = "CBM_LAUDO_COMPLEMENTAR",
        joinColumns = @JoinColumn(name = "ID_LAUDO"),
        inverseJoinColumns = @JoinColumn(name = "ID_ARQUIVO")
    )
    private Set<Arquivo> complementares = new HashSet<>();

    // Indica se este laudo é o consolidado (único por licenciamento+vistoria)
    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_CONSOLIDADO", length = 1)
    private Boolean consolidado;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_VISTORIA")
    private Vistoria vistoria;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_RENOVACAO", length = 1)
    private Boolean indRenovacao;

    // getters e setters omitidos
}
```

### 4.3 Appci

```java
@Entity
@Table(name = "CBM_APPCI")
@Audited
public class Appci {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_appci")
    @SequenceGenerator(name = "seq_appci", sequenceName = "SEQ_CBM_APPCI", allocationSize = 1)
    private Long id;

    // PDF do APPCI gerado (MinIO)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ARQUIVO")
    private Arquivo arquivo;

    @Column(name = "LOCALIZACAO", length = 500)
    private String localizacao;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "VERSAO")
    private Integer versao;

    @Column(name = "DTH_EMISSAO")
    private LocalDateTime dataHoraEmissao;

    @Column(name = "DATA_VALIDADE")
    private LocalDate dataValidade;

    // Indica se este APPCI é a versão vigente
    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_VERSAO_VIGENTE", length = 1)
    private Boolean indVersaoVigente;

    @Column(name = "DATA_VIGENCIA_INICIO")
    private LocalDate dataVigenciaInicio;

    @Column(name = "DATA_VIGENCIA_FIM")
    private LocalDate dataVigenciaFim;

    @Column(name = "DTH_CIENCIA")
    private LocalDateTime dthCiencia;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_CIENCIA", length = 1)
    private Boolean ciencia;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "IND_RENOVACAO", length = 1)
    private Boolean indRenovacao;

    // getters e setters omitidos
}
```

### 4.4 Vistoriante

```java
@Entity
@Table(name = "CBM_VISTORIANTE")
@Audited
public class Vistoriante {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_vistoriante")
    @SequenceGenerator(name = "seq_vistoriante", sequenceName = "SEQ_CBM_VISTORIANTE", allocationSize = 1)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_VISTORIA", nullable = false)
    private Vistoria vistoria;

    // FK para o usuário ADM/fiscal do CBM-RS
    @Column(name = "ID_USUARIO_CBM", nullable = false)
    private Long idUsuarioCbm;

    @Column(name = "NOME_USUARIO_CBM", length = 200)
    private String nomeUsuarioCbm;

    @Column(name = "MATRICULA", length = 50)
    private String matricula;

    // getters e setters omitidos
}
```

### 4.5 SimNaoBooleanConverter (utilitário compartilhado)

```java
@Converter
public class SimNaoBooleanConverter implements AttributeConverter<Boolean, String> {

    @Override
    public String convertToDatabaseColumn(Boolean attribute) {
        if (attribute == null) return null;
        return attribute ? "S" : "N";
    }

    @Override
    public Boolean convertToEntityAttribute(String dbData) {
        if (dbData == null) return null;
        return "S".equalsIgnoreCase(dbData);
    }
}
```

---

## 5. Repositórios Spring Data JPA

```java
public interface VistoriaRepository extends JpaRepository<Vistoria, Long> {

    Optional<Vistoria> findByLicenciamentoId(Long idLicenciamento);

    List<Vistoria> findByStatus(StatusVistoria status);

    // Vistorias distribuídas para um fiscal específico
    @Query("SELECT v FROM Vistoria v JOIN v.vistoriantes vt WHERE vt.idUsuarioCbm = :idFiscal AND v.status = :status")
    List<Vistoria> findByFiscalAndStatus(@Param("idFiscal") Long idFiscal,
                                         @Param("status") StatusVistoria status);

    // Listagem para distribuição — estado AGUARDA_DISTRIBUICAO_VISTORIA no licenciamento
    @Query("SELECT v FROM Vistoria v WHERE v.licenciamento.situacao = 'AGUARDA_DISTRIBUICAO_VISTORIA'")
    List<Vistoria> findAguardandoDistribuicao();

    // Vistorias aprovadas para consulta administrativa
    List<Vistoria> findByStatusOrderByDthStatusDesc(StatusVistoria status);
}

public interface LaudoVistoriaRepository extends JpaRepository<LaudoVistoria, Long> {

    List<LaudoVistoria> findByLicenciamentoId(Long idLicenciamento);

    Optional<LaudoVistoria> findByVistoriaIdAndConsolidado(Long idVistoria, Boolean consolidado);
}

public interface AppciRepository extends JpaRepository<Appci, Long> {

    Optional<Appci> findByLicenciamentoIdAndIndVersaoVigente(Long idLicenciamento, Boolean vigente);

    List<Appci> findByLicenciamentoIdOrderByVersaoDesc(Long idLicenciamento);
}

public interface VistorianteRepository extends JpaRepository<Vistoriante, Long> {

    List<Vistoriante> findByVistoriaId(Long idVistoria);
}
```

---

## 6. Services Spring

### 6.1 VistoriaService

Responsável pela criação, ciência, conclusão parcial (rascunho) e consulta da vistoria pelo cidadão/RT.

```java
@Service
@Transactional
public class VistoriaService {

    private final VistoriaRepository vistoriaRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final MarcoService marcoService;
    private final VistoriaNotificacaoService notificacaoService;

    /**
     * Obtém a vistoria vigente de um licenciamento.
     * Regra: apenas uma vistoria ativa por licenciamento (status != CANCELADA).
     */
    @Transactional(readOnly = true)
    @PreAuthorize("hasAnyRole('ROLE_RT', 'ROLE_ADM_CBM', 'ROLE_FISCAL')")
    public VistoriaDetalheResponse buscarPorLicenciamento(Long idLicenciamento) {
        Vistoria vistoria = vistoriaRepository.findByLicenciamentoId(idLicenciamento)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idLicenciamento));
        return VistoriaDetalheResponse.from(vistoria);
    }

    /**
     * Registra a ciência do cidadão/RT sobre a data prevista da vistoria.
     * Regra: vistoria deve estar no status EM_VISTORIA e campo dthPrevistaVistoria preenchido.
     * Persistência: seta ciencia='S' e dthCiencia=now().
     * Marco: nenhum marco registrado nesta etapa (apenas confirmação).
     */
    @PreAuthorize("hasAnyRole('ROLE_RT', 'ROLE_RU')")
    public void registrarCiencia(Long idLicenciamento, Long idVistoria) {
        Vistoria vistoria = buscarVistoriaValidada(idLicenciamento, idVistoria, StatusVistoria.EM_VISTORIA);
        if (vistoria.getDthPrevistaVistoria() == null) {
            throw new VistoriaSemDataPrevistaException(idVistoria);
        }
        vistoria.setCiencia(true);
        vistoria.setDthCiencia(LocalDateTime.now());
        vistoriaRepository.save(vistoria);
    }

    /**
     * Salva vistoria em rascunho (status EM_RASCUNHO).
     * Permite ao fiscal salvar andamento sem concluir.
     * Não altera o estado do licenciamento.
     */
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public void salvarRascunho(Long idLicenciamento, VistoriaRascunhoRequest request) {
        Vistoria vistoria = vistoriaRepository.findByLicenciamentoId(idLicenciamento)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idLicenciamento));
        validarStatusParaEdicao(vistoria);
        // Aplica campos editáveis: observações, data realização, turno
        aplicarDadosRascunho(vistoria, request);
        vistoria.setStatus(StatusVistoria.EM_RASCUNHO);
        vistoriaRepository.save(vistoria);
    }

    private Vistoria buscarVistoriaValidada(Long idLic, Long idVistoria, StatusVistoria statusEsperado) {
        Vistoria vistoria = vistoriaRepository.findById(idVistoria)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idVistoria));
        if (!vistoria.getLicenciamento().getId().equals(idLic)) {
            throw new VistoriaNaoPertenceAoLicenciamentoException(idVistoria, idLic);
        }
        if (!vistoria.getStatus().equals(statusEsperado)) {
            throw new StatusVistoriaInvalidoException(vistoria.getStatus(), statusEsperado);
        }
        return vistoria;
    }
}
```

### 6.2 VistoriaConclusaoService

Responsável pela conclusão da vistoria (aprovação, reprovação ou inviabilidade) pelo fiscal, e pela homologação/indeferimento pelo ADM.

```java
@Service
@Transactional
public class VistoriaConclusaoService {

    private final VistoriaRepository vistoriaRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final LaudoVistoriaRepository laudoRepository;
    private final AppciService appciService;
    private final CivService civService;
    private final MarcoService marcoService;
    private final VistoriaNotificacaoService notificacaoService;

    /**
     * Fiscal conclui a vistoria com laudo de aprovação.
     * Pré-condição: vistoria em status EM_VISTORIA ou EM_RASCUNHO.
     * Ação: status da vistoria → EM_APROVACAO. Não altera licenciamento ainda.
     * Validações: laudo consolidado obrigatório; dthRealizacaoVistoria obrigatória.
     */
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public void concluirAprovacao(Long idLicenciamento, VistoriaConclusaoRequest request) {
        Vistoria vistoria = buscarVistoriaAtiva(idLicenciamento);
        validarConclusaoFiscal(vistoria);
        validarLaudoConsolidado(idLicenciamento, vistoria.getId());

        vistoria.setStatus(StatusVistoria.EM_APROVACAO);
        vistoria.setDthStatus(LocalDateTime.now());
        vistoria.setDthRealizacaoVistoria(request.dthRealizacaoVistoria());
        if (request.observacoes() != null) {
            vistoria.setObservacoes(new TextoFormatado(request.observacoes()));
        }
        vistoriaRepository.save(vistoria);
    }

    /**
     * Fiscal conclui a vistoria com laudo de reprovação.
     * Pré-condição: vistoria em status EM_VISTORIA ou EM_RASCUNHO.
     * Ação: status da vistoria → REPROVADO. Licenciamento → CIV (provisório, antes da homologação ADM).
     * Validações: laudo consolidado obrigatório; observações de inconformidade obrigatórias.
     * Nota: implementação do sistema atual muda situação do licenciamento diretamente;
     *        na stack moderna, aguardar homologação ADM (REPROVADO) antes de mudar situação.
     */
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public void concluirReprovacao(Long idLicenciamento, VistoriaConclusaoRequest request) {
        Vistoria vistoria = buscarVistoriaAtiva(idLicenciamento);
        validarConclusaoFiscal(vistoria);
        validarLaudoConsolidado(idLicenciamento, vistoria.getId());
        if (request.observacoes() == null || request.observacoes().isBlank()) {
            throw new ObservacoesInconformidadeObrigatoriaException();
        }

        vistoria.setStatus(StatusVistoria.REPROVADO);
        vistoria.setDthStatus(LocalDateTime.now());
        vistoria.setDthRealizacaoVistoria(request.dthRealizacaoVistoria());
        vistoria.setObservacoes(new TextoFormatado(request.observacoes()));
        vistoriaRepository.save(vistoria);
    }

    /**
     * ADM homologa vistoria aprovada.
     * Pré-condição: vistoria em status EM_APROVACAO.
     * Ações:
     *   1. Vistoria → status APROVADO.
     *   2. Gera APPCI (via AppciService).
     *   3. Licenciamento → situação AGUARDANDO_PRPCI.
     *   4. Registra marco HOMOLOGACAO_VISTORIA.
     *   5. Notifica cidadão/RT por e-mail.
     */
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public AppciResponse homologarAprovacao(Long idVistoria) {
        Vistoria vistoria = vistoriaRepository.findById(idVistoria)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idVistoria));
        if (!StatusVistoria.EM_APROVACAO.equals(vistoria.getStatus())) {
            throw new StatusVistoriaInvalidoException(vistoria.getStatus(), StatusVistoria.EM_APROVACAO);
        }

        vistoria.setStatus(StatusVistoria.APROVADO);
        vistoria.setDthStatus(LocalDateTime.now());

        Licenciamento licenciamento = vistoria.getLicenciamento();
        licenciamento.setSituacao(SituacaoLicenciamento.AGUARDANDO_PRPCI);

        Appci appci = appciService.gerarAppci(licenciamento, vistoria);
        vistoria.setAppci(appci);

        vistoriaRepository.save(vistoria);
        licenciamentoRepository.save(licenciamento);

        marcoService.registrar(licenciamento, TipoMarco.HOMOLOGACAO_VISTORIA);
        notificacaoService.notificarAprovacao(licenciamento);

        return AppciResponse.from(appci);
    }

    /**
     * ADM homologa vistoria reprovada (defere a reprovação).
     * Pré-condição: vistoria em status REPROVADO.
     * Ações:
     *   1. Licenciamento → situação CIV.
     *   2. Gera CIV (via CivService).
     *   3. Registra marco CIENCIA_CIV.
     *   4. Notifica cidadão/RT por e-mail com CIV em anexo.
     */
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public CivResponse deferir(Long idVistoria) {
        Vistoria vistoria = vistoriaRepository.findById(idVistoria)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idVistoria));
        if (!StatusVistoria.REPROVADO.equals(vistoria.getStatus())) {
            throw new StatusVistoriaInvalidoException(vistoria.getStatus(), StatusVistoria.REPROVADO);
        }

        Licenciamento licenciamento = vistoria.getLicenciamento();
        licenciamento.setSituacao(SituacaoLicenciamento.CIV);
        licenciamentoRepository.save(licenciamento);

        CivDocumento civ = civService.gerarCiv(licenciamento, vistoria);

        marcoService.registrar(licenciamento, TipoMarco.CIENCIA_CIV);
        notificacaoService.notificarReprovacao(licenciamento, civ);

        return CivResponse.from(civ);
    }

    /**
     * ADM indefere a conclusão do fiscal (devolve para EM_VISTORIA).
     * Uso: ADM discorda do laudo ou há pendência documental.
     * Ação: vistoria → EM_VISTORIA; licenciamento permanece EM_VISTORIA.
     * Validação: motivo do indeferimento obrigatório.
     */
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public void indeferir(Long idVistoria, VistoriaIndeferimentoRequest request) {
        Vistoria vistoria = vistoriaRepository.findById(idVistoria)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idVistoria));
        if (vistoria.getStatus() != StatusVistoria.EM_APROVACAO
                && vistoria.getStatus() != StatusVistoria.REPROVADO) {
            throw new IndeferimentoInvalidoException(vistoria.getStatus());
        }
        if (request.motivoIndeferimento() == null || request.motivoIndeferimento().isBlank()) {
            throw new MotivoIndeferimentoObrigatorioException();
        }

        vistoria.setStatus(StatusVistoria.EM_VISTORIA);
        vistoria.setDthStatus(LocalDateTime.now());
        vistoriaRepository.save(vistoria);

        notificacaoService.notificarIndeferimento(vistoria.getLicenciamento(), request.motivoIndeferimento());
    }

    /**
     * Marca vistoria como inviável.
     * Ações:
     *   1. Vistoria → status CANCELADA.
     *   2. Licenciamento → situação ANALISE_INVIABILIDADE_PENDENTE (encaminha para P11).
     *   3. Registra marco INVIABILIDADE_VISTORIA.
     */
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public void marcarInviavel(Long idLicenciamento, String motivo) {
        Vistoria vistoria = buscarVistoriaAtiva(idLicenciamento);

        vistoria.setStatus(StatusVistoria.CANCELADA);
        vistoria.setDthStatus(LocalDateTime.now());
        if (motivo != null) {
            vistoria.setObservacoes(new TextoFormatado(motivo));
        }
        vistoriaRepository.save(vistoria);

        Licenciamento licenciamento = vistoria.getLicenciamento();
        licenciamento.setSituacao(SituacaoLicenciamento.ANALISE_INVIABILIDADE_PENDENTE);
        licenciamentoRepository.save(licenciamento);

        marcoService.registrar(licenciamento, TipoMarco.INVIABILIDADE_VISTORIA);
    }

    private Vistoria buscarVistoriaAtiva(Long idLicenciamento) {
        return vistoriaRepository.findByLicenciamentoId(idLicenciamento)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idLicenciamento));
    }

    private void validarConclusaoFiscal(Vistoria vistoria) {
        if (vistoria.getStatus() != StatusVistoria.EM_VISTORIA
                && vistoria.getStatus() != StatusVistoria.EM_RASCUNHO) {
            throw new StatusVistoriaInvalidoException(vistoria.getStatus(),
                StatusVistoria.EM_VISTORIA);
        }
    }

    private void validarLaudoConsolidado(Long idLicenciamento, Long idVistoria) {
        laudoRepository.findByVistoriaIdAndConsolidado(idVistoria, true)
            .orElseThrow(() -> new LaudoConsolidadoObrigatorioException(idVistoria));
    }
}
```

### 6.3 VistoriaDistribuicaoService

```java
@Service
@Transactional
public class VistoriaDistribuicaoService {

    private final VistoriaRepository vistoriaRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final VistorianteRepository vistorianteRepository;
    private final MarcoService marcoService;
    private final VistoriaNotificacaoService notificacaoService;
    private final LaiIntegracaoService laiService; // substitui LicenciamentoIntegracaoLaiRN

    /**
     * Distribui a vistoria a um ou mais fiscais.
     * Pré-condição: licenciamento em AGUARDA_DISTRIBUICAO_VISTORIA.
     * Ações:
     *   1. Cria/atualiza registro em CBM_VISTORIA com status EM_VISTORIA.
     *   2. Cria registros em CBM_VISTORIANTE para cada fiscal.
     *   3. Licenciamento → situação EM_VISTORIA.
     *   4. Registra marco DISTRIBUICAO_VISTORIA.
     *   5. Cadastra demanda no sistema LAI (integração externa).
     *   6. Notifica fiscais por e-mail.
     */
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public VistoriaDistribuidaResponse distribuir(Long idLicenciamento,
                                                   VistoriaDistribuicaoRequest request) {
        Licenciamento licenciamento = licenciamentoRepository.findById(idLicenciamento)
            .orElseThrow(() -> new LicenciamentoNaoEncontradoException(idLicenciamento));
        if (!SituacaoLicenciamento.AGUARDA_DISTRIBUICAO_VISTORIA.equals(licenciamento.getSituacao())) {
            throw new SituacaoLicenciamentoInvalidaException(
                licenciamento.getSituacao(), SituacaoLicenciamento.AGUARDA_DISTRIBUICAO_VISTORIA);
        }
        if (request.fiscais() == null || request.fiscais().isEmpty()) {
            throw new FiscalObrigatorioException();
        }

        Vistoria vistoria = criarOuObterVistoria(licenciamento, request);
        vistoria.setStatus(StatusVistoria.EM_VISTORIA);
        vistoria.setDthDistribuicao(LocalDateTime.now());
        vistoria.setDthStatus(LocalDateTime.now());
        vistoria.setDthPrevistaVistoria(request.dthPrevista());
        vistoria.setTurnoPrevisto(request.turno());

        // Limpa vistoriantes anteriores (redistribuição)
        vistoria.getVistoriantes().clear();
        request.fiscais().forEach(f -> {
            Vistoriante v = new Vistoriante();
            v.setVistoria(vistoria);
            v.setIdUsuarioCbm(f.idUsuario());
            v.setNomeUsuarioCbm(f.nome());
            v.setMatricula(f.matricula());
            vistoria.getVistoriantes().add(v);
        });

        vistoriaRepository.save(vistoria);

        licenciamento.setSituacao(SituacaoLicenciamento.EM_VISTORIA);
        licenciamentoRepository.save(licenciamento);

        marcoService.registrar(licenciamento, TipoMarco.DISTRIBUICAO_VISTORIA);

        // Integração LAI — equivale a LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria()
        laiService.cadastrarDemandaVistoria(licenciamento, vistoria);

        notificacaoService.notificarDistribuicao(licenciamento, vistoria);

        return VistoriaDistribuidaResponse.from(vistoria);
    }

    private Vistoria criarOuObterVistoria(Licenciamento licenciamento,
                                           VistoriaDistribuicaoRequest request) {
        return vistoriaRepository.findByLicenciamentoId(licenciamento.getId())
            .orElseGet(() -> {
                Vistoria nova = new Vistoria();
                nova.setLicenciamento(licenciamento);
                nova.setDthSolicitacao(LocalDateTime.now());
                nova.setTipoVistoria(request.tipoVistoria());
                nova.setStatus(StatusVistoria.SOLICITADA);
                return nova;
            });
    }
}
```

### 6.4 LaudoVistoriaService

```java
@Service
@Transactional
public class LaudoVistoriaService {

    private final LaudoVistoriaRepository laudoRepository;
    private final VistoriaRepository vistoriaRepository;
    private final MinioService minioService;

    /**
     * Inclui ou altera laudo de vistoria (equivale a LaudoVistoriaRN.incluirOuAlterarLaudo).
     * Aceita multipart: arquivo principal, ARTs/RRTs e complementares.
     * Regra: apenas um laudo consolidado por vistoria.
     * Armazenamento: arquivo enviado ao MinIO; apenas o objectKey é persistido na entidade Arquivo.
     */
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public LaudoVistoriaResponse incluirOuAlterar(Long idLicenciamento,
                                                    LaudoVistoriaRequest request,
                                                    MultipartFile arquivoPrincipal,
                                                    List<MultipartFile> artRrts,
                                                    List<MultipartFile> complementares) {
        Vistoria vistoria = vistoriaRepository.findByLicenciamentoId(idLicenciamento)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idLicenciamento));

        LaudoVistoria laudo = laudoRepository
            .findByVistoriaIdAndConsolidado(vistoria.getId(), request.consolidado())
            .orElseGet(LaudoVistoria::new);

        laudo.setVistoria(vistoria);
        laudo.setLicenciamento(vistoria.getLicenciamento());
        laudo.setTpLaudo(request.tpLaudo());
        laudo.setConsolidado(request.consolidado());
        laudo.setIndRenovacao(request.indRenovacao());

        if (arquivoPrincipal != null && !arquivoPrincipal.isEmpty()) {
            String objectKey = minioService.upload(arquivoPrincipal, "laudos");
            Arquivo arquivo = new Arquivo(objectKey, arquivoPrincipal.getOriginalFilename(),
                arquivoPrincipal.getSize());
            laudo.setArquivo(arquivo);
        }

        uploadArquivosAdicionais(laudo.getArtRrts(), artRrts, "art-rrt");
        uploadArquivosAdicionais(laudo.getComplementares(), complementares, "complementares");

        return LaudoVistoriaResponse.from(laudoRepository.save(laudo));
    }

    private void uploadArquivosAdicionais(Set<Arquivo> destino,
                                           List<MultipartFile> arquivos,
                                           String pasta) {
        if (arquivos == null) return;
        arquivos.stream()
            .filter(f -> !f.isEmpty())
            .forEach(f -> {
                String key = minioService.upload(f, pasta);
                destino.add(new Arquivo(key, f.getOriginalFilename(), f.getSize()));
            });
    }
}
```

### 6.5 AppciService

```java
@Service
@Transactional
public class AppciService {

    private final AppciRepository appciRepository;
    private final AppciPdfGenerator pdfGenerator; // gera o PDF do APPCI
    private final MinioService minioService;

    /**
     * Gera o APPCI para um licenciamento aprovado.
     * Equivale a AppciRN do sistema atual.
     * Regras:
     *   - Marca todos os APPCIs anteriores como indVersaoVigente=false.
     *   - Gera PDF do APPCI e armazena no MinIO.
     *   - Cria novo registro com indVersaoVigente=true e versao incrementada.
     *   - dataValidade calculada conforme regras do CBM-RS (ex.: 1 ano para renovação).
     */
    public Appci gerarAppci(Licenciamento licenciamento, Vistoria vistoria) {
        // Invalida versões anteriores
        appciRepository.findByLicenciamentoIdAndIndVersaoVigente(licenciamento.getId(), true)
            .ifPresent(anterior -> {
                anterior.setIndVersaoVigente(false);
                appciRepository.save(anterior);
            });

        int proximaVersao = appciRepository.findByLicenciamentoIdOrderByVersaoDesc(licenciamento.getId())
            .stream().findFirst().map(a -> a.getVersao() + 1).orElse(1);

        byte[] pdfBytes = pdfGenerator.gerar(licenciamento, vistoria, proximaVersao);
        String objectKey = minioService.uploadBytes(pdfBytes, "appci",
            "APPCI_" + licenciamento.getNumeroPpci() + "_v" + proximaVersao + ".pdf");

        Arquivo arquivoPdf = new Arquivo(objectKey,
            "APPCI_" + licenciamento.getNumeroPpci() + ".pdf", (long) pdfBytes.length);

        Appci appci = new Appci();
        appci.setLicenciamento(licenciamento);
        appci.setArquivo(arquivoPdf);
        appci.setVersao(proximaVersao);
        appci.setDataHoraEmissao(LocalDateTime.now());
        appci.setIndVersaoVigente(true);
        appci.setDataVigenciaInicio(LocalDate.now());
        appci.setDataVigenciaFim(calcularDataValidade(licenciamento, vistoria));
        appci.setIndRenovacao(Boolean.TRUE.equals(vistoria.getLicenciamento().getIndRenovacao()));

        return appciRepository.save(appci);
    }

    private LocalDate calcularDataValidade(Licenciamento licenciamento, Vistoria vistoria) {
        // Regra de negócio: prazo de validade conforme classificação do estabelecimento
        // Implementação específica a ser definida conforme ITCBMRS vigente
        return LocalDate.now().plusYears(1);
    }
}
```

---

## 7. Validações e Exceções

### 7.1 Exceções de domínio

```java
// Hierarquia base
public abstract class SolBusinessException extends RuntimeException {
    private final String codigoErro;
    protected SolBusinessException(String codigoErro, String mensagem) {
        super(mensagem);
        this.codigoErro = codigoErro;
    }
    public String getCodigoErro() { return codigoErro; }
}

public class VistoriaNaoEncontradaException extends SolBusinessException {
    public VistoriaNaoEncontradaException(Long id) {
        super("VISTORIA_001", "Vistoria não encontrada: " + id);
    }
}

public class StatusVistoriaInvalidoException extends SolBusinessException {
    public StatusVistoriaInvalidoException(StatusVistoria atual, StatusVistoria esperado) {
        super("VISTORIA_002",
            String.format("Status inválido: %s. Esperado: %s", atual, esperado));
    }
}

public class LaudoConsolidadoObrigatorioException extends SolBusinessException {
    public LaudoConsolidadoObrigatorioException(Long idVistoria) {
        super("VISTORIA_003", "Laudo consolidado obrigatório para vistoria: " + idVistoria);
    }
}

public class FiscalObrigatorioException extends SolBusinessException {
    public FiscalObrigatorioException() {
        super("VISTORIA_004", "Ao menos um fiscal deve ser informado para a distribuição.");
    }
}

public class VistoriaSemDataPrevistaException extends SolBusinessException {
    public VistoriaSemDataPrevistaException(Long id) {
        super("VISTORIA_005", "Vistoria sem data prevista definida: " + id);
    }
}

public class ObservacoesInconformidadeObrigatoriaException extends SolBusinessException {
    public ObservacoesInconformidadeObrigatoriaException() {
        super("VISTORIA_006", "Observações de inconformidade são obrigatórias para reprovação.");
    }
}

public class MotivoIndeferimentoObrigatorioException extends SolBusinessException {
    public MotivoIndeferimentoObrigatorioException() {
        super("VISTORIA_007", "Motivo do indeferimento é obrigatório.");
    }
}

public class IndeferimentoInvalidoException extends SolBusinessException {
    public IndeferimentoInvalidoException(StatusVistoria status) {
        super("VISTORIA_008",
            "Indeferimento inválido para vistoria em status: " + status);
    }
}

public class VistoriaNaoPertenceAoLicenciamentoException extends SolBusinessException {
    public VistoriaNaoPertenceAoLicenciamentoException(Long idVistoria, Long idLic) {
        super("VISTORIA_009",
            String.format("Vistoria %d não pertence ao licenciamento %d", idVistoria, idLic));
    }
}
```

### 7.2 GlobalExceptionHandler

```java
@RestControllerAdvice
public class SolExceptionHandler {

    @ExceptionHandler(SolBusinessException.class)
    public ResponseEntity<ErroResponse> handleBusiness(SolBusinessException ex) {
        return ResponseEntity.unprocessableEntity()
            .body(new ErroResponse(ex.getCodigoErro(), ex.getMessage()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErroResponse> handleAcesso(AccessDeniedException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
            .body(new ErroResponse("ACESSO_NEGADO", "Permissão insuficiente."));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErroResponse> handleValidacao(MethodArgumentNotValidException ex) {
        String campos = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .collect(Collectors.joining("; "));
        return ResponseEntity.badRequest()
            .body(new ErroResponse("VALIDACAO_001", campos));
    }
}
```

---

## 8. REST Controllers Spring MVC

### 8.1 VistoriaController (endpoints do cidadão/RT)

```java
@RestController
@RequestMapping("/api/licenciamento-vistoria")
public class VistoriaController {

    private final VistoriaService vistoriaService;
    private final VistoriaConclusaoService conclusaoService;
    private final LaudoVistoriaService laudoService;

    /**
     * GET /api/licenciamento-vistoria/{idLic}
     * Retorna a vistoria vigente de um licenciamento.
     * Roles: ROLE_RT, ROLE_ADM_CBM, ROLE_FISCAL
     */
    @GetMapping("/{idLic}")
    @PreAuthorize("hasAnyRole('ROLE_RT', 'ROLE_ADM_CBM', 'ROLE_FISCAL')")
    public ResponseEntity<VistoriaDetalheResponse> buscar(@PathVariable Long idLic) {
        return ResponseEntity.ok(vistoriaService.buscarPorLicenciamento(idLic));
    }

    /**
     * PUT /api/licenciamento-vistoria/{idLic}/termo/{idVistoria}
     * Cidadão/RT registra ciência sobre a data prevista da vistoria.
     * Roles: ROLE_RT, ROLE_RU
     */
    @PutMapping("/{idLic}/termo/{idVistoria}")
    @PreAuthorize("hasAnyRole('ROLE_RT', 'ROLE_RU')")
    public ResponseEntity<Void> registrarCiencia(@PathVariable Long idLic,
                                                  @PathVariable Long idVistoria) {
        vistoriaService.registrarCiencia(idLic, idVistoria);
        return ResponseEntity.noContent().build();
    }

    /**
     * PUT /api/licenciamento-vistoria/{idLic}/laudo
     * Fiscal inclui ou altera laudo da vistoria (multipart/form-data).
     * Roles: ROLE_FISCAL
     */
    @PutMapping(value = "/{idLic}/laudo", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public ResponseEntity<LaudoVistoriaResponse> incluirLaudo(
            @PathVariable Long idLic,
            @RequestPart("dados") LaudoVistoriaRequest request,
            @RequestPart(value = "arquivo", required = false) MultipartFile arquivo,
            @RequestPart(value = "artRrts", required = false) List<MultipartFile> artRrts,
            @RequestPart(value = "complementares", required = false) List<MultipartFile> complementares) {
        return ResponseEntity.ok(laudoService.incluirOuAlterar(idLic, request, arquivo, artRrts, complementares));
    }

    /**
     * POST /api/licenciamento-vistoria/{idLic}
     * Fiscal conclui a vistoria com aprovação.
     * Roles: ROLE_FISCAL
     */
    @PostMapping("/{idLic}")
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public ResponseEntity<Void> concluirAprovacao(@PathVariable Long idLic,
                                                   @RequestBody @Valid VistoriaConclusaoRequest request) {
        conclusaoService.concluirAprovacao(idLic, request);
        return ResponseEntity.noContent().build();
    }

    /**
     * POST /api/licenciamento-vistoria/{idLic}/parcial
     * Fiscal salva vistoria em rascunho (andamento parcial).
     * Roles: ROLE_FISCAL
     */
    @PostMapping("/{idLic}/parcial")
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public ResponseEntity<Void> salvarRascunho(@PathVariable Long idLic,
                                                @RequestBody @Valid VistoriaRascunhoRequest request) {
        vistoriaService.salvarRascunho(idLic, request);
        return ResponseEntity.noContent().build();
    }

    /**
     * POST /api/licenciamento-vistoria/{idLic}/reprovar
     * Fiscal conclui a vistoria com reprovação.
     * Roles: ROLE_FISCAL
     */
    @PostMapping("/{idLic}/reprovar")
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public ResponseEntity<Void> concluirReprovacao(@PathVariable Long idLic,
                                                    @RequestBody @Valid VistoriaConclusaoRequest request) {
        conclusaoService.concluirReprovacao(idLic, request);
        return ResponseEntity.noContent().build();
    }

    /**
     * POST /api/licenciamento-vistoria/{idLic}/inviavel
     * Fiscal declara inviabilidade da vistoria.
     * Roles: ROLE_FISCAL
     */
    @PostMapping("/{idLic}/inviavel")
    @PreAuthorize("hasRole('ROLE_FISCAL')")
    public ResponseEntity<Void> marcarInviavel(@PathVariable Long idLic,
                                                @RequestBody VistoriaInviavelRequest request) {
        conclusaoService.marcarInviavel(idLic, request.motivo());
        return ResponseEntity.noContent().build();
    }
}
```

### 8.2 VistoriaAdmController (endpoints administrativos CBM-RS)

```java
@RestController
@RequestMapping("/api/adm/vistoria")
public class VistoriaAdmController {

    private final VistoriaConclusaoService conclusaoService;
    private final VistoriaDistribuicaoService distribuicaoService;
    private final VistoriaService vistoriaService;

    /**
     * PUT /api/adm/vistoria/{idVistoria}/aprovar
     * ADM homologa vistoria aprovada → gera APPCI.
     * Roles: ROLE_ADM_CBM
     */
    @PutMapping("/{idVistoria}/aprovar")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<AppciResponse> aprovar(@PathVariable Long idVistoria) {
        return ResponseEntity.ok(conclusaoService.homologarAprovacao(idVistoria));
    }

    /**
     * PUT /api/adm/vistoria/{idVistoria}/reprovar (deferir reprovação)
     * ADM homologa reprovação → gera CIV.
     * Roles: ROLE_ADM_CBM
     */
    @PutMapping("/{idVistoria}/reprovar")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<CivResponse> deferir(@PathVariable Long idVistoria) {
        return ResponseEntity.ok(conclusaoService.deferir(idVistoria));
    }

    /**
     * PUT /api/adm/vistoria/{idVistoria}/indeferir
     * ADM devolve vistoria para o fiscal (rejeita a conclusão).
     * Roles: ROLE_ADM_CBM
     */
    @PutMapping("/{idVistoria}/indeferir")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<Void> indeferir(@PathVariable Long idVistoria,
                                           @RequestBody @Valid VistoriaIndeferimentoRequest request) {
        conclusaoService.indeferir(idVistoria, request);
        return ResponseEntity.noContent().build();
    }
}
```

### 8.3 VistoriaDistribuicaoController

```java
@RestController
@RequestMapping("/api/adm/licenciamentos")
public class VistoriaDistribuicaoController {

    private final VistoriaDistribuicaoService distribuicaoService;
    private final VistoriaService vistoriaService;

    /**
     * PUT /api/adm/licenciamentos/distribuir/vistorias
     * Distribui vistoria a fiscal(is).
     * Roles: ROLE_ADM_CBM
     */
    @PutMapping("/distribuir/vistorias")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<VistoriaDistribuidaResponse> distribuir(
            @RequestBody @Valid VistoriaDistribuicaoRequest request) {
        return ResponseEntity.ok(distribuicaoService.distribuir(request.idLicenciamento(), request));
    }

    /**
     * GET /api/adm/licenciamentos/vistorias/solicitadas
     * Lista licenciamentos aguardando distribuição de vistoria.
     * Roles: ROLE_ADM_CBM
     */
    @GetMapping("/vistorias/solicitadas")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<List<VistoriaResumoResponse>> listarSolicitadas() {
        return ResponseEntity.ok(vistoriaService.listarAguardandoDistribuicao());
    }

    /**
     * GET /api/adm/licenciamentos/vistorias/distribuidas
     * Lista vistorias já distribuídas (em andamento).
     * Roles: ROLE_ADM_CBM, ROLE_FISCAL
     */
    @GetMapping("/vistorias/distribuidas")
    @PreAuthorize("hasAnyRole('ROLE_ADM_CBM', 'ROLE_FISCAL')")
    public ResponseEntity<List<VistoriaResumoResponse>> listarDistribuidas() {
        return ResponseEntity.ok(vistoriaService.listarEmAndamento());
    }

    /**
     * GET /api/adm/licenciamentos/vistorias/aprovadas
     * Lista vistorias concluídas aguardando homologação ADM.
     * Roles: ROLE_ADM_CBM
     */
    @GetMapping("/vistorias/aprovadas")
    @PreAuthorize("hasRole('ROLE_ADM_CBM')")
    public ResponseEntity<List<VistoriaResumoResponse>> listarAprovadas() {
        return ResponseEntity.ok(vistoriaService.listarEmAprovacao());
    }
}
```

---

## 9. DTOs (Records Java 16+)

```java
// Requisição de distribuição de vistoria
public record VistoriaDistribuicaoRequest(
    @NotNull Long idLicenciamento,
    @NotEmpty List<FiscalRequest> fiscais,
    LocalDate dthPrevista,
    TipoTurnoVistoria turno,
    TipoVistoria tipoVistoria
) {}

public record FiscalRequest(
    @NotNull Long idUsuario,
    @NotBlank String nome,
    String matricula
) {}

// Requisição de conclusão (aprovação ou reprovação)
public record VistoriaConclusaoRequest(
    @NotNull LocalDate dthRealizacaoVistoria,
    String observacoes
) {}

// Requisição de indeferimento pelo ADM
public record VistoriaIndeferimentoRequest(
    @NotBlank String motivoIndeferimento
) {}

// Requisição de rascunho parcial
public record VistoriaRascunhoRequest(
    LocalDate dthRealizacaoVistoria,
    TipoTurnoVistoria turno,
    String observacoes
) {}

// Requisição de inviabilidade
public record VistoriaInviavelRequest(
    String motivo
) {}

// Requisição de laudo (parte JSON do multipart)
public record LaudoVistoriaRequest(
    TipoLaudo tpLaudo,
    Boolean consolidado,
    Boolean indRenovacao
) {}

// Respostas
public record VistoriaDetalheResponse(
    Long id,
    StatusVistoria status,
    LocalDateTime dthStatus,
    LocalDate dthPrevistaVistoria,
    TipoTurnoVistoria turnoPrevisto,
    LocalDate dthRealizacaoVistoria,
    Boolean ciencia,
    LocalDateTime dthCiencia,
    TipoVistoria tipoVistoria,
    List<VistorianteResponse> vistoriantes,
    ArquivoResponse arquivoLaudo
) {
    public static VistoriaDetalheResponse from(Vistoria v) {
        return new VistoriaDetalheResponse(
            v.getId(), v.getStatus(), v.getDthStatus(), v.getDthPrevistaVistoria(),
            v.getTurnoPrevisto(), v.getDthRealizacaoVistoria(), v.getCiencia(), v.getDthCiencia(),
            v.getTipoVistoria(),
            v.getVistoriantes().stream().map(VistorianteResponse::from).toList(),
            v.getArquivo() != null ? ArquivoResponse.from(v.getArquivo()) : null
        );
    }
}

public record VistorianteResponse(Long id, String nome, String matricula) {
    public static VistorianteResponse from(Vistoriante vt) {
        return new VistorianteResponse(vt.getIdUsuarioCbm(), vt.getNomeUsuarioCbm(), vt.getMatricula());
    }
}

public record VistoriaResumoResponse(
    Long idLicenciamento,
    String numeroPpci,
    Long idVistoria,
    StatusVistoria status,
    LocalDateTime dthStatus
) {}

public record AppciResponse(
    Long id,
    String localizacao,
    Integer versao,
    LocalDateTime dataHoraEmissao,
    LocalDate dataValidade,
    Boolean indVersaoVigente,
    String urlDownload   // URL pré-assinada MinIO
) {
    public static AppciResponse from(Appci a) {
        return new AppciResponse(a.getId(), a.getLocalizacao(), a.getVersao(),
            a.getDataHoraEmissao(), a.getDataValidade(), a.getIndVersaoVigente(), null);
    }
}

public record LaudoVistoriaResponse(
    Long id,
    TipoLaudo tpLaudo,
    Boolean consolidado,
    ArquivoResponse arquivo,
    List<ArquivoResponse> artRrts,
    List<ArquivoResponse> complementares
) {
    public static LaudoVistoriaResponse from(LaudoVistoria l) {
        return new LaudoVistoriaResponse(
            l.getId(), l.getTpLaudo(), l.getConsolidado(),
            l.getArquivo() != null ? ArquivoResponse.from(l.getArquivo()) : null,
            l.getArtRrts().stream().map(ArquivoResponse::from).toList(),
            l.getComplementares().stream().map(ArquivoResponse::from).toList()
        );
    }
}

public record CivResponse(Long id, String numeroCiv, String urlDownload) {}

public record ArquivoResponse(Long id, String nomeOriginal, String objectKey) {
    public static ArquivoResponse from(Arquivo a) {
        return new ArquivoResponse(a.getId(), a.getNomeOriginal(), a.getObjectKey());
    }
}

public record ErroResponse(String codigo, String mensagem) {}

public record VistoriaDistribuidaResponse(
    Long idVistoria,
    StatusVistoria status,
    LocalDate dthPrevista,
    TipoTurnoVistoria turno,
    List<VistorianteResponse> vistoriantes
) {
    public static VistoriaDistribuidaResponse from(Vistoria v) {
        return new VistoriaDistribuidaResponse(
            v.getId(), v.getStatus(), v.getDthPrevistaVistoria(), v.getTurnoPrevisto(),
            v.getVistoriantes().stream().map(VistorianteResponse::from).toList()
        );
    }
}
```

---

## 10. Segurança — Keycloak JWT

### 10.1 Configuração Spring Security

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(keycloakJwtConverter()))
            );
        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter keycloakJwtConverter() {
        JwtGrantedAuthoritiesConverter conv = new JwtGrantedAuthoritiesConverter();
        conv.setAuthoritiesClaimName("realm_access.roles"); // Keycloak realm roles
        conv.setAuthorityPrefix("ROLE_");

        JwtAuthenticationConverter jwtConverter = new JwtAuthenticationConverter();
        jwtConverter.setJwtGrantedAuthoritiesConverter(conv);
        return jwtConverter;
    }
}
```

### 10.2 Mapeamento de perfis

| Perfil no sistema atual | Role Keycloak | Descrição |
|---|---|---|
| Cidadão / RT | `ROLE_RT` | Responsável Técnico — inicia solicitações e assina ciências |
| Responsável pelo Uso | `ROLE_RU` | Proprietário/responsável do estabelecimento |
| Fiscal CBM-RS | `ROLE_FISCAL` | Bombeiro fiscal que realiza a vistoria e sobe o laudo |
| Administrador CBM-RS | `ROLE_ADM_CBM` | Distribui, homologa ou indefere vistorias |

### 10.3 Equivalência com `@Permissao` do sistema atual

| Permissão antiga (`objeto/acao`) | Equivalência moderna |
|---|---|
| `VISTORIA / CONCLUIR` | `@PreAuthorize("hasRole('ROLE_FISCAL')")` em `concluirAprovacao/Reprovacao` |
| `VISTORIA / HOMOLOGAR` | `@PreAuthorize("hasRole('ROLE_ADM_CBM')")` em `aprovar/reprovar/indeferir` |
| `DISTRIBUICAOVISTORIA / DISTRIBUIR` | `@PreAuthorize("hasRole('ROLE_ADM_CBM')")` em `distribuir` |
| `@AutorizaEnvolvido` | Validado via `licenciamento.rt.cpfCnpj == jwt.sub` no service |

---

## 11. Integração MinIO (armazenamento de arquivos)

O sistema atual utiliza o Alfresco ECM, onde cada arquivo possui um `identificadorAlfresco` (nodeRef no formato `workspace://SpacesStore/{UUID}`). Na stack moderna, o MinIO substitui o Alfresco para armazenamento de todos os arquivos binários.

### 11.1 MinioService

```java
@Service
public class MinioService {

    private final MinioClient minioClient;

    @Value("${minio.bucket}")
    private String bucket;

    @Value("${minio.url-expiry-minutes:60}")
    private int urlExpiryMinutes;

    /**
     * Faz upload de um MultipartFile para o bucket MinIO.
     * @param pasta prefixo de pasta lógica (ex: "laudos", "appci", "art-rrt")
     * @return objectKey gerado (pasta/UUID-nomeOriginal)
     */
    public String upload(MultipartFile file, String pasta) {
        String objectKey = pasta + "/" + UUID.randomUUID() + "-" + file.getOriginalFilename();
        try {
            minioClient.putObject(PutObjectArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                .stream(file.getInputStream(), file.getSize(), -1)
                .contentType(file.getContentType())
                .build());
        } catch (Exception e) {
            throw new ArquivoUploadException("Falha ao enviar arquivo para MinIO: " + objectKey, e);
        }
        return objectKey;
    }

    /**
     * Faz upload de bytes brutos (ex: PDF gerado em memória).
     */
    public String uploadBytes(byte[] bytes, String pasta, String nomeArquivo) {
        String objectKey = pasta + "/" + UUID.randomUUID() + "-" + nomeArquivo;
        try {
            minioClient.putObject(PutObjectArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                .stream(new ByteArrayInputStream(bytes), bytes.length, -1)
                .contentType("application/pdf")
                .build());
        } catch (Exception e) {
            throw new ArquivoUploadException("Falha ao enviar PDF para MinIO: " + objectKey, e);
        }
        return objectKey;
    }

    /**
     * Gera URL pré-assinada para download direto pelo cliente (validade configurável).
     */
    public String gerarUrlPresignada(String objectKey) {
        try {
            return minioClient.getPresignedObjectUrl(GetPresignedObjectUrlArgs.builder()
                .bucket(bucket)
                .object(objectKey)
                .method(Method.GET)
                .expiry(urlExpiryMinutes, TimeUnit.MINUTES)
                .build());
        } catch (Exception e) {
            throw new ArquivoDownloadException("Falha ao gerar URL de download: " + objectKey, e);
        }
    }
}
```

### 11.2 Entidade Arquivo (adaptada para MinIO)

```java
@Entity
@Table(name = "CBM_ARQUIVO")
public class Arquivo {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_arquivo")
    @SequenceGenerator(name = "seq_arquivo", sequenceName = "SEQ_CBM_ARQUIVO", allocationSize = 1)
    private Long id;

    // ObjectKey no MinIO — equivale ao identificadorAlfresco no sistema atual
    @Column(name = "OBJECT_KEY", nullable = false, length = 500)
    private String objectKey;

    @Column(name = "NOME_ORIGINAL", length = 255)
    private String nomeOriginal;

    @Column(name = "TAMANHO_BYTES")
    private Long tamanhoBytes;

    @Column(name = "CONTENT_TYPE", length = 100)
    private String contentType;

    @Column(name = "DTH_UPLOAD", nullable = false)
    private LocalDateTime dthUpload;

    public Arquivo() {}

    public Arquivo(String objectKey, String nomeOriginal, Long tamanhoBytes) {
        this.objectKey = objectKey;
        this.nomeOriginal = nomeOriginal;
        this.tamanhoBytes = tamanhoBytes;
        this.dthUpload = LocalDateTime.now();
    }
    // getters e setters omitidos
}
```

### 11.3 Configuração MinIO (application.yml)

```yaml
minio:
  url: http://minio:9000
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket: sol-cbm-rs
  url-expiry-minutes: 60
```

---

## 12. Notificações — Spring Mail

Substitui `NotificacaoRN` + SOE PROCERGS email.

```java
@Service
public class VistoriaNotificacaoService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;

    @Value("${spring.mail.from}")
    private String remetente;

    /**
     * Notifica fiscal(is) e RT/RU sobre a distribuição da vistoria.
     * Template: notificacao-distribuicao-vistoria.html
     * Destino: e-mails dos fiscais + e-mail do RT do licenciamento
     */
    public void notificarDistribuicao(Licenciamento licenciamento, Vistoria vistoria) {
        Context ctx = new Context();
        ctx.setVariable("numeroPpci", licenciamento.getNumeroPpci());
        ctx.setVariable("dthPrevista", vistoria.getDthPrevistaVistoria());
        ctx.setVariable("turno", vistoria.getTurnoPrevisto());

        List<String> destinatarios = new ArrayList<>();
        vistoria.getVistoriantes().forEach(v -> {
            // E-mail do fiscal buscado no Keycloak Admin API ou tabela de usuários
            destinatarios.add(buscarEmailFiscal(v.getIdUsuarioCbm()));
        });
        destinatarios.add(licenciamento.getResponsavelTecnico().getEmail());

        enviarEmail(destinatarios, "SOL/CBM-RS — Vistoria Distribuída: " + licenciamento.getNumeroPpci(), ctx,
            "notificacao-distribuicao-vistoria");
    }

    /**
     * Notifica RT/RU sobre aprovação da vistoria e emissão do APPCI.
     * Template: notificacao-aprovacao-vistoria.html
     */
    public void notificarAprovacao(Licenciamento licenciamento) {
        Context ctx = new Context();
        ctx.setVariable("numeroPpci", licenciamento.getNumeroPpci());
        ctx.setVariable("situacao", "APROVADO");

        enviarEmail(
            List.of(licenciamento.getResponsavelTecnico().getEmail()),
            "SOL/CBM-RS — Vistoria Aprovada: " + licenciamento.getNumeroPpci(),
            ctx, "notificacao-aprovacao-vistoria"
        );
    }

    /**
     * Notifica RT/RU sobre reprovação da vistoria e envio do CIV.
     * Template: notificacao-reprovacao-vistoria.html
     */
    public void notificarReprovacao(Licenciamento licenciamento, CivDocumento civ) {
        Context ctx = new Context();
        ctx.setVariable("numeroPpci", licenciamento.getNumeroPpci());
        ctx.setVariable("numeroCiv", civ.getNumeroCiv());

        enviarEmail(
            List.of(licenciamento.getResponsavelTecnico().getEmail()),
            "SOL/CBM-RS — CIV Emitido: " + licenciamento.getNumeroPpci(),
            ctx, "notificacao-reprovacao-vistoria"
        );
    }

    /**
     * Notifica fiscal sobre indeferimento pelo ADM.
     */
    public void notificarIndeferimento(Licenciamento licenciamento, String motivo) {
        Context ctx = new Context();
        ctx.setVariable("numeroPpci", licenciamento.getNumeroPpci());
        ctx.setVariable("motivo", motivo);

        licenciamento.getVistoria().getVistoriantes().forEach(v ->
            enviarEmail(
                List.of(buscarEmailFiscal(v.getIdUsuarioCbm())),
                "SOL/CBM-RS — Vistoria Indeferida: " + licenciamento.getNumeroPpci(),
                ctx, "notificacao-indeferimento-vistoria"
            )
        );
    }

    private void enviarEmail(List<String> destinatarios, String assunto,
                              Context ctx, String template) {
        MimeMessage message = mailSender.createMimeMessage();
        try {
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(remetente);
            helper.setTo(destinatarios.toArray(new String[0]));
            helper.setSubject(assunto);
            helper.setText(templateEngine.process(template, ctx), true);
            mailSender.send(message);
        } catch (MessagingException e) {
            // Log e não propaga — notificação não deve bloquear o fluxo principal
            log.error("Falha ao enviar notificação de vistoria: {}", assunto, e);
        }
    }

    private String buscarEmailFiscal(Long idUsuarioCbm) {
        // Consulta tabela local de usuários CBM ou Keycloak Admin API
        // Implementação específica do projeto
        return usuarioCbmRepository.findById(idUsuarioCbm)
            .map(UsuarioCbm::getEmail)
            .orElse("sem-email@cbm.rs.gov.br");
    }
}
```

---

## 13. Máquinas de Estado

### 13.1 StatusVistoria — transições

```
SOLICITADA
    │
    └──► [ADM distribui fiscal(is)]
              │
              ▼
         EM_VISTORIA ◄────────────────────────────────────────────────────────────┐
              │                                                                   │
              ├──► [Fiscal salva parcialmente]                                    │ [ADM indefere]
              │         └──► EM_RASCUNHO ──► [Fiscal conclui] ──┐                │
              │                                                   │                │
              ├──► [Fiscal conclui com aprovação] ───────────────┤                │
              │         └──► EM_APROVACAO ──► [ADM homologa] ──► APROVADO         │
              │                          └──► [ADM indefere] ────────────────────►┘
              │
              ├──► [Fiscal conclui com reprovação]
              │         └──► REPROVADO ──► [ADM defere] ──► (situação CIV)
              │                        └──► [ADM indefere] ───────────────────────►┘
              │
              └──► [Fiscal declara inviabilidade]
                        └──► CANCELADA (situação ANALISE_INVIABILIDADE_PENDENTE)
```

### 13.2 SituacaoLicenciamento — transições em P07

```
AGUARDA_DISTRIBUICAO_VISTORIA
    │
    └──► [VistoriaDistribuicaoService.distribuir()]
              │
              ▼
         EM_VISTORIA
              │
              ├──► [VistoriaConclusaoService.homologarAprovacao()]
              │         └──► AGUARDANDO_PRPCI  (→ P08 — Emissão APPCI)
              │
              ├──► [VistoriaConclusaoService.deferir()]
              │         └──► CIV              (→ P09 — Recurso de Vistoria)
              │
              └──► [VistoriaConclusaoService.marcarInviavel()]
                        └──► ANALISE_INVIABILIDADE_PENDENTE  (→ P11 — Inviabilidade)
```

### 13.3 Marcos de auditoria registrados em P07

| Marco (`TipoMarco`) | Momento | Service | Objetivo |
|---|---|---|---|
| `DISTRIBUICAO_VISTORIA` | Distribuição do fiscal | `VistoriaDistribuicaoService.distribuir()` | Registra data e fiscal(is) designados; início do prazo |
| `HOMOLOGACAO_VISTORIA` | Homologação ADM (aprovação) | `VistoriaConclusaoService.homologarAprovacao()` | Registra conclusão positiva; dispara geração do APPCI |
| `CIENCIA_CIV` | Homologação ADM (reprovação) | `VistoriaConclusaoService.deferir()` | Registra emissão do CIV; início do prazo de recurso |
| `INVIABILIDADE_VISTORIA` | Declaração de inviabilidade | `VistoriaConclusaoService.marcarInviavel()` | Registra encaminhamento para análise de inviabilidade |

---

## 14. DDL PostgreSQL

```sql
-- Sequências
CREATE SEQUENCE SEQ_CBM_VISTORIA     START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_CBM_LAUDO_VISTORIA START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_CBM_APPCI        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_CBM_VISTORIANTE  START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE SEQ_CBM_ARQUIVO      START WITH 1 INCREMENT BY 1;

-- Arquivo (MinIO objectKey)
CREATE TABLE CBM_ARQUIVO (
    ID               BIGINT       PRIMARY KEY DEFAULT NEXTVAL('SEQ_CBM_ARQUIVO'),
    OBJECT_KEY       VARCHAR(500) NOT NULL,
    NOME_ORIGINAL    VARCHAR(255),
    TAMANHO_BYTES    BIGINT,
    CONTENT_TYPE     VARCHAR(100),
    DTH_UPLOAD       TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Vistoria
CREATE TABLE CBM_VISTORIA (
    ID                      BIGINT      PRIMARY KEY DEFAULT NEXTVAL('SEQ_CBM_VISTORIA'),
    ID_LICENCIAMENTO        BIGINT      NOT NULL REFERENCES CBM_LICENCIAMENTO(ID),
    NRO_VISTORIA            VARCHAR(30),
    STATUS                  VARCHAR(30) NOT NULL,
    DTH_STATUS              TIMESTAMP,
    ID_ARQUIVO              BIGINT      REFERENCES CBM_ARQUIVO(ID),
    ID_TEXTO_OBSERVACOES    BIGINT      REFERENCES CBM_TEXTO_FORMATADO(ID),
    DTH_SOLICITACAO         TIMESTAMP   NOT NULL,
    DTH_REALIZACAO_VISTORIA DATE,
    DTH_CIENCIA             TIMESTAMP,
    IND_CIENCIA             CHAR(1)     CHECK (IND_CIENCIA IN ('S','N')),
    TIPO_VISTORIA           VARCHAR(30),
    DTH_PREVISTA_VISTORIA   DATE,
    TURNO_PREVISTO          VARCHAR(20),
    DTH_DISTRIBUICAO        TIMESTAMP,
    ID_APPCI                BIGINT      REFERENCES CBM_APPCI(ID)
);

-- Vistoriante (fiscal responsável)
CREATE TABLE CBM_VISTORIANTE (
    ID               BIGINT       PRIMARY KEY DEFAULT NEXTVAL('SEQ_CBM_VISTORIANTE'),
    ID_VISTORIA      BIGINT       NOT NULL REFERENCES CBM_VISTORIA(ID),
    ID_USUARIO_CBM   BIGINT       NOT NULL,
    NOME_USUARIO_CBM VARCHAR(200),
    MATRICULA        VARCHAR(50)
);

-- Laudo de Vistoria
CREATE TABLE CBM_LAUDO_VISTORIA (
    ID               BIGINT   PRIMARY KEY DEFAULT NEXTVAL('SEQ_CBM_LAUDO_VISTORIA'),
    ID_LICENCIAMENTO BIGINT   NOT NULL REFERENCES CBM_LICENCIAMENTO(ID),
    TP_LAUDO         VARCHAR(50),
    ID_ARQUIVO       BIGINT   REFERENCES CBM_ARQUIVO(ID),
    IND_CONSOLIDADO  CHAR(1)  CHECK (IND_CONSOLIDADO IN ('S','N')),
    ID_VISTORIA      BIGINT   REFERENCES CBM_VISTORIA(ID),
    IND_RENOVACAO    CHAR(1)  CHECK (IND_RENOVACAO IN ('S','N'))
);

-- Tabelas associativas do laudo
CREATE TABLE CBM_LAUDO_ART_RRT (
    ID_LAUDO    BIGINT NOT NULL REFERENCES CBM_LAUDO_VISTORIA(ID),
    ID_ARQUIVO  BIGINT NOT NULL REFERENCES CBM_ARQUIVO(ID),
    PRIMARY KEY (ID_LAUDO, ID_ARQUIVO)
);

CREATE TABLE CBM_LAUDO_COMPLEMENTAR (
    ID_LAUDO    BIGINT NOT NULL REFERENCES CBM_LAUDO_VISTORIA(ID),
    ID_ARQUIVO  BIGINT NOT NULL REFERENCES CBM_ARQUIVO(ID),
    PRIMARY KEY (ID_LAUDO, ID_ARQUIVO)
);

-- APPCI
CREATE TABLE CBM_APPCI (
    ID                  BIGINT   PRIMARY KEY DEFAULT NEXTVAL('SEQ_CBM_APPCI'),
    ID_ARQUIVO          BIGINT   REFERENCES CBM_ARQUIVO(ID),
    LOCALIZACAO         VARCHAR(500),
    ID_LICENCIAMENTO    BIGINT   NOT NULL REFERENCES CBM_LICENCIAMENTO(ID),
    VERSAO              INTEGER,
    DTH_EMISSAO         TIMESTAMP,
    DATA_VALIDADE       DATE,
    IND_VERSAO_VIGENTE  CHAR(1)  CHECK (IND_VERSAO_VIGENTE IN ('S','N')),
    DATA_VIGENCIA_INICIO DATE,
    DATA_VIGENCIA_FIM    DATE,
    DTH_CIENCIA          TIMESTAMP,
    IND_CIENCIA          CHAR(1) CHECK (IND_CIENCIA IN ('S','N')),
    IND_RENOVACAO        CHAR(1) CHECK (IND_RENOVACAO IN ('S','N'))
);

-- Tabelas de auditoria Hibernate Envers (geradas automaticamente)
-- CBM_VISTORIA_AUD, CBM_LAUDO_VISTORIA_AUD, CBM_APPCI_AUD, CBM_VISTORIANTE_AUD

-- Índices de performance
CREATE INDEX IDX_VISTORIA_LICENCIAMENTO ON CBM_VISTORIA(ID_LICENCIAMENTO);
CREATE INDEX IDX_VISTORIA_STATUS        ON CBM_VISTORIA(STATUS);
CREATE INDEX IDX_LAUDO_VISTORIA_REF     ON CBM_LAUDO_VISTORIA(ID_VISTORIA);
CREATE INDEX IDX_VISTORIANTE_VISTORIA   ON CBM_VISTORIANTE(ID_VISTORIA);
CREATE INDEX IDX_APPCI_LICENCIAMENTO    ON CBM_APPCI(ID_LICENCIAMENTO);
CREATE INDEX IDX_APPCI_VIGENTE          ON CBM_APPCI(ID_LICENCIAMENTO, IND_VERSAO_VIGENTE);
```

---

## 15. Integração LAI (Sistema de Acesso à Informação)

O sistema atual possui `LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria()`, que registra a demanda de vistoria no sistema LAI do estado. Na stack moderna:

```java
@Service
public class LaiIntegracaoService {

    @Value("${lai.api.url}")
    private String laiApiUrl;

    private final RestClient restClient;

    /**
     * Registra demanda de vistoria no sistema LAI.
     * Equivale a LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria().
     * Falhas devem ser tratadas com retry ou fila (não devem bloquear a distribuição).
     */
    @Async
    public void cadastrarDemandaVistoria(Licenciamento licenciamento, Vistoria vistoria) {
        try {
            LaiDemandaRequest req = new LaiDemandaRequest(
                licenciamento.getNumeroPpci(),
                licenciamento.getEnderecoEstabelecimento(),
                vistoria.getDthPrevistaVistoria(),
                vistoria.getVistoriantes().stream()
                    .map(Vistoriante::getNomeUsuarioCbm)
                    .toList()
            );
            restClient.post()
                .uri(laiApiUrl + "/demandas/vistoria")
                .body(req)
                .retrieve()
                .toBodilessEntity();
        } catch (Exception e) {
            log.error("Falha na integração LAI para licenciamento {}: {}",
                licenciamento.getId(), e.getMessage());
            // Não propaga — integração assíncrona, não crítica para o fluxo
        }
    }
}
```

---

## Referência Cruzada — Sistema Atual × Stack Moderna

| Componente atual | Equivalente moderno |
|---|---|
| `VistoriaRN` (EJB Stateless) | `VistoriaService` (Spring `@Service`) |
| `VistoriaConclusaoRN` | `VistoriaConclusaoService` |
| `VistoriaHomologacaoAdmRN` | `VistoriaConclusaoService.homologarAprovacao/indeferir` |
| `LicenciamentoDistribuicaoVistoriaRN` | `VistoriaDistribuicaoService` |
| `LaudoVistoriaRN` | `LaudoVistoriaService` |
| `AppciRN` | `AppciService` |
| `CivCienciaCidadaoRN` | `CivService` |
| `LicenciamentoIntegracaoLaiRN` | `LaiIntegracaoService` |
| `@Permissao(VISTORIA/CONCLUIR)` | `@PreAuthorize("hasRole('ROLE_FISCAL')")` |
| `@Permissao(VISTORIA/HOMOLOGAR)` | `@PreAuthorize("hasRole('ROLE_ADM_CBM')")` |
| `@SOEAuthRest` / token SOE PROCERGS | JWT Bearer Token Keycloak |
| `@AutorizaEnvolvido` | Validação manual no service (`jwt.sub == rt.cpfCnpj`) |
| `identificadorAlfresco` (nodeRef Alfresco) | `objectKey` (MinIO S3) |
| `NotificacaoRN` + SOE email | `VistoriaNotificacaoService` + Spring Mail |
| `@Audited` (Hibernate Envers) | `@Audited` (Hibernate Envers — mantido) |
| `CBM_VISTORIA_AUD`, `CBM_APPCI_AUD` | Mantidas — geradas pelo Envers |
| `SimNaoBooleanConverter` (`'S'/'N'`) | `SimNaoBooleanConverter` (mantido — compatibilidade BD) |


---

## 16. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 03 (ID3601, Demanda 21) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (itens 6.4.8.1, 13.2).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P07.

---

### RN-P07-N1 — Tipos de Isenção na Vistoria de Renovação 🟠 P07-M1

**Prioridade:** Alta  
**Origem:** ID3601 + P06-M3 — Sprint 03 Hammer

**Descrição:** O fluxo de pagamento/isenção dentro do P07, no caminho de vistoria de renovação, deve contemplar os dois tipos de isenção de vistoria definidos no ID3601 e implementados no P06-C.

**Mudança no gateway de isenção durante vistoria de renovação:**

```
[GW] Isenção solicitada?
        │ SIM
        ▼
Tipo de isenção disponível para vistoria de renovação:
    ┌─ PARCIAL_VISTORIA: "Isenção desta vistoria apenas"
    └─ PARCIAL_FASE_VISTORIA: "Isenção de toda a fase até o APPCI"

ADM CBM escolhe o tipo e aprova/nega
        │
        ▼
Marco registra tipo de isenção aprovado
```

**Integração com P06-C:**
- O fluxo de aprovação de isenção de vistoria é delegado ao P06-C (novo)
- P07 recebe o resultado do P06-C e prossegue com o tipo de isenção definido

**Critérios de Aceitação:**
- [ ] CA-P07-N1a: Vistoria de renovação oferece opção de isenção com os 2 tipos disponíveis
- [ ] CA-P07-N1b: Tipo de isenção aprovado é registrado no marco do processo
- [ ] CA-P07-N1c: Após aprovação de `PARCIAL_FASE_VISTORIA`, revistorias subsequentes não cobram nova isenção

---

### RN-P07-N2 — Marcos do Licenciamento Visíveis ao Usuário Externo (Versão Filtrada) 🟡 P07-M2

**Prioridade:** Média  
**Origem:** Demanda 21 — Sprint 02 Hammer

**Descrição:** Atualmente os marcos do processo são visíveis apenas para bombeiros. O cidadão deve poder consultar uma **versão simplificada dos marcos**, sem informações internas do CBM.

**Novo parâmetro no endpoint existente:**
```
GET /api/v1/licenciamentos/{id}/marcos?perfil=externo
GET /api/v1/licenciamentos/{id}/marcos?perfil=interno  (padrão — bombeiros)
```

**Filtragem de campos sensíveis para perfil externo:**
```java
// MarcoResponseMapper.java
public MarcoPublicoDTO toPublico(Marco marco) {
    return MarcoPublicoDTO.builder()
        .dtRegistro(marco.getDtRegistro())
        .dsDescricaoPublica(marco.getTipoMarco().getDescricaoPublica())
        .dsStatus(marco.getTipoMarco().getStatusResultante().getDescricaoPublica())
        // NÃO incluir: nome do analista, despachos internos, justificativas internas
        .build();
}
```

**Campos disponíveis para perfil externo:**
| Campo | Visível ao externo |
|-------|---------------------|
| Data/hora do marco | ✅ Sim |
| Descrição pública do marco | ✅ Sim |
| Status resultante | ✅ Sim |
| Nome do analista | ❌ Não |
| Despachos internos | ❌ Não |
| Justificativas de priorização | ❌ Não |

**Autorização:**
```java
@GetMapping("/{id}/marcos")
@PreAuthorize("@licenciamentoSecurity.canView(#id, authentication)")
public ResponseEntity<List<MarcoDTO>> listarMarcos(
    @PathVariable UUID id,
    @RequestParam(defaultValue = "interno") String perfil,
    Authentication auth) {
    
    boolean interno = perfil.equals("interno") && 
                      auth.getAuthorities().stream()
                          .anyMatch(a -> a.getAuthority().startsWith("ROLE_FISCAL") || 
                                        a.getAuthority().startsWith("ROLE_ADM"));
    return ResponseEntity.ok(marcoService.listar(id, interno));
}
```

**Critérios de Aceitação:**
- [ ] CA-P07-N2a: Cidadão autenticado pode consultar marcos do seu licenciamento com `?perfil=externo`
- [ ] CA-P07-N2b: Versão externa não exibe nome do analista, despachos ou justificativas internas
- [ ] CA-P07-N2c: Versão interna (bombeiros) mantém todos os campos atuais
- [ ] CA-P07-N2d: Cidadão tentando acessar `?perfil=interno` recebe os dados filtrados (sem escalação de privilégio)

---

### RN-P07-N3 — Bloquear Nova Vistoria e Suspender Processo Após 30 Dias da Ciência do CIV 🔴 P07-M3

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C3 / Correção 3 — RT de Implantação SOL-CBMRS item 6.4.8.1

**Descrição:** Após a ciência do CIV, o cidadão tem **30 dias corridos** para protocolar nova vistoria. Após o prazo, o PPCI deve ser suspenso automaticamente.

**Mudança no fluxo pós-`CIV_EMITIDO`:**

```
CIV emitido + ciência registrada
        │
        ▼
Registrar dt_ciencia_civ
        │
        ├── Exibir no portal: "Prazo para nova vistoria: {dt+30} ({X} dias restantes)"
        │
        ├── [Job diário] verificar PPCIs com dt_ciencia_civ + 30 < NOW()
        │           sem nova solicitação de vistoria
        │           → transitar para SUSPENSO
        │           → registrar TipoMarco.SUSPENSAO_AUTOMATICA_CIV
        │           → notificar RT, RU e Proprietário
        │
        └── [Frontend] desabilitar botão "Solicitar Nova Vistoria" após prazo
```

**Campo necessário:**
```sql
ALTER TABLE cbm_vistoria
    ADD COLUMN dt_ciencia_civ DATE;
```

**Validação de bloqueio no backend:**
```java
public void validarNovaSolicitacaoVistoria(Licenciamento lic) {
    if (lic.getDtCienciaCiv() != null) {
        LocalDate prazo = lic.getDtCienciaCiv().plusDays(30);
        if (LocalDate.now().isAfter(prazo)) {
            throw new BusinessException(
                "Prazo expirado em " + prazo.format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) +
                ". O processo será suspenso. (RT de Implantação SOL item 6.4.8.1)"
            );
        }
    }
}
```

**Nota:** O job de suspensão diária está especificado em detalhes em **P13-N1** e **P13-N2**.

**Critérios de Aceitação:**
- [ ] CA-P07-N3a: Após ciência do CIV, portal exibe contador de prazo para nova vistoria
- [ ] CA-P07-N3b: Botão "Solicitar Nova Vistoria" fica desabilitado após 30 dias da ciência do CIV
- [ ] CA-P07-N3c: API retorna 422 com mensagem de prazo expirado ao tentar solicitar após o prazo
- [ ] CA-P07-N3d: Job suspende o processo automaticamente e registra marco `SUSPENSAO_AUTOMATICA_CIV`

---

### RN-P07-N4 — Distribuição Automática de Vistorias com Critério FIFO 🔴 P07-M4

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma A2 / RT de Implantação SOL-CBMRS item 13.2

**Descrição:** A distribuição das vistorias deve seguir o mesmo princípio FIFO do P04: ordem cronológica de protocolo (`dt_protocolo`), com o fiscal de menor carga como critério de desempate. A implementação é análoga à especificada em **RN-P04-N4**.

**Adaptação para vistorias:**
```java
// VistoriaDistribuicaoService.java
public SugestaoDistribuicaoDTO sugerirProxima() {
    // Próxima vistoria na fila FIFO
    Vistoria proxima = vistoriaRepository
        .findFirstByStatusOrderByDtProtocoloAsc(StatusVistoria.AGUARDANDO_DISTRIBUICAO);
    
    // Fiscal com menor carga de vistorias ativas
    Usuario fiscalSugerido = usuarioRepository
        .findFiscalComMenorCargaVistoria();
    
    return new SugestaoDistribuicaoDTO(proxima, fiscalSugerido);
}
```

**Critérios de Aceitação:**
- [ ] CA-P07-N4a: Sistema sugere automaticamente a próxima vistoria por ordem de `dt_protocolo`
- [ ] CA-P07-N4b: Fiscal sugerido é o de menor carga de vistorias ativas
- [ ] CA-P07-N4c: Coordenador pode confirmar ou substituir, com justificativa obrigatória se substituir
- [ ] CA-P07-N4d: Justificativa registrada com data/hora e usuário que alterou

---

### Resumo das Mudanças P07 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P07-M3 | RN-P07-N3 | Suspensão automática após 30 dias do CIV sem nova vistoria (OBRIGATÓRIO) | 🔴 Crítica |
| P07-M4 | RN-P07-N4 | Distribuição FIFO de vistorias (OBRIGATÓRIO) | 🔴 Crítica |
| P07-M1 | RN-P07-N1 | Tipos de isenção (P06-C) na vistoria de renovação | 🟠 Alta |
| P07-M2 | RN-P07-N2 | Marcos visíveis ao usuário externo (versão filtrada) | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 03–04 + Normas RTCBMRS*
