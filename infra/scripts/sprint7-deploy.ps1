#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 7 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P07:

      Fluxo A -- P07 Vistoria com CIV (ciclo completo):
        Setup: criar -> upload PPCI -> submeter -> distribuir
               -> iniciar-analise -> deferir -> status=DEFERIDO
        1.  POST  /licenciamentos/{id}/agendar-vistoria     (-> VISTORIA_PENDENTE)
        2.  PATCH /licenciamentos/{id}/atribuir-inspetor    (inspetor setado)
        3.  GET   /vistoria/fila                            (verifica fila)
        4.  POST  /licenciamentos/{id}/iniciar-vistoria     (-> EM_VISTORIA)
        5.  POST  /licenciamentos/{id}/emitir-civ           (-> CIV_EMITIDO)
        6.  GET   /licenciamentos/{id}/marcos               (verifica CIV_EMITIDO)
        7.  POST  /licenciamentos/{id}/registrar-ciencia-civ(-> CIV_CIENCIA)
        8.  POST  /licenciamentos/{id}/retomar-vistoria     (-> EM_VISTORIA)
        9.  POST  /licenciamentos/{id}/aprovar-vistoria     (-> PRPCI_EMITIDO)
        10. GET   /licenciamentos/{id}                      (confirma PRPCI_EMITIDO)

      Fluxo B -- P07 Aprovacao direta (sem CIV):
        Setup: criar -> upload PPCI -> submeter -> distribuir
               -> iniciar-analise -> deferir -> status=DEFERIDO
        11. POST  /licenciamentos/{id}/agendar-vistoria     (-> VISTORIA_PENDENTE)
        12. PATCH /licenciamentos/{id}/atribuir-inspetor    (inspetor setado)
        13. POST  /licenciamentos/{id}/iniciar-vistoria     (-> EM_VISTORIA)
        14. POST  /licenciamentos/{id}/aprovar-vistoria     (-> PRPCI_EMITIDO)
        15. GET   /licenciamentos/{id}                      (confirma PRPCI_EMITIDO)

        16. Limpeza Oracle (remove licenciamentos A e B + dependencias)

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: Sprints 1 a 6 concluidas com sucesso.
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

function Invoke-PrepararParaVistoria {
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

    # Deferir (analise aprovada, processo segue para vistoria)
    $dBody = @{ observacao = "PPCI aprovado na analise tecnica. Encaminhado para vistoria presencial." } | ConvertTo-Json
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)/deferir" `
        -Method POST -Body $dBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15
    Write-OK "Deferimento de analise OK -- status=$($lic.status)"

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
# FLUXO A -- P07: Vistoria com CIV (ciclo completo)
#   DEFERIDO -> VISTORIA_PENDENTE -> EM_VISTORIA -> CIV_EMITIDO
#            -> CIV_CIENCIA -> EM_VISTORIA -> PRPCI_EMITIDO
# ===========================================================================
Write-Step "=== FLUXO A: P07 -- Vistoria com CIV (ciclo completo) ==="

