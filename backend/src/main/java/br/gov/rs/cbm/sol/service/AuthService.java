package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.LoginRequestDTO;
import br.gov.rs.cbm.sol.dto.TokenResponseDTO;
import br.gov.rs.cbm.sol.dto.UserInfoDTO;
import br.gov.rs.cbm.sol.exception.BusinessException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.List;

/**
 * Servico de autenticacao (P01).
 *
 * Atua como proxy entre o cliente (Angular ou API consumer) e o Keycloak,
 * usando o fluxo Resource Owner Password Credentials (ROPC).
 *
 * Este padrao e adequado para:
 *   - Aplicacoes nativas/mobile que nao conseguem realizar redirect OAuth2
 *   - Testes automatizados e smoke tests de CI/CD
 *   - Backend-for-frontend onde o Angular delega o login ao backend
 *
 * PRE-REQUISITO no Keycloak:
 *   O client 'sol-frontend' no realm 'sol' deve ter
 *   "Direct access grants" habilitado (ver documentacao Sprint 3).
 */
@Service
public class AuthService {

    private final RestTemplate restTemplate;
    private final UsuarioService usuarioService;

    @Value("${keycloak.server-url}")
    private String keycloakServerUrl;

    @Value("${keycloak.realm}")
    private String realm;

    @Value("${keycloak.client.client-id}")
    private String clientId;

    public AuthService(UsuarioService usuarioService) {
        this.restTemplate = new RestTemplate();
        this.usuarioService = usuarioService;
    }

    // ---------------------------------------------------------------------------
    // Login (P01 -- fluxo ROPC)
    // ---------------------------------------------------------------------------

    /**
     * Autentica usuario via Keycloak e retorna o par access_token / refresh_token.
     *
     * Realiza POST para /realms/sol/protocol/openid-connect/token com
     * grant_type=password e retorna o JSON deserializado em TokenResponseDTO.
     *
     * Erros retornados pelo Keycloak (401 invalid_grant) sao convertidos
     * em BusinessException("AUTH-001") para padronizar a resposta ao cliente.
     */
    public TokenResponseDTO login(LoginRequestDTO dto) {
        String tokenUrl = keycloakServerUrl + "/realms/" + realm + "/protocol/openid-connect/token";

        MultiValueMap<String, String> params = new LinkedMultiValueMap<>();
        params.add("grant_type", "password");
        params.add("client_id", clientId);
        params.add("username", dto.username());
        params.add("password", dto.password());
        params.add("scope", "openid");

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        try {
            ResponseEntity<TokenResponseDTO> response = restTemplate.postForEntity(
                    tokenUrl, new HttpEntity<>(params, headers), TokenResponseDTO.class);
            return response.getBody();
        } catch (HttpClientErrorException e) {
            throw new BusinessException("AUTH-001", "Credenciais invalidas ou usuario desabilitado.");
        }
    }

    // ---------------------------------------------------------------------------
    // Refresh token
    // ---------------------------------------------------------------------------

    /**
     * Renova o access token usando o refresh token.
     * O refresh token e valido por 30 minutos (configuracao padrao do realm sol).
     */
    public TokenResponseDTO refresh(String refreshToken) {
        String tokenUrl = keycloakServerUrl + "/realms/" + realm + "/protocol/openid-connect/token";

        MultiValueMap<String, String> params = new LinkedMultiValueMap<>();
        params.add("grant_type", "refresh_token");
        params.add("client_id", clientId);
        params.add("refresh_token", refreshToken);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        try {
            ResponseEntity<TokenResponseDTO> response = restTemplate.postForEntity(
                    tokenUrl, new HttpEntity<>(params, headers), TokenResponseDTO.class);
            return response.getBody();
        } catch (HttpClientErrorException e) {
            throw new BusinessException("AUTH-002", "Refresh token invalido ou expirado.");
        }
    }

    // ---------------------------------------------------------------------------
    // Logout
    // ---------------------------------------------------------------------------

    /**
     * Invalida o refresh token no Keycloak (revoga a sessao).
     * O access token continua valido ate expirar (stateless JWT).
     * O cliente deve descartar ambos os tokens localmente.
     */
    public void logout(String refreshToken) {
        String logoutUrl = keycloakServerUrl + "/realms/" + realm + "/protocol/openid-connect/logout";

        MultiValueMap<String, String> params = new LinkedMultiValueMap<>();
        params.add("client_id", clientId);
        params.add("refresh_token", refreshToken);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        try {
            restTemplate.postForEntity(logoutUrl, new HttpEntity<>(params, headers), Void.class);
        } catch (HttpClientErrorException e) {
            // Token ja expirado -- logout silencioso e comportamento correto
        }
    }

    // ---------------------------------------------------------------------------
    // Dados do usuario autenticado
    // ---------------------------------------------------------------------------

    /**
     * Retorna informacoes do usuario autenticado combinando JWT e registro local.
     *
     * Estrategia:
     *   1. Extrai keycloakId (sub) e roles do JWT
     *   2. Busca o registro local pelo keycloakId
     *   3. Se nao encontrar (ex: admin criado diretamente no Keycloak),
     *      retorna apenas os dados do JWT (nome/email do claim)
     */
    public UserInfoDTO me(Jwt jwt) {
        String keycloakId = jwt.getSubject();
        List<String> roles = jwt.getClaimAsStringList("roles");

        var usuarioOpt = usuarioService.findAll().stream()
                .filter(u -> keycloakId.equals(u.keycloakId()))
                .findFirst();

        if (usuarioOpt.isPresent()) {
            var u = usuarioOpt.get();
            return new UserInfoDTO(
                    u.id(),
                    keycloakId,
                    u.nome(),
                    u.email(),
                    u.tipoUsuario() != null ? u.tipoUsuario().name() : null,
                    roles
            );
        }

        // Fallback para usuarios Keycloak sem registro local (ex: sol-admin de testes)
        return new UserInfoDTO(
                null,
                keycloakId,
                jwt.getClaimAsString("name"),
                jwt.getClaimAsString("email"),
                null,
                roles
        );
    }
}
