# Requisitos P08 — Emissão e Aceite do PRPCI
## Stack Java Moderna (Spring Boot 3.x · Keycloak · MinIO · PostgreSQL)

> Documento de requisitos destinado à equipe de desenvolvimento responsável pela reimplementação do processo P08 do sistema SOL (Sistema Online de Licenciamento) do CBM-RS.
> Não há dependência de serviços PROCERGS/SOE. A autenticação é integralmente gerida pelo Keycloak local.

---

## S1 — Visão Geral do Processo

O processo P08 representa a etapa final do ciclo de licenciamento: a **emissão do PRPCI** (Plano de Regularização e Proteção Contra Incêndio) e a consequente **liberação do APPCI** (Alvará de Prevenção e Proteção Contra Incêndio). É o único processo capaz de conduzir o licenciamento ao estado terminal `ALVARA_VIGENTE`.

O processo se divide em dois sub-fluxos mutuamente exclusivos, determinados pelo tipo de vistoria realizada no P07:

| Sub-processo | Gatilho (entrada) | Ator principal | Estado de saída |
|---|---|---|---|
| **P08-A — Emissão Normal** | `AGUARDANDO_PRPCI` (P07 vistoria definitiva/parcial aprovada) | Cidadão / Responsável Técnico (RT) | `ALVARA_VIGENTE` |
| **P08-B — Aceite de Renovação** | `AGUARDANDO_ACEITE_PRPCI` (P07 vistoria de renovação aprovada) | Responsável pelo Uso (RU) / Proprietário | `ALVARA_VIGENTE` |

**P08-A** exige que o RT faça o upload do documento PRPCI em PDF. O sistema valida o arquivo, persiste o documento no MinIO, registra a entidade `Prpci` e executa a transição de estado para `ALVARA_VIGENTE`, emitindo o APPCI.

**P08-B** dispensa o upload de documento: a vistoria de renovação já gerou os dados suficientes. O RU ou Proprietário concede o aceite eletrônico ao termo de vistoria. O sistema registra o aceite na entidade `Vistoria`, executa a transição de estado para `ALVARA_VIGENTE` e emite o APPCI de renovação.

Ambos os sub-fluxos encerram com a notificação por e-mail ao RT e ao RU.

---

## S2 — Stack Tecnológica

| Componente | Stack atual (Java EE) | Stack moderna (este documento) |
|---|---|---|
| Runtime | WildFly / JBoss · Java EE 7 | Spring Boot 3.3 · Java 21 |
| IoC / DI | CDI (`@Inject`, `@Qualifier`) | Spring IoC (`@Service`, `@Component`, `@Autowired`) |
| Camada de negócio | EJB `@Stateless` | `@Service` + `@Transactional` |
| Persistência | JPA/Hibernate · `@Stateless` BD class | Spring Data JPA · `JpaRepository` |
| Banco de dados | Oracle (sequences `CBM_ID_*_SEQ`) | PostgreSQL (sequences) |
| REST | JAX-RS (`@Path`, `@Consumes`) | Spring MVC (`@RestController`, `@RequestMapping`) |
| Upload multipart | `MultipartFormDataInput` (RESTEasy) | `MultipartFile` (Spring) |
| IdP / Autenticação | SOE PROCERGS (`meu.rs.gov.br`) | Keycloak local (JWT Bearer) |
| Autorização | `@Permissao` + CDI interceptor | `@PreAuthorize` (Spring Security + Keycloak) |
| Autorização envolvidos | `@AutorizaEnvolvido` + `SegurancaEnvolvidoInterceptor` | `@EnvolvidoAuthorization` + `EnvolvidoAuthorizationAspect` |
| ECM / Armazenamento | Alfresco (`workspace://SpacesStore/{UUID}`) | MinIO S3-compatible |
| Máquina de estados | CDI `@TrocaEstadoLicenciamentoQualifier` | `LicenciamentoStateTransitionService` |
| Conversão Boolean ↔ BD | `SimNaoBooleanConverter` (`'S'/'N'`) | JPA `Boolean` nativo (`true/false`) |
| Notificações | EJB assíncrono + JavaMail | Spring Mail (`JavaMailSender`) |
| Auditoria | Hibernate Envers (`@Audited`) | Spring Data Envers ou `@EntityListeners` |

---

## S3 — Enumerações

### 3.1 SituacaoLicenciamento (valores relevantes para P08)

```java
public enum SituacaoLicenciamento {

    // Situações de entrada para P08
    AGUARDANDO_PRPCI(26,
        "Aguardando envio do PRPCI pelo Responsável Técnico"),
    AGUARDANDO_ACEITE_PRPCI(27,
        "Aguardando aceite do PRPCI pelo Responsável pelo Uso ou Proprietário"),

    // Situação de saída (estado terminal do ciclo de licenciamento)
    ALVARA_VIGENTE(28,
        "Licenciamento com APPCI emitido e vigente");

    private final int codigo;
    private final String descricao;
}
```

> As situações acima são as únicas em que o P08 atua. Qualquer requisição recebida com situação diferente deve ser rejeitada com HTTP 422.

### 3.2 TipoMarco (marcos de auditoria registrados pelo P08)

```java
public enum TipoMarco {

    // P08-A — Emissão normal
    UPLOAD_PRPCI("Upload do documento PRPCI pelo RT"),
    LIBERACAO_APPCI("Emissão e liberação do APPCI ao licenciamento"),

    // P08-B — Aceite de renovação
    ACEITE_PRPCI("Aceite eletrônico do PRPCI pelo RU/Proprietário"),
    LIBERACAO_RENOV_APPCI("Emissão e liberação do APPCI de renovação");

    private final String descricao;
}
```

### 3.3 TipoArquivo (classificação do documento no MinIO)

```java
public enum TipoArquivo {
    PRPCI("Plano de Regularização e Proteção Contra Incêndio");
    // demais tipos omitidos — relevantes para outros processos
}
```

### 3.4 TrocaEstadoP08 (identificadores das transições de estado)

```java
public enum TrocaEstadoP08 {
    AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE,
    AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE
}
```

---

## S4 — Entidades JPA

### 4.1 Prpci

Representa um documento PRPCI associado a um licenciamento. Um licenciamento pode ter múltiplos arquivos PRPCI (re-uploads), mas apenas o conjunto do último upload ativo é considerado vigente.

```java
@Entity
@Table(name = "CBM_PRPCI")
@EntityListeners(AuditingEntityListener.class)
public class Prpci {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "prpci_seq")
    @SequenceGenerator(name = "prpci_seq",
                       sequenceName = "CBM_ID_PRPCI_SEQ",
                       allocationSize = 1)
    @Column(name = "NRO_INT_PRPCI")
    private Long id;

    /**
     * Referência ao arquivo armazenado no MinIO.
     * O campo objectKey contém o caminho completo no bucket MinIO,
     * equivalente ao identificadorAlfresco do sistema legado.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "NRO_INT_ARQUIVO", nullable = false)
    private Arquivo arquivo;

    /**
     * Localização do estabelecimento à época do upload.
     * Mantida para rastreabilidade histórica.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LOCALIZACAO")
    private Localizacao localizacao;

    /**
     * Licenciamento ao qual este PRPCI pertence.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @CreatedDate
    @Column(name = "DT_INCLUSAO", nullable = false, updatable = false)
    private LocalDateTime dataInclusao;

    @CreatedBy
    @Column(name = "NRO_INT_USUARIO_INCLUSAO", updatable = false)
    private Long idUsuarioInclusao;

    // getters e setters omitidos
}
```

### 4.2 Arquivo (entidade genérica de metadados de arquivo)

