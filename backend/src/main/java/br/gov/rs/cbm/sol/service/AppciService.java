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

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Servico de Emissao do APPCI (P08) do sistema SOL.
 *
 * Responsabilidades:
 *   - Emitir o APPCI a partir de licenciamentos em PRPCI_EMITIDO (RN-P08-001)
 *   - Calcular automaticamente a validade do APPCI pela area construida (RN-P08-002)
 *   - Preencher dtVencimentoPrpci se ausente (RN-P08-003)
 *   - Listar APPCIs vigentes (APPCI_EMITIDO)
 *   - Consultar detalhes do APPCI de um licenciamento especifico
 *   - Notificar RT e RU por e-mail apos emissao
 *
 * Maquina de estados P08:
 *   PRPCI_EMITIDO --[emitir-appci]--> APPCI_EMITIDO
 *
 * Calculo de validade do APPCI (RTCBMRS N.01/2024):
 *   areaConstruida <= 750 m²  ->  2 anos
 *   areaConstruida >  750 m²  ->  5 anos
 *   areaConstruida nula        ->  2 anos (conservador)
 *
 * Marco registrado:
 *   APPCI_EMITIDO -- emissao do Alvara de Prevencao e Protecao Contra Incendio
 */
@Service
@Transactional(readOnly = true)
public class AppciService {

    // Limiar de area para calculo de validade do APPCI (RTCBMRS N.01/2024)
    private static final BigDecimal AREA_LIMIAR = new BigDecimal("750.00");
    private static final int VALIDADE_ANOS_ATE_750   = 2;
    private static final int VALIDADE_ANOS_ACIMA_750 = 5;
    private static final int VALIDADE_PRPCI_ANOS     = 1;

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository       usuarioRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;
    private final LicenciamentoService    licenciamentoService;
    private final EmailService            emailService;

    public AppciService(LicenciamentoRepository licenciamentoRepository,
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

    /** Lista todos os licenciamentos com APPCI vigente (status APPCI_EMITIDO), paginado. */
    public Page<LicenciamentoDTO> findVigentes(Pageable pageable) {
        return licenciamentoRepository
            .findByStatus(StatusLicenciamento.APPCI_EMITIDO, pageable)
            .map(licenciamentoService::toDTO);
    }

    /**
     * Retorna os dados do APPCI de um licenciamento.
     * Valida que o licenciamento existe e esta em status APPCI_EMITIDO.
     *
     * @param licId ID do licenciamento
     */
    public LicenciamentoDTO findAppci(Long licId) {
        Licenciamento lic = buscarPorId(licId);
        if (lic.getStatus() != StatusLicenciamento.APPCI_EMITIDO) {
            throw new BusinessException("RN-P08-004",
                "O licenciamento ID " + licId + " nao possui APPCI emitido. "
                + "Status atual: " + lic.getStatus());
        }
        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Emissao do APPCI -- ADMIN / ANALISTA
    // ---------------------------------------------------------------------------

    /**
     * Emite o Alvara de Prevencao e Protecao Contra Incendio (APPCI).
     *
     * RN-P08-001: status deve ser PRPCI_EMITIDO.
     * RN-P08-002: validade do APPCI calculada automaticamente pela area construida:
     *             areaConstruida <= 750 m² -> 2 anos; > 750 m² -> 5 anos.
     * RN-P08-003: dtVencimentoPrpci preenchida como hoje + 1 ano se ainda nao definida.
     *
     * Transicao: PRPCI_EMITIDO -> APPCI_EMITIDO.
     * Marco: APPCI_EMITIDO com data de validade registrada na observacao.
     * Notifica RT e RU por e-mail.
     *
     * @param licId      ID do licenciamento
     * @param observacao observacao complementar (opcional)
     * @param keycloakId sub do JWT do usuario que esta emitindo
     */
    @Transactional
    public LicenciamentoDTO emitirAppci(Long licId, String observacao, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);

        // RN-P08-001
        if (lic.getStatus() != StatusLicenciamento.PRPCI_EMITIDO) {
            throw new BusinessException("RN-P08-001",
                "O APPCI so pode ser emitido em licenciamentos com status PRPCI_EMITIDO. "
                + "Status atual: " + lic.getStatus());
        }

        // RN-P08-002: calcula validade do APPCI pela area construida
        LocalDate hoje = LocalDate.now();
        int anosValidade = calcularAnosValidadeAppci(lic.getAreaConstruida());
        LocalDate dtValidade = hoje.plusYears(anosValidade);
        lic.setDtValidadeAppci(dtValidade);

        // RN-P08-003: preenche dtVencimentoPrpci se ausente (retroativo ao fim da vistoria)
        if (lic.getDtVencimentoPrpci() == null) {
            lic.setDtVencimentoPrpci(hoje.plusYears(VALIDADE_PRPCI_ANOS));
        }

        lic.setStatus(StatusLicenciamento.APPCI_EMITIDO);
        licenciamentoRepository.save(lic);

        String obsMarco = "APPCI emitido. Validade: " + dtValidade
            + " (" + anosValidade + " anos, area construida: "
            + (lic.getAreaConstruida() != null ? lic.getAreaConstruida() + " m²" : "nao informada") + ")."
            + (observacao != null && !observacao.isBlank() ? " " + observacao : "");

        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        registrarMarco(lic, TipoMarco.APPCI_EMITIDO, usuario, obsMarco);

        notificarEnvolvidos(lic,
            "SOL - APPCI emitido (licenciamento ID " + licId + ")",
            "O Alvara de Prevencao e Protecao Contra Incendio (APPCI) foi emitido para o "
            + "licenciamento ID " + licId + ".\n\n"
            + "Validade do APPCI: " + dtValidade + " (" + anosValidade + " anos)\n"
            + "Vencimento do PRPCI: " + lic.getDtVencimentoPrpci() + "\n\n"
            + (observacao != null && !observacao.isBlank()
                ? "Observacao: " + observacao + "\n\n" : "")
            + "Acesse o sistema SOL para consultar e imprimir o seu Alvara.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        return licenciamentoService.toDTO(lic);
    }

    // ---------------------------------------------------------------------------
    // Helpers internos
    // ---------------------------------------------------------------------------

    /**
     * Calcula o numero de anos de validade do APPCI com base na area construida.
     * Regra: area <= 750 m² -> 2 anos; area > 750 m² -> 5 anos.
     * Quando area nao informada, adota o criterio conservador de 2 anos.
     */
    private int calcularAnosValidadeAppci(BigDecimal area) {
        if (area == null || area.compareTo(AREA_LIMIAR) <= 0) {
            return VALIDADE_ANOS_ATE_750;
        }
        return VALIDADE_ANOS_ACIMA_750;
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
