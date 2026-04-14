package br.gov.rs.cbm.sol;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

/**
 * Teste de contexto Spring Boot — usa H2 em memória para não depender do Oracle XE.
 */
@SpringBootTest
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:testdb;MODE=Oracle;DB_CLOSE_DELAY=-1",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "spring.jpa.database-platform=org.hibernate.dialect.H2Dialect",
    "spring.jpa.hibernate.ddl-auto=create-drop",
    "spring.security.oauth2.resourceserver.jwt.jwk-set-uri=https://example.com/jwks",
    "spring.security.oauth2.resourceserver.jwt.issuer-uri="
})
class SolApplicationTests {

    @Test
    void contextLoads() {
        // Verifica que o contexto Spring inicializa sem erros
    }
}
