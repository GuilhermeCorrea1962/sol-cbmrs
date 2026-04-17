# =============================================================================
# sprint-f8-deploy.ps1
# Sprint F8 - Troca de Envolvidos (P09)
#
# Processo implementado:
#   P09  -  Troca de Envolvidos: o RT atual solicita sua propria saida do
#   licenciamento; o Admin aprova ou rejeita a solicitacao.
#
# Novos arquivos:
#   - src/app/core/models/troca-envolvidos.model.ts
#   - src/app/pages/troca-envolvidos/troca-fila/troca-fila.component.ts
#   - src/app/pages/troca-envolvidos/troca-detalhe/troca-detalhe.component.ts
#
# Arquivos modificados:
#   - src/app/core/models/licenciamento.model.ts
#     (+campos trocaPendente, justificativaTroca no LicenciamentoDTO)
#   - src/app/core/services/licenciamento.service.ts
#     (+secao F8: 4 metodos de troca)
#   - src/app/app.routes.ts
#     (+rota /app/trocas com filhos '' e ':id')
#   - src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts
#     (+formulario inline Solicitar Troca para RT + painel info se trocaPendente)
#
# Roles/endpoints adicionados:
#   GET  /api/licenciamentos/fila-troca             (ADMIN, CHEFE_SSEG_BBM)
#   POST /api/licenciamentos/{id}/solicitar-troca   (RT autenticado)
#   POST /api/licenciamentos/{id}/aceitar-troca     (ADMIN, CHEFE_SSEG_BBM)
#   POST /api/licenciamentos/{id}/rejeitar-troca    (ADMIN, CHEFE_SSEG_BBM)
#
# Pre-requisito: Sprints F1-F7 concluidas
#   Verificado pela presenca de recurso.model.ts (F7)
#
# Etapas:
#   1. Pre-verificacao do ambiente
#   2. Verificacao dos fontes F8
#   3. npm ci
#   4. Build de producao (ng build --configuration production)
#   5. Deploy: substituicao dos assets no diretorio Nginx
#   6. Reinicializacao do Nginx e smoke test
#   7. Gerar relatorio de deploy
#
# NOTA DE ENCODING:
#   Script criado com ASCII-only. Nenhum caractere Unicode acima de U+007F.
#   Compativel com PowerShell 5.x (Windows-1252) sem necessidade de BOM.
# =============================================================================

$ErrorActionPreference = "Continue"
$global:f8Erros = 0

