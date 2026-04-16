# Requisitos — P14: Renovação de Licenciamento (APPCI/Alvará)
## Versão Java Moderna (sem dependência da PROCERGS)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P14 — Renovação de Licenciamento
**Stack alvo:** Java 17+ · Spring Boot 3.x · Spring Security (OAuth2 Resource Server) · Spring Data JPA · Hibernate 6 · PostgreSQL · Spring Mail · Thymeleaf · Flyway
**Versão do documento:** 1.1
**Data:** 2026-03-16
**Referência de rastreabilidade:**
- `LicenciamentoRenovacaoCidadaoRN` → `RenovacaoService`
- `LicenciamentoRenovacaoRNVal` → `RenovacaoValidator`
- `TrocaEstado*RenovacaoRN` (10 classes) → `SituacaoTransitionService` + Strategy pattern
- `AppciCienciaCidadaoRenovacaoRN` → `AppciCienciaRenovacaoService`
- `LicenciamentoResponsavelPagamentoRN` → `ResponsavelPagamentoRenovacaoService`
- `TermoLicenciamentoRN` → `AnexoDRenovacaoService`

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Atores e Papéis](#2-atores-e-papéis)
3. [Pré-requisitos e Gatilhos](#3-pré-requisitos-e-gatilhos)
4. [Fase 1 — Iniciação da Renovação](#4-fase-1--iniciação-da-renovação)
5. [Fase 2 — Aceite do Anexo D de Renovação](#5-fase-2--aceite-do-anexo-d-de-renovação)
6. [Fase 3 — Pagamento ou Isenção da Taxa de Vistoria](#6-fase-3--pagamento-ou-isenção-da-taxa-de-vistoria)
7. [Fase 4 — Distribuição da Vistoria de Renovação](#7-fase-4--distribuição-da-vistoria-de-renovação)
8. [Fase 5 — Execução da Vistoria de Renovação](#8-fase-5--execução-da-vistoria-de-renovação)
9. [Fase 6 — Conclusão: Ciência do Novo APPCI ou CIV de Renovação](#9-fase-6--conclusão-ciência-do-novo-appci-ou-civ-de-renovação)
10. [Regras de Negócio](#10-regras-de-negócio)
11. [API REST — Endpoints](#11-api-rest--endpoints)
12. [Modelo de Dados](#12-modelo-de-dados)
13. [Máquina de Estados do Licenciamento](#13-máquina-de-estados-do-licenciamento)
14. [Segurança e Autorização](#14-segurança-e-autorização)
15. [Classes e Componentes Java Moderna](#15-classes-e-componentes-java-moderna)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P14 trata da **renovação de licenciamento de APPCI** (Alvará de Prevenção e Proteção Contra Incêndio) para estabelecimentos que já possuem alvará em vigor (`ALVARA_VIGENTE`) ou recentemente vencido (`ALVARA_VENCIDO`). É um processo distinto do P03 (primeira submissão): não há análise técnica do projeto — o PPCI já foi aprovado anteriormente — e a renovação percorre fluxo específico de aceite do Anexo D, pagamento de taxa de vistoria e nova vistoria presencial.

O processo pode ser iniciado pelo cidadão/RT ao acessar o portal, ou ter sido precedido pelas notificações automáticas de vencimento geradas pelo P13 (jobs de 90, 59 e 29 dias antes do vencimento).

### 1.2 Resultados possíveis

| Resultado | Situação final |
|---|---|
| Renovação aprovada — novo APPCI emitido | `ALVARA_VIGENTE` |
| Vistoria reprovada — CIV pendente | `CIV` |
| Cidadão recusa renovação (alvará ainda vigente) | `ALVARA_VIGENTE` (sem alteração) |
| Cidadão recusa renovação (alvará já vencido) | `ALVARA_VENCIDO` (permanece) |
| Isenção de taxa deferida | `AGUARDANDO_DISTRIBUICAO_RENOV` (pula pagamento) |
| Isenção de taxa indeferida | `AGUARDANDO_PAGAMENTO_RENOVACAO` (deve pagar boleto) |

### 1.3 Diferenças em relação ao P03 (primeira submissão)

| Aspecto | P03 | P14 |
|---|---|---|
| Estado de entrada | Licenciamento novo | `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` existente |
| Análise técnica | Obrigatória (P04) | Não — PPCI já aprovado |
| Tipo de vistoria | `TipoVistoria.PPCI` | `TipoVistoria.VISTORIA_RENOVACAO` |
| RT obrigatório | Qualquer tipo credenciado | Exclusivamente `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` |
| Aceite de termos | Não | Anexo D obrigatório |
| Ciência de APPCI | P08 (`APPCI`) | `APPCI_RENOV` (`AppciCienciaRenovacaoService`) |
| Listagem | `/minhas-solicitacoes` | `/minha-solicitacoes-renovacao` |
| Isenção de taxa | `solicitacaoIsencao` | campo separado `solicitacaoIsencaoRenovacao` |
| Responsáveis pagamento | RTs de execução + RU + Proprietário | APENAS RTs com `RENOVACAO_APPCI` + RU + Proprietário |

### 1.4 Referência na base de código legado

| Componente (Java EE 7) | Equivalente na stack moderna |
|---|---|
| `LicenciamentoRenovacaoCidadaoRN` | `RenovacaoService` |
| `LicenciamentoRenovacaoRNVal` | `RenovacaoValidator` |
| `TrocaEstadoLicenciamento*RN` (10 classes) | `SituacaoTransitionService` + Strategy pattern |
| `AppciCienciaCidadaoRenovacaoRN` | `AppciCienciaRenovacaoService` |
| `LicenciamentoResponsavelPagamentoRN` | `ResponsavelPagamentoRenovacaoService` |
| `TermoLicenciamentoRN` | `AnexoDRenovacaoService` |
| `@SegurancaEnvolvidoInterceptor` | `EnvolvidoAuthorizationService` (Spring Security) |
| `@AutorizaEnvolvido` | `@PreAuthorize("@envolvidoAuthz.verify(#idLic, authentication)")` |
| SOE PROCERGS / meu.rs.gov.br | Qualquer IdP OAuth2/OIDC (Keycloak, AWS Cognito, etc.) |

---

## 2. Atores e Papéis

| Ator | Papel no P14 |
|---|---|
| **Cidadão / RU** (Responsável pelo Uso) | Aceita ou recusa a renovação; assina o Anexo D; pode solicitar isenção de taxa |
| **RT Renovação** | RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI`; único RT habilitado para gerenciar o processo de renovação |
| **Proprietário PF** | Pode aceitar/recusar renovação e efetuar pagamento; identificado por CPF |
| **Proprietário PJ** | Identificado por CNPJ; representado por Procurador (CPF do procurador é o responsável de fato) |
| **Procurador** | Representante legal do Proprietário PJ; possui os mesmos poderes do proprietário |
| **Inspetor CBMRS** | Recebe a distribuição da vistoria de renovação; realiza a vistoria presencial; registra resultado |
| **Admin CBMRS** | Distribui a vistoria para inspetor; analisa isenções; homologa resultado da vistoria |
| **Sistema** | Confirma pagamentos via CNAB 240 (job P13-E); registra marcos e transições; enfileira notificações para P13-D |

---

## 3. Pré-requisitos e Gatilhos

### 3.1 Pré-requisitos obrigatórios

- Licenciamento em situação `ALVARA_VIGENTE` **ou** `ALVARA_VENCIDO` (RN-141). Qualquer outra situação → HTTP 422.
- Pelo menos um RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` vinculado ao licenciamento (RN-142).
- Usuário autenticado deve ser um dos seguintes envolvidos (RN-143):
  - RT com `RENOVACAO_APPCI`
  - RU (Responsável pelo Uso)
  - Proprietário PF (por CPF) ou PJ via Procurador (CPF do procurador)

### 3.2 Gatilhos de início

| Gatilho | Descrição |
|---|---|
| **Automático via P13** | Job P13-B notifica o cidadão por e-mail 90, 59 ou 29 dias antes do vencimento |
| **Manual (alvará vigente)** | Cidadão/RT acessa "Minhas Renovações" e solicita renovação proativamente |
| **Manual (alvará vencido)** | P13-A transitou para `ALVARA_VENCIDO`; cidadão acessa o portal para renovar |

### 3.3 Enum de situações por contexto

```java
public enum SituacaoLicenciamento {
    ALVARA_VIGENTE,
    ALVARA_VENCIDO,
    AGUARDANDO_ACEITE_RENOVACAO,
    AGUARDANDO_PAGAMENTO_RENOVACAO,
    AGUARDANDO_DISTRIBUICAO_RENOV,
    EM_VISTORIA_RENOVACAO,
    CIV,
    AGUARDANDO_CIENCIA_CIV,
    RECURSO_EM_ANALISE_1_CIV,
    RECURSO_EM_ANALISE_2_CIV,
    // ... demais situações ...

    /** RN-155: situações elegíveis para iniciar renovação */
    public static List<SituacaoLicenciamento> situacoesElegiveisRenovacao() {
        return List.of(ALVARA_VIGENTE, ALVARA_VENCIDO);
    }

    /** RN-141: situações que permitem edição no processo de renovação */
    public static List<SituacaoLicenciamento> situacoesEdicaoRenovacao() {
        return List.of(ALVARA_VIGENTE, ALVARA_VENCIDO, AGUARDANDO_ACEITE_RENOVACAO, CIV);
    }

    /** RN-154: situações listadas em "Minhas Renovações" */
    public static List<SituacaoLicenciamento> situacoesMinhasRenovacoes() {
        return List.of(
            AGUARDANDO_ACEITE_RENOVACAO, AGUARDANDO_CIENCIA_CIV, CIV,
            AGUARDANDO_PAGAMENTO_RENOVACAO, EM_VISTORIA_RENOVACAO,
            RECURSO_EM_ANALISE_1_CIV, RECURSO_EM_ANALISE_2_CIV
        );
    }
}
```

---

## 4. Fase 1 — Iniciação da Renovação

### 4.1 Fluxo de execução

```
1. Validação da situação do licenciamento (RN-141)
2. Validação de permissão do usuário autenticado (RN-143)
3. Validação de RT de renovação vinculado (RN-142)
4. Transição: ALVARA_VIGENTE ou ALVARA_VENCIDO → AGUARDANDO_ACEITE_RENOVACAO
5. Registro de histórico de situação (tb_licenciamento_situacao_hist)
6. Enfileiramento de notificação por e-mail (tb_licenciamento_notificacao — enviada pelo P13-D) (RN-160)
```

### 4.2 Implementação — RenovacaoService

```java
@Service
@RequiredArgsConstructor
public class RenovacaoService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final AppciRepository appciRepository;
    private final VistoriaRepository vistoriaRepository;
    private final SituacaoTransitionService transitionService;
    private final MarcoRepository marcoRepository;
    private final NotificacaoService notificacaoService;
    private final RenovacaoValidator renovacaoValidator;

    @Transactional
    public LicenciamentoResponseDTO iniciarRenovacao(Long idLicenciamento, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLicenciamento)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        // Valida situação (RN-141)
        renovacaoValidator.validarSituacaoParaEdicao(lic.getSituacao());

        // Valida permissão do usuário (RN-143)
        renovacaoValidator.validarPermissaoEnvolvido(lic, cpfUsuario);

        // Valida RT de renovação (RN-142)
        renovacaoValidator.validarRtRenovacao(lic, cpfUsuario);

        // Transição de estado
        transitionService.transicionar(lic,
            SituacaoLicenciamento.AGUARDANDO_ACEITE_RENOVACAO, cpfUsuario);

        // Notificação enfileirada para envio pelo P13-D (RN-160)
        notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);

        return LicenciamentoResponseDTO.from(lic);
    }

    /**
     * RN-145: Determina próximo estado no rollback (recusa da renovação).
     * Prioridade:
     * 1. Última vistoria encerrada = REPROVADO → CIV
     * 2. APPCI.dataValidade < hoje → ALVARA_VENCIDO
     * 3. Caso contrário → ALVARA_VIGENTE
     */
    public SituacaoLicenciamento resolverEstadoRollback(LicenciamentoEntity lic) {
        Optional<VistoriaEntity> ultimaVistoria = vistoriaRepository
            .findUltimaEncerradaRenovacaoByLicenciamento(lic.getId());

        if (ultimaVistoria.isPresent()
                && ultimaVistoria.get().getStatus() == StatusVistoria.REPROVADO) {
            return SituacaoLicenciamento.CIV;
        }

        LocalDate validadeAlvara = appciRepository
            .findVigenteByLicenciamento(lic)
            .map(AppciEntity::getDataValidade)
            .orElse(LocalDate.MIN);

        return LocalDate.now().isAfter(validadeAlvara)
            ? SituacaoLicenciamento.ALVARA_VENCIDO
            : SituacaoLicenciamento.ALVARA_VIGENTE;
    }

    @Transactional
    public LicenciamentoResponseDTO recusarRenovacao(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));
        renovacaoValidator.validarPermissaoEnvolvido(lic, cpfUsuario);

        SituacaoLicenciamento rollback = resolverEstadoRollback(lic);
        transitionService.transicionar(lic, rollback, cpfUsuario);
        notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
        return LicenciamentoResponseDTO.from(lic);
    }
}
```

### 4.3 Validações — RenovacaoValidator

```java
@Component
@RequiredArgsConstructor
public class RenovacaoValidator {

    /** RN-141 */
    public void validarSituacaoParaEdicao(SituacaoLicenciamento situacao) {
        if (!SituacaoLicenciamento.situacoesEdicaoRenovacao().contains(situacao)) {
            throw new RegraNegocioException(
                "Situação do licenciamento não pode ser editada no processo de renovação",
                HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }

    /** RN-142: RT com RENOVACAO_APPCI vinculado e usuário sendo esse RT */
    public void validarRtRenovacao(LicenciamentoEntity lic, String cpfUsuario) {
        List<ResponsavelTecnicoEntity> rtsRenovacao = lic.getResponsaveisTecnicos().stream()
            .filter(rt -> rt.getTipoResponsabilidade() == TipoResponsabilidadeTecnica.RENOVACAO_APPCI)
            .collect(Collectors.toList());

        if (rtsRenovacao.isEmpty()) {
            throw new RegraNegocioException(
                "Para solicitar a renovação do alvará, deve ser adicionado um responsável técnico " +
                "com tipo de responsabilidade técnica 'Renovação de APPCI'",
                HttpStatus.UNPROCESSABLE_ENTITY);
        }

        boolean usuarioEhRt = rtsRenovacao.stream()
            .anyMatch(rt -> rt.getUsuario().getCpf().equals(cpfUsuario));
        if (!usuarioEhRt) {
            throw new RegraNegocioException(
                "Usuário sem permissão de responsável técnico de renovação de APPCI",
                HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }

    /** RN-143: usuário deve ser RT(RENOVACAO_APPCI), RU, Proprietário PF ou Procurador PJ */
    public void validarPermissaoEnvolvido(LicenciamentoEntity lic, String cpfUsuario) {
        boolean eRT = lic.getResponsaveisTecnicos().stream()
            .anyMatch(rt -> rt.getTipoResponsabilidade() == TipoResponsabilidadeTecnica.RENOVACAO_APPCI
                        && rt.getUsuario().getCpf().equals(cpfUsuario));

        boolean eRU = lic.getResponsaveisUso().stream()
            .anyMatch(ru -> ru.getUsuario().getCpf().equals(cpfUsuario));

        boolean eProprietario = lic.getProprietarios().stream()
            .anyMatch(p -> p.getProprietario().getCpfCnpj().endsWith(cpfUsuario)
                       || (p.getProcurador() != null
                           && p.getProcurador().getUsuario().getCpf().equals(cpfUsuario)));

        if (!eRT && !eRU && !eProprietario) {
            throw new RegraNegocioException(
                "Alteração só pode ser realizada por RT de Renovação de APPCI, " +
                "proprietário ou responsável pelo uso",
                HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }
}
```

### 4.4 Listagem das renovações do usuário

**Endpoint:** `GET /api/v1/licenciamentos/minha-solicitacoes-renovacao`

```java
// LicenciamentoRepository
@Query("""
    SELECT l FROM LicenciamentoEntity l
    WHERE l.situacao IN :situacoes
      AND (
            EXISTS (SELECT rt FROM ResponsavelTecnicoEntity rt
                    WHERE rt.licenciamento = l
                      AND rt.tipoResponsabilidade = 'RENOVACAO_APPCI'
                      AND rt.usuario.cpf = :cpf)
         OR EXISTS (SELECT ru FROM ResponsavelUsoEntity ru
                    WHERE ru.licenciamento = l AND ru.usuario.cpf = :cpf)
         OR EXISTS (SELECT p FROM LicenciamentoProprietarioEntity p
                    WHERE p.licenciamento = l
                      AND (p.proprietario.cpfCnpj LIKE %:cpf
                           OR (p.procurador IS NOT NULL
                               AND p.procurador.usuario.cpf = :cpf)))
         )
      AND (:cidade IS NULL OR LOWER(l.endereco.cidade) LIKE LOWER(CONCAT('%', :cidade, '%')))
      AND (:numero IS NULL OR l.numeroPpci LIKE CONCAT('%', :numero, '%'))
      AND (:termo IS NULL
           OR l.numeroPpci LIKE CONCAT('%', :termo, '%')
           OR LOWER(l.endereco.logradouro) LIKE LOWER(CONCAT('%', :termo, '%')))
    """)
Page<LicenciamentoEntity> findMinhasRenovacoes(
    @Param("cpf") String cpf,
    @Param("situacoes") List<SituacaoLicenciamento> situacoes,
    @Param("cidade") String cidade,
    @Param("numero") String numero,
    @Param("termo") String termo,
    Pageable pageable
);
```

---

## 5. Fase 2 — Aceite do Anexo D de Renovação

O licenciamento está em `AGUARDANDO_ACEITE_RENOVACAO`. O cidadão deve ler e aceitar o **Anexo D de Renovação** antes de confirmar.

### 5.1 Leitura do Anexo D

**Endpoint:** `GET /api/v1/licenciamentos/{idLic}/termo-anexo-d-renovacao`

```java
@Service
@RequiredArgsConstructor
public class AnexoDRenovacaoService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final AppciRepository appciRepository;
    private final MarcoRepository marcoRepository;

    /** Retorna dados do Anexo D e situação de aceite atual */
    @Transactional(readOnly = true)
    public AnexoDRenovacaoResponseDTO consultar(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        AppciEntity appciVigente = appciRepository.findVigenteByLicenciamento(lic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("APPCI vigente não encontrado"));

        boolean aceiteAtual = marcoRepository.existsByLicenciamentoAndTipoMarco(
            lic, TipoMarco.ACEITE_ANEXOD_RENOVACAO);

        return AnexoDRenovacaoResponseDTO.builder()
            .aceito(aceiteAtual)
            .appci(AppciRenovacaoDTO.builder()
                .numeroPedido(appciVigente.getNumeroPedido())
                .validade(formatarData(appciVigente.getDataValidade()))
                .inicioVigencia(formatarData(appciVigente.getDataInicioVigencia()))
                .fimVigencia(formatarData(appciVigente.getDataFimVigencia()))
                .build())
            .build();
    }

    /** RN-144: Registra aceite do Anexo D */
    @Transactional
    public AnexoDRenovacaoResponseDTO confirmarAceite(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic)
            .tipoMarco(TipoMarco.ACEITE_ANEXOD_RENOVACAO)
            .tipoResponsavel(TipoResponsavelMarco.CIDADAO)
            .dataHora(LocalDateTime.now())
            .build());

        return consultar(idLic, cpfUsuario);
    }

    /** RN-144: Remove aceite — permitido enquanto situação = AGUARDANDO_ACEITE_RENOVACAO */
    @Transactional
    public void removerAceite(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        if (lic.getSituacao() != SituacaoLicenciamento.AGUARDANDO_ACEITE_RENOVACAO) {
            throw new RegraNegocioException(
                "Remoção do aceite só é permitida na situação AGUARDANDO_ACEITE_RENOVACAO",
                HttpStatus.UNPROCESSABLE_ENTITY);
        }
        marcoRepository.deleteByLicenciamentoAndTipoMarco(lic, TipoMarco.ACEITE_ANEXOD_RENOVACAO);
    }

    private String formatarData(LocalDate data) {
        return data != null ? data.format(DateTimeFormatter.ofPattern("dd/MM/yyyy")) : null;
    }
}
```

**DTOs:**

```java
// AppciRenovacaoDTO — dados do APPCI atual para exibição durante a renovação
@Value
@Builder
public class AppciRenovacaoDTO {
    Integer numeroPedido;
    String  validade;
    String  inicioVigencia;
    String  fimVigencia;
}

// AnexoDRenovacaoResponseDTO
@Value
@Builder
public class AnexoDRenovacaoResponseDTO {
    boolean aceito;
    AppciRenovacaoDTO appci;
}
```

### 5.2 Confirmação da renovação após aceite do Anexo D

Após aceitar o Anexo D, o cidadão confirma o prosseguimento. O sistema determina o próximo estado conforme **RN-145**:

| Condição | Próxima situação |
|---|---|
| Última vistoria encerrada = `REPROVADO` | `CIV` |
| Confirma + sem CIV + isenção aprovada | `AGUARDANDO_DISTRIBUICAO_RENOV` |
| Confirma + sem CIV + sem isenção | `AGUARDANDO_PAGAMENTO_RENOVACAO` |
| Recusa + alvará expirado (`dataValidade < hoje`) | `ALVARA_VENCIDO` |
| Recusa + alvará ainda válido | `ALVARA_VIGENTE` |

---

## 6. Fase 3 — Pagamento ou Isenção da Taxa de Vistoria

O licenciamento está em `AGUARDANDO_PAGAMENTO_RENOVACAO`. O cidadão deve quitar a taxa de vistoria ou solicitar isenção.

### 6.1 Listagem de responsáveis para pagamento da renovação

**Endpoint:** `GET /api/v1/licenciamentos/{idLic}/responsaveis-pagamento-renovacao`

**Nota de compatibilidade:** O endpoint original usa `reponsaveis` (sem segundo 's' — typo do código legado). Na stack moderna, corrigir para `responsaveis`. Se necessário, manter o path legado como alias via `@RequestMapping` adicional.

```java
@Service
@RequiredArgsConstructor
public class ResponsavelPagamentoRenovacaoService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final ResponsavelTecnicoRepository rtRepository;
    private final ResponsavelUsoRepository ruRepository;
    private final LicenciamentoProprietarioRepository proprietarioRepository;

    /**
     * RN-146: Lista responsáveis habilitados para pagamento da taxa de renovação.
     *
     * Diferença em relação ao pagamento padrão (P11):
     * - RT: filtra APENAS por TipoResponsabilidadeTecnica.RENOVACAO_APPCI
     * - RU: todos os RUs
     * - Proprietários: todos (PF = CPF; PJ = CNPJ + CPF do Procurador)
     * - Deduplicação por CPF/CNPJ; ordenação por nome.
     */
    @Transactional(readOnly = true)
    public List<ResponsavelPagamentoDTO> listar(Long idLic) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        Map<String, ResponsavelPagamentoDTO> responsaveisMap = new LinkedHashMap<>();

        // Apenas RTs com RENOVACAO_APPCI
        rtRepository.findByLicenciamento(lic).stream()
            .filter(rt -> rt.getTipoResponsabilidade() == TipoResponsabilidadeTecnica.RENOVACAO_APPCI)
            .forEach(rt -> responsaveisMap.putIfAbsent(
                rt.getUsuario().getCpf(), ResponsavelPagamentoDTO.fromRT(rt)));

        // Todos os RUs
        ruRepository.findByLicenciamento(lic)
            .forEach(ru -> responsaveisMap.putIfAbsent(
                ru.getUsuario().getCpf(), ResponsavelPagamentoDTO.fromRU(ru)));

        // Proprietários PF e PJ
        proprietarioRepository.findByLicenciamento(lic)
            .forEach(p -> responsaveisMap.putIfAbsent(
                p.getProprietario().getCpfCnpj(), ResponsavelPagamentoDTO.fromProprietario(p)));

        return responsaveisMap.values().stream()
            .sorted(Comparator.comparing(ResponsavelPagamentoDTO::getNome))
            .collect(Collectors.toList());
    }
}
```

**DTO de retorno:**

```java
@Value
@Builder
public class ResponsavelPagamentoDTO {
    String cpfCnpj;
    String nome;
    TipoResponsavelPagamento tipo;  // RT, RU, PROPRIETARIO_PF, PROPRIETARIO_PJ
    String cpfProcurador;           // somente para PROPRIETARIO_PJ
}
```

### 6.2 Solicitação de isenção de taxa de renovação

**Endpoint:** `PUT /api/v1/licenciamentos/{idLic}/solicitacao-isencao`

```java
// Request body
@Data
public class IsencaoRenovacaoRequestDTO {
    Boolean solicitacao;          // isenção do licenciamento original
    Boolean solicitacaoRenovacao; // isenção específica da renovação (RN-147, RN-157)
}

// Implementação
@Transactional
public void registrarSolicitacao(Long idLic, IsencaoRenovacaoRequestDTO req, String cpfUsuario) {
    LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

    renovacaoValidator.validarPermissaoEnvolvido(lic, cpfUsuario);

    // RN-157: campos independentes — não sobrescrever o outro
    if (req.getSolicitacao() != null) {
        lic.setSolicitacaoIsencao(req.getSolicitacao());
    }
    if (req.getSolicitacaoRenovacao() != null) {
        lic.setSolicitacaoIsencaoRenovacao(req.getSolicitacaoRenovacao());
    }
    licenciamentoRepository.save(lic);

    // Marco de solicitação (RN-147)
    if (Boolean.TRUE.equals(req.getSolicitacaoRenovacao())) {
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic)
            .tipoMarco(TipoMarco.SOLICITACAO_ISENCAO_RENOVACAO)
            .tipoResponsavel(TipoResponsavelMarco.CIDADAO)
            .dataHora(LocalDateTime.now())
            .build());
    }
}
```

### 6.3 Análise da isenção pelo Admin CBMRS

**Endpoint:** `PUT /api/v1/adm/licenciamentos/{idLic}/isencao-renovacao/analisar`

```java
@Transactional
public void analisarIsencaoRenovacao(Long idLic, boolean deferir) {
    LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

    if (deferir) {
        // RN-148: Deferido → AGUARDANDO_DISTRIBUICAO_RENOV
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.ANALISE_ISENCAO_RENOV_APROVADO)
            .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());
        transitionService.transicionar(lic,
            SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV, "SISTEMA");
    } else {
        // RN-148: Indeferido → permanece em AGUARDANDO_PAGAMENTO_RENOVACAO
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.ANALISE_ISENCAO_RENOV_REPROVADO)
            .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());
    }
    notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
}
```

### 6.4 Confirmação de pagamento via CNAB 240 (P13-E)

A confirmação de pagamento é realizada automaticamente pelo **job P13-E** (`BanrisulRetornoService`) ao processar arquivos CNAB 240 do Banrisul. Não há interação humana nesta etapa.

```java
// Dentro de BanrisulRetornoService (P13-E) — chamado por cada registro de pagamento do CNAB
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void processarPagamentoRenovacao(Long idLicenciamento) {
    LicenciamentoEntity lic = licenciamentoRepository.findById(idLicenciamento)
        .orElseThrow();

    if (lic.getSituacao() == SituacaoLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO) {
        // RN-149: marco + transição
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.LIQUIDACAO_VISTORIA_RENOVACAO)
            .tipoResponsavel(TipoResponsavelMarco.SISTEMA).dataHora(LocalDateTime.now()).build());
        transitionService.transicionar(lic,
            SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV, "SISTEMA");
    }
}
```

---

## 7. Fase 4 — Distribuição da Vistoria de Renovação

O licenciamento está em `AGUARDANDO_DISTRIBUICAO_RENOV`. O Admin CBMRS distribui a vistoria para um inspetor.

**Endpoint:** `PUT /api/v1/adm/licenciamentos/{idLic}/distribuir-vistoria-renovacao`

```java
@Transactional
public LicenciamentoResponseDTO distribuirVistoria(Long idLic, Long idInspetor) {
    LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

    if (lic.getSituacao() != SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV) {
        throw new RegraNegocioException(
            "Licenciamento não está aguardando distribuição de vistoria de renovação",
            HttpStatus.UNPROCESSABLE_ENTITY);
    }

    // RN-150: marco com TipoResponsavelMarco.BOMBEIROS
    marcoRepository.save(LicenciamentoMarcoEntity.builder()
        .licenciamento(lic).tipoMarco(TipoMarco.DISTRIBUICAO_VISTORIA_RENOV)
        .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());

    // Transição
    transitionService.transicionar(lic,
        SituacaoLicenciamento.EM_VISTORIA_RENOVACAO, "ADMIN");

    // Criação da vistoria de renovação (RN-151)
    InspetorEntity inspetor = inspetorRepository.findById(idInspetor)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Inspetor não encontrado"));

    vistoriaRepository.save(VistoriaEntity.builder()
        .licenciamento(lic)
        .inspetor(inspetor)
        .tipoVistoria(TipoVistoria.VISTORIA_RENOVACAO) // RN-151
        .status(StatusVistoria.AGENDADA)
        .dataHoraCriacao(LocalDateTime.now())
        .build());

    notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
    return LicenciamentoResponseDTO.from(lic);
}
```

---

## 8. Fase 5 — Execução da Vistoria de Renovação

O licenciamento está em `EM_VISTORIA_RENOVACAO`. O inspetor realiza a vistoria presencial com `TipoVistoria.VISTORIA_RENOVACAO`.

### 8.1 Tipo de vistoria específico (RN-151)

```java
public enum TipoVistoria {
    PPCI,               // ordinal 0 — P03/P07
    PSPCIM,             // ordinal 1
    RENOVACAO_PPCI,     // ordinal 2 (legado)
    VISTORIA_RENOVACAO  // ordinal 3 — P14 exclusivo
}
```

Qualquer query de vistoria em contexto de renovação **deve** filtrar por `TipoVistoria.VISTORIA_RENOVACAO`. Nunca usar `PPCI` (ordinal 0) em contexto de P14.

### 8.2 Registro do resultado pelo inspetor

**Endpoint:** `PUT /api/v1/inspetores/vistorias/{idVistoria}/resultado-renovacao`

```java
@Transactional
public void registrarResultado(Long idVistoria, ResultadoVistoriaDTO resultado) {
    VistoriaEntity vistoria = vistoriaRepository.findById(idVistoria)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Vistoria não encontrada"));

    if (vistoria.getTipoVistoria() != TipoVistoria.VISTORIA_RENOVACAO) {
        throw new RegraNegocioException("Vistoria não é do tipo renovação", HttpStatus.BAD_REQUEST);
    }

    vistoria.setStatus(resultado.isAprovado() ? StatusVistoria.APROVADO : StatusVistoria.REPROVADO);
    vistoria.setObservacoes(resultado.getObservacoes());
    vistoria.setDataHoraEncerramento(LocalDateTime.now());
    vistoriaRepository.save(vistoria);

    TipoMarco marco = resultado.isAprovado()
        ? TipoMarco.VISTORIA_RENOVACAO
        : TipoMarco.VISTORIA_RENOVACAO_CIV;

    marcoRepository.save(LicenciamentoMarcoEntity.builder()
        .licenciamento(vistoria.getLicenciamento()).tipoMarco(marco)
        .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());
}
```

### 8.3 Homologação pelo Admin CBMRS

**Endpoint:** `PUT /api/v1/adm/vistorias/{idVistoria}/homologar-renovacao`

O caso de `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` retorna a vistoria ao status `EM_VISTORIA` para reavaliação (equivalente a `TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN`):

```java
@Transactional
public void homologar(Long idVistoria, boolean deferir) {
    VistoriaEntity vistoria = vistoriaRepository.findById(idVistoria).orElseThrow();
    LicenciamentoEntity lic = vistoria.getLicenciamento();

    if (deferir) {
        vistoria.setStatus(StatusVistoria.HOMOLOGADO_APROVADO);
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.HOMOLOG_VISTORIA_RENOV_DEFERIDO)
            .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());
        // Segue para Fase 6A (emissão APPCI)
    } else {
        // Retorna para reavaliação — equivale a TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN
        vistoria.setStatus(StatusVistoria.EM_VISTORIA);
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.HOMOLOG_VISTORIA_RENOV_INDEFERIDO)
            .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS).dataHora(LocalDateTime.now()).build());
    }
    vistoriaRepository.save(vistoria);
}
```

---

## 9. Fase 6 — Conclusão: Ciência do Novo APPCI ou CIV de Renovação

### 9.1 Ciência e emissão do novo APPCI (Fase 6A — Aprovado)

**Endpoint:** `PUT /api/v1/licenciamentos/{idLic}/renovacao/ciencia-appci`

Equivalente a `AppciCienciaCidadaoRenovacaoRN` com `TipoLicenciamentoCiencia.APPCI_RENOV`.

```java
@Service
@RequiredArgsConstructor
public class AppciCienciaRenovacaoService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final AppciRepository appciRepository;
    private final MarcoRepository marcoRepository;
    private final SituacaoTransitionService transitionService;
    private final NotificacaoService notificacaoService;

    /**
     * RN-152: Ciência do novo APPCI sempre resulta em ALVARA_VIGENTE.
     * isLicenciamentoCienciaAprovado() sempre retorna true.
     */
    @Transactional
    public LicenciamentoResponseDTO registrarCienciaAppci(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        // Persiste o APPCI renovado (equivale a appciRN.altera() → entityManager.merge())
        appciRepository.findPendenteDeRenovacaoByLicenciamento(lic).ifPresent(appci -> {
            appci.setDataHoraAtualizacao(LocalDateTime.now());
            appciRepository.save(appci);
        });

        // Marco CIENCIA_APPCI_RENOVACAO (RN-152)
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.CIENCIA_APPCI_RENOVACAO)
            .tipoResponsavel(TipoResponsavelMarco.CIDADAO).dataHora(LocalDateTime.now()).build());

        // Marco LIBERACAO_RENOV_APPCI (RN-152)
        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.LIBERACAO_RENOV_APPCI)
            .tipoResponsavel(TipoResponsavelMarco.SISTEMA).dataHora(LocalDateTime.now()).build());

        // RN-152: sempre → ALVARA_VIGENTE
        transitionService.transicionar(lic, SituacaoLicenciamento.ALVARA_VIGENTE, cpfUsuario);

        notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
        return LicenciamentoResponseDTO.from(lic);
    }

    /**
     * RN-153: Cidadão toma ciência da CIV de renovação.
     * Situação → CIV; marco CIENCIA_CIV_RENOVACAO.
     */
    @Transactional
    public LicenciamentoResponseDTO registrarCienciaCiv(Long idLic, String cpfUsuario) {
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        marcoRepository.save(LicenciamentoMarcoEntity.builder()
            .licenciamento(lic).tipoMarco(TipoMarco.CIENCIA_CIV_RENOVACAO)
            .tipoResponsavel(TipoResponsavelMarco.CIDADAO).dataHora(LocalDateTime.now()).build());

        transitionService.transicionar(lic, SituacaoLicenciamento.CIV, cpfUsuario);
        notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
        return LicenciamentoResponseDTO.from(lic);
    }
}
```

### 9.2 Retomada da renovação após CIV corrigida (RN-153)

**Endpoint:** `PUT /api/v1/licenciamentos/{idLic}/renovacao/retomar-apos-civ`

```java
@Transactional
public LicenciamentoResponseDTO retornarDeCivParaAceite(Long idLic, String cpfUsuario) {
    LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
        .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

    if (lic.getSituacao() != SituacaoLicenciamento.CIV) {
        throw new RegraNegocioException(
            "Licenciamento não está em situação CIV", HttpStatus.UNPROCESSABLE_ENTITY);
    }

    renovacaoValidator.validarPermissaoEnvolvido(lic, cpfUsuario);

    // RN-153: CIV → AGUARDANDO_ACEITE_RENOVACAO
    transitionService.transicionar(lic,
        SituacaoLicenciamento.AGUARDANDO_ACEITE_RENOVACAO, cpfUsuario);

    notificacaoService.enfileirarNotificacaoEnvolvidos(lic, ContextoNotificacao.RENOVACAO);
    return LicenciamentoResponseDTO.from(lic);
}
```

---

## 10. Regras de Negócio

| ID | Regra | Implementação na stack moderna |
|---|---|---|
| **RN-141** | Somente licenciamentos em `ALVARA_VIGENTE`, `ALVARA_VENCIDO`, `AGUARDANDO_ACEITE_RENOVACAO` ou `CIV` podem ser editados no processo de renovação. Outras situações → HTTP 422. | `RenovacaoValidator.validarSituacaoParaEdicao()` |
| **RN-142** | Para solicitar renovação, deve haver ao menos um RT com `RENOVACAO_APPCI` vinculado e o usuário autenticado deve ser esse RT. Lista vazia → 422; usuário sem esse tipo → 422. | `RenovacaoValidator.validarRtRenovacao()` |
| **RN-143** | Alterações no processo de renovação só podem ser realizadas pelo usuário autenticado que seja RT (`RENOVACAO_APPCI`), RU, Proprietário PF (CPF) ou Procurador de PJ (CPF do procurador). HTTP 422 caso contrário. | `RenovacaoValidator.validarPermissaoEnvolvido()` |
| **RN-144** | O cidadão deve aceitar o Anexo D da renovação antes de confirmar. Aceite registrado como marco `ACEITE_ANEXOD_RENOVACAO`. Pode ser retirado enquanto situação = `AGUARDANDO_ACEITE_RENOVACAO`. | `AnexoDRenovacaoService.confirmarAceite()` / `removerAceite()` |
| **RN-145** | Próximo estado após ação do cidadão: (1) última vistoria encerrada `REPROVADO` → `CIV`; (2) sem CIV + `APPCI.dataValidade < hoje` → `ALVARA_VENCIDO`; (3) sem CIV + alvará válido → `ALVARA_VIGENTE`. Confirmação sem isenção → `AGUARDANDO_PAGAMENTO_RENOVACAO`; com isenção aprovada → `AGUARDANDO_DISTRIBUICAO_RENOV`. | `RenovacaoService.resolverEstadoRollback()` |
| **RN-146** | Responsáveis para pagamento da renovação: RTs com `RENOVACAO_APPCI` + todos os RUs + todos os Proprietários. Diferente do P11 (que filtra por RTs de execução). Deduplicação por CPF/CNPJ; ordenação por nome. | `ResponsavelPagamentoRenovacaoService.listar()` |
| **RN-147** | Solicitação de isenção de renovação usa o campo `solicitacaoIsencaoRenovacao` em `tb_licenciamento`, distinto de `solicitacaoIsencao`. Marco: `SOLICITACAO_ISENCAO_RENOVACAO`. | `IsencaoRenovacaoService.registrarSolicitacao()` |
| **RN-148** | Análise de isenção pelo CBMRS: deferida → marco `ANALISE_ISENCAO_RENOV_APROVADO` + transição para `AGUARDANDO_DISTRIBUICAO_RENOV`; indeferida → marco `ANALISE_ISENCAO_RENOV_REPROVADO` + permanece em `AGUARDANDO_PAGAMENTO_RENOVACAO`. | `IsencaoRenovacaoService.analisarIsencaoRenovacao()` |
| **RN-149** | Confirmação de pagamento exclusivamente via CNAB 240 do Banrisul, processado pelo job P13-E. Após confirmação: marco `LIQUIDACAO_VISTORIA_RENOVACAO` + transição `AGUARDANDO_PAGAMENTO_RENOVACAO` → `AGUARDANDO_DISTRIBUICAO_RENOV`. | `BanrisulRetornoService.processarPagamentoRenovacao()` |
| **RN-150** | Distribuição da vistoria: atualiza situação para `EM_VISTORIA_RENOVACAO` + marco `DISTRIBUICAO_VISTORIA_RENOV` com `TipoResponsavelMarco.BOMBEIROS`. | `VistoriaRenovacaoService.distribuirVistoria()` |
| **RN-151** | Vistoria de renovação usa exclusivamente `TipoVistoria.VISTORIA_RENOVACAO` (ordinal 3). Qualquer query no contexto de renovação deve filtrar por esse tipo. | `VistoriaEntity.tipoVistoria` + queries do repositório |
| **RN-152** | Ciência do APPCI de renovação sempre resulta em aprovação (`isLicenciamentoCienciaAprovado() = true`). Marcos: `CIENCIA_APPCI_RENOVACAO` (CIDADAO) + `LIBERACAO_RENOV_APPCI` (SISTEMA). Situação final: `ALVARA_VIGENTE`. | `AppciCienciaRenovacaoService.registrarCienciaAppci()` |
| **RN-153** | Vistoria reprovada (CIV): marco `CIENCIA_CIV_RENOVACAO`. Após correção, retomada via `CIV` → `AGUARDANDO_ACEITE_RENOVACAO`. | `AppciCienciaRenovacaoService.registrarCienciaCiv()` + `retornarDeCivParaAceite()` |
| **RN-154** | "Minhas Renovações" lista licenciamentos em: `AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_CIENCIA_CIV`, `CIV`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `EM_VISTORIA_RENOVACAO`, `RECURSO_EM_ANALISE_1_CIV`, `RECURSO_EM_ANALISE_2_CIV`. | `SituacaoLicenciamento.situacoesMinhasRenovacoes()` |
| **RN-155** | Apenas licenciamentos em `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` são elegíveis para iniciar nova renovação. | `SituacaoLicenciamento.situacoesElegiveisRenovacao()` |
| **RN-156** | Listagem de renovações: com `termo` → busca textual; sem `termo` → listagem paginada. Ambas filtradas pelo CPF do usuário autenticado. | `LicenciamentoRepository.findMinhasRenovacoes()` |
| **RN-157** | `solicitacaoIsencao` e `solicitacaoIsencaoRenovacao` são campos independentes em `tb_licenciamento`. Ambos podem ser definidos simultaneamente sem conflito. Na stack atual: `CHAR(1)` com `'S'/'N'`; na stack moderna: `BOOLEAN` nativo PostgreSQL. | `LicenciamentoEntity.solicitacaoIsencaoRenovacao` |
| **RN-158** | Todos os marcos de renovação registrados via `MarcoRepository.save()` com `tipoMarco`, `tipoResponsavel` e `dataHora = LocalDateTime.now()`. | `marcoRepository.save(...)` em todos os services |
| **RN-159** | Segurança de envolvido implementada via `EnvolvidoAuthorizationService` chamado por `@PreAuthorize("@envolvidoAuthz.verify(#idLic, authentication)")`. Equivale ao `@SegurancaEnvolvidoInterceptor` da stack atual. | `EnvolvidoAuthorizationService.verify()` |
| **RN-160** | Após cada transição de estado relevante, notificações enfileiradas em `tb_licenciamento_notificacao` para envio pelo job P13-D (`NotificacaoService.enfileirarNotificacaoEnvolvidos(lic, RENOVACAO)`). Destinatários: RT Renovação, RU, Proprietários. | `NotificacaoService.enfileirarNotificacaoEnvolvidos()` |

---

## 11. API REST — Endpoints

**Base path:** `/api/v1`
**Autenticação:** Bearer token JWT (OAuth2/OIDC — qualquer IdP compatível; sem dependência do SOE PROCERGS)
**CPF do usuário:** extraído do claim `sub` ou `preferred_username` do JWT conforme configuração do IdP

| Método | Path | Autorização | RNs |
|---|---|---|---|
| `GET` | `/licenciamentos/minha-solicitacoes-renovacao` | `isAuthenticated()` | RN-154, RN-156 |
| `GET` | `/licenciamentos/{idLic}/verificar-elegibilidade-renovacao` | `isAuthenticated()` | RN-155 |
| `POST` | `/licenciamentos/{idLic}/renovacao/iniciar` | `@envolvidoAuthz.verify` | RN-141, 142, 143 |
| `PUT` | `/licenciamentos/{idLic}/renovacao/confirmar` | `@envolvidoAuthz.verify` | RN-145 |
| `PUT` | `/licenciamentos/{idLic}/renovacao/recusar` | `@envolvidoAuthz.verify` | RN-145 |
| `GET` | `/licenciamentos/{idLic}/termo-anexo-d-renovacao` | `@envolvidoAuthz.verify` | RN-144 |
| `PUT` | `/licenciamentos/{idLic}/termo-anexo-d-renovacao` | `@envolvidoAuthz.verify` | RN-144 |
| `DELETE` | `/licenciamentos/{idLic}/termo-anexo-d-renovacao` | `@envolvidoAuthz.verify` | RN-144 |
| `GET` | `/licenciamentos/{idLic}/responsaveis-pagamento-renovacao` | `@envolvidoAuthz.verify` | RN-146 |
| `PUT` | `/licenciamentos/{idLic}/solicitacao-isencao` | `@envolvidoAuthz.verify` | RN-147, 157 |
| `PUT` | `/adm/licenciamentos/{idLic}/isencao-renovacao/analisar` | `ROLE_ADMIN_CBM` | RN-148 |
| `PUT` | `/adm/licenciamentos/{idLic}/distribuir-vistoria-renovacao` | `ROLE_ADMIN_CBM` | RN-150 |
| `PUT` | `/inspetores/vistorias/{idVistoria}/resultado-renovacao` | `ROLE_INSPETOR` | RN-151 |
| `PUT` | `/adm/vistorias/{idVistoria}/homologar-renovacao` | `ROLE_ADMIN_CBM` | RN-151 |
| `PUT` | `/licenciamentos/{idLic}/renovacao/ciencia-appci` | `@envolvidoAuthz.verify` | RN-152 |
| `PUT` | `/licenciamentos/{idLic}/renovacao/ciencia-civ` | `@envolvidoAuthz.verify` | RN-153 |
| `PUT` | `/licenciamentos/{idLic}/renovacao/retomar-apos-civ` | `@envolvidoAuthz.verify` | RN-153 |

### 11.1 Tratamento de erros

```java
@RestControllerAdvice
public class RenovacaoExceptionHandler {

    @ExceptionHandler(RegraNegocioException.class)
    public ResponseEntity<ErroDTO> handleRegraNegocio(RegraNegocioException ex) {
        return ResponseEntity.status(ex.getHttpStatus()).body(ErroDTO.of(ex.getMessage()));
    }

    @ExceptionHandler(EntidadeNaoEncontradaException.class)
    public ResponseEntity<ErroDTO> handleNaoEncontrado(EntidadeNaoEncontradaException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(ErroDTO.of(ex.getMessage()));
    }
}
```

---

## 12. Modelo de Dados

### 12.1 LicenciamentoEntity — campos específicos de renovação

```java
@Entity
@Table(name = "tb_licenciamento")
public class LicenciamentoEntity {
    // ... campos existentes ...

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false)
    private SituacaoLicenciamento situacao;

    /**
     * RN-157: campo INDEPENDENTE de solicitacao_isencao (do licenciamento original).
     * Stack atual (Oracle): IND_SOLICITACAO_ISENCAO_RENOVACAO CHAR(1) via SimNaoBooleanConverter.
     * Stack moderna (PostgreSQL): BOOLEAN nativo.
     */
    @Column(name = "solicitacao_isencao_renovacao", nullable = false)
    private boolean solicitacaoIsencaoRenovacao = false;

    @Column(name = "solicitacao_isencao", nullable = false)
    private boolean solicitacaoIsencao = false;

    @Column(name = "data_hora_atualizacao")
    private LocalDateTime dataHoraAtualizacao;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private List<ResponsavelTecnicoEntity> responsaveisTecnicos = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private List<ResponsavelUsoEntity> responsaveisUso = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private List<LicenciamentoProprietarioEntity> proprietarios = new ArrayList<>();
}
```

### 12.2 AppciEntity

```java
@Entity
@Table(name = "tb_appci")
public class AppciEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Column(name = "numero_pedido")
    private Integer numeroPedido;

    @Column(name = "data_validade")
    private LocalDate dataValidade;

    @Column(name = "data_inicio_vigencia")
    private LocalDate dataInicioVigencia;

    @Column(name = "data_fim_vigencia")
    private LocalDate dataFimVigencia;

    /**
     * Stack atual: IND_VERSAO_VIGENTE CHAR(1) via SimNaoBooleanConverter ('S'/'N').
     * Stack moderna: BOOLEAN nativo do PostgreSQL.
     */
    @Column(name = "versao_vigente", nullable = false)
    private boolean versaoVigente;

    @Column(name = "data_hora_atualizacao")
    private LocalDateTime dataHoraAtualizacao;
}
```

**Queries de APPCI para renovação:**

```java
// AppciRepository
@Query("SELECT a FROM AppciEntity a WHERE a.licenciamento = :lic AND a.versaoVigente = true")
Optional<AppciEntity> findVigenteByLicenciamento(@Param("lic") LicenciamentoEntity lic);
```

### 12.3 VistoriaEntity

```java
@Entity
@Table(name = "tb_vistoria")
public class VistoriaEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_vistoria", nullable = false)
    private TipoVistoria tipoVistoria; // VISTORIA_RENOVACAO para P14

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private StatusVistoria status;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_inspetor")
    private InspetorEntity inspetor;

    @Column(name = "observacoes", length = 2000)
    private String observacoes;

    @Column(name = "data_hora_criacao")
    private LocalDateTime dataHoraCriacao;

    @Column(name = "data_hora_encerramento")
    private LocalDateTime dataHoraEncerramento;
}
```

**Queries de vistoria para renovação:**

```java
// VistoriaRepository
@Query("""
    SELECT v FROM VistoriaEntity v
    WHERE v.licenciamento.id = :idLic
      AND v.tipoVistoria = com.cbmrs.sol.domain.TipoVistoria.VISTORIA_RENOVACAO
      AND v.dataHoraEncerramento IS NOT NULL
    ORDER BY v.dataHoraEncerramento DESC
    LIMIT 1
    """)
Optional<VistoriaEntity> findUltimaEncerradaRenovacaoByLicenciamento(@Param("idLic") Long idLic);
```

### 12.4 LicenciamentoMarcoEntity

```java
@Entity
@Table(name = "tb_licenciamento_marco")
public class LicenciamentoMarcoEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_marco", nullable = false, length = 100)
    private TipoMarco tipoMarco;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_responsavel", nullable = false, length = 20)
    private TipoResponsavelMarco tipoResponsavel;

    @Column(name = "data_hora", nullable = false)
    private LocalDateTime dataHora;
}
```

### 12.5 Marcos de auditoria do P14

| `TipoMarco` | Evento | `TipoResponsavelMarco` |
|---|---|---|
| `ACEITE_ANEXOD_RENOVACAO` | Cidadão aceita o Anexo D da renovação | `CIDADAO` |
| `SOLICITACAO_ISENCAO_RENOVACAO` | Cidadão solicita isenção da taxa de vistoria | `CIDADAO` |
| `ANALISE_ISENCAO_RENOV_APROVADO` | Admin CBMRS defere isenção de taxa | `BOMBEIROS` |
| `ANALISE_ISENCAO_RENOV_REPROVADO` | Admin CBMRS indefere isenção de taxa | `BOMBEIROS` |
| `BOLETO_VISTORIA_RENOVACAO_PPCI` | Sistema gera boleto para taxa de vistoria | `SISTEMA` |
| `LIQUIDACAO_VISTORIA_RENOVACAO` | Pagamento confirmado via CNAB 240 (P13-E) | `SISTEMA` |
| `DISTRIBUICAO_VISTORIA_RENOV` | Admin distribui vistoria para inspetor | `BOMBEIROS` |
| `ENVIO_VISTORIA_RENOVACAO` | Vistoria agendada/enviada | `BOMBEIROS` |
| `ACEITE_VISTORIA_RENOVACAO` | Envolvido aceita resultado da vistoria | `CIDADAO` |
| `FIM_ACEITES_VISTORIA_RENOVACAO` | Todos os envolvidos aceitaram resultado | `SISTEMA` |
| `VISTORIA_RENOVACAO` | Inspetor registra resultado aprovado | `BOMBEIROS` |
| `VISTORIA_RENOVACAO_CIV` | Inspetor registra resultado reprovado | `BOMBEIROS` |
| `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | Admin homologa resultado deferido | `BOMBEIROS` |
| `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` | Admin homologa resultado indeferido / retorna | `BOMBEIROS` |
| `CIENCIA_APPCI_RENOVACAO` | Cidadão/RT toma ciência do novo APPCI | `CIDADAO` |
| `CIENCIA_CIV_RENOVACAO` | Cidadão/RT toma ciência da CIV | `CIDADAO` |
| `LIBERACAO_RENOV_APPCI` | Sistema libera novo APPCI com nova validade | `SISTEMA` |
| `EMISSAO_DOC_COMPLEMENTAR_RENOV` | Sistema emite documentos complementares | `SISTEMA` |

### 12.6 Script Flyway (PostgreSQL)

```sql
-- V14__renovacao_licenciamento.sql

-- Campo de isenção específico da renovação (independente do campo original — RN-157)
ALTER TABLE tb_licenciamento
    ADD COLUMN IF NOT EXISTS solicitacao_isencao_renovacao BOOLEAN NOT NULL DEFAULT FALSE;

-- Índices de performance para o processo de renovação
CREATE INDEX IF NOT EXISTS idx_licenciamento_situacao_renovacao
    ON tb_licenciamento(situacao)
    WHERE situacao IN (
        'AGUARDANDO_ACEITE_RENOVACAO', 'AGUARDANDO_PAGAMENTO_RENOVACAO',
        'AGUARDANDO_DISTRIBUICAO_RENOV', 'EM_VISTORIA_RENOVACAO'
    );

CREATE INDEX IF NOT EXISTS idx_appci_versao_vigente
    ON tb_appci(id_licenciamento, versao_vigente)
    WHERE versao_vigente = true;

CREATE INDEX IF NOT EXISTS idx_vistoria_renovacao
    ON tb_vistoria(id_licenciamento, tipo_vistoria)
    WHERE tipo_vistoria = 'VISTORIA_RENOVACAO';

CREATE INDEX IF NOT EXISTS idx_marco_tipo_lic
    ON tb_licenciamento_marco(id_licenciamento, tipo_marco);
```

---

## 13. Máquina de Estados do Licenciamento

```
[ALVARA_VIGENTE]  [ALVARA_VENCIDO]  [CIV] (após ciência de CIV + correção)
       │                  │               │
       └──────────────────┴───────────────┘
                          │ iniciarRenovacao()
                          ▼
             [AGUARDANDO_ACEITE_RENOVACAO]
                          │
      ┌───────────────────┼──────────────────────────┐
      │ recusar()         │ confirmar()               │ recusar()
      │ (alvará vigente)  │                           │ (alvará vencido)
      ▼                   │                           ▼
 [ALVARA_VIGENTE]         │                    [ALVARA_VENCIDO]
                          │
          ┌───────────────┼───────────────┐
          │ (CIV pendente)│ (sem isenção) │ (isenção aprovada)
          ▼               ▼               ▼
        [CIV]    [AGUARDANDO_       [AGUARDANDO_
                  PAGAMENTO_         DISTRIBUICAO_
                  RENOVACAO]         RENOV]
                          │               │
           (CNAB 240 P13E)│               │
                          ▼               │
                 [AGUARDANDO_             │
                  DISTRIBUICAO_           │
                  RENOV]                  │
                          └───────────────┘
                                    │ distribuirVistoria()
                                    ▼
                        [EM_VISTORIA_RENOVACAO]
                                    │
                   ┌────────────────┴──────────────────┐
                   │ (aprovada)                          │ (reprovada)
                   ▼                                     ▼
             [ALVARA_VIGENTE]                          [CIV]
             cienciaAppci()                    cienciaCiv() ↑
             + LIBERACAO_RENOV_APPCI            retornarDeCivParaAceite()
                                                          │
                                               [AGUARDANDO_ACEITE_RENOVACAO]
```

### 13.1 Tabela completa de transições

| De | Para | Método | Marco | Responsável |
|---|---|---|---|---|
| `ALVARA_VIGENTE` | `AGUARDANDO_ACEITE_RENOVACAO` | `iniciarRenovacao()` | — | CIDADAO |
| `ALVARA_VENCIDO` | `AGUARDANDO_ACEITE_RENOVACAO` | `iniciarRenovacao()` | — | CIDADAO |
| `CIV` | `AGUARDANDO_ACEITE_RENOVACAO` | `retornarDeCivParaAceite()` | — | CIDADAO |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` | `confirmarRenovacao()` | — | CIDADAO |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_DISTRIBUICAO_RENOV` | `analisarIsencao(deferir=true)` | `ANALISE_ISENCAO_RENOV_APROVADO` | BOMBEIROS |
| `AGUARDANDO_ACEITE_RENOVACAO` | `ALVARA_VIGENTE` | `recusarRenovacao()` | — | CIDADAO |
| `AGUARDANDO_ACEITE_RENOVACAO` | `ALVARA_VENCIDO` | `recusarRenovacao()` | — | CIDADAO |
| `AGUARDANDO_ACEITE_RENOVACAO` | `CIV` | `confirmarRenovacao()` (CIV pendente) | — | CIDADAO |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | `AGUARDANDO_DISTRIBUICAO_RENOV` | P13-E CNAB | `LIQUIDACAO_VISTORIA_RENOVACAO` | SISTEMA |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | `EM_VISTORIA_RENOVACAO` | `distribuirVistoria()` | `DISTRIBUICAO_VISTORIA_RENOV` | BOMBEIROS |
| `EM_VISTORIA_RENOVACAO` | `ALVARA_VIGENTE` | `registrarCienciaAppci()` | `CIENCIA_APPCI_RENOVACAO` + `LIBERACAO_RENOV_APPCI` | CIDADAO / SISTEMA |
| `EM_VISTORIA_RENOVACAO` | `CIV` | `registrarCienciaCiv()` | `CIENCIA_CIV_RENOVACAO` | CIDADAO |

---

## 14. Segurança e Autorização

### 14.1 Autenticação — sem dependência de PROCERGS

Na stack atual, a autenticação é obrigatoriamente dependente do **SOE PROCERGS** (meu.rs.gov.br). Na stack moderna, o sistema é configurado como **OAuth2 Resource Server** e aceita tokens JWT de qualquer IdP compatível com OIDC.

```yaml
# application.yml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${OIDC_ISSUER_URI}   # configurado por variável de ambiente
          # Exemplos: Keycloak, AWS Cognito, Azure AD, Google Identity, etc.

sol:
  jwt:
    cpf-claim: ${JWT_CPF_CLAIM:sub}        # nome do claim que contém o CPF do usuário
```

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/api/v1/adm/**").hasRole("ADMIN_CBM")
                .requestMatchers("/api/v1/inspetores/**").hasRole("INSPETOR")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

### 14.2 Extração do CPF do JWT

```java
@Component
public class CpfExtractor {

    @Value("${sol.jwt.cpf-claim:sub}")
    private String cpfClaim;

    public String extrair(Authentication authentication) {
        if (authentication instanceof JwtAuthenticationToken jwtAuth) {
            return jwtAuth.getToken().getClaimAsString(cpfClaim);
        }
        throw new IllegalStateException("Autenticação não é JWT");
    }
}
```

### 14.3 EnvolvidoAuthorizationService (RN-159)

Equivalente ao `@SegurancaEnvolvidoInterceptor` + `@AutorizaEnvolvido` da stack atual:

```java
@Service("envolvidoAuthz")
@RequiredArgsConstructor
public class EnvolvidoAuthorizationService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final CpfExtractor cpfExtractor;

    /**
     * Verifica se o usuário autenticado é um envolvido no licenciamento.
     * Usado em: @PreAuthorize("@envolvidoAuthz.verify(#idLic, authentication)")
     */
    public boolean verify(Long idLic, Authentication authentication) {
        String cpf = cpfExtractor.extrair(authentication);
        LicenciamentoEntity lic = licenciamentoRepository.findById(idLic)
            .orElseThrow(() -> new EntidadeNaoEncontradaException("Licenciamento não encontrado"));

        return isRT(lic, cpf) || isRU(lic, cpf) || isProprietario(lic, cpf);
    }

    private boolean isRT(LicenciamentoEntity lic, String cpf) {
        return lic.getResponsaveisTecnicos().stream()
            .anyMatch(rt -> rt.getUsuario().getCpf().equals(cpf));
    }

    private boolean isRU(LicenciamentoEntity lic, String cpf) {
        return lic.getResponsaveisUso().stream()
            .anyMatch(ru -> ru.getUsuario().getCpf().equals(cpf));
    }

    private boolean isProprietario(LicenciamentoEntity lic, String cpf) {
        return lic.getProprietarios().stream()
            .anyMatch(p -> p.getProprietario().getCpfCnpj().endsWith(cpf)
                       || (p.getProcurador() != null
                           && p.getProcurador().getUsuario().getCpf().equals(cpf)));
    }
}
```

### 14.4 Proteção de dados — LGPD

- CPF e e-mail dos envolvidos são dados pessoais. Logs não devem registrar CPF completo.
- Dados do APPCI (numeração, datas): dados administrativos, não pessoais.
- Diretório de processamento de arquivos CNAB 240: acesso restrito ao usuário do serviço.

---

## 15. Classes e Componentes Java Moderna

### 15.1 Estrutura de pacotes

```
com.cbmrs.sol
├── api/
│   ├── renovacao/
│   │   ├── RenovacaoController.java          ← POST iniciar, PUT confirmar/recusar, retomar
│   │   ├── AnexoDController.java             ← GET/PUT/DELETE termo-anexo-d-renovacao
│   │   ├── PagamentoRenovacaoController.java ← GET responsaveis-pagamento-renovacao
│   │   ├── IsencaoController.java            ← PUT solicitacao-isencao
│   │   └── AppciCienciaController.java       ← PUT ciencia-appci, ciencia-civ
│   └── adm/
│       ├── AdmIsencaoController.java         ← PUT analisar isenção renovação
│       └── AdmVistoriaController.java        ← PUT distribuir e homologar vistoria
├── service/
│   ├── renovacao/
│   │   ├── RenovacaoService.java             ← iniciar, confirmar, recusar
│   │   ├── AnexoDRenovacaoService.java       ← consultar, confirmarAceite, removerAceite
│   │   ├── IsencaoRenovacaoService.java      ← registrar solicitação, analisar
│   │   ├── VistoriaRenovacaoService.java     ← distribuir, registrar resultado, homologar
│   │   └── AppciCienciaRenovacaoService.java ← ciência APPCI, ciência CIV, retomar
│   ├── ResponsavelPagamentoRenovacaoService.java
│   ├── SituacaoTransitionService.java        ← centraliza todas as transições de situação
│   └── NotificacaoService.java               ← enfileira notificações para P13-D
├── validator/
│   └── RenovacaoValidator.java               ← RN-141, RN-142, RN-143
├── security/
│   ├── EnvolvidoAuthorizationService.java    ← @envolvidoAuthz.verify() (RN-159)
│   ├── CpfExtractor.java                     ← Extrai CPF do JWT
│   └── SecurityConfig.java                   ← OAuth2 Resource Server
├── domain/
│   ├── LicenciamentoEntity.java
│   ├── AppciEntity.java
│   ├── VistoriaEntity.java
│   ├── LicenciamentoMarcoEntity.java
│   ├── LicenciamentoSituacaoHistEntity.java
│   ├── ResponsavelTecnicoEntity.java
│   ├── ResponsavelUsoEntity.java
│   ├── LicenciamentoProprietarioEntity.java
│   └── enums/
│       ├── SituacaoLicenciamento.java   ← métodos estáticos para grupos de situações
│       ├── TipoMarco.java               ← inclui todos os marcos de P14
│       ├── TipoVistoria.java            ← inclui VISTORIA_RENOVACAO (ordinal 3)
│       ├── TipoResponsabilidadeTecnica.java  ← inclui RENOVACAO_APPCI
│       ├── TipoResponsavelMarco.java
│       ├── TipoResponsavelPagamento.java
│       ├── StatusVistoria.java
│       └── ContextoNotificacao.java
├── repository/
│   ├── LicenciamentoRepository.java
│   ├── AppciRepository.java
│   ├── VistoriaRepository.java
│   ├── MarcoRepository.java
│   └── SituacaoHistoricoRepository.java
└── dto/
    ├── AppciRenovacaoDTO.java
    ├── AnexoDRenovacaoResponseDTO.java
    ├── IsencaoRenovacaoRequestDTO.java
    ├── ResponsavelPagamentoDTO.java
    └── LicenciamentoResponseDTO.java
```

### 15.2 Dependências Maven (pom.xml)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-mail</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-thymeleaf</artifactId>
</dependency>
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
</dependency>
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <optional>true</optional>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

### 15.3 Comparativo Stack Atual × Stack Moderna

| Componente | Stack Atual (Java EE 7 / WildFly) | Stack Moderna (Spring Boot 3 / JAR) |
|---|---|---|
| Framework | Java EE 7 + WildFly/JBoss | Spring Boot 3.x (JAR executável) |
| EJBs | `@Stateless` + `@TransactionAttribute` | `@Service` + `@Transactional` |
| Injeção de dependência | CDI `@Inject` + `@Qualifier` (10 classes TrocaEstado) | Spring `@Autowired` + Strategy pattern |
| Banco de dados | Oracle + `SimNaoBooleanConverter` (CHAR 'S'/'N') | PostgreSQL + `BOOLEAN` nativo |
| Campo isenção renovação | `IND_SOLICITACAO_ISENCAO_RENOVACAO CHAR(1)` | `solicitacao_isencao_renovacao BOOLEAN` |
| Persistência | Hibernate Criteria API + `entityManager.merge()` | Spring Data JPA + `repository.save()` |
| IdP / Autenticação | **SOE PROCERGS obrigatório** (meu.rs.gov.br) | **Qualquer IdP OIDC** via `${OIDC_ISSUER_URI}` |
| Extração do CPF | `securityContext.getUserPrincipal().getName()` | `JwtAuthenticationToken.getToken().getClaim(...)` |
| Segurança de envolvido | `@SegurancaEnvolvidoInterceptor` (CDI interceptor) | `@PreAuthorize("@envolvidoAuthz.verify(...)")` |
| REST framework | JAX-RS (`@Path`, `@GET`, `@PUT`, `@DELETE`) | Spring MVC (`@RestController`, `@GetMapping`, etc.) |
| E-mail | JavaMail via JNDI `java:jboss/mail/Default` | Spring Mail (`JavaMailSender`) |
| Templates e-mail | `messages.properties` / concatenação de strings | Thymeleaf templates HTML |
| Migrações de banco | Scripts manuais | Flyway automatizado |
| Monitoramento | Logs JBoss | Spring Boot Actuator |

### 15.4 Refatoração do padrão TrocaEstado para Strategy

Na stack atual, existem 10 classes `TrocaEstadoLicenciamento*RN` injetadas via CDI Qualifier. Na stack moderna, substituir por Strategy pattern centralizado:

```java
// Interface da estratégia
public interface SituacaoTransitionStrategy {
    SituacaoLicenciamento getOrigem();
    SituacaoLicenciamento getDestino();
    void executar(LicenciamentoEntity lic, String cpfExecutor);
}

// Serviço centralizador (equivale ao padrão TrocaEstadoLicenciamentoBaseRN)
@Service
@RequiredArgsConstructor
public class SituacaoTransitionService {

    private final Map<String, SituacaoTransitionStrategy> transicoes;
    private final LicenciamentoRepository licenciamentoRepository;
    private final SituacaoHistoricoRepository historicoRepository;

    @Transactional
    public LicenciamentoEntity transicionar(LicenciamentoEntity lic,
            SituacaoLicenciamento destino, String cpfExecutor) {

        String chave = lic.getSituacao() + "_PARA_" + destino;
        SituacaoTransitionStrategy strategy = Optional.ofNullable(transicoes.get(chave))
            .orElseThrow(() -> new RegraNegocioException(
                "Transição não permitida: " + chave, HttpStatus.UNPROCESSABLE_ENTITY));

        // Histórico obrigatório em toda transição (RN-158)
        historicoRepository.save(LicenciamentoSituacaoHistEntity.builder()
            .licenciamento(lic)
            .situacaoAnterior(lic.getSituacao())
            .situacaoAtual(destino)
            .dataHoraSituacaoAnterior(lic.getDataHoraAtualizacao())
            .dataHoraSituacaoAtual(LocalDateTime.now())
            .build());

        strategy.executar(lic, cpfExecutor);
        lic.setSituacao(destino);
        lic.setDataHoraAtualizacao(LocalDateTime.now());
        return licenciamentoRepository.save(lic);
    }
}
```

### 15.5 Casos de teste representativos

| TC | Descrição | Resultado esperado |
|---|---|---|
| TC-P14-01 | Iniciar renovação — `ALVARA_VIGENTE` + RT `RENOVACAO_APPCI` autenticado | Situação → `AGUARDANDO_ACEITE_RENOVACAO`; histórico gravado (RN-141, RN-142) |
| TC-P14-02 | Iniciar renovação — `ALVARA_VENCIDO` | Situação → `AGUARDANDO_ACEITE_RENOVACAO` |
| TC-P14-03 | Iniciar renovação sem RT `RENOVACAO_APPCI` vinculado | HTTP 422 — `"lista-rts-renovacao-vazia"` (RN-142) |
| TC-P14-04 | Iniciar renovação com usuário não envolvido | HTTP 422 — permissão negada (RN-143) |
| TC-P14-05 | Iniciar renovação com licenciamento em `EM_ANALISE` | HTTP 422 — situação inválida (RN-141) |
| TC-P14-06 | Aceitar Anexo D | Marco `ACEITE_ANEXOD_RENOVACAO` registrado; `aceito = true` (RN-144) |
| TC-P14-07 | Remover aceite do Anexo D | Marco deletado; `aceito = false` (RN-144) |
| TC-P14-08 | Confirmar renovação — sem CIV, sem isenção | Situação → `AGUARDANDO_PAGAMENTO_RENOVACAO` (RN-145) |
| TC-P14-09 | Confirmar renovação + isenção aprovada | Situação → `AGUARDANDO_DISTRIBUICAO_RENOV` (RN-145, RN-148) |
| TC-P14-10 | Confirmar renovação — última vistoria `REPROVADO` | Situação → `CIV` (RN-145) |
| TC-P14-11 | Recusar renovação — `APPCI.dataValidade >= hoje` | Situação → `ALVARA_VIGENTE` (RN-145) |
| TC-P14-12 | Recusar renovação — `APPCI.dataValidade < hoje` | Situação → `ALVARA_VENCIDO` (RN-145) |
| TC-P14-13 | Pagamento via CNAB 240 (job P13-E) | Situação → `AGUARDANDO_DISTRIBUICAO_RENOV`; marco `LIQUIDACAO_VISTORIA_RENOVACAO` (RN-149) |
| TC-P14-14 | Admin distribui vistoria | Situação → `EM_VISTORIA_RENOVACAO`; marco `DISTRIBUICAO_VISTORIA_RENOV` (BOMBEIROS) (RN-150) |
| TC-P14-15 | Ciência do APPCI renovado | Marco `CIENCIA_APPCI_RENOVACAO` + `LIBERACAO_RENOV_APPCI`; situação → `ALVARA_VIGENTE` (RN-152) |
| TC-P14-16 | Ciência da CIV | Situação → `CIV`; marco `CIENCIA_CIV_RENOVACAO` (RN-153) |
| TC-P14-17 | Retomar renovação após CIV corrigida | Situação → `AGUARDANDO_ACEITE_RENOVACAO` (RN-153) |
| TC-P14-18 | Listar responsáveis pagamento — RT tipo `EXECUCAO` vinculado | RT tipo `EXECUCAO` NÃO aparece; apenas `RENOVACAO_APPCI` (RN-146) |
| TC-P14-19 | Solicitar isenção renovação | Campo `solicitacaoIsencaoRenovacao = true`; marco `SOLICITACAO_ISENCAO_RENOVACAO` (RN-147) |
| TC-P14-20 | Tokens de IdP diferente do PROCERGS (ex.: Keycloak) | Autenticação funciona; CPF extraído do claim configurado em `${JWT_CPF_CLAIM}` |
| TC-P14-21 | `solicitacaoIsencao` e `solicitacaoIsencaoRenovacao` definidos juntos | Ambos atualizados independentemente (RN-157) |
| TC-P14-22 | Vistoria com `tipoVistoria = PPCI` tentada em P14 | HTTP 400 — tipo de vistoria incorreto (RN-151) |

---



---

## 16. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 03 (ID3601) e Sprint 04 (ID4401, ID4501, Demanda 22) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (itens 6.5.3, 13.2).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P14.

---

### RN-P14-N1 — Dois Tipos de Isenção na Fase de Pagamento da Renovação 🔴 P14-M1

**Prioridade:** CRÍTICA  
**Origem:** ID3601 + P06-M3 — Sprint 03 Hammer

**Descrição:** O P14, Fase 3 (Pagamento ou Isenção), atualmente oferece apenas **um tipo de isenção**. Com o ID3601, devem ser oferecidos dois tipos:
- `PARCIAL_VISTORIA`: isenta **somente esta vistoria** de renovação
- `PARCIAL_FASE_VISTORIA`: isenta toda a fase de vistoria até a emissão do APPCI de renovação

**Mudança no gateway `GW_IsencaoOuPagamento` (P14, Fase 3):**

```
[GW] Pagar ou Solicitar Isenção?
        │
   ┌────┴───────────────────────────────────────┐
   │ PAGAR                                      │ SOLICITAR ISENÇÃO
   │                                            │
   ▼                                            ▼
Gerar boleto (P11)                   Acionar P06-C (novo)
                                        │
                                        ├── PARCIAL_VISTORIA
                                        │   "Isenção somente desta vistoria de renovação"
                                        │
                                        └── PARCIAL_FASE_VISTORIA
                                            "Isenção até o APPCI de renovação"
                                            │
                                    Aguardar aprovação do ADM CBM
                                            │
                                    Retornar ao P14 com resultado
```

**Integração no P14:**
```java
// RenovacaoService.java — Fase 3
public void processarPagamentoOuIsencao(Renovacao renovacao, String opcao) {
    switch (opcao) {
        case "PAGAR" -> boletoService.gerarBoletoRenovacao(renovacao);
        case "ISENCAO" -> {
            // Acionar P06-C para solicitar isenção de renovação
            IsencaoRenovacaoRequest req = IsencaoRenovacaoRequest.builder()
                .idRenovacao(renovacao.getId())
                .tiposDisponiveis(List.of(
                    TipoIsencao.PARCIAL_VISTORIA, TipoIsencao.PARCIAL_FASE_VISTORIA))
                .build();
            isencaoRenovacaoService.iniciarSolicitacao(req);
        }
    }
}
```

**Critérios de Aceitação:**
- [ ] CA-P14-N1a: Fase 3 do P14 exibe opção "Solicitar Isenção" que dispara o P06-C
- [ ] CA-P14-N1b: P06-C oferece apenas `PARCIAL_VISTORIA` e `PARCIAL_FASE_VISTORIA` no contexto de renovação
- [ ] CA-P14-N1c: Após aprovação da isenção, P14 retoma na Fase 4 (distribuição da vistoria)
- [ ] CA-P14-N1d: Tipo de isenção aprovado é registrado no marco do processo de renovação
- [ ] CA-P14-N1e: Após aprovação de `PARCIAL_FASE_VISTORIA`, revistorias no P14 não exigem nova isenção

---

### RN-P14-N2 — Validade do APPCI Parcial Atualizada para 27/12/2027 🟠 P14-M2

**Prioridade:** Alta  
**Origem:** ID4401 — Sprint 04 Hammer

**Descrição:** O P14, ao gerar APPCI parcial na vistoria de renovação, deve usar a data limite **27/12/2027** (anteriormente 27/12/2026), conforme atualização da data parametrizada em P13-N3.

**Cálculo:**
```java
// RenovacaoAppciService.java
public LocalDate calcularValidadeAppciParcialRenovacao(LocalDate dtEmissao) {
    LocalDate dtLimite = configuracaoService.getDate("dt_limite_appci_parcial");
    LocalDate dtPorPrazo = dtEmissao.plusYears(2);
    return dtPorPrazo.isBefore(dtLimite) ? dtPorPrazo : dtLimite;
}
```

**Nota:** A data `27/12/2027` é lida do parâmetro configurável — mesma fonte que P13-N3. Não hard-coded.

**Critérios de Aceitação:**
- [ ] CA-P14-N2a: APPCI parcial de renovação usa `MIN(emissão + 2 anos, 27/12/2027)` como validade
- [ ] CA-P14-N2b: Data é lida do parâmetro configurável `dt_limite_appci_parcial` (não hard-coded)

---

### RN-P14-N3 — Cálculo Automático de Validade do APPCI de Renovação por Ocupação/Risco 🔴 P14-M3

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C3 — RT de Implantação SOL-CBMRS item 6.5.3

**Descrição:** Ao gerar o APPCI de renovação, o P14 deve calcular automaticamente se a validade é de **2 ou 5 anos** com base no `tp_grupo_ocupacao` e `tp_grau_risco` da edificação, conforme a mesma regra do P13-N4.

**Integração com `AppciValidadeCalculadoraRN` (implementado em P13-N4):**

```java
// RenovacaoService.java — Service Task T_GerarAPPCIRenovacao
public Appci gerarAppciRenovacao(Renovacao renovacao) {
    // Calcular validade usando o componente compartilhado de P13
    LocalDate dtValidade = appciValidadeCalculadoraRN
        .calcularDtValidade(renovacao.getLicenciamento(), LocalDate.now());
    
    Appci appci = Appci.builder()
        .idLicenciamento(renovacao.getIdLicenciamento())
        .dtEmissao(LocalDate.now())
        .dtValidade(dtValidade)
        .nrAutenticacao(gerarNrAutenticacao())
        .build();
    
    return appciRepository.save(appci);
}
```

**Critérios de Aceitação:**
- [ ] CA-P14-N3a: APPCI de renovação para Grupo F + risco médio/alto tem validade de 2 anos
- [ ] CA-P14-N3b: APPCI de renovação para risco elevado tem validade de 2 anos
- [ ] CA-P14-N3c: APPCI de renovação para demais casos tem validade de 5 anos
- [ ] CA-P14-N3d: Componente `AppciValidadeCalculadoraRN` é reutilizado (sem duplicação de código com P13)

---

### RN-P14-N4 — Distribuição FIFO das Vistorias de Renovação 🟠 P14-M4

**Prioridade:** Alta  
**Origem:** Oportunidade A2 — Análise de Racionalização + RT de Implantação SOL-CBMRS item 13.2

**Descrição:** A distribuição das vistorias de renovação deve seguir o mesmo critério FIFO do P04 e P07: ordem cronológica de protocolo, com fiscal de menor carga como desempate.

**Implementação análoga a `RN-P07-N4`:**

```java
// VistoriaRenovacaoDistribuicaoService.java
public SugestaoDistribuicaoDTO sugerirProxima() {
    // Reutilizar a lógica de sugestão FIFO do P07, 
    // filtrado para tipo RENOVACAO
    return vistoriaDistribuicaoService.sugerirProxima(TipoVistoria.RENOVACAO);
}
```

**Critérios de Aceitação:**
- [ ] CA-P14-N4a: Sistema sugere a próxima vistoria de renovação em ordem de `dt_protocolo`
- [ ] CA-P14-N4b: Fiscal sugerido é o de menor carga de vistorias ativas
- [ ] CA-P14-N4c: Coordenador pode confirmar ou substituir, com justificativa se substituir

---

### RN-P14-N5 — URL Atualizada e QR Code no APPCI de Renovação 🟡 P14-M5

**Prioridade:** Média  
**Origem:** ID4501 + Demanda 22 / DAS IDI2201 — Sprint 04 Hammer

**Descrição:** O APPCI emitido ao final do P14 deve:
1. Conter a URL atualizada `solcbm.rs.gov.br/solcbm` (em vez de `secweb.procergs.com.br/solcbm`)
2. Incluir **QR Code de autenticação** no canto superior direito

**URL:** Lida do parâmetro `APP_URL_BASE` configurado em P01-N2 (RF-27). Todos os relatórios `.jrxml` devem usar o parâmetro, não URL hard-coded.

**QR Code:** Mesmo componente especificado em P03-N6:
```xml
<!-- APPCI_Renovacao.jrxml -->
<jr:BarcodeComponent type="QRCode" moduleWidth="2.0">
    <jr:codeExpression>
        <![CDATA[$P{APP_URL_BASE} + "/autenticacao?id=" + $F{nrAutenticacao}]]>
    </jr:codeExpression>
</jr:BarcodeComponent>
```

**Critérios de Aceitação:**
- [ ] CA-P14-N5a: APPCI de renovação contém URL `solcbm.rs.gov.br/solcbm` (não a URL antiga)
- [ ] CA-P14-N5b: APPCI de renovação com `nr_autenticacao` exibe QR Code legível
- [ ] CA-P14-N5c: QR Code aponta para `solcbm.rs.gov.br/solcbm/autenticacao?id={nr_autenticacao}`
- [ ] CA-P14-N5d: Ambas as mudanças (URL e QR Code) usam os mesmos componentes de P01-N2 e P03-N6 (sem duplicação)

---

### Resumo das Mudanças P14 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P14-M1 | RN-P14-N1 | Dois tipos de isenção na Fase 3 de renovação — P06-C (OBRIGATÓRIO) | 🔴 Crítica |
| P14-M3 | RN-P14-N3 | Cálculo automático de validade APPCI (2 ou 5 anos) por ocupação/risco (OBRIGATÓRIO) | 🔴 Crítica |
| P14-M2 | RN-P14-N2 | Validade APPCI parcial: data limite 27/12/2027 (parâmetro configurável) | 🟠 Alta |
| P14-M4 | RN-P14-N4 | Distribuição FIFO das vistorias de renovação | 🟠 Alta |
| P14-M5 | RN-P14-N5 | URL atualizada + QR Code no APPCI de renovação | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 03–04 + Normas RTCBMRS*

*Documento gerado em 2026-03-16 (v1.1 — atualizado v2.1 em 25/03/2026). Regras de Negócio: RN-141 a RN-160. Referências: `Requisitos_P14_RenovacaoLicenciamento_StackAtual.md` · `Descritivo_P14_FluxoBPMN_StackAtual.md` · código-fonte `SOLCBM.BackEnd16-06` (pacotes `licenciamentorenovacao`, `licenciamento.trocaestado`, `licenciamentociencia`).*
