package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.IsencaoRequestDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.service.IsencaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de Isencao de Taxa (P06) do sistema SOL.
 *
 * POST /licenciamentos/{id}/solicitar-isencao
 *   Cidadao/RT solicita isencao da taxa de licenciamento.
 *   Nao altera status — registra marco ISENCAO_SOLICITADA.
 *
 * POST /licenciamentos/{id}/deferir-isencao
 *   ADMIN defere a isencao: isentoTaxa = true.
 *   Marco: ISENCAO_DEFERIDA.
 *
 * POST /licenciamentos/{id}/indeferir-isencao
 *   ADMIN indefere a isencao: isentoTaxa permanece false.
 *   Marco: ISENCAO_INDEFERIDA.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Isencao de Taxa", description = "P06 - Solicitacao e Decisao de Isencao de Taxa")
public class IsencaoController {

    private final IsencaoService isencaoService;

    public IsencaoController(IsencaoService isencaoService) {
        this.isencaoService = isencaoService;
    }

    // ---------------------------------------------------------------------------
    // Solicitacao de isencao
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/solicitar-isencao")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(
        summary = "Solicita isencao da taxa de licenciamento",
        description = "RN-P06-001: motivo obrigatorio. "
                    + "RN-P06-002: nao permitido em EXTINTO, INDEFERIDO ou RENOVADO. "
                    + "Nao altera status do licenciamento. Marco: ISENCAO_SOLICITADA.")
    public ResponseEntity<LicenciamentoDTO> solicitarIsencao(
            @PathVariable Long id,
            @RequestBody IsencaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            isencaoService.solicitarIsencao(id, dto.motivo(), jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Deferimento da isencao
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/deferir-isencao")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Defere a isencao de taxa (isentoTaxa = true)",
        description = "RN-P06-004: nao permitido se isencao ja foi deferida. "
                    + "Marco: ISENCAO_DEFERIDA. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> deferirIsencao(
            @PathVariable Long id,
            @RequestBody(required = false) IsencaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String obs = (dto != null) ? dto.motivo() : null;
        return ResponseEntity.ok(
            isencaoService.deferirIsencao(id, obs, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Indeferimento da isencao
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/indeferir-isencao")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Indefere a isencao de taxa (isentoTaxa permanece false)",
        description = "RN-P06-003: motivo obrigatorio. "
                    + "Marco: ISENCAO_INDEFERIDA. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> indeferirIsencao(
            @PathVariable Long id,
            @RequestBody IsencaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            isencaoService.indeferirIsencao(id, dto.motivo(), jwt.getSubject()));
    }
}
