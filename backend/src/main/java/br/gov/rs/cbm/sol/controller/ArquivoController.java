package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.ArquivoEDDTO;
import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;
import br.gov.rs.cbm.sol.service.ArquivoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.io.InputStream;
import java.net.URI;
import java.util.List;
import java.util.Map;

/**
 * Endpoints de gestao de arquivos digitais (ArquivoED) do sistema SOL.
 *
 * POST  /arquivos/upload                         — faz upload de documento
 * GET   /arquivos/{id}                           — metadados do arquivo
 * GET   /arquivos/{id}/download                  — download direto (stream)
 * GET   /arquivos/{id}/download-url              — URL pre-assinada (1 hora)
 * DELETE /arquivos/{id}                          — remove do MinIO + banco
 * GET   /licenciamentos/{licenciamentoId}/arquivos      — lista arquivos do licenciamento
 * GET   /licenciamentos/{licenciamentoId}/arquivos?tipo — filtra por tipo
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Arquivos", description = "Upload e download de documentos dos licenciamentos")
public class ArquivoController {

    private final ArquivoService arquivoService;

    public ArquivoController(ArquivoService arquivoService) {
        this.arquivoService = arquivoService;
    }

    // ---------------------------------------------------------------------------
    // Upload
    // ---------------------------------------------------------------------------

    @PostMapping(value = "/arquivos/upload",
                 consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Faz upload de documento para um licenciamento",
               description = "RN-ARQ-001 a 003: arquivo nao pode ser vazio, max 50 MB, tipo PDF/JPEG/PNG/TIFF/ZIP/DWG")
    public ResponseEntity<ArquivoEDDTO> upload(
            @RequestPart("file")
            @Parameter(description = "Arquivo a ser enviado (max 50 MB)")
            MultipartFile file,

            @RequestParam("licenciamentoId")
            @Parameter(description = "ID do licenciamento ao qual o arquivo sera vinculado")
            Long licenciamentoId,

            @RequestParam("tipoArquivo")
            @Parameter(description = "Tipo logico do documento (PPCI, ART_RRT, MEMORIA_CALCULO...)")
            TipoArquivo tipoArquivo,

            @AuthenticationPrincipal Jwt jwt) {

        String keycloakId = jwt.getSubject();
        ArquivoEDDTO criado = arquivoService.upload(file, licenciamentoId, tipoArquivo, keycloakId);

        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
            .path("/api/arquivos/{id}")
            .buildAndExpand(criado.id())
            .toUri();

        return ResponseEntity.created(location).body(criado);
    }

    // ---------------------------------------------------------------------------
    // Metadados
    // ---------------------------------------------------------------------------

    @GetMapping("/arquivos/{id}")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Retorna metadados de um arquivo")
    public ResponseEntity<ArquivoEDDTO> findById(@PathVariable Long id) {
        return ResponseEntity.ok(arquivoService.findById(id));
    }

    // ---------------------------------------------------------------------------
    // Download direto
    // ---------------------------------------------------------------------------

    @GetMapping("/arquivos/{id}/download")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Download direto do arquivo (stream)")
    public ResponseEntity<InputStreamResource> download(@PathVariable Long id) {
        ArquivoEDDTO meta = arquivoService.findById(id);
        InputStream stream = arquivoService.download(id);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.parseMediaType(
            meta.contentType() != null ? meta.contentType() : "application/octet-stream"));
        headers.setContentDisposition(
            ContentDisposition.attachment().filename(meta.nomeArquivo()).build());
        if (meta.tamanho() != null) {
            headers.setContentLength(meta.tamanho());
        }

        return ResponseEntity.ok()
            .headers(headers)
            .body(new InputStreamResource(stream));
    }

    // ---------------------------------------------------------------------------
    // URL pre-assinada
    // ---------------------------------------------------------------------------

    @GetMapping("/arquivos/{id}/download-url")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Gera URL pre-assinada para download direto (valida 1 hora)")
    public ResponseEntity<Map<String, String>> getDownloadUrl(@PathVariable Long id) {
        String url = arquivoService.getPresignedUrl(id);
        return ResponseEntity.ok(Map.of("url", url));
    }

    // ---------------------------------------------------------------------------
    // Exclusao
    // ---------------------------------------------------------------------------

    @DeleteMapping("/arquivos/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'CIDADAO', 'RT')")
    @Operation(summary = "Remove arquivo do MinIO e do banco")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        arquivoService.delete(id);
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------------------
    // Listagem por licenciamento (rota aninhada)
    // ---------------------------------------------------------------------------

    @GetMapping("/licenciamentos/{licenciamentoId}/arquivos")
    @PreAuthorize("isAuthenticated()")
    @Operation(summary = "Lista arquivos de um licenciamento",
               description = "Parametro opcional 'tipo' filtra por TipoArquivo (ex: PPCI, ART_RRT)")
    public ResponseEntity<List<ArquivoEDDTO>> findByLicenciamento(
            @PathVariable Long licenciamentoId,
            @RequestParam(required = false) TipoArquivo tipo) {

        List<ArquivoEDDTO> lista = tipo != null
            ? arquivoService.findByLicenciamentoETipo(licenciamentoId, tipo)
            : arquivoService.findByLicenciamento(licenciamentoId);

        return ResponseEntity.ok(lista);
    }
}
