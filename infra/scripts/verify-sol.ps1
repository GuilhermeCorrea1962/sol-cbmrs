###############################################################################
# verify-sol.ps1 -- Verificacao funcional do sistema SOL CBM-RS
# Executar no servidor:       powershell -File verify-sol.ps1
# Executar de maquina remota: powershell -File verify-sol.ps1 -ServerIP 10.62.2.40
###############################################################################

param(
    [string]$ServerIP   = "localhost",
    [string]$AdminUser  = "sol-admin",
    [string]$AdminPass  = "Admin@SOL2026",
    [string]$ClientId   = "sol-frontend",
    [int]   $PortApi    = 8080,
    [int]   $PortKc     = 8180,
    [int]   $PortMinio  = 9000,
    [int]   $PortMail   = 8025,
    [switch]$ManterdDados  # se presente, nao remove o licenciamento de teste
)

$ErrorActionPreference = "SilentlyContinue"

$BASE     = "http://${ServerIP}:${PortApi}/api"
$KC_BASE  = "http://${ServerIP}:${PortKc}"
$MINIO    = "http://${ServerIP}:${PortMinio}"
$MAILHOG  = "http://${ServerIP}:${PortMail}"

$ok  = 0
$err = 0
$warn = 0
$licId = $null

function Write-Step { param($n, $msg) Write-Host "`n=== [$n] $msg ===" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green;  $script:ok++  }
function Write-ERR  { param($msg) Write-Host "  [ERRO] $msg" -ForegroundColor Red;    $script:err++ }
function Write-WARN { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warn++ }
function Write-INFO { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Gray }

###############################################################################
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  SOL CBM-RS -- Verificacao Funcional" -ForegroundColor Magenta
Write-Host "  Servidor : $ServerIP" -ForegroundColor Magenta
Write-Host "  Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

###############################################################################
Write-Step "1" "Conectividade TCP (portas)"

foreach ($porta in @($PortApi, $PortKc, $PortMinio, $PortMail)) {
    $tcp = Test-NetConnection -ComputerName $ServerIP -Port $porta -WarningAction SilentlyContinue
    if ($tcp.TcpTestSucceeded) {
        Write-OK "Porta $porta acessivel"
    } else {
        Write-ERR "Porta $porta INACESSIVEL (verifique firewall ou servico)"
    }
}

###############################################################################
Write-Step "2" "Health Check -- Spring Boot Actuator"

try {
    $health = Invoke-RestMethod -Uri "$BASE/actuator/health" -TimeoutSec 10
    if ($health.status -eq "UP") {
        Write-OK "Backend status: UP"
    } else {
        Write-ERR "Backend status: $($health.status)"
    }
} catch {
    Write-ERR "Health check falhou: $_"
}

###############################################################################
Write-Step "3" "Keycloak -- Token JWT"

$TOKEN  = $null
$AUTH   = $null

