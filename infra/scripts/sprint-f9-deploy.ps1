# sprint-f9-deploy.ps1
# Deploy da Sprint F9 - Relatorios (P-REL)
# Pre-requisito: Sprints F1-F8 concluidas (valida presenca de troca-envolvidos.model.ts)
#
# Etapas:
#   1 - Pre-verificacao do ambiente
#   2 - Verificacao dos fontes F9
#   3 - npm ci
#   4 - Build de producao (ng build --configuration production)
#   5 - Deploy para C:\nginx\html\sol
#   6 - Reinicializacao do Nginx + smoke test
#   7 - Relatorio de deploy

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$frontendDir  = "C:\SOL\frontend"
$nginxHtml    = "C:\nginx\html\sol"
$distDir      = "$frontendDir\dist\sol-frontend\browser"
$logDir       = "C:\SOL\logs"
$relatorio    = "$logDir\sprint-f9-relatorio-deploy.md"
$dataHora     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$erros        = 0
$warnings     = @()

function Ok  ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green  }
function Fail ($msg) { Write-Host "  [ERRO] $msg" -ForegroundColor Red; $script:erros++ }
function Info ($msg) { Write-Host "  [INFO] $msg" -ForegroundColor Cyan  }
function Warn ($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warnings += $msg }

# ==============================================================================
Write-Host ""
Write-Host "SPRINT F9 - RELATORIOS (P-REL)" -ForegroundColor Magenta
Write-Host "Deploy iniciado em: $dataHora"
Write-Host ""

# ==============================================================================
# ETAPA 1 - Pre-verificacao do ambiente
# ==============================================================================
Write-Host "ETAPA 1 - Pre-verificacao do ambiente" -ForegroundColor Yellow

# Node.js
try {
    $nodeVer = & node --version 2>&1
    Ok "Node.js: $nodeVer"
} catch {
    Fail "Node.js nao encontrado no PATH"
}

# Diretorio frontend
if (Test-Path $frontendDir) {
    Ok "Diretorio frontend: $frontendDir"
} else {
    Fail "Diretorio nao encontrado: $frontendDir"
}

# package.json
if (Test-Path "$frontendDir\package.json") {
    Ok "package.json encontrado"
} else {
    Fail "package.json ausente em $frontendDir"
}

# Pre-requisito F8: troca-envolvidos.model.ts
$arquivoF8 = "$frontendDir\src\app\core\models\troca-envolvidos.model.ts"
if (Test-Path $arquivoF8) {
    Ok "Pre-requisito F8: troca-envolvidos.model.ts presente"
} else {
    Fail "Pre-requisito F8 nao satisfeito: $arquivoF8 ausente. Execute a Sprint F8 primeiro."
}

if ($erros -gt 0) {
    Write-Host ""
    Write-Host "ABORTANDO: $erros erro(s) na pre-verificacao." -ForegroundColor Red
    exit 1
}

# ==============================================================================
# ETAPA 2 - Verificacao dos fontes F9
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 2 - Verificacao dos fontes F9" -ForegroundColor Yellow

$srcDir = "$frontendDir\src"

# Novos arquivos TypeScript
$novos = @(
    "app\core\models\relatorio.model.ts",
    "app\core\services\relatorio.service.ts",
    "app\pages\relatorios\relatorios-menu\relatorios-menu.component.ts",
    "app\pages\relatorios\relatorio-licenciamentos\relatorio-licenciamentos.component.ts"
)

foreach ($arq in $novos) {
    $caminho = "$srcDir\$arq"
    if (Test-Path $caminho) {
        Ok "Presente: $arq"
    } else {
        Fail "Ausente:  $arq"
    }
}

# Marcadores nos arquivos modificados

# relatorio.model.ts deve conter RelatorioLicenciamentosItem
$modelPath = "$srcDir\app\core\models\relatorio.model.ts"
if (Test-Path $modelPath) {
    $modelContent = Get-Content $modelPath -Raw
    if ($modelContent -match "RelatorioLicenciamentosItem") {
        Ok "relatorio.model.ts: DTO RelatorioLicenciamentosItem presente"
    } else {
        Fail "relatorio.model.ts: marcador 'RelatorioLicenciamentosItem' nao encontrado"
    }
}

# relatorio.service.ts deve conter Sprint F9
$svcPath = "$srcDir\app\core\services\relatorio.service.ts"
if (Test-Path $svcPath) {
    $svcContent = Get-Content $svcPath -Raw
    if ($svcContent -match "Sprint F9") {
        Ok "relatorio.service.ts: secao Sprint F9 presente"
    } else {
        Fail "relatorio.service.ts: marcador 'Sprint F9' nao encontrado"
    }
}

