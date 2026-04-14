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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

/**
 * Servico de Vistoria Presencial (P07) do sistema SOL.
 *
 * Responsabilidades:
 *   - Consultar fila de vistoria (VISTORIA_PENDENTE) e vistorias em andamento (EM_VISTORIA)
 *   - Agendar vistoria presencial (RN-P07-001 / RN-P07-002)
 *   - Atribuir inspetor ao licenciamento (RN-P07-003)
 *   - Iniciar vistoria (RN-P07-003 / RN-P07-004)
 *   - Emitir CIV com observacao obrigatoria (RN-P07-005 / RN-P07-006)
 *   - Aprovar vistoria, transicionando para PRPCI_EMITIDO (RN-P07-007)
 *   - Registrar ciencia do CIV pelo interessado (RN-P07-008)
 *   - Retomar vistoria apos correcao das inconformidades (RN-P07-009)
 *   - Notificar envolvidos por e-mail em cada transicao
 *
 * Maquina de estados P07:
 *   DEFERIDO          --[agendar-vistoria]-------> VISTORIA_PENDENTE
 *   VISTORIA_PENDENTE --[iniciar-vistoria]-------> EM_VISTORIA
 *   EM_VISTORIA       --[emitir-civ]-----------> CIV_EMITIDO
 *   EM_VISTORIA       --[aprovar-vistoria]-------> PRPCI_EMITIDO
 *   CIV_EMITIDO       --[registrar-ciencia-civ]--> CIV_CIENCIA
 *   CIV_CIENCIA       --[retomar-vistoria]-------> EM_VISTORIA
 *
 * Marcos registrados:
 *   VISTORIA_AGENDADA  -- agendamento da vistoria
 *   VISTORIA_REALIZADA -- inicio da vistoria (e retomada apos CIV)
 *   CIV_EMITIDO        -- emissao do Comunicado de Inconformidade na Vistoria
 *   CIV_CIENCIA        -- ciencia do CIV pelo interessado
 *   VISTORIA_APROVADA  -- aprovacao da vistoria (-> PRPCI_EMITIDO)
 */