```java
@Entity
@Table(name = "CBM_ARQUIVO")
public class Arquivo {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "arquivo_seq")
    @SequenceGenerator(name = "arquivo_seq",
                       sequenceName = "CBM_ID_ARQUIVO_SEQ",
                       allocationSize = 1)
    @Column(name = "NRO_INT_ARQUIVO")
    private Long id;

    /**
     * Chave do objeto no MinIO.
     * Formato: "licenciamentos/{idLicenciamento}/prpci/{uuid}/{nomeOriginal}"
     * Equivalente ao identificadorAlfresco (nodeRef) do sistema legado.
     */
    @Column(name = "DSC_OBJECT_KEY", nullable = false, length = 500)
    private String objectKey;

    @Column(name = "DSC_NOME_ORIGINAL", nullable = false, length = 255)
    private String nomeOriginal;

    @Column(name = "DSC_CONTENT_TYPE", length = 100)
    private String contentType;

    @Column(name = "NRO_INT_TAMANHO_BYTES")
    private Long tamanhoBytes;

    @Enumerated(EnumType.STRING)
    @Column(name = "DSC_TIPO_ARQUIVO", nullable = false, length = 50)
    private TipoArquivo tipoArquivo;

    // getters e setters omitidos
}
```

### 4.3 Campos de aceite em Vistoria (P08-B)

Os campos abaixo são acrescentados à entidade `Vistoria` existente (definida no P07). Nenhuma nova entidade é criada para o aceite — ele é registrado diretamente na vistoria correspondente.

```java
// Campos adicionados à entidade Vistoria (definida no P07)

/**
 * ID do usuário (RU, Proprietário ou seus Procuradores) que executou o aceite.
 * Null enquanto o aceite ainda não foi concedido.
 */
@Column(name = "NRO_INT_USUARIO_ACEITE_PRPCI")
private Long idUsuarioAceitePrpci;

/**
 * Indica se o aceite foi concedido.
 * Em PostgreSQL armazenado como BOOLEAN nativo (true/false).
 * No sistema legado era VARCHAR(1) 'S'/'N' com SimNaoBooleanConverter.
 */
@Column(name = "IND_ACEITE_PRPCI")
private Boolean aceitePrpci;

/**
 * Data e hora em que o aceite foi concedido.
 */
@Column(name = "DT_ACEITE_PRPCI")
private LocalDateTime dataAceitePrpci;
```

---

## S5 — Repositórios Spring Data JPA

### 5.1 PrpciRepository

```java
@Repository
public interface PrpciRepository extends JpaRepository<Prpci, Long> {

    /**
     * Retorna todos os PRPCIs associados a um licenciamento,
     * ordenados por data de inclusão decrescente.
     */
    List<Prpci> findByLicenciamentoIdOrderByDataInclusaoDesc(Long idLicenciamento);

    /**
     * Retorna apenas a entidade Prpci (sem eager load de arquivo e localizacao).
     * Usada para verificações de existência.
     */
    boolean existsByLicenciamentoId(Long idLicenciamento);
}
```

### 5.2 ArquivoRepository

```java
@Repository
public interface ArquivoRepository extends JpaRepository<Arquivo, Long> {
    List<Arquivo> findByTipoArquivoAndLicenciamentoId(TipoArquivo tipo, Long idLicenciamento);
}
```

> Nota: a relação entre `Arquivo` e `Licenciamento` pode ser direta (FK `NRO_INT_LICENCIAMENTO`) ou indireta via `Prpci` — a implementação deve seguir o modelo de dados existente. Se indireta, a consulta deve ser via JOIN JPQL.

### 5.3 VistoriaRepository (extensão — P08)

```java
// Acrescenta ao VistoriaRepository existente (definido no P07):

/**
 * Retorna a vistoria ativa (aceitePrpci ainda null) para um licenciamento
 * em situação de renovação.
 */
Optional<Vistoria> findByLicenciamentoIdAndAceitePrpciIsNull(Long idLicenciamento);

/**
 * Verifica se já existe aceite para a vistoria informada.
 */
boolean existsByIdAndAceitePrpciTrue(Long idVistoria);
```

---

## S6 — Services

### 6.1 PrpciService (orquestrador principal)

```java
@Service
@Transactional
@RequiredArgsConstructor
public class PrpciService {

    private final PrpciRepository prpciRepository;
    private final ArquivoRepository arquivoRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final VistoriaRepository vistoriaRepository;
    private final MinioStorageService minioStorageService;
    private final PrpciValidationService validationService;
    private final LicenciamentoStateTransitionService stateTransitionService;
    private final MarcoService marcoService;
    private final PrpciNotificacaoService notificacaoService;
    private final EnvolvidoAuthorizationService envolvidoAuthorizationService;

    /**
     * P08-A — Emissão normal: RT faz upload do documento PRPCI.
     *
     * Pré-condições:
     *   - Licenciamento existe e está em AGUARDANDO_PRPCI
     *   - Usuário autenticado tem papel ROLE_RT ou ROLE_CIDADAO
     *   - Arquivo não é nulo e é PDF (content-type application/pdf)
     *   - Tamanho do arquivo <= 10 MB (configurável)
     *
     * Pós-condições:
     *   - Arquivo salvo no MinIO (bucket "prpci", key "licenciamentos/{id}/prpci/{uuid}/{nome}")
     *   - Entidade Arquivo persistida no banco
     *   - Entidade Prpci persistida com FK para Arquivo e Licenciamento
     *   - Marco UPLOAD_PRPCI registrado
     *   - Estado transicionado: AGUARDANDO_PRPCI → ALVARA_VIGENTE
     *   - Marco LIBERACAO_APPCI registrado
     *   - Notificação e-mail enviada ao RT e ao RU
     *
     * @param idLicenciamento ID do licenciamento
     * @param arquivo         Arquivo multipart enviado pelo RT
     * @param nomeOriginal    Nome original do arquivo
     * @param idUsuario       ID do usuário autenticado (extraído do JWT)
     */
    public void incluirPrpci(Long idLicenciamento,
                              MultipartFile arquivo,
                              String nomeOriginal,
                              Long idUsuario) {

        // 1. Carregar e validar licenciamento
        Licenciamento lic = licenciamentoRepository
            .findById(idLicenciamento)
            .orElseThrow(() -> new LicenciamentoNaoEncontradoException(idLicenciamento));

        validationService.validarSituacaoParaUpload(lic);
        validationService.validarArquivo(arquivo);

        // 2. Persistir arquivo no MinIO
        String objectKey = gerarObjectKey(idLicenciamento, nomeOriginal);
        minioStorageService.upload(objectKey, arquivo, "application/pdf");

        // 3. Persistir metadados do arquivo no banco
        Arquivo arquivoED = new Arquivo();
        arquivoED.setObjectKey(objectKey);
        arquivoED.setNomeOriginal(nomeOriginal);
        arquivoED.setContentType("application/pdf");
        arquivoED.setTamanhoBytes(arquivo.getSize());
        arquivoED.setTipoArquivo(TipoArquivo.PRPCI);
        arquivoRepository.save(arquivoED);

        // 4. Persistir entidade Prpci
        Prpci prpci = new Prpci();
        prpci.setArquivo(arquivoED);
        prpci.setLicenciamento(lic);
        prpci.setLocalizacao(lic.getLocalizacao());
        prpciRepository.save(prpci);

        // 5. Registrar marco UPLOAD_PRPCI
        marcoService.registrar(lic, TipoMarco.UPLOAD_PRPCI, idUsuario);

        // 6. Transicionar estado e registrar marco LIBERACAO_APPCI
        stateTransitionService.transicionar(
            lic,
            TrocaEstadoP08.AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE,
            idUsuario
        );
        // O StateTransitionService registra internamente o marco LIBERACAO_APPCI
        // e fecha o PeriodoSolicitacao.VISTORIA, se ainda aberto

        // 7. Notificar envolvidos
        notificacaoService.notificarConclusaoNormal(lic);
    }

    /**
     * P08-B — Aceite de renovação: RU/Proprietário concede aceite eletrônico.
     *
     * Pré-condições:
     *   - Licenciamento existe e está em AGUARDANDO_ACEITE_PRPCI
     *   - Vistoria informada existe e pertence ao licenciamento
     *   - Usuário autenticado é RU, Procurador de RU, Proprietário PF
     *     ou Procurador de Proprietário do licenciamento
     *   - APPCI do licenciamento existe (lista não vazia)
     *   - Aceite ainda não foi concedido para esta vistoria
     *
     * Pós-condições:
     *   - Vistoria atualizada: aceitePrpci=true, idUsuarioAceitePrpci, dataAceitePrpci=now()
     *   - Marco ACEITE_PRPCI registrado
     *   - Estado transicionado: AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE
     *   - Marco LIBERACAO_RENOV_APPCI registrado
     *   - Notificação e-mail enviada ao RT e ao RU
     *
     * @param idLicenciamento ID do licenciamento
     * @param idVistoria      ID da vistoria cuja renovação está sendo aceita
     * @param idUsuario       ID do usuário autenticado (extraído do JWT)
     */
    public void aceitarPrpci(Long idLicenciamento,
                              Long idVistoria,
                              Long idUsuario) {

        // 1. Carregar e validar licenciamento
        Licenciamento lic = licenciamentoRepository
            .findById(idLicenciamento)
            .orElseThrow(() -> new LicenciamentoNaoEncontradoException(idLicenciamento));

        validationService.validarSituacaoParaAceite(lic);

        // 2. Verificar autorização do envolvido
        envolvidoAuthorizationService.validarAceitePrpci(lic, idUsuario);

        // 3. Validar APPCI existente
        validationService.validarAppciExistente(lic);

        // 4. Carregar e validar vistoria
        Vistoria vistoria = vistoriaRepository
            .findById(idVistoria)
            .orElseThrow(() -> new VistoriaNaoEncontradaException(idVistoria));

        validationService.validarAceiteNaoRealizado(vistoria);

        // 5. Registrar aceite na vistoria
        vistoria.setAceitePrpci(true);
        vistoria.setIdUsuarioAceitePrpci(idUsuario);
        vistoria.setDataAceitePrpci(LocalDateTime.now());
        vistoriaRepository.save(vistoria);

        // 6. Registrar marco ACEITE_PRPCI
        marcoService.registrar(lic, TipoMarco.ACEITE_PRPCI, idUsuario);

        // 7. Transicionar estado e registrar marco LIBERACAO_RENOV_APPCI
        stateTransitionService.transicionar(
            lic,
            TrocaEstadoP08.AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE,
            idUsuario
        );

        // 8. Notificar envolvidos
        notificacaoService.notificarConclusaoRenovacao(lic);
    }

    /**
     * Verifica se o usuário autenticado pode conceder o aceite para o licenciamento.
     * Usado pelo frontend para habilitar/desabilitar o botão de aceite.
     *
     * @return true se: situacao == AGUARDANDO_ACEITE_PRPCI
     *               && APPCI existe
     *               && usuário é RU/Procurador RU/Proprietário PF/Procurador Proprietário
     */
    @Transactional(readOnly = true)
    public boolean verificarPermissaoAceite(Long idLicenciamento, Long idUsuario) {
        return licenciamentoRepository.findById(idLicenciamento)
            .map(lic -> {
                if (lic.getSituacao() != SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI) {
                    return false;
                }
                if (lic.getAppcis() == null || lic.getAppcis().isEmpty()) {
                    return false;
                }
                return envolvidoAuthorizationService.podeAceitarPrpci(lic, idUsuario);
            })
            .orElse(false);
    }

    @Transactional(readOnly = true)
    public List<Prpci> listarPorLicenciamento(Long idLicenciamento) {
        return prpciRepository.findByLicenciamentoIdOrderByDataInclusaoDesc(idLicenciamento);
    }

    private String gerarObjectKey(Long idLicenciamento, String nomeOriginal) {
        String uuid = UUID.randomUUID().toString();
        return String.format("licenciamentos/%d/prpci/%s/%s", idLicenciamento, uuid, nomeOriginal);
    }
}
```

