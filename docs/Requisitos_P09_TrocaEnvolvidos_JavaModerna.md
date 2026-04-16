# Requisitos P09 — Troca de Envolvidos (Substituição do Responsável Técnico)
## Stack Java Moderna — Sem Dependência PROCERGS

> Documento de requisitos destinado à equipe de desenvolvimento.
> Stack-alvo: **Spring Boot 3.x · Spring Security · Keycloak (OIDC/OAuth2) · PostgreSQL · MinIO · Jakarta EE 10 APIs**.
> Nenhuma dependência do SOE PROCERGS, WildFly ou Alfresco — todas as responsabilidades equivalentes
> são mapeadas para tecnologias de mercado abertas.

---

## S1 — Visão Geral do Processo

O processo P09 permite substituir o **Responsável Técnico (RT)** vinculado a um licenciamento ativo.
A troca é necessária quando o RT original não pode mais exercer a função
(rescisão de contrato, impedimento legal, morte, desistência), e o estabelecimento precisa de
um novo profissional habilitado para continuar responsável pelo PPCI (Plano de Prevenção e
Proteção Contra Incêndio).

O processo envolve **três atores** com papéis distintos:

| Ator | Papel no Processo |
|---|---|
| **Solicitante** (RU ou Proprietário) | Inicia a troca, seleciona o novo RT |
| **RT Atual** | Deve autorizar formalmente a saída do processo |
| **Novo RT** | Deve aceitar formalmente a entrada e assumir responsabilidade técnica |

O fluxo utiliza **aceites paralelos obrigatórios**: somente após ambos os RTs (saindo e entrando)
confirmarem é que a troca é efetivada. Se qualquer um recusar, a troca é cancelada e o RT
original permanece vinculado.

### Restrições de Escopo

- Permitido apenas para licenciamentos do tipo **PPCI** ou **PSPCIM**.
- Proibido quando há outra troca de envolvido já em andamento para o mesmo licenciamento.
- Proibido durante fases de análise técnica, vistoria em andamento, ou recurso administrativo ativo.
- O novo RT deve ter registro ativo no CREA/CAU validado pela integração com a API de conselhos profissionais.

### Estados do Licenciamento no P09

| Situação | Descrição |
|---|---|
| `AGUARDANDO_ACEITE_TROCA_ENVOLVIDO` | Troca solicitada — aguardando autorizações dos dois RTs |
| *(situação anterior mantida)* | Se troca cancelada, situação volta ao valor pré-troca |

---

## S2 — Modelo de Dados

### 2.1 Entidade `TrocaEnvolvido`

Tabela: **`sol_troca_envolvido`**

```java
@Entity
@Table(name = "sol_troca_envolvido")
public class TrocaEnvolvido {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Licenciamento ao qual esta troca de RT se aplica.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    /**
     * RT que está saindo do licenciamento.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_rt_atual", nullable = false)
    private ResponsavelTecnico rtAtual;

    /**
     * RT que está sendo proposto como substituto.
     */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_rt_novo", nullable = false)
    private ResponsavelTecnico rtNovo;

    /**
     * Situação atual da solicitação de troca.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 40)
    private StatusTrocaEnvolvido status;

    /**
     * Usuário que solicitou a troca (RU ou Proprietário autenticado no Keycloak).
     */
    @Column(name = "id_usuario_solicitante", nullable = false)
    private String idUsuarioSolicitante; // subject do token JWT (UUID Keycloak)

    /**
     * Indica se o RT atual autorizou a saída.
     * Null = ainda não respondeu; true = autorizou; false = recusou.
     */
    @Column(name = "aceite_rt_atual")
    private Boolean aceiteRtAtual;

    /**
     * Data/hora em que o RT atual respondeu.
     */
    @Column(name = "dth_aceite_rt_atual")
    private OffsetDateTime dthAceiteRtAtual;

    /**
     * Indica se o novo RT autorizou a entrada.
     * Null = ainda não respondeu; true = autorizou; false = recusou.
     */
    @Column(name = "aceite_rt_novo")
    private Boolean aceiteRtNovo;

    /**
     * Data/hora em que o novo RT respondeu.
     */
    @Column(name = "dth_aceite_rt_novo")
    private OffsetDateTime dthAceiteRtNovo;

    /**
     * Data/hora da criação da solicitação.
     */
    @Column(name = "dth_criacao", nullable = false)
    private OffsetDateTime dthCriacao;

    /**
     * Data/hora em que a troca foi efetivada ou cancelada.
     */
    @Column(name = "dth_conclusao")
    private OffsetDateTime dthConclusao;

    /**
     * Motivo informado pelo RT que recusou (quando aplicável).
     */
    @Column(name = "motivo_recusa", length = 500)
    private String motivoRecusa;

    /**
     * Situação do licenciamento antes da troca (usada para reversão em caso de cancelamento).
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_licenciamento_anterior", length = 80)
    private SituacaoLicenciamento situacaoAnterior;
}
```

**DDL PostgreSQL:**

```sql
CREATE TABLE sol_troca_envolvido (
    id                              BIGSERIAL PRIMARY KEY,
    id_licenciamento                BIGINT        NOT NULL REFERENCES sol_licenciamento(id),
    id_rt_atual                     BIGINT        NOT NULL REFERENCES sol_responsavel_tecnico(id),
    id_rt_novo                      BIGINT        NOT NULL REFERENCES sol_responsavel_tecnico(id),
    status                          VARCHAR(40)   NOT NULL DEFAULT 'SOLICITADO',
    id_usuario_solicitante          VARCHAR(36)   NOT NULL,  -- UUID Keycloak
    aceite_rt_atual                 BOOLEAN,
    dth_aceite_rt_atual             TIMESTAMPTZ,
    aceite_rt_novo                  BOOLEAN,
    dth_aceite_rt_novo              TIMESTAMPTZ,
    dth_criacao                     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    dth_conclusao                   TIMESTAMPTZ,
    motivo_recusa                   VARCHAR(500),
    situacao_licenciamento_anterior VARCHAR(80),
    CONSTRAINT uq_troca_lic_ativa   UNIQUE (id_licenciamento, status)
    -- A constraint UNIQUE garante que só pode haver UMA troca SOLICITADO por licenciamento
    -- (derruba-se parcialmente via partial index — ver abaixo)
);

-- Permite apenas 1 troca SOLICITADO ativa por licenciamento
CREATE UNIQUE INDEX idx_troca_ativa
    ON sol_troca_envolvido (id_licenciamento)
    WHERE status = 'SOLICITADO';
```

---

### 2.2 Entidade `ResponsavelTecnico` — campos relevantes ao P09

```java
@Entity
@Table(name = "sol_responsavel_tecnico")
public class ResponsavelTecnico {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** CPF do profissional — usado para busca na API CREA/CAU */
    @Column(name = "cpf", nullable = false, length = 11, unique = true)
    private String cpf;

    /** Número de registro profissional (CREA ou CAU) */
    @Column(name = "nro_registro_profissional", length = 30)
    private String nroRegistroProfissional;

    /** Conselho profissional: CREA ou CAU */
    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_conselho", length = 10)
    private TipoConselho tipoConselho;

    /** Indicador de situação ativa no conselho (atualizado via integração) */
    @Column(name = "ind_habilitado")
    private Boolean indHabilitado;

    /** Data da última verificação de habilitação junto ao conselho */
    @Column(name = "dth_verificacao_habilitacao")
    private OffsetDateTime dthVerificacaoHabilitacao;

    /** Nome completo do profissional */
    @Column(name = "nome", nullable = false, length = 200)
    private String nome;

    /** E-mail para notificações */
    @Column(name = "email", length = 200)
    private String email;
}
```

---

### 2.3 Entidade `Licenciamento` — campos relevantes ao P09

```java
// Campos adicionados/relevantes na entidade Licenciamento para P09:

/** Tipo do licenciamento — apenas PPCI e PSPCIM permitem troca de RT */
@Enumerated(EnumType.STRING)
@Column(name = "tipo_licenciamento", nullable = false, length = 30)
private TipoLicenciamento tipoLicenciamento;

/** Situação atual — alterada para AGUARDANDO_ACEITE_TROCA_ENVOLVIDO durante P09 */
@Enumerated(EnumType.STRING)
@Column(name = "situacao", nullable = false, length = 80)
private SituacaoLicenciamento situacao;

/** RT atualmente vinculado ao licenciamento */
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "id_responsavel_tecnico")
private ResponsavelTecnico responsavelTecnico;
```

---

## S3 — Enumerações

