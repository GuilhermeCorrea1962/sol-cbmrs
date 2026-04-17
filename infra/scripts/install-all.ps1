###############################################################################
# install-all.ps1 -- Instalador Mestre do SOL CBM-RS
#
# Executa todos os passos de instalacao em sequencia com verificacao
# entre cada etapa. Pode ser interrompido e re-executado com seguranca:
# cada script individual verifica se o componente ja esta instalado.
#
# PREREQUISITO OBRIGATORIO (manual, antes de executar este script):
#   Oracle XE 21c instalado a partir de:
#   https://www.oracle.com/database/technologies/xe-downloads.html
#
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-all.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-all.ps1 -SysPassword MinhaS3nha
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-all.ps1 -PularAte 5
#
# Parametros:
#   -SysPassword   Senha SYS definida durante a instalacao do Oracle XE
#   -PularAte      Numero do passo a partir do qual retomar (1-14)
#   -ApenasVerify  Executa apenas a verificacao final (passos 13 e 14)
###############################################################################

param(
    [string]$SysPassword            = "",
    [string]$KeycloakAdminPassword  = "Keycloak@Admin2026",
    [int]   $PularAte               = 1,
    [switch]$ApenasVerify
)

$ErrorActionPreference = "Continue"
$ScriptsDir = $PSScriptRoot
$LogFile    = "C:\SOL\logs\install-all.log"

$global:PassoAtual = 0
$global:Erros      = 0
$global:Avisos     = 0

# ===========================================================================
# Helpers
# ===========================================================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Banner {
    param([string]$Titulo)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Titulo" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Passo {
    param(
        [int]    $Numero,
        [string] $Titulo,
        [scriptblock] $Acao,
        [scriptblock] $Verificacao = $null
    )
    $global:PassoAtual = $Numero

    if ($Numero -lt $PularAte) {
        Write-Host "  [SKIP] Passo $Numero - $Titulo (PularAte=$PularAte)" -ForegroundColor DarkGray
        return
    }

    Write-Banner "PASSO $Numero / 14 -- $Titulo"
    Write-Log "==> Iniciando passo ${Numero}: $Titulo"

    try {
        & $Acao
    } catch {
        Write-Log "ERRO no passo ${Numero}: $_" "ERROR"
        $global:Erros++
        Write-Host ""
        Write-Host "  [ERRO] Passo $Numero falhou. Deseja continuar mesmo assim? (S/N)" -ForegroundColor Red
        $resp = Read-Host
        if ($resp -notin @("S","s","sim","SIM")) {
            Write-Log "Instalacao interrompida pelo usuario no passo $Numero."
            Mostrar-Resumo
            exit 1
        }
        Write-Log "Continuando apesar do erro no passo $Numero..." "WARN"
        return
    }

    # Verificacao pos-passo
    if ($null -ne $Verificacao) {
        Start-Sleep -Seconds 3
        try {
            $ok = & $Verificacao
            if ($ok) {
                Write-Log "[OK] Verificacao do passo $Numero passou."
            } else {
                Write-Log "[WARN] Verificacao do passo $Numero indicou problema." "WARN"
                $global:Avisos++
            }
        } catch {
            Write-Log "[WARN] Verificacao do passo $Numero lancou excecao: $_" "WARN"
            $global:Avisos++
        }
    }

    Write-Log "==> Passo $Numero concluido."
    Start-Sleep -Seconds 2
}