### 6.2 LicenciamentoStateTransitionService (extensão — P08)

```java
// Transições específicas do P08 (acrescidas ao serviço existente do P07)

/**
 * AGUARDANDO_PRPCI → ALVARA_VIGENTE
 * Executado após upload do PRPCI pelo RT (P08-A).
 */
@Component("aguardandoPrpciParaAlvaraVigente")
public class AguardandoPrpciParaAlvaraVigenteTransition
        implements LicenciamentoStateTransition {

    private final MarcoService marcoService;
    private final PeriodoSolicitacaoService periodoSolicitacaoService;
    private final AppciService appciService;

    @Override
    public void executar(Licenciamento licenciamento, Long idUsuario) {
        // 1. Alterar situação
        licenciamento.setSituacao(SituacaoLicenciamento.ALVARA_VIGENTE);
        licenciamento.setDataAlteracao(LocalDateTime.now());

        // 2. Fechar período de solicitação de vistoria (se ainda aberto)
        periodoSolicitacaoService.fecharPeriodo(
            licenciamento, TipoPeriodo.VISTORIA, idUsuario);

        // 3. Registrar marco LIBERACAO_APPCI
        marcoService.registrar(licenciamento, TipoMarco.LIBERACAO_APPCI, idUsuario);

        // 4. Gerar/ativar APPCI
        appciService.emitirAppci(licenciamento, idUsuario);
    }

    @Override
    public SituacaoLicenciamento getSituacaoOrigem() {
        return SituacaoLicenciamento.AGUARDANDO_PRPCI;
    }

    @Override
    public SituacaoLicenciamento getSituacaoDestino() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;
    }
}

/**
 * AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE
 * Executado após aceite eletrônico do RU/Proprietário (P08-B).
 */
@Component("aguardandoAceitePrpciParaAlvaraVigente")
public class AguardandoAceitePrpciParaAlvaraVigenteTransition
        implements LicenciamentoStateTransition {

    private final MarcoService marcoService;
    private final AppciService appciService;

    @Override
    public void executar(Licenciamento licenciamento, Long idUsuario) {
        // 1. Alterar situação
        licenciamento.setSituacao(SituacaoLicenciamento.ALVARA_VIGENTE);
        licenciamento.setDataAlteracao(LocalDateTime.now());

        // 2. Registrar marco LIBERACAO_RENOV_APPCI
        marcoService.registrar(licenciamento, TipoMarco.LIBERACAO_RENOV_APPCI, idUsuario);

        // 3. Gerar/ativar APPCI de renovação
        appciService.emitirAppciRenovacao(licenciamento, idUsuario);
    }

    @Override
    public SituacaoLicenciamento getSituacaoOrigem() {
        return SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI;
    }

    @Override
    public SituacaoLicenciamento getSituacaoDestino() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;
    }
}
```

### 6.3 EnvolvidoAuthorizationService (extensão — P08-B)

```java
// Acrescido ao EnvolvidoAuthorizationService existente

/**
 * Verifica se o usuário pode conceder aceite do PRPCI.
 *
 * Perfis autorizados:
 *   1. RU (Responsável pelo Uso) do licenciamento
 *   2. Procurador do RU
 *   3. Proprietário Pessoa Física do estabelecimento
 *   4. Procurador do Proprietário Pessoa Física
 *
 * Nenhum RT, funcionário CBM-RS ou usuário sem vínculo pode aceitar.
 */
public boolean podeAceitarPrpci(Licenciamento licenciamento, Long idUsuario) {
    return isResponsavelPeloUso(licenciamento, idUsuario)
        || isProcuradorRU(licenciamento, idUsuario)
        || isProprietarioPF(licenciamento, idUsuario)
        || isProcuradorProprietario(licenciamento, idUsuario);
}

/**
 * Lança EnvolvidoNaoAutorizadoException se podeAceitarPrpci() retornar false.
 */
public void validarAceitePrpci(Licenciamento licenciamento, Long idUsuario) {
    if (!podeAceitarPrpci(licenciamento, idUsuario)) {
        throw new EnvolvidoNaoAutorizadoException(
            "Usuário " + idUsuario +
            " não tem permissão para aceitar o PRPCI do licenciamento " +
            licenciamento.getId());
    }
}
```

### 6.4 PrpciNotificacaoService

