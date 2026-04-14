package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.AnaliseDecisaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.service.AppciService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de Emissao do APPCI (P08) do sistema SOL.
 *
 * GET  /appci/vigentes
 *   Lista todos os licenciamentos com APPCI vigente (APPCI_EMITIDO), paginado.
 *
 * POST /licenciamentos/{id}/emitir-appci
 *   Emite o APPCI. Transicao: PRPCI_EMITIDO -> APPCI_EMITIDO.
 *   Calcula validade automaticamente: area <= 750 m² -> 2 anos; > 750 m² -> 5 anos.
 *
 * GET  /licenciamentos/{id}/appci
 *   Retorna os dados do APPCI de um licenciamento especifico.
 *   Exige status APPCI_EMITIDO.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "APPCI", description = "P08 - Emissao do Alvara de Prevencao e Protecao Contra Incendio")
public class AppciController {

    private final AppciService appciService;

    public AppciController(AppciService appciService) {
        this.appciService = appciService;
    }

    // ---------------------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------------------

    @GetMapping("/appci/vigentes")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')")
    @Operation(
        summary = "Lista APPCIs vigentes (APPCI_EMITIDO)",
        description = "Retorna todos os licenciamentos com Alvara emitido e vigente, paginado.")
    public ResponseEntity<Page<LicenciamentoDTO>> findVigentes(Pageable pageable) {
        return ResponseEntity.ok(appciService.findVigentes(pageable));
    }

    @GetMapping("/licenciamentos/{id}/appci")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CIDADAO', 'RT')")
    @Operation(
        summary = "Retorna dados do APPCI de um licenciamento",
        description = "Retorna dtValidadeAppci, dtVencimentoPrpci e dados completos do licenciamento. "
                    + "Exige status APPCI_EMITIDO (RN-P08-004).")
    public ResponseEntity<LicenciamentoDTO> findAppci(@PathVariable Long id) {
        return ResponseEntity.ok(appciService.findAppci(id));
    }

    // ---------------------------------------------------------------------------
    // Emissao do APPCI
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/emitir-appci")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(
        summary = "Emite o APPCI (PRPCI_EMITIDO -> APPCI_EMITIDO)",
        description = "RN-P08-001: status deve ser PRPCI_EMITIDO. "
                    + "RN-P08-002: validade calculada automaticamente pela area construida "
                    + "(area <= 750 m² = 2 anos; > 750 m² = 5 anos, RTCBMRS N.01/2024). "
                    + "RN-P08-003: dtVencimentoPrpci preenchida automaticamente se ausente. "
                    + "Marco: APPCI_EMITIDO. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> emitirAppci(
            @PathVariable Long id,
            @RequestBody(required = false) AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String obs = (dto != null) ? dto.observacao() : null;
        return ResponseEntity.ok(
            appciService.emitirAppci(id, obs, jwt.getSubject()));
    }
}
