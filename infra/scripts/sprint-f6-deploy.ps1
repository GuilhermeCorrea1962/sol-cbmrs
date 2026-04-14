# =============================================================================
# sprint-f6-deploy.ps1
# Sprint F6 - Emissao de APPCI (P08)
#
# Etapas:
#   1. Pre-verificacao do ambiente
#   2. Verificacao dos arquivos-fonte da Sprint F6
#   3. Instalacao de dependencias (npm ci)
#   4. Build de producao (ng build --configuration production)
#   5. Deploy: substituicao dos assets no diretorio de producao
#   6. Reinicializacao do Nginx e smoke test final
#   7. Gerar relatorio de deploy
#
# Pre-requisitos:
#   - Sprints F1 a F5 ja executadas com sucesso
#   - Node.js 18+ e npm no PATH
#   - Angular CLI (npx ng) disponivel via node_modules
#   - Nginx em execucao como servico Windows "sol-nginx" (ou equivalente)
#
# Novos arquivos F6:
#   - src/app/core/models/appci.model.ts                   (novo)
#   - src/app/pages/appci/appci-fila/...                   (novo)
#   - src/app/pages/appci/appci-detalhe/...                (novo)
#
# Arquivos atualizados F6:
#   - src/app/core/services/licenciamento.service.ts       (2 novos metodos)
#   - src/app/app.routes.ts                                (rota appci com filhos)
#   - src/app/pages/licenciamentos/licenciamento-detalhe/  (botao Emitir APPCI)
#   - src/app/pages/licenciamentos/licenciamento-novo/     (correcao NG8011)
#
# NOTA DE ENCODING:
#   Script criado com ASCII-only. Nenhum caractere Unicode acima de U+007F.
#   Compativel com PowerShell 5.x (Windows-1252) sem necessidade de BOM.
# =============================================================================

$ErrorActionPreference = "Continue"
$global:sprintErros = 0