```java
@Service
@RequiredArgsConstructor
public class PrpciNotificacaoService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;    // Thymeleaf
    private final LicenciamentoRepository licenciamentoRepository;

    /**
     * Notifica RT e RU sobre a emissão normal do APPCI (P08-A).
     * Template: "email/prpci-conclusao-normal"
     */
    public void notificarConclusaoNormal(Licenciamento licenciamento) {
        enviarNotificacao(licenciamento, "email/prpci-conclusao-normal",
            "APPCI emitido — Licenciamento " + licenciamento.getNumeroPpci());
    }

    /**
     * Notifica RT e RU sobre a emissão do APPCI de renovação (P08-B).
     * Template: "email/prpci-conclusao-renovacao"
     */
    public void notificarConclusaoRenovacao(Licenciamento licenciamento) {
        enviarNotificacao(licenciamento, "email/prpci-conclusao-renovacao",
            "APPCI de renovação emitido — Licenciamento " + licenciamento.getNumeroPpci());
    }

    private void enviarNotificacao(Licenciamento lic, String template, String assunto) {
        // Coleta endereços de RT e RU a partir dos envolvidos do licenciamento
        List<String> destinatarios = coletarDestinatarios(lic);
        if (destinatarios.isEmpty()) return;

        Context ctx = new Context();
        ctx.setVariable("licenciamento", lic);
        ctx.setVariable("numeroPpci", lic.getNumeroPpci());
        String corpo = templateEngine.process(template, ctx);

        MimeMessage msg = mailSender.createMimeMessage();
        try {
            MimeMessageHelper helper = new MimeMessageHelper(msg, true, "UTF-8");
            helper.setTo(destinatarios.toArray(new String[0]));
            helper.setSubject(assunto);
            helper.setText(corpo, true);
            mailSender.send(msg);
        } catch (MessagingException e) {
            // Log e continua — notificação não deve impedir transação principal
            log.error("Falha ao enviar notificação P08 para licenciamento {}: {}",
                lic.getId(), e.getMessage());
        }
    }

    private List<String> coletarDestinatarios(Licenciamento lic) {
        // Extrai e-mail do RT e do RU via getEnvolvidos()
        // Implementação depende da estrutura de EnvolvidoED
        return lic.getEnvolvidos().stream()
            .map(env -> env.getUsuario().getEmail())
            .filter(StringUtils::hasText)
            .distinct()
            .toList();
    }
}
```

---

## S7 — Validações e Exceções

### 7.1 PrpciValidationService

```java
@Service
public class PrpciValidationService {

    private static final long TAMANHO_MAXIMO_BYTES = 10 * 1024 * 1024L; // 10 MB
    private static final List<String> CONTENT_TYPES_PERMITIDOS =
        List.of("application/pdf");

    /**
     * Valida que o licenciamento está em AGUARDANDO_PRPCI (P08-A).
     * @throws SituacaoLicenciamentoInvalidaException se estiver em outra situação.
     */
    public void validarSituacaoParaUpload(Licenciamento lic) {
        if (lic.getSituacao() != SituacaoLicenciamento.AGUARDANDO_PRPCI) {
            throw new SituacaoLicenciamentoInvalidaException(
                "Upload de PRPCI somente permitido na situação AGUARDANDO_PRPCI. " +
                "Situação atual: " + lic.getSituacao());
        }
    }

    /**
     * Valida que o licenciamento está em AGUARDANDO_ACEITE_PRPCI (P08-B).
     * @throws SituacaoLicenciamentoInvalidaException se estiver em outra situação.
     */
    public void validarSituacaoParaAceite(Licenciamento lic) {
        if (lic.getSituacao() != SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI) {
            throw new SituacaoLicenciamentoInvalidaException(
                "Aceite de PRPCI somente permitido na situação AGUARDANDO_ACEITE_PRPCI. " +
                "Situação atual: " + lic.getSituacao());
        }
    }

    /**
     * Valida o arquivo recebido para upload.
     * @throws ArquivoInvalidoException se nulo, vazio, grande demais ou tipo incorreto.
     */
    public void validarArquivo(MultipartFile arquivo) {
        if (arquivo == null || arquivo.isEmpty()) {
            throw new ArquivoInvalidoException("O arquivo PRPCI não pode ser nulo ou vazio.");
        }
        if (arquivo.getSize() > TAMANHO_MAXIMO_BYTES) {
            throw new ArquivoInvalidoException(
                "O arquivo excede o tamanho máximo permitido de 10 MB.");
        }
        String ct = arquivo.getContentType();
        if (!CONTENT_TYPES_PERMITIDOS.contains(ct)) {
            throw new ArquivoInvalidoException(
                "Tipo de arquivo inválido: " + ct + ". Somente PDF é aceito.");
        }
    }

    /**
     * Valida que o licenciamento possui pelo menos um APPCI emitido.
     * @throws AppciAusenteException se a lista de APPCIs estiver vazia ou nula.
     */
    public void validarAppciExistente(Licenciamento lic) {
        if (lic.getAppcis() == null || lic.getAppcis().isEmpty()) {
            throw new AppciAusenteException(
                "Licenciamento " + lic.getId() +
                " não possui APPCI. O aceite de PRPCI exige APPCI emitido.");
        }
    }

    /**
     * Valida que o aceite ainda não foi concedido para a vistoria informada.
     * @throws AceiteJaRealizadoException se aceitePrpci já for true.
     */
    public void validarAceiteNaoRealizado(Vistoria vistoria) {
        if (Boolean.TRUE.equals(vistoria.getAceitePrpci())) {
            throw new AceiteJaRealizadoException(
                "Aceite do PRPCI já foi concedido para a vistoria " + vistoria.getId());
        }
    }
}
```

### 7.2 Exceções de domínio

| Classe | HTTP Status | Código de erro |
|---|---|---|
| `LicenciamentoNaoEncontradoException` | 404 Not Found | `LICENCIAMENTO_NAO_ENCONTRADO` |
| `VistoriaNaoEncontradaException` | 404 Not Found | `VISTORIA_NAO_ENCONTRADA` |
| `SituacaoLicenciamentoInvalidaException` | 422 Unprocessable Entity | `SITUACAO_INVALIDA` |
| `ArquivoInvalidoException` | 400 Bad Request | `ARQUIVO_INVALIDO` |
| `AppciAusenteException` | 422 Unprocessable Entity | `APPCI_AUSENTE` |
| `AceiteJaRealizadoException` | 409 Conflict | `ACEITE_JA_REALIZADO` |
| `EnvolvidoNaoAutorizadoException` | 403 Forbidden | `ENVOLVIDO_NAO_AUTORIZADO` |
| `MinioStorageException` | 500 Internal Server Error | `ERRO_ARMAZENAMENTO` |

Todas as exceções devem ser interceptadas por um `@ControllerAdvice` global que retorna o seguinte envelope JSON:

```json
{
  "codigo": "SITUACAO_INVALIDA",
  "mensagem": "Upload de PRPCI somente permitido na situação AGUARDANDO_PRPCI. Situação atual: ANALISE_PENDENTE",
  "timestamp": "2026-03-11T14:32:00.000Z"
}
```

---

## S8 — REST Controllers

### 8.1 PrpciController

