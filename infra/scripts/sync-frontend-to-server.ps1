###############################################################################
# sync-frontend-to-server.ps1
# Copia corretamente os arquivos da Sprint F1 da maquina local (C:\SOL)
# para o servidor (Y:\), corrigindo o problema de pastas duplicadas causado
# pelo Copy-Item -Recurse anterior.
#
# Execute na MAQUINA LOCAL (nao no servidor):
#   powershell -ExecutionPolicy Bypass -File sync-frontend-to-server.ps1
###############################################################################

param(
    [string]$LocalBase  = "C:\SOL\frontend",
    [string]$ServerBase = "Y:\frontend"
)

$ErrorActionPreference = "Stop"

function Write-OK   { param($m) Write-Host "[OK]   $m" -ForegroundColor Green  }
function Write-STEP { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }
function Write-INFO { param($m) Write-Host "[INFO] $m" -ForegroundColor White  }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Sincronizacao Sprint F1: Local -> Servidor" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Verificar acesso ao servidor
if (-not (Test-Path $ServerBase)) {
    Write-Host "[ERRO] Servidor nao acessivel em $ServerBase" -ForegroundColor Red
    exit 1
}
Write-OK "Servidor acessivel: $ServerBase"

###############################################################################
Write-STEP "1. Remover pastas duplicadas no servidor"

$duplicates = @(
    "$ServerBase\src\app\layout\layout",
    "$ServerBase\src\app\pages\dashboard\dashboard",
    "$ServerBase\src\app\pages\not-found\not-found",
    "$ServerBase\src\app\core\core",
    "$ServerBase\src\app\shared\shared"
)

foreach ($d in $duplicates) {
    if (Test-Path $d) {
        Remove-Item $d -Recurse -Force
        Write-OK "Removido: $d"
    }
}

###############################################################################
Write-STEP "2. Criar estrutura de diretorios no servidor"

$dirs = @(
    "$ServerBase\src\app\core\services",
    "$ServerBase\src\app\core\guards",
    "$ServerBase\src\app\layout\shell",
    "$ServerBase\src\app\shared\components\loading",
    "$ServerBase\src\app\shared\components\error-alert",
    "$ServerBase\src\app\pages\dashboard",
    "$ServerBase\src\app\pages\not-found"
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Write-INFO "Dir: $d"
}

###############################################################################
Write-STEP "3. Copiar arquivos de fonte (core, guards)"

$fileMappings = @(
    # core
    @{ Src = "src\app\core\services\auth.service.ts";          Dst = "src\app\core\services\auth.service.ts" },
    @{ Src = "src\app\core\guards\auth.guard.ts";              Dst = "src\app\core\guards\auth.guard.ts" },
    @{ Src = "src\app\core\guards\role.guard.ts";              Dst = "src\app\core\guards\role.guard.ts" },
    # layout
    @{ Src = "src\app\layout\shell\shell.component.ts";        Dst = "src\app\layout\shell\shell.component.ts" },
    # shared
    @{ Src = "src\app\shared\components\loading\loading.component.ts";         Dst = "src\app\shared\components\loading\loading.component.ts" },
    @{ Src = "src\app\shared\components\error-alert\error-alert.component.ts"; Dst = "src\app\shared\components\error-alert\error-alert.component.ts" },
    # pages
    @{ Src = "src\app\pages\dashboard\dashboard.component.ts"; Dst = "src\app\pages\dashboard\dashboard.component.ts" },
    @{ Src = "src\app\pages\not-found\not-found.component.ts"; Dst = "src\app\pages\not-found\not-found.component.ts" },
    @{ Src = "src\app\pages\home\home.component.ts";           Dst = "src\app\pages\home\home.component.ts" },
    # raiz do app
    @{ Src = "src\app\app.routes.ts";   Dst = "src\app\app.routes.ts" },
    @{ Src = "src\app\app.config.ts";   Dst = "src\app\app.config.ts" },
    @{ Src = "src\app\app.component.ts"; Dst = "src\app\app.component.ts" },
    @{ Src = "src\styles.scss";          Dst = "src\styles.scss" },
    @{ Src = "package.json";             Dst = "package.json" }
)

foreach ($m in $fileMappings) {
    $src = Join-Path $LocalBase $m.Src
    $dst = Join-Path $ServerBase $m.Dst
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-OK "$($m.Dst)"
    } else {
        Write-Host "[WARN] Arquivo local nao encontrado: $src" -ForegroundColor Yellow
    }
}

###############################################################################
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Sincronizacao concluida." -ForegroundColor Magenta
Write-Host "  Execute agora no SERVIDOR:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -Command `"& 'C:\SOL\infra\scripts\sprint-f1-deploy.ps1'`"" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host ""
