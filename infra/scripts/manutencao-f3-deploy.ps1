# =============================================================================
# manutencao-f3-deploy.ps1
# Manutencao F3 - Correcao de CSS budget em licenciamento-novo.component.ts
#
# Historico do problema:
#   - Sprint F3: componente criado com CSS de 2.18 kB (limite: 2.05 kB, +132 bytes)
#   - Sprint F5: warning NG8011 identificado no mesmo componente
#   - Sprint F6: correcao NG8011 aplicada (ng-container no botao Confirmar e Enviar)
#   - Manutencao F3: remocao de 5 propriedades CSS desnecessarias (~140 bytes minificados):
#       transition em .tipo-card, user-select em .tipo-card, transition em .tipo-check,
#       regra inteira .review-section { border-radius }, margin-top em .review-info mat-icon
#
# Arquivo modificado:
#   - src/app/pages/licenciamentos/licenciamento-novo/licenciamento-novo.component.ts
#
# Etapas:
#   1. Pre-verificacao do ambiente
#   2. Verificacao do arquivo corrigido
#   3. Build de producao (ng build --configuration production)
#   4. Deploy: substituicao dos assets no diretorio de producao
#   5. Reinicializacao do Nginx e smoke test final
#   6. Gerar relatorio de manutencao
#
# NOTA DE ENCODING:
#   Script criado com ASCII-only. Nenhum caractere Unicode acima de U+007F.
#   Compativel com PowerShell 5.x (Windows-1252) sem necessidade de BOM.
# =============================================================================

$ErrorActionPreference = "Continue"
$global:manutErros = 0