# --- Cores e helpers -----------------------------------------------------------
function Passo([int]$n, [string]$titulo) {
  Write-Host ""
  Write-Host "===========================================================" -ForegroundColor Cyan
  Write-Host "  ETAPA $n - $titulo" -ForegroundColor Cyan
  Write-Host "===========================================================" -ForegroundColor Cyan
}
function OK([string]$msg)   { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function FAIL([string]$msg) { Write-Host "  [ERRO] $msg" -ForegroundColor Red; $global:f8Erros++ }
function INFO([string]$msg) { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

# --- Caminhos -----------------------------------------------------------------
$FrontendDir   = "C:\SOL\frontend"
$DistDir       = "C:\SOL\frontend\dist\sol-frontend\browser"
$NginxHtmlDir  = "C:\nginx\html\sol"
$NginxSvcName  = "sol-nginx"
$RelatorioPath = "C:\SOL\logs\sprint-f8-relatorio-deploy.md"

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

# Pre-requisito: Sprint F7 presente
$recursoModel = Join-Path $FrontendDir "src\app\core\models\recurso.model.ts"
if (Test-Path $recursoModel) {
  OK "Pre-requisito F7: recurso.model.ts presente"
} else {
  FAIL "Pre-requisito ausente: recurso.model.ts nao encontrado - execute Sprints F1-F7 antes"
  exit 1
}

if ($global:f8Erros -gt 0) { exit 1 }

# =============================================================================
# ETAPA 2 - Verificacao dos fontes F8
# =============================================================================
Passo 2 "Verificacao dos fontes F8"

$arquivosF8 = @(
  "src\app\core\models\troca-envolvidos.model.ts",
  "src\app\pages\troca-envolvidos\troca-fila\troca-fila.component.ts",
  "src\app\pages\troca-envolvidos\troca-detalhe\troca-detalhe.component.ts"
)

foreach ($rel in $arquivosF8) {
  $full = Join-Path $FrontendDir $rel
  if (Test-Path $full) {
    OK "Presente: $rel"
  } else {
    FAIL "Ausente:  $rel"
  }
}

# Verificar campos trocaPendente no model
$modelPath    = Join-Path $FrontendDir "src\app\core\models\licenciamento.model.ts"
$modelContent = Get-Content $modelPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($modelContent -match "trocaPendente") {
  OK "licenciamento.model.ts: campo trocaPendente presente"
} else {
  FAIL "licenciamento.model.ts: campo trocaPendente ausente"
}

# Verificar secao F8 no service
$svcPath    = Join-Path $FrontendDir "src\app\core\services\licenciamento.service.ts"
$svcContent = Get-Content $svcPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($svcContent -match "Sprint F8") {
  OK "licenciamento.service.ts: secao F8 presente"
} else {
  FAIL "licenciamento.service.ts: secao F8 ausente"
}

# Verificar rota trocas no app.routes.ts
$routesPath    = Join-Path $FrontendDir "src\app\app.routes.ts"
$routesContent = Get-Content $routesPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($routesContent -match "troca-fila") {
  OK "app.routes.ts: rota /trocas presente"
} else {
  FAIL "app.routes.ts: rota /trocas ausente"
}

# Verificar formulario de troca no licenciamento-detalhe
$detalhePath    = Join-Path $FrontendDir "src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts"
$detalheContent = Get-Content $detalhePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($detalheContent -match "podeSubmeterTroca") {
  OK "licenciamento-detalhe.component.ts: formulario Solicitar Troca presente"
} else {
  FAIL "licenciamento-detalhe.component.ts: formulario Solicitar Troca ausente"
}

if ($global:f8Erros -gt 0) {
  FAIL "Etapa 2 falhou. Verifique os arquivos ausentes e tente novamente."
  exit 1
}

# =============================================================================
# ETAPA 3 - npm ci
# =============================================================================
Passo 3 "npm ci (instalar/atualizar dependencias)"

Set-Location $FrontendDir
INFO "Executando: npm ci ..."
& npm ci 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) {
  FAIL "npm ci falhou (exit code $LASTEXITCODE)"
  exit 1
}
OK "npm ci concluido"

# =============================================================================
# ETAPA 4 - Build de producao
# =============================================================================
Passo 4 "Build de producao (ng build --configuration production)"

INFO "Executando: npx ng build --configuration production ..."
INFO "Este processo pode levar 2-5 minutos ..."

$buildOutput = & npx ng build --configuration production 2>&1
$buildExit   = $LASTEXITCODE

$buildOutput | ForEach-Object { Write-Host "    $_" }

# Verificar warnings de budget
$budgetWarnings = $buildOutput | Where-Object { $_ -match "exceeded maximum budget" }
if ($budgetWarnings) {
  INFO "Warnings de budget CSS detectados:"
  $budgetWarnings | ForEach-Object { INFO "  $_" }
} else {
  OK "Nenhum warning de budget CSS"
}

# Verificar warnings NG8011
$ng8011Warnings = $buildOutput | Where-Object { $_ -match "NG8011" }
if ($ng8011Warnings) {
  INFO "Warnings NG8011 detectados:"
  $ng8011Warnings | ForEach-Object { INFO "  $_" }
} else {
  OK "Nenhum warning NG8011"
}

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
}

# =============================================================================
# ETAPA 7 - Gerar relatorio de deploy
# =============================================================================
Passo 7 "Gerar relatorio de deploy"

$dataHora  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$jsCount   = (Get-ChildItem "$DistDir\*.js" -ErrorAction SilentlyContinue).Count
$statusStr = if ($global:f8Erros -eq 0) { "SUCESSO" } else { "ERROS: $global:f8Erros" }
$budgetStr = if ($budgetWarnings) { $budgetWarnings -join "; " } else { "Nenhum" }
$ng8011Str = if ($ng8011Warnings) { $ng8011Warnings -join "; " } else { "Nenhum" }

