package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.AnaliseDecisaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.service.CienciaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de Ciencia de CIA e Retomada de Analise (P05) do sistema SOL.
 *
 * POST /licenciamentos/{id}/registrar-ciencia-cia
 *   Cidadao/RT registra ciencia do Comunicado de Inconformidade.
 *   Transicao: CIA_EMITIDO -> CIA_CIENCIA.
 *
 * POST /licenciamentos/{id}/retomar-analise
 *   Analista retoma analise tecnica apos correcao das inconformidades.
 *   Transicao: CIA_CIENCIA -> EM_ANALISE.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Ciencia CIA", description = "P05 - Ciencia de CIA e Retomada de Analise")
public class CienciaController {

    private final CienciaService cienciaService;

    public CienciaController(CienciaService cienciaService) {
        this.cienciaService = cienciaService;
    }

    // ---------------------------------------------------------------------------
    // Registro de ciencia do CIA
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/registrar-ciencia-cia")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(
        summary = "Registra ciencia do CIA pelo interessado (CIA_EMITIDO -> CIA_CIENCIA)",
        description = "RN-P05-001: status deve ser CIA_EMITIDO. "
                    + "Observacao opcional. Marco: CIA_CIENCIA. "
                    + "Notifica o analista por e-mail.")
    public ResponseEntity<LicenciamentoDTO> registrarCienciaCia(
            @PathVariable Long id,
            @RequestBody(required = false) AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String obs = (dto != null) ? dto.observacao() : null;
        return ResponseEntity.ok(
            cienciaService.registrarCienciaCia(id, obs, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Retomada de analise apos correcao
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/retomar-analise")
    @PreAuthorize("hasAnyRole('ANALISTA', 'ADMIN')")
    @Operation(
        summary = "Retoma analise tecnica apos correcao das inconformidades (CIA_CIENCIA -> EM_ANALISE)",
        description = "RN-P05-002: status deve ser CIA_CIENCIA. "
                    + "Marco: INICIO_ANALISE (retomada). "
                    + "Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> retomarAnalise(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            cienciaService.retomarAnalise(id, jwt.getSubject()));
    }
}
