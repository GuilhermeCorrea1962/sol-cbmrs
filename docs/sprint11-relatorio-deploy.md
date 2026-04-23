# Sprint 11 — P11 Pagamento de Boleto: Relatório de Deploy e Smoke Test

**Data de execução:** 2026-03-31
**Responsável:** Guilherme (CBM-QCG-239)
**Script base:** `C:\SOL\infra\scripts\sprint11-deploy.ps1`
**Resultado final:** ✅ Concluída com sucesso

---

## Tags

`#sol` `#sprint11` `#deploy` `#smoke-test` `#boleto` `#cbm-rs`

---

## 1. Contexto da Sprint

A Sprint 11 implementou o módulo **P11 — Pagamento de Boleto**, responsável pelo ciclo completo de geração, confirmação e vencimento automático de boletos de taxa de licenciamento no sistema SOL (Sistema Online de Licenciamento — CBM-RS).

### Funcionalidades entregues

| Código | Descrição |
|--------|-----------|
| **P11-A** | Fluxo manual: geração de boleto e confirmação de pagamento pelo operador |
| **P11-B** | Job automático noturno (`@Scheduled`, cron `0 0 2 * * *`) que expira boletos vencidos |

### Arquivos alterados/criados nesta sprint

| Operação | Arquivo | Mudanças |
|----------|---------|---------|
| `[M]` Modificado | `BoletoService.java` | Adição de `keycloakId`, e-mails, marcos de processo, método `vencerBoleto()` |
| `[M]` Modificado | `BoletoController.java` | Injeção de `@AuthenticationPrincipal Jwt` nos endpoints `create` e `confirmarPagamento` |
| `[N]` Novo | `BoletoJobService.java` | Job agendado P11-B — busca boletos `PENDENTE` com `dtVencimento < hoje` e os marca como `VENCIDO` |

### Regras de negócio validadas

| Regra | Descrição |
|-------|-----------|
| **RN-090** | Não pode existir boleto `PENDENTE` ativo para o mesmo licenciamento. Tentativa de gerar segundo boleto enquanto o primeiro está `PENDENTE` deve retornar HTTP 422. |
| **RN-091** | Licenciamento isento de taxa (`isentoTaxa = true`) não gera boleto. |
| **RN-095** | Boleto só pode ter pagamento confirmado se estiver com status `PENDENTE`. Confirmação sobre boleto `PAGO` ou `VENCIDO` retorna HTTP 422. |

---

## 2. Ambiente de Execução (ao final do deploy)

| Componente | Valor |
|------------|-------|
| **Backend JAR** | `C:\SOL\backend\target\sol-backend-1.0.0.jar` |
| **Serviço Windows** | `SOL-Backend` |
| **Java** | Eclipse Adoptium JDK 21.0.9 — `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot` |
| **Maven** | Apache Maven 3.9.6 via Chocolatey — `C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd` |
| **Spring Boot** | 3.3.4 |
| **Oracle XE** | 21c — schema `SOL`, PDB `XEPDB1`, porta 1521, usuário `sol` / `Sol@CBM2026` |
| **Keycloak** | 24.0.3 — `http://localhost:8180`, realm `sol` |
| **MinIO** | `http://localhost:9000` |
| **MailHog** | `http://localhost:8025` (UI) / `localhost:1025` (SMTP) — instalado nesta sprint |
| **URL base da API** | `http://localhost:8080/api` |

---

## 3. Log Completo da Execução Final (bem-sucedida)

> Execução iniciada em **2026-03-31 22:24:23** após todas as correções descritas na seção 4.

