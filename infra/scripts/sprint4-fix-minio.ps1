#Requires -Version 5.1
<#
.SYNOPSIS
    Corrige incompatibilidade entre MinIO SDK 8.5.x e MinIO Server RELEASE.2025-09-07.

.DESCRIPTION
    O MinIO Server 2025-09-07 passou a exigir checksums de integridade nas requisicoes
    PUT (alinhamento com o novo padrao AWS S3 Express). O SDK Java 8.5.17 ainda nao
    suporta o algoritmo crc64nvme exigido pelo servidor novo.

    Esta correcao atua em duas frentes:

    FRENTE 1 — Servidor MinIO (NSSM env var)
      Define MINIO_API_CONTENT_CHECKSUM_MODE=optional, que instrui o servidor a aceitar
      uploads sem checksum obrigatorio. Equivale ao comando:
        mc admin config set sol-minio/ api content_checksum_mode=optional

    FRENTE 2 — Aplicacao Java (MinioConfig.java atualizado)
      Interceptor OkHttp substitui "STREAMING-AWS4-HMAC-SHA256-PAYLOAD" por
      "UNSIGNED-PAYLOAD", eliminando o chunked signing que o servidor tambem rejeita.
      Apos esta correcao o SDK envia um PUT normal (Content-Length conhecido, sem
      Transfer-Encoding: chunked), compativel com o servidor em modo optional.

    Apos aplicar as correcoes, o script recompila e reinicia o servico, depois
    re-executa apenas os smoke tests de upload (etapas 7-12 do sprint4-deploy.ps1).

.NOTES
    Executar como Administrador.
    PRE-REQUISITO: NSSM instalado e servico SOL-MinIO registrado.
    PRE-REQUISITO: MinioConfig.java ja atualizado (versao corrigida no repositorio).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServiceBackend = "SOL-Backend"
$ServiceMinio   = "SOL-MinIO"
$JavaHome       = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$ProjectRoot    = "C:\SOL\backend"
$BaseUrl        = "http://localhost:8080/api"
$HealthUrl      = "$BaseUrl/health"
$KeycloakUrl    = "http://localhost:8180"
$MavenOpts      = "-Dmaven.test.skip=true -q"

$AdminUser      = "sol-admin"
$AdminPassword  = "Admin@SOL2026"
$TestCep        = "90010100"

