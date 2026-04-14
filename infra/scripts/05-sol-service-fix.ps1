# Script temporário para registrar SOL-Backend com Java 21
$java21 = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot'
$JarPath = 'C:\SOL\backend\target\sol-backend-1.0.0.jar'
$JavaExe = "$java21\bin\java.exe"
$svcName = 'SOL-Backend'
$LogFile = 'C:\SOL\logs\05-sol-service.log'

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Registrando SOL Backend como servico Windows ==="
Write-Log "Java: $JavaExe"
Write-Log "JAR:  $JarPath"

if (-not (Test-Path $JarPath)) {
    Write-Log "ERRO: JAR nao encontrado em $JarPath" "ERROR"
    exit 1
}

$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removendo servico existente $svcName..."
    & nssm stop $svcName 2>$null
    Start-Sleep -Seconds 3
    & nssm remove $svcName confirm
}

$params = "-Xms256m -Xmx1g -Dspring.profiles.active=prod -Dserver.port=8080 -jar `"$JarPath`""

Write-Log "Registrando servico $svcName..."
& nssm install $svcName $JavaExe
& nssm set $svcName AppParameters $params
& nssm set $svcName AppDirectory 'C:\SOL\backend'
& nssm set $svcName DisplayName 'SOL - Backend Spring Boot'
& nssm set $svcName Description 'SOL CBM-RS Backend - Spring Boot 3 / Java 21'
& nssm set $svcName Start SERVICE_AUTO_START
& nssm set $svcName AppStdout 'C:\SOL\logs\sol-backend-stdout.log'
& nssm set $svcName AppStderr 'C:\SOL\logs\sol-backend-stderr.log'
& nssm set $svcName AppRotateFiles 1
& nssm set $svcName AppRotateBytes 10485760

Write-Log "Iniciando servico SOL Backend..."
Start-Service -Name $svcName
Start-Sleep -Seconds 20

$svc = Get-Service -Name $svcName
Write-Log "Status do servico: $($svc.Status)"

try {
    $health = Invoke-RestMethod -Uri "http://localhost:8080/api/health" -TimeoutSec 30
    Write-Log "Health check OK: $($health | ConvertTo-Json)"
} catch {
    Write-Log "AVISO: Health check falhou (backend ainda inicializando)" "WARN"
}

Write-Log "05-sol-service concluido. Servico: $svcName, Porta: 8080"
