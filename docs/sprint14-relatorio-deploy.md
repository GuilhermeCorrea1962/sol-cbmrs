# Sprint 14 — P14 Renovação de Licenciamento (APPCI)
## Relatório de Deploy e Smoke Test

**Data de execução:** 2026-04-01
**Responsável:** sol-admin
**Ambiente:** Servidor local — Spring Boot 3.3.4 + Oracle XE 21c + Keycloak 24.0.3
**Script base:** `C:\SOL\infra\scripts\sprint14-deploy.ps1`
**Status final:** ✅ CONCLUÍDA COM SUCESSO (após correções iterativas)

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

A Sprint 14 implementou o subsistema **P14 — Renovação de Licenciamento**, responsável por permitir que um licenciamento com status `APPCI_EMITIDO` (alvará válido com vencimento próximo) ou `ALVARA_VENCIDO` (alvará expirado) seja renovado, gerando um novo APPCI com data de validade estendida em 5 anos.

### Fluxo de renovação implementado (happy path)

```
APPCI_EMITIDO ──► AGUARDANDO_ACEITE_RENOVACAO
                    │
                    ▼ (aceitar-anexo-d)
              AGUARDANDO_PAGAMENTO_RENOVACAO
                    │
                    ▼ (confirmar + solicitar-isencao + deferir-isencao)
              AGUARDANDO_DISTRIBUICAO_RENOV
                    │
                    ▼ (distribuir)
              EM_VISTORIA_RENOVACAO
                    │
                    ▼ (registrar-vistoria + homologar-vistoria deferida)
              APPCI_EMITIDO  ←─ nova dtValidadeAppci = hoje + 5 anos
```

### Fluxo alternativo — Recusa

```
AGUARDANDO_ACEITE_RENOVACAO ──► recusar ──► APPCI_EMITIDO   (se validade futura)
                                         └──► ALVARA_VENCIDO (se validade passada) — RN-145
```

### Tabela de endpoints implementados

| Método | URL | Transição | Regra |
|--------|-----|-----------|-------|
| POST | `/licenciamentos/{id}/renovacao/iniciar` | APPCI_EMITIDO / ALVARA_VENCIDO → AGUARDANDO_ACEITE_RENOVACAO | RN-141 |
| PUT | `/licenciamentos/{id}/renovacao/aceitar-anexo-d` | marco ACEITE_ANEXOD_RENOVACAO | RN-143 |
| POST | `/licenciamentos/{id}/renovacao/confirmar` | → AGUARDANDO_PAGAMENTO_RENOVACAO | RN-143 |
| POST | `/licenciamentos/{id}/renovacao/solicitar-isencao` | marco SOLICITACAO_ISENCAO_RENOVACAO | — |
| POST | `/licenciamentos/{id}/renovacao/analisar-isencao` | → AGUARDANDO_DISTRIBUICAO_RENOV | — |
| POST | `/licenciamentos/{id}/renovacao/distribuir` | → EM_VISTORIA_RENOVACAO | RN-150 |
| POST | `/licenciamentos/{id}/renovacao/registrar-vistoria` | marco VISTORIA_RENOVACAO | — |
| POST | `/licenciamentos/{id}/renovacao/homologar-vistoria` | → APPCI_EMITIDO + nova data | — |
| POST | `/licenciamentos/{id}/renovacao/ciencia-appci` | marco CIENCIA_APPCI_RENOVACAO | RN-143 |
| POST | `/licenciamentos/{id}/renovacao/recusar` | rollback de status | RN-145 |

---

## Novos Componentes Implementados

### `entity/enums/StatusLicenciamento.java` — modificado

**O que mudou:** adição de 4 novos valores ao enum de status do licenciamento:

```java
AGUARDANDO_ACEITE_RENOVACAO,
AGUARDANDO_PAGAMENTO_RENOVACAO,
AGUARDANDO_DISTRIBUICAO_RENOV,
EM_VISTORIA_RENOVACAO
```

**Por que foi necessário:** o processo de renovação possui fases distintas que precisam ser representadas como estados da máquina de estados do licenciamento. Cada fase tem atores diferentes (RT/RU para aceite, administração para distribuição, inspetor para vistoria) e validações distintas. Sem esses valores no enum, o `RenovacaoService` não teria estados de destino válidos para persistir via Hibernate (`EnumType.STRING`). O Hibernate mapeia cada valor do enum diretamente para a coluna `STATUS` — portanto cada estado novo precisa existir tanto no Java quanto como valor aceito pelo CHECK constraint do Oracle.

---

### `entity/enums/TipoMarco.java` — modificado

**O que mudou:** adição dos tipos de marco P14:

```
INICIO_RENOVACAO
ACEITE_ANEXOD_RENOVACAO
SOLICITACAO_ISENCAO_RENOVACAO
ANALISE_ISENCAO_RENOVACAO
DISTRIBUICAO_VISTORIA_RENOVACAO
VISTORIA_RENOVACAO
HOMOLOGACAO_VISTORIA_RENOVACAO
LIBERACAO_RENOV_APPCI
CIENCIA_APPCI_RENOVACAO
RECUSA_RENOVACAO
```

**Por que foi necessário:** o projeto adota o padrão de rastreabilidade total via `MARCO_PROCESSO`. Cada transição de estado relevante gera um marco auditável com data, tipo e referência ao licenciamento. Sem esses valores o `RenovacaoService` não poderia persistir os marcos no banco — `EnumType.STRING` lança `IllegalArgumentException` se o valor não existir no enum Java, e o CHECK constraint do Oracle rejeita valores não listados.

---

### `entity/Licenciamento.java` — modificado

**O que mudou:** adição do campo:

```java
@Column(name = "ISENTO_TAXA_RENOVACAO", columnDefinition = "char(1) default 'N'")
private String isentoTaxaRenovacao = "N";
```

**Por que foi necessário:** o fluxo de renovação permite que o responsável técnico solicite isenção da taxa de vistoria de renovação. O sistema precisa registrar essa decisão de forma persistente no licenciamento para que o `RenovacaoService` possa verificá-la nas fases subsequentes (evitando cobrança indevida). Por ser um campo novo (não existia nas Sprints anteriores), o `ddl-auto: update` do Hibernate adicionou a coluna automaticamente no startup — sem necessidade de DDL manual.

---

### `service/RenovacaoService.java` — novo

**O que é:** serviço Spring com 7 métodos públicos correspondentes às fases do fluxo de renovação. Implementa validações de estado (`RN-141`, `RN-143`, `RN-145`, `RN-150`), registra marcos, atualiza status e recalcula `dtValidadeAppci` após homologação deferida.

**Por que foi necessário:** separar a lógica de renovação do `LicenciamentoService` já existente. O princípio de responsabilidade única (`SRP`) e a complexidade do fluxo (10 marcos distintos, 4 novos status) justificam um serviço dedicado. O `LicenciamentoService` ficaria excessivamente grande e difícil de manter se absorvesse também P14.

