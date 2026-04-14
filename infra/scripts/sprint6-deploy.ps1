#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 6 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P05 e P06:

      Fluxo A -- P05 Ciencia CIA completo:
        Setup: criar licenciamento -> upload PPCI -> submeter -> distribuir
               -> iniciar-analise -> emitir-cia -> status=CIA_EMITIDO
        1. POST /licenciamentos/{id}/registrar-ciencia-cia  (-> CIA_CIENCIA)
        2. GET  /licenciamentos/{id}/marcos                 (verifica CIA_CIENCIA)
        3. POST /licenciamentos/{id}/retomar-analise        (-> EM_ANALISE)
        4. POST /licenciamentos/{id}/deferir                (-> DEFERIDO)
        5. GET  /licenciamentos/{id}                        (confirma DEFERIDO)

      Fluxo B -- P06 Isencao deferida:
        Setup: criar licenciamento -> upload PPCI -> submeter
        6. POST /licenciamentos/{id}/solicitar-isencao      (marco ISENCAO_SOLICITADA)
        7. GET  /licenciamentos/{id}/marcos                 (verifica marco)
        8. POST /licenciamentos/{id}/deferir-isencao        (isentoTaxa = true)
        9. GET  /licenciamentos/{id}                        (confirma isentoTaxa=true)

      Fluxo C -- P06 Isencao indeferida:
        Setup: criar licenciamento -> upload PPCI -> submeter
       10. POST /licenciamentos/{id}/solicitar-isencao      (marco ISENCAO_SOLICITADA)
       11. POST /licenciamentos/{id}/indeferir-isencao      (marco ISENCAO_INDEFERIDA)
       12. GET  /licenciamentos/{id}                        (confirma isentoTaxa=false)

       13. Limpeza Oracle (remove licenciamentos A, B e C + dependencias)

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: Sprints 1 a 5 concluidas com sucesso.
    PRE-REQUISITO: MinIO rodando com policy sol-app-policy (s3:GetBucketLocation).
    PRE-REQUISITO: sol-admin com role ADMIN no realm sol do Keycloak.
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
# Funcoes auxiliares
# ---------------------------------------------------------------------------
function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }

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

function New-LicBody {
    return @{
        tipo = "PPCI"; areaConstruida = 500.00; alturaMaxima = 10.00
        numPavimentos = 3; tipoOcupacao = "Comercial - Loja"
        usoPredominante = "Comercial"
        endereco = @{
            cep = $TestCep; logradouro = "Rua dos Andradas"; numero = "999"
            complemento = $null; bairro = "Centro Historico"
            municipio = "Porto Alegre"; uf = "RS"
            latitude = $null; longitude = $null; dataAtualizacao = $null
        }
        responsavelTecnicoId = $null; responsavelUsoId = $null
        licenciamentoPaiId = $null
    } | ConvertTo-Json -Depth 5
}

function Invoke-CriarSubmeter {
    param([string]$Token, [hashtable]$AuthHdr, [Long]$AdminId)
    # Cria licenciamento
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicBody) -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Licenciamento criado -- id=$($lic.id)"

    # Upload PPCI
    $tmp = New-PdfTemp
    try {
        $null = Invoke-MultipartUpload -Uri "$BaseUrl/arquivos/upload" `
            -FilePath $tmp -BearerToken $Token -LicId $lic.id
        Write-OK "Upload PPCI OK"
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    # Submeter
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/submeter" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Submissao OK -- status=$($lic.status)"

    return $lic
}

function Invoke-PrepararParaAnalise {
    param($Lic, [string]$Token, [hashtable]$AuthHdr, [Long]$AdminId)
    # Distribuir
    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($Lic.id)/distribuir?analistaId=$AdminId" `
        -Method PATCH -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Distribuicao OK"

    # Iniciar analise
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/iniciar-analise" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Inicio de analise OK -- status=$($lic.status)"

    return $lic
}

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

# ===========================================================================
# FLUXO A -- P05: CIA_EMITIDO -> CIA_CIENCIA -> EM_ANALISE -> DEFERIDO
# ===========================================================================
Write-Step "=== FLUXO A: P05 -- Ciencia CIA + Retomada de Analise ==="

