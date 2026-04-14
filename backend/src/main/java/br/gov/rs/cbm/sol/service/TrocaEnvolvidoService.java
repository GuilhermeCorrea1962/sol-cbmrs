package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.MarcoProcesso;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.exception.ResourceNotFoundException;
import br.gov.rs.cbm.sol.repository.LicenciamentoRepository;
import br.gov.rs.cbm.sol.repository.MarcoProcessoRepository;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Set;

/**
 * Servico de Troca de Envolvidos (P09) do sistema SOL.
 *
 * Gerencia a substituicao do Responsavel Tecnico (RT) e do Responsavel pelo Uso (RU)
 * em um licenciamento existente.
 *
 * A troca de envolvidos e um fluxo lateral: nao altera o status principal do
 * licenciamento — apenas atualiza os campos responsavelTecnico / responsavelUso
 * e registra marcos de auditoria.
 *
 * Fluxo troca RT (3 passos):
 *   [solicitar-troca-rt]  --> marco TROCA_RT_SOLICITADA   (RT permanece o atual)
 *   [autorizar-troca-rt]  --> marco TROCA_RT_AUTORIZADA   (RT permanece o atual)
 *   [efetivar-troca-rt]   --> marco TROCA_RT_EFETIVADA    (RT = novo RT)
 *
 * Fluxo troca RU (1 passo para ADMIN):
 *   [efetivar-troca-ru]   --> marco TROCA_RU_EFETIVADA    (RU = novo RU)
 *
 * Regras de negocio:
 *   RN-P09-001: novoResponsavelId obrigatorio nas operacoes de efetivacao
 *   RN-P09-002: novo RT/RU deve existir no sistema como usuario ativo
 *   RN-P09-003: troca RT requer autorizacao previa (3 passos); troca RU e direta (1 passo ADMIN)
 *   RN-P09-004: operacoes nao permitidas em licenciamentos EXTINTO, INDEFERIDO ou RENOVADO
 *   RN-P09-005: motivo obrigatorio para solicitacao de troca RT
 */
@Service
@Transactional(readOnly = true)
public class TrocaEnvolvidoService {

    /** Status que impedem qualquer troca de envolvido (processo encerrado). */
    private static final Set<StatusLicenciamento> STATUS_BLOQUEADOS = Set.of(
        StatusLicenciamento.EXTINTO,
        StatusLicenciamento.INDEFERIDO,
        StatusLicenciamento.RENOVADO
    );

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public TrocaEnvolvidoService(LicenciamentoRepository licenciamentoRepository,
                                 UsuarioRepository usuarioRepository,
                                 MarcoProcessoRepository marcoProcessoRepository,
                                 LicenciamentoService licenciamentoService,
                                 EmailService emailService) {
        this.licenciamentoRepository = licenciamentoRepository;
        this.usuarioRepository       = usuarioRepository;
        this.marcoProcessoRepository = marcoProcessoRepository;
        this.licenciamentoService    = licenciamentoService;
        this.emailService            = emailService;
    }

