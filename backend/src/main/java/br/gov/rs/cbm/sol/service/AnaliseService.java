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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

/**
 * Servico de Analise Tecnica (P04) do sistema SOL.
 *
 * Responsabilidades:
 *   - Consultar fila de analise (ANALISE_PENDENTE) e processos em andamento (EM_ANALISE)
 *   - Distribuir licenciamentos a analistas (RN-P04-001)
 *   - Iniciar analise tecnica (RN-P04-002 / RN-P04-003)
 *   - Emitir CIA com observacao obrigatoria (RN-P04-004 / RN-P04-005)
 *   - Deferir licenciamento (RN-P04-006)
 *   - Indeferir licenciamento com motivo obrigatorio (RN-P04-007 / RN-P04-008)
 *   - Listar marcos do processo (historico de eventos)
 *   - Notificar envolvidos por e-mail em cada transicao
 *
 * Maquina de estados P04:
 *   ANALISE_PENDENTE --[distribuir]--> ANALISE_PENDENTE (analista setado)
 *   ANALISE_PENDENTE --[iniciarAnalise]--> EM_ANALISE
 *   EM_ANALISE       --[emitirCia]-----> CIA_EMITIDO
 *   EM_ANALISE       --[deferir]-------> DEFERIDO
 *   EM_ANALISE       --[indeferir]-----> INDEFERIDO
 */
