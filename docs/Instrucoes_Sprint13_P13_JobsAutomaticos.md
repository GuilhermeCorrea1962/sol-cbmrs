# Sprint 13 — P13 Jobs Automáticos de Alvarás

**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Sprint:** 13 — Processo P13
**Data de criacao:** 2026-04-01
**Script principal:** `C:\SOL\infra\scripts\sprint13-deploy.ps1`

---

## 1. Contexto do processo P13

O processo P13 e o conjunto de **jobs automaticos agendados** do sistema SOL responsaveis por gerenciar o ciclo de vida dos alvaras (APPCIs) e disparar as notificacoes de vencimento. Diferentemente dos processos P01–P12, o P13 **nao possui interacao humana direta** — e um processo daemon que executa em background, acionado pelo Spring Scheduler.

O P13 substitui o `EJBTimerService` da stack Java EE original pelo mecanismo `@Scheduled` do Spring Boot 3.

### Jobs implementados

| Job | Agendamento | Responsabilidade |
|---|---|---|
| **P13-A** | Diario 00:01 | Detecta `APPCI_EMITIDO` com `dtValidadeAppci <= hoje` e transiciona para `ALVARA_VENCIDO` |
| **P13-B** | Diario 00:01 | Notifica envolvidos 90, 59 e 29 dias antes do vencimento do alvara |
| **P13-C** | Diario 00:01 | Notifica envolvidos quando o alvara venceu no intervalo recente |
| **P13-D** | Diario 00:31 | Verificacao de notificacoes pendentes (stub — EmailService e assincrono) |
| **P13-E** | A cada 12h | Verificacao de pagamento Banrisul CNAB 240 (stub — nao implementado) |

### Novo status adicionado

| Status | Predecessor | Descricao |
|---|---|---|
| `ALVARA_VENCIDO` | `APPCI_EMITIDO` | Licenciamento com APPCI expirado; aguardando renovacao (P14) |

### Novos TipoMarco adicionados

