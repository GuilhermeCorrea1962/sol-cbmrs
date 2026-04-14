package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.BoletoDTO;
import br.gov.rs.cbm.sol.service.BoletoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.time.LocalDate;
import java.util.List;

/**
 * Endpoints de gestao de boletos (guias de recolhimento) do sistema SOL.
 *
 * GET  /boletos/licenciamento/{id}              — autenticado
 * POST /boletos/licenciamento/{id}              — ADMIN, ANALISTA, INSPETOR (gera boleto)
 * PATCH /boletos/{id}/confirmar-pagamento       — ADMIN, ANALISTA (confirma pagamento manual)
 */
@RestController
@RequestMapping("/boletos")
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Boletos", description = "Gestao de guias de recolhimento (P11)")
public class BoletoController {

    private final BoletoService boletoService;

    public BoletoController(BoletoService boletoService) {
        this.boletoService = boletoService;
    }

    @GetMapping("/licenciamento/{licenciamentoId}")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Lista boletos de um licenciamento")
    public ResponseEntity<List<BoletoDTO>> findByLicenciamento(
            @PathVariable Long licenciamentoId) {
        return ResponseEntity.ok(boletoService.findByLicenciamento(licenciamentoId));
    }

    @PostMapping("/licenciamento/{licenciamentoId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')")
    @Operation(summary = "Gera novo boleto para o licenciamento (P11-A passo 1)",
               description = "RN-090: sem boleto PENDENTE duplicado por licenciamento. "
                           + "RN-091: licenciamento isento nao gera boleto. "
                           + "Marco: BOLETO_GERADO.")
    public ResponseEntity<BoletoDTO> create(
            @PathVariable Long licenciamentoId,
            @AuthenticationPrincipal Jwt jwt) {
        BoletoDTO criado = boletoService.create(licenciamentoId, jwt.getSubject());
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/boletos/{id}")
                .buildAndExpand(criado.id())
                .toUri();
        return ResponseEntity.created(location).body(criado);
    }

    @PatchMapping("/{boletoId}/confirmar-pagamento")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(summary = "Confirma pagamento de boleto (P11-A passo 2)",
               description = "RN-095: boleto deve estar PENDENTE. "
                           + "Se dataPagamento apos vencimento: status VENCIDO, marco BOLETO_VENCIDO. "
                           + "Caso contrario: status PAGO, marco PAGAMENTO_CONFIRMADO.")
    public ResponseEntity<BoletoDTO> confirmarPagamento(
            @PathVariable Long boletoId,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dataPagamento,
            @AuthenticationPrincipal Jwt jwt) {
        LocalDate dataEfetiva = dataPagamento != null ? dataPagamento : LocalDate.now();
        return ResponseEntity.ok(
            boletoService.confirmarPagamento(boletoId, dataEfetiva, jwt.getSubject()));
    }
}
