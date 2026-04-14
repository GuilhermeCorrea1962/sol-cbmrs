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
 * Servico de Isencao de Taxa (P06) do sistema SOL.
 *
 * Permite que o cidadao ou RT solicite isencao da taxa de licenciamento,
 * e que o ADMIN ou CHEFE_SSEG_BBM defira ou indefira a solicitacao.
 *
 * A isencao e um fluxo lateral (nao altera o status principal do licenciamento)
 * exceto pelo registro de marcos e pela atualizacao dos campos isentoTaxa e
 * obsIsencao na entidade Licenciamento.
 *
 * Fluxo:
 *   [solicitar-isencao]  --> marco ISENCAO_SOLICITADA  (isentoTaxa permanece false)
 *   [deferir-isencao]    --> marco ISENCAO_DEFERIDA    (isentoTaxa = true)
 *   [indeferir-isencao]  --> marco ISENCAO_INDEFERIDA  (isentoTaxa = false)
 *
 * Regras de negocio:
 *   RN-P06-001: solicitacao exige motivo descritivo
 *   RN-P06-002: isencao so pode ser solicitada em licenciamentos ativos
 *               (nao EXTINTO, nao INDEFERIDO, nao RENOVADO)
 *   RN-P06-003: motivo do indeferimento e obrigatorio
 *   RN-P06-004: nao e permitido deferir isencao ja deferida (isentoTaxa = true)
 */
@Service
@Transactional(readOnly = true)
public class IsencaoService {

    /** Status que impedem a solicitacao de isencao (processo encerrado). */
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

    public IsencaoService(LicenciamentoRepository licenciamentoRepository,
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
    // Solicitacao de isencao -- CIDADAO / RT / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Registra solicitacao de isencao de taxa para o licenciamento.
     *
     * RN-P06-001: motivo obrigatorio.
     * RN-P06-002: licenciamento nao pode estar em status terminal
     *             (EXTINTO, INDEFERIDO, RENOVADO).
     *
     * Marco: ISENCAO_SOLICITADA.
     * O campo isentoTaxa permanece false ate decisao do ADMIN.
     *
     * @param licId      ID do licenciamento
     * @param motivo     justificativa da solicitacao de isencao
     * @param keycloakId sub do JWT do solicitante
     */
    @Transactional
    public LicenciamentoDTO solicitarIsencao(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-P06-001",
                "O motivo da solicitacao de isencao e obrigatorio. "
                + "Descreva a justificativa para a isencao da taxa.");
        }

        if (STATUS_BLOQUEADOS.contains(lic.getStatus())) {
            throw new BusinessException("RN-P06-002",
                "Nao e possivel solicitar isencao para licenciamentos com status "
                + lic.getStatus() + ". O processo ja foi encerrado.");
        }

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.ISENCAO_SOLICITADA, usuario,
            "Isencao de taxa solicitada. Motivo: " + motivo);

        // Notifica analista atribuido (se houver) sobre a solicitacao
        if (lic.getAnalista() != null && lic.getAnalista().getEmail() != null) {
            emailService.notificarAsync(
                lic.getAnalista().getEmail(),
                "SOL - Solicitacao de isencao de taxa (licenciamento ID " + licId + ")",
                "Foi registrada uma solicitacao de isencao de taxa para o "
                + "licenciamento ID " + licId + ".\n\n"
                + "Motivo informado: " + motivo + "\n\n"
                + "Acesse o sistema SOL para avaliar a solicitacao.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Deferimento da isencao -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Defere a solicitacao de isencao de taxa.
     *
     * RN-P06-004: isencao nao pode ser deferida se ja estiver deferida.
     *
     * Efeitos:
     *   - isentoTaxa = true
     *   - obsIsencao = observacao
     * Marco: ISENCAO_DEFERIDA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao complementar (opcional)
     * @param keycloakId sub do JWT do responsavel pela decisao
     */
    @Transactional
    public LicenciamentoDTO deferirIsencao(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (Boolean.TRUE.equals(lic.getIsentoTaxa())) {
            throw new BusinessException("RN-P06-004",
                "Este licenciamento ja possui isencao de taxa deferida.");
        }

        lic.setIsentoTaxa(true);
        lic.setObsIsencao(observacao != null && !observacao.isBlank()
            ? observacao : "Isencao de taxa deferida.");
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.ISENCAO_DEFERIDA, responsavel,
            "Isencao de taxa deferida. "
            + (observacao != null && !observacao.isBlank() ? observacao : ""));

        notificarEnvolvidos(lic,
            "SOL - Isencao de taxa deferida (licenciamento ID " + licId + ")",
            "A solicitacao de isencao de taxa para o licenciamento ID " + licId
            + " foi DEFERIDA.\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Observacao: " + observacao + "\n\n" : "")
            + "Nenhuma taxa sera cobrada para este licenciamento.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Indeferimento da isencao -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Indefere a solicitacao de isencao de taxa.
     *
     * RN-P06-003: motivo do indeferimento e obrigatorio.
     *
     * Efeitos:
     *   - isentoTaxa permanece false
     *   - obsIsencao = "Indeferido: " + motivo
     * Marco: ISENCAO_INDEFERIDA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param motivo     motivo do indeferimento (obrigatorio)
     * @param keycloakId sub do JWT do responsavel pela decisao
     */
    @Transactional
    public LicenciamentoDTO indeferirIsencao(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-P06-003",
                "O motivo do indeferimento da isencao e obrigatorio.");
        }

        lic.setIsentoTaxa(false);
        lic.setObsIsencao("Isencao indeferida. Motivo: " + motivo);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.ISENCAO_INDEFERIDA, responsavel,
            "Isencao de taxa indeferida. Motivo: " + motivo);

        notificarEnvolvidos(lic,
            "SOL - Solicitacao de isencao de taxa indeferida (licenciamento ID " + licId + ")",
            "A solicitacao de isencao de taxa para o licenciamento ID " + licId
            + " foi INDEFERIDA.\n\n"
            + "Motivo: " + motivo + "\n\n"
            + "A taxa de licenciamento devera ser recolhida normalmente. "
            + "Para recorrer desta decisao, acesse o sistema SOL.\n\n"
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