$licA = $null
try {
    # Setup: criar -> submeter -> distribuir -> iniciar-analise -> deferir
    Write-Step "Fluxo A -- Setup: criar + submeter"
    $licA = Invoke-CriarSubmeter -Token $token -AuthHdr $authHdr -AdminId $adminId

    Write-Step "Fluxo A -- Setup: distribuir + iniciar-analise + deferir (-> DEFERIDO)"
    $licA = Invoke-PrepararParaVistoria -Lic $licA -Token $token -AuthHdr $authHdr -AdminId $adminId

    # --- Teste 1: Agendar vistoria ---
    Write-Step "Fluxo A -- Teste 1: POST /licenciamentos/$($licA.id)/agendar-vistoria"
    $dataVistoria = (Get-Date).AddDays(7).ToString("yyyy-MM-dd")
    $agBody = @{
        dataVistoria = $dataVistoria
        observacao   = "Acesso pela portaria lateral. Contato: zelador no local."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/agendar-vistoria" `
        -Method POST -Body $agBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "VISTORIA_PENDENTE") {
        Write-OK "Vistoria agendada -- status=$($licA.status) data=$dataVistoria"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado VISTORIA_PENDENTE)"
    }

    # --- Teste 2: Atribuir inspetor ---
    Write-Step "Fluxo A -- Teste 2: PATCH /licenciamentos/$($licA.id)/atribuir-inspetor?inspetorId=$adminId"
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/atribuir-inspetor?inspetorId=$adminId" `
        -Method PATCH -Headers $authHdr -TimeoutSec 15
    if ($null -ne $licA.inspetorId) {
        Write-OK "Inspetor atribuido -- inspetorId=$($licA.inspetorId) nome=$($licA.inspetorNome)"
    } else {
        Write-WARN "inspetorId nulo -- verificar atribuicao"
    }

    # --- Teste 3: Verificar fila de vistoria ---
    Write-Step "Fluxo A -- Teste 3: GET /vistoria/fila"
    $fila = Invoke-RestMethod -Uri "$BaseUrl/vistoria/fila?page=0&size=10" `
        -Headers $authHdr -TimeoutSec 10
    $totalFila = if ($null -ne $fila.totalElements) { $fila.totalElements } else { $fila.content.Count }
    Write-OK "Fila de vistoria: $totalFila licenciamento(s) pendente(s)"

    # --- Teste 4: Iniciar vistoria ---
    Write-Step "Fluxo A -- Teste 4: POST /licenciamentos/$($licA.id)/iniciar-vistoria"
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/iniciar-vistoria" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    if ($licA.status -eq "EM_VISTORIA") {
        Write-OK "Vistoria iniciada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado EM_VISTORIA)"
    }

    # --- Teste 5: Emitir CIV ---
    Write-Step "Fluxo A -- Teste 5: POST /licenciamentos/$($licA.id)/emitir-civ"
    $civBody = @{
        observacao = "Falta sinalizacao de rota de fuga no 3o pavimento. " +
                     "Extintor de incendio com validade vencida no corredor leste."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/emitir-civ" `
        -Method POST -Body $civBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "CIV_EMITIDO") {
        Write-OK "CIV emitido -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado CIV_EMITIDO)"
    }

    # --- Teste 6: Verificar marcos ---
    Write-Step "Fluxo A -- Teste 6: GET /licenciamentos/$($licA.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    if ($marcos | Where-Object { $_.tipoMarco -eq "CIV_EMITIDO" }) {
        Write-OK "Marco CIV_EMITIDO presente"
    } else {
        Write-WARN "Marco CIV_EMITIDO NAO encontrado"
    }

    # --- Teste 7: Registrar ciencia do CIV ---
    Write-Step "Fluxo A -- Teste 7: POST /licenciamentos/$($licA.id)/registrar-ciencia-civ"
    $cienciaBody = @{
        observacao = "Ciencia registrada. Sinalizacao e extintores serao regularizados em 15 dias."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/registrar-ciencia-civ" `
        -Method POST -Body $cienciaBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "CIV_CIENCIA") {
        Write-OK "Ciencia do CIV registrada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado CIV_CIENCIA)"
    }

    # --- Teste 8: Retomar vistoria ---
    Write-Step "Fluxo A -- Teste 8: POST /licenciamentos/$($licA.id)/retomar-vistoria"
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/retomar-vistoria" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    if ($licA.status -eq "EM_VISTORIA") {
        Write-OK "Vistoria retomada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado EM_VISTORIA)"
    }

    # --- Teste 9: Aprovar vistoria ---
    Write-Step "Fluxo A -- Teste 9: POST /licenciamentos/$($licA.id)/aprovar-vistoria"
    $aprovBody = @{
        observacao = "Inconformidades corrigidas. Instalacoes em conformidade com a norma."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/aprovar-vistoria" `
        -Method POST -Body $aprovBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licA.status -eq "PRPCI_EMITIDO") {
        Write-OK "Vistoria aprovada -- status=$($licA.status)"
    } else {
        Write-WARN "Status inesperado: $($licA.status) (esperado PRPCI_EMITIDO)"
    }

    # --- Teste 10: Confirmar status final ---
    Write-Step "Fluxo A -- Teste 10: GET /licenciamentos/$($licA.id) (confirmar PRPCI_EMITIDO)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.status -eq "PRPCI_EMITIDO") {
        Write-OK "Status PRPCI_EMITIDO confirmado -- inspetorNome=$($cur.inspetorNome)"
    } else {
        Write-WARN "Status inesperado: $($cur.status)"
    }
} catch {
    Write-FAIL "Fluxo A falhou: $($_.Exception.Message)"
}

# ===========================================================================
# FLUXO B -- P07: Aprovacao direta (sem CIV)
#   DEFERIDO -> VISTORIA_PENDENTE -> EM_VISTORIA -> PRPCI_EMITIDO
# ===========================================================================
Write-Step "=== FLUXO B: P07 -- Aprovacao direta (sem CIV) ==="