```java
/** Status da solicitação de troca de envolvido */
public enum StatusTrocaEnvolvido {
    SOLICITADO,       // Troca iniciada — aguardando aceites
    EFETIVADO,        // Ambos os RTs confirmaram — troca concluída
    CANCELADO,        // Recusa de um dos RTs ou cancelamento pelo solicitante
    CANCELADO_ADM     // Cancelado administrativamente pelo CBM-RS
}

/** Tipos de licenciamento que aceitam troca de RT */
public enum TipoLicenciamento {
    PPCI,             // Plano de Prevenção e Proteção Contra Incêndio
    PSPCIM,           // Plano de Segurança Preventiva Contra Incêndio e Movimentação
    FACT              // Formulário de Atendimento e Consulta Técnica (NÃO permite troca)
}

/** Conselho profissional do RT */
public enum TipoConselho {
    CREA,   // Conselho Regional de Engenharia e Agronomia
    CAU     // Conselho de Arquitetura e Urbanismo
}

/** Situações do Licenciamento relevantes para P09 */
public enum SituacaoLicenciamento {
    // ... demais situações omitidas ...
    AGUARDANDO_ACEITE_TROCA_ENVOLVIDO,  // P09 — aguardando aceites do RT atual e novo RT
    ALVARA_VIGENTE,                      // Situações a partir das quais P09 é permitido
    AGUARDANDO_PRPCI,
    AGUARDANDO_ACEITE_PRPCI,
    CA,
    // Situações que BLOQUEIAM P09:
    RASCUNHO,
    AGUARDANDO_ACEITE,
    AGUARDANDO_PAGAMENTO,
    EM_ANALISE,
    EM_VISTORIA,
    RECURSO_EM_ANALISE_1_CIA,
    RECURSO_EM_ANALISE_2_CIA,
    RECURSO_EM_ANALISE_1_CIV,
    RECURSO_EM_ANALISE_2_CIV,
    EXTINGUIDO
}

/** Marcos de auditoria do P09 */
public enum TipoMarco {
    // ... demais marcos omitidos ...
    SOLICITACAO_TROCA_ENVOLVIDO,    // Troca solicitada
    ACEITE_TROCA_ENVOLVIDO_RT_ATUAL,// RT atual autorizou saída
    ACEITE_TROCA_ENVOLVIDO_RT_NOVO, // Novo RT autorizou entrada
    RECUSA_TROCA_ENVOLVIDO,         // Um dos RTs recusou
    EFETIVACAO_TROCA_ENVOLVIDO,     // Troca efetivada com sucesso
    CANCELAMENTO_TROCA_ENVOLVIDO    // Troca cancelada (solicitante ou adm)
}
```

---

## S4 — Regras de Negócio

### RN01 — Tipo de licenciamento obrigatoriamente PPCI ou PSPCIM

```java
public void validarTipoLicenciamento(Licenciamento lic) {
    if (!EnumSet.of(TipoLicenciamento.PPCI, TipoLicenciamento.PSPCIM)
                .contains(lic.getTipoLicenciamento())) {
        throw new TrocaEnvolvidoException(
            "P09-RN01: Troca de RT permitida apenas para licenciamentos " +
            "do tipo PPCI ou PSPCIM. Tipo atual: " + lic.getTipoLicenciamento());
    }
}
```

### RN02 — Situação do licenciamento deve ser compatível com troca

```java
private static final Set<SituacaoLicenciamento> SITUACOES_BLOQUEADAS_P09 = EnumSet.of(
    SituacaoLicenciamento.RASCUNHO,
    SituacaoLicenciamento.AGUARDANDO_ACEITE,
    SituacaoLicenciamento.AGUARDANDO_PAGAMENTO,
    SituacaoLicenciamento.EM_ANALISE,
    SituacaoLicenciamento.EM_VISTORIA,
    SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIA,
    SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIA,
    SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIV,
    SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIV,
    SituacaoLicenciamento.EXTINGUIDO,
    SituacaoLicenciamento.AGUARDANDO_ACEITE_TROCA_ENVOLVIDO
);

public void validarSituacaoPermiteTrioca(Licenciamento lic) {
    if (SITUACOES_BLOQUEADAS_P09.contains(lic.getSituacao())) {
        throw new TrocaEnvolvidoException(
            "P09-RN02: Não é possível solicitar troca de RT quando o " +
            "licenciamento está na situação: " + lic.getSituacao());
    }
}
```

### RN03 — Não pode haver troca já em andamento para o mesmo licenciamento

```java
public void validarNaoExisteTrocaAtiva(Long idLicenciamento) {
    boolean existeAtiva = trocaEnvolvidoRepository
        .existsByLicenciamentoIdAndStatus(idLicenciamento, StatusTrocaEnvolvido.SOLICITADO);
    if (existeAtiva) {
        throw new TrocaEnvolvidoException(
            "P09-RN03: Já existe uma solicitação de troca de RT ativa " +
            "para este licenciamento. Conclua ou cancele a troca anterior.");
    }
}
```

### RN04 — Novo RT deve ser diferente do RT atual

```java
public void validarRtsDiferentes(Long idRtAtual, Long idRtNovo) {
    if (idRtAtual.equals(idRtNovo)) {
        throw new TrocaEnvolvidoException(
            "P09-RN04: O novo RT deve ser diferente do RT atualmente " +
            "vinculado ao licenciamento.");
    }
}
```

### RN05 — Novo RT deve ter habilitação ativa no CREA/CAU

```java
public void validarHabilitacaoRtNovo(ResponsavelTecnico rtNovo) {
    // Verifica cache local — se verificação recente (< 24h), usa o cached
    if (rtNovo.getDthVerificacaoHabilitacao() != null &&
        rtNovo.getDthVerificacaoHabilitacao().isAfter(OffsetDateTime.now().minusHours(24))) {
        if (!Boolean.TRUE.equals(rtNovo.getIndHabilitado())) {
            throw new TrocaEnvolvidoException(
                "P09-RN05: O profissional " + rtNovo.getNome() +
                " não possui habilitação ativa no " + rtNovo.getTipoConselho());
        }
        return;
    }
    // Consulta API do conselho profissional
    boolean habilitado = conselhoApiClient.verificarHabilitacao(
        rtNovo.getCpf(), rtNovo.getNroRegistroProfissional(), rtNovo.getTipoConselho());
    // Atualiza cache local
    rtNovo.setIndHabilitado(habilitado);
    rtNovo.setDthVerificacaoHabilitacao(OffsetDateTime.now());
    responsavelTecnicoRepository.save(rtNovo);
    if (!habilitado) {
        throw new TrocaEnvolvidoException(
            "P09-RN05: O profissional " + rtNovo.getNome() +
            " não possui habilitação ativa no " + rtNovo.getTipoConselho());
    }
}
```

### RN06 — Apenas RU ou Proprietário pode solicitar a troca

```java
public void validarPapelSolicitante(String idUsuarioKeycloak, Licenciamento lic) {
    boolean isRU = lic.getResponsavelUso() != null &&
                   lic.getResponsavelUso().getIdUsuarioKeycloak().equals(idUsuarioKeycloak);
    boolean isProprietario = lic.getProprietarios().stream()
        .anyMatch(p -> p.getIdUsuarioKeycloak().equals(idUsuarioKeycloak));
    boolean isProcurador = lic.getProcuradores().stream()
        .anyMatch(p -> p.getIdUsuarioKeycloak().equals(idUsuarioKeycloak) &&
                       (p.isRepresentanteRU() || p.isRepresentanteProprietario()));
    if (!isRU && !isProprietario && !isProcurador) {
        throw new AcessoNegadoException(
            "P09-RN06: Apenas o Responsável pelo Uso, Proprietário " +
            "ou seus procuradores podem solicitar a troca de RT.");
    }
}
```

### RN07 — Prazo máximo para resposta dos RTs

```java
// Prazo em dias para cada RT responder. Após o prazo, a troca é cancelada automaticamente.
static final int PRAZO_RESPOSTA_RT_DIAS = 15;

public boolean verificarPrazoExpirado(TrocaEnvolvido troca) {
    return troca.getDthCriacao()
                .plusDays(PRAZO_RESPOSTA_RT_DIAS)
                .isBefore(OffsetDateTime.now());
}
```

### RN08 — Efetivação somente após ambos os aceites

```java
public boolean podosEfetivar(TrocaEnvolvido troca) {
    return Boolean.TRUE.equals(troca.getAceiteRtAtual()) &&
           Boolean.TRUE.equals(troca.getAceiteRtNovo());
}
```

### RN09 — Recusa de qualquer RT cancela a troca

