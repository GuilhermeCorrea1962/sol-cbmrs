package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.MarcoProcesso;
import br.gov.rs.cbm.sol.entity.RotinaExecucao;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import br.gov.rs.cbm.sol.repository.LicenciamentoRepository;
import br.gov.rs.cbm.sol.repository.MarcoProcessoRepository;
import br.gov.rs.cbm.sol.repository.RotinaExecucaoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Servico de negocio dos Jobs Automaticos de Alvaras (P13) do sistema SOL.
 *
 * Cada metodo transacional opera sobre um unico licenciamento, garantindo que
 * falha em um item nao reverta o processamento dos anteriores (equivalente ao
 * @TransactionAttribute(REQUIRES_NEW) da stack Java EE — aqui implementado
 * pela separacao em bean distinto do AlvaraJobService, que chama estes metodos
 * via proxy Spring, ativando a transacao a cada invocacao).
 *
 * P13-A: atualizarAlvaraVencido  — APPCI_EMITIDO + dtValidadeAppci vencida -> ALVARA_VENCIDO
 * P13-B: registrarNotificacaoVencimento — notificacoes 90/59/29 dias antes do vencimento
 * P13-C: registrarNotificacaoAlvaraVencido — notificacao pos-vencimento (1 vez, RN-129)
 *
 * Rastreabilidade: cada execucao da rotina diaria registra um RotinaExecucao,
 * cuja data de fim e usada como baseline temporal para as queries de P13-B/C (RN-140).
 */
@Service
@Transactional(readOnly = true)
public class AlvaraVencimentoService {

    private static final Logger log = LoggerFactory.getLogger(AlvaraVencimentoService.class);

    private static final String ROTINA_ALVARA = "GERAR_NOTIFICACAO_ALVARA_VENCIDO";

    private final LicenciamentoRepository   licenciamentoRepository;
    private final MarcoProcessoRepository   marcoProcessoRepository;
    private final RotinaExecucaoRepository  rotinaExecucaoRepository;
    private final EmailService              emailService;

    public AlvaraVencimentoService(LicenciamentoRepository licenciamentoRepository,
                                   MarcoProcessoRepository marcoProcessoRepository,
                                   RotinaExecucaoRepository rotinaExecucaoRepository,
                                   EmailService emailService) {
        this.licenciamentoRepository  = licenciamentoRepository;
        this.marcoProcessoRepository  = marcoProcessoRepository;
        this.rotinaExecucaoRepository = rotinaExecucaoRepository;
        this.emailService             = emailService;
    }

    // -----------------------------------------------------------------------
    // P13-A: Queries e atualizacao de alvaras vencidos
    // -----------------------------------------------------------------------

    /**
     * Retorna IDs de licenciamentos APPCI_EMITIDO com dtValidadeAppci <= hoje.
     * RN-121, RN-122.
     */
    public List<Long> buscarAlvarasVencidosIds() {
        return licenciamentoRepository.findAppciVencidosIds(LocalDate.now());
    }

    /**
     * Transiciona um licenciamento de APPCI_EMITIDO para ALVARA_VENCIDO.
     * Executa em transacao isolada (por ser chamado de bean externo — AlvaraJobService).
     * RN-121, RN-122, RN-123 (log de auditoria via marco de sistema).
     *
     * @param licId ID do licenciamento a ser atualizado
     */
    @Transactional
    public void atualizarAlvaraVencido(Long licId) {
        Licenciamento lic = licenciamentoRepository.findById(licId)
                .orElseThrow(() -> new IllegalArgumentException("Licenciamento nao encontrado: " + licId));

        if (lic.getStatus() != StatusLicenciamento.APPCI_EMITIDO) {
            log.debug("[P13-A] Licenciamento {} nao e mais APPCI_EMITIDO (status atual: {}). Ignorando.",
                    licId, lic.getStatus());
            return;
        }

        lic.setStatus(StatusLicenciamento.ALVARA_VENCIDO);
        licenciamentoRepository.save(lic);
        log.info("[P13-A] Licenciamento {} APPCI_EMITIDO -> ALVARA_VENCIDO (dtValidadeAppci: {}).",
                licId, lic.getDtValidadeAppci());
    }

    // -----------------------------------------------------------------------
    // P13-B: Notificacoes de vencimento proximo (90/59/29 dias)
    // -----------------------------------------------------------------------

    /**
     * Retorna IDs de licenciamentos APPCI_EMITIDO com alvara a vencer exatamente
     * em dataAlvo (calculada a partir da dataBase da ultima rotina concluida + dias).
     * RN-125, RN-126, RN-140.
     *
     * @param dataBase data de baseline (ultima execucao concluida da rotina)
     * @param dias     numero de dias antes do vencimento (90, 59 ou 29)
     * @return lista de IDs dos licenciamentos a notificar
     */
    public List<Long> buscarAlvarasAVencerIds(LocalDate dataBase, int dias) {
        LocalDate dataAlvo = dataBase.plusDays(dias);
        return licenciamentoRepository.findAppciAVencerIds(dataAlvo);
    }

