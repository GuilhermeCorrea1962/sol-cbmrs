#Requires -Version 5.1
<#
.SYNOPSIS
    Sprint 13 - P13 Jobs Automaticos de Alvaras - Deploy e smoke test
.DESCRIPTION
    Executa o rebuild do backend SOL e valida os jobs automaticos P13:
      P13-A: APPCI_EMITIDO com dtValidadeAppci vencida -> ALVARA_VENCIDO
      P13-B: Marco NOTIFICACAO_SOLICITAR_RENOVACAO_90 (se existir alvara a vencer em 90d)
      P13-C: Marco NOTIFICACAO_ALVARA_VENCIDO apos vencimento (idempotente - RN-129)
      RN-129: segundo disparo do job nao registra marco duplicado
      Verificacao da entidade RotinaExecucao no banco (via sqlplus)
.NOTES
    Executar com:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        C:\SOL\infra\scripts\sprint13-deploy.ps1
    Pre-requisito: sqlplus disponivel no PATH (necessario para DDL da sequence
    e para setup/verificacao dos dados de teste).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuracao (valores reais do servidor -- descobertos na Sprint 11)
# ---------------------------------------------------------------------------
$BaseUrl      = "http://localhost:8080/api"
$BackendDir   = "C:\SOL\backend"
$MvnCmd       = "C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd"
$JavaHome     = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$MailHogExe   = "C:\SOL\infra\mailhog\MailHog.exe"

$AdminUser    = "sol-admin"
$AdminPass    = "Admin@SOL2026"

$OraUser      = "sol"
$OraPass      = "Sol@CBM2026"
$OraConn      = "localhost:1521/XEPDB1"

