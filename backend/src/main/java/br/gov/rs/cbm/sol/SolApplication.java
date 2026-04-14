package br.gov.rs.cbm.sol;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Ponto de entrada do SOL Backend.
 *
 * Sistema Online de Licenciamento — CBM-RS
 * Versão Autônoma Windows — Spring Boot 3 / Java 21 / Oracle XE
 */
@SpringBootApplication
@EnableScheduling
public class SolApplication {

    public static void main(String[] args) {
        SpringApplication.run(SolApplication.class, args);
    }
}