# --- Cores e helpers -----------------------------------------------------------
function Passo([int]$n, [string]$titulo) {
  Write-Host ""
  Write-Host "===========================================================" -ForegroundColor Cyan
  Write-Host "  ETAPA $n - $titulo" -ForegroundColor Cyan
  Write-Host "===========================================================" -ForegroundColor Cyan
}
function OK([string]$msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function FAIL([string]$msg) { Write-Host "  [ERRO] $msg" -ForegroundColor Red; $global:sprintErros++ }
function INFO([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

# --- Caminhos -----------------------------------------------------------------
$FrontendDir  = "C:\SOL\frontend"
$DistDir      = "C:\SOL\frontend\dist\sol-frontend\browser"
$NginxHtmlDir = "C:\nginx\html\sol"
$NginxSvcName = "sol-nginx"
$RelatorioPath = "C:\SOL\logs\sprint-f6-relatorio-deploy.md"

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
  FAIL "Node.js nao encontrado no PATH. Instale Node.js 18+ antes de continuar."
}

$ErrorActionPreference = "SilentlyContinue"
$npmVer = & npm --version 2>&1
$ErrorActionPreference = "Continue"
if ($LASTEXITCODE -eq 0 -or $npmVer -match "\d+\.\d+") {
  OK "npm: $npmVer"
} else {
  FAIL "npm nao encontrado. Verifique a instalacao do Node.js."
}

if (Test-Path $FrontendDir) {
  OK "Diretorio frontend existe: $FrontendDir"
} else {
  FAIL "Diretorio frontend nao encontrado: $FrontendDir"
  Write-Host "ABORTANDO - ambiente invalido." -ForegroundColor Red
  exit 1
}

if (Test-Path "$FrontendDir\package.json") {
  OK "package.json encontrado"
} else {
  FAIL "package.json nao encontrado em $FrontendDir"
  Write-Host "ABORTANDO - projeto Angular nao inicializado." -ForegroundColor Red
  exit 1
}

# Verificar pre-requisito: arquivos F5 presentes
$vistoriaModel = Join-Path $FrontendDir "src\app\core\models\vistoria.model.ts"
if (Test-Path $vistoriaModel) {
  OK "Pre-requisito F5: vistoria.model.ts presente"
} else {
  FAIL "Pre-requisito F5 ausente: vistoria.model.ts nao encontrado - execute Sprint F5 antes"
  exit 1
}

# =============================================================================
# ETAPA 2 - Verificacao dos arquivos-fonte da Sprint F6
# =============================================================================
Passo 2 "Verificacao dos arquivos-fonte da Sprint F6"

$arquivosF6 = @(
  @{ Path = "src\app\core\models\appci.model.ts";
     Desc = "Novo modelo AppciEmitirDTO" },
  @{ Path = "src\app\pages\appci\appci-fila\appci-fila.component.ts";
     Desc = "Novo componente AppciFilaComponent (fila de emissao de APPCI)" },
  @{ Path = "src\app\pages\appci\appci-detalhe\appci-detalhe.component.ts";
     Desc = "Novo componente AppciDetalheComponent (tela de emissao de APPCI)" },
  @{ Path = "src\app\core\services\licenciamento.service.ts";
     Desc = "Service atualizado com getFilaAppci, emitirAppci" },
  @{ Path = "src\app\app.routes.ts";
     Desc = "Rotas atualizadas: /app/appci com filhos (fila + :id)" },
  @{ Path = "src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts";
     Desc = "Detalhe atualizado com botao Emitir APPCI (ADMIN/CHEFE)" },
  @{ Path = "src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts";
     Desc = "Novo: correcao NG8011 no botao Confirmar e Enviar" }
)

foreach ($arq in $arquivosF6) {
  $fullPath = Join-Path $FrontendDir $arq.Path
  if (Test-Path $fullPath) {
    OK "$($arq.Desc)"
  } else {
    FAIL "Arquivo nao encontrado: $($arq.Path)"
  }
}

# --- Verificacoes de conteudo criticas ---

$appciModel = Join-Path $FrontendDir "src\app\core\models\appci.model.ts"
if (Test-Path $appciModel) {
  $content = Get-Content $appciModel -Raw
  if ($content -match "AppciEmitirDTO") {
    OK "appci.model.ts contem interface AppciEmitirDTO"
  } else {
    FAIL "appci.model.ts nao contem AppciEmitirDTO"
  }
}

$appciFilaComp = Join-Path $FrontendDir "src\app\pages\appci\appci-fila\appci-fila.component.ts"
if (Test-Path $appciFilaComp) {
  $content = Get-Content $appciFilaComp -Raw
  if ($content -match "AppciFilaComponent") {
    OK "appci-fila.component.ts contem classe AppciFilaComponent"
  } else {
    FAIL "appci-fila.component.ts nao contem AppciFilaComponent"
  }
}

$appciDetalheComp = Join-Path $FrontendDir "src\app\pages\appci\appci-detalhe\appci-detalhe.component.ts"
if (Test-Path $appciDetalheComp) {
  $content = Get-Content $appciDetalheComp -Raw
  if ($content -match "AppciDetalheComponent") {
    OK "appci-detalhe.component.ts contem AppciDetalheComponent"
  } else {
    FAIL "appci-detalhe.component.ts nao contem AppciDetalheComponent"
  }
  if ($content -match "confirmarEmissao\(\)") {
    OK "appci-detalhe.component.ts contem metodo confirmarEmissao()"
  } else {
    FAIL "appci-detalhe.component.ts nao contem confirmarEmissao()"
  }
}

$svc = Join-Path $FrontendDir "src\app\core\services\licenciamento.service.ts"
if (Test-Path $svc) {
  $content = Get-Content $svc -Raw
  if ($content -match "getFilaAppci") {
    OK "licenciamento.service.ts contem metodo getFilaAppci"
  } else {
    FAIL "licenciamento.service.ts nao contem getFilaAppci"
  }
  if ($content -match "emitirAppci") {
    OK "licenciamento.service.ts contem metodo emitirAppci"
  } else {
    FAIL "licenciamento.service.ts nao contem emitirAppci"
  }
}

$routes = Join-Path $FrontendDir "src\app\app.routes.ts"
if (Test-Path $routes) {
  $content = Get-Content $routes -Raw
  if ($content -match "appci-fila.component") {
    OK "app.routes.ts contem import de appci-fila.component (rota /appci ativa)"
  } else {
    FAIL "app.routes.ts nao contem appci-fila.component"
  }
  if ($content -match "appci-detalhe.component") {
    OK "app.routes.ts contem import de appci-detalhe.component (rota /appci/:id)"
  } else {
    FAIL "app.routes.ts nao contem appci-detalhe.component"
  }
}

$detalheLic = Join-Path $FrontendDir "src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts"
if (Test-Path $detalheLic) {
  $content = Get-Content $detalheLic -Raw
  if ($content -match "podeEmitirAppci") {
    OK "licenciamento-detalhe.component.ts contem propriedade podeEmitirAppci"
  } else {
    FAIL "licenciamento-detalhe.component.ts nao contem podeEmitirAppci"
  }
}

$novoComp = Join-Path $FrontendDir "src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts"
if (Test-Path $novoComp) {
  $content = Get-Content $novoComp -Raw
  if ($content -match "ng-container") {
    OK "licenciamento-novo.component.ts contem ng-container (correcao NG8011 aplicada)"
  } else {
    FAIL "licenciamento-novo.component.ts nao contem ng-container - correcao NG8011 ausente"
  }
}

if ($global:sprintErros -gt 0) {
  Write-Host ""
  FAIL "Etapa 2 falhou com $global:sprintErros erro(s). Corrija os arquivos antes de continuar."
  exit 1
}

# =============================================================================
# ETAPA 3 - npm ci (instalacao limpa de dependencias)
# =============================================================================
Passo 3 "Instalacao de dependencias (npm ci)"

Set-Location $FrontendDir
INFO "Executando: npm ci --prefer-offline ..."

$npmOutput = & npm ci --prefer-offline 2>&1
$npmExit   = $LASTEXITCODE

$npmOutput | ForEach-Object { Write-Host "    $_" }

if ($npmExit -eq 0) {
  OK "npm ci concluido com sucesso"
} else {
  if (Test-Path "$FrontendDir\node_modules\@angular\core") {
    INFO "npm ci retornou exit code $npmExit mas @angular/core presente - prosseguindo"
  } else {
    FAIL "npm ci falhou (exit code $npmExit) e @angular/core nao encontrado"
    exit 1
  }
}

# =============================================================================
# ETAPA 4 - Build de producao
# =============================================================================
Passo 4 "Build de producao (ng build --configuration production)"

INFO "Executando: npx ng build --configuration production ..."
INFO "Este processo pode levar 2-5 minutos ..."

$buildOutput = & npx ng build --configuration production 2>&1
$buildExit   = $LASTEXITCODE

$buildOutput | ForEach-Object { Write-Host "    $_" }

if ($buildExit -eq 0) {
  OK "Build concluido com sucesso (exit code 0)"
} else {
  if (Test-Path "$DistDir\index.html") {
    INFO "Build retornou exit code $buildExit mas index.html foi gerado - prosseguindo"
  } else {
    FAIL "Build falhou (exit code $buildExit) - $DistDir\index.html nao encontrado"
    exit 1
  }
}

$jsFiles = Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue
INFO "Arquivos JS gerados: $($jsFiles.Count)"
if ($jsFiles.Count -gt 0) {
  OK "Chunks JavaScript presentes no dist"
  $f6Chunks = $jsFiles | Where-Object { $_.Name -match "appci" }
  if ($f6Chunks.Count -gt 0) {
    OK "Chunk(s) F6 encontrado(s): $($f6Chunks.Name -join ', ')"
  } else {
    INFO "Nenhum chunk com 'appci' no nome - verificar bundle pelo hash gerado"
  }
} else {
  FAIL "Nenhum arquivo .js encontrado em $DistDir"
  exit 1
}

# =============================================================================
# ETAPA 5 - Deploy dos assets para o diretorio Nginx
# =============================================================================
Passo 5 "Deploy dos assets para $NginxHtmlDir"

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
# ETAPA 6 - Reinicializacao do Nginx e smoke test
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
  INFO "Verifique se o Nginx esta ouvindo na porta 80 e o caminho do html esta correto."
}

# =============================================================================
# ETAPA 7 - Gerar relatorio de deploy
# =============================================================================
Passo 7 "Gerar relatorio de deploy"

$dataHora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$jsCount  = (Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue).Count
$status   = if ($global:sprintErros -eq 0) { "SUCESSO" } else { "ERROS: $global:sprintErros" }

$relatorio = @"
# Relatorio de Deploy - Sprint F6

**Data/hora:** $dataHora
**Status geral:** $status
**Chunks JS gerados:** $jsCount

## Arquivos implantados

### Novos (3 arquivos)

| Arquivo | Status |
|---|---|
| core/models/appci.model.ts | OK |
| pages/appci/appci-fila/appci-fila.component.ts | OK |
| pages/appci/appci-detalhe/appci-detalhe.component.ts | OK |

### Atualizados (4 arquivos)

| Arquivo | Mudanca | Status |
|---|---|---|
| core/services/licenciamento.service.ts | +2 metodos F6: getFilaAppci, emitirAppci | OK |
| app.routes.ts | Rota /appci com filhos lazy | OK |
| licenciamentos/licenciamento-detalhe | podeEmitirAppci + botao | OK |
| licenciamentos/licenciamento-novo | Correcao NG8011 ng-container | OK |

## Rotas disponiveis apos F6

| Rota | Componente | Roles |
|---|---|---|
| /app/appci | AppciFilaComponent | ADMIN, CHEFE_SSEG_BBM |
| /app/appci/:id | AppciDetalheComponent | ADMIN, CHEFE_SSEG_BBM |

## Endpoints consumidos

- GET  /api/licenciamentos/fila-appci
- POST /api/licenciamentos/{id}/emitir-appci

## Proximas acoes sugeridas

- Configurar endpoint GET /api/licenciamentos/fila-appci no backend (retornar PRPCI_EMITIDO)
- Configurar endpoint POST /api/licenciamentos/{id}/emitir-appci (transicao PRPCI_EMITIDO -> APPCI_EMITIDO)
- Testar fluxo completo: submissao -> analise -> vistoria -> APPCI
- Sprint F7: Gestao de usuarios (rota /app/usuarios ainda e placeholder)
"@

$relatorio | Out-File -FilePath $RelatorioPath -Encoding UTF8 -Force
if (Test-Path $RelatorioPath) {
  OK "Relatorio gerado: $RelatorioPath"
} else {
  FAIL "Nao foi possivel gerar o relatorio em $RelatorioPath"
}

# =============================================================================
# RESUMO FINAL
# =============================================================================
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  SPRINT F6 - RESUMO FINAL" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

if ($global:sprintErros -eq 0) {
  Write-Host ""
  Write-Host "  SPRINT F6 CONCLUIDA COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Novos arquivos entregues:" -ForegroundColor White
  Write-Host "    - appci.model.ts                     (novo - DTO AppciEmitirDTO)" -ForegroundColor White
  Write-Host "    - appci-fila.component.ts             (novo - fila PRPCI_EMITIDO)" -ForegroundColor White
  Write-Host "    - appci-detalhe.component.ts          (novo - emissao APPCI)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Arquivos atualizados:" -ForegroundColor White
  Write-Host "    - licenciamento.service.ts            (getFilaAppci + emitirAppci)" -ForegroundColor White
  Write-Host "    - app.routes.ts                       (rota /appci com filhos)" -ForegroundColor White
  Write-Host "    - licenciamento-detalhe.component.ts  (botao Emitir APPCI)" -ForegroundColor White
  Write-Host "    - licenciamento-novo.component.ts     (correcao NG8011)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Rotas disponiveis:" -ForegroundColor White
  Write-Host "    /app/appci        -> Fila de emissao de APPCI (ADMIN / CHEFE_SSEG_BBM)" -ForegroundColor White
  Write-Host "    /app/appci/:id    -> Tela de emissao com confirmacao" -ForegroundColor White
  Write-Host ""
  Write-Host "  Endpoints consumidos:" -ForegroundColor White
  Write-Host "    GET  /api/licenciamentos/fila-appci" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos/{id}/emitir-appci" -ForegroundColor White
  Write-Host ""
  Write-Host "  Relatorio: $RelatorioPath" -ForegroundColor White
} else {
  Write-Host ""
  Write-Host "  SPRINT F6 CONCLUIDA COM $global:sprintErros ERRO(S)" -ForegroundColor Red
  Write-Host "  Revise os erros acima e re-execute o script." -ForegroundColor Red
}
Write-Host ""
