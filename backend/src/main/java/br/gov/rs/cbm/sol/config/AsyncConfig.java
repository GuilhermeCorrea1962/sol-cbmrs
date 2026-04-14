package br.gov.rs.cbm.sol.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * Habilita execucao assincrona de metodos anotados com @Async.
 *
 * Utilizado pelo EmailService.notificarAsync() para que o envio de e-mails
 * nao bloqueie o fluxo principal da requisicao HTTP. Em caso de falha no
 * servidor de e-mail (ex: MailHog desligado), a excecao e apenas logada
 * como WARN e nao afeta a resposta ao cliente.
 */
@Configuration
@EnableAsync
public class AsyncConfig {
}