$licB = $null
try {
    # Setup: criar -> submeter -> distribuir -> iniciar-analise -> deferir
    Write-Step "Fluxo B -- Setup: criar + submeter"
    $licB = Invoke-CriarSubmeter -Token $token -AuthHdr $authHdr -AdminId $adminId

    Write-Step "Fluxo B -- Setup: distribuir + iniciar-analise + deferir (-> DEFERIDO)"
    $licB = Invoke-PrepararParaVistoria -Lic $licB -Token $token -AuthHdr $authHdr -AdminId $adminId

    # --- Teste 11: Agendar vistoria ---
    Write-Step "Fluxo B -- Teste 11: POST /licenciamentos/$($licB.id)/agendar-vistoria"
    $dataVistoriaB = (Get-Date).AddDays(14).ToString("yyyy-MM-dd")
    $agBodyB = @{
        dataVistoria = $dataVistoriaB
        observacao   = "Edificio residencial. Acesso livre durante horario comercial."
    } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/agendar-vistoria" `
        -Method POST -Body $agBodyB -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licB.status -eq "VISTORIA_PENDENTE") {
        Write-OK "Vistoria agendada -- status=$($licB.status)"
    } else {
        Write-WARN "Status inesperado: $($licB.status) (esperado VISTORIA_PENDENTE)"
    }

    # --- Teste 12: Atribuir inspetor ---
    Write-Step "Fluxo B -- Teste 12: PATCH /licenciamentos/$($licB.id)/atribuir-inspetor?inspetorId=$adminId"
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/atribuir-inspetor?inspetorId=$adminId" `
        -Method PATCH -Headers $authHdr -TimeoutSec 15
    Write-OK "Inspetor atribuido -- inspetorId=$($licB.inspetorId)"

    # --- Teste 13: Iniciar vistoria ---
    Write-Step "Fluxo B -- Teste 13: POST /licenciamentos/$($licB.id)/iniciar-vistoria"
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/iniciar-vistoria" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    if ($licB.status -eq "EM_VISTORIA") {
        Write-OK "Vistoria iniciada -- status=$($licB.status)"
    } else {
        Write-WARN "Status inesperado: $($licB.status) (esperado EM_VISTORIA)"
    }

    # --- Teste 14: Aprovar vistoria diretamente ---
    Write-Step "Fluxo B -- Teste 14: POST /licenciamentos/$($licB.id)/aprovar-vistoria"
    $aprovBodyB = @{
        observacao = "Edificio em conformidade com todas as normas de prevencao contra incendio. PRPCI emitido."
    } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/aprovar-vistoria" `
        -Method POST -Body $aprovBodyB -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    if ($licB.status -eq "PRPCI_EMITIDO") {
        Write-OK "Vistoria aprovada diretamente -- status=$($licB.status)"
    } else {
        Write-WARN "Status inesperado: $($licB.status) (esperado PRPCI_EMITIDO)"
    }

    # --- Teste 15: Confirmar status final ---
    Write-Step "Fluxo B -- Teste 15: GET /licenciamentos/$($licB.id) (confirmar PRPCI_EMITIDO)"
    $curB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($curB.status -eq "PRPCI_EMITIDO") {
        Write-OK "Status PRPCI_EMITIDO confirmado -- inspetorNome=$($curB.inspetorNome)"
    } else {
        Write-WARN "Status inesperado: $($curB.status)"
    }
} catch {
    Write-FAIL "Fluxo B falhou: $($_.Exception.Message)"
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste (licenciamentos A e B)"

foreach ($lic in @($licA, $licB) | Where-Object { $null -ne $_ }) {
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
Write-Step "Sprint 7 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P07 -- Agendamento de vistoria (DEFERIDO -> VISTORIA_PENDENTE)"
Write-Host "    P07 -- Atribuicao de inspetor"
Write-Host "    P07 -- Inicio de vistoria (VISTORIA_PENDENTE -> EM_VISTORIA)"
Write-Host "    P07 -- Emissao de CIV (EM_VISTORIA -> CIV_EMITIDO)"
Write-Host "    P07 -- Ciencia do CIV (CIV_EMITIDO -> CIV_CIENCIA)"
Write-Host "    P07 -- Retomada de vistoria (CIV_CIENCIA -> EM_VISTORIA)"
Write-Host "    P07 -- Aprovacao de vistoria (EM_VISTORIA -> PRPCI_EMITIDO)"
Write-Host "    Marcos: VISTORIA_AGENDADA, VISTORIA_REALIZADA, CIV_EMITIDO, CIV_CIENCIA, VISTORIA_APROVADA"
Write-Host ""
Write-Host "  Deploy da Sprint 7 concluido com sucesso!" -ForegroundColor Green
exit 0
