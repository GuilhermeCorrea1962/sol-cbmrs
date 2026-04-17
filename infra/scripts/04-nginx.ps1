# =============================================================================
# 04-nginx.ps1
# Sprint 0  -  SOL Autônomo Windows
# Baixa, instala e configura Nginx for Windows como serviço Windows
# Execute como Administrador
# =============================================================================

param(
    [string]$NginxVersion = "1.26.2",
    [string]$InstallDir = "C:\SOL\infra\nginx",
    [int]$HttpPort = 80,
    [int]$BackendPort = 8080,
    [int]$KeycloakPort = 8180,
    [string]$FrontendBuildDir = "C:/SOL/frontend/dist/sol-frontend/browser"
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\04-nginx.log"
$DownloadUrl = "https://nginx.org/download/nginx-$NginxVersion.zip"
$ZipPath = "C:\SOL\instaladores\nginx-$NginxVersion.zip"
$NginxDir = "$InstallDir\nginx-$NginxVersion"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Iniciando instalação do Nginx $NginxVersion ==="

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Baixar Nginx
if (-not (Test-Path $ZipPath)) {
    Write-Log "Baixando Nginx $NginxVersion..."
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $ZipPath)
    Write-Log "Download concluído."
} else {
    Write-Log "Arquivo já existe: $ZipPath"
}

# Extrair
if (-not (Test-Path $NginxDir)) {
    Write-Log "Extraindo Nginx..."
    Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force
    Write-Log "Extraído em: $NginxDir"
} else {
    Write-Log "Já extraído em: $NginxDir"
}

# Gerar nginx.conf
$nginxConf = @"
worker_processes  1;

error_log  C:/SOL/logs/nginx-error.log warn;
pid        C:/SOL/logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent"';

    access_log  C:/SOL/logs/nginx-access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    # Limite de upload  -  50MB para plantas e documentos técnicos
    client_max_body_size 50M;

    # Upstream  -  SOL Backend
    upstream sol_backend {
        server 127.0.0.1:$BackendPort;
    }

    # Upstream  -  Keycloak
    upstream keycloak {
        server 127.0.0.1:$KeycloakPort;
    }

    server {
        listen       $HttpPort;
        server_name  localhost;

        # Frontend Angular  -  arquivos estáticos
        root   $FrontendBuildDir;
        index  index.html;

        # Angular Router  -  redirecionar todas as rotas para index.html
        location / {
            try_files `$uri `$uri/ /index.html;
        }

        # API Backend  -  proxy para Spring Boot
        location /api/ {
            proxy_pass         http://sol_backend/api/;
            proxy_set_header   Host `$host;
            proxy_set_header   X-Real-IP `$remote_addr;
            proxy_set_header   X-Forwarded-For `$proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto `$scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout    60s;
            proxy_read_timeout    120s;
        }

        # Keycloak  -  proxy
        location /auth/ {
            proxy_pass         http://keycloak/auth/;
            proxy_set_header   Host `$host;
            proxy_set_header   X-Real-IP `$remote_addr;
            proxy_set_header   X-Forwarded-For `$proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto `$scheme;
            proxy_buffer_size  128k;
            proxy_buffers      4 256k;
            proxy_busy_buffers_size 256k;
        }

        # Segurança básica  -  ocultar versão do Nginx
        server_tokens off;

        # Headers de segurança
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;

        error_page 404 /index.html;
        error_page 500 502 503 504 /index.html;
    }
}
"@
$confPath = "$NginxDir\conf\nginx.conf"
Set-Content -Path $confPath -Value $nginxConf
# Também salvar cópia no diretório de infra
New-Item -ItemType Directory -Path "C:\SOL\infra\nginx" -Force | Out-Null
Copy-Item -Path $confPath -Destination "C:\SOL\infra\nginx\nginx.conf" -Force
Write-Log "nginx.conf gerado em $confPath"

# Registrar como serviço via NSSM
$svcName = "SOL-Nginx"
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removendo serviço existente $svcName..."
    & nssm stop $svcName 2>$null
    & nssm remove $svcName confirm
}

Write-Log "Registrando Nginx como serviço Windows ($svcName)..."
& nssm install $svcName "$NginxDir\nginx.exe"
& nssm set $svcName AppDirectory $NginxDir
& nssm set $svcName DisplayName "SOL - Nginx Web Server"
& nssm set $svcName Description "Nginx $NginxVersion - Servidor web do SOL CBM-RS"
& nssm set $svcName Start SERVICE_AUTO_START
& nssm set $svcName AppStdout "C:\SOL\logs\nginx-stdout.log"
& nssm set $svcName AppStderr "C:\SOL\logs\nginx-stderr.log"

Write-Log "Iniciando serviço Nginx..."
Start-Service -Name $svcName
Start-Sleep -Seconds 3

$svc = Get-Service -Name $svcName
Write-Log "Status do serviço: $($svc.Status)"

Write-Log "========================================"
Write-Log "04-nginx.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  URL principal:  http://localhost:$HttpPort"
Write-Log "  Frontend:       http://localhost:$HttpPort/"
Write-Log "  Backend API:    http://localhost:$HttpPort/api/"
Write-Log "  Keycloak:       http://localhost:$HttpPort/auth/"
Write-Log "  Diretório:      $NginxDir"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 05-sol-service.ps1 (após compilar o backend)"