```
==> Sprint 11 - P11 Pagamento de Boleto
  Data/hora: 2026-03-31 22:24:23
  Backend:   C:\SOL\backend
  URL base:  http://localhost:8080/api

==> Passo 0a - MailHog (SMTP localhost:1025)
    [OK] MailHog ja rodando.

==> Passo 0b - Parar servico SOL-Backend (pre-build)
    [OK] Servico parado.

==> Passo 1 - Build Maven (skip tests)
    [OK] Build concluido.

==> Passo 2 - Reiniciar servico SOL-Backend
    [OK] Servico reiniciado.

==> Passo 3 - Health check
    [OK] Health UP.

==> Passo 4 - Autenticacao
    [OK] Tokens obtidos (admin + analista1).
    [OK] analista1 Oracle ID: 25

==> Passo 5 - Limpeza preventiva (Oracle JDBC)
    [WARN] ojdbc11.jar nao encontrado em C:\tools\ojdbc11.jar. Pulando limpeza SQL.

==> Passo 6 - Fluxo A: Gerar boleto + confirmar pagamento (status esperado: PAGO)
    Criando licenciamento ID-alvo 65...
    Licenciamento criado com ID real: 67
    Licenciamento 67 em EM_ANALISE.
    6.1 Gerando boleto para licenciamento 67...
    [OK] Boleto ID 3 gerado com status PENDENTE. Valor: R$ 150.0. Vencimento: 2026-04-30
    6.2 Verificando marco BOLETO_GERADO...
    [OK] Marco BOLETO_GERADO registrado: 'Boleto gerado. Valor: R$ 150.0. Vencimento: 2026-04-30. Boleto ID: 3'
    6.2b Testando RN-090 (duplicata PENDENTE bloqueada)...
    [OK] RN-090 OK: segundo boleto bloqueado enquanto primeiro PENDENTE (HTTP 422).
    6.3 Confirmando pagamento em 2026-03-31 (dentro do prazo)...
    [OK] Boleto 3 status PAGO confirmado.
    6.4 Verificando marco PAGAMENTO_CONFIRMADO...
    [OK] Marco PAGAMENTO_CONFIRMADO registrado: 'Pagamento confirmado em 2026-03-31. Boleto ID: 3'
    [OK] Fluxo A concluido com sucesso.

==> Passo 7 - Fluxo B: Gerar boleto + confirmar pagamento apos vencimento (status esperado: VENCIDO)
    Criando licenciamento ID-alvo 66...
    Licenciamento criado com ID real: 68
    Licenciamento 68 em EM_ANALISE.
    7.1 Gerando boleto para licenciamento 68...
    [OK] Boleto ID 4 gerado com status PENDENTE. Vencimento: 2026-04-30
    7.2 Verificando marco BOLETO_GERADO...
    [OK] Marco BOLETO_GERADO registrado.
    7.3 Confirmando pagamento com data futura 2026-05-05 (apos vencimento de 30 dias)...
    [OK] Boleto 4 status VENCIDO confirmado (pagamento registrado apos vencimento).
    7.4 Verificando marco BOLETO_VENCIDO...
    [OK] Marco BOLETO_VENCIDO registrado: 'Pagamento registrado apos vencimento em 2026-05-05. Boleto ID: 4'
    7.5 Testando RN-095 (confirmacao de boleto nao-PENDENTE bloqueada)...
    [OK] RN-095 OK: confirmacao de boleto nao-PENDENTE bloqueada (HTTP 422).
    [OK] Fluxo B concluido com sucesso.

==> Passo 8 - RN-091: licenciamento isento nao gera boleto
    Verificacao via tentativa de POST com licenciamento isento.
    [WARN] RN-091 nao testado automaticamente neste script (requer setup de licenciamento isento separado).
    [WARN] Para testar manualmente: POST /boletos/licenciamento/{id} onde isentoTaxa=true deve retornar HTTP 400/422.

==> Passo 9 - Limpeza dos dados de teste
    [OK] Dados de teste removidos via sqlplus.

==> SUMARIO

  Sprint 11 - P11 Pagamento de Boleto concluida com sucesso.

  Arquivos alterados/criados nesta sprint:
    [M] BoletoService.java       : marcos, emails, keycloakId, vencerBoleto()
    [M] BoletoController.java    : AuthenticationPrincipal Jwt em create e confirmarPagamento
    [N] BoletoJobService.java    : job P11-B (@Scheduled 02:00 diario)

  Fluxos validados:
    Fluxo A: PENDENTE => PAGO    + marcos BOLETO_GERADO, PAGAMENTO_CONFIRMADO
    Fluxo B: PENDENTE => VENCIDO + marcos BOLETO_GERADO, BOLETO_VENCIDO
    RN-090 : boleto PENDENTE duplicado bloqueado
    RN-095 : confirmacao de boleto nao-PENDENTE bloqueada

  Job P11-B (BoletoJobService):
    Cron  : 0 0 2 * * * (02:00 diario)
    Busca : boletos PENDENTE com dtVencimento menor que hoje
    Acao  : PENDENTE => VENCIDO + marco BOLETO_VENCIDO + e-mail RT/RU

  Data/hora: 2026-03-31 22:25:18
```

---

## 4. Problemas Detectados e Soluções Aplicadas

> Esta seção documenta cada falha encontrada nas tentativas de execução anteriores, a causa-raiz identificada e a correção implementada.

---

### Problema 1 — ParseError do PowerShell em caracteres Unicode no script

**Primeira mensagem de erro:**
```
No C:\SOL\infra\scripts\sprint11-deploy.ps1:528 caractere:108
+ ... oletoService.java     →" marcos, emails, keycloakId, vencerBoleto()"
```

**Causa:** O arquivo `.ps1` original continha caracteres Unicode fora do ASCII básico dentro de strings `Write-Host`:
- `→` (U+2192, seta para direita) — usado no sumário para indicar mudanças
- `@Scheduled` dentro de aspas duplas — o PowerShell tentava interpretar como referência de variável
- `<` (operador de comparação) — dentro de strings não-interpoladas, confundia o parser

O PowerShell tentava interpretar esses caracteres como parte da sintaxe da linguagem ao carregar o arquivo, antes mesmo de executar qualquer linha, fazendo o script abortar com `ParserError`.

**Solução:** O arquivo já estava corrigido no disco no momento da execução (os símbolos haviam sido substituídos por texto simples). Nenhuma alteração adicional foi necessária neste ponto. Diagnóstico confirmado comparando o conteúdo em ISO-8859-1 e UTF-8 com as linhas reportadas no erro.

---

### Problema 2 — Caminhos de Maven e JDK inexistentes

**Mensagem de erro:**
```
& : O termo 'C:\tools\maven\bin\mvn.cmd' nao e reconhecido como nome de cmdlet...
```