# relatorios-menu.component.ts deve conter sol-relatorios-menu
$menuPath = "$srcDir\app\pages\relatorios\relatorios-menu\relatorios-menu.component.ts"
if (Test-Path $menuPath) {
    $menuContent = Get-Content $menuPath -Raw
    if ($menuContent -match "sol-relatorios-menu") {
        Ok "relatorios-menu.component.ts: seletor sol-relatorios-menu presente"
    } else {
        Fail "relatorios-menu.component.ts: seletor 'sol-relatorios-menu' nao encontrado"
    }
}

# relatorio-licenciamentos.component.ts deve conter exportarCSV
$relLicPath = "$srcDir\app\pages\relatorios\relatorio-licenciamentos\relatorio-licenciamentos.component.ts"
if (Test-Path $relLicPath) {
    $relLicContent = Get-Content $relLicPath -Raw
    if ($relLicContent -match "exportarCSV") {
        Ok "relatorio-licenciamentos.component.ts: metodo exportarCSV presente"
    } else {
        Fail "relatorio-licenciamentos.component.ts: metodo 'exportarCSV' nao encontrado"
    }
}

# app.routes.ts deve conter relatorios-menu
$routesPath = "$srcDir\app\app.routes.ts"
if (Test-Path $routesPath) {
    $routesContent = Get-Content $routesPath -Raw
    if ($routesContent -match "relatorios-menu") {
        Ok "app.routes.ts: rota /relatorios com filho relatorios-menu presente"
    } else {
        Fail "app.routes.ts: marcador 'relatorios-menu' nao encontrado"
    }
}

if ($erros -gt 0) {
    Write-Host ""
    Write-Host "ABORTANDO: $erros erro(s) na verificacao dos fontes F9." -ForegroundColor Red
    Write-Host "Verifique se todos os arquivos foram copiados corretamente para C:\SOL." -ForegroundColor Yellow
    exit 1
}

# ==============================================================================
# ETAPA 3 - npm ci
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 3 - npm ci" -ForegroundColor Yellow

Push-Location $frontendDir
try {
    & npm ci 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { Fail "npm ci falhou (exit code $LASTEXITCODE)" }
    else { Ok "npm ci concluido" }
} finally {
    Pop-Location
}

if ($erros -gt 0) { Write-Host "ABORTANDO: npm ci falhou." -ForegroundColor Red; exit 1 }

# ==============================================================================
# ETAPA 4 - Build de producao
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 4 - Build de producao" -ForegroundColor Yellow

Push-Location $frontendDir
try {
    $buildOutput = & npx ng build --configuration production 2>&1
    $buildExit   = $LASTEXITCODE
    $buildOutput | ForEach-Object { Write-Host "    $_" }
} finally {
    Pop-Location
}

if ($buildExit -ne 0) {
    Fail "ng build falhou (exit code $buildExit)"
    Write-Host "ABORTANDO: build de producao falhou." -ForegroundColor Red
    exit 1
}
Ok "Build concluido com sucesso (exit code 0)"

# Verificar warnings de budget CSS
$buildText = $buildOutput -join "`n"
if ($buildText -match "exceeded maximum budget") {
    Warn "Warning de budget CSS detectado  -  verifique os estilos adicionados"
} else {
    Ok "Nenhum warning de budget CSS"
}

# Verificar warnings NG8011 (elementos desconhecidos)
if ($buildText -match "NG8011") {
    Warn "Warning NG8011 detectado  -  verifique imports[] dos componentes standalone"
} else {
    Ok "Nenhum warning NG8011"
}

# Contar chunks JS
$chunksDir = $distDir
if (Test-Path $chunksDir) {
    $chunks = (Get-ChildItem "$chunksDir\*.js" -ErrorAction SilentlyContinue).Count
    Info "Chunks JS gerados: $chunks"
} else {
    Warn "Diretorio dist nao encontrado em $chunksDir"
}

if ($erros -gt 0) { Write-Host "ABORTANDO: erros no build." -ForegroundColor Red; exit 1 }

# ==============================================================================
# ETAPA 5 - Deploy para Nginx
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 5 - Deploy dos assets" -ForegroundColor Yellow

if (-not (Test-Path $distDir)) {
    Fail "Diretorio dist nao encontrado: $distDir"
    exit 1
}