    /**
     * Registra marco de notificacao e envia e-mail para RT e RU do licenciamento.
     * Executa em transacao isolada por licenciamento.
     * RN-125, RN-126, RN-128.
     *
     * @param licId     ID do licenciamento
     * @param tipoMarco tipo do marco de notificacao (90/59/29 dias)
     * @param dias      numero de dias para o vencimento (para texto do e-mail)
     */
    @Transactional
    public void registrarNotificacaoVencimento(Long licId, TipoMarco tipoMarco, int dias) {
        Licenciamento lic = licenciamentoRepository.findById(licId)
                .orElseThrow(() -> new IllegalArgumentException("Licenciamento nao encontrado: " + licId));

        MarcoProcesso marco = MarcoProcesso.builder()
                .licenciamento(lic)
                .tipoMarco(tipoMarco)
                .observacao("Notificacao automatica P13-B: alvara vence em "
                        + dias + " dia(s) em " + lic.getDtValidadeAppci() + ".")
                .build();
        marcoProcessoRepository.save(marco);

        String assunto = resolverAssunto(tipoMarco);
        String corpo   = resolverCorpoVencimentoProximo(lic, dias);
        notificarEnvolvidos(lic, assunto, corpo);

        log.info("[P13-B] Marco {} registrado para licenciamento {} (validade: {}).",
                tipoMarco, licId, lic.getDtValidadeAppci());
    }

    // -----------------------------------------------------------------------
    // P13-C: Notificacao de alvara vencido
    // -----------------------------------------------------------------------

    /**
     * Retorna IDs de licenciamentos ALVARA_VENCIDO com dtValidadeAppci no
     * intervalo [dataBase, hoje) — para notificacao pos-vencimento.
     * RN-129, RN-140.
     *
     * @param dataBase data de baseline (ultima execucao concluida da rotina)
     * @return lista de IDs dos licenciamentos a notificar
     */
    public List<Long> buscarAlvaresVencidosParaNotificacaoIds(LocalDate dataBase) {
        return licenciamentoRepository
                .findAlvaresVencidosParaNotificacaoIds(dataBase, LocalDate.now());
    }

    /**
     * Registra marco NOTIFICACAO_ALVARA_VENCIDO e envia e-mail (apenas uma vez
     * por licenciamento — idempotente conforme RN-129).
     * Executa em transacao isolada por licenciamento.
     *
     * @param licId ID do licenciamento
     */
    @Transactional
    public void registrarNotificacaoAlvaraVencido(Long licId) {
        Licenciamento lic = licenciamentoRepository.findById(licId)
                .orElseThrow(() -> new IllegalArgumentException("Licenciamento nao encontrado: " + licId));

        // RN-129: registrar apenas uma vez por licenciamento
        if (marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco(
                licId, TipoMarco.NOTIFICACAO_ALVARA_VENCIDO)) {
            log.debug("[P13-C] Marco NOTIFICACAO_ALVARA_VENCIDO ja existe para licenciamento {}. Ignorando.", licId);
            return;
        }

        MarcoProcesso marco = MarcoProcesso.builder()
                .licenciamento(lic)
                .tipoMarco(TipoMarco.NOTIFICACAO_ALVARA_VENCIDO)
                .observacao("Notificacao automatica P13-C: alvara vencido em " + lic.getDtValidadeAppci() + ".")
                .build();
        marcoProcessoRepository.save(marco);

        String assunto = "SOL CBM-RS - Alvara vencido: providencie a renovacao imediatamente";
        String corpo   = resolverCorpoAlvaraVencido(lic);
        notificarEnvolvidos(lic, assunto, corpo);

        log.info("[P13-C] Marco NOTIFICACAO_ALVARA_VENCIDO registrado para licenciamento {} (validade: {}).",
                licId, lic.getDtValidadeAppci());
    }

    // -----------------------------------------------------------------------
    // Controle de rotina — RN-140
    // -----------------------------------------------------------------------

    /**
     * Retorna a data de baseline para calcular as janelas de notificacao.
     * Usa a data de fim da ultima rotina CONCLUIDA. Se nenhuma existir, usa ontem.
     * RN-140.
     */
    public LocalDate buscarDataBaseRotina() {
        return rotinaExecucaoRepository
                .findTopByTipoRotinaAndSituacaoOrderByDataFimExecucaoDesc(ROTINA_ALVARA, "CONCLUIDA")
                .map(r -> r.getDataFimExecucao().toLocalDate())
                .orElse(LocalDate.now().minusDays(1));
    }