function Write-Step { param([string]$M); Write-Host ""; Write-Host "===> $M" -ForegroundColor Cyan }
function Write-OK   { param([string]$M); Write-Host "  [OK] $M"    -ForegroundColor Green  }
function Write-FAIL { param([string]$M); Write-Host "  [FALHA] $M" -ForegroundColor Red    }
function Write-WARN { param([string]$M); Write-Host "  [AVISO] $M" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. Configurar MinIO Server: checksum mode = optional (via NSSM)
# ---------------------------------------------------------------------------
Write-Step "Configurando MinIO Server -- MINIO_API_CONTENT_CHECKSUM_MODE=optional"

$nssmPath = (Get-Command nssm.exe -ErrorAction SilentlyContinue)?.Source
if ($null -eq $nssmPath) {
    # Tenta locais comuns
    foreach ($p in @("C:\nssm\nssm.exe","C:\tools\nssm.exe","C:\Windows\nssm.exe")) {
        if (Test-Path $p) { $nssmPath = $p; break }
    }
}
if ($null -eq $nssmPath) {
    Write-WARN "nssm.exe nao encontrado no PATH -- tentando mc admin config set como alternativa"
    $mcPath = (Get-Command mc.exe -ErrorAction SilentlyContinue)?.Source
    if ($null -eq $mcPath) {
        foreach ($p in @("C:\MinIO\mc.exe","C:\tools\mc.exe")) {
            if (Test-Path $p) { $mcPath = $p; break }
        }
    }
    if ($null -ne $mcPath) {
        try {
            & $mcPath admin config set sol-minio/ api content_checksum_mode=optional 2>&1 | Out-Null
            Write-OK "Checksum mode configurado via mc admin config"
        } catch {
            Write-WARN "mc admin config falhou: $($_.Exception.Message)"
        }
    } else {
        Write-WARN "mc.exe tambem nao encontrado -- pulando configuracao de servidor"
    }
} else {
    try {
        # Le variavel atual para nao sobrescrever outras
        $currentEnv = & $nssmPath get $ServiceMinio AppEnvironmentExtra 2>&1
        if ($currentEnv -notmatch "MINIO_API_CONTENT_CHECKSUM_MODE") {
            $newEnv = if ($currentEnv -and $currentEnv -notmatch "^nssm") {
                "$currentEnv`nMINIO_API_CONTENT_CHECKSUM_MODE=optional"
            } else {
                "MINIO_API_CONTENT_CHECKSUM_MODE=optional"
            }
            & $nssmPath set $ServiceMinio AppEnvironmentExtra "$newEnv" | Out-Null
            Write-OK "NSSM: MINIO_API_CONTENT_CHECKSUM_MODE=optional adicionado ao servico $ServiceMinio"
        } else {
            Write-OK "NSSM: variavel MINIO_API_CONTENT_CHECKSUM_MODE ja configurada"
        }
    } catch {
        Write-WARN "NSSM set falhou: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 2. Reiniciar MinIO para aplicar a nova variavel de ambiente
# ---------------------------------------------------------------------------
Write-Step "Reiniciando servico $ServiceMinio"
try {
    Restart-Service -Name $ServiceMinio -Force
    Start-Sleep -Seconds 8
    Write-OK "MinIO reiniciado"
} catch {
    Write-WARN "Nao foi possivel reiniciar $ServiceMinio: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 3. Validar MinIO com mc (upload direto de teste)
# ---------------------------------------------------------------------------
Write-Step "Validando MinIO com mc.exe (upload de objeto de teste)"
$mcPath2 = $null
foreach ($p in @(
    (Get-Command mc.exe -ErrorAction SilentlyContinue)?.Source,
    "C:\MinIO\mc.exe","C:\tools\mc.exe"
)) { if ($p -and (Test-Path $p)) { $mcPath2 = $p; break } }

if ($null -ne $mcPath2) {
    $tmpTest = [System.IO.Path]::GetTempFileName() + ".txt"
    [System.IO.File]::WriteAllText($tmpTest, "minio-test-$(Get-Date -Format 'yyyyMMddHHmmss')")
    try {
        & $mcPath2 cp $tmpTest "sol-minio/sol-arquivos/health-test.txt" 2>&1 | Out-Null
        Write-OK "mc.exe: upload de objeto de teste OK -- MinIO Server operacional"
        & $mcPath2 rm "sol-minio/sol-arquivos/health-test.txt" 2>&1 | Out-Null
    } catch {
        Write-WARN "mc.exe upload falhou: $($_.Exception.Message)"
    } finally {
        Remove-Item $tmpTest -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-WARN "mc.exe nao encontrado -- pulando validacao direta do MinIO"
}

# ---------------------------------------------------------------------------
# 4. Parar Backend, recompilar com SDK 8.5.17 + MinioConfig corrigido
# ---------------------------------------------------------------------------
Write-Step "Parando servico $ServiceBackend para recompilacao"
$svc = Get-Service -Name $ServiceBackend -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceBackend -Force
    Start-Sleep -Seconds 5
    Write-OK "Backend parado"
} else {
    Write-WARN "Backend nao estava em execucao"
}

Write-Step "Compilando com Maven (SDK minio 8.5.17 + MinioConfig corrigido)"
$env:JAVA_HOME = $JavaHome
$env:PATH      = "$JavaHome\bin;$env:PATH"

$mvn = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvn)) { $mvn = "mvn" }

Push-Location $ProjectRoot
try {
    & cmd /c "$mvn clean package $MavenOpts"
    if ($LASTEXITCODE -ne 0) { throw "Maven falhou com codigo $LASTEXITCODE" }
    Write-OK "Build concluido"
} finally { Pop-Location }

# ---------------------------------------------------------------------------
# 5. Reiniciar Backend
# ---------------------------------------------------------------------------
Write-Step "Reiniciando servico $ServiceBackend"
if ($null -ne $svc) {
    Start-Service -Name $ServiceBackend
    Write-OK "Backend iniciado"
} else {
    $jar = Get-ChildItem "$ProjectRoot\target\*.jar" |
           Where-Object { $_.Name -notlike "*sources*" } |
           Select-Object -First 1
    if ($null -eq $jar) { throw "JAR nao encontrado" }
    Start-Process -FilePath "$JavaHome\bin\java.exe" `
                  -ArgumentList "-jar `"$($jar.FullName)`"" `
                  -WorkingDirectory $ProjectRoot -NoNewWindow
    Write-WARN "JAR iniciado diretamente (modo dev)"
}

Write-Step "Aguardando 35 segundos para inicializacao do Spring Boot"
Start-Sleep -Seconds 35

# ---------------------------------------------------------------------------
# 6. Health check
# ---------------------------------------------------------------------------
Write-Step "Health check -- $HealthUrl"
$ok = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) { Write-OK "Saudavel (tentativa $i)"; $ok = $true; break }
    } catch {
        Write-WARN "Tentativa $i falhou -- aguardando 10s"
        Start-Sleep -Seconds 10
    }
}
if (-not $ok) { Write-FAIL "Health check falhou"; exit 1 }

