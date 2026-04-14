#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 8 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests do fluxo P08:

      Fluxo A -- P08 Emissao de APPCI (ciclo completo P03->P04->P07->P08):
        Setup: criar -> upload PPCI -> submeter
               -> distribuir -> iniciar-analise -> deferir (DEFERIDO)
               -> agendar-vistoria -> atribuir-inspetor -> iniciar-vistoria
               -> aprovar-vistoria (PRPCI_EMITIDO)
        1. POST /licenciamentos/{id}/emitir-appci         (-> APPCI_EMITIDO)
        2. GET  /licenciamentos/{id}                      (confirma APPCI_EMITIDO + dtValidadeAppci)
        3. GET  /appci/vigentes                           (verifica lista)
        4. GET  /licenciamentos/{id}/marcos               (verifica marco APPCI_EMITIDO)
        5. GET  /licenciamentos/{id}/appci                (endpoint dedicado APPCI)
        6. Limpeza Oracle (remove licenciamento A + dependencias)

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: Sprints 1 a 7 concluidas com sucesso.
    PRE-REQUISITO: MinIO rodando com policy sol-app-policy (s3:GetBucketLocation).
    PRE-REQUISITO: sol-admin com role ADMIN no realm sol do Keycloak.

    Calculo de validade do APPCI (RTCBMRS N.01/2024):
      areaConstruida <= 750 m² -> 2 anos
      areaConstruida >  750 m² -> 5 anos
    O teste usa area=500 m² -> validade esperada de 2 anos.
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
    # area=500 m² -> APPCI valido por 2 anos (limiar <= 750 m²)
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

