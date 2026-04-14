package br.gov.rs.cbm.sol.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

/**
 * Servico de envio de e-mails do sistema SOL.
 *
 * Em ambiente de desenvolvimento utiliza MailHog (SMTP local na porta 1025).
 * Interface web para visualizar os e-mails: http://localhost:8025
 *
 * O metodo notificarAsync e executado de forma assincrona (@Async + AsyncConfig)
 * para que falhas no servidor SMTP nao propaguem excecao para o chamador e
 * nao atrasem a resposta HTTP da operacao principal (ex: emitirCia, deferir).
 *
 * Configuracao SMTP em application.yml:
 *   spring.mail.host = localhost
 *   spring.mail.port = 1025
 */
@Service
public class EmailService {

    private static final Logger log = LoggerFactory.getLogger(EmailService.class);

    private static final String REMETENTE = "sol-noreply@cbmrs.rs.gov.br";

    private final JavaMailSender mailSender;

    public EmailService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }

    /**
     * Envia e-mail de texto simples de forma assincrona.
     *
     * Falhas sao logadas como WARN e nao propagam excecao, garantindo que
     * o fluxo de negocio (alteracao de status, registro de marco) nao seja
     * revertido por problemas de infraestrutura de e-mail.
     *
     * @param destinatario endereco de e-mail do destinatario
     * @param assunto      assunto da mensagem
     * @param corpo        corpo da mensagem em texto plano
     */
    @Async
    public void notificarAsync(String destinatario, String assunto, String corpo) {
        if (destinatario == null || destinatario.isBlank()) {
            log.warn("Envio de e-mail ignorado: destinatario vazio -- assunto: {}", assunto);
            return;
        }
        try {
            SimpleMailMessage msg = new SimpleMailMessage();
            msg.setFrom(REMETENTE);
            msg.setTo(destinatario);
            msg.setSubject(assunto);
            msg.setText(corpo);
            mailSender.send(msg);
            log.debug("E-mail enviado para {} -- assunto: {}", destinatario, assunto);
        } catch (Exception ex) {
            log.warn("Falha ao enviar e-mail para {} -- assunto: {} -- erro: {}",
                destinatario, assunto, ex.getMessage());
        }
    }
}
