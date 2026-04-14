package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.BoletoDTO;
import br.gov.rs.cbm.sol.entity.Boleto;
import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.MarcoProcesso;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusBoleto;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.exception.ResourceNotFoundException;
import br.gov.rs.cbm.sol.repository.BoletoRepository;
import br.gov.rs.cbm.sol.repository.LicenciamentoRepository;
import br.gov.rs.cbm.sol.repository.MarcoProcessoRepository;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Servico de Pagamento de Boleto (P11) do sistema SOL.
 *
 * P11-A — fluxo manual (operador):
 *   Gerar boleto: POST /boletos/licenciamento/{id}
 *     RN-090: nao pode existir boleto PENDENTE ativo para o mesmo licenciamento
 *     RN-091: licenciamento isento nao gera boleto
 *     Marco: BOLETO_GERADO
 *   Confirmar pagamento: PATCH /boletos/{id}/confirmar-pagamento
 *     RN-095: boleto deve estar PENDENTE
 *     Marco: PAGAMENTO_CONFIRMADO (se dentro do prazo) ou BOLETO_VENCIDO (se apos vencimento)
 *
 * P11-B — job automatico (BoletoJobService):
 *   Busca boletos PENDENTE com dtVencimento < hoje
 *   Transicao: PENDENTE -> VENCIDO
 *   Marco: BOLETO_VENCIDO
 */
@Service
@Transactional(readOnly = true)
public class BoletoService {

    private final BoletoRepository        boletoRepository;
    private final LicenciamentoRepository  licenciamentoRepository;
    private final UsuarioRepository        usuarioRepository;
    private final MarcoProcessoRepository  marcoProcessoRepository;
    private final LicenciamentoService     licenciamentoService;
    private final EmailService             emailService;

    public BoletoService(BoletoRepository boletoRepository,
                         LicenciamentoRepository licenciamentoRepository,
                         UsuarioRepository usuarioRepository,
                         MarcoProcessoRepository marcoProcessoRepository,
                         LicenciamentoService licenciamentoService,
                         EmailService emailService) {
        this.boletoRepository       = boletoRepository;
        this.licenciamentoRepository = licenciamentoRepository;
        this.usuarioRepository       = usuarioRepository;
        this.marcoProcessoRepository = marcoProcessoRepository;
        this.licenciamentoService    = licenciamentoService;
        this.emailService            = emailService;
    }

    // ---------------------------------------------------------------------------
    // Consulta
    // ---------------------------------------------------------------------------

    public List<BoletoDTO> findByLicenciamento(Long licenciamentoId) {
        licenciamentoRepository.findById(licenciamentoId)
                .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", licenciamentoId));
        return boletoRepository.findByLicenciamentoId(licenciamentoId).stream()
                .map(this::toDTO)
                .toList();
    }

    // ---------------------------------------------------------------------------
    // Geracao de boleto — P11-A passo 1
    // ---------------------------------------------------------------------------