```java
public boolean deveSerCancelada(TrocaEnvolvido troca) {
    return Boolean.FALSE.equals(troca.getAceiteRtAtual()) ||
           Boolean.FALSE.equals(troca.getAceiteRtNovo());
}
```

---

## S5 — Serviços (Camada de Aplicação)

### 5.1 `TrocaEnvolvidoService` — Orquestrador Principal

```java
@Service
@Transactional
public class TrocaEnvolvidoService {

    private final TrocaEnvolvidoRepository trocaRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final ResponsavelTecnicoRepository rtRepository;
    private final LicenciamentoMarcoService marcoService;
    private final TrocaEnvolvidoNotificacaoService notificacaoService;
    private final TrocaEnvolvidoValidationService validationService;
    private final LicenciamentoStateTransitionService stateTransitionService;
    private final ApplicationEventPublisher eventPublisher;

    /**
     * Solicita a troca de RT em um licenciamento.
     * Chamado pelo RU ou Proprietário via endpoint REST.
     *
     * @param idLicenciamento  ID do licenciamento
     * @param idRtNovo         ID do novo RT a ser vinculado
     * @param idUsuarioLogado  Subject do token Keycloak do solicitante
     * @return TrocaEnvolvido  Solicitação criada com status SOLICITADO
     */
    public TrocaEnvolvido solicitarTroca(Long idLicenciamento, Long idRtNovo,
                                          String idUsuarioLogado) {
        Licenciamento lic = licenciamentoRepository.findById(idLicenciamento)
            .orElseThrow(() -> new RecursoNaoEncontradoException("Licenciamento não encontrado"));

        ResponsavelTecnico rtAtual = lic.getResponsavelTecnico();
        ResponsavelTecnico rtNovo  = rtRepository.findById(idRtNovo)
            .orElseThrow(() -> new RecursoNaoEncontradoException("RT não encontrado"));

        // Validações de pré-condição
        validationService.validarTipoLicenciamento(lic);
        validationService.validarSituacaoPermiteTrioca(lic);
        validationService.validarNaoExisteTrocaAtiva(idLicenciamento);
        validationService.validarRtsDiferentes(rtAtual.getId(), rtNovo.getId());
        validationService.validarPapelSolicitante(idUsuarioLogado, lic);
        validationService.validarHabilitacaoRtNovo(rtNovo);

        // Registra a situação anterior para eventual reversão
        SituacaoLicenciamento situacaoAnterior = lic.getSituacao();

        // Cria a solicitação de troca
        TrocaEnvolvido troca = new TrocaEnvolvido();
        troca.setLicenciamento(lic);
        troca.setRtAtual(rtAtual);
        troca.setRtNovo(rtNovo);
        troca.setStatus(StatusTrocaEnvolvido.SOLICITADO);
        troca.setIdUsuarioSolicitante(idUsuarioLogado);
        troca.setSituacaoAnterior(situacaoAnterior);
        troca.setDthCriacao(OffsetDateTime.now());
        trocaRepository.save(troca);

        // Transiciona situação do licenciamento
        stateTransitionService.transicionar(lic,
            SituacaoLicenciamento.AGUARDANDO_ACEITE_TROCA_ENVOLVIDO);

        // Registra marco de auditoria
        marcoService.registrar(lic, TipoMarco.SOLICITACAO_TROCA_ENVOLVIDO, null);

        // Notifica RT atual e novo RT
        notificacaoService.notificarSolicitacao(troca);

        return troca;
    }

    /**
     * RT Atual autoriza ou recusa a saída.
     *
     * @param idTroca          ID da TrocaEnvolvido
     * @param autoriza         true = autoriza saída; false = recusa
     * @param motivo           Motivo da recusa (obrigatório se autoriza=false)
     * @param idUsuarioLogado  Subject do token Keycloak do RT atual
     */
    public TrocaEnvolvido responderRtAtual(Long idTroca, boolean autoriza,
                                            String motivo, String idUsuarioLogado) {
        TrocaEnvolvido troca = buscarTrocaAberta(idTroca);

        // Valida que quem está respondendo é de fato o RT atual
        if (!troca.getRtAtual().getIdUsuarioKeycloak().equals(idUsuarioLogado)) {
            throw new AcessoNegadoException(
                "P09: Apenas o RT atual pode responder à autorização de saída.");
        }
        if (troca.getAceiteRtAtual() != null) {
            throw new TrocaEnvolvidoException("P09: RT atual já respondeu a esta solicitação.");
        }

        troca.setAceiteRtAtual(autoriza);
        troca.setDthAceiteRtAtual(OffsetDateTime.now());
        if (!autoriza) {
            troca.setMotivoRecusa(motivo);
        }
        trocaRepository.save(troca);

        marcoService.registrar(troca.getLicenciamento(),
            autoriza ? TipoMarco.ACEITE_TROCA_ENVOLVIDO_RT_ATUAL
                     : TipoMarco.RECUSA_TROCA_ENVOLVIDO, null);

        // Avalia se pode efetivar ou deve cancelar
        avaliarDesfecho(troca);
        return troca;
    }

    /**
     * Novo RT autoriza ou recusa a entrada.
     *
     * @param idTroca          ID da TrocaEnvolvido
     * @param autoriza         true = aceita entrar; false = recusa
     * @param motivo           Motivo da recusa (obrigatório se autoriza=false)
     * @param idUsuarioLogado  Subject do token Keycloak do novo RT
     */
    public TrocaEnvolvido responderRtNovo(Long idTroca, boolean autoriza,
                                           String motivo, String idUsuarioLogado) {
        TrocaEnvolvido troca = buscarTrocaAberta(idTroca);

        // Valida que quem está respondendo é de fato o novo RT
        if (!troca.getRtNovo().getIdUsuarioKeycloak().equals(idUsuarioLogado)) {
            throw new AcessoNegadoException(
                "P09: Apenas o novo RT pode responder à autorização de entrada.");
        }
        if (troca.getAceiteRtNovo() != null) {
            throw new TrocaEnvolvidoException("P09: Novo RT já respondeu a esta solicitação.");
        }

        troca.setAceiteRtNovo(autoriza);
        troca.setDthAceiteRtNovo(OffsetDateTime.now());
        if (!autoriza) {
            troca.setMotivoRecusa(motivo);
        }
        trocaRepository.save(troca);

        marcoService.registrar(troca.getLicenciamento(),
            autoriza ? TipoMarco.ACEITE_TROCA_ENVOLVIDO_RT_NOVO
                     : TipoMarco.RECUSA_TROCA_ENVOLVIDO, null);

        avaliarDesfecho(troca);
        return troca;
    }

    /**
     * Cancela a troca antes da efetivação.
     * Pode ser chamado pelo solicitante (RU/Prop) a qualquer momento antes da efetivação.
     */
    public TrocaEnvolvido cancelarTroca(Long idTroca, String idUsuarioLogado) {
        TrocaEnvolvido troca = buscarTrocaAberta(idTroca);

        // Valida que o cancelador é o solicitante original
        if (!troca.getIdUsuarioSolicitante().equals(idUsuarioLogado)) {
            throw new AcessoNegadoException(
                "P09: Apenas o solicitante pode cancelar a troca de RT.");
        }

        encerrarComCancelamento(troca, StatusTrocaEnvolvido.CANCELADO);
        return troca;
    }

    /**
     * Cancela a troca por decisão administrativa do CBM-RS.
     */
    public TrocaEnvolvido cancelarTrocaAdm(Long idTroca) {
        TrocaEnvolvido troca = buscarTrocaAberta(idTroca);
        encerrarComCancelamento(troca, StatusTrocaEnvolvido.CANCELADO_ADM);
        return troca;
    }

    // ─── Métodos privados ───────────────────────────────────────────────────

    private void avaliarDesfecho(TrocaEnvolvido troca) {
        if (podosEfetivar(troca)) {
            efetivarTroca(troca);
        } else if (deveSerCancelada(troca)) {
            encerrarComCancelamento(troca, StatusTrocaEnvolvido.CANCELADO);
        }
        // Se nenhum dos dois, aguarda a resposta pendente
    }

    private boolean podosEfetivar(TrocaEnvolvido troca) {
        return Boolean.TRUE.equals(troca.getAceiteRtAtual()) &&
               Boolean.TRUE.equals(troca.getAceiteRtNovo());
    }

    private boolean deveSerCancelada(TrocaEnvolvido troca) {
        return Boolean.FALSE.equals(troca.getAceiteRtAtual()) ||
               Boolean.FALSE.equals(troca.getAceiteRtNovo());
    }

    private void efetivarTroca(TrocaEnvolvido troca) {
        Licenciamento lic = troca.getLicenciamento();

        // 1. Substitui o RT no licenciamento
        lic.setResponsavelTecnico(troca.getRtNovo());

        // 2. Restaura a situação anterior do licenciamento
        stateTransitionService.transicionar(lic, troca.getSituacaoAnterior());

        // 3. Encerra a solicitação de troca
        troca.setStatus(StatusTrocaEnvolvido.EFETIVADO);
        troca.setDthConclusao(OffsetDateTime.now());
        trocaRepository.save(troca);
        licenciamentoRepository.save(lic);

        // 4. Marco de auditoria
        marcoService.registrar(lic, TipoMarco.EFETIVACAO_TROCA_ENVOLVIDO, null);

        // 5. Notificações
        notificacaoService.notificarEfetivacao(troca);
    }

    private void encerrarComCancelamento(TrocaEnvolvido troca, StatusTrocaEnvolvido statusFinal) {
        Licenciamento lic = troca.getLicenciamento();

        // 1. Restaura situação anterior do licenciamento
        stateTransitionService.transicionar(lic, troca.getSituacaoAnterior());

        // 2. Encerra a solicitação
        troca.setStatus(statusFinal);
        troca.setDthConclusao(OffsetDateTime.now());
        trocaRepository.save(troca);
        licenciamentoRepository.save(lic);

        // 3. Marco de auditoria
        marcoService.registrar(lic, TipoMarco.CANCELAMENTO_TROCA_ENVOLVIDO, null);

        // 4. Notificações
        notificacaoService.notificarCancelamento(troca);
    }

    private TrocaEnvolvido buscarTrocaAberta(Long idTroca) {
        TrocaEnvolvido troca = trocaRepository.findById(idTroca)
            .orElseThrow(() -> new RecursoNaoEncontradoException("Troca não encontrada"));
        if (troca.getStatus() != StatusTrocaEnvolvido.SOLICITADO) {
            throw new TrocaEnvolvidoException(
                "P09: Esta solicitação de troca já foi concluída (status: " +
                troca.getStatus() + "). Não é possível alterá-la.");
        }
        return troca;
    }
}
```

