package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.LicenciamentoCreateDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.service.LicenciamentoService;
import br.gov.rs.cbm.sol.service.UsuarioService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;

/**
 * Endpoints de gestao de licenciamentos do sistema SOL.
 *
 * GET /                   — ADMIN, ANALISTA, INSPETOR, CHEFE_SSEG_BBM
 * GET /{id}               — autenticado
 * GET /meus               — CIDADAO, RT (licenciamentos do usuario autenticado)
 * POST /                  — CIDADAO, RT
 * PATCH /{id}/status      — ADMIN, ANALISTA, INSPETOR, CHEFE_SSEG_BBM
 * DELETE /{id}            — CIDADAO, RT (somente RASCUNHO)
 */
@RestController
@RequestMapping("/licenciamentos")
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Licenciamentos", description = "Gestao de licenciamentos PPCI/PSPCIM")
public class LicenciamentoController {

    private final LicenciamentoService licenciamentoService;
    private final UsuarioService usuarioService;

    public LicenciamentoController(LicenciamentoService licenciamentoService,
                                   UsuarioService usuarioService) {
        this.licenciamentoService = licenciamentoService;
        this.usuarioService = usuarioService;
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Lista todos os licenciamentos (paginado)")
    public ResponseEntity<Page<LicenciamentoDTO>> findAll(
            @PageableDefault(size = 20, sort = "id") Pageable pageable) {
        return ResponseEntity.ok(licenciamentoService.findAll(pageable));
    }

    @GetMapping("/{id}")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Busca licenciamento por ID")
    public ResponseEntity<LicenciamentoDTO> findById(@PathVariable Long id) {
        return ResponseEntity.ok(licenciamentoService.findById(id));
    }

    @GetMapping("/meus")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT')")
    @Operation(summary = "Lista licenciamentos do usuario autenticado")
    public ResponseEntity<Page<LicenciamentoDTO>> findMeus(
            @AuthenticationPrincipal Jwt jwt,
            @PageableDefault(size = 20, sort = "id") Pageable pageable) {

        // Recupera o usuario local pelo keycloakId extraido do JWT
        String keycloakId = jwt.getSubject();
        var usuario = usuarioService.findById(
                usuarioService.findAll().stream()
                        .filter(u -> keycloakId.equals(u.keycloakId()))
                        .findFirst()
                        .orElseThrow()
                        .id()
        );

        return ResponseEntity.ok(licenciamentoService.findByUsuario(usuario.id(), pageable));
    }

    @PostMapping
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(summary = "Cria novo licenciamento (inicia wizard P03)")
    public ResponseEntity<LicenciamentoDTO> create(
            @Valid @RequestBody LicenciamentoCreateDTO dto) {
        LicenciamentoDTO criado = licenciamentoService.create(dto);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(criado.id())
                .toUri();
        return ResponseEntity.created(location).body(criado);
    }

    /**
     * Submete o licenciamento para analise (P03 - ultimo passo do wizard).
     * RN-P03-001: status deve ser RASCUNHO.
     * RN-P03-002: obrigatorio ter pelo menos um arquivo PPCI anexado.
     */
    @PostMapping("/{id}/submeter")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(summary = "Submete licenciamento para analise (RASCUNHO -> ANALISE_PENDENTE)",
               description = "RN-P03-001: status deve ser RASCUNHO. RN-P03-002: obrigatorio ter pelo menos um PPCI anexado.")
    public ResponseEntity<LicenciamentoDTO> submeter(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(licenciamentoService.submeter(id, jwt.getSubject()));
    }

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Atualiza status do licenciamento")
    public ResponseEntity<LicenciamentoDTO> updateStatus(
            @PathVariable Long id,
            @RequestParam StatusLicenciamento status) {
        return ResponseEntity.ok(licenciamentoService.updateStatus(id, status));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(summary = "Remove licenciamento em RASCUNHO (soft delete)")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        licenciamentoService.delete(id);
        return ResponseEntity.noContent().build();
    }
}
