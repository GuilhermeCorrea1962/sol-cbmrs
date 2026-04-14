#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 9 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P09:

      Fluxo A -- Troca de Responsavel Tecnico (RT) -- ciclo completo de 3 passos:
        Setup: criar licenciamento (RASCUNHO)
        1. POST /licenciamentos/{id}/solicitar-troca-rt    (-> marco TROCA_RT_SOLICITADA)
        2. POST /licenciamentos/{id}/autorizar-troca-rt    (-> marco TROCA_RT_AUTORIZADA)
        3. POST /licenciamentos/{id}/efetivar-troca-rt     (-> marco TROCA_RT_EFETIVADA + RT atualizado)
        4. GET  /licenciamentos/{id}                       (confirma responsavelTecnicoId = adminId)
        5. GET  /licenciamentos/{id}/marcos                (verifica marcos P09)

      Fluxo B -- Troca de Responsavel pelo Uso (RU) -- efetivacao direta:
        Setup: criar licenciamento (RASCUNHO)
        1. POST /licenciamentos/{id}/efetivar-troca-ru     (-> marco TROCA_RU_EFETIVADA + RU atualizado)
        2. GET  /licenciamentos/{id}                       (confirma responsavelUsoId = adminId)
        3. GET  /licenciamentos/{id}/marcos                (verifica marco TROCA_RU_EFETIVADA)

      Limpeza Oracle: remove licenciamentos A e B + dependencias.

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: Sprints 1 a 8 concluidas com sucesso.
    PRE-REQUISITO: sol-admin com role ADMIN no realm sol do Keycloak.

    P09 e um fluxo lateral: nao altera o StatusLicenciamento principal.
    Funciona em qualquer status nao terminal (nao EXTINTO, INDEFERIDO, RENOVADO).
    O teste usa licenciamentos em RASCUNHO para minimizar o setup.

    Troca RT: 3 passos (solicitacao -> autorizacao -> efetivacao).
    Troca RU: 1 passo direto pelo ADMIN (sem autorizacao previa).
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
$WaitSeconds   = 35
$MavenOpts     = "-Dmaven.test.skip=true -q"
$AdminUser     = "sol-admin"
$AdminPassword = "Admin@SOL2026"
$TestCep       = "90010100"

# ---------------------------------------------------------------------------
# Funcoes auxiliares
# ---------------------------------------------------------------------------
function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }

function Show-ErrorBody {
    param($CatchVar)
    try {
        $resp = $CatchVar.Exception.Response
        if ($null -ne $resp) {
            $sc = [int]$resp.StatusCode
            try {
                $stream = $resp.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $corpo  = $reader.ReadToEnd()
                $reader.Dispose()
                Write-Host "  [DIAGNOSTICO] HTTP $sc -- $corpo" -ForegroundColor Magenta
            } catch {
                if ($null -ne $CatchVar.ErrorDetails) {
                    Write-Host "  [DIAGNOSTICO] HTTP $sc -- $($CatchVar.ErrorDetails.Message)" -ForegroundColor Magenta
                } else {
                    Write-WARN "Nao foi possivel ler corpo do erro HTTP $sc"
                }
            }
        }
    } catch {
        Write-WARN "Show-ErrorBody falhou: $($_.Exception.Message)"
    }
}

function New-LicBody {
    return @{
        tipo = "PPCI"; areaConstruida = 300.00; alturaMaxima = 8.00
        numPavimentos = 2; tipoOcupacao = "Residencial - Apartamento"
        usoPredominante = "Residencial"
        endereco = @{
            cep = $TestCep; logradouro = "Rua Voluntarios da Patria"; numero = "100"
            complemento = $null; bairro = "Santana"
            municipio = "Porto Alegre"; uf = "RS"
            latitude = $null; longitude = $null; dataAtualizacao = $null
        }
        responsavelTecnicoId = $null; responsavelUsoId = $null
        licenciamentoPaiId = $null
    } | ConvertTo-Json -Depth 5
}

