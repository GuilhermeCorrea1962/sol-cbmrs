package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.UsuarioCreateDTO;
import br.gov.rs.cbm.sol.dto.UsuarioDTO;
import br.gov.rs.cbm.sol.service.CadastroService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;

/**
 * Endpoints de cadastro de novos usuarios (P02).
 *
 * Ambos os endpoints sao publicos (nao exigem JWT) pois o usuario
 * ainda nao existe no sistema no momento do cadastro.
 *
 * Diferencas entre RT e RU:
 *   RT: campos numeroRegistro, tipoConselho e especialidade sao obrigatorios
 *       (validacao de negocio no CadastroService, nao no Bean Validation).
 *   RU: campos profissionais sao opcionais / ignorados.
 *
 * Em ambos os casos o TipoUsuario deve ser informado no DTO:
 *   RT -> tipoUsuario: "RT"
 *   RU -> tipoUsuario: "CIDADAO"
 */
@RestController
@RequestMapping("/cadastro")
@Tag(name = "Cadastro", description = "P02 - Registro de RT e RU no sistema e no Keycloak")
public class CadastroController {

    private final CadastroService cadastroService;

    public CadastroController(CadastroService cadastroService) {
        this.cadastroService = cadastroService;
    }

    @PostMapping("/rt")
    @Operation(summary = "Registra Responsavel Tecnico (RT) -- cria usuario local e no Keycloak")
    public ResponseEntity<UsuarioDTO> registrarRT(@Valid @RequestBody UsuarioCreateDTO dto) {
        UsuarioDTO criado = cadastroService.registrar(dto);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/usuarios/{id}")
                .buildAndExpand(criado.id())
                .toUri();
        return ResponseEntity.created(location).body(criado);
    }

    @PostMapping("/ru")
    @Operation(summary = "Registra Responsavel pelo Uso / Cidadao (RU) -- cria usuario local e no Keycloak")
    public ResponseEntity<UsuarioDTO> registrarRU(@Valid @RequestBody UsuarioCreateDTO dto) {
        UsuarioDTO criado = cadastroService.registrar(dto);
        URI location = ServletUriComponentsBuilder.fromCurrentContextPath()
                .path("/api/usuarios/{id}")
                .buildAndExpand(criado.id())
                .toUri();
        return ResponseEntity.created(location).body(criado);
    }
}
