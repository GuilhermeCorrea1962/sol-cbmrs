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
 * Servico de Extincao de Licenciamento (P12) do sistema SOL.
 *
 * Gerencia o encerramento definitivo de um licenciamento, com dois fluxos:
 *
 * Fluxo P12-A — Extincao via solicitacao do cidadao/RT:
 *   [solicitar-extincao]  --> marco EXTINCAO_SOLICITADA  (status nao muda)
 *   [efetivar-extincao]   --> marco EXTINCAO_EFETIVADA   (status -> EXTINTO, ativo = false)
 *
 * Fluxo P12-B — Extincao administrativa direta (ADMIN/CHEFE_SSEG_BBM):
 *   [efetivar-extincao]   --> marco EXTINCAO_EFETIVADA   (status -> EXTINTO, ativo = false)
 *
 * Status admissiveis para extincao (maquina de estados):
 *   ANALISE_PENDENTE, APPCI_EMITIDO, SUSPENSO
 *
 * Regras de negocio:
 *   RN-109: Extincao so pode ser solicitada/efetivada em status admissivel.
 *   RN-110: Motivo e obrigatorio para solicitar extincao.
 *   RN-111: Motivo e obrigatorio para efetivar extincao.
 *   RN-112: Ao efetivar, status muda para EXTINTO e ativo = false.
 *   RN-113: Licenciamento EXTINTO e estado terminal — sem operacoes subsequentes.
 *   RN-114: Cidadao/RT solicita; ADMIN/CHEFE_SSEG_BBM efetiva ou extingue diretamente.
 */
@Service
@Transactional(readOnly = true)
public class ExtincaoService {

    /**
     * Status a partir dos quais a extincao pode ser solicitada ou efetivada.
     * Alinhado com validarTransicaoStatus de LicenciamentoService:
     *   ANALISE_PENDENTE -> EXTINTO
     *   APPCI_EMITIDO    -> EXTINTO
     *   SUSPENSO         -> EXTINTO
     */
    private static final Set<StatusLicenciamento> STATUS_EXTINCAO_ADMISSIVEL = Set.of(
        StatusLicenciamento.ANALISE_PENDENTE,
        StatusLicenciamento.APPCI_EMITIDO,
        StatusLicenciamento.SUSPENSO
    );

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public ExtincaoService(LicenciamentoRepository licenciamentoRepository,
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
    // Solicitacao de extincao -- CIDADAO / RT / ADMIN (P12-A)
    // ---------------------------------------------------------------------------

    /**
     * Registra a solicitacao de extincao do licenciamento pelo cidadao ou RT.
     *
     * RN-109: Status do licenciamento deve estar em STATUS_EXTINCAO_ADMISSIVEL.
     * RN-110: Motivo e obrigatorio.
     *
     * Nao altera o status do licenciamento — apenas registra o marco
     * EXTINCAO_SOLICITADA e notifica o analista responsavel para avaliacao.
     *
     * @param licId      ID do licenciamento
     * @param motivo     justificativa da solicitacao (obrigatorio)
     * @param keycloakId sub do JWT do solicitante
     * @return LicenciamentoDTO atualizado
     */
    @Transactional
    public LicenciamentoDTO solicitarExtincao(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-110",
                "O motivo da solicitacao de extincao e obrigatorio. "
                + "Descreva a justificativa para o encerramento do licenciamento.");
        }

        if (!STATUS_EXTINCAO_ADMISSIVEL.contains(lic.getStatus())) {
            throw new BusinessException("RN-109",
                "Extincao nao pode ser solicitada para licenciamento com status "
                + lic.getStatus() + ". Status admissiveis: "
                + STATUS_EXTINCAO_ADMISSIVEL + ".");
        }

        Usuario solicitante = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.EXTINCAO_SOLICITADA, solicitante,
            "Extincao solicitada. Motivo: " + motivo);

        // Notifica analista atribuido (se houver)
        if (lic.getAnalista() != null && lic.getAnalista().getEmail() != null) {
            emailService.notificarAsync(
                lic.getAnalista().getEmail(),
                "SOL - Solicitacao de extincao de licenciamento (ID " + licId + ")",
                "Foi registrada uma solicitacao de extincao para o licenciamento ID " + licId
                + ".\n\n"
                + "Motivo informado: " + motivo + "\n\n"
                + "Acesse o sistema SOL para avaliar e efetivar ou recusar a extincao.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");
        }

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Efetivacao da extincao -- ADMIN / CHEFE_SSEG_BBM (P12-A e P12-B)
    // ---------------------------------------------------------------------------

    /**
     * Efetiva a extincao do licenciamento, transitando para o status EXTINTO.
     *
     * RN-109: Status do licenciamento deve estar em STATUS_EXTINCAO_ADMISSIVEL.
     * RN-111: Motivo e obrigatorio.
     * RN-112: Status muda para EXTINTO; ativo = false.
     * RN-113: EXTINTO e estado terminal.
     *
     * Usado tanto apos solicitacao do cidadao (P12-A) quanto em extincao
     * administrativa direta (P12-B).
     *
     * Marco: EXTINCAO_EFETIVADA.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param motivo     justificativa da extincao (obrigatorio)
     * @param keycloakId sub do JWT do responsavel pela efetivacao
     * @return LicenciamentoDTO com status EXTINTO
     */
    @Transactional
    public LicenciamentoDTO efetivarExtincao(Long licId, String motivo, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        if (motivo == null || motivo.isBlank()) {
            throw new BusinessException("RN-111",
                "O motivo da extincao e obrigatorio. "
                + "Informe a justificativa para o encerramento definitivo do licenciamento.");
        }

        if (!STATUS_EXTINCAO_ADMISSIVEL.contains(lic.getStatus())) {
            throw new BusinessException("RN-109",
                "Extincao nao pode ser efetivada para licenciamento com status "
                + lic.getStatus() + ". Status admissiveis: "
                + STATUS_EXTINCAO_ADMISSIVEL + ".");
        }

        // RN-112: transicao para EXTINTO + inativacao logica
        lic.setStatus(StatusLicenciamento.EXTINTO);
        lic.setAtivo(false);
        licenciamentoRepository.save(lic);

        Usuario responsavel = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.EXTINCAO_EFETIVADA, responsavel,
            "Extincao efetivada. Motivo: " + motivo
            + ". Licenciamento ID " + licId + " encerrado definitivamente.");

        notificarEnvolvidos(lic,
            "SOL - Licenciamento extinto (ID " + licId + ")",
            "O licenciamento ID " + licId + " foi EXTINTO.\n\n"
            + "Motivo: " + motivo + "\n\n"
            + "Este licenciamento foi encerrado definitivamente e nao admite "
            + "novas operacoes. Para iniciar um novo processo de licenciamento, "
            + "acesse o sistema SOL.\n\n"
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