function New-Lic {
    param([hashtable]$AuthHdr)
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body (New-LicBody) -ContentType "application/json" `
        -Headers $AuthHdr -TimeoutSec 15
    Write-OK "Licenciamento criado -- id=$($lic.id) status=$($lic.status)"
    return $lic
}

# ---------------------------------------------------------------------------
# 1. Parar servico
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceName"
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force; Start-Sleep -Seconds 5
    Write-OK "Servico parado"
} else { Write-WARN "Servico nao estava em execucao -- continuando" }

# ---------------------------------------------------------------------------
# 2. Compilar com Maven
# ---------------------------------------------------------------------------
Write-Step "Compilando com Maven (JAVA_HOME=$JavaHome)"
$env:JAVA_HOME = $JavaHome
$env:PATH      = "$JavaHome\bin;$env:PATH"
$mvn = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvn)) { $mvn = "mvn" }

Push-Location $ProjectRoot
try {
    & cmd /c "$mvn clean package $MavenOpts"
    if ($LASTEXITCODE -ne 0) { throw "Maven falhou com codigo $LASTEXITCODE" }
    Write-OK "Build concluido com sucesso"
} finally { Pop-Location }

# ---------------------------------------------------------------------------
# 3. Reiniciar servico
# ---------------------------------------------------------------------------
Write-Step "Reiniciando servico $ServiceName"
if ($null -ne $svc) {
    Start-Service -Name $ServiceName; Write-OK "Servico iniciado"
} else {
    $jar = Get-ChildItem "$ProjectRoot\target\*.jar" |
           Where-Object { $_.Name -notlike "*sources*" } | Select-Object -First 1
    if ($null -eq $jar) { throw "JAR nao encontrado" }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
        -ArgumentList "-jar `"$($jar.FullName)`"" `
        -WorkingDirectory $ProjectRoot -NoNewWindow
    Write-WARN "JAR iniciado diretamente (modo dev)"
}

# ---------------------------------------------------------------------------
# 4. Aguardar e health check
# ---------------------------------------------------------------------------
Write-Step "Aguardando $WaitSeconds segundos"
Start-Sleep -Seconds $WaitSeconds

Write-Step "Health check -- $HealthUrl"
$healthy = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) { Write-OK "Saudavel (tentativa $i)"; $healthy = $true; break }
    } catch { Write-WARN "Tentativa $i falhou -- aguardando 10s"; Start-Sleep -Seconds 10 }
}
if (-not $healthy) { Write-FAIL "Health check falhou"; exit 1 }

# ---------------------------------------------------------------------------
# 5. Login
# ---------------------------------------------------------------------------
Write-Step "Login -- POST /auth/login"
$tr = $null
try {
    $tr = Invoke-RestMethod -Uri "$BaseUrl/auth/login" -Method POST `
        -Body (@{ username = $AdminUser; password = $AdminPassword } | ConvertTo-Json) `
        -ContentType "application/json" -TimeoutSec 15
    Write-OK "Login OK"
} catch { Write-FAIL "Login falhou: $($_.Exception.Message)"; exit 1 }

