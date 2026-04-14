package br.gov.rs.cbm.sol.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Resposta do endpoint de token do Keycloak.
 * Mapeado diretamente do JSON retornado pelo endpoint
 * /realms/sol/protocol/openid-connect/token.
 */
public record TokenResponseDTO(

        @JsonProperty("access_token")
        String accessToken,

        @JsonProperty("refresh_token")
        String refreshToken,

        @JsonProperty("token_type")
        String tokenType,

        @JsonProperty("expires_in")
        Integer expiresIn,

        @JsonProperty("refresh_expires_in")
        Integer refreshExpiresIn,

        String scope
) {}
