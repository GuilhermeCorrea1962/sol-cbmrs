# Requisitos — P13: Jobs Automáticos do Sistema (Renovação de Alvarás)
## Versão Stack Moderna (Java 17+ · Spring Boot 3.x — sem dependência da PROCERGS)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P13 — Jobs Automáticos do Sistema
**Stack:** Java 17+ · Spring Boot 3.x · Spring Scheduler · Spring Data JPA · Hibernate 6 · PostgreSQL · Spring Mail · Thymeleaf
**Versão do documento:** 1.0
**Data:** 2026-03-14
**Referência:** `EJBTimerService` · `LicenciamentoRN` · `LicenciamentoNotificacaoRN` · `AppciRN` · `RotinaRN`

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Caracterização dos Jobs](#2-caracterização-dos-jobs)
3. [Job P13-A — Atualização de Alvarás Vencidos](#3-job-p13-a--atualização-de-alvarás-vencidos)
4. [Job P13-B — Notificação de Vencimento Próximo (90/59/29 dias)](#4-job-p13-b--notificação-de-vencimento-próximo-905929-dias)
5. [Job P13-C — Notificação de Alvará Vencido](#5-job-p13-c--notificação-de-alvará-vencido)
6. [Job P13-D — Envio de Notificações Pendentes por E-mail](#6-job-p13-d--envio-de-notificações-pendentes-por-e-mail)
7. [Job P13-E — Verificação de Pagamento Banrisul (CNAB 240)](#7-job-p13-e--verificação-de-pagamento-banrisul-cnab-240)
8. [Regras de Negócio](#8-regras-de-negócio)
9. [Modelo de Dados](#9-modelo-de-dados)
10. [Máquina de Estados do Licenciamento (Renovação)](#10-máquina-de-estados-do-licenciamento-renovação)
11. [Marcos de Auditoria (TipoMarco)](#11-marcos-de-auditoria-tipmarco)
12. [Templates de E-mail](#12-templates-de-e-mail)
13. [Rastreabilidade de Execução (Rotina)](#13-rastreabilidade-de-execução-rotina)
14. [Segurança e Autorização](#14-segurança-e-autorização)
15. [Classes e Componentes Java Moderna](#15-classes-e-componentes-java-moderna)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P13 é o conjunto de **jobs automáticos agendados** do SOL responsáveis por gerenciar o ciclo de vida de alvarás (APPCIs) e o fluxo de renovação de licenciamentos. Diferentemente dos processos P01–P12, **P13 não possui interação humana direta** — é um processo daemon que executa em background, acionado por agendador temporal.

O processo cobre cinco jobs com agendamentos distintos:

| Job | Nome | Agendamento | Responsabilidade |
|---|---|---|---|
| **P13-A** | Atualização de Alvarás Vencidos | Diário 00:01 | Detecta APPCIs com `dataValidade <= hoje` e transita licenciamentos de `ALVARA_VIGENTE` → `ALVARA_VENCIDO` |
| **P13-B** | Notificação de Vencimento Próximo | Diário 00:01 | Notifica envolvidos 90, 59 e 29 dias antes do vencimento do alvará |
| **P13-C** | Notificação de Alvará Vencido | Diário 00:01 | Notifica envolvidos quando o alvará venceu no dia anterior |
| **P13-D** | Envio de E-mails Pendentes | Diário 00:31 | Processa fila de notificações pendentes e reenvia as com erro |
| **P13-E** | Verificação de Pagamento Banrisul | A cada 12h | Lê retorno CNAB 240 do Banrisul e processa pagamentos de boletos |

### 1.2 Resultados possíveis

| Resultado | Situação/Estado |
|---|---|
| Alvarás vencidos detectados e atualizados | `SituacaoLicenciamento: ALVARA_VIGENTE → ALVARA_VENCIDO` |
| Envolvidos notificados sobre vencimento próximo | `TipoMarco: NOTIFICACAO_SOLICITAR_RENOVACAO_90/59/29` |
| Envolvidos notificados sobre alvará vencido | `TipoMarco: NOTIFICACAO_ALVARA_VENCIDO` |
| E-mails pendentes enviados | `SituacaoEnvio: PENDENTE → ENVIADO` |
| Falha de envio de e-mail registrada | `SituacaoEnvio: ERRO` (reprocessado no próximo ciclo) |
| Pagamentos CNAB processados | Boletos baixados/confirmados |

### 1.3 Referência na base de código atual

| Componente | Localização (stack atual) |
|---|---|
| Orquestrador dos jobs | `com.procergs.solcbm.EJBTimerService` |
| RN principal — vencimento e notificação | `com.procergs.solcbm.licenciamento.LicenciamentoRN` |
| Fila de notificações por e-mail | `com.procergs.solcbm.licenciamentonotificacao.LicenciamentoNotificacaoRN` |
| Validade do APPCI | `com.procergs.solcbm.appci.AppciRN` |
| Rastreabilidade de execução | `com.procergs.solcbm.rotina.RotinaRN` |
| Dados — queries de alvará | `com.procergs.solcbm.licenciamento.LicenciamentoBD` |
| Servlet alternativo (Workload) | `com.procergs.solcbm.batch.alvara.remote.AlvaraBatchServlet` |

---

## 2. Caracterização dos Jobs

### 2.1 Natureza do processo

P13 é um processo **puramente automatizado**:
- Sem interação de usuário.
- Sem endpoints REST de entrada (não é acionado via HTTP em produção).
- Sem autenticação OAuth2/OIDC (não há sessão de usuário).
- Executa com identidade de sistema (`sistema@sol.cbm.rs.gov.br`).

### 2.2 Agendamento na stack moderna (Spring Scheduler)

Na stack atual, os jobs são implementados via `@Singleton @Startup` + `@Schedule` (EJB 3.2). Na stack moderna, o equivalente direto é **Spring Scheduler** com `@Scheduled`.

```java
@Configuration
@EnableScheduling
public class SchedulerConfig {
    // Habilitação global do agendador Spring
}

@Component
@Slf4j
public class AlvaraScheduler {

    // Job P13-A, P13-B, P13-C — executa diariamente às 00:01
    @Scheduled(cron = "0 1 0 * * *", zone = "America/Sao_Paulo")
    @Transactional
    public void rotinaDiariaAlvaras() { ... }

    // Job P13-D — executa diariamente às 00:31
    @Scheduled(cron = "0 31 0 * * *", zone = "America/Sao_Paulo")
    public void enviarNotificacoesPendentes() { ... }

    // Job P13-E — executa a cada 12 horas
    @Scheduled(cron = "0 0 */12 * * *", zone = "America/Sao_Paulo")
    public void verificarPagamentoBanrisul() { ... }

    // Job de faturamento — 1º dia do mês às 01:05
    @Scheduled(cron = "0 5 1 1 * *", zone = "America/Sao_Paulo")
    public void faturamentoMes() { ... }
}
```

**Importante:** O fuso horário deve ser configurado explicitamente como `America/Sao_Paulo` para garantir execução nos horários locais corretos, independente do fuso da JVM/servidor.

### 2.3 Isolamento de transação por job

Cada job deve executar em transação independente. Na stack atual, o método de notificação usa `@TransactionAttribute(REQUIRES_NEW)` por licenciamento. Na stack moderna, recomenda-se:

```java
// Serviço transacional para cada unidade de trabalho
@Service
@Transactional(propagation = Propagation.REQUIRES_NEW)
public class AlvaraVencidoService {
    public void processarLicenciamento(Long idLicenciamento) { ... }
}
```

Isso garante que a falha em um licenciamento não reverta o processamento de outros.

### 2.4 Controle de execução única (Single Instance)

Em ambiente com múltiplas instâncias da aplicação (cluster), apenas uma instância deve executar o job por vez. Implementar com **ShedLock**:

```xml
<!-- pom.xml -->
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-spring</artifactId>
    <version>5.x</version>
</dependency>
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-provider-jdbc-template</artifactId>
    <version>5.x</version>
</dependency>
```

```java
@Scheduled(cron = "0 1 0 * * *", zone = "America/Sao_Paulo")
@SchedulerLock(name = "rotinaDiariaAlvaras", lockAtMostFor = "PT2H", lockAtLeastFor = "PT30M")
public void rotinaDiariaAlvaras() { ... }
```

---

## 3. Job P13-A — Atualização de Alvarás Vencidos

### 3.1 Objetivo

Detectar diariamente todos os licenciamentos com situação `ALVARA_VIGENTE` cujo APPCI vigente (`indVersaoVigente = true`) tenha `dataValidade <= LocalDate.now()` e transitar sua situação para `ALVARA_VENCIDO`.

### 3.2 Fluxo de execução

```
1. Consulta licenciamentos elegíveis (query abaixo)
2. Para cada licenciamento:
   a. Registra histórico de situação (LicenciamentoSituacaoHistEntity)
   b. Atualiza situacao → ALVARA_VENCIDO
   c. Marca todos os APPCIs do licenciamento com indVersaoVigente = false
   d. Marca documentos complementares do APPCI como não vigentes
3. Registra rotina de execução (RotinaEntity) para rastreabilidade
```

### 3.3 Query de detecção (Spring Data JPA)

```java
// LicenciamentoRepository
@Query("""
    SELECT l FROM LicenciamentoEntity l
    WHERE l.situacao = :situacao
      AND EXISTS (
          SELECT a FROM AppciEntity a
          WHERE a.licenciamento = l
            AND a.dataValidade <= :hoje
            AND a.versaoVigente = true
      )
    """)
List<LicenciamentoEntity> findAlvarasVencidos(
    @Param("situacao") SituacaoLicenciamento situacao,
    @Param("hoje") LocalDate hoje
);
```

**Chamada:**
```java
List<LicenciamentoEntity> lista = licenciamentoRepository
    .findAlvarasVencidos(SituacaoLicenciamento.ALVARA_VIGENTE, LocalDate.now());
```

### 3.4 Processamento por licenciamento

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void atualizarAlvaraVencido(LicenciamentoEntity lic) {
    // 1. Histórico de situação
    LicenciamentoSituacaoHistEntity hist = LicenciamentoSituacaoHistEntity.builder()
        .licenciamento(lic)
        .situacaoAnterior(lic.getSituacao())
        .situacaoAtual(SituacaoLicenciamento.ALVARA_VENCIDO)
        .dataHoraSituacaoAtual(LocalDateTime.now())
        .dataHoraSituacaoAnterior(lic.getDataHoraAtualizacao())
        .build();
    situacaoHistRepository.save(hist);

    // 2. Atualiza situação
    lic.setSituacao(SituacaoLicenciamento.ALVARA_VENCIDO);
    licenciamentoRepository.save(lic);

    // 3. Marca APPCIs como não vigentes
    appciRepository.findByLicenciamento(lic).forEach(appci -> {
        appci.setVersaoVigente(false);
        appciRepository.save(appci);
    });

    // 4. Marca documentos complementares como não vigentes
    docComplementarRepository.findByLicenciamento(lic).forEach(doc -> {
        doc.setVersaoVigente(false);
        docComplementarRepository.save(doc);
    });
}
```

### 3.5 Regras de negócio aplicáveis

- **RN-121:** Apenas licenciamentos com `situacao = ALVARA_VIGENTE` são processados. Licenciamentos já em `ALVARA_VENCIDO` ou em qualquer estado de renovação/análise não são re-processados.
- **RN-122:** O critério de vencimento usa `dataValidade <= LocalDate.now()` do APPCI com `versaoVigente = true`. Se nenhum APPCI vigente existir, o licenciamento não é elegível.
- **RN-123:** A transição gera obrigatoriamente um registro em `tb_licenciamento_situacao_hist` para fins de auditoria completa.
- **RN-124:** A marcação `versaoVigente = false` nos APPCIs é irreversível dentro deste job. A restauração só ocorre via processo de renovação (quando novo APPCI é emitido).

---

## 4. Job P13-B — Notificação de Vencimento Próximo (90/59/29 dias)

### 4.1 Objetivo

Notificar os envolvidos do licenciamento (RT, RU, Proprietários) quando o alvará está próximo do vencimento, nos marcos de 90, 59 e 29 dias antes da `dataValidade` do APPCI vigente.

### 4.2 Agendamento e execução

Executado dentro da rotina diária (00:01), após o Job P13-A. Os três marcos são processados sequencialmente na mesma execução:

```java
public void rotinaDiariaAlvaras() {
    alvaraVencidoService.atualizarAlvarasVencidos();                           // P13-A
    notificacaoVencimentoService.notificarAVencer(TipoMarco.NOTIFICACAO_SOLICITAR_RENOVACAO_90);    // P13-B 90d
    notificacaoVencimentoService.notificarAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59); // P13-B 59d
    notificacaoVencimentoService.notificarAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29); // P13-B 29d
    notificacaoVencimentoService.notificarVencidos();                           // P13-C
    rotinaService.finalizarRotina(RotinaEnum.GERAR_NOTIFICACAO_ALVARA_VENCIDO); // Rastreabilidade
}
```

### 4.3 Controle de reprocessamento (data de última execução)

Cada execução é comparada com a última execução registrada na tabela `tb_rotina`, usando `RotinaEnum.GERAR_NOTIFICACAO_ALVARA_VENCIDO`. Isso evita renotificação em re-execuções do mesmo dia:

```java
public void notificarAVencer(TipoMarco marco) {
    LocalDate dataBase = rotinaRepository
        .findUltimaExecucao(RotinaEnum.GERAR_NOTIFICACAO_ALVARA_VENCIDO)
        .map(RotinaEntity::getDataExecucao)
        .orElse(LocalDate.now().minusDays(1)); // Padrão: ontem

    int dias = diasPorMarco(marco);
    LocalDate dataAlvo = dataBase.plusDays(dias);

    List<LicenciamentoEntity> licenciamentos = licenciamentoRepository
        .findAlvarasAVencer(dataAlvo);

    licenciamentos.forEach(lic -> criarNotificacaoVencimento(lic, marco));
}
```

### 4.4 Query de licenciamentos a vencer

```java
// LicenciamentoRepository
@Query("""
    SELECT l FROM LicenciamentoEntity l
    WHERE l.situacao = com.cbmrs.sol.domain.SituacaoLicenciamento.ALVARA_VIGENTE
      AND EXISTS (
          SELECT a FROM AppciEntity a
          WHERE a.licenciamento = l
            AND a.dataValidade = :dataAlvo
            AND a.versaoVigente = true
      )
    """)
List<LicenciamentoEntity> findAlvarasAVencer(@Param("dataAlvo") LocalDate dataAlvo);
```

### 4.5 Seleção de destinatários por tipo de APPCI

A lógica de seleção de destinatários depende da quantidade de APPCIs do licenciamento:

| Condição | Destinatário RT |
|---|---|
| Licenciamento com 1 único APPCI | RT com `tipoResponsabilidade IN (PROJETO_EXECUCAO, EXECUCAO)` |
| Licenciamento com múltiplos APPCIs | RT com `tipoResponsabilidade = RENOVACAO_APPCI` |
| Sempre notificados | Todos os RU ativos + todos os Proprietários ativos |

```java
private List<String> resolverDestinatarios(LicenciamentoEntity lic) {
    List<String> emails = new ArrayList<>();

    // RU e Proprietários sempre notificados
    lic.getResponsaveisUso().stream()
        .filter(ru -> ru.getSituacao() == SituacaoEnvolvido.ATIVO)
        .map(ru -> ru.getUsuario().getEmail())
        .forEach(emails::add);

    lic.getProprietarios().stream()
        .filter(p -> p.getSituacao() == SituacaoEnvolvido.ATIVO)
        .map(p -> p.getUsuario().getEmail())
        .forEach(emails::add);

    // RT: seleção por tipo de responsabilidade
    long totalAppcis = appciRepository.countByLicenciamento(lic);
    TipoResponsabilidadeTecnica tipoRT = totalAppcis == 1
        ? null // PROJETO_EXECUCAO ou EXECUCAO
        : TipoResponsabilidadeTecnica.RENOVACAO_APPCI;

    lic.getResponsaveisTecnicos().stream()
        .filter(rt -> rt.getSituacao() == SituacaoEnvolvido.ATIVO)
        .filter(rt -> tipoRT == null
            ? Set.of(TipoResponsabilidadeTecnica.PROJETO_EXECUCAO, TipoResponsabilidadeTecnica.EXECUCAO)
                .contains(rt.getTipoResponsabilidade())
            : rt.getTipoResponsabilidade() == tipoRT)
        .map(rt -> rt.getUsuario().getEmail())
        .forEach(emails::add);

    return emails.stream().distinct().collect(toList());
}
```

### 4.6 Criação da notificação pendente

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void criarNotificacaoVencimento(LicenciamentoEntity lic, TipoMarco marco) {
    // Registra marco de auditoria
    LicenciamentoMarcoEntity marcoEntity = LicenciamentoMarcoEntity.builder()
        .licenciamento(lic)
        .tipoMarco(marco)
        .dataHora(LocalDateTime.now())
        .build();
    marcoRepository.save(marcoEntity);

    // Cria notificação pendente para cada destinatário
    List<String> destinatarios = resolverDestinatarios(lic);
    for (String email : destinatarios) {
        LicenciamentoNotificacaoEntity notif = LicenciamentoNotificacaoEntity.builder()
            .licenciamento(lic)
            .marco(marcoEntity)
            .tipoEnvio(TipoEnvioNotificacao.EMAIL)
            .situacao(SituacaoEnvioNotificacao.PENDENTE)
            .destinatario(email)
            .assunto(resolverAssunto(marco))
            .contexto(marco.name())
            .uuid(UUID.randomUUID().toString())
            .dataHoraCriacao(LocalDateTime.now())
            .build();
        notificacaoRepository.save(notif);
    }
}
```

### 4.7 Regras de negócio aplicáveis

- **RN-125:** A notificação de 90 dias é enviada quando `dataValidade do APPCI == LocalDate.now() + 90`. Não é uma janela — é um dia específico. O controle de "não reenviar" é feito pela data de última execução da rotina.
- **RN-126:** O mesmo padrão vale para 59 e 29 dias. Se a rotina não executou um dia (ex.: falha de servidor), ela recupera o intervalo perdido na próxima execução usando a data de última execução registrada.
- **RN-127:** Licenciamentos em estados de renovação já em andamento (`AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, etc.) **não** recebem nova notificação de vencimento — já estão no fluxo de renovação.
- **RN-128:** Destinatários com e-mail inválido ou ausente são ignorados (log de aviso emitido). O job não falha por destinatário inválido.

---

## 5. Job P13-C — Notificação de Alvará Vencido

### 5.1 Objetivo

Notificar os envolvidos quando o alvará **venceu no dia anterior** (ou desde a última execução). Diferente do P13-B (que avisa antes), este job notifica *após* o vencimento ter ocorrido.

### 5.2 Query de alvarás vencidos para notificação

```java
// LicenciamentoRepository
@Query("""
    SELECT l FROM LicenciamentoEntity l
    WHERE l.situacao = com.cbmrs.sol.domain.SituacaoLicenciamento.ALVARA_VENCIDO
      AND EXISTS (
          SELECT a FROM AppciEntity a
          WHERE a.licenciamento = l
            AND a.dataValidade >= :dataInicio
            AND a.dataValidade < :dataFim
      )
    """)
List<LicenciamentoEntity> findAlvarasVencidosParaNotificacao(
    @Param("dataInicio") LocalDate dataInicio,
    @Param("dataFim") LocalDate dataFim
);
```

Onde `dataInicio` = última execução e `dataFim` = hoje.

### 5.3 Marco registrado

`TipoMarco.NOTIFICACAO_ALVARA_VENCIDO`

### 5.4 Template de e-mail

`notificacao.email.template.perda.periodo.renovacao`

### 5.5 Regras de negócio aplicáveis

- **RN-129:** O marco `NOTIFICACAO_ALVARA_VENCIDO` é registrado apenas uma vez por licenciamento, mesmo que o job execute múltiplas vezes. Verificar existência do marco antes de inserir.
- **RN-130:** Os destinatários seguem a mesma lógica do P13-B (seleção por tipo de APPCI).

---

## 6. Job P13-D — Envio de Notificações Pendentes por E-mail

### 6.1 Objetivo

Processar a fila de notificações com `situacao = PENDENTE` ou `situacao = ERRO` e efetivamente enviar os e-mails via SMTP. Este job é separado do P13-B/C propositalmente: a criação da notificação (P13-B/C) é transacional; o envio (P13-D) é I/O externo e não deve ser incluído em transação de banco.

### 6.2 Fluxo de execução

```
1. Busca notificações com situacao IN (PENDENTE, ERRO)
2. Para cada notificação:
   a. Resolve template Thymeleaf com dados do licenciamento
   b. Envia e-mail via Spring Mail (JavaMailSender)
   c. Atualiza situacao → ENVIADO (sucesso) ou ERRO (falha)
   d. Se ERRO: incrementa contador de tentativas
3. Notificações com 3+ tentativas com ERRO: situacao → ABANDONADO (não reprocessa mais)
```

### 6.3 Implementação Spring Mail + Thymeleaf

```java
@Service
@RequiredArgsConstructor
public class NotificacaoEmailService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;
    private final LicenciamentoNotificacaoRepository notificacaoRepository;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void enviarNotificacao(LicenciamentoNotificacaoEntity notif) {
        try {
            // Resolve template
            Context ctx = new Context(new Locale("pt", "BR"));
            ctx.setVariable("licenciamento", notif.getLicenciamento());
            ctx.setVariable("dataValidade",
                appciRepository.findVigenteByLicenciamento(notif.getLicenciamento())
                    .map(a -> a.getDataValidade()).orElse(null));
            String corpo = templateEngine.process(
                resolverTemplate(notif.getContexto()), ctx);

            // Monta e envia e-mail
            MimeMessage msg = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(msg, "UTF-8");
            helper.setFrom("noreply@sol.cbm.rs.gov.br");
            helper.setTo(notif.getDestinatario());
            helper.setSubject(notif.getAssunto());
            helper.setText(corpo, true);
            mailSender.send(msg);

            // Marca como enviado
            notif.setSituacao(SituacaoEnvioNotificacao.ENVIADO);
            notif.setDataHoraEnvio(LocalDateTime.now());

        } catch (Exception e) {
            log.error("Falha ao enviar notificação {}: {}", notif.getUuid(), e.getMessage());
            notif.setTentativas(notif.getTentativas() + 1);
            notif.setSituacao(notif.getTentativas() >= 3
                ? SituacaoEnvioNotificacao.ABANDONADO
                : SituacaoEnvioNotificacao.ERRO);
        }
        notificacaoRepository.save(notif);
    }
}
```

### 6.4 Configuração Spring Mail (application.yml)

```yaml
spring:
  mail:
    host: ${MAIL_HOST:smtp.procergs.rs.gov.br}
    port: ${MAIL_PORT:587}
    username: ${MAIL_USERNAME}
    password: ${MAIL_PASSWORD}
    properties:
      mail.smtp.auth: true
      mail.smtp.starttls.enable: true
      mail.smtp.connectiontimeout: 5000
      mail.smtp.timeout: 5000
      mail.smtp.writetimeout: 5000
```

**Nota:** Na stack moderna sem PROCERGS, o servidor SMTP pode ser qualquer relay disponível (SendGrid, AWS SES, SMTP corporativo do governo RS). A chave é que a dependência do servidor SMTP é uma configuração de ambiente, não de código.

### 6.5 Regras de negócio aplicáveis

- **RN-131:** O envio de e-mail é operação de I/O externo e **não** deve estar dentro de transação de banco de dados. A notificação (`PENDENTE/ERRO/ENVIADO`) é atualizada em transação separada após o envio.
- **RN-132:** Notificações com `tentativas >= 3` e `situacao = ERRO` são marcadas como `ABANDONADO` e não são mais reprocessadas. Um alerta deve ser gerado para o administrador do sistema.
- **RN-133:** O job de envio executa também as notificações com `situacao = ERRO` (máx. 2 tentativas anteriores), garantindo reprocessamento automático de falhas transientes de SMTP.
- **RN-134:** O corpo do e-mail é renderizado pelo **Thymeleaf** a partir de templates HTML. O template usado é determinado pelo campo `contexto` da notificação (que armazena o nome do `TipoMarco`).

---

## 7. Job P13-E — Verificação de Pagamento Banrisul (CNAB 240)

### 7.1 Objetivo

A cada 12 horas, verificar o retorno de cobranças do Banrisul no formato CNAB 240 e processar pagamentos confirmados de boletos de vistoria de renovação.

### 7.2 Relação com P11

O Job P13-E é o equivalente automatizado do Job P11-B (`EJBTimer`) documentado em P11. Na stack moderna, a lógica permanece a mesma — o que muda é apenas o mecanismo de agendamento (EJB `@Schedule` → Spring `@Scheduled`).

Referência completa ao modelo de dados CNAB 240 e à lógica de processamento: ver documento `Requisitos_P11_PagamentoBoleto_JavaModerna.md`, seção 5 (Job P11-B) e seção 10 (Modelo de dados CNAB).

### 7.3 Configuração

```yaml
sol:
  banrisul:
    retorno-diretorio: ${BANRISUL_RETORNO_DIR:/mnt/banrisul/retorno}
    processado-diretorio: ${BANRISUL_PROCESSADO_DIR:/mnt/banrisul/processado}
```

### 7.4 Regras de negócio aplicáveis

- **RN-135:** Arquivo CNAB já processado não deve ser reprocessado. Após processamento, o arquivo é movido para diretório de processados com timestamp.
- **RN-136:** Falha no processamento de um arquivo não impede o processamento dos demais.

---

## 8. Regras de Negócio

| ID | Descrição | Job | Impacto |
|---|---|---|---|
| **RN-121** | Apenas licenciamentos com `situacao = ALVARA_VIGENTE` são elegíveis para P13-A | P13-A | Query filtragem |
| **RN-122** | Critério de vencimento: `APPCI.dataValidade <= LocalDate.now()` com `versaoVigente = true` | P13-A | Query filtragem |
| **RN-123** | Toda transição de situação registra `LicenciamentoSituacaoHistEntity` | P13-A | Auditoria obrigatória |
| **RN-124** | Marcação `versaoVigente = false` em APPCIs é realizada após a transição de situação | P13-A | Consistência de dados |
| **RN-125** | Notificação de 90d: `APPCI.dataValidade == hoje + 90`. Calculado a partir da última execução da rotina | P13-B | Controle de re-execução |
| **RN-126** | Notificação de 59d e 29d: mesma lógica de RN-125 com dias diferentes | P13-B | Controle de re-execução |
| **RN-127** | Licenciamentos já em fluxo de renovação (`AGUARDANDO_*_RENOVACAO`) não recebem notificação de vencimento | P13-B | Regra de negócio |
| **RN-128** | Destinatário com e-mail inválido/ausente: log de aviso, job não falha | P13-B/C/D | Resiliência |
| **RN-129** | `NOTIFICACAO_ALVARA_VENCIDO` é registrado uma única vez por licenciamento | P13-C | Idempotência |
| **RN-130** | Seleção de RT destinatário depende do número de APPCIs do licenciamento | P13-B/C | Regra de negócio |
| **RN-131** | Envio de e-mail é I/O externo — fora de transação de banco | P13-D | Arquitetura |
| **RN-132** | Máximo 3 tentativas de envio. Após, status `ABANDONADO` + alerta ao admin | P13-D | Resiliência |
| **RN-133** | Reprocessamento automático de notificações com `ERRO` no job seguinte | P13-D | Resiliência |
| **RN-134** | Corpo do e-mail renderizado por Thymeleaf; template determinado pelo `contexto` da notificação | P13-D | Template engine |
| **RN-135** | Arquivo CNAB processado é movido para diretório de processados | P13-E | Idempotência |
| **RN-136** | Falha em um arquivo CNAB não impede processamento dos demais | P13-E | Resiliência |
| **RN-137** | Jobs operam com fuso `America/Sao_Paulo` nos cron expressions | Todos | Configuração |
| **RN-138** | Em ambiente com múltiplas instâncias, ShedLock garante execução única por job | Todos | Cluster safety |
| **RN-139** | Cada licenciamento processado no P13-A executa em transação independente (`REQUIRES_NEW`) | P13-A | Isolamento de falhas |
| **RN-140** | A data de última execução da rotina é usada como baseline para os intervalos de notificação | P13-B/C | Controle de execução |

---

## 9. Modelo de Dados

### 9.1 Entidades JPA (stack moderna — PostgreSQL)

#### `LicenciamentoEntity` (tabela: `tb_licenciamento`)
Campo relevante: `situacao` (`SituacaoLicenciamento` enum)

#### `AppciEntity` (tabela: `tb_appci`)

```java
@Entity
@Table(name = "tb_appci")
public class AppciEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Column(name = "data_validade", nullable = false)
    private LocalDate dataValidade;

    @Column(name = "versao_vigente", nullable = false)
    private boolean versaoVigente;

    @Column(name = "data_inicio_vigencia")
    private LocalDate dataInicioVigencia;

    @Column(name = "numero_appci", length = 20)
    private String numeroAppci;

    // ... demais campos
}
```

**Nota:** Na stack atual (Oracle), o campo é `IND_VERSAO_VIGENTE CHAR(1)` com `'S'/'N'` via `SimNaoBooleanConverter`. Na stack moderna (PostgreSQL), usar `BOOLEAN` nativo.

#### `LicenciamentoNotificacaoEntity` (tabela: `tb_licenciamento_notificacao`)

```java
@Entity
@Table(name = "tb_licenciamento_notificacao")
public class LicenciamentoNotificacaoEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_marco")
    private LicenciamentoMarcoEntity marco;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_envio", nullable = false)
    private TipoEnvioNotificacao tipoEnvio;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false)
    private SituacaoEnvioNotificacao situacao;

    @Column(name = "destinatario", length = 200)
    private String destinatario;

    @Column(name = "assunto", length = 300)
    private String assunto;

    @Column(name = "contexto", length = 100)
    private String contexto; // nome do TipoMarco

    @Column(name = "uuid", length = 36, unique = true, nullable = false)
    private String uuid;

    @Column(name = "tentativas")
    private Integer tentativas = 0;

    @Column(name = "data_hora_criacao")
    private LocalDateTime dataHoraCriacao;

    @Column(name = "data_hora_envio")
    private LocalDateTime dataHoraEnvio;
}
```

#### `LicenciamentoSituacaoHistEntity` (tabela: `tb_licenciamento_situacao_hist`)

```java
@Entity
@Table(name = "tb_licenciamento_situacao_hist")
public class LicenciamentoSituacaoHistEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private LicenciamentoEntity licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_anterior")
    private SituacaoLicenciamento situacaoAnterior;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_atual", nullable = false)
    private SituacaoLicenciamento situacaoAtual;

    @Column(name = "data_hora_situacao_anterior")
    private LocalDateTime dataHoraSituacaoAnterior;

    @Column(name = "data_hora_situacao_atual", nullable = false)
    private LocalDateTime dataHoraSituacaoAtual;
}
```

#### `RotinaEntity` (tabela: `tb_rotina`)

```java
@Entity
@Table(name = "tb_rotina")
public class RotinaEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_rotina", nullable = false)
    private RotinaEnum tipoRotina;

    @Column(name = "data_inicio_execucao")
    private LocalDateTime dataInicioExecucao;

    @Column(name = "data_fim_execucao")
    private LocalDateTime dataFimExecucao;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao")
    private SituacaoRotina situacao; // EM_EXECUCAO, CONCLUIDA, ERRO

    @Column(name = "mensagem_erro", length = 2000)
    private String mensagemErro;
}
```

### 9.2 Script Flyway (PostgreSQL)

```sql
-- V13__jobs_automaticos.sql

-- Tabela de histórico de situação do licenciamento
CREATE TABLE tb_licenciamento_situacao_hist (
    id                        BIGSERIAL PRIMARY KEY,
    id_licenciamento          BIGINT NOT NULL REFERENCES tb_licenciamento(id),
    situacao_anterior         VARCHAR(50),
    situacao_atual            VARCHAR(50) NOT NULL,
    data_hora_situacao_ant    TIMESTAMP,
    data_hora_situacao_atual  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tabela de notificações
CREATE TABLE tb_licenciamento_notificacao (
    id                   BIGSERIAL PRIMARY KEY,
    id_licenciamento     BIGINT NOT NULL REFERENCES tb_licenciamento(id),
    id_marco             BIGINT REFERENCES tb_licenciamento_marco(id),
    tipo_envio           VARCHAR(10) NOT NULL DEFAULT 'EMAIL',
    situacao             VARCHAR(15) NOT NULL DEFAULT 'PENDENTE',
    destinatario         VARCHAR(200),
    assunto              VARCHAR(300),
    contexto             VARCHAR(100),
    uuid                 VARCHAR(36) NOT NULL UNIQUE,
    tentativas           INTEGER NOT NULL DEFAULT 0,
    data_hora_criacao    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_hora_envio      TIMESTAMP
);

-- Tabela de controle de rotinas
CREATE TABLE tb_rotina (
    id                      BIGSERIAL PRIMARY KEY,
    tipo_rotina             VARCHAR(60) NOT NULL,
    data_inicio_execucao    TIMESTAMP,
    data_fim_execucao       TIMESTAMP,
    situacao                VARCHAR(15),
    mensagem_erro           VARCHAR(2000)
);

-- Tabela ShedLock (controle de execução única em cluster)
CREATE TABLE shedlock (
    name       VARCHAR(64)  NOT NULL,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);

-- Índices de performance
CREATE INDEX idx_notificacao_situacao ON tb_licenciamento_notificacao(situacao);
CREATE INDEX idx_notificacao_licenciamento ON tb_licenciamento_notificacao(id_licenciamento);
CREATE INDEX idx_appci_data_validade ON tb_appci(data_validade) WHERE versao_vigente = true;
CREATE INDEX idx_licenciamento_situacao ON tb_licenciamento(situacao);
CREATE INDEX idx_rotina_tipo ON tb_rotina(tipo_rotina);
```

---

## 10. Máquina de Estados do Licenciamento (Renovação)

P13 opera na entrada do ciclo de renovação. A transição `ALVARA_VIGENTE → ALVARA_VENCIDO` é o gatilho para os demais processos de renovação (que são independentes do P13):

```
[ALVARA_VIGENTE]
     |
     |── P13-A (job diário): dataValidade APPCI <= hoje
     ↓
[ALVARA_VENCIDO]
     |
     |── Cidadão solicita renovação (processo separado — P15/futuro)
     ↓
[AGUARDANDO_ACEITE_RENOVACAO]
     |
     |── Aceites concluídos
     ↓
[AGUARDANDO_PAGAMENTO_RENOVACAO]
     |
     |── Pagamento confirmado (P11)
     ↓
[AGUARDANDO_DISTRIBUICAO_RENOV]
     |
     |── Distribuição para vistoriador (P07-renov)
     ↓
[EM_VISTORIA_RENOVACAO]
     |
     |── Vistoria aprovada → novo APPCI emitido → [ALVARA_VIGENTE] (novo ciclo)
     |── Vistoria reprovada → [RECURSO_EM_ANALISE_*_CIV_RENOV]
```

**Atividade de P13 por situação:**

| Situação | P13-A | P13-B/C | P13-D |
|---|---|---|---|
| ALVARA_VIGENTE | Verifica vencimento | Notifica 90/59/29d | Envia pendentes |
| ALVARA_VENCIDO | — (já processado) | Notifica vencidos (P13-C) | Envia pendentes |
| AGUARDANDO_ACEITE_RENOVACAO | — | — | Envia pendentes |
| Demais estados de renovação | — | — | Envia pendentes |

---

## 11. Marcos de Auditoria (TipoMarco)

| TipoMarco | Registrado em | Descrição |
|---|---|---|
| `NOTIFICACAO_SOLICITAR_RENOVACAO_90` | P13-B | Notificação enviada 90 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` | P13-B | Notificação enviada 59 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` | P13-B | Notificação enviada 29 dias antes do vencimento |
| `NOTIFICACAO_ALVARA_VENCIDO` | P13-C | Notificação enviada após o vencimento do alvará |

Os demais marcos do ciclo de renovação (`ACEITE_VISTORIA_RENOVACAO`, `LIBERACAO_RENOV_APPCI`, etc.) são registrados pelos processos que continuam o fluxo de renovação iniciado pelo P13.

---

## 12. Templates de E-mail

### 12.1 Mapeamento TipoMarco → Template Thymeleaf

| TipoMarco | Template Thymeleaf | Assunto |
|---|---|---|
| `NOTIFICACAO_SOLICITAR_RENOVACAO_90` | `emails/vencimento-alvara-90d.html` | `Seu alvará vence em 90 dias — SOL CBM-RS` |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` | `emails/vencimento-alvara-59d.html` | `Período de renovação próximo — SOL CBM-RS` |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` | `emails/vencimento-alvara-29d.html` | `Período de renovação próximo — SOL CBM-RS` |
| `NOTIFICACAO_ALVARA_VENCIDO` | `emails/alvara-vencido.html` | `Seu alvará venceu — SOL CBM-RS` |

### 12.2 Estrutura dos templates Thymeleaf

```html
<!-- src/main/resources/templates/emails/vencimento-alvara-90d.html -->
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org" lang="pt-BR">
<head><meta charset="UTF-8"/><title>Vencimento do Alvará</title></head>
<body>
<p>Prezado(a),</p>
<p>O alvará do licenciamento <strong th:text="${licenciamento.numeroPpci}"></strong>
   (<span th:text="${licenciamento.enderecoFormatado}"></span>)
   vence em <strong th:text="${#temporals.format(dataValidade, 'dd/MM/yyyy')}"></strong>.</p>
<p>Acesse o <a href="https://sol.cbm.rs.gov.br">Sistema SOL</a> para iniciar o processo de renovação.</p>
<p>Corpo de Bombeiros Militar do Rio Grande do Sul</p>
</body>
</html>
```

### 12.3 Variáveis de contexto disponíveis nos templates

| Variável | Tipo | Descrição |
|---|---|---|
| `licenciamento` | `LicenciamentoEntity` | Objeto completo do licenciamento |
| `dataValidade` | `LocalDate` | Data de validade do APPCI vigente |
| `diasRestantes` | `Integer` | Dias até o vencimento (90, 59, 29 ou 0) |
| `urlPortal` | `String` | URL do portal SOL (configurável por ambiente) |

---

## 13. Rastreabilidade de Execução (Rotina)

### 13.1 Objetivo

Cada execução da rotina diária é registrada em `tb_rotina` com data de início, data de fim e status. Isso permite:
1. Determinar o baseline temporal para as queries de notificação (evitar renotificação).
2. Auditoria de execuções — histórico de quando cada job rodou.
3. Diagnóstico de falhas — registro de erros com stack trace.

### 13.2 RotinaEnum

```java
public enum RotinaEnum {
    GERAR_NOTIFICACAO_ALVARA_VENCIDO,
    VERIFICAR_PAGAMENTO_BANRISUL,
    FATURAMENTO_MENSAL
}
```

### 13.3 Serviço de rastreabilidade

```java
@Service
@RequiredArgsConstructor
public class RotinaService {

    private final RotinaRepository rotinaRepository;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public RotinaEntity iniciarRotina(RotinaEnum tipo) {
        RotinaEntity rotina = RotinaEntity.builder()
            .tipoRotina(tipo)
            .dataInicioExecucao(LocalDateTime.now())
            .situacao(SituacaoRotina.EM_EXECUCAO)
            .build();
        return rotinaRepository.save(rotina);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void finalizarRotina(RotinaEntity rotina) {
        rotina.setSituacao(SituacaoRotina.CONCLUIDA);
        rotina.setDataFimExecucao(LocalDateTime.now());
        rotinaRepository.save(rotina);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void registrarErroRotina(RotinaEntity rotina, Exception e) {
        rotina.setSituacao(SituacaoRotina.ERRO);
        rotina.setDataFimExecucao(LocalDateTime.now());
        rotina.setMensagemErro(e.getMessage() != null
            ? e.getMessage().substring(0, Math.min(e.getMessage().length(), 2000))
            : "Erro desconhecido");
        rotinaRepository.save(rotina);
    }

    public Optional<LocalDate> consultarUltimaExecucao(RotinaEnum tipo) {
        return rotinaRepository
            .findTopByTipoRotinaAndSituacaoOrderByDataFimExecucaoDesc(
                tipo, SituacaoRotina.CONCLUIDA)
            .map(r -> r.getDataFimExecucao().toLocalDate());
    }
}
```

---

## 14. Segurança e Autorização

### 14.1 Perfil de execução

P13 é um processo **puramente de sistema**, sem interação de usuário. Não há autenticação OAuth2/OIDC envolvida. Os jobs executam com identidade de serviço da aplicação.

### 14.2 Endpoint de acionamento manual (opcional)

Para permitir acionamento manual em situações de emergência (ex.: falha da rotina agendada), pode-se expor um endpoint administrativo:

```java
@RestController
@RequestMapping("/admin/jobs")
@PreAuthorize("hasRole('ROLE_ADMIN_SISTEMA')")
public class JobAdminController {

    private final AlvaraScheduler alvaraScheduler;

    @PostMapping("/rotina-diaria")
    public ResponseEntity<String> executarRotinaDiaria() {
        alvaraScheduler.rotinaDiariaAlvaras();
        return ResponseEntity.ok("Rotina diária executada com sucesso");
    }

    @PostMapping("/enviar-notificacoes")
    public ResponseEntity<String> enviarNotificacoes() {
        alvaraScheduler.enviarNotificacoesPendentes();
        return ResponseEntity.ok("Envio de notificações executado");
    }
}
```

**Proteção:** `ROLE_ADMIN_SISTEMA` — perfil restrito a administradores técnicos do sistema, diferente de `ROLE_ADMIN_CBM` (administradores de negócio do CBM-RS).

### 14.3 Proteção de dados

- Endereços de e-mail dos destinatários são dados pessoais — devem ser tratados conforme LGPD.
- Logs de execução não devem registrar e-mails completos — usar máscara (ex.: `jo***@email.com`).
- Arquivos CNAB 240 contêm dados financeiros sensíveis — diretório de processamento com permissão restrita ao usuário do serviço.

---

## 15. Classes e Componentes Java Moderna

### 15.1 Estrutura de pacotes

```
com.cbmrs.sol
├── scheduler/
│   ├── AlvaraScheduler.java               ← @Component com @Scheduled
│   └── SchedulerConfig.java               ← @Configuration @EnableScheduling
├── jobs/
│   ├── alvara/
│   │   ├── AlvaraVencidoService.java      ← P13-A: transição ALVARA_VIGENTE → ALVARA_VENCIDO
│   │   └── AlvaraVencidoRepository.java   ← queries Hibernate/JPA
│   ├── notificacao/
│   │   ├── NotificacaoVencimentoService.java  ← P13-B/C: criação de notificações
│   │   ├── NotificacaoEmailService.java       ← P13-D: envio de e-mails
│   │   └── LicenciamentoNotificacaoRepository.java
│   └── banrisul/
│       └── BanrisulRetornoService.java    ← P13-E: processamento CNAB 240
├── domain/
│   ├── AppciEntity.java
│   ├── LicenciamentoNotificacaoEntity.java
│   ├── LicenciamentoSituacaoHistEntity.java
│   ├── RotinaEntity.java
│   └── enums/
│       ├── SituacaoLicenciamento.java
│       ├── TipoMarco.java
│       ├── TipoEnvioNotificacao.java
│       ├── SituacaoEnvioNotificacao.java
│       ├── RotinaEnum.java
│       └── SituacaoRotina.java
└── infrastructure/
    └── RotinaService.java                 ← rastreabilidade de execução
```

### 15.2 Dependências Maven (pom.xml)

```xml
<!-- Spring Boot Starter Web -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>

<!-- Spring Data JPA + Hibernate 6 -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>

<!-- PostgreSQL Driver -->
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>

<!-- Spring Mail -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-mail</artifactId>
</dependency>

<!-- Thymeleaf (templates de e-mail) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-thymeleaf</artifactId>
</dependency>

<!-- Thymeleaf Extras — e-mails HTML -->
<dependency>
    <groupId>org.thymeleaf.extras</groupId>
    <artifactId>thymeleaf-extras-java8time</artifactId>
</dependency>

<!-- ShedLock — execução única em cluster -->
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-spring</artifactId>
    <version>5.12.0</version>
</dependency>
<dependency>
    <groupId>net.javacrumbs.shedlock</groupId>
    <artifactId>shedlock-provider-jdbc-template</artifactId>
    <version>5.12.0</version>
</dependency>

<!-- Flyway — migrações de banco -->
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
</dependency>

<!-- Lombok -->
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <optional>true</optional>
</dependency>

<!-- Spring Security (proteção do endpoint admin) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>

<!-- Spring Boot Actuator (monitoramento de jobs) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

### 15.3 Comparativo Stack Atual × Stack Moderna

| Componente | Stack Atual (Java EE) | Stack Moderna (Spring Boot 3) |
|---|---|---|
| Agendador | `@Singleton @Startup` + `@Schedule(hour=..., minute=...)` | `@Component` + `@Scheduled(cron="...")` |
| Fuso horário | Depende da JVM/servidor (implícito) | `zone = "America/Sao_Paulo"` explícito no `@Scheduled` |
| Execução única em cluster | Nenhuma (risco de dupla execução) | **ShedLock** com JDBC backend |
| Transação por registro | `@TransactionAttribute(REQUIRES_NEW)` | `@Transactional(propagation = REQUIRES_NEW)` |
| Persistência | Hibernate Criteria API | Spring Data JPA (JPQL + `@Query`) |
| Banco de dados | Oracle + `SimNaoBooleanConverter` para booleanos | PostgreSQL + `BOOLEAN` nativo |
| Envio de e-mail | JavaMail direto | **Spring Mail** (`JavaMailSender`) |
| Templates de e-mail | String concatenation / MessageProvider i18n | **Thymeleaf** templates HTML |
| Controle de rotina | `RotinaED` + `RotinaRN` (EJB Stateless) | `RotinaEntity` + `RotinaService` (Spring @Service) |
| Notificações na fila | `LicenciamentoNotificacaoED` | `LicenciamentoNotificacaoEntity` (mesma semântica) |
| Retry de e-mail | Manual (campo `tentativas`, reprocessado no job seguinte) | **Idem** — mesma lógica |
| CNAB 240 | `PagamentoBoletoRN` (EJB) | `BanrisulRetornoService` (Spring @Service) |
| Monitoramento | Logs JBoss | Spring Boot **Actuator** (`/actuator/health`, métricas) |
| Servlet alternativo | `AlvaraBatchServlet` (acionamento via Workload) | Endpoint REST `/admin/jobs` com `@PreAuthorize` |

### 15.4 Casos de teste representativos

| TC | Descrição | Resultado esperado |
|---|---|---|
| TC-P13-01 | APPCI com `dataValidade = ontem`, licenciamento `ALVARA_VIGENTE` | Situação → `ALVARA_VENCIDO`; histórico gravado; APPCI `versaoVigente = false` |
| TC-P13-02 | APPCI com `dataValidade = hoje + 90`, licenciamento `ALVARA_VIGENTE` | Notificação criada com marco `NOTIFICACAO_SOLICITAR_RENOVACAO_90` |
| TC-P13-03 | APPCI com `dataValidade = hoje + 59` | Notificação criada com marco `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` |
| TC-P13-04 | APPCI com `dataValidade = hoje + 29` | Notificação criada com marco `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` |
| TC-P13-05 | Alvará venceu ontem, licenciamento `ALVARA_VENCIDO` | Notificação criada com marco `NOTIFICACAO_ALVARA_VENCIDO` |
| TC-P13-06 | Licenciamento em `AGUARDANDO_ACEITE_RENOVACAO` com APPCI a vencer em 30d | **Nenhuma notificação** (RN-127) |
| TC-P13-07 | Notificação com `situacao = PENDENTE` | E-mail enviado; `situacao → ENVIADO`; `dataHoraEnvio` gravada |
| TC-P13-08 | Notificação com `situacao = PENDENTE`, SMTP falhando | `situacao → ERRO`; `tentativas = 1`; reprocessado no próximo ciclo |
| TC-P13-09 | Notificação com `situacao = ERRO`, `tentativas = 2`, SMTP falhando | `situacao → ABANDONADO`; `tentativas = 3`; não reprocessado |
| TC-P13-10 | Rotina executa duas vezes no mesmo dia (re-execução) | Segunda execução não gera duplicatas — controle via `tb_rotina.dataFimExecucao` |
| TC-P13-11 | Job executando em duas instâncias simultaneamente (cluster) | ShedLock garante que apenas uma instância processa |
| TC-P13-12 | Licenciamento com 1 APPCI: RT tipo PROJETO_EXECUCAO | RT notificado |
| TC-P13-13 | Licenciamento com múltiplos APPCIs: RT tipo RENOVACAO_APPCI | RT notificado; RT com outro tipo não notificado |
| TC-P13-14 | Destinatário com e-mail nulo | Log de aviso emitido; job continua sem falha (RN-128) |
| TC-P13-15 | Arquivo CNAB 240 já processado presente no diretório | Ignorado; não reprocessado (RN-135) |

---

## 16. Complementos Normativos (RT de Implantação SOL-CBMRS 4ª Ed./2022)

Esta seção acrescenta novos jobs automáticos derivados da leitura direta da RT de Implantação SOL-CBMRS 4ª Edição/2022. Os jobs P13-A a P13-E e as RNs RN-121 a RN-140 não são alterados.

---

### RN-P13-N1 — Job de Suspensão por CIA sem Movimentação (6 meses)

**Base normativa:** item 6.3.7.2.3 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

**Job P13-F — Suspensão por Inatividade após CIA**

Job diário que verifica processos em estado `AGUARD_CORRECAO_CIA` sem qualquer movimentação por **6 (seis) meses** a partir da data de emissão da CIA.

**Agendamento:** diário às 02:00h (horário de Brasília — fora do horário de pico do sistema).

```java
@Scheduled(cron = "0 0 2 * * *", zone = "America/Sao_Paulo")
@SchedulerLock(name = "suspensaoPorCiaSemMovimentacao",
               lockAtMostFor = "PT2H", lockAtLeastFor = "PT30M")
public void suspenderPorCiaSemMovimentacao() { ... }
```

**Critério de elegibilidade:**

```sql
SELECT l.* FROM tb_licenciamento l
WHERE l.situacao = 'AGUARD_CORRECAO_CIA'
  AND NOT EXISTS (
      SELECT 1 FROM tb_licenciamento_marco m
      WHERE m.id_licenciamento = l.id
        AND m.data_hora >= (CURRENT_TIMESTAMP - INTERVAL '6 months')
  )
```

**Ações ao detectar processo elegível:**

1. Transitar o licenciamento para o estado `SUSPENSO`.
2. Registrar marco `SUSPENSAO_AUTOMATICA` com data/hora e motivo `"Inatividade superior a 6 meses após emissão de CIA"`.
3. Enviar notificação (e-mail) ao proprietário, RU e RT com o texto: "Seu processo [NÚMERO] foi suspenso por inatividade. Acesse o sistema SOL para reativá-lo."
4. Registrar execução na tabela `tb_rotina` com `RotinaEnum.SUSPENSAO_POR_CIA_SEM_MOVIMENTACAO`.

**Regras:**

- Apenas processos em `AGUARD_CORRECAO_CIA` são elegíveis. Processos em qualquer outra situação são ignorados.
- A contagem de 6 meses é baseada na data do último marco registrado para o licenciamento (campo `data_hora` da tabela `tb_licenciamento_marco`).
- Falha no processamento de um licenciamento não deve interromper o job — registrar erro individual e continuar.

---

### RN-P13-N2 — Job de Suspensão por CA/CIV sem Movimentação (2 anos)

**Base normativa:** item 6.4.8.2 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

**Job P13-G — Suspensão por Inatividade após CA ou CIV**

Job diário que verifica processos em estados `AGUARD_VISTORIA` ou `AGUARD_CORRECAO_CIV` sem movimentação por **2 (dois) anos** a partir da emissão do CA ou CIV.

**Agendamento:** diário às 02:15h (horário de Brasília), após o Job P13-F.

```java
@Scheduled(cron = "0 15 2 * * *", zone = "America/Sao_Paulo")
@SchedulerLock(name = "suspensaoPorCivSemMovimentacao",
               lockAtMostFor = "PT2H", lockAtLeastFor = "PT30M")
public void suspenderPorCivSemMovimentacao() { ... }
```

**Critério de elegibilidade:**

```sql
SELECT l.* FROM tb_licenciamento l
WHERE l.situacao IN ('AGUARD_VISTORIA', 'AGUARD_CORRECAO_CIV')
  AND NOT EXISTS (
      SELECT 1 FROM tb_licenciamento_marco m
      WHERE m.id_licenciamento = l.id
        AND m.data_hora >= (CURRENT_TIMESTAMP - INTERVAL '2 years')
  )
```

**Ações ao detectar processo elegível:** idênticas à RN-P13-N1 (transição para `SUSPENSO`, marco `SUSPENSAO_AUTOMATICA`, notificação e rastreabilidade de rotina com `RotinaEnum.SUSPENSAO_POR_CIV_SEM_MOVIMENTACAO`).

---

### RN-P13-N3 — Job de Alerta de Renovação do APPCI (60 dias antes do vencimento)

**Base normativa:** item 8.1.2c da RT de Implantação SOL-CBMRS 4ª Ed./2022, que exige renovação com antecedência mínima de 2 meses.

**Job P13-H — Alerta de Renovação 60 dias**

Job diário que verifica APPCIs com vencimento em exatamente **60 dias corridos** a partir da data de execução.

**Agendamento:** integrado à rotina diária (`rotinaDiariaAlvaras()`), executado após os marcos de 90/59/29 dias (P13-B).

**Ações ao detectar APPCI elegível:**

1. Enviar notificação (e-mail) ao proprietário e ao RT com o texto:

   > "Seu APPCI [NÚMERO], referente ao licenciamento [NÚMERO], vence em [DD/MM/AAAA]. Solicite a renovação até [DD/MM/AAAA - 60 dias]. Solicitações realizadas com menos de 2 meses de antecedência podem inviabilizar a conclusão do processo de renovação antes do vencimento."

2. Registrar marco `ALERTA_RENOVACAO_60_DIAS` no licenciamento.
3. Exibir badge "Vence em X dias — Renovar agora" no dashboard do cidadão no portal SOL.

**Enum a acrescentar:**

```java
// TipoMarco — acrescentar:
ALERTA_RENOVACAO_60_DIAS,
ALERTA_RENOVACAO_30_DIAS,
SUSPENSAO_AUTOMATICA,
PRAZO_RECURSO_ENCERRADO
```

**Regras:**

- Apenas APPCIs com `versaoVigente = true` e licenciamento em `ALVARA_VIGENTE` são considerados.
- Não deve ser gerado alerta se já existir processo de renovação em andamento para o licenciamento (situação diferente de `ALVARA_VIGENTE`).
- O controle de reprocessamento segue o mesmo padrão dos jobs P13-B/C: verificação via `tb_rotina` para evitar alertas duplicados no mesmo dia.

---

### RN-P13-N4 — Job de Alerta de Renovação do APPCI (30 dias antes do vencimento)

**Job P13-I — Alerta de Renovação 30 dias**

Job diário complementar ao P13-H, com alerta de urgência **30 dias corridos** antes do vencimento do APPCI.

**Agendamento:** integrado à rotina diária, executado após o P13-H.

**Ações ao detectar APPCI elegível:**

1. Enviar notificação (e-mail) ao proprietário e ao RT com urgência reforçada.
2. Registrar marco `ALERTA_RENOVACAO_30_DIAS` no licenciamento.
3. Se não houver processo de renovação em andamento (licenciamento ainda em `ALVARA_VIGENTE`), escalonar o alerta para o **Chefe SSeg do BBM** responsável pela área, com a informação de que o prazo mínimo normativo (2 meses) já foi ultrapassado sem início de renovação.
4. O escalonamento consiste no envio de e-mail ao e-mail do grupo `CHEFE_SSEG_BBM` do BBM competente, com lista dos licenciamentos em risco de vencimento sem renovação iniciada.

**Regras:** as mesmas da RN-P13-N3, com o acréscimo do escalonamento ao Chefe SSeg.

---

### RN-P13-N5 — Job de Bloqueio de Recurso Intempestivo

**Base normativa:** item 12.2 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

**Job P13-J — Bloqueio de Prazo de Recurso**

Job diário (ou event-driven) que verifica processos com CIA, CIV ou decisão administrativa cujo prazo de recurso em dias úteis foi atingido sem interposição de recurso.

**Agendamento:** diário às 02:30h (horário de Brasília).

```java
@Scheduled(cron = "0 30 2 * * *", zone = "America/Sao_Paulo")
@SchedulerLock(name = "bloqueioPrazoRecurso",
               lockAtMostFor = "PT1H", lockAtLeastFor = "PT15M")
public void bloquearRecursoIntempestivo() { ... }
```

**Critério de elegibilidade:**

- Licenciamentos em situação que indica CIA ou CIV emitida (ex.: `AGUARD_CORRECAO_CIA`, `AGUARD_CORRECAO_CIV`) sem `RecursoED` ativo associado.
- Data de emissão da CIA ou CIV + 30 dias úteis (calculados via tabela `sol.feriado`) < data atual.
- Campo `recursoBloqueado` do `LicenciamentoED` ainda é `false`.

**Ações ao detectar processo elegível:**

1. Setar `recursoBloqueado = true` no `LicenciamentoED`.
2. Registrar marco `PRAZO_RECURSO_ENCERRADO` no licenciamento, com data/hora e motivo `"Prazo de 30 dias úteis encerrado sem interposição de recurso"`.
3. Registrar execução em `tb_rotina` com `RotinaEnum.BLOQUEIO_PRAZO_RECURSO`.

**Regras:**

- O job não cancela recursos já criados — apenas impede a criação de novos recursos para a CIA/CIV em questão.
- O cálculo de dias úteis deve usar a tabela `sol.feriado` (ver RN-P13-N6).

---

### RN-P13-N6 — Job de Manutenção da Tabela de Feriados

**Job P13-K — Manutenção de Feriados**

Job anual, executado em novembro de cada ano, que verifica se os feriados do próximo ano estão cadastrados na tabela `sol.feriado`. Se os feriados do ano seguinte não estiverem cadastrados, o job gera alerta para o administrador do sistema.

**Agendamento:** anual, no dia 1.º de novembro de cada ano, às 09:00h.

```java
@Scheduled(cron = "0 0 9 1 11 *", zone = "America/Sao_Paulo")
@SchedulerLock(name = "manutencaoFeriados",
               lockAtMostFor = "PT30M", lockAtLeastFor = "PT5M")
public void verificarFeriadosAnoSeguinte() { ... }
```

**Estrutura da tabela `sol.feriado` (PostgreSQL):**

```sql
CREATE TABLE sol.feriado (
    id           BIGSERIAL   PRIMARY KEY,
    data_feriado DATE        NOT NULL,
    descricao    VARCHAR(100) NOT NULL,
    tipo         VARCHAR(20) NOT NULL,  -- FEDERAL, ESTADUAL_RS, MUNICIPAL
    municipio    VARCHAR(100),          -- preenchido apenas para feriados municipais
    ativo        BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX idx_feriado_data_municipio
    ON sol.feriado(data_feriado, COALESCE(municipio, ''));
```

**Ações do job:**

1. Verificar se existem registros em `sol.feriado` com `data_feriado` no intervalo `[01/01/{ano+1}, 31/12/{ano+1}]` e `tipo IN ('FEDERAL', 'ESTADUAL_RS')`.
2. Se o count for zero, enviar alerta por e-mail ao grupo `ADMIN_SISTEMA` com o texto:

   > "Atenção: os feriados federais e estaduais do RS para [ano+1] não foram cadastrados na tabela sol.feriado. Cadastre-os para garantir o correto cálculo de prazos em dias úteis (recursos, suspensões e bloqueios). Os feriados municipais relevantes também devem ser verificados e cadastrados manualmente."

3. Registrar execução em `tb_rotina` com `RotinaEnum.MANUTENCAO_FERIADOS`.

**Regras de manutenção:**

- Os feriados **federais** e **estaduais do RS** são mantidos por script automatizado executado pela equipe de infraestrutura (script Flyway ou equivalente) no início de cada ano.
- Os feriados **municipais** relevantes (municípios com grande volume de processos no SOL) devem ser cadastrados manualmente pelo administrador do sistema.
- O campo `DiasUteisService.calcularDiasUteis(dataInicio, qtdDias)` deve consultar `sol.feriado` com `tipo IN ('FEDERAL', 'ESTADUAL_RS')` e `ativo = true` para o cálculo dos prazos de recurso (RN-P10-N3 e RN-P13-N5).

**Enum a acrescentar:**

```java
// RotinaEnum — acrescentar:
SUSPENSAO_POR_CIA_SEM_MOVIMENTACAO,
SUSPENSAO_POR_CIV_SEM_MOVIMENTACAO,
BLOQUEIO_PRAZO_RECURSO,
MANUTENCAO_FERIADOS
```

---



---

## 17. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (ID4401, Demanda 18) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (itens 6.3.7.2.3, 6.4.8.2, 6.5.3, 8.1.2c).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P13.
>
> ⚠️ **IMPACTO ALTO — Jobs obrigatórios não existentes no sistema atual:** Os jobs P13-N1 e P13-N2 implementam suspensão automática exigida pela norma e **não existem no sistema atual**.

---

### RN-P13-N1 — Job: Suspensão Automática por Inatividade após CIA (6 Meses) 🔴 P13-M1

**Prioridade:** CRÍTICA — job obrigatório por norma  
**Origem:** Norma / Correção 5 — RT de Implantação SOL-CBMRS item 6.3.7.2.3

**Descrição:** PPCIs em estado `AGUARDANDO_CORRECAO_CIA` sem nenhuma movimentação por **6 meses** devem ser automaticamente suspensos.

**Novo job — `LicenciamentoSuspensaoBatchRN.suspenderPorInatividadeAposCia()`:**

```java
@Component
public class LicenciamentoSuspensaoScheduler {

    // Executa toda segunda-feira às 02h
    @Scheduled(cron = "0 0 2 * * MON")
    public void suspenderPorInatividadeAposCia() {
        log.info("Iniciando job de suspensão por inatividade após CIA");
        
        LocalDateTime limiteInatividade = LocalDateTime.now().minusMonths(6);
        
        List<Licenciamento> candidatos = licenciamentoRepository
            .findParaSuspensaoAposCia(limiteInatividade);
        
        int suspensos = 0;
        for (Licenciamento lic : candidatos) {
            try {
                lic.setStatus(StatusLicenciamento.SUSPENSO);
                lic.setDtSuspensao(LocalDateTime.now());
                lic.setMotivoSuspensao("Inatividade superior a 6 meses após emissão de CIA");
                licenciamentoRepository.save(lic);
                
                marcoService.registrar(lic, TipoMarco.SUSPENSAO_AUTOMATICA_CIA,
                    "Suspenso automaticamente por inatividade de 6 meses após CIA " +
                    "(RT de Implantação SOL item 6.3.7.2.3)");
                
                notificacaoService.notificarSuspensaoAposCia(lic);
                suspensos++;
            } catch (Exception e) {
                log.error("Erro ao suspender licenciamento {}: {}", lic.getId(), e.getMessage());
            }
        }
        log.info("Job suspensão CIA concluído. {} licenciamentos suspensos.", suspensos);
    }
}
```

**Query para identificar candidatos:**
```sql
SELECT l.*
FROM cbm_licenciamento l
JOIN cbm_cia c ON c.id_licenciamento = l.id
WHERE l.tp_status = 'AGUARDANDO_CORRECAO_CIA'
  AND NOT EXISTS (
      SELECT 1 FROM cbm_marco_processo m
      WHERE m.id_licenciamento = l.id
        AND m.dt_registro > :limiteInatividade
  )
  AND c.dt_emissao <= :limiteInatividade;
```

**Novo `TipoMarco`:**
```java
SUSPENSAO_AUTOMATICA_CIA("Suspensão automática — inatividade após CIA (6 meses)"),
```

**Notificação:** E-mail para RT, RU e Proprietário informando a suspensão e orientando sobre como reativar.

**Critérios de Aceitação:**
- [ ] CA-P13-N1a: Job executado toda segunda-feira às 02h
- [ ] CA-P13-N1b: PPCIs em `AGUARDANDO_CORRECAO_CIA` sem movimentação há 6 meses são suspensos
- [ ] CA-P13-N1c: Marco `SUSPENSAO_AUTOMATICA_CIA` registrado com referência à norma
- [ ] CA-P13-N1d: RT, RU e Proprietário notificados por e-mail
- [ ] CA-P13-N1e: PPCIs com movimentação recente (< 6 meses) não são afetados

---

### RN-P13-N2 — Job: Suspensão Automática por Inatividade após CA ou CIV (2 Anos) 🔴 P13-M2

**Prioridade:** CRÍTICA — job obrigatório por norma  
**Origem:** Norma / Correção 5 — RT de Implantação SOL-CBMRS item 6.4.8.2

**Descrição:** PPCIs em estado `AGUARDANDO_VISTORIA` ou `AGUARDANDO_CORRECAO_CIV` sem movimentação por **2 anos** após a emissão de CA ou CIV devem ser automaticamente suspensos.

**Novo job — `LicenciamentoSuspensaoBatchRN.suspenderPorInatividadeAposCaOuCiv()`:**

```java
// Executa toda segunda-feira às 03h (1h depois do job CIA)
@Scheduled(cron = "0 0 3 * * MON")
public void suspenderPorInatividadeAposCaOuCiv() {
    log.info("Iniciando job de suspensão por inatividade após CA/CIV");
    
    LocalDateTime limite = LocalDateTime.now().minusYears(2);
    
    List<Licenciamento> candidatos = licenciamentoRepository
        .findParaSuspensaoAposCaOuCiv(limite);
    
    for (Licenciamento lic : candidatos) {
        lic.setStatus(StatusLicenciamento.SUSPENSO);
        marcoService.registrar(lic, TipoMarco.SUSPENSAO_AUTOMATICA_CA_CIV,
            "Suspenso automaticamente por inatividade de 2 anos após CA/CIV " +
            "(RT de Implantação SOL item 6.4.8.2)");
        notificacaoService.notificarSuspensaoAposCaOuCiv(lic);
    }
}
```

**Query:**
```sql
SELECT l.*
FROM cbm_licenciamento l
WHERE l.tp_status IN ('AGUARDANDO_VISTORIA', 'AGUARDANDO_CORRECAO_CIV')
  AND NOT EXISTS (
      SELECT 1 FROM cbm_marco_processo m
      WHERE m.id_licenciamento = l.id
        AND m.dt_registro > :limite
  );
```

**Novo `TipoMarco`:**
```java
SUSPENSAO_AUTOMATICA_CA_CIV("Suspensão automática — inatividade após CA/CIV (2 anos)"),
```

**Critérios de Aceitação:**
- [ ] CA-P13-N2a: Job executado toda segunda-feira às 03h
- [ ] CA-P13-N2b: PPCIs em `AGUARDANDO_VISTORIA` ou `AGUARDANDO_CORRECAO_CIV` sem movimentação há 2 anos são suspensos
- [ ] CA-P13-N2c: Marco `SUSPENSAO_AUTOMATICA_CA_CIV` registrado com referência à norma
- [ ] CA-P13-N2d: RT, RU e Proprietário notificados por e-mail
- [ ] CA-P13-N2e: Job CA/CIV e job CIA NÃO executam no mesmo horário (evitar sobrecarga)

---

### RN-P13-N3 — Atualizar Data Limite do APPCI Parcial para 27/12/2027 🟠 P13-M3

**Prioridade:** Alta  
**Origem:** ID4401 — Sprint 04 Hammer

**Descrição:** O job que gera APPCIs parciais deve usar a data limite **27/12/2027** (anteriormente 27/12/2026). Este parâmetro deve ser **configurável**, não hard-coded.

**Mudança:**

```sql
-- Tabela de configuração do sistema
UPDATE sol.configuracao_sistema
   SET vl_config = '2027-12-27'
 WHERE nm_config = 'dt_limite_appci_parcial';

-- Se não existir, criar:
INSERT INTO sol.configuracao_sistema(nm_config, vl_config, ds_descricao)
VALUES ('dt_limite_appci_parcial', '2027-12-27', 
        'Data limite para validade de APPCIs parciais emitidos pelo sistema');
```

**Uso no cálculo:**
```java
// AppciParcialService.java
public LocalDate calcularValidadeAppciParcial(LocalDate dtEmissao) {
    LocalDate dtLimiteSistema = configuracaoService
        .getDate("dt_limite_appci_parcial"); // lê do banco
    return dtEmissao.plusYears(2).isBefore(dtLimiteSistema)
        ? dtEmissao.plusYears(2)
        : dtLimiteSistema;
}
```

**Critérios de Aceitação:**
- [ ] CA-P13-N3a: APPCI parcial emitido usa `MIN(emissão + 2 anos, 27/12/2027)` como validade
- [ ] CA-P13-N3b: Data limite é lida da tabela `sol.configuracao_sistema` (não hard-coded)
- [ ] CA-P13-N3c: Mudança da data não requer recompilação — apenas UPDATE no banco

---

### RN-P13-N4 — Cálculo Automático de Validade do APPCI por Tipo de Ocupação e Grau de Risco 🔴 P13-M4

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C3 — RT de Implantação SOL-CBMRS item 6.5.3

**Descrição:** A validade do APPCI deve ser calculada automaticamente com base no **tipo de ocupação** e no **grau de risco** da edificação:

| Condição | Validade |
|----------|---------|
| Grupo F (reunião de público) + risco médio, alto ou elevado | **2 anos** |
| Locais de risco elevado (qualquer grupo) | **2 anos** |
| Todos os demais casos | **5 anos** |

**Componente de cálculo:**

```java
@Service
public class AppciValidadeCalculadoraRN {

    public int calcularAnosValidade(Licenciamento lic) {
        GrupoOcupacao grupo = lic.getTpGrupoOcupacao();
        ClasseRisco classeRisco = lic.getClasseRiscoMaxima();
        
        // Grupo F com risco médio/alto/elevado → 2 anos
        if (GrupoOcupacao.F.equals(grupo) &&
            List.of(ClasseRisco.MEDIO, ClasseRisco.ALTO, ClasseRisco.ELEVADO).contains(classeRisco)) {
            return 2;
        }
        
        // Qualquer risco elevado → 2 anos
        if (ClasseRisco.ELEVADO.equals(classeRisco)) {
            return 2;
        }
        
        // Demais casos → 5 anos
        return 5;
    }
    
    public LocalDate calcularDtValidade(Licenciamento lic, LocalDate dtEmissao) {
        int anos = calcularAnosValidade(lic);
        return dtEmissao.plusYears(anos);
    }
}
```

**Integração com job de vencimento:**
```java
// Job existente de marcação de APPCIs vencidos deve usar dt_validade calculada
// e NÃO mais uma validade fixa de X anos para todos
```

**Critérios de Aceitação:**
- [ ] CA-P13-N4a: APPCI emitido para Grupo F + risco médio/alto tem validade de 2 anos
- [ ] CA-P13-N4b: APPCI emitido para risco elevado tem validade de 2 anos
- [ ] CA-P13-N4c: APPCI emitido para demais casos tem validade de 5 anos
- [ ] CA-P13-N4d: Job de vencimento usa a `dt_validade` calculada por ocupação/risco

---

### RN-P13-N5 — Mascaramento de CPF na Consulta Pública (LGPD) 🟡 P13-M5

**Prioridade:** Média  
**Origem:** Demanda 18 — Sprint 02 Hammer

**Descrição:** O endpoint que alimenta a consulta pública de autenticidade de documentos deve retornar o CPF **mascarado** para conformidade com a LGPD.

**Formato do mascaramento:**
- CPF `123.456.789-00` → retornar como `***.456.789-**`

**Implementação:**
```java
// CpfMascarador.java — utilitário
public static String mascarar(String cpf) {
    if (cpf == null || cpf.length() < 11) return "***.***.***-**";
    // Remove pontuação se houver
    String digits = cpf.replaceAll("[^0-9]", "");
    return String.format("***.%s.%s-**", digits.substring(3, 6), digits.substring(6, 9));
}
```

**Aplicação no endpoint público:**
```java
@GetMapping("/publico/autenticidade/{nrAutenticacao}")
public ResponseEntity<AutenticidadePublicaDTO> verificarAutenticidade(@PathVariable String nrAutenticacao) {
    DocumentoAutenticado doc = documentoService.findByNrAutenticacao(nrAutenticacao);
    return ResponseEntity.ok(AutenticidadePublicaDTO.builder()
        .nrProtocolo(doc.getNrProtocolo())
        .nmProprietario(doc.getNmProprietario())
        .cpfProprietario(CpfMascarador.mascarar(doc.getCpfProprietario())) // mascarado
        .dtEmissao(doc.getDtEmissao())
        .dtValidade(doc.getDtValidade())
        .build());
}
```

**Critérios de Aceitação:**
- [ ] CA-P13-N5a: Endpoint de consulta pública retorna CPF no formato `***.XXX.XXX-**`
- [ ] CA-P13-N5b: CPF completo NÃO aparece em nenhuma resposta de endpoint público
- [ ] CA-P13-N5c: Endpoints internos (com autenticação) mantêm CPF completo (apenas endpoints públicos mascaram)

---

### Resumo das Mudanças P13 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P13-M1 | RN-P13-N1 | Job: Suspensão após CIA com 6 meses de inatividade (OBRIGATÓRIO — não existe) | 🔴 Crítica |
| P13-M2 | RN-P13-N2 | Job: Suspensão após CA/CIV com 2 anos de inatividade (OBRIGATÓRIO — não existe) | 🔴 Crítica |
| P13-M4 | RN-P13-N4 | Cálculo de validade APPCI por tipo de ocupação e grau de risco (OBRIGATÓRIO) | 🔴 Crítica |
| P13-M3 | RN-P13-N3 | Data limite APPCI parcial: 27/12/2026 → 27/12/2027 (parâmetro configurável) | 🟠 Alta |
| P13-M5 | RN-P13-N5 | Mascaramento de CPF na consulta pública (LGPD) | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprint 04 + Normas RTCBMRS*

*Seção 16 adicionada em 2026-03-20. Base normativa: RT de Implantação SOL-CBMRS 4ª Edição/2022 (itens 6.3.7.2.3, 6.4.8.2, 8.1.2c e 12.2).*