    // ---------------------------------------------------------------------------
    // Troca RT -- Passo 1: Solicitacao -- RT atual / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Registra solicitacao de troca do Responsavel Tecnico.
     *
     * RN-P09-004: licenciamento nao pode estar em status terminal.
     * RN-P09-005: motivo obrigatorio.
     *
     * O RT atual permanece vinculado ate a efetivacao.
     * Marco: TROCA_RT_SOLICITADA.
     * Notifica o ADMIN (analista atribuido) sobre a solicitacao.
     *
     * @param licId      ID do licenciamento
     * @param motivo     justificativa da troca (obrigatorio)
     * @param keycloakId sub do JWT do solicitante
     */
    @Transactional
    public LicenciamentoDTO solicitarTrocaRt(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        validarStatusPermitido(lic);

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-P09-005",
                "O motivo da solicitacao de troca do Responsavel Tecnico e obrigatorio. "
                + "Descreva a justificativa para a substituicao.");
        }

        Usuario solicitante = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.TROCA_RT_SOLICITADA, solicitante,
            "Troca de Responsavel Tecnico solicitada. Motivo: " + motivo);

        // Notifica analista atribuido (se houver) sobre a solicitacao
        if (lic.getAnalista() != null && lic.getAnalista().getEmail() != null) {
            emailService.notificarAsync(
                lic.getAnalista().getEmail(),
                "SOL - Solicitacao de troca de RT (licenciamento ID " + licId + ")",
                "Foi registrada uma solicitacao de troca do Responsavel Tecnico para o "
                + "licenciamento ID " + licId + ".\n\n"
                + "Motivo informado: " + motivo + "\n\n"
                + "Acesse o sistema SOL para autorizar ou recusar a solicitacao.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Troca RT -- Passo 2: Autorizacao -- ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Autoriza a troca do Responsavel Tecnico pendente.
     *
     * RN-P09-004: licenciamento nao pode estar em status terminal.
     *
     * O RT atual permanece vinculado ate a efetivacao pelo novo RT.
     * Marco: TROCA_RT_AUTORIZADA.
     * Notifica o RT atual sobre a autorizacao.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao do ADMIN (opcional)
     * @param keycloakId sub do JWT do ADMIN que autoriza
     */
    @Transactional
    public LicenciamentoDTO autorizarTrocaRt(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        validarStatusPermitido(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Troca de Responsavel Tecnico autorizada."
            + (observacao != null && !observacao.isBlank() ? " " + observacao : "");
        registrarMarco(lic, TipoMarco.TROCA_RT_AUTORIZADA, responsavel, obsMarco);

        // Notifica RT atual sobre autorizacao
        if (lic.getResponsavelTecnico() != null
                && lic.getResponsavelTecnico().getEmail() != null) {
            emailService.notificarAsync(
                lic.getResponsavelTecnico().getEmail(),
                "SOL - Troca de RT autorizada (licenciamento ID " + licId + ")",
                "A solicitacao de troca do Responsavel Tecnico para o licenciamento ID "
                + licId + " foi AUTORIZADA.\n\n"
                + (observacao != null && !observacao.isBlank()
                    ? "Observacao: " + observacao + "\n\n" : "")
                + "O novo Responsavel Tecnico devera ser indicado para efetivacao da troca.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Troca RT -- Passo 3: Efetivacao -- ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Efetiva a troca do Responsavel Tecnico.
     *
     * RN-P09-001: novoResponsavelId obrigatorio.
     * RN-P09-002: novo RT deve existir no sistema como usuario ativo.
     * RN-P09-004: licenciamento nao pode estar em status terminal.
     *
     * Efeito: responsavelTecnico = novo RT.
     * Marco: TROCA_RT_EFETIVADA.
     * Notifica o novo RT e o RU por e-mail.
     *
     * @param licId            ID do licenciamento
     * @param novoRtId         ID do novo Responsavel Tecnico
     * @param observacao       observacao complementar (opcional)
     * @param keycloakId       sub do JWT do ADMIN que efetiva
     */
    @Transactional
    public LicenciamentoDTO efetivarTrocaRt(Long licId, Long novoRtId,
                                            String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        validarStatusPermitido(lic);

        if (novoRtId == null) {
            throw new BusinessException("RN-P09-001",
                "O ID do novo Responsavel Tecnico e obrigatorio para efetivar a troca.");
        }

        Usuario novoRt = usuarioRepository.findById(novoRtId)
            .orElseThrow(() -> new BusinessException("RN-P09-002",
                "Usuario ID " + novoRtId + " nao encontrado no sistema SOL. "
                + "O novo Responsavel Tecnico deve estar cadastrado."));

        String rtAnteriorNome = lic.getResponsavelTecnico() != null
            ? lic.getResponsavelTecnico().getNome() : "nao informado";

        lic.setResponsavelTecnico(novoRt);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Responsavel Tecnico substituido. Anterior: " + rtAnteriorNome
            + ". Novo RT: " + novoRt.getNome() + "."
            + (observacao != null && !observacao.isBlank() ? " " + observacao : "");
        registrarMarco(lic, TipoMarco.TROCA_RT_EFETIVADA, responsavel, obsMarco);

        // Notifica novo RT
        if (novoRt.getEmail() != null) {
            emailService.notificarAsync(
                novoRt.getEmail(),
                "SOL - Voce foi designado como RT (licenciamento ID " + licId + ")",
                "Voce foi designado como novo Responsavel Tecnico do licenciamento ID "
                + licId + ".\n\n"
                + (observacao != null && !observacao.isBlank()
                    ? "Observacao: " + observacao + "\n\n" : "")
                + "Acesse o sistema SOL para consultar os detalhes do licenciamento.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        // Notifica RU
        if (lic.getResponsavelUso() != null
                && lic.getResponsavelUso().getEmail() != null) {
            String emailNovoRt = novoRt.getEmail() != null ? novoRt.getEmail() : "";
            if (!lic.getResponsavelUso().getEmail().equalsIgnoreCase(emailNovoRt)) {
                emailService.notificarAsync(
                    lic.getResponsavelUso().getEmail(),
                    "SOL - Troca de RT efetivada (licenciamento ID " + licId + ")",
                    "O Responsavel Tecnico do licenciamento ID " + licId
                    + " foi substituido.\n\n"
                    + "Novo Responsavel Tecnico: " + novoRt.getNome() + "\n\n"
                    + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                    + "Sistema Online de Licenciamento -- SOL");
            }
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Troca RU -- Efetivacao direta -- ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Efetiva a troca do Responsavel pelo Uso (RU).
     *
     * A troca de RU nao requer autorizacao previa — e executada diretamente pelo ADMIN.
     *
     * RN-P09-001: novoResponsavelId obrigatorio.
     * RN-P09-002: novo RU deve existir no sistema como usuario ativo.
     * RN-P09-004: licenciamento nao pode estar em status terminal.
     *
     * Efeito: responsavelUso = novo RU.
     * Marco: TROCA_RU_EFETIVADA.
     * Notifica o novo RU e o RT por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param novoRuId   ID do novo Responsavel pelo Uso
     * @param observacao observacao complementar (opcional)
     * @param keycloakId sub do JWT do ADMIN que efetiva
     */
    @Transactional
    public LicenciamentoDTO efetivarTrocaRu(Long licId, Long novoRuId,
                                            String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        validarStatusPermitido(lic);

        if (novoRuId == null) {
            throw new BusinessException("RN-P09-001",
                "O ID do novo Responsavel pelo Uso e obrigatorio para efetivar a troca.");
        }

        Usuario novoRu = usuarioRepository.findById(novoRuId)
            .orElseThrow(() -> new BusinessException("RN-P09-002",
                "Usuario ID " + novoRuId + " nao encontrado no sistema SOL. "
                + "O novo Responsavel pelo Uso deve estar cadastrado."));

        String ruAnteriorNome = lic.getResponsavelUso() != null
            ? lic.getResponsavelUso().getNome() : "nao informado";

        lic.setResponsavelUso(novoRu);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Responsavel pelo Uso substituido. Anterior: " + ruAnteriorNome
            + ". Novo RU: " + novoRu.getNome() + "."
            + (observacao != null && !observacao.isBlank() ? " " + observacao : "");
        registrarMarco(lic, TipoMarco.TROCA_RU_EFETIVADA, responsavel, obsMarco);

        // Notifica novo RU
        if (novoRu.getEmail() != null) {
            emailService.notificarAsync(
                novoRu.getEmail(),
                "SOL - Voce foi designado como RU (licenciamento ID " + licId + ")",
                "Voce foi designado como novo Responsavel pelo Uso do licenciamento ID "
                + licId + ".\n\n"
                + (observacao != null && !observacao.isBlank()
                    ? "Observacao: " + observacao + "\n\n" : "")
                + "Acesse o sistema SOL para consultar os detalhes do licenciamento.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        // Notifica RT
        if (lic.getResponsavelTecnico() != null
                && lic.getResponsavelTecnico().getEmail() != null) {
            String emailNovoRu = novoRu.getEmail() != null ? novoRu.getEmail() : "";
            if (!lic.getResponsavelTecnico().getEmail().equalsIgnoreCase(emailNovoRu)) {
                emailService.notificarAsync(
                    lic.getResponsavelTecnico().getEmail(),
                    "SOL - Troca de RU efetivada (licenciamento ID " + licId + ")",
                    "O Responsavel pelo Uso do licenciamento ID " + licId
                    + " foi substituido.\n\n"
                    + "Novo Responsavel pelo Uso: " + novoRu.getNome() + "\n\n"
                    + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                    + "Sistema Online de Licenciamento -- SOL");
            }
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Helpers internos
    // ---------------------------------------------------------------------------

    private void validarStatusPermitido(Licenciamento lic) {
        if (STATUS_BLOQUEADOS.contains(lic.getStatus())) {
            throw new BusinessException("RN-P09-004",
                "Nao e possivel realizar troca de envolvidos em licenciamentos com status "
                + lic.getStatus() + ". O processo ja foi encerrado.");
        }
    }

    private Licenciamento buscarPorId(Long id) {
        return licenciamentoRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));
    }

    private void registrarMarco(Licenciamento lic, TipoMarco tipo,
                                Usuario usuario, String observacao) {
        marcoProcessoRepository.save(
            MarcoProcesso.builder()
                .tipoMarco(tipo)
                .licenciamento(lic)
                .usuario(usuario)
                .observacao(observacao)
                .build()
        );
    }
}
