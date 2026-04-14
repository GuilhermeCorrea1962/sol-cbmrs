package br.gov.rs.cbm.sol.controller;

import br.gov.rs.cbm.sol.dto.LoginRequestDTO;
import br.gov.rs.cbm.sol.dto.TokenResponseDTO;
import br.gov.rs.cbm.sol.dto.UserInfoDTO;
import br.gov.rs.cbm.sol.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints de autenticacao do sistema SOL (P01).
 *
 * Endpoints publicos (sem JWT):
 *   POST /auth/login   -- autentica e retorna tokens
 *   POST /auth/refresh -- renova access token via refresh token
 *
 * Endpoints autenticados (com JWT):
 *   POST /auth/logout  -- invalida refresh token no Keycloak
 *   GET  /auth/me      -- dados do usuario autenticado
 */
@RestController
@RequestMapping("/auth")
@Tag(name = "Autenticacao", description = "P01 - Login, refresh, logout e dados do usuario autenticado")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    @Operation(summary = "Autentica usuario e retorna JWT (P01 -- ROPC via Keycloak)")
    public ResponseEntity<TokenResponseDTO> login(@Valid @RequestBody LoginRequestDTO dto) {
        return ResponseEntity.ok(authService.login(dto));
    }

    @PostMapping("/refresh")
    @Operation(summary = "Renova access token usando refresh token")
    public ResponseEntity<TokenResponseDTO> refresh(@RequestParam String refreshToken) {
        return ResponseEntity.ok(authService.refresh(refreshToken));
    }

    @PostMapping("/logout")
    @SecurityRequirement(name = "bearerAuth")
    @Operation(summary = "Invalida refresh token no Keycloak (encerra sessao)")
    public ResponseEntity<Void> logout(@RequestParam String refreshToken) {
        authService.logout(refreshToken);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    @SecurityRequirement(name = "bearerAuth")
    @Operation(summary = "Retorna dados do usuario autenticado extraidos do JWT e do banco local")
    public ResponseEntity<UserInfoDTO> me(@AuthenticationPrincipal Jwt jwt) {
        return ResponseEntity.ok(authService.me(jwt));
    }
}
