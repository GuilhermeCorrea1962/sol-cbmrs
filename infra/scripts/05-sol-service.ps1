# =============================================================================
# 05-sol-service.ps1
# Sprint 0  -  SOL Autônomo Windows
# Registra o JAR compilado do SOL Backend como serviço Windows via NSSM
# PRE-REQUISITO: mvn clean package já executado em C:\SOL\backend\
# Execute como Administrador
# =============================================================================

param(
    [string]$JarPath = "C:\SOL\backend\target\sol-backend-1.0.0.jar",
    [string]$JavaHome = "",
    [int]$Port = 8080,
    [string]$Profile = "prod"
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\05-sol-service.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

# Descobrir JAVA_HOME
if ([string]::IsNullOrEmpty($JavaHome)) {
    $JavaHome = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ([string]::IsNullOrEmpty($JavaHome)) {
        # Tentar localizar Java 21 instalado pelo Chocolatey / Temurin
        $possiblePaths = @(
            "C:\Program Files\Eclipse Adoptium\jdk-21*",
            "C:\Program Files\Java\jdk-21*"
        )
        foreach ($pattern in $possiblePaths) {
            $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $JavaHome = $found.FullName; break }
        }
    }
}

if ([string]::IsNullOrEmpty($JavaHome)) {
    Write-Log "ERRO: JAVA_HOME não encontrado. Informe com -JavaHome <caminho>" "ERROR"
    exit 1
}

$JavaExe = "$JavaHome\bin\java.exe"
Write-Log "Usando Java: $JavaExe"

# Verificar JAR
if (-not (Test-Path $JarPath)) {
    Write-Log "ERRO: JAR não encontrado em $JarPath" "ERROR"
    Write-Log "Execute primeiro: cd C:\SOL\backend && mvn clean package -DskipTests" "ERROR"
    exit 1
}
Write-Log "JAR encontrado: $JarPath"

# Registrar como serviço via NSSM
$svcName = "SOL-Backend"
$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Parando e removendo serviço existente $svcName..."
    & nssm stop $svcName 2>$null
    Start-Sleep -Seconds 3
    & nssm remove $svcName confirm
}

$jvmArgs = "-Xms256m -Xmx1g -Dspring.profiles.active=$Profile -Dserver.port=$Port"
$jarArgs = "-jar `"$JarPath`""

Write-Log "Registrando SOL Backend como serviço Windows ($svcName)..."
& nssm install $svcName $JavaExe
& nssm set $svcName AppParameters "$jvmArgs $jarArgs"
& nssm set $svcName AppDirectory "C:\SOL\backend"
& nssm set $svcName DisplayName "SOL - Backend Spring Boot"
& nssm set $svcName Description "SOL CBM-RS Backend - Spring Boot 3 / Java 21"
& nssm set $svcName Start SERVICE_AUTO_START
& nssm set $svcName AppStdout "C:\SOL\logs\sol-backend-stdout.log"
& nssm set $svcName AppStderr "C:\SOL\logs\sol-backend-stderr.log"
& nssm set $svcName AppRotateFiles 1
& nssm set $svcName AppRotateOnline 1
& nssm set $svcName AppRotateBytes 10485760

Write-Log "Iniciando serviço SOL Backend..."
Start-Service -Name $svcName
Start-Sleep -Seconds 20

# Verificar health
$svc = Get-Service -Name $svcName
Write-Log "Status do serviço: $($svc.Status)"

try {
    $health = Invoke-RestMethod -Uri "http://localhost:$Port/api/health" -TimeoutSec 30
    Write-Log "Health check: $($health | ConvertTo-Json)"
} catch {
    Write-Log "AVISO: Health check falhou  -  o backend pode ainda estar inicializando" "WARN"
    Write-Log "Verifique: http://localhost:$Port/api/health" "WARN"
}

Write-Log "========================================"
Write-Log "05-sol-service.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  Serviço:  $svcName"
Write-Log "  JAR:      $JarPath"
Write-Log "  Porta:    $Port"
Write-Log "  Profile:  $Profile"
Write-Log "  Health:   http://localhost:$Port/api/health"
Write-Log ""
Write-Log "LOGS em: C:\SOL\logs\sol-backend-stdout.log"