| Marco | Registrado em | Descricao |
|---|---|---|
| `NOTIFICACAO_SOLICITAR_RENOVACAO_90` | P13-B | Notificacao 90 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59` | P13-B | Notificacao 59 dias antes do vencimento |
| `NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29` | P13-B | Notificacao 29 dias antes do vencimento |
| `NOTIFICACAO_ALVARA_VENCIDO` | P13-C | Notificacao apos o vencimento do alvara (idempotente) |

---

## 2. Arquivos criados/modificados nesta sprint

### 2.1 `StatusLicenciamento.java` (MODIFICADO)

**Alteracao:** adicionado valor `ALVARA_VENCIDO` apos `APPCI_EMITIDO`.

**Necessidade:** P13-A transiciona o licenciamento de `APPCI_EMITIDO` para `ALVARA_VENCIDO` quando o `dtValidadeAppci` expira. Sem este estado, nao ha como distinguir um licenciamento com alvara vigente de um com alvara expirado esperando renovacao. O estado e terminal para o ciclo atual e precede o processo de renovacao P14.

**Compatibilidade:** O valor e armazenado como `VARCHAR2` no Oracle. Adicionar um novo valor ao enum nao requer DDL — a coluna ja aceita qualquer string dentro do tamanho definido.

### 2.2 `TipoMarco.java` (MODIFICADO)

**Alteracao:** adicionados 4 valores de notificacao de alvara na secao P13.

**Necessidade:** O sistema de rastreabilidade exige que cada evento automatico significativo seja registrado como um marco. As notificacoes de 90/59/29 dias e a notificacao pos-vencimento sao eventos distintos, cada um com semantica propria, assunto de e-mail diferente e necessidade de controle de idempotencia (RN-129).

### 2.3 `LicenciamentoRepository.java` (MODIFICADO)

**Alteracao:** adicionadas 3 queries que retornam `List<Long>` (IDs) em vez de entidades completas:
- `findAppciVencidosIds(LocalDate hoje)` — P13-A
- `findAppciAVencerIds(LocalDate dataAlvo)` — P13-B
- `findAlvaresVencidosParaNotificacaoIds(LocalDate inicio, LocalDate fim)` — P13-C

**Necessidade:** Os jobs processam cada licenciamento em uma transacao separada (`@Transactional` por item, chamado de bean externo para garantir proxy Spring). Passar o ID (e nao o objeto JPA) evita `LazyInitializationException` ao acessar relacionamentos `FetchType.LAZY` fora da transacao que buscou a lista. O metodo `@Transactional` re-carrega o licenciamento pelo ID dentro de uma nova sessao JPA.

### 2.4 `RotinaExecucao.java` (NOVO)

**Tabela Oracle:** `SOL.ROTINA_EXECUCAO`
**Sequence Oracle:** `SOL.SEQ_ROTINA_EXECUCAO` (criada no Passo 0c do script)

Campos principais:

| Campo | Tipo | Descricao |
|---|---|---|
| `tipoRotina` | String(60) | Nome da rotina (ex.: `GERAR_NOTIFICACAO_ALVARA_VENCIDO`) |
| `dataInicioExecucao` | LocalDateTime | Quando o job iniciou |
| `dataFimExecucao` | LocalDateTime | Quando o job concluiu (baseline para P13-B/C — RN-140) |
| `situacao` | String(15) | `EM_EXECUCAO` / `CONCLUIDA` / `ERRO` |
| `numProcessados` | Integer | Itens processados com sucesso |
| `numErros` | Integer | Itens com falha |
| `mensagemErro` | String(2000) | Descricao do erro principal, se houver |

**Necessidade:** RN-140 exige que a data de ultima execucao bem-sucedida seja usada como baseline temporal para calcular as janelas de notificacao de P13-B e P13-C. Sem este controle, em caso de downtime do servidor a rotina perderia o historico de quando executou pela ultima vez, podendo pular ou duplicar notificacoes.

**Criacao automatica da tabela:** O Hibernate com `ddl-auto: update` cria a tabela `ROTINA_EXECUCAO` automaticamente na primeira inicializacao do servico. A sequence, contudo, precisa existir ANTES do startup — por isso o Passo 0c do script a cria via sqlplus.

### 2.5 `RotinaExecucaoRepository.java` (NOVO)

Repository Spring Data JPA com metodo derivado:
```java
Optional<RotinaExecucao> findTopByTipoRotinaAndSituacaoOrderByDataFimExecucaoDesc(
    String tipoRotina, String situacao);
