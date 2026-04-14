# =============================================================================
# sync-f3-to-server.ps1
# Copia todos os arquivos da Sprint F3 de C:\SOL para Y:\ (servidor)
#
# Execute este script na maquina local ANTES de rodar sprint-f3-deploy.ps1
# no servidor. Requer que Y:\ esteja mapeado para C:\SOL no servidor.
# =============================================================================

$ErrorActionPreference = "Continue"
$erros = 0

function OK([string]$m)   { Write-Host "  [OK]  $m" -ForegroundColor Green }
function FAIL([string]$m) { Write-Host "  [ERRO] $m" -ForegroundColor Red; $erros++ }
function INFO([string]$m) { Write-Host "  [INFO] $m" -ForegroundColor Yellow }
function CABECALHO([string]$t) {
  Write-Host ""
  Write-Host "─────────────────────────────────────────────────" -ForegroundColor Cyan
  Write-Host "  $t" -ForegroundColor Cyan
  Write-Host "─────────────────────────────────────────────────" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SYNC Sprint F3 — C:\SOL  →  Y:\" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

# Verificar Y:\
if (-not (Test-Path "Y:\")) {
  FAIL "Drive Y:\ nao acessivel. Mapeie o drive de rede antes de continuar."
  exit 1
}
OK "Drive Y:\ acessivel"

# Lista de arquivos a copiar: origem (C:\SOL) -> destino (Y:\)
$arquivos = @(
  @{
    Origem  = "C:\SOL\frontend\src\app\core\models\licenciamento-create.model.ts"
    Destino = "Y:\frontend\src\app\core\models\licenciamento-create.model.ts"
    Desc    = "Novo modelo LicenciamentoCreateDTO"
  },
  @{
    Origem  = "C:\SOL\frontend\src\app\core\models\licenciamento.model.ts"
    Destino = "Y:\frontend\src\app\core\models\licenciamento.model.ts"
    Desc    = "Modelo atualizado (23 status)"
  },
  @{
    Origem  = "C:\SOL\frontend\src\app\core\services\licenciamento.service.ts"
    Destino = "Y:\frontend\src\app\core\services\licenciamento.service.ts"
    Desc    = "Service com criar() e submeter()"
  },
  @{
    Origem  = "C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts"
    Destino = "Y:\frontend\src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts"
    Desc    = "Wizard 4 passos (componente novo)"
  },
  @{
    Origem  = "C:\SOL\frontend\src\app\app.routes.ts"
    Destino = "Y:\frontend\src\app\app.routes.ts"
    Desc    = "Rotas atualizadas (/novo antes de /:id)"
  },
  @{
    Origem  = "C:\SOL\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts"
    Destino = "Y:\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts"
    Desc    = "Lista de licenciamentos (botao ativo)"
  },
  @{
    Origem  = "C:\SOL\infra\scripts\sprint-f3-deploy.ps1"
    Destino = "Y:\infra\scripts\sprint-f3-deploy.ps1"
    Desc    = "Script de deploy Sprint F3"
  }
)

CABECALHO "Copiando arquivos-fonte"

foreach ($arq in $arquivos) {
  if (-not (Test-Path $arq.Origem)) {
    FAIL "Origem nao encontrada: $($arq.Origem)"
    continue
  }
  $dir = Split-Path $arq.Destino -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    INFO "Diretorio criado: $dir"
  }
  Copy-Item -Path $arq.Origem -Destination $arq.Destino -Force
  if (Test-Path $arq.Destino) {
    OK "$($arq.Desc)"
    OK "   $($arq.Origem) -> $($arq.Destino)"
  } else {
    FAIL "Falha ao copiar: $($arq.Origem)"
  }
}

# Tambem copiar o launcher
CABECALHO "Criando launcher run-sprint-f3.ps1 em Y:\logs\"

$launcherContent = @'
$out = "C:\SOL\logs\sprint-f3-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f3-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f3-run-exitcode.txt" -Encoding UTF8
'@

$launcherDest = "Y:\logs\run-sprint-f3.ps1"
$logsDir = "Y:\logs"
if (-not (Test-Path $logsDir)) {
  New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$launcherContent | Out-File -FilePath $launcherDest -Encoding UTF8 -Force
if (Test-Path $launcherDest) {
  OK "Launcher criado: $launcherDest"
} else {
  FAIL "Falha ao criar launcher em $launcherDest"
}

# Resumo
Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
if ($erros -eq 0) {
  Write-Host "  SYNC CONCLUIDO COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Proximo passo: execute no servidor (ou via Claude Code):" -ForegroundColor White
  Write-Host "    C:\SOL\logs\run-sprint-f3.ps1" -ForegroundColor White
} else {
  Write-Host "  SYNC CONCLUIDO COM $erros ERRO(S)" -ForegroundColor Red
}
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