    /**
     * Registra o inicio de uma execucao da rotina (status EM_EXECUCAO).
     *
     * @return entidade persistida com ID gerado (usado para finalizar depois)
     */
    @Transactional
    public RotinaExecucao iniciarRotina() {
        RotinaExecucao rotina = RotinaExecucao.builder()
                .tipoRotina(ROTINA_ALVARA)
                .dataInicioExecucao(LocalDateTime.now())
                .situacao("EM_EXECUCAO")
                .numProcessados(0)
                .numErros(0)
                .build();
        return rotinaExecucaoRepository.save(rotina);
    }

    /**
     * Finaliza a execucao da rotina (status CONCLUIDA ou ERRO).
     *
     * @param rotinaId    ID da rotina a finalizar
     * @param processados total de itens processados com sucesso
     * @param erros       total de itens com erro
     * @param msgErro     descricao do erro principal (null se nenhum)
     */
    @Transactional
    public void finalizarRotina(Long rotinaId, int processados, int erros, String msgErro) {
        rotinaExecucaoRepository.findById(rotinaId).ifPresent(rotina -> {
            rotina.setDataFimExecucao(LocalDateTime.now());
            rotina.setSituacao(erros > 0 && processados == 0 ? "ERRO" : "CONCLUIDA");
            rotina.setNumProcessados(processados);
            rotina.setNumErros(erros);
            rotina.setMensagemErro(msgErro);
            rotinaExecucaoRepository.save(rotina);
        });
    }

    // -----------------------------------------------------------------------
    // Helpers privados
    // -----------------------------------------------------------------------

    private void notificarEnvolvidos(Licenciamento lic, String assunto, String corpo) {
        // RN-128: destinatario invalido/ausente gera log; job nao e interrompido
        if (lic.getResponsavelTecnico() != null) {
            emailService.notificarAsync(lic.getResponsavelTecnico().getEmail(), assunto, corpo);
        }
        if (lic.getResponsavelUso() != null) {
            emailService.notificarAsync(lic.getResponsavelUso().getEmail(), assunto, corpo);
        }
    }

    private String resolverAssunto(TipoMarco marco) {
        return switch (marco) {
            case NOTIFICACAO_SOLICITAR_RENOVACAO_90      -> "SOL CBM-RS - Seu alvara vence em 90 dias";
            case NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59 -> "SOL CBM-RS - Periodo de renovacao proximo (59 dias)";
            case NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29 -> "SOL CBM-RS - Periodo de renovacao proximo (29 dias)";
            case NOTIFICACAO_ALVARA_VENCIDO              -> "SOL CBM-RS - Alvara vencido: providencie a renovacao";
            default -> "SOL CBM-RS - Notificacao de alvara";
        };
    }

    private String resolverCorpoVencimentoProximo(Licenciamento lic, int dias) {
        String ppci    = lic.getNumeroPpci() != null ? lic.getNumeroPpci() : "(numero nao gerado)";
        String validade = lic.getDtValidadeAppci() != null ? lic.getDtValidadeAppci().toString() : "nao informada";
        String endereco = lic.getEndereco() != null
                ? lic.getEndereco().getLogradouro() + ", " + lic.getEndereco().getNumero()
                        + " - " + lic.getEndereco().getMunicipio() + "/" + lic.getEndereco().getUf()
                : "(endereco nao informado)";

        return String.format(
                "Prezado(a),%n%n" +
                "O alvara (APPCI) do licenciamento %s referente ao imovel%n" +
                "%s%n" +
                "vencera em %d dia(s), na data %s.%n%n" +
                "Acesse o portal SOL CBM-RS para iniciar o processo de renovacao antes do vencimento.%n%n" +
                "Corpo de Bombeiros Militar do Rio Grande do Sul%n" +
                "Sistema Online de Licenciamento — SOL",
                ppci, endereco, dias, validade);
    }

    private String resolverCorpoAlvaraVencido(Licenciamento lic) {
        String ppci    = lic.getNumeroPpci() != null ? lic.getNumeroPpci() : "(numero nao gerado)";
        String validade = lic.getDtValidadeAppci() != null ? lic.getDtValidadeAppci().toString() : "nao informada";
        String endereco = lic.getEndereco() != null
                ? lic.getEndereco().getLogradouro() + ", " + lic.getEndereco().getNumero()
                        + " - " + lic.getEndereco().getMunicipio() + "/" + lic.getEndereco().getUf()
                : "(endereco nao informado)";

        return String.format(
                "Prezado(a),%n%n" +
                "O alvara (APPCI) do licenciamento %s referente ao imovel%n" +
                "%s%n" +
                "venceu na data %s.%n%n" +
                "A ausencia de alvara valido configura irregularidade. Acesse o portal SOL CBM-RS " +
                "e providencie a renovacao imediatamente.%n%n" +
                "Corpo de Bombeiros Militar do Rio Grande do Sul%n" +
                "Sistema Online de Licenciamento — SOL",
                ppci, endereco, validade);
    }
}
