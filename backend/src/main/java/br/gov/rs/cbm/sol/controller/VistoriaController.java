package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.AnaliseDecisaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.VistoriaAgendamentoDTO;
import br.gov.rs.cbm.sol.service.VistoriaService;
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
 * Endpoints de Vistoria Presencial (P07) do sistema SOL.
 *
 * GET  /vistoria/fila
 *   Lista licenciamentos aguardando vistoria (VISTORIA_PENDENTE).
 *
 * GET  /vistoria/em-andamento
 *   Lista vistorias em andamento (EM_VISTORIA).
 *
 * GET  /vistoria/por-inspetor?inspetorId=X
 *   Lista licenciamentos atribuidos ao inspetor.
 *
 * POST /licenciamentos/{id}/agendar-vistoria
 *   Agenda vistoria presencial. Transicao: DEFERIDO -> VISTORIA_PENDENTE.
 *
 * PATCH /licenciamentos/{id}/atribuir-inspetor?inspetorId=X
 *   Atribui inspetor ao licenciamento. Nao altera status.
 *
 * POST /licenciamentos/{id}/iniciar-vistoria
 *   Inicia vistoria. Transicao: VISTORIA_PENDENTE -> EM_VISTORIA.
 *
 * POST /licenciamentos/{id}/emitir-civ
 *   Emite CIV. Transicao: EM_VISTORIA -> CIV_EMITIDO.
 *
 * POST /licenciamentos/{id}/aprovar-vistoria
 *   Aprova vistoria. Transicao: EM_VISTORIA -> PRPCI_EMITIDO.
 *
 * POST /licenciamentos/{id}/registrar-ciencia-civ
 *   Registra ciencia do CIV. Transicao: CIV_EMITIDO -> CIV_CIENCIA.
 *
 * POST /licenciamentos/{id}/retomar-vistoria
 *   Retoma vistoria apos correcao. Transicao: CIV_CIENCIA -> EM_VISTORIA.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Vistoria Presencial", description = "P07 - Vistoria Presencial (CIV, PRPCI)")
public class VistoriaController {

    private final VistoriaService vistoriaService;

    public VistoriaController(VistoriaService vistoriaService) {
        this.vistoriaService = vistoriaService;
    }

    // ---------------------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------------------

    @GetMapping("/vistoria/fila")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')")
    @Operation(
        summary = "Lista licenciamentos aguardando vistoria (VISTORIA_PENDENTE)",
        description = "Fila de vistorias pendentes para atribuicao e agendamento.")
    public ResponseEntity<Page<LicenciamentoDTO>> findFila(Pageable pageable) {
        return ResponseEntity.ok(vistoriaService.findFila(pageable));
    }

    @GetMapping("/vistoria/em-andamento")
    @PreAuthorize("hasAnyRole('ADMIN', 'INSPETOR')")
    @Operation(
        summary = "Lista vistorias em andamento (EM_VISTORIA)",
        description = "Licenciamentos atualmente em fase de vistoria presencial.")
    public ResponseEntity<Page<LicenciamentoDTO>> findEmAndamento(Pageable pageable) {
        return ResponseEntity.ok(vistoriaService.findEmAndamento(pageable));
    }

    @GetMapping("/vistoria/por-inspetor")
    @PreAuthorize("hasAnyRole('ADMIN', 'INSPETOR')")
    @Operation(
        summary = "Lista licenciamentos atribuidos ao inspetor informado",
        description = "Retorna todos os licenciamentos com o inspetor especificado.")
    public ResponseEntity<Page<LicenciamentoDTO>> findByInspetor(
            @RequestParam Long inspetorId,
            Pageable pageable) {
        return ResponseEntity.ok(vistoriaService.findByInspetor(inspetorId, pageable));
    }

