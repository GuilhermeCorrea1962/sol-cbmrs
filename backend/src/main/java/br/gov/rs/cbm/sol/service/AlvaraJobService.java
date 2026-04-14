package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.entity.RotinaExecucao;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Agendador de Jobs Automaticos (P13) do sistema SOL.
 *
 * Orquestra a execucao dos jobs de ciclo de vida de alvaras (APPCIs).
 * A logica de negocio transacional por licenciamento esta em AlvaraVencimentoService;
 * este componente controla apenas os loops externos e o agendamento.
 *
 * Jobs implementados:
 *   P13-A  diario 00:01  Detecta APPCI_EMITIDO com dtValidadeAppci vencida -> ALVARA_VENCIDO
 *   P13-B  diario 00:01  Notifica envolvidos 90, 59 e 29 dias antes do vencimento
 *   P13-C  diario 00:01  Notifica envolvidos quando alvara venceu no intervalo recente
 *   P13-D  diario 00:31  Verificacao de notificacoes pendentes (stub — EmailService e assincrono)
 *   P13-E  a cada 12h    Verificacao de pagamento Banrisul CNAB 240 (stub — nao implementado)
 *
 * Todos os jobs rodam na timezone do servidor (America/Sao_Paulo configurada no SO).
 * RN-137: o cron deve usar o fuso horario local; nao ha offset hardcoded aqui pois
 * o servidor esta configurado com timezone America/Sao_Paulo.
 *
 * Obs: @EnableScheduling esta habilitado globalmente (BoletoJobService ja funciona
 * com @Scheduled desde a Sprint 11 — nenhuma configuracao adicional necessaria).
 */
@Service
public class AlvaraJobService {

    private static final Logger log = LoggerFactory.getLogger(AlvaraJobService.class);

    private final AlvaraVencimentoService alvaraVencimentoService;

    public AlvaraJobService(AlvaraVencimentoService alvaraVencimentoService) {
        this.alvaraVencimentoService = alvaraVencimentoService;
    }

    // -----------------------------------------------------------------------
    // P13-A + P13-B + P13-C — rotina diaria 00:01
    // -----------------------------------------------------------------------

    /**
     * Rotina diaria de alvaras — P13-A + P13-B + P13-C.
     *
     * Executada todos os dias as 00:01 pelo Spring Scheduler.
     * Tambem pode ser disparada manualmente via AlvaraAdminController
     * para testes em desenvolvimento/homologacao.
     *
     * Cron: 0 1 0 * * * (segundo, minuto, hora, dia-mes, mes, dia-semana)
     */
    @Scheduled(cron = "0 1 0 * * *")
    public void rotinaDiariaAlvaras() {
        log.info("[P13] Iniciando rotina diaria de alvaras em {}.", LocalDateTime.now());

        RotinaExecucao rotina = alvaraVencimentoService.iniciarRotina();
        int totalProcessados = 0;
        int totalErros       = 0;
        String mensagemErro  = null;

        try {
            // --- P13-A: Atualizar alvaras vencidos ---------------------------------
            List<Long> idsVencidos = alvaraVencimentoService.buscarAlvarasVencidosIds();
            log.info("[P13-A] {} alvara(s) vencido(s) detectado(s).", idsVencidos.size());
            for (Long licId : idsVencidos) {
                try {
                    alvaraVencimentoService.atualizarAlvaraVencido(licId);
                    totalProcessados++;
                } catch (Exception ex) {
                    log.error("[P13-A] Erro ao atualizar licenciamento {}: {}", licId, ex.getMessage(), ex);
                    totalErros++;
                }
            }

            // --- P13-B: Notificacoes 90/59/29 dias ---------------------------------
            LocalDate dataBase = alvaraVencimentoService.buscarDataBaseRotina();
            log.info("[P13-B] dataBase para notificacoes: {}.", dataBase);

            int[] diasNotificacao = {90, 59, 29};
            TipoMarco[] marcosNotificacao = {
                TipoMarco.NOTIFICACAO_SOLICITAR_RENOVACAO_90,
                TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59,
                TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29
            };

            for (int i = 0; i < diasNotificacao.length; i++) {
                int dias         = diasNotificacao[i];
                TipoMarco marco  = marcosNotificacao[i];
                List<Long> ids   = alvaraVencimentoService.buscarAlvarasAVencerIds(dataBase, dias);
                log.info("[P13-B] {} licenciamento(s) a vencer em {} dias (dataAlvo={}).",
                        ids.size(), dias, dataBase.plusDays(dias));
                for (Long licId : ids) {
                    try {
                        alvaraVencimentoService.registrarNotificacaoVencimento(licId, marco, dias);
                        totalProcessados++;
                    } catch (Exception ex) {
                        log.error("[P13-B] Erro ao notificar licenciamento {} ({} dias): {}",
                                licId, dias, ex.getMessage(), ex);
                        totalErros++;
                    }
                }
            }

            // --- P13-C: Notificacao alvara vencido ---------------------------------
            List<Long> idsParaNotifVencido = alvaraVencimentoService
                    .buscarAlvaresVencidosParaNotificacaoIds(dataBase);
            log.info("[P13-C] {} licenciamento(s) para notificacao de alvara vencido.", idsParaNotifVencido.size());
            for (Long licId : idsParaNotifVencido) {
                try {
                    alvaraVencimentoService.registrarNotificacaoAlvaraVencido(licId);
                    totalProcessados++;
                } catch (Exception ex) {
                    log.error("[P13-C] Erro ao registrar notificacao de alvara vencido para {}: {}",
                            licId, ex.getMessage(), ex);
                    totalErros++;
                }
            }

        } catch (Exception ex) {
            log.error("[P13] Erro inesperado na rotina diaria: {}", ex.getMessage(), ex);
            mensagemErro = ex.getMessage();
            totalErros++;
        } finally {
            alvaraVencimentoService.finalizarRotina(rotina.getId(), totalProcessados, totalErros, mensagemErro);
            log.info("[P13] Rotina diaria concluida. Processados: {}, Erros: {}.", totalProcessados, totalErros);
        }
    }

