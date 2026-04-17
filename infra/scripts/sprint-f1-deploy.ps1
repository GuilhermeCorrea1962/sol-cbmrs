###############################################################################
# sprint-f1-deploy.ps1 -- Sprint F1: Frontend Foundation
# SOL CBM-RS -- Corpo de Bombeiros Militar do Rio Grande do Sul
#
# O que este script faz:
#   1. Verifica pre-requisitos (Node.js, npm, servico SOL-Nginx)
#   2. Instala dependencias do Angular (incluindo Angular Material 18)
#   3. Compila o Angular em modo producao
#   4. Copia o nginx.conf da Sprint F1 para o diretorio do Nginx instalado
#   5. Testa a configuracao do Nginx e reinicia o servico SOL-Nginx
#   6. Verifica se o frontend esta respondendo em HTTP
#   7. Exibe sumario final
#
# Prerequisitos no servidor:
#   - Node.js 20+ instalado (node e npm no PATH)
#   - Angular CLI 18 instalado globalmente (npm install -g @angular/cli@18)
#   - Servico SOL-Nginx instalado (criado pelo script 04-nginx.ps1)
#   - Servico SOL-Backend em execucao (necessario para testar /api/)
#
# Execucao:
#   powershell -ExecutionPolicy Bypass -File sprint-f1-deploy.ps1
#
# Estimativa de tempo: 3 a 6 minutos (npm install + build Angular)
###############################################################################

param(
    [string]$FrontendDir  = "C:\SOL\frontend",
    [string]$NginxConfDir = "C:\SOL\infra\nginx\nginx-1.26.2\conf",
    [string]$NginxSrcConf = "C:\SOL\infra\nginx\nginx.conf",
    [string]$NginxExe     = "C:\SOL\infra\nginx\nginx-1.26.2\nginx.exe",
    [string]$DistDir      = "C:\SOL\frontend\dist\sol-frontend\browser",
    [string]$LogFile      = "C:\SOL\logs\sprint-f1-deploy.log",
    [string]$NginxSvcName = "SOL-Nginx",
    [int]   $HttpPort     = 80
)

$ErrorActionPreference = "Stop"
$ok   = 0
$err  = 0
$warn = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $(
        switch ($Level) {
            "OK"   { "Green"  }
            "ERRO" { "Red"    }
            "WARN" { "Yellow" }
            default{ "White"  }
        }
    )
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Step { param([int]$n, [string]$msg)
    Write-Host "`n=== [$n] $msg ===" -ForegroundColor Cyan
}
function Write-OK   { param($m) Write-Log $m "OK";   $script:ok++   }
function Write-ERR  { param($m) Write-Log $m "ERRO"; $script:err++  }
function Write-WARN { param($m) Write-Log $m "WARN"; $script:warn++ }

###############################################################################
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  SOL CBM-RS -- Sprint F1: Frontend Foundation" -ForegroundColor Magenta
Write-Host "  Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

###############################################################################
Write-Step 1 "Verificacao de pre-requisitos"

# Node.js
try {
    $nodeVer = & node --version 2>&1
    Write-OK "Node.js: $nodeVer"
} catch {
    Write-ERR "Node.js nao encontrado no PATH. Instale Node.js 20+ e adicione ao PATH."
}

# npm
try {
    $npmVer = & npm --version 2>&1
    Write-OK "npm: v$npmVer"
} catch {
    Write-ERR "npm nao encontrado. Verifique a instalacao do Node.js."
}

# Angular CLI
try {
    $ngVer = & ng version --skip-git 2>&1 | Select-String "Angular CLI"
    Write-OK "Angular CLI: $ngVer"
} catch {
    Write-WARN "Angular CLI global nao encontrado. Tentando com npx durante o build."
}

# Diretorio do frontend
if (Test-Path $FrontendDir) {
    Write-OK "Diretorio frontend: $FrontendDir"
} else {
    Write-ERR "Diretorio nao encontrado: $FrontendDir"
}

# Servico Nginx
$nginxSvc = Get-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
if ($nginxSvc) {
    Write-OK "Servico $NginxSvcName encontrado (Status: $($nginxSvc.Status))"
} else {
    Write-ERR "Servico $NginxSvcName nao encontrado. Execute 04-nginx.ps1 primeiro."
}

if ($err -gt 0) {
    Write-Host "`n[ABORTANDO] $err erro(s) de prerequisito detectado(s). Corrija antes de prosseguir." -ForegroundColor Red
    exit 1
}

###############################################################################
Write-Step 2 "npm install (Angular Material 18 + dependencias)"

Write-Log "Executando: npm install em $FrontendDir"
Push-Location $FrontendDir
# Nao usar try/catch com 2>&1|ForEach  -  o PS trata warnings de npm como erros
# com $ErrorActionPreference=Stop. Usamos $LASTEXITCODE para detectar falha real.
$ErrorActionPreference = "Continue"
& npm install
$npmExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($npmExit -eq 0) {
    Write-OK "npm install concluido com sucesso"
} else {
    Write-ERR "npm install falhou (exit code $npmExit)"
    Pop-Location
    exit 1
}
Pop-Location

###############################################################################
Write-Step 3 "Build Angular (modo producao)"

