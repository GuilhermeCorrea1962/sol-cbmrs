package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.MarcoProcessoDTO;
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

/**
 * Servico de Ciencia de CIA e Retomada de Analise (P05) do sistema SOL.
 *
 * O P05 cobre o ciclo de inconformidade apos a emissao de um CIA pelo analista:
 *
 *   CIA_EMITIDO
 *     --[registrarCienciaCia]--> CIA_CIENCIA   (cidadao/RT confirma recebimento)
 *     --[retomarAnalise]-------> EM_ANALISE    (analista retoma apos correcao)
 *
 * Apos a retomada, o analista pode:
 *   - Deferir   (EM_ANALISE -> DEFERIDO)       via AnaliseService
 *   - Emitir novo CIA (EM_ANALISE -> CIA_EMITIDO) via AnaliseService
 *   - Indeferir (EM_ANALISE -> INDEFERIDO)     via AnaliseService
 *
 * Regras de negocio:
 *   RN-P05-001: ciencia so pode ser registrada em CIA_EMITIDO
 *   RN-P05-002: retomada de analise so pode ocorrer em CIA_CIENCIA
 *
 * Marcos registrados: CIA_CIENCIA, INICIO_ANALISE (reuso na retomada)
 */
@Service
@Transactional(readOnly = true)
public class CienciaService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public CienciaService(LicenciamentoRepository licenciamentoRepository,
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
    // Registro de ciencia do CIA -- CIDADAO / RT / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Registra a ciencia do Comunicado de Inconformidade na Analise (CIA).
     *
     * RN-P05-001: status deve ser CIA_EMITIDO.
     *
     * Transicao: CIA_EMITIDO -> CIA_CIENCIA.
     * Marco: CIA_CIENCIA.
     * Notifica o analista responsavel por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao do cidadao/RT ao tomar ciencia (opcional)
     * @param keycloakId sub do JWT do usuario que esta tomando ciencia
     */
    @Transactional
    public LicenciamentoDTO registrarCienciaCia(Long licId, String observacao,
                                                String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.CIA_EMITIDO) {
            throw new BusinessException("RN-P05-001",
                "A ciencia do CIA so pode ser registrada em licenciamentos com status "
                + "CIA_EMITIDO. Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.CIA_CIENCIA);
        licenciamentoRepository.save(lic);

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = (observacao != null && !observacao.isBlank())
            ? "Ciencia registrada. " + observacao
            : "Ciencia do CIA registrada pelo interessado.";
        registrarMarco(lic, TipoMarco.CIA_CIENCIA, usuario, obsMarco);

        // Notifica o analista atribuido
        if (lic.getAnalista() != null && lic.getAnalista().getEmail() != null) {
            emailService.notificarAsync(
                lic.getAnalista().getEmail(),
                "SOL - Ciencia do CIA registrada (licenciamento ID " + licId + ")",
                "Prezado(a) " + lic.getAnalista().getNome() + ",\n\n"
                + "O interessado registrou ciencia do Comunicado de Inconformidade "
                + "na Analise (CIA) para o licenciamento ID " + licId + ".\n\n"
                + (observacao != null && !observacao.isBlank()
                    ? "Observacao do interessado: " + observacao + "\n\n" : "")
                + "Aguarde a correcao dos itens apontados e retome a analise "
                + "quando adequado.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Retomada de analise apos correcao -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Retoma a analise tecnica apos o interessado ter corrigido as inconformidades
     * e registrado ciencia do CIA.
     *
     * RN-P05-002: status deve ser CIA_CIENCIA.
     *
     * Transicao: CIA_CIENCIA -> EM_ANALISE.
     * Marco: INICIO_ANALISE (retomada).
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do analista que esta retomando
     */
    @Transactional
    public LicenciamentoDTO retomarAnalise(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.CIA_CIENCIA) {
            throw new BusinessException("RN-P05-002",
                "A retomada de analise so pode ocorrer em licenciamentos com status "
                + "CIA_CIENCIA. Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.EM_ANALISE);
        licenciamentoRepository.save(lic);

        Usuario analista = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.INICIO_ANALISE, analista,
            "Analise tecnica retomada apos ciencia do CIA e correcao das inconformidades. "
            + "Analista: " + (analista != null ? analista.getNome() : keycloakId));

        // Notifica RT e RU
        notificarEnvolvidos(lic,
            "SOL - Analise tecnica retomada (licenciamento ID " + licId + ")",
            "A analise tecnica do licenciamento ID " + licId
            + " foi retomada pelo analista responsavel.\n\n"
            + "O processo voltou ao status EM_ANALISE. "
            + "Acompanhe o andamento pelo sistema SOL.\n\n"
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