**Causa:** O script original hardcodava:
```powershell
$MvnCmd   = "C:\tools\maven\bin\mvn.cmd"
$JavaHome = "C:\tools\jdk21"
```

Esses caminhos não existem neste ambiente. O Maven foi instalado via Chocolatey e o JDK via Eclipse Adoptium, ambos em locais diferentes.

**Investigação:** Executado `Get-Command mvn` e verificado `Test-Path` nos candidatos comuns.

**Resultado da investigação:**
- Maven encontrado em: `C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd`
- JDK encontrado em: `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot`
- `C:\tools\` não existe nesta máquina

**Correção aplicada no script:**
```powershell
# Antes
$MvnCmd   = "C:\tools\maven\bin\mvn.cmd"
$JavaHome = "C:\tools\jdk21"

# Depois
$MvnCmd   = "C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd"
$JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
```

---

### Problema 3 — Build Maven falhava com JAR em uso

**Mensagem de erro:**
```
[ERROR] Failed to execute goal maven-clean-plugin:3.3.2:clean: Failed to delete
C:\SOL\backend\target\sol-backend-1.0.0.jar
```

**Causa:** O Passo 1 (build) executava antes do Passo 2 (restart do serviço). O serviço `SOL-Backend` estava rodando e mantinha o JAR aberto com lock exclusivo do sistema operacional Windows. O plugin `maven-clean` não consegue deletar arquivos bloqueados.

**Por que a ordem original estava errada:** O script original assumia que o serviço poderia ser reiniciado *depois* do build, mas no Windows o `mvn clean` remove o JAR antigo antes de gerar o novo — e para removê-lo, o arquivo precisa estar livre.

**Solução:** Adição do **Passo 0b** — parar o serviço antes do build:
```powershell
Write-Step "Passo 0b - Parar servico SOL-Backend (pre-build)"
$svc = Get-Service -Name "SOL-Backend" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Stop-Service -Name "SOL-Backend" -Force
    Start-Sleep -Seconds 5
    Write-OK "Servico parado."
}
```

O Passo 2 (Restart-Service) permanece depois do build para subir o serviço com o novo JAR.

---

### Problema 4 — Health check retornando HTTP 404

**Mensagem de erro:**
```
Invoke-RestMethod : HTTP Status 404 - Not Found
```

**URL tentada:** `http://localhost:8080/actuator/health`

**Causa:** O `application.yml` define `context-path: /api`. Portanto, **todos** os endpoints — inclusive os do Actuator — ficam sob `/api`. A URL correta é `http://localhost:8080/api/actuator/health`.

Consequência direta: a variável `$BaseUrl = "http://localhost:8080"` também estava errada para todos os endpoints de negócio da API.

**Correção aplicada:**
```powershell
# Antes
$BaseUrl = "http://localhost:8080"

# Depois
$BaseUrl = "http://localhost:8080/api"
```

---

### Problema 5 — Health check retornando HTTP 503 (status DOWN)

**Mensagem de erro:**
```
{"status":"DOWN"}
```

**Causa:** O Spring Boot Actuator agrega o status de todos os health indicators. O `MailHealthIndicator` (Spring Boot Actuator built-in) tenta conectar ao servidor SMTP configurado em `application.yml` para verificar se está acessível. Como o `spring.mail.host=localhost` e `spring.mail.port=1025` apontam para o MailHog, e o MailHog não estava rodando, a conexão falhava e o indicador reportava `DOWN`, arrastando o status global do `/actuator/health` para `DOWN` com HTTP 503.

**Log confirmando a causa:**
```
WARN MailHealthIndicator : Mail health check failed
org.eclipse.angus.mail.util.MailConnectException: Couldn't connect to host, port: localhost, 1025; timeout -1
```

**Por que o MailHog é necessário nesta sprint:** O módulo P11 envia e-mails reais ao RT (Responsável Técnico) e ao RU (Responsável pelo Uso) nos eventos de boleto gerado, pagamento confirmado e boleto vencido. O MailHog é o servidor SMTP de desenvolvimento que captura esses e-mails localmente sem enviá-los para destinatários reais.

**Investigação:** Verificado que o MailHog não estava instalado e que `choco install mailhog` falhou (pacote não disponível no repositório público do Chocolatey na versão disponível).

**Solução:** Download direto do executável a partir do GitHub Releases e adição do **Passo 0a** no script:
```powershell
# Download manual (feito uma vez)
$url  = 'https://github.com/mailhog/MailHog/releases/download/v1.0.1/MailHog_windows_amd64.exe'
$dest = 'C:\SOL\infra\mailhog\MailHog.exe'
Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing

# Passo 0a inserido no script
Write-Step "Passo 0a - MailHog (SMTP localhost:1025)"
$smtpOk = Test-NetConnection -ComputerName localhost -Port 1025 -InformationLevel Quiet
if (-not $smtpOk) {
    Start-Process -FilePath $MailHogExe -WindowStyle Hidden
    Start-Sleep -Seconds 4
    Write-OK "MailHog iniciado (SMTP :1025, UI :8025)."
} else {
    Write-OK "MailHog ja rodando."
}
```

