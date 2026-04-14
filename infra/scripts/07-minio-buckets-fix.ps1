# Cria buckets e politicas no MinIO
$MinioUrl = "http://localhost:9000"
$RootUser = "solminio"
$RootPassword = "MinIO@SOL2026"
$McDir = "C:\SOL\infra\minio"
$McExe = "$McDir\mc.exe"
$LogFile = "C:\SOL\logs\07-minio-buckets.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Configurando buckets MinIO para SOL ==="

New-Item -ItemType Directory -Path $McDir -Force | Out-Null

# Baixar mc se necessario
if (-not (Test-Path $McExe)) {
    Write-Log "Baixando MinIO Client (mc)..."
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile("https://dl.min.io/client/mc/release/windows-amd64/mc.exe", $McExe)
    Write-Log "mc baixado em $McExe"
} else {
    Write-Log "mc ja existe: $McExe"
}

# Configurar alias
Write-Log "Configurando alias 'sol-minio'..."
& $McExe alias set sol-minio $MinioUrl $RootUser $RootPassword

# Criar buckets
$buckets = @(
    @{ Name = "sol-arquivos";    Desc = "Documentos do processo" },
    @{ Name = "sol-appci";       Desc = "APPCIs emitidos em PDF" },
    @{ Name = "sol-guias";       Desc = "Guias de Recolhimento" },
    @{ Name = "sol-laudos";      Desc = "Laudos tecnicos de vistoria" },
    @{ Name = "sol-decisoes";    Desc = "Decisoes de recurso em PDF" },
    @{ Name = "sol-temp";        Desc = "Uploads temporarios" }
)

foreach ($bucket in $buckets) {
    Write-Log "Criando bucket: $($bucket.Name)"
    & $McExe mb --ignore-existing "sol-minio/$($bucket.Name)"
}

# Criar usuario de aplicacao
Write-Log "Criando usuario de aplicacao 'sol-app'..."
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

Write-Log "=== 07-minio-buckets concluido com SUCESSO ==="
Write-Log "  Buckets: sol-arquivos, sol-appci, sol-guias, sol-laudos, sol-decisoes, sol-temp"
Write-Log "  Usuario app: sol-app / SolApp@Minio2026"
Write-Log "  Console: http://localhost:9001"