```java
@RestController
@RequestMapping("/api/prpci")
@RequiredArgsConstructor
@Tag(name = "P08 — PRPCI", description = "Emissão e aceite do PRPCI")
public class PrpciController {

    private final PrpciService prpciService;
    private final JwtService jwtService; // extrai idUsuario do token Keycloak

    /**
     * P08-A — Upload do documento PRPCI pelo RT.
     *
     * Roles permitidas: ROLE_RT, ROLE_CIDADAO
     * Requer: licenciamento em AGUARDANDO_PRPCI
     *
     * Método: PUT
     * Path:   /api/prpci/{idLicenciamento}
     * Body:   multipart/form-data com campo "arquivo" (PDF, max 10 MB)
     *
     * Resposta de sucesso: 204 No Content
     */
    @PutMapping(value = "/{idLicenciamento}",
                consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("hasAnyRole('RT', 'CIDADAO')")
    @Operation(summary = "Enviar documento PRPCI (P08-A — emissão normal)")
    @ApiResponse(responseCode = "204", description = "PRPCI enviado com sucesso")
    @ApiResponse(responseCode = "400", description = "Arquivo inválido")
    @ApiResponse(responseCode = "422", description = "Situação do licenciamento inválida")
    public ResponseEntity<Void> incluirPrpci(
            @PathVariable Long idLicenciamento,
            @RequestPart("arquivo") MultipartFile arquivo,
            Authentication authentication) {

        Long idUsuario = jwtService.extrairIdUsuario(authentication);
        prpciService.incluirPrpci(
            idLicenciamento,
            arquivo,
            arquivo.getOriginalFilename(),
            idUsuario
        );
        return ResponseEntity.noContent().build();
    }

    /**
     * P08-B — Aceite eletrônico do PRPCI pelo RU/Proprietário.
     *
     * Roles permitidas: ROLE_CIDADAO (RU ou Proprietário PF — validado no Service)
     * Requer: licenciamento em AGUARDANDO_ACEITE_PRPCI
     *
     * Método: PUT
     * Path:   /api/prpci/{idLicenciamento}/termo/{idVistoria}/aceite-prpci
     *
     * Resposta de sucesso: 204 No Content
     */
    @PutMapping("/{idLicenciamento}/termo/{idVistoria}/aceite-prpci")
    @PreAuthorize("hasRole('CIDADAO')")
    @Operation(summary = "Aceitar PRPCI (P08-B — renovação)")
    @ApiResponse(responseCode = "204", description = "Aceite registrado com sucesso")
    @ApiResponse(responseCode = "403", description = "Usuário não autorizado para este aceite")
    @ApiResponse(responseCode = "409", description = "Aceite já realizado")
    @ApiResponse(responseCode = "422", description = "Situação do licenciamento inválida")
    public ResponseEntity<Void> aceitarPrpci(
            @PathVariable Long idLicenciamento,
            @PathVariable Long idVistoria,
            Authentication authentication) {

        Long idUsuario = jwtService.extrairIdUsuario(authentication);
        prpciService.aceitarPrpci(idLicenciamento, idVistoria, idUsuario);
        return ResponseEntity.noContent().build();
    }

    /**
     * Consulta se o usuário autenticado pode conceder o aceite.
     * Usado pelo frontend para habilitar/desabilitar o botão de aceite.
     *
     * Roles permitidas: ROLE_CIDADAO
     *
     * Método: GET
     * Path:   /api/prpci/{idLicenciamento}/pode-aceite-prpci
     *
     * Resposta: { "podeAceitar": true | false }
     */
    @GetMapping("/{idLicenciamento}/pode-aceite-prpci")
    @PreAuthorize("hasRole('CIDADAO')")
    @Operation(summary = "Consultar permissão de aceite (P08-B)")
    public ResponseEntity<PodeAceitarPrpciResponse> consultarPermissaoAceite(
            @PathVariable Long idLicenciamento,
            Authentication authentication) {

        Long idUsuario = jwtService.extrairIdUsuario(authentication);
        boolean podeAceitar = prpciService.verificarPermissaoAceite(idLicenciamento, idUsuario);
        return ResponseEntity.ok(new PodeAceitarPrpciResponse(podeAceitar));
    }

    /**
     * Lista todos os PRPCIs de um licenciamento (para exibição no histórico).
     *
     * Roles permitidas: ROLE_RT, ROLE_CIDADAO, ROLE_FISCAL_CBM
     *
     * Método: GET
     * Path:   /api/prpci/{idLicenciamento}
     */
    @GetMapping("/{idLicenciamento}")
    @PreAuthorize("hasAnyRole('RT', 'CIDADAO', 'FISCAL_CBM', 'ADM_CBM')")
    @Operation(summary = "Listar PRPCIs de um licenciamento")
    public ResponseEntity<List<PrpciDTO>> listar(@PathVariable Long idLicenciamento) {
        List<Prpci> prpcis = prpciService.listarPorLicenciamento(idLicenciamento);
        return ResponseEntity.ok(PrpciMapper.toDtoList(prpcis));
    }
}
```

---

## S9 — DTOs

### 9.1 PrpciDTO (resposta de listagem)

```java
public record PrpciDTO(
    Long id,
    String nomeOriginalArquivo,
    String urlDownload,        // URL pré-assinada MinIO (validade: 1h)
    Long tamanhoBytes,
    LocalDateTime dataInclusao,
    Long idUsuarioInclusao
) {}
```

### 9.2 PodeAceitarPrpciResponse

```java
public record PodeAceitarPrpciResponse(boolean podeAceitar) {}
```

### 9.3 PrpciRelatorioDTO (para geração de relatórios e APPCI)

```java
public record PrpciRelatorioDTO(
    Long idLicenciamento,
    String numeroPpci,
    String nomeEstabelecimento,
    List<String> urlsArquivos,     // URLs pré-assinadas MinIO dos PRPCIs
    LocalDateTime dataEmissaoAppci,
    String tipoVistoria            // DEFINITIVA, PARCIAL ou RENOVACAO
) {}
```

### 9.4 PrpciMapper

```java
@Component
public class PrpciMapper {

    private final MinioStorageService minioStorageService;

    public PrpciDTO toDto(Prpci prpci) {
        String urlDownload = minioStorageService
            .gerarUrlPreAssinada(prpci.getArquivo().getObjectKey(), Duration.ofHours(1));
        return new PrpciDTO(
            prpci.getId(),
            prpci.getArquivo().getNomeOriginal(),
            urlDownload,
            prpci.getArquivo().getTamanhoBytes(),
            prpci.getDataInclusao(),
            prpci.getIdUsuarioInclusao()
        );
    }

    public static List<PrpciDTO> toDtoList(List<Prpci> prpcis) {
        // mapeamento via instância do @Component injetado
        return prpcis.stream().map(this::toDto).toList();
    }
}
```

---

## S10 — Segurança com Keycloak

### 10.1 Papéis (roles) utilizados pelo P08

| Role Keycloak | Descrição | Ações permitidas no P08 |
|---|---|---|
| `ROLE_RT` | Responsável Técnico cadastrado | Upload PRPCI (P08-A) · Listar PRPCIs |
| `ROLE_CIDADAO` | Cidadão/RU/Proprietário | Upload PRPCI (P08-A) · Aceite PRPCI (P08-B) · Consultar permissão aceite · Listar PRPCIs |
| `ROLE_FISCAL_CBM` | Fiscal do CBM-RS | Listar PRPCIs (somente leitura) |
| `ROLE_ADM_CBM` | Administrador do CBM-RS | Listar PRPCIs (somente leitura) |

### 10.2 Configuração do SecurityFilterChain (P08)

```java
// Acrescido ao SecurityConfig existente

http.authorizeHttpRequests(auth -> auth
    // P08-A — Upload PRPCI
    .requestMatchers(HttpMethod.PUT, "/api/prpci/{idLicenciamento}")
        .hasAnyRole("RT", "CIDADAO")
    // P08-B — Aceite
    .requestMatchers(HttpMethod.PUT,
        "/api/prpci/{idLicenciamento}/termo/{idVistoria}/aceite-prpci")
        .hasRole("CIDADAO")
    // Consulta permissão aceite
    .requestMatchers(HttpMethod.GET, "/api/prpci/{idLicenciamento}/pode-aceite-prpci")
        .hasRole("CIDADAO")
    // Listagem
    .requestMatchers(HttpMethod.GET, "/api/prpci/{idLicenciamento}")
        .hasAnyRole("RT", "CIDADAO", "FISCAL_CBM", "ADM_CBM")
);
```

### 10.3 Extração do ID do usuário a partir do JWT

```java
@Component
public class JwtService {

    /**
     * Extrai o ID interno do usuário do claim "sub" ou "userId" do token Keycloak.
     * O claim "userId" deve ser mapeado via Keycloak Client Scope como
     * o ID do usuário na tabela CBM_USUARIO.
     */
    public Long extrairIdUsuario(Authentication authentication) {
        Jwt jwt = (Jwt) authentication.getPrincipal();
        // Tenta claim customizado "userId" primeiro, depois "sub"
        Object userId = jwt.getClaim("userId");
        if (userId != null) {
            return Long.valueOf(userId.toString());
        }
        // Fallback: busca por sub (UUID Keycloak → resolve na tabela de usuários)
        String sub = jwt.getSubject();
        return usuarioRepository.findByKeycloakSub(sub)
            .map(Usuario::getId)
            .orElseThrow(() -> new UsuarioNaoEncontradoException(sub));
    }
}
```