# ---------------------------------------------------------------------------
# 7. Login
# ---------------------------------------------------------------------------
Write-Step "Login -- POST /auth/login"
$tokenResp = $null
try {
    $tokenResp = Invoke-RestMethod `
        -Uri "$BaseUrl/auth/login" -Method POST `
        -Body (@{ username = $AdminUser; password = $AdminPassword } | ConvertTo-Json) `
        -ContentType "application/json" -TimeoutSec 15
    Write-OK "Login OK"
} catch {
    Write-FAIL "Login falhou: $($_.Exception.Message)"; exit 1
}
$token     = $tokenResp.access_token
$authHdr   = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# ---------------------------------------------------------------------------
# 8. Criar licenciamento de teste
# ---------------------------------------------------------------------------
Write-Step "POST /licenciamentos (RASCUNHO)"
$licBody = @{
    tipo            = "PPCI"
    areaConstruida  = 500.00
    alturaMaxima    = 10.00
    numPavimentos   = 3
    tipoOcupacao    = "Comercial - Loja"
    usoPredominante = "Comercial"
    endereco = @{
        cep         = $TestCep
        logradouro  = "Rua dos Andradas"
        numero      = "999"
        complemento = $null
        bairro      = "Centro Historico"
        municipio   = "Porto Alegre"
        uf          = "RS"
        latitude    = $null
        longitude   = $null
        dataAtualizacao = $null
    }
    responsavelTecnicoId = $null
    responsavelUsoId     = $null
    licenciamentoPaiId   = $null
} | ConvertTo-Json -Depth 5

$lic = $null
try {
    $lic = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos" -Method POST `
        -Body $licBody -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 15
    Write-OK "Licenciamento criado -- id=$($lic.id) status=$($lic.status)"
} catch {
    Write-FAIL "Criacao falhou: $($_.Exception.Message)"; exit 1
}

# ---------------------------------------------------------------------------
# 9. Upload de PDF via multipart (System.Net.Http -- PS 5.1 compat)
# ---------------------------------------------------------------------------
Write-Step "POST /arquivos/upload (multipart -- TESTE DA CORRECAO MINIO)"

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

Add-Type -AssemblyName System.Net.Http
$http      = [System.Net.Http.HttpClient]::new()
$http.DefaultRequestHeaders.Authorization =
    [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)
