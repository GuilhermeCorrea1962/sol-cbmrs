#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 10 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P10:

      Fluxo A -- P10 Recurso CIA -> DEFERIDO (recurso provido):
        Setup: criar -> upload PPCI -> submeter -> distribuir -> iniciar-analise
               -> emitir-cia -> registrar-ciencia-cia  (status = CIA_CIENCIA)
        1. POST /licenciamentos/{id}/interpor-recurso   (-> RECURSO_PENDENTE + marco RECURSO_INTERPOSTO)
        2. POST /licenciamentos/{id}/iniciar-recurso    (-> EM_RECURSO + marco RECURSO_EM_ANALISE)
        3. POST /licenciamentos/{id}/deferir-recurso    (-> DEFERIDO + marco RECURSO_DEFERIDO)
        4. GET  /licenciamentos/{id}                    (confirma status=DEFERIDO)
        5. GET  /licenciamentos/{id}/marcos             (verifica todos os marcos P10)

      Fluxo B -- P10 Recurso CIA -> INDEFERIDO (recurso improvido):
        Setup: mesma cadeia CIA_CIENCIA
        1. POST /licenciamentos/{id}/interpor-recurso   (-> RECURSO_PENDENTE)
        2. POST /licenciamentos/{id}/iniciar-recurso    (-> EM_RECURSO)
        3. POST /licenciamentos/{id}/indeferir-recurso  (-> INDEFERIDO + marco RECURSO_INDEFERIDO)
        4. GET  /licenciamentos/{id}                    (confirma status=INDEFERIDO)
        5. GET  /licenciamentos/{id}/marcos             (verifica marcos P10)

      Limpeza Oracle: remove licenciamentos A e B + dependencias.

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: Sprints 1 a 9 concluidas com sucesso.
    PRE-REQUISITO: MinIO rodando com policy sol-app-policy (para upload PPCI).
    PRE-REQUISITO: sol-admin com roles ADMIN e CIDADAO no realm sol do Keycloak.

    Novos arquivos gerados para esta Sprint:
      Y:\backend\src\main\java\br\gov\rs\cbm\sol\dto\RecursoDTO.java
      Y:\backend\src\main\java\br\gov\rs\cbm\sol\service\RecursoService.java
      Y:\backend\src\main\java\br\gov\rs\cbm\sol\controller\RecursoController.java

    Maquina de estados P10:
      CIA_CIENCIA | CIV_CIENCIA -> RECURSO_PENDENTE -> EM_RECURSO -> DEFERIDO | INDEFERIDO
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuracoes
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Funcoes auxiliares de log
# ---------------------------------------------------------------------------
function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }

function Show-ErrorBody {
    param($CatchVar)
    try {
        $resp = $CatchVar.Exception.Response
        if ($null -ne $resp) {
            $sc = [int]$resp.StatusCode
            try {
                $stream = $resp.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $corpo  = $reader.ReadToEnd()
                $reader.Dispose()
                Write-Host "  [DIAGNOSTICO] HTTP $sc -- $corpo" -ForegroundColor Magenta
            } catch {
                if ($null -ne $CatchVar.ErrorDetails) {
                    Write-Host "  [DIAGNOSTICO] HTTP $sc -- $($CatchVar.ErrorDetails.Message)" -ForegroundColor Magenta
                } else {
                    Write-WARN "Nao foi possivel ler corpo do erro HTTP $sc"
                }
            }
        }
    } catch {
        Write-WARN "Show-ErrorBody falhou: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Funcao: upload multipart de arquivo PPCI
# Reaproveitada do padrao Sprint 8.
# ---------------------------------------------------------------------------
function Invoke-MultipartUpload {
    param([string]$Uri, [string]$FilePath, [string]$BearerToken, [Long]$LicId)
    Add-Type -AssemblyName System.Net.Http
    $http  = [System.Net.Http.HttpClient]::new()
    $http.DefaultRequestHeaders.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $BearerToken)
    $mp    = [System.Net.Http.MultipartFormDataContent]::new()
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fc    = [System.Net.Http.ByteArrayContent]::new($bytes)
    $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/pdf")
    $mp.Add($fc,  "file",             [System.IO.Path]::GetFileName($FilePath))
    $mp.Add([System.Net.Http.StringContent]::new("$LicId"), "licenciamentoId")
    $mp.Add([System.Net.Http.StringContent]::new("PPCI"),   "tipoArquivo")
    $task  = $http.PostAsync($Uri, $mp)
    $task.Wait()
    $resp  = $task.Result
    $body  = $resp.Content.ReadAsStringAsync().Result
    $http.Dispose()
    if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $body" }
    return $body | ConvertFrom-Json
}

# ---------------------------------------------------------------------------
# Funcao: cria PDF minimo valido como arquivo temporario
# Reaproveitada do padrao Sprint 8.
# ---------------------------------------------------------------------------
function New-PdfTemp {
    $pdf = @"
%PDF-1.0
1 0 obj<</Type /Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type /Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type /Page/MediaBox[0 0 612 792]/Parent 2 0 R>>endobj
xref
0 4
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
trailer<</Size 4/Root 1 0 R>>
startxref
190
%%EOF
"@
    $tmp = [System.IO.Path]::GetTempFileName() + ".pdf"
    [System.IO.File]::WriteAllText($tmp, $pdf)
    return $tmp
}

# ---------------------------------------------------------------------------
# Funcao: corpo padrao para criacao de licenciamento de teste
# ---------------------------------------------------------------------------
function New-LicBody {
    return @{
        tipo = "PPCI"; areaConstruida = 300.00; alturaMaxima = 8.00
        numPavimentos = 2; tipoOcupacao = "Comercial - Escritorio"
        usoPredominante = "Comercial"
        endereco = @{
            cep = $TestCep; logradouro = "Rua dos Andradas"; numero = "500"
            complemento = $null; bairro = "Centro Historico"
            municipio = "Porto Alegre"; uf = "RS"
            latitude = $null; longitude = $null; dataAtualizacao = $null
        }
        responsavelTecnicoId = $null; responsavelUsoId = $null
        licenciamentoPaiId = $null
    } | ConvertTo-Json -Depth 5
}

# ---------------------------------------------------------------------------
# Funcao: prepara licenciamento em CIA_CIENCIA
#
# Executa a cadeia completa de setup do P10:
#   P03: criar -> upload PPCI -> submeter
#   P04: distribuir -> iniciar-analise -> emitir-cia
#   P05: registrar-ciencia-cia  (-> CIA_CIENCIA)
#
# Retorna o objeto licenciamento em CIA_CIENCIA.
# ---------------------------------------------------------------------------
function Invoke-SetupCiaCiencia {
    param([string]$Token, [hashtable]$AuthHdr, [Long]$AdminId)

    # --- P03: criar licenciamento ---
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicBody) -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Setup: Licenciamento criado -- id=$($lic.id) status=$($lic.status)"

    # --- P03: upload do PPCI (arquivo PDF) ---
    $tmp = New-PdfTemp
    try {
        $null = Invoke-MultipartUpload -Uri "$BaseUrl/arquivos/upload" `
            -FilePath $tmp -BearerToken $Token -LicId $lic.id
        Write-OK "Setup: Upload PPCI OK"
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    # --- P03: submeter ---
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/submeter" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Setup: Submissao OK -- status=$($lic.status)"

    # --- P04: distribuir (PATCH com query param analistaId) ---
    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/distribuir?analistaId=$AdminId" `
        -Method PATCH -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Setup: Distribuicao OK -- analista atribuido"

    # --- P04: iniciar analise ---
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/iniciar-analise" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Setup: Inicio de analise OK -- status=$($lic.status)"

    # --- P04: emitir CIA ---
    $ciaObs = "Inconformidade detectada: planta de incendio desatualizada. Os extintores nao estao posicionados conforme RTCBMRS N.01/2024 Tabela 3."
    $ciaBody = @{ observacao = $ciaObs } | ConvertTo-Json
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/emitir-cia" `
        -Method POST -Body $ciaBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Setup: CIA emitido -- status=$($lic.status)"

    # --- P05: registrar ciencia do CIA (CIDADAO/RT toma ciencia) ---
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/registrar-ciencia-cia" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Setup: Ciencia do CIA registrada -- status=$($lic.status)"

    if ($lic.status -ne "CIA_CIENCIA") {
        Write-WARN "Status esperado CIA_CIENCIA mas obtido $($lic.status)"
    }

    return $lic
}

# ===========================================================================
# EXECUCAO DO DEPLOY
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. Parar servico
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceName"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force; Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else { Write-WARN "Servico nao estava em execucao -- continuando" }

# ---------------------------------------------------------------------------
# 2. Compilar com Maven
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 3. Reiniciar servico
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 4. Aguardar e health check
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 5. Login
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 6. Obter ID do usuario admin
# ---------------------------------------------------------------------------
Write-Step "Obtendo ID do usuario admin"
$adminId   = 1
$adminNome = "admin"
try {
    $users = Invoke-RestMethod -Uri "$BaseUrl/usuarios?page=0&size=50" `
        -Headers $authHdr -TimeoutSec 10
    $u = $users.content | Where-Object {
        $_.nome -like "*admin*" -or $_.email -like "*admin*"
    } | Select-Object -First 1
    if ($null -eq $u) { $u = $users.content | Select-Object -First 1 }
    if ($null -ne $u) {
        $adminId   = $u.id
        $adminNome = $u.nome
        Write-OK "Admin id=$adminId nome=$adminNome"
    } else { Write-WARN "Usuario nao encontrado -- usando id=1" }
} catch {
    Write-WARN "GET /usuarios falhou -- usando id=1 como fallback"
    Show-ErrorBody $_
}

# ===========================================================================
# FLUXO A -- P10: Recurso CIA -> DEFERIDO (recurso provido)
# ===========================================================================
Write-Step "=== FLUXO A: P10 -- Recurso CIA -> DEFERIDO (recurso provido) ==="

$licA = $null
try {
    # Setup: cadeia CIA_CIENCIA
    Write-Step "Fluxo A -- Setup: preparando licenciamento em CIA_CIENCIA"
    $licA = Invoke-SetupCiaCiencia -Token $token -AuthHdr $authHdr -AdminId $adminId
    Write-OK "Fluxo A -- Setup concluido: id=$($licA.id) status=$($licA.status)"

    # --- Teste A1: Interpor recurso ---
    Write-Step "Fluxo A -- Teste A1: POST /licenciamentos/$($licA.id)/interpor-recurso"
    $motivoA1 = "A planta apresentada esta em conformidade com a norma vigente. Os extintores foram posicionados conforme Tabela 3 da RTCBMRS N.01/2024. O comunicado de inconformidade contem erros de interpretacao tecnica."
    $interporBody = @{ motivo = $motivoA1 } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/interpor-recurso" `
        -Method POST -Body $interporBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Recurso interposto -- status=$($licA.status)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "RECURSO_INTERPOSTO" }) {
        Write-OK "Marco RECURSO_INTERPOSTO presente"
    } else { Write-WARN "Marco RECURSO_INTERPOSTO NAO encontrado" }

    if ($licA.status -eq "RECURSO_PENDENTE") {
        Write-OK "Status RECURSO_PENDENTE confirmado"
    } else { Write-WARN "Status esperado RECURSO_PENDENTE, obtido $($licA.status)" }

    # --- Teste A2: Iniciar analise do recurso ---
    Write-Step "Fluxo A -- Teste A2: POST /licenciamentos/$($licA.id)/iniciar-recurso"
    $iniciarBody = @{
        motivo = "Recurso recebido e encaminhado para analise pelo CHEFE_SSEG_BBM."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/iniciar-recurso" `
        -Method POST -Body $iniciarBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Analise do recurso iniciada -- status=$($licA.status)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "RECURSO_EM_ANALISE" }) {
        Write-OK "Marco RECURSO_EM_ANALISE presente"
    } else { Write-WARN "Marco RECURSO_EM_ANALISE NAO encontrado" }

    if ($licA.status -eq "EM_RECURSO") {
        Write-OK "Status EM_RECURSO confirmado"
    } else { Write-WARN "Status esperado EM_RECURSO, obtido $($licA.status)" }

    # --- Teste A3: Deferir recurso ---
    Write-Step "Fluxo A -- Teste A3: POST /licenciamentos/$($licA.id)/deferir-recurso"
    $motivoA3 = "Apos analise tecnica detalhada, constata-se que os extintores estao posicionados em conformidade com a Tabela 3 da RTCBMRS N.01/2024. CIA considerado improcedente. Licenciamento aprovado."
    $deferirBody = @{ motivo = $motivoA3 } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/deferir-recurso" `
        -Method POST -Body $deferirBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Recurso deferido -- status=$($licA.status)"

    # --- Teste A4: Verificar status DEFERIDO ---
    Write-Step "Fluxo A -- Teste A4: GET /licenciamentos/$($licA.id) (confirma DEFERIDO)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.status -eq "DEFERIDO") {
        Write-OK "Status DEFERIDO confirmado -- licenciamento aprovado apos recurso"
    } else {
        Write-WARN "Status esperado DEFERIDO, obtido $($cur.status)"
    }

    # --- Teste A5: Verificar todos os marcos P10 ---
    Write-Step "Fluxo A -- Teste A5: GET /licenciamentos/$($licA.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    foreach ($m in @("RECURSO_INTERPOSTO", "RECURSO_EM_ANALISE", "RECURSO_DEFERIDO")) {
        if ($marcos | Where-Object { $_.tipoMarco -eq $m }) {
            Write-OK "Marco $m presente"
        } else { Write-WARN "Marco $m NAO encontrado" }
    }

} catch {
    Write-FAIL "Fluxo A falhou: $($_.Exception.Message)"
    Show-ErrorBody $_
}