### 10.4 Validação de envolvido (substituição do @AutorizaEnvolvido)

No sistema legado, `@AutorizaEnvolvido` + `SegurancaEnvolvidoInterceptor` validava que o usuário autenticado é um envolvido no licenciamento (RT, RU ou Proprietário).

Na stack moderna, essa lógica é centralizada em `EnvolvidoAuthorizationService` e chamada explicitamente nos métodos de serviço. Não há uso de interceptor CDI; o controle é declarativo via `@PreAuthorize` para papéis e programático via `EnvolvidoAuthorizationService` para vinculação ao licenciamento específico.

---

## S11 — Integração MinIO

### 11.1 MinioStorageService

```java
@Service
@RequiredArgsConstructor
public class MinioStorageService {

    private final MinioClient minioClient;

    @Value("${minio.bucket.prpci:prpci}")
    private String bucketPrpci;

    /**
     * Envia arquivo ao MinIO.
     *
     * @param objectKey   Chave do objeto (caminho no bucket)
     * @param arquivo     MultipartFile recebido pelo controller
     * @param contentType Content-Type (ex: "application/pdf")
     */
    public void upload(String objectKey, MultipartFile arquivo, String contentType) {
        try {
            // Garante que o bucket existe
            boolean bucketExists = minioClient.bucketExists(
                BucketExistsArgs.builder().bucket(bucketPrpci).build());
            if (!bucketExists) {
                minioClient.makeBucket(
                    MakeBucketArgs.builder().bucket(bucketPrpci).build());
            }

            minioClient.putObject(
                PutObjectArgs.builder()
                    .bucket(bucketPrpci)
                    .object(objectKey)
                    .stream(arquivo.getInputStream(), arquivo.getSize(), -1)
                    .contentType(contentType)
                    .build()
            );
        } catch (Exception e) {
            throw new MinioStorageException(
                "Falha ao armazenar PRPCI no MinIO: " + e.getMessage(), e);
        }
    }

    /**
     * Gera URL pré-assinada para download temporário.
     *
     * @param objectKey Chave do objeto no bucket
     * @param validade  Duração de validade da URL
     * @return URL pré-assinada HTTPS
     */
    public String gerarUrlPreAssinada(String objectKey, Duration validade) {
        try {
            return minioClient.getPresignedObjectUrl(
                GetPresignedObjectUrlArgs.builder()
                    .method(Method.GET)
                    .bucket(bucketPrpci)
                    .object(objectKey)
                    .expiry((int) validade.getSeconds(), TimeUnit.SECONDS)
                    .build()
            );
        } catch (Exception e) {
            throw new MinioStorageException(
                "Falha ao gerar URL pré-assinada para " + objectKey, e);
        }
    }

    /**
     * Remove arquivo do MinIO (usado em testes ou rollback manual).
     */
    public void remover(String objectKey) {
        try {
            minioClient.removeObject(
                RemoveObjectArgs.builder()
                    .bucket(bucketPrpci)
                    .object(objectKey)
                    .build()
            );
        } catch (Exception e) {
            throw new MinioStorageException(
                "Falha ao remover PRPCI do MinIO: " + e.getMessage(), e);
        }
    }
}
```

### 11.2 Configuração MinIO

```yaml
# application.yml
minio:
  endpoint: http://minio:9000
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket:
    prpci: prpci

spring:
  servlet:
    multipart:
      max-file-size: 10MB
      max-request-size: 12MB
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

---

## S12 — Notificações por E-mail

### 12.1 Templates Thymeleaf

**`email/prpci-conclusao-normal.html`** — notificação de emissão do APPCI (P08-A):
```html
<!-- Corpo do template — variáveis disponíveis: -->
<!-- licenciamento (objeto Licenciamento) -->
<!-- numeroPpci (String — número formatado do PPCI) -->
<p>O PRPCI do licenciamento <strong th:text="${numeroPpci}">A 00000361 AA 001</strong>
   foi enviado com sucesso.</p>
<p>O APPCI foi emitido e o licenciamento está agora com situação
   <strong>Alvará Vigente</strong>.</p>
```

**`email/prpci-conclusao-renovacao.html`** — notificação de aceite de renovação (P08-B):
```html
<p>O aceite do PRPCI de renovação do licenciamento
   <strong th:text="${numeroPpci}">A 00000361 AA 002</strong>
   foi registrado com sucesso.</p>
<p>O APPCI de renovação foi emitido e o licenciamento está agora com situação
   <strong>Alvará Vigente</strong>.</p>
```

### 12.2 Configuração SMTP

```yaml
spring:
  mail:
    host: ${SMTP_HOST:smtp.cbm.rs.gov.br}
    port: ${SMTP_PORT:587}
    username: ${SMTP_USER}
    password: ${SMTP_PASS}
    properties:
      mail.smtp.auth: true
      mail.smtp.starttls.enable: true
```

---

## S13 — Máquinas de Estado

### 13.1 SituacaoLicenciamento — transições do P08

```
        ┌──────────────────────────────────────────────────────────────┐
        │                    CICLO P08 — PRPCI                         │
        └──────────────────────────────────────────────────────────────┘

  [P07 NORMAL ENCERRA]           [P07 RENOVAÇÃO ENCERRA]
         │                                │
         ▼                                ▼
 ┌─────────────────┐          ┌───────────────────────┐
 │ AGUARDANDO_PRPCI│          │AGUARDANDO_ACEITE_PRPCI│
 │   (situação 26) │          │      (situação 27)    │
 └────────┬────────┘          └───────────┬───────────┘
          │                               │
          │  RT faz upload               │  RU/Prop concede aceite
          │  PUT /api/prpci/{id}         │  PUT /api/prpci/{id}/
          │  [arquivo PDF]                │  termo/{idVistoria}/
          │                               │  aceite-prpci
          │  Marcos:                      │
          │  - UPLOAD_PRPCI               │  Marcos:
          │  - LIBERACAO_APPCI            │  - ACEITE_PRPCI
          │                               │  - LIBERACAO_RENOV_APPCI
          ▼                               ▼
 ┌─────────────────────────────────────────────┐
 │               ALVARA_VIGENTE                │
 │                 (situação 28)               │
 │         [Estado TERMINAL do ciclo]          │
 └─────────────────────────────────────────────┘
```

### 13.2 StatusVistoria — campo aceitePrpci (P08-B)

```
VistoriaED.aceitePrpci:

  null  ──────────────────────────────────────►  true
  (antes do aceite)    aceite concedido pelo     (aceite registrado)
                       RU/Prop via P08-B
                       + idUsuarioAceitePrpci
                       + dataAceitePrpci = now()
