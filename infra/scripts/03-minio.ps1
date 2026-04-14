# =============================================================================
# 03-minio.ps1
# Sprint 0 — SOL Autônomo Windows
# Baixa, instala e configura MinIO como serviço Windows
# Execute como Administrador
# =============================================================================

param(
    [string]$InstallDir = "C:\SOL\infra\minio",
    [string]$DataDir = "C:\SOL\data\minio",
    [string]$RootUser = "solminio",
    [string]$RootPassword = "MinIO@SOL2026",
    [int]$ApiPort = 9000,
    [int]$ConsolePort = 9001
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\03-minio.log"
$DownloadUrl = "https://dl.min.io/server/minio/release/windows-amd64/minio.exe"
$MinioExe = "$InstallDir\minio.exe"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Iniciando instalação do MinIO ==="

# Criar diretórios
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null

# Baixar MinIO
if (-not (Test-Path $MinioExe)) {
    Write-Log "Baixando MinIO de $DownloadUrl ..."
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $MinioExe)
    Write-Log "Download concluído: $MinioExe"
} else {
    Write-Log "MinIO já baixado: $MinioExe"
}

# Configurar variáveis de ambiente
[System.Environment]::SetEnvironmentVariable("MINIO_ROOT_USER", $RootUser, "Machine")
[System.Environment]::SetEnvironmentVariable("MINIO_ROOT_PASSWORD", $RootPassword, "Machine")
$env:MINIO_ROOT_USER = $RootUser
$env:MINIO_ROOT_PASSWORD = $RootPassword

# Registrar como serviço Windows via NSSM
$svcName = "SOL-MinIO"
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removendo serviço existente $svcName..."
    & nssm stop $svcName 2>$null
    & nssm remove $svcName confirm
}

Write-Log "Registrando MinIO como serviço Windows ($svcName)..."
& nssm install $svcName $MinioExe
& nssm set $svcName AppParameters "server $DataDir --address :$ApiPort --console-address :$ConsolePort"
& nssm set $svcName AppDirectory $InstallDir
& nssm set $svcName DisplayName "SOL - MinIO Object Storage"
& nssm set $svcName Description "MinIO - Servidor de arquivos do SOL CBM-RS"
& nssm set $svcName Start SERVICE_AUTO_START
& nssm set $svcName AppStdout "C:\SOL\logs\minio-stdout.log"
& nssm set $svcName AppStderr "C:\SOL\logs\minio-stderr.log"
& nssm set $svcName AppEnvironmentExtra "MINIO_ROOT_USER=$RootUser" "MINIO_ROOT_PASSWORD=$RootPassword"

Write-Log "Iniciando serviço MinIO..."
Start-Service -Name $svcName
Start-Sleep -Seconds 5

$svc = Get-Service -Name $svcName
Write-Log "Status do serviço: $($svc.Status)"

Write-Log "========================================"
Write-Log "03-minio.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  API:      http://localhost:$ApiPort"
Write-Log "  Console:  http://localhost:$ConsolePort"
Write-Log "  Usuário:  $RootUser"
Write-Log "  Senha:    $RootPassword"
Write-Log "  Dados:    $DataDir"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 04-nginx.ps1"
Write-Log "DEPOIS:        Execute 07-minio-buckets.ps1 para criar os buckets"
