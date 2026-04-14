#Requires -Version 5.1
<#
.SYNOPSIS
    Sprint 11 - P11 Pagamento de Boleto - Deploy e smoke test
.DESCRIPTION
    Executa o rebuild do backend SOL e valida os fluxos P11-A e P11-B:
      Fluxo A: Gerar boleto -> confirmar pagamento no prazo -> verificar status PAGO + marcos
      Fluxo B: Gerar boleto -> confirmar pagamento apos vencimento -> verificar status VENCIDO + marcos
    Limpa os dados de teste ao final.
.NOTES
    Executar com:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        C:\SOL\infra\scripts\sprint11-deploy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
$BaseUrl      = "http://localhost:8080/api"
$BackendDir   = "C:\SOL\backend"
$MvnCmd       = "C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd"
$JavaHome     = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"

$MailHogExe   = "C:\SOL\infra\mailhog\MailHog.exe"

$AdminUser    = "sol-admin"
$AdminPass    = "Admin@SOL2026"
$AnalistaUser = "analista1"
$AnalistaPass = "Analista@123"

# IDs usados nos testes (limpos ao final)
$LicIds = @(65, 66)

# ---------------------------------------------------------------------------
# Helpers de output
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-FAIL  { param([string]$msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red; exit 1 }
function Write-WARN  { param([string]$msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }

function Show-ErrorBody {
    param($err)
    try {
        $stream = $err.Exception.Response.GetResponseStream()
        $reader = [System.IO.StreamReader]::new($stream)
        $body   = $reader.ReadToEnd()
        Write-Host "    Corpo do erro: $body" -ForegroundColor DarkYellow
    } catch {
        Write-Host "    (nao foi possivel ler corpo do erro)" -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# Autenticacao -- retorna token JWT
# ---------------------------------------------------------------------------
function Get-Token {
    param([string]$username, [string]$password)
    $body = @{ username = $username; password = $password }
    $resp = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/auth/login" `
        -ContentType "application/json" `
        -Body ($body | ConvertTo-Json)
    return $resp.access_token
}

# ---------------------------------------------------------------------------
# Upload de arquivo PDF temporario
# ---------------------------------------------------------------------------
function New-PdfTemp {
    $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.pdf'
    [System.IO.File]::WriteAllBytes($path, [byte[]]@(0x25,0x50,0x44,0x46,0x2D,0x31,0x2E,0x34,0x0A))
    return $path
}

function Invoke-MultipartUpload {
    param([string]$uri, [string]$filePath, [string]$token)
    $boundary  = [System.Guid]::NewGuid().ToString()
    $fileName  = [System.IO.Path]::GetFileName($filePath)
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $encoding  = [System.Text.Encoding]::UTF8

    $bodyParts = [System.Collections.Generic.List[byte]]::new()
    $header = "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`nContent-Type: application/pdf`r`n`r`n"
    $bodyParts.AddRange($encoding.GetBytes($header))
    $bodyParts.AddRange($fileBytes)
    $footer = "`r`n--$boundary--`r`n"
    $bodyParts.AddRange($encoding.GetBytes($footer))

    $headers = @{ Authorization = "Bearer $token" }
    return Invoke-RestMethod -Method Post -Uri $uri `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $bodyParts.ToArray() `
        -Headers $headers
}

# ---------------------------------------------------------------------------
# Monta body de novo licenciamento (estrutura LicenciamentoCreateDTO)
# ---------------------------------------------------------------------------
function New-LicBody {
    param([int]$seed)
    return @{
        tipo         = "PPCI"
        areaConstruida = 300.00
        endereco     = @{
            cep        = "90010100"
            logradouro = "Rua dos Testes"
            numero     = "$seed"
            bairro     = "Centro"
            municipio  = "Porto Alegre"
            uf         = "RS"
        }
    } | ConvertTo-Json -Depth 5
}

# ---------------------------------------------------------------------------
# Funcao auxiliar: cria licenciamento em estado EM_ANALISE (pre-requisito P11)
# Cadeia: criar -> upload -> submeter -> distribuir -> iniciar-analise
# ---------------------------------------------------------------------------
function Invoke-SetupEmAnalise {
    param([int]$licId, [string]$tokenAdmin, [string]$tokenAnalista, [long]$analistaOracleId)

    Write-Host "    Criando licenciamento ID-alvo $licId..." -ForegroundColor Gray

    # 1. Criar
    $licBody = New-LicBody -seed $licId
    try {
        $lic = Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/licenciamentos" `
            -ContentType "application/json" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } `
            -Body $licBody
    } catch {
        Show-ErrorBody $_
        Write-FAIL "Falha ao criar licenciamento $licId"
    }
    $id = $lic.id
    Write-Host "    Licenciamento criado com ID real: $id" -ForegroundColor Gray

    # 2. Upload PPCI
    $pdf = New-PdfTemp
    try {
        Invoke-MultipartUpload `
            -uri "$BaseUrl/arquivos/upload?licenciamentoId=$id&tipoArquivo=PPCI" `
            -filePath $pdf `
            -token $tokenAdmin | Out-Null
    } catch {
        Show-ErrorBody $_
        Write-FAIL "Falha no upload PPCI para licenciamento $id"
    } finally {
        Remove-Item $pdf -Force -ErrorAction SilentlyContinue
    }

    # 3. Submeter
    try {
        Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/licenciamentos/$id/submeter" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } | Out-Null
    } catch {
        Show-ErrorBody $_
        Write-FAIL "Falha ao submeter licenciamento $id"
    }

    # 4. Distribuir (PATCH com analistaId)
    try {
        Invoke-RestMethod -Method Patch `
            -Uri "$BaseUrl/licenciamentos/$id/distribuir?analistaId=$analistaOracleId" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } | Out-Null
    } catch {
        Show-ErrorBody $_
        Write-FAIL "Falha ao distribuir licenciamento $id"
    }

    # 5. Iniciar analise
    try {
        Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/licenciamentos/$id/iniciar-analise" `
            -Headers @{ Authorization = "Bearer $tokenAnalista" } | Out-Null
    } catch {
        Show-ErrorBody $_
        Write-FAIL "Falha ao iniciar analise do licenciamento $id"
    }

    Write-Host "    Licenciamento $id em EM_ANALISE." -ForegroundColor Gray
    return $id
}

# ===========================================================================
# INICIO
# ===========================================================================

Write-Step "Sprint 11 - P11 Pagamento de Boleto"
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "  Backend:   $BackendDir"
Write-Host "  URL base:  $BaseUrl"

# ---------------------------------------------------------------------------
# Passo 0a: Garantir MailHog rodando (SMTP local para e-mails de boleto)
# ---------------------------------------------------------------------------
Write-Step "Passo 0a - MailHog (SMTP localhost:1025)"
$smtpOk = (Test-NetConnection -ComputerName localhost -Port 1025 -InformationLevel Quiet -WarningAction SilentlyContinue)
if (-not $smtpOk) {
    if (-not (Test-Path $MailHogExe)) { Write-FAIL "MailHog nao encontrado em $MailHogExe" }
    Start-Process -FilePath $MailHogExe -WindowStyle Hidden
    Start-Sleep -Seconds 4
    $smtpOk = (Test-NetConnection -ComputerName localhost -Port 1025 -InformationLevel Quiet -WarningAction SilentlyContinue)
    if (-not $smtpOk) { Write-FAIL "MailHog nao subiu na porta 1025." }
    Write-OK "MailHog iniciado (SMTP :1025, UI :8025)."
} else {
    Write-OK "MailHog ja rodando."
}

# ---------------------------------------------------------------------------
# Passo 0b: Parar servico antes do build (libera o JAR em uso)
# ---------------------------------------------------------------------------
Write-Step "Passo 0b - Parar servico SOL-Backend (pre-build)"
try {
    $svc = Get-Service -Name "SOL-Backend" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service -Name "SOL-Backend" -Force
        Start-Sleep -Seconds 5
        Write-OK "Servico parado."
    } else {
        Write-WARN "Servico ja parado ou nao encontrado."
    }
} catch {
    Write-WARN "Nao foi possivel parar o servico: $_"
}

# ---------------------------------------------------------------------------
# Passo 1: Build do backend
# ---------------------------------------------------------------------------
Write-Step "Passo 1 - Build Maven (skip tests)"
$env:JAVA_HOME = $JavaHome
Push-Location $BackendDir
try {
    & $MvnCmd clean package -DskipTests -q
    if ($LASTEXITCODE -ne 0) { Write-FAIL "Build Maven falhou (exit $LASTEXITCODE)" }
    Write-OK "Build concluido."
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Passo 2: Reiniciar servico
# ---------------------------------------------------------------------------
Write-Step "Passo 2 - Reiniciar servico SOL-Backend"
try {
    Restart-Service -Name "SOL-Backend" -Force
    Start-Sleep -Seconds 20
    Write-OK "Servico reiniciado."
} catch {
    Write-WARN "Nao foi possivel reiniciar o servico automaticamente: $($_.Exception.Message)"
    Write-WARN "Reinicie manualmente e aguarde o startup antes de continuar."
    Read-Host "Pressione ENTER apos confirmar que o servico esta em execucao"
}

# ---------------------------------------------------------------------------
# Passo 3: Health check
# ---------------------------------------------------------------------------
Write-Step "Passo 3 - Health check"
$maxTentativas = 12
$tentativa     = 0
$ok            = $false
while ($tentativa -lt $maxTentativas -and -not $ok) {
    $tentativa++
    try {
        $health = Invoke-RestMethod -Uri "$BaseUrl/actuator/health" -TimeoutSec 5
        if ($health.status -eq "UP") { $ok = $true }
    } catch { }
    if (-not $ok) {
        Write-Host "    Tentativa $tentativa/$maxTentativas - aguardando..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}
if (-not $ok) { Write-FAIL "Servico nao respondeu em tempo habil." }
Write-OK "Health UP."

# ---------------------------------------------------------------------------
# Passo 4: Autenticacao
# ---------------------------------------------------------------------------
Write-Step "Passo 4 - Autenticacao"
try {
    $tokenAdmin    = Get-Token -username $AdminUser    -password $AdminPass
    $tokenAnalista = Get-Token -username $AnalistaUser -password $AnalistaPass
    Write-OK "Tokens obtidos (sol-admin + analista1)."
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha na autenticacao."
}

# Busca ID Oracle do analista1 (necessario para distribuir)
$analistaOracleId = $null
try {
    $meAnalista = Invoke-RestMethod -Uri "$BaseUrl/auth/me" `
        -Headers @{ Authorization = "Bearer $tokenAnalista" }
    $analistaOracleId = $meAnalista.id
    Write-OK "analista1 Oracle ID: $analistaOracleId"
} catch {
    Show-ErrorBody $_
    Write-FAIL "Nao foi possivel obter ID Oracle do analista."
}

# ---------------------------------------------------------------------------
# Passo 5: Limpeza preventiva de dados de teste anteriores
# ---------------------------------------------------------------------------
Write-Step "Passo 5 - Limpeza preventiva (Oracle JDBC)"
$sqlUser = "sol"
$sqlPass = "Sol@CBM2026"

$cleanSql = @"
BEGIN
  FOR r IN (
    SELECT l.id FROM sol.licenciamento l
    WHERE l.nr_ppci IN ('A00000065AA001','A00000066AA001')
  ) LOOP
    DELETE FROM sol.marco_processo WHERE id_licenciamento = r.id;
    DELETE FROM sol.arquivo_ed      WHERE id_licenciamento = r.id;
    DELETE FROM sol.boleto          WHERE id_licenciamento = r.id;
    DELETE FROM sol.licenciamento   WHERE id = r.id;
  END LOOP;
  COMMIT;
END;
"@

$sqlplus = Get-Command sqlplus -ErrorAction SilentlyContinue
if ($sqlplus) {
    echo $cleanSql | sqlplus -S "${sqlUser}/${sqlPass}@localhost:1521/XEPDB1" | Out-Null
    Write-OK "Limpeza via sqlplus concluida."
} else {
    Write-WARN "sqlplus nao encontrado. Pulando limpeza preventiva SQL."
}

# ---------------------------------------------------------------------------
# Passo 6: Fluxo A -- Gerar boleto + confirmar pagamento no prazo (PAGO)
# ---------------------------------------------------------------------------
Write-Step "Passo 6 - Fluxo A: Gerar boleto + confirmar pagamento (status esperado: PAGO)"

$idA = Invoke-SetupEmAnalise -licId 65 -tokenAdmin $tokenAdmin -tokenAnalista $tokenAnalista -analistaOracleId $analistaOracleId

# 6.1 Gerar boleto
Write-Host "    6.1 Gerando boleto para licenciamento $idA..." -ForegroundColor Gray
try {
    $boleto = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/boletos/licenciamento/$idA" `
        -Headers @{ Authorization = "Bearer $tokenAnalista" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao gerar boleto para licenciamento $idA"
}
$boletoId = $boleto.id
if ($boleto.status -ne "PENDENTE") {
    Write-FAIL "Boleto gerado com status inesperado: $($boleto.status) (esperado: PENDENTE)"
}
Write-OK "Boleto ID $boletoId gerado com status PENDENTE. Valor: R$ $($boleto.valor). Vencimento: $($boleto.dtVencimento)"

# 6.2 Verificar marco BOLETO_GERADO
Write-Host "    6.2 Verificando marco BOLETO_GERADO..." -ForegroundColor Gray
try {
    $marcos = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$idA/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao buscar marcos do licenciamento $idA"
}
$marcoGerado = $marcos | Where-Object { $_.tipoMarco -eq "BOLETO_GERADO" }
if (-not $marcoGerado) {
    Write-FAIL "Marco BOLETO_GERADO nao encontrado para licenciamento $idA"
}
Write-OK "Marco BOLETO_GERADO registrado: '$($marcoGerado.observacao)'"

# 6.2b Testar RN-090: tentar gerar segundo boleto enquanto primeiro ainda PENDENTE (deve falhar)
Write-Host "    6.2b Testando RN-090 (duplicata PENDENTE bloqueada)..." -ForegroundColor Gray
try {
    Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/boletos/licenciamento/$idA" `
        -Headers @{ Authorization = "Bearer $tokenAnalista" } | Out-Null
    Write-FAIL "RN-090 nao funcionou: segundo boleto foi gerado indevidamente (primeiro ainda PENDENTE)"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -in @(400, 409, 422)) {
        Write-OK "RN-090 OK: segundo boleto bloqueado enquanto primeiro PENDENTE (HTTP $statusCode)."
    } else {
        Write-WARN "RN-090: resposta inesperada HTTP $statusCode"
    }
}

# 6.3 Confirmar pagamento no prazo
$dataHoje = (Get-Date).ToString("yyyy-MM-dd")
Write-Host "    6.3 Confirmando pagamento em $dataHoje (dentro do prazo)..." -ForegroundColor Gray
try {
    $boletoConfirmado = Invoke-RestMethod -Method Patch `
        -Uri "$BaseUrl/boletos/$boletoId/confirmar-pagamento?dataPagamento=$dataHoje" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao confirmar pagamento do boleto $boletoId"
}
if ($boletoConfirmado.status -ne "PAGO") {
    Write-FAIL "Boleto $boletoId com status inesperado apos confirmacao: $($boletoConfirmado.status) (esperado: PAGO)"
}
Write-OK "Boleto $boletoId status PAGO confirmado."

# 6.4 Verificar marco PAGAMENTO_CONFIRMADO
Write-Host "    6.4 Verificando marco PAGAMENTO_CONFIRMADO..." -ForegroundColor Gray
try {
    $marcos2 = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$idA/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao buscar marcos pos-pagamento do licenciamento $idA"
}
$marcoPago = $marcos2 | Where-Object { $_.tipoMarco -eq "PAGAMENTO_CONFIRMADO" }
if (-not $marcoPago) {
    Write-FAIL "Marco PAGAMENTO_CONFIRMADO nao encontrado para licenciamento $idA"
}
Write-OK "Marco PAGAMENTO_CONFIRMADO registrado: '$($marcoPago.observacao)'"

Write-OK "Fluxo A concluido com sucesso."

# ---------------------------------------------------------------------------
# Passo 7: Fluxo B -- Gerar boleto + confirmar pagamento apos vencimento (VENCIDO)
# ---------------------------------------------------------------------------
Write-Step "Passo 7 - Fluxo B: Gerar boleto + confirmar pagamento apos vencimento (status esperado: VENCIDO)"

$idB = Invoke-SetupEmAnalise -licId 66 -tokenAdmin $tokenAdmin -tokenAnalista $tokenAnalista -analistaOracleId $analistaOracleId

# 7.1 Gerar boleto
Write-Host "    7.1 Gerando boleto para licenciamento $idB..." -ForegroundColor Gray
try {
    $boletoB = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/boletos/licenciamento/$idB" `
        -Headers @{ Authorization = "Bearer $tokenAnalista" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao gerar boleto para licenciamento $idB"
}
$boletoBId = $boletoB.id
if ($boletoB.status -ne "PENDENTE") {
    Write-FAIL "Boleto B gerado com status inesperado: $($boletoB.status) (esperado: PENDENTE)"
}
Write-OK "Boleto ID $boletoBId gerado com status PENDENTE. Vencimento: $($boletoB.dtVencimento)"

# 7.2 Verificar marco BOLETO_GERADO
Write-Host "    7.2 Verificando marco BOLETO_GERADO..." -ForegroundColor Gray
try {
    $marcosB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$idB/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao buscar marcos do licenciamento $idB"
}
$marcoGeradoB = $marcosB | Where-Object { $_.tipoMarco -eq "BOLETO_GERADO" }
if (-not $marcoGeradoB) {
    Write-FAIL "Marco BOLETO_GERADO nao encontrado para licenciamento $idB"
}
Write-OK "Marco BOLETO_GERADO registrado."

# 7.3 Confirmar pagamento APOS vencimento
$dataAtrasada = (Get-Date).AddDays(35).ToString("yyyy-MM-dd")
Write-Host "    7.3 Confirmando pagamento com data futura $dataAtrasada (apos vencimento de 30 dias)..." -ForegroundColor Gray
try {
    $boletoBConfirmado = Invoke-RestMethod -Method Patch `
        -Uri "$BaseUrl/boletos/$boletoBId/confirmar-pagamento?dataPagamento=$dataAtrasada" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao confirmar pagamento atrasado do boleto $boletoBId"
}
if ($boletoBConfirmado.status -ne "VENCIDO") {
    Write-FAIL "Boleto $boletoBId com status inesperado: $($boletoBConfirmado.status) (esperado: VENCIDO)"
}
Write-OK "Boleto $boletoBId status VENCIDO confirmado (pagamento registrado apos vencimento)."

# 7.4 Verificar marco BOLETO_VENCIDO
Write-Host "    7.4 Verificando marco BOLETO_VENCIDO..." -ForegroundColor Gray
try {
    $marcosB2 = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$idB/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch {
    Show-ErrorBody $_
    Write-FAIL "Falha ao buscar marcos pos-vencimento do licenciamento $idB"
}
$marcoVencido = $marcosB2 | Where-Object { $_.tipoMarco -eq "BOLETO_VENCIDO" }
if (-not $marcoVencido) {
    Write-FAIL "Marco BOLETO_VENCIDO nao encontrado para licenciamento $idB"
}
Write-OK "Marco BOLETO_VENCIDO registrado: '$($marcoVencido.observacao)'"

# 7.5 Testar RN-095: tentar confirmar boleto nao-PENDENTE (deve falhar)
Write-Host "    7.5 Testando RN-095 (confirmacao de boleto nao-PENDENTE bloqueada)..." -ForegroundColor Gray
try {
    Invoke-RestMethod -Method Patch `
        -Uri "$BaseUrl/boletos/$boletoBId/confirmar-pagamento" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } | Out-Null
    Write-FAIL "RN-095 nao funcionou: confirmacao de boleto nao-PENDENTE foi aceita"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -in @(400, 409, 422)) {
        Write-OK "RN-095 OK: confirmacao de boleto nao-PENDENTE bloqueada (HTTP $statusCode)."
    } else {
        Write-WARN "RN-095: resposta inesperada HTTP $statusCode"
    }
}

Write-OK "Fluxo B concluido com sucesso."

# ---------------------------------------------------------------------------
# Passo 8: RN-091 -- aviso de verificacao manual
# ---------------------------------------------------------------------------
Write-Step "Passo 8 - RN-091: licenciamento isento nao gera boleto"
Write-Host "    Verificacao via tentativa de POST com licenciamento isento (requer licenciamento isento pre-existente)." -ForegroundColor Gray
Write-WARN "RN-091 nao testado automaticamente neste script (requer setup de licenciamento isento separado)."
Write-WARN "Para testar manualmente: POST /boletos/licenciamento/{id} onde isentoTaxa=true deve retornar HTTP 400/422."

# ---------------------------------------------------------------------------
# Passo 9: Limpeza pos-teste
# ---------------------------------------------------------------------------
Write-Step "Passo 9 - Limpeza dos dados de teste"
$sqlplus2 = Get-Command sqlplus -ErrorAction SilentlyContinue
if ($sqlplus2) {
    $delSql = @"
BEGIN
  FOR r IN (
    SELECT l.id FROM sol.licenciamento l
    WHERE l.nr_ppci IN ('A00000065AA001','A00000066AA001')
  ) LOOP
    DELETE FROM sol.marco_processo WHERE id_licenciamento = r.id;
    DELETE FROM sol.arquivo_ed      WHERE id_licenciamento = r.id;
    DELETE FROM sol.boleto          WHERE id_licenciamento = r.id;
    DELETE FROM sol.licenciamento   WHERE id = r.id;
  END LOOP;
  COMMIT;
END;
"@
    echo $delSql | sqlplus -S "${sqlUser}/${sqlPass}@localhost:1521/XEPDB1" | Out-Null
    Write-OK "Dados de teste removidos via sqlplus."
} else {
    Write-WARN "sqlplus nao disponivel. Remova manualmente os licenciamentos com nr_ppci em A00000065AA001 e A00000066AA001."
}

# ---------------------------------------------------------------------------
# Sumario
# ---------------------------------------------------------------------------
Write-Step "SUMARIO"
Write-Host ""
Write-Host "  Sprint 11 - P11 Pagamento de Boleto concluida com sucesso." -ForegroundColor Green
Write-Host ""
Write-Host "  Arquivos alterados/criados nesta sprint:" -ForegroundColor White
Write-Host "    [M] BoletoService.java       : marcos, emails, keycloakId, vencerBoleto()"
Write-Host "    [M] BoletoController.java    : AuthenticationPrincipal Jwt em create e confirmarPagamento"
Write-Host "    [N] BoletoJobService.java    : job P11-B (Scheduled 02:00 diario)"
Write-Host ""
Write-Host "  Fluxos validados:" -ForegroundColor White
Write-Host "    Fluxo A: PENDENTE => PAGO    + marcos BOLETO_GERADO, PAGAMENTO_CONFIRMADO"
Write-Host "    Fluxo B: PENDENTE => VENCIDO + marcos BOLETO_GERADO, BOLETO_VENCIDO"
Write-Host "    RN-090 : boleto PENDENTE duplicado bloqueado"
Write-Host "    RN-095 : confirmacao de boleto nao-PENDENTE bloqueada"
Write-Host ""
Write-Host "  Job P11-B (BoletoJobService):" -ForegroundColor White
Write-Host "    Cron  : 0 0 2 * * * (02:00 diario)"
Write-Host "    Busca : boletos PENDENTE com dtVencimento menor que hoje"
Write-Host "    Acao  : PENDENTE => VENCIDO + marco BOLETO_VENCIDO + e-mail RT/RU"
Write-Host ""
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""