    /**
     * Gera um novo boleto para o licenciamento.
     *
     * RN-090: nao pode existir boleto PENDENTE ativo para o mesmo licenciamento.
     * RN-091: licenciamento isento nao gera boleto.
     *
     * Transicao: cria novo registro PENDENTE.
     * Marco: BOLETO_GERADO.
     * Notifica RT e RU sobre a emissao do boleto.
     *
     * @param licenciamentoId ID do licenciamento
     * @param keycloakId      sub do JWT do operador que gerou o boleto
     */
    @Transactional
    public BoletoDTO create(Long licenciamentoId, String keycloakId) {
        Licenciamento licenciamento = licenciamentoRepository.findById(licenciamentoId)
                .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", licenciamentoId));

        // RN-090: nao pode existir boleto PENDENTE ativo para o mesmo licenciamento
        if (boletoRepository.existsByLicenciamentoIdAndStatus(licenciamentoId, StatusBoleto.PENDENTE)) {
            throw new BusinessException("RN-090",
                    "Ja existe um boleto pendente para o licenciamento " + licenciamentoId
                    + ". Aguarde o pagamento ou vencimento antes de gerar um novo.");
        }

        // RN-091: licenciamento isento nao gera boleto
        if (Boolean.TRUE.equals(licenciamento.getIsentoTaxa())) {
            throw new BusinessException("RN-091",
                    "Licenciamento " + licenciamentoId + " e isento de taxa. Boleto nao gerado.");
        }

        BigDecimal valor = calcularTaxa(licenciamento);
        LocalDate hoje = LocalDate.now();
        LocalDate vencimento = hoje.plusDays(30);

        Boleto boleto = Boleto.builder()
                .licenciamento(licenciamento)
                .valor(valor)
                .dtEmissao(hoje)
                .dtVencimento(vencimento)
                .status(StatusBoleto.PENDENTE)
                .build();

        Boleto salvo = boletoRepository.save(boleto);

        Usuario operador = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        String obsMarco = "Boleto gerado. Valor: R$ " + valor
            + ". Vencimento: " + vencimento
            + ". Boleto ID: " + salvo.getId();
        registrarMarco(licenciamento, TipoMarco.BOLETO_GERADO, operador, obsMarco);

        String assunto = "SOL - Boleto emitido (licenciamento ID " + licenciamentoId + ")";
        String corpo = "Foi emitido um boleto de pagamento para o licenciamento ID " + licenciamentoId + ".\n\n"
            + "Valor: R$ " + valor + "\n"
            + "Vencimento: " + vencimento + "\n\n"
            + "Efetue o pagamento ate a data de vencimento para dar continuidade ao processo.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL";
        notificarEnvolvidos(licenciamento, assunto, corpo);

        return toDTO(salvo);
    }

    // ---------------------------------------------------------------------------
    // Confirmacao de pagamento — P11-A passo 2
    // ---------------------------------------------------------------------------

    /**
     * Confirma o pagamento manual de um boleto.
     *
     * RN-095: boleto deve estar PENDENTE.
     *
     * Se dataPagamento posterior ao vencimento: PENDENTE -> VENCIDO (pagamento em atraso).
     * Caso contrario: PENDENTE -> PAGO.
     *
     * Marco: PAGAMENTO_CONFIRMADO ou BOLETO_VENCIDO.
     * Notifica RT e RU sobre a confirmacao.
     *
     * @param boletoId      ID do boleto
     * @param dataPagamento data efetiva do pagamento
     * @param keycloakId    sub do JWT do operador que confirmou
     */
    @Transactional
    public BoletoDTO confirmarPagamento(Long boletoId, LocalDate dataPagamento, String keycloakId) {
        Boleto boleto = boletoRepository.findById(boletoId)
                .orElseThrow(() -> new ResourceNotFoundException("Boleto", boletoId));

        if (boleto.getStatus() != StatusBoleto.PENDENTE) {
            throw new BusinessException("RN-095",
                    "Boleto " + boletoId + " nao esta PENDENTE. Status atual: " + boleto.getStatus());
        }

        Usuario operador = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        boleto.setUsuarioConfirmacao(operador);
        boleto.setDtPagamento(LocalDateTime.now());

        Licenciamento lic = boleto.getLicenciamento();
        TipoMarco tipoMarco;
        String obsMarco;
        String assunto;
        String corpo;

        if (dataPagamento != null && dataPagamento.isAfter(boleto.getDtVencimento())) {
            boleto.setStatus(StatusBoleto.VENCIDO);
            tipoMarco = TipoMarco.BOLETO_VENCIDO;
            obsMarco  = "Pagamento registrado apos vencimento em " + dataPagamento
                      + ". Boleto ID: " + boletoId;
            assunto = "SOL - Pagamento registrado com atraso (licenciamento ID " + lic.getId() + ")";
            corpo   = "O pagamento do boleto para o licenciamento ID " + lic.getId()
                + " foi registrado apos a data de vencimento (" + boleto.getDtVencimento() + ").\n\n"
                + "Data de pagamento: " + dataPagamento + "\n\n"
                + "Em caso de multa ou encargos, aguarde orientacao do CBMRS.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL";
        } else {
            boleto.setStatus(StatusBoleto.PAGO);
            tipoMarco = TipoMarco.PAGAMENTO_CONFIRMADO;
            obsMarco  = "Pagamento confirmado em " + dataPagamento
                      + ". Boleto ID: " + boletoId;
            assunto = "SOL - Pagamento confirmado (licenciamento ID " + lic.getId() + ")";
            corpo   = "O pagamento do boleto para o licenciamento ID " + lic.getId()
                + " foi confirmado.\n\n"
                + "Data de pagamento: " + dataPagamento + "\n\n"
                + "Acesse o sistema SOL para acompanhar as proximas etapas.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL";
        }

        Boleto salvo = boletoRepository.save(boleto);
        registrarMarco(lic, tipoMarco, operador, obsMarco);
        notificarEnvolvidos(lic, assunto, corpo);

        return toDTO(salvo);
    }

