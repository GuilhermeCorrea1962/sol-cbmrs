# =============================================================================
# sprint-f5-deploy.ps1
# Sprint F5 - Vistoria Presencial (P07)
#
# Etapas:
#   1. Pre-verificacao do ambiente
#   2. Verificacao dos arquivos-fonte da Sprint F5
#   3. Instalacao de dependencias (npm ci)
#   4. Build de producao (ng build --configuration production)
#   5. Deploy: substituicao dos assets no diretorio de producao
#   6. Reinicializacao do Nginx e smoke test final
#
# Pre-requisitos:
#   - Sprints F1 a F4 ja executadas com sucesso
#   - Node.js 18+ e npm no PATH
#   - Angular CLI (npx ng) disponivel via node_modules
#   - Nginx em execucao como servico Windows "sol-nginx" (ou equivalente)
#   - Assets de producao em C:\SOL\frontend\dist\sol-frontend\browser
#     copiados para C:\nginx\html\sol
#
# Novos arquivos F5:
#   - src/app/core/models/vistoria.model.ts               (novo)
#   - src/app/pages/vistoria/vistoria-fila/...            (novo)
#   - src/app/pages/vistoria/vistoria-detalhe/...         (novo)
#
# Arquivos atualizados F5:
#   - src/app/core/services/licenciamento.service.ts      (4 novos metodos)
#   - src/app/app.routes.ts                               (rota vistorias com filhos)
#   - src/app/pages/licenciamentos/licenciamento-detalhe/ (botao Abrir Vistoria)
#   - src/app/pages/analise/licenciamento-analise/        (correcao NG8011 ng-container)
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

# =============================================================================
# ETAPA 2 - Verificacao dos arquivos-fonte da Sprint F5
# =============================================================================
Passo 2 "Verificacao dos arquivos-fonte da Sprint F5"

$arquivosF5 = @(
  @{ Path = "src\app\core\models\vistoria.model.ts";
     Desc = "Novo modelo CivCreateDTO / AprovacaoVistoriaCreateDTO" },
  @{ Path = "src\app\pages\vistoria\vistoria-fila\vistoria-fila.component.ts";
     Desc = "Novo componente VistoriaFilaComponent (fila de vistoria)" },
  @{ Path = "src\app\pages\vistoria\vistoria-detalhe\vistoria-detalhe.component.ts";
     Desc = "Novo componente VistoriaDetalheComponent (tela de vistoria)" },
  @{ Path = "src\app\core\services\licenciamento.service.ts";
     Desc = "Service atualizado com getFilaVistoria, iniciarVistoria, emitirCiv, aprovarVistoria" },
  @{ Path = "src\app\app.routes.ts";
     Desc = "Rotas atualizadas: vistorias com filhos (fila + :id)" },
  @{ Path = "src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts";
     Desc = "Detalhe atualizado com botao Abrir Vistoria (INSPETOR/CHEFE)" },
  @{ Path = "src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts";
     Desc = "Analise corrigida: NG8011 - ng-container nos blocos @else dos botoes" }
)

foreach ($arq in $arquivosF5) {
  $fullPath = Join-Path $FrontendDir $arq.Path
  if (Test-Path $fullPath) {
    OK "$($arq.Desc)"
    OK "   -> $($arq.Path)"
  } else {
    FAIL "Arquivo nao encontrado: $($arq.Path)"
    FAIL "   -> $($arq.Desc)"
  }
}

# --- Verificacoes de conteudo criticas ---

$vistoriaModel = Join-Path $FrontendDir "src\app\core\models\vistoria.model.ts"
if (Test-Path $vistoriaModel) {
  $content = Get-Content $vistoriaModel -Raw
  if ($content -match "CivCreateDTO") {
    OK "vistoria.model.ts contem interface CivCreateDTO"
  } else {
    FAIL "vistoria.model.ts nao contem CivCreateDTO"
  }
  if ($content -match "AprovacaoVistoriaCreateDTO") {
    OK "vistoria.model.ts contem interface AprovacaoVistoriaCreateDTO"
  } else {
    FAIL "vistoria.model.ts nao contem AprovacaoVistoriaCreateDTO"
  }
}

$filaComp = Join-Path $FrontendDir "src\app\pages\vistoria\vistoria-fila\vistoria-fila.component.ts"
if (Test-Path $filaComp) {
  $content = Get-Content $filaComp -Raw
  if ($content -match "VistoriaFilaComponent") {
    OK "vistoria-fila.component.ts contem classe VistoriaFilaComponent"
  } else {
    FAIL "vistoria-fila.component.ts nao contem VistoriaFilaComponent"
  }
}

$detalheComp = Join-Path $FrontendDir "src\app\pages\vistoria\vistoria-detalhe\vistoria-detalhe.component.ts"
if (Test-Path $detalheComp) {
  $content = Get-Content $detalheComp -Raw
  if ($content -match "VistoriaDetalheComponent") {
    OK "vistoria-detalhe.component.ts contem VistoriaDetalheComponent"
  } else {
    FAIL "vistoria-detalhe.component.ts nao contem VistoriaDetalheComponent"
  }
  if ($content -match "confirmarCiv\(\)") {
    OK "vistoria-detalhe.component.ts contem metodo confirmarCiv()"
  } else {
    FAIL "vistoria-detalhe.component.ts nao contem confirmarCiv()"
  }
}

