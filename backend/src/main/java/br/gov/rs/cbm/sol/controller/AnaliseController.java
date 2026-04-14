package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.AnaliseDecisaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.MarcoProcessoDTO;
import br.gov.rs.cbm.sol.service.AnaliseService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * Endpoints de Analise Tecnica (P04) do sistema SOL.
 *
 * Consultas:
 *   GET /analise/fila           — fila de distribuicao (ANALISE_PENDENTE)
 *   GET /analise/em-andamento   — processos em analise (EM_ANALISE)
 *   GET /analise/por-analista   — licenciamentos de um analista especifico
 *
 * Acoes sobre licenciamentos:
 *   PATCH /licenciamentos/{id}/distribuir      — atribui analista
 *   POST  /licenciamentos/{id}/iniciar-analise — ANALISE_PENDENTE -> EM_ANALISE
 *   POST  /licenciamentos/{id}/emitir-cia      — EM_ANALISE -> CIA_EMITIDO
 *   POST  /licenciamentos/{id}/deferir         — EM_ANALISE -> DEFERIDO
 *   POST  /licenciamentos/{id}/indeferir       — EM_ANALISE -> INDEFERIDO
 *
 * Historico:
 *   GET /licenciamentos/{id}/marcos            — linha do tempo de eventos
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Analise Tecnica", description = "P04 - Analise Tecnica de Licenciamentos PPCI/PSPCIM")
public class AnaliseController {

    private final AnaliseService analiseService;

    public AnaliseController(AnaliseService analiseService) {
        this.analiseService = analiseService;
    }

    // ---------------------------------------------------------------------------
    // Consultas de fila
    // ---------------------------------------------------------------------------

    @GetMapping("/analise/fila")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Lista licenciamentos aguardando analise (ANALISE_PENDENTE)",
               description = "Fila de distribuicao para analistas. Ordenado por data de criacao (FIFO).")
    public ResponseEntity<Page<LicenciamentoDTO>> findFila(
            @PageableDefault(size = 20, sort = "dataCriacao") Pageable pageable) {
        return ResponseEntity.ok(analiseService.findFila(pageable));
    }

    @GetMapping("/analise/em-andamento")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Lista licenciamentos em analise tecnica (EM_ANALISE)")
    public ResponseEntity<Page<LicenciamentoDTO>> findEmAndamento(
            @PageableDefault(size = 20, sort = "dataCriacao") Pageable pageable) {
        return ResponseEntity.ok(analiseService.findEmAndamento(pageable));
    }

    @GetMapping("/analise/por-analista")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Lista licenciamentos atribuidos a um analista especifico")
    public ResponseEntity<Page<LicenciamentoDTO>> findPorAnalista(
            @RequestParam @Parameter(description = "ID do analista") Long analistaId,
            @PageableDefault(size = 20, sort = "dataCriacao") Pageable pageable) {
        return ResponseEntity.ok(analiseService.findByAnalista(analistaId, pageable));
    }

    // ---------------------------------------------------------------------------
    // Distribuicao
    // ---------------------------------------------------------------------------

    @PatchMapping("/licenciamentos/{id}/distribuir")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(summary = "Atribui analista ao licenciamento (distribuicao)",
               description = "RN-P04-001: licenciamento deve estar em ANALISE_PENDENTE. "
                           + "Registra marco DISTRIBUICAO e notifica o analista por e-mail.")
    public ResponseEntity<LicenciamentoDTO> distribuir(
            @PathVariable Long id,
            @RequestParam @Parameter(description = "ID do usuario analista") Long analistaId,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(analiseService.distribuir(id, analistaId, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Inicio de analise
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/iniciar-analise")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(summary = "Inicia a analise tecnica (ANALISE_PENDENTE -> EM_ANALISE)",
               description = "RN-P04-002: status deve ser ANALISE_PENDENTE. "
                           + "RN-P04-003: analista deve estar atribuido. "
                           + "Marco: INICIO_ANALISE.")
    public ResponseEntity<LicenciamentoDTO> iniciarAnalise(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(analiseService.iniciarAnalise(id, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Emissao de CIA
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/emitir-cia")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(summary = "Emite Comunicado de Inconformidade na Analise (EM_ANALISE -> CIA_EMITIDO)",
               description = "RN-P04-004: status deve ser EM_ANALISE. "
                           + "RN-P04-005: observacao obrigatoria com as inconformidades. "
                           + "Marco: CIA_EMITIDO. Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> emitirCia(
            @PathVariable Long id,
            @RequestBody AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(analiseService.emitirCia(id, dto.observacao(), jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Deferimento
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/deferir")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(summary = "Defere o licenciamento (EM_ANALISE -> DEFERIDO)",
               description = "RN-P04-006: status deve ser EM_ANALISE. "
                           + "Observacao opcional. Marco: APROVACAO_ANALISE. "
                           + "Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> deferir(
            @PathVariable Long id,
            @RequestBody(required = false) AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        String obs = (dto != null) ? dto.observacao() : null;
        return ResponseEntity.ok(analiseService.deferir(id, obs, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Indeferimento
    // ---------------------------------------------------------------------------

    @PostMapping("/licenciamentos/{id}/indeferir")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
    @Operation(summary = "Indefere o licenciamento (EM_ANALISE -> INDEFERIDO)",
               description = "RN-P04-007: status deve ser EM_ANALISE. "
                           + "RN-P04-008: motivo obrigatorio. Marco: REPROVACAO_ANALISE. "
                           + "Notifica RT e RU por e-mail.")
    public ResponseEntity<LicenciamentoDTO> indeferir(
            @PathVariable Long id,
            @RequestBody AnaliseDecisaoDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(analiseService.indeferir(id, dto.observacao(), jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------
    // Historico de marcos
    // ---------------------------------------------------------------------------

    @GetMapping("/licenciamentos/{id}/marcos")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Lista marcos do processo (historico de eventos do licenciamento)",
               description = "Retorna todos os eventos registrados para o licenciamento "
                           + "em ordem cronologica crescente.")
    public ResponseEntity<List<MarcoProcessoDTO>> findMarcos(@PathVariable Long id) {
        return ResponseEntity.ok(analiseService.findMarcos(id));
    }
}
