package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.AnexoDRenovacaoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.dto.RenovacaoRequestDTO;
import br.gov.rs.cbm.sol.service.RenovacaoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * Endpoints de Renovacao de Licenciamento (P14) do sistema SOL.
 *
 * Processo P14 -- Renovacao de APPCI (Alvara de Prevencao e Protecao Contra Incendio).
 * Cobre as seis fases do fluxo de renovacao conforme o BPMN P14_RenovacaoLicenciamento_StackAtual.bpmn.
 *
 * Regras de negocio: RN-141 a RN-160.
 *
 * Endpoints implementados:
 *
 *   LISTAGEM
 *   GET  /licenciamentos/renovacao/elegiveis       -- licenciamentos elegiveis (CIDADAO/RT)
 *   GET  /licenciamentos/renovacao/em-andamento    -- renovacoes em andamento (CIDADAO/RT)
 *
 *   FASE 1 -- INICIACAO
 *   POST /licenciamentos/{id}/renovacao/iniciar    -- iniciar renovacao (CIDADAO/RT)
 *
 *   FASE 2 -- ACEITE DO ANEXO D
 *   GET  /licenciamentos/{id}/renovacao/anexo-d    -- ler Anexo D (CIDADAO/RT)
 *   PUT  /licenciamentos/{id}/renovacao/aceitar-anexo-d    -- aceitar Anexo D
 *   DELETE /licenciamentos/{id}/renovacao/aceitar-anexo-d  -- remover aceite
 *   POST /licenciamentos/{id}/renovacao/confirmar  -- confirmar renovacao
 *   POST /licenciamentos/{id}/renovacao/recusar    -- recusar/cancelar renovacao
 *
 *   FASE 3 -- PAGAMENTO OU ISENCAO
 *   POST /licenciamentos/{id}/renovacao/solicitar-isencao  -- solicitar isencao (CIDADAO/RT)
 *   POST /licenciamentos/{id}/renovacao/analisar-isencao   -- analisar isencao (ADMIN)
 *   POST /licenciamentos/{id}/renovacao/confirmar-pagamento -- confirmar pgto (ADMIN - testes)
 *
 *   FASE 4 -- DISTRIBUICAO
 *   POST /licenciamentos/{id}/renovacao/distribuir         -- distribuir vistoria (ADMIN)
 *
 *   FASE 5 -- VISTORIA
 *   POST /licenciamentos/{id}/renovacao/registrar-vistoria -- resultado (INSPETOR/ADMIN)
 *   POST /licenciamentos/{id}/renovacao/homologar-vistoria -- homologar (ADMIN)
 *
 *   FASE 6 -- CONCLUSAO
 *   POST /licenciamentos/{id}/renovacao/ciencia-appci      -- ciencia APPCI (CIDADAO/RT)
 *   POST /licenciamentos/{id}/renovacao/ciencia-civ        -- ciencia CIV (CIDADAO/RT)
 *   POST /licenciamentos/{id}/renovacao/retomar            -- retomar apos CIV (CIDADAO/RT)
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Renovacao", description = "Renovacao de licenciamento -- APPCI (P14)")
public class RenovacaoController {

    private final RenovacaoService renovacaoService;

    public RenovacaoController(RenovacaoService renovacaoService) {
        this.renovacaoService = renovacaoService;
    }

    // =========================================================================
    // LISTAGEM
    // =========================================================================

