###############################################################################
# sprint-f2-deploy.ps1 -- Sprint F2: Modulo de Licenciamentos
# SOL CBM-RS -- Corpo de Bombeiros Militar do Rio Grande do Sul
#
# O que este script faz:
#   1. Verifica pre-requisitos (Node.js, npm, servico SOL-Nginx)
#   2. Verifica que os arquivos-fonte da Sprint F2 estao presentes
#   3. Executa npm install (sem novos pacotes — confirmacao de integridade)
#   4. Compila o Angular em modo producao (ng build --configuration production)
#   5. Copia o nginx.conf e reinicia o servico SOL-Nginx
#   6. Verifica HTTP 200 no frontend e saude do backend
#   7. Exibe sumario final
#
# Arquivos Angular adicionados pela Sprint F2:
#   src/app/core/models/licenciamento.model.ts
#   src/app/core/services/licenciamento.service.ts
#   src/app/pages/licenciamentos/licenciamentos.component.ts
#   src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts
#   src/app/app.routes.ts  (modificado — rotas reais substituem placeholder NotFound)
#
# Prerequisitos no servidor:
#   - Node.js 20+ instalado (node e npm no PATH)
#   - Servico SOL-Nginx instalado e configurado (sprint F1 concluida)
#   - Servico SOL-Backend em execucao
#
# Execucao:
#   powershell -ExecutionPolicy Bypass -File C:\SOL\infra\scripts\sprint-f2-deploy.ps1
#
# Estimativa de tempo: 3 a 5 minutos (build Angular)
###############################################################################

