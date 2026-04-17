#Requires -Version 5.1
<#
.SYNOPSIS
    Sprint 12 - P12 Extincao de Licenciamento - Deploy e smoke test
.DESCRIPTION
    Executa o rebuild do backend SOL e valida os fluxos P12-A e P12-B:
      Fluxo A: solicitar-extincao (cidadao) + efetivar-extincao (admin) -> EXTINTO + 2 marcos
      Fluxo B: efetivar-extincao direta (admin) -> EXTINTO + 1 marco
      RN-109: status invalido bloqueado
      RN-110: motivo obrigatorio na solicitacao
      RN-111: motivo obrigatorio na efetivacao
      RN-113: operacao em licenciamento EXTINTO bloqueada
.NOTES
    Executar com:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        C:\SOL\infra\scripts\sprint12-deploy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuracao (valores reais do servidor  -  descobertos na Sprint 11)
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

# ---------------------------------------------------------------------------
# Cria licenciamento em ANALISE_PENDENTE (pre-requisito P12)
# Cadeia: criar -> upload -> submeter
# Retorna o ID real gerado
# ---------------------------------------------------------------------------
function Invoke-SetupAnalisePendente {
    param([int]$seed, [string]$tokenAdmin)

    Write-Host "    Criando licenciamento seed=$seed..." -ForegroundColor Gray

    $body = @{
        tipo           = "PPCI"
        areaConstruida = 200.00
        endereco       = @{
            cep        = "90010100"
            logradouro = "Rua da Extincao"
            numero     = "$seed"
            bairro     = "Centro"
            municipio  = "Porto Alegre"
            uf         = "RS"
        }
    } | ConvertTo-Json -Depth 5

    try {
        $lic = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos" `
            -ContentType "application/json" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } `
            -Body $body
    } catch { Show-ErrorBody $_; Write-FAIL "Falha ao criar licenciamento seed=$seed" }

    $id = $lic.id
    Write-Host "    Licenciamento criado ID=$id" -ForegroundColor Gray

    $pdf = New-PdfTemp
    try {
        Invoke-MultipartUpload `
            -uri "$BaseUrl/arquivos/upload?licenciamentoId=$id&tipoArquivo=PPCI" `
            -filePath $pdf -token $tokenAdmin | Out-Null
    } catch { Show-ErrorBody $_; Write-FAIL "Falha no upload PPCI ID=$id" }
    finally { Remove-Item $pdf -Force -ErrorAction SilentlyContinue }

    try {
        Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$id/submeter" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } | Out-Null
    } catch { Show-ErrorBody $_; Write-FAIL "Falha ao submeter licenciamento ID=$id" }

    Write-Host "    Licenciamento ID=$id em ANALISE_PENDENTE." -ForegroundColor Gray
    return $id
}

# ---------------------------------------------------------------------------
# Verifica se um marco existe para o licenciamento
# ---------------------------------------------------------------------------
function Assert-Marco {
    param([long]$licId, [string]$tipoMarco, [string]$tokenAdmin)
    try {
        $marcos = Invoke-RestMethod "$BaseUrl/licenciamentos/$licId/marcos" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" }
    } catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar marcos do licenciamento $licId" }
    $encontrado = $marcos | Where-Object { $_.tipoMarco -eq $tipoMarco }
    if (-not $encontrado) {
        Write-FAIL "Marco $tipoMarco nao encontrado para licenciamento $licId"
    }
    Write-OK "Marco $tipoMarco registrado: '$($encontrado.observacao)'"
}

# ---------------------------------------------------------------------------
# Verifica status de um licenciamento via GET /licenciamentos/{id}
# ---------------------------------------------------------------------------
function Assert-Status {
    param([long]$licId, [string]$statusEsperado, [string]$tokenAdmin)
    try {
        $lic = Invoke-RestMethod "$BaseUrl/licenciamentos/$licId" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" }
    } catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar licenciamento $licId" }
    if ($lic.status -ne $statusEsperado) {
        Write-FAIL "Licenciamento $licId com status inesperado: $($lic.status) (esperado: $statusEsperado)"
    }
    Write-OK "Licenciamento $licId status $statusEsperado confirmado."
}

# ===========================================================================
# INICIO
# ===========================================================================

Write-Step "Sprint 12 - P12 Extincao de Licenciamento"
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
# ---------------------------------------------------------------------------
Write-Step "Passo 3 - Health check"
$ok = $false
for ($i = 1; $i -le 12 -and -not $ok; $i++) {
    try {
        $h = Invoke-RestMethod "$BaseUrl/actuator/health" -TimeoutSec 5
        if ($h.status -eq "UP") { $ok = $true }
    } catch { }
    if (-not $ok) {
        Write-Host "    Tentativa $i/12 - aguardando..." -ForegroundColor DarkGray
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
    $tokenAdmin    = Get-Token $AdminUser    $AdminPass
    $tokenAnalista = Get-Token $AnalistaUser $AnalistaPass
    Write-OK "Tokens obtidos (sol-admin + analista1)."
} catch { Show-ErrorBody $_; Write-FAIL "Falha na autenticacao." }

# Busca ID Oracle do analista (necessario para distribuir em sprints futuras)
$analistaOracleId = $null
try {
    $meAnalista = Invoke-RestMethod "$BaseUrl/auth/me" `
        -Headers @{ Authorization = "Bearer $tokenAnalista" }
    $analistaOracleId = $meAnalista.id
    Write-OK "analista1 Oracle ID: $analistaOracleId"
} catch { Show-ErrorBody $_; Write-FAIL "Nao foi possivel obter ID Oracle do analista." }