if (-not (Test-Path $nginxHtml)) {
    try {
        New-Item -ItemType Directory -Path $nginxHtml -Force | Out-Null
        Info "Diretorio criado: $nginxHtml"
    } catch {
        Fail "Nao foi possivel criar $nginxHtml : $_"
        exit 1
    }
}

try {
    Copy-Item -Path "$distDir\*" -Destination $nginxHtml -Recurse -Force
    Ok "Assets copiados para $nginxHtml"
    $indexDest = "$nginxHtml\index.html"
    if (Test-Path $indexDest) { Ok "index.html copiado para $nginxHtml" }
    else { Warn "index.html nao encontrado em $nginxHtml apos copia" }
} catch {
    Fail "Falha ao copiar assets: $_"
    exit 1
}

# ==============================================================================
# ETAPA 6 - Reinicializacao do Nginx + smoke test
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 6 - Nginx e smoke test" -ForegroundColor Yellow

$servicoNginx = $null
foreach ($nome in @("sol-nginx", "nginx")) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if ($svc) { $servicoNginx = $nome; break }
}

if ($servicoNginx) {
    try {
        Restart-Service -Name $servicoNginx -Force
        Start-Sleep -Seconds 2
        Ok "Servico $servicoNginx reiniciado"
    } catch {
        Warn "Nao foi possivel reiniciar o servico ${servicoNginx}: $_"
    }
} else {
    Warn "Servico Nginx nao encontrado (sol-nginx / nginx)  -  reinicie manualmente"
}

# Smoke test HTTP
try {
    $resp = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10
    if ($resp.StatusCode -eq 200) {
        Ok "HTTP $($resp.StatusCode) OK - aplicacao acessivel"
    } else {
        Warn "HTTP $($resp.StatusCode)  -  verifique a configuracao do Nginx"
    }
} catch {
    Warn "Smoke test falhou: $_"
}

# ==============================================================================
# ETAPA 7 - Relatorio de deploy
# ==============================================================================
Write-Host ""
Write-Host "ETAPA 7 - Relatorio" -ForegroundColor Yellow

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$statusFinal = if ($erros -eq 0) { "SUCESSO" } else { "ERROS: $erros" }
$warningsStr = if ($warnings.Count -eq 0) { "Nenhum" } else { ($warnings | ForEach-Object { "- $_" }) -join "`n" }

$relatorioConteudo = @"
# Relatorio de Deploy  -  Sprint F9 Relatorios

**Data/Hora:** $dataHora
**Status:**    $statusFinal
**Chunks JS:** $chunks
**Warnings:**
$warningsStr

## Arquivos novos

| Arquivo | Tipo |
|---|---|
| frontend/src/app/core/models/relatorio.model.ts | NOVO |
| frontend/src/app/core/services/relatorio.service.ts | NOVO |
| frontend/src/app/pages/relatorios/relatorios-menu/relatorios-menu.component.ts | NOVO |
| frontend/src/app/pages/relatorios/relatorio-licenciamentos/relatorio-licenciamentos.component.ts | NOVO |

## Arquivos modificados

| Arquivo | Modificacao |
|---|---|
| frontend/src/app/app.routes.ts | Rota /relatorios substituida: placeholder -> children com relatorios-menu e relatorio-licenciamentos |

## Rotas implementadas

| Rota | Componente | Roles |
|---|---|---|
| /app/relatorios | RelatoriosMenuComponent | ADMIN, CHEFE_SSEG_BBM |
| /app/relatorios/licenciamentos | RelatorioLicenciamentosComponent | ADMIN, CHEFE_SSEG_BBM |

## Endpoints consumidos

| Metodo | Endpoint | Uso |
|---|---|---|
| GET | /api/relatorios/resumo-status | Painel de resumo no menu |
| GET | /api/relatorios/licenciamentos | Relatorio paginado com filtros |
| GET | /api/relatorios/licenciamentos/csv | Exportacao CSV (Blob download) |
"@

$relatorioConteudo | Out-File -FilePath $relatorio -Encoding UTF8
Ok "Relatorio gerado: $relatorio"

# ==============================================================================
# Resultado final
# ==============================================================================
Write-Host ""
if ($erros -eq 0) {
    Write-Host "  SPRINT F9 CONCLUIDA COM SUCESSO" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  SPRINT F9 CONCLUIDA COM $erros ERRO(S)" -ForegroundColor Red
    exit 1
}
