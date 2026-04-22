#Requires -Version 5.1
# fix-login.ps1
# Corrige o fluxo de login do SOL:
#   1. Adiciona escopos openid/profile/email ao realm sol no Keycloak
#   2. Garante que sol-frontend tem os scopes corretos
#   3. Reconstroi o frontend Angular com ng build --configuration production
#   4. Reinicia o Nginx
#
# Execute como Administrador em C:\SOL\infra\scripts\

$ErrorActionPreference = 'Stop'
$base  = 'http://localhost:8180'
$realm = 'sol'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SOL - Correcao do fluxo de login      " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Obter token admin
# ---------------------------------------------------------------------------
Write-Host "==> Obtendo token admin do Keycloak..." -ForegroundColor Yellow
$tok = (Invoke-RestMethod -Method Post `
    "$base/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body 'grant_type=password&client_id=admin-cli&username=admin&password=Keycloak@Admin2026').access_token
$h = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
Write-Host "==> Token OK" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Criar/garantir escopos necessarios
# ---------------------------------------------------------------------------
$existingScopes = Invoke-RestMethod "$base/admin/realms/$realm/client-scopes" -Headers $h
$existingNames  = $existingScopes | ForEach-Object { $_.name }

function Ensure-Scope {
    param([string]$Name, [hashtable]$Body)
    if ($existingNames -contains $Name) {
        Write-Host "  Escopo '$Name' ja existe." -ForegroundColor Gray
        return ($existingScopes | Where-Object { $_.name -eq $Name })[0].id
    }
    Write-Host "  Criando escopo '$Name'..." -ForegroundColor Yellow
    $json = $Body | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method Post "$base/admin/realms/$realm/client-scopes" -Headers $h -Body $json | Out-Null
    $updated = Invoke-RestMethod "$base/admin/realms/$realm/client-scopes" -Headers $h
    return ($updated | Where-Object { $_.name -eq $Name })[0].id
}

# openid
$openidId = Ensure-Scope -Name 'openid' -Body @{
    name       = 'openid'
    protocol   = 'openid-connect'
    attributes = @{ 'include.in.token.scope' = 'true'; 'display.on.consent.screen' = 'false' }
    protocolMappers = @(
        @{
            name           = 'sub'
            protocol       = 'openid-connect'
            protocolMapper = 'oidc-sub-mapper'
            consentRequired = $false
            config         = @{ 'access.token.claim' = 'false'; 'id.token.claim' = 'true' }
        }
    )
}

# profile
$profileId = Ensure-Scope -Name 'profile' -Body @{
    name       = 'profile'
    protocol   = 'openid-connect'
    attributes = @{ 'include.in.token.scope' = 'true'; 'display.on.consent.screen' = 'true' }
    protocolMappers = @(
        @{
            name           = 'username'
            protocol       = 'openid-connect'
            protocolMapper = 'oidc-usermodel-property-mapper'
            consentRequired = $false
            config         = @{ 'user.attribute' = 'username'; 'claim.name' = 'preferred_username';
                                'access.token.claim' = 'true'; 'id.token.claim' = 'true'; 'userinfo.token.claim' = 'true' }
        },
        @{
            name           = 'given name'
            protocol       = 'openid-connect'
            protocolMapper = 'oidc-usermodel-property-mapper'
            consentRequired = $false
            config         = @{ 'user.attribute' = 'firstName'; 'claim.name' = 'given_name';
                                'access.token.claim' = 'true'; 'id.token.claim' = 'true'; 'userinfo.token.claim' = 'true' }
        },
        @{
            name           = 'family name'
            protocol       = 'openid-connect'
            protocolMapper = 'oidc-usermodel-property-mapper'
            consentRequired = $false
            config         = @{ 'user.attribute' = 'lastName'; 'claim.name' = 'family_name';
                                'access.token.claim' = 'true'; 'id.token.claim' = 'true'; 'userinfo.token.claim' = 'true' }
        }
    )
}

# email
$emailId = Ensure-Scope -Name 'email' -Body @{
    name       = 'email'
    protocol   = 'openid-connect'
    attributes = @{ 'include.in.token.scope' = 'true'; 'display.on.consent.screen' = 'true' }
    protocolMappers = @(
        @{
            name           = 'email'
            protocol       = 'openid-connect'
            protocolMapper = 'oidc-usermodel-property-mapper'
            consentRequired = $false
            config         = @{ 'user.attribute' = 'email'; 'claim.name' = 'email';
                                'access.token.claim' = 'true'; 'id.token.claim' = 'true'; 'userinfo.token.claim' = 'true' }
        }
    )
}

Write-Host "==> Escopos verificados/criados." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Obter ID do client sol-frontend e atribuir todos os scopes como default
# ---------------------------------------------------------------------------
Write-Host "==> Configurando sol-frontend com os escopos corretos..." -ForegroundColor Yellow
$clients  = Invoke-RestMethod "$base/admin/realms/$realm/clients?clientId=sol-frontend" -Headers $h
$clientId = $clients[0].id

$currentDefault = Invoke-RestMethod "$base/admin/realms/$realm/clients/$clientId/default-client-scopes" -Headers $h
$currentNames   = $currentDefault | ForEach-Object { $_.name }

# Todos os scopes necessarios (obter IDs atualizados)
$allScopes = Invoke-RestMethod "$base/admin/realms/$realm/client-scopes" -Headers $h
$needed = @('openid', 'profile', 'email', 'roles')

foreach ($scopeName in $needed) {
    if ($currentNames -contains $scopeName) {
        Write-Host "  Scope '$scopeName' ja esta no sol-frontend." -ForegroundColor Gray
        continue
    }
    $scope = $allScopes | Where-Object { $_.name -eq $scopeName }
    if ($null -eq $scope) {
        Write-Host "  AVISO: scope '$scopeName' nao encontrado - pulando." -ForegroundColor Red
        continue
    }
    $sid = $scope.id
    try {
        Invoke-RestMethod -Method Put `
            "$base/admin/realms/$realm/clients/$clientId/default-client-scopes/$sid" `
            -Headers $h | Out-Null
        Write-Host "  Scope '$scopeName' adicionado ao sol-frontend." -ForegroundColor Green
    } catch {
        Write-Host "  AVISO ao adicionar '$scopeName': $_" -ForegroundColor Yellow
    }
}

# Verificar resultado
$afterDefault = Invoke-RestMethod "$base/admin/realms/$realm/clients/$clientId/default-client-scopes" -Headers $h
Write-Host "==> Scopes atuais do sol-frontend:" -ForegroundColor Green
$afterDefault | ForEach-Object { Write-Host "    - $($_.name)" }

# ---------------------------------------------------------------------------
# 4. Rebuild do frontend Angular com configuracao production
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Reconstruindo frontend Angular..." -ForegroundColor Yellow
Push-Location "C:\SOL\frontend"
try {
    & npm ci --prefer-offline 2>&1 | Out-Null
    $out = & npx ng build --configuration production 2>&1
    $out | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -and -not (Test-Path "dist\sol-frontend\browser\index.html")) {
        throw "ng build falhou (exit code $LASTEXITCODE)"
    }
    Write-Host "==> Build Angular concluido." -ForegroundColor Green
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 5. Reiniciar Nginx
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Reiniciando Nginx..." -ForegroundColor Yellow
$nginxBase = "C:\SOL\infra\nginx\nginx-1.26.2"
$nginxTemp = "$nginxBase\temp"
"client_body_temp","proxy_temp","fastcgi_temp","uwsgi_temp","scgi_temp" | ForEach-Object {
    New-Item -ItemType Directory -Path "$nginxTemp\$_" -Force | Out-Null
}
Stop-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$svc = Get-Service -Name "SOL-Nginx" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "==> Nginx rodando." -ForegroundColor Green
} else {
    Write-Host "==> AVISO: Nginx pode nao ter iniciado. Verifique com: Get-Service SOL-Nginx" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  CORRECAO CONCLUIDA                    " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Acesse: http://localhost/" -ForegroundColor White
Write-Host "  Clique em 'Entrar com credenciais SOL'" -ForegroundColor White
Write-Host "  Login: sol-admin  /  Admin@SOL2026" -ForegroundColor White
Write-Host ""
Write-Host "  Se ainda tiver problemas, abra o DevTools (F12)," -ForegroundColor Gray
Write-Host "  aba Console, e verifique a mensagem de erro apos o login." -ForegroundColor Gray
Write-Host ""