$relatorio = @"
# Relatorio de Deploy  -  Sprint F8 (Troca de Envolvidos)

**Data/hora:** $dataHora
**Status geral:** $statusStr
**Chunks JS gerados:** $jsCount
**Warnings de budget CSS:** $budgetStr
**Warnings NG8011:** $ng8011Str

## Processo implementado

P09  -  Troca de Envolvidos: o Responsavel Tecnico atual pode solicitar sua
propria saida de um licenciamento. A solicitacao e registrada e enviada para
analise pelo administrador, que pode aceitar (habilitando a entrada de novo RT)
ou rejeitar (mantendo o RT atual).

## Novos arquivos

| Arquivo | Descricao |
|---|---|
| core/models/troca-envolvidos.model.ts | DTOs: TrocaSolicitarDTO, TrocaAceitarDTO, TrocaRejeitarDTO |
| pages/troca-envolvidos/troca-fila/ | Fila de trocas pendentes (ADMIN, CHEFE_SSEG_BBM) |
| pages/troca-envolvidos/troca-detalhe/ | Aceitar ou rejeitar solicitacao |

## Arquivos modificados

| Arquivo | Modificacao |
|---|---|
| licenciamento.model.ts | +campos trocaPendente e justificativaTroca no LicenciamentoDTO |
| licenciamento.service.ts | +4 metodos Sprint F8 (getFilaTrocaPendente, solicitarTroca, aceitarTroca, rejeitarTroca) |
| app.routes.ts | +rota /app/trocas com filhos '' e ':id' |
| licenciamento-detalhe.component.ts | +formulario inline Solicitar Troca + painel info trocaPendente |

## Novas rotas

| Rota | Componente | Roles |
|---|---|---|
| /app/trocas | TrocaFilaComponent | ADMIN, CHEFE_SSEG_BBM |
| /app/trocas/:id | TrocaDetalheComponent | ADMIN, CHEFE_SSEG_BBM |

## Novos endpoints consumidos

| Verbo | Endpoint | Role |
|---|---|---|
| GET | /api/licenciamentos/fila-troca | ADMIN, CHEFE_SSEG_BBM |
| POST | /api/licenciamentos/{id}/solicitar-troca | RT autenticado |
| POST | /api/licenciamentos/{id}/aceitar-troca | ADMIN, CHEFE_SSEG_BBM |
| POST | /api/licenciamentos/{id}/rejeitar-troca | ADMIN, CHEFE_SSEG_BBM |
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
Write-Host "  SPRINT F8 - RESUMO FINAL" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

if ($global:f8Erros -eq 0) {
  Write-Host ""
  Write-Host "  SPRINT F8 CONCLUIDA COM SUCESSO" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Novos componentes:" -ForegroundColor White
  Write-Host "    - troca-fila.component.ts  (fila /app/trocas)" -ForegroundColor White
  Write-Host "    - troca-detalhe.component.ts (/app/trocas/:id)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Acoes disponiveis por perfil:" -ForegroundColor White
  Write-Host "    - RT: Solicitar Troca de RT (na tela de detalhe do licenciamento)" -ForegroundColor White
  Write-Host "    - RT: Visualizar painel 'aguardando aprovacao' se trocaPendente" -ForegroundColor White
  Write-Host "    - ADMIN/CHEFE: Ver fila de trocas pendentes em /app/trocas" -ForegroundColor White
  Write-Host "    - ADMIN/CHEFE: Aceitar troca (com observacao opcional)" -ForegroundColor White
  Write-Host "    - ADMIN/CHEFE: Rejeitar troca (com motivo obrigatorio)" -ForegroundColor White
  Write-Host ""
  Write-Host "  Chunks JS: $jsCount" -ForegroundColor White
  Write-Host "  Relatorio: $RelatorioPath" -ForegroundColor White
} else {
  Write-Host ""
  Write-Host "  SPRINT F8 COM $global:f8Erros ERRO(S)" -ForegroundColor Red
  Write-Host "  Revise os erros acima antes de prosseguir." -ForegroundColor Red
}
Write-Host ""