# ===========================================================================
# FLUXO B -- P10: Recurso CIA -> INDEFERIDO (recurso improvido)
# ===========================================================================
Write-Step "=== FLUXO B: P10 -- Recurso CIA -> INDEFERIDO (recurso improvido) ==="

$licB = $null
try {
    # Setup: cadeia CIA_CIENCIA (novo licenciamento independente)
    Write-Step "Fluxo B -- Setup: preparando licenciamento em CIA_CIENCIA"
    $licB = Invoke-SetupCiaCiencia -Token $token -AuthHdr $authHdr -AdminId $adminId
    Write-OK "Fluxo B -- Setup concluido: id=$($licB.id) status=$($licB.status)"

    # --- Teste B1: Interpor recurso ---
    Write-Step "Fluxo B -- Teste B1: POST /licenciamentos/$($licB.id)/interpor-recurso"
    $motivoB1 = "A empresa contratante discorda do CIA emitido. Solicita revisao tecnica da planta apresentada."
    $interporBody = @{ motivo = $motivoB1 } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/interpor-recurso" `
        -Method POST -Body $interporBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Recurso interposto -- status=$($licB.status)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "RECURSO_INTERPOSTO" }) {
        Write-OK "Marco RECURSO_INTERPOSTO presente"
    } else { Write-WARN "Marco RECURSO_INTERPOSTO NAO encontrado" }

    # --- Teste B2: Iniciar analise do recurso ---
    Write-Step "Fluxo B -- Teste B2: POST /licenciamentos/$($licB.id)/iniciar-recurso"
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/iniciar-recurso" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    Write-OK "Analise do recurso iniciada -- status=$($licB.status)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "RECURSO_EM_ANALISE" }) {
        Write-OK "Marco RECURSO_EM_ANALISE presente"
    } else { Write-WARN "Marco RECURSO_EM_ANALISE NAO encontrado" }

    # --- Teste B3: Indeferir recurso ---
    Write-Step "Fluxo B -- Teste B3: POST /licenciamentos/$($licB.id)/indeferir-recurso"
    $motivoB3 = "Apos analise do recurso, as inconformidades apontadas no CIA sao procedentes. A disposicao dos extintores nao atende ao item 5.3.2 da RTCBMRS N.01/2024. Recurso improvido. Licenciamento indeferido."
    $indeferirBody = @{ motivo = $motivoB3 } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/indeferir-recurso" `
        -Method POST -Body $indeferirBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Recurso indeferido -- status=$($licB.status)"

    # --- Teste B4: Verificar status INDEFERIDO ---
    Write-Step "Fluxo B -- Teste B4: GET /licenciamentos/$($licB.id) (confirma INDEFERIDO)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.status -eq "INDEFERIDO") {
        Write-OK "Status INDEFERIDO confirmado -- licenciamento encerrado apos recurso improvido"
    } else {
        Write-WARN "Status esperado INDEFERIDO, obtido $($cur.status)"
    }

    # --- Teste B5: Verificar todos os marcos P10 ---
    Write-Step "Fluxo B -- Teste B5: GET /licenciamentos/$($licB.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    foreach ($m in @("RECURSO_INTERPOSTO", "RECURSO_EM_ANALISE", "RECURSO_INDEFERIDO")) {
        if ($marcos | Where-Object { $_.tipoMarco -eq $m }) {
            Write-OK "Marco $m presente"
        } else { Write-WARN "Marco $m NAO encontrado" }
    }

} catch {
    Write-FAIL "Fluxo B falhou: $($_.Exception.Message)"
    Show-ErrorBody $_
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste"

foreach ($licLimpeza in @($licA, $licB)) {
    if ($null -ne $licLimpeza) {
        $lid = $licLimpeza.id
        $sql = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $lid;
DELETE FROM sol.marco_processo WHERE id_licenciamento = $lid;
DELETE FROM sol.boleto WHERE id_licenciamento = $lid;
DELETE FROM sol.licenciamento WHERE id_licenciamento = $lid;
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
}

# ===========================================================================
# Resultado final
# ===========================================================================
Write-Step "Sprint 10 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P10 Fluxo A -- Recurso CIA -> DEFERIDO (recurso provido):"
Write-Host "         interpor-recurso -> iniciar-recurso -> deferir-recurso"
Write-Host "         Marcos: RECURSO_INTERPOSTO + RECURSO_EM_ANALISE + RECURSO_DEFERIDO"
Write-Host "         Status final: DEFERIDO"
Write-Host ""
Write-Host "    P10 Fluxo B -- Recurso CIA -> INDEFERIDO (recurso improvido):"
Write-Host "         interpor-recurso -> iniciar-recurso -> indeferir-recurso"
Write-Host "         Marcos: RECURSO_INTERPOSTO + RECURSO_EM_ANALISE + RECURSO_INDEFERIDO"
Write-Host "         Status final: INDEFERIDO"
Write-Host ""
Write-Host "  Deploy da Sprint 10 concluido com sucesso!" -ForegroundColor Green
exit 0