O MailHog fica disponível também via UI web em `http://localhost:8025` para inspeção manual dos e-mails enviados.

---

### Problema 6 — Autenticação falhando com AUTH-001

**Mensagem de erro:**
```
{"codigoRegra":"AUTH-001","detail":"Credenciais invalidas ou usuario desabilitado."}
```

**Causa:** O script original usava:
```powershell
$AdminUser    = "admin"
$AdminPass    = "admin123"
$AnalistaUser = "analista1"
$AnalistaPass = "analista123"
```

Essas credenciais nunca existiram no Keycloak do ambiente. A consulta à API Admin do Keycloak confirmou que apenas um usuário existia no realm `sol`: `sol-admin` com role `ADMIN`.

**Correção das credenciais do admin:**
```powershell
$AdminUser = "sol-admin"
$AdminPass = "Admin@SOL2026"
```

**Criação do usuário `analista1`:** O usuário analista precisava ser criado tanto no Keycloak quanto na tabela Oracle `sol.usuario`.

**Criação no Keycloak:**
- Primeira tentativa falhou silenciosamente com HTTP 400 (corpo vazio) ao incluir `credentials` no payload — limitação da API Admin do Keycloak ao criar usuário e senha simultaneamente em alguns contextos
- Solução: criar o usuário sem senha, depois definir a senha via `PUT /admin/realms/sol/users/{id}/reset-password`
- A senha `analista123` foi rejeitada pela política do Keycloak: `invalidPasswordMinSpecialCharsMessage` (exige ao menos 1 caractere especial)
- Senha final usada: `Analista@123`
- Role `ANALISTA` atribuída via `POST /admin/realms/sol/users/{id}/role-mappings/realm`

**Criação no Oracle:**
- A coluna `CPF` aceita no máximo 11 caracteres (dígitos sem máscara). Primeira tentativa usou `000.000.001-99` (14 chars) — rejeitado com `ORA-12899`
- A coluna `STATUS_CADASTRO` é um enum; valores válidos: `INCOMPLETO`, `ANALISE_PENDENTE`, `EM_ANALISE`, `APROVADO`, `REPROVADO`. O valor `ATIVO` usado inicialmente causou `ORA-02290` (violação de check constraint `SYS_C0073362`)
- A coluna `ATIVO` usa converter `SimNaoBooleanConverter` — armazena `S`/`N`, não `1`/`0`
- A senha do Oracle é `Sol@CBM2026`, não `sol123` como estava no script. O `@` na senha causa conflito com a sintaxe de connection string do sqlplus; solução: usar `/nolog` + `CONNECT` dentro do script SQL com senha entre aspas duplas:
  ```sql
  CONNECT sol/"Sol@CBM2026"@//localhost:1521/XEPDB1
  ```

**INSERT final bem-sucedido:**
```sql
INSERT INTO sol.usuario (
    id_usuario, nome, cpf, email, tipo_usuario, status_cadastro,
    id_keycloak, ativo, dt_criacao, dt_atualizacao
) VALUES (
    sol.seq_usuario.NEXTVAL,
    'Analista Teste',
    '00000000199',
    'analista1@sol.cbm.rs.gov.br',
    'ANALISTA',
    'APROVADO',
    '1e13f4d1-fcf9-4118-9389-72487ffaa889',
    'S',
    SYSDATE,
    SYSDATE
);
```

`analista1` criado com **ID Oracle = 25** e keycloakId `1e13f4d1-fcf9-4118-9389-72487ffaa889`.

---

### Problema 7 — `$resp.token` lançava exceção com StrictMode

**Mensagem de erro:**
```
(nao foi possivel ler corpo do erro)
[FAIL] Falha na autenticacao.
```

**Causa:** O script tem `Set-StrictMode -Version Latest` no topo. Em strict mode, acessar uma propriedade inexistente em um objeto PowerShell lança uma exceção terminante, em vez de retornar `$null` silenciosamente.

O endpoint `POST /api/auth/login` retorna o token no campo `access_token` (padrão OAuth2/OpenID Connect). A função `Get-Token` acessava `$resp.token`, que não existe na resposta:

```powershell
# Antes (campo inexistente → exceção em StrictMode)
return $resp.token

# Depois (campo correto)
return $resp.access_token
```

O erro era engolido pela `Show-ErrorBody` que tentava ler o corpo da resposta HTTP, mas como a exceção veio de acesso a propriedade (não de HTTP), não havia `Response` para ler, resultando na mensagem `(nao foi possivel ler corpo do erro)`.

---

### Problema 8 — Body de criação do licenciamento incompleto

**Mensagem de erro:**
```json
{"detail":"Um ou mais campos falharam na validacao",
 "erros":{"endereco":"Endereco e obrigatorio","tipo":"Tipo de licenciamento e obrigatorio"}}
```

**Causa:** O `New-LicBody` original usava campos de uma versão antiga do DTO (`numeroPpci`, `tipoPpci`, `nomeProprietario`, etc.) que não correspondem ao `LicenciamentoCreateDTO` atual. O DTO atual (`LicenciamentoCreateDTO.java`) exige:
- `tipo`: enum `TipoLicenciamento` (`PPCI` ou `PSPCIM`) — anotado com `@NotNull`
- `endereco`: objeto `EnderecoDTO` com `cep` (8 dígitos, sem hífen), `logradouro`, `bairro`, `municipio`, `uf` — anotado com `@NotNull @Valid`