```

### 13.3 Marcos de auditoria do P08

| Ordem | Marco | Sub-processo | Evento |
|---|---|---|---|
| 1 | `UPLOAD_PRPCI` | P08-A | RT envia documento PRPCI |
| 2 | `LIBERACAO_APPCI` | P08-A | Sistema emite APPCI e transiciona para ALVARA_VIGENTE |
| 3 | `ACEITE_PRPCI` | P08-B | RU/Prop concede aceite eletrônico |
| 4 | `LIBERACAO_RENOV_APPCI` | P08-B | Sistema emite APPCI de renovação e transiciona para ALVARA_VIGENTE |

---

## S14 — DDL PostgreSQL

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela CBM_ARQUIVO — metadados dos arquivos armazenados no MinIO
-- (equivale ao par ArquivoED + identificadorAlfresco do sistema legado)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE cbm_id_arquivo_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE cbm_arquivo (
    nro_int_arquivo        BIGINT        NOT NULL DEFAULT nextval('cbm_id_arquivo_seq'),
    dsc_object_key         VARCHAR(500)  NOT NULL,
    dsc_nome_original      VARCHAR(255)  NOT NULL,
    dsc_content_type       VARCHAR(100),
    nro_int_tamanho_bytes  BIGINT,
    dsc_tipo_arquivo       VARCHAR(50)   NOT NULL,  -- enum TipoArquivo
    dt_inclusao            TIMESTAMP     NOT NULL DEFAULT NOW(),
    nro_int_usuario_incl   BIGINT,
    CONSTRAINT pk_cbm_arquivo PRIMARY KEY (nro_int_arquivo)
);

COMMENT ON TABLE cbm_arquivo IS
    'Metadados de arquivos binários armazenados no MinIO. '
    'O conteúdo binário NUNCA é persistido no banco relacional.';
COMMENT ON COLUMN cbm_arquivo.dsc_object_key IS
    'Chave do objeto no bucket MinIO. Formato: licenciamentos/{id}/prpci/{uuid}/{nome}';


-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela CBM_PRPCI — documentos PRPCI associados a licenciamentos
-- ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE cbm_id_prpci_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE cbm_prpci (
    nro_int_prpci          BIGINT  NOT NULL DEFAULT nextval('cbm_id_prpci_seq'),
    nro_int_arquivo        BIGINT  NOT NULL,
    nro_int_localizacao    BIGINT,
    nro_int_licenciamento  BIGINT  NOT NULL,
    CONSTRAINT pk_cbm_prpci          PRIMARY KEY (nro_int_prpci),
    CONSTRAINT fk_prpci_arquivo      FOREIGN KEY (nro_int_arquivo)
                                     REFERENCES cbm_arquivo (nro_int_arquivo),
    CONSTRAINT fk_prpci_localizacao  FOREIGN KEY (nro_int_localizacao)
                                     REFERENCES cbm_localizacao (nro_int_localizacao),
    CONSTRAINT fk_prpci_licenciamento FOREIGN KEY (nro_int_licenciamento)
                                     REFERENCES cbm_licenciamento (nro_int_licenciamento)
);

COMMENT ON TABLE cbm_prpci IS
    'Documentos PRPCI (Plano de Regularização e Proteção Contra Incêndio) '
    'associados ao licenciamento. Um licenciamento pode ter múltiplos registros '
    '(re-uploads), sendo o mais recente o vigente.';


-- ─────────────────────────────────────────────────────────────────────────────
-- Campos de aceite PRPCI na tabela CBM_VISTORIA (alteração — P08-B)
-- Executar apenas se a tabela já foi criada sem estes campos (migração Flyway)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE cbm_vistoria
    ADD COLUMN IF NOT EXISTS nro_int_usuario_aceite_prpci  BIGINT,
    ADD COLUMN IF NOT EXISTS ind_aceite_prpci              BOOLEAN,
    ADD COLUMN IF NOT EXISTS dt_aceite_prpci               TIMESTAMP;

COMMENT ON COLUMN cbm_vistoria.nro_int_usuario_aceite_prpci IS
    'ID do usuário (RU, Proprietário ou Procurador) que concedeu o aceite do PRPCI.';
COMMENT ON COLUMN cbm_vistoria.ind_aceite_prpci IS
    'Indica se o aceite eletrônico do PRPCI foi concedido. '
    'No legado: VARCHAR(1) ''S''/''N'' com SimNaoBooleanConverter.';
COMMENT ON COLUMN cbm_vistoria.dt_aceite_prpci IS
    'Data e hora em que o aceite do PRPCI foi concedido.';


-- ─────────────────────────────────────────────────────────────────────────────
-- Índices de desempenho
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX idx_prpci_licenciamento
    ON cbm_prpci (nro_int_licenciamento);

CREATE INDEX idx_arquivo_tipo
    ON cbm_arquivo (dsc_tipo_arquivo);


-- ─────────────────────────────────────────────────────────────────────────────
-- Script de migração Flyway sugerido
-- Arquivo: V008__prpci_aceite.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- (Contém todos os comandos acima na ordem correta)
```

---

## S15 — Resumo dos Dois Fluxos Completos

### Fluxo P08-A — Emissão Normal (AGUARDANDO_PRPCI → ALVARA_VIGENTE)

```
1. Pré-condição:
   - P07 (vistoria definitiva ou parcial) foi aprovado e homologado pelo ADM CBM-RS
   - LicenciamentoStateTransition P07→P08 colocou situação = AGUARDANDO_PRPCI

2. Ator: Responsável Técnico (ROLE_RT) ou Cidadão (ROLE_CIDADAO)

3. Passos:
   3.1 RT acessa o painel do licenciamento no frontend Angular
   3.2 RT seleciona o arquivo PDF do PRPCI (max 10 MB)
   3.3 Frontend POST multipart: PUT /api/prpci/{idLicenciamento}
       Header: Authorization: Bearer <token_keycloak_jwt>
       Body:   multipart/form-data  campo "arquivo" = PDF

   3.4 PrpciController recebe requisição
       - Extrai idUsuario do JWT via JwtService
       - Chama prpciService.incluirPrpci(idLicenciamento, arquivo, nome, idUsuario)

   3.5 PrpciService executa:
       a) Carrega Licenciamento — 404 se não existir
       b) Valida situação == AGUARDANDO_PRPCI — 422 se diferente
       c) Valida arquivo (nulo/vazio, tamanho, content-type) — 400 se inválido
       d) Gera objectKey: "licenciamentos/{id}/prpci/{uuid}/{nome}"
       e) minioStorageService.upload(objectKey, arquivo, "application/pdf")
       f) Persiste Arquivo no banco (INSERT cbm_arquivo)
       g) Persiste Prpci no banco (INSERT cbm_prpci)
       h) marcoService.registrar(lic, UPLOAD_PRPCI, idUsuario)
       i) stateTransitionService.transicionar(lic,
             AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE, idUsuario):
             - lic.setSituacao(ALVARA_VIGENTE)
             - periodoSolicitacaoService.fecharPeriodo(VISTORIA)
             - marcoService.registrar(lic, LIBERACAO_APPCI, idUsuario)
             - appciService.emitirAppci(lic, idUsuario)
       j) notificacaoService.notificarConclusaoNormal(lic)
          → e-mail ao RT e RU com template "prpci-conclusao-normal"

   3.6 Resposta: HTTP 204 No Content

4. Estado final: ALVARA_VIGENTE
```

---

### Fluxo P08-B — Aceite de Renovação (AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE)

```
1. Pré-condição:
   - P07 (vistoria de RENOVAÇÃO) foi aprovado e homologado pelo ADM CBM-RS
   - LicenciamentoStateTransition P07→P08 colocou situação = AGUARDANDO_ACEITE_PRPCI
   - APPCI de renovação foi previamente emitido (lista licenciamento.getAppcis() não vazia)

2. Ator: RU (Responsável pelo Uso), Procurador do RU, Proprietário PF
         ou Procurador do Proprietário (todos ROLE_CIDADAO)

3. Passos:
   3.1 Usuário acessa painel do licenciamento no frontend Angular
   3.2 Frontend consulta: GET /api/prpci/{idLicenciamento}/pode-aceite-prpci
       - Retorna { "podeAceitar": true } se condições atendidas
       - Frontend habilita botão "Aceitar PRPCI"

   3.3 Usuário clica "Aceitar PRPCI"
   3.4 Frontend envia: PUT /api/prpci/{idLicenciamento}/termo/{idVistoria}/aceite-prpci
       Header: Authorization: Bearer <token_keycloak_jwt>

   3.5 PrpciController recebe requisição
       - Extrai idUsuario do JWT
       - Chama prpciService.aceitarPrpci(idLicenciamento, idVistoria, idUsuario)

   3.6 PrpciService executa:
       a) Carrega Licenciamento — 404 se não existir
       b) Valida situação == AGUARDANDO_ACEITE_PRPCI — 422 se diferente
       c) envolvidoAuthorizationService.validarAceitePrpci(lic, idUsuario)
          → verifica isRU || isProcRU || isPropPF || isProcProp
          → lança EnvolvidoNaoAutorizadoException (403) se inválido
       d) validationService.validarAppciExistente(lic) — 422 se APPCI ausente
       e) Carrega Vistoria — 404 se não existir
       f) validationService.validarAceiteNaoRealizado(vistoria) — 409 se já aceito
       g) vistoria.setAceitePrpci(true)
          vistoria.setIdUsuarioAceitePrpci(idUsuario)
          vistoria.setDataAceitePrpci(LocalDateTime.now())
          vistoriaRepository.save(vistoria)
       h) marcoService.registrar(lic, ACEITE_PRPCI, idUsuario)
       i) stateTransitionService.transicionar(lic,
             AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE, idUsuario):
             - lic.setSituacao(ALVARA_VIGENTE)
             - marcoService.registrar(lic, LIBERACAO_RENOV_APPCI, idUsuario)
             - appciService.emitirAppciRenovacao(lic, idUsuario)
       j) notificacaoService.notificarConclusaoRenovacao(lic)
          → e-mail ao RT e RU com template "prpci-conclusao-renovacao"

   3.7 Resposta: HTTP 204 No Content

4. Estado final: ALVARA_VIGENTE
```

