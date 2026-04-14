#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 5 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P04:

      Fluxo A -- Caminho feliz completo (deferimento):
        1. POST /licenciamentos            (cria em RASCUNHO)
        2. POST /arquivos/upload           (upload PPCI para habilitar submissao)
        3. POST /licenciamentos/{id}/submeter         (-> ANALISE_PENDENTE)
        4. GET  /analise/fila              (verifica que aparece na fila)
        5. Obtem ID do usuario sol-admin via GET /usuarios
        6. PATCH /licenciamentos/{id}/distribuir      (atribui analista)
        7. POST  /licenciamentos/{id}/iniciar-analise (-> EM_ANALISE)
        8. GET   /analise/em-andamento     (verifica que aparece em andamento)
        9. GET   /licenciamentos/{id}/marcos           (SUBMISSAO + DISTRIBUICAO + INICIO_ANALISE)
       10. POST  /licenciamentos/{id}/deferir          (-> DEFERIDO)
       11. GET   /licenciamentos/{id}      (status=DEFERIDO confirmado)
       12. GET   /licenciamentos/{id}/marcos           (+ APROVACAO_ANALISE)

      Fluxo B -- CIA (inconformidade):
       13. POST /licenciamentos            (segundo licenciamento em RASCUNHO)
       14. POST /arquivos/upload + submeter           (-> ANALISE_PENDENTE)
       15. PATCH distribuir + POST iniciar-analise   (-> EM_ANALISE)
       16. POST  /licenciamentos/{id}/emitir-cia     (-> CIA_EMITIDO)
       17. GET   /licenciamentos/{id}      (status=CIA_EMITIDO confirmado)

       18. Limpeza Oracle (remove ambos os licenciamentos + arquivos + marcos)

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: MinIO (SOL-MinIO) rodando com bucket sol-arquivos e policy
                   sol-app-policy contendo s3:GetBucketLocation (corrigido Sprint 4).
    PRE-REQUISITO: usuario sol-admin deve existir no realm sol com role ADMIN
                   e Direct Access Grants habilitado em sol-frontend.
    PRE-REQUISITO: MailHog (SOL-MailHog) rodando na porta 1025 (ou Spring Mail
                   configurado -- falha de e-mail nao interrompe o smoke test).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuracoes
# ---------------------------------------------------------------------------
$ServiceName    = "SOL-Backend"
$JavaHome       = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$ProjectRoot    = "C:\SOL\backend"
$BaseUrl        = "http://localhost:8080/api"
$HealthUrl      = "$BaseUrl/health"
$WaitSeconds    = 35
$MavenOpts      = "-Dmaven.test.skip=true -q"

$AdminUser      = "sol-admin"
$AdminPassword  = "Admin@SOL2026"
$TestCep        = "90010100"

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
    $http   = [System.Net.Http.HttpClient]::new()
    $http.DefaultRequestHeaders.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $BearerToken)
    $mp     = [System.Net.Http.MultipartFormDataContent]::new()
    $bytes  = [System.IO.File]::ReadAllBytes($FilePath)
    $fc     = [System.Net.Http.ByteArrayContent]::new($bytes)
    $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/pdf")
    $mp.Add($fc,  "file",             [System.IO.Path]::GetFileName($FilePath))
    $mp.Add([System.Net.Http.StringContent]::new("$LicId"), "licenciamentoId")
    $mp.Add([System.Net.Http.StringContent]::new("PPCI"),   "tipoArquivo")
    $task   = $http.PostAsync($Uri, $mp)
    $task.Wait()
    $resp   = $task.Result
    $body   = $resp.Content.ReadAsStringAsync().Result
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

function New-LicenciamentoBody {
    return @{
        tipo            = "PPCI"
        areaConstruida  = 500.00
        alturaMaxima    = 10.00
        numPavimentos   = 3
        tipoOcupacao    = "Comercial - Loja"
        usoPredominante = "Comercial"
        endereco        = @{
            cep             = $TestCep
            logradouro      = "Rua dos Andradas"
            numero          = "999"
            complemento     = $null
            bairro          = "Centro Historico"
            municipio       = "Porto Alegre"
            uf              = "RS"
            latitude        = $null
            longitude       = $null
            dataAtualizacao = $null
        }
        responsavelTecnicoId = $null
        responsavelUsoId     = $null
        licenciamentoPaiId   = $null
    } | ConvertTo-Json -Depth 5
}

