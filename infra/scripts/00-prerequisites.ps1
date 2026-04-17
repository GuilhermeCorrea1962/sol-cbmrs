# =============================================================================
# 00-prerequisites.ps1
# Sprint 0  -  SOL Autônomo Windows
# Instala pré-requisitos: Chocolatey, Java 21, Node 20, Maven 3.9, Git, NSSM
# Execute como Administrador
# =============================================================================

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\00-prerequisites.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Verificar privilégios
if (-not (Test-Administrator)) {
    Write-Host "ERRO: Execute este script como Administrador." -ForegroundColor Red
    exit 1
}

# Criar diretórios base
Write-Log "Criando estrutura de diretórios C:\SOL..."
@("C:\SOL", "C:\SOL\logs", "C:\SOL\infra", "C:\SOL\infra\scripts",
  "C:\SOL\infra\keycloak", "C:\SOL\infra\nginx",
  "C:\SOL\backend", "C:\SOL\frontend",
  "C:\SOL\data\oracle", "C:\SOL\data\keycloak",
  "C:\SOL\data\minio", "C:\SOL\instaladores", "C:\SOL\certs") | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Log "  Criado: $_"
    } else {
        Write-Log "  Já existe: $_"
    }
}

# Instalar Chocolatey
Write-Log "Verificando Chocolatey..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Instalando Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    # Recarregar PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Chocolatey instalado com sucesso."
} else {
    Write-Log "Chocolatey já está instalado: $(choco --version)"
}

# Instalar Java 21 (Eclipse Temurin)
Write-Log "Verificando Java 21..."
$javaVersion = java -version 2>&1 | Select-String "21\."
if (-not $javaVersion) {
    Write-Log "Instalando Eclipse Temurin JDK 21..."
    choco install temurin21 -y
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Java 21 instalado."
} else {
    Write-Log "Java já está instalado: $javaVersion"
}

# Instalar Node.js 20 LTS
Write-Log "Verificando Node.js 20..."
$nodeVersion = node --version 2>&1
if (-not ($nodeVersion -match "v20\.")) {
    Write-Log "Instalando Node.js 20 LTS..."
    choco install nodejs-lts --version=20.18.0 -y
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Node.js 20 instalado."
} else {
    Write-Log "Node.js já está instalado: $nodeVersion"
}

# Instalar Maven 3.9
Write-Log "Verificando Maven..."
if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    Write-Log "Instalando Maven 3.9..."
    choco install maven --version=3.9.6 -y
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Maven instalado."
} else {
    Write-Log "Maven já está instalado: $(mvn --version | Select-Object -First 1)"
}

# Instalar Git
Write-Log "Verificando Git..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "Instalando Git..."
    choco install git -y
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "Git instalado."
} else {
    Write-Log "Git já está instalado: $(git --version)"
}

# Instalar NSSM (Non-Sucking Service Manager)
Write-Log "Verificando NSSM..."
if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
    Write-Log "Instalando NSSM..."
    choco install nssm -y
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Log "NSSM instalado."
} else {
    Write-Log "NSSM já está instalado."
}

# Instalar Angular CLI 18
Write-Log "Verificando Angular CLI..."
$ngVersion = ng version 2>&1 | Select-String "Angular CLI:"
if (-not ($ngVersion -match "18\.")) {
    Write-Log "Instalando Angular CLI 18..."
    npm install -g @angular/cli@18 2>&1 | ForEach-Object { Write-Log $_ }
    Write-Log "Angular CLI 18 instalado."
} else {
    Write-Log "Angular CLI já está instalado: $ngVersion"
}

Write-Log "========================================"
Write-Log "00-prerequisites.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "Versões instaladas:"
Write-Log "  Java:   $(java -version 2>&1 | Select-Object -First 1)"
Write-Log "  Node:   $(node --version)"
Write-Log "  npm:    $(npm --version)"
Write-Log "  Maven:  $(mvn --version 2>&1 | Select-Object -First 1)"
Write-Log "  Git:    $(git --version)"
Write-Log "  ng:     $(ng version 2>&1 | Select-String 'Angular CLI')"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 01-oracle-xe.ps1"