---

### 5.2 `TrocaEnvolvidoValidationService` — Validações isoladas

```java
@Service
public class TrocaEnvolvidoValidationService {

    private static final Set<SituacaoLicenciamento> SITUACOES_BLOQUEADAS = EnumSet.of(
        SituacaoLicenciamento.RASCUNHO,
        SituacaoLicenciamento.AGUARDANDO_ACEITE,
        SituacaoLicenciamento.AGUARDANDO_PAGAMENTO,
        SituacaoLicenciamento.EM_ANALISE,
        SituacaoLicenciamento.EM_VISTORIA,
        SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIA,
        SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIA,
        SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIV,
        SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIV,
        SituacaoLicenciamento.EXTINGUIDO,
        SituacaoLicenciamento.AGUARDANDO_ACEITE_TROCA_ENVOLVIDO
    );

    public void validarTipoLicenciamento(Licenciamento lic) { ... }
    public void validarSituacaoPermiteTrioca(Licenciamento lic) { ... }
    public void validarNaoExisteTrocaAtiva(Long idLicenciamento) { ... }
    public void validarRtsDiferentes(Long idRtAtual, Long idRtNovo) { ... }
    public void validarPapelSolicitante(String idUsuario, Licenciamento lic) { ... }
    public void validarHabilitacaoRtNovo(ResponsavelTecnico rtNovo) { ... }
}
```

---

### 5.3 `ConselhoApiClient` — Integração com CREA/CAU

```java
/**
 * Cliente REST para verificação de habilitação profissional nos conselhos.
 * Implementação deve consultar API pública do CREA-RS e CAU-BR.
 * Em ambiente de homologação/dev: use stub/mock.
 */
@Component
public class ConselhoApiClient {

    private final RestClient restClient;

    /**
     * Verifica se o profissional possui registro ativo no conselho.
     *
     * @param cpf                  CPF do profissional (11 dígitos, sem pontuação)
     * @param nroRegistro          Número do registro no conselho
     * @param tipoConselho         CREA ou CAU
     * @return true se habilitado, false se inativo/cancelado/suspenso
     */
    public boolean verificarHabilitacao(String cpf, String nroRegistro, TipoConselho tipoConselho) {
        String baseUrl = switch (tipoConselho) {
            case CREA -> creaApiBaseUrl;
            case CAU  -> cauApiBaseUrl;
        };
        try {
            HabilitacaoResponse resp = restClient.get()
                .uri(baseUrl + "/profissionais?cpf={cpf}&registro={reg}", cpf, nroRegistro)
                .retrieve()
                .body(HabilitacaoResponse.class);
            return resp != null && "ATIVO".equalsIgnoreCase(resp.getSituacao());
        } catch (Exception e) {
            // Falha na API do conselho → lança exceção de integração (não assume habilitado)
            throw new IntegracaoConselhoException(
                "P09-RN05: Falha ao verificar habilitação no " + tipoConselho +
                ". Tente novamente em instantes.");
        }
    }
}
```

---

### 5.4 `TrocaEnvolvidoNotificacaoService` — Notificações por e-mail

```java
@Service
public class TrocaEnvolvidoNotificacaoService {

    private final MailService mailService;

    /** Notifica RT atual e novo RT sobre a solicitação criada */
    public void notificarSolicitacao(TrocaEnvolvido troca) {
        // E-mail para o RT atual
        mailService.enviar(
            troca.getRtAtual().getEmail(),
            "Solicitação de Troca de Responsável Técnico — SOL CBM-RS",
            "email/troca-envolvido-rt-atual-solicitacao",
            buildContexto(troca)
        );
        // E-mail para o novo RT
        mailService.enviar(
            troca.getRtNovo().getEmail(),
            "Convite para Assumir Responsabilidade Técnica — SOL CBM-RS",
            "email/troca-envolvido-rt-novo-solicitacao",
            buildContexto(troca)
        );
    }

    /** Notifica todos os envolvidos sobre a efetivação da troca */
    public void notificarEfetivacao(TrocaEnvolvido troca) {
        Set<String> destinatarios = coletarTodosEmails(troca);
        destinatarios.forEach(email ->
            mailService.enviar(email,
                "Troca de Responsável Técnico Efetivada — SOL CBM-RS",
                "email/troca-envolvido-efetivada",
                buildContexto(troca)));
    }

    /** Notifica todos sobre cancelamento */
    public void notificarCancelamento(TrocaEnvolvido troca) {
        Set<String> destinatarios = coletarTodosEmails(troca);
        destinatarios.forEach(email ->
            mailService.enviar(email,
                "Troca de Responsável Técnico Cancelada — SOL CBM-RS",
                "email/troca-envolvido-cancelada",
                buildContexto(troca)));
    }

    private Set<String> coletarTodosEmails(TrocaEnvolvido troca) {
        Set<String> emails = new LinkedHashSet<>();
        emails.add(troca.getRtAtual().getEmail());
        emails.add(troca.getRtNovo().getEmail());
        Licenciamento lic = troca.getLicenciamento();
        if (lic.getResponsavelUso() != null && lic.getResponsavelUso().getEmail() != null)
            emails.add(lic.getResponsavelUso().getEmail());
        lic.getProprietarios().stream()
            .map(p -> p.getEmail())
            .filter(Objects::nonNull)
            .forEach(emails::add);
        return emails;
    }

    private Map<String, Object> buildContexto(TrocaEnvolvido troca) {
        return Map.of(
            "nroLicenciamento", troca.getLicenciamento().getNroLicenciamento(),
            "nomeRtAtual",      troca.getRtAtual().getNome(),
            "nomeRtNovo",       troca.getRtNovo().getNome(),
            "status",           troca.getStatus(),
            "dthSolicitacao",   troca.getDthCriacao()
        );
    }
}
```

---

### 5.5 `TrocaEnvolvidoPrazoScheduler` — Cancelamento automático por prazo

```java
/**
 * Job agendado para cancelar automaticamente trocas que excederam o prazo
 * de resposta dos RTs (PRAZO_RESPOSTA_RT_DIAS = 15 dias).
 * Executa diariamente às 03:00.
 */
@Component
public class TrocaEnvolvidoPrazoScheduler {

    private final TrocaEnvolvidoRepository trocaRepository;
    private final TrocaEnvolvidoService trocaService;

    @Scheduled(cron = "0 0 3 * * *")
    @Transactional
    public void cancelarTrocasVencidas() {
        OffsetDateTime limite = OffsetDateTime.now()
            .minusDays(TrocaEnvolvidoService.PRAZO_RESPOSTA_RT_DIAS);

        List<TrocaEnvolvido> vencidas = trocaRepository
            .findByStatusAndDthCriacaoBefore(StatusTrocaEnvolvido.SOLICITADO, limite);

        vencidas.forEach(troca -> {
            log.warn("P09: Cancelando troca vencida id={}, licenciamento={}",
                troca.getId(), troca.getLicenciamento().getId());
            trocaService.cancelarTrocaAdm(troca.getId());
        });
    }
}
```