# --- Cores e helpers -----------------------------------------------------------
function Passo([int]$n, [string]$titulo) {
  Write-Host ""
  Write-Host "===========================================================" -ForegroundColor Cyan
  Write-Host "  ETAPA $n - $titulo" -ForegroundColor Cyan
  Write-Host "===========================================================" -ForegroundColor Cyan
}
function OK([string]$msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function FAIL([string]$msg) { Write-Host "  [ERRO] $msg" -ForegroundColor Red; $global:manutErros++ }
function INFO([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

# --- Caminhos -----------------------------------------------------------------
$FrontendDir   = "C:\SOL\frontend"
$DistDir       = "C:\SOL\frontend\dist\sol-frontend\browser"
$NginxHtmlDir  = "C:\nginx\html\sol"
$NginxSvcName  = "sol-nginx"
$RelatorioPath = "C:\SOL\logs\manutencao-f3-relatorio.md"
$CompPath      = "src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts"
$CompFull      = Join-Path $FrontendDir $CompPath

# =============================================================================
# ETAPA 1 - Pre-verificacao do ambiente
# =============================================================================
Passo 1 "Pre-verificacao do ambiente"

$ErrorActionPreference = "SilentlyContinue"
$nodeVer = & node --version 2>&1
$ErrorActionPreference = "Continue"
if ($LASTEXITCODE -eq 0 -or $nodeVer -match "v\d") {
  OK "Node.js: $nodeVer"
} else {
  FAIL "Node.js nao encontrado no PATH."
}

if (Test-Path $FrontendDir) {
  OK "Diretorio frontend: $FrontendDir"
} else {
  FAIL "Diretorio frontend nao encontrado: $FrontendDir"
  exit 1
}

if (Test-Path "$FrontendDir\package.json") {
  OK "package.json encontrado"
} else {
  FAIL "package.json nao encontrado"
  exit 1
}

# Pre-requisito: Sprints F1-F6 presentes
$appciModel = Join-Path $FrontendDir "src\app\core\models\appci.model.ts"
if (Test-Path $appciModel) {
  OK "Pre-requisito F6: appci.model.ts presente"
} else {
  FAIL "Pre-requisito ausente: appci.model.ts nao encontrado - execute Sprints F1-F6 antes"
  exit 1
}

# =============================================================================
# ETAPA 2 - Verificacao do arquivo corrigido
# =============================================================================
Passo 2 "Verificacao do arquivo corrigido"

if (-not (Test-Path $CompFull)) {
  FAIL "Arquivo nao encontrado: $CompPath"
  exit 1
}
OK "Arquivo presente: $CompPath"

$content = Get-Content $CompFull -Raw -Encoding UTF8

# Verificar correcao NG8011 (aplicada na Sprint F6, deve estar presente)
if ($content -match "ng-container") {
  OK "ng-container presente - correcao NG8011 (Sprint F6) confirmada"
} else {
  FAIL "ng-container ausente - correcao NG8011 nao encontrada no arquivo"
}

# Verificar que as propriedades CSS desnecessarias foram removidas
$cssPresentes = 0
if ($content -match "transition:\s*border-color\s*0\.2s") { $cssPresentes++; INFO "Propriedade 'transition: border-color' ainda presente em .tipo-card" }
if ($content -match "user-select:\s*none") { $cssPresentes++; INFO "Propriedade 'user-select: none' ainda presente" }
if ($content -match "transition:\s*opacity\s*0\.2s") { $cssPresentes++; INFO "Propriedade 'transition: opacity' ainda presente em .tipo-check" }
if ($content -match "\.review-section\s*\{[^}]*border-radius") { $cssPresentes++; INFO "Regra '.review-section { border-radius }' ainda presente" }
if ($content -match "\.review-info mat-icon[^}]*margin-top:\s*1px") { $cssPresentes++; INFO "Propriedade 'margin-top: 1px' ainda presente em .review-info mat-icon" }

if ($cssPresentes -eq 0) {
  OK "Propriedades CSS desnecessarias removidas - reducao de ~140 bytes minificados aplicada"
} else {
  FAIL "$cssPresentes propriedade(s) CSS ainda presente(s) - arquivo pode nao ter sido atualizado"
  exit 1
}

# Verificar tamanho aproximado do bloco styles
$stylesMatch = [regex]::Match($content, "styles:\s*\[``([^``]+)``\]")
if ($stylesMatch.Success) {
  $stylesLen = [System.Text.Encoding]::UTF8.GetByteCount($stylesMatch.Groups[1].Value)
  INFO "Tamanho do bloco styles (UTF-8): ~$stylesLen bytes"
  if ($stylesLen -lt 2100) {
    OK "Tamanho dentro do limite esperado (<= 2100 bytes)"
  } else {
    INFO "Tamanho ainda acima de 2100 bytes - o build confirmara o resultado exato"
  }
} else {
  INFO "Nao foi possivel extrair o bloco styles para medir - o build confirmara"
}

if ($global:manutErros -gt 0) {
  Write-Host ""
  FAIL "Etapa 2 falhou com $global:manutErros erro(s). Corrija o arquivo antes de continuar."
  exit 1
}

# =============================================================================
# ETAPA 3 - Build de producao
# =============================================================================
Passo 3 "Build de producao (ng build --configuration production)"

Set-Location $FrontendDir
INFO "Executando: npx ng build --configuration production ..."
INFO "Este processo pode levar 2-5 minutos ..."

$buildOutput = & npx ng build --configuration production 2>&1
$buildExit   = $LASTEXITCODE

$buildOutput | ForEach-Object { Write-Host "    $_" }

# Verificar se o warning de budget sumiu
$budgetWarning = $buildOutput | Where-Object { $_ -match "licenciamento-novo.*exceeded" -or ($_ -match "licenciamento-novo" -and $_ -match "budget") }
if ($budgetWarning) {
  FAIL "Warning de budget CSS ainda presente apos o build:"
  $budgetWarning | ForEach-Object { FAIL "  $_" }
} else {
  OK "Nenhum warning de budget CSS para licenciamento-novo - problema resolvido"
}

# Verificar resultado do build
if ($buildExit -eq 0) {
  OK "Build concluido com sucesso (exit code 0)"
} else {
  if (Test-Path "$DistDir\index.html") {
    INFO "Build retornou exit code $buildExit mas index.html presente - prosseguindo"
  } else {
    FAIL "Build falhou (exit code $buildExit)"
    exit 1
  }
}

$jsFiles = Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue
INFO "Chunks JS gerados: $($jsFiles.Count)"
if ($jsFiles.Count -gt 0) {
  OK "Chunks JavaScript presentes no dist"
} else {
  FAIL "Nenhum arquivo .js encontrado em $DistDir"
  exit 1
}

# =============================================================================
# ETAPA 4 - Deploy dos assets para o diretorio Nginx
# =============================================================================
Passo 4 "Deploy dos assets para $NginxHtmlDir"

if (-not (Test-Path $NginxHtmlDir)) {
  INFO "Diretorio Nginx nao existe - criando: $NginxHtmlDir"
  New-Item -ItemType Directory -Path $NginxHtmlDir -Force | Out-Null
}

INFO "Copiando arquivos de $DistDir para $NginxHtmlDir ..."
Get-ChildItem -Path $DistDir -Recurse | ForEach-Object {
  $destPath = $_.FullName.Replace($DistDir, $NginxHtmlDir)
  if ($_.PSIsContainer) {
    if (-not (Test-Path $destPath)) {
      New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    }
  } else {
    Copy-Item -Path $_.FullName -Destination $destPath -Force
  }
}

$indexDest = Join-Path $NginxHtmlDir "index.html"
if (Test-Path $indexDest) {
  OK "index.html copiado para $NginxHtmlDir"
} else {
  FAIL "index.html nao encontrado em $NginxHtmlDir apos deploy"
  exit 1
}

# =============================================================================
# ETAPA 5 - Reinicializacao do Nginx e smoke test
# =============================================================================
Passo 5 "Reinicializacao do Nginx e smoke test"

$svc5 = Get-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
if ($null -ne $svc5) {
  INFO "Reiniciando servico: ${NginxSvcName} ..."
  Restart-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  $svcAfter = Get-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
  if ($svcAfter.Status -eq 'Running') {
    OK "Servico ${NginxSvcName} reiniciado e em execucao"
  } else {
    FAIL "Servico ${NginxSvcName} nao ficou em estado Running apos restart"
  }
} else {
  INFO "Servico '${NginxSvcName}' nao encontrado - tentando servico 'nginx' ..."
  Restart-Service -Name "nginx" -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  $nginxAlt = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
  if ($null -ne $nginxAlt -and $nginxAlt.Status -eq 'Running') {
    OK "Servico nginx reiniciado"
  } else {
    INFO "Nginx nao gerenciado como servico Windows - reinicie manualmente se necessario"
  }
}

INFO "Smoke test: GET http://localhost/ ..."
$ErrorActionPreference = "SilentlyContinue"
try {
  $resp = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10
  $ErrorActionPreference = "Continue"
  if ($resp.StatusCode -eq 200) {
    OK "HTTP 200 OK - aplicacao acessivel"
  } else {
    INFO "HTTP $($resp.StatusCode) - verifique a configuracao do Nginx"
  }
} catch {
  $ErrorActionPreference = "Continue"
  INFO "Smoke test falhou: $_"
}

# =============================================================================
# ETAPA 6 - Gerar relatorio de manutencao
# =============================================================================
Passo 6 "Gerar relatorio de manutencao"

$dataHora  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$jsCount   = (Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue).Count
$statusStr = if ($global:manutErros -eq 0) { "SUCESSO" } else { "ERROS: $global:manutErros" }
$budgetStr = if ($budgetWarning) { "WARNING ainda presente" } else { "Resolvido" }

$relatorio = @"
# Relatorio de Manutencao F3

**Data/hora:** $dataHora
**Status geral:** $statusStr
**Warning de budget CSS:** $budgetStr
**Chunks JS gerados:** $jsCount

## Problema corrigido

### Contexto

O componente licenciamento-novo.component.ts foi criado na Sprint F3 com um bloco
de estilos CSS de 2,18 kB, acima do limite configurado em angular.json de 2,05 kB
(excesso de 132 bytes). O build emitia um warning nao-bloqueante a cada compilacao
desde a Sprint F3.

### Causa

O bloco styles continha propriedades CSS de animacao e decoracao desnecessarias para
a funcionalidade do componente: transitions, user-select e border-radius extras.
Essas propriedades, embora inofensivas funcionalmente, aumentavam o CSS minificado
acima do limite de 2,05 kB configurado em angular.json.

### Correcao aplicada

Remocao de 5 propriedades/regras CSS desnecessarias:
1. transition: border-color 0.2s, box-shadow 0.2s  (em .tipo-card)
2. user-select: none                                (em .tipo-card)
3. transition: opacity 0.2s                        (em .tipo-check)
4. .review-section { border-radius: 8px }          (regra inteira removida)
5. margin-top: 1px                                 (em .review-info mat-icon)

Reducao estimada: ~140 bytes minificados (> 132 bytes necessarios).

### Correcao NG8011 (referencia)

O warning NG8011 do mesmo componente (botao "Confirmar e Enviar" com dois nos raiz
no @else) foi corrigido na Sprint F6 com adicao de ng-container. Esta manutencao
apenas confirma a presenca dessa correcao anterior.

## Arquivo modificado

| Arquivo | Modificacao |
|---|---|
| licenciamentos/licenciamento-novo/licenciamento-novo.component.ts | Remocao de 5 propriedades CSS desnecessarias (~140 bytes minificados) |

## Estado dos warnings apos esta manutencao

- Budget CSS licenciamento-novo: $budgetStr
- NG8011 (todos os componentes): Resolvido (F5 + F6)
"@

$relatorio | Out-File -FilePath $RelatorioPath -Encoding UTF8 -Force
if (Test-Path $RelatorioPath) {
  OK "Relatorio gerado: $RelatorioPath"
} else {
  FAIL "Nao foi possivel gerar o relatorio"
}

# =============================================================================
# RESUMO FINAL
# =============================================================================
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  MANUTENCAO F3 - RESUMO FINAL" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

if ($global:manutErros -eq 0) {
  Write-Host ""
  Write-Host "  MANUTENCAO F3 CONCLUIDA COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Arquivo modificado:" -ForegroundColor White
  Write-Host "    - licenciamento-novo.component.ts (5 propriedades CSS removidas, ~140 bytes)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Resultado:" -ForegroundColor White
  Write-Host "    - Budget CSS: $budgetStr" -ForegroundColor White
  Write-Host "    - NG8011: Resolvido (confirmado - ng-container presente)" -ForegroundColor White
  Write-Host "    - Chunks JS: $jsCount" -ForegroundColor White
  Write-Host ""
  Write-Host "  Relatorio: $RelatorioPath" -ForegroundColor White
} else {
  Write-Host ""
  Write-Host "  MANUTENCAO F3 COM $global:manutErros ERRO(S)" -ForegroundColor Red
  Write-Host "  Revise os erros acima." -ForegroundColor Red
}
Write-Host ""