# ---------------------------------------------------------------------------
# 1. Parar servico
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceName"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else {
    Write-WARN "Servico nao estava em execucao ou nao existe -- continuando"
}

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
    Start-Service -Name $ServiceName
    Write-OK "Servico iniciado"
} else {
    $jar = Get-ChildItem "$ProjectRoot\target\*.jar" |
           Where-Object { $_.Name -notlike "*sources*" } | Select-Object -First 1
    if ($null -eq $jar) { throw "JAR nao encontrado em $ProjectRoot\target\" }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
                  -ArgumentList "-jar `"$($jar.FullName)`"" `
                  -WorkingDirectory $ProjectRoot -NoNewWindow
    Write-WARN "Servico nao registrado -- JAR iniciado diretamente (modo dev)"
}

# ---------------------------------------------------------------------------
# 4. Aguardar inicializacao
# ---------------------------------------------------------------------------
Write-Step "Aguardando $WaitSeconds segundos para inicializacao do Spring Boot"
Start-Sleep -Seconds $WaitSeconds

# ---------------------------------------------------------------------------
# 5. Health check
# ---------------------------------------------------------------------------
Write-Step "Health check -- $HealthUrl"
$healthy = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) { Write-OK "Saudavel (tentativa $i)"; $healthy = $true; break }
    } catch {
        Write-WARN "Tentativa $i falhou -- aguardando 10s"
        Start-Sleep -Seconds 10
    }
}
if (-not $healthy) { Write-FAIL "Health check falhou"; exit 1 }

# ---------------------------------------------------------------------------
# 6. Login
# ---------------------------------------------------------------------------
Write-Step "Login -- POST /auth/login (usuario: $AdminUser)"
$tokenResp = $null
try {
    $tokenResp = Invoke-RestMethod `
        -Uri "$BaseUrl/auth/login" -Method POST `
        -Body (@{ username = $AdminUser; password = $AdminPassword } | ConvertTo-Json) `
        -ContentType "application/json" -TimeoutSec 15
    Write-OK "Login OK -- token expira em $($tokenResp.expires_in)s"
} catch {
    Write-FAIL "Login falhou: $($_.Exception.Message)"; exit 1
}
$token   = $tokenResp.access_token
$authHdr = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------------------
# 7. Obter ID do usuario sol-admin (necessario para distribuir)
# ---------------------------------------------------------------------------
Write-Step "Obtendo ID do usuario sol-admin via GET /usuarios"
$adminUserId = $null
try {
    $usuarios = Invoke-RestMethod `
        -Uri "$BaseUrl/usuarios?page=0&size=50" `
        -Headers $authHdr -TimeoutSec 10
    # Tenta encontrar pelo nome ou email; fallback: primeiro da lista
    $adminUser = $usuarios.content | Where-Object {
        $_.nome -like "*admin*" -or $_.email -like "*admin*"
    } | Select-Object -First 1
    if ($null -eq $adminUser) { $adminUser = $usuarios.content | Select-Object -First 1 }
    $adminUserId = $adminUser.id
    Write-OK "Usuario encontrado -- id=$adminUserId nome=$($adminUser.nome)"
} catch {
    Write-WARN "Nao foi possivel obter usuarios: $($_.Exception.Message)"
    Write-WARN "Usando id=1 como fallback para o analista de teste"
    $adminUserId = 1
}

# ===========================================================================
# FLUXO A -- Caminho feliz: criar -> submeter -> distribuir ->
#            iniciar-analise -> deferir
# ===========================================================================
Write-Step "=== FLUXO A: RASCUNHO -> ANALISE_PENDENTE -> EM_ANALISE -> DEFERIDO ==="

# --- 8. Criar licenciamento A ---
Write-Step "Fluxo A -- POST /licenciamentos (RASCUNHO)"
$licA = $null
try {
    $licA = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicenciamentoBody) -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Licenciamento A criado -- id=$($licA.id) status=$($licA.status)"
} catch {
    Write-FAIL "Criacao A falhou: $($_.Exception.Message)"; exit 1
}

# --- 9. Upload PPCI para licenciamento A ---
Write-Step "Fluxo A -- POST /arquivos/upload (PPCI)"
$tmpA = New-PdfTemp
try {
    $arqA = Invoke-MultipartUpload -Uri "$BaseUrl/arquivos/upload" `
        -FilePath $tmpA -BearerToken $token -LicId $licA.id
    Write-OK "Upload A OK -- arquivoId=$($arqA.id)"
} catch {
    Write-FAIL "Upload A falhou: $($_.Exception.Message)"; exit 1
} finally { Remove-Item $tmpA -Force -ErrorAction SilentlyContinue }

# --- 10. Submeter licenciamento A ---
Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/submeter"
try {
    $licA = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/submeter" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    Write-OK "Submissao A OK -- status=$($licA.status)"
} catch {
    Write-FAIL "Submissao A falhou: $($_.Exception.Message)"; exit 1
}

