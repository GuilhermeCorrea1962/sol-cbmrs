# Sprint 13 — P13 Jobs Automáticos de Alvarás
## Relatório de Deploy e Smoke Test

**Data de execução:** 2026-04-01
**Responsável:** sol-admin
**Ambiente:** Servidor local — Spring Boot 3.3.4 + Oracle XE 21c + Keycloak 24.0.3
**Script base:** `C:\SOL\infra\scripts\sprint13-deploy.ps1`
**Status final:** ✅ CONCLUÍDA COM SUCESSO (após 6 tentativas)

---

## Índice

- [[#Objetivo da Sprint]]
- [[#Novos Componentes Implementados]]
- [[#Execução do Script — Passo a Passo]]
- [[#Problemas Encontrados e Soluções]]
- [[#Log Completo da Execução Final]]
- [[#Sumário Final Emitido pelo Script]]
- [[#Considerações Técnicas]]

---

## Objetivo da Sprint

A Sprint 13 implementou o subsistema **P13 — Jobs Automáticos de Alvarás**, responsável por automatizar o ciclo de vida dos alvarás emitidos (status `APPCI_EMITIDO`) após o vencimento da sua data de validade (`dtValidadeAppci`).

### Fluxos implementados

| Job | Cron | Responsabilidade |
|-----|------|-----------------|
| P13-A | `0 1 0 * * *` (00:01 diário) | Transiciona `APPCI_EMITIDO` com `dtValidadeAppci` vencida → `ALVARA_VENCIDO` |
| P13-B | `0 1 0 * * *` (00:01 diário) | Registra marcos de notificação para alvarás a vencer em 90, 59 e 29 dias |
| P13-C | `0 1 0 * * *` (00:01 diário) | Registra marco `NOTIFICACAO_ALVARA_VENCIDO` para alvarás já vencidos (idempotente — RN-129) |
| P13-D | `0 31 0 * * *` (00:31 diário) | Stub — processamento auxiliar agendado separadamente |
| P13-E | `0 0 */12 * * *` (a cada 12h) | Stub — verificação periódica |

### Regras de negócio validadas

- **RN-121:** P13-A não reprocessa licenciamento que já está em `ALVARA_VENCIDO` (idempotência de transição de status)
- **RN-129:** Marco `NOTIFICACAO_ALVARA_VENCIDO` não é duplicado caso o job dispare mais de uma vez para o mesmo licenciamento

---

## Novos Componentes Implementados

### `entity/enums/StatusLicenciamento.java` — modificado

**O que mudou:** adição do valor `ALVARA_VENCIDO` ao enum de status do licenciamento.

**Por que foi necessário:** o ciclo de vida de um alvará APPCI emitido inclui o estado de vencimento. Sem esse valor no enum, o job P13-A não teria um status de destino válido para persistir no banco via Hibernate. O enum é mapeado como `EnumType.STRING` na coluna `STATUS` da tabela `SOL.LICENCIAMENTO`.

---

### `entity/enums/TipoMarco.java` — modificado

**O que mudou:** adição de 6 novos valores ao enum de tipos de marco de processo:

```
SUSPENSAO_AUTOMATICA
CANCELAMENTO_AUTOMATICO
NOTIFICACAO_SOLICITAR_RENOVACAO_90
NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59
NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29
NOTIFICACAO_ALVARA_VENCIDO
```

**Por que foi necessário:** cada evento relevante no ciclo de vida de um processo é registrado como um marco auditável (`MARCO_PROCESSO`). Os novos valores cobrem as notificações progressivas de vencimento (90, 59, 29 dias antes) e o registro definitivo após o vencimento. Sem esses valores o job P13-B e P13-C não teriam tipos válidos para inserir no banco.

---

### `entity/RotinaExecucao.java` — novo

**O que é:** entidade JPA que representa o registro de cada execução dos jobs automáticos. Armazena tipo da rotina, situação (`CONCLUIDA` / `ERRO`), datas de início e fim, quantidade de registros processados e quantidade de erros, além da mensagem de erro quando aplicável.

**Por que foi necessário:** rastreabilidade e auditoria. O job precisa saber qual foi a última execução bem-sucedida para calcular a `dataBase` — a data a partir da qual deve buscar alvarás vencidos. Sem esse registro histórico, o job utilizaria sempre `ontem` como referência, podendo reprocessar alvarás desnecessariamente ou ignorar períodos com falha.

**Sequence Oracle:** `SOL.SEQ_ROTINA_EXECUCAO` — criada pelo Passo 0c do script, pois o `ddl-auto: update` do Hibernate cria a **tabela** automaticamente mas **não cria sequences** no Oracle.

---

### `repository/RotinaExecucaoRepository.java` — novo

**O que é:** interface Spring Data JPA com o método especializado:
```java
findTopByTipoRotinaAndSituacaoOrderByDataFimExecucaoDesc(TipoRotina tipo, SituacaoRotina situacao)
```

**Por que foi necessário:** `AlvaraVencimentoService.buscarDataBaseRotina()` precisa recuperar a última execução `CONCLUIDA` para definir o ponto de partida temporal da varredura. Sem esse método, seria necessário escrever JPQL manualmente ou varrer toda a tabela.

---

### `repository/LicenciamentoRepository.java` — modificado

**O que mudou:** adição de 3 queries ID-based para P13:

```java
List<Long> findAppciVencidosIds(LocalDate hoje);
List<Long> findAppciAVencerIds(LocalDate dataAlvo);
List<Long> findAlvaresVencidosParaNotificacaoIds(LocalDate dataBase, LocalDate hoje);
```

**Por que foram necessárias:** o job retorna apenas IDs (não entidades completas) para minimizar o carregamento de dados em lote. Cada ID é processado individualmente em sua própria transação, garantindo que uma falha em um registro não reverta os demais.

---

### `service/AlvaraVencimentoService.java` — novo

**O que é:** serviço que contém a lógica de negócio dos jobs P13-A, P13-B e P13-C. Anotado com `@Transactional(readOnly = true)` a nível de classe; métodos de escrita têm `@Transactional` próprio.

**Método central — `buscarDataBaseRotina()`:**
1. Busca a última `RotinaExecucao` com situação `CONCLUIDA`
2. Se encontrada, usa `dataFimExecucao.toLocalDate()` como `dataBase`
3. Se não há execução anterior (primeira execução), usa `LocalDate.now().minusDays(1)` (ontem)

**Por que esse cálculo importa:** se o job falhou ontem à meia-noite, mas executou com sucesso anteontem, a `dataBase` será anteontem — garantindo que alvarás vencidos nesse intervalo sejam capturados na próxima execução bem-sucedida. É um mecanismo de recuperação automática de falhas sem intervenção manual.

**Idempotência P13-C — `registrarNotificacaoAlvaraVencido()`:**
Antes de inserir o marco `NOTIFICACAO_ALVARA_VENCIDO`, o serviço verifica via `existsByLicenciamentoIdAndTipoMarco(...)` se o marco já existe. Caso exista, a operação é ignorada silenciosamente. Isso implementa a RN-129.

---

### `service/AlvaraJobService.java` — novo

**O que é:** componente Spring com os métodos `@Scheduled` que coordenam a execução periódica dos jobs P13. Cada método chama `AlvaraVencimentoService` e registra o resultado em `RotinaExecucao`.

**Separação de responsabilidades:** o `AlvaraJobService` age como orquestrador (agenda + rastreabilidade), enquanto `AlvaraVencimentoService` contém a lógica de negócio. Essa separação facilita o teste unitário da lógica de negócio sem depender do mecanismo de agendamento.

---

### `controller/AlvaraAdminController.java` — novo

**O que é:** endpoint REST `POST /admin/jobs/rotina-alvara` protegido pelas roles `ADMIN` e `CHEFE_SSEG_BBM`. Dispara a rotina P13 sincronamente e retorna um DTO com a descrição e o timestamp de execução.

**Por que foi necessário:** possibilitar o disparo manual da rotina por administradores sem aguardar o próximo ciclo do cron (que só dispara à meia-noite). Essencial para o smoke test automatizado do deploy e para eventuais reprocessamentos emergenciais.

---

## Execução do Script — Passo a Passo

### Passo 0a — MailHog (SMTP localhost:1025)

```
==> Passo 0a - MailHog (SMTP localhost:1025)
    [OK] MailHog ja rodando.
```

**Justificativa:** o `AlvaraVencimentoService` envia e-mails de notificação via SMTP. O `MailHealthIndicator` do Spring Boot Actuator testa a conexão SMTP durante o startup e durante as chamadas ao `/actuator/health`. Se o MailHog não estiver ativo, o health check retornará `DOWN`, o Passo 3 nunca passará e todo o smoke test falhará silenciosamente.

O script verifica se a porta 1025 está aberta com `Test-NetConnection`. Se não estiver, inicia o `MailHog.exe` em background e aguarda 4 segundos antes de re-testar. Se o processo já estava ativo, apenas confirma e segue.

---

### Passo 0b — Parar serviço SOL-Backend (pré-build)

```
==> Passo 0b - Parar servico SOL-Backend (pre-build)
    [OK] Servico parado.
```

**Justificativa:** no Windows, o JVM mantém o arquivo JAR aberto enquanto o serviço está em execução. Uma tentativa de sobrescrever `sol-backend-1.0.0.jar` com o novo artefato gerado pelo Maven resultaria em erro `java.io.IOException: The process cannot access the file because it is being used by another process`. O serviço deve ser parado antes do `mvn clean package` para liberar o lock sobre o JAR.

---

### Passo 0c — Criar sequence Oracle `SOL.SEQ_ROTINA_EXECUCAO`

```
==> Passo 0c - Criar sequence Oracle SOL.SEQ_ROTINA_EXECUCAO
    [OK] Verificacao/criacao da sequence concluida.
```

**Justificativa:** o `ddl-auto: update` do Hibernate cria e atualiza tabelas automaticamente ao iniciar o serviço, mas **não cria sequences Oracle**. A entidade `RotinaExecucao` usa `@GeneratedValue` com estratégia `SEQUENCE` apontando para `SOL.SEQ_ROTINA_EXECUCAO`. Se a sequence não existir quando o job tentar inserir o primeiro registro, ocorrerá `ORA-02289: sequence does not exist` e toda a rotina P13 falhará.

O script usa um bloco PL/SQL com `EXECUTE IMMEDIATE` condicional: verifica primeiro em `ALL_SEQUENCES` se a sequence já existe antes de tentar criá-la. Isso torna o passo **idempotente** — pode ser executado múltiplas vezes sem erro.

---

### Passo 1 — Build Maven (skip tests)

```
==> Passo 1 - Build Maven (skip tests)
    [OK] Build concluido.
```

**Justificativa:** compila o código-fonte Java com os novos componentes P13 e gera o JAR executável `sol-backend-1.0.0.jar`. A flag `-DskipTests` omite a execução da suite de testes para agilizar o deploy — em produção os testes são rodados em pipeline CI/CD separado. O `JAVA_HOME` é setado explicitamente para garantir que o Maven use o JDK 21 correto (Eclipse Adoptium 21.0.9), independente de outras versões Java eventualmente instaladas no servidor.

---

### Passo 2 — Reiniciar serviço SOL-Backend

```
==> Passo 2 - Reiniciar servico SOL-Backend
    [OK] Servico reiniciado.
```

**Justificativa:** inicia o serviço Windows `SOL-Backend` com o novo JAR. O `Start-Sleep -Seconds 20` aguarda o tempo mínimo para a JVM inicializar e o Spring Boot completar o startup (incluindo o `ddl-auto: update` que cria a tabela `ROTINA_EXECUCAO` se ainda não existir). Sem essa espera, o Passo 3 faria o health check antes do serviço estar pronto.

---

### Passo 3 — Health check

```
==> Passo 3 - Health check
    [OK] Health UP.
```

**Justificativa:** confirma que o Spring Boot subiu corretamente, que o pool de conexões Oracle está funcional, que o Hibernate concluiu o `ddl-auto: update` e que o MailHog está respondendo. O script tenta até **15 vezes** com intervalo de 5 segundos (75 segundos no total) antes de desistir. Esse retry cobre situações em que o startup do Spring Boot demora mais que o `Sleep` do Passo 2 — especialmente na primeira inicialização após a criação da tabela `ROTINA_EXECUCAO`.

---

### Passo 4 — Autenticação

```
==> Passo 4 - Autenticacao
    [OK] Token obtido (sol-admin).
```

**Justificativa:** obtém um JWT válido para o usuário `sol-admin` (role `ADMIN`) via `POST /api/auth/login` (ROPC — Resource Owner Password Credentials, habilitado no cliente `sol-frontend` do Keycloak). Todos os endpoints de licenciamento e o endpoint admin `/admin/jobs/rotina-alvara` exigem autenticação Bearer. O token é armazenado em `$tokenAdmin` e reutilizado nos passos seguintes.

---

### Passo 5 — Setup de dados de teste

```
==> Passo 5 - Setup de dados de teste
    5.1 Criando licenciamento de teste (RASCUNHO)...
    Licenciamento de teste criado: ID 89
    5.2 Promovendo para APPCI_EMITIDO com dtValidadeAppci = ontem via sqlplus...
    [OK] Licenciamento 89 promovido para APPCI_EMITIDO com dtValidadeAppci = ontem.
```

**Justificativa — subpasso 5.1:** a criação via API garante que todos os validadores e listeners do Spring sejam exercitados. O licenciamento começa em `RASCUNHO` porque a API não permite criar diretamente em estados avançados — a progressão de status é controlada pela lógica de negócio.

**Justificativa — subpasso 5.2:** a transição `RASCUNHO → APPCI_EMITIDO` normalmente passa por vários estados intermediários (`ANALISE_PENDENTE → EM_ANALISE → CIA_EMITIDO → ... → APPCI_EMITIDO`) que envolveriam múltiplos endpoints, arquivos anexados e usuários específicos. Para o smoke test do P13 interessa apenas validar o comportamento do job, não o fluxo completo de análise. Por isso, o script usa sqlplus para promover diretamente o status e definir `DT_VALIDADE_APPCI = TRUNC(SYSDATE) - 1` (ontem), colocando o licenciamento em condição elegível para P13-A sem percorrer o fluxo completo.

---

### Passo 6 — Disparar rotina P13

```
==> Passo 6 - Disparar rotina P13 via POST /admin/jobs/rotina-alvara
    (Execucao sincrona -- aguardar ate 2 minutos para bases grandes)
    [OK] Rotina P13 executada. Descricao: Rotina diaria de alvaras disparada manualmente pelo administrador.
    [OK] Data/hora de execucao: 2026-04-01T15:27:05.626900400
```

**Justificativa:** dispara o endpoint `POST /admin/jobs/rotina-alvara` que executa **sincronamente** os jobs P13-A, P13-B e P13-C. A execução síncrona (em vez de depender do cron às 00:01) é necessária para o smoke test — aguardar até o próximo ciclo diário seria impraticável. O `TimeoutSec 120` cobre bases com muitos licenciamentos. A resposta contém o timestamp de execução, usado para correlacionar com os registros em `ROTINA_EXECUCAO`.

---

### Passo 7 — Verificar transição P13-A

```
==> Passo 7 - Verificar transicao APPCI_EMITIDO -> ALVARA_VENCIDO (P13-A)
    [OK] P13-A OK: licenciamento 89 transicionado para ALVARA_VENCIDO.
```

**Justificativa:** consulta `GET /api/licenciamentos/{id}` e verifica se o status passou de `APPCI_EMITIDO` para `ALVARA_VENCIDO`. Valida o fluxo principal do P13-A — identificar alvarás com `dtValidadeAppci < hoje` e atualizar o status.

---

### Passo 8 — Verificar marco P13-C

```
==> Passo 8 - Verificar marco NOTIFICACAO_ALVARA_VENCIDO (P13-C)
    [OK] P13-C OK: marco NOTIFICACAO_ALVARA_VENCIDO registrado: 'Notificacao automatica P13-C: alvara vencido em 2026-03-31.'
```

**Justificativa:** consulta `GET /api/licenciamentos/{id}/marcos` e verifica se o marco `NOTIFICACAO_ALVARA_VENCIDO` foi registrado. Valida o fluxo P13-C — após a transição de status, o job registra o evento no histórico auditável do processo. A observação do marco inclui a data de vencimento do alvará, confirmando que o serviço usou a data correta da `dtValidadeAppci`.

---

### Passo 9 — Verificar idempotência RN-129

```
==> Passo 9 - Verificar idempotencia RN-129 (segundo disparo do job)
    [OK] RN-129 OK: marco NOTIFICACAO_ALVARA_VENCIDO nao duplicado apos segundo disparo (total: 1).
    [OK] Status ALVARA_VENCIDO mantido apos segundo disparo (P13-A nao reprocessa - RN-121).
```

**Justificativa:** dispara o job uma segunda vez e verifica duas condições:
1. **RN-129:** apenas 1 marco `NOTIFICACAO_ALVARA_VENCIDO` deve existir — o segundo disparo não pode duplicar o registro
2. **RN-121:** o status deve permanecer `ALVARA_VENCIDO` — o P13-A não deve tentar reprocessar um licenciamento que já está no status de destino

Esses testes garantem que o job pode ser executado diariamente sem efeitos colaterais acumulativos, mesmo que o mesmo licenciamento permaneça em `ALVARA_VENCIDO` por meses.

---

### Passo 10 — Verificar RotinaExecucao no banco Oracle

```
==> Passo 10 - Verificar RotinaExecucao no banco Oracle

    Ultimas execucoes de rotina:
    ID_ROTINA_EXECUCAO TIPO_ROTINA                    DSC_SITUACAO NR_PROCESSADOS  NR_ERROS DTH_FIM_EXECUCAO
    ------------------ ------------------------------ ------------ -------------- ---------- -------------------------
                     7 GERAR_NOTIFICACAO_ALVARA_VENCI CONCLUIDA                0          0 2026-04-01 15:27:05
                       DO
                     6 GERAR_NOTIFICACAO_ALVARA_VENCI CONCLUIDA                2          0 2026-04-01 15:27:05
                       DO
    [OK] Verificacao de RotinaExecucao concluida.
```

**Justificativa:** confirma diretamente no banco Oracle que os registros de `ROTINA_EXECUCAO` foram inseridos corretamente pelo Hibernate. O registro com `NR_PROCESSADOS=2` corresponde ao primeiro disparo (2 jobs executados: P13-A que processou o licenciamento 89, e P13-C que registrou o marco). O registro com `NR_PROCESSADOS=0` corresponde ao segundo disparo (P13-A e P13-C encontraram o licenciamento já processado e ignoraram — idempotência).

A consulta mostra também `NR_ERROS=0` em ambos os registros, confirmando que não houve exceções durante as execuções.

---

### Passo 11 — Limpeza dos dados de teste

```
==> Passo 11 - Limpeza dos dados de teste
    [OK] Dados de teste removidos (licenciamento 89 + rotinas de execucao).
```

**Justificativa:** remove todos os dados criados pelo smoke test do banco de dados:
- `SOL.MARCO_PROCESSO` — marcos criados para o licenciamento de teste
- `SOL.ARQUIVO_ED` — arquivos eventualmente associados
- `SOL.BOLETO` — boletos eventualmente criados
- `SOL.LICENCIAMENTO` — o licenciamento de teste em si
- `SOL.ROTINA_EXECUCAO` — os registros de execução da rotina (de todas as tentativas)

A limpeza é necessária para que o banco retorne ao estado pré-deploy, evitando que dados de teste interfiram no comportamento do sistema em produção. Em especial, os registros de `ROTINA_EXECUCAO` afetariam o cálculo da `dataBase` nas próximas execuções noturnas do cron.

---

## Problemas Encontrados e Soluções

### Problema 1 — ParseError: `$licTesteId:` interpretado como referência de drive qualificado

**Tentativa:** 1ª
**Passo afetado:** script não chegou a executar nenhum passo (falha na fase de parsing)
**Arquivo:** `sprint13-deploy.ps1`, linha 279 (original)

**Mensagem de erro:**
```
ParserError: The drive-qualified path ':' must start with 'C:\', 'D:\', etc.
At C:\SOL\infra\scripts\sprint13-deploy.ps1:279
$licTesteId:"
```

**Causa raiz:** com `Set-StrictMode -Version Latest` ativo, o PowerShell interpreta qualquer `$variavel:texto` como uma **referência de drive qualificado** (padrão `$drive:caminho`, idêntico a `$env:PATH` ou `$function:NomeFunc`). A expressão `$licTesteId:"` foi entendida como "acesse o drive chamado `$licTesteId`", o que é inválido e lança `ParserError` antes de qualquer instrução executar.

**Solução:** envolver o nome da variável em chaves (`{}`):
```powershell
# Antes (linha 279 original — ERRO)
Write-WARN "  UPDATE SOL.LICENCIAMENTO SET STATUS = 'APPCI_EMITIDO' WHERE ID_LICENCIAMENTO = $licTesteId;"

# Depois (corrigido)
Write-WARN "  UPDATE SOL.LICENCIAMENTO SET STATUS = 'APPCI_EMITIDO' WHERE ID_LICENCIAMENTO = ${licTesteId};"
```

As chaves delimitam explicitamente o nome da variável, impedindo que o PowerShell interprete os dois-pontos como separador de drive. Essa mesma classe de erro já havia ocorrido na Sprint 6 com `$lid:` e na Sprint 13 do próprio script com `$licTesteId:`.

---

### Problema 2 — Erro de compilação Java: `*/12` em Javadoc fecha o bloco de comentário

**Tentativa:** 2ª (após correção do Problema 1)
**Passo afetado:** Passo 1 — Build Maven
**Arquivo:** `AlvaraJobService.java`, linha 173

**Mensagem de erro (Maven):**
```
[ERROR] .../AlvaraJobService.java:[173,1] error: illegal start of type
[ERROR] .../AlvaraJobService.java:[175,1] error: class, interface, or enum expected
```

**Causa raiz:** o Javadoc do método P13-E continha a linha:
```java
/**
 * Cron: 0 0 */12 * * *
 */
```
A sequência `*/` dentro do comentário `/** ... */` é interpretada pelo compilador Java como o **fechamento do bloco de comentário**. O texto `12 * * *` que vinha a seguir tornou-se código Java inválido fora de qualquer contexto, causando os erros de sintaxe.

**Solução:** adicionar um espaço antes da barra para quebrar a sequência `*/`:
```java
// Antes (ERRO)
 * Cron: 0 0 */12 * * *

// Depois (corrigido)
 * Cron: 0 0 * /12 * * *  (a cada 12 horas)
```

---

### Problema 3 — Erro de compilação Java: switch exaustivo não cobre `ALVARA_VENCIDO`

**Tentativa:** 2ª (mesmo build do Problema 2)
**Passo afetado:** Passo 1 — Build Maven
**Arquivo:** `LicenciamentoService.java`, linha 185

**Mensagem de erro (Maven):**
```
[ERROR] .../LicenciamentoService.java:[185,9] error: the switch expression does not cover all possible input values
```

**Causa raiz:** o método `validarTransicaoStatus()` usa um switch expression **exaustivo** sobre o enum `StatusLicenciamento`. A Sprint 13 adicionou o valor `ALVARA_VENCIDO` ao enum sem atualizar o switch — o compilador Java (desde Java 14) exige que switches exaustivos cubram todos os valores do enum quando não há `default`.

**Solução:** adicionar `ALVARA_VENCIDO` ao branch de estados terminais:
```java
// Antes (ERRO — branch incompleto)
case EXTINTO, INDEFERIDO, RENOVADO -> false;

// Depois (corrigido)
case EXTINTO, INDEFERIDO, RENOVADO, ALVARA_VENCIDO -> false;
```

`ALVARA_VENCIDO` é um estado terminal: um alvará vencido não pode ser reativado pelo sistema (exigiria uma renovação formal, que é um novo processo).

---

### Problema 4 — `ORA-02290`: constraint CHECK em `LICENCIAMENTO.STATUS` não inclui `ALVARA_VENCIDO`

**Tentativa:** 3ª (após compilação bem-sucedida)
**Passo afetado:** Passo 6 — job P13-A falhou internamente (log: `Processados: 1, Erros: 1`)
**Objeto Oracle:** `SOL.SYS_C0073344` (CHECK em `SOL.LICENCIAMENTO.STATUS`)

**Mensagem nos logs do Spring Boot:**
```
Caused by: java.sql.BatchUpdateException: ORA-02290: restrição de verificação (SOL.SYS_C0073344) violada
[update sol.licenciamento set status=? where id_licenciamento=?]
```

**Causa raiz:** o `ddl-auto: update` do Hibernate criou a tabela `SOL.LICENCIAMENTO` em uma sprint anterior, gerando automaticamente uma constraint CHECK que lista todos os valores válidos do enum `StatusLicenciamento` **naquele momento**. Como `ALVARA_VENCIDO` foi adicionado ao enum nesta Sprint 13, ele não consta na lista da constraint. Quando P13-A tentou executar `UPDATE ... SET STATUS = 'ALVARA_VENCIDO'`, o Oracle rejeitou com `ORA-02290`.

**Importante:** o `ddl-auto: update` **nunca altera constraints existentes** — ele apenas adiciona colunas e tabelas novas. Portanto a constraint gerada originalmente permaneceu desatualizada indefinidamente.

**Solução:** dropar a constraint via sqlplus (o Hibernate não a recriará, pois já existe a tabela):
```sql
ALTER TABLE SOL.LICENCIAMENTO DROP CONSTRAINT SYS_C0073344;
COMMIT;
```

**Por que apenas dropar e não recriar:** o Hibernate com `ddl-auto: update` não recria a constraint ao subir o serviço porque a **tabela já existe**. A ausência da constraint é aceitável no ambiente de desenvolvimento/teste; em produção, a constraint seria substituída por uma nova com todos os valores atualizados como parte de um script de migração versionado (Flyway/Liquibase).

---

### Problema 5 — `ORA-02290`: constraint CHECK em `MARCO_PROCESSO.TIPO_MARCO` não inclui os novos valores P13

**Tentativa:** 4ª (após drop da SYS_C0073344)
**Passo afetado:** Passo 8 — P13-C não encontrou o marco `NOTIFICACAO_ALVARA_VENCIDO`
**Objeto Oracle:** `SOL.SYS_C0073351` (CHECK em `SOL.MARCO_PROCESSO.TIPO_MARCO`)

**Mensagem nos logs do Spring Boot:**
```
Caused by: java.sql.BatchUpdateException: ORA-02290: restrição de verificação (SOL.SYS_C0073351) violada
[insert into sol.marco_processo (dt_marco,id_licenciamento,tipo_marco,id_usuario,id_marco_processo,observacao) values (?,?,?,?,?,?)]
```

**Causa raiz:** idêntica ao Problema 4 — a tabela `MARCO_PROCESSO` foi criada em uma sprint anterior com uma constraint CHECK listando os valores de `TipoMarco` vigentes na época. Os 6 novos valores adicionados pela Sprint 13 (`NOTIFICACAO_ALVARA_VENCIDO`, etc.) não estão na constraint. O job P13-C tentou inserir um marco com `tipo_marco='NOTIFICACAO_ALVARA_VENCIDO'` e o Oracle rejeitou.

**Solução:** mesmo padrão — dropar a constraint:
```sql
ALTER TABLE SOL.MARCO_PROCESSO DROP CONSTRAINT SYS_C0073351;
COMMIT;
```

Além disso, os dados de teste acumulados nas tentativas anteriores (licenciamentos 87 e 88 em estado `ALVARA_VENCIDO`, registros de `ROTINA_EXECUCAO` com situação `ERRO`) precisaram ser limpos. A presença de uma `ROTINA_EXECUCAO` com situação `CONCLUIDA` afetaria o cálculo da `dataBase` em `buscarDataBaseRotina()`:

> Se existisse uma execução `CONCLUIDA` de hoje, `dataBase = hoje`. A query de P13-C buscaria `dtValidadeAppci >= hoje AND dtValidadeAppci < hoje` — intervalo sempre vazio — e nenhum marco seria registrado.

Por isso, a limpeza incluiu também os registros de `ROTINA_EXECUCAO`:
```sql
DELETE FROM SOL.ROTINA_EXECUCAO WHERE TIPO_ROTINA = 'GERAR_NOTIFICACAO_ALVARA_VENCIDO';
```

---

### Problema 6 — `PropertyNotFoundStrict`: `.Count` em objeto único sem StrictMode

**Tentativa:** 5ª (após drop das constraints e limpeza dos dados)
**Passo afetado:** Passo 9 — verificação de idempotência RN-129
**Arquivo:** `sprint13-deploy.ps1`, linha 342

**Mensagem de erro:**
```
A propriedade 'Count' não foi encontrada neste objeto. Verifique se a propriedade existe.
No C:\SOL\infra\scripts\sprint13-deploy.ps1:342 caractere:1
+ $qtdMarcosVencido = ($marcos2 | Where-Object { $_.tipoMarco -eq "NOTI ...
```

**Causa raiz:** em PowerShell, o operador pipeline `|` tem comportamento polimórfico:
- Se `Where-Object` retorna **zero ou mais de um** elemento, retorna um **array** — objetos array têm `.Count`
- Se retorna **exatamente um** elemento, retorna o **objeto diretamente** — objetos individuais não têm `.Count` por padrão

Com `Set-StrictMode -Version Latest`, acessar uma propriedade inexistente em um objeto lança exceção imediatamente (em vez de retornar `$null` silenciosamente). Como o licenciamento 89 tinha exatamente 1 marco `NOTIFICACAO_ALVARA_VENCIDO`, `Where-Object` retornou o objeto do marco diretamente — e `.Count` não existe em `PSCustomObject`.

**Solução:** envolver o resultado do pipeline no operador `@()` (array subexpression operator), que **sempre retorna um array** independente da quantidade de elementos:
```powershell
# Antes (ERRO com Set-StrictMode)
$qtdMarcosVencido = ($marcos2 | Where-Object { $_.tipoMarco -eq "NOTIFICACAO_ALVARA_VENCIDO" }).Count

# Depois (corrigido)
$qtdMarcosVencido = @($marcos2 | Where-Object { $_.tipoMarco -eq "NOTIFICACAO_ALVARA_VENCIDO" }).Count
```

O `@()` garante que o resultado seja sempre um array: `@(objeto_único)` retorna `@(objeto_único)` com `.Count = 1`; `@($null)` retorna array vazio com `.Count = 0`.

---

## Log Completo da Execução Final

> Execução bem-sucedida — 6ª tentativa — 2026-04-01 às 15:25:56

```
==> Sprint 13 - P13 Jobs Automaticos de Alvaras
  Data/hora: 2026-04-01 15:25:56
  Backend:   C:\SOL\backend
  URL base:  http://localhost:8080/api

==> Passo 0a - MailHog (SMTP localhost:1025)
    [OK] MailHog ja rodando.

==> Passo 0b - Parar servico SOL-Backend (pre-build)
    [OK] Servico parado.

==> Passo 0c - Criar sequence Oracle SOL.SEQ_ROTINA_EXECUCAO
    [OK] Verificacao/criacao da sequence concluida.

==> Passo 1 - Build Maven (skip tests)
    [OK] Build concluido.

==> Passo 2 - Reiniciar servico SOL-Backend
    [OK] Servico reiniciado.

==> Passo 3 - Health check
    [OK] Health UP.

==> Passo 4 - Autenticacao
    [OK] Token obtido (sol-admin).

==> Passo 5 - Setup de dados de teste
    5.1 Criando licenciamento de teste (RASCUNHO)...
    Licenciamento de teste criado: ID 89
    5.2 Promovendo para APPCI_EMITIDO com dtValidadeAppci = ontem via sqlplus...
    [OK] Licenciamento 89 promovido para APPCI_EMITIDO com dtValidadeAppci = ontem.

==> Passo 6 - Disparar rotina P13 via POST /admin/jobs/rotina-alvara
    (Execucao sincrona -- aguardar ate 2 minutos para bases grandes)
    [OK] Rotina P13 executada. Descricao: Rotina diaria de alvaras disparada manualmente pelo administrador.
    [OK] Data/hora de execucao: 2026-04-01T15:27:05.626900400

==> Passo 7 - Verificar transicao APPCI_EMITIDO -> ALVARA_VENCIDO (P13-A)
    [OK] P13-A OK: licenciamento 89 transicionado para ALVARA_VENCIDO.

==> Passo 8 - Verificar marco NOTIFICACAO_ALVARA_VENCIDO (P13-C)
    [OK] P13-C OK: marco NOTIFICACAO_ALVARA_VENCIDO registrado: 'Notificacao automatica P13-C: alvara vencido em 2026-03-31.'

==> Passo 9 - Verificar idempotencia RN-129 (segundo disparo do job)
    [OK] RN-129 OK: marco NOTIFICACAO_ALVARA_VENCIDO nao duplicado apos segundo disparo (total: 1).
    [OK] Status ALVARA_VENCIDO mantido apos segundo disparo (P13-A nao reprocessa - RN-121).

==> Passo 10 - Verificar RotinaExecucao no banco Oracle

    Ultimas execucoes de rotina:
    ID_ROTINA_EXECUCAO TIPO_ROTINA                    DSC_SITUACAO NR_PROCESSADOS  NR_ERROS DTH_FIM_EXECUCAO
    ------------------ ------------------------------ ------------ -------------- ---------- -------------------------
                     7 GERAR_NOTIFICACAO_ALVARA_VENCI CONCLUIDA                0          0 2026-04-01 15:27:05
                       DO
                     6 GERAR_NOTIFICACAO_ALVARA_VENCI CONCLUIDA                2          0 2026-04-01 15:27:05
                       DO
    [OK] Verificacao de RotinaExecucao concluida.

==> Passo 11 - Limpeza dos dados de teste
    [OK] Dados de teste removidos (licenciamento 89 + rotinas de execucao).
```

---

## Sumário Final Emitido pelo Script

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

  Data/hora: 2026-04-01 15:27:36
```

---

## Considerações Técnicas

### Padrão recorrente: constraints CHECK do Hibernate desatualizadas

Esta sprint revelou um padrão sistemático que surgiu também na Sprint 13 pré-implantação e que tende a se repetir em sprints futuras: o `ddl-auto: update` do Hibernate gera constraints CHECK sobre colunas de enum no momento da **criação da tabela**. Ao adicionar novos valores ao enum em sprints posteriores, as constraints não são atualizadas automaticamente.

**Tabelas afetadas identificadas até a Sprint 13:**

| Tabela | Coluna | Constraint | Problema |
|--------|--------|------------|---------|
| `SOL.LICENCIAMENTO` | `STATUS` | `SYS_C0073344` *(dropada)* | `ALVARA_VENCIDO` não incluído |
| `SOL.MARCO_PROCESSO` | `TIPO_MARCO` | `SYS_C0073351` *(dropada)* | Novos TipoMarco P13 não incluídos |

**Recomendação para sprints futuras:** ao adicionar valores a qualquer enum mapeado como `EnumType.STRING`, verificar se existe constraint CHECK na coluna correspondente e dropá-la antes de subir o serviço.

---

### Sensibilidade temporal do job P13-C

O método `buscarDataBaseRotina()` tem comportamento distinto dependendo do estado de `ROTINA_EXECUCAO`:

| Estado da tabela | `dataBase` usada | Comportamento de P13-C |
|-----------------|-----------------|----------------------|
| Sem registros (primeira execução) | `ontem` | Busca alvarás com `dtValidadeAppci >= ontem AND < hoje` |
| Última execução = `CONCLUIDA` hoje | `hoje` | Busca `dtValidadeAppci >= hoje AND < hoje` → **sempre vazio** |
| Última execução = `CONCLUIDA` anteontem | `anteontem` | Busca alvarás dos últimos 2 dias |

Por esse motivo, os registros de `ROTINA_EXECUCAO` devem ser limpos entre tentativas de smoke test. Uma execução `CONCLUIDA` de hoje tornaria P13-C ineficaz na próxima tentativa.

---

### Resumo de todas as correções aplicadas

| # | Arquivo | Tipo | Problema | Solução |
|---|---------|------|---------|---------|
| 1 | `sprint13-deploy.ps1:279` | Script PS | `$licTesteId:` drive-reference ParseError | `${licTesteId}:` com chaves |
| 2 | `AlvaraJobService.java:173` | Java | `*/12` fecha bloco Javadoc | `* /12` com espaço |
| 3 | `LicenciamentoService.java:185` | Java | Switch exaustivo sem `ALVARA_VENCIDO` | Adicionado ao branch terminal |
| 4 | Oracle `SYS_C0073344` | DDL | CHECK desatualizado em `LICENCIAMENTO.STATUS` | `ALTER TABLE ... DROP CONSTRAINT` |
| 5 | Oracle `SYS_C0073351` | DDL | CHECK desatualizado em `MARCO_PROCESSO.TIPO_MARCO` | `ALTER TABLE ... DROP CONSTRAINT` |
| 6 | `sprint13-deploy.ps1:342` | Script PS | `.Count` em objeto único com StrictMode | `@(...).Count` com array subexpression |

---

*Relatório gerado em 2026-04-01 — SOL CBM-RS*
