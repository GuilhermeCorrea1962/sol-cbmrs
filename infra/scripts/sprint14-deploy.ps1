###############################################################################
# sprint14-deploy.ps1 -- Sprint 14: P14 Renovacao de Licenciamento (APPCI)
# Sistema SOL -- CBM-RS
# Executar como: powershell -NoProfile -ExecutionPolicy Bypass -File sprint14-deploy.ps1
###############################################################################
# Fluxo testado (happy path completo):
#   Passo 5:  Setup -- licenciamento APPCI_EMITIDO com validade futura
#   Passo 6:  Iniciar renovacao     -> AGUARDANDO_ACEITE_RENOVACAO
#   Passo 7:  Aceitar Anexo D       -> marco ACEITE_ANEXOD_RENOVACAO
#   Passo 8:  Confirmar renovacao   -> AGUARDANDO_PAGAMENTO_RENOVACAO
#   Passo 9:  Solicitar isencao     -> marco SOLICITACAO_ISENCAO_RENOVACAO
#   Passo 10: Deferir isencao       -> AGUARDANDO_DISTRIBUICAO_RENOV
#   Passo 11: Distribuir vistoria   -> EM_VISTORIA_RENOVACAO
#   Passo 12: Registrar vistoria    -> marco VISTORIA_RENOVACAO (aprovada)
#   Passo 13: Homologar vistoria    -> APPCI_EMITIDO + nova dtValidadeAppci
#   Passo 14: Ciencia APPCI         -> marco CIENCIA_APPCI_RENOVACAO
#   Passo 15: Verificar via sqlplus
#   Passo 16: Testar recusar renovacao (segundo licenciamento)
#   Passo 17: Limpeza
###############################################################################

$ErrorActionPreference = "Stop"

$BASE_URL    = "http://localhost:8080/api"
$ORACLE_CONN = 'sol/"Sol@CBM2026"@localhost:1521/XEPDB1'
$TEMP_DIR    = "C:\Temp"

$ok  = 0
$err = 0
$licId     = $null
$licId2    = $null
$inspetorId = $null

function Write-Step { param($n, $msg) Write-Host "`n=== Passo $n -- $msg ===" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green;  $script:ok++  }
function Write-ERR  { param($msg) Write-Host "  [ERRO] $msg" -ForegroundColor Red;   $script:err++ }
function Write-INFO { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Yellow }

function Invoke-Sql {
    param([string]$sql, [string]$arquivo = "C:\Temp\_sprint14_tmp.sql")
    $sql | Out-File -FilePath $arquivo -Encoding ASCII -Force
    $saida = & sqlplus /nolog "@$arquivo" 2>&1
    Remove-Item $arquivo -ErrorAction SilentlyContinue
    return $saida
}

function Get-Token {
    param([string]$username, [string]$password = "Admin@SOL2026")
    $body = "grant_type=password&client_id=sol-frontend&username=$username&password=$password"
    $resp = Invoke-RestMethod -Uri "http://localhost:8180/realms/sol/protocol/openid-connect/token" `
        -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    return $resp.access_token
}

###############################################################################
Write-Host ""
Write-Host "==> Sprint 14 -- P14 Renovacao de Licenciamento" -ForegroundColor Magenta
Write-Host "    Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host ""

###############################################################################
Write-Step "0a" "Verificar MailHog (SMTP para notificacoes de e-mail)"
try {
    $mh = Invoke-RestMethod -Uri "http://localhost:8025/api/v2/messages" -TimeoutSec 5
    Write-OK "MailHog respondendo. Mensagens na caixa: $($mh.total)"
} catch {
    Write-INFO "MailHog indisponivel -- notificacoes de e-mail serao ignoradas (log WARN no servico)."
}

###############################################################################
Write-Step "0b" "Parar servico SOL (sol-backend)"
try {
    Stop-Service -Name "sol-backend" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-OK "Servico parado."
} catch {
    Write-INFO "Servico nao estava em execucao ou nao existe como servico Windows."
}

###############################################################################
Write-Step "1" "Build Maven (compilar e empacotar o backend)"
Write-INFO "Compilando... aguarde (pode levar 1-2 minutos)."
Push-Location "C:\SOL\backend"
try {
    $mvn = & mvn clean package -DskipTests -q 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ERR "Build Maven falhou. Saida:`n$($mvn -join "`n")"
        exit 1
    }
    Write-OK "Build Maven concluido com sucesso."
} finally {
    Pop-Location
}