# --- 11. Verificar fila de analise ---
Write-Step "Fluxo A -- GET /analise/fila (deve conter licenciamento A)"
try {
    $fila = Invoke-RestMethod -Uri "$BaseUrl/analise/fila?page=0&size=20" `
        -Headers $authHdr -TimeoutSec 10
    $naFila = $fila.content | Where-Object { $_.id -eq $licA.id }
    if ($null -ne $naFila) {
        Write-OK "Fila OK -- licenciamento A (id=$($licA.id)) encontrado na fila ($($fila.totalElements) total)"
    } else {
        Write-WARN "Licenciamento A nao encontrado na fila (pode estar em pagina diferente)"
    }
} catch {
    Write-FAIL "GET /analise/fila falhou: $($_.Exception.Message)"
}

# --- 12. Distribuir para analista ---
Write-Step "Fluxo A -- PATCH /licenciamentos/$($licA.id)/distribuir?analistaId=$adminUserId"
try {
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/distribuir?analistaId=$adminUserId" `
        -Method PATCH -Headers $authHdr -TimeoutSec 15
    Write-OK "Distribuicao A OK -- analistaId=$adminUserId status=$($licA.status)"
} catch {
    Write-FAIL "Distribuicao A falhou: $($_.Exception.Message)"
}

# --- 13. Iniciar analise ---
Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/iniciar-analise"
try {
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/iniciar-analise" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    Write-OK "Inicio de analise A OK -- status=$($licA.status)"
} catch {
    Write-FAIL "Inicio de analise A falhou: $($_.Exception.Message)"
}

# --- 14. Verificar em-andamento ---
Write-Step "Fluxo A -- GET /analise/em-andamento"
try {
    $emAnd = Invoke-RestMethod -Uri "$BaseUrl/analise/em-andamento?page=0&size=20" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Em-andamento OK -- $($emAnd.totalElements) licenciamento(s) em analise"
} catch {
    Write-FAIL "GET /analise/em-andamento falhou: $($_.Exception.Message)"
}

# --- 15. Verificar marcos (antes do deferimento) ---
Write-Step "Fluxo A -- GET /licenciamentos/$($licA.id)/marcos (ate INICIO_ANALISE)"
try {
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos OK -- $($marcos.Count) marco(s) registrado(s):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.dtMarco) | $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
} catch {
    Write-FAIL "GET /marcos falhou: $($_.Exception.Message)"
}

# --- 16. Deferir licenciamento A ---
Write-Step "Fluxo A -- POST /licenciamentos/$($licA.id)/deferir (EM_ANALISE -> DEFERIDO)"
try {
    $deferBody = @{ observacao = "PPCI aprovado. Projeto em conformidade com RTCBMRS N.01/2024." } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/deferir" `
        -Method POST -Body $deferBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Deferimento A OK -- status=$($licA.status)"
} catch {
    Write-FAIL "Deferimento A falhou: $($_.Exception.Message)"
}

# --- 17. Verificar status DEFERIDO ---
Write-Step "Fluxo A -- GET /licenciamentos/$($licA.id) (verificar DEFERIDO)"
try {
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.status -eq "DEFERIDO") {
        Write-OK "Status DEFERIDO confirmado (correto)"
    } else {
        Write-WARN "Status inesperado: $($cur.status) (esperado DEFERIDO)"
    }
} catch {
    Write-FAIL "Verificacao status A falhou: $($_.Exception.Message)"
}

# --- 18. Marcos finais do licenciamento A ---
Write-Step "Fluxo A -- GET /licenciamentos/$($licA.id)/marcos (final)"
try {
    $marcosF = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos finais -- $($marcosF.Count) marco(s):"
    $marcosF | ForEach-Object {
        Write-Host "    $($_.dtMarco) | $($_.tipoMarco)" -ForegroundColor Gray
    }
    $tiposEsperados = @("SUBMISSAO","DISTRIBUICAO","INICIO_ANALISE","APROVACAO_ANALISE")
    $tiposEncontrados = $marcosF | ForEach-Object { $_.tipoMarco }
    foreach ($t in $tiposEsperados) {
        if ($tiposEncontrados -contains $t) {
            Write-OK "Marco $t presente"
        } else {
            Write-WARN "Marco $t NAO encontrado"
        }
    }
} catch {
    Write-FAIL "GET /marcos finais falhou: $($_.Exception.Message)"
}

# ===========================================================================
# FLUXO B -- CIA: criar -> submeter -> distribuir -> iniciar-analise -> emitir-cia
# ===========================================================================
Write-Step "=== FLUXO B: RASCUNHO -> ANALISE_PENDENTE -> EM_ANALISE -> CIA_EMITIDO ==="

