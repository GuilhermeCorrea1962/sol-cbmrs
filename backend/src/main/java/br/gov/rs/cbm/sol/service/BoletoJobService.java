package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.entity.Boleto;
import br.gov.rs.cbm.sol.repository.BoletoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;

/**
 * Job automatico de vencimento de boletos (P11-B) do sistema SOL.
 *
 * Executa diariamente para verificar boletos PENDENTE com data de vencimento
 * anterior a data atual e transicioná-los para o status VENCIDO.
 *
 * Cada boleto vencido recebe:
 *   - Status: VENCIDO
 *   - Marco: BOLETO_VENCIDO
 *   - Notificacao por e-mail ao RT e RU do licenciamento
 *
 * O job e coordenado pelo BoletoService.vencerBoleto para garantir que toda a
 * logica de marco e notificacao seja executada dentro de uma transacao por boleto.
 *
 * Cron: executa todos os dias as 02:00 (horario do servidor).
 */
@Service
public class BoletoJobService {

    private static final Logger log = LoggerFactory.getLogger(BoletoJobService.class);

    private final BoletoRepository boletoRepository;
    private final BoletoService    boletoService;

    public BoletoJobService(BoletoRepository boletoRepository,
                            BoletoService boletoService) {
        this.boletoRepository = boletoRepository;
        this.boletoService    = boletoService;
    }

    /**
     * Verifica e vence boletos expirados.
     *
     * Executa diariamente as 02:00. Busca todos os boletos com status PENDENTE
     * e dtVencimento anterior a hoje, vencendo cada um individualmente via
     * BoletoService.vencerBoleto (transacao por boleto).
     */
    @Scheduled(cron = "0 0 2 * * *")
    public void vencerBoletosExpirados() {
        LocalDate hoje = LocalDate.now();
        List<Boleto> vencidos = boletoRepository.findBoletosVencidos(hoje);

        if (vencidos.isEmpty()) {
            log.debug("[P11-B] Nenhum boleto expirado encontrado em {}.", hoje);
            return;
        }

        log.info("[P11-B] Processando {} boleto(s) expirado(s) em {}.", vencidos.size(), hoje);
        int sucessos  = 0;
        int erros     = 0;

        for (Boleto boleto : vencidos) {
            try {
                boletoService.vencerBoleto(boleto);
                log.info("[P11-B] Boleto ID {} vencido (licenciamento ID {}).",
                    boleto.getId(),
                    boleto.getLicenciamento() != null ? boleto.getLicenciamento().getId() : "?");
                sucessos++;
            } catch (Exception ex) {
                log.error("[P11-B] Erro ao vencer boleto ID {}: {}", boleto.getId(), ex.getMessage(), ex);
                erros++;
            }
        }

        log.info("[P11-B] Conclusao: {} vencido(s), {} erro(s).", sucessos, erros);
    }
}