    // -----------------------------------------------------------------------
    // P13-D — verificacao de notificacoes pendentes (00:31)
    // -----------------------------------------------------------------------

    /**
     * P13-D: Verificacao de notificacoes pendentes.
     *
     * Na stack atual, o EmailService.notificarAsync ja e assincrono e tolerante
     * a falhas de SMTP (log de WARN, sem excecao propagada). Notificacoes que
     * nao foram entregues por falha transiente de SMTP serao reenviadas quando
     * a proxima execucao dos jobs P13-B/C as recriar (se o licenciamento ainda
     * for elegivel) — ou permanecerão registradas via log para analise operacional.
     *
     * Uma fila de notificacoes persistente (TB_LICENCIAMENTO_NOTIFICACAO) esta
     * especificada no documento de requisitos stack moderna (P13-D completo) e
     * pode ser implementada em sprint futura.
     *
     * Cron: 0 31 0 * * *
     */
    @Scheduled(cron = "0 31 0 * * *")
    public void verificarNotificacoesPendentes() {
        log.info("[P13-D] Verificacao de notificacoes pendentes (00:31). " +
                "EmailService.notificarAsync gerencia retentativas automaticamente via log WARN.");
    }

    // -----------------------------------------------------------------------
    // P13-E — verificacao de pagamento Banrisul CNAB 240 (a cada 12h)
    // -----------------------------------------------------------------------

    /**
     * P13-E: Verificacao de pagamento Banrisul CNAB 240.
     *
     * Integracao CNAB 240 com o Banrisul nao implementada nesta sprint.
     * O processamento do arquivo de retorno sera implementado em sprint futura,
     * seguindo a especificacao de Requisitos_P11_PagamentoBoleto_StackAtual.md,
     * secao 5 (Job P11-B) e Requisitos_P13_JobsAutomaticos_StackAtual.md, secao 7.
     *
     * Cron: 0 0 * /12 * * *  (a cada 12 horas)
     */
    @Scheduled(cron = "0 0 */12 * * *")
    public void verificarPagamentoBanrisul() {
        log.info("[P13-E] Verificacao de pagamento Banrisul (CNAB 240) -- nao implementado nesta sprint.");
    }
}