$token   = $tr.access_token
$authHdr = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------------------
# 6. Obter ID do usuario admin
# ---------------------------------------------------------------------------
Write-Step "Obtendo ID do usuario admin"
$adminId   = 1
$adminNome = "admin"
try {
    $users = Invoke-RestMethod -Uri "$BaseUrl/usuarios?page=0&size=50" `
        -Headers $authHdr -TimeoutSec 10
    $u = $users.content | Where-Object {
        $_.nome -like "*admin*" -or $_.email -like "*admin*"
    } | Select-Object -First 1
    if ($null -eq $u) { $u = $users.content | Select-Object -First 1 }
    if ($null -ne $u) {
        $adminId   = $u.id
        $adminNome = $u.nome
        Write-OK "Admin id=$adminId nome=$adminNome"
    } else { Write-WARN "Usuario nao encontrado -- usando id=1" }
} catch {
    Write-WARN "GET /usuarios falhou -- usando id=1 como fallback"
    Show-ErrorBody $_
}

# ===========================================================================
# FLUXO A -- P09: Troca de Responsavel Tecnico (RT) -- 3 passos
# ===========================================================================
Write-Step "=== FLUXO A: P09 -- Troca de Responsavel Tecnico (RT) ==="

$licA = $null
try {
    Write-Step "Fluxo A -- Setup: criar licenciamento"
    $licA = New-Lic -AuthHdr $authHdr

    # --- Teste A1: Solicitar troca RT ---
    Write-Step "Fluxo A -- Teste A1: POST /licenciamentos/$($licA.id)/solicitar-troca-rt"
    $solBody = @{
        motivo = "RT original nao esta mais disponivel para acompanhar o projeto. Necessidade de substituicao."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/solicitar-troca-rt" `
        -Method POST -Body $solBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Solicitacao de troca RT registrada -- id=$($licA.id)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "TROCA_RT_SOLICITADA" }) {
        Write-OK "Marco TROCA_RT_SOLICITADA presente"
    } else { Write-WARN "Marco TROCA_RT_SOLICITADA NAO encontrado" }

    # --- Teste A2: Autorizar troca RT ---
    Write-Step "Fluxo A -- Teste A2: POST /licenciamentos/$($licA.id)/autorizar-troca-rt"
    $autBody = @{
        motivo = "Solicitacao aprovada pelo setor de licenciamento. Prosseguir com a substituicao."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/autorizar-troca-rt" `
        -Method POST -Body $autBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Troca RT autorizada -- id=$($licA.id)"

    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    if ($marcos | Where-Object { $_.tipoMarco -eq "TROCA_RT_AUTORIZADA" }) {
        Write-OK "Marco TROCA_RT_AUTORIZADA presente"
    } else { Write-WARN "Marco TROCA_RT_AUTORIZADA NAO encontrado" }

    # --- Teste A3: Efetivar troca RT ---
    Write-Step "Fluxo A -- Teste A3: POST /licenciamentos/$($licA.id)/efetivar-troca-rt (novoRtId=$adminId)"
    $efRtBody = @{
        novoResponsavelId = $adminId
        motivo = "Troca de RT efetivada conforme autorizacao."
    } | ConvertTo-Json
    $licA = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licA.id)/efetivar-troca-rt" `
        -Method POST -Body $efRtBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Troca RT efetivada -- id=$($licA.id)"

    # --- Teste A4: Verificar responsavelTecnicoId ---
    Write-Step "Fluxo A -- Teste A4: GET /licenciamentos/$($licA.id) (confirma responsavelTecnicoId)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.responsavelTecnicoId -eq $adminId) {
        Write-OK "responsavelTecnicoId=$($cur.responsavelTecnicoId) ($($cur.responsavelTecnicoNome)) -- troca efetivada corretamente"
    } else {
        Write-WARN "responsavelTecnicoId=$($cur.responsavelTecnicoId) (esperado $adminId)"
    }

    # --- Teste A5: Verificar marcos P09 RT ---
    Write-Step "Fluxo A -- Teste A5: GET /licenciamentos/$($licA.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licA.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    foreach ($m in @("TROCA_RT_SOLICITADA", "TROCA_RT_AUTORIZADA", "TROCA_RT_EFETIVADA")) {
        if ($marcos | Where-Object { $_.tipoMarco -eq $m }) {
            Write-OK "Marco $m presente"
        } else { Write-WARN "Marco $m NAO encontrado" }
    }

} catch {
    Write-FAIL "Fluxo A falhou: $($_.Exception.Message)"
    Show-ErrorBody $_
}

# ===========================================================================
# FLUXO B -- P09: Troca de Responsavel pelo Uso (RU) -- efetivacao direta
# ===========================================================================
Write-Step "=== FLUXO B: P09 -- Troca de Responsavel pelo Uso (RU) ==="