---

## S6 — Repositório JPA

```java
public interface TrocaEnvolvidoRepository extends JpaRepository<TrocaEnvolvido, Long> {

    /** Verifica se existe troca ativa para um licenciamento */
    boolean existsByLicenciamentoIdAndStatus(Long idLicenciamento, StatusTrocaEnvolvido status);

    /** Busca todas as trocas SOLICITADAS com data de criação anterior ao limite */
    List<TrocaEnvolvido> findByStatusAndDthCriacaoBefore(
        StatusTrocaEnvolvido status, OffsetDateTime limite);

    /** Busca a troca ativa de um licenciamento */
    Optional<TrocaEnvolvido> findByLicenciamentoIdAndStatus(
        Long idLicenciamento, StatusTrocaEnvolvido status);

    /** Histórico de trocas de um licenciamento */
    List<TrocaEnvolvido> findByLicenciamentoIdOrderByDthCriacaoDesc(Long idLicenciamento);

    /** Trocas pendentes de resposta para um RT específico */
    @Query("""
        SELECT t FROM TrocaEnvolvido t
        WHERE t.status = 'SOLICITADO'
          AND (
            (t.rtAtual.idUsuarioKeycloak = :idUsuario AND t.aceiteRtAtual IS NULL)
            OR
            (t.rtNovo.idUsuarioKeycloak = :idUsuario AND t.aceiteRtNovo IS NULL)
          )
        ORDER BY t.dthCriacao ASC
    """)
    List<TrocaEnvolvido> findPendentesParaRt(@Param("idUsuario") String idUsuario);
}
```

---

## S7 — API REST

### 7.1 Controller Cidadão — `TrocaEnvolvidoController`

```java
@RestController
@RequestMapping("/api/licenciamentos/{idLicenciamento}/troca-rt")
@SecurityRequirement(name = "keycloak")
@Tag(name = "P09 - Troca de Responsável Técnico")
public class TrocaEnvolvidoController {

    private final TrocaEnvolvidoService service;
    private final TrocaEnvolvidoMapper mapper;

    /**
     * POST /api/licenciamentos/{idLicenciamento}/troca-rt
     * Inicia a solicitação de troca de RT.
     * Papel requerido: RU, Proprietário ou seu Procurador do licenciamento informado.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TrocaEnvolvidoResponseDTO solicitar(
            @PathVariable Long idLicenciamento,
            @RequestBody @Valid TrocaSolicitacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String idUsuario = jwt.getSubject();
        TrocaEnvolvido troca = service.solicitarTroca(
            idLicenciamento, dto.getIdRtNovo(), idUsuario);
        return mapper.toResponseDTO(troca);
    }

    /**
     * PUT /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}/rt-atual/resposta
     * RT atual autoriza ou recusa a saída.
     * Papel requerido: RT atual vinculado à troca.
     */
    @PutMapping("/{idTroca}/rt-atual/resposta")
    public TrocaEnvolvidoResponseDTO responderRtAtual(
            @PathVariable Long idLicenciamento,
            @PathVariable Long idTroca,
            @RequestBody @Valid RespostaRtRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        TrocaEnvolvido troca = service.responderRtAtual(
            idTroca, dto.isAutoriza(), dto.getMotivo(), jwt.getSubject());
        return mapper.toResponseDTO(troca);
    }

    /**
     * PUT /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}/rt-novo/resposta
     * Novo RT autoriza ou recusa a entrada.
     * Papel requerido: Novo RT vinculado à troca.
     */
    @PutMapping("/{idTroca}/rt-novo/resposta")
    public TrocaEnvolvidoResponseDTO responderRtNovo(
            @PathVariable Long idLicenciamento,
            @PathVariable Long idTroca,
            @RequestBody @Valid RespostaRtRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        TrocaEnvolvido troca = service.responderRtNovo(
            idTroca, dto.isAutoriza(), dto.getMotivo(), jwt.getSubject());
        return mapper.toResponseDTO(troca);
    }

    /**
     * DELETE /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}
     * Cancela a troca antes da efetivação.
     * Papel requerido: Solicitante original (RU/Proprietário).
     */
    @DeleteMapping("/{idTroca}")
    public TrocaEnvolvidoResponseDTO cancelar(
            @PathVariable Long idLicenciamento,
            @PathVariable Long idTroca,
            @AuthenticationPrincipal Jwt jwt) {

        TrocaEnvolvido troca = service.cancelarTroca(idTroca, jwt.getSubject());
        return mapper.toResponseDTO(troca);
    }

    /**
     * GET /api/licenciamentos/{idLicenciamento}/troca-rt
     * Lista o histórico de trocas de um licenciamento.
     */
    @GetMapping
    public List<TrocaEnvolvidoResponseDTO> listar(@PathVariable Long idLicenciamento) {
        return service.listarPorLicenciamento(idLicenciamento)
                      .stream()
                      .map(mapper::toResponseDTO)
                      .toList();
    }

    /**
     * GET /api/licenciamentos/{idLicenciamento}/troca-rt/ativa
     * Retorna a troca ativa (SOLICITADO) do licenciamento, se houver.
     */
    @GetMapping("/ativa")
    public ResponseEntity<TrocaEnvolvidoResponseDTO> buscarAtiva(
            @PathVariable Long idLicenciamento) {
        return service.buscarTrocaAtiva(idLicenciamento)
                      .map(mapper::toResponseDTO)
                      .map(ResponseEntity::ok)
                      .orElse(ResponseEntity.notFound().build());
    }

    /**
     * GET /api/minha-conta/trocas-pendentes
     * Lista as trocas que aguardam resposta do RT autenticado.
     */
    @GetMapping("/minha-conta/trocas-pendentes")
    public List<TrocaEnvolvidoResponseDTO> listarPendentesParaMim(
            @AuthenticationPrincipal Jwt jwt) {
        return service.listarPendentesParaRt(jwt.getSubject())
                      .stream()
                      .map(mapper::toResponseDTO)
                      .toList();
    }
}
```

---

### 7.2 Controller Administrativo — `TrocaEnvolvidoAdmController`

```java
@RestController
@RequestMapping("/api/adm/licenciamentos/{idLicenciamento}/troca-rt")
@SecurityRequirement(name = "keycloak")
@Tag(name = "P09 ADM - Gestão Administrativa de Troca de RT")
public class TrocaEnvolvidoAdmController {

    /**
     * DELETE /api/adm/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}
     * Cancela a troca administrativamente.
     * Role requerida: ROLE_ADM_CBM
     */
    @DeleteMapping("/{idTroca}")
    @PreAuthorize("hasRole('ADM_CBM')")
    public TrocaEnvolvidoResponseDTO cancelarAdm(
            @PathVariable Long idLicenciamento,
            @PathVariable Long idTroca) {
        TrocaEnvolvido troca = service.cancelarTrocaAdm(idTroca);
        return mapper.toResponseDTO(troca);
    }

    /**
     * GET /api/adm/licenciamentos/{idLicenciamento}/troca-rt
     * Visualiza todas as trocas do licenciamento (visão administrativa).
     * Role requerida: ROLE_ADM_CBM ou ROLE_ANALISTA_CBM
     */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADM_CBM', 'ANALISTA_CBM')")
    public List<TrocaEnvolvidoResponseDTO> listarAdm(@PathVariable Long idLicenciamento) {
        return service.listarPorLicenciamento(idLicenciamento)
                      .stream()
                      .map(mapper::toResponseDTO)
                      .toList();
    }
}
```

---

## S8 — DTOs

