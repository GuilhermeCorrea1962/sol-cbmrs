# Sprint 12 — P12 Extinção de Licenciamento

**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Sprint:** 12 — Processo P12
**Data de criacao:** 2026-03-31
**Script principal:** `C:\SOL\infra\scripts\sprint12-deploy.ps1`

---

## 1. Contexto do processo P12

O processo P12 gerencia o **encerramento definitivo** de um licenciamento no sistema SOL. Uma vez extinto, o licenciamento passa para o status `EXTINTO`, que e um **estado terminal** — nenhuma operacao subsequente e admitida sobre ele.

Existem dois fluxos de extincao:

| Fluxo | Iniciador | Efetivador | Marcos gerados |
|---|---|---|---|
| **P12-A** | Cidadao, RT, ADMIN | ADMIN, CHEFE_SSEG_BBM | `EXTINCAO_SOLICITADA` + `EXTINCAO_EFETIVADA` |
| **P12-B** | — | ADMIN, CHEFE_SSEG_BBM | `EXTINCAO_EFETIVADA` (somente) |

**Status admissiveis para extincao (RN-109):**
- `ANALISE_PENDENTE`
- `APPCI_EMITIDO`
- `SUSPENSO`

Status **nao admissiveis:** `RASCUNHO`, `EM_ANALISE`, `EXTINTO` (e todos os demais).

---

## 2. Arquivos criados nesta sprint

### 2.1 `ExtincaoDTO.java` — DTO de entrada

**Caminho:** `br.gov.rs.cbm.sol.dto.ExtincaoDTO`

```java
public record ExtincaoDTO(String motivo) {}
```

**Necessidade:** Transporta o campo `motivo` (obrigatorio em ambas as operacoes) do corpo da requisicao HTTP para o servico. O uso de `record` do Java 21 elimina boilerplate (getters, construtores, equals/hashCode) e torna o contrato da API imediatamente legivel.

### 2.2 `ExtincaoService.java` — Logica de negocio

**Caminho:** `br.gov.rs.cbm.sol.service.ExtincaoService`

Contem dois metodos transacionais publicos:

#### `solicitarExtincao(Long licId, String motivo, String keycloakId)`

- Aplica **RN-110:** rejeita motivo nulo ou em branco (`BusinessException`)
- Aplica **RN-109:** rejeita status fora do conjunto admissivel (`BusinessException`)
- Registra marco `EXTINCAO_SOLICITADA` (nao altera o status do licenciamento)
- Notifica o analista atribuido por e-mail (via `EmailService.notificarAsync`)

#### `efetivarExtincao(Long licId, String motivo, String keycloakId)`

- Aplica **RN-111:** rejeita motivo nulo ou em branco (`BusinessException`)
- Aplica **RN-109:** rejeita status fora do conjunto admissivel (`BusinessException`)
- Transiciona `status` para `EXTINTO` e seta `ativo = false` (**RN-112**)
- Persiste via `licenciamentoRepository.save(lic)`
- Registra marco `EXTINCAO_EFETIVADA`
- Notifica RT (Responsavel Tecnico) e RU (Responsavel pelo Uso) por e-mail

**Observacao sobre RN-113:** A restricao de estado terminal e garantida organicamente pela propria logica de RN-109: `EXTINTO` nao esta no conjunto `STATUS_EXTINCAO_ADMISSIVEL`, logo qualquer chamada sobre um licenciamento ja extinto sera rejeitada com erro de negocio.

### 2.3 `ExtincaoController.java` — Endpoints REST

**Caminho:** `br.gov.rs.cbm.sol.controller.ExtincaoController`

| Endpoint | Roles permitidas | Acao |
|---|---|---|
| `POST /licenciamentos/{id}/solicitar-extincao` | `CIDADAO`, `RT`, `ADMIN`, `CHEFE_SSEG_BBM` | Registra solicitacao (P12-A) |
| `POST /licenciamentos/{id}/efetivar-extincao` | `ADMIN`, `CHEFE_SSEG_BBM` | Efetiva extincao (P12-A e P12-B) |

**Padrao de implementacao:**
- `@RestController` sem `@RequestMapping` a nivel de classe (mesmo padrao do `RecursoController` e demais controllers do sistema)
- `@AuthenticationPrincipal Jwt jwt` em todos os metodos — extrai o `sub` (keycloakId) do token JWT para rastreabilidade
- `@PreAuthorize` com `hasAnyRole(...)` — seguranca declarativa
- Documentacao Swagger via `@Operation` com descricao das RNs relevantes

---