param(
    [string]$FrontendDir  = "C:\SOL\frontend",
    [string]$NginxConfDir = "C:\SOL\infra\nginx\nginx-1.26.2\conf",
    [string]$NginxSrcConf = "C:\SOL\infra\nginx\nginx.conf",
    [string]$NginxExe     = "C:\SOL\infra\nginx\nginx-1.26.2\nginx.exe",
    [string]$DistDir      = "C:\SOL\frontend\dist\sol-frontend\browser",
    [string]$LogFile      = "C:\SOL\logs\sprint-f2-deploy.log",
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
Write-Host "  SOL CBM-RS -- Sprint F2: Modulo de Licenciamentos" -ForegroundColor Magenta
Write-Host "  Inicio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

###############################################################################
Write-Step 1 "Verificacao de pre-requisitos"

try {
    $nodeVer = & node --version 2>&1
    Write-OK "Node.js: $nodeVer"
} catch {
    Write-ERR "Node.js nao encontrado no PATH."
}

try {
    $npmVer = & npm --version 2>&1
    Write-OK "npm: v$npmVer"
} catch {
    Write-ERR "npm nao encontrado."
}

if (Test-Path $FrontendDir) {
    Write-OK "Diretorio frontend: $FrontendDir"
} else {
    Write-ERR "Diretorio nao encontrado: $FrontendDir"
}

$nginxSvc = Get-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
if ($nginxSvc) {
    Write-OK "Servico $NginxSvcName encontrado (Status: $($nginxSvc.Status))"
} else {
    Write-ERR "Servico $NginxSvcName nao encontrado. Execute 04-nginx.ps1 e sprint-f1-deploy.ps1 primeiro."
}

if ($err -gt 0) {
    Write-Host "`n[ABORTANDO] $err erro(s) de prerequisito. Corrija antes de prosseguir." -ForegroundColor Red
    exit 1
}

###############################################################################
Write-Step 2 "Verificacao dos arquivos-fonte da Sprint F2"

$f2Files = @(
    "$FrontendDir\src\app\core\models\licenciamento.model.ts",
    "$FrontendDir\src\app\core\services\licenciamento.service.ts",
    "$FrontendDir\src\app\pages\licenciamentos\licenciamentos.component.ts",
    "$FrontendDir\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts",
    "$FrontendDir\src\app\app.routes.ts"
)

$allPresent = $true
foreach ($f in $f2Files) {
    if (Test-Path $f) {
        Write-OK "Presente: $(Split-Path $f -Leaf)"
    } else {
        Write-ERR "AUSENTE : $f"
        $allPresent = $false
    }
}

# Verifica que app.routes.ts contem a rota real (nao o placeholder NotFound)
$routesContent = Get-Content "$FrontendDir\src\app\app.routes.ts" -Raw
if ($routesContent -match "licenciamentos\.component") {
    Write-OK "app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent"
} else {
    Write-ERR "app.routes.ts: rota /licenciamentos ainda aponta para NotFoundComponent (placeholder nao substituido)"
    $allPresent = $false
}

if (-not $allPresent) {
    Write-Host "`n[ABORTANDO] Arquivos-fonte da Sprint F2 ausentes ou incorretos." -ForegroundColor Red
    exit 1
}

###############################################################################
Write-Step 3 "npm install (verificacao de integridade das dependencias)"

Write-Log "Executando: npm install em $FrontendDir"
Push-Location $FrontendDir
$ErrorActionPreference = "Continue"
& npm install
$npmExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($npmExit -eq 0) {
    Write-OK "npm install concluido"
} else {
    Write-ERR "npm install falhou (exit code $npmExit)"
    Pop-Location; exit 1
}
Pop-Location

###############################################################################
Write-Step 4 "Build Angular (modo producao)"

Write-Log "Executando: npm run build:prod em $FrontendDir"
Write-Log "Este processo pode levar de 2 a 5 minutos..."
Push-Location $FrontendDir
$ErrorActionPreference = "Continue"
& npm run build:prod
$buildExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($buildExit -ne 0) {
    Write-ERR "Build Angular falhou (exit code $buildExit)"
    Pop-Location; exit 1
}
Write-OK "Build Angular concluido"
Pop-Location

if (Test-Path "$DistDir\index.html") {
    $buildFiles = (Get-ChildItem $DistDir -Recurse | Measure-Object).Count
    Write-OK "Dist gerado: $DistDir ($buildFiles arquivos)"
} else {
    Write-ERR "index.html nao encontrado em $DistDir apos o build"
    exit 1
}

###############################################################################
Write-Step 5 "Atualizar configuracao do Nginx e reiniciar servico"

if (Test-Path $NginxSrcConf) {
    if (Test-Path $NginxConfDir) {
        Copy-Item -Path $NginxSrcConf -Destination "$NginxConfDir\nginx.conf" -Force
        Write-OK "nginx.conf copiado para $NginxConfDir"
    } else {
        Write-WARN "Diretorio $NginxConfDir nao encontrado -- usando configuracao existente"
    }
} else {
    Write-WARN "Arquivo $NginxSrcConf nao encontrado -- usando configuracao existente"
}

if (Test-Path $NginxExe) {
    try {
        $testResult = & $NginxExe -t 2>&1
        Write-Log "nginx -t: $testResult"
        if ($testResult -match "successful") { Write-OK "Sintaxe nginx.conf: OK" }
        else { Write-WARN "Resultado nginx -t: $testResult" }
    } catch {
        Write-WARN "Nao foi possivel testar nginx.conf: $_"
    }
} else {
    Write-WARN "nginx.exe nao encontrado em $NginxExe -- pulando teste de sintaxe"
}

try {
    if ($nginxSvc.Status -eq "Running") {
        Write-Log "Parando $NginxSvcName..."
        Stop-Service -Name $NginxSvcName -Force
        Start-Sleep -Seconds 2
    }
    Write-Log "Iniciando $NginxSvcName..."
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

try {
    $resp = Invoke-WebRequest -Uri "http://localhost:$HttpPort/" -TimeoutSec 10 -UseBasicParsing
    if ($resp.StatusCode -eq 200) {
        Write-OK "http://localhost:$HttpPort/ -- HTTP $($resp.StatusCode)"
        if ($resp.Content -match "SOL") {
            Write-OK "Conteudo HTML contem 'SOL' -- Angular SPA carregado"
        } else {
            Write-WARN "HTML nao contem 'SOL' -- verifique o build"
        }
    } else {
        Write-WARN "http://localhost:$HttpPort/ retornou HTTP $($resp.StatusCode)"
    }
} catch {
    Write-ERR "Nao foi possivel acessar http://localhost:$HttpPort/ : $_"
}

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
Write-Host "  SUMARIO -- Sprint F2" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  OK      : $ok"   -ForegroundColor Green
Write-Host "  AVISOS  : $warn" -ForegroundColor $(if ($warn -gt 0) { "Yellow" } else { "Green" })
Write-Host "  ERROS   : $err"  -ForegroundColor $(if ($err  -gt 0) { "Red"    } else { "Green" })
Write-Host "  Fim     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

if ($err -eq 0) {
    Write-Host ""
    Write-Host "  Sprint F2 implantada com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Frontend:       http://localhost:$HttpPort/" -ForegroundColor Cyan
    Write-Host "  Licenciamentos: http://localhost:$HttpPort/app/licenciamentos" -ForegroundColor Cyan
    Write-Host "  API:            http://localhost:$HttpPort/api/licenciamentos/meus" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  PROXIMO PASSO: Sprint F3 -- Wizard de Solicitacao de Licenciamento" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  $err erro(s) encontrado(s). Revise os itens [ERRO] acima." -ForegroundColor Red
}
Write-Host ""