```

Retorna a ultima rotina concluida para um tipo, sem JPQL customizado.

### 2.6 `AlvaraVencimentoService.java` (NOVO)

Servico de negocio do P13. Separado do `AlvaraJobService` (agendador) para garantir isolamento transacional correto.

**Por que dois beans separados (AlvaraVencimentoService + AlvaraJobService)?**

O Spring AOP aplica transacoes apenas em chamadas que passam pelo proxy do bean. Se os metodos `@Transactional` e o loop estivessem no mesmo bean (`AlvaraJobService`), a auto-invocacao (`this.metodoTransacional()`) bypassaria o proxy, anulando o `@Transactional`. Com dois beans, `AlvaraJobService` chama `alvaraVencimentoService.atualizarAlvaraVencido(id)` pelo proxy, e a transacao e aplicada corretamente a cada item.

Este e o mesmo padrao do `BoletoJobService` (Sprint 11) que chama `BoletoService.vencerBoleto()`.

Metodos publicos do `AlvaraVencimentoService`:

| Metodo | Transacao | Descricao |
|---|---|---|
| `buscarAlvarasVencidosIds()` | readOnly | Retorna IDs para P13-A |
| `atualizarAlvaraVencido(Long licId)` | @Transactional (write) | Transiciona APPCI_EMITIDO -> ALVARA_VENCIDO |
| `buscarDataBaseRotina()` | readOnly | Retorna baseline temporal (RN-140) |
| `buscarAlvarasAVencerIds(dataBase, dias)` | readOnly | Retorna IDs para P13-B |
| `registrarNotificacaoVencimento(licId, marco, dias)` | @Transactional (write) | Marco + e-mail P13-B |
| `buscarAlvaresVencidosParaNotificacaoIds(dataBase)` | readOnly | Retorna IDs para P13-C |
| `registrarNotificacaoAlvaraVencido(Long licId)` | @Transactional (write) | Marco + e-mail P13-C (idempotente) |
| `iniciarRotina()` | @Transactional (write) | Cria RotinaExecucao com status EM_EXECUCAO |
| `finalizarRotina(id, ok, err, msg)` | @Transactional (write) | Atualiza RotinaExecucao com resultado |

### 2.7 `AlvaraJobService.java` (NOVO)

Agendador Spring com 3 metodos `@Scheduled`. Nao tem logica de negocio — apenas:
1. Chama `alvaraVencimentoService.buscar*Ids()` para obter a lista de IDs
2. Itera a lista chamando o metodo transacional correspondente por item
3. Conta sucessos e erros
4. Chama `iniciarRotina()` antes e `finalizarRotina()` ao final

Os jobs P13-D (verificacao de notificacoes pendentes) e P13-E (CNAB Banrisul) estao como stubs com `log.info(...)`.

### 2.8 `AlvaraAdminController.java` (NOVO)

Endpoint REST exclusivo para testes e manutencao:

| Endpoint | Roles | Comportamento |
|---|---|---|
| `POST /admin/jobs/rotina-alvara` | `ADMIN`, `CHEFE_SSEG_BBM` | Dispara P13-A + P13-B + P13-C de forma sincrona |

**Por que e necessario:** Os jobs agendados executam as 00:01, tornando o teste em horario comercial impossivel sem este endpoint. Em producao, o endpoint tambem permite reprocessamento manual em caso de falha na execucao noturna.

---

## 3. DDL Oracle necessario

A unica acao DDL manual necessaria e a criacao da sequence `SOL.SEQ_ROTINA_EXECUCAO`. O script executa isso automaticamente no Passo 0c. Caso o sqlplus nao esteja disponivel, execute manualmente antes de iniciar o servico:

```sql
CREATE SEQUENCE SOL.SEQ_ROTINA_EXECUCAO
    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
