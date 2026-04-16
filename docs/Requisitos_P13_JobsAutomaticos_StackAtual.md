# Requisitos — P13: Jobs Automáticos do Sistema (Renovação de Alvarás)
## Versão Stack Atual (Java EE 7 · EJB 3.2 · JAX-RS · CDI · JPA/Hibernate · Oracle · WildFly)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P13 — Jobs Automáticos do Sistema
**Stack:** Java EE 7 · EJB 3.2 (`@Singleton @Startup @Schedule`) · CDI · JPA/Hibernate (Criteria API) · Oracle · WildFly/JBoss · JavaMail
**Versão do documento:** 1.0
**Data:** 2026-03-14
**Referência no código-fonte:**
- `com.procergs.solcbm.EJBTimerService`
- `com.procergs.solcbm.licenciamento.LicenciamentoRN`
- `com.procergs.solcbm.licenciamento.LicenciamentoBD`
- `com.procergs.solcbm.licenciamentonotificacao.LicenciamentoNotificacaoRN`
- `com.procergs.solcbm.appci.AppciRN`
- `com.procergs.solcbm.rotina.RotinaRN`
- `com.procergs.solcbm.batch.alvara.remote.AlvaraBatchServlet`

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
9. [Modelo de Dados (Oracle)](#9-modelo-de-dados-oracle)
10. [Máquina de Estados do Licenciamento — Ciclo de Renovação](#10-máquina-de-estados-do-licenciamento--ciclo-de-renovação)
11. [Marcos de Auditoria (TipoMarco)](#11-marcos-de-auditoria-tipomarco)
12. [Notificações e Templates de E-mail](#12-notificações-e-templates-de-e-mail)
13. [Rastreabilidade de Execução (RotinaRN)](#13-rastreabilidade-de-execução-rotinarn)
14. [Segurança e Autorização](#14-segurança-e-autorização)
15. [Classes, EJBs e Componentes](#15-classes-ejbs-e-componentes)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P13 é o conjunto de **jobs automáticos agendados** do SOL responsáveis por gerenciar o ciclo de vida de alvarás (APPCIs) e o fluxo de renovação de licenciamentos. Diferentemente dos processos P01–P12, **P13 não possui interação humana direta** — é um processo daemon que executa em background, acionado pelo mecanismo **EJB Timer Service** do servidor de aplicação WildFly.

O processo cobre cinco jobs com agendamentos distintos, todos orquestrados pela classe `EJBTimerService`:

| Job | Nome | Agendamento (`@Schedule`) | Classe principal |
|---|---|---|---|
| **P13-A** | Atualização de Alvarás Vencidos | `hour="0", minute="1"` (00:01 diário) | `LicenciamentoRN.verificaValidadeAlvara()` |
| **P13-B** | Notificação de Vencimento Próximo | `hour="0", minute="1"` (00:01 diário) | `LicenciamentoRN.notificaAlvaraAVencer(TipoMarco)` |
| **P13-C** | Notificação de Alvará Vencido | `hour="0", minute="1"` (00:01 diário) | `LicenciamentoRN.notificaAlvaraAVencer(NOTIFICACAO_ALVARA_VENCIDO)` |
| **P13-D** | Envio de Notificações Pendentes | `hour="0", minute="31"` (00:31 diário) | `LicenciamentoNotificacaoRN.enviarNotificacoesLicenciamentosPorEmail()` |
| **P13-E** | Verificação de Pagamento Banrisul | `minute="0", hour="*/12"` (a cada 12h) | `PagamentoBoletoRN.verificaPagamentoBanrisul()` |

### 1.2 Resultados possíveis

| Resultado | Estado/Situação resultante |
|---|---|
| Alvarás com `dataValidade <= hoje` atualizados | `SituacaoLicenciamento.ALVARA_VENCIDO` |
| Envolvidos notificados 90 dias antes | Marco `NOTIFICACAO_SOLICITAR_RENOVACAO_90` registrado |
| Envolvidos notificados 59 dias antes | Marco `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` registrado |
| Envolvidos notificados 29 dias antes | Marco `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` registrado |
| Envolvidos notificados após vencimento | Marco `NOTIFICACAO_ALVARA_VENCIDO` registrado |
| Notificação enviada com sucesso | `SituacaoEnvioLicenciamentoNotificacao.ENVIADO` |
| Falha de envio registrada | `SituacaoEnvioLicenciamentoNotificacao.ERRO` (reprocessado) |
| Pagamento CNAB 240 confirmado | Boleto baixado; situação do licenciamento avança |

### 1.3 User Stories relacionadas

P13 não está associado a uma única User Story. É um processo transversal de infraestrutura que sustenta o ciclo de renovação, referenciado implicitamente nas histórias de renovação de APPCI. O componente de acionamento alternativo via Workload está implementado em `AlvaraBatchServlet` (`/public/verificaAlvara`).

---

## 2. Caracterização dos Jobs

### 2.1 Natureza do processo

P13 é um processo **puramente automatizado**:
- Sem interação de usuário.
- Sem endpoints REST de entrada expostos ao público.
- Sem sessão de usuário ou token OAuth2/OIDC.
- Executado com identidade de sistema pelo servidor de aplicação WildFly.

### 2.2 Mecanismo de agendamento: EJB Timer Service

Na stack atual, o agendamento é feito via **EJB 3.2 Timer Service** com anotações `@Schedule` declarativas sobre métodos de um EJB `@Singleton @Startup`. A persistência do timer (`persistent = false`) significa que os timers são recriados a cada reinicialização do servidor — não há recuperação automática de execuções perdidas por downtime.

```java
@Singleton
@Startup
public class EJBTimerService {

    @EJB private LicenciamentoRN licenciamentoRN;
    @EJB private LicenciamentoNotificacaoRN licenciamentoNotificacaoRN;
    @EJB private PagamentoBoletoRN pagamentoBoletoRN;

    // Job diário — 00:01 — P13-A + P13-B + P13-C
    @Schedule(dayOfMonth = "*", month = "*", year = "*",
              hour = "0", minute = "1", persistent = false)
    public void notificaAlvarasVencimento() {
        licenciamentoRN.verificaValidadeAlvara();
        licenciamentoRN.notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLICITAR_RENOVACAO_90);
        licenciamentoRN.notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59);
        licenciamentoRN.notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29);
        licenciamentoRN.notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_ALVARA_VENCIDO);
        licenciamentoRN.iniciaRotinaDeAlvaraVencido();
    }

    // Job diário — 00:31 — P13-D
    @Schedule(dayOfMonth = "*", month = "*", year = "*",
              hour = "0", minute = "31", persistent = false)
    public void enviarNotificacaoLicenciamento() {
        licenciamentoNotificacaoRN.enviarNotificacoesLicenciamentosPorEmail();
    }

    // Job a cada 12h — P13-E
    @Schedule(minute = "0", hour = "*/12", persistent = false)
    public void verificaPagamentoBanrisul() {
        pagamentoBoletoRN.verificaPagamentoBanrisul();
    }

    // Job mensal — 1º dia do mês às 01:05
    @Schedule(dayOfMonth = "1", hour = "0", minute = "5",
              month = "*", year = "*", persistent = false)
    public void faturamentoMes() {
        // faturamento mensal
    }
}
```

### 2.3 Isolamento de transação por job

Cada método anotado com `@Schedule` executa em contexto transacional gerenciado pelo container EJB. O método `notificaAlvaraAVencer` usa `@TransactionAttribute(TransactionAttributeType.REQUIRES_NEW)` para garantir que a falha no processamento de um licenciamento não reverta os demais.

### 2.4 Servlet alternativo (Workload)

Para acionamento externo via Workload (integração legada), existe:

```java
@WebServlet(urlPatterns = "/public/verificaAlvara")
public class AlvaraBatchServlet extends HttpServlet {
    @EJB private LicenciamentoRN licenciamentoRN;

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) {
        licenciamentoRN.verificaValidadeAlvara();
        // ... demais chamadas
    }
}
```

Este servlet está no path `/public/` — acessível sem autenticação, protegido apenas por restrição de rede (chamado somente pelo Workload interno).

---

## 3. Job P13-A — Atualização de Alvarás Vencidos

### 3.1 Objetivo

Detectar diariamente todos os licenciamentos com situação `ALVARA_VIGENTE` cujo APPCI vigente (`IND_VERSAO_VIGENTE = 'S'`) tenha `DATA_VALIDADE <= SYSDATE` e transitar sua situação para `ALVARA_VENCIDO`.

### 3.2 Classe responsável

`com.procergs.solcbm.licenciamento.LicenciamentoRN`
Método: `verificaValidadeAlvara()`
Anotação: `@TransactionAttribute(TransactionAttributeType.REQUIRED)`

### 3.3 Implementação atual

```java
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public void verificaValidadeAlvara() {
    List<LicenciamentoED> alvaras = licenciamentoBD.consultaAlvaraVencido();
    for (LicenciamentoED obj : alvaras) {
        // 1. Registra histórico de situação
        LicenciamentoSituacaoHistED hist = BuilderLicenciamentoSituacaoHistED
            .of()
            .licenciamento(obj)
            .situacaoAnterior(obj.getSituacao())
            .situacaoAtual(SituacaoLicenciamento.ALVARA_VENCIDO)
            .dthSituacaoAtual(Calendar.getInstance())
            .dthSituacaoAnterior(obj.getCtrDthAtu())
            .instance();
        licenciamentoSituacaoHistRN.inclui(hist);

        // 2. Atualiza situação do licenciamento
        obj.setSituacao(SituacaoLicenciamento.ALVARA_VENCIDO);
        altera(obj);

        // 3. Marca APPCIs como não vigentes
        appciRN.alteraIndVersaoVigenteAppciVencido(obj);

        // 4. Marca documentos complementares como não vigentes
        docCompRN.alteraIndVersaoVigenteAppciDocComplementarVencido(obj);
    }
}
```

### 3.4 Query Oracle (Hibernate Criteria API — `LicenciamentoBD.consultaAlvaraVencido()`)

```java
public List<LicenciamentoED> consultaAlvaraVencido() {
    // Subcritério: APPCIs com dataValidade vencida e versão vigente
    DetachedCriteria subCriteria = DetachedCriteria.forClass(AppciED.class);
    subCriteria.add(Restrictions.le("dataValidade", Calendar.getInstance()));
    subCriteria.add(Restrictions.eq("indVersaoVigente", "S")); // SimNaoBooleanConverter
    subCriteria.setProjection(Projections.property("licenciamento.id"));

    // Critério principal: licenciamentos ALVARA_VIGENTE com APPCI vencido
    Criteria criteria = getSession().createCriteria(LicenciamentoED.class);
    criteria.add(Restrictions.eq("situacao", SituacaoLicenciamento.ALVARA_VIGENTE));
    criteria.add(Subqueries.propertyIn("id", subCriteria));

    return criteria.list();
}
```

**SQL gerado equivalente (Oracle):**
```sql
SELECT l.*
FROM   TB_LICENCIAMENTO l
WHERE  l.DSC_SITUACAO = 'ALVARA_VIGENTE'
  AND  l.ID IN (
           SELECT a.ID_LICENCIAMENTO
           FROM   TB_APPCI a
           WHERE  a.DAT_VALIDADE <= SYSDATE
             AND  a.IND_VERSAO_VIGENTE = 'S'
       )
```

### 3.5 Marcação de APPCIs — `AppciRN.alteraIndVersaoVigenteAppciVencido()`

```java
public void alteraIndVersaoVigenteAppciVencido(LicenciamentoED licenciamentoED) {
    if (!licenciamentoED.getAppcis().isEmpty()) {
        licenciamentoED.getAppcis().stream().forEach((appci) -> {
            appci.setIndVersaoVigente("N"); // SimNaoBooleanConverter: false = 'N'
            altera(appci);
        });
    }
}
```

**Tabela afetada:** `TB_APPCI` — coluna `IND_VERSAO_VIGENTE CHAR(1)` → valor `'N'`

### 3.6 Regras de negócio aplicáveis

- **RN-121:** Apenas licenciamentos com `DSC_SITUACAO = 'ALVARA_VIGENTE'` são elegíveis. Licenciamentos já em `ALVARA_VENCIDO` ou em qualquer estado de renovação em andamento não são re-processados.
- **RN-122:** O critério de vencimento usa `TB_APPCI.DAT_VALIDADE <= SYSDATE` com `IND_VERSAO_VIGENTE = 'S'`. Se não existir APPCI vigente, o licenciamento não é elegível.
- **RN-123:** A transição gera obrigatoriamente um registro em `TB_LICENCIAMENTO_SITUACAO_HIST` para auditoria.
- **RN-124:** A marcação `IND_VERSAO_VIGENTE = 'N'` nos APPCIs ocorre após a alteração de situação do licenciamento, na mesma transação (`REQUIRED`).

---

## 4. Job P13-B — Notificação de Vencimento Próximo (90/59/29 dias)

### 4.1 Objetivo

Notificar os envolvidos do licenciamento (RT, RU, Proprietários) quando o alvará está próximo do vencimento, nos marcos de 90, 59 e 29 dias antes da `DATA_VALIDADE` do APPCI vigente.

### 4.2 Classe responsável

`com.procergs.solcbm.licenciamento.LicenciamentoRN`
Método: `notificaAlvaraAVencer(TipoMarco marco)`
Anotação: `@TransactionAttribute(TransactionAttributeType.REQUIRES_NEW)`

### 4.3 Implementação atual

```java
@TransactionAttribute(TransactionAttributeType.REQUIRES_NEW)
public void notificaAlvaraAVencer(TipoMarco marco) {
    String templateEmail;
    String templateNotificacao;
    Integer dias;
    String assunto;

    switch (marco) {
        case NOTIFICACAO_SOLICITAR_RENOVACAO_90:
            templateEmail      = "notificacao.email.template.vencimento.alvara.90";
            templateNotificacao = "notificacao.vencimento.alvara.90";
            dias               = 90;
            assunto            = "notificacao.email.assunto.vencimento.alvara.90";
            break;
        case NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59:
            templateEmail      = "notificacao.email.template.vencimento.alvara.59";
            templateNotificacao = "notificacao.vencimento.alvara.59";
            dias               = 59;
            assunto            = "notificacao.email.assunto.perda.periodo.renovacao";
            break;
        case NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29:
            templateEmail      = "notificacao.email.template.vencimento.alvara.29";
            templateNotificacao = "notificacao.vencimento.alvara.29";
            dias               = 29;
            assunto            = "notificacao.email.assunto.perda.periodo.renovacao";
            break;
        case NOTIFICACAO_ALVARA_VENCIDO:
            templateEmail      = "notificacao.email.template.perda.periodo.renovacao";
            templateNotificacao = "notificacao.perda.periodo.renovacao";
            dias               = -1; // alvarás já vencidos
            assunto            = "notificacao.email.assunto.perda.periodo.renovacao";
            break;
        default:
            return;
    }

    // Determina baseline: data da última execução bem-sucedida da rotina
    Calendar dataBase = ultimaDataProcessamentoAlvarasVencidos(
        RotinaEnum.GERAR_NOTIFICACAO_ALVARA_VENCIDO);

    List<LicenciamentoED> licenciamentos;
    if (dias > 0) {
        licenciamentos = licenciamentoBD.consultaAlvarasAVencer(dias, dataBase);
    } else {
        licenciamentos = licenciamentoBD.consultaAlvarasVencidos(dataBase);
    }

    for (LicenciamentoED lic : licenciamentos) {
        notificaAlvara(lic, marco, templateEmail, templateNotificacao, assunto);
    }
}
```

### 4.4 Controle de reprocessamento — `ultimaDataProcessamentoAlvarasVencidos()`

```java
private Calendar ultimaDataProcessamentoAlvarasVencidos(RotinaEnum tipoRotina) {
    RotinaED ultimaExecucao = rotinaRN.consultaUltimaRotinaConcluida(tipoRotina);
    if (ultimaExecucao != null && ultimaExecucao.getDataFimExecucao() != null) {
        return ultimaExecucao.getDataFimExecucao();
    }
    // Padrão: ontem
    Calendar ontem = Calendar.getInstance();
    ontem.add(Calendar.DATE, -1);
    return ontem;
}
```

**Comportamento:** Se a rotina não executou ontem (ex.: falha de servidor), o baseline retrocede até a última execução registrada, garantindo que os alvarás do intervalo perdido sejam notificados na próxima execução.

### 4.5 Query Oracle — `LicenciamentoBD.consultaAlvarasAVencer(Integer dias, Calendar dataInicio)`

```java
public List<LicenciamentoED> consultaAlvarasAVencer(Integer dias, Calendar dataInicio) {
    // Calcula a janela de datas: [dataInicio + dias (00:00) .. dataInicio + dias (23:59)]
    Calendar inicio = (Calendar) dataInicio.clone();
    inicio.add(Calendar.DATE, dias);
    inicio.set(Calendar.HOUR_OF_DAY, 0);
    inicio.set(Calendar.MINUTE, 0);
    inicio.set(Calendar.SECOND, 0);

    Calendar fim = (Calendar) inicio.clone();
    fim.set(Calendar.HOUR_OF_DAY, 23);
    fim.set(Calendar.MINUTE, 59);
    fim.set(Calendar.SECOND, 59);

    DetachedCriteria subCriteria = DetachedCriteria.forClass(AppciED.class);
    subCriteria.add(Restrictions.ge("dataValidade", inicio));
    subCriteria.add(Restrictions.le("dataValidade", fim));
    subCriteria.add(Restrictions.eq("indVersaoVigente", "S"));
    subCriteria.setProjection(Projections.property("licenciamento.id"));

    Criteria criteria = getSession().createCriteria(LicenciamentoED.class);
    criteria.add(Restrictions.eq("situacao", SituacaoLicenciamento.ALVARA_VIGENTE));
    criteria.add(Subqueries.propertyIn("id", subCriteria));

    return criteria.list();
}
```

**SQL equivalente Oracle:**
```sql
SELECT l.*
FROM   TB_LICENCIAMENTO l
WHERE  l.DSC_SITUACAO = 'ALVARA_VIGENTE'
  AND  l.ID IN (
           SELECT a.ID_LICENCIAMENTO
           FROM   TB_APPCI a
           WHERE  a.DAT_VALIDADE >= :inicio   -- dataBase + dias, 00:00
             AND  a.DAT_VALIDADE <= :fim       -- dataBase + dias, 23:59
             AND  a.IND_VERSAO_VIGENTE = 'S'
       )
```

### 4.6 Seleção de destinatários

A lógica de seleção de RT destinatário depende da quantidade de APPCIs do licenciamento:

| Condição | RT notificado |
|---|---|
| 1 único APPCI | RT com `TIPO_RESPONSABILIDADE IN ('PROJETO_EXECUCAO', 'EXECUCAO')` |
| Múltiplos APPCIs | RT com `TIPO_RESPONSABILIDADE = 'RENOVACAO_APPCI'` |
| Sempre | Todos os RU ativos + todos os Proprietários ativos |

### 4.7 Criação da notificação em fila — `LicenciamentoNotificacaoRN.registraNotificacaoEmail()`

```java
public void registraNotificacaoEmail(LicenciamentoED licenciamento,
        LicenciamentoMarcoED marco, String usuario,
        String destinatario, String assunto, String mensagem, String contexto) {

    LicenciamentoNotificacaoED notif = new LicenciamentoNotificacaoED();
    notif.setLicenciamento(licenciamento);
    notif.setMarco(marco);
    notif.setTipoEnvio(TipoEnvioLicenciamentoNotificacao.EMAIL);
    notif.setTipoSituacaoNotificacao(SituacaoEnvioLicenciamentoNotificacao.PENDENTE);
    notif.setDestinatario(destinatario);
    notif.setAssunto(assunto);
    notif.setMensagem(mensagem);
    notif.setContexto(contexto); // nome do TipoMarco
    notif.setUuid(UUID.randomUUID().toString());
    notif.setCtrDthInc(Calendar.getInstance());
    inclui(notif);
}
```

**Tabela Oracle:** `TB_LICENCIAMENTO_NOTIFICACAO` — coluna `DSC_SITUACAO = 'PENDENTE'`

### 4.8 Regras de negócio aplicáveis

- **RN-125:** Notificação de 90d: `TB_APPCI.DAT_VALIDADE` deve cair na janela `[dataBase + 90 dias, 00:00 até 23:59]`. O controle de não-reenvio é feito pelo baseline `dataBase` (última execução da rotina).
- **RN-126:** Notificações de 59d e 29d seguem a mesma lógica de RN-125.
- **RN-127:** Licenciamentos em estados de renovação já em andamento (`AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO`) **não** retornam na query (filtro por `DSC_SITUACAO = 'ALVARA_VIGENTE'`), portanto não recebem nova notificação.
- **RN-128:** Destinatário com e-mail nulo/inválido: o método de envio não falha; emite log e continua para o próximo destinatário.

---

## 5. Job P13-C — Notificação de Alvará Vencido

### 5.1 Objetivo

Notificar os envolvidos quando o alvará **venceu** desde a última execução da rotina. Diferente do P13-B (que avisa *antes* do vencimento), este job notifica *após* o vencimento ter ocorrido.

### 5.2 Classe responsável

`com.procergs.solcbm.licenciamento.LicenciamentoRN`
Método: `notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_ALVARA_VENCIDO)`
(mesmo método do P13-B, ramo `case NOTIFICACAO_ALVARA_VENCIDO` com `dias = -1`)

### 5.3 Query Oracle — `LicenciamentoBD.consultaAlvarasVencidos(Calendar dataInicio)`

```java
public List<LicenciamentoED> consultaAlvarasVencidos(Calendar dataInicio) {
    // Janela: [dataInicio, ontem 23:59]
    Calendar fim = Calendar.getInstance();
    fim.set(Calendar.HOUR_OF_DAY, 23);
    fim.set(Calendar.MINUTE, 59);
    fim.set(Calendar.SECOND, 59);
    fim.add(Calendar.DATE, -1); // até ontem

    DetachedCriteria subCriteria = DetachedCriteria.forClass(AppciED.class);
    subCriteria.add(Restrictions.ge("dataValidade", dataInicio));
    subCriteria.add(Restrictions.le("dataValidade", fim));
    // Sem filtro IND_VERSAO_VIGENTE — APPCIs já foram marcados como 'N' pelo P13-A
    subCriteria.setProjection(Projections.property("licenciamento.id"));

    Criteria criteria = getSession().createCriteria(LicenciamentoED.class);
    criteria.add(Restrictions.eq("situacao", SituacaoLicenciamento.ALVARA_VENCIDO));
    criteria.add(Subqueries.propertyIn("id", subCriteria));

    return criteria.list();
}
```

### 5.4 Marco registrado

`TipoMarco.NOTIFICACAO_ALVARA_VENCIDO`

**Tabela Oracle:** `TB_LICENCIAMENTO_MARCO` — `DSC_TIPO_MARCO = 'NOTIFICACAO_ALVARA_VENCIDO'`

### 5.5 Regras de negócio aplicáveis

- **RN-129:** O marco `NOTIFICACAO_ALVARA_VENCIDO` deve ser registrado apenas uma vez por licenciamento. A query usa o baseline `dataBase` (última execução da rotina) para delimitar o intervalo, impedindo re-notificação.
- **RN-130:** Destinatários seguem a mesma lógica de seleção de RN-125/RN-128.

---

## 6. Job P13-D — Envio de Notificações Pendentes por E-mail

### 6.1 Objetivo

Processar a fila de notificações com `DSC_SITUACAO = 'PENDENTE'` ou `DSC_SITUACAO = 'ERRO'` na tabela `TB_LICENCIAMENTO_NOTIFICACAO` e efetivamente transmitir os e-mails via JavaMail/SMTP do WildFly.

### 6.2 Separação intencional de Jobs

O P13-B/C cria as notificações (operação de banco — transacional), enquanto o P13-D as envia (operação de I/O externo — SMTP). A separação evita que o rollback de uma falha SMTP reverta os registros de banco criados pelos jobs anteriores.

### 6.3 Classe responsável

`com.procergs.solcbm.licenciamentonotificacao.LicenciamentoNotificacaoRN`
Método: `enviarNotificacoesLicenciamentosPorEmail()`
EJB: `@Stateless`

### 6.4 Implementação atual

```java
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public void enviarNotificacoesLicenciamentosPorEmail() {
    // Processa notificações PENDENTES
    enviarNotificacoesLicenciamentoPorEmailLista(
        listarNotificacoesLicenciamentosPorSituacao(
            TipoEnvioLicenciamentoNotificacao.EMAIL,
            SituacaoEnvioLicenciamentoNotificacao.PENDENTE));

    // Processa notificações com ERRO (retry)
    enviarNotificacoesLicenciamentoPorEmailLista(
        listarNotificacoesLicenciamentosPorSituacao(
            TipoEnvioLicenciamentoNotificacao.EMAIL,
            SituacaoEnvioLicenciamentoNotificacao.ERRO));
}

private void enviarNotificacoesLicenciamentoPorEmailLista(
        List<LicenciamentoNotificacaoED> lista) {
    for (LicenciamentoNotificacaoED notif : lista) {
        try {
            // Envia e-mail via NotificacaoEmailRN (JavaMail)
            notificacaoEmailRN.enviar(
                notif.getDestinatario(),
                notif.getAssunto(),
                notif.getMensagem());

            // Atualiza para ENVIADO
            notif.setTipoSituacaoNotificacao(
                SituacaoEnvioLicenciamentoNotificacao.ENVIADO);
            notif.setCtrDthEnvio(Calendar.getInstance());

        } catch (Exception e) {
            log.error("Falha ao enviar notificação {}: {}", notif.getUuid(), e.getMessage());
            // Atualiza para ERRO
            notif.setTipoSituacaoNotificacao(
                SituacaoEnvioLicenciamentoNotificacao.ERRO);
        }
        altera(notif);
    }
}
```

### 6.5 Query de notificações pendentes (Oracle)

```sql
SELECT n.*
FROM   TB_LICENCIAMENTO_NOTIFICACAO n
WHERE  n.DSC_TIPO_ENVIO    = 'EMAIL'
  AND  n.DSC_SITUACAO IN ('PENDENTE', 'ERRO')
ORDER BY n.CTR_DTH_INC ASC
```

### 6.6 Configuração JavaMail no WildFly

O servidor de e-mail é configurado no WildFly como `@Resource(lookup = "java:jboss/mail/Default")` dentro do `NotificacaoEmailRN`. As propriedades (`mail.smtp.host`, `mail.smtp.port`, `mail.smtp.auth`) são definidas no `standalone.xml` do WildFly — não no código da aplicação.

### 6.7 Enumerações envolvidas

```java
public enum TipoEnvioLicenciamentoNotificacao {
    EMAIL, SMS
}

public enum SituacaoEnvioLicenciamentoNotificacao {
    PENDENTE,
    ENVIADO,
    ERRO
}
```

### 6.8 Regras de negócio aplicáveis

- **RN-131:** O envio de e-mail (I/O SMTP) é executado fora de transação de banco de forma efetiva — a atualização do status é feita *após* a tentativa de envio, em `altera(notif)`.
- **RN-132:** Não há limite explícito de tentativas no código atual. Notificações com `ERRO` são reprocessadas indefinidamente a cada 00:31. A equipe de operações deve monitorar notificações em `ERRO` por longa data.
- **RN-133:** A ordem de processamento segue `CTR_DTH_INC ASC` (mais antigas primeiro).

---

## 7. Job P13-E — Verificação de Pagamento Banrisul (CNAB 240)

### 7.1 Objetivo

A cada 12 horas, verificar o retorno de cobranças do **Banrisul** no formato **CNAB 240** e processar pagamentos confirmados de boletos de vistoria de renovação.

### 7.2 Relação com P11

O Job P13-E é o sub-processo P11-B documentado em `Requisitos_P11_PagamentoBoleto_StackAtual.md`. O agendamento de 12h em 12h é feito pelo `EJBTimerService`, mas a lógica de negócio reside em `PagamentoBoletoRN`.

### 7.3 Classe responsável

`com.procergs.solcbm.pagamentoboleto.PagamentoBoletoRN`
Método: `verificaPagamentoBanrisul()`

### 7.4 Regras de negócio aplicáveis

- **RN-135:** Arquivo CNAB 240 já processado não deve ser reprocessado. O controle é feito por marcação/movimentação do arquivo no diretório de retorno.
- **RN-136:** Falha no processamento de um arquivo não impede o processamento dos demais.

Para a especificação completa do processamento CNAB 240, consultar: `Requisitos_P11_PagamentoBoleto_StackAtual.md`, seção 5 (Job P11-B).

---

## 8. Regras de Negócio

| ID | Descrição | Job | Tabelas Oracle afetadas |
|---|---|---|---|
| **RN-121** | Apenas licenciamentos com `DSC_SITUACAO = 'ALVARA_VIGENTE'` são elegíveis para P13-A | P13-A | `TB_LICENCIAMENTO` |
| **RN-122** | Critério de vencimento: `TB_APPCI.DAT_VALIDADE <= SYSDATE` com `IND_VERSAO_VIGENTE = 'S'` | P13-A | `TB_APPCI` |
| **RN-123** | Toda transição de situação registra `TB_LICENCIAMENTO_SITUACAO_HIST` | P13-A | `TB_LICENCIAMENTO_SITUACAO_HIST` |
| **RN-124** | Marcação `IND_VERSAO_VIGENTE = 'N'` nos APPCIs ocorre na mesma transação da mudança de situação | P13-A | `TB_APPCI` |
| **RN-125** | Notificação de 90d: `TB_APPCI.DAT_VALIDADE` deve cair na janela `[dataBase+90, 00:00–23:59]`. `dataBase` = data da última execução bem-sucedida da rotina | P13-B | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` |
| **RN-126** | Notificações de 59d e 29d: mesma lógica de RN-125 com intervalos distintos | P13-B | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` |
| **RN-127** | Licenciamentos em estados de renovação em andamento não recebem nova notificação de vencimento (query filtra por `ALVARA_VIGENTE`) | P13-B | — |
| **RN-128** | Destinatário com e-mail nulo/inválido: log de aviso emitido; job não interrompido | P13-B/C/D | — |
| **RN-129** | Marco `NOTIFICACAO_ALVARA_VENCIDO` é registrado apenas dentro do intervalo `[dataBase, ontem 23:59]` — controle feito pela query de vencidos | P13-C | `TB_LICENCIAMENTO_MARCO` |
| **RN-130** | Seleção de RT destinatário: 1 APPCI → tipo `PROJETO_EXECUCAO`/`EXECUCAO`; múltiplos APPCIs → tipo `RENOVACAO_APPCI` | P13-B/C | — |
| **RN-131** | Atualização de status da notificação (`PENDENTE/ENVIADO/ERRO`) ocorre após a tentativa de envio SMTP | P13-D | `TB_LICENCIAMENTO_NOTIFICACAO` |
| **RN-132** | Não há limite de tentativas no código atual: notificações `ERRO` são reprocessadas em todos os ciclos de 00:31 até serem enviadas | P13-D | `TB_LICENCIAMENTO_NOTIFICACAO` |
| **RN-133** | Ordem de processamento das notificações: `CTR_DTH_INC ASC` (mais antigas primeiro) | P13-D | — |
| **RN-134** | O conteúdo do e-mail é gerado a partir de chaves de template internacionalizadas (`MessageProvider`) definidas em arquivos de propriedades no classpath | P13-B/C/D | — |
| **RN-135** | Arquivo CNAB 240 processado é movido/marcado para não reprocessamento | P13-E | — |
| **RN-136** | Falha em um arquivo CNAB não impede o processamento dos demais | P13-E | — |
| **RN-137** | EJB Timer usa `persistent = false`: timers não sobrevivem a reinicializações do servidor; execuções perdidas por downtime não são recuperadas automaticamente | Todos | — |
| **RN-138** | Em ambiente com múltiplas instâncias WildFly (cluster), o EJB Timer pode disparar em todas — não há proteção nativa de execução única na stack atual | Todos | — |
| **RN-139** | O método `notificaAlvaraAVencer` usa `@TransactionAttribute(REQUIRES_NEW)`: a falha em um licenciamento não reverte o processamento dos anteriores | P13-B/C | — |
| **RN-140** | A data de última execução da rotina (`TB_ROTINA`) é o baseline temporal para todas as queries de notificação | P13-B/C | `TB_ROTINA` |

---

## 9. Modelo de Dados (Oracle)

### 9.1 `TB_APPCI` — Alvará de Prevenção e Proteção Contra Incêndio

| Coluna | Tipo Oracle | Descrição |
|---|---|---|
| `ID` | `NUMBER(19)` | PK |
| `ID_LICENCIAMENTO` | `NUMBER(19)` | FK → `TB_LICENCIAMENTO.ID` |
| `DAT_VALIDADE` | `DATE` | Data de validade do alvará |
| `DAT_INICIO_VIGENCIA` | `DATE` | Data de início da vigência |
| `IND_VERSAO_VIGENTE` | `CHAR(1)` | `'S'` = vigente / `'N'` = não vigente (`SimNaoBooleanConverter`) |
| `NRO_APPCI` | `VARCHAR2(20)` | Número do alvará (ex.: `A 00000361 AA 001`) |
| `CTR_DTH_INC` | `TIMESTAMP` | Data/hora de inclusão |
| `CTR_DTH_ATU` | `TIMESTAMP` | Data/hora de última alteração |

**Índice relevante para P13-A:**
```sql
CREATE INDEX IDX_APPCI_DAT_VALIDADE_VIGENTE
    ON TB_APPCI(DAT_VALIDADE, IND_VERSAO_VIGENTE);
```

### 9.2 `TB_LICENCIAMENTO_NOTIFICACAO` — Fila de Notificações

| Coluna | Tipo Oracle | Descrição |
|---|---|---|
| `ID` | `NUMBER(19)` | PK |
| `ID_LICENCIAMENTO` | `NUMBER(19)` | FK → `TB_LICENCIAMENTO.ID` |
| `ID_MARCO` | `NUMBER(19)` | FK → `TB_LICENCIAMENTO_MARCO.ID` |
| `DSC_TIPO_ENVIO` | `VARCHAR2(10)` | `'EMAIL'` / `'SMS'` |
| `DSC_SITUACAO` | `VARCHAR2(15)` | `'PENDENTE'` / `'ENVIADO'` / `'ERRO'` |
| `DSC_DESTINATARIO` | `VARCHAR2(200)` | Endereço de e-mail ou número de telefone |
| `DSC_ASSUNTO` | `VARCHAR2(300)` | Assunto do e-mail |
| `DSC_MENSAGEM` | `CLOB` | Corpo do e-mail (HTML) |
| `DSC_CONTEXTO` | `VARCHAR2(100)` | Nome do `TipoMarco` (ex.: `NOTIFICACAO_SOLICITAR_RENOVACAO_90`) |
| `UUID` | `VARCHAR2(36)` | UUID único da notificação |
| `CTR_DTH_INC` | `TIMESTAMP` | Data/hora de criação |
| `CTR_DTH_ENVIO` | `TIMESTAMP` | Data/hora de envio efetivo |

### 9.3 `TB_LICENCIAMENTO_SITUACAO_HIST` — Histórico de Transições de Situação

| Coluna | Tipo Oracle | Descrição |
|---|---|---|
| `ID` | `NUMBER(19)` | PK |
| `ID_LICENCIAMENTO` | `NUMBER(19)` | FK → `TB_LICENCIAMENTO.ID` |
| `DSC_SITUACAO_ANTERIOR` | `VARCHAR2(50)` | Situação antes da transição |
| `DSC_SITUACAO_ATUAL` | `VARCHAR2(50)` | Situação após a transição |
| `DTH_SITUACAO_ANTERIOR` | `TIMESTAMP` | Data/hora da situação anterior (`CTR_DTH_ATU` do licenciamento) |
| `DTH_SITUACAO_ATUAL` | `TIMESTAMP` | Data/hora da nova situação |

### 9.4 `TB_ROTINA` — Controle de Execução de Rotinas

| Coluna | Tipo Oracle | Descrição |
|---|---|---|
| `ID` | `NUMBER(19)` | PK |
| `DSC_TIPO_ROTINA` | `VARCHAR2(60)` | Nome do `RotinaEnum` (ex.: `GERAR_NOTIFICACAO_ALVARA_VENCIDO`) |
| `DTH_INICIO_EXECUCAO` | `TIMESTAMP` | Início da execução |
| `DTH_FIM_EXECUCAO` | `TIMESTAMP` | Fim da execução (baseline para próxima execução) |
| `DSC_SITUACAO` | `VARCHAR2(15)` | `'EM_EXECUCAO'` / `'CONCLUIDA'` / `'ERRO'` |
| `DSC_MENSAGEM_ERRO` | `VARCHAR2(2000)` | Detalhe do erro, se houver |

### 9.5 `TB_LICENCIAMENTO_MARCO` — Marcos de Auditoria

| Coluna | Tipo Oracle | Descrição |
|---|---|---|
| `ID` | `NUMBER(19)` | PK |
| `ID_LICENCIAMENTO` | `NUMBER(19)` | FK → `TB_LICENCIAMENTO.ID` |
| `DSC_TIPO_MARCO` | `VARCHAR2(80)` | Nome do `TipoMarco` |
| `DTH_MARCO` | `TIMESTAMP` | Data/hora do registro |
| `DSC_USUARIO` | `VARCHAR2(100)` | Login do usuário (jobs usam `'sistema'`) |

### 9.6 Changelog Liquibase (estrutura esperada)

```xml
<!-- src/main/resources/db/changelog/changes/sXX-notificacao-licenciamento.xml -->
<changeSet id="XX-1" author="sol">
    <createTable tableName="TB_LICENCIAMENTO_NOTIFICACAO">
        <column name="ID" type="NUMBER(19)" autoIncrement="true">
            <constraints primaryKey="true"/>
        </column>
        <column name="ID_LICENCIAMENTO" type="NUMBER(19)">
            <constraints nullable="false"
                         foreignKeyName="FK_NOTIF_LICEN"
                         references="TB_LICENCIAMENTO(ID)"/>
        </column>
        <column name="ID_MARCO" type="NUMBER(19)"/>
        <column name="DSC_TIPO_ENVIO" type="VARCHAR2(10)" defaultValue="EMAIL">
            <constraints nullable="false"/>
        </column>
        <column name="DSC_SITUACAO" type="VARCHAR2(15)" defaultValue="PENDENTE">
            <constraints nullable="false"/>
        </column>
        <column name="DSC_DESTINATARIO" type="VARCHAR2(200)"/>
        <column name="DSC_ASSUNTO" type="VARCHAR2(300)"/>
        <column name="DSC_MENSAGEM" type="CLOB"/>
        <column name="DSC_CONTEXTO" type="VARCHAR2(100)"/>
        <column name="UUID" type="VARCHAR2(36)">
            <constraints nullable="false" unique="true"/>
        </column>
        <column name="CTR_DTH_INC" type="TIMESTAMP" defaultValueComputed="SYSTIMESTAMP">
            <constraints nullable="false"/>
        </column>
        <column name="CTR_DTH_ENVIO" type="TIMESTAMP"/>
    </createTable>
    <createIndex tableName="TB_LICENCIAMENTO_NOTIFICACAO"
                 indexName="IDX_NOTIF_SITUACAO">
        <column name="DSC_SITUACAO"/>
    </createIndex>
</changeSet>
```

---

## 10. Máquina de Estados do Licenciamento — Ciclo de Renovação

P13 dispara o início do ciclo de renovação. A transição `ALVARA_VIGENTE → ALVARA_VENCIDO` é o gatilho para que o cidadão possa solicitar a renovação:

```
[ALVARA_VIGENTE]
     │
     │ P13-B: notifica em 90d, 59d, 29d (somente aviso)
     │
     │ P13-A: DAT_VALIDADE APPCI <= SYSDATE
     ▼
[ALVARA_VENCIDO]
     │
     │ P13-C: notifica envolvidos
     │
     │ Cidadão solicita renovação (processo separado — P14 ou futuro)
     ▼
[AGUARDANDO_ACEITE_RENOVACAO]
     │
     │ Aceites de todos os envolvidos
     ▼
[AGUARDANDO_PAGAMENTO_RENOVACAO]
     │
     │ Pagamento confirmado — P11 / P13-E
     ▼
[AGUARDANDO_DISTRIBUICAO_RENOV]
     │
     │ Distribuição para vistoriador
     ▼
[EM_VISTORIA_RENOVACAO]
     │
     │ Vistoria aprovada → novo APPCI emitido → [ALVARA_VIGENTE] (novo ciclo)
     │ Vistoria reprovada (CIV) → fluxo de recurso de renovação
```

**Estados ativos por job:**

| Situação | P13-A | P13-B/C | P13-D |
|---|---|---|---|
| `ALVARA_VIGENTE` | Verifica vencimento | Notifica 90/59/29d | Envia pendentes |
| `ALVARA_VENCIDO` | — (já processado) | Notifica vencidos (P13-C) | Envia pendentes |
| `AGUARDANDO_ACEITE_RENOVACAO` e demais | — | — | Envia pendentes |

---

## 11. Marcos de Auditoria (TipoMarco)

| TipoMarco | Job | Tabela | Descrição |
|---|---|---|---|
| `NOTIFICACAO_SOLICITAR_RENOVACAO_90` | P13-B | `TB_LICENCIAMENTO_MARCO` | Notificação gerada 90 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` | P13-B | `TB_LICENCIAMENTO_MARCO` | Notificação gerada 59 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` | P13-B | `TB_LICENCIAMENTO_MARCO` | Notificação gerada 29 dias antes do vencimento |
| `NOTIFICACAO_ALVARA_VENCIDO` | P13-C | `TB_LICENCIAMENTO_MARCO` | Notificação gerada após o vencimento do alvará |

Demais marcos do ciclo de renovação (`ACEITE_VISTORIA_RENOVACAO`, `LIBERACAO_RENOV_APPCI`, etc.) são registrados pelos processos subsequentes ao P13.

---

## 12. Notificações e Templates de E-mail

### 12.1 Mapeamento TipoMarco → chave de template

| TipoMarco | Chave do template (e-mail) | Chave do template (notificação interna) | Assunto (chave) |
|---|---|---|---|
| `NOTIFICACAO_SOLICITAR_RENOVACAO_90` | `notificacao.email.template.vencimento.alvara.90` | `notificacao.vencimento.alvara.90` | `notificacao.email.assunto.vencimento.alvara.90` |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` | `notificacao.email.template.vencimento.alvara.59` | `notificacao.vencimento.alvara.59` | `notificacao.email.assunto.perda.periodo.renovacao` |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` | `notificacao.email.template.vencimento.alvara.29` | `notificacao.vencimento.alvara.29` | `notificacao.email.assunto.perda.periodo.renovacao` |
| `NOTIFICACAO_ALVARA_VENCIDO` | `notificacao.email.template.perda.periodo.renovacao` | `notificacao.perda.periodo.renovacao` | `notificacao.email.assunto.perda.periodo.renovacao` |

### 12.2 Resolução de templates

As chaves são resolvidas via `MessageProvider` — componente CDI que carrega arquivos `.properties` do classpath. Exemplo:

```java
@Inject
private MessageProvider messageProvider;

String corpo = messageProvider.getMessage(
    templateEmail,                    // chave do template
    lic.getNumeroPpci(),              // parâmetro 0 — número do PPCI
    formatarData(dataValidade),       // parâmetro 1 — data de validade
    lic.getEndereco().getFormatado()  // parâmetro 2 — endereço
);
```

### 12.3 Fluxo completo da notificação (P13-B → P13-D)

```
[P13-B / 00:01]
LicenciamentoRN.notificaAlvaraAVencer(TipoMarco)
    └─ Para cada licenciamento elegível:
         └─ Para cada destinatário (RT/RU/Proprietário):
              └─ LicenciamentoNotificacaoRN.registraNotificacaoEmail()
                   └─ INSERT TB_LICENCIAMENTO_NOTIFICACAO (DSC_SITUACAO='PENDENTE')

[P13-D / 00:31]
LicenciamentoNotificacaoRN.enviarNotificacoesLicenciamentosPorEmail()
    └─ SELECT TB_LICENCIAMENTO_NOTIFICACAO WHERE DSC_SITUACAO IN ('PENDENTE','ERRO')
         └─ Para cada notificação:
              ├─ NotificacaoEmailRN.enviar(destinatario, assunto, mensagem)
              │    └─ JavaMail → SMTP WildFly
              ├─ Sucesso: UPDATE DSC_SITUACAO = 'ENVIADO', CTR_DTH_ENVIO = SYSTIMESTAMP
              └─ Falha:   UPDATE DSC_SITUACAO = 'ERRO'
```

---

## 13. Rastreabilidade de Execução (RotinaRN)

### 13.1 Objetivo

Cada execução da rotina diária é registrada em `TB_ROTINA`. O campo `DTH_FIM_EXECUCAO` da última rotina `CONCLUIDA` é usado como baseline temporal para os intervalos de notificação.

### 13.2 `RotinaEnum`

```java
public enum RotinaEnum {
    GERAR_NOTIFICACAO_ALVARA_VENCIDO,
    VERIFICAR_PAGAMENTO_BANRISUL,
    FATURAMENTO_MENSAL
}
```

### 13.3 Ciclo de vida da rotina

```java
// Em LicenciamentoRN.iniciaRotinaDeAlvaraVencido()
public void iniciaRotinaDeAlvaraVencido() {
    RotinaED rotina = rotinaRN.iniciarRotina(
        RotinaEnum.GERAR_NOTIFICACAO_ALVARA_VENCIDO);

    // Aqui a rotina fica com DSC_SITUACAO = 'EM_EXECUCAO'
    // O registro é confirmado mesmo que os jobs anteriores tenham falhado parcialmente

    rotinaRN.finalizarRotina(rotina);
    // Atualiza: DSC_SITUACAO = 'CONCLUIDA', DTH_FIM_EXECUCAO = SYSTIMESTAMP
}
```

**Nota:** Na implementação atual, `iniciaRotinaDeAlvaraVencido()` é chamado **após** todos os jobs de notificação, servindo mais como "marcador de conclusão" do que como rastreador por etapa. Isso significa que, se um job anterior falhar com exceção não capturada, a rotina não é registrada e o baseline permanece na penúltima execução — o que leva ao reprocessamento do intervalo perdido na próxima execução.

### 13.4 Consulta da última execução

```java
// Em LicenciamentoRN.ultimaDataProcessamentoAlvarasVencidos()
private Calendar ultimaDataProcessamentoAlvarasVencidos(RotinaEnum tipoRotina) {
    RotinaED ultimaExecucao = rotinaRN.consultaUltimaRotinaConcluida(tipoRotina);
    if (ultimaExecucao != null && ultimaExecucao.getDataFimExecucao() != null) {
        return ultimaExecucao.getDataFimExecucao();
    }
    Calendar ontem = Calendar.getInstance();
    ontem.add(Calendar.DATE, -1);
    return ontem;
}
```

**Query Oracle:**
```sql
SELECT r.*
FROM   TB_ROTINA r
WHERE  r.DSC_TIPO_ROTINA = 'GERAR_NOTIFICACAO_ALVARA_VENCIDO'
  AND  r.DSC_SITUACAO    = 'CONCLUIDA'
ORDER BY r.DTH_FIM_EXECUCAO DESC
FETCH FIRST 1 ROWS ONLY
```

---

## 14. Segurança e Autorização

### 14.1 Perfil de execução

P13 é um processo **exclusivamente de sistema**:
- Não há autenticação OAuth2/OIDC — nenhum token SOE PROCERGS é necessário.
- Não há anotações `@AutorizaEnvolvido` ou `@SegurancaEnvolvidoInterceptor` — não se aplica.
- O `EJBTimerService` é um `@Singleton` gerenciado pelo container WildFly.

### 14.2 Servlet Alternativo — Segurança por rede

O `AlvaraBatchServlet` (`/public/verificaAlvara`) está no path `/public/` que, no WildFly, não exige autenticação de aplicação. A proteção se dá exclusivamente por:
- Restrição de rede (firewall): somente o servidor Workload interno pode acessar este endpoint.
- Não deve ser exposto na DMZ ou internet.

### 14.3 Dados sensíveis

- Endereços de e-mail dos destinatários são armazenados em `TB_LICENCIAMENTO_NOTIFICACAO.DSC_DESTINATARIO` — dado pessoal conforme LGPD.
- Logs de execução não devem registrar endereços completos de e-mail — recomendável mascarar (ex.: `jo***@dominio.com`).
- Arquivos CNAB 240 contêm dados financeiros: o diretório de retorno Banrisul deve ter permissão restrita ao usuário do processo WildFly no sistema operacional.

---

## 15. Classes, EJBs e Componentes

### 15.1 Diagrama de dependências

```
EJBTimerService (@Singleton @Startup)
    │
    ├─ @EJB LicenciamentoRN (@Stateless)
    │       ├─ @EJB LicenciamentoBD (@Stateless) ← Hibernate Criteria API
    │       ├─ @EJB AppciRN (@Stateless)
    │       │       └─ @EJB AppciBD (@Stateless)
    │       ├─ @EJB LicenciamentoSituacaoHistRN (@Stateless)
    │       ├─ @EJB LicenciamentoNotificacaoRN (@Stateless)
    │       └─ @EJB RotinaRN (@Stateless)
    │               └─ @EJB RotinaBD (@Stateless)
    │
    ├─ @EJB LicenciamentoNotificacaoRN (@Stateless)
    │       └─ @EJB NotificacaoEmailRN (@Stateless)
    │               └─ @Resource(lookup="java:jboss/mail/Default") Session mailSession
    │
    └─ @EJB PagamentoBoletoRN (@Stateless)
            └─ (ver Requisitos_P11)
```

### 15.2 Entidade JPA — `LicenciamentoNotificacaoED`

```java
@Entity
@Table(name = "TB_LICENCIAMENTO_NOTIFICACAO")
public class LicenciamentoNotificacaoED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "SEQ_LICENCIAMENTO_NOTIFICACAO")
    @SequenceGenerator(name = "SEQ_LICENCIAMENTO_NOTIFICACAO",
                       sequenceName = "SEQ_LICENCIAMENTO_NOTIFICACAO",
                       allocationSize = 1)
    @Column(name = "ID")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private LicenciamentoED licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_MARCO")
    private LicenciamentoMarcoED marco;

    @Enumerated(EnumType.STRING)
    @Column(name = "DSC_TIPO_ENVIO", nullable = false, length = 10)
    private TipoEnvioLicenciamentoNotificacao tipoEnvio;

    @Enumerated(EnumType.STRING)
    @Column(name = "DSC_SITUACAO", nullable = false, length = 15)
    private SituacaoEnvioLicenciamentoNotificacao tipoSituacaoNotificacao;

    @Column(name = "DSC_DESTINATARIO", length = 200)
    private String destinatario;

    @Column(name = "DSC_ASSUNTO", length = 300)
    private String assunto;

    @Lob
    @Column(name = "DSC_MENSAGEM")
    private String mensagem;

    @Column(name = "DSC_CONTEXTO", length = 100)
    private String contexto;

    @Column(name = "UUID", length = 36, unique = true, nullable = false)
    private String uuid;

    @Column(name = "CTR_DTH_INC")
    @Temporal(TemporalType.TIMESTAMP)
    private Calendar ctrDthInc;

    @Column(name = "CTR_DTH_ENVIO")
    @Temporal(TemporalType.TIMESTAMP)
    private Calendar ctrDthEnvio;
}
```

### 15.3 Entidade JPA — `AppciED` (campos relevantes para P13)

```java
@Entity
@Table(name = "TB_APPCI")
public class AppciED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "SEQ_APPCI")
    @SequenceGenerator(name = "SEQ_APPCI", sequenceName = "SEQ_APPCI", allocationSize = 1)
    @Column(name = "ID")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private LicenciamentoED licenciamento;

    @Column(name = "DAT_VALIDADE")
    @Temporal(TemporalType.DATE)
    private Calendar dataValidade;

    @Column(name = "IND_VERSAO_VIGENTE", length = 1)
    @Convert(converter = SimNaoBooleanConverter.class) // 'S' = true, 'N' = false
    private String indVersaoVigente;

    @Column(name = "NRO_APPCI", length = 20)
    private String numeroAppci;

    // ... demais campos
}
```

**Atenção ao `SimNaoBooleanConverter`:** O campo `IND_VERSAO_VIGENTE` é `CHAR(1)` no Oracle. A query Hibernate usa a string literal `"S"` (não o booleano `true`) por conta do converter. Qualquer query JPQL ou Criteria que filtre por `indVersaoVigente` deve usar `"S"` ou `"N"`.

### 15.4 Enumerações completas

#### `SituacaoLicenciamento` — estados relevantes para P13

```java
public enum SituacaoLicenciamento {
    ALVARA_VIGENTE("APPCI em vigor"),
    ALVARA_VENCIDO("APPCI vencido"),
    AGUARDANDO_ACEITE_RENOVACAO("Aguardando aceite da renovação"),
    AGUARDANDO_PAGAMENTO_RENOVACAO("Aguardando Pagamento ou isenção da Vistoria da Renovação"),
    AGUARDANDO_DISTRIBUICAO_RENOV("Aguardando Distribuição de Vistoria da Renovação"),
    EM_VISTORIA_RENOVACAO("Em vistoria de renovação");
    // ... demais valores (não usados por P13)
}
```

#### `TipoMarco` — marcos registrados pelo P13

```java
public enum TipoMarco {
    NOTIFICACAO_SOLICITAR_RENOVACAO_90,
    NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59,
    NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29,
    NOTIFICACAO_ALVARA_VENCIDO
    // ... demais valores do ciclo de renovação (registrados por outros processos)
}
```

#### `TipoEnvioLicenciamentoNotificacao`

```java
public enum TipoEnvioLicenciamentoNotificacao {
    EMAIL, SMS
}
```

#### `SituacaoEnvioLicenciamentoNotificacao`

```java
public enum SituacaoEnvioLicenciamentoNotificacao {
    PENDENTE, ENVIADO, ERRO
}
```

#### `RotinaEnum`

```java
public enum RotinaEnum {
    GERAR_NOTIFICACAO_ALVARA_VENCIDO,
    VERIFICAR_PAGAMENTO_BANRISUL,
    FATURAMENTO_MENSAL
}
```

### 15.5 Casos de teste — cenários BDD representativos

| TC | Dado | Quando | Então |
|---|---|---|---|
| TC-P13-01 | APPCI com `DAT_VALIDADE = SYSDATE - 1`, licenciamento `ALVARA_VIGENTE` | Job P13-A executa às 00:01 | `DSC_SITUACAO → 'ALVARA_VENCIDO'`; registro em `TB_LICENCIAMENTO_SITUACAO_HIST`; `IND_VERSAO_VIGENTE = 'N'` no APPCI |
| TC-P13-02 | APPCI com `DAT_VALIDADE = dataBase + 90` | Job P13-B executa | Notificação criada com contexto `NOTIFICACAO_SOLICITAR_RENOVACAO_90`; `DSC_SITUACAO = 'PENDENTE'` |
| TC-P13-03 | APPCI com `DAT_VALIDADE = dataBase + 59` | Job P13-B executa | Notificação `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` criada |
| TC-P13-04 | APPCI com `DAT_VALIDADE = dataBase + 29` | Job P13-B executa | Notificação `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` criada |
| TC-P13-05 | Licenciamento `ALVARA_VENCIDO`, `DAT_VALIDADE` do APPCI dentro da janela `[dataBase, ontem]` | Job P13-C executa | Notificação `NOTIFICACAO_ALVARA_VENCIDO` criada |
| TC-P13-06 | Licenciamento em `AGUARDANDO_ACEITE_RENOVACAO` com APPCI a vencer | Job P13-B executa | **Nenhuma notificação** (filtro `ALVARA_VIGENTE` exclui) |
| TC-P13-07 | Notificação com `DSC_SITUACAO = 'PENDENTE'` | Job P13-D executa às 00:31 | E-mail enviado via SMTP; `DSC_SITUACAO → 'ENVIADO'`; `CTR_DTH_ENVIO` gravado |
| TC-P13-08 | Notificação com `DSC_SITUACAO = 'PENDENTE'`, SMTP indisponível | Job P13-D executa | `DSC_SITUACAO → 'ERRO'`; processamento continua para as demais notificações |
| TC-P13-09 | Notificação com `DSC_SITUACAO = 'ERRO'` de execução anterior | Job P13-D executa | E-mail reenviado; se sucesso `→ 'ENVIADO'`; se falha permanece `→ 'ERRO'` |
| TC-P13-10 | Rotina executa duas vezes no mesmo dia (re-execução manual) | Job P13-B executa | Segunda execução não gera duplicatas — baseline `dataBase` avança para a primeira conclusão |
| TC-P13-11 | Licenciamento com 1 APPCI: RT tipo `PROJETO_EXECUCAO` + RT tipo `RENOVACAO_APPCI` | Job P13-B executa | Somente RT com `PROJETO_EXECUCAO` é notificado |
| TC-P13-12 | Licenciamento com múltiplos APPCIs: RT tipo `RENOVACAO_APPCI` | Job P13-B executa | Somente RT com `RENOVACAO_APPCI` é notificado |
| TC-P13-13 | Destinatário com `DSC_DESTINATARIO = NULL` | Job P13-D executa | Log de aviso; `DSC_SITUACAO` não é alterado; job não interrompido |
| TC-P13-14 | `TB_ROTINA` sem registro de `GERAR_NOTIFICACAO_ALVARA_VENCIDO` | Job P13-B executa pela primeira vez | `dataBase` calculado como `SYSDATE - 1`; notificações do dia anterior processadas |
| TC-P13-15 | Arquivo CNAB 240 já processado no diretório de retorno | Job P13-E executa | Arquivo ignorado; não reprocessado |