function Mostrar-Resumo {
    Write-Banner "RESUMO DA INSTALACAO"
    Write-Host "  Ultimo passo executado : $global:PassoAtual / 14" -ForegroundColor White
    Write-Host "  Erros encontrados      : $global:Erros"  -ForegroundColor $(if ($global:Erros  -gt 0) { "Red"    } else { "Green" })
    Write-Host "  Avisos encontrados     : $global:Avisos" -ForegroundColor $(if ($global:Avisos -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
    if ($global:Erros -eq 0 -and $global:PassoAtual -ge 14) {
        Write-Host "  INSTALACAO CONCLUIDA COM SUCESSO!" -ForegroundColor Green
        Write-Host "  Acesse o sistema: http://localhost/" -ForegroundColor Green
    } elseif ($global:Erros -eq 0) {
        Write-Host "  Instalacao em andamento. Retome com: -PularAte $($global:PassoAtual + 1)" -ForegroundColor Yellow
    } else {
        Write-Host "  Instalacao concluida com $global:Erros erro(s)." -ForegroundColor Red
        Write-Host "  Verifique os logs em C:\SOL\logs\" -ForegroundColor Red
        Write-Host "  Para retomar a partir do passo com erro: -PularAte $global:PassoAtual" -ForegroundColor Yellow
    }
    Write-Host "  Log completo: $LogFile" -ForegroundColor Gray
    Write-Host ""
}

# ===========================================================================
# Verificacoes iniciais
# ===========================================================================
if (-not (Test-Administrator)) {
    Write-Host "ERRO: Execute este script como Administrador." -ForegroundColor Red
    Write-Host "  Clique com botao direito no PowerShell e escolha 'Executar como Administrador'."
    exit 1
}

New-Item -ItemType Directory -Path "C:\SOL\logs" -Force | Out-Null

Write-Banner "SOL CBM-RS -- Instalador Mestre"
Write-Log "Iniciando install-all.ps1  |  PularAte=$PularAte  |  ApenasVerify=$ApenasVerify"
Write-Host ""
Write-Host "  Este script instalara e configurara todos os componentes do SOL:" -ForegroundColor White
Write-Host "    Oracle XE schema, Keycloak, MinIO, Nginx, Spring Boot backend," -ForegroundColor White
Write-Host "    Angular frontend e MailHog." -ForegroundColor White
Write-Host ""

if ($ApenasVerify) {
    $PularAte = 13
    Write-Host "  Modo ApenasVerify: executando apenas passos 13 e 14." -ForegroundColor Yellow
}

# Verificar Oracle XE instalado (prerequisito obrigatorio)
if ($PularAte -le 3) {
    $oracleSvc = Get-Service -Name "OracleServiceXE" -ErrorAction SilentlyContinue
    if ($null -eq $oracleSvc) {
        Write-Host ""
        Write-Host "  ATENCAO: Oracle XE nao detectado (servico OracleServiceXE ausente)." -ForegroundColor Red
        Write-Host ""
        Write-Host "  ACAO NECESSARIA ANTES DE CONTINUAR:" -ForegroundColor Yellow
        Write-Host "    1. Acesse: https://www.oracle.com/database/technologies/xe-downloads.html" -ForegroundColor Yellow
        Write-Host "    2. Baixe:  Oracle Database 21c Express Edition for Windows x64" -ForegroundColor Yellow
        Write-Host "    3. Execute o instalador como Administrador" -ForegroundColor Yellow
        Write-Host "    4. Anote a senha do SYS e execute novamente:" -ForegroundColor Yellow
        Write-Host "       .\install-all.ps1 -SysPassword <sua_senha>" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Deseja continuar mesmo sem Oracle? (N recomendado)" -ForegroundColor Red
        $resp = Read-Host "(S = continuar / N = sair)"
        if ($resp -notin @("S","s")) {
            Write-Host "Instalacao cancelada. Instale o Oracle XE e execute novamente." -ForegroundColor Yellow
            exit 0
        }
    } else {
        Write-Log "Oracle XE detectado. Status: $($oracleSvc.Status)"
        if ([string]::IsNullOrEmpty($SysPassword)) {
            Write-Host ""
            Write-Host "  Oracle XE detectado. Informe a senha SYS para configurar o schema SOL:" -ForegroundColor Yellow
            $SysPassword = Read-Host "  Senha SYS do Oracle XE"
        }
    }
}

# ===========================================================================
# PASSOS DE INSTALACAO
# ===========================================================================

# ---------------------------------------------------------------------------
# PASSO 1 -- Pre-requisitos (Java, Node, Maven, NSSM, Angular CLI)
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 1 -Titulo "Pre-requisitos (Java 21, Node.js, Maven, NSSM, Angular CLI)" -Acao {
    & "$ScriptsDir\00-prerequisites.ps1"
} -Verificacao {
    $java = java -version 2>&1 | Select-String "21\."
    $node = node --version 2>&1
    $mvn  = mvn  --version 2>&1 | Select-Object -First 1
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    $null -ne $java -and $null -ne $node -and $null -ne $mvn -and $null -ne $nssm
}

# Recarregar PATH apos instalacao de ferramentas
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

# ---------------------------------------------------------------------------
# PASSO 2 -- Oracle XE: criar tablespace e usuario SOL
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 2 -Titulo "Oracle XE -- Criar tablespace SOL_DATA e usuario SOL" -Acao {
    if ([string]::IsNullOrEmpty($SysPassword)) {
        throw "SysPassword nao informado. Execute: .\install-all.ps1 -SysPassword <senha>"
    }
    & "$ScriptsDir\01-oracle-xe.ps1" -SysPassword $SysPassword
} -Verificacao {
    Test-Path "C:\SOL\data\oracle\connection.properties"
}

# ---------------------------------------------------------------------------
# PASSO 3 -- Keycloak 24.0.3
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 3 -Titulo "Keycloak 24.0.3 (porta 8180)" -Acao {
    & "$ScriptsDir\02-keycloak.ps1"
} -Verificacao {
    $svc = Get-Service -Name "SOL-Keycloak" -ErrorAction SilentlyContinue
    $null -ne $svc -and $svc.Status -eq "Running"
}

# ---------------------------------------------------------------------------
# PASSO 4 -- MinIO
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 4 -Titulo "MinIO Object Storage (porta 9000 / console 9001)" -Acao {
    & "$ScriptsDir\03-minio.ps1"
} -Verificacao {
    $svc = Get-Service -Name "SOL-MinIO" -ErrorAction SilentlyContinue
    $null -ne $svc -and $svc.Status -eq "Running"
}

# ---------------------------------------------------------------------------
# PASSO 5 -- Nginx
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 5 -Titulo "Nginx 1.26.2 (porta 80)" -Acao {
    & "$ScriptsDir\04-nginx.ps1"
} -Verificacao {
    $svc = Get-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
    $null -ne $svc -and $svc.Status -eq "Running"
}

# ---------------------------------------------------------------------------
# PASSO 6 -- Compilar backend (Maven)
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 6 -Titulo "Compilar backend Spring Boot (mvn clean package)" -Acao {
    Write-Log "Compilando backend em C:\SOL\backend ..."
    Push-Location "C:\SOL\backend"
    try {
        $out = & mvn clean package -DskipTests 2>&1
        if ($LASTEXITCODE -ne 0) {
            $out | ForEach-Object { Write-Log $_ }
            throw "Build Maven falhou (exit code $LASTEXITCODE)"
        }
        Write-Log "Build Maven concluido com sucesso."
    } finally {
        Pop-Location
    }
} -Verificacao {
    Test-Path "C:\SOL\backend\target\sol-backend-1.0.0.jar"
}

# ---------------------------------------------------------------------------
# PASSO 7 -- Registrar backend como servico Windows
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 7 -Titulo "Registrar SOL Backend como servico Windows (porta 8080)" -Acao {
    & "$ScriptsDir\05-sol-service.ps1"
} -Verificacao {
    Start-Sleep -Seconds 15  # aguardar Spring Boot + Hibernate DDL
    try {
        $h = Invoke-RestMethod -Uri "http://localhost:8080/api/actuator/health" -TimeoutSec 20
        $h.status -eq "UP"
    } catch { $false }
}

# ---------------------------------------------------------------------------
# PASSO 8 -- Importar realm SOL no Keycloak
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 8 -Titulo "Importar realm 'sol' no Keycloak" -Acao {
    # Aguardar Keycloak estar responsivo
    Write-Log "Aguardando Keycloak estar disponivel em :8180 ..."
    $tentativas = 0
    while ($tentativas -lt 20) {
        try {
            Invoke-RestMethod -Uri "http://localhost:8180/realms/master" -TimeoutSec 5 | Out-Null
            Write-Log "Keycloak disponivel."
            break
        } catch {
            $tentativas++
            Write-Log "Tentativa $tentativas/20 -- aguardando Keycloak..."
            Start-Sleep -Seconds 5
        }
    }
    & "$ScriptsDir\06-keycloak-realm.ps1" -AdminPassword $KeycloakAdminPassword
} -Verificacao {
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:8180/realms/sol" -TimeoutSec 10
        $r.realm -eq "sol"
    } catch { $false }
}

# ---------------------------------------------------------------------------
# PASSO 9 -- Criar buckets e usuario no MinIO
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 9 -Titulo "Criar buckets MinIO e usuario sol-app" -Acao {
    & "$ScriptsDir\07-minio-buckets.ps1"
} -Verificacao {
    Test-Path "C:\SOL\infra\minio\mc.exe"
}

# ---------------------------------------------------------------------------
# PASSO 10 -- Build do frontend Angular
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 10 -Titulo "Build do frontend Angular (ng build --configuration production)" -Acao {
    Write-Log "Instalando dependencias npm em C:\SOL\frontend ..."
    Push-Location "C:\SOL\frontend"
    try {
        & npm ci --prefer-offline 2>&1 | ForEach-Object { Write-Log $_ }
        Write-Log "Executando ng build --configuration production ..."
        $out = & npx ng build --configuration production 2>&1
        $out | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path "dist\sol-frontend\browser\index.html")) {
            throw "ng build falhou (exit code $LASTEXITCODE)"
        }
        Write-Log "Build Angular concluido."
    } finally {
        Pop-Location
    }
} -Verificacao {
    Test-Path "C:\SOL\frontend\dist\sol-frontend\browser\index.html"
}

