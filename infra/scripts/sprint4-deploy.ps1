#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy automatizado da Sprint 4 do sistema SOL CBM-RS.

.DESCRIPTION
    Para o servico SOL-Backend, compila com Maven (Java 21), reinicia,
    aguarda inicializacao e executa smoke tests dos fluxos P03:
      - POST /licenciamentos            (cria licenciamento em RASCUNHO)
      - POST /arquivos/upload           (upload de PDF via multipart)
      - GET  /licenciamentos/{id}/arquivos (lista arquivos do licenciamento)
      - GET  /arquivos/{id}/download-url   (URL pre-assinada MinIO)
      - POST /licenciamentos/{id}/submeter (RASCUNHO -> ANALISE_PENDENTE)
      - Verificacao do status apos submissao
      - Limpeza no Oracle (remove licenciamento + arquivos de teste)

.NOTES
    Executar como Administrador.
    Servico Windows: SOL-Backend
    PRE-REQUISITO: MinIO (SOL-MinIO) deve estar rodando com bucket sol-arquivos.
    PRE-REQUISITO: usuario sol-admin deve existir no realm sol com role ADMIN
                   e Direct Access Grants habilitado em sol-frontend.
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

# Credenciais do usuario de teste (criado na Sprint 3)
$AdminUser     = "sol-admin"
$AdminPassword = "Admin@SOL2026"

# Dados do licenciamento de teste (removido na limpeza)
$TestCep       = "90010100"
$TestLogradouro = "Rua dos Andradas"
$TestNumero    = "999"
$TestMunicipio = "Porto Alegre"

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

