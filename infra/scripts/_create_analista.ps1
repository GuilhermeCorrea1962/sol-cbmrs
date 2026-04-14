#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$tok = (Invoke-RestMethod -Method Post `
    'http://localhost:8180/realms/master/protocol/openid-connect/token' `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body 'grant_type=password&client_id=admin-cli&username=admin&password=Keycloak@Admin2026').access_token

Write-Host "Token OK"

# Busca usuario existente
$users = Invoke-RestMethod "http://localhost:8180/admin/realms/sol/users?username=analista1" `
    -Headers @{ Authorization = "Bearer $tok" }
$uid = $users[0].id
Write-Host "UID: $uid"

# Define senha
$passBody = '{"type":"password","value":"Analista@123","temporary":false}'
Invoke-RestMethod -Method Put `
    "http://localhost:8180/admin/realms/sol/users/$uid/reset-password" `
    -ContentType 'application/json' `
    -Headers @{ Authorization = "Bearer $tok" } `
    -Body $passBody
Write-Host "Senha definida: Analista@123"

# Atribui role ANALISTA
$roles = Invoke-RestMethod 'http://localhost:8180/admin/realms/sol/roles' `
    -Headers @{ Authorization = "Bearer $tok" }
$roleAnalista = $roles | Where-Object { $_.name -eq 'ANALISTA' }
$roleBody = "[{`"id`":`"$($roleAnalista.id)`",`"name`":`"ANALISTA`"}]"

Invoke-RestMethod -Method Post `
    "http://localhost:8180/admin/realms/sol/users/$uid/role-mappings/realm" `
    -ContentType 'application/json' `
    -Headers @{ Authorization = "Bearer $tok" } `
    -Body $roleBody

Write-Host "Role ANALISTA atribuida."
Write-Host "keycloakId=$uid"