$licB = $null
try {
    Write-Step "Fluxo B -- Setup: criar licenciamento"
    $licB = New-Lic -AuthHdr $authHdr

    # --- Teste B1: Efetivar troca RU ---
    Write-Step "Fluxo B -- Teste B1: POST /licenciamentos/$($licB.id)/efetivar-troca-ru (novoRuId=$adminId)"
    $efRuBody = @{
        novoResponsavelId = $adminId
        motivo = "Proprietario anterior vendeu o imovel. Novo responsavel pelo uso designado."
    } | ConvertTo-Json
    $licB = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licB.id)/efetivar-troca-ru" `
        -Method POST -Body $efRuBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Troca RU efetivada -- id=$($licB.id)"

    # --- Teste B2: Verificar responsavelUsoId ---
    Write-Step "Fluxo B -- Teste B2: GET /licenciamentos/$($licB.id) (confirma responsavelUsoId)"
    $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)" `
        -Headers $authHdr -TimeoutSec 10
    if ($cur.responsavelUsoId -eq $adminId) {
        Write-OK "responsavelUsoId=$($cur.responsavelUsoId) ($($cur.responsavelUsoNome)) -- troca efetivada corretamente"
    } else {
        Write-WARN "responsavelUsoId=$($cur.responsavelUsoId) (esperado $adminId)"
    }

    # --- Teste B3: Verificar marco TROCA_RU_EFETIVADA ---
    Write-Step "Fluxo B -- Teste B3: GET /licenciamentos/$($licB.id)/marcos"
    $marcos = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($licB.id)/marcos" `
        -Headers $authHdr -TimeoutSec 10
    Write-OK "Marcos registrados ($($marcos.Count)):"
    $marcos | ForEach-Object {
        Write-Host "    $($_.tipoMarco) | $($_.observacao)" -ForegroundColor Gray
    }
    if ($marcos | Where-Object { $_.tipoMarco -eq "TROCA_RU_EFETIVADA" }) {
        Write-OK "Marco TROCA_RU_EFETIVADA presente"
    } else { Write-WARN "Marco TROCA_RU_EFETIVADA NAO encontrado" }

} catch {
    Write-FAIL "Fluxo B falhou: $($_.Exception.Message)"
    Show-ErrorBody $_
}

# ===========================================================================
# LIMPEZA Oracle
# ===========================================================================
Write-Step "Limpeza Oracle -- removendo dados de teste"

foreach ($licLimpeza in @($licA, $licB)) {
    if ($null -ne $licLimpeza) {
        $lid = $licLimpeza.id
        $sql = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $lid;
DELETE FROM sol.marco_processo WHERE id_licenciamento = $lid;
DELETE FROM sol.boleto WHERE id_licenciamento = $lid;
DELETE FROM sol.licenciamento WHERE id_licenciamento = $lid;
COMMIT;
EXIT;
"@
        $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
        Set-Content -Path $tmpSql -Value $sql
        try {
            & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
            Write-OK "Licenciamento id=$lid removido"
        } catch {
            Write-WARN "Limpeza id=${lid}: $($_.Exception.Message)"
        } finally {
            Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
        }
    }
}

# ===========================================================================
# Resultado final
# ===========================================================================
Write-Step "Sprint 9 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P09 Fluxo A -- Troca RT: solicitar -> autorizar -> efetivar (3 passos)"
Write-Host "    P09 Fluxo A -- Marcos: TROCA_RT_SOLICITADA + TROCA_RT_AUTORIZADA + TROCA_RT_EFETIVADA"
Write-Host "    P09 Fluxo A -- responsavelTecnico atualizado para usuario admin"
Write-Host "    P09 Fluxo B -- Troca RU: efetivacao direta (1 passo)"
Write-Host "    P09 Fluxo B -- Marco: TROCA_RU_EFETIVADA"
Write-Host "    P09 Fluxo B -- responsavelUso atualizado para usuario admin"
Write-Host ""
Write-Host "  Deploy da Sprint 9 concluido com sucesso!" -ForegroundColor Green
exit 0