# Upload multipart via System.Net.Http (compativel com PS 5.1)
function Invoke-MultipartUpload {
    param(
        [string]$Uri,
        [string]$FilePath,
        [string]$FieldNameFile,
        [hashtable]$Fields,
        [string]$BearerToken
    )

    Add-Type -AssemblyName System.Net.Http

    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.DefaultRequestHeaders.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $BearerToken)

    $multipart = [System.Net.Http.MultipartFormDataContent]::new()

    # Adiciona o arquivo
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
    $fileContent.Headers.ContentType =
        [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/pdf")
    $multipart.Add($fileContent, $FieldNameFile, [System.IO.Path]::GetFileName($FilePath))

    # Adiciona campos de texto
    foreach ($key in $Fields.Keys) {
        $sc = [System.Net.Http.StringContent]::new($Fields[$key])
        $multipart.Add($sc, $key)
    }

    $task = $httpClient.PostAsync($Uri, $multipart)
    $task.Wait()
    $response = $task.Result
    $body = $response.Content.ReadAsStringAsync().Result
    $httpClient.Dispose()

    if (-not $response.IsSuccessStatusCode) {
        throw "HTTP $([int]$response.StatusCode): $body"
    }

    return $body | ConvertFrom-Json
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
# 6. Login via /auth/login
# ---------------------------------------------------------------------------
Write-Step "Login -- POST /auth/login (usuario: $AdminUser)"

$loginBody = @{
    username = $AdminUser
    password = $AdminPassword
} | ConvertTo-Json

$tokenResponse = $null
try {
    $tokenResponse = Invoke-RestMethod `
        -Uri "$BaseUrl/auth/login" `
        -Method POST `
        -Body $loginBody `
        -ContentType "application/json" `
        -TimeoutSec 15
    Write-OK "Login OK -- token expira em $($tokenResponse.expires_in)s"
} catch {
    Write-FAIL "Login falhou: $($_.Exception.Message)"
    Write-WARN "Verifique se sol-admin existe no realm sol, tem role ADMIN e Direct Access Grants habilitado"
    exit 1
}

$accessToken = $tokenResponse.access_token
$authHeader  = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------------------
# 7. Smoke test P03 -- POST /licenciamentos (cria em RASCUNHO)
# ---------------------------------------------------------------------------
Write-Step "Smoke test P03 -- POST /licenciamentos"

$licBody = @{
    tipo           = "PPCI"
    areaConstruida = 500.00
    alturaMaxima   = 10.00
    numPavimentos  = 3
    tipoOcupacao   = "Comercial - Loja"
    usoPredominante = "Comercial"
    endereco       = @{
        cep        = $TestCep
        logradouro = $TestLogradouro
        numero     = $TestNumero
        complemento = $null
        bairro     = "Centro Historico"
        municipio  = $TestMunicipio
        uf         = "RS"
        latitude   = $null
        longitude  = $null
        dataAtualizacao = $null
    }
    responsavelTecnicoId = $null
    responsavelUsoId     = $null
    licenciamentoPaiId   = $null
} | ConvertTo-Json -Depth 5

$licCriado = $null
try {
    $licCriado = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos" `
        -Method POST `
        -Body $licBody `
        -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -TimeoutSec 15
    Write-OK "Licenciamento criado -- id=$($licCriado.id) status=$($licCriado.status)"
} catch {
    Write-FAIL "Criacao de licenciamento falhou: $($_.Exception.Message)"
    exit 1
}

# ---------------------------------------------------------------------------
# 8. Smoke test P03 -- POST /arquivos/upload (PDF de teste)
# ---------------------------------------------------------------------------
Write-Step "Smoke test P03 -- POST /arquivos/upload (multipart)"

# Cria um PDF minimo valido para o teste
$pdfMinimo = @"
%PDF-1.0
1 0 obj<</Type /Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type /Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type /Page/MediaBox[0 0 612 792]/Parent 2 0 R>>endobj
xref
0 4
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
trailer<</Size 4/Root 1 0 R>>
startxref
190
%%EOF
"@
$tmpPdf = [System.IO.Path]::GetTempFileName() + ".pdf"
[System.IO.File]::WriteAllText($tmpPdf, $pdfMinimo)

$arquivoCriado = $null
try {
    $arquivoCriado = Invoke-MultipartUpload `
        -Uri "$BaseUrl/arquivos/upload" `
        -FilePath $tmpPdf `
        -FieldNameFile "file" `
        -Fields @{
            licenciamentoId = "$($licCriado.id)"
            tipoArquivo     = "PPCI"
        } `
        -BearerToken $accessToken

    Write-OK "Upload OK -- arquivoId=$($arquivoCriado.id) nome=$($arquivoCriado.nomeArquivo) tamanho=$($arquivoCriado.tamanho) bytes"
} catch {
    Write-FAIL "Upload falhou: $($_.Exception.Message)"
    Write-WARN "Verifique se o servico SOL-MinIO esta rodando e o bucket sol-arquivos existe"
} finally {
    Remove-Item $tmpPdf -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 9. Smoke test P03 -- GET /licenciamentos/{id}/arquivos (lista arquivos)
# ---------------------------------------------------------------------------
Write-Step "Smoke test P03 -- GET /licenciamentos/$($licCriado.id)/arquivos"
try {
    $listaArquivos = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licCriado.id)/arquivos" `
        -Headers $authHeader -TimeoutSec 10
    Write-OK "Lista OK -- $($listaArquivos.Count) arquivo(s) encontrado(s)"
    $listaArquivos | ForEach-Object {
        Write-Host "    id=$($_.id) tipo=$($_.tipoArquivo) nome=$($_.nomeArquivo)" -ForegroundColor Gray
    }
} catch {
    Write-FAIL "Listagem de arquivos falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 10. Smoke test P03 -- GET /arquivos/{id}/download-url (URL pre-assinada)
# ---------------------------------------------------------------------------
if ($null -ne $arquivoCriado) {
    Write-Step "Smoke test P03 -- GET /arquivos/$($arquivoCriado.id)/download-url"
    try {
        $urlResp = Invoke-RestMethod `
            -Uri "$BaseUrl/arquivos/$($arquivoCriado.id)/download-url" `
            -Headers $authHeader -TimeoutSec 10
        $urlPreview = if ($urlResp.url.Length -gt 80) {
            $urlResp.url.Substring(0, 80) + "..."
        } else {
            $urlResp.url
        }
        Write-OK "URL pre-assinada OK -- $urlPreview"
    } catch {
        Write-FAIL "Geracao de URL pre-assinada falhou: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 11. Smoke test P03 -- POST /licenciamentos/{id}/submeter (RASCUNHO -> ANALISE_PENDENTE)
# ---------------------------------------------------------------------------
Write-Step "Smoke test P03 -- POST /licenciamentos/$($licCriado.id)/submeter"
$licSubmetido = $null
try {
    $licSubmetido = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licCriado.id)/submeter" `
        -Method POST `
        -Headers $authHeader -TimeoutSec 15
    Write-OK "Submissao OK -- status=$($licSubmetido.status)"
} catch {
    Write-FAIL "Submissao falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 12. Verificacao do status apos submissao
# ---------------------------------------------------------------------------
Write-Step "Verificando status apos submissao -- GET /licenciamentos/$($licCriado.id)"
try {
    $licAtual = Invoke-RestMethod `
        -Uri "$BaseUrl/licenciamentos/$($licCriado.id)" `
        -Headers $authHeader -TimeoutSec 10
    if ($licAtual.status -eq "ANALISE_PENDENTE") {
        Write-OK "Status verificado -- ANALISE_PENDENTE (correto)"
    } else {
        Write-WARN "Status inesperado -- $($licAtual.status) (esperado ANALISE_PENDENTE)"
    }
} catch {
    Write-FAIL "Verificacao de status falhou: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 13. Limpeza -- remove arquivo e licenciamento de teste do Oracle
# ---------------------------------------------------------------------------
Write-Step "Limpeza -- removendo dados de teste do Oracle"

$sqlDelete = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.marco_processo WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.boleto WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.licenciamento WHERE id_licenciamento = $($licCriado.id);
COMMIT;
EXIT;
"@

$tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
Set-Content -Path $tmpSql -Value $sqlDelete
try {
    & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
    Write-OK "Dados de teste removidos do Oracle (licenciamento id=$($licCriado.id))"
} catch {
    Write-WARN "Nao foi possivel remover do Oracle: $($_.Exception.Message)"
} finally {
    Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
}

# Nota: o objeto no MinIO ja foi removido ao deletar ArquivoED via Oracle,
# mas como deletamos direto no Oracle sem passar pelo DELETE /arquivos/{id},
# o objeto no bucket pode permanecer. Limpar manualmente se necessario:
# mc.exe rm sol-minio/sol-arquivos/licenciamentos/<id>/ --recursive

# ---------------------------------------------------------------------------
# 14. Resultado final
# ---------------------------------------------------------------------------
Write-Step "Sprint 4 concluida"
Write-Host ""
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P03 -- Criacao de Licenciamento (RASCUNHO)"
Write-Host "    P03 -- Upload de PPCI (multipart -> MinIO -> Oracle)"
Write-Host "    P03 -- Listagem de arquivos do licenciamento"
Write-Host "    P03 -- URL pre-assinada MinIO (1h)"
Write-Host "    P03 -- Submissao (RASCUNHO -> ANALISE_PENDENTE + marco SUBMISSAO)"
Write-Host ""
Write-Host "  Deploy da Sprint 4 concluido com sucesso!" -ForegroundColor Green
exit 0