```java
/** Requisição para iniciar troca de RT */
public record TrocaSolicitacaoRequestDTO(
    @NotNull(message = "ID do novo RT é obrigatório")
    Long idRtNovo
) {}

/** Requisição para resposta do RT (autorizar ou recusar) */
public record RespostaRtRequestDTO(
    boolean autoriza,
    @Size(max = 500, message = "Motivo deve ter no máximo 500 caracteres")
    String motivo  // obrigatório quando autoriza=false (validado no Service)
) {}

/** Resposta com dados da troca */
public record TrocaEnvolvidoResponseDTO(
    Long                    id,
    Long                    idLicenciamento,
    String                  nroLicenciamento,
    RtResumoDTO             rtAtual,
    RtResumoDTO             rtNovo,
    StatusTrocaEnvolvido    status,
    Boolean                 aceiteRtAtual,
    OffsetDateTime          dthAceiteRtAtual,
    Boolean                 aceiteRtNovo,
    OffsetDateTime          dthAceiteRtNovo,
    OffsetDateTime          dthCriacao,
    OffsetDateTime          dthConclusao,
    String                  motivoRecusa,
    SituacaoLicenciamento   situacaoLicenciamentoAnterior,
    LocalDate               prazoResposta    // dthCriacao + 15 dias
) {}

/** Resumo de um RT para exibição na resposta */
public record RtResumoDTO(
    Long   id,
    String nome,
    String cpf,
    String nroRegistroProfissional,
    String tipoConselho,
    String email
) {}

/** DTO de busca de RT por CPF ou registro profissional */
public record BuscarRtDTO(
    String cpf,
    String nroRegistro,
    String tipoConselho
) {}

/** Resposta da API do conselho profissional */
public record HabilitacaoResponse(
    String situacao,    // "ATIVO", "INATIVO", "SUSPENSO", "CANCELADO"
    String nome,
    String tipoConselho,
    String nroRegistro
) {}
```

---

## S9 — Segurança com Keycloak

### 9.1 Configuração Spring Security

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/adm/**").hasRole("ADM_CBM")
                .requestMatchers("/api/**").authenticated()
                .anyRequest().permitAll()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(keycloakJwtConverter()))
            );
        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter keycloakJwtConverter() {
        JwtGrantedAuthoritiesConverter converter = new JwtGrantedAuthoritiesConverter();
        converter.setAuthoritiesClaimName("realm_access.roles");
        converter.setAuthorityPrefix("ROLE_");
        JwtAuthenticationConverter jwtConverter = new JwtAuthenticationConverter();
        jwtConverter.setJwtGrantedAuthoritiesConverter(converter);
        return jwtConverter;
    }
}
```

### 9.2 Roles Keycloak utilizadas

| Role Keycloak | Permissões no P09 |
|---|---|
| `ROLE_CIDADAO` | Solicitar troca (se RU/Prop do licenciamento), cancelar própria solicitação |
| `ROLE_RT` | Responder (autorizar/recusar) como RT atual ou novo RT |
| `ROLE_ADM_CBM` | Cancelar troca administrativamente, visualizar todas as trocas |
| `ROLE_ANALISTA_CBM` | Visualizar trocas (somente leitura) |

### 9.3 Verificação de Envolvimento

O sistema verifica no nível de serviço (não de filtro) se o usuário é **envolvido** no licenciamento:

```java
@Component
public class LicenciamentoEnvolvidoChecker {

    /**
     * Lança AcessoNegadoException se o usuário não for envolvido (RT, RU, Proprietário,
     * Procurador) do licenciamento informado.
     */
    public void verificar(String idUsuarioKeycloak, Licenciamento lic) {
        boolean envolvido =
            isRt(idUsuarioKeycloak, lic)       ||
            isRu(idUsuarioKeycloak, lic)        ||
            isProprietario(idUsuarioKeycloak, lic) ||
            isProcurador(idUsuarioKeycloak, lic);
        if (!envolvido) {
            throw new AcessoNegadoException(
                "Usuário não possui vínculo com o licenciamento " + lic.getId());
        }
    }
}
```

---

## S10 — Tratamento de Exceções

```java
/** Exceção de negócio para violações das regras do P09 */
public class TrocaEnvolvidoException extends RuntimeException {
    public TrocaEnvolvidoException(String message) { super(message); }
}

/** Exceção de acesso negado (HTTP 403) */
public class AcessoNegadoException extends RuntimeException {
    public AcessoNegadoException(String message) { super(message); }
}

/** Exceção de falha na integração com CREA/CAU */
public class IntegracaoConselhoException extends RuntimeException {
    public IntegracaoConselhoException(String message) { super(message); }
}

/** Handler global de exceções */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(TrocaEnvolvidoException.class)
    public ResponseEntity<ErrorResponse> handleTrocaException(TrocaEnvolvidoException ex) {
        return ResponseEntity.unprocessableEntity()     // HTTP 422
            .body(new ErrorResponse("TROCA_ENVOLVIDO_ERROR", ex.getMessage()));
    }

    @ExceptionHandler(AcessoNegadoException.class)
    public ResponseEntity<ErrorResponse> handleAcessoNegado(AcessoNegadoException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)    // HTTP 403
            .body(new ErrorResponse("ACESSO_NEGADO", ex.getMessage()));
    }

    @ExceptionHandler(IntegracaoConselhoException.class)
    public ResponseEntity<ErrorResponse> handleIntegracao(IntegracaoConselhoException ex) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)   // HTTP 503
            .body(new ErrorResponse("INTEGRACAO_INDISPONIVEL", ex.getMessage()));
    }
}
```

---

## S11 — Máquina de Estados do Processo P09

```
SITUAÇÕES QUE PERMITEM P09:
  ALVARA_VIGENTE, CA, AGUARDANDO_PRPCI, AGUARDANDO_ACEITE_PRPCI, etc.
                │
                │ solicitarTroca()
                ▼
  AGUARDANDO_ACEITE_TROCA_ENVOLVIDO  ← Status da TrocaEnvolvido: SOLICITADO
                │
        ┌───────┴────────┐
        │ (em paralelo)  │
        ▼                ▼
  RT Atual          Novo RT
  responde          responde
        │                │
        └───────┬────────┘
                │
   ┌────────────┴─────────────┐
   │ Ambos                    │ Qualquer
   │ autorizaram?             │ recusou?
   ▼                          ▼
EFETIVADO                 CANCELADO
   │                          │
   │ efetivarTroca()          │ encerrarComCancelamento()
   ▼                          ▼
[situação anterior]        [situação anterior]
  restaurada                 restaurada
  novo RT vinculado          RT original mantido
```

### Marcos de Auditoria registrados

| Ação | Marco (`TipoMarco`) |
|---|---|
| Troca solicitada | `SOLICITACAO_TROCA_ENVOLVIDO` |
| RT atual autorizou saída | `ACEITE_TROCA_ENVOLVIDO_RT_ATUAL` |
| Novo RT autorizou entrada | `ACEITE_TROCA_ENVOLVIDO_RT_NOVO` |
| Qualquer RT recusou | `RECUSA_TROCA_ENVOLVIDO` |
| Troca efetivada com sucesso | `EFETIVACAO_TROCA_ENVOLVIDO` |
| Troca cancelada | `CANCELAMENTO_TROCA_ENVOLVIDO` |

---

## S12 — Templates de E-mail (Thymeleaf)

### Template: RT Atual — Notificação de Solicitação

**`email/troca-envolvido-rt-atual-solicitacao.html`**
```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<body>
  <h2>Solicitação de Troca de Responsável Técnico</h2>
  <p>Prezado(a) <strong th:text="${nomeRtAtual}">RT Atual</strong>,</p>
  <p>
    Foi solicitada sua substituição como Responsável Técnico no licenciamento
    <strong th:text="${nroLicenciamento}">000001</strong>.
  </p>
  <p>
    O profissional indicado como substituto é:
    <strong th:text="${nomeRtNovo}">Novo RT</strong>.
  </p>
  <p>
    Para autorizar sua saída ou recusar a troca, acesse o sistema SOL e responda
    até <strong th:text="${prazoResposta}">15 dias</strong> a partir da data desta notificação.
  </p>
  <p>
    <a th:href="${linkSistema}">Acessar o Sistema SOL</a>
  </p>
  <p><em>Se você não solicitou esta ação, entre em contato com o CBM-RS.</em></p>
</body>
</html>
```

### Template: Novo RT — Convite para Assumir

**`email/troca-envolvido-rt-novo-solicitacao.html`**
```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<body>
  <h2>Convite para Assumir Responsabilidade Técnica</h2>
  <p>Prezado(a) <strong th:text="${nomeRtNovo}">Novo RT</strong>,</p>
  <p>
    Você foi indicado como novo Responsável Técnico no licenciamento
    <strong th:text="${nroLicenciamento}">000001</strong>,
    em substituição ao profissional <strong th:text="${nomeRtAtual}">RT Atual</strong>.
  </p>
  <p>
    Ao aceitar, você assumirá integralmente a responsabilidade técnica pelo
    PPCI do estabelecimento vinculado a este licenciamento.
  </p>
  <p>
    Acesse o sistema SOL para aceitar ou recusar este convite dentro de
    <strong th:text="${prazoResposta}">15 dias</strong>.
  </p>
  <p><a th:href="${linkSistema}">Acessar o Sistema SOL</a></p>