@Service
@Transactional(readOnly = true)
public class VistoriaService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public VistoriaService(LicenciamentoRepository licenciamentoRepository,
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

    /** Lista licenciamentos aguardando vistoria (VISTORIA_PENDENTE), paginado. */
    public Page<LicenciamentoDTO> findFila(Pageable pageable) {
        return licenciamentoRepository
            .findByStatus(StatusLicenciamento.VISTORIA_PENDENTE, pageable)
            .map(licenciamentoService::toDTO);
    }

    /** Lista vistorias em andamento (EM_VISTORIA), paginado. */
    public Page<LicenciamentoDTO> findEmAndamento(Pageable pageable) {
        return licenciamentoRepository
            .findByStatus(StatusLicenciamento.EM_VISTORIA, pageable)
            .map(licenciamentoService::toDTO);
    }

    /** Lista licenciamentos atribuidos ao inspetor informado, paginado. */
    public Page<LicenciamentoDTO> findByInspetor(Long inspetorId, Pageable pageable) {
        Usuario inspetor = usuarioRepository.findById(inspetorId)
            .orElseThrow(() -> new ResourceNotFoundException("Inspetor", inspetorId));
        return licenciamentoRepository.findByInspetor(inspetor, pageable)
            .map(licenciamentoService::toDTO);
    }

    // ---------------------------------------------------------------------------
    // Agendamento de vistoria -- ANALISTA / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Agenda a vistoria presencial para o licenciamento.
     *
     * RN-P07-001: licenciamento deve estar em status DEFERIDO.
     * RN-P07-002: dataVistoria e obrigatoria.
     *
     * Transicao: DEFERIDO -> VISTORIA_PENDENTE.
     * Marco: VISTORIA_AGENDADA com a data registrada na observacao.
     * Notifica RT, RU e inspetor (se ja atribuido) por e-mail.
     *
     * @param licId        ID do licenciamento
     * @param dataVistoria data prevista para a vistoria
     * @param observacao   informacoes complementares (opcional)
     * @param keycloakId   sub do JWT do responsavel pelo agendamento
     */
    @Transactional
    public LicenciamentoDTO agendarVistoria(Long licId, LocalDate dataVistoria,
                                            String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.DEFERIDO) {
            throw new BusinessException("RN-P07-001",
                "A vistoria so pode ser agendada em licenciamentos com status DEFERIDO. "
                + "Status atual: " + lic.getStatus());
        }

        if (dataVistoria == null) {
            throw new BusinessException("RN-P07-002",
                "A data da vistoria e obrigatoria. "
                + "Informe a data prevista para a realizacao da vistoria presencial.");
        }

        lic.setStatus(StatusLicenciamento.VISTORIA_PENDENTE);
        licenciamentoRepository.save(lic);

        String obsMarco = "Vistoria presencial agendada para " + dataVistoria
            + (observacao != null && !observacao.isBlank() ? ". " + observacao : "");

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.VISTORIA_AGENDADA, responsavel, obsMarco);

        String corpoEmail = "Foi agendada uma vistoria presencial para o licenciamento ID "
            + licId + ".\n\nData prevista: " + dataVistoria
            + (observacao != null && !observacao.isBlank() ? "\n\nObservacoes: " + observacao : "")
            + "\n\nAcesse o sistema SOL para acompanhar o andamento.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL";

        notificarEnvolvidos(lic,
            "SOL - Vistoria presencial agendada (licenciamento ID " + licId + ")",
            corpoEmail);

        if (lic.getInspetor() != null && lic.getInspetor().getEmail() != null) {
            emailService.notificarAsync(
                lic.getInspetor().getEmail(),
                "SOL - Vistoria presencial agendada (licenciamento ID " + licId + ")",
                "Prezado(a) " + lic.getInspetor().getNome() + ",\n\n"
                + "Voce esta atribuido a vistoria presencial do licenciamento ID "
                + licId + ".\n\nData prevista: " + dataVistoria
                + "\n\nAcesse o sistema SOL para mais detalhes.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Atribuicao de inspetor -- ADMIN / CHEFE_SSEG_BBM
    // ---------------------------------------------------------------------------

    /**
     * Atribui um inspetor ao licenciamento.
     *
     * Nao altera o status do licenciamento. Pode ser realizado a qualquer momento,
     * desde que o licenciamento exista. Notifica o inspetor por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param inspetorId ID do usuario inspetor a ser atribuido
     * @param keycloakId sub do JWT do responsavel pela atribuicao
     */
    @Transactional
    public LicenciamentoDTO atribuirInspetor(Long licId, Long inspetorId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        Usuario inspetor = usuarioRepository.findById(inspetorId)
            .orElseThrow(() -> new ResourceNotFoundException("Inspetor", inspetorId));

        lic.setInspetor(inspetor);
        licenciamentoRepository.save(lic);

        emailService.notificarAsync(
            inspetor.getEmail(),
            "SOL - Vistoria atribuida (licenciamento ID " + licId + ")",
            "Prezado(a) " + inspetor.getNome() + ",\n\n"
            + "Voce foi atribuido(a) como inspetor(a) responsavel pelo licenciamento ID "
            + licId + ".\n"
            + "Status atual: " + lic.getStatus() + "\n\n"
            + "Acesse o sistema SOL para acompanhar o agendamento da vistoria.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Inicio da vistoria -- INSPETOR / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Inicia a vistoria presencial.
     *
     * RN-P07-003: status deve ser VISTORIA_PENDENTE.
     * RN-P07-004: inspetor deve estar atribuido ao licenciamento.
     *
     * Transicao: VISTORIA_PENDENTE -> EM_VISTORIA.
     * Marco: VISTORIA_REALIZADA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do inspetor que esta iniciando
     */
    @Transactional
    public LicenciamentoDTO iniciarVistoria(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.VISTORIA_PENDENTE) {
            throw new BusinessException("RN-P07-003",
                "A vistoria so pode ser iniciada em licenciamentos com status VISTORIA_PENDENTE. "
                + "Status atual: " + lic.getStatus());
        }

        if (lic.getInspetor() == null) {
            throw new BusinessException("RN-P07-004",
                "Nenhum inspetor atribuido a este licenciamento. "
                + "Realize a atribuicao do inspetor antes de iniciar a vistoria.");
        }

        lic.setStatus(StatusLicenciamento.EM_VISTORIA);
        licenciamentoRepository.save(lic);

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.VISTORIA_REALIZADA, usuario,
            "Vistoria presencial iniciada. Inspetor: " + lic.getInspetor().getNome());

        notificarEnvolvidos(lic,
            "SOL - Vistoria presencial iniciada (licenciamento ID " + licId + ")",
            "A vistoria presencial do licenciamento ID " + licId
            + " foi iniciada pelo inspetor " + lic.getInspetor().getNome() + ".\n\n"
            + "Acesse o sistema SOL para acompanhar o resultado.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Emissao de CIV -- INSPETOR / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Emite o Comunicado de Inconformidade na Vistoria (CIV).
     *
     * RN-P07-005: status deve ser EM_VISTORIA.
     * RN-P07-006: observacao com as inconformidades e obrigatoria.
     *
     * Transicao: EM_VISTORIA -> CIV_EMITIDO.
     * Marco: CIV_EMITIDO com as inconformidades registradas.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao descricao das inconformidades encontradas (obrigatoria)
     * @param keycloakId sub do JWT do inspetor
     */
    @Transactional
    public LicenciamentoDTO emitirCiv(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_VISTORIA) {
            throw new BusinessException("RN-P07-005",
                "O CIV so pode ser emitido em licenciamentos com status EM_VISTORIA. "
                + "Status atual: " + lic.getStatus());
        }

        if (observacao == null || observacao.isBlank()) {
            throw new BusinessException("RN-P07-006",
                "A observacao e obrigatoria ao emitir um CIV. "
                + "Descreva as inconformidades encontradas na vistoria presencial.");
        }

        lic.setStatus(StatusLicenciamento.CIV_EMITIDO);
        licenciamentoRepository.save(lic);

        Usuario inspetor = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.CIV_EMITIDO, inspetor, "CIV emitido: " + observacao);

        notificarEnvolvidos(lic,
            "SOL - Comunicado de Inconformidade na Vistoria (CIV) emitido (licenciamento ID " + licId + ")",
            "Foi emitido um Comunicado de Inconformidade na Vistoria (CIV) para o "
            + "licenciamento ID " + licId + ".\n\n"
            + "Inconformidades identificadas:\n" + observacao + "\n\n"
            + "Voce tem 30 dias corridos para tomar ciencia e corrigir as inconformidades "
            + "apontadas. Acesse o sistema SOL para consultar os detalhes.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Aprovacao da vistoria -- INSPETOR / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Aprova a vistoria presencial, emitindo o PRPCI.
     *
     * RN-P07-007: status deve ser EM_VISTORIA.
     *
     * Transicao: EM_VISTORIA -> PRPCI_EMITIDO.
     * Marco: VISTORIA_APROVADA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao complementar (opcional)
     * @param keycloakId sub do JWT do inspetor
     */
    @Transactional
    public LicenciamentoDTO aprovarVistoria(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.EM_VISTORIA) {
            throw new BusinessException("RN-P07-007",
                "A aprovacao da vistoria so pode ocorrer em licenciamentos com status EM_VISTORIA. "
                + "Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.PRPCI_EMITIDO);
        licenciamentoRepository.save(lic);

        Usuario inspetor = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = (observacao != null && !observacao.isBlank())
            ? observacao
            : "Vistoria presencial aprovada. PRPCI emitido.";
        registrarMarco(lic, TipoMarco.VISTORIA_APROVADA, inspetor, obsMarco);

        notificarEnvolvidos(lic,
            "SOL - Vistoria presencial aprovada (licenciamento ID " + licId + ")",
            "A vistoria presencial do licenciamento ID " + licId
            + " foi APROVADA. O Parecer de Resultado da Pesquisa de Campo do Inspetor "
            + "(PRPCI) foi emitido.\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Observacao do inspetor: " + observacao + "\n\n" : "")
            + "O processo seguira para a emissao do APPCI. "
            + "Acesse o sistema SOL para acompanhar.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Ciencia do CIV pelo interessado -- CIDADAO / RT / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Registra a ciencia do CIV pelo interessado.
     *
     * RN-P07-008: status deve ser CIV_EMITIDO.
     *
     * Transicao: CIV_EMITIDO -> CIV_CIENCIA.
     * Marco: CIV_CIENCIA.
     * Notifica o inspetor por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao do interessado (opcional)
     * @param keycloakId sub do JWT do interessado
     */
    @Transactional
    public LicenciamentoDTO registrarCienciaCiv(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.CIV_EMITIDO) {
            throw new BusinessException("RN-P07-008",
                "A ciencia do CIV so pode ser registrada em licenciamentos com status CIV_EMITIDO. "
                + "Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.CIV_CIENCIA);
        licenciamentoRepository.save(lic);

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = (observacao != null && !observacao.isBlank())
            ? "Ciencia do CIV registrada: " + observacao
            : "Ciencia do CIV registrada pelo interessado. Correcoes em andamento.";
        registrarMarco(lic, TipoMarco.CIV_CIENCIA, usuario, obsMarco);

        if (lic.getInspetor() != null && lic.getInspetor().getEmail() != null) {
            emailService.notificarAsync(
                lic.getInspetor().getEmail(),
                "SOL - Ciencia do CIV registrada (licenciamento ID " + licId + ")",
                "O interessado registrou ciencia do CIV para o licenciamento ID "
                + licId + ".\n\n"
                + (observacao != null && !observacao.isBlank()
                    ? "Observacao: " + observacao + "\n\n" : "")
                + "Aguarde o prazo para correcao das inconformidades antes de retomar a vistoria.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Retomada da vistoria -- INSPETOR / ADMIN
    // ---------------------------------------------------------------------------

    /**
     * Retoma a vistoria apos a correcao das inconformidades pelo interessado.
     *
     * RN-P07-009: status deve ser CIV_CIENCIA.
     *
     * Transicao: CIV_CIENCIA -> EM_VISTORIA.
     * Marco: VISTORIA_REALIZADA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do inspetor
     */
    @Transactional
    public LicenciamentoDTO retomarVistoria(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (lic.getStatus() != StatusLicenciamento.CIV_CIENCIA) {
            throw new BusinessException("RN-P07-009",
                "A retomada da vistoria so pode ocorrer em licenciamentos com status CIV_CIENCIA. "
                + "Status atual: " + lic.getStatus());
        }

        lic.setStatus(StatusLicenciamento.EM_VISTORIA);
        licenciamentoRepository.save(lic);

        Usuario inspetor = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.VISTORIA_REALIZADA, inspetor,
            "Vistoria retomada apos correcao das inconformidades do CIV.");

        notificarEnvolvidos(lic,
            "SOL - Vistoria presencial retomada (licenciamento ID " + licId + ")",
            "A vistoria presencial do licenciamento ID " + licId
            + " foi retomada apos a ciencia e correcao das inconformidades do CIV.\n\n"
            + "Acesse o sistema SOL para acompanhar o resultado da nova vistoria.\n\n"
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