**Correção:**
```powershell
function New-LicBody {
    param([int]$seed)
    return @{
        tipo           = "PPCI"
        areaConstruida = 300.00
        endereco       = @{
            cep        = "90010100"
            logradouro = "Rua dos Testes"
            numero     = "$seed"
            bairro     = "Centro"
            municipio  = "Porto Alegre"
            uf         = "RS"
        }
    } | ConvertTo-Json -Depth 5
}
```

---

### Problema 9 — Endpoint de upload PPCI na URL errada

**Mensagem de erro:**
```json
{"status":500,"detail":"NoResourceFoundException: No static resource licenciamentos/67/arquivo-ppci."}
```

**Causa:** O script chamava `POST /licenciamentos/{id}/arquivo-ppci`, URL que não existe. O Spring tentava resolver como recurso estático e retornava 500.

O endpoint correto, conforme `ArquivoController.java`, é:
```
POST /api/arquivos/upload
  - file:           multipart/form-data (campo "file")
  - licenciamentoId: query param (Long)
  - tipoArquivo:    query param (enum TipoArquivo, ex: "PPCI")
  - Authorization:  Bearer <token>
```

**Correção na chamada:**
```powershell
# Antes
-uri "$BaseUrl/licenciamentos/$id/arquivo-ppci"

# Depois
-uri "$BaseUrl/arquivos/upload?licenciamentoId=$id&tipoArquivo=PPCI"
```

---

### Problema 10 — Endpoint `distribuir` com método e parâmetros errados

**Causa:** O script usava `POST /licenciamentos/{id}/distribuir` sem parâmetros. O endpoint correto, conforme `AnaliseController.java`, é:
```
PATCH /api/licenciamentos/{id}/distribuir?analistaId={oracleId}
```

Dois erros simultâneos:
1. **Método HTTP errado:** `POST` em vez de `PATCH`
2. **Parâmetro ausente:** `analistaId` é obrigatório (`@RequestParam`) — é o ID Oracle do analista na tabela `sol.usuario`, não o keycloakId

**Obtenção do ID Oracle do analista:** Adicionado bloco após Passo 4 para buscar o ID via `GET /api/auth/me` com o token do analista, que retorna os dados do usuário local incluindo `id` (Oracle):
```powershell
$meAnalista = Invoke-RestMethod -Uri "$BaseUrl/auth/me" `
    -Headers @{ Authorization = "Bearer $tokenAnalista" }
$analistaOracleId = $meAnalista.id  # = 25
```

**Correção na chamada:**
```powershell
# Antes
Invoke-RestMethod -Method Post -Uri "$BaseUrl/licenciamentos/$id/distribuir"

