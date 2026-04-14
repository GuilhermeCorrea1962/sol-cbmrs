package br.gov.rs.cbm.sol.dto;

import java.util.List;

/**
 * Dados do usuario autenticado, retornados pelo endpoint GET /auth/me.
 * Combina informacoes do JWT (keycloakId, roles) com o registro local (id, nome, email).
 */
public record UserInfoDTO(

        Long id,
        String keycloakId,
        String nome,
        String email,
        String tipoUsuario,
        List<String> roles
) {}