## 3. Estrutura do script `sprint12-deploy.ps1`

O script e dividido em 9 passos sequenciais. A descricao a seguir explica **o que cada passo faz e por que e necessario**.

---

### Passo 0a — Verificar/iniciar MailHog

**O que faz:** Testa se a porta 1025 (SMTP) esta respondendo. Se nao estiver, inicia o `MailHog.exe` em background e aguarda 4 segundos antes de reconfirmar.

**Por que e necessario:** O `ExtincaoService` chama `EmailService.notificarAsync(...)` ao solicitar e ao efetivar uma extincao. O Spring Boot verifica a conectividade SMTP durante o startup. Se o servidor SMTP nao estiver disponivel, o health check do Actuator retorna `DOWN` (componente de mail em falha) e os testes de integracao falham imediatamente. O MailHog e o servidor SMTP de desenvolvimento que captura os e-mails sem entrega-los.

---

### Passo 0b — Parar o servico SOL-Backend antes do build

**O que faz:** Localiza o servico Windows `SOL-Backend` e o para antes de iniciar o `mvn clean package`.

**Por que e necessario:** No Windows, o JAR em execucao e bloqueado pelo sistema operacional. O `mvn clean` tenta deletar o diretorio `target/` para garantir uma compilacao limpa; se o JAR estiver em uso, a exclusao falha e o build e interrompido com erro de acesso negado. Parar o servico antes libera o lock sobre o arquivo.

---

### Passo 1 — Build Maven

**O que faz:** Executa `mvn clean package -DskipTests -q` no diretorio `C:\SOL\backend` com `JAVA_HOME` apontando para o JDK correto.

**Por que e necessario:** Os tres arquivos Java criados nesta sprint (`ExtincaoDTO`, `ExtincaoService`, `ExtincaoController`) precisam ser compilados e empacotados no JAR do backend. Sem o rebuild, a API continua rodando a versao anterior sem os novos endpoints.

**Detalhes do ambiente:**
- Maven: `C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd`
- JDK: `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot`

---

### Passo 2 — Reiniciar o servico SOL-Backend

**O que faz:** Executa `Restart-Service SOL-Backend` e aguarda 20 segundos para a JVM inicializar.

**Por que e necessario:** O JAR anterior continua em memoria ate o servico ser reiniciado. A reinicializacao carrega o novo JAR com os endpoints de extincao. O tempo de espera de 20 segundos e necessario para que o Spring Boot complete a inicializacao do contexto (conexao com Oracle, Keycloak, scan de beans, etc.) antes de comecar a enviar requisicoes.

Se o restart automatico falhar, o script pausa e solicita confirmacao manual antes de continuar.

---

### Passo 3 — Health check

**O que faz:** Chama `GET /actuator/health` em loop (ate 12 tentativas, intervalo de 5 segundos = 60 segundos maximo) ate receber `{"status":"UP"}`.

**Por que e necessario:** Garante que o backend esta completamente inicializado e todos os subsistemas (banco de dados, mail, Keycloak) estao operacionais antes de comecar os testes. Evita falsos negativos causados por tentativas de chamada durante o startup da JVM.

---

### Passo 4 — Autenticacao

**O que faz:**
1. Obtem token JWT para `sol-admin` via `POST /api/auth/login`
2. Obtem token JWT para `analista1` via `POST /api/auth/login`
3. Chama `GET /api/auth/me` com o token do analista para obter o ID Oracle

**Por que e necessario:** Todos os endpoints da Sprint 12 exigem autenticacao Bearer. O `sol-admin` tem papel `ADMIN` e pode usar ambos os endpoints. O `analista1` e obtido para manter consistencia com o padrao das demais sprints (e porque o ID Oracle pode ser necessario em sprints futuras que envolvam distribuicao).

---

### Passo 5 — Limpeza preventiva

**O que faz:** Se `sqlplus` estiver disponivel, executa um bloco PL/SQL que remove licenciamentos de teste remanescentes de execucoes anteriores (identificados por `area_construida = 200` e status `EXTINTO` ou `ANALISE_PENDENTE` entre os 10 mais recentes).

**Por que e necessario:** Execucoes anteriores com falha podem ter deixado licenciamentos intermediarios no banco. A limpeza preventiva evita que esses residuos interfiram nos testes da execucao atual, garantindo reproducibilidade.

---

### Passo 6 — Fluxo A: Solicitacao + Efetivacao

**O que faz:** Testa o fluxo completo P12-A com 5 sub-passos:

| Sub-passo | Acao | Verificacao |
|---|---|---|
| Setup | Criar licenciamento + upload PPCI + submeter | Status `ANALISE_PENDENTE` |
| 6.1 | `POST /solicitar-extincao` com motivo | Retorno nao deve ser `EXTINTO` (status nao muda) |
| 6.2 | `GET /marcos` | Marco `EXTINCAO_SOLICITADA` presente |
| 6.3 | `POST /efetivar-extincao` com motivo | Retorno deve ter `status = EXTINTO` |
| 6.4 | `GET /marcos` | Marco `EXTINCAO_EFETIVADA` presente |
| 6.5 | `GET /licenciamentos/{id}` | `status = EXTINTO` confirmado via leitura direta |

**Por que e necessario:** Valida o fluxo bidirecional (cidadao solicita, admin efetiva) e confirma que:
- `solicitar-extincao` nao e um estado terminal — apenas registra intenção
- `efetivar-extincao` e que transiciona o status
- Ambos os marcos ficam gravados com rastreabilidade

---

### Passo 7 — Fluxo B: Extincao administrativa direta

**O que faz:** Testa o fluxo P12-B com 3 sub-passos:

| Sub-passo | Acao | Verificacao |
|---|---|---|
| Setup | Criar licenciamento + upload PPCI + submeter | Status `ANALISE_PENDENTE` |
| 7.1 | `POST /efetivar-extincao` direto (sem solicitar) | `status = EXTINTO` |
| 7.2 | `GET /marcos` | Marco `EXTINCAO_EFETIVADA` presente |
| 7.3 | `GET /marcos` | Marco `EXTINCAO_SOLICITADA` **ausente** |

**Por que e necessario:** O ADMIN pode extinguir um licenciamento diretamente sem que haja solicitacao previa do cidadao (extincao por auditoria, irregularidade grave, etc.). O teste confirma que esse caminho funciona independentemente e que o sistema nao cria marcos fantasmas de solicitacao que nao ocorreram.

---

### Passo 8 — Validacao das regras de negocio

**O que faz:** Testa 4 cenarios de rejeicao. Em todos os casos, o script **espera um erro HTTP** (400, 409 ou 422) e considera o teste bem-sucedido se o erro ocorrer.

#### 8.1 — RN-113: Operacao em licenciamento EXTINTO

Reutiliza o licenciamento `$idA` (ja extinto no Passo 6) e tenta chamar `solicitar-extincao` novamente.

**Expectativa:** HTTP 400/422 com mensagem de negocio.

**Por que RN-113 funciona sem codigo adicional:** O conjunto `STATUS_EXTINCAO_ADMISSIVEL` nao inclui `EXTINTO`. Portanto, qualquer chamada sobre um licenciamento extinto falha organicamente no guard de RN-109 com a mensagem "Extincao nao pode ser solicitada para licenciamento com status EXTINTO".

#### 8.2 — RN-110: Motivo obrigatorio na solicitacao

Cria um terceiro licenciamento em `ANALISE_PENDENTE` e chama `solicitar-extincao` com `motivo = ""`.

**Expectativa:** HTTP 400/422 com codigo `RN-110`.

#### 8.3 — RN-111: Motivo obrigatorio na efetivacao

Reutiliza o mesmo licenciamento do 8.2 (ainda em `ANALISE_PENDENTE`) e chama `efetivar-extincao` com `motivo = ""`.

**Expectativa:** HTTP 400/422 com codigo `RN-111`.

#### 8.4 — RN-109: Status invalido (RASCUNHO)

Cria um licenciamento novo **sem submeter** (permanece em status `RASCUNHO`) e tenta chamar `efetivar-extincao`.

**Expectativa:** HTTP 400/422 com codigo `RN-109`.

---

### Passo 9 — Limpeza pos-teste

**O que faz:** Remove todos os licenciamentos de teste criados nesta execucao (identificados por `area_construida IN (200, 100)` entre os 20 IDs mais recentes), incluindo marcos e arquivos vinculados.

**Por que e necessario:** Manter o banco limpo apos os testes evita acumulo de dados ficticios, facilita a repeticao do script e nao polui relatorios ou consultas sobre o ambiente.

---

## 4. Como executar

### Pre-requisitos

- Servidor com Windows Server + PowerShell 5.1
- Servico `SOL-Backend` configurado (NSSM ou sc.exe)
- Oracle XE rodando em `localhost:1521/XEPDB1` com usuario `sol`/`Sol@CBM2026`
- Keycloak rodando em `localhost:8180` com realm `sol`
- `MailHog.exe` em `C:\SOL\infra\mailhog\`
- Usuarios `sol-admin` (papel ADMIN) e `analista1` (papel ANALISTA) criados no Keycloak

### Comando de execucao

No servidor destino, abra o PowerShell como Administrador e execute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\SOL\infra\scripts\sprint12-deploy.ps1
```