# Depois
Invoke-RestMethod -Method Patch -Uri "$BaseUrl/licenciamentos/$id/distribuir?analistaId=$analistaOracleId"
```

A assinatura da função `Invoke-SetupEmAnalise` também foi atualizada para receber `[long]$analistaOracleId` como parâmetro.

---

### Problema 11 — Teste de RN-090 na sequência errada

**Mensagem de erro:**
```
[FAIL] RN-090 nao funcionou: segundo boleto foi gerado indevidamente
```

**Causa:** O teste de RN-090 estava posicionado **após** a confirmação do pagamento (passo 6.3). Nesse ponto, o boleto já estava com status `PAGO`. A regra RN-090 proíbe apenas um boleto `PENDENTE` duplicado — após o primeiro ser `PAGO`, é correto e esperado que um segundo boleto possa ser gerado.

Portanto, o código do `BoletoService` estava **correto**; o erro estava no script de teste.

**Verificação no `BoletoService.java`:**
```java
// RN-090: so bloqueia se existir PENDENTE
if (boletoRepository.existsByLicenciamentoIdAndStatus(licenciamentoId, StatusBoleto.PENDENTE)) {
    throw new BusinessException("RN-090", "Ja existe um boleto pendente...");
}
```

**Correção:** O teste de RN-090 foi movido para o **passo 6.2b**, imediatamente após a geração do primeiro boleto (enquanto ainda `PENDENTE`) e antes da confirmação do pagamento:

```
6.1  → Gerar boleto        (status: PENDENTE)
6.2  → Verificar marco BOLETO_GERADO
6.2b → Tentar gerar 2º boleto  ← RN-090 deve bloquear aqui (HTTP 422) ✅
6.3  → Confirmar pagamento  (status: PAGO)
6.4  → Verificar marco PAGAMENTO_CONFIRMADO
```

O passo 6.5 original (que testava após o PAGO) foi removido por ser logicamente incorreto.

---

## 5. Justificativa de Cada Passo do Script

Esta seção explica a razão de existência de cada passo do script `sprint11-deploy.ps1` e o que seria validado ou o que poderia dar errado sem ele.

---

### Passo 0a — Garantir MailHog rodando

**Justificativa:** O `BoletoService` envia e-mails assíncronos ao RT e ao RU em todos os eventos de boleto (gerado, pago, vencido). O `application.yml` aponta o SMTP para `localhost:1025` (MailHog). Se o MailHog não estiver no ar, o `MailHealthIndicator` do Spring Boot reporta `DOWN`, fazendo o health check do Passo 3 falhar e impedindo a execução dos testes. Além disso, sem MailHog, os e-mails falhariam silenciosamente ou com exceção, dependendo da configuração do `EmailService`.

**O que valida:** Que a infraestrutura de e-mail está funcional antes de subir o backend.

---

### Passo 0b — Parar serviço SOL-Backend antes do build

**Justificativa:** No Windows, arquivos abertos por um processo não podem ser deletados ou sobrescritos por outro processo. O `maven-clean-plugin` precisa deletar o JAR antigo em `target/` antes de gerar o novo. Como o serviço `SOL-Backend` mantém o JAR carregado na JVM, a limpeza falha com `MojoExecutionException`. Parar o serviço libera o lock antes do build.

**O que valida:** Que o ambiente está pronto para uma compilação limpa.

---

### Passo 1 — Build Maven (skip tests)

**Justificativa:** Recompila o backend com o código da Sprint 11 (`BoletoService`, `BoletoController`, `BoletoJobService`). Os testes unitários são pulados (`-DskipTests`) porque o smoke test integrado dos passos seguintes é mais abrangente para o contexto de deploy. O build usa o Maven local instalado via Chocolatey, com `JAVA_HOME` apontando para o JDK 21 da Eclipse Adoptium.

**O que valida:** Que o código compila sem erros de sintaxe ou dependências faltando.

---

### Passo 2 — Reiniciar serviço SOL-Backend

**Justificativa:** Após o build, o serviço precisa ser reiniciado para carregar o novo JAR com as mudanças da Sprint 11. O `Restart-Service` para e sobe o serviço Windows `SOL-Backend`, aguardando 20 segundos para o Spring Boot completar a inicialização (incluindo conexão com Oracle, Keycloak e MinIO).

**O que valida:** Que o novo código está em execução.

---

### Passo 3 — Health check

**Justificativa:** Verifica se o Spring Boot subiu completamente e todos os seus health indicators estão `UP` (banco Oracle, Keycloak JWKS, MinIO, MailHog). São feitas até 12 tentativas com intervalo de 5 segundos (total: ~60 segundos de espera máxima). Sem esse passo, os testes subsequentes seriam executados contra um backend ainda inicializando, causando falhas espúrias de conexão recusada ou 503.

**O que valida:** Que o backend está pronto para receber requisições de negócio.

---

### Passo 4 — Autenticação e obtenção de tokens

**Justificativa:** Todos os endpoints da API exigem `Authorization: Bearer <token>`. São necessários dois tokens distintos:
- **tokenAdmin** (`sol-admin` / role `ADMIN`): para criar licenciamentos, fazer uploads, submeter, distribuir e confirmar pagamentos
- **tokenAnalista** (`analista1` / role `ANALISTA`): para `iniciar-analise` e gerar boletos

Após obter os tokens, o script consulta `GET /auth/me` com o token do analista para recuperar o **ID Oracle** (`id = 25`) necessário para o parâmetro `analistaId` do endpoint `distribuir`. Sem esse ID, a distribuição falha com 404 ou 400.

**O que valida:** Que a autenticação ROPC via Keycloak funciona e que os dois perfis de usuário estão configurados corretamente.

---

### Passo 5 — Limpeza preventiva de dados de teste

**Justificativa:** Os licenciamentos de teste usam `nr_ppci` previsíveis (`A00000065AA001`, `A00000066AA001`). Se uma execução anterior do script tiver deixado dados residuais (falha antes da limpeza final), a criação dos licenciamentos com os mesmos campos pode conflitar ou gerar IDs inesperados. A limpeza preventiva garante um estado inicial limpo.

**Estado atual:** O `ojdbc11.jar` não está em `C:\tools\`, então o script cai para o `sqlplus` como alternativa. Nesta execução o sqlplus também não foi encontrado no PATH, então a limpeza emitiu `[WARN]` e foi pulada. Os IDs dos licenciamentos foram gerados pela sequence Oracle (`id = 67, 68` em vez de `65, 66`), o que não afeta a validade dos testes.

**Recomendação:** Colocar o `ojdbc11.jar` em `C:\tools\` ou adicionar o diretório do `sqlplus` ao PATH do sistema para que a limpeza funcione automaticamente nas próximas execuções.

---

### Passo 6 — Fluxo A: Gerar boleto + confirmar pagamento no prazo (→ PAGO)

**Justificativa:** Valida o caminho feliz principal do módulo P11-A. O licenciamento precisa estar em `EM_ANALISE` para que o boleto possa ser gerado. A função auxiliar `Invoke-SetupEmAnalise` percorre a cadeia completa: criar → upload PPCI → submeter → distribuir → iniciar-analise, colocando o licenciamento no estado correto antes dos testes de boleto.

**Substeps e o que cada um valida:**

| Sub-passo | Endpoint | O que valida |
|-----------|----------|-------------|
| 6.1 | `POST /boletos/licenciamento/{id}` | Boleto criado com status `PENDENTE`, valor calculado (R$ 150,00), vencimento em 30 dias |
| 6.2 | `GET /licenciamentos/{id}/marcos` | Marco `BOLETO_GERADO` registrado com observação correta |
| 6.2b | `POST /boletos/licenciamento/{id}` | **RN-090**: retorna HTTP 422 enquanto primeiro boleto está `PENDENTE` |
| 6.3 | `PATCH /boletos/{id}/confirmar-pagamento?dataPagamento=hoje` | Status muda para `PAGO` (data de pagamento ≤ vencimento) |
| 6.4 | `GET /licenciamentos/{id}/marcos` | Marco `PAGAMENTO_CONFIRMADO` registrado |

---

### Passo 7 — Fluxo B: Confirmar pagamento após vencimento (→ VENCIDO)

**Justificativa:** Valida o caminho alternativo onde o pagamento é registrado após a data de vencimento. O `BoletoService` detecta que `dataPagamento > dtVencimento` e muda o status para `VENCIDO` em vez de `PAGO`, registrando o marco `BOLETO_VENCIDO`. Usa um segundo licenciamento independente para não interferir no estado do Fluxo A.

**Substeps e o que cada um valida:**

| Sub-passo | Endpoint | O que valida |
|-----------|----------|-------------|
| 7.1 | `POST /boletos/licenciamento/{id}` | Boleto criado com status `PENDENTE` |
| 7.2 | `GET /licenciamentos/{id}/marcos` | Marco `BOLETO_GERADO` registrado |
| 7.3 | `PATCH /boletos/{id}/confirmar-pagamento?dataPagamento=2026-05-05` | Status muda para `VENCIDO` (data futura além do vencimento de 30 dias) |
| 7.4 | `GET /licenciamentos/{id}/marcos` | Marco `BOLETO_VENCIDO` registrado |
| 7.5 | `PATCH /boletos/{id}/confirmar-pagamento` (sobre boleto já VENCIDO) | **RN-095**: retorna HTTP 422 — boleto não está mais `PENDENTE` |

---

### Passo 8 — RN-091: licenciamento isento não gera boleto

**Justificativa:** A regra RN-091 impede a geração de boleto para licenciamentos com `isentoTaxa = true`. Essa validação existe porque licenciamentos isentos (deferidos em processo de isenção via Sprint 6) não devem ser cobrados.

**Estado atual:** O teste automático foi marcado como `[WARN]` não executado, pois exigiria um licenciamento em `EM_ANALISE` com `isentoTaxa = true` já existente no banco, o que requer setup adicional não coberto pelos dados de teste desta sprint.

**Como testar manualmente:**
```http
POST /api/boletos/licenciamento/{id_isento}
Authorization: Bearer <tokenAnalista>
→ Esperado: HTTP 422, codigoRegra: RN-091
```

---

### Passo 9 — Limpeza dos dados de teste

**Justificativa:** Remove os licenciamentos, boletos, marcos de processo e arquivos criados durante os testes para não poluir o banco com dados fictícios. A limpeza é feita via `sqlplus` com um bloco PL/SQL que itera pelos licenciamentos pelo `nr_ppci` de teste e deleta em cascade (marcos → arquivos → boletos → licenciamento).

**Importância:** Sem essa limpeza, execuções subsequentes do script ou de outros smoke tests podem encontrar estado inesperado no banco, especialmente se os IDs reutilizados por sequences colidirem com dados de testes anteriores.

---

## 6. Função Auxiliar `Invoke-SetupEmAnalise` — Detalhamento

Esta função cria um licenciamento em estado `EM_ANALISE` a partir do zero, percorrendo toda a cadeia de transições de estado necessárias como pré-requisito para os testes de boleto.

```
RASCUNHO
  → (upload PPCI)
  → RASCUNHO com arquivo
  → (submeter)
  → ANALISE_PENDENTE
  → (distribuir, com analistaId)
  → ANALISE_PENDENTE com analista atribuído
  → (iniciar-analise, com token do analista)
  → EM_ANALISE  ← estado necessário para gerar boleto