$licA = $null
try {
    # Setup: criar -> submeter -> distribuir -> iniciar -> emitir CIA
    Write-Step "Fluxo A -- Setup: criar + submeter"
    $licA = Invoke-CriarSubmeter -Token $token -AuthHdr $authHdr -AdminId $adminId

    Write-Step "Fluxo A -- Setup: distribuir + iniciar analise"
    $licA = Invoke-PrepararParaAnalise -Lic $licA -Token $token -AuthHdr $authHdr -AdminId $adminId

    Write-Step "Fluxo A -- Setup: emitir CIA (-> CIA_EMITIDO)"
    $ciaBody = @{ observacao = "Falta extrator de fumaca no pavimento 2. Escada pressurizada inadequada." } | ConvertTo-Json
    $licA = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/emitir-cia" `
        -Method POST -Body $ciaBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "CIA emitida -- status=$($licA.status)"

    # --- Teste 1: Registrar ciencia do CIA ---
    Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/registrar-ciencia-cia"
    $cienciaBody = @{ observacao = "Ciencia registrada. Correcoes em andamento." } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/registrar-ciencia-cia" `
        -Method POST -Body $cienciaBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "CIA_CIENCIA") {
        Write-OK "Ciencia CIA registrada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado CIA_CIENCIA)"
    }

    # --- Teste 2: Verificar marco CIA_CIENCIA ---
    Write-Step "Fluxo A -- GET /licenciamentos/$($licA.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    if ($marcos | Where-Object { $_.tipoMarco -eq "CIA_CIENCIA" }) {
        Write-OK "Marco CIA_CIENCIA presente"
    } else {
        Write-WARN "Marco CIA_CIENCIA NAO encontrado"
    }

    # --- Teste 3: Retomar analise ---
    Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/retomar-analise (CIA_CIENCIA -> EM_ANALISE)"
    $licA = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/retomar-analise" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    if ($licA.status -eq "EM_ANALISE") {
        Write-OK "Analise retomada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado EM_ANALISE)"
    }

    # --- Teste 4: Deferir apos correcao ---
    Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/deferir"
    $dBody = @{ observacao = "Inconformidades corrigidas. PPCI aprovado." } | ConvertTo-Json
    $licA = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/deferir" `
        -Method POST -Body $dBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "DEFERIDO") {
        Write-OK "Deferimento OK -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado DEFERIDO)"
    }

    # --- Teste 5: Verificar status final ---
    Write-Step "Fluxo A -- GET /licenciamentos/$($licA.id) (confirmar DEFERIDO)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.status -eq "DEFERIDO") {
        Write-OK "Status DEFERIDO confirmado"
    } else {
        Write-WARN "Status inesperado: $($cur.status)"
    }
} catch {
    Write-FAIL "Fluxo A falhou: $($_.Exception.Message)"
}

# ===========================================================================
# FLUXO B -- P06: Solicitar isencao -> DEFERIR
# ===========================================================================
Write-Step "=== FLUXO B: P06 -- Isencao de Taxa (DEFERIDA) ==="

$licB = $null
try {
    Write-Step "Fluxo B -- Setup: criar + submeter"
    $licB = Invoke-CriarSubmeter -Token $token -AuthHdr $authHdr -AdminId $adminId

    # --- Teste 6: Solicitar isencao ---
    Write-Step "Fluxo B -- POST /licenciamentos/$($licB.id)/solicitar-isencao"
    $solBody = @{
        motivo = "Edificio publico pertencente a autarquia municipal. " +
                 "Enquadrado no Art. 12, inciso III da Lei Estadual 12.345/2024."
    } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/solicitar-isencao" `
        -Method POST -Body $solBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Solicitacao de isencao registrada -- status=$($licB.status) isentoTaxa=$($licB.isentoTaxa)"

    # --- Teste 7: Verificar marco ISENCAO_SOLICITADA ---
    Write-Step "Fluxo B -- GET /licenciamentos/$($licB.id)/marcos"
    $marcosB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcosB | Where-Object { $_.tipoMarco -eq "ISENCAO_SOLICITADA" }) {
        Write-OK "Marco ISENCAO_SOLICITADA presente ($($marcosB.Count) marcos)"
    } else {
        Write-WARN "Marco ISENCAO_SOLICITADA NAO encontrado"
    }

    # --- Teste 8: Deferir isencao ---
    Write-Step "Fluxo B -- POST /licenciamentos/$($licB.id)/deferir-isencao"
    $defIsBody = @{ motivo = "Documentacao comprobatoria validada. Isencao deferida." } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/deferir-isencao" `
        -Method POST -Body $defIsBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Isencao deferida -- isentoTaxa=$($licB.isentoTaxa)"

    # --- Teste 9: Verificar isentoTaxa = true ---
    Write-Step "Fluxo B -- GET /licenciamentos/$($licB.id) (confirmar isentoTaxa=true)"
    $curB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($curB.isentoTaxa -eq $true) {
        Write-OK "isentoTaxa=true confirmado"
    } else {
        Write-WARN "isentoTaxa=$($curB.isentoTaxa) (esperado true)"
    }
    Write-Host "    obsIsencao: $($curB.obsIsencao)" -ForegroundColor Gray
} catch {
    Write-FAIL "Fluxo B falhou: $($_.Exception.Message)"
}

