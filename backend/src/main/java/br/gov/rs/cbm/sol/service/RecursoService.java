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
 * Servico de Recurso CIA/CIV (P10) do sistema SOL.
 *
 * Permite que o interessado interponha recurso administrativo contra um
 * Comunicado de Inconformidade na Analise (CIA) ou na Vistoria (CIV),
 * e que o ADMIN ou CHEFE_SSEG_BBM analise e decida o recurso.
 *
 * Maquina de estados P10:
 *   CIA_CIENCIA  --[interpor-recurso]--> RECURSO_PENDENTE
 *   CIV_CIENCIA  --[interpor-recurso]--> RECURSO_PENDENTE
 *   RECURSO_PENDENTE --[iniciar-recurso]--> EM_RECURSO
 *   EM_RECURSO   --[deferir-recurso]---> DEFERIDO
 *   EM_RECURSO   --[indeferir-recurso]-> INDEFERIDO
 *
 * Regras de negocio:
 *   RN-P10-001: recurso so admissivel em CIA_CIENCIA ou CIV_CIENCIA
 *   RN-P10-002: motivo obrigatorio ao interpor recurso
 *   RN-P10-003: analise do recurso so pode ser iniciada em RECURSO_PENDENTE
 *   RN-P10-004: deferimento e indeferimento so permitidos em EM_RECURSO
 *   RN-P10-005: motivo obrigatorio para indeferimento do recurso
 *
 * RN-089 (norma): durante o recurso (RECURSO_PENDENTE ou EM_RECURSO)
 *   o licenciamento fica bloqueado para qualquer outra acao de fluxo principal.
 *   O bloqueio e garantido pelas validacoes de status em cada servico.
 */
@Service
@Transactional(readOnly = true)
public class RecursoService {

    /** Status que admitem interposicao de recurso. */
    private static final Set<StatusLicenciamento> STATUS_RECURSO_ADMISSIVEL = Set.of(
        StatusLicenciamento.CIA_CIENCIA,
        StatusLicenciamento.CIV_CIENCIA
    );

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public RecursoService(LicenciamentoRepository licenciamentoRepository,
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
    // Interposicao de Recurso -- CIDADAO / RT / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Registra a interposicao de recurso contra CIA ou CIV.
     *
     * RN-P10-001: status deve ser CIA_CIENCIA ou CIV_CIENCIA.
     * RN-P10-002: motivo da interposicao e obrigatorio.
     *
     * Transicao: CIA_CIENCIA | CIV_CIENCIA -> RECURSO_PENDENTE.
     * Marco: RECURSO_INTERPOSTO.
     * Notifica analista (se atribuido) sobre o recurso interposto.
     *
     * @param licId      ID do licenciamento
     * @param motivo     fundamentacao do recurso (obrigatorio)
     * @param keycloakId sub do JWT do interessado que interpos o recurso
     */
    @Transactional
    public LicenciamentoDTO interporRecurso(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (!STATUS_RECURSO_ADMISSIVEL.contains(lic.getStatus())) {
            throw new BusinessException("RN-P10-001",
                "O recurso so pode ser interposto quando o licenciamento estiver em "
                + "CIA_CIENCIA ou CIV_CIENCIA. Status atual: " + lic.getStatus());
        }

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-P10-002",
                "O motivo da interposicao do recurso e obrigatorio. "
                + "Apresente a fundamentacao tecnica ou juridica do recurso.");
        }

        String origemRecurso = lic.getStatus().name(); // CIA_CIENCIA ou CIV_CIENCIA
        lic.setStatus(StatusLicenciamento.RECURSO_PENDENTE);
        licenciamentoRepository.save(lic);

