package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.AnexoDRenovacaoDTO;
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
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Set;

/**
 * Servico de Renovacao de Licenciamento (P14) do sistema SOL.
 *
 * Implementa as seis fases do processo de renovacao de APPCI:
 *
 *   Fase 1  Iniciacao da Renovacao
 *           Validacao de elegibilidade (RN-141 a RN-143) e transicao para
 *           AGUARDANDO_ACEITE_RENOVACAO.
 *
 *   Fase 2  Aceite ou Rejeicao do Anexo D
 *           Leitura, aceite e remocao do aceite do Anexo D de Renovacao (RN-144).
 *           Confirmacao (RN-145) -> AGUARDANDO_PAGAMENTO_RENOVACAO.
 *           Recusa (RN-145) -> rollback para APPCI_EMITIDO ou ALVARA_VENCIDO.
 *
 *   Fase 3  Pagamento ou Isencao da Taxa de Vistoria
 *           Solicitacao de isencao (RN-147) e analise pelo CBMRS (RN-148).
 *           Deferida  -> AGUARDANDO_DISTRIBUICAO_RENOV.
 *           Indeferida -> permanece AGUARDANDO_PAGAMENTO_RENOVACAO.
 *           Pagamento via CNAB 240 (P13-E stub) -> AGUARDANDO_DISTRIBUICAO_RENOV.
 *
 *   Fase 4  Distribuicao da Vistoria de Renovacao
 *           Admin distribui para inspetor (RN-150) -> EM_VISTORIA_RENOVACAO.
 *
 *   Fase 5  Execucao da Vistoria de Renovacao
 *           Inspetor registra resultado (RN-151).
 *           Admin homologa: deferido -> APPCI_EMITIDO (nova data de validade);
 *                           indeferido -> retorna para vistoria ou CIV_EMITIDO.
 *
 *   Fase 6  Conclusao
 *           6A: cidadao/RT toma ciencia do novo APPCI (RN-152).
 *           6B: cidadao/RT toma ciencia da CIV (RN-153); pode retomar renovacao.
 *
 * Regras de negocio: RN-141 a RN-160.
 *
 * Padrao transacional:
 *   - Classe com @Transactional(readOnly = true)
 *   - Metodos de escrita com @Transactional (override para readOnly = false)
 *   - Pattern identico ao ExtincaoService e AlvaraVencimentoService
 */
@Service
@Transactional(readOnly = true)
public class RenovacaoService {

    private static final Logger log = LoggerFactory.getLogger(RenovacaoService.class);

    /** Duracao padrao do novo APPCI apos renovacao aprovada (anos). RN-152. */
    private static final int ANOS_VALIDADE_APPCI_RENOVADO = 5;

    /**
     * Estados de entrada admissiveis para o processo de renovacao.
     * RN-141: ALVARA_VIGENTE (= APPCI_EMITIDO no Spring Boot) ou ALVARA_VENCIDO.
     */
    private static final Set<StatusLicenciamento> STATUS_ENTRADA_RENOVACAO = Set.of(
        StatusLicenciamento.APPCI_EMITIDO,
        StatusLicenciamento.ALVARA_VENCIDO
    );

    /**
     * Texto padrao do Anexo D de Renovacao exibido ao cidadao/RT.
     * Em producao, deve ser carregado de template configuravel (ex.: Alfresco ou classpath).
     * RN-144.
     */
    private static final String TEXTO_ANEXO_D =
        "ANEXO D -- TERMO DE RENOVACAO DE APPCI\n\n" +
        "Declaro que estou ciente das condicoes estabelecidas pelo Corpo de Bombeiros " +
        "Militar do Rio Grande do Sul para renovacao do Alvara de Prevencao e Protecao " +
        "Contra Incendio (APPCI) do estabelecimento identificado neste licenciamento.\n\n" +
        "Confirmo que as condicoes estruturais e de seguranca da edificacao permanecem " +
        "em conformidade com o PPCI aprovado no ciclo anterior, e autorizo a realizacao " +
        "de vistoria presencial para verificacao.\n\n" +
        "Estou ciente de que a renovacao do APPCI esta condicionada ao resultado " +
        "favoravel da vistoria realizada pelos inspetores do CBMRS.";

    private final LicenciamentoRepository  licenciamentoRepository;
    private final UsuarioRepository        usuarioRepository;
    private final MarcoProcessoRepository  marcoProcessoRepository;
    private final LicenciamentoService     licenciamentoService;
    private final EmailService             emailService;