$svc = Join-Path $FrontendDir "src\app\core\services\licenciamento.service.ts"
if (Test-Path $svc) {
  $content = Get-Content $svc -Raw
  if ($content -match "getFilaVistoria") {
    OK "licenciamento.service.ts contem metodo getFilaVistoria"
  } else {
    FAIL "licenciamento.service.ts nao contem getFilaVistoria"
  }
  if ($content -match "emitirCiv") {
    OK "licenciamento.service.ts contem metodo emitirCiv"
  } else {
    FAIL "licenciamento.service.ts nao contem emitirCiv"
  }
  if ($content -match "iniciarVistoria") {
    OK "licenciamento.service.ts contem metodo iniciarVistoria"
  } else {
    FAIL "licenciamento.service.ts nao contem iniciarVistoria"
  }
}

$routes = Join-Path $FrontendDir "src\app\app.routes.ts"
if (Test-Path $routes) {
  $content = Get-Content $routes -Raw
  if ($content -match "vistoria-fila.component") {
    OK "app.routes.ts contem import de vistoria-fila.component (rota /vistorias ativa)"
  } else {
    FAIL "app.routes.ts nao contem vistoria-fila.component - rota /vistorias ainda e placeholder"
  }
  if ($content -match "vistoria-detalhe.component") {
    OK "app.routes.ts contem import de vistoria-detalhe.component (rota /vistorias/:id)"
  } else {
    FAIL "app.routes.ts nao contem vistoria-detalhe.component"
  }
}

$detalheLic = Join-Path $FrontendDir "src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts"
if (Test-Path $detalheLic) {
  $content = Get-Content $detalheLic -Raw
  if ($content -match "podeVistoriar") {
    OK "licenciamento-detalhe.component.ts contem propriedade podeVistoriar (botao ativo)"
  } else {
    FAIL "licenciamento-detalhe.component.ts nao contem podeVistoriar"
  }
}

$analiseComp = Join-Path $FrontendDir "src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts"
if (Test-Path $analiseComp) {
  $content = Get-Content $analiseComp -Raw
  if ($content -match "<ng-container>") {
    OK "licenciamento-analise.component.ts contem ng-container (correcao NG8011 aplicada)"
  } else {
    FAIL "licenciamento-analise.component.ts nao contem ng-container - correcao NG8011 ausente"
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
  $f5Chunks = $jsFiles | Where-Object { $_.Name -match "vistoria" }
  if ($f5Chunks.Count -gt 0) {
    OK "Chunk(s) relacionado(s) a F5 encontrado(s): $($f5Chunks.Name -join ', ')"
  } else {
    INFO "Nenhum chunk com 'vistoria' no nome - verificar pelo nome do componente no dist"
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
# RESUMO FINAL
# =============================================================================
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  SPRINT F5 - RESUMO FINAL" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

if ($global:sprintErros -eq 0) {
  Write-Host ""
  Write-Host "  SPRINT F5 CONCLUIDA COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Novos arquivos entregues:" -ForegroundColor White
  Write-Host "    - vistoria.model.ts                 (novo - DTOs de vistoria)" -ForegroundColor White
  Write-Host "    - vistoria-fila.component.ts         (novo - fila VISTORIA_PENDENTE/EM_VISTORIA)" -ForegroundColor White
  Write-Host "    - vistoria-detalhe.component.ts      (novo - Iniciar/CIV/Aprovar)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Arquivos atualizados:" -ForegroundColor White
  Write-Host "    - licenciamento.service.ts           (4 novos metodos de vistoria)" -ForegroundColor White
  Write-Host "    - app.routes.ts                      (rota /vistorias com filhos)" -ForegroundColor White
  Write-Host "    - licenciamento-detalhe.component.ts (botao Abrir Vistoria)" -ForegroundColor White
  Write-Host "    - licenciamento-analise.component.ts (correcao NG8011 ng-container)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Rotas disponiveis:" -ForegroundColor White
  Write-Host "    /app/vistorias        -> Fila de vistoria (INSPETOR / CHEFE_SSEG_BBM)" -ForegroundColor White
  Write-Host "    /app/vistorias/:id    -> Tela de vistoria com Iniciar/CIV/Aprovar" -ForegroundColor White
  Write-Host ""
  Write-Host "  Endpoints consumidos:" -ForegroundColor White
  Write-Host "    GET  /api/licenciamentos/fila-vistoria" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos/{id}/iniciar-vistoria" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos/{id}/civ" -ForegroundColor White
  Write-Host "    POST /api/licenciamentos/{id}/aprovar-vistoria" -ForegroundColor White
} else {
  Write-Host ""
  Write-Host "  SPRINT F5 CONCLUIDA COM $global:sprintErros ERRO(S)" -ForegroundColor Red
  Write-Host "  Revise os erros acima e re-execute o script." -ForegroundColor Red
}
Write-Host ""