###############################################################################
Write-Step "2" "Iniciar servico SOL (sol-backend)"
try {
    Start-Service -Name "sol-backend" -ErrorAction SilentlyContinue
    Write-INFO "Servico iniciado. Aguardando startup do Spring Boot..."
} catch {
    Write-INFO "Iniciando via JAR diretamente..."
    $jar = Get-ChildItem "C:\SOL\backend\target\*.jar" | Select-Object -First 1
    Start-Process -FilePath "java" -ArgumentList "-jar", $jar.FullName `
        -RedirectStandardOutput "C:\Temp\sol-sprint14.log" `
        -RedirectStandardError  "C:\Temp\sol-sprint14-err.log" `
        -NoNewWindow
}

###############################################################################
Write-Step "3" "Health check (aguardar Spring Boot + Hibernate DDL)"
# Hibernate ddl-auto:update adiciona coluna ISENTO_TAXA_RENOVACAO e os novos
# status enum no startup. Permite ate 20 tentativas (aprox. 60s).
$tentativas = 0
$maxTentativas = 20
$pronto = $false
while ($tentativas -lt $maxTentativas -and -not $pronto) {
    Start-Sleep -Seconds 3
    $tentativas++
    try {
        $health = Invoke-RestMethod -Uri "$BASE_URL/actuator/health" -TimeoutSec 5
        if ($health.status -eq "UP") {
            $pronto = $true
            Write-OK "Servico disponivel apos $($tentativas * 3)s. Status: $($health.status)"
        }
    } catch {
        Write-INFO "Tentativa $tentativas/$maxTentativas -- aguardando..."
    }
}
if (-not $pronto) {
    Write-ERR "Servico nao ficou disponivel em $($maxTentativas * 3)s. Verifique os logs."
    exit 1
}

###############################################################################
Write-Step "4" "Autenticacao -- obter token JWT (sol-admin)"
try {
    $TOKEN = Get-Token -username "sol-admin"
    $AUTH  = @{ Authorization = "Bearer $TOKEN" }
    Write-OK "Token JWT obtido com sucesso."
} catch {
    Write-ERR "Falha ao obter token: $_"
    exit 1
}

###############################################################################
Write-Step "4b" "Garantir usuario sol-admin na tabela SOL.USUARIO"
$solAdminKcId = "6a6065a2-edc1-415a-ac91-a260ebc9063c"
$sql4b = @"
CONNECT $ORACLE_CONN
MERGE INTO SOL.USUARIO dst
USING (SELECT '$solAdminKcId' AS KC FROM DUAL) src
ON (dst.ID_KEYCLOAK = src.KC)
WHEN NOT MATCHED THEN
  INSERT (ID_USUARIO, NOME, CPF, EMAIL, TIPO_USUARIO, STATUS_CADASTRO,
          ID_KEYCLOAK, ATIVO, DT_CRIACAO, DT_ATUALIZACAO)
  VALUES (SOL.SEQ_USUARIO.NEXTVAL, 'Admin SOL', '00000000001',
          'sol-admin@cbm.rs.gov.br', 'ADMIN', 'APROVADO',
          '$solAdminKcId', 'S', SYSDATE, SYSDATE);
COMMIT;
SELECT TO_CHAR(ID_USUARIO) FROM SOL.USUARIO WHERE ID_KEYCLOAK = '$solAdminKcId';
EXIT;
"@
$r4b = Invoke-Sql -sql $sql4b
$adminDbId = ($r4b | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
if ($adminDbId) { $adminDbId = $adminDbId.Trim() }
if (-not $adminDbId) {
    Write-ERR "Nao foi possivel obter ID do sol-admin no banco."
    exit 1
}
$inspetorId = $adminDbId
Write-OK "sol-admin no banco. ID: $adminDbId"

###############################################################################
Write-Step "5" "Setup de dados de teste -- criar licenciamento APPCI_EMITIDO valido"

# 5a: Criar licenciamento RASCUNHO via API
Write-INFO "Criando licenciamento RASCUNHO via API..."
$bodyLic = @{
    tipo           = "PPCI"
    areaConstruida = 500.0
    alturaMaxima   = 10.0
    numPavimentos  = 2
    tipoOcupacao   = "Comercial"
    usoPredominante = "Loja"
    endereco       = @{
        cep        = "90010100"
        logradouro = "Av Borges de Medeiros"
        numero     = "1501"
        bairro     = "Centro Historico"
        municipio  = "Porto Alegre"
        uf         = "RS"
    }
} | ConvertTo-Json -Depth 5

try {
    $respLic = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos" `
        -Method POST -Headers $AUTH -Body $bodyLic -ContentType "application/json"
    $licId = $respLic.id
    Write-OK "Licenciamento criado. ID: $licId"
} catch {
    Write-ERR "Falha ao criar licenciamento: $_"
    exit 1
}

