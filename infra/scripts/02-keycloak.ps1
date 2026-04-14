# =============================================================================
# 02-keycloak.ps1
# Sprint 0 — SOL Autônomo Windows
# Baixa, instala e configura Keycloak 24 como serviço Windows
# Execute como Administrador
# =============================================================================

param(
    [string]$KeycloakVersion = "24.0.3",
    [string]$InstallDir = "C:\SOL\infra\keycloak",
    [string]$AdminUser = "admin",
    [string]$AdminPassword = "Keycloak@Admin2026",
    [int]$Port = 8180
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\02-keycloak.log"
$DownloadUrl = "https://github.com/keycloak/keycloak/releases/download/$KeycloakVersion/keycloak-$KeycloakVersion.zip"
$ZipPath = "C:\SOL\instaladores\keycloak-$KeycloakVersion.zip"
$ExtractDir = "C:\SOL\instaladores\keycloak-extract"
$KeycloakDir = "$InstallDir\keycloak-$KeycloakVersion"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Iniciando instalação do Keycloak $KeycloakVersion ==="

# Criar diretórios
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path "C:\SOL\data\keycloak" -Force | Out-Null

# Baixar Keycloak
if (-not (Test-Path $ZipPath)) {
    Write-Log "Baixando Keycloak $KeycloakVersion de $DownloadUrl ..."
    Write-Log "(Isso pode demorar alguns minutos dependendo da conexão)"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $ZipPath)
    Write-Log "Download concluído: $ZipPath"
} else {
    Write-Log "Arquivo já existe: $ZipPath"
}

# Extrair
if (-not (Test-Path $KeycloakDir)) {
    Write-Log "Extraindo Keycloak..."
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    Move-Item -Path "$ExtractDir\keycloak-$KeycloakVersion" -Destination $KeycloakDir
    Write-Log "Extraído em: $KeycloakDir"
} else {
    Write-Log "Já extraído em: $KeycloakDir"
}

# Criar arquivo de configuração keycloak.conf
$keycloakConf = @"
# Keycloak Configuration — SOL Autônomo
# Gerado por 02-keycloak.ps1

# HTTP
http-port=$Port
hostname=localhost
hostname-strict=false
hostname-strict-https=false

# Banco de dados (H2 embarcado para ambiente simples)
# Para produção, considere migrar para Oracle ou PostgreSQL
db=dev-file
db-url-path=C:/SOL/data/keycloak/keycloak-db

# Log
log=console,file
log-file=C:/SOL/logs/keycloak.log
log-level=info

# Desabilitar HTTPS em ambiente interno (habilitar para produção com certificado)
http-enabled=true
"@
Set-Content -Path "$KeycloakDir\conf\keycloak.conf" -Value $keycloakConf
Write-Log "Arquivo keycloak.conf configurado na porta $Port"

# Criar conta admin inicial via variáveis de ambiente
[System.Environment]::SetEnvironmentVariable("KEYCLOAK_ADMIN", $AdminUser, "Machine")
[System.Environment]::SetEnvironmentVariable("KEYCLOAK_ADMIN_PASSWORD", $AdminPassword, "Machine")

# Fazer build do Keycloak (necessário antes de iniciar como serviço)
Write-Log "Executando build do Keycloak (pode demorar ~2 minutos)..."
$buildProcess = Start-Process -FilePath "$KeycloakDir\bin\kc.bat" `
    -ArgumentList "build" `
    -WorkingDirectory $KeycloakDir `
    -Wait -PassThru -NoNewWindow
if ($buildProcess.ExitCode -ne 0) {
    Write-Log "AVISO: Build do Keycloak retornou código $($buildProcess.ExitCode)" "WARN"
}
Write-Log "Build do Keycloak concluído."

# Registrar como serviço Windows via NSSM
$svcName = "SOL-Keycloak"
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removendo serviço existente $svcName..."
    & nssm stop $svcName 2>$null
    & nssm remove $svcName confirm
}

Write-Log "Registrando Keycloak como serviço Windows ($svcName)..."
& nssm install $svcName "$KeycloakDir\bin\kc.bat"
& nssm set $svcName AppParameters "start --http-port=$Port"
& nssm set $svcName AppDirectory $KeycloakDir
& nssm set $svcName DisplayName "SOL - Keycloak Identity Provider"
& nssm set $svcName Description "Keycloak $KeycloakVersion - Provedor de Identidade do SOL CBM-RS"
& nssm set $svcName Start SERVICE_AUTO_START
& nssm set $svcName AppStdout "C:\SOL\logs\keycloak-stdout.log"
& nssm set $svcName AppStderr "C:\SOL\logs\keycloak-stderr.log"
& nssm set $svcName AppEnvironmentExtra "KEYCLOAK_ADMIN=$AdminUser" "KEYCLOAK_ADMIN_PASSWORD=$AdminPassword"

Write-Log "Iniciando serviço Keycloak..."
Start-Service -Name $svcName
Start-Sleep -Seconds 15

# Verificar se iniciou
$svc = Get-Service -Name $svcName
Write-Log "Status do serviço: $($svc.Status)"

Write-Log "========================================"
Write-Log "02-keycloak.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  Console Admin: http://localhost:$Port"
Write-Log "  Usuário admin: $AdminUser"
Write-Log "  Senha admin:   $AdminPassword"
Write-Log "  Serviço:       $svcName"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 03-minio.ps1"
Write-Log "DEPOIS:        Execute 06-keycloak-realm.ps1 para criar o realm SOL"
