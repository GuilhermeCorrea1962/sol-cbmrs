#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostico rapido da Sprint 9 -- identifica causa do HTTP 500.

.DESCRIPTION
    Faz login, decodifica o JWT para ver as roles reais,
    e testa os endpoints P09 capturando o corpo completo do erro.
    NAO recompila nem reinicia o servico.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$BaseUrl       = "http://localhost:8080/api"
$AdminUser     = "sol-admin"
$AdminPassword = "Admin@SOL2026"

function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [INFO] $M"  -ForegroundColor Yellow }

# Funcao que faz POST e captura SEMPRE o corpo (200 ou erro)
function Invoke-Post {
    param(
        [string]$Uri,
        [string]$Body,
        [hashtable]$Headers
    )
    try {
        $r = Invoke-WebRequest -Uri $Uri -Method POST -Body $Body `
            -ContentType "application/json" -Headers $Headers `
            -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        Write-OK "HTTP $($r.StatusCode)"
        Write-Host "  Corpo: $($r.Content)" -ForegroundColor Gray
        return ($r.Content | ConvertFrom-Json)
    } catch {
        $resp = $_.Exception.Response
        if ($null -ne $resp) {
            $sc = [int]$resp.StatusCode
            try {
                # PowerShell 5.1: usar GetResponseStream
                $stream = $resp.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $corpo  = $reader.ReadToEnd()
                $reader.Dispose()
                Write-FAIL "HTTP $sc"
                Write-Host "  [CORPO ERRO] $corpo" -ForegroundColor Magenta
            } catch {
                # PowerShell 7+: tentar ErrorDetails
                $corpo = $_.ErrorDetails.Message
                Write-FAIL "HTTP $sc"
                Write-Host "  [CORPO ERRO] $corpo" -ForegroundColor Magenta
            }
        } else {
            Write-FAIL "Sem resposta HTTP: $($_.Exception.Message)"
        }
        return $null
    }
}

# ---------------------------------------------------------------------------
# 1. Login
# ---------------------------------------------------------------------------
Write-Step "Login"
$loginBody = @{ username = $AdminUser; password = $AdminPassword } | ConvertTo-Json
$tr = $null
try {
    $tr = Invoke-RestMethod -Uri "$BaseUrl/auth/login" -Method POST `
        -Body $loginBody -ContentType "application/json" -TimeoutSec 15
    Write-OK "Login OK -- token obtido"
} catch {
    Write-FAIL "Login falhou: $($_.Exception.Message)"; exit 1
}

$token   = $tr.access_token
$authHdr = @{ Authorization = "Bearer $token" }

# ---------------------------------------------------------------------------
# 2. Decodificar JWT -- ver roles reais
# ---------------------------------------------------------------------------
Write-Step "Decodificando JWT (payload)"
try {
    $parts   = $token.Split(".")
    $payload = $parts[1]
    # Adicionar padding Base64
    $pad = 4 - ($payload.Length % 4)
    if ($pad -ne 4) { $payload += "=" * $pad }
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    $jwt     = $decoded | ConvertFrom-Json
    Write-OK "sub (keycloakId): $($jwt.sub)"
    Write-OK "preferred_username: $($jwt.preferred_username)"
    if ($null -ne $jwt.roles) {
        Write-OK "roles (claim 'roles'): $($jwt.roles -join ', ')"
    } else {
        Write-WARN "Claim 'roles' NAO encontrado no JWT!"
        Write-Host "  Claims disponiveis: $($decoded)" -ForegroundColor Yellow
    }
    if ($null -ne $jwt.realm_access) {
        Write-OK "realm_access.roles: $($jwt.realm_access.roles -join ', ')"
    }
    if ($null -ne $jwt.resource_access) {
        Write-OK "resource_access: $($decoded | Select-String 'resource_access')"
    }
} catch {
    Write-WARN "Nao foi possivel decodificar JWT: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 3. Criar licenciamento de teste
# ---------------------------------------------------------------------------
Write-Step "Criar licenciamento de teste (RASCUNHO)"
$licBody = @{
    tipo = "PPCI"; areaConstruida = 100.00; alturaMaxima = 5.00; numPavimentos = 1
    tipoOcupacao = "Comercial"; usoPredominante = "Comercial"
    endereco = @{
        cep = "90010100"; logradouro = "Av. Borges de Medeiros"; numero = "1501"
        complemento = $null; bairro = "Centro"; municipio = "Porto Alegre"; uf = "RS"
        latitude = $null; longitude = $null; dataAtualizacao = $null
    }
    responsavelTecnicoId = $null; responsavelUsoId = $null; licenciamentoPaiId = $null
} | ConvertTo-Json -Depth 5

$lic = Invoke-Post -Uri "$BaseUrl/licenciamentos" -Body $licBody -Headers $authHdr
if ($null -eq $lic) { Write-FAIL "Nao foi possivel criar licenciamento"; exit 1 }
$licId = $lic.id
Write-OK "Licenciamento id=$licId criado"

# ---------------------------------------------------------------------------
# 4. Testar solicitar-troca-rt
# ---------------------------------------------------------------------------
Write-Step "POST /licenciamentos/$licId/solicitar-troca-rt"
$solBody = @{ motivo = "Teste diagnostico P09." } | ConvertTo-Json
Invoke-Post -Uri "$BaseUrl/licenciamentos/$licId/solicitar-troca-rt" `
    -Body $solBody -Headers $authHdr | Out-Null

# ---------------------------------------------------------------------------
# 5. Testar efetivar-troca-ru
# ---------------------------------------------------------------------------
Write-Step "POST /licenciamentos/$licId/efetivar-troca-ru"
$ruBody = @{ novoResponsavelId = 1; motivo = "Teste diagnostico P09." } | ConvertTo-Json
Invoke-Post -Uri "$BaseUrl/licenciamentos/$licId/efetivar-troca-ru" `
    -Body $ruBody -Headers $authHdr | Out-Null

# ---------------------------------------------------------------------------
# 6. Testar GET /usuarios (exige ADMIN)
# ---------------------------------------------------------------------------
Write-Step "GET /usuarios (requer role ADMIN)"
try {
    $r = Invoke-WebRequest -Uri "$BaseUrl/usuarios?page=0&size=5" `
        -Headers $authHdr -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-OK "GET /usuarios OK -- HTTP $($r.StatusCode)"
} catch {
    $resp = $_.Exception.Response
    if ($null -ne $resp) {
        $sc = [int]$resp.StatusCode
        try {
            $stream = $resp.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $corpo  = $reader.ReadToEnd()
            $reader.Dispose()
            Write-FAIL "GET /usuarios falhou HTTP $sc -- $corpo"
        } catch {
            Write-FAIL "GET /usuarios falhou HTTP $sc"
        }
    } else {
        Write-FAIL "GET /usuarios sem resposta: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 7. Limpeza
# ---------------------------------------------------------------------------
Write-Step "Limpeza -- removendo licenciamento id=$licId"
$sql = @"
DELETE FROM sol.marco_processo WHERE id_licenciamento = $licId;
DELETE FROM sol.licenciamento WHERE id_licenciamento = $licId;
COMMIT;
EXIT;
"@
$tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
Set-Content -Path $tmpSql -Value $sql
try {
    & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
    Write-OK "Licenciamento id=$licId removido"
} catch {
    Write-WARN "Limpeza falhou: $($_.Exception.Message)"
} finally {
    Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
}

Write-Step "Diagnostico concluido"