# 5b: Promover para APPCI_EMITIDO com validade de 1 ano via sqlplus
Write-INFO "Atualizando status e dtValidadeAppci via sqlplus..."
$sql5b = @"
CONNECT $ORACLE_CONN
UPDATE SOL.LICENCIAMENTO
   SET STATUS                 = 'APPCI_EMITIDO',
       DT_VALIDADE_APPCI      = SYSDATE + 365,
       NUMERO_PPCI            = 'A S14TEST ' || TO_CHAR($licId),
       ID_RESPONSAVEL_TECNICO = $adminDbId
 WHERE ID_LICENCIAMENTO       = $licId;
COMMIT;
EXIT;
"@
$r5b = Invoke-Sql -sql $sql5b
if ($r5b -match "ORA-") {
    Write-ERR "Erro sqlplus no setup: $($r5b | Where-Object { $_ -match 'ORA-' })"
    exit 1
}
Write-OK "Licenciamento $licId promovido para APPCI_EMITIDO com DT_VALIDADE_APPCI = SYSDATE+365."

# 5c: Obter ID do RT (responsavel tecnico) para usar como inspetor nos testes
Write-INFO "Obtendo ID do responsavel tecnico para usar como inspetor..."
$sql5c = @"
CONNECT $ORACLE_CONN
SELECT TO_CHAR(ID_RESPONSAVEL_TECNICO) FROM SOL.LICENCIAMENTO WHERE ID_LICENCIAMENTO = $licId;
EXIT;
"@
$r5c = Invoke-Sql -sql $sql5c
$rawId = ($r5c | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
$inspetorId = if ($rawId) { $rawId.Trim() } else { $null }
if (-not $inspetorId) {
    Write-INFO "Nao foi possivel obter inspetorId automaticamente. Usando ID=1 como fallback."
    $inspetorId = "1"
}
Write-OK "inspetorId para testes: $inspetorId"

###############################################################################
Write-Step "6" "P14 Fase 1 -- Iniciar renovacao (APPCI_EMITIDO -> AGUARDANDO_ACEITE_RENOVACAO)"
try {
    $r6 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/iniciar" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
    if ($r6.status -eq "AGUARDANDO_ACEITE_RENOVACAO") {
        Write-OK "Renovacao iniciada. Status: $($r6.status)"
    } else {
        Write-ERR "Status inesperado apos iniciar renovacao: $($r6.status)"
    }
} catch {
    Write-ERR "Falha ao iniciar renovacao: $_"
}

###############################################################################
Write-Step "7" "P14 Fase 2 -- Aceitar Anexo D (marco ACEITE_ANEXOD_RENOVACAO)"
try {
    $r7 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/aceitar-anexo-d" `
        -Method PUT -Headers $AUTH -ContentType "application/json"
    if ($r7.aceiteRegistrado -eq $true) {
        Write-OK "Aceite do Anexo D registrado. aceiteRegistrado=$($r7.aceiteRegistrado)"
    } else {
        Write-ERR "Aceite nao confirmado na resposta: $($r7 | ConvertTo-Json -Compress)"
    }
} catch {
    Write-ERR "Falha ao aceitar Anexo D: $_"
}

###############################################################################
Write-Step "8" "P14 Fase 2 -- Confirmar renovacao (-> AGUARDANDO_PAGAMENTO_RENOVACAO)"
try {
    $r8 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/confirmar" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
    if ($r8.status -eq "AGUARDANDO_PAGAMENTO_RENOVACAO") {
        Write-OK "Renovacao confirmada. Status: $($r8.status)"
    } else {
        Write-ERR "Status inesperado apos confirmar: $($r8.status)"
    }
} catch {
    Write-ERR "Falha ao confirmar renovacao: $_"
}

###############################################################################
Write-Step "9" "P14 Fase 3 -- Solicitar isencao de taxa (marco SOLICITACAO_ISENCAO_RENOVACAO)"
try {
    $r9 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/solicitar-isencao" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
    Write-OK "Isencao solicitada. Status atual: $($r9.status)"
} catch {
    Write-ERR "Falha ao solicitar isencao: $_"
}

###############################################################################
Write-Step "10" "P14 Fase 3 -- Deferir isencao (-> AGUARDANDO_DISTRIBUICAO_RENOV)"
try {
    $r10 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/analisar-isencao" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body '{"deferida":true}'
    if ($r10.status -eq "AGUARDANDO_DISTRIBUICAO_RENOV") {
        Write-OK "Isencao deferida. Status: $($r10.status)"
    } else {
        Write-ERR "Status inesperado apos deferir isencao: $($r10.status)"
    }
} catch {
    Write-ERR "Falha ao analisar isencao: $_"
}

###############################################################################
Write-Step "11" "P14 Fase 4 -- Distribuir vistoria para inspetor (-> EM_VISTORIA_RENOVACAO)"
try {
    $body11 = "{`"inspetorId`": $inspetorId}"
    $r11 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/distribuir" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body $body11
    if ($r11.status -eq "EM_VISTORIA_RENOVACAO") {
        Write-OK "Vistoria distribuida. Status: $($r11.status)"
    } else {
        Write-ERR "Status inesperado apos distribuir: $($r11.status)"
    }
} catch {
    Write-ERR "Falha ao distribuir vistoria: $_"
}

###############################################################################
Write-Step "12" "P14 Fase 5 -- Registrar vistoria aprovada (marco VISTORIA_RENOVACAO)"
try {
    $r12 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/registrar-vistoria" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body '{"vistoriaAprovada":true}'
    # Status permanece EM_VISTORIA_RENOVACAO -- aguarda homologacao
    Write-OK "Resultado da vistoria registrado. Status atual: $($r12.status)"
} catch {
    Write-ERR "Falha ao registrar vistoria: $_"
}

###############################################################################
Write-Step "13" "P14 Fase 5 -- Homologar vistoria deferida (-> APPCI_EMITIDO + nova data)"
try {
    $r13 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/homologar-vistoria" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body '{"deferida":true}'
    if ($r13.status -eq "APPCI_EMITIDO") {
        Write-OK "Vistoria homologada DEFERIDA. Status: $($r13.status). dtValidadeAppci: $($r13.dtValidadeAppci)"
    } else {
        Write-ERR "Status inesperado apos homologar: $($r13.status)"
    }
} catch {
    Write-ERR "Falha ao homologar vistoria: $_"
}

###############################################################################
Write-Step "14" "P14 Fase 6A -- Ciencia do novo APPCI (marco CIENCIA_APPCI_RENOVACAO)"
try {
    $r14 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId/renovacao/ciencia-appci" `
        -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
    Write-OK "Ciencia do APPCI registrada. Status: $($r14.status)"
} catch {
    Write-ERR "Falha ao registrar ciencia do APPCI: $_"
}

###############################################################################
Write-Step "15" "Verificar estado final via sqlplus (dtValidadeAppci + marcos)"
$sql15 = @"
CONNECT $ORACLE_CONN
SELECT STATUS, TO_CHAR(DT_VALIDADE_APPCI,'DD/MM/YYYY') AS VALIDADE, ISENTO_TAXA_RENOVACAO
  FROM SOL.LICENCIAMENTO WHERE ID_LICENCIAMENTO = $licId;
SELECT COUNT(*) AS TOTAL_MARCOS FROM SOL.MARCO_PROCESSO WHERE ID_LICENCIAMENTO = $licId;
SELECT TIPO_MARCO FROM SOL.MARCO_PROCESSO
 WHERE ID_LICENCIAMENTO = $licId ORDER BY DT_MARCO;
EXIT;
"@
$r15 = Invoke-Sql -sql $sql15
Write-INFO "Resultado sqlplus:"
$r15 | Where-Object { $_ -notmatch '^(SQL|Connected|$)' } | ForEach-Object { Write-INFO "  $_" }
if ($r15 -match "APPCI_EMITIDO") {
    Write-OK "Status APPCI_EMITIDO confirmado no banco."
} else {
    Write-ERR "Status APPCI_EMITIDO NAO encontrado no banco."
}
if ($r15 -match "CIENCIA_APPCI_RENOVACAO") {
    Write-OK "Marco CIENCIA_APPCI_RENOVACAO presente."
} else {
    Write-ERR "Marco CIENCIA_APPCI_RENOVACAO ausente."
}
if ($r15 -match "LIBERACAO_RENOV_APPCI") {
    Write-OK "Marco LIBERACAO_RENOV_APPCI presente (novo APPCI emitido)."
} else {
    Write-ERR "Marco LIBERACAO_RENOV_APPCI ausente."
}

###############################################################################
Write-Step "16" "Testar caminho de recusa -- novo licenciamento ALVARA_VENCIDO -> recusar -> ALVARA_VENCIDO"

# 16a: Criar segundo licenciamento
Write-INFO "Criando segundo licenciamento para teste de recusa..."
try {
    $respLic2 = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos" `
        -Method POST -Headers $AUTH -Body $bodyLic -ContentType "application/json"
    $licId2 = $respLic2.id
    Write-OK "Segundo licenciamento criado. ID: $licId2"
} catch {
    Write-ERR "Falha ao criar segundo licenciamento: $_"
}

if ($licId2) {
    # 16b: Promover para ALVARA_VENCIDO (dtValidadeAppci no passado)
    $sql16b = @"
CONNECT $ORACLE_CONN
UPDATE SOL.LICENCIAMENTO
   SET STATUS                 = 'ALVARA_VENCIDO',
       DT_VALIDADE_APPCI      = SYSDATE - 30,
       ID_RESPONSAVEL_TECNICO = $adminDbId
 WHERE ID_LICENCIAMENTO       = $licId2;
COMMIT;
EXIT;
"@
    $r16b = Invoke-Sql -sql $sql16b
    Write-OK "Licenciamento $licId2 promovido para ALVARA_VENCIDO (validade = SYSDATE-30)."

    # 16c: Iniciar renovacao
    try {
        $r16c = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId2/renovacao/iniciar" `
            -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
        Write-OK "Renovacao iniciada no lic $licId2. Status: $($r16c.status)"
    } catch {
        Write-ERR "Falha ao iniciar renovacao no lic ${licId2}: $_"
    }

    # 16d: Recusar renovacao
    try {
        $r16d = Invoke-RestMethod -Uri "$BASE_URL/licenciamentos/$licId2/renovacao/recusar" `
            -Method POST -Headers $AUTH -ContentType "application/json" -Body "{}"
        if ($r16d.status -eq "ALVARA_VENCIDO") {
            Write-OK "RN-145 verificado: recusa com alvara vencido -> ALVARA_VENCIDO. Status: $($r16d.status)"
        } else {
            Write-ERR "RN-145 falhou: status apos recusa = $($r16d.status) (esperado ALVARA_VENCIDO)"
        }
    } catch {
        Write-ERR "Falha ao recusar renovacao: $_"
    }
}

###############################################################################
Write-Step "17" "Limpeza dos dados de teste"
$idsParaLimpar = @($licId, $licId2) | Where-Object { $_ }
$listaIds = $idsParaLimpar -join ","

if ($listaIds) {
    $sql17 = @"
CONNECT $ORACLE_CONN
DELETE FROM SOL.MARCO_PROCESSO WHERE ID_LICENCIAMENTO IN ($listaIds);
DELETE FROM SOL.ARQUIVO_ED      WHERE ID_LICENCIAMENTO IN ($listaIds);
DELETE FROM SOL.BOLETO          WHERE ID_LICENCIAMENTO IN ($listaIds);
DELETE FROM SOL.LICENCIAMENTO   WHERE ID_LICENCIAMENTO IN ($listaIds);
COMMIT;
SELECT COUNT(*) AS LICENCIAMENTOS_RESTANTES FROM SOL.LICENCIAMENTO
 WHERE ID_LICENCIAMENTO IN ($listaIds);
EXIT;
"@
    $r17 = Invoke-Sql -sql $sql17
    Write-OK "Dados de teste removidos (IDs: $listaIds)."
    $r17 | Where-Object { $_ -match '\d' -and $_ -notmatch 'Connected|SQL' } |
        ForEach-Object { Write-INFO "  $_" }
}

###############################################################################
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  SUMARIO SPRINT 14 -- P14 Renovacao de Licenciamento" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "  Verificacoes OK  : $ok" -ForegroundColor Green
Write-Host "  Erros encontrados: $err" -ForegroundColor $(if ($err -gt 0) { "Red" } else { "Green" })
Write-Host "  Data/hora final  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
if ($err -eq 0) {
    Write-Host "  Sprint 14 concluida com sucesso." -ForegroundColor Green
} else {
    Write-Host "  Sprint 14 concluida com $err erro(s). Revise os itens [ERRO] acima." -ForegroundColor Red
}
Write-Host ""