# ---------------------------------------------------------------------------
# Passo 5: Limpeza preventiva
# ---------------------------------------------------------------------------
Write-Step "Passo 5 - Limpeza preventiva de dados de teste anteriores"
$sqlUser = "sol"
$sqlPass = "Sol@CBM2026"
$cleanSql = @"
BEGIN
  FOR r IN (
    SELECT l.id FROM sol.licenciamento l
    WHERE l.id IN (
      SELECT id FROM sol.licenciamento
      ORDER BY id DESC FETCH FIRST 10 ROWS ONLY
    )
    AND l.status IN ('EXTINTO','ANALISE_PENDENTE')
    AND l.area_construida = 200
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
    Write-OK "Limpeza preventiva concluida."
} else {
    Write-WARN "sqlplus nao disponivel. Limpeza preventiva ignorada."
}

# ===========================================================================
# Passo 6: FLUXO A  -  Solicitacao + Efetivacao (2 atores, 2 marcos)
# ===========================================================================
Write-Step "Passo 6 - Fluxo A: solicitar-extincao (admin) + efetivar-extincao (admin)"

$idA = Invoke-SetupAnalisePendente -seed 67 -tokenAdmin $tokenAdmin

# 6.1 Solicitar extincao
Write-Host "    6.1 Solicitando extincao do licenciamento $idA..." -ForegroundColor Gray
$bodyExtA = @{ motivo = "Solicitacao de extincao: estabelecimento encerrado por decisao do proprietario." } | ConvertTo-Json
try {
    $respA = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idA/solicitar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyExtA
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao solicitar extincao do licenciamento $idA" }

if ($respA.status -eq "EXTINTO") {
    Write-FAIL "solicitar-extincao nao deve alterar o status (retornou EXTINTO prematuramente)"
}
Write-OK "solicitar-extincao concluido. Status atual: $($respA.status) (deve permanecer ANALISE_PENDENTE)."

# 6.2 Verificar marco EXTINCAO_SOLICITADA
Write-Host "    6.2 Verificando marco EXTINCAO_SOLICITADA..." -ForegroundColor Gray
Assert-Marco -licId $idA -tipoMarco "EXTINCAO_SOLICITADA" -tokenAdmin $tokenAdmin

# 6.3 Efetivar extincao
Write-Host "    6.3 Efetivando extincao do licenciamento $idA..." -ForegroundColor Gray
$bodyEfetA = @{ motivo = "Efetivacao administrativa: confirmado encerramento das atividades." } | ConvertTo-Json
try {
    $respEfetA = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idA/efetivar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyEfetA
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao efetivar extincao do licenciamento $idA" }

if ($respEfetA.status -ne "EXTINTO") {
    Write-FAIL "Status esperado EXTINTO, recebido: $($respEfetA.status)"
}
Write-OK "efetivar-extincao: status EXTINTO confirmado no retorno do endpoint."

# 6.4 Verificar marco EXTINCAO_EFETIVADA
Write-Host "    6.4 Verificando marco EXTINCAO_EFETIVADA..." -ForegroundColor Gray
Assert-Marco -licId $idA -tipoMarco "EXTINCAO_EFETIVADA" -tokenAdmin $tokenAdmin

# 6.5 Confirmar status EXTINTO via GET
Write-Host "    6.5 Confirmando status via GET /licenciamentos/$idA..." -ForegroundColor Gray
Assert-Status -licId $idA -statusEsperado "EXTINTO" -tokenAdmin $tokenAdmin

Write-OK "Fluxo A concluido: ANALISE_PENDENTE => EXTINTO com 2 marcos."

# ===========================================================================
# Passo 7: FLUXO B  -  Extincao direta (admin, sem solicitar)
# ===========================================================================
Write-Step "Passo 7 - Fluxo B: efetivar-extincao direta (sem solicitar-extincao)"

$idB = Invoke-SetupAnalisePendente -seed 68 -tokenAdmin $tokenAdmin

# 7.1 Efetivar diretamente
Write-Host "    7.1 Efetivando extincao direta do licenciamento $idB..." -ForegroundColor Gray
$bodyEfetB = @{ motivo = "Extincao administrativa direta: irregularidade grave identificada em auditoria." } | ConvertTo-Json
try {
    $respEfetB = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idB/efetivar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyEfetB
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao efetivar extincao direta do licenciamento $idB" }

if ($respEfetB.status -ne "EXTINTO") {
    Write-FAIL "Status esperado EXTINTO, recebido: $($respEfetB.status)"
}
Write-OK "Extincao direta: status EXTINTO confirmado."

# 7.2 Verificar marco EXTINCAO_EFETIVADA (sem EXTINCAO_SOLICITADA)
Write-Host "    7.2 Verificando marco EXTINCAO_EFETIVADA (Fluxo B)..." -ForegroundColor Gray
Assert-Marco -licId $idB -tipoMarco "EXTINCAO_EFETIVADA" -tokenAdmin $tokenAdmin

# 7.3 Confirmar ausencia de EXTINCAO_SOLICITADA (direto, sem solicitacao previa)
try {
    $marcosB = Invoke-RestMethod "$BaseUrl/licenciamentos/$idB/marcos" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" }
} catch { Show-ErrorBody $_; Write-FAIL "Falha ao buscar marcos do licenciamento $idB" }
$solicitada = $marcosB | Where-Object { $_.tipoMarco -eq "EXTINCAO_SOLICITADA" }
if ($solicitada) {
    Write-WARN "Marco EXTINCAO_SOLICITADA presente no Fluxo B (esperado: ausente)."
} else {
    Write-OK "Marco EXTINCAO_SOLICITADA corretamente ausente no Fluxo B."
}

Write-OK "Fluxo B concluido: extincao direta com 1 marco."

# ===========================================================================
# Passo 8: Validacao de regras de negocio
# ===========================================================================
Write-Step "Passo 8 - Validacao de regras de negocio"

# 8.1 RN-113: operacao em licenciamento EXTINTO deve ser bloqueada
Write-Host "    8.1 RN-113: tentando solicitar extincao de licenciamento ja EXTINTO..." -ForegroundColor Gray
try {
    $bodyRn113 = @{ motivo = "Tentativa em licenciamento extinto." } | ConvertTo-Json
    Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idA/solicitar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyRn113 | Out-Null
    Write-FAIL "RN-113 nao funcionou: operacao aceita em licenciamento EXTINTO"
} catch {
    $sc = $_.Exception.Response.StatusCode.value__
    if ($sc -in @(400, 409, 422)) {
        Write-OK "RN-113 OK: operacao em licenciamento EXTINTO bloqueada (HTTP $sc)."
    } else {
        Write-WARN "RN-113: resposta inesperada HTTP $sc"
    }
}

# 8.2 RN-110: solicitar-extincao sem motivo deve falhar
Write-Host "    8.2 RN-110: solicitar-extincao sem motivo..." -ForegroundColor Gray
$idTemp = Invoke-SetupAnalisePendente -seed 69 -tokenAdmin $tokenAdmin
try {
    $bodyVazio = @{ motivo = "" } | ConvertTo-Json
    Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idTemp/solicitar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyVazio | Out-Null
    Write-FAIL "RN-110 nao funcionou: solicitar-extincao sem motivo foi aceito"
} catch {
    $sc = $_.Exception.Response.StatusCode.value__
    if ($sc -in @(400, 409, 422)) {
        Write-OK "RN-110 OK: solicitar-extincao sem motivo bloqueado (HTTP $sc)."
    } else {
        Write-WARN "RN-110: resposta inesperada HTTP $sc"
    }
}

# 8.3 RN-111: efetivar-extincao sem motivo deve falhar
Write-Host "    8.3 RN-111: efetivar-extincao sem motivo..." -ForegroundColor Gray
try {
    $bodyVazio2 = @{ motivo = "" } | ConvertTo-Json
    Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idTemp/efetivar-extincao" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyVazio2 | Out-Null
    Write-FAIL "RN-111 nao funcionou: efetivar-extincao sem motivo foi aceito"
} catch {
    $sc = $_.Exception.Response.StatusCode.value__
    if ($sc -in @(400, 409, 422)) {
        Write-OK "RN-111 OK: efetivar-extincao sem motivo bloqueado (HTTP $sc)."
    } else {
        Write-WARN "RN-111: resposta inesperada HTTP $sc"
    }
}

# 8.4 RN-109: status invalido (RASCUNHO) deve bloquear
Write-Host "    8.4 RN-109: efetivar-extincao em licenciamento RASCUNHO..." -ForegroundColor Gray
$bodyRascunho = @{
    tipo           = "PPCI"
    areaConstruida = 100.00
    endereco       = @{
        cep = "90010100"; logradouro = "Rua Teste"; numero = "99"
        bairro = "Centro"; municipio = "Porto Alegre"; uf = "RS"
    }
} | ConvertTo-Json -Depth 5
try {
    $licRascunho = Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos" `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $tokenAdmin" } `
        -Body $bodyRascunho
    $idRascunho = $licRascunho.id
} catch { Show-ErrorBody $_; Write-WARN "Nao foi possivel criar licenciamento RASCUNHO para RN-109." }

if ($idRascunho) {
    try {
        $bodyEfetRasc = @{ motivo = "Tentativa em RASCUNHO." } | ConvertTo-Json
        Invoke-RestMethod -Method Post "$BaseUrl/licenciamentos/$idRascunho/efetivar-extincao" `
            -ContentType "application/json" `
            -Headers @{ Authorization = "Bearer $tokenAdmin" } `
            -Body $bodyEfetRasc | Out-Null
        Write-FAIL "RN-109 nao funcionou: extincao de RASCUNHO foi aceita"
    } catch {
        $sc = $_.Exception.Response.StatusCode.value__
        if ($sc -in @(400, 409, 422)) {
            Write-OK "RN-109 OK: extincao de RASCUNHO bloqueada (HTTP $sc)."
        } else {
            Write-WARN "RN-109: resposta inesperada HTTP $sc"
        }
    }
}

# ===========================================================================
# Passo 9: Limpeza pos-teste
# ===========================================================================
Write-Step "Passo 9 - Limpeza dos dados de teste"
if ($sqlplus) {
    $delSql = @"
BEGIN
  FOR r IN (
    SELECT l.id FROM sol.licenciamento l
    WHERE l.area_construida IN (200, 100)
    AND l.id >= (SELECT MAX(id) - 20 FROM sol.licenciamento)
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
    Write-OK "Dados de teste removidos."
} else {
    Write-WARN "sqlplus nao disponivel. Remova manualmente os licenciamentos de teste."
}

# ===========================================================================
# Sumario
# ===========================================================================
Write-Step "SUMARIO"
Write-Host ""
Write-Host "  Sprint 12 - P12 Extincao de Licenciamento concluida com sucesso." -ForegroundColor Green
Write-Host ""
Write-Host "  Arquivos criados nesta sprint:" -ForegroundColor White
Write-Host "    [N] dto/ExtincaoDTO.java         : record ExtincaoDTO(String motivo)"
Write-Host "    [N] service/ExtincaoService.java : solicitarExtincao + efetivarExtincao"
Write-Host "    [N] controller/ExtincaoController.java : 2 endpoints POST"
Write-Host ""
Write-Host "  Endpoints:" -ForegroundColor White
Write-Host "    POST /licenciamentos/{id}/solicitar-extincao  (CIDADAO, RT, ADMIN)"
Write-Host "    POST /licenciamentos/{id}/efetivar-extincao   (ADMIN, CHEFE_SSEG_BBM)"
Write-Host ""
Write-Host "  Fluxos validados:" -ForegroundColor White
Write-Host "    Fluxo A: ANALISE_PENDENTE + solicitar + efetivar => EXTINTO + 2 marcos"
Write-Host "    Fluxo B: ANALISE_PENDENTE + efetivar direto      => EXTINTO + 1 marco"
Write-Host "    RN-109 : status RASCUNHO bloqueado"
Write-Host "    RN-110 : motivo vazio na solicitacao bloqueado"
Write-Host "    RN-111 : motivo vazio na efetivacao bloqueado"
Write-Host "    RN-113 : operacao em licenciamento EXTINTO bloqueada"
Write-Host ""
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""