# ---------------------------------------------------------------------------
# PASSO 11 -- Reiniciar Nginx para servir o novo dist
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 11 -Titulo "Reiniciar Nginx para publicar o frontend" -Acao {
    $nginxBase = "C:\SOL\infra\nginx\nginx-1.26.2"
    $nginxExe  = "$nginxBase\nginx.exe"
    # Garantir pasta temp (necessaria para Nginx no Windows)
    New-Item -ItemType Directory -Path "$nginxBase\temp" -Force | Out-Null
    # Teste de configuracao antes de reiniciar
    if (Test-Path $nginxExe) {
        $test = & $nginxExe -t -c "$nginxBase\conf\nginx.conf" 2>&1
        Write-Log "Nginx config test: $test"
    }
    Stop-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    $svc = Get-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq "Running") {
        Write-Log "Nginx iniciado com sucesso."
    } else {
        $stderr = Get-Content "C:\SOL\logs\nginx-stderr.log" -Tail 5 -ErrorAction SilentlyContinue
        Write-Log "AVISO: Nginx nao iniciou. Ultimo log: $stderr" "WARN"
    }
} -Verificacao {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10
        $r.StatusCode -in 200, 304
    } catch { $false }
}

# ---------------------------------------------------------------------------
# PASSO 12 -- MailHog (SMTP de desenvolvimento)
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 12 -Titulo "MailHog SMTP de desenvolvimento (porta 1025 / web 8025)" -Acao {
    & "$ScriptsDir\08.5-mailhog.ps1"
} -Verificacao {
    $svc = Get-Service -Name "SOL-MailHog" -ErrorAction SilentlyContinue
    $null -ne $svc -and $svc.Status -eq "Running"
}

