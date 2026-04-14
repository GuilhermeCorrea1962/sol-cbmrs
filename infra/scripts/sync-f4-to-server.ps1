# sync-f4-to-server.ps1
# Sincroniza os arquivos da Sprint F4 de C:\SOL para Y:\ (servidor).
# Executar na maquina local com Y:\ mapeado e acessivel.

$ErrorActionPreference = "Stop"

function Copiar([string]$origem, [string]$destino) {
  $dir = Split-Path $destino -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Copy-Item -Path $origem -Destination $destino -Force
  Write-Host "  [OK]  $destino" -ForegroundColor Green
}

# Verificar Y:\ acessivel
if (-not (Test-Path "Y:\")) {
  Write-Host "[ERRO] Drive Y:\ nao esta acessivel. Mapeie o drive e tente novamente." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==========================================================="
Write-Host "  SYNC F4 -C:\SOL -> Y:\"
Write-Host "==========================================================="
Write-Host ""

$base   = "C:\SOL\frontend\src\app"
$baseY  = "Y:\frontend\src\app"

# --- Novos arquivos F4 ---
Copiar "$base\core\models\analise.model.ts"                                                    "$baseY\core\models\analise.model.ts"
Copiar "$base\pages\analise\analise-fila\analise-fila.component.ts"                            "$baseY\pages\analise\analise-fila\analise-fila.component.ts"
Copiar "$base\pages\analise\licenciamento-analise\licenciamento-analise.component.ts"          "$baseY\pages\analise\licenciamento-analise\licenciamento-analise.component.ts"

# --- Arquivos atualizados F4 ---
Copiar "$base\core\services\licenciamento.service.ts"                                          "$baseY\core\services\licenciamento.service.ts"
Copiar "$base\app.routes.ts"                                                                   "$baseY\app.routes.ts"
Copiar "$base\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts"   "$baseY\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts"

# --- Scripts ---
Copiar "C:\SOL\infra\scripts\sprint-f4-deploy.ps1"   "Y:\infra\scripts\sprint-f4-deploy.ps1"
Copiar "C:\SOL\logs\run-sprint-f4.ps1"               "Y:\logs\run-sprint-f4.ps1"

Write-Host ""
Write-Host "  SYNC F4 CONCLUIDO -8 arquivos copiados para Y:\" -ForegroundColor Green
Write-Host ""
Write-Host "  Proximo passo: executar no servidor:" -ForegroundColor White
Write-Host "    C:\SOL\logs\run-sprint-f4.ps1" -ForegroundColor White
Write-Host ""