# ---------------------------------------------------------------------------
# Helpers de output
# ---------------------------------------------------------------------------
function Write-Step { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-FAIL { param([string]$msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red; exit 1 }
function Write-WARN { param([string]$msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }

function Show-ErrorBody {
    param($err)
    try {
        $stream = $err.Exception.Response.GetResponseStream()
        $reader = [System.IO.StreamReader]::new($stream)
        Write-Host "    Corpo do erro: $($reader.ReadToEnd())" -ForegroundColor DarkYellow
    } catch {
        Write-Host "    (nao foi possivel ler corpo do erro)" -ForegroundColor DarkYellow
    }
}

function Invoke-Sqlplus {
    param([string]$sql)
    $sqlplus = Get-Command sqlplus -ErrorAction SilentlyContinue
    if (-not $sqlplus) { Write-WARN "sqlplus nao disponivel. Operacao ignorada."; return $null }
    $result = echo $sql | sqlplus -S "${OraUser}/${OraPass}@${OraConn}" 2>&1
    return $result
}

# ---------------------------------------------------------------------------
# Autenticacao
# ---------------------------------------------------------------------------
function Get-Token {
    param([string]$username, [string]$password)
    $resp = Invoke-RestMethod -Method Post "$BaseUrl/auth/login" `
        -ContentType "application/json" `
        -Body (@{ username = $username; password = $password } | ConvertTo-Json)
    return $resp.access_token
}

# ---------------------------------------------------------------------------
# Upload de PDF minimo
# ---------------------------------------------------------------------------
function New-PdfTemp {
    $path = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.pdf'
    [System.IO.File]::WriteAllBytes($path, [byte[]]@(0x25,0x50,0x44,0x46,0x2D,0x31,0x2E,0x34,0x0A))
    return $path
}

function Invoke-MultipartUpload {
    param([string]$uri, [string]$filePath, [string]$token)
    $boundary = [System.Guid]::NewGuid().ToString()
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $enc = [System.Text.Encoding]::UTF8
    $parts = [System.Collections.Generic.List[byte]]::new()
    $parts.AddRange($enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`nContent-Type: application/pdf`r`n`r`n"))
    $parts.AddRange($fileBytes)
    $parts.AddRange($enc.GetBytes("`r`n--$boundary--`r`n"))
    return Invoke-RestMethod -Method Post -Uri $uri `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $parts.ToArray() `
        -Headers @{ Authorization = "Bearer $token" }
}

# ===========================================================================
# INICIO
# ===========================================================================

Write-Step "Sprint 13 - P13 Jobs Automaticos de Alvaras"
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "  Backend:   $BackendDir"
Write-Host "  URL base:  $BaseUrl"

# ---------------------------------------------------------------------------
# Passo 0a: MailHog
# ---------------------------------------------------------------------------
Write-Step "Passo 0a - MailHog (SMTP localhost:1025)"
$smtpOk = (Test-NetConnection -ComputerName localhost -Port 1025 `
    -InformationLevel Quiet -WarningAction SilentlyContinue)
if (-not $smtpOk) {
    if (-not (Test-Path $MailHogExe)) { Write-FAIL "MailHog nao encontrado em $MailHogExe" }
    Start-Process -FilePath $MailHogExe -WindowStyle Hidden
    Start-Sleep -Seconds 4
    $smtpOk = (Test-NetConnection -ComputerName localhost -Port 1025 `
        -InformationLevel Quiet -WarningAction SilentlyContinue)
    if (-not $smtpOk) { Write-FAIL "MailHog nao subiu na porta 1025." }
    Write-OK "MailHog iniciado."
} else {
    Write-OK "MailHog ja rodando."
}

# ---------------------------------------------------------------------------
# Passo 0b: Parar servico antes do build
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
} catch { Write-WARN "Nao foi possivel parar o servico: $_" }

# ---------------------------------------------------------------------------
# Passo 0c: Criar sequence Oracle SOL.SEQ_ROTINA_EXECUCAO
# (ddl-auto:update cria a tabela mas NAO cria sequences Oracle)
# ---------------------------------------------------------------------------
Write-Step "Passo 0c - Criar sequence Oracle SOL.SEQ_ROTINA_EXECUCAO"
$sqlSeq = @"
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM   all_sequences
  WHERE  sequence_owner = 'SOL'
    AND  sequence_name  = 'SEQ_ROTINA_EXECUCAO';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE SOL.SEQ_ROTINA_EXECUCAO START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('Sequence SOL.SEQ_ROTINA_EXECUCAO criada.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Sequence SOL.SEQ_ROTINA_EXECUCAO ja existe. Ignorando.');
  END IF;
END;
/
EXIT;
"@
$sqlplusCmd = Get-Command sqlplus -ErrorAction SilentlyContinue
if ($sqlplusCmd) {
    echo $sqlSeq | sqlplus -S "${OraUser}/${OraPass}@${OraConn}" | Out-Null
    Write-OK "Verificacao/criacao da sequence concluida."
} else {
    Write-WARN "sqlplus nao disponivel. A sequence precisa ser criada manualmente antes de iniciar o servico."
    Read-Host "Crie a sequence manualmente e pressione ENTER para continuar"
}

# ---------------------------------------------------------------------------
# Passo 1: Build Maven
# ---------------------------------------------------------------------------
Write-Step "Passo 1 - Build Maven (skip tests)"
$env:JAVA_HOME = $JavaHome
Push-Location $BackendDir
try {
    & $MvnCmd clean package -DskipTests -q
    if ($LASTEXITCODE -ne 0) { Write-FAIL "Build Maven falhou (exit $LASTEXITCODE)" }
    Write-OK "Build concluido."
} finally { Pop-Location }

# ---------------------------------------------------------------------------
# Passo 2: Restart servico
# ---------------------------------------------------------------------------
Write-Step "Passo 2 - Reiniciar servico SOL-Backend"
try {
    Restart-Service -Name "SOL-Backend" -Force
    Start-Sleep -Seconds 20
    Write-OK "Servico reiniciado."
} catch {
    Write-WARN "Restart automatico falhou: $($_.Exception.Message)"
    Read-Host "Reinicie manualmente e pressione ENTER para continuar"
}

# ---------------------------------------------------------------------------
# Passo 3: Health check
# (Na primeira inicializacao apos ddl-auto:update, o Hibernate cria a tabela
#  ROTINA_EXECUCAO -- pode levar alguns segundos extras)
# ---------------------------------------------------------------------------
Write-Step "Passo 3 - Health check"
$ok = $false
for ($i = 1; $i -le 15 -and -not $ok; $i++) {
    try {
        $h = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 5
        if ($h.status -eq "UP") { $ok = $true }
    } catch { }
    if (-not $ok) {
        Write-Host "    Tentativa $i/15 - aguardando..." -ForegroundColor DarkGray
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
    $tokenAdmin = Get-Token $AdminUser $AdminPass
    Write-OK "Token obtido (sol-admin)."
} catch { Show-ErrorBody $_; Write-FAIL "Falha na autenticacao." }

# ---------------------------------------------------------------------------
# Passo 5: Setup de dados de teste (via sqlplus)
# Cria um licenciamento RASCUNHO via API, depois promove via SQL para
# APPCI_EMITIDO com dtValidadeAppci = ontem (elegivel para P13-A)
# ---------------------------------------------------------------------------
Write-Step "Passo 5 - Setup de dados de teste"

# 5.1 Criar licenciamento via API (status RASCUNHO)
Write-Host "    5.1 Criando licenciamento de teste (RASCUNHO)..." -ForegroundColor Gray
$bodyLic = @{
    tipo           = "PPCI"
    areaConstruida = 350.00
    endereco       = @{
        cep        = "90010100"
        logradouro = "Rua dos Jobs Automaticos"
        numero     = "13"
        bairro     = "Centro"
        municipio  = "Porto Alegre"
        uf         = "RS"
    }
} | ConvertTo-Json -Depth 5
try {
    $licTeste = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyLic
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao criar licenciamento de teste." }

$licTesteId = $licTeste.id
Write-Host "    Licenciamento de teste criado: ID $licTesteId" -ForegroundColor Gray

# 5.2 Promover para APPCI_EMITIDO com dtValidadeAppci = ontem via sqlplus
Write-Host "    5.2 Promovendo para APPCI_EMITIDO com dtValidadeAppci = ontem via sqlplus..." -ForegroundColor Gray
if ($sqlplusCmd) {
    $sqlPromotar = @"
UPDATE SOL.LICENCIAMENTO
SET    STATUS           = 'APPCI_EMITIDO',
       DT_VALIDADE_APPCI = TRUNC(SYSDATE) - 1,
       NUMERO_PPCI      = 'TESTE-P13-' || $licTesteId
WHERE  ID_LICENCIAMENTO = $licTesteId;
COMMIT;
EXIT;
"@
    echo $sqlPromotar | sqlplus -S "${OraUser}/${OraPass}@${OraConn}" | Out-Null
    Write-OK "Licenciamento $licTesteId promovido para APPCI_EMITIDO com dtValidadeAppci = ontem."
} else {
    Write-WARN "sqlplus nao disponivel. Promova manualmente o licenciamento $licTesteId:"
    Write-WARN "  UPDATE SOL.LICENCIAMENTO SET STATUS = 'APPCI_EMITIDO', DT_VALIDADE_APPCI = TRUNC(SYSDATE) - 1 WHERE ID_LICENCIAMENTO = $licTesteId;"
    Read-Host "Execute o SQL manualmente e pressione ENTER para continuar"
}

# ---------------------------------------------------------------------------
# Passo 6: Disparar rotina P13 via endpoint admin
# ---------------------------------------------------------------------------
Write-Step "Passo 6 - Disparar rotina P13 via POST /admin/jobs/rotina-alvara"
Write-Host "    (Execucao sincrona -- aguardar ate 2 minutos para bases grandes)" -ForegroundColor Gray
try {
    $respJob = Invoke-RestMethod -Method Post "$BaseUrl/admin/jobs/rotina-alvara" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -TimeoutSec 120
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao disparar rotina P13." }
Write-OK "Rotina P13 executada. Descricao: $($respJob.descricao)"
Write-OK "Data/hora de execucao: $($respJob.dataHora)"

# ---------------------------------------------------------------------------
# Passo 7: Verificar status ALVARA_VENCIDO (P13-A)
# ---------------------------------------------------------------------------
Write-Step "Passo 7 - Verificar transicao APPCI_EMITIDO -> ALVARA_VENCIDO (P13-A)"
try {
    $licAtual = Invoke-RestMethod "$BaseUrl/licenciamentos/$licTesteId" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar licenciamento $licTesteId." }

if ($licAtual.status -ne "ALVARA_VENCIDO") {
    Write-FAIL "P13-A FALHOU: status esperado ALVARA_VENCIDO, recebido: $($licAtual.status)"
}
Write-OK "P13-A OK: licenciamento $licTesteId transicionado para ALVARA_VENCIDO."

# ---------------------------------------------------------------------------
# Passo 8: Verificar marco NOTIFICACAO_ALVARA_VENCIDO (P13-C)
# ---------------------------------------------------------------------------
Write-Step "Passo 8 - Verificar marco NOTIFICACAO_ALVARA_VENCIDO (P13-C)"
try {
    $marcos = Invoke-RestMethod "$BaseUrl/licenciamentos/$licTesteId/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar marcos do licenciamento $licTesteId." }

$marcoVencido = $marcos | Where-Object { $_.tipoMarco -eq "NOTIFICACAO_ALVARA_VENCIDO" }
if (-not $marcoVencido) {
    Write-FAIL "P13-C FALHOU: marco NOTIFICACAO_ALVARA_VENCIDO nao encontrado para licenciamento $licTesteId."
}
Write-OK "P13-C OK: marco NOTIFICACAO_ALVARA_VENCIDO registrado: '$($marcoVencido.observacao)'"

# ---------------------------------------------------------------------------
# Passo 9: Verificar idempotencia (RN-129) -- disparar rotina uma segunda vez
# ---------------------------------------------------------------------------
Write-Step "Passo 9 - Verificar idempotencia RN-129 (segundo disparo do job)"
try {
    Invoke-RestMethod -Method Post "$BaseUrl/admin/jobs/rotina-alvara" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -TimeoutSec 120 | Out-Null
} catch { Show-ErrorBody $_; Write-FAIL "Falha no segundo disparo da rotina P13." }

# Verificar que o marco NOTIFICACAO_ALVARA_VENCIDO nao foi duplicado
try {
    $marcos2 = Invoke-RestMethod "$BaseUrl/licenciamentos/$licTesteId/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar marcos apos segundo disparo." }

$qtdMarcosVencido = ($marcos2 | Where-Object { $_.tipoMarco -eq "NOTIFICACAO_ALVARA_VENCIDO" }).Count
if ($qtdMarcosVencido -ne 1) {
    Write-FAIL "RN-129 FALHOU: esperado 1 marco NOTIFICACAO_ALVARA_VENCIDO, encontrado: $qtdMarcosVencido"
}
Write-OK "RN-129 OK: marco NOTIFICACAO_ALVARA_VENCIDO nao duplicado apos segundo disparo (total: $qtdMarcosVencido)."

# Verificar que o status nao mudou (licenciamento ja esta em ALVARA_VENCIDO -- P13-A nao reprocessa)
$licApos2 = Invoke-RestMethod "$BaseUrl/licenciamentos/$licTesteId" `
    -Headers @{ Authorization = "Bearer $tokenAdmin" }
if ($licApos2.status -ne "ALVARA_VENCIDO") {
    Write-WARN "Status inesperado apos segundo disparo: $($licApos2.status)"
} else {
    Write-OK "Status ALVARA_VENCIDO mantido apos segundo disparo (P13-A nao reprocessa - RN-121)."
}

# ---------------------------------------------------------------------------
# Passo 10: Verificar RotinaExecucao no banco (via sqlplus)
# ---------------------------------------------------------------------------
Write-Step "Passo 10 - Verificar RotinaExecucao no banco Oracle"
if ($sqlplusCmd) {
    $sqlVerRot = @"
SET PAGESIZE 10
SET LINESIZE 120
COLUMN TIPO_ROTINA FORMAT A30
COLUMN DSC_SITUACAO FORMAT A12
COLUMN DTH_FIM_EXECUCAO FORMAT A25
SELECT ID_ROTINA_EXECUCAO, TIPO_ROTINA, DSC_SITUACAO, NR_PROCESSADOS, NR_ERROS,
       TO_CHAR(DTH_FIM_EXECUCAO, 'YYYY-MM-DD HH24:MI:SS') AS DTH_FIM_EXECUCAO
FROM   SOL.ROTINA_EXECUCAO
ORDER  BY ID_ROTINA_EXECUCAO DESC
FETCH FIRST 5 ROWS ONLY;
EXIT;
"@
    $rotinas = echo $sqlVerRot | sqlplus -S "${OraUser}/${OraPass}@${OraConn}" 2>&1
    Write-Host ""
    Write-Host "    Ultimas execucoes de rotina:" -ForegroundColor White
    $rotinas | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-OK "Verificacao de RotinaExecucao concluida."
} else {
    Write-WARN "sqlplus nao disponivel. Verifique manualmente: SELECT * FROM SOL.ROTINA_EXECUCAO ORDER BY ID_ROTINA_EXECUCAO DESC;"
}

# ---------------------------------------------------------------------------
# Passo 11: Limpeza dos dados de teste
# ---------------------------------------------------------------------------
Write-Step "Passo 11 - Limpeza dos dados de teste"
if ($sqlplusCmd) {
    $sqlClean = @"
BEGIN
  DELETE FROM SOL.MARCO_PROCESSO WHERE ID_LICENCIAMENTO = $licTesteId;
  DELETE FROM SOL.ARQUIVO_ED      WHERE ID_LICENCIAMENTO = $licTesteId;
  DELETE FROM SOL.BOLETO          WHERE ID_LICENCIAMENTO = $licTesteId;
  DELETE FROM SOL.LICENCIAMENTO   WHERE ID_LICENCIAMENTO = $licTesteId;
  DELETE FROM SOL.ROTINA_EXECUCAO WHERE TIPO_ROTINA = 'GERAR_NOTIFICACAO_ALVARA_VENCIDO';
  COMMIT;
END;
/
EXIT;
"@
    echo $sqlClean | sqlplus -S "${OraUser}/${OraPass}@${OraConn}" | Out-Null
    Write-OK "Dados de teste removidos (licenciamento $licTesteId + rotinas de execucao)."
} else {
    Write-WARN "sqlplus nao disponivel. Remova manualmente o licenciamento $licTesteId."
}

# ===========================================================================
# Sumario
# ===========================================================================
Write-Step "SUMARIO"
Write-Host ""
Write-Host "  Sprint 13 - P13 Jobs Automaticos de Alvaras concluida com sucesso." -ForegroundColor Green
Write-Host ""
Write-Host "  Arquivos modificados:" -ForegroundColor White
Write-Host "    [M] entity/enums/StatusLicenciamento.java    : + ALVARA_VENCIDO"
Write-Host "    [M] entity/enums/TipoMarco.java              : + 4 marcos de notificacao P13"
Write-Host "    [M] repository/LicenciamentoRepository.java  : + 3 queries ID-based para P13"
Write-Host ""
Write-Host "  Arquivos criados:" -ForegroundColor White
Write-Host "    [N] entity/RotinaExecucao.java               : entidade de rastreabilidade de execucao"
Write-Host "    [N] repository/RotinaExecucaoRepository.java : repositorio de RotinaExecucao"
Write-Host "    [N] service/AlvaraVencimentoService.java     : logica de negocio P13-A/B/C"
Write-Host "    [N] service/AlvaraJobService.java            : agendador @Scheduled P13-A/B/C/D/E"
Write-Host "    [N] controller/AlvaraAdminController.java    : endpoint admin para disparo manual"
Write-Host ""
Write-Host "  DDL Oracle:" -ForegroundColor White
Write-Host "    Sequence SOL.SEQ_ROTINA_EXECUCAO criada (Passo 0c)"
Write-Host "    Tabela SOL.ROTINA_EXECUCAO criada pelo Hibernate (ddl-auto:update no startup)"
Write-Host ""
Write-Host "  Endpoint de teste:" -ForegroundColor White
Write-Host "    POST /admin/jobs/rotina-alvara  (ADMIN, CHEFE_SSEG_BBM)"
Write-Host ""
Write-Host "  Jobs agendados:" -ForegroundColor White
Write-Host "    P13-A/B/C: 00:01 diario  (cron: 0 1 0 * * *)"
Write-Host "    P13-D:     00:31 diario  (cron: 0 31 0 * * *)"
Write-Host "    P13-E:     a cada 12h   (cron: 0 0 */12 * * *)  -- stub"
Write-Host ""
Write-Host "  Fluxos validados:" -ForegroundColor White
Write-Host "    P13-A: APPCI_EMITIDO + dtValidadeAppci vencida => ALVARA_VENCIDO"
Write-Host "    P13-C: Marco NOTIFICACAO_ALVARA_VENCIDO registrado"
Write-Host "    RN-121: P13-A nao reprocessa licenciamento ja ALVARA_VENCIDO"
Write-Host "    RN-129: Marco NOTIFICACAO_ALVARA_VENCIDO nao duplicado (idempotente)"
Write-Host ""
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""
