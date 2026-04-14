# =============================================================================
# 06-keycloak-realm.ps1
# Sprint 0 — SOL Autônomo Windows
# Importa o realm 'sol' no Keycloak via Admin REST API
# PRE-REQUISITO: Keycloak rodando na porta 8180
# Execute como Administrador
# =============================================================================

param(
    [string]$KeycloakUrl = "http://localhost:8180",
    [string]$AdminUser = "admin",
    [string]$AdminPassword = "Keycloak@Admin2026",
    [string]$RealmJsonPath = "C:\SOL\infra\keycloak\sol-realm.json"
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\SOL\logs\06-keycloak-realm.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Importando Realm SOL no Keycloak ==="

# Verificar arquivo de realm
if (-not (Test-Path $RealmJsonPath)) {
    Write-Log "ERRO: Arquivo de realm não encontrado: $RealmJsonPath" "ERROR"
    exit 1
}

# Obter token de admin
Write-Log "Autenticando no Keycloak Admin..."
$tokenBody = @{
    grant_type = "password"
    client_id  = "admin-cli"
    username   = $AdminUser
    password   = $AdminPassword
}
try {
    $tokenResponse = Invoke-RestMethod `
        -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
        -Method POST `
        -Body $tokenBody `
        -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token
    Write-Log "Token obtido com sucesso."
} catch {
    Write-Log "ERRO: Falha ao obter token admin. Verifique se o Keycloak está rodando e as credenciais estão corretas." "ERROR"
    Write-Log "Detalhes: $_" "ERROR"
    exit 1
}

$headers = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }

# Verificar se realm já existe
Write-Log "Verificando se realm 'sol' já existe..."
try {
    $existingRealm = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Headers $headers -ErrorAction Stop
    Write-Log "Realm 'sol' já existe. Removendo para reimportar..."
    Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Method DELETE -Headers $headers | Out-Null
    Write-Log "Realm removido."
    Start-Sleep -Seconds 2
} catch {
    Write-Log "Realm 'sol' não existe ainda. Será criado."
}

# Importar realm
Write-Log "Importando realm SOL de $RealmJsonPath ..."
$realmJson = Get-Content -Path $RealmJsonPath -Raw
try {
    Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms" -Method POST -Headers $headers -Body $realmJson | Out-Null
    Write-Log "Realm SOL importado com sucesso."
} catch {
    Write-Log "ERRO ao importar realm: $_" "ERROR"
    exit 1
}

# Verificar criação
Start-Sleep -Seconds 2
try {
    $realm = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Headers $headers
    Write-Log "Realm verificado: $($realm.realm) — displayName: $($realm.displayNameHtml)"
} catch {
    Write-Log "AVISO: Não foi possível verificar o realm após importação." "WARN"
}

Write-Log "========================================"
Write-Log "06-keycloak-realm.ps1 concluído com SUCESSO"
Write-Log "========================================"
Write-Log ""
Write-Log "  Realm:         sol"
Write-Log "  Login URL:     $KeycloakUrl/realms/sol/protocol/openid-connect/auth"
Write-Log "  JWKS URL:      $KeycloakUrl/realms/sol/protocol/openid-connect/certs"
Write-Log "  Token URL:     $KeycloakUrl/realms/sol/protocol/openid-connect/token"
Write-Log ""
Write-Log "Clients configurados: sol-frontend, sol-backend"
Write-Log "Roles: CIDADAO, RT, ANALISTA, INSPETOR, ADMIN, CHEFE_SSEG_BBM"
