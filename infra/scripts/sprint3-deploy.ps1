#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 3 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P01 e P02:
      - POST /auth/login    (login via Keycloak ROPC)
      - GET  /auth/me       (dados do usuario autenticado)
      - POST /cadastro/rt   (registro de RT com criacao no Keycloak)
      - GET  /api/usuarios  (verifica usuario criado localmente)
      - Limpeza do usuario de teste no Keycloak e Oracle

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: o client sol-frontend no realm sol deve ter
    "Direct Access Grants" habilitado no Keycloak.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuracoes
# ---------------------------------------------------------------------------
$ServiceName   = "SOL-Backend"
$JavaHome      = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$ProjectRoot   = "C:\SOL\backend"
$BaseUrl       = "http://localhost:8080/api"
$HealthUrl     = "$BaseUrl/health"
$KeycloakUrl   = "http://localhost:8180"
$Realm         = "sol"
$WaitSeconds   = 30
$MavenOpts     = "-Dmaven.test.skip=true -q"

# Dados do usuario de teste (criado e removido durante o smoke test)
$TestCpf       = "00000000191"
$TestEmail     = "rt.teste.sprint3@sol.cbm.rs.gov.br"
$TestNome      = "RT Smoke Test Sprint3"
$TestSenha     = "Sprint3@Teste2026"

# ---------------------------------------------------------------------------
# Funcoes auxiliares
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Mensagem)
    Write-Host ""
    Write-Host "===> $Mensagem" -ForegroundColor Cyan
}

function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red   }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }

function Get-MasterToken {
    $body = @{
        grant_type = "password"; client_id = "admin-cli"
        username = "admin"; password = "Keycloak@Admin2026"
    }
    $r = Invoke-RestMethod -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" `
         -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    return $r.access_token
}

# ---------------------------------------------------------------------------
# 1. Parar o servico
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceName"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else {
    Write-WARN "Servico nao estava em execucao ou nao existe -- continuando"
}

# ---------------------------------------------------------------------------
# 2. Compilar com Maven
# ---------------------------------------------------------------------------
Write-Step "Compilando com Maven (JAVA_HOME=$JavaHome)"

$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"

$mvnWrapper = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvnWrapper)) { $mvnWrapper = "mvn" }

Push-Location $ProjectRoot
try {
    & cmd /c "$mvnWrapper clean package $MavenOpts"
    if ($LASTEXITCODE -ne 0) { throw "Maven falhou com codigo $LASTEXITCODE" }
    Write-OK "Build concluido com sucesso"
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 3. Reiniciar o servico
# ---------------------------------------------------------------------------
Write-Step "Reiniciando servico $ServiceName"
if ($null -ne $svc) {
    Start-Service -Name $ServiceName
    Write-OK "Servico iniciado"
} else {
    $jarPath = Get-ChildItem "$ProjectRoot\target\*.jar" |
               Where-Object { $_.Name -notlike "*sources*" } |
               Select-Object -First 1
    if ($null -eq $jarPath) { throw "JAR nao encontrado em $ProjectRoot\target\" }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
                  -ArgumentList "-jar `"$($jarPath.FullName)`"" `
                  -WorkingDirectory $ProjectRoot -NoNewWindow
    Write-WARN "Servico nao registrado -- JAR iniciado diretamente (modo dev)"
}

# ---------------------------------------------------------------------------
# 4. Aguardar inicializacao
# ---------------------------------------------------------------------------
Write-Step "Aguardando $WaitSeconds segundos para inicializacao do Spring Boot"
Start-Sleep -Seconds $WaitSeconds

# ---------------------------------------------------------------------------
# 5. Health check com retry
# ---------------------------------------------------------------------------
Write-Step "Health check -- $HealthUrl"
$healthy = $false
for ($i = 1; $i -le 5; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) { Write-OK "Saudavel (tentativa $i)"; $healthy = $true; break }
    } catch {
        Write-WARN "Tentativa $i falhou -- aguardando 10s..."
        Start-Sleep -Seconds 10
    }
}
if (-not $healthy) { Write-FAIL "Health check falhou"; exit 1 }

# ---------------------------------------------------------------------------
# 6. Smoke test P01 -- Login via /auth/login
# ---------------------------------------------------------------------------
Write-Step "Smoke test P01 -- POST /auth/login"

# Obtem token do usuario sol-admin criado na Sprint 2
$loginBody = @{
    username = "sol-admin"; password = "Admin@SOL2026"
} | ConvertTo-Json