</body>
</html>
```

---

## S13 — DDL PostgreSQL Completo

```sql
-- Enum como check constraint (PostgreSQL não exige tipo ENUM nativo)
ALTER TABLE sol_licenciamento
    ADD COLUMN IF NOT EXISTS situacao VARCHAR(80) NOT NULL DEFAULT 'RASCUNHO';

-- Tabela principal do P09
CREATE TABLE sol_troca_envolvido (
    id                              BIGSERIAL     PRIMARY KEY,
    id_licenciamento                BIGINT        NOT NULL
        REFERENCES sol_licenciamento(id) ON DELETE RESTRICT,
    id_rt_atual                     BIGINT        NOT NULL
        REFERENCES sol_responsavel_tecnico(id),
    id_rt_novo                      BIGINT        NOT NULL
        REFERENCES sol_responsavel_tecnico(id),
    status                          VARCHAR(40)   NOT NULL DEFAULT 'SOLICITADO'
        CHECK (status IN ('SOLICITADO','EFETIVADO','CANCELADO','CANCELADO_ADM')),
    id_usuario_solicitante          VARCHAR(36)   NOT NULL,
    aceite_rt_atual                 BOOLEAN,
    dth_aceite_rt_atual             TIMESTAMPTZ,
    aceite_rt_novo                  BOOLEAN,
    dth_aceite_rt_novo              TIMESTAMPTZ,
    dth_criacao                     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    dth_conclusao                   TIMESTAMPTZ,
    motivo_recusa                   VARCHAR(500),
    situacao_licenciamento_anterior VARCHAR(80),
    CONSTRAINT chk_rt_diferentes   CHECK (id_rt_atual <> id_rt_novo)
);

-- Garante no máximo 1 troca SOLICITADA por licenciamento
CREATE UNIQUE INDEX idx_troca_ativa_por_lic
    ON sol_troca_envolvido (id_licenciamento)
    WHERE status = 'SOLICITADO';

-- Índices de performance
CREATE INDEX idx_troca_status         ON sol_troca_envolvido (status);
CREATE INDEX idx_troca_dth_criacao    ON sol_troca_envolvido (dth_criacao);
CREATE INDEX idx_troca_rt_atual       ON sol_troca_envolvido (id_rt_atual);
CREATE INDEX idx_troca_rt_novo        ON sol_troca_envolvido (id_rt_novo);

-- Campos adicionados à tabela de RTs para habilitação (se não existirem)
ALTER TABLE sol_responsavel_tecnico
    ADD COLUMN IF NOT EXISTS id_usuario_keycloak  VARCHAR(36),
    ADD COLUMN IF NOT EXISTS nro_registro_profissional VARCHAR(30),
    ADD COLUMN IF NOT EXISTS tipo_conselho         VARCHAR(10)
        CHECK (tipo_conselho IN ('CREA','CAU')),
    ADD COLUMN IF NOT EXISTS ind_habilitado        BOOLEAN,
    ADD COLUMN IF NOT EXISTS dth_verificacao_habilitacao TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS email                 VARCHAR(200);
```

---

## S14 — Fluxo Completo Passo a Passo

### Fluxo P09-A: Troca com Sucesso (ambos autorizam)

```
PASSO 1 — RU acessa detalhe do licenciamento e clica em "Solicitar Troca de RT"

PASSO 2 — Frontend Angular busca a lista de RTs cadastrados no sistema
  GET /api/responsaveis-tecnicos?nome=&cpf=&tipoConselho=

PASSO 3 — RU seleciona o novo RT e confirma
  POST /api/licenciamentos/{idLicenciamento}/troca-rt
  Body: { "idRtNovo": 42 }
  Header: Authorization: Bearer {token_keycloak}

PASSO 4 — Backend executa TrocaEnvolvidoService.solicitarTroca():
  4a. Carrega Licenciamento e verifica tipo (PPCI/PSPCIM) — RN01
  4b. Verifica situação compatível — RN02
  4c. Verifica inexistência de troca ativa — RN03
  4d. Verifica RTs diferentes — RN04
  4e. Verifica papel do solicitante (RU/Prop) — RN06
  4f. Consulta API CREA/CAU para validar habilitação do novo RT — RN05
  4g. Cria TrocaEnvolvido (status=SOLICITADO) em sol_troca_envolvido
  4h. Atualiza situação do licenciamento → AGUARDANDO_ACEITE_TROCA_ENVOLVIDO
  4i. Registra marco SOLICITACAO_TROCA_ENVOLVIDO
  4j. Envia e-mail para RT atual e novo RT
  4k. Retorna HTTP 201 com TrocaEnvolvidoResponseDTO

PASSO 5 — RT atual recebe e-mail e acessa o sistema
  GET /api/minha-conta/trocas-pendentes
  → Vê a troca pendente de sua autorização

PASSO 6 — RT atual autoriza saída
  PUT /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}/rt-atual/resposta
  Body: { "autoriza": true }
  → Backend seta aceiteRtAtual=true, registra marco ACEITE_TROCA_ENVOLVIDO_RT_ATUAL
  → Verifica se ambos já responderam: NÃO (novo RT ainda pendente)
  → Retorna TrocaEnvolvidoResponseDTO atualizado

PASSO 7 — Novo RT recebe e-mail e acessa o sistema
  GET /api/minha-conta/trocas-pendentes
  → Vê o convite pendente de sua resposta

PASSO 8 — Novo RT aceita a entrada
  PUT /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}/rt-novo/resposta
  Body: { "autoriza": true }
  → Backend seta aceiteRtNovo=true, registra marco ACEITE_TROCA_ENVOLVIDO_RT_NOVO
  → Verifica: ambos autorizaram → CHAMA efetivarTroca()
    8a. Atualiza sol_licenciamento.id_responsavel_tecnico = idRtNovo
    8b. Restaura situação anterior do licenciamento
    8c. Status da troca → EFETIVADO, dthConclusao = now()
    8d. Registra marco EFETIVACAO_TROCA_ENVOLVIDO
    8e. Envia e-mail de conclusão para todos os envolvidos
  → HTTP 200 com TrocaEnvolvidoResponseDTO (status=EFETIVADO)
```

---

### Fluxo P09-B: Troca Cancelada por Recusa do Novo RT

```
PASSOS 1–6: idênticos ao fluxo P09-A

PASSO 7 — Novo RT recusa a entrada
  PUT /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}/rt-novo/resposta
  Body: { "autoriza": false, "motivo": "Não tenho disponibilidade para assumir este projeto" }
  → Backend seta aceiteRtNovo=false, motivoRecusa="...", registra marco RECUSA_TROCA_ENVOLVIDO
  → Verifica: algum recusou → CHAMA encerrarComCancelamento()
    7a. Restaura situação anterior do licenciamento
    7b. Status da troca → CANCELADO, dthConclusao = now()
    7c. RT original permanece vinculado (não houve substituição)
    7d. Registra marco CANCELAMENTO_TROCA_ENVOLVIDO
    7e. Envia e-mail de cancelamento para todos os envolvidos
  → HTTP 200 com TrocaEnvolvidoResponseDTO (status=CANCELADO)
```

---

### Fluxo P09-C: Cancelamento pelo Solicitante

```
PASSOS 1–4: troca criada com status SOLICITADO

PASSO 5 — RU muda de ideia e cancela a solicitação
  DELETE /api/licenciamentos/{idLicenciamento}/troca-rt/{idTroca}
  → Backend verifica que o solicitante (jwt.sub) é o mesmo que criou a troca
  → encerrarComCancelamento() com StatusTrocaEnvolvido.CANCELADO
  → HTTP 200 com TrocaEnvolvidoResponseDTO (status=CANCELADO)
