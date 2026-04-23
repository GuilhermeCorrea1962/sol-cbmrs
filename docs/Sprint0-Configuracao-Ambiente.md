# Sprint 0 — Configuração do Ambiente SOL CBM-RS

> **Data:** 2026-03-26
> **Objetivo:** Instalar e configurar toda a infraestrutura necessária para o sistema SOL (Sistema Online de Licenciamento) do CBM-RS em modo autônomo Windows, sem Docker.
> **Resultado final:** ✅ 23/23 checks PASS — Ambiente totalmente operacional.

---

## Sumário

- [[#Contexto]]
- [[#Pré-condição — Oracle XE já configurado]]
- [[#Problemas Estruturais Identificados]]
- [[#Script 02 — Keycloak]]
- [[#Script 03 — MinIO]]
- [[#Script 04 — Nginx]]
- [[#Script 05 — SOL Backend]]
- [[#Script 06 — Keycloak Realm SOL]]
- [[#Script 07 — MinIO Buckets]]
- [[#Script 08 — Verificação Final]]
- [[#Resultado Final]]
- [[#Referência de Credenciais e Portas]]

---

## Contexto

O projeto SOL é executado como um sistema autônomo em Windows Server, instalando cada componente como serviço Windows via **NSSM** (Non-Sucking Service Manager). Os scripts de instalação estão em `C:\SOL\infra\scripts\` e seguem a sequência numerada de `00` a `08`.

O Oracle XE já havia sido configurado com sucesso (tablespace `SOL_DATA` e usuário `sol` criados) em uma sessão anterior. A tarefa desta sessão foi executar os scripts `02` até `08`.

**Estrutura de diretórios relevante:**

```
C:\SOL\
├── infra\
│   ├── scripts\        ← Scripts PowerShell de instalação
│   ├── keycloak\       ← Binários e configuração do Keycloak
│   ├── minio\          ← Binário do MinIO e mc.exe
│   └── nginx\          ← Binários do Nginx
├── backend\            ← Código-fonte Spring Boot
├── frontend\           ← Código-fonte Angular
├── data\               ← Dados persistentes (Oracle, MinIO, Keycloak)
├── logs\               ← Logs de todos os serviços
└── instaladores\       ← ZIPs baixados (cache)
```

---

## Pré-condição — Oracle XE já configurado

Antes de iniciar esta sessão, o estado do ambiente era:

| Serviço | Status |
|---------|--------|
| OracleServiceXE | ✅ Running |
| SOL-Keycloak | ❌ Não instalado |
| SOL-MinIO | ❌ Não instalado |
| SOL-Nginx | ❌ Não instalado |
| SOL-Backend | ❌ Não instalado |

Nenhum arquivo havia sido baixado ainda (Keycloak ZIP, MinIO exe, Nginx ZIP).

---

## Problemas Estruturais Identificados

Antes de detalhar cada script, é importante registrar dois problemas transversais descobertos durante a execução:

### Problema 1 — Encoding dos scripts .ps1

Vários scripts originais (`02`, `05`, `06`, `07`, `08`) apresentavam erro de parsing no PowerShell:

```
A cadeia de caracteres não tem o terminador: "
```

Isso ocorre porque os arquivos foram gravados com um encoding ou caractere especial (provavelmente UTF-8 com BOM corrompido, ou caracteres Unicode nos comentários) que o parser do PowerShell não consegue interpretar ao ser invocado via `-File`. A solução adotada foi criar versões corrigidas (`-fix.ps1`) com o conteúdo reescrito pelo Claude diretamente com o tool `Write`, garantindo encoding correto.

### Problema 2 — Java 25 incompatível com a stack

A máquina possui **Java 25.0.1** como padrão no PATH, mas toda a stack exige Java 21 LTS:

| Componente | Versão Java mínima | Java 25 funciona? | Motivo da falha |
|------------|-------------------|-------------------|-----------------|
| Keycloak 24 (`kc build`) | Java 17+ | ❌ | Byte Buddy não suporta class file version 69 (Java 25) |
| Spring Boot + MapStruct | Java 17–21 | ❌ | `javac.code.TypeTag::UNKNOWN` — API interna removida |
| Keycloak 24 (runtime) | Java 17+ | ⚠️ Parcial | `Subject.getSubject()` não suportado sem flag extra |

**Solução:** Instalação do Java 21 Temurin via Chocolatey e configuração do `JAVA_HOME` permanente.

---

## Script 02 — Keycloak

### O que faz

- Baixa `keycloak-24.0.3.zip` do GitHub (~100 MB)
- Extrai em `C:\SOL\infra\keycloak\keycloak-24.0.3\`
- Gera `keycloak.conf` (banco H2 embarcado, porta 8180, sem HTTPS)
- Executa `kc.bat build` para pré-compilar o servidor
- Registra como serviço Windows `SOL-Keycloak` via NSSM
- Inicia o serviço

### Execução e problemas

**Tentativa 1** — Executada com `java -version` = Java 25:

```
ERROR: Java 25 (69) is not supported by the current version of Byte Buddy
which officially supports Java 22 (66) - update Byte Buddy or set
net.bytebuddy.experimental as a VM property
```

O `kc build` falhou, mas o script continuou e registrou o serviço mesmo assim (o script trata o erro como WARN). O serviço foi iniciado mas o Keycloak não funcionaria corretamente sem o build.

**Correção aplicada:**

```powershell
# Parar o serviço
Stop-Service SOL-Keycloak

# Adicionar flag ao ambiente NSSM do serviço
nssm set SOL-Keycloak AppEnvironmentExtra `
    "KEYCLOAK_ADMIN=admin" `
    "KEYCLOAK_ADMIN_PASSWORD=Keycloak@Admin2026" `
    "JAVA_TOOL_OPTIONS=-Dnet.bytebuddy.experimental=true"

# Rodar o build com a flag ativa
$env:JAVA_TOOL_OPTIONS = "-Dnet.bytebuddy.experimental=true"
& "C:\SOL\infra\keycloak\keycloak-24.0.3\bin\kc.bat" build
# → Build ExitCode: 0 ✅

# Reiniciar o serviço
Start-Service SOL-Keycloak
```

A flag `net.bytebuddy.experimental=true` instrui o Byte Buddy a operar em modo experimental, aceitando versões de class file acima da 66 (Java 22).

### Resultado

```
✅ SOL-Keycloak instalado e em execução
   Porta: 8180
   Admin: http://localhost:8180
   Credenciais: admin / Keycloak@Admin2026
```

---

## Script 03 — MinIO

### O que faz

- Baixa `minio.exe` (~100 MB) de `dl.min.io`
- Configura variáveis de ambiente `MINIO_ROOT_USER` e `MINIO_ROOT_PASSWORD`
- Registra como serviço Windows `SOL-MinIO` via NSSM
- Inicia o serviço nas portas 9000 (API S3) e 9001 (Console Web)

### Execução

O script original tem problema de encoding, mas foi executado com sucesso via `-File` nesta máquina (o erro de encoding ocorreu nos scripts maiores). O MinIO foi baixado e instalado sem problemas.

> ℹ️ O download do MinIO (~100 MB) foi executado em background em paralelo com o script 04-nginx.

### Resultado

```
✅ SOL-MinIO instalado e em execução
   API:     http://localhost:9000
   Console: http://localhost:9001
   Usuário: solminio / MinIO@SOL2026
   Dados:   C:\SOL\data\minio\
```

---

## Script 04 — Nginx

### O que faz

- Baixa `nginx-1.26.2.zip` (~1 MB) do nginx.org
- Gera `nginx.conf` com:
  - Porta 80 servindo frontend Angular (arquivos estáticos)
  - `/api/` em proxy para Spring Boot na porta 8080
  - `/auth/` em proxy para Keycloak na porta 8180
  - Headers de segurança (`X-Frame-Options`, `X-Content-Type-Options`)
  - Limite de upload 50 MB (para plantas e documentos técnicos)
- Registra como serviço Windows `SOL-Nginx` via NSSM

### Execução

Executado com sucesso sem problemas. O serviço iniciou e o Nginx ficou em estado `Running`.

**Problema identificado posteriormente:** O diretório do frontend (`C:\SOL\frontend\dist\sol-frontend\browser\`) não existia — o Angular ainda não havia sido compilado. Isso causava um erro 500 (Internal Server Error) na porta 80 por um loop de reescrita:

```
[error] rewrite or internal redirection cycle while internally redirecting to "/index.html"
```

**Correção:**

```powershell
# Criar diretório e placeholder do frontend
New-Item -ItemType Directory -Path "C:\SOL\frontend\dist\sol-frontend\browser" -Force
Set-Content -Path "C:\SOL\frontend\dist\sol-frontend\browser\index.html" -Value @"
<!DOCTYPE html>
<html>
<head><title>SOL CBM-RS</title></head>
<body>
  <h1>SOL - Sistema Online de Licenciamento</h1>
  <p>Frontend em construção. Backend disponível em /api/</p>
</body>
</html>
"@

# Reiniciar Nginx para carregar o arquivo
Stop-Service SOL-Nginx
Start-Service SOL-Nginx
# → HTTP 200 ✅
```

### Resultado

```
✅ SOL-Nginx instalado e em execução
   Porta: 80
   Frontend:    http://localhost/
   Backend API: http://localhost/api/
   Keycloak:    http://localhost/auth/
```

---

## Script 05 — SOL Backend

### O que faz

- Localiza o JAVA_HOME e o JAR compilado do Spring Boot
- Registra como serviço Windows `SOL-Backend` via NSSM
- Inicia com parâmetros: `-Xms256m -Xmx1g -Dspring.profiles.active=prod -Dserver.port=8080`
- Verifica o health endpoint após inicialização

### Pré-requisito: compilar o backend

O JAR `C:\SOL\backend\target\sol-backend-1.0.0.jar` não existia. Era necessário compilar com Maven:

**Tentativa 1** — com Java 25 no PATH:

```
[ERROR] Fatal error compiling: java.lang.ExceptionInInitializerError:
com.sun.tools.javac.code.TypeTag :: UNKNOWN
```

O processador de anotações **MapStruct** (usado para geração de código DTO↔Entity) utiliza APIs internas do compilador `javac` que foram alteradas no Java 23+. O resultado é uma falha fatal de inicialização do compilador.

**Solução — Instalar Java 21:**

```powershell
choco install temurin21 -y
# Instalado em: C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot

# Definir JAVA_HOME permanentemente na máquina
[System.Environment]::SetEnvironmentVariable(
    "JAVA_HOME",
    "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot",
    "Machine"
)
```

**Compilação com Java 21:**

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

cd C:\SOL\backend
mvn clean package -DskipTests
# → BUILD SUCCESS ✅
# → JAR: C:\SOL\backend\target\sol-backend-1.0.0.jar
```

**Registro e inicialização do serviço:**

O script original `05-sol-service.ps1` apresentava erro de encoding. Foi criado `05-sol-service-fix.ps1` com o mesmo comportamento:

```powershell
$java21 = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
$JavaExe = "$java21\bin\java.exe"
$params = "-Xms256m -Xmx1g -Dspring.profiles.active=prod -Dserver.port=8080 -jar C:\SOL\backend\target\sol-backend-1.0.0.jar"

nssm install SOL-Backend $JavaExe
nssm set SOL-Backend AppParameters $params
nssm set SOL-Backend AppDirectory "C:\SOL\backend"
nssm set SOL-Backend Start SERVICE_AUTO_START
# ... demais configurações de log e rotação

Start-Service SOL-Backend
```

### Verificação do health check

```json
{
  "version":  "1.0.0",
  "system":   "SOL CBM-RS Autônomo",
  "timestamp": "2026-03-26T17:49:13.264023800",
  "status":   "UP"
}
```

### Resultado

```
✅ SOL-Backend instalado e em execução
   Porta:   8080
   Health:  http://localhost:8080/api/health → UP
   Profile: prod
   JAR:     C:\SOL\backend\target\sol-backend-1.0.0.jar
```

---

## Script 06 — Keycloak Realm SOL

### O que faz

- Autentica no Keycloak Admin via REST API (realm `master`)
- Verifica se o realm `sol` já existe (e remove se existir, para reimportar)
- Importa o arquivo `C:\SOL\infra\keycloak\sol-realm.json`
- Verifica a criação do realm

### Problema: Keycloak ainda não estava totalmente pronto

O Keycloak levou mais tempo para inicializar após a segunda configuração (adição da flag `JAVA_OPTS_APPEND`). O script original (`06-keycloak-realm.ps1`) também tinha problema de encoding.

O script `06-keycloak-realm-fix.ps1` foi criado com lógica de retry (10 tentativas com intervalo de 10s) para aguardar o Keycloak ficar disponível antes de tentar importar o realm.

**Segundo problema de inicialização do Keycloak:**

Após reiniciar com a flag `JAVA_TOOL_OPTIONS`, o Keycloak apresentou um novo erro:

```
java.lang.UnsupportedOperationException: getSubject is not supported
    at javax.security.auth.Subject.getSubject(Subject.java:277)
    at org.infinispan.security.Security.getSubject(...)
```

**Causa:** O Infinispan (cache distribuído embutido no Keycloak) usa `Subject.getSubject(AccessControlContext)`, uma API que foi depreciada no Java 17 e, no Java 21, lança `UnsupportedOperationException` por padrão, pois requer que um SecurityManager esteja ativo.

**Correção:**

```powershell
nssm set SOL-Keycloak AppEnvironmentExtra `
    "KEYCLOAK_ADMIN=admin" `
    "KEYCLOAK_ADMIN_PASSWORD=Keycloak@Admin2026" `
    "JAVA_TOOL_OPTIONS=-Dnet.bytebuddy.experimental=true" `
    "JAVA_OPTS_APPEND=-Djava.security.manager=allow"
```

A propriedade `-Djava.security.manager=allow` reabilita o SecurityManager no Java 21 (ainda presente mas depreciado), permitindo que `Subject.getSubject()` funcione normalmente.

Após o restart com essa configuração, o Keycloak iniciou em ~8 segundos:

```
INFO [io.quarkus] Keycloak 24.0.3 on JVM (powered by Quarkus 3.8.3)
     started in 7.742s. Listening on: http://0.0.0.0:8180
INFO [org.keycloak.services] KC-SERVICES0009: Added user 'admin' to realm 'master'
```

### Realm importado

O arquivo `sol-realm.json` contém a definição completa do realm, incluindo:

- **Clients:** `sol-frontend` (Angular, público) e `sol-backend` (confidencial)
- **Roles:** `CIDADAO`, `RT`, `ANALISTA`, `INSPETOR`, `ADMIN`, `CHEFE_SSEG_BBM`
- Configurações de token, sessão e políticas de senha

### Resultado

```
✅ Realm 'sol' importado no Keycloak
   Login URL: http://localhost:8180/realms/sol/protocol/openid-connect/auth
   JWKS URL:  http://localhost:8180/realms/sol/protocol/openid-connect/certs
   Token URL: http://localhost:8180/realms/sol/protocol/openid-connect/token
```

---

## Script 07 — MinIO Buckets

### O que faz

- Baixa o cliente `mc.exe` (MinIO Client)
- Configura o alias `sol-minio` apontando para `http://localhost:9000`
- Cria os 6 buckets do sistema
- Configura usuário de aplicação `sol-app` com política de acesso restrita

### Buckets criados

| Bucket | Finalidade |
|--------|-----------|
| `sol-arquivos` | Documentos do processo (plantas, ART, memorial descritivo) |
| `sol-appci` | APPCIs emitidos em PDF |
| `sol-guias` | Guias de Recolhimento geradas |
| `sol-laudos` | Laudos técnicos de vistoria |
| `sol-decisoes` | Decisões de recurso em PDF |
| `sol-temp` | Uploads temporários |

### Usuário de aplicação

O usuário `sol-app` foi criado com uma política IAM que concede apenas as permissões necessárias (`GetObject`, `PutObject`, `DeleteObject`, `ListBucket`) nos 6 buckets, sem acesso administrativo ao MinIO.

```
sol-app / SolApp@Minio2026
```

Este é o usuário que o Spring Boot utiliza para armazenar e recuperar arquivos. As credenciais devem estar configuradas em `application.yml`:

```yaml
minio:
  url: http://localhost:9000
  access-key: sol-app
  secret-key: SolApp@Minio2026
```

### Resultado

```
✅ 6 buckets criados
✅ Usuário sol-app com política restrita configurado
```

---

## Script 08 — Verificação Final

### O que faz

Executa uma bateria de 23 verificações cobrindo:

1. Status dos serviços Windows (5 checks)
2. Endpoints HTTP respondendo (5 checks)
3. Oracle XE acessível na porta 1521 (2 checks)
4. Realm `sol` existente no Keycloak (1 check)
5. 6 buckets MinIO existentes (6 checks)
6. Ferramentas de desenvolvimento disponíveis (4 checks)

### Problema: script original com encoding corrompido

O `08-verify-all.ps1` original falhou ao ser executado. Foi criado `08-verify-fix.ps1`.

### Problema: falsos negativos no `Invoke-WebRequest`

A verificação original usava `Invoke-WebRequest` para testar os endpoints. Em respostas sem corpo (MinIO health, 200 OK sem body) ou com body binário (MinIO Console), o cmdlet lançava `NullReferenceException` mesmo com status 200.

**Solução:** Trocar para `System.Net.HttpWebRequest` (baixo nível), que não tenta interpretar o corpo da resposta:

```powershell
function Test-Http {
    param([string]$Url, [int[]]$OkCodes = @(200))
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = 10000
        $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        $code -in $OkCodes
    } catch [System.Net.WebException] {
        $code = [int]$_.Exception.Response.StatusCode
        $code -in $OkCodes
    } catch {
        $false
    }
}
```

### Resultado Final

```
========================================
 SOL Autonomo - Verificacao de Ambiente
========================================

--- Servicos Windows ---
  [PASS] Servico SOL-Keycloak rodando
  [PASS] Servico SOL-MinIO rodando
  [PASS] Servico SOL-Nginx rodando
  [PASS] Servico OracleServiceXE rodando
  [PASS] Servico SOL-Backend rodando

--- Endpoints HTTP ---
  [PASS] Keycloak respondendo (porta 8180)
  [PASS] MinIO API respondendo (porta 9000)
  [PASS] MinIO Console respondendo (porta 9001)
  [PASS] Nginx respondendo (porta 80)
  [PASS] SOL Backend health (porta 8080)

--- Banco de Dados Oracle ---
  [PASS] Oracle XE porta 1521 aberta
  [PASS] Arquivo de configuracao Oracle criado

--- Keycloak Realm SOL ---
  [PASS] Realm 'sol' existe no Keycloak

--- MinIO Buckets ---
  [PASS] Bucket 'sol-arquivos' existe
  [PASS] Bucket 'sol-appci' existe
  [PASS] Bucket 'sol-guias' existe
  [PASS] Bucket 'sol-laudos' existe
  [PASS] Bucket 'sol-decisoes' existe
  [PASS] Bucket 'sol-temp' existe

--- Ferramentas de Desenvolvimento ---
  [PASS] Java 21+ disponivel
  [PASS] Node.js disponivel
  [PASS] Maven disponivel
  [PASS] Angular CLI disponivel

========================================
 RESULTADO: 23/23 PASS -- AMBIENTE OK
========================================
```

---

## Resultado Final

| Componente | Versão | Porta | Serviço Windows | Status |
|-----------|--------|-------|----------------|--------|
| Oracle XE | 21c | 1521 | OracleServiceXE | ✅ Running |
| Keycloak | 24.0.3 | 8180 | SOL-Keycloak | ✅ Running |
| MinIO | 2025-09 | 9000/9001 | SOL-MinIO | ✅ Running |
| Nginx | 1.26.2 | 80 | SOL-Nginx | ✅ Running |
| Spring Boot | 3.3.4 | 8080 | SOL-Backend | ✅ Running |

---

## Referência de Credenciais e Portas

> ⚠️ Estas credenciais são para ambiente interno/desenvolvimento. Alterar antes de qualquer exposição externa.

### Keycloak

| Item | Valor |
|------|-------|
| URL Admin | http://localhost:8180 |
| Usuário admin | `admin` |
| Senha admin | `Keycloak@Admin2026` |
| Realm | `sol` |

### MinIO

| Item | Valor |
|------|-------|
| URL API | http://localhost:9000 |
| URL Console | http://localhost:9001 |
| Root user | `solminio` |
| Root password | `MinIO@SOL2026` |
| App user | `sol-app` |
| App password | `SolApp@Minio2026` |

### Oracle

| Item | Valor |
|------|-------|
| Host | localhost:1521 |
| Usuário | `sol` |
| Tablespace | `SOL_DATA` |

---

## Notas de Manutenção

### Reinicialização do servidor

Todos os serviços estão configurados com `Start = SERVICE_AUTO_START` no NSSM e iniciarão automaticamente com o Windows.

Após reinicialização, verificar com:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\SOL\infra\scripts\08-verify-fix.ps1"
```

> ⚠️ Usar o `08-verify-fix.ps1` (versão corrigida), **não** o `08-verify-all.ps1` original.

### Flags permanentes do Keycloak

O NSSM do serviço `SOL-Keycloak` está configurado com:

```
JAVA_TOOL_OPTIONS = -Dnet.bytebuddy.experimental=true
JAVA_OPTS_APPEND  = -Djava.security.manager=allow
```

Essas flags são necessárias enquanto o Java 25 for o padrão do sistema. Se o `JAVA_HOME` for atualizado para Java 21 globalmente, a flag `net.bytebuddy.experimental` pode ser removida. A flag `java.security.manager=allow` pode ser necessária dependendo da versão do Keycloak e do Java 21.

### Java 21 como padrão para builds

O `JAVA_HOME` da máquina foi definido como:

```
C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot
```

Para compilar o backend (quando necessário):

```powershell
cd C:\SOL\backend
mvn clean package -DskipTests
```

O JAR gerado em `target\sol-backend-1.0.0.jar` será automaticamente usado pelo serviço `SOL-Backend` na próxima reinicialização. Para aplicar sem reiniciar:

```powershell
Restart-Service SOL-Backend
```

### Frontend

O diretório `C:\SOL\frontend\dist\sol-frontend\browser\` contém atualmente apenas um `index.html` de placeholder. Após compilar o Angular:

```bash
cd C:\SOL\frontend
ng build --configuration production
```

O Nginx servirá automaticamente os arquivos gerados (sem necessidade de reiniciar).

---

## Scripts auxiliares criados nesta sessão

Os seguintes arquivos foram criados para contornar os problemas de encoding dos scripts originais:

| Arquivo | Substitui | Motivo |
|---------|-----------|--------|
| `05-sol-service-fix.ps1` | `05-sol-service.ps1` | Encoding corrompido no original |
| `06-keycloak-realm-fix.ps1` | `06-keycloak-realm.ps1` | Encoding + lógica de retry para aguardar Keycloak |
| `07-minio-buckets-fix.ps1` | `07-minio-buckets.ps1` | Encoding corrompido no original |
| `08-verify-fix.ps1` | `08-verify-all.ps1` | Encoding + uso de `HttpWebRequest` em vez de `Invoke-WebRequest` |
| `test-endpoints.ps1` | — | Script auxiliar de diagnóstico de endpoints HTTP |

---

*Documento gerado em 2026-03-26 ao final da sessão de configuração do Sprint 0.*