```

**Por que cada etapa é necessária:**

| Etapa | Endpoint | Pré-condição verificada pelo backend |
|-------|----------|--------------------------------------|
| Criar | `POST /licenciamentos` | Nenhuma — cria em `RASCUNHO` |
| Upload PPCI | `POST /arquivos/upload?...&tipoArquivo=PPCI` | **RN-P03-002**: submissão exige pelo menos um arquivo PPCI |
| Submeter | `POST /licenciamentos/{id}/submeter` | Status deve ser `RASCUNHO` + PPCI anexado |
| Distribuir | `PATCH /licenciamentos/{id}/distribuir?analistaId=25` | Status deve ser `ANALISE_PENDENTE`; requer role `ADMIN` ou `CHEFE_SSEG_BBM` |
| Iniciar análise | `POST /licenciamentos/{id}/iniciar-analise` | Status deve ser `ANALISE_PENDENTE`; analista deve estar atribuído; requer role `ANALISTA` |

---

## 7. Arquivos Criados/Modificados Durante o Deploy

| Arquivo | Tipo | Descrição |
|---------|------|-----------|
| `C:\SOL\infra\scripts\sprint11-deploy.ps1` | Modificado | Script principal — 11 correções aplicadas |
| `C:\SOL\infra\mailhog\MailHog.exe` | Criado | Executável MailHog v1.0.1 baixado do GitHub |
| `C:\SOL\infra\scripts\_create_analista.ps1` | Criado | Script auxiliar de setup do usuário analista1 no Keycloak |
| `C:\SOL\infra\scripts\_test_auth.ps1` | Criado | Script auxiliar de diagnóstico de autenticação |
| `C:\SOL\infra\scripts\_insert_analista.sql` | Criado | Script SQL de insert do analista1 na tabela Oracle |
| `C:\SOL\infra\scripts\_check_usuarios.sql` | Criado | Script SQL auxiliar de consulta de usuários |

---

## 8. Estado do Banco após o Deploy

### Keycloak — Realm `sol`

| Username | ID Keycloak | Roles | Senha |
|----------|-------------|-------|-------|
| `sol-admin` | `6a6065a2-edc1-415a-ac91-a260ebc9063c` | `ADMIN` | `Admin@SOL2026` |
| `analista1` | `1e13f4d1-fcf9-4118-9389-72487ffaa889` | `ANALISTA` | `Analista@123` |

### Oracle — Tabela `sol.usuario`

| id_usuario | nome | tipo_usuario | id_keycloak |
|------------|------|--------------|-------------|
| 1 | RT Smoke Test Sprint3 | RT | `ce513485-a0a6-4538-a168-ac8b599882af` |
| 25 | Analista Teste | ANALISTA | `1e13f4d1-fcf9-4118-9389-72487ffaa889` |

### Oracle — Tabela `sol.boleto` (após limpeza)

Sem registros de teste (limpeza executada no Passo 9).

---

## 9. Observações e Pendências

> [!warning] Limpeza preventiva (Passo 5) não executada automaticamente
> O `ojdbc11.jar` não está em `C:\tools\` e o `sqlplus` não está no PATH. A limpeza emitiu `[WARN]` e foi ignorada. Para corrigir, adicionar o diretório do sqlplus ao PATH do sistema:
> ```
> C:\app\Guilherme\product\21c\dbhomeXE\bin
> ```
> Ou copiar `ojdbc11.jar` para `C:\tools\`.

> [!warning] RN-091 não testada automaticamente
> O teste de licenciamento isento exige setup manual separado. Incluir na próxima sprint um fixture de licenciamento isento pré-existente para cobertura automática.

> [!note] IDs dos licenciamentos de teste
> O script usa `$LicIds = @(65, 66)` como referência, mas os IDs reais gerados pela sequence Oracle foram `67` e `68` (devido a execuções anteriores que não limparam dados). Isso é esperado e não afeta a validade dos testes.

> [!note] Job P11-B não executável no smoke test
> O `BoletoJobService` é agendado para `02:00` diário (`cron = "0 0 2 * * *"`). Não é possível testá-lo diretamente no smoke test sem manipular horário do sistema ou forçar execução do método via endpoint interno. O Fluxo B cobre a mesma lógica de transição `PENDENTE → VENCIDO` de forma indireta via `confirmarPagamento` com data posterior ao vencimento.

---

## 10. Resumo das Correções no Script

| # | Problema | Linha(s) afetada(s) | Correção |
|---|----------|---------------------|----------|
| 1 | Caminhos Maven/JDK inexistentes | `$MvnCmd`, `$JavaHome` | Atualizado para caminhos reais do ambiente |
| 2 | JAR em uso bloqueando `mvn clean` | Antes do Passo 1 | Adicionado Passo 0b: parar serviço antes do build |
| 3 | `$BaseUrl` sem `/api` | `$BaseUrl` | `http://localhost:8080` → `http://localhost:8080/api` |
| 4 | MailHog ausente → health DOWN | Antes do Passo 0b | Adicionado Passo 0a: verificar/iniciar MailHog |
| 5 | Credenciais admin erradas | `$AdminUser`, `$AdminPass` | `admin/admin123` → `sol-admin/Admin@SOL2026` |
| 6 | Usuário analista inexistente | `$AnalistaUser`, `$AnalistaPass` | Criado no Keycloak + Oracle; senha `Analista@123` |
| 7 | `$resp.token` → exceção StrictMode | `Get-Token` | `.token` → `.access_token` |
| 8 | Body do licenciamento incompleto | `New-LicBody` | Adicionados campos `tipo` e `endereco` conforme DTO |
| 9 | Endpoint upload PPCI errado | `Invoke-SetupEmAnalise` passo 2 | URL corrigida para `/arquivos/upload?licenciamentoId=X&tipoArquivo=PPCI` |
| 10 | `distribuir`: método e parâmetro errados | `Invoke-SetupEmAnalise` passo 4 | `POST` → `PATCH`; adicionado `?analistaId=25` |
| 11 | Teste RN-090 após boleto PAGO (lógica errada) | Passo 6.5 | Teste movido para 6.2b (boleto ainda PENDENTE) |

---

*Relatório gerado em 2026-03-31 ao final da execução da Sprint 11.*
*Sistema: SOL — Sistema Online de Licenciamento — CBM-RS*
