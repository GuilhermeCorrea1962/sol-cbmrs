# Verificacao completa do ambiente SOL
$LogFile = "C:\SOL\logs\08-verify.log"
$PassCount = 0
$FailCount = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Test-Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            Write-Log "[PASS] $Name"
            $script:PassCount++
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            Write-Log "[FAIL] $Name" "ERROR"
            $script:FailCount++
        }
    } catch {
        Write-Host "  [FAIL] $Name -- $_" -ForegroundColor Red
        Write-Log "[FAIL] $Name -- $_" "ERROR"
        $script:FailCount++
    }
}

function Test-Http {
    param([string]$Url, [int[]]$OkCodes = @(200))
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = 10000
        $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        $code -in $OkCodes
    } catch [System.Net.WebException] {
        $code = [int]$_.Exception.Response.StatusCode
        $code -in $OkCodes
    } catch {
        $false
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " SOL Autonomo - Verificacao de Ambiente " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "--- Servicos Windows ---" -ForegroundColor Yellow

Test-Check "Servico SOL-Keycloak rodando" {
    (Get-Service -Name "SOL-Keycloak" -ErrorAction Stop).Status -eq "Running"
}
Test-Check "Servico SOL-MinIO rodando" {
    (Get-Service -Name "SOL-MinIO" -ErrorAction Stop).Status -eq "Running"
}
Test-Check "Servico SOL-Nginx rodando" {
    (Get-Service -Name "SOL-Nginx" -ErrorAction Stop).Status -eq "Running"
}
Test-Check "Servico OracleServiceXE rodando" {
    (Get-Service -Name "OracleServiceXE" -ErrorAction Stop).Status -eq "Running"
}
$solBackendSvc = Get-Service -Name "SOL-Backend" -ErrorAction SilentlyContinue
if ($solBackendSvc) {
    Test-Check "Servico SOL-Backend rodando" {
        $solBackendSvc.Status -eq "Running"
    }
} else {
    Write-Host "  [SKIP] Servico SOL-Backend (ainda nao registrado)" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "--- Endpoints HTTP ---" -ForegroundColor Yellow

Test-Check "Keycloak respondendo (porta 8180)" {
    Test-Http "http://localhost:8180/realms/master" @(200)
}
Test-Check "MinIO API respondendo (porta 9000)" {
    Test-Http "http://localhost:9000/minio/health/live" @(200, 204)
}
Test-Check "MinIO Console respondendo (porta 9001)" {
    Test-Http "http://localhost:9001" @(200, 302)
}
Test-Check "Nginx respondendo (porta 80)" {
    Test-Http "http://localhost:80" @(200, 302, 304)
}
Test-Check "SOL Backend health (porta 8080)" {
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:8080/api/health" -TimeoutSec 10
        $r.status -eq "UP"
    } catch { $false }
}

Write-Host ""
Write-Host "--- Banco de Dados Oracle ---" -ForegroundColor Yellow

Test-Check "Oracle XE porta 1521 aberta" {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tcp.Connect("localhost", 1521)
        $tcp.Connected
    } finally {
        $tcp.Close()
    }
}
Test-Check "Arquivo de configuracao Oracle criado" {
    Test-Path "C:\SOL\data\oracle\connection.properties"
}

Write-Host ""
Write-Host "--- Keycloak Realm SOL ---" -ForegroundColor Yellow

Test-Check "Realm 'sol' existe no Keycloak" {
    try {
        $body = @{ grant_type="password"; client_id="admin-cli"; username="admin"; password="Keycloak@Admin2026" }
        $t = Invoke-RestMethod -Uri "http://localhost:8180/realms/master/protocol/openid-connect/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
        $h = @{ Authorization = "Bearer $($t.access_token)" }
        $realm = Invoke-RestMethod -Uri "http://localhost:8180/admin/realms/sol" -Headers $h -TimeoutSec 10
        $realm.realm -eq "sol"
    } catch { $false }
}

Write-Host ""
Write-Host "--- MinIO Buckets ---" -ForegroundColor Yellow

$expectedBuckets = @("sol-arquivos", "sol-appci", "sol-guias", "sol-laudos", "sol-decisoes", "sol-temp")
foreach ($bucket in $expectedBuckets) {
    Test-Check "Bucket '$bucket' existe" {
        $mcExe = "C:\SOL\infra\minio\mc.exe"
        if (Test-Path $mcExe) {
            & $mcExe ls "sol-minio/$bucket" 2>&1 | Out-Null
            $LASTEXITCODE -eq 0
        } else { $false }
    }
}

Write-Host ""
Write-Host "--- Ferramentas de Desenvolvimento ---" -ForegroundColor Yellow

Test-Check "Java 21+ disponivel" {
    Test-Path "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot\bin\java.exe"
}
Test-Check "Node.js disponivel" {
    $null -ne (node --version 2>&1)
}
Test-Check "Maven disponivel" {
    $null -ne (mvn --version 2>&1 | Select-Object -First 1)
}
Test-Check "Angular CLI disponivel" {
    $null -ne (ng version 2>&1 | Select-String "Angular CLI")
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
$totalChecks = $PassCount + $FailCount
if ($FailCount -eq 0) {
    Write-Host " RESULTADO: $PassCount/$totalChecks PASS -- AMBIENTE OK " -ForegroundColor Green
} else {
    Write-Host " RESULTADO: $PassCount PASS / $FailCount FAIL " -ForegroundColor Red
    Write-Host " Corrija os itens FAIL antes de prosseguir. " -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Log "RESULTADO FINAL: $PassCount PASS / $FailCount FAIL de $totalChecks checks"
