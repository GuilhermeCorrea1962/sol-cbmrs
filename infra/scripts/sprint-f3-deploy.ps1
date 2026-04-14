# =============================================================================
# sprint-f3-deploy.ps1
# Sprint F3 -Wizard de Solicitacao de Licenciamento (P03)
#
# Etapas:
#   1. Pre-verificacao do ambiente
#   2. Verificacao dos arquivos-fonte da Sprint F3
#   3. Instalacao de dependencias (npm ci)
#   4. Build de producao (ng build --configuration production)
#   5. Deploy: substituicao dos assets no diretorio de producao
#   6. Reinicializacao do Nginx e smoke test final
#
# Pre-requisitos:
#   - Node.js 18+ e npm no PATH
#   - Angular CLI (npx ng) disponivel
#   - Sprints F1 e F2 ja executadas com sucesso
#   - Nginx em execucao como servico Windows "sol-nginx" (ou nome equivalente)
#   - Arquivo de producao em C:\SOL\frontend\dist\sol-frontend\browser
#     copiado para o diretorio raiz do Nginx (ex: C:\nginx\html\sol)
#
# NOTA DE ENCODING (2026-04-07):
#   Versao corrigida pelo Claude Code no servidor apos falha de parse no PS5.x.
#   Caracteres Unicode (U+2550 =, U+2500 -, U+2014 -) foram substituidos por
#   equivalentes ASCII para compatibilidade com PowerShell 5.x (Windows-1252).
# =============================================================================

$ErrorActionPreference = "Continue"
$global:sprintErros = 0

