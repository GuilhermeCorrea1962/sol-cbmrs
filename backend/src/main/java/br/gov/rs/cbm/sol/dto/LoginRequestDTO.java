package br.gov.rs.cbm.sol.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Payload de login (P01).
 * username = CPF do usuario cadastrado no Keycloak.
 */
public record LoginRequestDTO(

        @NotBlank(message = "Username e obrigatorio")
        String username,

        @NotBlank(message = "Password e obrigatorio")
        String password
) {}