O script e completamente automatizado. Nao requer intervencao manual salvo se o restart do servico falhar (nesse caso, o script pausa e aguarda confirmacao com `ENTER`).

### Duracao estimada

Aproximadamente **4 a 6 minutos** (variacao conforme velocidade do build Maven e inicializacao da JVM).

---

## 5. Saida esperada (SUMARIO)

Ao final da execucao bem-sucedida, o script exibe:

```
==> SUMARIO

  Sprint 12 - P12 Extincao de Licenciamento concluida com sucesso.

  Arquivos criados nesta sprint:
    [N] dto/ExtincaoDTO.java         : record ExtincaoDTO(String motivo)
    [N] service/ExtincaoService.java : solicitarExtincao + efetivarExtincao
    [N] controller/ExtincaoController.java : 2 endpoints POST

  Endpoints:
    POST /licenciamentos/{id}/solicitar-extincao  (CIDADAO, RT, ADMIN)
    POST /licenciamentos/{id}/efetivar-extincao   (ADMIN, CHEFE_SSEG_BBM)

  Fluxos validados:
    Fluxo A: ANALISE_PENDENTE + solicitar + efetivar => EXTINTO + 2 marcos
    Fluxo B: ANALISE_PENDENTE + efetivar direto      => EXTINTO + 1 marco
    RN-109 : status RASCUNHO bloqueado
    RN-110 : motivo vazio na solicitacao bloqueado
    RN-111 : motivo vazio na efetivacao bloqueado
    RN-113 : operacao em licenciamento EXTINTO bloqueada
```

---

## 6. Possiveis problemas e solucoes

| Problema | Causa provavel | Solucao |
|---|---|---|
| Build Maven falha com "Access denied" | JAR em uso (servico nao parou) | Verificar Passo 0b; parar o servico manualmente |
| Health check nao passa de DOWN | MailHog nao rodando | Verificar Passo 0a; iniciar MailHog manualmente |
| `401 Unauthorized` nos testes | Token expirado ou credenciais erradas | Verificar variaveis `$AdminUser`/`$AdminPass` no script |
| `404 Not Found` nos endpoints de extincao | Build nao foi compilado com os novos arquivos | Verificar se os 3 arquivos Java estao em `Y:\backend\src\...` |
| `500 Internal Server Error` no solicitar/efetivar | Bean `ExtincaoService` nao injetado | Verificar se `@Service` esta presente; recompilar |
| Marco nao encontrado | Endpoint retornou OK mas nao persistiu | Verificar logs do servico; possivel problema de transacao |
| `$idRascunho` nao definido no 8.4 | Criacao do licenciamento RASCUNHO falhou | WARN e exibido; script continua (nao e bloqueante) |

---

## 7. Rastreabilidade — Regras de Negocio implementadas

| Codigo | Descricao | Implementacao |
|---|---|---|
| RN-109 | Status admissivel para extincao | `STATUS_EXTINCAO_ADMISSIVEL` em `ExtincaoService` |
| RN-110 | Motivo obrigatorio na solicitacao | Guard `motivo == null || motivo.isBlank()` em `solicitarExtincao` |
| RN-111 | Motivo obrigatorio na efetivacao | Guard `motivo == null || motivo.isBlank()` em `efetivarExtincao` |
| RN-112 | Status => EXTINTO, ativo = false | `lic.setStatus(EXTINTO); lic.setAtivo(false)` em `efetivarExtincao` |
| RN-113 | EXTINTO e estado terminal | Consequencia organica de RN-109 (EXTINTO nao esta no conjunto admissivel) |
| RN-114 | Cidadao/RT solicita; Admin efetiva | `@PreAuthorize` em cada endpoint do `ExtincaoController` |

---

## 8. Estado do projeto apos Sprint 12

| Processo | BPMN | Req. Stack Atual | Req. Java Moderna | Descritivo | Implementacao |
|---|---|---|---|---|---|
| P11 Pagamento Boleto | ✅ | ✅ | ✅ | ✅ | ✅ Sprint 11 |
| P12 Extincao Licenciamento | ✅ | ✅ | ✅ | ✅ | ✅ Sprint 12 |
| P13 Jobs Automaticos | ✅ | ✅ | ✅ | ✅ | pendente |
| P14 Renovacao Licenciamento | ✅ | ✅ | pendente | ✅ | pendente |