Write-Log "Executando: npm run build:prod em $FrontendDir"
Write-Log "Este processo pode levar de 2 a 5 minutos..."
Push-Location $FrontendDir
$ErrorActionPreference = "Continue"
& npm run build:prod
$buildExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($buildExit -ne 0) {
    Write-ERR "Build Angular falhou (exit code $buildExit)"
    Pop-Location
    exit 1
}
Write-OK "Build Angular concluido"
Pop-Location

# Verificar se o dist foi gerado
if (Test-Path "$DistDir\index.html") {
    $buildFiles = (Get-ChildItem $DistDir -Recurse | Measure-Object).Count
    Write-OK "Dist gerado: $DistDir ($buildFiles arquivos)"
} else {
    Write-ERR "Arquivo index.html nao encontrado em $DistDir apos o build"
    exit 1
}

###############################################################################
Write-Step 4 "Atualizar configuracao do Nginx"

if (Test-Path $NginxSrcConf) {
    if (Test-Path $NginxConfDir) {
        Copy-Item -Path $NginxSrcConf -Destination "$NginxConfDir\nginx.conf" -Force
        Write-OK "nginx.conf copiado para $NginxConfDir"
    } else {
        Write-WARN "Diretorio $NginxConfDir nao encontrado -- usando configuracao existente no servico"
    }
} else {
    Write-WARN "Arquivo $NginxSrcConf nao encontrado -- usando configuracao existente no servico"
}

# Testar sintaxe do nginx.conf
if (Test-Path $NginxExe) {
    try {
        $testResult = & $NginxExe -t 2>&1
        Write-Log "nginx -t: $testResult"
        if ($testResult -match "successful") {
            Write-OK "Sintaxe do nginx.conf: OK"
        } else {
            Write-WARN "Resultado do teste de sintaxe: $testResult"
        }
    } catch {
        Write-WARN "Nao foi possivel testar o nginx.conf: $_"
    }
} else {
    Write-WARN "nginx.exe nao encontrado em $NginxExe -- pulando teste de sintaxe"
}

###############################################################################
Write-Step 5 "Reiniciar servico SOL-Nginx"

try {
    if ($nginxSvc.Status -eq "Running") {
        Write-Log "Parando servico SOL-Nginx..."
        Stop-Service -Name $NginxSvcName -Force
        Start-Sleep -Seconds 2
    }
    Write-Log "Iniciando servico SOL-Nginx..."
    Start-Service -Name $NginxSvcName
    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $NginxSvcName
    if ($svc.Status -eq "Running") {
        Write-OK "Servico ${NginxSvcName}: RUNNING"
    } else {
        Write-ERR "Servico $NginxSvcName nao iniciou (Status: $($svc.Status))"
    }
} catch {
    Write-ERR "Erro ao reiniciar ${NginxSvcName}: $_"
}

###############################################################################
Write-Step 6 "Verificacao HTTP"

Start-Sleep -Seconds 2

# Frontend (raiz)
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:$HttpPort/" -TimeoutSec 10 -UseBasicParsing
    if ($resp.StatusCode -eq 200) {
        Write-OK "http://localhost:$HttpPort/ -- HTTP $($resp.StatusCode)"
        if ($resp.Content -match "SOL") {
            Write-OK "Conteudo HTML contem 'SOL' -- Angular SPA carregado"
        } else {
            Write-WARN "HTML retornado nao contem 'SOL' -- verifique o build"
        }
    } else {
        Write-WARN "http://localhost:$HttpPort/ retornou HTTP $($resp.StatusCode)"
    }
} catch {
    Write-ERR "Nao foi possivel acessar http://localhost:$HttpPort/ : $_"
}

# Verificar que /api/ ainda proxeia para o backend
try {
    $health = Invoke-RestMethod -Uri "http://localhost:$HttpPort/api/actuator/health" -TimeoutSec 10
    if ($health.status -eq "UP") {
        Write-OK "http://localhost:$HttpPort/api/actuator/health -- Backend UP"
    } else {
        Write-WARN "Backend health: $($health.status)"
    }
} catch {
    Write-WARN "Proxy /api/ nao respondeu (verifique se SOL-Backend esta em execucao): $_"
}

###############################################################################
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  SUMARIO -- Sprint F1" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  OK      : $ok"   -ForegroundColor Green
Write-Host "  AVISOS  : $warn" -ForegroundColor $(if ($warn -gt 0) { "Yellow" } else { "Green" })
Write-Host "  ERROS   : $err"  -ForegroundColor $(if ($err  -gt 0) { "Red"    } else { "Green" })
Write-Host "  Fim     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

if ($err -eq 0) {
    Write-Host ""
    Write-Host "  Sprint F1 implantada com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Frontend:  http://localhost:$HttpPort/" -ForegroundColor Cyan
    Write-Host "  API:       http://localhost:$HttpPort/api/" -ForegroundColor Cyan
    Write-Host "  Keycloak:  http://localhost:8180/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  PROXIMO PASSO: Sprint F2 -- Modulo de Licenciamentos (CIDADAO)" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  $err erro(s) encontrado(s). Revise os itens [ERRO] acima." -ForegroundColor Red
}
Write-Host ""