```

---

## S15 — Rastreabilidade: Requisitos × Código-Fonte Original

| Requisito (stack moderna) | Correspondente na stack atual (Java EE) |
|---|---|
| `TrocaEnvolvido` entity | `TrocaEnvolvidoED` (CBM_TROCA_ENVOLVIDO) |
| `TrocaEnvolvidoService.solicitarTroca()` | `LicenciamentoCidadaoTrocaEnvolvidoRN.solicitar()` |
| `TrocaEnvolvidoService.responderRtAtual()` | `LicenciamentoCidadaoTrocaEnvolvidoRN.autorizarSaida()` |
| `TrocaEnvolvidoService.responderRtNovo()` | `LicenciamentoCidadaoTrocaEnvolvidoRN.autorizarEntrada()` |
| `TrocaEnvolvidoService.cancelarTroca()` | `LicenciamentoCidadaoTrocaEnvolvidoRN.cancelar()` |
| `TrocaEnvolvidoValidationService` | `LicenciamentoCidadaoTrocaEnvolvidoRNVal` |
| `ConselhoApiClient` | Integração legada com sistema CREA-RS (via webservice SOAP) |
| `TrocaEnvolvidoController` | `LicenciamentoRestImpl` (endpoints `/troca-envolvido`) |
| `TrocaEnvolvidoAdmController` | `LicenciamentoAdmRestImpl` (endpoints adm) |
| `TrocaEnvolvidoNotificacaoService` | `NotificacaoRN` + templates de e-mail Velocity |
| `TrocaEnvolvidoPrazoScheduler` | Job agendado via `@Scheduled` (EJB Timer no original) |
| `StatusTrocaEnvolvido` enum | `TrocaEnvolvidoEnum` (SOLICITADO, EFETIVADO, CANCELADO) |
| `TipoMarco.EFETIVACAO_TROCA_ENVOLVIDO` | `TipoMarco.TROCA_ENVOLVIDO` |
| `LicenciamentoEnvolvidoChecker` | `SegurancaEnvolvidoInterceptor` + `@AutorizaEnvolvido` |
| `@PreAuthorize("hasRole('ADM_CBM')")` | `@Permissao(objeto="TROCAENVOLVIDO", acao="DISTRIBUIR")` |
| Keycloak JWT (`jwt.getSubject()`) | Token SOE PROCERGS (CPF extraído de claim privada) |
| `RestClient` para CREA/CAU (REST/JSON) | WebService SOAP CREA-RS (WSDL + JAX-WS) |
| PostgreSQL + BIGSERIAL | Oracle + SEQUENCE `SEQ_CBM_TROCA_ENVOLVIDO` |
| `@Scheduled(cron)` Spring | `@Schedule` EJB Timer Service |
| Thymeleaf templates | Apache Velocity templates |


---

## Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (ID4601, Demanda 9).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P09.
>
> ⚠️ **IMPACTO ALTO — Correção de bug crítico:** A troca de RT atualmente apaga RRT/ART aprovados. Isso força reanálise de inviabilidade técnica já decidida, impactando diretamente os processos em andamento.

---

### RN-P09-N1 — Preservar RRT/ART Aprovados ao Trocar o Responsável Técnico 🔴 P09-M1

**Prioridade:** CRÍTICA — correção de bug com impacto normativo  
**Origem:** Demanda 9 / ID4601 — Sprint 04 Hammer

**Descrição:** Quando um RT é substituído via P09, o sistema **não deve apagar** os RRT/ART aprovados em análise de inviabilidade técnica. O novo RT deve herdar esses documentos aprovados sem necessidade de nova análise.

**Comportamento atual (INCORRETO):**
```
Fase 3 — Efetivação da troca de RT
    → UPDATE cbm_envolvido SET id_usuario = novoRT
    → DELETE cbm_inviabilidade_tecnica  ← BUG: apaga tudo, inclusive aprovados
```

**Comportamento corrigido:**
```
Fase 3 — Efetivação da troca de RT
    → Verificar: existem RRT/ART com dt_aprovacao IS NOT NULL?
        │ SIM: NÃO deletar — desvincular do RT anterior e vincular ao licenciamento
        │ NÃO: pode deletar normalmente
    → UPDATE cbm_envolvido SET id_usuario = novoRT
    → Registrar marco: "RRT/ART de inviabilidade técnica preservado — análise anterior aprovada em DD/MM/AAAA"
```

**Mudança no banco de dados:**

```sql
-- Adicionar campos de aprovação na tabela de inviabilidade técnica
ALTER TABLE cbm_inviabilidade_tecnica
    ADD COLUMN dt_aprovacao TIMESTAMP,
    ADD COLUMN id_rrt_art_aprovado BIGINT REFERENCES cbm_documento(id),
    ADD COLUMN id_rt_original BIGINT REFERENCES cbm_usuario(id);
-- id_rt_original: referência ao RT que tinha o RRT/ART aprovado (preservado para auditoria)
```

**Mudança na Service de efetivação (Fase 3 do P09):**

```java
// TrocaEnvolvidosService.java — efetivarTroca()
@Transactional
public void efetivarTroca(TrocaEnvolvidos troca) {
    
    // 1. Verificar RRT/ART aprovados vinculados ao RT sendo substituído
    List<InviabilidadeTecnica> aprovadas = inviabilidadeRepo
        .findByIdLicenciamentoAndIdRtAndDtAprovacaoIsNotNull(
            troca.getIdLicenciamento(), troca.getIdRtAntigo());
    
    // 2. Substituir RT
    envolvidoRepository.updateRt(troca.getIdLicenciamento(), troca.getIdRtNovo());
    
    // 3. Preservar RRT/ART aprovados — NÃO deletar quando aprovados
    for (InviabilidadeTecnica inv : aprovadas) {
        inv.setIdRtOriginal(troca.getIdRtAntigo()); // auditoria
        // NÃO deletar — manter vinculado ao licenciamento
        inviabilidadeRepo.save(inv);
        
        // Registrar marco
        marcoService.registrar(troca.getIdLicenciamento(),
            TipoMarco.RRT_ART_PRESERVADO,
            "RRT/ART de inviabilidade técnica preservado — análise anterior aprovada em " +
            inv.getDtAprovacao().format(DateTimeFormatter.ofPattern("dd/MM/yyyy")));
    }
    
    // 4. Deletar apenas inviabilidades NÃO aprovadas
    inviabilidadeRepo.deleteByIdLicenciamentoAndIdRtAndDtAprovacaoIsNull(
        troca.getIdLicenciamento(), troca.getIdRtAntigo());
}
```

**Critérios de Aceitação:**
- [ ] CA-P09-N1a: Após troca de RT, RRT/ART com `dt_aprovacao IS NOT NULL` são preservados no licenciamento
- [ ] CA-P09-N1b: Novo RT não precisa submeter nova análise de inviabilidade se já há aprovação prévia
- [ ] CA-P09-N1c: Marco registra "RRT/ART de inviabilidade técnica preservado — análise anterior aprovada em DD/MM/AAAA"
- [ ] CA-P09-N1d: RRT/ART **sem** aprovação são removidos normalmente na troca de RT
- [ ] CA-P09-N1e: Campo `id_rt_original` registra o RT que possuía o documento (auditoria)

---

### RN-P09-N2 — Upload de RRT/ART de Inviabilidade Obrigatório Apenas na Primeira Vez 🔴 P09-M2

**Prioridade:** CRÍTICA  
**Origem:** ID4601 — Sprint 04 Hammer

**Descrição:** O upload de RRT/ART de inviabilidade técnica deve ser obrigatório **apenas na primeira vez**. Se o licenciamento já possui RRT/ART com aprovação registrada — mesmo após receber uma CIA de análise técnica — o sistema **não deve exigir novo upload** nem reencaminhar para análise de inviabilidade.

**Regra de validação:**

```java
// InviabilidadeTecnicaService.java
public boolean exigeNovoUploadRrtArt(UUID idLicenciamento) {
    // Verificar se já existe aprovação de inviabilidade para este licenciamento
    return !inviabilidadeRepo.existsByIdLicenciamentoAndDtAprovacaoIsNotNull(idLicenciamento);
}
```

**Mudança no fluxo de reanálise após CIA:**

```
Após receber CIA e corrigir o PPCI:
    │
    ▼
[GW] Licenciamento possui RRT/ART de inviabilidade aprovado?
        │ SIM              │ NÃO
        │                  │
        ▼                  ▼
Upload de RRT/ART     Upload de RRT/ART
NÃO exigido           OBRIGATÓRIO
        │                  │
        └──────────┬────────┘
                   ▼
         Encaminhar para reanálise
```

**Critérios de Aceitação:**
- [ ] CA-P09-N2a: Licenciamento com RRT/ART aprovado não exige novo upload após CIA
- [ ] CA-P09-N2b: Licenciamento sem aprovação prévia de inviabilidade exige upload do RRT/ART
- [ ] CA-P09-N2c: Endpoint de envio para reanálise verifica a existência de aprovação antes de exigir upload

---

### Resumo das Mudanças P09 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P09-M1 | RN-P09-N1 | Preservar RRT/ART aprovados ao trocar RT — correção de bug crítico | 🔴 Crítica |
| P09-M2 | RN-P09-N2 | Upload de RRT/ART obrigatório apenas na 1ª vez | 🔴 Crítica |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprint 04 (ID4601)*
