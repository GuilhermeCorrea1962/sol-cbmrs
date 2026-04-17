# =============================================================================
# 07-minio-buckets.ps1
# Sprint 0  -  SOL Autônomo Windows
# Cria buckets e políticas no MinIO via mc (MinIO Client)
# PRE-REQUISITO: MinIO rodando na porta 9000
# Execute como Administrador
# =============================================================================

param(
    [string]$MinioUrl = "http://localhost:9000",
    [string]$RootUser = "solminio",
    [string]$RootPassword = "MinIO@SOL2026",
    [string]$McDir = "C:\SOL\infra\minio"
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\07-minio-buckets.log"
$McExe = "$McDir\mc.exe"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Configurando buckets MinIO para SOL ==="

New-Item -ItemType Directory -Path $McDir -Force | Out-Null

# Baixar mc (MinIO Client)
if (-not (Test-Path $McExe)) {
    Write-Log "Baixando MinIO Client (mc)..."
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile("https://dl.min.io/client/mc/release/windows-amd64/mc.exe", $McExe)
    Write-Log "mc baixado em $McExe"
} else {
    Write-Log "mc já existe: $McExe"
}

# Configurar alias
Write-Log "Configurando alias 'sol-minio'..."
& $McExe alias set sol-minio $MinioUrl $RootUser $RootPassword

# Criar buckets
$buckets = @(
    @{ Name = "sol-arquivos";    Desc = "Documentos do processo (plantas, ART, memorial)" },
    @{ Name = "sol-appci";       Desc = "APPCIs emitidos em PDF" },
    @{ Name = "sol-guias";       Desc = "Guias de Recolhimento geradas" },
    @{ Name = "sol-laudos";      Desc = "Laudos técnicos de vistoria" },
    @{ Name = "sol-decisoes";    Desc = "Decisões de recurso em PDF" },
    @{ Name = "sol-temp";        Desc = "Uploads temporários (expirar em 24h)" }
)

foreach ($bucket in $buckets) {
    Write-Log "Criando bucket: $($bucket.Name)  -  $($bucket.Desc)"
    & $McExe mb --ignore-existing "sol-minio/$($bucket.Name)"
}

# Política de expiração para bucket temporário (24h)
Write-Log "Configurando política de expiração no bucket sol-temp..."
$lifecycleConfig = @"
{
  "Rules": [
    {
      "ID": "expire-temp-24h",
      "Status": "Enabled",
      "Expiration": { "Days": 1 },
      "Filter": { "Prefix": "" }
    }
  ]
}
"@
$lcFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $lcFile -Value $lifecycleConfig
& $McExe ilm import "sol-minio/sol-temp" < $lcFile 2>$null
Remove-Item $lcFile -Force

# Criar usuário de aplicação (menos privilégios que root)
Write-Log "Criando usuário de aplicação 'sol-app'..."
& $McExe admin user add sol-minio sol-app "SolApp@Minio2026"

$policyJson = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::sol-arquivos/*","arn:aws:s3:::sol-arquivos",
        "arn:aws:s3:::sol-appci/*","arn:aws:s3:::sol-appci",
        "arn:aws:s3:::sol-guias/*","arn:aws:s3:::sol-guias",
        "arn:aws:s3:::sol-laudos/*","arn:aws:s3:::sol-laudos",
        "arn:aws:s3:::sol-decisoes/*","arn:aws:s3:::sol-decisoes",
        "arn:aws:s3:::sol-temp/*","arn:aws:s3:::sol-temp"
      ]
    }
  ]
}
"@
$policyFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $policyFile -Value $policyJson
& $McExe admin policy create sol-minio sol-app-policy $policyFile
& $McExe admin policy attach sol-minio sol-app-policy --user sol-app
Remove-Item $policyFile -Force

Write-Log "========================================"
Write-Log "07-minio-buckets.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  Buckets criados:"
foreach ($b in $buckets) { Write-Log "    - $($b.Name)" }
Write-Log ""
Write-Log "  Usuário app: sol-app / SolApp@Minio2026"
Write-Log "  Console:     http://localhost:9001"
Write-Log ""
Write-Log "  Configure no application.yml:"
Write-Log "    minio.url=http://localhost:9000"
Write-Log "    minio.access-key=sol-app"
Write-Log "    minio.secret-key=SolApp@Minio2026"