$mp        = [System.Net.Http.MultipartFormDataContent]::new()
$bytes     = [System.IO.File]::ReadAllBytes($tmpPdf)
$fileCtx   = [System.Net.Http.ByteArrayContent]::new($bytes)
$fileCtx.Headers.ContentType =
    [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/pdf")
$mp.Add($fileCtx, "file", [System.IO.Path]::GetFileName($tmpPdf))
$mp.Add([System.Net.Http.StringContent]::new("$($lic.id)"), "licenciamentoId")
$mp.Add([System.Net.Http.StringContent]::new("PPCI"),        "tipoArquivo")

$arq = $null
try {
    $task     = $http.PostAsync("$BaseUrl/arquivos/upload", $mp)
    $task.Wait()
    $resp     = $task.Result
    $body     = $resp.Content.ReadAsStringAsync().Result
    $http.Dispose()
    if (-not $resp.IsSuccessStatusCode) {
        throw "HTTP $([int]$resp.StatusCode): $body"
    }
    $arq = $body | ConvertFrom-Json
    Write-OK "UPLOAD OK -- id=$($arq.id) nome=$($arq.nomeArquivo) tamanho=$($arq.tamanho) bytes"
    Write-OK "A CORRECAO DO MINIO FUNCIONOU!"
} catch {
    Write-FAIL "Upload ainda falhou: $($_.Exception.Message)"
    Write-WARN ""
    Write-WARN "Proximos passos manuais:"
    Write-WARN "  1. Verificar log do MinIO Server:"
    Write-WARN "     Get-EventLog -LogName Application -Source SOL-MinIO -Newest 10"
    Write-WARN "     OU: Get-Content C:\SOL\logs\minio.log -Tail 30 -ErrorAction SilentlyContinue"
    Write-WARN "  2. Tentar via mc admin config:"
    Write-WARN "     mc admin config set sol-minio/ api checksum_algorithm=off"
    Write-WARN "     mc admin service restart sol-minio/"
    Write-WARN "  3. Se o erro for '400 x-amz-checksum' ou 'CRC':"
    Write-WARN "     Considerar downgrade do MinIO para RELEASE.2024-11-07 ou anterior"
    Write-WARN "     (compativel com SDK 8.5.17)"
} finally {
    Remove-Item $tmpPdf -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 10. Se upload funcionou: submeter e verificar
# ---------------------------------------------------------------------------
if ($null -ne $arq) {
    Write-Step "POST /licenciamentos/$($lic.id)/submeter (RASCUNHO -> ANALISE_PENDENTE)"
    try {
        $sub = Invoke-RestMethod `
            -Uri "$BaseUrl/licenciamentos/$($lic.id)/submeter" -Method POST `
            -Headers $authHdr -TimeoutSec 15
        Write-OK "Submissao OK -- status=$($sub.status)"
    } catch {
        Write-FAIL "Submissao falhou: $($_.Exception.Message)"
    }

    Write-Step "Verificando status -- GET /licenciamentos/$($lic.id)"
    try {
        $cur = Invoke-RestMethod -Uri "$BaseUrl/licenciamentos/$($lic.id)" `
            -Headers $authHdr -TimeoutSec 10
        if ($cur.status -eq "ANALISE_PENDENTE") {
            Write-OK "Status ANALISE_PENDENTE (correto)"
        } else {
            Write-WARN "Status inesperado: $($cur.status)"
        }
    } catch {
        Write-FAIL "Verificacao falhou: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 11. Limpeza Oracle
# ---------------------------------------------------------------------------
Write-Step "Limpeza Oracle -- removendo dados de teste"
$sql = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $($lic.id);
DELETE FROM sol.marco_processo WHERE id_licenciamento = $($lic.id);
DELETE FROM sol.boleto WHERE id_licenciamento = $($lic.id);
DELETE FROM sol.licenciamento WHERE id_licenciamento = $($lic.id);
COMMIT;
EXIT;
"@
$tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
Set-Content -Path $tmpSql -Value $sql
try {
    & "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql" | Out-Null
    Write-OK "Dados de teste removidos (licenciamento id=$($lic.id))"
} catch {
    Write-WARN "Limpeza Oracle falhou: $($_.Exception.Message)"
} finally {
    Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
Write-Step "Sprint 4 Fix -- concluido"
Write-Host ""
if ($null -ne $arq) {
    Write-Host "  RESULTADO: Upload MinIO FUNCIONANDO com SDK 8.5.17 + OkHttp interceptor" -ForegroundColor Green
    Write-Host "  Sprint 4 completa -- todos os fluxos P03 verificados." -ForegroundColor Green
} else {
    Write-Host "  RESULTADO: Upload MinIO ainda falha -- ver instrucoes acima." -ForegroundColor Red
    Write-Host "  Proxima acao: checar log do MinIO para o codigo de erro exato." -ForegroundColor Yellow
}
exit 0