    // ---------------------------------------------------------------------------
    // Vencimento automatico — chamado pelo BoletoJobService (P11-B)
    // ---------------------------------------------------------------------------

    /**
     * Marca um boleto PENDENTE como VENCIDO (chamado pelo job P11-B).
     *
     * Marco: BOLETO_VENCIDO.
     * Notifica RT e RU sobre o vencimento.
     *
     * @param boleto boleto a ser vencido (deve estar PENDENTE com dtVencimento < hoje)
     */
    @Transactional
    public void vencerBoleto(Boleto boleto) {
        boleto.setStatus(StatusBoleto.VENCIDO);
        boletoRepository.save(boleto);

        Licenciamento lic = boleto.getLicenciamento();
        String obsMarco = "Boleto ID " + boleto.getId() + " vencido automaticamente em "
            + LocalDate.now() + ". Valor: R$ " + boleto.getValor();
        registrarMarco(lic, TipoMarco.BOLETO_VENCIDO, null, obsMarco);

        String assunto = "SOL - Boleto vencido (licenciamento ID " + lic.getId() + ")";
        String corpo   = "O boleto de pagamento para o licenciamento ID " + lic.getId()
            + " venceu sem pagamento.\n\n"
            + "Vencimento: " + boleto.getDtVencimento() + "\n"
            + "Valor: R$ " + boleto.getValor() + "\n\n"
            + "Gere um novo boleto acessando o sistema SOL para regularizar o pagamento.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL";
        notificarEnvolvidos(lic, assunto, corpo);
    }

    // ---------------------------------------------------------------------------
    // Calculo de taxa (stub — substituir por implementacao real)
    // ---------------------------------------------------------------------------

    private BigDecimal calcularTaxa(Licenciamento licenciamento) {
        // Valor base provisorio. A regra real depende da area construida,
        // tipo de ocupacao e tabela de taxa do CBMRS.
        if (licenciamento.getAreaConstruida() == null) {
            return BigDecimal.valueOf(150.00);
        }
        return licenciamento.getAreaConstruida()
                .multiply(BigDecimal.valueOf(0.50))
                .max(BigDecimal.valueOf(150.00));
    }

    // ---------------------------------------------------------------------------
    // Helpers internos
    // ---------------------------------------------------------------------------

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

    // ---------------------------------------------------------------------------
    // Mapeamento manual Entity -> DTO
    // ---------------------------------------------------------------------------

    public BoletoDTO toDTO(Boleto b) {
        return new BoletoDTO(
                b.getId(),
                b.getNossoNumero(),
                b.getCodigoBarras(),
                b.getLinhaDigitavel(),
                b.getValor(),
                b.getDtEmissao(),
                b.getDtVencimento(),
                b.getDtPagamento(),
                b.getStatus(),
                b.getCaminhoPdf(),
                b.getObsPagamento(),
                b.getLicenciamento() != null ? b.getLicenciamento().getId() : null,
                b.getLicenciamento() != null ? b.getLicenciamento().getNumeroPpci() : null,
                b.getUsuarioConfirmacao() != null ? b.getUsuarioConfirmacao().getId() : null,
                b.getUsuarioConfirmacao() != null ? b.getUsuarioConfirmacao().getNome() : null,
                b.getDtCriacao(),
                b.getDtAtualizacao()
        );
    }
}
