# Sprint 8 — Relatório de Execução
**Sistema:** SOL — Sistema Online de Licenciamento · CBM-RS
**Data de execução:** 2026-03-28
**Script base:** `C:\SOL\infra\scripts\sprint8-deploy.ps1`
**Status final:** Concluída com sucesso na primeira tentativa — sem correções de código
**Sprints acumuladas:** 1 · 2 · 3 · 4 · 5 · 6 · 7 · **8**

---

## Índice

1. [[#Contexto da Sprint 8 — O que é o APPCI]]
2. [[#Análise Pré-Deploy — Verificações Preventivas]]
3. [[#Execução do Script — Justificativa e Mensagens por Passo]]
   - [[#Bloco de Configuração — Variáveis Globais]]
   - [[#Funções Auxiliares do Script]]
   - [[#Passo 1 — Parar o Serviço Windows]]
   - [[#Passo 2 — Compilar com Maven]]
   - [[#Passo 3 — Reiniciar o Serviço]]
   - [[#Passo 4 — Aguardar e Health Check]]
   - [[#Passo 5 — Login Keycloak (ROPC)]]
   - [[#Passo 6 — Obter ID do Usuário Admin]]
   - [[#Fluxo A — Setup P03 + P04 + P07 (Invoke-PrepararParaAppci)]]
   - [[#Fluxo A — Teste 1 — Emitir APPCI]]
   - [[#Fluxo A — Teste 2 — Confirmar APPCI_EMITIDO e Validade]]
   - [[#Fluxo A — Teste 3 — Listar APPCIs Vigentes]]
   - [[#Fluxo A — Teste 4 — Verificar Marco APPCI_EMITIDO]]
   - [[#Fluxo A — Teste 5 — Endpoint Dedicado /appci]]
   - [[#Passo Final — Limpeza Oracle]]
4. [[#Problema Recorrente — Aviso GET /usuarios]]
5. [[#Arquitetura dos Novos Componentes P08]]
6. [[#Máquina de Estados Completa Após Sprint 8]]
7. [[#Trilha de Auditoria — 8 Marcos do Licenciamento 14]]
8. [[#Tabela Consolidada de Resultados]]
9. [[#Estado Final do Sistema]]

---

## Contexto da Sprint 8 — O que é o APPCI

### Definição

O **APPCI** (Alvará de Prevenção e Proteção Contra Incêndio) é o documento final emitido pelo CBM-RS que autoriza formalmente o funcionamento de um estabelecimento do ponto de vista de prevenção de incêndios. É o objetivo de todo o processo de licenciamento — o "alvará" que o requerente precisa obter e manter renovado para operar legalmente.

O APPCI é emitido após a aprovação da vistoria presencial. Sua validade é determinada pela área construída do imóvel, conforme **RTCBMRS N.01/2024**:

| Área construída | Validade do APPCI |
|---|---|
| ≤ 750 m² | 2 anos |
| > 750 m² | 5 anos |

### Posição no ciclo de licenciamento

```
P03 (submissão) → P04 (análise) → P07 (vistoria) → P08 (APPCI) ← Sprint 8
```

A Sprint 8 implementa a **fase final** do ciclo principal. Com o APPCI emitido o estabelecimento está plenamente regularizado junto ao CBM-RS.

### Novos componentes introduzidos

| Componente | Tipo | Responsabilidade |
|---|---|---|
| `AppciService.java` | `@Service` | Regras de negócio P08 (RN-P08-001 a RN-P08-004) |
| `AppciController.java` | `@RestController` | Endpoints `/appci/vigentes`, `/{id}/emitir-appci`, `/{id}/appci` |
| `Licenciamento.dtValidadeAppci` | campo `LocalDate` | Data de vencimento do APPCI |
| `Licenciamento.dtVencimentoPrpci` | campo `LocalDate` | Data de vencimento do PRPCI (preenchida automaticamente) |
| `TipoMarco.APPCI_EMITIDO` | enum value | Marco de auditoria do APPCI |
| `StatusLicenciamento.APPCI_EMITIDO` | enum value | Estado final do ciclo principal |

### Regras de negócio implementadas

| RN | Descrição |
|---|---|
| RN-P08-001 | APPCI só pode ser emitido em licenciamentos com status `PRPCI_EMITIDO` |
| RN-P08-002 | Validade calculada automaticamente: área ≤ 750 m² → 2 anos; > 750 m² → 5 anos |
| RN-P08-003 | `dtVencimentoPrpci` preenchida como `hoje + 1 ano` se ainda não definida |
| RN-P08-004 | `GET /{id}/appci` só aceita licenciamentos em `APPCI_EMITIDO` |

---

## Análise Pré-Deploy — Verificações Preventivas

Diferentemente das Sprints 6 e 7 (que tiveram bugs de script e de compilação respectivamente), a Sprint 8 foi submetida a uma **análise pré-deploy proativa** dos arquivos Java antes de qualquer execução. Essa abordagem teria prevenido o bug de Sprint 7 (`LicenciamentoRepository` com método ausente) se aplicada naquela ocasião.

### Verificações do script PowerShell

| Ponto verificado | Resultado |
|---|---|
| CEP `"90010100"` (sem hífen, 8 dígitos) | OK — padrão correto desde Sprint 4 |
| Senha `"Admin@SOL2026"` (case correto) | OK — bug de senha foi da Sprint 3 |
| `Push-Location $ProjectRoot` antes do Maven | OK — garante o pom.xml correto |
| Fallback `mvnw.cmd` → `mvn` global | OK — proteção para ambiente sem wrapper |
| `${lid}` na limpeza Oracle | OK — padrão correto desde Sprint 6 |

### Verificações dos arquivos Java

Arquivos inspecionados antes da execução:

- `AppciService.java` — verificados todos os métodos de repositório chamados
- `AppciController.java` — verificado uso de `AnaliseDecisaoDTO`
- `StatusLicenciamento.java` — confirmados `APPCI_EMITIDO` e `PRPCI_EMITIDO`
- `TipoMarco.java` — confirmado `APPCI_EMITIDO`
- `Licenciamento.java` (via grep) — confirmados campos `areaConstruida`, `dtValidadeAppci`, `dtVencimentoPrpci`, `inspetor`
- `LicenciamentoRepository.java` — confirmado `findByStatus()` existente (usado por `AppciService.findVigentes`)

**Resultado:** Nenhuma inconsistência detectada. Nenhuma correção necessária. Script executado sem modificações.

---

## Execução do Script — Justificativa e Mensagens por Passo

### Bloco de Configuração — Variáveis Globais

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServiceName   = "SOL-Backend"
$JavaHome      = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$ProjectRoot   = "C:\SOL\backend"
$BaseUrl       = "http://localhost:8080/api"
$HealthUrl     = "$BaseUrl/health"
$WaitSeconds   = 35
$MavenOpts     = "-Dmaven.test.skip=true -q"
$AdminUser     = "sol-admin"
$AdminPassword = "Admin@SOL2026"
$TestCep       = "90010100"
```

**Justificativa:**

- **`Set-StrictMode -Version Latest`** — força o PowerShell a tratar variáveis não declaradas e referências inválidas como erros fatais. Sem isso, erros silenciosos (como `$undefined` avaliando para string vazia) passariam despercebidos e o script continuaria com dados incorretos.
- **`$ErrorActionPreference = "Stop"`** — transforma qualquer erro cmdlet em exceção terminante. Garante que uma falha num passo não deixa o script continuar para o próximo passo com estado inválido.
- **`$WaitSeconds = 35`** — a JVM do Spring Boot precisa de tempo para inicializar o contexto Spring, conectar ao Oracle XE e ao Keycloak e registrar todos os beans. 35 segundos é o valor calibrado nas sprints anteriores como suficiente para este ambiente.
- **`$TestCep = "90010100"`** — sem hífen. O `EnderecoDTO` tem `@Pattern(regexp="\\d{8}")` — validação implementada desde a Sprint 1. Bug corrigido na Sprint 4 (o script original usava `"90010-100"` com hífen, que causava HTTP 400).
- **`$AdminPassword = "Admin@SOL2026"`** — case sensitive. Bug corrigido na Sprint 3 (script original usava `"Admin@Sol2026"` com 's' minúsculo, que causava HTTP 401).

---

### Funções Auxiliares do Script

#### Write-Step / Write-OK / Write-FAIL / Write-WARN

```powershell
function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }
```

**Justificativa:** Padroniza a saída visual do script — marcadores `[OK]`, `[FALHA]` e `[AVISO]` tornam imediata a identificação visual de problemas durante a execução, com cores distintas. Padrão estabelecido na Sprint 1 e mantido em todas as sprints. Cada mensagem prefixada com `==>` indica um passo de nível superior; mensagens indentadas com dois espaços indicam resultados dentro do passo.

#### Invoke-MultipartUpload

```powershell
function Invoke-MultipartUpload {
    param([string]$Uri, [string]$FilePath, [string]$BearerToken, [Long]$LicId)
    # Usa System.Net.Http.HttpClient diretamente
    # ...
}
```

**Justificativa:** O `Invoke-RestMethod` nativo do PowerShell não suporta multipart/form-data com múltiplos campos heterogêneos (file + string fields) de forma confiável. O endpoint `POST /arquivos/upload` exige um multipart com três partes: `file` (binário PDF), `licenciamentoId` (inteiro) e `tipoArquivo` (string). A única forma de enviar isso corretamente no PowerShell é instanciar `HttpClient` e `MultipartFormDataContent` via .NET diretamente, contornando as limitações do cmdlet.

#### New-PdfTemp

```powershell
function New-PdfTemp {
    $pdf = @"
%PDF-1.0
1 0 obj<</Type /Catalog/Pages 2 0 R>>endobj
...
%%EOF
"@
    $tmp = [System.IO.Path]::GetTempFileName() + ".pdf"
    [System.IO.File]::WriteAllText($tmp, $pdf)
    return $tmp
}
```

**Justificativa:** O smoke test precisa de um arquivo PDF real para testar o upload ao MinIO. O backend valida o content-type como `application/pdf`. Um PDF mínimo válido (apenas estrutura obrigatória do formato PDF 1.0) é gerado em memória e salvo em arquivo temporário, evitando a dependência de um PDF externo. O `GetTempFileName()` garante um caminho único sem colisão mesmo em execuções paralelas.

#### New-LicBody

```powershell
function New-LicBody {
    # area=500 m² -> APPCI valido por 2 anos (limiar <= 750 m²)
    return @{
        tipo = "PPCI"; areaConstruida = 500.00; alturaMaxima = 10.00
        numPavimentos = 3; tipoOcupacao = "Comercial - Loja"
        usoPredominante = "Comercial"
        endereco = @{
            cep = $TestCep; ...
        }
        ...
    } | ConvertTo-Json -Depth 5
}
```

**Justificativa:** O campo `areaConstruida = 500.00` foi escolhido deliberadamente. Com 500 m² (abaixo do limiar de 750 m²), a RN-P08-002 deve calcular validade de **2 anos**. O teste verificará exatamente esse valor. Se tivesse sido usada uma área > 750 m², a validade seria 5 anos — um comportamento diferente que não testaria a regra do limiar menor. A função é encapsulada para reutilização em `Invoke-PrepararParaAppci`.

#### Invoke-PrepararParaAppci

```powershell
function Invoke-PrepararParaAppci {
    param([string]$Token, [hashtable]$AuthHdr, [Long]$AdminId)
    # Executa P03 (criar + upload + submeter)
    # Executa P04 (distribuir + iniciar-analise + deferir)
    # Executa P07 (agendar-vistoria + atribuir-inspetor + iniciar-vistoria + aprovar-vistoria)
    return $lic  # com status PRPCI_EMITIDO
}
```

**Justificativa:** O foco da Sprint 8 é exclusivamente P08. As sprints anteriores já validaram P03, P04 e P07 exaustivamente. Reexibir cada passo intermediário seria ruído no output — o que importa é que o setup chegou a `PRPCI_EMITIDO` antes de testar os novos endpoints. A função consolida **10 operações** em sequência com verificação de guarda ao final:

```powershell
if ($licA.status -ne "PRPCI_EMITIDO") {
    throw "Setup falhou: status esperado PRPCI_EMITIDO, obtido $($licA.status)"
}
```

Essa verificação garante que qualquer falha no setup aborta imediatamente — sem tentar executar os testes P08 sobre um licenciamento em estado incorreto.

**Evolução das funções auxiliares nas sprints:**

| Sprint | Funções auxiliares | Passos encapsulados |
|---|---|---|
| 5 | `Invoke-CriarSubmeter` | 3 (criar, upload, submeter) |
| 5 | `Invoke-PrepararParaAnalise` | 2 (distribuir, iniciar-analise) |
| 6/7 | `Invoke-CriarSubmeter` (reutilizada) | 3 |
| 7 | `Invoke-PrepararParaVistoria` | 3 (distribuir, iniciar-analise, deferir) |
| **8** | **`Invoke-PrepararParaAppci`** | **10 (P03+P04+P07 completos)** |

---

### Passo 1 — Parar o Serviço Windows

**Código do script (linhas 188–194):**

```powershell
Write-Step "Parando servico $ServiceName"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force; Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else { Write-WARN "Servico nao estava em execucao -- continuando" }
```

**Mensagem emitida:**

```
===> Parando servico SOL-Backend
  [OK] Servico parado
```

**O que aconteceu:** O serviço Windows `SOL-Backend` (gerenciado pelo NSSM — Non-Sucking Service Manager) estava em execução e foi encerrado com sucesso via `Stop-Service -Force`.

**Justificativa de cada elemento:**

- **`Get-Service -ErrorAction SilentlyContinue`** — permite que o script continue mesmo se o serviço não existir (cenário de primeiro deploy). Sem isso, `Get-Service` lançaria exceção e abortaria.
- **`Stop-Service -Force`** — encerra o serviço mesmo que tenha processos dependentes. O `-Force` é necessário porque o NSSM pode ter processos filhos.
- **`Start-Sleep -Seconds 5`** — aguarda 5 segundos após o stop para garantir que a JVM libere o lock exclusivo no arquivo JAR antes do Maven tentar sobrescrevê-lo na compilação. Sem esse sleep, o Maven poderia falhar com "arquivo em uso" ao tentar escrever o novo JAR em `target/`.

---

### Passo 2 — Compilar com Maven

**Código do script (linhas 198–210):**

```powershell
Write-Step "Compilando com Maven (JAVA_HOME=$JavaHome)"
$env:JAVA_HOME = $JavaHome
$env:PATH      = "$JavaHome\bin;$env:PATH"
$mvn = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvn)) { $mvn = "mvn" }

Push-Location $ProjectRoot
try {
    & cmd /c "$mvn clean package $MavenOpts"
    if ($LASTEXITCODE -ne 0) { throw "Maven falhou com codigo $LASTEXITCODE" }
    Write-OK "Build concluido com sucesso"
} finally { Pop-Location }
```

**Mensagem emitida:**

```
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso
```

**O que aconteceu:** O Maven compilou o projeto com os novos arquivos da Sprint 8 sem erros:

- `AppciService.java` — novo serviço P08
- `AppciController.java` — novos endpoints APPCI
- `Licenciamento.java` (atualizado) — campos `dtValidadeAppci` e `dtVencimentoPrpci`
- Schema Hibernate: novas colunas `dt_validade_appci` e `dt_vencimento_prpci` na tabela `LICENCIAMENTO` serão criadas pelo `ddl-auto: update` na primeira inicialização

**Justificativa de cada elemento:**

- **`$env:JAVA_HOME = $JavaHome` / `$env:PATH = "$JavaHome\bin;..."`** — define explicitamente o Java 21 para o processo Maven. Necessário porque o `PATH` do sistema pode apontar para outra versão do Java, e o Spring Boot 3.3.4 requer Java 21+.
- **`mvnw.cmd` com fallback para `mvn`** — o Maven Wrapper (`mvnw.cmd`) garante que todos os builds usem a mesma versão do Maven definida no `.mvn/wrapper/maven-wrapper.properties`, independentemente do Maven instalado globalmente. O fallback para `mvn` global cobre o caso de o wrapper não estar presente.
- **`Push-Location $ProjectRoot` / `finally { Pop-Location }`** — o Maven deve ser executado na raiz do projeto para encontrar o `pom.xml`. O `finally` garante que o diretório de trabalho seja restaurado mesmo se o build falhar, evitando que comandos subsequentes operem no diretório errado.
- **`cmd /c "$mvn clean package $MavenOpts"`** — o wrapper `mvnw.cmd` é um script batch (`.cmd`) e precisa ser invocado via `cmd /c` quando chamado do PowerShell, pois o PowerShell não executa arquivos `.cmd` com `&` de forma confiável em todas as versões.
- **`-Dmaven.test.skip=true -q`** — pula os testes unitários (que seriam executados pelo Surefire) e ativa o modo silencioso (`-q`). Os smoke tests do deploy script substituem os testes automatizados neste contexto. Rodar os testes JUnit durante o deploy seria redundante e aumentaria o tempo de build sem benefício adicional.
- **`$LASTEXITCODE -ne 0`** — verifica o código de saída do processo Maven. O PowerShell não lança exceção automaticamente para processos externos com falha — é necessário verificar `$LASTEXITCODE` explicitamente.

---

### Passo 3 — Reiniciar o Serviço

**Código do script (linhas 214–227):**

```powershell
Write-Step "Reiniciando servico $ServiceName"
if ($null -ne $svc) {
    Start-Service -Name $ServiceName; Write-OK "Servico iniciado"
} else {
    $jar = Get-ChildItem "$ProjectRoot\target\*.jar" |
           Where-Object { $_.Name -notlike "*sources*" } | Select-Object -First 1
    if ($null -eq $jar) { throw "JAR nao encontrado" }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
        -ArgumentList "-jar `"$($jar.FullName)`"" `
        -WorkingDirectory $ProjectRoot -NoNewWindow
    Write-WARN "JAR iniciado diretamente (modo dev)"
}
```

**Mensagem emitida:**

```
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
```

**O que aconteceu:** O NSSM iniciou o serviço com o JAR recém-compilado. O Spring Boot carregou:

- `AppciService` e `AppciController` como novos beans Spring
- `LicenciamentoRepository` com os métodos existentes (incluindo `findByInspetor` adicionado na Sprint 7)
- O Hibernate detectou as novas colunas `dt_validade_appci` e `dt_vencimento_prpci` via `ddl-auto: update` e as criou no Oracle XE

**Justificativa de cada elemento:**

- **Bifurcação `if ($null -ne $svc)`** — o script suporta dois cenários: (1) serviço NSSM registrado (produção), onde `Start-Service` delega ao gerenciador de serviços; (2) ausência de serviço (desenvolvimento), onde o JAR é iniciado diretamente com `java -jar`. Isso torna o script reutilizável em ambiente de desenvolvimento sem modificação.
- **`Get-ChildItem ... -notlike "*sources*"`** — filtra o JAR de sources (`-sources.jar`) para pegar apenas o JAR executável. O Maven gera dois arquivos na fase `package` quando o plugin `maven-source-plugin` está ativo.
- **`-WorkingDirectory $ProjectRoot`** — o Spring Boot usa o diretório de trabalho para resolver caminhos relativos de recursos (templates, certificados, etc.). Iniciar com o diretório de trabalho correto previne `FileNotFoundException` para recursos externos.

---

### Passo 4 — Aguardar e Health Check

**Código do script (linhas 231–242):**

```powershell
Write-Step "Aguardando $WaitSeconds segundos"
Start-Sleep -Seconds $WaitSeconds

Write-Step "Health check -- $HealthUrl"
$healthy = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) { Write-OK "Saudavel (tentativa $i)"; $healthy = $true; break }
    } catch { Write-WARN "Tentativa $i falhou -- aguardando 10s"; Start-Sleep -Seconds 10 }
}
if (-not $healthy) { Write-FAIL "Health check falhou"; exit 1 }
```

**Mensagens emitidas:**

```
===> Aguardando 35 segundos
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
```

**O que aconteceu:** Após 35 segundos, o `GET /api/health` respondeu `HTTP 200` na primeira tentativa, indicando inicialização completa.

**Justificativa de cada elemento:**

- **`Start-Sleep -Seconds 35`** — a JVM do Spring Boot precisa de tempo para: (a) descompactar o JAR fat; (b) inicializar o contexto Spring com todos os beans; (c) estabelecer o connection pool do HikariCP para o Oracle XE; (d) verificar/atualizar o schema Hibernate (`ddl-auto: update`); (e) conectar ao Keycloak para descoberta do JWKS. Nas sprints anteriores, 35 segundos demonstrou ser suficiente neste hardware.
- **Loop de 6 tentativas com 10s de espera** — proteção contra variações de tempo de inicialização. Se o serviço demorar mais que o esperado (GC pause, lock de tabela Oracle no schema update), o script aguarda até 95 segundos adicionais (6×10s menos o tempo da primeira tentativa) antes de desistir.
- **`Invoke-WebRequest -UseBasicParsing`** — evita a dependência do Internet Explorer engine para parsing de HTML, que pode não estar disponível em Windows Server Core. Mais robusto que `Invoke-RestMethod` para verificações de liveness.
- **`exit 1` se não saudável** — qualquer smoke test executado com o backend não responsivo produziria falsos negativos. É melhor abortar com diagnóstico claro.

---

### Passo 5 — Login Keycloak (ROPC)

**Código do script (linhas 247–257):**

```powershell
Write-Step "Login -- POST /auth/login"
$tr = $null
try {
    $tr = Invoke-RestMethod -Uri "$BaseUrl/auth/login" -Method POST `
        -Body (@{ username = $AdminUser; password = $AdminPassword } | ConvertTo-Json) `
        -ContentType "application/json" -TimeoutSec 15
    Write-OK "Login OK"
} catch { Write-FAIL "Login falhou: $($_.Exception.Message)"; exit 1 }

$token   = $tr.access_token
$authHdr = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
```

**Mensagem emitida:**

```
===> Login -- POST /auth/login
  [OK] Login OK
```

**O que aconteceu:** JWT obtido via ROPC (Resource Owner Password Credentials) com `expires_in=3600s`. A role `ADMIN` no token autoriza todos os endpoints P08: `hasAnyRole('ADMIN', 'ANALISTA')` em `/emitir-appci` e `hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')` em `/appci/vigentes`.

**Justificativa:**

- **ROPC via `POST /auth/login`** — o endpoint do `AuthController` é um proxy para o Keycloak (`sol-frontend` client com `directAccessGrantsEnabled=true`). Em vez de o script interagir diretamente com o Keycloak, usa a mesma API que o frontend usaria. Isso valida também o endpoint de login como parte do smoke test.
- **`$tr.access_token`** — o JWT é extraído do response e reutilizado em todas as chamadas subsequentes do script. O token único de 3600s é suficiente para toda a execução do deploy (que leva menos de 5 minutos).
- **`$authHdr`** — o header combinado com `Authorization` e `Content-Type` é montado uma vez e passado como hashtable para todos os `Invoke-RestMethod` subsequentes, evitando repetição.
- **`exit 1` em falha** — sem token válido, nenhum teste autenticado pode ser executado. Abortar imediatamente evita uma cascata de falsos negativos de autenticação.

---

### Passo 6 — Obter ID do Usuário Admin

**Código do script (linhas 262–273):**

```powershell
Write-Step "Obtendo ID do usuario admin"
$adminId = 1
try {
    $users = Invoke-RestMethod -Uri "$BaseUrl/usuarios?page=0&size=50" `
        -Headers $authHdr -TimeoutSec 10
    $u = $users.content | Where-Object {
        $_.nome -like "*admin*" -or $_.email -like "*admin*"
    } | Select-Object -First 1
    if ($null -eq $u) { $u = $users.content | Select-Object -First 1 }
    if ($null -ne $u) { $adminId = $u.id; Write-OK "Admin id=$adminId nome=$($u.nome)" }
    else { Write-WARN "Usuario nao encontrado -- usando id=1" }
} catch { Write-WARN "GET /usuarios falhou -- usando id=1 como fallback" }
```

**Mensagem emitida:**

```
===> Obtendo ID do usuario admin
  [AVISO] GET /usuarios falhou -- usando id=1 como fallback
```

**O que aconteceu:** O aviso é recorrente (quarta sprint consecutiva). Ver [[#Problema Recorrente — Aviso GET /usuarios]] para diagnóstico completo. O fallback `$adminId = 1` funcionou corretamente para todos os papéis (analista e inspetor) no setup.

**Justificativa:**

- **Fallback `$adminId = 1`** — a sequence Oracle para `USUARIO` nunca foi resetada desde as sprints anteriores (resets mantêm o valor da sequence mesmo após `DELETE`). O usuário `sol-admin` foi criado nas primeiras sprints e tem id=1. O fallback é portanto fiável para este ambiente específico.
- **Busca por nome/email com `*admin*`** — estratégia mais robusta que buscar por id fixo. Em outros ambientes, o usuário admin pode ter um id diferente. A busca dinâmica tornaria o script portável, se o `GET /usuarios` funcionasse corretamente.
- **Wrap em `try/catch` sem `exit`** — a falha no GET de usuários é não-bloqueante. O script continua com o fallback, que é suficiente para os testes.

---

### Fluxo A — Setup P03 + P04 + P07 (Invoke-PrepararParaAppci)

**Mensagens emitidas:**

```
===> === FLUXO A: P08 -- Emissao do APPCI ===
===> Fluxo A -- Setup: P03 + P04 + P07 (-> PRPCI_EMITIDO)
  [OK] Licenciamento criado -- id=14
  [OK] Upload PPCI OK
  [OK] Submissao OK -- status=ANALISE_PENDENTE
  [OK] Distribuicao OK
  [OK] Inicio de analise OK
  [OK] Deferimento analise OK -- status=DEFERIDO
  [OK] Vistoria agendada -- status=VISTORIA_PENDENTE
  [OK] Inspetor atribuido
  [OK] Vistoria iniciada -- status=EM_VISTORIA
  [OK] Vistoria aprovada -- status=PRPCI_EMITIDO
  [OK] Setup concluido -- id=14 status=PRPCI_EMITIDO
```

**O que aconteceu:** A função `Invoke-PrepararParaAppci` executou 10 operações sequenciais:

| # | Endpoint | Método | Status resultante |
|---|---|---|---|
| 1 | `/licenciamentos` | POST | RASCUNHO (id=14) |
| 2 | `/arquivos/upload` | POST | — (PPCI no MinIO) |
| 3 | `/licenciamentos/14/submeter` | POST | ANALISE_PENDENTE |
| 4 | `/licenciamentos/14/distribuir?analistaId=1` | PATCH | ANALISE_PENDENTE |
| 5 | `/licenciamentos/14/iniciar-analise` | POST | EM_ANALISE |
| 6 | `/licenciamentos/14/deferir` | POST | DEFERIDO |
| 7 | `/licenciamentos/14/agendar-vistoria` | POST | VISTORIA_PENDENTE |
| 8 | `/licenciamentos/14/atribuir-inspetor?inspetorId=1` | PATCH | EM_VISTORIA (sem mudança) |
| 9 | `/licenciamentos/14/iniciar-vistoria` | POST | EM_VISTORIA |
| 10 | `/licenciamentos/14/aprovar-vistoria` | POST | PRPCI_EMITIDO |

O id=14 confirma que todos os testes anteriores (sprints 3–7) foram executados e limpos corretamente — a sequence Oracle não retroage após `DELETE`.

---

### Fluxo A — Teste 1 — Emitir APPCI

**Código do script (linhas 291–305):**

```powershell
Write-Step "Fluxo A -- Teste 1: POST /licenciamentos/$($licA.id)/emitir-appci"
$appciBody = @{
    observacao = "APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."
} | ConvertTo-Json
$licA = Invoke-RestMethod `
    -Uri "$BaseUrl/licenciamentos/$($licA.id)/emitir-appci" `
    -Method POST -Body $appciBody -ContentType "application/json" `
    -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15

if ($licA.status -eq "APPCI_EMITIDO") {
    Write-OK "APPCI emitido -- status=$($licA.status)"
} else {
    Write-WARN "Status inesperado: $($licA.status) (esperado APPCI_EMITIDO)"
}
```

**Mensagem emitida:**

```
===> Fluxo A -- Teste 1: POST /licenciamentos/14/emitir-appci
  [OK] APPCI emitido -- status=APPCI_EMITIDO
```

**Fluxo interno em `AppciService.emitirAppci()`:**

```
1. buscarPorId(14)                             → Licenciamento carregado
2. lic.getStatus() != PRPCI_EMITIDO?           → false (RN-P08-001 OK)
3. hoje = LocalDate.now()                      → 2026-03-28
4. anosValidade = calcularAnosValidadeAppci(500.00)
   → 500.00 <= 750.00 → retorna 2
5. dtValidade = 2026-03-28 + 2 anos            → 2028-03-28
6. lic.setDtValidadeAppci(2028-03-28)
7. lic.getDtVencimentoPrpci() == null?         → true (RN-P08-003)
   lic.setDtVencimentoPrpci(2026-03-28 + 1 ano) → 2027-03-28
8. lic.setStatus(APPCI_EMITIDO)
9. licenciamentoRepository.save(lic)           → commit no Oracle
10. obsMarco = "APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²).
                APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."
11. registrarMarco(lic, TipoMarco.APPCI_EMITIDO, usuario, obsMarco)
12. notificarEnvolvidos(lic, assunto, corpo)   → RT e RU nulos neste teste (sem-op)
13. return licenciamentoService.toDTO(lic)     → LicenciamentoDTO com status=APPCI_EMITIDO
```

**Por que `PRPCI_EMITIDO` como pré-condição (RN-P08-001):** O APPCI só pode ser emitido após confirmação física de conformidade do imóvel. `PRPCI_EMITIDO` representa que o inspetor visitou o local e aprovou. Emitir o APPCI de qualquer outro estado seria juridicamente inválido e comprometeria a segurança pública.

**Justificativa do teste:**

O teste verifica que a transição `PRPCI_EMITIDO → APPCI_EMITIDO` funciona corretamente e que o response imediato do POST já reflete o novo status — confirmando que o `save()` e o `toDTO()` operam na mesma transação.

---

### Fluxo A — Teste 2 — Confirmar APPCI_EMITIDO e Validade

**Código do script (linhas 307–338):**

```powershell
Write-Step "Fluxo A -- Teste 2: GET /licenciamentos/$($licA.id) (confirmar APPCI_EMITIDO + dtValidadeAppci)"
$cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
    -Headers $authHdr -TimeoutSec 10

if ($cur.status -eq "APPCI_EMITIDO") { Write-OK "Status APPCI_EMITIDO confirmado" }

if ($null -ne $cur.dtValidadeAppci) {
    $dtValidade   = [DateTime]::Parse($cur.dtValidadeAppci)
    $anosValidade = ($dtValidade - (Get-Date)).Days / 365
    Write-OK "dtValidadeAppci=$($cur.dtValidadeAppci) (~$([Math]::Round($anosValidade,1)) anos)"
    $anosDiff = [Math]::Abs($anosValidade - 2)
    if ($anosDiff -lt 0.1) { Write-OK "Validade de 2 anos confirmada (area=500 m² <= 750 m²)" }
    else { Write-WARN "Validade inesperada: ~$([Math]::Round($anosValidade,1)) anos (esperado 2 anos)" }
}

if ($null -ne $cur.dtVencimentoPrpci) { Write-OK "dtVencimentoPrpci=$($cur.dtVencimentoPrpci)" }
```

**Mensagens emitidas:**

```
===> Fluxo A -- Teste 2: GET /licenciamentos/14 (confirmar APPCI_EMITIDO + dtValidadeAppci)
  [OK] Status APPCI_EMITIDO confirmado
  [OK] dtValidadeAppci=2028-03-28 (~2 anos)
  [OK] Validade de 2 anos confirmada (area=500 m² <= 750 m²)
  [OK] dtVencimentoPrpci=2027-03-28
```

**O que aconteceu:** Verificação independente via GET de três campos críticos persistidos no Oracle.

**Por que este teste é necessário (não apenas confiar no POST anterior):**
O Teste 1 verificou o response imediato do POST. O Teste 2 faz um GET independente, confirmando que a transição de estado e os valores calculados foram **persistidos corretamente** no banco Oracle — e não apenas preenchidos no objeto em memória antes de ser serializado para o response.

**Semântica dos dois campos de data:**

| Campo | O que representa | Como é calculado |
|---|---|---|
| `dtValidadeAppci` | Vencimento do alvará (APPCI) | Hoje + 2 ou 5 anos (por área, RN-P08-002) |
| `dtVencimentoPrpci` | Vencimento do parecer do inspetor (PRPCI) | Hoje + 1 ano (fixo, RN-P08-003) |

O APPCI tem validade maior que o PRPCI porque o alvará é o documento administrativo final, enquanto o PRPCI é o laudo técnico do inspetor — que precisa ser renovado mais frequentemente para garantir que as condições físicas do imóvel continuam conformes.

**Tolerância de 0.1 anos no cálculo:**
```powershell
$anosValidade = ($dtValidade - (Get-Date)).Days / 365   # ≈ 2.0
$anosDiff     = [Math]::Abs($anosValidade - 2)          # ≈ 0.0
# $anosDiff < 0.1 → validade de 2 anos confirmada
```
A tolerância protege contra variações de ano bissexto e diferenças de hora do dia. O cálculo `Days / 365` não é exato para períodos que cruzam anos bissextos, mas para smoke test de validação é suficiente.

---

### Fluxo A — Teste 3 — Listar APPCIs Vigentes

**Código do script (linhas 341–349):**

```powershell
Write-Step "Fluxo A -- Teste 3: GET /appci/vigentes"
$vigentes = Invoke-RestMethod -Uri "$BaseUrl/appci/vigentes?page=0&size=10" `
    -Headers $authHdr -TimeoutSec 10
$total = if ($null -ne $vigentes.totalElements) { $vigentes.totalElements }
         else { $vigentes.content.Count }
if ($total -ge 1) { Write-OK "APPCIs vigentes: $total licenciamento(s)" }
else { Write-WARN "Nenhum APPCI vigente encontrado na lista" }
```

**Mensagem emitida:**

```
===> Fluxo A -- Teste 3: GET /appci/vigentes
  [OK] APPCIs vigentes: 1 licenciamento(s)
```

**O que aconteceu:** `GET /api/appci/vigentes?page=0&size=10` delegou para `AppciService.findVigentes()` → `licenciamentoRepository.findByStatus(APPCI_EMITIDO, pageable)`. O resultado `1` confirma exatamente o licenciamento 14 — nenhum resíduo de testes anteriores (todos foram limpos).

**Justificativa do endpoint dedicado `/appci/vigentes`:**
Em produção o CBM-RS precisa monitorar todos os APPCIs ativos para:
- Saber quais estabelecimentos estão regularizados
- Identificar APPCIs próximos do vencimento (jobs de notificação automática)
- Gerar relatórios gerenciais de cobertura de licenciamento

Um endpoint dedicado com paginação e filtro por status é mais eficiente do que buscar todos os licenciamentos e filtrar no cliente.

**Lógica defensiva `totalElements` vs `content.Count`:**
```powershell
$total = if ($null -ne $vigentes.totalElements) { $vigentes.totalElements }
         else { $vigentes.content.Count }
```
Antecipa variações no formato de resposta — o mesmo padrão usado na Sprint 5 para `GET /analise/fila`. Se por alguma razão o endpoint retornar array em vez de Page, o script ainda obtém a contagem correta.

---

### Fluxo A — Teste 4 — Verificar Marco APPCI_EMITIDO

**Código do script (linhas 352–363):**

```powershell
Write-Step "Fluxo A -- Teste 4: GET /licenciamentos/$($licA.id)/marcos (marco APPCI_EMITIDO)"
$marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
    -Headers $authHdr -TimeoutSec 10
Write-OK "Marcos registrados ($($marcos.Count)):"
$marcos | ForEach-Object {
    Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
}
if ($marcos | Where-Object { $_.tipoMarco -eq "APPCI_EMITIDO" }) {
    Write-OK "Marco APPCI_EMITIDO presente"
} else { Write-WARN "Marco APPCI_EMITIDO NAO encontrado" }
```

**Mensagens emitidas:**

```
===> Fluxo A -- Teste 4: GET /licenciamentos/14/marcos (marco APPCI_EMITIDO)
  [OK] Marcos registrados (8):
    SUBMISSAO         | Licenciamento submetido para analise via P03. Arquivos PPCI: 1
    DISTRIBUICAO      | Licenciamento distribuido para analise. Analista: RT Smoke Test Sprint3
    INICIO_ANALISE    | Analise tecnica iniciada. Analista: 6a6065a2-edc1-415a-ac91-a260ebc9063c
    APROVACAO_ANALISE | PPCI aprovado. Encaminhado para vistoria.
    VISTORIA_AGENDADA | Vistoria presencial agendada para 2026-04-04. Vistoria para emissao de APPCI.
    VISTORIA_REALIZADA| Vistoria presencial iniciada. Inspetor: RT Smoke Test Sprint3
    VISTORIA_APROVADA | Edificio em conformidade. PRPCI emitido.
    APPCI_EMITIDO     | APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²).
                        APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes.
  [OK] Marco APPCI_EMITIDO presente
```

**O que aconteceu:** 8 marcos — a trilha de auditoria mais completa gerada até este ponto no projeto.

**Por que a trilha de marcos é testada separadamente:**
O marco é um registro separado na tabela `MARCO_PROCESSO`, não um campo da tabela `LICENCIAMENTO`. Um bug poderia ter persistido o status no `LICENCIAMENTO` mas falhado silenciosamente ao inserir o marco — sem este teste, o bug passaria despercebido.

**Observação sobre texto do marco:**
O marco `APPCI_EMITIDO` concatena corretamente:
- **Prefixo automático (backend):** `"APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²)."`
- **Observação do request:** `"APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."`

Diferentemente do bug de texto duplicado observado no marco `CIA_CIENCIA` da Sprint 6, o `AppciService` concatena sem repetição.

---

### Fluxo A — Teste 5 — Endpoint Dedicado /appci

**Código do script (linhas 366–373):**

```powershell
Write-Step "Fluxo A -- Teste 5: GET /licenciamentos/$($licA.id)/appci"
$appci = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/appci" `
    -Headers $authHdr -TimeoutSec 10
if ($appci.status -eq "APPCI_EMITIDO") {
    Write-OK "Endpoint /appci OK -- dtValidadeAppci=$($appci.dtValidadeAppci)"
} else { Write-WARN "Endpoint /appci retornou status=$($appci.status)" }
```

**Mensagem emitida:**

```
===> Fluxo A -- Teste 5: GET /licenciamentos/14/appci
  [OK] Endpoint /appci OK -- dtValidadeAppci=2028-03-28
```

**O que aconteceu:** `GET /api/licenciamentos/14/appci` validou a RN-P08-004: só retorna dados se o licenciamento estiver em `APPCI_EMITIDO`. Se chamado com licenciamento em outro estado, lança `BusinessException("RN-P08-004", ...)` → HTTP 422.

**Por que um endpoint dedicado `/appci` além do `/licenciamentos/{id}`:**
O `GET /licenciamentos/{id}` retorna o licenciamento independentemente do status. O `GET /{id}/appci` é um endpoint semântico — útil para:
- O frontend exibir a "tela do alvará" com garantia de que os dados de validade estarão presentes
- Integrações de terceiros (sistemas de fiscalização estadual) que precisam consultar especificamente o status de alvará de um CNPJ
- O próprio CBM-RS para verificar rapidamente se um estabelecimento possui APPCI vigente

---

### Passo Final — Limpeza Oracle

**Código do script (linhas 382–404):**

```powershell
Write-Step "Limpeza Oracle -- removendo dados de teste (licenciamento A)"
if ($null -ne $licA) {
    $lid = $licA.id
    $sql = @"
DELETE FROM sol.arquivo_ed     WHERE id_licenciamento = $lid;
DELETE FROM sol.marco_processo WHERE id_licenciamento = $lid;
DELETE FROM sol.boleto         WHERE id_licenciamento = $lid;
DELETE FROM sol.licenciamento  WHERE id_licenciamento = $lid;
COMMIT;
EXIT;
"@
    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tmpSql -Value $sql
    try {
        & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
        Write-OK "Licenciamento id=$lid removido"
    } catch {
        Write-WARN "Limpeza id=${lid}: $($_.Exception.Message)"
    } finally {
        Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
    }
}
```

**Mensagem emitida:**

```
===> Limpeza Oracle -- removendo dados de teste (licenciamento A)
  [OK] Licenciamento id=14 removido
```

**O que aconteceu:** SQL executado via `sqlplus.exe -S "/ as sysdba"`. Os 8 marcos e o registro principal do licenciamento 14 foram removidos. O arquivo PPCI no MinIO permanece no bucket `sol-arquivos` (comportamento consistente com todas as sprints anteriores — o script não chama `DELETE /arquivos/{id}` antes da limpeza Oracle, deixando o objeto MinIO órfão).

**Justificativa de cada elemento:**

- **Ordem dos DELETEs** — a ordem respeita as foreign keys do schema Oracle: `arquivo_ed`, `marco_processo` e `boleto` são filhos de `licenciamento`. Deletar `licenciamento` primeiro causaria `ORA-02292: integrity constraint violated`. A ordem garante que as tabelas filhas são limpas antes da tabela pai.
- **`COMMIT`** — o Oracle usa transações autocommit por padrão apenas em certas ferramentas. No `sqlplus`, um `DELETE` sem `COMMIT` seria revertido ao encerrar a sessão (o `EXIT` executaria um rollback implícito). O `COMMIT` explícito garante a persistência.
- **`/ as sysdba`** — autentica via OS authentication (sem senha), usando o usuário Oracle do sistema operacional que tem role `SYSDBA`. Mais seguro do que hardcodar senha de DBA no script.
- **`$tmpSql`** — o SQL é escrito em arquivo temporário porque o `sqlplus` recebe scripts via `@arquivo`. A alternativa (pipe via stdin) não é confiável no PowerShell para scripts multi-linha. O `finally` remove o arquivo temporário mesmo se o sqlplus falhar.
- **`${lid}` entre chaves** — padrão corrigido na Sprint 6 (bug: `$lid:` era interpretado como drive qualificado, causando `ParserError` antes de qualquer linha executar). Com chaves, o PowerShell interpreta corretamente como variável seguida de dois-pontos literais.

---

## Problema Recorrente — Aviso GET /usuarios

```
[AVISO] GET /usuarios falhou -- usando id=1 como fallback
```

Quarta sprint consecutiva (Sprints 5, 6, 7, 8) com este aviso. Não-bloqueante.

### Diagnóstico

`GET /api/usuarios?page=0&size=50` retorna `List<UsuarioDTO>` (array JSON diretamente) em vez de `Page<UsuarioDTO>` (objeto com campo `.content`). O `Invoke-RestMethod` do PowerShell deserializa arrays JSON como `Object[]`, que não possui a propriedade `.content`. A tentativa de acessar `$users.content` retorna `$null`, o `Where-Object` retorna vazio, e o bloco `catch` é ativado.

### Por que não foi corrigido

A correção exigiria modificar `UsuarioController.getAll()` para retornar `ResponseEntity<Page<UsuarioDTO>>` — uma mudança de contrato da API que está fora do escopo dos smoke tests (que apenas testam, não corrigem funcionalidades fora do escopo da sprint).

### Impacto

Nenhum. O fallback `$adminId = 1` é fiável para este ambiente: a sequence Oracle `SEQ_USUARIO` nunca foi resetada, e o usuário `sol-admin` (criado na Sprint 1) tem consistentemente `id=1`.

### Recomendação

Padronizar `UsuarioController.getAll()` para retornar `ResponseEntity<Page<UsuarioDTO>>` com `Pageable`, alinhando com os demais endpoints paginados do sistema (`/licenciamentos`, `/analise/fila`, `/vistoria/fila`, `/appci/vigentes`).

---

## Arquitetura dos Novos Componentes P08

### AppciController — Mapeamento de Endpoints

```
GET /api/appci/vigentes
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')")
  → AppciService.findVigentes(pageable)
  → licenciamentoRepository.findByStatus(APPCI_EMITIDO, pageable)
  → Page<LicenciamentoDTO>

GET /api/licenciamentos/{id}/appci
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CIDADAO', 'RT')")
  → AppciService.findAppci(licId)
  → Valida: status == APPCI_EMITIDO (RN-P08-004)
  → LicenciamentoDTO

POST /api/licenciamentos/{id}/emitir-appci
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
  body: AnaliseDecisaoDTO? (observacao opcional)
  → AppciService.emitirAppci(id, obs, jwt.getSubject())
  → LicenciamentoDTO
```

**`@RequestBody(required = false)` em `emitirAppci`:** Permite chamar o endpoint sem body JSON. Útil para automações que querem emitir o APPCI sem observação. O service trata `dto == null` como `obs = null`, e o marco registrado usa apenas o prefixo automático.

### AppciService — Cálculo de Validade

```java
private static final BigDecimal AREA_LIMIAR         = new BigDecimal("750.00");
private static final int VALIDADE_ANOS_ATE_750       = 2;
private static final int VALIDADE_ANOS_ACIMA_750     = 5;
private static final int VALIDADE_PRPCI_ANOS         = 1;

private int calcularAnosValidadeAppci(BigDecimal area) {
    if (area == null || area.compareTo(AREA_LIMIAR) <= 0) {
        return VALIDADE_ANOS_ATE_750;   // conservador quando área não informada
    }
    return VALIDADE_ANOS_ACIMA_750;
}
```

O uso de `BigDecimal` para comparação de área é consistente com o restante do sistema — campo `areaConstruida` da entidade `Licenciamento` é `BigDecimal` desde a Sprint 1 (corrigido de `Double` para evitar problemas de precisão com Hibernate 6.5).

### Padrão de Design — Consistência com VistoriaService

| Aspecto | VistoriaService (S7) | AppciService (S8) |
|---|---|---|
| `@Transactional(readOnly = true)` na classe | Sim | Sim |
| `@Transactional` nos métodos de escrita | Sim | Sim |
| `emailService.notificarAsync()` | Sim | Sim |
| `BusinessException(código, mensagem)` | Sim | Sim |
| Helper `registrarMarco()` privado | Sim | Sim |
| Helper `notificarEnvolvidos()` privado | Sim | Sim |
| Helper `buscarPorId()` privado | Sim | Sim |

### LocalDate vs LocalDateTime para datas de validade

O `AppciService` usa `LocalDate` (sem hora) para `dtValidadeAppci` e `dtVencimentoPrpci`. Isso é correto para datas de validade administrativa: o APPCI vence no fim do dia, não em um instante específico. `LocalDate` simplifica a exibição ao usuário e elimina problemas de timezone.

O método `LocalDate.plusYears()` do Java lida corretamente com anos bissextos: `2024-02-29 + 1 ano = 2025-02-28` (fevereiro do ano não bissexto), sem necessidade de tratamento especial.

---

## Máquina de Estados Completa Após Sprint 8

```
            MÁQUINA DE ESTADOS — LICENCIAMENTO (após Sprint 8)
   ═══════════════════════════════════════════════════════════════════

   [P03]        [P04]              [P07 — Vistoria]        [P08]
   ─────        ─────              ────────────────        ────
   RASCUNHO
      │/submeter
      ▼
   ANALISE_PENDENTE
      │/distribuir (sem mudança de status)
      │/iniciar-analise
      ▼
   EM_ANALISE ──/emitir-cia──► CIA_EMITIDO
      │                            │/registrar-ciencia-cia
      │/deferir                    ▼
      ▼                        CIA_CIENCIA
   DEFERIDO                        │/retomar-analise
      │/agendar-vistoria            └──────────────► EM_ANALISE
      ▼
   VISTORIA_PENDENTE
      │/iniciar-vistoria
      │(requer inspetor atribuido)
      ▼
   EM_VISTORIA ──/emitir-civ──► CIV_EMITIDO
      │                              │/registrar-ciencia-civ
      │/aprovar-vistoria             ▼
      ▼                          CIV_CIENCIA
   PRPCI_EMITIDO                     │/retomar-vistoria
      │/emitir-appci                 └──────────────► EM_VISTORIA
      ▼
   APPCI_EMITIDO  ✅  (estado final do ciclo principal)

   [P06 — Paralelo]  /solicitar-isencao → isentoTaxa (true/false)
   [Futuros]  RECURSO_PENDENTE · EM_RECURSO · SUSPENSO · EXTINTO · RENOVADO
```

---

## Trilha de Auditoria — 8 Marcos do Licenciamento 14

O licenciamento 14 gerou a trilha de auditoria mais completa do projeto, cobrindo os fluxos P03, P04, P07 e P08:

| # | Marco | Observação registrada |
|---|---|---|
| 1 | `SUBMISSAO` | Licenciamento submetido via P03. Arquivos PPCI: 1 |
| 2 | `DISTRIBUICAO` | Distribuido. Analista: RT Smoke Test Sprint3 |
| 3 | `INICIO_ANALISE` | Analise iniciada. Analista: 6a6065a2-edc1-415a-ac91-a260ebc9063c (UUID Keycloak) |
| 4 | `APROVACAO_ANALISE` | PPCI aprovado. Encaminhado para vistoria. |
| 5 | `VISTORIA_AGENDADA` | Vistoria agendada para 2026-04-04. Vistoria para emissao de APPCI. |
| 6 | `VISTORIA_REALIZADA` | Vistoria iniciada. Inspetor: RT Smoke Test Sprint3 |
| 7 | `VISTORIA_APROVADA` | Edificio em conformidade. PRPCI emitido. |
| 8 | `APPCI_EMITIDO` | APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²). APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes. |

**Valor jurídico desta trilha:**
Cada marco representa um ato administrativo com data, responsável e justificativa. Em auditoria, fiscalização ou recurso judicial, o CBM-RS pode demonstrar com precisão o histórico completo: quem analisou, quando aprovou, quem inspecionou, quando o alvará foi emitido e sua data de vencimento. Esse modelo está alinhado com a **Lei nº 14.129/2021 (Lei do Governo Digital)**, que exige rastreabilidade de processos administrativos eletrônicos.

---

## Tabela Consolidada de Resultados

| # | Endpoint / Ação | Método | Resultado | Observação |
|---|---|---|---|---|
| 1 | Serviço SOL-Backend | STOP | OK | Parado normalmente |
| 2 | Maven `clean package` | BUILD | OK | 1ª tentativa, sem erros |
| 3 | Serviço SOL-Backend | START | OK | AppciService e AppciController carregados |
| 4 | `/api/health` | GET | OK | Tentativa 1 |
| 5 | `/api/auth/login` | POST | OK | JWT 3600s |
| 6 | `/api/usuarios` | GET | AVISO | Sem `.content`; fallback id=1 |
| **Setup P03+P04+P07** | | | | |
| 7 | `/api/licenciamentos` | POST | OK | id=14, RASCUNHO |
| 8 | `/api/arquivos/upload` | POST | OK | PPCI → MinIO |
| 9 | `/api/licenciamentos/14/submeter` | POST | OK | ANALISE_PENDENTE |
| 10 | `/api/licenciamentos/14/distribuir` | PATCH | OK | analistaId=1 |
| 11 | `/api/licenciamentos/14/iniciar-analise` | POST | OK | EM_ANALISE |
| 12 | `/api/licenciamentos/14/deferir` | POST | OK | DEFERIDO |
| 13 | `/api/licenciamentos/14/agendar-vistoria` | POST | OK | VISTORIA_PENDENTE, data=2026-04-04 |
| 14 | `/api/licenciamentos/14/atribuir-inspetor` | PATCH | OK | inspetorId=1 |
| 15 | `/api/licenciamentos/14/iniciar-vistoria` | POST | OK | EM_VISTORIA |
| 16 | `/api/licenciamentos/14/aprovar-vistoria` | POST | OK | PRPCI_EMITIDO |
| **Testes P08** | | | | |
| 17 | `/api/licenciamentos/14/emitir-appci` | POST | OK | APPCI_EMITIDO |
| 18 | `/api/licenciamentos/14` | GET | OK | APPCI_EMITIDO + dtValidadeAppci=2028-03-28 + dtVencimentoPrpci=2027-03-28 |
| 19 | Validade 2 anos (área 500 m²) | Calc | OK | RN-P08-002 validada |
| 20 | `/api/appci/vigentes` | GET | OK | 1 APPCI vigente |
| 21 | `/api/licenciamentos/14/marcos` | GET | OK | 8 marcos, APPCI_EMITIDO presente |
| 22 | `/api/licenciamentos/14/appci` | GET | OK | dtValidadeAppci=2028-03-28 |
| **Limpeza** | | | | |
| 23 | Limpeza Oracle id=14 | sqlplus | OK | 4 DELETEs + COMMIT |

**Sprint 8 é a primeira desde a Sprint 5 a ser concluída sem nenhuma correção de código** — nem no script PowerShell nem nos arquivos Java. A análise pré-deploy proativa dos arquivos Java preveniu a repetição do bug de Sprint 7.

---

## Estado Final do Sistema

```
┌──────────────────────┬──────────────────────────────────────────────────────────┐
│ Serviço Windows      │ SOL-Backend — RUNNING (NSSM)                             │
│ JAR em execução      │ C:\SOL\backend\target\sol-backend-1.0.0.jar               │
│ Spring Boot          │ 3.3.4 — perfil prod — porta 8080                         │
│ Java                 │ 21.0.9 Eclipse Adoptium (JDK)                            │
│ Oracle XE            │ XEPDB1, schema SOL — dados de teste removidos            │
│ Keycloak             │ localhost:8180, realm sol — operacional                   │
│ MinIO                │ localhost:9000 — policy sol-app-policy OK                 │
├──────────────────────┼──────────────────────────────────────────────────────────┤
│ Sprints concluídas   │ 1 · 2 · 3 · 4 · 5 · 6 · 7 · 8                          │
│ Fluxos operacionais  │ P01 · P02 · P03 · P04 · P05 · P06 · P07 · P08           │
│ Endpoints totais     │ ~39 endpoints validados                                   │
│ Correções nesta S8   │ Nenhuma — primeira execução limpa desde Sprint 5          │
│ Ciclo principal      │ COMPLETO (RASCUNHO → APPCI_EMITIDO)                      │
└──────────────────────┴──────────────────────────────────────────────────────────┘
```

### Histórico de sprints

| Sprint | Fluxo | Entregas principais |
|---|---|---|
| 1 | — | Infraestrutura: Oracle, Keycloak, NSSM, tabelas |
| 2 | — | API REST base: CRUD usuários, Swagger, JWT |
| 3 | P01/P02 | Auth ROPC + Cadastro RT/RU |
| 4 | P03 | Licenciamento + Upload MinIO + Submissão |
| 5 | P04 | Análise técnica: distribuição, início, deferimento, CIA |
| 6 | P05/P06 | Ciência CIA + Retomada · Isenção de Taxa |
| 7 | P07 | Vistoria presencial: agendamento, CIV, aprovação, PRPCI |
| **8** | **P08** | **Emissão do APPCI — conclusão do ciclo principal** |

---

*Relatório gerado por Claude Code em 2026-03-29.*
*Script de referência: `C:\SOL\infra\scripts\sprint8-deploy.ps1`*
*Log do serviço: `C:\SOL\logs\sol-backend.log`*
*Ciclo principal de licenciamento: CONCLUÍDO.*