```

A tabela `SOL.ROTINA_EXECUCAO` e criada automaticamente pelo Hibernate na primeira inicializacao do servico apos o build (`ddl-auto: update` no `application.yml`).

---

## 4. Estrutura do script `sprint13-deploy.ps1`

### Passo 0a — MailHog

**O que faz:** Verifica/inicia o MailHog na porta 1025.

**Por que e necessario:** `AlvaraVencimentoService` chama `EmailService.notificarAsync()` ao registrar marcos de notificacao (P13-B/C). O Spring Mail verifica a conectividade SMTP no startup; sem MailHog ativo, o health check retorna `DOWN`.

### Passo 0b — Parar servico SOL-Backend

**O que faz:** Para o servico Windows `SOL-Backend` antes do `mvn clean package`.

**Por que e necessario:** No Windows, o JAR em execucao e bloqueado pelo sistema operacional. O `mvn clean` falha ao tentar deletar o diretorio `target/` com o JAR em uso.

### Passo 0c — Criar sequence Oracle

**O que faz:** Executa um bloco PL/SQL que cria `SOL.SEQ_ROTINA_EXECUCAO` somente se ela nao existir.

**Por que e necessario:** O Hibernate com `ddl-auto: update` cria tabelas e indices automaticamente, mas **nao cria sequences Oracle**. A entidade `RotinaExecucao` usa `@SequenceGenerator` com `SOL.SEQ_ROTINA_EXECUCAO`. Se a sequence nao existir quando o JPA tentar inserir o primeiro registro, ocorre `ORA-02289: sequence does not exist`. Este passo previne a falha.

**Seguranca:** O bloco PL/SQL verifica `all_sequences` antes de criar — nao falha se a sequence ja existir.

### Passo 1 — Build Maven

**O que faz:** Executa `mvn clean package -DskipTests -q` com o JDK correto.

**Por que e necessario:** Compila todos os 8 arquivos novos/modificados desta sprint e os empacota no JAR do backend.

### Passo 2 — Restart do servico

**O que faz:** Reinicia o servico `SOL-Backend` e aguarda 20 segundos para o Spring inicializar.

**Detalhe importante:** Na primeira inicializacao apos esta sprint, o Hibernate cria a tabela `ROTINA_EXECUCAO`. Isso pode levar alguns segundos extras — por isso o health check no Passo 3 tem 15 tentativas (vs. 12 nas sprints anteriores).

### Passo 3 — Health check

**O que faz:** Chama `GET /actuator/health` em loop ate receber `{"status":"UP"}` (15 tentativas, 5 segundos cada = 75 segundos maximo).

### Passo 4 — Autenticacao

**O que faz:** Obtem o token JWT do `sol-admin` para os proximos passos.

### Passo 5 — Setup de dados de teste

**O que faz:** 2 sub-passos:
1. Cria um licenciamento via `POST /licenciamentos` (status `RASCUNHO`, area 350m²)
2. Via sqlplus: promove para `APPCI_EMITIDO` com `DT_VALIDADE_APPCI = SYSDATE - 1` (vencido ontem)

**Por que via sqlplus e nao via API?** O caminho natural `RASCUNHO → ANALISE_PENDENTE → EM_ANALISE → ... → APPCI_EMITIDO` requer P03 + P04 + P07 + P08, o que levaria varios minutos e envolveria multiplos endpoints. Para o smoke test, o acesso direto ao banco e justificado.

**Por que area 350m²?** Distingue os registros de teste dos dados reais para facilitar limpeza.

### Passo 6 — Disparar rotina P13

**O que faz:** Chama `POST /admin/jobs/rotina-alvara` com o token de administrador.

**Por que e sincrono:** A execucao e sincrona no thread HTTP — a resposta e retornada apenas apos P13-A + P13-B + P13-C completarem. Em bases com muitos licenciamentos APPCI_EMITIDO, pode levar ate 2 minutos. O timeout do `Invoke-RestMethod` esta configurado para 120 segundos.

**O que o job faz internamente:**
1. `iniciarRotina()` — insere em `ROTINA_EXECUCAO` com `EM_EXECUCAO`
2. P13-A: busca IDs com `findAppciVencidosIds(hoje)` — inclui o licenciamento de teste (vencido ontem)
3. Para o licenciamento de teste: chama `atualizarAlvaraVencido(id)` — muda status para `ALVARA_VENCIDO`
4. P13-B: busca APPCIs a vencer em 90/59/29 dias — nenhum resultado esperado (so temos um vencido, nao a vencer)
5. P13-C: busca `ALVARA_VENCIDO` com `dtValidadeAppci >= ontem` — inclui o licenciamento de teste
6. Para o licenciamento de teste: chama `registrarNotificacaoAlvaraVencido(id)` — marco + e-mail async
7. `finalizarRotina()` — atualiza `ROTINA_EXECUCAO` com `CONCLUIDA`

### Passo 7 — Verificar transicao P13-A

**O que faz:** Chama `GET /licenciamentos/{id}` e verifica que `status == "ALVARA_VENCIDO"`.

**Criterio de sucesso:** Status mudou de `APPCI_EMITIDO` para `ALVARA_VENCIDO`.

### Passo 8 — Verificar marco P13-C

**O que faz:** Chama `GET /licenciamentos/{id}/marcos` e verifica que o marco `NOTIFICACAO_ALVARA_VENCIDO` existe.

**Criterio de sucesso:** Marco presente com observacao que menciona a data de validade.

### Passo 9 — Verificar idempotencia RN-129

**O que faz:** Dispara a rotina P13 uma segunda vez e verifica que:
1. O marco `NOTIFICACAO_ALVARA_VENCIDO` aparece exatamente 1 vez (nao duplicado)
2. O status permanece `ALVARA_VENCIDO` (P13-A nao reprocessa — RN-121)

**Por que e necessario:** RN-129 exige que `NOTIFICACAO_ALVARA_VENCIDO` seja registrado apenas uma vez por licenciamento, mesmo que o job execute multiplas vezes. O `AlvaraVencimentoService.registrarNotificacaoAlvaraVencido()` usa `marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco()` para verificar antes de inserir.

### Passo 10 — Verificar RotinaExecucao no banco

**O que faz:** Executa um `SELECT` em `SOL.ROTINA_EXECUCAO` via sqlplus e exibe as ultimas 5 execucoes.

**O que deve aparecer:** 2 registros com `TIPO_ROTINA = 'GERAR_NOTIFICACAO_ALVARA_VENCIDO'` e `DSC_SITUACAO = 'CONCLUIDA'` (um para cada disparo do Passo 6 e Passo 9).

### Passo 11 — Limpeza

**O que faz:** Remove o licenciamento de teste e todos os seus marcos/rotinas via sqlplus.

---

## 5. Como executar

### Pre-requisitos

- Servidor com Windows Server + PowerShell 5.1
- Oracle XE em `localhost:1521/XEPDB1` com usuario `sol`/`Sol@CBM2026`
- **sqlplus disponivel no PATH** (obrigatorio para Passo 0c, 5, 10 e 11)
- MailHog em `C:\SOL\infra\mailhog\MailHog.exe`
- Servico `SOL-Backend` configurado

### Comando de execucao

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\SOL\infra\scripts\sprint13-deploy.ps1
```