# ---------------------------------------------------------------------------
# PASSO 13 -- Criar usuarios iniciais no Keycloak
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 13 -Titulo "Criar usuarios iniciais no Keycloak (sol-admin, analista)" -Acao {
    & "$ScriptsDir\setup-test-user.ps1"
    & "$ScriptsDir\_create_analista.ps1" -ErrorAction SilentlyContinue
} -Verificacao {
    try {
        $body = "grant_type=password&client_id=sol-frontend&username=sol-admin&password=Admin@SOL2026"
        $r = Invoke-RestMethod -Uri "http://localhost:8180/realms/sol/protocol/openid-connect/token" `
            -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 10
        $null -ne $r.access_token
    } catch { $false }
}

# ---------------------------------------------------------------------------
# PASSO 14 -- Verificacao completa do ambiente
# ---------------------------------------------------------------------------
Invoke-Passo -Numero 14 -Titulo "Verificacao completa do ambiente" -Acao {
    & "$ScriptsDir\08-verify-all.ps1"
    Write-Host ""
    Write-Host "--- Verificacao funcional da API ---" -ForegroundColor Cyan
    & "$ScriptsDir\verify-sol.ps1"
}

# ===========================================================================
# RESUMO FINAL
# ===========================================================================
Mostrar-Resumo

if ($global:Erros -eq 0 -and $global:PassoAtual -ge 14) {
    Write-Host ""
    Write-Host "  Servicos Windows instalados e rodando:" -ForegroundColor Green
    Write-Host "    SOL-Backend   -> http://localhost:8080/api/actuator/health" -ForegroundColor Green
    Write-Host "    SOL-Keycloak  -> http://localhost:8180/realms/sol" -ForegroundColor Green
    Write-Host "    SOL-MinIO     -> http://localhost:9001  (console)" -ForegroundColor Green
    Write-Host "    SOL-Nginx     -> http://localhost/      (frontend)" -ForegroundColor Green
    Write-Host "    SOL-MailHog   -> http://localhost:8025  (caixa de e-mail)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Credenciais de acesso:" -ForegroundColor Cyan
    Write-Host "    Admin SOL     : sol-admin / Admin@SOL2026" -ForegroundColor White
    Write-Host "    Keycloak Admin: admin / Keycloak@Admin2026" -ForegroundColor White
    Write-Host "    MinIO Console : solminio / MinIO@SOL2026" -ForegroundColor White
    Write-Host "    Oracle SOL    : sol / Sol@CBM2026" -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host "  ACESSE O SISTEMA: http://localhost/" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host ""
}