    // ---------------------------------------------------------------------------
    // Agendamento de vistoria
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/agendar-vistoria")
    @PreAuthorize("hasAnyRole('ANALISTA', 'ADMIN')")
    @Operation(
        summary = "Agenda vistoria presencial (DEFERIDO -> VISTORIA_PENDENTE)",
        description = "RN-P07-001: status deve ser DEFERIDO. "
                    + "RN-P07-002: dataVistoria obrigatoria. "
                    + "Marco: VISTORIA_AGENDADA. Notifica RT, RU e inspetor (se atribuido).")
    public ResponseEntity<LicenciamentoDTO> agendarVistoria(
            @PathVariable Long id,
            @RequestBody VistoriaAgendamentoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            vistoriaService.agendarVistoria(
                id, dto.dataVistoria(), dto.observacao(), jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Atribuicao de inspetor
    // ---------------------------------------------------------------------------

    @PatchMapping("/licenciamentos/{id}/atribuir-inspetor")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Atribui inspetor ao licenciamento (nao altera status)",
        description = "Associa o inspetor responsavel pela vistoria. "
                    + "Pode ser realizado antes ou apos o agendamento. "
                    + "Notifica o inspetor por e-mail.")
    public ResponseEntity<LicenciamentoDTO> atribuirInspetor(
            @PathVariable Long id,
            @RequestParam Long inspetorId,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            vistoriaService.atribuirInspetor(id, inspetorId, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Inicio da vistoria
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/iniciar-vistoria")
    @PreAuthorize("hasAnyRole('INSPETOR', 'ADMIN')")
    @Operation(
        summary = "Inicia vistoria presencial (VISTORIA_PENDENTE -> EM_VISTORIA)",
        description = "RN-P07-003: status deve ser VISTORIA_PENDENTE. "
                    + "RN-P07-004: inspetor deve estar atribuido. "
                    + "Marco: VISTORIA_REALIZADA. Notifica RT e RU.")
    public ResponseEntity<LicenciamentoDTO> iniciarVistoria(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            vistoriaService.iniciarVistoria(id, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Emissao de CIV
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/emitir-civ")
    @PreAuthorize("hasAnyRole('INSPETOR', 'ADMIN')")
    @Operation(
        summary = "Emite CIV (EM_VISTORIA -> CIV_EMITIDO)",
        description = "RN-P07-005: status deve ser EM_VISTORIA. "
                    + "RN-P07-006: observacao com inconformidades obrigatoria. "
                    + "Marco: CIV_EMITIDO. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> emitirCiv(
            @PathVariable Long id,
            @RequestBody AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            vistoriaService.emitirCiv(id, dto.observacao(), jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Aprovacao da vistoria
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/aprovar-vistoria")
    @PreAuthorize("hasAnyRole('INSPETOR', 'ADMIN')")
    @Operation(
        summary = "Aprova vistoria e emite PRPCI (EM_VISTORIA -> PRPCI_EMITIDO)",
        description = "RN-P07-007: status deve ser EM_VISTORIA. "
                    + "Marco: VISTORIA_APROVADA. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> aprovarVistoria(
            @PathVariable Long id,
            @RequestBody(required = false) AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String obs = (dto != null) ? dto.observacao() : null;
        return ResponseEntity.ok(
            vistoriaService.aprovarVistoria(id, obs, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Ciencia do CIV pelo interessado
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/registrar-ciencia-civ")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")
    @Operation(
        summary = "Registra ciencia do CIV pelo interessado (CIV_EMITIDO -> CIV_CIENCIA)",
        description = "RN-P07-008: status deve ser CIV_EMITIDO. "
                    + "Observacao opcional. Marco: CIV_CIENCIA. Notifica o inspetor.")
    public ResponseEntity<LicenciamentoDTO> registrarCienciaCiv(
            @PathVariable Long id,
            @RequestBody(required = false) AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {

        String obs = (dto != null) ? dto.observacao() : null;
        return ResponseEntity.ok(
            vistoriaService.registrarCienciaCiv(id, obs, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Retomada da vistoria
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/retomar-vistoria")
    @PreAuthorize("hasAnyRole('INSPETOR', 'ADMIN')")
    @Operation(
        summary = "Retoma vistoria apos correcao do CIV (CIV_CIENCIA -> EM_VISTORIA)",
        description = "RN-P07-009: status deve ser CIV_CIENCIA. "
                    + "Marco: VISTORIA_REALIZADA. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> retomarVistoria(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {

        return ResponseEntity.ok(
            vistoriaService.retomarVistoria(id, jwt.getSubject()));
    }
}