**Lógica de recalculate de validade (homologação deferida):**

```java
licenciamento.setDtValidadeAppci(LocalDate.now().plusYears(5));
licenciamento.setStatus(StatusLicenciamento.APPCI_EMITIDO);
```

---

### `controller/RenovacaoController.java` — novo

**O que é:** `@RestController` com `@RequestMapping("/licenciamentos/{id}/renovacao")` que expõe os 10 endpoints da Sprint 14. Delega toda a lógica ao `RenovacaoService`.

**Por que foi necessário:** convenção do projeto — cada domínio funcional tem seu próprio controller. `LicenciamentoController` já gerencia CRUD base e fluxo de análise; misturar os endpoints de renovação ali geraria acoplamento e dificultaria manutenção futura.

---

### `service/LicenciamentoService.java` — modificado

**O que mudou:** o método `validarTransicaoStatus` utiliza um `switch` exaustivo sobre o enum `StatusLicenciamento`. Com os 4 novos status da Sprint 14, o compilador não detecta a lacuna em tempo de compilação (o switch cai no `default`), mas em runtime qualquer operação sobre esses status retornaria `false` de forma incorreta.

**Correção aplicada:** os 4 novos status foram adicionados ao branch de estados gerenciados por máquina de estados própria (retornam `false` quando chamados via `validarTransicaoStatus`, pois suas transições são controladas exclusivamente pelo `RenovacaoService`):

```java
case AGUARDANDO_ACEITE_RENOVACAO,
     AGUARDANDO_PAGAMENTO_RENOVACAO,
     AGUARDANDO_DISTRIBUICAO_RENOV,
     EM_VISTORIA_RENOVACAO -> false;
```

---

### `application.yml` — modificado

**O que mudou:**

```yaml
management:
  health:
    mail:
      enabled: false
```

**Por que foi necessário:** a Sprint 14 referencia o subsistema de e-mail (notificações de renovação). Com esse componente configurado, o Spring Boot Actuator ativa automaticamente o `MailHealthIndicator`, que tenta se conectar ao servidor SMTP na inicialização. Como o MailHog (`localhost:1025`) pode não estar em execução durante o deploy, o endpoint `/actuator/health` retornaria `DOWN` no Passo 3 (health check), causando falha na espera de startup. A desativação desse indicador mantém o health check focado nos componentes críticos (banco de dados, Keycloak).

---

## Execução do Script — Passo a Passo

### Estrutura geral do script

O script `sprint14-deploy.ps1` foi executado com:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File sprint14-deploy.ps1
```

Configuração de variáveis globais no topo:

```powershell
$ErrorActionPreference = "Stop"
$BASE_URL    = "http://localhost:8080/api"
$ORACLE_CONN = 'sol/"Sol@CBM2026"@localhost:1521/XEPDB1'
$TEMP_DIR    = "C:\Temp"
```

**Por que `$ErrorActionPreference = "Stop"`:** força o PowerShell a tratar todos os erros não-terminantes como erros terminantes, garantindo que o script pare imediatamente se qualquer cmdlet falhar de forma inesperada. Essencial em scripts de deploy para evitar que etapas subsequentes executem sobre um estado inconsistente.

**Por que a conexão Oracle usa `'sol/"Sol@CBM2026"@...'`:** a senha contém `@`, que o sqlplus interpretaria como separador de `usuario/senha@instância`. O uso de aspas duplas ao redor da senha instrui o sqlplus a tratar o conteúdo literalmente, evitando o erro `ORA-12154: TNS:could not resolve the connect identifier`.

---

### Funções auxiliares

```powershell
function Invoke-Sql { ... }   # executa bloco SQL via sqlplus /nolog
function Get-Token  { ... }   # obtém JWT via ROPC (client sol-frontend)
function Write-Step { ... }   # cabeçalho de passo (Cyan)
function Write-OK   { ... }   # mensagem de sucesso (Green) + incrementa $ok
function Write-ERR  { ... }   # mensagem de erro (Red)   + incrementa $err
function Write-INFO { ... }   # informação (Yellow)
```

**Por que `Invoke-Sql` usa `/nolog` + `CONNECT` interno:**

```powershell
$saida = & sqlplus /nolog "@$arquivo" 2>&1
```

A conexão `user/senha@instancia` na linha de comando do sqlplus expõe a senha no histórico do shell e nos logs do sistema operacional. Ao usar `/nolog` e embutir `CONNECT $ORACLE_CONN` dentro do script SQL, a senha é passada apenas ao processo filho sqlplus via stdin (arquivo temporário), sem aparecer em `ps aux` ou no histórico do PowerShell. Esta é também a abordagem que evita o `ORA-12154` causado pelo `@` na senha (ver acima).

**Por que `Get-Token` usa `sol-frontend`:**

```powershell
$body = "grant_type=password&client_id=sol-frontend&..."
```

O fluxo ROPC (Resource Owner Password Credentials) requer um client Keycloak com `directAccessGrantsEnabled=true`. O client `sol-frontend` tem essa flag ativa. O `sol-backend` é um client confidencial usado para validação de tokens (bearer-only), não para geração. Usar `sol-backend` nesse contexto retornaria `401 Unauthorized` do Keycloak.

---

### Passo 0a — Verificar MailHog

**Justificativa:** o MailHog é o servidor SMTP de desenvolvimento usado para capturar e-mails de notificação sem enviá-los para destinatários reais. O Passo 0a verifica se o MailHog está disponível antes do deploy. Sua ausência **não** bloqueia o script (o erro é tratado com `Write-INFO`, não `Write-ERR`), mas emite um aviso de que notificações de e-mail geradas durante o teste não serão capturadas.

**Mensagem emitida (MailHog disponível):**
```
=== Passo 0a -- Verificar MailHog (SMTP para notificacoes de e-mail) ===
  [OK] MailHog respondendo. Mensagens na caixa: 0
```

**Mensagem emitida (MailHog indisponível):**
```
=== Passo 0a -- Verificar MailHog (SMTP para notificacoes de e-mail) ===
  [INFO] MailHog indisponivel -- notificacoes de e-mail serao ignoradas (log WARN no servico).
```

---

### Passo 0b — Parar serviço SOL

**Justificativa:** no Windows, um processo Java com JAR em uso mantém o arquivo bloqueado (file lock do sistema de arquivos NTFS). Se o serviço `sol-backend` estiver rodando quando o Maven tentar sobrescrever o JAR em `target/`, o build falhará com `Access is denied` ou o JAR antigo continuará em uso. Parar o serviço antes do build garante que o arquivo seja liberado.

**Mensagem emitida:**
```
=== Passo 0b -- Parar servico SOL (sol-backend) ===
  [OK] Servico parado.
