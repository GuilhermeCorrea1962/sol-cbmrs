# =============================================================================
# 08.5-mailhog.ps1
# SOL Autonomo Windows
# Instala e configura MailHog como servico Windows (SMTP de desenvolvimento)
# Execute como Administrador
# =============================================================================

param(
    [string]$InstallDir  = "C:\SOL\infra\mailhog",
    [int]   $SmtpPort   = 1025,
    [int]   $WebPort    = 8025,
    [string]$Version    = "1.0.1"
)

$ErrorActionPreference = "Stop"
$LogFile   = "C:\SOL\logs\08.5-mailhog.log"
$SvcName   = "SOL-MailHog"
$ExePath   = "$InstallDir\MailHog.exe"
$DownloadUrl = "https://github.com/mailhog/MailHog/releases/download/v$Version/MailHog_windows_amd64.exe"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "ERRO: Execute este script como Administrador." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $InstallDir    -Force | Out-Null
New-Item -ItemType Directory -Path "C:\SOL\logs"  -Force | Out-Null

Write-Log "=== Iniciando instalacao do MailHog $Version ==="

# --------------------------------------------------------------------------
# 1. Baixar MailHog.exe
# --------------------------------------------------------------------------
if (Test-Path $ExePath) {
    Write-Log "MailHog.exe ja existe em $ExePath — pulando download."
} else {
    Write-Log "Baixando MailHog v$Version ..."
    Write-Log "  URL: $DownloadUrl"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($DownloadUrl, $ExePath)
        Write-Log "Download concluido: $ExePath"
    } catch {
        # Fallback: tentar via Invoke-WebRequest
        Write-Log "WebClient falhou ($($_.Exception.Message)) — tentando Invoke-WebRequest..." "WARN"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath -UseBasicParsing
        Write-Log "Download concluido via Invoke-WebRequest."
    }
}

if (-not (Test-Path $ExePath)) {
    Write-Log "ERRO: MailHog.exe nao encontrado apos download." "ERROR"
    exit 1
}

# --------------------------------------------------------------------------
# 2. Remover servico anterior se existir
# --------------------------------------------------------------------------
$existingSvc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removendo servico existente '$SvcName'..."
    & nssm stop   $SvcName 2>$null
    Start-Sleep -Seconds 2
    & nssm remove $SvcName confirm
    Write-Log "Servico removido."
}

# --------------------------------------------------------------------------
# 3. Registrar como servico Windows via NSSM
# --------------------------------------------------------------------------
Write-Log "Registrando MailHog como servico Windows ($SvcName)..."

& nssm install $SvcName $ExePath
& nssm set $SvcName AppParameters    "-smtp-bind-addr 0.0.0.0:$SmtpPort -api-bind-addr 0.0.0.0:$WebPort"
& nssm set $SvcName AppDirectory     $InstallDir
& nssm set $SvcName DisplayName      "SOL - MailHog SMTP Dev Server"
& nssm set $SvcName Description      "MailHog $Version - Servidor SMTP de desenvolvimento do SOL CBM-RS"
& nssm set $SvcName Start            SERVICE_AUTO_START
& nssm set $SvcName AppStdout        "C:\SOL\logs\mailhog-stdout.log"
& nssm set $SvcName AppStderr        "C:\SOL\logs\mailhog-stderr.log"
& nssm set $SvcName AppRotateFiles   1
& nssm set $SvcName AppRotateBytes   5242880

# --------------------------------------------------------------------------
# 4. Iniciar servico
# --------------------------------------------------------------------------
Write-Log "Iniciando servico $SvcName ..."
Start-Service -Name $SvcName
Start-Sleep -Seconds 4

$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Write-Log "Servico $SvcName iniciado com sucesso. Status: $($svc.Status)"
} else {
    Write-Log "AVISO: Status do servico: $($svc.Status) — verifique C:\SOL\logs\mailhog-stderr.log" "WARN"
}

# --------------------------------------------------------------------------
# 5. Smoke test na Web UI
# --------------------------------------------------------------------------
Write-Log "Smoke test: GET http://localhost:$WebPort/api/v2/messages ..."
Start-Sleep -Seconds 2
try {
    $resp = Invoke-RestMethod -Uri "http://localhost:$WebPort/api/v2/messages" -TimeoutSec 8
    Write-Log "MailHog respondendo. Mensagens na caixa: $($resp.total)"
} catch {
    Write-Log "AVISO: Smoke test falhou — MailHog pode ainda estar inicializando. Tente: http://localhost:$WebPort" "WARN"
}

# --------------------------------------------------------------------------
# 6. Resumo
# --------------------------------------------------------------------------
Write-Log "========================================"
Write-Log "08.5-mailhog.ps1 concluido com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  Servico : $SvcName"
Write-Log "  SMTP    : localhost:$SmtpPort  (use no application.yml: spring.mail.port=$SmtpPort)"
Write-Log "  Web UI  : http://localhost:$WebPort"
Write-Log "  Exe     : $ExePath"
Write-Log ""
Write-Log "  application.yml ja configurado:"
Write-Log "    spring.mail.host=localhost"
Write-Log "    spring.mail.port=$SmtpPort"
Write-Log "    spring.mail.properties.mail.smtp.auth=false"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 08-verify-all.ps1 para verificar todo o ambiente."