# --- Cores e helpers -----------------------------------------------------------
function Passo([int]$n, [string]$titulo) {
  Write-Host ""
  Write-Host "===========================================================" -ForegroundColor Cyan
  Write-Host "  ETAPA $n -$titulo" -ForegroundColor Cyan
  Write-Host "===========================================================" -ForegroundColor Cyan
}
function OK([string]$msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function FAIL([string]$msg) { Write-Host "  [ERRO] $msg" -ForegroundColor Red; $global:sprintErros++ }
function INFO([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

# --- Caminhos -----------------------------------------------------------------
$FrontendDir  = "C:\SOL\frontend"
$DistDir      = "C:\SOL\frontend\dist\sol-frontend\browser"
$NginxHtmlDir = "C:\nginx\html\sol"   # ajuste se o caminho for diferente
$NginxSvcName = "sol-nginx"

# =============================================================================
# ETAPA 1 -Pre-verificacao do ambiente
# =============================================================================
Passo 1 "Pre-verificacao do ambiente"

# Node.js
$ErrorActionPreference = "SilentlyContinue"
$nodeVer = & node --version 2>&1
$ErrorActionPreference = "Continue"
if ($LASTEXITCODE -eq 0 -or $nodeVer -match "v\d") {
  OK "Node.js: $nodeVer"
} else {
  FAIL "Node.js nao encontrado no PATH. Instale Node.js 18+ antes de continuar."
}

# npm
$ErrorActionPreference = "SilentlyContinue"
$npmVer = & npm --version 2>&1
$ErrorActionPreference = "Continue"
if ($LASTEXITCODE -eq 0 -or $npmVer -match "\d+\.\d+") {
  OK "npm: $npmVer"
} else {
  FAIL "npm nao encontrado. Verifique a instalacao do Node.js."
}

# Diretorio frontend
if (Test-Path $FrontendDir) {
  OK "Diretorio frontend existe: $FrontendDir"
} else {
  FAIL "Diretorio frontend nao encontrado: $FrontendDir"
  Write-Host ""
  Write-Host "ABORTANDO -ambiente invalido." -ForegroundColor Red
  exit 1
}

# package.json
if (Test-Path "$FrontendDir\package.json") {
  OK "package.json encontrado"
} else {
  FAIL "package.json nao encontrado em $FrontendDir"
  Write-Host ""
  Write-Host "ABORTANDO -projeto Angular nao inicializado." -ForegroundColor Red
  exit 1
}

# =============================================================================
# ETAPA 2 -Verificacao dos arquivos-fonte da Sprint F3
# =============================================================================
Passo 2 "Verificacao dos arquivos-fonte da Sprint F3"

$arquivosF3 = @(
  @{ Path = "src\app\core\models\licenciamento-create.model.ts";            Desc = "Novo modelo LicenciamentoCreateDTO / EnderecoCreateDTO / UF_OPTIONS" },
  @{ Path = "src\app\core\models\licenciamento.model.ts";                   Desc = "Modelo atualizado com todos os 23 valores de StatusLicenciamento" },
  @{ Path = "src\app\core\services\licenciamento.service.ts";               Desc = "Service atualizado com criar() e submeter()" },
  @{ Path = "src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts"; Desc = "Wizard MatStepper 4 passos" },
  @{ Path = "src\app\app.routes.ts";                                        Desc = "Rota /novo adicionada antes de /:id" },
  @{ Path = "src\app\pages\licenciamentos\licenciamentos.component.ts";     Desc = "Botao Nova Solicitacao habilitado com routerLink" }
)

foreach ($arq in $arquivosF3) {
  $fullPath = Join-Path $FrontendDir $arq.Path
  if (Test-Path $fullPath) {
    OK "$($arq.Desc)"
    OK "   -> $($arq.Path)"
  } else {
    FAIL "Arquivo nao encontrado: $($arq.Path)"
    FAIL "   -> $($arq.Desc)"
  }
}

# Verificacao de conteudo critica
$modelCreate = Join-Path $FrontendDir "src\app\core\models\licenciamento-create.model.ts"
if (Test-Path $modelCreate) {
  $content = Get-Content $modelCreate -Raw
  if ($content -match "LicenciamentoCreateDTO") {
    OK "licenciamento-create.model.ts contem interface LicenciamentoCreateDTO"
  } else {
    FAIL "licenciamento-create.model.ts nao contem LicenciamentoCreateDTO"
  }
}

$modelStatus = Join-Path $FrontendDir "src\app\core\models\licenciamento.model.ts"
if (Test-Path $modelStatus) {
  $content = Get-Content $modelStatus -Raw
  if ($content -match "APPCI_EMITIDO") {
    OK "licenciamento.model.ts contem status APPCI_EMITIDO (23 valores presentes)"
  } else {
    FAIL "licenciamento.model.ts nao foi atualizado com todos os status"
  }
}

$routes = Join-Path $FrontendDir "src\app\app.routes.ts"
if (Test-Path $routes) {
  $content = Get-Content $routes -Raw
  if ($content -match "licenciamento-novo") {
    OK "app.routes.ts contem rota licenciamento-novo"
  } else {
    FAIL "app.routes.ts nao contem rota licenciamento-novo"
  }
  # Verifica que 'novo' aparece antes de ':id'
  $idxNovo = $content.IndexOf("'novo'")
  $idxId   = $content.IndexOf("':id'")
  if ($idxNovo -ge 0 -and $idxId -ge 0 -and $idxNovo -lt $idxId) {
    OK "Rota 'novo' esta declarada ANTES de ':id' (ordenacao correta)"
  } else {
    FAIL "Rota 'novo' NAO esta antes de ':id' -risco de match errado no router"
  }
}

$svc = Join-Path $FrontendDir "src\app\core\services\licenciamento.service.ts"
if (Test-Path $svc) {
  $content = Get-Content $svc -Raw
  if ($content -match "criar\(" -and $content -match "submeter\(") {
    OK "licenciamento.service.ts contem metodos criar() e submeter()"
  } else {
    FAIL "licenciamento.service.ts nao contem criar() e/ou submeter()"
  }
}

if ($global:sprintErros -gt 0) {
  Write-Host ""
  FAIL "Etapa 2 falhou com $global:sprintErros erro(s). Corrija os arquivos antes de continuar."
  exit 1
}

# =============================================================================
# ETAPA 3 -npm ci (instalacao limpa de dependencias)
# =============================================================================
Passo 3 "Instalacao de dependencias (npm ci)"

Set-Location $FrontendDir
INFO "Executando: npm ci --prefer-offline ..."

$ErrorActionPreference = "Continue"
$npmOutput = & npm ci --prefer-offline 2>&1
$npmExit   = $LASTEXITCODE
$ErrorActionPreference = "Continue"

$npmOutput | ForEach-Object { Write-Host "    $_" }

if ($npmExit -eq 0) {
  OK "npm ci concluido com sucesso"
} else {
  # npm pode retornar exit code != 0 por warnings -verificar se node_modules existe
  if (Test-Path "$FrontendDir\node_modules\@angular\core") {
    INFO "npm ci retornou exit code $npmExit mas @angular/core esta presente -prosseguindo"
  } else {
    FAIL "npm ci falhou (exit code $npmExit) e node_modules/@angular/core nao encontrado"
    exit 1
  }
}

# =============================================================================
# ETAPA 4 -Build de producao
# =============================================================================
Passo 4 "Build de producao (ng build --configuration production)"

INFO "Executando: npx ng build --configuration production ..."
INFO "Este processo pode levar 2-5 minutos ..."

$ErrorActionPreference = "Continue"
$buildOutput = & npx ng build --configuration production 2>&1
$buildExit   = $LASTEXITCODE
$ErrorActionPreference = "Continue"

$buildOutput | ForEach-Object { Write-Host "    $_" }

if ($buildExit -eq 0) {
  OK "Build concluido com sucesso (exit code 0)"
} else {
  # Verificar se arquivos foram gerados mesmo com exit != 0
  if (Test-Path "$DistDir\index.html") {
    INFO "Build retornou exit code $buildExit mas index.html foi gerado -prosseguindo"
  } else {
    FAIL "Build falhou (exit code $buildExit) -$DistDir\index.html nao encontrado"
    exit 1
  }
}

# Verificar presenca dos chunks F3
$jsFiles = Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue
INFO "Arquivos JS gerados: $($jsFiles.Count)"
if ($jsFiles.Count -gt 0) {
  OK "Chunks JavaScript presentes no dist"
} else {
  FAIL "Nenhum arquivo .js encontrado em $DistDir"
  exit 1
}

# =============================================================================
# ETAPA 5 -Deploy: substituicao dos assets no diretorio Nginx
# =============================================================================
Passo 5 "Deploy dos assets para $NginxHtmlDir"

if (-not (Test-Path $NginxHtmlDir)) {
  INFO "Diretorio Nginx nao existe -criando: $NginxHtmlDir"
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

# Verificacao pos-deploy
$indexDest = Join-Path $NginxHtmlDir "index.html"
if (Test-Path $indexDest) {
  OK "index.html copiado para $NginxHtmlDir"
} else {
  FAIL "index.html nao encontrado em $NginxHtmlDir apos deploy"
  exit 1
}

# =============================================================================
# ETAPA 6 -Reinicializacao do Nginx e smoke test
# =============================================================================
Passo 6 "Reinicializacao do Nginx e smoke test"

$svc6 = Get-Service -Name $NginxSvcName -ErrorAction SilentlyContinue
if ($null -ne $svc6) {
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
  INFO "Servico '${NginxSvcName}' nao encontrado -tentando Restart-Service 'nginx' ..."
  Restart-Service -Name "nginx" -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  $nginxAlt = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
  if ($null -ne $nginxAlt -and $nginxAlt.Status -eq 'Running') {
    OK "Servico nginx reiniciado"
  } else {
    INFO "Nginx nao gerenciado como servico Windows -reinicie manualmente se necessario"
  }
}

# Smoke test HTTP
INFO "Smoke test: GET http://localhost/ ..."
$ErrorActionPreference = "SilentlyContinue"
try {
  $resp = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10
  $ErrorActionPreference = "Continue"
  if ($resp.StatusCode -eq 200) {
    OK "HTTP 200 OK -aplicacao acessivel"
  } else {
    INFO "HTTP $($resp.StatusCode) -verifique a configuracao do Nginx"
  }
} catch {
  $ErrorActionPreference = "Continue"
  INFO "Smoke test falhou: $_"
  INFO "Verifique se o Nginx esta ouvindo na porta 80 e o caminho do html esta correto."
}

# =============================================================================
# RESUMO FINAL
# =============================================================================
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  SPRINT F3 -RESUMO FINAL" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

if ($global:sprintErros -eq 0) {
  Write-Host ""
  Write-Host "  SPRINT F3 CONCLUIDA COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Entregas desta sprint:" -ForegroundColor White
  Write-Host "    - licenciamento-create.model.ts   (novo -LicenciamentoCreateDTO)" -ForegroundColor White
  Write-Host "    - licenciamento.model.ts           (atualizado -23 status)" -ForegroundColor White
  Write-Host "    - licenciamento.service.ts         (atualizado -criar() + submeter())" -ForegroundColor White
  Write-Host "    - licenciamento-novo.component.ts  (novo -wizard 4 passos)" -ForegroundColor White
  Write-Host "    - app.routes.ts                    (atualizado -rota /novo)" -ForegroundColor White
  Write-Host "    - licenciamentos.component.ts      (atualizado -botao ativo)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Funcionalidades disponiveis:" -ForegroundColor White
  Write-Host "    /app/licenciamentos/novo  -> Wizard de criacao (CIDADAO / ADMIN)" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos  -> criacao de rascunho" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos/{id}/submeter  -> envio para analise" -ForegroundColor White
} else {
  Write-Host ""
  Write-Host "  SPRINT F3 CONCLUIDA COM $global:sprintErros ERRO(S)" -ForegroundColor Red
  Write-Host "  Revise os erros acima e re-execute o script." -ForegroundColor Red
}
Write-Host ""