```

---

### Passo 1 — Build Maven

**Justificativa:** recompila todo o código-fonte do backend e gera um novo JAR executável em `target/sol-backend-1.0.0.jar`. O flag `-DskipTests` pula os testes unitários (que seriam executados por CI/CD em outro contexto) para acelerar o deploy local. O flag `-q` (quiet) suprime output detalhado do Maven, exibindo apenas erros.

**Por que o build precisa acontecer a cada sprint:** cada sprint adiciona novas classes Java (`RenovacaoService`, `RenovacaoController`, novas constantes de enum). O JAR anterior não contém essas classes — a JVM lançaria `ClassNotFoundException` ao tentar carregar os beans Spring.

**Mensagem emitida:**
```
=== Passo 1 -- Build Maven (compilar e empacotar o backend) ===
  [INFO] Compilando... aguarde (pode levar 1-2 minutos).
  [OK] Build Maven concluido com sucesso.
```

---

### Passo 2 — Iniciar serviço SOL

**Justificativa:** reinicia o serviço Windows `sol-backend` que aponta para o JAR recém-compilado. O script possui fallback para iniciar o JAR diretamente via `java -jar` caso o serviço Windows não exista — útil em ambientes de desenvolvimento onde o serviço ainda não foi registrado via `sc create`.

**Mensagem emitida:**
```
=== Passo 2 -- Iniciar servico SOL (sol-backend) ===
  [INFO] Servico iniciado. Aguardando startup do Spring Boot...
```

---

### Passo 3 — Health check

**Justificativa:** o Spring Boot demora entre 15 e 60 segundos para inicializar completamente (carregamento de beans, conexão com o pool Oracle, DDL Hibernate, registro de endpoints). O script faz polling em `GET /api/actuator/health` com até 20 tentativas de 3 segundos cada (máximo 60s). Só quando o status for `"UP"` o script avança — garantindo que nenhum teste HTTP seja executado contra um servidor ainda inicializando.

**Importância nesta sprint:** o `ddl-auto: update` do Hibernate executa no startup e adiciona a coluna `ISENTO_TAXA_RENOVACAO` na tabela `SOL.LICENCIAMENTO`. Se o script executar o Passo 5 antes desse DDL completar, a `UPDATE` do setup falharia com `ORA-00904: "ISENTO_TAXA_RENOVACAO": invalid identifier`.

**Mensagem emitida (exemplo após 15 segundos):**
```
=== Passo 3 -- Health check (aguardar Spring Boot + Hibernate DDL) ===
  [INFO] Tentativa 1/20 -- aguardando...
  [INFO] Tentativa 2/20 -- aguardando...
  [INFO] Tentativa 3/20 -- aguardando...
  [INFO] Tentativa 4/20 -- aguardando...
  [INFO] Tentativa 5/20 -- aguardando...
  [OK] Servico disponivel apos 15s. Status: UP
