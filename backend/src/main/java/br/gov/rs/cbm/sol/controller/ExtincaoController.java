package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.ExtincaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.service.ExtincaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de Extincao de Licenciamento (P12) do sistema SOL.
 *
 * POST /licenciamentos/{id}/solicitar-extincao  -- CIDADAO, RT, ADMIN
 * POST /licenciamentos/{id}/efetivar-extincao   -- ADMIN, CHEFE_SSEG_BBM
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Extincao", description = "Extincao de licenciamento (P12)")
public class ExtincaoController {

    private final ExtincaoService extincaoService;

    public ExtincaoController(ExtincaoService extincaoService) {
        this.extincaoService = extincaoService;
    }

    @PostMapping("/licenciamentos/{id}/solicitar-extincao")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Solicita extincao do licenciamento (P12-A)",
        description =
            "RN-109: status admissivel: ANALISE_PENDENTE, APPCI_EMITIDO, SUSPENSO. " +
            "RN-110: motivo obrigatorio. " +
            "Nao altera o status — registra marco EXTINCAO_SOLICITADA e notifica analista."
    )
    public ResponseEntity<LicenciamentoDTO> solicitarExtincao(
            @PathVariable Long id,
            @RequestBody ExtincaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            extincaoService.solicitarExtincao(id, dto.motivo(), jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/efetivar-extincao")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Efetiva extincao do licenciamento (P12-A e P12-B)",
        description =
            "RN-109: status admissivel: ANALISE_PENDENTE, APPCI_EMITIDO, SUSPENSO. " +
            "RN-111: motivo obrigatorio. " +
            "RN-112: status -> EXTINTO, ativo = false. " +
            "RN-113: EXTINTO e estado terminal. " +
            "Marco: EXTINCAO_EFETIVADA. Notifica RT e RU por e-mail."
    )
    public ResponseEntity<LicenciamentoDTO> efetivarExtincao(
            @PathVariable Long id,
            @RequestBody ExtincaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            extincaoService.efetivarExtincao(id, dto.motivo(), jwt.getSubject()));
    }
}
