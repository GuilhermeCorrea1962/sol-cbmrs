package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.UsuarioCreateDTO;
import br.gov.rs.cbm.sol.dto.UsuarioDTO;
import br.gov.rs.cbm.sol.service.UsuarioService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;

/**
 * Endpoints de gestao de usuarios do sistema SOL.
 *
 * Perfis de acesso:
 *   GET /        — ADMIN
 *   GET /{id}    — autenticado (usuario ve a si mesmo; ADMIN ve qualquer um)
 *   GET /cpf/{cpf} — ADMIN
 *   POST /       — ADMIN
 *   PUT /{id}    — ADMIN
 *   DELETE /{id} — ADMIN
 */
@RestController
@RequestMapping("/usuarios")
@SecurityRequirement(name = "bearerAuth")
@Tag(name = "Usuarios", description = "Gestao de usuarios do sistema SOL")
public class UsuarioController {

    private final UsuarioService usuarioService;

    public UsuarioController(UsuarioService usuarioService) {
        this.usuarioService = usuarioService;
    }

    @GetMapping
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Lista todos os usuarios")
    public ResponseEntity<List<UsuarioDTO>> findAll() {
        return ResponseEntity.ok(usuarioService.findAll());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CHEFE_SSEG_BBM', 'CIDADAO', 'RT')")
    @Operation(summary = "Busca usuario por ID")
    public ResponseEntity<UsuarioDTO> findById(@PathVariable Long id) {
        return ResponseEntity.ok(usuarioService.findById(id));
    }

    @GetMapping("/cpf/{cpf}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Busca usuario por CPF")
    public ResponseEntity<UsuarioDTO> findByCpf(@PathVariable String cpf) {
        return ResponseEntity.ok(usuarioService.findByCpf(cpf));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Cria novo usuario")
    public ResponseEntity<UsuarioDTO> create(@Valid @RequestBody UsuarioCreateDTO dto) {
        UsuarioDTO criado = usuarioService.create(dto);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(criado.id())
                .toUri();
        return ResponseEntity.created(location).body(criado);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Atualiza dados de usuario")
    public ResponseEntity<UsuarioDTO> update(
            @PathVariable Long id,
            @Valid @RequestBody UsuarioDTO dto) {
        return ResponseEntity.ok(usuarioService.update(id, dto));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Desativa usuario (soft delete)")
    public ResponseEntity<Void> deactivate(@PathVariable Long id) {
        usuarioService.deactivate(id);
        return ResponseEntity.noContent().build();
    }
}