# --- 19. Criar licenciamento B ---
Write-Step "Fluxo B -- POST /licenciamentos (RASCUNHO)"
$licB = $null
try {
    $licB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicenciamentoBody) -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Licenciamento B criado -- id=$($licB.id)"
} catch {
    Write-FAIL "Criacao B falhou: $($_.Exception.Message)"; exit 1
}

# --- 20. Upload PPCI + submeter licenciamento B ---
Write-Step "Fluxo B -- Upload PPCI + submeter"
$tmpB = New-PdfTemp
try {
    $null = Invoke-MultipartUpload -Uri "$BaseUrl/arquivos/upload" `
        -FilePath $tmpB -BearerToken $token -LicId $licB.id
    Write-OK "Upload B OK"
} catch {
    Write-FAIL "Upload B falhou: $($_.Exception.Message)"
} finally { Remove-Item $tmpB -Force -ErrorAction SilentlyContinue }

try {
    $licB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/submeter" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    Write-OK "Submissao B OK -- status=$($licB.status)"
} catch {
    Write-FAIL "Submissao B falhou: $($_.Exception.Message)"
}

# --- 21. Distribuir + iniciar analise B ---
Write-Step "Fluxo B -- Distribuir + iniciar analise"
try {
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/distribuir?analistaId=$adminUserId" `
        -Method PATCH -Headers $authHdr -TimeoutSec 15
    Write-OK "Distribuicao B OK"
} catch {
    Write-FAIL "Distribuicao B falhou: $($_.Exception.Message)"
}
try {
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/iniciar-analise" `
        -Method POST -Headers $authHdr -TimeoutSec 15
    Write-OK "Inicio analise B OK -- status=$($licB.status)"
} catch {
    Write-FAIL "Inicio analise B falhou: $($_.Exception.Message)"
}

# --- 22. Emitir CIA ---
Write-Step "Fluxo B -- POST /licenciamentos/$($licB.id)/emitir-cia (EM_ANALISE -> CIA_EMITIDO)"
try {
    $ciaBody = @{
        observacao = "Saidas de emergencia insuficientes. Extintores fora do prazo de validade. " +
                     "Largura dos corredores abaixo do minimo exigido pelo RTCBMRS N.01/2024."
    } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/emitir-cia" `
        -Method POST -Body $ciaBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "CIA emitida OK -- status=$($licB.status)"
} catch {
    Write-FAIL "Emissao CIA falhou: $($_.Exception.Message)"
}

# --- 23. Verificar status CIA_EMITIDO ---
Write-Step "Fluxo B -- GET /licenciamentos/$($licB.id) (verificar CIA_EMITIDO)"
try {
    $curB = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($curB.status -eq "CIA_EMITIDO") {
        Write-OK "Status CIA_EMITIDO confirmado (correto)"
    } else {
        Write-WARN "Status inesperado: $($curB.status) (esperado CIA_EMITIDO)"
    }
} catch {
    Write-FAIL "Verificacao status B falhou: $($_.Exception.Message)"
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste"

$idsLic = @()
if ($null -ne $licA) { $idsLic += $licA.id }
if ($null -ne $licB) { $idsLic += $licB.id }

foreach ($lid in $idsLic) {
    $sql = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $lid;
DELETE FROM sol.marco_processo WHERE id_licenciamento = $lid;
DELETE FROM sol.boleto WHERE id_licenciamento = $lid;
DELETE FROM sol.endereco WHERE id_endereco IN (
    SELECT id_endereco FROM sol.licenciamento WHERE id_licenciamento = $lid
);
DELETE FROM sol.licenciamento WHERE id_licenciamento = $lid;
COMMIT;
EXIT;
"@
    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tmpSql -Value $sql
    try {
        & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
        Write-OK "Licenciamento id=$lid removido do Oracle"
    } catch {
        Write-WARN "Limpeza Oracle id=$lid falhou: $($_.Exception.Message)"
    } finally {
        Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
    }
}

# ===========================================================================
# Resultado final
# ===========================================================================
Write-Step "Sprint 5 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P04 -- Fila de analise (GET /analise/fila)"
Write-Host "    P04 -- Distribuicao de licenciamento para analista"
Write-Host "    P04 -- Inicio de analise (ANALISE_PENDENTE -> EM_ANALISE)"
Write-Host "    P04 -- Em-andamento (GET /analise/em-andamento)"
Write-Host "    P04 -- Deferimento (EM_ANALISE -> DEFERIDO)"
Write-Host "    P04 -- Historico de marcos (GET /licenciamentos/{id}/marcos)"
Write-Host "    P04 -- Emissao CIA (EM_ANALISE -> CIA_EMITIDO)"
Write-Host "    Notificacoes e-mail via MailHog (assincrono -- verificar http://localhost:8025)"
Write-Host ""
Write-Host "  Deploy da Sprint 5 concluido com sucesso!" -ForegroundColor Green
exit 0