        Usuario solicitante = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.RECURSO_INTERPOSTO, solicitante,
            "Recurso interposto contra " + origemRecurso + ". Motivo: " + motivo);

        // Notifica analista sobre o recurso
        if (lic.getAnalista() != null && lic.getAnalista().getEmail() != null) {
            emailService.notificarAsync(
                lic.getAnalista().getEmail(),
                "SOL - Recurso interposto (licenciamento ID " + licId + ")",
                "Foi interposto um recurso administrativo para o licenciamento ID "
                + licId + " (contra " + origemRecurso + ").\n\n"
                + "Fundamentacao: " + motivo + "\n\n"
                + "O licenciamento aguarda analise do recurso pelo setor competente.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Inicio da Analise do Recurso -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Inicia a analise administrativa do recurso interposto.
     *
     * RN-P10-003: status deve ser RECURSO_PENDENTE.
     *
     * Transicao: RECURSO_PENDENTE -> EM_RECURSO.
     * Marco: RECURSO_EM_ANALISE.
     * Notifica RT e RU por e-mail sobre o inicio da analise.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao de abertura (opcional)
     * @param keycloakId sub do JWT do responsavel pela analise
     */
    @Transactional
    public LicenciamentoDTO iniciarRecurso(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.RECURSO_PENDENTE) {
            throw new BusinessException("RN-P10-003",
                "A analise do recurso so pode ser iniciada em licenciamentos com status "
                + "RECURSO_PENDENTE. Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.EM_RECURSO);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Analise do recurso iniciada."
            + (observacao != null && !observacao.isBlank() ? " " + observacao : "");
        registrarMarco(lic, TipoMarco.RECURSO_EM_ANALISE, responsavel, obsMarco);

        notificarEnvolvidos(lic,
            "SOL - Recurso em analise (licenciamento ID " + licId + ")",
            "O recurso interposto para o licenciamento ID " + licId
            + " encontra-se EM ANALISE pelo setor competente do CBMRS.\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Observacao: " + observacao + "\n\n" : "")
            + "Aguarde a decisao administrativa.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Deferimento do Recurso -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Defere o recurso administrativo, aprovando o licenciamento.
     *
     * RN-P10-004: status deve ser EM_RECURSO.
     *
     * O deferimento do recurso significa que o CIA ou CIV foi considerado
     * improcedente: o edificio esta em conformidade e o licenciamento e
     * aprovado (DEFERIDO).
     *
     * Transicao: EM_RECURSO -> DEFERIDO.
     * Marco: RECURSO_DEFERIDO.
     * Notifica RT e RU por e-mail sobre o resultado favoravel.
     *
     * @param licId      ID do licenciamento
     * @param observacao fundamentacao da decisao (opcional)
     * @param keycloakId sub do JWT do responsavel pela decisao
     */
    @Transactional
    public LicenciamentoDTO deferirRecurso(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_RECURSO) {
            throw new BusinessException("RN-P10-004",
                "O deferimento do recurso so e permitido em licenciamentos com status "
                + "EM_RECURSO. Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.DEFERIDO);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Recurso DEFERIDO. Licenciamento aprovado."
            + (observacao != null && !observacao.isBlank() ? " Fundamentacao: " + observacao : "");
        registrarMarco(lic, TipoMarco.RECURSO_DEFERIDO, responsavel, obsMarco);

        notificarEnvolvidos(lic,
            "SOL - Recurso DEFERIDO (licenciamento ID " + licId + ")",
            "O recurso administrativo referente ao licenciamento ID " + licId
            + " foi DEFERIDO.\n\n"
            + "O comunicado de inconformidade foi considerado improcedente e o "
            + "licenciamento esta APROVADO.\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Fundamentacao: " + observacao + "\n\n" : "")
            + "Acesse o sistema SOL para acompanhar as proximas etapas.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Indeferimento do Recurso -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Indefere o recurso administrativo, encerrando o licenciamento.
     *
     * RN-P10-004: status deve ser EM_RECURSO.
     * RN-P10-005: motivo do indeferimento e obrigatorio.
     *
     * O indeferimento do recurso significa que o CIA ou CIV foi considerado
     * procedente: as inconformidades apontadas sao validas e o licenciamento
     * e encerrado como INDEFERIDO.
     *
     * Transicao: EM_RECURSO -> INDEFERIDO.
     * Marco: RECURSO_INDEFERIDO.
     * Notifica RT e RU por e-mail sobre o resultado desfavoravel.
     *
     * @param licId      ID do licenciamento
     * @param motivo     fundamentacao do indeferimento (obrigatorio)
     * @param keycloakId sub do JWT do responsavel pela decisao
     */
    @Transactional
    public LicenciamentoDTO indeferirRecurso(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_RECURSO) {
            throw new BusinessException("RN-P10-004",
                "O indeferimento do recurso so e permitido em licenciamentos com status "
                + "EM_RECURSO. Status atual: " + lic.getStatus());
        }

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-P10-005",
                "O motivo do indeferimento do recurso e obrigatorio. "
                + "Apresente a fundamentacao tecnica ou juridica da decisao.");
        }

        lic.setStatus(StatusLicenciamento.INDEFERIDO);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.RECURSO_INDEFERIDO, responsavel,
            "Recurso INDEFERIDO. Motivo: " + motivo);

        notificarEnvolvidos(lic,
            "SOL - Recurso INDEFERIDO (licenciamento ID " + licId + ")",
            "O recurso administrativo referente ao licenciamento ID " + licId
            + " foi INDEFERIDO.\n\n"
            + "As inconformidades apontadas no comunicado foram mantidas e o "
            + "licenciamento e considerado INDEFERIDO.\n\n"
            + "Motivo: " + motivo + "\n\n"
            + "Para mais informacoes, acesse o sistema SOL ou contate o CBMRS.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Helpers internos
    // ---------------------------------------------------------------------------

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

    private void notificarEnvolvidos(Licenciamento lic, String assunto, String corpo) {
        if (lic.getResponsavelTecnico() != null
                && lic.getResponsavelTecnico().getEmail() != null) {
            emailService.notificarAsync(
                lic.getResponsavelTecnico().getEmail(), assunto, corpo);
        }
        if (lic.getResponsavelUso() != null
                && lic.getResponsavelUso().getEmail() != null) {
            String emailRt = lic.getResponsavelTecnico() != null
                ? lic.getResponsavelTecnico().getEmail() : "";
            if (!lic.getResponsavelUso().getEmail().equalsIgnoreCase(emailRt)) {
                emailService.notificarAsync(
                    lic.getResponsavelUso().getEmail(), assunto, corpo);
            }
        }
    }
}
