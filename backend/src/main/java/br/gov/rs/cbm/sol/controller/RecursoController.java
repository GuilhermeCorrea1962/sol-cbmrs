package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.RecursoDTO;
import br.gov.rs.cbm.sol.service.RecursoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de Recurso CIA/CIV (P10) do sistema SOL.
 *
 * Interposicao (cidadao/RT/ADMIN):
 *   POST /licenciamentos/{id}/interpor-recurso   -- CIA_CIENCIA|CIV_CIENCIA -> RECURSO_PENDENTE
 *
 * Analise administrativa (ADMIN/CHEFE_SSEG_BBM):
 *   POST /licenciamentos/{id}/iniciar-recurso    -- RECURSO_PENDENTE -> EM_RECURSO
 *   POST /licenciamentos/{id}/deferir-recurso    -- EM_RECURSO -> DEFERIDO
 *   POST /licenciamentos/{id}/indeferir-recurso  -- EM_RECURSO -> INDEFERIDO
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Recurso CIA/CIV", description = "P10 - Recurso Administrativo contra CIA ou CIV")
public class RecursoController {

    private final RecursoService recursoService;

    public RecursoController(RecursoService recursoService) {
        this.recursoService = recursoService;
    }

    @PostMapping("/licenciamentos/{id}/interpor-recurso")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(summary = "Interpos recurso contra CIA ou CIV (passo 1 de 3)",
               description = "RN-P10-001: status deve ser CIA_CIENCIA ou CIV_CIENCIA. "
                           + "RN-P10-002: motivo obrigatorio. "
                           + "Transicao: CIA_CIENCIA|CIV_CIENCIA -> RECURSO_PENDENTE. "
                           + "Marco: RECURSO_INTERPOSTO.")
    public ResponseEntity<LicenciamentoDTO> interporRecurso(
            @PathVariable Long id,
            @RequestBody RecursoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            recursoService.interporRecurso(id, dto.motivo(), jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/iniciar-recurso")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Inicia analise administrativa do recurso (passo 2 de 3)",
               description = "RN-P10-003: status deve ser RECURSO_PENDENTE. "
                           + "Transicao: RECURSO_PENDENTE -> EM_RECURSO. "
                           + "Marco: RECURSO_EM_ANALISE.")
    public ResponseEntity<LicenciamentoDTO> iniciarRecurso(
            @PathVariable Long id,
            @RequestBody(required = false) RecursoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        String obs = dto != null ? dto.motivo() : null;
        return ResponseEntity.ok(
            recursoService.iniciarRecurso(id, obs, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/deferir-recurso")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Defere o recurso, aprovando o licenciamento (passo 3a de 3)",
               description = "RN-P10-004: status deve ser EM_RECURSO. "
                           + "CIA/CIV considerado improcedente. "
                           + "Transicao: EM_RECURSO -> DEFERIDO. "
                           + "Marco: RECURSO_DEFERIDO.")
    public ResponseEntity<LicenciamentoDTO> deferirRecurso(
            @PathVariable Long id,
            @RequestBody(required = false) RecursoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        String obs = dto != null ? dto.motivo() : null;
        return ResponseEntity.ok(
            recursoService.deferirRecurso(id, obs, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/indeferir-recurso")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Indefere o recurso, encerrando o licenciamento (passo 3b de 3)",
               description = "RN-P10-004: status deve ser EM_RECURSO. "
                           + "RN-P10-005: motivo obrigatorio. "
                           + "CIA/CIV considerado procedente. "
                           + "Transicao: EM_RECURSO -> INDEFERIDO. "
                           + "Marco: RECURSO_INDEFERIDO.")
    public ResponseEntity<LicenciamentoDTO> indeferirRecurso(
            @PathVariable Long id,
            @RequestBody RecursoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            recursoService.indeferirRecurso(id, dto.motivo(), jwt.getSubject()));
    }
}
