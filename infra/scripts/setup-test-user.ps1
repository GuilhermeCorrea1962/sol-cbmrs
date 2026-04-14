$base = 'http://localhost:8180'
$realm = 'sol'

# --- Token admin do master ---
$masterToken = (Invoke-RestMethod -Method Post `
    -Uri "$base/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='admin-cli'; username='admin'; password='Keycloak@Admin2026' }
).access_token
$h = @{ Authorization = "Bearer $masterToken"; 'Content-Type' = 'application/json' }

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
$userId = (Invoke-RestMethod -Uri "$base/admin/realms/$realm/users?username=sol-admin" -Headers $h)[0].id
Write-Host "==> ID do usuario: $userId"

# --- Criar role ADMIN se nao existir ---
$adminRole = $roles | Where-Object { $_.name -eq 'ADMIN' }
if ($null -eq $adminRole) {
    $body = @{ name='ADMIN'; description='Administrador do SOL' } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/roles" -Headers $h -Body $body | Out-Null
    Write-Host "==> Role ADMIN criada"
    $adminRole = Invoke-RestMethod -Uri "$base/admin/realms/$realm/roles/ADMIN" -Headers $h
} else {
    Write-Host "==> Role ADMIN ja existe"
}

# --- Atribuir role ADMIN ao usuario ---
$body = @($adminRole) | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/users/$userId/role-mappings/realm" `
    -Headers $h -Body $body | Out-Null
Write-Host "==> Role ADMIN atribuida ao usuario sol-admin"

# --- Habilitar directAccessGrants no sol-frontend ---
$clients = Invoke-RestMethod -Uri "$base/admin/realms/$realm/clients?clientId=sol-frontend" -Headers $h
$clientId = $clients[0].id
$clientRep = Invoke-RestMethod -Uri "$base/admin/realms/$realm/clients/$clientId" -Headers $h
$clientRep.directAccessGrantsEnabled = $true
$body = $clientRep | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm/clients/$clientId" -Headers $h -Body $body | Out-Null
Write-Host "==> directAccessGrantsEnabled habilitado no sol-frontend"

# --- Obter token JWT do usuario sol-admin ---
$tokenResp = Invoke-RestMethod -Method Post `
    -Uri "$base/realms/$realm/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='sol-frontend'; username='sol-admin'; password='Admin@SOL2026' }

$jwt = $tokenResp.access_token
Write-Host "`n==> JWT obtido: $($jwt.Substring(0,30))..."

# Decodificar payload para confirmar roles
$payload = $jwt.Split('.')[1]
$padded = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded))
$claims = $decoded | ConvertFrom-Json
Write-Host "==> Roles no JWT: $($claims.roles)"
Write-Host "==> sub: $($claims.sub)"

# Salvar token em arquivo para uso nos testes
$jwt | Out-File -FilePath 'C:\SOL\infra\scripts\test-token.txt' -Encoding utf8 -NoNewline
Write-Host "`n==> Token salvo em C:\SOL\infra\scripts\test-token.txt"
