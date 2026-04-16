# Sprint 10 — P10: Recurso CIA/CIV

## Contexto geral

A Sprint 10 implementa o processo **P10 — Recurso Administrativo contra CIA ou CIV** do sistema SOL CBM-RS. Trata-se do mecanismo pelo qual o interessado (Responsável Técnico, cidadão ou seu representante) pode contestar formalmente um Comunicado de Inconformidade na Análise (CIA) ou na Vistoria (CIV) emitido pelo Corpo de Bombeiros.

O recurso é um direito administrativo: se o interessado considera que a inconformidade apontada é indevida ou equivocada, ele fundamenta sua contestação por escrito e o CBMRS (via ADMIN ou CHEFE_SSEG_BBM) analisa e decide o mérito. O resultado pode ser:

- **DEFERIDO** (recurso provido): a inconformidade foi considerada improcedente, o licenciamento é aprovado.
- **INDEFERIDO** (recurso improvido): a inconformidade é mantida, o licenciamento é encerrado negativamente.

---

## Arquivos gerados

| Caminho (local `C:\SOL`) | Caminho no servidor (`Y:\`) | Tipo |
|---|---|---|
| `backend\src\main\java\br\gov\rs\cbm\sol\dto\RecursoDTO.java` | `backend\src\main\java\br\gov\rs\cbm\sol\dto\RecursoDTO.java` | Java DTO |
| `backend\src\main\java\br\gov\rs\cbm\sol\service\RecursoService.java` | `backend\src\main\java\br\gov\rs\cbm\sol\service\RecursoService.java` | Java Service |
| `backend\src\main\java\br\gov\rs\cbm\sol\controller\RecursoController.java` | `backend\src\main\java\br\gov\rs\cbm\sol\controller\RecursoController.java` | Java Controller |
| `infra\scripts\sprint10-deploy.ps1` | `infra\scripts\sprint10-deploy.ps1` | PowerShell Deploy |

---

## Maquina de estados P10

```
CIA_CIENCIA  ─┐
              ├─[interpor-recurso]─> RECURSO_PENDENTE ─[iniciar-recurso]─> EM_RECURSO ─┬─[deferir-recurso]──> DEFERIDO
CIV_CIENCIA  ─┘                                                                         └─[indeferir-recurso]─> INDEFERIDO
```

### Transições e papéis autorizados

| Endpoint | De | Para | Papéis | Marco |
|---|---|---|---|---|
| `POST /interpor-recurso` | CIA_CIENCIA ou CIV_CIENCIA | RECURSO_PENDENTE | CIDADAO, RT, ADMIN | RECURSO_INTERPOSTO |
| `POST /iniciar-recurso` | RECURSO_PENDENTE | EM_RECURSO | ADMIN, CHEFE_SSEG_BBM | RECURSO_EM_ANALISE |
| `POST /deferir-recurso` | EM_RECURSO | DEFERIDO | ADMIN, CHEFE_SSEG_BBM | RECURSO_DEFERIDO |
| `POST /indeferir-recurso` | EM_RECURSO | INDEFERIDO | ADMIN, CHEFE_SSEG_BBM | RECURSO_INDEFERIDO |

---

## Regras de negócio implementadas

| Código | Descrição |
|---|---|
| RN-P10-001 | Recurso só admissível quando status for CIA_CIENCIA ou CIV_CIENCIA. Qualquer outro status retorna HTTP 422 (BusinessException). |
| RN-P10-002 | Campo `motivo` obrigatório ao interpor recurso. Cadeia nula ou em branco retorna HTTP 422. |
| RN-P10-003 | Início da análise só permitido em RECURSO_PENDENTE. Status divergente retorna HTTP 422. |
| RN-P10-004 | Deferimento e indeferimento só permitidos em EM_RECURSO. Status divergente retorna HTTP 422. |
| RN-P10-005 | Campo `motivo` obrigatório ao indeferir recurso. Cadeia nula ou em branco retorna HTTP 422. |
| RN-089 | (Norma RTCBMRS) Durante RECURSO_PENDENTE ou EM_RECURSO o licenciamento fica bloqueado para ações do fluxo principal. O bloqueio é garantido pelas validações de status em cada service: nenhum outro endpoint aceita essas transições. |

---

## Descrição dos arquivos

### 1. `RecursoDTO.java`

DTO de entrada compartilhado pelos 4 endpoints. Contém apenas o campo `motivo` (String). É obrigatório em `interpor-recurso` e `indeferir-recurso`; opcional em `iniciar-recurso` e `deferir-recurso` (os respectivos controllers anotam `@RequestBody(required = false)`).

**Por que um DTO único:** os 4 endpoints precisam de no máximo um campo livre de texto. Criar DTOs separados seria redundância desnecessária. O mesmo padrão foi adotado em `AnaliseDecisaoDTO` (P04/P05) e `TrocaEnvolvidoDTO` (P09).

---

### 2. `RecursoService.java`

Camada de negócio do P10. Padrões herdados dos services anteriores (IsencaoService, TrocaEnvolvidoService):

- `@Service @Transactional(readOnly = true)` na classe — todas as operações de leitura não abrem transação de escrita.
- `@Transactional` em cada método de escrita — garante atomicidade: se o `registrarMarco` falhar após o `save`, o status não é persistido.
- Injeção via construtor (sem `@Autowired`) — compatível com Spring Boot 3 e facilita testes.
- `registrarMarco(lic, tipo, usuario, observacao)` — helper privado que salva o `MarcoProcesso` com builder.
- `notificarEnvolvidos(lic, assunto, corpo)` — helper que envia e-mail ao RT e ao RU (sem duplicar se forem o mesmo endereço).

**Decisão: DEFERIDO vs. volta para EM_ANALISE**

Ao deferir o recurso, o status vai para `DEFERIDO` (StatusLicenciamento.DEFERIDO), não para EM_ANALISE. Isso segue a modelagem do BPMN P10 e o requisito `Req. P10 Stack Atual`: o deferimento do recurso significa que o CIA/CIV era improcedente e o edificio está em conformidade — o licenciamento é diretamente aprovado. Caso o CBMRS queira uma reanálise, o fluxo correto é abrir um novo licenciamento.

---

### 3. `RecursoController.java`

Controller REST sem `@RequestMapping` de classe — segue o padrão flat adotado desde a Sprint 9 (`TrocaEnvolvidoController`) para evitar conflito de mapeamento com `LicenciamentoController`. Cada `@PostMapping` define o path completo `/licenciamentos/{id}/...`.

- `interpor-recurso`: `@RequestBody RecursoDTO` obrigatório (sem `required=false`) — valida implicitamente que o corpo não é nulo.
- `iniciar-recurso` e `deferir-recurso`: `@RequestBody(required = false)` — motivo opcional.
- `indeferir-recurso`: `@RequestBody RecursoDTO` obrigatório — o service valida o campo motivo.

---

### 4. `sprint10-deploy.ps1`

Script PowerShell de deploy automatizado da Sprint 10. Executa o ciclo completo: parar serviço → compilar Maven → reiniciar → health check → login → smoke tests → limpeza Oracle.

#### Funções auxiliares herdadas de Sprints anteriores

| Função | Origem | Finalidade |
|---|---|---|
| `Write-Step/OK/FAIL/WARN` | Sprint 1+ | Log colorido padronizado |
| `Show-ErrorBody` | Sprint 9 | Exibe corpo da resposta HTTP em caso de erro |
| `Invoke-MultipartUpload` | Sprint 8 | Upload de arquivo PDF via multipart/form-data para `POST /arquivos/upload` |
| `New-PdfTemp` | Sprint 8 | Cria um PDF mínimo válido como arquivo temporário para upload |

#### Função nova: `Invoke-SetupCiaCiencia`

Encapsula a cadeia de 7 passos necessária para levar um licenciamento do zero ao status `CIA_CIENCIA`:

```
P03: criar → upload PPCI → submeter
P04: distribuir → iniciar-analise → emitir-cia
P05: registrar-ciencia-cia  → CIA_CIENCIA
```

**Por que encapsular:** os dois fluxos (A e B) precisam do mesmo ponto de partida (CIA_CIENCIA). Extrair para função evita duplicação de ~30 linhas e garante que ambos os fluxos partem de um estado idêntico.

---

## Detalhamento dos smoke tests

### Fluxo A — Recurso CIA → DEFERIDO

Objetivo: verificar que o caminho feliz do recurso provido funciona de ponta a ponta.

| Passo | Ação | Status esperado | Marco esperado |
|---|---|---|---|
| Setup | `Invoke-SetupCiaCiencia` | CIA_CIENCIA | (CIA_CIENCIA + marcos P03/P04/P05) |
| A1 | `POST /interpor-recurso` (motivo obrigatório) | RECURSO_PENDENTE | RECURSO_INTERPOSTO |
| A2 | `POST /iniciar-recurso` (motivo opcional) | EM_RECURSO | RECURSO_EM_ANALISE |
| A3 | `POST /deferir-recurso` (motivo opcional) | DEFERIDO | RECURSO_DEFERIDO |
| A4 | `GET /licenciamentos/{id}` | Confirma `status=DEFERIDO` | — |
| A5 | `GET /licenciamentos/{id}/marcos` | Lista todos os marcos | RECURSO_INTERPOSTO + RECURSO_EM_ANALISE + RECURSO_DEFERIDO |

### Fluxo B — Recurso CIA → INDEFERIDO

Objetivo: verificar o caminho do recurso improvido (CIA mantido, processo encerrado).

| Passo | Ação | Status esperado | Marco esperado |
|---|---|---|---|
| Setup | `Invoke-SetupCiaCiencia` (novo licenciamento) | CIA_CIENCIA | — |
| B1 | `POST /interpor-recurso` (motivo obrigatório) | RECURSO_PENDENTE | RECURSO_INTERPOSTO |
| B2 | `POST /iniciar-recurso` (sem corpo) | EM_RECURSO | RECURSO_EM_ANALISE |
| B3 | `POST /indeferir-recurso` (motivo obrigatório) | INDEFERIDO | RECURSO_INDEFERIDO |
| B4 | `GET /licenciamentos/{id}` | Confirma `status=INDEFERIDO` | — |
| B5 | `GET /licenciamentos/{id}/marcos` | Lista todos os marcos | RECURSO_INTERPOSTO + RECURSO_EM_ANALISE + RECURSO_INDEFERIDO |

---

## Pré-requisitos para execução

1. Sprints 1 a 9 executadas com sucesso no servidor.
2. MinIO em execução com bucket `sol` e policy `sol-app-policy` (`s3:GetBucketLocation` habilitado) — necessário para o upload do PPCI no setup.
3. Usuário `sol-admin` com roles `ADMIN` e `CIDADAO` no realm `sol` do Keycloak — necessário para interpor recurso (role CIDADAO) e para as ações administrativas (role ADMIN).
4. Drive `Y:\` acessível no servidor (mapeamento SMB para `C:\SOL\`).

---

## Instrucoes de execucao

### Passo 1 — Copiar arquivos Java para o servidor

No servidor (ou via acesso ao drive Y:\), confirmar que os seguintes arquivos existem:

```
Y:\backend\src\main\java\br\gov\rs\cbm\sol\dto\RecursoDTO.java
Y:\backend\src\main\java\br\gov\rs\cbm\sol\service\RecursoService.java
Y:\backend\src\main\java\br\gov\rs\cbm\sol\controller\RecursoController.java
Y:\infra\scripts\sprint10-deploy.ps1
```

### Passo 2 — Executar o script no servidor

Abrir PowerShell como Administrador no servidor e executar:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\SOL\infra\scripts\sprint10-deploy.ps1
```

### Passo 3 — Interpretar o resultado

Cada linha de saída começa com um prefixo colorido:

| Prefixo | Cor | Significado |
|---|---|---|
| `[OK]` | Verde | Passo bem-sucedido |
| `[AVISO]` | Amarelo | Situação inesperada mas não bloqueante |
| `[FALHA]` | Vermelho | Erro que abortou o fluxo |
| `[DIAGNOSTICO]` | Magenta | Corpo da resposta HTTP em caso de erro (para depuração) |

---

## Cenários de erro esperados e diagnóstico

| Erro | Causa provável | Diagnóstico |
|---|---|---|
| HTTP 403 em `interpor-recurso` | Token não tem role CIDADAO ou RT | Verificar roles do `sol-admin` no Keycloak |
| HTTP 422 em `interpor-recurso` | Status não é CIA_CIENCIA (setup falhou) | Ver `[DIAGNOSTICO]` — campo `codigoRegra` deve ser `RN-P10-001` |
| HTTP 422 em `interpor-recurso` sem motivo | `motivo` nulo ou vazio | Campo `motivo` obrigatório — ver `RN-P10-002` |
| HTTP 403 em `iniciar-recurso` | Token não tem role ADMIN ou CHEFE_SSEG_BBM | Verificar roles no Keycloak |
| HTTP 422 em `iniciar-recurso` | Status não é RECURSO_PENDENTE | Setup não chegou ao status correto |
| HTTP 422 em `deferir/indeferir-recurso` | Status não é EM_RECURSO | `iniciar-recurso` falhou anteriormente |
| HTTP 500 em qualquer endpoint | Arquivo Java não compilado | Verificar path `Y:\backend\...` (não `Y:\SOL\backend\...`) |
| Setup falha em `upload PPCI` | MinIO indisponível | Iniciar MinIO antes de executar o script |
| Setup falha em `distribuir` | `analistaId` inválido | `adminId` deve ser id válido de usuário ativo |

---

## Observação sobre o mapeamento Y:\

**Regra crítica** (aprendida na Sprint 9): o drive `Y:\` mapeia diretamente para `C:\SOL\` no servidor.

- **CORRETO:** `Y:\backend\...` = `C:\SOL\backend\...`
- **ERRADO:** `Y:\SOL\backend\...` = `C:\SOL\SOL\backend\...` (diretório inexistente)

Sempre verificar que os arquivos Java foram gravados em `Y:\backend\src\main\java\...` e não em `Y:\SOL\backend\...`.

---

## Estado do processo P10 após esta Sprint

| Artefato | Status |
|---|---|
| BPMN detalhado | Concluido (P10_Recurso_StackAtual.bpmn) |
| Req. Stack Atual | Concluido (Requisitos_P10_Recurso_StackAtual.md) |
| Req. Java Moderna | Concluido (Requisitos_P10_Recurso_JavaModerna.md) |
| Descritivo BPMN | Concluido (Descritivo_P10_FluxoBPMN_StackAtual.md) |
| Implementacao backend | **Esta Sprint** — RecursoDTO + RecursoService + RecursoController |
| Smoke tests | **Esta Sprint** — Fluxo A (DEFERIDO) + Fluxo B (INDEFERIDO) |