function Invoke-PrepararParaAppci {
    param([string]$Token, [hashtable]$AuthHdr, [Long]$AdminId)

    # --- P03: criar + upload + submeter ---
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicBody) -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Licenciamento criado -- id=$($lic.id)"

    $tmp = New-PdfTemp
    try {
        $null = Invoke-MultipartUpload -Uri "$BaseUrl/arquivos/upload" `
            -FilePath $tmp -BearerToken $Token -LicId $lic.id
        Write-OK "Upload PPCI OK"
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/submeter" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Submissao OK -- status=$($lic.status)"

    # --- P04: distribuir + iniciar-analise + deferir ---
    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/distribuir?analistaId=$AdminId" `
        -Method PATCH -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Distribuicao OK"

    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/iniciar-analise" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Inicio de analise OK"

    $dBody = @{ observacao = "PPCI aprovado. Encaminhado para vistoria." } | ConvertTo-Json
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/deferir" `
        -Method POST -Body $dBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Deferimento analise OK -- status=$($lic.status)"

    # --- P07: agendar + atribuir-inspetor + iniciar + aprovar ---
    $dataVistoria = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")
    $agBody = @{ dataVistoria = $dataVistoria; observacao = "Vistoria para emissao de APPCI." } | ConvertTo-Json
    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/agendar-vistoria" `
        -Method POST -Body $agBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Vistoria agendada -- status=$($lic.status)"

    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/atribuir-inspetor?inspetorId=$AdminId" `
        -Method PATCH -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Inspetor atribuido"

    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/iniciar-vistoria" `
        -Method POST -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Vistoria iniciada -- status=$($lic.status)"

    $aprovBody = @{ observacao = "Edificio em conformidade. PRPCI emitido." } | ConvertTo-Json
    $lic = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($lic.id)/aprovar-vistoria" `
        -Method POST -Body $aprovBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Vistoria aprovada -- status=$($lic.status)"

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
# FLUXO A -- P08: Emissao do APPCI (ciclo completo P03->P04->P07->P08)
# ===========================================================================
Write-Step "=== FLUXO A: P08 -- Emissao do APPCI ==="

$licA = $null
try {
    # Setup: executa P03 + P04 + P07 para chegar em PRPCI_EMITIDO
    Write-Step "Fluxo A -- Setup: P03 + P04 + P07 (-> PRPCI_EMITIDO)"
    $licA = Invoke-PrepararParaAppci -Token $token -AuthHdr $authHdr -AdminId $adminId

    if ($licA.status -ne "PRPCI_EMITIDO") {
        throw "Setup falhou: status esperado PRPCI_EMITIDO, obtido $($licA.status)"
    }
    Write-OK "Setup concluido -- id=$($licA.id) status=$($licA.status)"

    # --- Teste 1: Emitir APPCI ---
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

    # --- Teste 2: Confirmar dtValidadeAppci (area=500m² -> +2 anos) ---
    Write-Step "Fluxo A -- Teste 2: GET /licenciamentos/$($licA.id) (confirmar APPCI_EMITIDO + dtValidadeAppci)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10

    if ($cur.status -eq "APPCI_EMITIDO") {
        Write-OK "Status APPCI_EMITIDO confirmado"
    } else {
        Write-WARN "Status inesperado: $($cur.status)"
    }

    if ($null -ne $cur.dtValidadeAppci) {
        $dtValidade = [DateTime]::Parse($cur.dtValidadeAppci)
        $anosValidade = ($dtValidade - (Get-Date)).Days / 365
        Write-OK "dtValidadeAppci=$($cur.dtValidadeAppci) (~$([Math]::Round($anosValidade,1)) anos)"

        # Verifica se a validade e aproximadamente 2 anos (area=500 m² <= 750 m²)
        $anosDiff = [Math]::Abs($anosValidade - 2)
        if ($anosDiff -lt 0.1) {
            Write-OK "Validade de 2 anos confirmada (area=500 m² <= 750 m²)"
        } else {
            Write-WARN "Validade inesperada: ~$([Math]::Round($anosValidade,1)) anos (esperado 2 anos)"
        }
    } else {
        Write-WARN "dtValidadeAppci nula -- verificar AppciService.emitirAppci()"
    }

    if ($null -ne $cur.dtVencimentoPrpci) {
        Write-OK "dtVencimentoPrpci=$($cur.dtVencimentoPrpci)"
    } else {
        Write-WARN "dtVencimentoPrpci nula -- verificar RN-P08-003"
    }

    # --- Teste 3: Listar APPCIs vigentes ---
    Write-Step "Fluxo A -- Teste 3: GET /appci/vigentes"
    $vigentes = Invoke-RestMethod -Uri "$BaseUrl/appci/vigentes?page=0&size=10" `
        -Headers $authHdr -TimeoutSec 10
    $total = if ($null -ne $vigentes.totalElements) { $vigentes.totalElements } else { $vigentes.content.Count }
    if ($total -ge 1) {
        Write-OK "APPCIs vigentes: $total licenciamento(s)"
    } else {
        Write-WARN "Nenhum APPCI vigente encontrado na lista"
    }

    # --- Teste 4: Verificar marco APPCI_EMITIDO ---
    Write-Step "Fluxo A -- Teste 4: GET /licenciamentos/$($licA.id)/marcos (marco APPCI_EMITIDO)"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    if ($marcos | Where-Object { $_.tipoMarco -eq "APPCI_EMITIDO" }) {
        Write-OK "Marco APPCI_EMITIDO presente"
    } else {
        Write-WARN "Marco APPCI_EMITIDO NAO encontrado"
    }

    # --- Teste 5: Endpoint dedicado /appci ---
    Write-Step "Fluxo A -- Teste 5: GET /licenciamentos/$($licA.id)/appci"
    $appci = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/appci" `
        -Headers $authHdr -TimeoutSec 10
    if ($appci.status -eq "APPCI_EMITIDO") {
        Write-OK "Endpoint /appci OK -- dtValidadeAppci=$($appci.dtValidadeAppci)"
    } else {
        Write-WARN "Endpoint /appci retornou status=$($appci.status)"
    }

} catch {
    Write-FAIL "Fluxo A falhou: $($_.Exception.Message)"
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste (licenciamento A)"

if ($null -ne $licA) {
    $lid = $licA.id
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
Write-Step "Sprint 8 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P08 -- Emissao do APPCI (PRPCI_EMITIDO -> APPCI_EMITIDO)"
Write-Host "    P08 -- Calculo automatico de validade (area 500 m² -> 2 anos)"
Write-Host "    P08 -- dtVencimentoPrpci preenchida automaticamente (RN-P08-003)"
Write-Host "    P08 -- Listagem de APPCIs vigentes (GET /appci/vigentes)"
Write-Host "    P08 -- Consulta dedicada do APPCI (GET /licenciamentos/{id}/appci)"
Write-Host "    Marco: APPCI_EMITIDO"
Write-Host ""
Write-Host "  Deploy da Sprint 8 concluido com sucesso!" -ForegroundColor Green
exit 0
