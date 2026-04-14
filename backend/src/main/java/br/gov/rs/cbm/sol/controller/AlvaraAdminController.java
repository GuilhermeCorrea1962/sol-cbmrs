package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.service.AlvaraJobService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * Controller administrativo para acionamento manual dos jobs de P13.
 *
 * Permite disparar a rotina diaria de alvaras fora do horario agendado,
 * facilitando testes em ambiente de desenvolvimento e homologacao sem
 * aguardar a execucao automatica das 00:01.
 *
 * Seguranca: restrito aos perfis ADMIN e CHEFE_SSEG_BBM.
 *
 * Endpoints:
 *   POST /admin/jobs/rotina-alvara  — Dispara P13-A + P13-B + P13-C imediatamente (sincrono)
 */
@RestController
public class AlvaraAdminController {

    private final AlvaraJobService alvaraJobService;

    public AlvaraAdminController(AlvaraJobService alvaraJobService) {
        this.alvaraJobService = alvaraJobService;
    }

    /**
     * Executa a rotina diaria de alvaras imediatamente (P13-A + P13-B + P13-C).
     *
     * A execucao e sincrona: a resposta HTTP e retornada somente apos a conclusao
     * completa da rotina. Em producao, aguardar ate 2 minutos para bases grandes.
     *
     * @return JSON com confirmacao, data/hora de execucao e descricao dos jobs
     */
    @PostMapping("/admin/jobs/rotina-alvara")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    public ResponseEntity<Map<String, Object>> executarRotinaAlvara() {
        alvaraJobService.rotinaDiariaAlvaras();
        return ResponseEntity.ok(Map.of(
                "executado", true,
                "dataHora", LocalDateTime.now().toString(),
                "jobs", "P13-A (APPCI_EMITIDO -> ALVARA_VENCIDO) + P13-B (90/59/29d) + P13-C (pos-vencimento)",
                "descricao", "Rotina diaria de alvaras disparada manualmente pelo administrador."
        ));
    }
}
