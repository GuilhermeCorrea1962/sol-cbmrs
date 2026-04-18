$ErrorActionPreference = "Stop"
$base  = 'http://localhost:8180'
$realm = 'sol'

# --- Token admin do master ---
Write-Host "==> Obtendo token admin do Keycloak..."
$masterToken = (Invoke-RestMethod -Method Post `
    -Uri "$base/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='admin-cli'; username='admin'; password='Keycloak@Admin2026' }
).access_token
$h = @{ Authorization = "Bearer $masterToken"; 'Content-Type' = 'application/json' }
Write-Host "==> Token admin obtido."

# --- Listar roles do realm ---
$roles = Invoke-RestMethod -Uri "$base/admin/realms/$realm/roles" -Headers $h
Write-Host "==> Roles no realm sol:"
$roles | Select-Object name | Format-Table

# --- Criar usuario sol-admin se nao existir ---
$users = Invoke-RestMethod -Uri "$base/admin/realms/$realm/users?username=sol-admin" -Headers $h
if ($users.Count -eq 0) {
    $body = @{
        username    = 'sol-admin'
        email       = 'sol-admin@cbm.rs.gov.br'
        firstName   = 'Admin'
        lastName    = 'SOL'
        enabled     = $true
        credentials = @(@{ type='password'; value='Admin@SOL2026'; temporary=$false })
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/users" -Headers $h -Body $body | Out-Null
    Write-Host "==> Usuario sol-admin criado"
} else {
    Write-Host "==> Usuario sol-admin ja existe"
}

# --- Obter ID do usuario ---
$userList = Invoke-RestMethod -Uri "$base/admin/realms/$realm/users?username=sol-admin" -Headers $h
$userId = $userList[0].id
Write-Host "==> ID do usuario: $userId"

# --- Garantir role ADMIN existe no realm ---
$adminRole = $roles | Where-Object { $_.name -eq 'ADMIN' }
if ($null -eq $adminRole) {
    $body = @{ name='ADMIN'; description='Administrador do SOL' } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/roles" -Headers $h -Body $body | Out-Null
    Write-Host "==> Role ADMIN criada"
    $adminRole = Invoke-RestMethod -Uri "$base/admin/realms/$realm/roles/ADMIN" -Headers $h
} else {
    Write-Host "==> Role ADMIN ja existe"
    # Recarregar com todos os campos necessarios para o mapeamento
    $adminRole = Invoke-RestMethod -Uri "$base/admin/realms/$realm/roles/ADMIN" -Headers $h
}

# --- Atribuir role ADMIN ao usuario (apenas id e name conforme API Keycloak) ---
try {
    $roleBody = ConvertTo-Json @( @{ id = $adminRole.id; name = $adminRole.name } )
    Invoke-RestMethod -Method Post `
        -Uri "$base/admin/realms/$realm/users/$userId/role-mappings/realm" `
        -Headers $h -Body $roleBody | Out-Null
    Write-Host "==> Role ADMIN atribuida ao usuario sol-admin"
} catch {
    Write-Host "==> AVISO: Atribuicao de role falhou (pode ja estar atribuida): $_"
}

# --- Habilitar directAccessGrants no sol-frontend ---
try {
    $clients  = Invoke-RestMethod -Uri "$base/admin/realms/$realm/clients?clientId=sol-frontend" -Headers $h
    $clientId = $clients[0].id
    # Envia apenas os campos necessarios para evitar conflitos com campos read-only
    $patch = @{ directAccessGrantsEnabled = $true } | ConvertTo-Json
    # Keycloak nao tem PATCH nativo; usar PUT com representacao completa mas sanitizada
    $clientRep = Invoke-RestMethod -Uri "$base/admin/realms/$realm/clients/$clientId" -Headers $h
    $clientRep.directAccessGrantsEnabled = $true
    $body = $clientRep | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Put `
        -Uri "$base/admin/realms/$realm/clients/$clientId" `
        -Headers $h -Body $body | Out-Null
    Write-Host "==> directAccessGrantsEnabled habilitado no sol-frontend"
} catch {
    Write-Host "==> AVISO: Nao foi possivel habilitar directAccessGrants: $_"
}

# --- Obter token JWT do usuario sol-admin ---
Write-Host "`n==> Testando login do sol-admin..."
try {
    $tokenResp = Invoke-RestMethod -Method Post `
        -Uri "$base/realms/$realm/protocol/openid-connect/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ grant_type='password'; client_id='sol-frontend'; username='sol-admin'; password='Admin@SOL2026' }

    $jwt = $tokenResp.access_token
    Write-Host "==> JWT obtido: $($jwt.Substring(0,30))..."

    # Decodificar payload para confirmar roles
    $payload = $jwt.Split('.')[1]
    $padded  = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
    $claims  = $decoded | ConvertFrom-Json
    Write-Host "==> realm_access.roles: $($claims.realm_access.roles)"
    Write-Host "==> sub: $($claims.sub)"

    $jwt | Out-File -FilePath 'C:\SOL\infra\scripts\test-token.txt' -Encoding utf8 -NoNewline
    Write-Host "==> Token salvo em C:\SOL\infra\scripts\test-token.txt"
} catch {
    Write-Host "==> AVISO: Nao foi possivel obter token para sol-admin: $_"
    Write-Host "    Verifique se directAccessGrantsEnabled esta ativo no client sol-frontend."
}

Write-Host "`n==> setup-test-user.ps1 concluido."
