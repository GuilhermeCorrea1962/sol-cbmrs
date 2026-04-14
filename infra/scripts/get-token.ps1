# Passo 1: token de admin do master realm
$masterToken = (Invoke-RestMethod -Method Post `
    -Uri 'http://localhost:8180/realms/master/protocol/openid-connect/token' `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{
        grant_type = 'password'
        client_id  = 'admin-cli'
        username   = 'admin'
        password   = 'Keycloak@Admin2026'
    }).access_token

Write-Host "==> Token master obtido: $($masterToken.Substring(0,20))..."

# Passo 2: listar clientes do realm sol
$clients = Invoke-RestMethod -Uri 'http://localhost:8180/admin/realms/sol/clients' `
    -Headers @{ Authorization = "Bearer $masterToken" }

Write-Host "`n==> Clientes no realm sol:"
$clients | Select-Object clientId, publicClient, directAccessGrantsEnabled | Format-Table

# Passo 3: listar usuarios do realm sol
$users = Invoke-RestMethod -Uri 'http://localhost:8180/admin/realms/sol/users' `
    -Headers @{ Authorization = "Bearer $masterToken" }

Write-Host "==> Usuarios no realm sol:"
$users | Select-Object username, email, enabled | Format-Table
