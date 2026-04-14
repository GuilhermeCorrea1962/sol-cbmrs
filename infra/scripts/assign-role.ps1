$base = 'http://localhost:8180'
$realm = 'sol'

# Token admin master
$masterToken = (Invoke-RestMethod -Method Post `
    -Uri "$base/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='admin-cli'; username='admin'; password='Keycloak@Admin2026' }
).access_token
$h = @{ Authorization = "Bearer $masterToken"; 'Content-Type' = 'application/json' }

# ID do usuario
$userId = (Invoke-RestMethod -Uri "$base/admin/realms/$realm/users?username=sol-admin" -Headers $h)[0].id
Write-Host "Usuario ID: $userId"

# Role ADMIN completa (com todos os campos necessarios)
$adminRole = Invoke-RestMethod -Uri "$base/admin/realms/$realm/roles/ADMIN" -Headers $h
Write-Host "Role: $($adminRole.name) | ID: $($adminRole.id)"

# Atribuir via array com campos minimos obrigatorios
$body = "[{`"id`":`"$($adminRole.id)`",`"name`":`"$($adminRole.name)`"}]"
Write-Host "Body: $body"

try {
    Invoke-RestMethod -Method Post `
        -Uri "$base/admin/realms/$realm/users/$userId/role-mappings/realm" `
        -Headers $h -Body $body
    Write-Host "[OK] Role ADMIN atribuida"
} catch {
    Write-Host "[ERRO] $($_.Exception.Message)"
    Write-Host $_.ErrorDetails.Message
}

# Verificar roles do usuario
$mappings = Invoke-RestMethod -Uri "$base/admin/realms/$realm/users/$userId/role-mappings/realm" -Headers $h
Write-Host "Roles do usuario: $($mappings.name -join ', ')"

# Novo token
$tokenResp = Invoke-RestMethod -Method Post `
    -Uri "$base/realms/$realm/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='sol-frontend'; username='sol-admin'; password='Admin@SOL2026' }

$jwt = $tokenResp.access_token
$payload = $jwt.Split('.')[1]
$padded = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
$claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($padded)) | ConvertFrom-Json
Write-Host "==> Roles no JWT: $($claims.roles)"

$jwt | Out-File -FilePath 'C:\SOL\infra\scripts\test-token.txt' -Encoding utf8 -NoNewline
Write-Host "==> Token salvo"
