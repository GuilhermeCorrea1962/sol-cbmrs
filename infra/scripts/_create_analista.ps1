#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$base  = 'http://localhost:8180'
$realm = 'sol'

$tok = (Invoke-RestMethod -Method Post `
    "$base/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body 'grant_type=password&client_id=admin-cli&username=admin&password=Keycloak@Admin2026').access_token

$h = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
Write-Host "Token OK"

# Criar usuario analista1 se nao existir
$users = Invoke-RestMethod "$base/admin/realms/$realm/users?username=analista1" -Headers $h
if ($users.Count -eq 0) {
    $body = @{
        username    = 'analista1'
        email       = 'analista1@cbm.rs.gov.br'
        firstName   = 'Analista'
        lastName    = 'SOL'
        enabled     = $true
        credentials = @(@{ type = 'password'; value = 'Analista@123'; temporary = $false })
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post "$base/admin/realms/$realm/users" -Headers $h -Body $body | Out-Null
    Write-Host "==> Usuario analista1 criado"
    $users = Invoke-RestMethod "$base/admin/realms/$realm/users?username=analista1" -Headers $h
} else {
    Write-Host "==> Usuario analista1 ja existe"
}

$uid = $users[0].id
Write-Host "UID: $uid"

# Atribuir role ANALISTA
$roles       = Invoke-RestMethod "$base/admin/realms/$realm/roles" -Headers $h
$roleAnalista = $roles | Where-Object { $_.name -eq 'ANALISTA' }
if ($null -ne $roleAnalista) {
    $roleBody = ConvertTo-Json @( @{ id = $roleAnalista.id; name = 'ANALISTA' } )
    try {
        Invoke-RestMethod -Method Post `
            "$base/admin/realms/$realm/users/$uid/role-mappings/realm" `
            -Headers $h -Body $roleBody | Out-Null
        Write-Host "Role ANALISTA atribuida."
    } catch {
        Write-Host "AVISO: Role ANALISTA pode ja estar atribuida: $_"
    }
}

Write-Host "keycloakId=$uid"
Write-Host "==> _create_analista.ps1 concluido."
