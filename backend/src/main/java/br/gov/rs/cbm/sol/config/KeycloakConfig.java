package br.gov.rs.cbm.sol.config;

import org.keycloak.admin.client.Keycloak;
import org.keycloak.admin.client.KeycloakBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configura o Keycloak Admin Client como bean Spring.
 *
 * Usa as credenciais do admin-cli (master realm) para operacoes
 * administrativas: criar usuarios, atribuir roles, resetar senha.
 *
 * Propriedades lidas de application.yml:
 *   keycloak.server-url, keycloak.admin.client-id,
 *   keycloak.admin.username, keycloak.admin.password
 */
@Configuration
public class KeycloakConfig {

    @Value("${keycloak.server-url}")
    private String serverUrl;

    @Value("${keycloak.admin.client-id}")
    private String adminClientId;

    @Value("${keycloak.admin.username}")
    private String adminUsername;

    @Value("${keycloak.admin.password}")
    private String adminPassword;

    @Bean
    public Keycloak keycloakAdminClient() {
        return KeycloakBuilder.builder()
                .serverUrl(serverUrl)
                .realm("master")
                .clientId(adminClientId)
                .username(adminUsername)
                .password(adminPassword)
                .build();
    }
}