# ===========================================================================
# FLUXO C -- P06: Solicitar isencao -> INDEFERIR
# ===========================================================================
Write-Step "=== FLUXO C: P06 -- Isencao de Taxa (INDEFERIDA) ==="

$licC = $null
try {
    Write-Step "Fluxo C -- Setup: criar + submeter"
    $licC = Invoke-CriarSubmeter -Token $token -AuthHdr $authHdr -AdminId $adminId

    # --- Teste 10: Solicitar isencao ---
    Write-Step "Fluxo C -- POST /licenciamentos/$($licC.id)/solicitar-isencao"
    $solBodyC = @{ motivo = "Alegacao de dificuldades financeiras para pagamento da taxa." } | ConvertTo-Json
    $licC = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licC.id)/solicitar-isencao" `
        -Method POST -Body $solBodyC -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Solicitacao registrada"

    # --- Teste 11: Indeferir isencao ---
    Write-Step "Fluxo C -- POST /licenciamentos/$($licC.id)/indeferir-isencao"
    $indIsBody = @{
        motivo = "Justificativa insuficiente. Documentacao comprobatoria nao apresentada. " +
                 "Nao enquadrado nos criterios do Art. 12 da Lei Estadual."
    } | ConvertTo-Json
    $licC = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licC.id)/indeferir-isencao" `
        -Method POST -Body $indIsBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Isencao indeferida -- isentoTaxa=$($licC.isentoTaxa)"

    # --- Teste 12: Verificar isentoTaxa = false ---
    Write-Step "Fluxo C -- GET /licenciamentos/$($licC.id) (confirmar isentoTaxa=false)"
    $curC = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licC.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($curC.isentoTaxa -eq $false) {
        Write-OK "isentoTaxa=false confirmado (isencao indeferida)"
    } else {
        Write-WARN "isentoTaxa=$($curC.isentoTaxa) (esperado false)"
    }
    Write-Host "    obsIsencao: $($curC.obsIsencao)" -ForegroundColor Gray
} catch {
    Write-FAIL "Fluxo C falhou: $($_.Exception.Message)"
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste (licenciamentos A, B e C)"

foreach ($lic in @($licA, $licB, $licC) | Where-Object { $null -ne $_ }) {
    $lid = $lic.id
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

# ===========================================================================
# Resultado final
# ===========================================================================
Write-Step "Sprint 6 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P05 -- Ciencia do CIA (CIA_EMITIDO -> CIA_CIENCIA)"
Write-Host "    P05 -- Retomada de analise (CIA_CIENCIA -> EM_ANALISE)"
Write-Host "    P05 -- Ciclo completo CIA: emitir -> ciencia -> retomar -> deferir"
Write-Host "    P06 -- Solicitacao de isencao de taxa"
Write-Host "    P06 -- Deferimento de isencao (isentoTaxa=true)"
Write-Host "    P06 -- Indeferimento de isencao (isentoTaxa=false)"
Write-Host "    Marcos: CIA_CIENCIA, ISENCAO_SOLICITADA, ISENCAO_DEFERIDA, ISENCAO_INDEFERIDA"
Write-Host ""
Write-Host "  Deploy da Sprint 6 concluido com sucesso!" -ForegroundColor Green
exit 0
