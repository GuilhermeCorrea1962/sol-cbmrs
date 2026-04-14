# Importa o realm SOL no Keycloak
$KeycloakUrl = "http://localhost:8180"
$AdminUser = "admin"
$AdminPassword = "Keycloak@Admin2026"
$RealmJsonPath = "C:\SOL\infra\keycloak\sol-realm.json"
$LogFile = "C:\SOL\logs\06-keycloak-realm.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

Write-Log "=== Importando Realm SOL no Keycloak ==="

if (-not (Test-Path $RealmJsonPath)) {
    Write-Log "ERRO: Arquivo de realm nao encontrado: $RealmJsonPath" "ERROR"
    exit 1
}

# Aguardar Keycloak estar pronto
Write-Log "Verificando se Keycloak esta respondendo..."
$maxAttempts = 10
$attempt = 0
$ready = $false
while ($attempt -lt $maxAttempts -and -not $ready) {
    $attempt++
    try {
        $r = Invoke-RestMethod -Uri "$KeycloakUrl/realms/master" -TimeoutSec 5
        if ($r.realm -eq "master") { $ready = $true }
    } catch {
        Write-Log "Tentativa $attempt/$maxAttempts - Keycloak ainda nao disponivel, aguardando 10s..."
        Start-Sleep -Seconds 10
    }
}

if (-not $ready) {
    Write-Log "ERRO: Keycloak nao respondeu apos $maxAttempts tentativas" "ERROR"
    exit 1
}
Write-Log "Keycloak disponivel."

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
    Write-Log "ERRO: Falha ao obter token admin: $_" "ERROR"
    exit 1
}

$headers = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }

# Verificar se realm ja existe
Write-Log "Verificando se realm 'sol' ja existe..."
try {
    $existingRealm = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Headers $headers -ErrorAction Stop
    Write-Log "Realm 'sol' ja existe. Removendo para reimportar..."
    Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Method DELETE -Headers $headers | Out-Null
    Write-Log "Realm removido."
    Start-Sleep -Seconds 2
} catch {
    Write-Log "Realm 'sol' nao existe ainda. Sera criado."
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

Start-Sleep -Seconds 2
try {
    $realm = Invoke-RestMethod -Uri "$KeycloakUrl/admin/realms/sol" -Headers $headers
    Write-Log "Realm verificado: $($realm.realm)"
} catch {
    Write-Log "AVISO: Nao foi possivel verificar o realm apos importacao." "WARN"
}

Write-Log "=== 06-keycloak-realm concluido com SUCESSO ==="
Write-Log "  Realm: sol"
Write-Log "  Login URL: $KeycloakUrl/realms/sol/protocol/openid-connect/auth"
