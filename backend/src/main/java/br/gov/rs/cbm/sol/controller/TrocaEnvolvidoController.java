package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.TrocaEnvolvidoDTO;
import br.gov.rs.cbm.sol.service.TrocaEnvolvidoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de troca de envolvidos (P09) do sistema SOL.
 *
 * Troca RT (3 passos):
 *   POST /licenciamentos/{id}/solicitar-troca-rt  -- ADMIN ou RT
 *   POST /licenciamentos/{id}/autorizar-troca-rt  -- ADMIN
 *   POST /licenciamentos/{id}/efetivar-troca-rt   -- ADMIN
 *
 * Troca RU (1 passo):
 *   POST /licenciamentos/{id}/efetivar-troca-ru   -- ADMIN
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Troca de Envolvidos", description = "P09 - Substituicao de Responsavel Tecnico e Responsavel pelo Uso")
public class TrocaEnvolvidoController {

    private final TrocaEnvolvidoService trocaEnvolvidoService;

    public TrocaEnvolvidoController(TrocaEnvolvidoService trocaEnvolvidoService) {
        this.trocaEnvolvidoService = trocaEnvolvidoService;
    }

    @PostMapping("/licenciamentos/{id}/solicitar-troca-rt")
    @PreAuthorize("hasAnyRole('ADMIN', 'RT')")
    @Operation(summary = "Solicita troca do Responsavel Tecnico (passo 1 de 3)",
               description = "RN-P09-004: status nao pode ser EXTINTO/INDEFERIDO/RENOVADO. RN-P09-005: motivo obrigatorio.")
    public ResponseEntity<LicenciamentoDTO> solicitarTrocaRt(
            @PathVariable Long id,
            @RequestBody TrocaEnvolvidoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            trocaEnvolvidoService.solicitarTrocaRt(id, dto.motivo(), jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/autorizar-troca-rt")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Autoriza a troca do Responsavel Tecnico solicitada (passo 2 de 3)",
               description = "RN-P09-004: status nao pode ser EXTINTO/INDEFERIDO/RENOVADO.")
    public ResponseEntity<LicenciamentoDTO> autorizarTrocaRt(
            @PathVariable Long id,
            @RequestBody(required = false) TrocaEnvolvidoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        String obs = dto != null ? dto.motivo() : null;
        return ResponseEntity.ok(
            trocaEnvolvidoService.autorizarTrocaRt(id, obs, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/efetivar-troca-rt")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Efetiva a troca do Responsavel Tecnico (passo 3 de 3)",
               description = "RN-P09-001: novoResponsavelId obrigatorio. RN-P09-002: novo RT deve existir no sistema.")
    public ResponseEntity<LicenciamentoDTO> efetivarTrocaRt(
            @PathVariable Long id,
            @RequestBody TrocaEnvolvidoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            trocaEnvolvidoService.efetivarTrocaRt(id, dto.novoResponsavelId(), dto.motivo(), jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/efetivar-troca-ru")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Efetiva a troca do Responsavel pelo Uso (efetivacao direta)",
               description = "RN-P09-001: novoResponsavelId obrigatorio. RN-P09-002: novo RU deve existir no sistema.")
    public ResponseEntity<LicenciamentoDTO> efetivarTrocaRu(
            @PathVariable Long id,
            @RequestBody TrocaEnvolvidoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            trocaEnvolvidoService.efetivarTrocaRu(id, dto.novoResponsavelId(), dto.motivo(), jwt.getSubject()));
    }
}