@Service
@Transactional(readOnly = true)
public class AnaliseService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public AnaliseService(LicenciamentoRepository licenciamentoRepository,
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
    // Consultas
    // ---------------------------------------------------------------------------

    /** Lista licenciamentos aguardando analise (status ANALISE_PENDENTE), paginado. */
    public Page<LicenciamentoDTO> findFila(Pageable pageable) {
        return licenciamentoRepository
            .findByStatus(StatusLicenciamento.ANALISE_PENDENTE, pageable)
            .map(licenciamentoService::toDTO);
    }

    /** Lista licenciamentos em andamento (status EM_ANALISE), paginado. */
    public Page<LicenciamentoDTO> findEmAndamento(Pageable pageable) {
        return licenciamentoRepository
            .findByStatus(StatusLicenciamento.EM_ANALISE, pageable)
            .map(licenciamentoService::toDTO);
    }

    /** Lista licenciamentos atribuidos ao analista informado, paginado. */
    public Page<LicenciamentoDTO> findByAnalista(Long analistaId, Pageable pageable) {
        Usuario analista = usuarioRepository.findById(analistaId)
            .orElseThrow(() -> new ResourceNotFoundException("Analista", analistaId));
        return licenciamentoRepository.findByAnalista(analista, pageable)
            .map(licenciamentoService::toDTO);
    }

    /**
     * Lista todos os marcos do processo de um licenciamento em ordem cronologica.
     * Representa o historico completo de eventos do licenciamento.
     */
    public List<MarcoProcessoDTO> findMarcos(Long licenciamentoId) {
        if (!licenciamentoRepository.existsById(licenciamentoId)) {
            throw new ResourceNotFoundException("Licenciamento", licenciamentoId);
        }
        return marcoProcessoRepository
            .findByLicenciamentoIdOrderByDtMarcoAsc(licenciamentoId)
            .stream()
            .map(this::toMarcoDTO)
            .collect(Collectors.toList());
    }

    // ---------------------------------------------------------------------------
    // Distribuicao -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Atribui um analista ao licenciamento (distribuicao).
     *
     * RN-P04-001: licenciamento deve estar em ANALISE_PENDENTE.
     *
     * Nao altera o status — o licenciamento permanece em ANALISE_PENDENTE ate
     * que o analista chame iniciarAnalise(). Registra marco DISTRIBUICAO e
     * notifica o analista por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param analistaId ID do usuario analista a ser atribuido
     * @param keycloakId sub do JWT do responsavel pela distribuicao
     */
    @Transactional
    public LicenciamentoDTO distribuir(Long licId, Long analistaId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.ANALISE_PENDENTE) {
            throw new BusinessException("RN-P04-001",
                "Apenas licenciamentos em ANALISE_PENDENTE podem ser distribuidos. "
                + "Status atual: " + lic.getStatus());
        }

        Usuario analista = usuarioRepository.findById(analistaId)
            .orElseThrow(() -> new ResourceNotFoundException("Analista", analistaId));

        lic.setAnalista(analista);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.DISTRIBUICAO, responsavel,
            "Licenciamento distribuido para analise. Analista: " + analista.getNome());

        emailService.notificarAsync(
            analista.getEmail(),
            "SOL - Licenciamento atribuido para analise",
            "Prezado(a) " + analista.getNome() + ",\n\n"
            + "O licenciamento ID " + licId + " foi atribuido a voce para analise tecnica.\n"
            + "Acesse o sistema SOL para iniciar o processo de analise.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Inicio de Analise -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Inicia a analise tecnica do licenciamento.
     *
     * RN-P04-002: status deve ser ANALISE_PENDENTE.
     * RN-P04-003: analista deve estar atribuido (distribuicao realizada).
     *
     * Transicao: ANALISE_PENDENTE -> EM_ANALISE.
     * Marco: INICIO_ANALISE.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do analista que esta iniciando
     */
    @Transactional
    public LicenciamentoDTO iniciarAnalise(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.ANALISE_PENDENTE) {
            throw new BusinessException("RN-P04-002",
                "A analise so pode ser iniciada em licenciamentos com status ANALISE_PENDENTE. "
                + "Status atual: " + lic.getStatus());
        }

        if (lic.getAnalista() == null) {
            throw new BusinessException("RN-P04-003",
                "Nenhum analista atribuido a este licenciamento. "
                + "Realize a distribuicao antes de iniciar a analise.");
        }

        lic.setStatus(StatusLicenciamento.EM_ANALISE);
        licenciamentoRepository.save(lic);

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.INICIO_ANALISE, usuario,
            "Analise tecnica iniciada. Analista: "
            + (usuario != null ? usuario.getNome() : keycloakId));

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Emissao de CIA -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Emite Comunicado de Inconformidade na Analise (CIA).
     *
     * RN-P04-004: status deve ser EM_ANALISE.
     * RN-P04-005: observacao obrigatoria descrevendo as inconformidades.
     *
     * Transicao: EM_ANALISE -> CIA_EMITIDO.
     * Marco: CIA_EMITIDO com a observacao registrada.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao descricao das inconformidades encontradas
     * @param keycloakId sub do JWT do analista
     */
    @Transactional
    public LicenciamentoDTO emitirCia(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_ANALISE) {
            throw new BusinessException("RN-P04-004",
                "A CIA so pode ser emitida em licenciamentos com status EM_ANALISE. "
                + "Status atual: " + lic.getStatus());
        }

        if (observacao == null || observacao.isBlank()) {
            throw new BusinessException("RN-P04-005",
                "A observacao e obrigatoria ao emitir uma CIA. "
                + "Descreva as inconformidades encontradas na analise tecnica.");
        }

        lic.setStatus(StatusLicenciamento.CIA_EMITIDO);
        licenciamentoRepository.save(lic);

        Usuario analista = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.CIA_EMITIDO, analista, "CIA emitida: " + observacao);

        notificarEnvolvidos(lic,
            "SOL - Comunicado de Inconformidade na Analise (CIA) emitido",
            "Foi emitido um Comunicado de Inconformidade na Analise (CIA) para o "
            + "licenciamento ID " + licId + ".\n\n"
            + "Inconformidades identificadas:\n" + observacao + "\n\n"
            + "Voce tem 30 dias corridos para tomar ciencia e corrigir as inconformidades "
            + "apontadas. Acesse o sistema SOL para consultar os detalhes.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Deferimento -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Defere o licenciamento (analise tecnica aprovada).
     *
     * RN-P04-006: status deve ser EM_ANALISE.
     *
     * Transicao: EM_ANALISE -> DEFERIDO.
     * Marco: APROVACAO_ANALISE.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao complementar (opcional)
     * @param keycloakId sub do JWT do analista
     */
    @Transactional
    public LicenciamentoDTO deferir(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_ANALISE) {
            throw new BusinessException("RN-P04-006",
                "O deferimento so pode ocorrer em licenciamentos com status EM_ANALISE. "
                + "Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.DEFERIDO);
        licenciamentoRepository.save(lic);

        Usuario analista = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = (observacao != null && !observacao.isBlank())
            ? observacao
            : "Analise tecnica aprovada. Licenciamento deferido.";
        registrarMarco(lic, TipoMarco.APROVACAO_ANALISE, analista, obsMarco);

        notificarEnvolvidos(lic,
            "SOL - Licenciamento deferido",
            "A analise tecnica do licenciamento ID " + licId
            + " foi concluida com DEFERIMENTO.\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Observacao do analista: " + observacao + "\n\n" : "")
            + "O processo seguira para a proxima etapa. "
            + "Acesse o sistema SOL para acompanhar.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Indeferimento -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Indefere o licenciamento (analise tecnica reprovada).
     *
     * RN-P04-007: status deve ser EM_ANALISE.
     * RN-P04-008: motivo do indeferimento e obrigatorio.
     *
     * Transicao: EM_ANALISE -> INDEFERIDO.
     * Marco: REPROVACAO_ANALISE com o motivo registrado.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao motivo do indeferimento (obrigatorio)
     * @param keycloakId sub do JWT do analista
     */
    @Transactional
    public LicenciamentoDTO indeferir(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_ANALISE) {
            throw new BusinessException("RN-P04-007",
                "O indeferimento so pode ocorrer em licenciamentos com status EM_ANALISE. "
                + "Status atual: " + lic.getStatus());
        }

        if (observacao == null || observacao.isBlank()) {
            throw new BusinessException("RN-P04-008",
                "O motivo do indeferimento e obrigatorio.");
        }

        lic.setStatus(StatusLicenciamento.INDEFERIDO);
        licenciamentoRepository.save(lic);

        Usuario analista = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.REPROVACAO_ANALISE, analista,
            "Licenciamento indeferido. Motivo: " + observacao);

        notificarEnvolvidos(lic,
            "SOL - Licenciamento indeferido",
            "A analise tecnica do licenciamento ID " + licId
            + " foi concluida com INDEFERIMENTO.\n\n"
            + "Motivo: " + observacao + "\n\n"
            + "O interessado pode interpor recurso administrativo no prazo de "
            + "30 dias uteis a contar desta data.\n\n"
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
            // Evita enviar duplicado se RT e RU forem o mesmo e-mail
            if (!lic.getResponsavelUso().getEmail().equalsIgnoreCase(emailRt)) {
                emailService.notificarAsync(
                    lic.getResponsavelUso().getEmail(), assunto, corpo);
            }
        }
    }

    public MarcoProcessoDTO toMarcoDTO(MarcoProcesso m) {
        return new MarcoProcessoDTO(
            m.getId(),
            m.getTipoMarco(),
            m.getObservacao(),
            m.getLicenciamento() != null ? m.getLicenciamento().getId() : null,
            m.getUsuario()       != null ? m.getUsuario().getId()       : null,
            m.getUsuario()       != null ? m.getUsuario().getNome()     : null,
            m.getDtMarco()
        );
    }
}