    @GetMapping("/licenciamentos/renovacao/elegiveis")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Lista licenciamentos elegiveis para renovacao",
        description =
            "RN-155: retorna licenciamentos em APPCI_EMITIDO (alvara vigente) ou ALVARA_VENCIDO " +
            "onde o usuario autenticado e RT ou RU. Base para a tela 'Minhas Renovacoes'."
    )
    public ResponseEntity<List<LicenciamentoDTO>> listarElegiveis(
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.listarElegiveisParaRenovacao(jwt.getSubject()));
    }

    @GetMapping("/licenciamentos/renovacao/em-andamento")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Lista renovacoes em andamento do usuario",
        description =
            "RN-154: retorna licenciamentos em qualquer status de renovacao ativo " +
            "(AGUARDANDO_ACEITE_RENOVACAO, AGUARDANDO_PAGAMENTO_RENOVACAO, " +
            "AGUARDANDO_DISTRIBUICAO_RENOV, EM_VISTORIA_RENOVACAO, CIV_EMITIDO)."
    )
    public ResponseEntity<List<LicenciamentoDTO>> listarEmAndamento(
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.listarRenovacoesEmAndamento(jwt.getSubject()));
    }

    // =========================================================================
    // FASE 1 -- INICIACAO
    // =========================================================================

    @PostMapping("/licenciamentos/{id}/renovacao/iniciar")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Inicia o processo de renovacao do licenciamento (P14 Fase 1)",
        description =
            "RN-141: status admissivel: APPCI_EMITIDO (alvara vigente) ou ALVARA_VENCIDO. " +
            "RN-143: usuario deve ser RT ou RU do licenciamento. " +
            "Transicao: -> AGUARDANDO_ACEITE_RENOVACAO. Marco: INICIO_RENOVACAO."
    )
    public ResponseEntity<LicenciamentoDTO> iniciarRenovacao(
            @PathVariable Long id,
            @RequestBody(required = false) RenovacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.iniciarRenovacao(id, jwt.getSubject()));
    }

    // =========================================================================
    // FASE 2 -- ACEITE DO ANEXO D
    // =========================================================================

    @GetMapping("/licenciamentos/{id}/renovacao/anexo-d")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Retorna o Anexo D de Renovacao para leitura (P14 Fase 2)",
        description =
            "RN-144: retorna texto do Anexo D, status de aceite e dados do APPCI vigente " +
            "(data de validade, numero do pedido). Nao altera estado."
    )
    public ResponseEntity<AnexoDRenovacaoDTO> getAnexoD(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.getAnexoD(id, jwt.getSubject()));
    }

    @PutMapping("/licenciamentos/{id}/renovacao/aceitar-anexo-d")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Registra aceite do Anexo D de Renovacao (P14 Fase 2)",
        description =
            "RN-144: requer status AGUARDANDO_ACEITE_RENOVACAO. " +
            "Marco: ACEITE_ANEXOD_RENOVACAO. Operacao idempotente."
    )
    public ResponseEntity<AnexoDRenovacaoDTO> aceitarAnexoD(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.aceitarAnexoD(id, jwt.getSubject()));
    }

    @DeleteMapping("/licenciamentos/{id}/renovacao/aceitar-anexo-d")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Remove o aceite do Anexo D de Renovacao (P14 Fase 2)",
        description =
            "RN-144: permite que o cidadao reveja os termos antes de confirmar. " +
            "Requer status AGUARDANDO_ACEITE_RENOVACAO. Marco: REMOCAO_ACEITE_ANEXOD_RENOVACAO."
    )
    public ResponseEntity<AnexoDRenovacaoDTO> removerAceiteAnexoD(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.removerAceiteAnexoD(id, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/confirmar")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Confirma a renovacao apos aceite do Anexo D (P14 Fase 2)",
        description =
            "RN-145: requer status AGUARDANDO_ACEITE_RENOVACAO e aceite do Anexo D. " +
            "Transicao: -> AGUARDANDO_PAGAMENTO_RENOVACAO."
    )
    public ResponseEntity<LicenciamentoDTO> confirmarRenovacao(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.confirmarRenovacao(id, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/recusar")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Recusa a renovacao e faz rollback de status (P14 Fase 2)",
        description =
            "RN-145: requer AGUARDANDO_ACEITE_RENOVACAO. " +
            "Rollback: se dtValidadeAppci >= hoje -> APPCI_EMITIDO; senao -> ALVARA_VENCIDO. " +
            "Marco: RENOVACAO_CANCELADA."
    )
    public ResponseEntity<LicenciamentoDTO> recusarRenovacao(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.recusarRenovacao(id, jwt.getSubject()));
    }

    // =========================================================================
    // FASE 3 -- PAGAMENTO OU ISENCAO
    // =========================================================================

    @PostMapping("/licenciamentos/{id}/renovacao/solicitar-isencao")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Solicita isencao da taxa de vistoria de renovacao (P14 Fase 3)",
        description =
            "RN-147: requer status AGUARDANDO_PAGAMENTO_RENOVACAO. " +
            "Marco: SOLICITACAO_ISENCAO_RENOVACAO. Admin devera analisar via /analisar-isencao."
    )
    public ResponseEntity<LicenciamentoDTO> solicitarIsencao(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.solicitarIsencao(id, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/analisar-isencao")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Analisa solicitacao de isencao de taxa de vistoria (P14 Fase 3)",
        description =
            "RN-148: requer status AGUARDANDO_PAGAMENTO_RENOVACAO. " +
            "deferida=true -> AGUARDANDO_DISTRIBUICAO_RENOV + marco ANALISE_ISENCAO_RENOV_APROVADO. " +
            "deferida=false -> permanece AGUARDANDO_PAGAMENTO_RENOVACAO + marco ANALISE_ISENCAO_RENOV_REPROVADO."
    )
    public ResponseEntity<LicenciamentoDTO> analisarIsencao(
            @PathVariable Long id,
            @RequestBody RenovacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        boolean deferida = dto.deferida() != null && dto.deferida();
        return ResponseEntity.ok(
            renovacaoService.analisarIsencao(id, deferida, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/confirmar-pagamento")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Confirma pagamento do boleto de vistoria de renovacao -- apenas testes (P14 Fase 3)",
        description =
            "RN-149: em producao, pagamento e confirmado exclusivamente via CNAB 240 Banrisul (job P13-E). " +
            "Este endpoint e somente para homologacao/testes. " +
            "Transicao: AGUARDANDO_PAGAMENTO_RENOVACAO -> AGUARDANDO_DISTRIBUICAO_RENOV. " +
            "Marco: LIQUIDACAO_VISTORIA_RENOVACAO."
    )
    public ResponseEntity<LicenciamentoDTO> confirmarPagamento(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.confirmarPagamento(id, jwt.getSubject()));
    }

    // =========================================================================
    // FASE 4 -- DISTRIBUICAO
    // =========================================================================

    @PostMapping("/licenciamentos/{id}/renovacao/distribuir")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Distribui a vistoria de renovacao para um inspetor CBMRS (P14 Fase 4)",
        description =
            "RN-150: requer status AGUARDANDO_DISTRIBUICAO_RENOV. " +
            "Campo inspetorId e obrigatorio no body. " +
            "Transicao: -> EM_VISTORIA_RENOVACAO. Marco: DISTRIBUICAO_VISTORIA_RENOV."
    )
    public ResponseEntity<LicenciamentoDTO> distribuirVistoria(
            @PathVariable Long id,
            @RequestBody RenovacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.distribuirVistoria(id, dto.inspetorId(), jwt.getSubject()));
    }

    // =========================================================================
    // FASE 5 -- VISTORIA
    // =========================================================================

    @PostMapping("/licenciamentos/{id}/renovacao/registrar-vistoria")
    @PreAuthorize("hasAnyRole('INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Inspetor registra resultado da vistoria de renovacao (P14 Fase 5)",
        description =
            "RN-151: requer status EM_VISTORIA_RENOVACAO. " +
            "vistoriaAprovada=true -> marco VISTORIA_RENOVACAO. " +
            "vistoriaAprovada=false -> marco VISTORIA_RENOVACAO_CIV. " +
            "Status nao transita aqui -- aguarda homologacao (POST /homologar-vistoria)."
    )
    public ResponseEntity<LicenciamentoDTO> registrarVistoria(
            @PathVariable Long id,
            @RequestBody RenovacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        boolean aprovada = dto.vistoriaAprovada() != null && dto.vistoriaAprovada();
        return ResponseEntity.ok(
            renovacaoService.registrarVistoria(id, aprovada, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/homologar-vistoria")
    @PreAuthorize("hasAnyRole('ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Admin homologa resultado da vistoria de renovacao (P14 Fase 5)",
        description =
            "RN-152 (deferida): nova dtValidadeAppci = hoje + 5 anos; " +
            "marcos HOMOLOG_VISTORIA_RENOV_DEFERIDO + LIBERACAO_RENOV_APPCI; status -> APPCI_EMITIDO. " +
            "RN-153 (indeferida/CIV): marco HOMOLOG_VISTORIA_RENOV_INDEFERIDO; status -> CIV_EMITIDO."
    )
    public ResponseEntity<LicenciamentoDTO> homologarVistoria(
            @PathVariable Long id,
            @RequestBody RenovacaoRequestDTO dto,
            @AuthenticationPrincipal Jwt jwt) {
        boolean deferida = dto.deferida() != null && dto.deferida();
        return ResponseEntity.ok(
            renovacaoService.homologarVistoria(id, deferida, jwt.getSubject()));
    }

    // =========================================================================
    // FASE 6 -- CONCLUSAO
    // =========================================================================

    @PostMapping("/licenciamentos/{id}/renovacao/ciencia-appci")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Cidadao/RT toma ciencia do novo APPCI apos renovacao aprovada (P14 Fase 6A)",
        description =
            "RN-152: requer status APPCI_EMITIDO. " +
            "Marcos: CIENCIA_APPCI_RENOVACAO + RENOVACAO_CONCLUIDA. Operacao idempotente."
    )
    public ResponseEntity<LicenciamentoDTO> cienciaAppci(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.cienciaAppci(id, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/ciencia-civ")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Cidadao/RT toma ciencia da CIV apos vistoria reprovada (P14 Fase 6B)",
        description =
            "RN-153: requer status CIV_EMITIDO. " +
            "Marco: CIENCIA_CIV_RENOVACAO. Para retomar a renovacao, " +
            "chamar POST /renovacao/retomar apos corrigir pendencias."
    )
    public ResponseEntity<LicenciamentoDTO> cienciaCiv(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.cienciaCiv(id, jwt.getSubject()));
    }

    @PostMapping("/licenciamentos/{id}/renovacao/retomar")
    @PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN', 'CHEFE_SSEG_BBM')")
    @Operation(
        summary = "Retoma o processo de renovacao apos correcao das pendencias da CIV (P14 Fase 6B -- loop)",
        description =
            "RN-153: requer status CIV_EMITIDO. " +
            "Transicao: CIV_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO (loop de retorno do BPMN P14). " +
            "Marco: INICIO_RENOVACAO (segundo ciclo)."
    )
    public ResponseEntity<LicenciamentoDTO> retomarRenovacao(
            @PathVariable Long id,
            @AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(
            renovacaoService.retomarRenovacao(id, jwt.getSubject()));
    }
}