    public RenovacaoService(LicenciamentoRepository licenciamentoRepository,
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

    // =========================================================================
    // FASE 1 -- INICIACAO DA RENOVACAO
    // =========================================================================

    /**
     * Lista os licenciamentos elegiveis para renovacao do usuario autenticado.
     *
     * Retorna licenciamentos em APPCI_EMITIDO (= ALVARA_VIGENTE) ou ALVARA_VENCIDO
     * onde o usuario e o RT ou RU. Usado pela tela "Minhas Renovacoes" -- aba elegiveis.
     * RN-155.
     *
     * @param keycloakId sub do JWT do usuario autenticado
     * @return lista de LicenciamentoDTO elegiveis
     */
    public List<LicenciamentoDTO> listarElegiveisParaRenovacao(String keycloakId) {
        Usuario usuario = buscarUsuario(keycloakId);
        return licenciamentoRepository
            .findElegiveisParaRenovacao(usuario.getId())
            .stream()
            .map(licenciamentoService::toDTO)
            .toList();
    }

    /**
     * Lista as renovacoes em andamento do usuario autenticado.
     *
     * Retorna licenciamentos em qualquer status de renovacao ativo
     * (AGUARDANDO_ACEITE_RENOVACAO, AGUARDANDO_PAGAMENTO_RENOVACAO,
     *  AGUARDANDO_DISTRIBUICAO_RENOV, EM_VISTORIA_RENOVACAO, CIV_EMITIDO).
     * RN-154.
     *
     * @param keycloakId sub do JWT do usuario autenticado
     * @return lista de LicenciamentoDTO em andamento
     */
    public List<LicenciamentoDTO> listarRenovacoesEmAndamento(String keycloakId) {
        Usuario usuario = buscarUsuario(keycloakId);
        return licenciamentoRepository
            .findRenovacoesEmAndamento(usuario.getId())
            .stream()
            .map(licenciamentoService::toDTO)
            .toList();
    }

    /**
     * Inicia o processo de renovacao do licenciamento.
     *
     * Validacoes:
     *   RN-141: status deve ser APPCI_EMITIDO ou ALVARA_VENCIDO.
     *   RN-143: usuario autenticado deve ser RT ou RU do licenciamento.
     *
     * Transicao: APPCI_EMITIDO ou ALVARA_VENCIDO -> AGUARDANDO_ACEITE_RENOVACAO.
     * Marco: INICIO_RENOVACAO.
     * Notificacao: e-mail para RT e RU (RN-160).
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do solicitante
     * @return LicenciamentoDTO com status AGUARDANDO_ACEITE_RENOVACAO
     */
    @Transactional
    public LicenciamentoDTO iniciarRenovacao(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusParaRenovacao(lic);       // RN-141
        validarEnvolvido(lic, usuario);        // RN-143

        StatusLicenciamento statusAnterior = lic.getStatus();
        lic.setStatus(StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO);
        licenciamentoRepository.save(lic);

        registrarMarco(lic, TipoMarco.INICIO_RENOVACAO, usuario,
            "Renovacao iniciada. Status anterior: " + statusAnterior);

        notificarEnvolvidos(lic,
            "SOL -- Renovacao de licenciamento iniciada (ID " + licId + ")",
            "O processo de renovacao do licenciamento ID " + licId
            + " (PPCI: " + lic.getNumeroPpci() + ") foi iniciado.\n\n"
            + "Acesse o portal SOL para ler e aceitar o Anexo D de Renovacao.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        log.info("[P14-Fase1] Renovacao iniciada: licenciamento {} status {} -> {}",
            licId, statusAnterior, lic.getStatus());
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 2 -- ACEITE OU REJEICAO DO ANEXO D
    // =========================================================================

    /**
     * Retorna o Anexo D de Renovacao para leitura pelo cidadao/RT.
     *
     * Nao altera estado. Retorna texto do termo, status de aceite do usuario
     * autenticado e dados do APPCI vigente (data de validade).
     * RN-144.
     *
     * @param licId      ID do licenciamento em AGUARDANDO_ACEITE_RENOVACAO
     * @param keycloakId sub do JWT do usuario
     * @return AnexoDRenovacaoDTO com texto e metadados do APPCI atual
     */
    public AnexoDRenovacaoDTO getAnexoD(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);
        validarEnvolvido(lic, usuario);

        boolean aceiteRegistrado = marcoProcessoRepository
            .existsByLicenciamentoIdAndTipoMarco(licId, TipoMarco.ACEITE_ANEXOD_RENOVACAO);

        String dtValidade = lic.getDtValidadeAppci() != null
            ? lic.getDtValidadeAppci().format(DateTimeFormatter.ISO_LOCAL_DATE)
            : "nao informada";

        return new AnexoDRenovacaoDTO(
            lic.getId(),
            lic.getNumeroPpci(),
            lic.getStatus().name(),
            aceiteRegistrado,
            dtValidade,
            TEXTO_ANEXO_D
        );
    }

    /**
     * Registra o aceite do Anexo D de Renovacao pelo cidadao/RT.
     *
     * Requer status AGUARDANDO_ACEITE_RENOVACAO.
     * Marco: ACEITE_ANEXOD_RENOVACAO.
     * RN-144.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do usuario
     * @return AnexoDRenovacaoDTO atualizado com aceiteRegistrado = true
     */
    @Transactional
    public AnexoDRenovacaoDTO aceitarAnexoD(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO,
            "RN-144", "Aceite do Anexo D so e permitido com status AGUARDANDO_ACEITE_RENOVACAO.");
        validarEnvolvido(lic, usuario);

        // Idempotente: registra apenas se ainda nao aceitou
        if (!marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco(
                licId, TipoMarco.ACEITE_ANEXOD_RENOVACAO)) {
            registrarMarco(lic, TipoMarco.ACEITE_ANEXOD_RENOVACAO, usuario,
                "Cidadao/RT aceitou o Anexo D de Renovacao.");
        }

        log.info("[P14-Fase2] Aceite do Anexo D registrado: licenciamento {}, usuario {}",
            licId, usuario.getId());
        return getAnexoD(licId, keycloakId);
    }