### Duracao estimada

Aproximadamente **5 a 7 minutos** (inclui criacao de sequence, DDL da tabela no startup, e 2 execucoes da rotina P13).

---

## 6. Saida esperada (SUMARIO)

```
==> SUMARIO

  Sprint 13 - P13 Jobs Automaticos de Alvaras concluida com sucesso.

  Arquivos modificados:
    [M] entity/enums/StatusLicenciamento.java    : + ALVARA_VENCIDO
    [M] entity/enums/TipoMarco.java              : + 4 marcos de notificacao P13
    [M] repository/LicenciamentoRepository.java  : + 3 queries ID-based para P13

  Arquivos criados:
    [N] entity/RotinaExecucao.java               : entidade de rastreabilidade de execucao
    [N] repository/RotinaExecucaoRepository.java : repositorio de RotinaExecucao
    [N] service/AlvaraVencimentoService.java     : logica de negocio P13-A/B/C
    [N] service/AlvaraJobService.java            : agendador @Scheduled P13-A/B/C/D/E
    [N] controller/AlvaraAdminController.java    : endpoint admin para disparo manual

  DDL Oracle:
    Sequence SOL.SEQ_ROTINA_EXECUCAO criada (Passo 0c)
    Tabela SOL.ROTINA_EXECUCAO criada pelo Hibernate (ddl-auto:update no startup)

  Endpoint de teste:
    POST /admin/jobs/rotina-alvara  (ADMIN, CHEFE_SSEG_BBM)

  Jobs agendados:
    P13-A/B/C: 00:01 diario  (cron: 0 1 0 * * *)
    P13-D:     00:31 diario  (cron: 0 31 0 * * *)
    P13-E:     a cada 12h   (cron: 0 0 */12 * * *)  -- stub

  Fluxos validados:
    P13-A: APPCI_EMITIDO + dtValidadeAppci vencida => ALVARA_VENCIDO
    P13-C: Marco NOTIFICACAO_ALVARA_VENCIDO registrado
    RN-121: P13-A nao reprocessa licenciamento ja ALVARA_VENCIDO
    RN-129: Marco NOTIFICACAO_ALVARA_VENCIDO nao duplicado (idempotente)
```

---

## 7. Possiveis problemas e solucoes

