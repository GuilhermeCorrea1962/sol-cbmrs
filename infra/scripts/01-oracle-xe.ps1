# =============================================================================
# 01-oracle-xe.ps1
# Sprint 0  -  SOL Autônomo Windows
# Configura Oracle XE 21c após instalação manual
# PREREQUISITO: Oracle XE 21c já instalado manualmente a partir de
#   https://www.oracle.com/database/technologies/xe-downloads.html
# Execute como Administrador
# =============================================================================

param(
    [string]$OracleHome = "",
    [string]$SolPassword = "Sol@CBM2026",
    [string]$SysPassword = "Oracle@XE2026"
)

# Auto-detectar ORACLE_HOME se não informado
if ([string]::IsNullOrEmpty($OracleHome)) {
    # Tentar via variável de ambiente
    if ($env:ORACLE_HOME -and (Test-Path "$env:ORACLE_HOME\bin\sqlplus.exe")) {
        $OracleHome = $env:ORACLE_HOME
    } else {
        # Tentar via registro do Windows
        $regPath = "HKLM:\SOFTWARE\ORACLE"
        if (Test-Path $regPath) {
            Get-ChildItem $regPath | ForEach-Object {
                $oh = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ORACLE_HOME
                if ($oh -and (Test-Path "$oh\bin\sqlplus.exe")) {
                    $OracleHome = $oh
                }
            }
        }
        # Procurar em paths comuns
        if ([string]::IsNullOrEmpty($OracleHome)) {
            $candidates = @(
                "C:\app\Administrator\product\21c\dbhomeXE",
                "C:\app\$env:USERNAME\product\21c\dbhomeXE",
                "C:\Oracle\product\21c\dbhomeXE"
            )
            foreach ($c in $candidates) {
                if (Test-Path "$c\bin\sqlplus.exe") { $OracleHome = $c; break }
            }
        }
    }
    if ([string]::IsNullOrEmpty($OracleHome)) {
        Write-Host "[ERROR] Não foi possível detectar ORACLE_HOME automaticamente."
        Write-Host "        Execute: .\01-oracle-xe.ps1 -OracleHome 'C:\app\SeuUsuario\product\21c\dbhomeXE' -SysPassword <senha>"
        exit 1
    }
    Write-Host "[INFO] ORACLE_HOME detectado automaticamente: $OracleHome"
}

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\01-oracle-xe.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Invoke-SqlPlus {
    param([string]$Sql, [string]$ConnStr = "/ as sysdba")
    $tmpFile = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tmpFile -Value "$Sql`nEXIT;"
    $result = & "$OracleHome\bin\sqlplus.exe" -S $ConnStr "@$tmpFile" 2>&1
    Remove-Item $tmpFile -Force
    return $result
}

Write-Log "=== Iniciando configuração Oracle XE para SOL ==="

# Verificar se Oracle XE está instalado
if (-not (Test-Path "$OracleHome\bin\sqlplus.exe")) {
    Write-Log "ERRO: Oracle XE não encontrado em $OracleHome" "ERROR"
    Write-Log "ACAO NECESSARIA:" "ERROR"
    Write-Log "  1. Acesse: https://www.oracle.com/database/technologies/xe-downloads.html" "ERROR"
    Write-Log "  2. Baixe: Oracle Database 21c Express Edition for Windows x64" "ERROR"
    Write-Log "  3. Execute o instalador como Administrador" "ERROR"
    Write-Log "  4. Anote a senha do SYS definida durante a instalação" "ERROR"
    Write-Log "  5. Execute este script novamente com -SysPassword <senha_definida>" "ERROR"
    exit 1
}

# Verificar serviço Oracle
$svcName = "OracleServiceXE"
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Write-Log "ERRO: Serviço $svcName não encontrado. Oracle XE pode não estar instalado." "ERROR"
    exit 1
}
if ($svc.Status -ne "Running") {
    Write-Log "Iniciando serviço Oracle XE..."
    Start-Service -Name $svcName
    Start-Sleep -Seconds 10
}
Write-Log "Serviço Oracle XE: $($svc.Status)"

# Configurar variável de ambiente ORACLE_HOME
[System.Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "Machine")
[System.Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$OracleHome\bin", "Machine")
$env:ORACLE_HOME = $OracleHome
$env:PATH = "$env:PATH;$OracleHome\bin"

# Criar tablespace para o SOL
Write-Log "Criando tablespace SOL_DATA..."
$sqlTablespace = @"
CREATE TABLESPACE SOL_DATA
  DATAFILE 'C:\SOL\data\oracle\sol_data01.dbf'
  SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE 10G
  EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;
"@
$result = Invoke-SqlPlus -Sql $sqlTablespace -ConnStr "sys/$SysPassword@localhost:1521/XE as sysdba"
Write-Log "Tablespace: $result"

# Criar usuário SOL
Write-Log "Criando usuário SOL..."
$sqlUser = @"
CREATE USER sol IDENTIFIED BY "$SolPassword"
  DEFAULT TABLESPACE SOL_DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA UNLIMITED ON SOL_DATA;
GRANT CONNECT, RESOURCE TO sol;
GRANT CREATE SESSION TO sol;
GRANT CREATE TABLE TO sol;
GRANT CREATE SEQUENCE TO sol;
GRANT CREATE VIEW TO sol;
GRANT CREATE PROCEDURE TO sol;
GRANT CREATE TRIGGER TO sol;
GRANT EXECUTE ON DBMS_CRYPTO TO sol;
"@
$result = Invoke-SqlPlus -Sql $sqlUser -ConnStr "sys/$SysPassword@localhost:1521/XE as sysdba"
Write-Log "Usuário SOL: $result"

# Salvar configuração de conexão
$connConfig = @"
# Configuracao de conexao Oracle XE - SOL
# Gerado por 01-oracle-xe.ps1 em $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

ORACLE_HOME=$OracleHome
SOL_JDBC_URL=jdbc:oracle:thin:@localhost:1521:XE
SOL_DB_USER=sol
SOL_DB_PASS=$SolPassword

# Para uso no application.yml do Spring Boot:
# spring.datasource.url=jdbc:oracle:thin:@localhost:1521:XE
# spring.datasource.username=sol
# spring.datasource.password=$SolPassword
# spring.datasource.driver-class-name=oracle.jdbc.OracleDriver
"@
Set-Content -Path "C:\SOL\data\oracle\connection.properties" -Value $connConfig
Write-Log "Configuração de conexão salva em C:\SOL\data\oracle\connection.properties"

Write-Log "========================================"
Write-Log "01-oracle-xe.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  URL JDBC:  jdbc:oracle:thin:@localhost:1521:XE"
Write-Log "  Usuário:   sol"
Write-Log "  Senha:     $SolPassword"
Write-Log "  Tablespace: SOL_DATA"
Write-Log ""
Write-Log "PROXIMO PASSO: Execute 02-keycloak.ps1"