try {
    $body = "grant_type=password&client_id=${ClientId}&username=${AdminUser}&password=${AdminPass}"
    $resp = Invoke-RestMethod -Uri "$KC_BASE/realms/sol/protocol/openid-connect/token" `
        -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 15
    $TOKEN = $resp.access_token
    $AUTH  = @{ Authorization = "Bearer $TOKEN" }
    Write-OK "Token JWT obtido (expires_in: $($resp.expires_in)s)"
} catch {
    Write-ERR "Falha ao obter token: $_"
}

# Decodificar e validar o token
if ($TOKEN) {
    try {
        $partes = $TOKEN.Split(".")
        $pad = $partes[1].Length % 4
        if ($pad) { $partes[1] += "=" * (4 - $pad) }
        $payload = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($partes[1])) | ConvertFrom-Json

        $exp  = ([DateTimeOffset]::FromUnixTimeSeconds($payload.exp)).LocalDateTime
        $vida = ($exp - (Get-Date)).TotalSeconds

        Write-INFO "  iss : $($payload.iss)"
        Write-INFO "  sub : $($payload.sub)"
        Write-INFO "  exp : $exp (em $([int]$vida)s)"

        if ($vida -gt 0) {
            Write-OK "Token valido por mais $([int]$vida) segundos"
        } else {
            Write-ERR "Token JA EXPIRADO"
        }

        if ($payload.iss -match $ServerIP -or $payload.iss -match "localhost") {
            Write-OK "Issuer coerente com o servidor configurado"
        } else {
            Write-WARN "Issuer '$($payload.iss)' pode nao coincidir com issuer-uri do Spring Boot"
        }
    } catch {
        Write-WARN "Nao foi possivel decodificar o token: $_"
    }
}

###############################################################################
Write-Step "4" "API -- Endpoints autenticados (GET)"

if (-not $AUTH) {
    Write-ERR "Sem token -- pulando testes autenticados"
} else {
    # Licenciamentos
    try {
        $lic = Invoke-RestMethod -Uri "$BASE/licenciamentos" -Headers $AUTH -TimeoutSec 10
        Write-OK "GET /licenciamentos -- total: $($lic.totalElements)"
    } catch {
        Write-ERR "GET /licenciamentos falhou ($($_.Exception.Response.StatusCode)): $_"
    }

    # Usuarios
    try {
        $usr = Invoke-RestMethod -Uri "$BASE/usuarios" -Headers $AUTH -TimeoutSec 10
        Write-OK "GET /usuarios -- total: $($usr.totalElements)"
    } catch {
        Write-ERR "GET /usuarios falhou ($($_.Exception.Response.StatusCode)): $_"
    }
}

###############################################################################
Write-Step "5" "API -- Criar licenciamento de teste (POST)"

if (-not $AUTH) {
    Write-ERR "Sem token -- pulando criacao"
} else {
    $bodyLic = @{
        tipo            = "PPCI"
        areaConstruida  = 150.0
        alturaMaxima    = 6.0
        numPavimentos   = 2
        tipoOcupacao    = "Comercial"
        usoPredominante = "Escritorio"
        endereco        = @{
            cep        = "90010100"
            logradouro = "Av Borges de Medeiros"
            numero     = "999"
            bairro     = "Centro"
            municipio  = "Porto Alegre"
            uf         = "RS"
        }
    } | ConvertTo-Json -Depth 5

    try {
        $novo = Invoke-RestMethod -Uri "$BASE/licenciamentos" `
            -Method POST -Headers $AUTH -Body $bodyLic -ContentType "application/json" -TimeoutSec 10
        $licId = $novo.id
        if ($novo.status -eq "RASCUNHO") {
            Write-OK "Licenciamento criado. ID: $licId | Status: $($novo.status)"
        } else {
            Write-WARN "Status inesperado: $($novo.status) (esperado RASCUNHO)"
        }
    } catch {
        Write-ERR "POST /licenciamentos falhou: $_"
    }

    # GET por ID
    if ($licId) {
        try {
            $get = Invoke-RestMethod -Uri "$BASE/licenciamentos/$licId" -Headers $AUTH -TimeoutSec 10
            Write-OK "GET /licenciamentos/$licId OK -- Municipio: $($get.endereco.municipio)"
        } catch {
            Write-ERR "GET /licenciamentos/$licId falhou: $_"
        }
    }
}

###############################################################################
Write-Step "6" "MinIO -- Console de armazenamento"

try {
    $minio = Invoke-RestMethod -Uri "$MINIO/minio/health/live" -TimeoutSec 10
    Write-OK "MinIO health: OK"
} catch {
    # MinIO pode retornar 200 sem corpo ou outro status
    if ($_.Exception.Response.StatusCode.value__ -eq 200) {
        Write-OK "MinIO respondendo (HTTP 200)"
    } else {
        Write-WARN "MinIO nao respondeu no endpoint /health/live -- verifique $MINIO"
    }
}

###############################################################################
Write-Step "7" "MailHog -- Servidor SMTP de desenvolvimento"

try {
    $mail = Invoke-RestMethod -Uri "$MAILHOG/api/v2/messages" -TimeoutSec 10
    Write-OK "MailHog respondendo. Mensagens na caixa: $($mail.total)"
} catch {
    Write-WARN "MailHog indisponivel em $MAILHOG (nao critico para operacao da API)"
}

###############################################################################
Write-Step "8" "Limpeza -- Remover licenciamento de teste"

if ($licId -and -not $ManterdDados -and $AUTH) {
    try {
        Invoke-RestMethod -Uri "$BASE/licenciamentos/$licId" `
            -Method DELETE -Headers $AUTH -TimeoutSec 10 | Out-Null
        Write-OK "Licenciamento de teste $licId removido."
    } catch {
        Write-WARN "Nao foi possivel remover licenciamento $licId (pode nao existir endpoint DELETE ou ja removido)"
    }
} elseif ($licId -and $ManterdDados) {
    Write-INFO "Flag -ManterdDados ativo -- licenciamento $licId mantido para inspecao."
}

###############################################################################
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  SUMARIO DA VERIFICACAO" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  OK      : $ok"   -ForegroundColor Green
Write-Host "  AVISOS  : $warn" -ForegroundColor $(if ($warn -gt 0) { "Yellow" } else { "Green" })
Write-Host "  ERROS   : $err"  -ForegroundColor $(if ($err  -gt 0) { "Red"    } else { "Green" })
Write-Host "  Hora fim: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

if ($err -eq 0 -and $warn -eq 0) {
    Write-Host "  Sistema SOL operacional. Todos os testes passaram." -ForegroundColor Green
} elseif ($err -eq 0) {
    Write-Host "  Sistema SOL operacional com avisos. Revise os itens [WARN]." -ForegroundColor Yellow
} else {
    Write-Host "  $err erro(s) encontrado(s). Revise os itens [ERRO] acima." -ForegroundColor Red
}
Write-Host ""