---



---

## Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (Demandas 17, 32).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P08.

---

### RN-P08-N1 — Upload de Múltiplos Arquivos no PRPCI 🟠 P08-M1

**Prioridade:** Alta  
**Origem:** Demanda 32 — Sprint 04 Hammer

**Descrição:** O P08-A atualmente aceita apenas **um único arquivo** de PRPCI. O sistema deve ser atualizado para aceitar **múltiplos arquivos** (laudos técnicos, documentos complementares, anexos), com possibilidade de adicionar, remover e visualizar cada arquivo individualmente.

**Mudança na UserTask `P08_T02_RT_Upload`:**

A tela de upload deve exibir:
- Lista de arquivos já adicionados com nome, tamanho e data
- Botão "Adicionar arquivo" (selecionar novo arquivo)
- Botão "Visualizar" por arquivo (abre preview)
- Botão "Remover" por arquivo (remove da lista — com confirmação)

**Mudança no modelo de dados:**

```sql
-- ANTES: um arquivo por PRPCI
ALTER TABLE cbm_prpci DROP COLUMN IF EXISTS id_arquivo_alfresco;

-- DEPOIS: lista de arquivos por PRPCI
CREATE TABLE cbm_prpci_arquivo (
    id BIGSERIAL PRIMARY KEY,
    id_prpci BIGINT NOT NULL REFERENCES cbm_prpci(id),
    nm_arquivo VARCHAR(255) NOT NULL,
    ds_tipo VARCHAR(50) NOT NULL
        CHECK (ds_tipo IN ('PRPCI_PRINCIPAL','LAUDO_COMPLEMENTAR','ANEXO')),
    ds_path_storage VARCHAR(500) NOT NULL,  -- path no MinIO/S3
    nr_tamanho_bytes BIGINT NOT NULL,
    dt_upload TIMESTAMP NOT NULL DEFAULT NOW(),
    id_usuario_upload BIGINT REFERENCES cbm_usuario(id)
);
```

**Novos endpoints:**

```
POST /api/v1/prpcis/{id}/arquivos
Content-Type: multipart/form-data
→ Adiciona um arquivo ao PRPCI

GET /api/v1/prpcis/{id}/arquivos
→ Lista todos os arquivos do PRPCI

DELETE /api/v1/prpcis/{id}/arquivos/{idArquivo}
→ Remove um arquivo (apenas enquanto PRPCI não enviado)

GET /api/v1/prpcis/{id}/arquivos/{idArquivo}/download
→ Download do arquivo
```

**Implementação — MinIO/S3:**

```java
// PrpciArquivoService.java
public PrpciArquivo adicionarArquivo(UUID idPrpci, MultipartFile file, TipoArquivoPrpci tipo) {
    String path = String.format("prpcis/%s/%s/%s", idPrpci, tipo.name(), UUID.randomUUID());
    storageService.upload(path, file.getInputStream(), file.getContentType());
    
    PrpciArquivo arquivo = new PrpciArquivo();
    arquivo.setIdPrpci(idPrpci);
    arquivo.setNmArquivo(file.getOriginalFilename());
    arquivo.setDsTipo(tipo);
    arquivo.setDsPathStorage(path);
    arquivo.setNrTamanhoBytes(file.getSize());
    return prpciArquivoRepository.save(arquivo);
}
```

**Validações:**
- Tamanho máximo por arquivo: 50MB
- Tipos aceitos: PDF, DWG, PNG, JPG
- Mínimo de 1 arquivo obrigatório para envio do PRPCI
- Remoção de arquivo bloqueada após PRPCI enviado (`status != RASCUNHO`)

**Critérios de Aceitação:**
- [ ] CA-P08-N1a: RT pode adicionar múltiplos arquivos ao PRPCI antes do envio
- [ ] CA-P08-N1b: Cada arquivo pode ser visualizado individualmente (preview/download)
- [ ] CA-P08-N1c: RT pode remover arquivo enquanto PRPCI em `RASCUNHO`
- [ ] CA-P08-N1d: Tentativa de remover arquivo após envio retorna 422
- [ ] CA-P08-N1e: PRPCI sem nenhum arquivo não pode ser enviado (validação 422)
- [ ] CA-P08-N1f: Arquivos armazenados no path `prpcis/{id}/{tipo}/{uuid}` no MinIO/S3

---

### RN-P08-N2 — Revisão das Permissões para Aceite do Anexo D 🟡 P08-M2

**Prioridade:** Média  
**Origem:** Demanda 17 — Sprint 02 Hammer

**Descrição:** As regras de permissão para aceite do **Anexo D** devem ser revisadas. Atualmente apenas o RT com tipo de responsabilidade "Renovação de APPCI" pode aceitar o Anexo D. Proprietário ou RU também devem poder dar o aceite em determinadas situações.

**Regra de autorização atualizada:**

```java
// AnexoDService.java
public boolean podeAceitarAnexoD(UUID idLicenciamento, UUID idUsuario) {
    Envolvido envolvido = envolvidoRepository
        .findByIdLicenciamentoAndIdUsuario(idLicenciamento, idUsuario)
        .orElseThrow(() -> new ForbiddenException("Usuário não é envolvido neste licenciamento"));
    
    return switch (envolvido.getTpPerfil()) {
        case RT_RENOVACAO   -> true;  // sempre pode
        case PROPRIETARIO   -> true;  // pode aceitar Anexo D
        case RU             -> licenciamentoService.proprietarioAusenteOuInativo(idLicenciamento);
        default             -> false;
    };
}
```

**Cenários permitidos:**

| Perfil | Pode aceitar Anexo D? | Condição |
|--------|----------------------|----------|
| RT com responsabilidade "Renovação de APPCI" | ✅ Sim | Sempre |
| Proprietário | ✅ Sim | Sempre |
| Responsável pelo Uso (RU) | ✅ Sim | Quando Proprietário ausente/inativo |
| Outros perfis | ❌ Não | — |

**Atualização da anotação:**
```java
@PostMapping("/{id}/aceite-anexo-d")
@PreAuthorize("@anexoDSecurity.podeAceitar(#id, authentication.principal.id)")
public ResponseEntity<Void> aceitarAnexoD(@PathVariable UUID id) {
    anexoDService.registrarAceite(id, securityContext.getUsuarioLogado().getId());
    return ResponseEntity.noContent().build();
}
```

**Critérios de Aceitação:**
- [ ] CA-P08-N2a: RT com responsabilidade "Renovação de APPCI" pode aceitar o Anexo D
- [ ] CA-P08-N2b: Proprietário pode aceitar o Anexo D em qualquer situação
- [ ] CA-P08-N2c: RU pode aceitar o Anexo D quando Proprietário está ausente/inativo
- [ ] CA-P08-N2d: Outros perfis recebem 403 ao tentar aceitar o Anexo D

---

### Resumo das Mudanças P08 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P08-M1 | RN-P08-N1 | Upload de múltiplos arquivos no PRPCI (substituição de campo único por lista) | 🟠 Alta |
| P08-M2 | RN-P08-N2 | Revisão de permissões para aceite do Anexo D (Proprietário e RU incluídos) | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 02–04*

*Documento gerado para o Projeto SOL — CBM-RS. Versão referenciada: código-fonte SOLCBM.BackEnd16-06. Stack de destino: Spring Boot 3.3 / Java 21 / Keycloak / MinIO / PostgreSQL.*