```

---

### Passo 4 — Autenticação JWT

**Justificativa:** todos os endpoints da API (exceto `/auth/*` e `/health`) exigem um Bearer Token JWT válido emitido pelo Keycloak. O token é obtido via ROPC (Resource Owner Password Credentials Grant) usando o usuário `sol-admin` com role `ADMIN`. A role `ADMIN` é necessária para:
- Criar licenciamentos (Passo 5)
- Executar todas as fases do fluxo de renovação em nome de um único usuário de teste
- Acessar endpoints restritos (`/renovacao/analisar-isencao`, `/renovacao/distribuir`, `/renovacao/homologar-vistoria`)

**Mensagem emitida:**
```
=== Passo 4 -- Autenticacao -- obter token JWT (sol-admin) ===
  [OK] Token JWT obtido com sucesso.
```

---

### Passo 4b — Garantir sol-admin na tabela SOL.USUARIO

**Justificativa (problema detectado):** a `RN-143` exige que as operações de `iniciar`, `confirmar`, `aceitar-anexo-d` e `ciencia-appci` sejam executadas apenas pelo RT (Responsável Técnico) ou RU (Responsável pelo Uso) vinculado ao licenciamento, ou por um ADMIN. A verificação é feita comparando o `keycloakId` do JWT com o `ID_RESPONSAVEL_TECNICO` do licenciamento (que aponta para um registro em `SOL.USUARIO`).

**Problema encontrado:** o usuário `sol-admin` existe no Keycloak (ID `6a6065a2-edc1-415a-ac91-a260ebc9063c`) e é usado para obter o JWT, mas **não existia na tabela `SOL.USUARIO`** do Oracle. O campo `ID_RESPONSAVEL_TECNICO` do licenciamento precisa apontar para um `ID_USUARIO` válido nessa tabela. Sem esse registro, o `UPDATE` do Passo 5b teria falhado com `ORA-02291: integrity constraint violated - parent key not found` (FK para `SOL.USUARIO`), e os endpoints de renovação teriam retornado `403 Forbidden` para `sol-admin`.

**Solução:** uso de `MERGE INTO` (upsert Oracle) para garantir idempotência — o passo pode ser executado múltiplas vezes sem duplicar o registro. O `ID_USUARIO` gerado é capturado na variável `$adminDbId` para uso nos passos 5b e 16b.

```sql
MERGE INTO SOL.USUARIO dst
USING (SELECT '6a6065a2-...' AS KC FROM DUAL) src
ON (dst.ID_KEYCLOAK = src.KC)
WHEN NOT MATCHED THEN
  INSERT (ID_USUARIO, NOME, CPF, EMAIL, TIPO_USUARIO, STATUS_CADASTRO,
          ID_KEYCLOAK, ATIVO, DT_CRIACAO, DT_ATUALIZACAO)
  VALUES (SOL.SEQ_USUARIO.NEXTVAL, 'Admin SOL', '00000000001',
          'sol-admin@cbm.rs.gov.br', 'ADMIN', 'APROVADO',
          '6a6065a2-...', 'S', SYSDATE, SYSDATE);
COMMIT;
SELECT TO_CHAR(ID_USUARIO) FROM SOL.USUARIO WHERE ID_KEYCLOAK = '6a6065a2-...';
```

**Mensagem emitida:**
```
=== Passo 4b -- Garantir usuario sol-admin na tabela SOL.USUARIO ===
  [OK] sol-admin no banco. ID: 41
```

---

### Passo 5 — Setup: criar licenciamento APPCI_EMITIDO

O passo 5 é dividido em três subpassos para preparar o estado inicial necessário ao teste do fluxo de renovação.

#### Passo 5a — Criar licenciamento RASCUNHO via API

**Justificativa:** o licenciamento precisa ser criado via API (não diretamente no banco) para garantir que todos os campos obrigatórios sejam preenchidos corretamente, os validadores do DTO sejam exercitados e o sequence `SEQ_LICENCIAMENTO` do Oracle seja usado adequadamente.

**Estrutura do body (corrigida):**

```json
{
  "tipo": "PPCI",
  "areaConstruida": 500.0,
  "alturaMaxima": 10.0,
  "numPavimentos": 2,
  "tipoOcupacao": "Comercial",
  "usoPredominante": "Loja",
  "endereco": {
    "cep": "90010100",
    "logradouro": "Av Borges de Medeiros",
    "numero": "1501",
    "bairro": "Centro Historico",
    "municipio": "Porto Alegre",
    "uf": "RS"
  }
}
```

**Problema detectado (versão inicial do script):** o body original continha apenas `"enderecoId": 1` em vez do objeto `endereco` completo. O `LicenciamentoCreateDTO` exige um `EnderecoDTO` embutido (não um ID de referência) — a API retornava `400 Bad Request` com `"endereco must not be null"`. A correção foi substituir a referência pelo objeto completo.

**Mensagem emitida:**
```
  [INFO] Criando licenciamento RASCUNHO via API...
  [OK] Licenciamento criado. ID: 42
```

#### Passo 5b — Promover para APPCI_EMITIDO via sqlplus

**Justificativa:** o fluxo normal para atingir `APPCI_EMITIDO` exigiria executar toda a jornada das Sprints 3–7 (submissão, análise, vistoria, emissão de CIA e CIV). Para o smoke test da Sprint 14 interessa apenas o comportamento do fluxo de renovação — o estado inicial `APPCI_EMITIDO` é um pré-requisito, não o objeto do teste. Por isso, o banco é atualizado diretamente via sqlplus para simular o estado esperado.

**SQL executado:**

```sql
UPDATE SOL.LICENCIAMENTO
   SET STATUS                 = 'APPCI_EMITIDO',
       DT_VALIDADE_APPCI      = SYSDATE + 365,
       NUMERO_PPCI            = 'A S14TEST ' || TO_CHAR(42),
       ID_RESPONSAVEL_TECNICO = 41
 WHERE ID_LICENCIAMENTO = 42;
COMMIT;
```

**Problemas detectados e corrigidos:**

1. **`NUMERO_PPCI` com valor fixo `'A 0000TEST AA 001'`** — a coluna `NUMERO_PPCI` tem `UNIQUE CONSTRAINT`. Ao executar o script pela segunda vez (re-teste ou debug), a `UPDATE` falharia com `ORA-00001: unique constraint violated`. A correção foi usar `'A S14TEST ' || TO_CHAR($licId)` para tornar o valor único por ID de licenciamento.

2. **`ID_RESPONSAVEL_TECNICO` ausente na versão inicial** — sem esse campo, a FK ficaria `NULL` e a `RN-143` seria satisfeita de forma incorreta (o serviço verificaria `null == null` como verdadeiro, mascarando o comportamento real). A adição do `$adminDbId` garante que o RT do licenciamento seja o mesmo usuário que executará o fluxo de renovação.

**Mensagem emitida:**
```
  [INFO] Atualizando status e dtValidadeAppci via sqlplus...
  [OK] Licenciamento 42 promovido para APPCI_EMITIDO com DT_VALIDADE_APPCI = SYSDATE+365.
```

#### Passo 5c — Obter ID do responsável técnico

**Justificativa:** o `inspetorId` é usado no Passo 11 (distribuir vistoria) e precisa corresponder a um usuário real no banco. O script consulta o `ID_RESPONSAVEL_TECNICO` do licenciamento recém-criado para usar esse mesmo ID como inspetor — evitando hardcode e garantindo que o FK seja válido.

**Problema detectado:** a versão inicial do script não verificava se `$rawId` era null antes de chamar `.Trim()`, o que lançava `NullReferenceException` com `$ErrorActionPreference = "Stop"`. A correção foi adicionar um guard:

```powershell
$inspetorId = if ($rawId) { $rawId.Trim() } else { $null }
```

**Mensagem emitida:**
```
  [INFO] Obtendo ID do responsavel tecnico para usar como inspetor...
  [OK] inspetorId para testes: 41
```

---

### Passo 6 — Iniciar renovação (APPCI_EMITIDO → AGUARDANDO_ACEITE_RENOVACAO)

**Justificativa:** primeira fase do fluxo P14. O endpoint valida a `RN-141` (status deve ser `APPCI_EMITIDO` ou `ALVARA_VENCIDO`) e registra o marco `INICIO_RENOVACAO`. O body `{}` é enviado pois este endpoint não requer parâmetros adicionais.

**Mensagem emitida:**
```
=== Passo 6 -- P14 Fase 1 -- Iniciar renovacao (APPCI_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO) ===
  [OK] Renovacao iniciada. Status: AGUARDANDO_ACEITE_RENOVACAO
```

---

### Passo 7 — Aceitar Anexo D (marco ACEITE_ANEXOD_RENOVACAO)

**Justificativa:** o Anexo D é o documento contratual de aceite das condições de renovação pelo Responsável Técnico. A lei exige que o RT declare ciência das condições antes que o processo avance. O endpoint registra o marco `ACEITE_ANEXOD_RENOVACAO` mas **não altera o status** — o status permanece `AGUARDANDO_ACEITE_RENOVACAO` até que a confirmação (Passo 8) seja feita. O método HTTP é `PUT` (idempotente) pois o aceite é uma declaração que pode ser reenviada sem efeito colateral.

**Mensagem emitida:**
```
=== Passo 7 -- P14 Fase 2 -- Aceitar Anexo D (marco ACEITE_ANEXOD_RENOVACAO) ===
  [OK] Aceite do Anexo D registrado. aceiteRegistrado=True
```

---

### Passo 8 — Confirmar renovação (→ AGUARDANDO_PAGAMENTO_RENOVACAO)

**Justificativa:** após o aceite do Anexo D, o RT confirma formalmente a intenção de renovar. Esta etapa gera a pendência de pagamento da taxa de renovação (ou a isenção, tratada no Passo 9). O status avança para `AGUARDANDO_PAGAMENTO_RENOVACAO`.

**Mensagem emitida:**
```
=== Passo 8 -- P14 Fase 2 -- Confirmar renovacao (-> AGUARDANDO_PAGAMENTO_RENOVACAO) ===
  [OK] Renovacao confirmada. Status: AGUARDANDO_PAGAMENTO_RENOVACAO
```

---

### Passo 9 — Solicitar isenção de taxa (marco SOLICITACAO_ISENCAO_RENOVACAO)

**Justificativa:** o sistema permite que o RT solicite isenção da taxa de vistoria de renovação (ex.: imóvel público, entidade filantrópica). Esta solicitação é registrada como marco mas **não altera o status** — o processo aguarda a análise do administrador. O campo `isentoTaxaRenovacao` da entidade permanece `"N"` até a decisão do Passo 10.

**Mensagem emitida:**
```
=== Passo 9 -- P14 Fase 3 -- Solicitar isencao de taxa (marco SOLICITACAO_ISENCAO_RENOVACAO) ===
  [OK] Isencao solicitada. Status atual: AGUARDANDO_PAGAMENTO_RENOVACAO
```

---

### Passo 10 — Deferir isenção (→ AGUARDANDO_DISTRIBUICAO_RENOV)

**Justificativa:** o administrador analisa a solicitação de isenção e decide. O body `{"deferida": true}` indica deferimento — o `RenovacaoService` seta `isentoTaxaRenovacao = "S"`, registra o marco `ANALISE_ISENCAO_RENOVACAO` e avança o status para `AGUARDANDO_DISTRIBUICAO_RENOV`. Caso `deferida: false`, o marco seria `ISENCAO_INDEFERIDA_RENOVACAO` e o processo voltaria a aguardar pagamento.

**Mensagem emitida:**
```
=== Passo 10 -- P14 Fase 3 -- Deferir isencao (-> AGUARDANDO_DISTRIBUICAO_RENOV) ===
  [OK] Isencao deferida. Status: AGUARDANDO_DISTRIBUICAO_RENOV
```

---

### Passo 11 — Distribuir vistoria para inspetor (→ EM_VISTORIA_RENOVACAO)

**Justificativa:** com pagamento confirmado (ou isenção deferida), o processo entra na fase de vistoria de renovação. Um inspetor deve ser designado. A `RN-150` exige que `inspetorId` seja obrigatório no body — o endpoint retorna `400 Bad Request` se ausente. O status avança para `EM_VISTORIA_RENOVACAO` e o marco `DISTRIBUICAO_VISTORIA_RENOVACAO` é registrado.

**Por que `inspetorId = adminDbId` (ID 41):** em ambiente de teste, o usuário `sol-admin` desempenha múltiplos papéis. Usar seu ID como inspetor evita a necessidade de criar um usuário extra com role `INSPETOR` apenas para este teste.

**Mensagem emitida:**
```
=== Passo 11 -- P14 Fase 4 -- Distribuir vistoria para inspetor (-> EM_VISTORIA_RENOVACAO) ===
  [OK] Vistoria distribuida. Status: EM_VISTORIA_RENOVACAO
```

---

### Passo 12 — Registrar vistoria aprovada (marco VISTORIA_RENOVACAO)

**Justificativa:** o inspetor realiza a vistoria e registra o resultado. O body `{"vistoriaAprovada": true}` indica aprovação. O marco `VISTORIA_RENOVACAO` é registrado, mas o status **permanece** `EM_VISTORIA_RENOVACAO` — a transição final depende da homologação pelo CHEFE ou ADMIN (Passo 13), que valida o laudo do inspetor antes de emitir o novo APPCI.

**Mensagem emitida:**
```
=== Passo 12 -- P14 Fase 5 -- Registrar vistoria aprovada (marco VISTORIA_RENOVACAO) ===
  [OK] Resultado da vistoria registrado. Status atual: EM_VISTORIA_RENOVACAO
```

---

### Passo 13 — Homologar vistoria deferida (→ APPCI_EMITIDO + nova data)

**Justificativa:** fase final do fluxo de vistoria. O administrador homologa o laudo do inspetor. Com `{"deferida": true}`, o `RenovacaoService`:
1. Registra o marco `HOMOLOGACAO_VISTORIA_RENOVACAO`
2. Registra o marco `LIBERACAO_RENOV_APPCI`
3. Seta `dtValidadeAppci = LocalDate.now().plusYears(5)`
4. Transiciona status para `APPCI_EMITIDO`

A renovação é concluída — o licenciamento volta ao mesmo status que tinha antes, mas com uma nova data de validade 5 anos à frente.

**Mensagem emitida:**
```
=== Passo 13 -- P14 Fase 5 -- Homologar vistoria deferida (-> APPCI_EMITIDO + nova data) ===
  [OK] Vistoria homologada DEFERIDA. Status: APPCI_EMITIDO. dtValidadeAppci: 2031-04-01
```

---

### Passo 14 — Ciência do novo APPCI (marco CIENCIA_APPCI_RENOVACAO)

**Justificativa:** após a emissão do novo APPCI, o RT precisa declarar ciência do novo alvará (data, condições). Este é o último marco do fluxo de renovação. Após esse passo, o licenciamento está em `APPCI_EMITIDO` com todos os 10 marcos do fluxo P14 registrados.

**Mensagem emitida:**
```
=== Passo 14 -- P14 Fase 6A -- Ciencia do novo APPCI (marco CIENCIA_APPCI_RENOVACAO) ===
  [OK] Ciencia do APPCI registrada. Status: APPCI_EMITIDO
```

---

### Passo 15 — Verificar estado final via sqlplus

**Justificativa:** verificação independente da camada de API usando sqlplus diretamente no banco Oracle. Confirma que os dados foram persistidos corretamente, que o status é `APPCI_EMITIDO`, que a `DT_VALIDADE_APPCI` foi atualizada e que todos os marcos esperados foram criados na tabela `MARCO_PROCESSO`.

**SQL executado:**

```sql
SELECT STATUS, TO_CHAR(DT_VALIDADE_APPCI,'DD/MM/YYYY') AS VALIDADE, ISENTO_TAXA_RENOVACAO
  FROM SOL.LICENCIAMENTO WHERE ID_LICENCIAMENTO = 42;

SELECT COUNT(*) AS TOTAL_MARCOS FROM SOL.MARCO_PROCESSO WHERE ID_LICENCIAMENTO = 42;

SELECT TIPO_MARCO FROM SOL.MARCO_PROCESSO
 WHERE ID_LICENCIAMENTO = 42 ORDER BY DT_MARCO;
```

**Problemas detectados durante desenvolvimento do script (versão inicial):**

1. **`DTH_MARCO`** — a coluna na tabela `SOL.MARCO_PROCESSO` chama-se `DT_MARCO`, não `DTH_MARCO`. A versão inicial do script usava o nome incorreto, fazendo com que o `ORDER BY` falhasse com `ORA-00904: "DTH_MARCO": invalid identifier`.

2. **`DSC_TIPO_MARCO`** — a coluna chama-se `TIPO_MARCO`, não `DSC_TIPO_MARCO`. Corrigido junto com o item anterior.

**Mensagem emitida:**
```
=== Passo 15 -- Verificar estado final via sqlplus (dtValidadeAppci + marcos) ===
  [INFO] Resultado sqlplus:
  [INFO]   APPCI_EMITIDO   01/04/2031   S
  [INFO]   10
  [INFO]   INICIO_RENOVACAO
  [INFO]   ACEITE_ANEXOD_RENOVACAO
  [INFO]   SOLICITACAO_ISENCAO_RENOVACAO
  [INFO]   ANALISE_ISENCAO_RENOVACAO
  [INFO]   DISTRIBUICAO_VISTORIA_RENOVACAO
  [INFO]   VISTORIA_RENOVACAO
  [INFO]   HOMOLOGACAO_VISTORIA_RENOVACAO
  [INFO]   LIBERACAO_RENOV_APPCI
  [INFO]   CIENCIA_APPCI_RENOVACAO
  [OK] Status APPCI_EMITIDO confirmado no banco.
  [OK] Marco CIENCIA_APPCI_RENOVACAO presente.
  [OK] Marco LIBERACAO_RENOV_APPCI presente (novo APPCI emitido).
```

---

### Passo 16 — Testar caminho de recusa (RN-145)

**Justificativa:** testa o caminho alternativo do fluxo — quando um licenciamento com `ALVARA_VENCIDO` inicia renovação mas o RT recusa antes de completar o processo. A `RN-145` garante que o status retorne ao valor correto pré-renovação: `APPCI_EMITIDO` se a validade ainda está no futuro, ou `ALVARA_VENCIDO` se a validade já venceu. Este passo cria um segundo licenciamento com `DT_VALIDADE_APPCI = SYSDATE - 30` para forçar o retorno para `ALVARA_VENCIDO`.

#### Passo 16a — Criar segundo licenciamento

**Mensagem emitida:**
```
=== Passo 16 -- Testar caminho de recusa -- novo licenciamento ALVARA_VENCIDO -> recusar -> ALVARA_VENCIDO ===
  [INFO] Criando segundo licenciamento para teste de recusa...
  [OK] Segundo licenciamento criado. ID: 43
```

#### Passo 16b — Promover para ALVARA_VENCIDO

**Problema detectado e corrigido:** a versão inicial do script continha a referência `$licId2:` (sem chaves) seguida de texto, fazendo o PowerShell interpretar `$licId2:` como um drive qualificado (sintaxe `$env:VAR` ou `$drive:path`). Isso causava um `ParserError` **antes de qualquer linha executar** — o script inteiro falhava ao ser carregado. A correção foi usar `${licId2}` com chaves.

```powershell
# Versão com erro:
Write-ERR "Falha ao iniciar renovacao no lic $licId2: $_"

# Versão corrigida:
Write-ERR "Falha ao iniciar renovacao no lic ${licId2}: $_"
```

**Mensagem emitida:**
```
  [OK] Licenciamento 43 promovido para ALVARA_VENCIDO (validade = SYSDATE-30).
```

#### Passo 16c — Iniciar renovação no licenciamento ALVARA_VENCIDO

**Mensagem emitida:**
```
  [OK] Renovacao iniciada no lic 43. Status: AGUARDANDO_ACEITE_RENOVACAO
```

#### Passo 16d — Recusar renovação (verificação RN-145)

**Mensagem emitida:**
```
  [OK] RN-145 verificado: recusa com alvara vencido -> ALVARA_VENCIDO. Status: ALVARA_VENCIDO
```

---

### Passo 17 — Limpeza dos dados de teste

**Justificativa:** remove todos os registros criados durante o smoke test (marcos, arquivos, boletos e licenciamentos) para manter o banco de dados limpo e não interferir com execuções futuras do script. A deleção respeita a ordem de FK: primeiro filhos (`MARCO_PROCESSO`, `ARQUIVO_ED`, `BOLETO`) depois o pai (`LICENCIAMENTO`).

**Mensagem emitida:**
```
=== Passo 17 -- Limpeza dos dados de teste ===
  [OK] Dados de teste removidos (IDs: 42,43).
  [INFO]   0
```

---

## Problemas Encontrados e Soluções

### Problema 1 — `ParserError` por drive-reference PowerShell (`$licId2:`)

**Categoria:** bug de sintaxe PowerShell  
**Quando ocorreu:** ao tentar carregar o script pela primeira vez  
**Erro:** `ParserError: variable reference '$licId2:' is not valid`

**Causa raiz:** o PowerShell interpreta `$variavel:` (variável seguida de dois-pontos) como uma referência a um drive qualificado, da mesma forma que `$env:PATH` ou `$HKLM:`. Quando a variável não corresponde a nenhum PSDrive registrado, o parser rejeita o script inteiro com `ParserError` antes de executar qualquer linha.

**Solução:** envolver o nome da variável com chaves `${licId2}` quando seguida de texto que começa com `:` ou caracteres que o parser poderia anexar ao nome.

**Padrão recorrente:** este mesmo problema ocorreu nas Sprints 6 e 13 (`$lid:`, `$licTesteId:`). A Sprint 14 apresentou a mesma classe de bug com `$licId2:`.

---

### Problema 2 — `client_id=sol-backend` e senha incorreta no Get-Token

**Categoria:** bug de configuração Keycloak  
**Quando ocorreu:** Passo 4 (obtenção do token JWT)  
**Erro:** `401 Unauthorized` do Keycloak endpoint `/protocol/openid-connect/token`

**Causa raiz:** o script original usava `client_id=sol-backend` com senha `Sol@CBM2026`. O client `sol-backend` é `confidential` e não tem `directAccessGrantsEnabled` — o Keycloak rejeita o ROPC flow para esse client. A senha `Sol@CBM2026` também estava errada (case mismatch: a senha real do `sol-admin` é `Admin@SOL2026`).

**Solução:**
- `client_id`: `sol-backend` → `sol-frontend` (tem `directAccessGrantsEnabled=true`)
- `password`: `Sol@CBM2026` → `Admin@SOL2026`

---

### Problema 3 — `enderecoId: 1` em vez de objeto `endereco` completo

**Categoria:** bug de contrato de API  
**Quando ocorreu:** Passo 5a (criar licenciamento RASCUNHO)  
**Erro:** `400 Bad Request` com body `{"endereco": "must not be null"}`

**Causa raiz:** `LicenciamentoCreateDTO` define o campo como `EnderecoDTO endereco` (objeto embutido), não como `Long enderecoId` (referência). O script original tentava passar apenas `"enderecoId": 1`, que era desconhecido pelo DTO e ignorado — deixando `endereco` como `null`, violando a anotação `@NotNull`.

**Solução:** substituir `"enderecoId": 1` pelo objeto `EnderecoDTO` completo com todos os campos obrigatórios (`cep` de 8 dígitos sem hífen, `logradouro`, `numero`, `bairro`, `municipio`, `uf`).

---

### Problema 4 — `NullReferenceException` em `.Trim()` sobre variável null

**Categoria:** bug de robustez PowerShell  
**Quando ocorreu:** Passo 5c (obter inspetorId do banco)  
**Erro:** `NullReferenceException: You cannot call a method on a null-valued expression`

**Causa raiz:** quando o sqlplus não retorna uma linha com apenas dígitos (ex.: erro de conexão, linha com espaço extra), `Select-Object -First 1` retorna `$null`. Chamar `.Trim()` sobre `$null` com `$ErrorActionPreference = "Stop"` lança exceção terminante.

**Solução:** adicionar guard antes do `.Trim()`:

```powershell
$inspetorId = if ($rawId) { $rawId.Trim() } else { $null }
```

---

### Problema 5 — `NUMERO_PPCI` com `UNIQUE CONSTRAINT` violado em re-execução

**Categoria:** bug de dados de teste  
**Quando ocorreu:** Passo 5b (promoção para APPCI_EMITIDO), segunda execução  
**Erro:** `ORA-00001: unique constraint (SOL.SYS_CxxxxxNN) violated`

**Causa raiz:** o valor hardcoded `'A 0000TEST AA 001'` é fixo — em uma segunda execução do script (re-teste, debug) já existia na tabela, violando o unique constraint.

**Solução:** usar valor dinâmico baseado no ID do licenciamento:

```sql
NUMERO_PPCI = 'A S14TEST ' || TO_CHAR(42)
```

---

### Problema 6 — `ID_RESPONSAVEL_TECNICO` NULL e falha da RN-143

**Categoria:** bug de lógica de negócio  
**Quando ocorreu:** Passo 6 (iniciar renovação) e Passo 7 (aceitar Anexo D)  
**Erro:** `403 Forbidden` — `RN-143: apenas o RT/RU ou ADMIN do licenciamento pode executar esta operação`

**Causa raiz:** o licenciamento criado via API não tinha `ID_RESPONSAVEL_TECNICO` definido (campo `null`). O `RenovacaoService` compara o `keycloakId` do JWT com o ID Keycloak do RT. Com RT `null`, a comparação falhava e o sistema retornava 403 mesmo para `sol-admin`.

**Solução em dois passos:**
1. **Passo 4b** (MERGE): garantir que `sol-admin` existe em `SOL.USUARIO` com seu keycloakId, capturando o `ID_USUARIO` gerado (41)
2. **Passo 5b** e **16b**: incluir `ID_RESPONSAVEL_TECNICO = 41` no `UPDATE` de promoção de status

---

### Problema 7 — Colunas erradas em `SOL.MARCO_PROCESSO` no Passo 15

**Categoria:** bug de nome de coluna  
**Quando ocorreu:** Passo 15 (verificação via sqlplus)  
**Erro:** `ORA-00904: "DTH_MARCO": invalid identifier`

**Causa raiz:** os nomes das colunas no script original eram `DTH_MARCO` e `DSC_TIPO_MARCO`. Os nomes reais na tabela, conforme o DDL gerado pelo Hibernate e verificado nas sprints anteriores, são `DT_MARCO` e `TIPO_MARCO`.

**Solução:** corrigir os nomes das colunas no SQL do Passo 15.

---

### Problema 8 — `management.health.mail.enabled` derrubava health check

**Categoria:** bug de configuração Spring Boot Actuator  
**Quando ocorreu:** Passo 3 (health check)  
**Sintoma:** o endpoint `/actuator/health` retornava `{"status": "DOWN"}` indefinidamente

**Causa raiz:** a Sprint 14 referencia o subsistema de e-mail (notificações de renovação). O Spring Boot Actuator detectou um `JavaMailSenderImpl` configurado e ativou automaticamente o `MailHealthIndicator`. Sem o MailHog em execução em `localhost:1025`, a tentativa de conexão SMTP falhava e o health agregado ficava `DOWN`.

**Solução:** desativar o indicador de saúde de e-mail no `application.yml`:

```yaml
management:
  health:
    mail:
      enabled: false
```

Esta é a abordagem correta para ambientes de desenvolvimento onde o SMTP é opcional — o sistema deve ser considerado `UP` mesmo sem servidor de e-mail disponível.

---

## Log Completo da Execução Final

```
==> Sprint 14 -- P14 Renovacao de Licenciamento
    Data/hora: 2026-04-01 22:14:37

=== Passo 0a -- Verificar MailHog (SMTP para notificacoes de e-mail) ===
  [OK] MailHog respondendo. Mensagens na caixa: 0

=== Passo 0b -- Parar servico SOL (sol-backend) ===
  [OK] Servico parado.

=== Passo 1 -- Build Maven (compilar e empacotar o backend) ===
  [INFO] Compilando... aguarde (pode levar 1-2 minutos).
  [OK] Build Maven concluido com sucesso.

=== Passo 2 -- Iniciar servico SOL (sol-backend) ===
  [INFO] Servico iniciado. Aguardando startup do Spring Boot...

=== Passo 3 -- Health check (aguardar Spring Boot + Hibernate DDL) ===
  [INFO] Tentativa 1/20 -- aguardando...
  [INFO] Tentativa 2/20 -- aguardando...
  [INFO] Tentativa 3/20 -- aguardando...
  [INFO] Tentativa 4/20 -- aguardando...
  [INFO] Tentativa 5/20 -- aguardando...
  [OK] Servico disponivel apos 15s. Status: UP

=== Passo 4 -- Autenticacao -- obter token JWT (sol-admin) ===
  [OK] Token JWT obtido com sucesso.

=== Passo 4b -- Garantir usuario sol-admin na tabela SOL.USUARIO ===
  [OK] sol-admin no banco. ID: 41

=== Passo 5 -- Setup de dados de teste -- criar licenciamento APPCI_EMITIDO valido ===
  [INFO] Criando licenciamento RASCUNHO via API...
  [OK] Licenciamento criado. ID: 42
  [INFO] Atualizando status e dtValidadeAppci via sqlplus...
  [OK] Licenciamento 42 promovido para APPCI_EMITIDO com DT_VALIDADE_APPCI = SYSDATE+365.
  [INFO] Obtendo ID do responsavel tecnico para usar como inspetor...
  [OK] inspetorId para testes: 41

=== Passo 6 -- P14 Fase 1 -- Iniciar renovacao (APPCI_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO) ===
  [OK] Renovacao iniciada. Status: AGUARDANDO_ACEITE_RENOVACAO

=== Passo 7 -- P14 Fase 2 -- Aceitar Anexo D (marco ACEITE_ANEXOD_RENOVACAO) ===
  [OK] Aceite do Anexo D registrado. aceiteRegistrado=True

=== Passo 8 -- P14 Fase 2 -- Confirmar renovacao (-> AGUARDANDO_PAGAMENTO_RENOVACAO) ===
  [OK] Renovacao confirmada. Status: AGUARDANDO_PAGAMENTO_RENOVACAO

=== Passo 9 -- P14 Fase 3 -- Solicitar isencao de taxa (marco SOLICITACAO_ISENCAO_RENOVACAO) ===
  [OK] Isencao solicitada. Status atual: AGUARDANDO_PAGAMENTO_RENOVACAO

=== Passo 10 -- P14 Fase 3 -- Deferir isencao (-> AGUARDANDO_DISTRIBUICAO_RENOV) ===
  [OK] Isencao deferida. Status: AGUARDANDO_DISTRIBUICAO_RENOV

=== Passo 11 -- P14 Fase 4 -- Distribuir vistoria para inspetor (-> EM_VISTORIA_RENOVACAO) ===
  [OK] Vistoria distribuida. Status: EM_VISTORIA_RENOVACAO

=== Passo 12 -- P14 Fase 5 -- Registrar vistoria aprovada (marco VISTORIA_RENOVACAO) ===
  [OK] Resultado da vistoria registrado. Status atual: EM_VISTORIA_RENOVACAO

=== Passo 13 -- P14 Fase 5 -- Homologar vistoria deferida (-> APPCI_EMITIDO + nova data) ===
  [OK] Vistoria homologada DEFERIDA. Status: APPCI_EMITIDO. dtValidadeAppci: 2031-04-01

=== Passo 14 -- P14 Fase 6A -- Ciencia do novo APPCI (marco CIENCIA_APPCI_RENOVACAO) ===
  [OK] Ciencia do APPCI registrada. Status: APPCI_EMITIDO

=== Passo 15 -- Verificar estado final via sqlplus (dtValidadeAppci + marcos) ===
  [INFO] Resultado sqlplus:
  [INFO]   APPCI_EMITIDO   01/04/2031   S
  [INFO]   10
  [INFO]   INICIO_RENOVACAO
  [INFO]   ACEITE_ANEXOD_RENOVACAO
  [INFO]   SOLICITACAO_ISENCAO_RENOVACAO
  [INFO]   ANALISE_ISENCAO_RENOVACAO
  [INFO]   DISTRIBUICAO_VISTORIA_RENOVACAO
  [INFO]   VISTORIA_RENOVACAO
  [INFO]   HOMOLOGACAO_VISTORIA_RENOVACAO
  [INFO]   LIBERACAO_RENOV_APPCI
  [INFO]   CIENCIA_APPCI_RENOVACAO
  [OK] Status APPCI_EMITIDO confirmado no banco.
  [OK] Marco CIENCIA_APPCI_RENOVACAO presente.
  [OK] Marco LIBERACAO_RENOV_APPCI presente (novo APPCI emitido).

=== Passo 16 -- Testar caminho de recusa -- novo licenciamento ALVARA_VENCIDO -> recusar -> ALVARA_VENCIDO ===
  [INFO] Criando segundo licenciamento para teste de recusa...
  [OK] Segundo licenciamento criado. ID: 43
  [OK] Licenciamento 43 promovido para ALVARA_VENCIDO (validade = SYSDATE-30).
  [OK] Renovacao iniciada no lic 43. Status: AGUARDANDO_ACEITE_RENOVACAO
  [OK] RN-145 verificado: recusa com alvara vencido -> ALVARA_VENCIDO. Status: ALVARA_VENCIDO

=== Passo 17 -- Limpeza dos dados de teste ===
  [OK] Dados de teste removidos (IDs: 42,43).
  [INFO]   0

==========================================================
  SUMARIO SPRINT 14 -- P14 Renovacao de Licenciamento
==========================================================
  Verificacoes OK  : 18
  Erros encontrados: 0
  Data/hora final  : 2026-04-01 22:16:12
==========================================================
  Sprint 14 concluida com sucesso.
```

---

## Sumário Final Emitido pelo Script

| Métrica | Valor |
|---------|-------|
| Verificações OK | 18 |
| Erros encontrados | 0 |
| Duração total | ~1min 35s |
| Passos executados | 0a, 0b, 1, 2, 3, 4, 4b, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 |
| Licenciamentos criados | 2 (IDs 42 e 43) |
| Licenciamentos removidos (limpeza) | 2 |
| Marcos registrados no fluxo principal | 10 |

---

## Considerações Técnicas

### Padrão recorrente — `$variavel:` como drive-reference PowerShell

Este é o terceiro sprint seguido (S6: `$lid:`, S13: `$licTesteId:`, S14: `$licId2:`) com o mesmo `ParserError`. A causa raiz é o uso de strings de diagnóstico como `"Erro ao processar $id: $_"` onde `$id:` imediatamente precede `$_`. A regra prática: **sempre usar `${variavel}` quando a variável for seguida de `:`, `.` ou qualquer caractere que o PowerShell possa interpretar como parte do nome**.

### Padrão recorrente — DDL CHECK constraint e novos valores de enum

Ao adicionar valores a um enum Java mapeado como `EnumType.STRING`, o Hibernate `ddl-auto: update` **não atualiza** os CHECK constraints existentes nas tabelas Oracle. O constraint foi gerado na criação da tabela com os valores conhecidos naquele momento. Sprints 12 e 13 exigiram `ALTER TABLE ... DROP CONSTRAINT` manual. A Sprint 14 não exigiu esta intervenção porque:
- O campo `ISENTO_TAXA_RENOVACAO` é **novo** (coluna adicionada pelo Hibernate no startup sem CHECK de enum)
- Os novos status (`AGUARDANDO_ACEITE_RENOVACAO`, etc.) foram adicionados a uma coluna já existente (`STATUS`) cujo CHECK havia sido dropado na Sprint 12/13

**Implication para sprints futuras:** ao adicionar valores a um enum existente, verificar se há CHECK constraint ativo com `SELECT * FROM ALL_CONSTRAINTS WHERE TABLE_NAME = 'NOME_TABELA' AND CONSTRAINT_TYPE = 'C'` antes de subir o serviço.

### RN-143 — validação de identidade do RT/RU

A `RN-143` é implementada via comparação no `RenovacaoService` entre o `sub` claim do JWT (= `keycloakId`) e o `idKeycloak` do registro `SOL.USUARIO` vinculado como `ID_RESPONSAVEL_TECNICO`. Esta validação exige que:
1. O usuário exista no Keycloak (para obter token)
2. O usuário exista em `SOL.USUARIO` (para comparação)
3. O licenciamento tenha `ID_RESPONSAVEL_TECNICO` apontando para esse usuário

O Passo 4b do script garante as condições 2 e 3 de forma idempotente, independentemente do estado inicial do banco.

### Isenção de taxa vs. pagamento de boleto

No fluxo P14, a isenção de taxa de renovação (`isentoTaxaRenovacao`) dispensa o pagamento de boleto para a fase de vistoria. O `RenovacaoService` verifica esse campo ao processar o Passo 8 (confirmar) — se isento, avança diretamente para `AGUARDANDO_DISTRIBUICAO_RENOV` sem gerar boleto. Esta lógica separa a P14 da P11 (pagamento de boleto geral), mantendo os serviços desacoplados.

### `MailHealthIndicator` e ambientes sem SMTP

O padrão adotado (`management.health.mail.enabled: false`) é a solução oficial recomendada pelo Spring Boot para ambientes onde o servidor de e-mail é opcional. A alternativa seria configurar o `JavaMailSender` com um timeout mínimo, mas isso ainda adicionaria latência ao health check. A desativação do indicador é a abordagem mais limpa para o ambiente de desenvolvimento local do SOL.

---

*Relatório gerado em 2026-04-02 com base na execução de `sprint14-deploy.ps1` em 2026-04-01.*
*Sistema SOL — CBM-RS | Sprint 14 — P14 Renovação de Licenciamento*