    /**
     * Remove o aceite do Anexo D de Renovacao.
     *
     * Permite que o cidadao reveja os termos antes de confirmar.
     * Requer status AGUARDANDO_ACEITE_RENOVACAO. RN-144.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do usuario
     * @return AnexoDRenovacaoDTO atualizado com aceiteRegistrado = false
     */
    @Transactional
    public AnexoDRenovacaoDTO removerAceiteAnexoD(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO,
            "RN-144", "Remocao do aceite do Anexo D so e permitida com status AGUARDANDO_ACEITE_RENOVACAO.");
        validarEnvolvido(lic, usuario);

        registrarMarco(lic, TipoMarco.REMOCAO_ACEITE_ANEXOD_RENOVACAO, usuario,
            "Cidadao/RT removeu o aceite do Anexo D de Renovacao.");

        log.info("[P14-Fase2] Aceite do Anexo D removido: licenciamento {}, usuario {}",
            licId, usuario.getId());
        return getAnexoD(licId, keycloakId);
    }

    /**
     * Confirma a renovacao apos aceite do Anexo D.
     *
     * Requer: status AGUARDANDO_ACEITE_RENOVACAO e marco ACEITE_ANEXOD_RENOVACAO presente.
     * Transicao: AGUARDANDO_ACEITE_RENOVACAO -> AGUARDANDO_PAGAMENTO_RENOVACAO.
     * RN-145.
     *
     * O cidadao podera solicitar isencao (Fase 3) ou aguardar o pagamento do
     * boleto (gerado pelo sistema na implementacao completa do P11 de renovacao).
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do usuario
     * @return LicenciamentoDTO com status AGUARDANDO_PAGAMENTO_RENOVACAO
     */
    @Transactional
    public LicenciamentoDTO confirmarRenovacao(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO,
            "RN-145", "Confirmacao da renovacao so e permitida com status AGUARDANDO_ACEITE_RENOVACAO.");
        validarEnvolvido(lic, usuario);

        if (!marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco(
                licId, TipoMarco.ACEITE_ANEXOD_RENOVACAO)) {
            throw new BusinessException("RN-144",
                "E necessario aceitar o Anexo D de Renovacao antes de confirmar o processo.");
        }

        lic.setStatus(StatusLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO);
        licenciamentoRepository.save(lic);

        notificarEnvolvidos(lic,
            "SOL -- Renovacao confirmada (ID " + licId + ")",
            "O processo de renovacao do licenciamento ID " + licId
            + " foi confirmado. Efetue o pagamento da taxa de vistoria ou solicite isencao "
            + "para prosseguir.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        log.info("[P14-Fase2] Renovacao confirmada: licenciamento {} -> AGUARDANDO_PAGAMENTO_RENOVACAO",
            licId);
        return licenciamentoService.toDTO(lic);
    }

    /**
     * Recusa a renovacao e faz rollback para o status anterior.
     *
     * RN-145:
     *   - Se dtValidadeAppci >= hoje  -> APPCI_EMITIDO (alvara ainda vigente)
     *   - Se dtValidadeAppci < hoje   -> ALVARA_VENCIDO (alvara ja expirou)
     * Marco: RENOVACAO_CANCELADA.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do usuario
     * @return LicenciamentoDTO com status restaurado
     */
    @Transactional
    public LicenciamentoDTO recusarRenovacao(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO,
            "RN-145", "Recusa da renovacao so e permitida com status AGUARDANDO_ACEITE_RENOVACAO.");
        validarEnvolvido(lic, usuario);

        // RN-145: rollback baseado na validade do alvara
        StatusLicenciamento statusRollback;
        if (lic.getDtValidadeAppci() != null
                && !LocalDate.now().isAfter(lic.getDtValidadeAppci())) {
            statusRollback = StatusLicenciamento.APPCI_EMITIDO;  // alvara ainda vigente
        } else {
            statusRollback = StatusLicenciamento.ALVARA_VENCIDO;  // alvara expirado
        }

        lic.setStatus(statusRollback);
        licenciamentoRepository.save(lic);

        registrarMarco(lic, TipoMarco.RENOVACAO_CANCELADA, usuario,
            "Cidadao/RT recusou a renovacao. Status restaurado para: " + statusRollback);

        log.info("[P14-Fase2] Renovacao recusada: licenciamento {} -> {}", licId, statusRollback);
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 3 -- PAGAMENTO OU ISENCAO DA TAXA DE VISTORIA
    // =========================================================================

    /**
     * Solicita isencao da taxa de vistoria de renovacao.
     *
     * Requer status AGUARDANDO_PAGAMENTO_RENOVACAO.
     * Marca isentoTaxaRenovacao = false (pendente de analise).
     * Marco: SOLICITACAO_ISENCAO_RENOVACAO.
     * RN-147.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do solicitante
     * @return LicenciamentoDTO com solicitacao registrada
     */
    @Transactional
    public LicenciamentoDTO solicitarIsencao(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO,
            "RN-147", "Solicitacao de isencao so e permitida com status AGUARDANDO_PAGAMENTO_RENOVACAO.");
        validarEnvolvido(lic, usuario);

        registrarMarco(lic, TipoMarco.SOLICITACAO_ISENCAO_RENOVACAO, usuario,
            "Cidadao/RT solicitou isencao da taxa de vistoria de renovacao.");

        log.info("[P14-Fase3] Isencao solicitada: licenciamento {}", licId);
        return licenciamentoService.toDTO(lic);
    }

    /**
     * Analisa a solicitacao de isencao da taxa de vistoria de renovacao.
     *
     * Requer perfil ADMIN ou CHEFE_SSEG_BBM.
     * Requer status AGUARDANDO_PAGAMENTO_RENOVACAO.
     *
     * RN-148:
     *   - Deferida: isentoTaxaRenovacao = true; marco ANALISE_ISENCAO_RENOV_APROVADO;
     *               status -> AGUARDANDO_DISTRIBUICAO_RENOV.
     *   - Indeferida: isentoTaxaRenovacao = false; marco ANALISE_ISENCAO_RENOV_REPROVADO;
     *                 status permanece AGUARDANDO_PAGAMENTO_RENOVACAO.
     *
     * @param licId      ID do licenciamento
     * @param deferida   true = deferida, false = indeferida
     * @param keycloakId sub do JWT do admin
     * @return LicenciamentoDTO com status atualizado
     */
    @Transactional
    public LicenciamentoDTO analisarIsencao(Long licId, boolean deferida, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario admin     = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO,
            "RN-148", "Analise de isencao so e permitida com status AGUARDANDO_PAGAMENTO_RENOVACAO.");

        if (deferida) {
            lic.setIsentoTaxaRenovacao(true);
            lic.setStatus(StatusLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV);
            licenciamentoRepository.save(lic);

            registrarMarco(lic, TipoMarco.ANALISE_ISENCAO_RENOV_APROVADO, admin,
                "CBMRS deferiu a isencao da taxa de vistoria de renovacao. " +
                "Licenciamento avancado para AGUARDANDO_DISTRIBUICAO_RENOV.");

            notificarEnvolvidos(lic,
                "SOL -- Isencao de taxa de renovacao deferida (ID " + licId + ")",
                "A solicitacao de isencao da taxa de vistoria de renovacao do "
                + "licenciamento ID " + licId + " foi DEFERIDA.\n\n"
                + "O licenciamento prosseguira para distribuicao da vistoria.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");

            log.info("[P14-Fase3] Isencao deferida: licenciamento {} -> AGUARDANDO_DISTRIBUICAO_RENOV",
                licId);
        } else {
            lic.setIsentoTaxaRenovacao(false);
            licenciamentoRepository.save(lic);

            registrarMarco(lic, TipoMarco.ANALISE_ISENCAO_RENOV_REPROVADO, admin,
                "CBMRS indeferiu a isencao da taxa de vistoria de renovacao. " +
                "Cidadao deve efetuar o pagamento do boleto.");

            notificarEnvolvidos(lic,
                "SOL -- Isencao de taxa de renovacao indeferida (ID " + licId + ")",
                "A solicitacao de isencao da taxa de vistoria de renovacao do "
                + "licenciamento ID " + licId + " foi INDEFERIDA.\n\n"
                + "Efetue o pagamento do boleto para prosseguir com a renovacao.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");

            log.info("[P14-Fase3] Isencao indeferida: licenciamento {} permanece AGUARDANDO_PAGAMENTO_RENOVACAO",
                licId);
        }

        return licenciamentoService.toDTO(lic);
    }

    /**
     * Confirma pagamento do boleto de vistoria de renovacao (simulacao para testes).
     *
     * Em producao, o pagamento e processado exclusivamente via CNAB 240 do Banrisul
     * pelo job P13-E. Este endpoint serve apenas para testes e homologacao.
     * Marco: LIQUIDACAO_VISTORIA_RENOVACAO.
     * RN-149.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do admin
     * @return LicenciamentoDTO com status AGUARDANDO_DISTRIBUICAO_RENOV
     */
    @Transactional
    public LicenciamentoDTO confirmarPagamento(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario admin     = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO,
            "RN-149", "Confirmacao de pagamento so e permitida com status AGUARDANDO_PAGAMENTO_RENOVACAO.");

        lic.setStatus(StatusLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV);
        licenciamentoRepository.save(lic);

        registrarMarco(lic, TipoMarco.LIQUIDACAO_VISTORIA_RENOVACAO, admin,
            "Pagamento da taxa de vistoria de renovacao confirmado (simulacao admin). " +
            "Em producao: via CNAB 240 Banrisul (job P13-E).");

        log.info("[P14-Fase3] Pagamento confirmado (simulacao): licenciamento {} -> AGUARDANDO_DISTRIBUICAO_RENOV",
            licId);
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 4 -- DISTRIBUICAO DA VISTORIA DE RENOVACAO
    // =========================================================================

    /**
     * Distribui a vistoria de renovacao para um inspetor CBMRS.
     *
     * Requer perfil ADMIN ou CHEFE_SSEG_BBM.
     * Requer status AGUARDANDO_DISTRIBUICAO_RENOV.
     * Transicao: AGUARDANDO_DISTRIBUICAO_RENOV -> EM_VISTORIA_RENOVACAO.
     * Marco: DISTRIBUICAO_VISTORIA_RENOV.
     * RN-150.
     *
     * @param licId      ID do licenciamento
     * @param inspetorId ID do Usuario designado como inspetor
     * @param keycloakId sub do JWT do admin que distribui
     * @return LicenciamentoDTO com status EM_VISTORIA_RENOVACAO
     */
    @Transactional
    public LicenciamentoDTO distribuirVistoria(Long licId, Long inspetorId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario admin     = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV,
            "RN-150", "Distribuicao de vistoria so e permitida com status AGUARDANDO_DISTRIBUICAO_RENOV.");

        if (inspetorId == null) {
            throw new BusinessException("RN-150",
                "O ID do inspetor e obrigatorio para distribuicao da vistoria de renovacao.");
        }

        Usuario inspetor = usuarioRepository.findById(inspetorId)
            .orElseThrow(() -> new ResourceNotFoundException("Usuario (inspetor)", inspetorId));

        lic.setInspetor(inspetor);
        lic.setStatus(StatusLicenciamento.EM_VISTORIA_RENOVACAO);
        licenciamentoRepository.save(lic);

        registrarMarco(lic, TipoMarco.DISTRIBUICAO_VISTORIA_RENOV, admin,
            "Vistoria de renovacao distribuida para inspetor ID " + inspetorId
            + " (" + inspetor.getNome() + ").");

        notificarEnvolvidos(lic,
            "SOL -- Vistoria de renovacao agendada (ID " + licId + ")",
            "A vistoria de renovacao do licenciamento ID " + licId
            + " foi distribuida para o inspetor " + inspetor.getNome() + ".\n\n"
            + "Aguarde o contato do CBMRS para agendamento da vistoria presencial.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        log.info("[P14-Fase4] Vistoria distribuida: licenciamento {} inspetor {} -> EM_VISTORIA_RENOVACAO",
            licId, inspetorId);
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 5 -- EXECUCAO E HOMOLOGACAO DA VISTORIA DE RENOVACAO
    // =========================================================================

    /**
     * Inspetor registra o resultado da vistoria de renovacao.
     *
     * Requer perfil INSPETOR (ou ADMIN em testes).
     * Requer status EM_VISTORIA_RENOVACAO.
     * RN-151: tipo de vistoria = VISTORIA_RENOVACAO (ordinal 3).
     *
     * Marcos:
     *   - Aprovada: VISTORIA_RENOVACAO
     *   - Reprovada: VISTORIA_RENOVACAO_CIV
     *
     * Status nao transita aqui -- aguarda homologacao pelo admin (Fase 5B).
     *
     * @param licId           ID do licenciamento
     * @param vistoriaAprovada resultado da vistoria (true = aprovada, false = reprovada)
     * @param keycloakId      sub do JWT do inspetor
     * @return LicenciamentoDTO com marco registrado (status permanece EM_VISTORIA_RENOVACAO)
     */
    @Transactional
    public LicenciamentoDTO registrarVistoria(Long licId, boolean vistoriaAprovada, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario inspetor  = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.EM_VISTORIA_RENOVACAO,
            "RN-151", "Registro de vistoria so e permitido com status EM_VISTORIA_RENOVACAO.");

        TipoMarco marco = vistoriaAprovada
            ? TipoMarco.VISTORIA_RENOVACAO
            : TipoMarco.VISTORIA_RENOVACAO_CIV;

        registrarMarco(lic, marco, inspetor,
            "Resultado da vistoria de renovacao registrado pelo inspetor "
            + inspetor.getNome() + ": "
            + (vistoriaAprovada ? "APROVADA" : "REPROVADA (CIV)") + ". "
            + "Aguardando homologacao pelo CBMRS.");

        log.info("[P14-Fase5] Vistoria registrada: licenciamento {} resultado={}",
            licId, vistoriaAprovada ? "APROVADA" : "REPROVADA");
        return licenciamentoService.toDTO(lic);
    }

    /**
     * Admin CBMRS homologa o resultado da vistoria de renovacao.
     *
     * Requer perfil ADMIN ou CHEFE_SSEG_BBM.
     * Requer status EM_VISTORIA_RENOVACAO.
     *
     * Deferida (vistoria aprovada):
     *   - Marco: HOMOLOG_VISTORIA_RENOV_DEFERIDO
     *   - Nova dtValidadeAppci = hoje + ANOS_VALIDADE_APPCI_RENOVADO (5 anos)
     *   - Marco: LIBERACAO_RENOV_APPCI
     *   - Status -> APPCI_EMITIDO (= ALVARA_VIGENTE)
     *
     * Indeferida (retorna para vistoria / CIV):
     *   - Marco: HOMOLOG_VISTORIA_RENOV_INDEFERIDO
     *   - Status -> CIV_EMITIDO (cidadao deve corrigir pendencias e retomar)
     *
     * RN-152 (deferimento) / RN-153 (CIV).
     *
     * @param licId      ID do licenciamento
     * @param deferida   true = deferida (aprovada), false = indeferida (CIV)
     * @param keycloakId sub do JWT do admin
     * @return LicenciamentoDTO com novo status e nova data de validade (se deferida)
     */
    @Transactional
    public LicenciamentoDTO homologarVistoria(Long licId, boolean deferida, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario admin     = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.EM_VISTORIA_RENOVACAO,
            "RN-152", "Homologacao de vistoria so e permitida com status EM_VISTORIA_RENOVACAO.");

        if (deferida) {
            // Emissao do novo APPCI com nova data de validade
            LocalDate novaValidade = LocalDate.now().plusYears(ANOS_VALIDADE_APPCI_RENOVADO);
            lic.setDtValidadeAppci(novaValidade);
            lic.setStatus(StatusLicenciamento.APPCI_EMITIDO);
            licenciamentoRepository.save(lic);

            registrarMarco(lic, TipoMarco.HOMOLOG_VISTORIA_RENOV_DEFERIDO, admin,
                "CBMRS homologou vistoria de renovacao como DEFERIDA.");
            registrarMarco(lic, TipoMarco.LIBERACAO_RENOV_APPCI, admin,
                "Novo APPCI emitido. Nova data de validade: "
                + novaValidade.format(DateTimeFormatter.ISO_LOCAL_DATE) + ".");

            notificarEnvolvidos(lic,
                "SOL -- Renovacao DEFERIDA -- Novo APPCI emitido (ID " + licId + ")",
                "A vistoria de renovacao do licenciamento ID " + licId
                + " foi homologada como DEFERIDA pelo CBMRS.\n\n"
                + "Novo APPCI emitido com validade ate: "
                + novaValidade.format(DateTimeFormatter.ISO_LOCAL_DATE) + ".\n\n"
                + "Acesse o portal SOL para tomar ciencia do novo alvara.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");

            log.info("[P14-Fase5] Vistoria homologada DEFERIDA: licenciamento {} nova validade {} -> APPCI_EMITIDO",
                licId, novaValidade);
        } else {
            // Vistoria reprovada: CIV emitida
            lic.setStatus(StatusLicenciamento.CIV_EMITIDO);
            licenciamentoRepository.save(lic);

            registrarMarco(lic, TipoMarco.HOMOLOG_VISTORIA_RENOV_INDEFERIDO, admin,
                "CBMRS homologou vistoria de renovacao como INDEFERIDA. CIV emitida.");

            notificarEnvolvidos(lic,
                "SOL -- Renovacao INDEFERIDA -- CIV emitida (ID " + licId + ")",
                "A vistoria de renovacao do licenciamento ID " + licId
                + " foi homologada como INDEFERIDA pelo CBMRS.\n\n"
                + "Um Comunicado de Inconformidade na Vistoria (CIV) foi emitido. "
                + "Corrija as pendencias apontadas e acesse o portal SOL para retomar "
                + "o processo de renovacao.\n\n"
                + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
                + "Sistema Online de Licenciamento -- SOL");

            log.info("[P14-Fase5] Vistoria homologada INDEFERIDA: licenciamento {} -> CIV_EMITIDO", licId);
        }

        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 6A -- CIENCIA DO NOVO APPCI
    // =========================================================================

    /**
     * Cidadao/RT toma ciencia do novo APPCI emitido apos renovacao aprovada.
     *
     * Requer status APPCI_EMITIDO (ja transitado pelo homologarVistoria).
     * Marco: CIENCIA_APPCI_RENOVACAO.
     * RN-152.
     *
     * Operacao idempotente: se o marco ja existe, nao cria duplicata.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do cidadao/RT
     * @return LicenciamentoDTO com marco CIENCIA_APPCI_RENOVACAO registrado
     */
    @Transactional
    public LicenciamentoDTO cienciaAppci(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.APPCI_EMITIDO,
            "RN-152", "Ciencia do APPCI de renovacao so e permitida com status APPCI_EMITIDO.");
        validarEnvolvido(lic, usuario);

        // RN-152: idempotente -- nao duplicar ciencia
        if (!marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco(
                licId, TipoMarco.CIENCIA_APPCI_RENOVACAO)) {
            registrarMarco(lic, TipoMarco.CIENCIA_APPCI_RENOVACAO, usuario,
                "Cidadao/RT tomou ciencia do novo APPCI emitido apos renovacao. " +
                "Validade: " + (lic.getDtValidadeAppci() != null
                    ? lic.getDtValidadeAppci().format(DateTimeFormatter.ISO_LOCAL_DATE)
                    : "nao informada") + ".");
            registrarMarco(lic, TipoMarco.RENOVACAO_CONCLUIDA, usuario,
                "Processo de renovacao concluido com sucesso. Novo APPCI vigente.");
        }

        log.info("[P14-Fase6A] Ciencia do APPCI registrada: licenciamento {}", licId);
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // FASE 6B -- CIENCIA DA CIV E RETOMADA DA RENOVACAO
    // =========================================================================

    /**
     * Cidadao/RT toma ciencia da CIV emitida apos vistoria reprovada.
     *
     * Requer status CIV_EMITIDO.
     * Marco: CIENCIA_CIV_RENOVACAO.
     * RN-153.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do cidadao/RT
     * @return LicenciamentoDTO com marco CIENCIA_CIV_RENOVACAO registrado
     */
    @Transactional
    public LicenciamentoDTO cienciaCiv(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.CIV_EMITIDO,
            "RN-153", "Ciencia da CIV de renovacao so e permitida com status CIV_EMITIDO.");
        validarEnvolvido(lic, usuario);

        if (!marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco(
                licId, TipoMarco.CIENCIA_CIV_RENOVACAO)) {
            registrarMarco(lic, TipoMarco.CIENCIA_CIV_RENOVACAO, usuario,
                "Cidadao/RT tomou ciencia da CIV de renovacao. " +
                "Corrija as inconformidades e retome o processo de renovacao.");
        }

        log.info("[P14-Fase6B] Ciencia da CIV registrada: licenciamento {}", licId);
        return licenciamentoService.toDTO(lic);
    }

    /**
     * Retoma o processo de renovacao apos correcao das pendencias da CIV.
     *
     * Requer status CIV_EMITIDO.
     * Transicao: CIV_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO (loop P14).
     * Marco: INICIO_RENOVACAO (segundo ciclo).
     * RN-153.
     *
     * @param licId      ID do licenciamento
     * @param keycloakId sub do JWT do cidadao/RT
     * @return LicenciamentoDTO com status AGUARDANDO_ACEITE_RENOVACAO (novo ciclo)
     */
    @Transactional
    public LicenciamentoDTO retomarRenovacao(Long licId, String keycloakId) {
        Licenciamento lic = buscarPorId(licId);
        Usuario usuario   = buscarUsuario(keycloakId);

        validarStatusExato(lic, StatusLicenciamento.CIV_EMITIDO,
            "RN-153", "Retomada de renovacao so e permitida com status CIV_EMITIDO.");
        validarEnvolvido(lic, usuario);

        lic.setStatus(StatusLicenciamento.AGUARDANDO_ACEITE_RENOVACAO);
        licenciamentoRepository.save(lic);

        registrarMarco(lic, TipoMarco.INICIO_RENOVACAO, usuario,
            "Renovacao retomada apos correcao de CIV. Novo ciclo iniciado.");

        notificarEnvolvidos(lic,
            "SOL -- Renovacao retomada (ID " + licId + ")",
            "O processo de renovacao do licenciamento ID " + licId
            + " foi retomado apos correcao das inconformidades da CIV.\n\n"
            + "Acesse o portal SOL para aceitar o Anexo D e prosseguir com a renovacao.\n\n"
            + "Corpo de Bombeiros Militar do Rio Grande do Sul\n"
            + "Sistema Online de Licenciamento -- SOL");

        log.info("[P14-Fase6B] Renovacao retomada: licenciamento {} CIV_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO",
            licId);
        return licenciamentoService.toDTO(lic);
    }

    // =========================================================================
    // HELPERS INTERNOS
    // =========================================================================

    private Licenciamento buscarPorId(Long id) {
        return licenciamentoRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));
    }

    private Usuario buscarUsuario(String keycloakId) {
        return usuarioRepository.findByKeycloakId(keycloakId)
            .orElseThrow(() -> new BusinessException("AUTH-001",
                "Usuario autenticado nao encontrado no sistema. "
                + "Realize o login novamente."));
    }

    /**
     * RN-141: Valida que o licenciamento esta em status admissivel para iniciar renovacao.
     * Admite: APPCI_EMITIDO (= ALVARA_VIGENTE) ou ALVARA_VENCIDO.
     */
    private void validarStatusParaRenovacao(Licenciamento lic) {
        if (!STATUS_ENTRADA_RENOVACAO.contains(lic.getStatus())) {
            throw new BusinessException("RN-141",
                "Renovacao nao pode ser iniciada para licenciamento com status "
                + lic.getStatus() + ". Status admissiveis: APPCI_EMITIDO (alvara vigente) "
                + "ou ALVARA_VENCIDO.");
        }
    }

    /**
     * Valida que o status do licenciamento e exatamente o esperado.
     */
    private void validarStatusExato(Licenciamento lic, StatusLicenciamento esperado,
                                     String rn, String mensagem) {
        if (!esperado.equals(lic.getStatus())) {
            throw new BusinessException(rn,
                mensagem + " Status atual: " + lic.getStatus() + ". Esperado: " + esperado + ".");
        }
    }

    /**
     * RN-143: Valida que o usuario autenticado e RT ou RU do licenciamento.
     * Na stack Spring Boot, a validacao e por ID do Usuario (via Keycloak sub).
     */
    private void validarEnvolvido(Licenciamento lic, Usuario usuario) {
        boolean ehRt = lic.getResponsavelTecnico() != null
            && lic.getResponsavelTecnico().getId().equals(usuario.getId());
        boolean ehRu = lic.getResponsavelUso() != null
            && lic.getResponsavelUso().getId().equals(usuario.getId());

        if (!ehRt && !ehRu) {
            throw new BusinessException("RN-143",
                "Usuario nao e responsavel tecnico (RT) nem responsavel pelo uso (RU) "
                + "deste licenciamento. Operacoes de renovacao sao restritas aos envolvidos.");
        }
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