| Problema | Causa provavel | Solucao |
|---|---|---|
| `ORA-02289: sequence does not exist` no startup | Sequence nao criada antes do build | Executar Passo 0c manualmente antes de iniciar o servico |
| Build falha com "Access denied" no clean | JAR ainda em uso (servico nao parou) | Verificar Passo 0b; parar servico manualmente |
| Health retorna DOWN | MailHog nao rodando | Verificar Passo 0a; iniciar MailHog manualmente |
| `POST /admin/jobs/rotina-alvara` retorna 403 | Token nao tem papel ADMIN | Verificar credenciais em `$AdminUser`/`$AdminPass` |
| Status nao muda para ALVARA_VENCIDO (Passo 7) | dtValidadeAppci nao foi atualizado no Passo 5 | Verificar se sqlplus executou o UPDATE; checar diretamente no banco |
| Tabela ROTINA_EXECUCAO nao criada | Hibernate nao detectou a nova entidade | Verificar se `RotinaExecucao.java` esta no pacote correto (`entity`) |
| `NullPointerException` em `notificarEnvolvidos` | Licenciamento de teste sem RT/RU | Esperado — EmailService loga WARN e continua (RN-128) |

---

## 8. Rastreabilidade — Regras de Negocio implementadas

| Codigo | Descricao | Implementacao |
|---|---|---|
| RN-121 | Apenas `APPCI_EMITIDO` e elegivel para P13-A | Guard `status != APPCI_EMITIDO` em `atualizarAlvaraVencido` |
| RN-122 | Criterio: `dtValidadeAppci <= hoje` | Query `findAppciVencidosIds` com `<= :hoje` |
| RN-125 | Notificacao 90d: `dtValidadeAppci == dataBase + 90` | Query `findAppciAVencerIds` com `= :dataAlvo` |
| RN-126 | Notificacoes 59d e 29d: mesma logica de RN-125 | Mesmo metodo com dias diferentes |
| RN-127 | Licenciamentos em renovacao nao recebem notificacao | Query filtra apenas `APPCI_EMITIDO` (renovacoes tem outro status) |
| RN-128 | Destinatario invalido: log WARN; job nao interrompido | `EmailService.notificarAsync` ja trata null/blank |
| RN-129 | `NOTIFICACAO_ALVARA_VENCIDO` registrado apenas 1 vez | `marcoProcessoRepository.existsByLicenciamentoIdAndTipoMarco()` |
| RN-137 | Cron em fuso America/Sao_Paulo | Servidor configurado com timezone local; `@Scheduled` usa TZ da JVM |
| RN-139 | Cada licenciamento processado em transacao independente | Chamada de bean externo (AlvaraJobService -> AlvaraVencimentoService via proxy Spring) |
| RN-140 | Data de ultima execucao como baseline | `RotinaExecucaoRepository.findTopBy...OrderByDataFimExecucaoDesc` |

---

## 9. Estado do projeto apos Sprint 13

| Processo | BPMN | Req. Stack Atual | Req. Java Moderna | Descritivo | Implementacao |
|---|---|---|---|---|---|
| P11 Pagamento Boleto | ✅ | ✅ | ✅ | ✅ | ✅ Sprint 11 |
| P12 Extincao Licenciamento | ✅ | ✅ | ✅ | ✅ | ✅ Sprint 12 |
| P13 Jobs Automaticos | ✅ | ✅ | ✅ | ✅ | ✅ Sprint 13 |
| P14 Renovacao Licenciamento | ✅ | ✅ | pendente | ✅ | pendente |

### Pendencias do P13 para sprints futuras

| Item | Descricao |
|---|---|
| P13-D completo | Fila persistente `TB_LICENCIAMENTO_NOTIFICACAO` com reenvio de e-mails com falha |
| P13-E completo | Integracao CNAB 240 Banrisul (leitura de arquivo de retorno) |
| P13-F | Job de suspensao automatica por CIA (6 meses sem movimentacao — `SUSPENSAO_AUTOMATICA`) |
| P13-G | Job de cancelamento automatico por `SUSPENSO` prolongado — `CANCELAMENTO_AUTOMATICO` |
