#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 2 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia o servico,
    aguarda inicializacao e executa smoke tests nos endpoints da Sprint 2.

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend (deve estar previamente registrado com nssm ou sc.exe)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuracoes
# ---------------------------------------------------------------------------
$ServiceName  = "SOL-Backend"
$JavaHome     = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$ProjectRoot  = "C:\SOL\backend"
$BaseUrl      = "http://localhost:8080/api"
$HealthUrl    = "$BaseUrl/health"
$WaitSeconds  = 30
$MavenOpts    = "-Dmaven.test.skip=true -q"

# ---------------------------------------------------------------------------
# Funcoes auxiliares
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Mensagem)
    Write-Host ""
    Write-Host "===> $Mensagem" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Mensagem)
    Write-Host "  [OK] $Mensagem" -ForegroundColor Green
}

function Write-FAIL {
    param([string]$Mensagem)
    Write-Host "  [FALHA] $Mensagem" -ForegroundColor Red
}

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Descricao,
        [string]$Token = ""
    )
    try {
        $headers = @{ "Accept" = "application/json" }
        if ($Token -ne "") {
            $headers["Authorization"] = "Bearer $Token"
        }
        $response = Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -in @(200, 201, 204)) {
            Write-OK "$Descricao -- HTTP $($response.StatusCode)"
            return $true
        } else {
            Write-FAIL "$Descricao -- HTTP $($response.StatusCode)"
            return $false
        }
    } catch {
        Write-FAIL "$Descricao -- Erro: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# 1. Parar o servico
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceName"

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else {
    Write-Host "  Servico nao estava em execucao ou nao existe -- continuando" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 2. Compilar com Maven
# ---------------------------------------------------------------------------
Write-Step "Compilando com Maven (JAVA_HOME=$JavaHome)"

$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"

$mvnWrapper = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvnWrapper)) {
    $mvnWrapper = "mvn"
}

$buildArgs = "clean package $MavenOpts"
Write-Host "  Executando: $mvnWrapper $buildArgs" -ForegroundColor DarkGray

Push-Location $ProjectRoot
try {
    & cmd /c "$mvnWrapper $buildArgs"
    if ($LASTEXITCODE -ne 0) {
        throw "Maven falhou com codigo de saida $LASTEXITCODE"
    }
    Write-OK "Build concluido com sucesso"
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 3. Reiniciar o servico
# ---------------------------------------------------------------------------
Write-Step "Reiniciando servico $ServiceName"

if ($null -ne $svc) {
    Start-Service -Name $ServiceName
    Write-OK "Servico iniciado"
} else {
    Write-Host "  Servico nao registrado. Iniciando JAR diretamente (modo dev)..." -ForegroundColor Yellow
    $jarPath = Get-ChildItem "$ProjectRoot\target\*.jar" | Where-Object { $_.Name -notlike "*sources*" } | Select-Object -First 1
    if ($null -eq $jarPath) {
        throw "JAR nao encontrado em $ProjectRoot\target\"
    }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
                  -ArgumentList "-jar `"$($jarPath.FullName)`"" `
                  -WorkingDirectory $ProjectRoot `
                  -NoNewWindow
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
for ($i = 1; $i -le 5; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            Write-OK "Aplicacao saudavel (tentativa $i)"
            $healthy = $true
            break
        }
    } catch {
        Write-Host "  Tentativa $i falhou -- aguardando 10s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}

if (-not $healthy) {
    Write-FAIL "Aplicacao nao respondeu ao health check apos 5 tentativas"
    exit 1
}

# ---------------------------------------------------------------------------
# 6. Smoke tests dos endpoints da Sprint 2
#    Nota: endpoints protegidos exigem JWT valido. Neste script usamos
#    uma variavel de ambiente SOL_ADMIN_TOKEN (token Keycloak do admin)
#    pre-configurada no ambiente de CI/CD.
# ---------------------------------------------------------------------------
Write-Step "Smoke tests dos endpoints"

$token = $env:SOL_ADMIN_TOKEN
if ([string]::IsNullOrEmpty($token)) {
    Write-Host "  Variavel SOL_ADMIN_TOKEN nao definida -- smoke tests de endpoints protegidos serao ignorados" -ForegroundColor Yellow
    $token = ""
}

$resultados = [System.Collections.Generic.List[bool]]::new()

# Health (publico)
$resultados.Add((Test-Endpoint -Url $HealthUrl -Descricao "GET /health (publico)"))

# Endpoints autenticados
if ($token -ne "") {
    $resultados.Add((Test-Endpoint -Url "$BaseUrl/usuarios"       -Descricao "GET /api/usuarios"       -Token $token))
    $resultados.Add((Test-Endpoint -Url "$BaseUrl/licenciamentos" -Descricao "GET /api/licenciamentos" -Token $token))
} else {
    Write-Host "  [AVISO] Testes de /usuarios e /licenciamentos ignorados (sem token)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 7. Resultado final
# ---------------------------------------------------------------------------
Write-Step "Resultado final"

$falhas = $resultados | Where-Object { $_ -eq $false }
$total  = $resultados.Count

if ($falhas.Count -eq 0) {
    Write-Host ""
    Write-Host "  Deploy da Sprint 2 concluido com sucesso! ($total/$total testes OK)" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "  Deploy concluido com $($falhas.Count) falha(s) de $total testes." -ForegroundColor Red
    exit 1
}