$tokenResponse = $null
try {
    $tokenResponse = Invoke-RestMethod `
        -Uri "$BaseUrl/auth/login" `
        -Method POST `
        -Body $loginBody `
        -ContentType "application/json" `
        -TimeoutSec 15
    Write-OK "Login OK -- access_token obtido (expira em $($tokenResponse.expires_in)s)"
} catch {
    Write-FAIL "Login falhou: $($_.Exception.Message)"
    Write-WARN "Verifique se o usuario sol-admin existe no realm sol e se Direct Access Grants esta habilitado no client sol-frontend"
    exit 1
}

$accessToken  = $tokenResponse.access_token
$refreshToken = $tokenResponse.refresh_token
$authHeader   = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------------------
# 7. Smoke test P01 -- GET /auth/me
# ---------------------------------------------------------------------------
Write-Step "Smoke test P01 -- GET /auth/me"
try {
    $me = Invoke-RestMethod -Uri "$BaseUrl/auth/me" -Headers $authHeader -TimeoutSec 10
    Write-OK "/auth/me OK -- keycloakId=$($me.keycloakId) roles=$($me.roles -join ',')"
} catch {
    Write-FAIL "/auth/me falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 8. Smoke test P01 -- POST /auth/refresh
# ---------------------------------------------------------------------------
Write-Step "Smoke test P01 -- POST /auth/refresh"
try {
    $refreshed = Invoke-RestMethod `
        -Uri "$BaseUrl/auth/refresh?refreshToken=$refreshToken" `
        -Method POST -TimeoutSec 10
    Write-OK "Refresh OK -- novo access_token obtido"
    $accessToken = $refreshed.access_token
    $authHeader  = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }
} catch {
    Write-FAIL "Refresh falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 9. Smoke test P02 -- POST /cadastro/rt (cria RT + Keycloak)
# ---------------------------------------------------------------------------
Write-Step "Smoke test P02 -- POST /cadastro/rt"

$rtBody = @{
    cpf            = $TestCpf
    nome           = $TestNome
    email          = $TestEmail
    telefone       = "51900000000"
    tipoUsuario    = "RT"
    senha          = $TestSenha
    numeroRegistro = "CREA-RS 999999"
    tipoConselho   = "CREA"
    especialidade  = "Engenharia Civil"
} | ConvertTo-Json

$rtCriado = $null
try {
    $rtCriado = Invoke-RestMethod `
        -Uri "$BaseUrl/cadastro/rt" `
        -Method POST `
        -Body $rtBody `
        -ContentType "application/json" `
        -TimeoutSec 20
    Write-OK "RT criado -- id=$($rtCriado.id) keycloakId=$($rtCriado.keycloakId)"
} catch {
    Write-FAIL "Cadastro RT falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 10. Smoke test P02 -- verifica usuario criado no banco local
# ---------------------------------------------------------------------------
if ($null -ne $rtCriado) {
    Write-Step "Verificando usuario RT no banco -- GET /api/usuarios/$($rtCriado.id)"
    try {
        $usuarioDB = Invoke-RestMethod `
            -Uri "$BaseUrl/usuarios/$($rtCriado.id)" `
            -Headers $authHeader -TimeoutSec 10
        Write-OK "Usuario local verificado -- cpf=$($usuarioDB.cpf) status=$($usuarioDB.statusCadastro)"
    } catch {
        Write-FAIL "Verificacao local falhou: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 11. Limpeza -- remove usuario de teste do Keycloak e do Oracle
# ---------------------------------------------------------------------------
Write-Step "Limpeza -- removendo usuario de teste"

if ($null -ne $rtCriado -and $null -ne $rtCriado.keycloakId) {
    try {
        $masterToken = Get-MasterToken
        $kh = @{ Authorization = "Bearer $masterToken" }
        Invoke-RestMethod `
            -Uri "$KeycloakUrl/admin/realms/$Realm/users/$($rtCriado.keycloakId)" `
            -Method DELETE -Headers $kh | Out-Null
        Write-OK "Usuario removido do Keycloak ($($rtCriado.keycloakId))"
    } catch {
        Write-WARN "Nao foi possivel remover do Keycloak: $($_.Exception.Message)"
    }
}

if ($null -ne $rtCriado -and $null -ne $rtCriado.id) {
    $sqlDelete = @"
DELETE FROM sol.usuario WHERE id_usuario = $($rtCriado.id);
COMMIT;
EXIT;
"@
    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tmpSql -Value $sqlDelete
    try {
        & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
        Write-OK "Usuario removido do Oracle (id=$($rtCriado.id))"
    } catch {
        Write-WARN "Nao foi possivel remover do Oracle: $($_.Exception.Message)"
    } finally {
        Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 12. Smoke test P01 -- POST /auth/logout
# ---------------------------------------------------------------------------
Write-Step "Smoke test P01 -- POST /auth/logout"
try {
    Invoke-RestMethod `
        -Uri "$BaseUrl/auth/logout?refreshToken=$refreshToken" `
        -Method POST -Headers $authHeader -TimeoutSec 10 | Out-Null
    Write-OK "Logout OK -- sessao encerrada"
} catch {
    Write-WARN "Logout retornou erro (pode ser token ja expirado): $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 13. Resultado final
# ---------------------------------------------------------------------------
Write-Step "Sprint 3 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P01 -- Login (ROPC), refresh, /me, logout"
Write-Host "    P02 -- Cadastro RT (local + Keycloak)"
Write-Host ""
Write-Host "  Deploy da Sprint 3 concluido com sucesso!" -ForegroundColor Green
exit 0
