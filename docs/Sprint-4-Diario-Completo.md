# Sprint 4 — Diário Completo de Execução

**Projeto:** SOL — Sistema Online de Licenciamento do CBM-RS
**Data de execução:** 2026-03-28
**Sprint:** 4 de N
**Responsável:** Guilherme
**Executor (IA):** Claude Code (claude-sonnet-4-6)
**Script base:** `Y:\infra\scripts\sprint4-deploy.ps1`
**Drive Y:** `\\CBM-QCG-238\SOL` (compartilhamento de rede — máquina vizinha)

---

## Índice

- [[#Contexto da Sprint 4]]
- [[#Arquivos Java Entregues]]
- [[#Análise Prévia ao Deploy]]
- [[#Problemas Detectados e Soluções — Visão Geral]]
- [[#Primeira Execução do Script — Falha no Passo 7]]
  - [[#Correção 1 — CEP com Hífen]]
- [[#Segunda Execução do Script — Falha no Passo 8 (MinIO)]]
  - [[#Diagnóstico do Access Denied — Processo Completo]]
  - [[#Correção 2 — MinIO SDK 8.5.11 → 8.5.17]]
  - [[#Resultado da Segunda Execução]]
  - [[#Correção 3 — s3:GetBucketLocation na Policy MinIO]]
- [[#Terceira Execução — Sucesso Completo]]
- [[#Saída Completa do Script (Execução Final)]]
- [[#Execução de Cada Passo do Script]]
  - [[#Passo 1 — Parada do Serviço]]
  - [[#Passo 2 — Compilação Maven]]
  - [[#Passo 3 — Reinício do Serviço]]
  - [[#Passo 4 — Aguardo de Inicialização]]
  - [[#Passo 5 — Health Check]]
  - [[#Passo 6 — Login]]
  - [[#Passo 7 — POST /licenciamentos (RASCUNHO)]]
  - [[#Passo 8 — POST /arquivos/upload (Multipart)]]
  - [[#Passo 9 — GET /licenciamentos/{id}/arquivos]]
  - [[#Passo 10 — GET /arquivos/{id}/download-url]]
  - [[#Passo 11 — POST /licenciamentos/{id}/submeter]]
  - [[#Passo 12 — Verificação de Status]]
  - [[#Passo 13 — Limpeza Oracle]]
  - [[#Passo 14 — Resultado Final]]
- [[#Arquitetura Implementada na Sprint 4]]
  - [[#ArquivoController e ArquivoService]]
  - [[#MinioService]]
  - [[#LicenciamentoService — Novos Métodos]]
  - [[#LicenciamentoController — Novos Endpoints]]
  - [[#Máquina de Estados do Licenciamento]]
- [[#Análise do Bug MinIO — Investigação Detalhada]]
- [[#Resultado dos Smoke Tests]]
- [[#Estado Final do Sistema]]

---

## Contexto da Sprint 4

A Sprint 4 implementou o fluxo **P03 — Submissão de Licenciamento**, que é o passo central de todo o sistema SOL: o RT ou Cidadão cria um processo de licenciamento, anexa os documentos obrigatórios (PPCI e outros), e submete para análise do CBM-RS.

Os componentes entregues nesta sprint foram:

| Arquivo | Tipo | Responsabilidade |
|---|---|---|
| `ArquivoController.java` | Controller | Upload, download, listagem e remoção de documentos |
| `ArquivoService.java` | Service | Validação MIME/tamanho, geração de chave, orquestração MinIO↔Oracle |
| `MinioService.java` | Service | Wrapper do MinIO Java SDK — upload, download, delete, URL pré-assinada |
| `LicenciamentoController.java` | Controller | Atualizado: POST criação, POST submeter, GET por id, GET meus |
| `LicenciamentoService.java` | Service | Atualizado: create(), submeter(), máquina de estados completa |

A Sprint 4 introduziu integração real com o **MinIO** (armazenamento de objetos S3-compatível) e com o **fluxo de negócio de submissão**, incluindo:
- Regras de negócio `RN-ARQ-001` a `RN-ARQ-004` (validação de arquivos)
- Regras `RN-P03-001` e `RN-P03-002` (pré-condições para submissão)
- Registro de marco de processo (`TipoMarco.SUBMISSAO`) no Oracle

**Observação sobre o drive Y:**
O script foi disponibilizado em `Y:\infra\scripts\sprint4-deploy.ps1`, onde `Y:` é o mapeamento de rede `\\CBM-QCG-238\SOL` (máquina CBM-QCG-238). A compilação Maven usa `$ProjectRoot = "C:\SOL\backend"` (local, na máquina CBM-QCG-239), onde os mesmos arquivos Java já foram depositados previamente.

---

## Arquivos Java Entregues

```
C:\SOL\backend\src\main\java\br\gov\rs\cbm\sol\
├── controller\
│   ├── ArquivoController.java       ← NOVO Sprint 4
│   └── LicenciamentoController.java ← ATUALIZADO Sprint 4
├── service\
│   ├── ArquivoService.java          ← NOVO Sprint 4
│   ├── MinioService.java            ← NOVO Sprint 4
│   └── LicenciamentoService.java    ← ATUALIZADO Sprint 4
```

Todos os demais arquivos (entidades, DTOs, repositórios, configurações) permaneceram inalterados ou já continham os campos necessários para a Sprint 4 (ex: `ArquivoED.java` já tinha `bucketMinio`, `contentType`, `tamanho`, `usuarioUpload`).

---

## Análise Prévia ao Deploy

Antes de qualquer execução, os seguintes arquivos foram lidos e analisados:

- `sprint4-deploy.ps1` — estrutura geral, variáveis, smoke tests
- `ArquivoService.java` — lógica de upload, validação MIME, geração de chave MinIO
- `MinioService.java` — wrapper SDK, signing, URL pré-assinada
- `ArquivoController.java` — endpoints e autorizações
- `LicenciamentoController.java` — novos endpoints POST e submeter
- `LicenciamentoService.java` — create(), submeter(), máquina de estados
- `ArquivoEDRepository.java` — confirmar métodos `findByLicenciamentoId` e `findByLicenciamentoIdAndTipoArquivo`
- `UsuarioRepository.java` — confirmar `findByKeycloakId`
- `LicenciamentoCreateDTO.java` — campos esperados vs. body do script
- `EnderecoDTO.java` — **encontrada a validação `@Pattern(regexp="\\d{8}")`**
- `TipoLicenciamento.java` — confirmar `PPCI` existe
- `TipoArquivo.java` — confirmar `PPCI` existe
- `pom.xml` — dependências, versão do MinIO SDK

A análise revelou imediatamente o **Bug 1 (CEP com hífen)**, descrito abaixo.

---

## Problemas Detectados e Soluções — Visão Geral

| # | Tipo | Localização | Descrição | Solução |
|---|---|---|---|---|
| 1 | Bug no script de deploy | `sprint4-deploy.ps1` L46 | CEP `"90010-100"` (9 chars com hífen) reprovado por `@Pattern(regexp="\\d{8}")` | Corrigido para `"90010100"` |
| 2 | Incompatibilidade de versão | `pom.xml` | MinIO SDK `8.5.11` incompatível com MinIO Server `2025-09-07` | Atualizado para `8.5.17` |
| 3 | Permissão faltante | MinIO `sol-app-policy` | `s3:GetBucketLocation` ausente — SDK Java chama esse endpoint antes de qualquer PUT | Policy atualizada + `AbortMultipartUpload` + `ListMultipartUploadParts` |

---

## Primeira Execução do Script — Falha no Passo 7

```
===> Parando servico SOL-Backend
  [OK] Servico parado
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
===> Aguardando 30 segundos para inicializacao do Spring Boot
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
===> Login -- POST /auth/login (usuario: sol-admin)
  [OK] Login OK -- token expira em 3600s
===> Smoke test P03 -- POST /licenciamentos
  [FALHA] Criacao de licenciamento falhou: O servidor remoto retornou um erro: (400) Solicitação Incorreta.
```

O script encerrou com `exit 1` neste ponto.

### Correção 1 — CEP com Hífen

**Arquivo:** `Y:\infra\scripts\sprint4-deploy.ps1`, linha 46
**Tipo:** Bug de dados de teste — formato inválido

O script enviou no body do `POST /licenciamentos`:
```json
"endereco": {
  "cep": "90010-100",
  ...
}
```

O `EnderecoDTO.java` contém a seguinte validação:

```java
@NotBlank(message = "CEP e obrigatorio")
@Pattern(regexp = "\\d{8}", message = "CEP deve conter 8 digitos numericos")
String cep,
```

`\\d{8}` significa: **exatamente 8 dígitos numéricos**. O valor `"90010-100"` tem 9 caracteres e contém um hífen — reprovado pelo Bean Validation com HTTP 400.

**Por que o Bean Validation retorna 400 e não 422?**
O `GlobalExceptionHandler` trata `MethodArgumentNotValidException` (que é o que o Spring lança para falhas `@Valid`) retornando HTTP 400 Bad Request com a lista de erros de campo. O 422 é usado apenas para `BusinessException` (regras de negócio internas). A distinção é:
- HTTP 400 → erro de entrada (payload inválido, violação de constraint)
- HTTP 422 → dado válido mas viola regra de negócio (ex: CPF já cadastrado)

**Correção aplicada:**
```diff
- $TestCep = "90010-100"
+ $TestCep = "90010100"
```

---

## Segunda Execução do Script — Falha no Passo 8 (MinIO)

Após a correção do CEP, o script foi re-executado:

```
===> Parando servico SOL-Backend
  [OK] Servico parado
===> Compilando com Maven ...
  [OK] Build concluido com sucesso
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
===> Aguardando 30 segundos para inicializacao do Spring Boot
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
===> Login -- POST /auth/login (usuario: sol-admin)
  [OK] Login OK -- token expira em 3600s
===> Smoke test P03 -- POST /licenciamentos
  [OK] Licenciamento criado -- id=1 status=RASCUNHO
===> Smoke test P03 -- POST /arquivos/upload (multipart)
  [FALHA] Upload falhou: HTTP 422: {"type":"https://sol.cbm.rs.gov.br/erros/regra-negocio",
  "title":"Violacao de regra de negocio","status":422,
  "detail":"Falha ao armazenar arquivo no MinIO: Falha ao fazer upload para MinIO
  [bucket=sol-arquivos key=licenciamentos/1/PPCI/3e7c9ca0-..._tmp3CA.tmp.pdf]: Access Denied.",
  "instance":"/api/arquivos/upload","codigoRegra":"RN-ARQ-004"}
  [AVISO] Verifique se o servico SOL-MinIO esta rodando e o bucket sol-arquivos existe
===> Smoke test P03 -- GET /licenciamentos/1/arquivos
  [OK] Lista OK -- 0 arquivo(s) encontrado(s)
===> Smoke test P03 -- POST /licenciamentos/1/submeter
  [FALHA] Submissao falhou: O servidor remoto retornou um erro: (422).
===> Verificando status apos submissao -- GET /licenciamentos/1
  [AVISO] Status inesperado -- RASCUNHO (esperado ANALISE_PENDENTE)
===> Limpeza -- removendo dados de teste do Oracle
  [OK] Dados de teste removidos do Oracle (licenciamento id=1)
===> Sprint 4 concluida
  Deploy da Sprint 4 concluido com sucesso!
```

O script concluiu com `exit 0` (o resultado final é sempre impresso), mas dois smoke tests falharam:
- **Passo 8** — upload retornou HTTP 422 `Access Denied` do MinIO
- **Passo 11** — submissão falhou com HTTP 422 `RN-P03-002` (sem PPCI anexado, consequência do passo 8)

### Diagnóstico do Access Denied — Processo Completo

O erro reportado pelo Spring Boot foi:

```
Falha ao armazenar arquivo no MinIO: Falha ao fazer upload para MinIO
[bucket=sol-arquivos key=licenciamentos/1/PPCI/3e7c9ca0-..._tmp3CA.tmp.pdf]: Access Denied.
```

A cadeia de exceções é:
```
MinioException("Access Denied.")
  → RuntimeException("Falha ao fazer upload para MinIO [bucket=...]: Access Denied.")
    → BusinessException("RN-ARQ-004", "Falha ao armazenar arquivo no MinIO: ...")
      → GlobalExceptionHandler → HTTP 422 ProblemDetail
```

**Etapa 1 — Verificação de infraestrutura básica**

Confirmado que o MinIO estava rodando e o `sol-app` com policy `sol-app-policy` estava ativo:
```
AccessKey: sol-app
Status: enabled
PolicyName: sol-app-policy
MemberOf: []
```

**Etapa 2 — Teste com `mc cp` (Go SDK)**

Upload direto via `mc cp` com credenciais do `sol-app` para o caminho `sol-arquivos/licenciamentos/1/PPCI/test-sdk-compat.pdf`:
```
Name      : test-sdk-compat.pdf
Date      : 2026-03-28 11:34:19 -03
Size      : 18 B
ETag      : 7e4b486562aaf88cacf90458af1adbfb
Type      : file
Metadata  :
  Content-Type: application/pdf
```
**Resultado: SUCESSO.** As credenciais e permissões estavam corretas para o Go SDK (`mc`).

**Etapa 3 — Versão do MinIO**

```
Version: 2025-09-07T16:13:09Z
Uptime: 3 hours
```

MinIO versão **setembro de 2025** — muito mais recente que o SDK Java `8.5.11` (lançado em 2024).

**Etapa 4 — Teste raw HTTP com SigV4**

Para isolat se o problema era de permissão ou de assinatura do SDK, foi executado um PUT HTTP puro com AWS Signature V4 calculada manualmente em PowerShell, usando o hash SHA256 real do conteúdo:

```powershell
x-amz-content-sha256: <sha256-real-do-pdf>
Authorization: AWS4-HMAC-SHA256 Credential=sol-app/...
```

**Resultado: HTTP 200 — SUCESSO.**

**Etapa 5 — Teste raw com `UNSIGNED-PAYLOAD`**

O MinIO Java SDK, em conexões HTTP (não HTTPS), usa `x-amz-content-sha256: UNSIGNED-PAYLOAD` ao invés do hash real, por eficiência. Testado explicitamente:

```powershell
x-amz-content-sha256: UNSIGNED-PAYLOAD
```

**Resultado: HTTP 200 — SUCESSO.** `UNSIGNED-PAYLOAD` também é aceito.

**Conclusão parcial:** O problema não era de permissão de bucket nem de método de assinatura. Era específico do comportamento do SDK Java.

**Etapa 6 — Atualização do SDK (tentativa)**

Atualizado `pom.xml`: `minio.version` `8.5.11` → `8.5.17`. Recompilado e reiniciado. O upload **continuou falhando** com o mesmo erro.

**Etapa 7 — MinIO Admin Trace**

A chave do diagnóstico veio do `mc admin trace --call s3`, que captura em tempo real as requisições recebidas pelo servidor MinIO. Durante um upload via Spring Boot:

```
2026-03-28T12:47:27.881 [403 Forbidden] s3.GetBucketLocation
localhost:9000/sol-arquivos?location=  127.0.0.1  0s  ↑ 116 B ↓ 303 B
```

**O MinIO SDK Java chamava `GetBucketLocation` (GET /?location=) antes do PUT, e recebia HTTP 403 Forbidden.** Ao receber esse erro, o SDK abortava toda a operação e reportava "Access Denied".

Isso explicava todas as observações:
- O `mc` (Go SDK) faz chamadas diferentes e tolera 403 em `GetBucketLocation` silenciosamente
- O raw HTTP PUT funcionava porque não chamava `GetBucketLocation`
- O SDK Java 8.5.17 (assim como o 8.5.11) chama `GetBucketLocation` como primeira etapa de qualquer operação de objeto, para determinar dinamicamente a região do bucket

### Correção 2 — MinIO SDK 8.5.11 → 8.5.17

**Por que foi feita mesmo antes de descobrir a causa real?**

A investigação seguiu o raciocínio correto: MinIO `2025-09-07` com SDK `8.5.11` de 2024 é uma combinação que pode ter incompatibilidades. Atualizar o SDK foi a primeira hipótese razoável, e era uma correção segura (não modifica comportamento funcional, apenas atualiza dependência).

A hipótese original era que o SDK antigo usasse `STREAMING-AWS4-HMAC-SHA256-PAYLOAD` (chunked signing) que versões novas do MinIO não aceitariam. Essa hipótese foi descartada pelos testes 4 e 5 (ambos os métodos funcionaram no raw HTTP).

A atualização para `8.5.17` ficou no `pom.xml` porque representa uma melhoria legítima de compatibilidade.

**Arquivo:** `C:\SOL\backend\pom.xml`
```diff
- <minio.version>8.5.11</minio.version>
+ <minio.version>8.5.17</minio.version>
```

### Resultado da Segunda Execução

Após a atualização do SDK e recompilação, o upload **ainda falhava** — confirmando que o problema não era a versão do SDK, mas sim a política do MinIO.

### Correção 3 — s3:GetBucketLocation na Policy MinIO

**Causa raiz confirmada:** A `sol-app-policy` não incluía `s3:GetBucketLocation`. A ação foi adicionada junto com `s3:AbortMultipartUpload` e `s3:ListMultipartUploadParts`, que são necessárias para uploads multipart de arquivos maiores.

**Por que `s3:GetBucketLocation` não estava na policy original?**

O script `07-minio-buckets.ps1` (Sprint 0) criou a policy com:
```json
"Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
```

Esse conjunto era suficiente para operações S3 básicas com SDKs Go/Python que não chamam `GetBucketLocation`. O SDK Java da MinIO (8.x) chama `GetBucketLocation` como parte da inicialização de qualquer operação, comportamento que não estava documentado no setup original.

**Tentativa inicial com BOM:**
O primeiro script de correção usou `Set-Content -Encoding utf8` que no PowerShell 5.1 adiciona um BOM (Byte Order Mark `U+FEFF` = `ï»¿`) no início do arquivo. O `mc` rejeitou o JSON com:
```
mc.exe: <ERROR> Unable to create new policy:
invalid character 'ï' looking for beginning of value.
```

A solução foi usar a ferramenta `Write` do Claude Code (que escreve UTF-8 sem BOM) para criar o arquivo, e então passá-lo ao `mc`:

**Policy final aplicada:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ],
    "Resource": [
      "arn:aws:s3:::sol-arquivos",  "arn:aws:s3:::sol-arquivos/*",
      "arn:aws:s3:::sol-appci",     "arn:aws:s3:::sol-appci/*",
      "arn:aws:s3:::sol-guias",     "arn:aws:s3:::sol-guias/*",
      "arn:aws:s3:::sol-laudos",    "arn:aws:s3:::sol-laudos/*",
      "arn:aws:s3:::sol-decisoes",  "arn:aws:s3:::sol-decisoes/*",
      "arn:aws:s3:::sol-temp",      "arn:aws:s3:::sol-temp/*"
    ]
  }]
}
```

Após aplicar a policy e executar o teste diagnóstico:
```
HTTP 201
{"id":1,"nomeArquivo":"diag.pdf","identificadorAlfresco":"licenciamentos/5/PPCI/1530ed45-..._diag.pdf",
 "bucketMinio":"sol-arquivos","contentType":"application/pdf","tamanho":13,...}
```

Upload funcionando. Terceira execução do script.

---

## Terceira Execução — Sucesso Completo

```
===> Parando servico SOL-Backend
  [OK] Servico parado
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
===> Aguardando 30 segundos para inicializacao do Spring Boot
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
===> Login -- POST /auth/login (usuario: sol-admin)
  [OK] Login OK -- token expira em 3600s
===> Smoke test P03 -- POST /licenciamentos
  [OK] Licenciamento criado -- id=6 status=RASCUNHO
===> Smoke test P03 -- POST /arquivos/upload (multipart)
  [OK] Upload OK -- arquivoId=2 nome=tmpE7F1.tmp.pdf tamanho=301 bytes
===> Smoke test P03 -- GET /licenciamentos/6/arquivos
  [OK] Lista OK -- 1 arquivo(s) encontrado(s)
    id=2 tipo=PPCI nome=tmpE7F1.tmp.pdf
===> Smoke test P03 -- GET /arquivos/2/download-url
  [OK] URL pre-assinada OK -- http://localhost:9000/sol-arquivos/licenciamentos/6/PPCI/25c72ff9-9835-4ab0-bb58...
===> Smoke test P03 -- POST /licenciamentos/6/submeter
  [OK] Submissao OK -- status=ANALISE_PENDENTE
===> Verificando status apos submissao -- GET /licenciamentos/6
  [OK] Status verificado -- ANALISE_PENDENTE (correto)
===> Limpeza -- removendo dados de teste do Oracle
  [OK] Dados de teste removidos do Oracle (licenciamento id=6)
===> Sprint 4 concluida

  Fluxos verificados:
    P03 -- Criacao de Licenciamento (RASCUNHO)
    P03 -- Upload de PPCI (multipart -> MinIO -> Oracle)
    P03 -- Listagem de arquivos do licenciamento
    P03 -- URL pre-assinada MinIO (1h)
    P03 -- Submissao (RASCUNHO -> ANALISE_PENDENTE + marco SUBMISSAO)

  Deploy da Sprint 4 concluido com sucesso!
```

Script encerrou com `exit 0`. Todos os 7 smoke tests passaram.

---

## Saída Completa do Script (Execução Final)

```
===> Parando servico SOL-Backend
  [OK] Servico parado

===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso

===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado

===> Aguardando 30 segundos para inicializacao do Spring Boot

===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)

===> Login -- POST /auth/login (usuario: sol-admin)
  [OK] Login OK -- token expira em 3600s

===> Smoke test P03 -- POST /licenciamentos
  [OK] Licenciamento criado -- id=6 status=RASCUNHO

===> Smoke test P03 -- POST /arquivos/upload (multipart)
  [OK] Upload OK -- arquivoId=2 nome=tmpE7F1.tmp.pdf tamanho=301 bytes

===> Smoke test P03 -- GET /licenciamentos/6/arquivos
  [OK] Lista OK -- 1 arquivo(s) encontrado(s)
    id=2 tipo=PPCI nome=tmpE7F1.tmp.pdf

===> Smoke test P03 -- GET /arquivos/2/download-url
  [OK] URL pre-assinada OK -- http://localhost:9000/sol-arquivos/licenciamentos/6/PPCI/25c72ff9-9835-4ab0-bb58...

===> Smoke test P03 -- POST /licenciamentos/6/submeter
  [OK] Submissao OK -- status=ANALISE_PENDENTE

===> Verificando status apos submissao -- GET /licenciamentos/6
  [OK] Status verificado -- ANALISE_PENDENTE (correto)

===> Limpeza -- removendo dados de teste do Oracle
  [OK] Dados de teste removidos do Oracle (licenciamento id=6)

===> Sprint 4 concluida

  Fluxos verificados:
    P03 -- Criacao de Licenciamento (RASCUNHO)
    P03 -- Upload de PPCI (multipart -> MinIO -> Oracle)
    P03 -- Listagem de arquivos do licenciamento
    P03 -- URL pre-assinada MinIO (1h)
    P03 -- Submissao (RASCUNHO -> ANALISE_PENDENTE + marco SUBMISSAO)

  Deploy da Sprint 4 concluido com sucesso!
```

---

## Execução de Cada Passo do Script

### Passo 1 — Parada do Serviço

**Código:**
```powershell
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $svc -and $svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 5
}
```

**O que aconteceu:** O serviço `SOL-Backend` (gerenciado pelo NSSM) estava em execução. `Stop-Service -Force` enviou o sinal de parada ao NSSM, que por sua vez encerrou o processo Java. Os 5 segundos de espera garantem que o JVM finalizou e liberou o arquivo JAR em `C:\SOL\backend\target\sol-backend-1.0.0.jar`.

**Por que é necessário:** No Windows, arquivos em uso por um processo não podem ser sobrescritos. Se o Maven tentasse gerar um novo JAR com o serviço rodando, receberia `Access Denied` no sistema de arquivos.

---

### Passo 2 — Compilação Maven

**Código:**
```powershell
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"
$mvnWrapper = Join-Path $ProjectRoot "mvnw.cmd"
if (-not (Test-Path $mvnWrapper)) { $mvnWrapper = "mvn" }
Push-Location $ProjectRoot
& cmd /c "$mvnWrapper clean package $MavenOpts"
```

**O que aconteceu:**
- O `mvnw.cmd` (Maven Wrapper) **não existe** em `C:\SOL\backend`. O script caiu no fallback `$mvnWrapper = "mvn"`, usando o Maven global instalado via Chocolatey em `C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd`.
- `mvn clean package -Dmaven.test.skip=true -q` compilou todos os sources, processou as anotações Lombok e MapStruct, e gerou `sol-backend-1.0.0.jar`.
- **Nota:** Na terceira execução (após a correção do SDK), o Maven baixou `minio-8.5.17.jar` e o empacotou no fat JAR. Confirmado via inspeção do ZIP: `BOOT-INF/lib/minio-8.5.17.jar` presente.

**Por que `clean`?** Remove o diretório `target/` anterior, evitando que classes compiladas de sprints anteriores permaneçam no classpath e causem conflitos. Essencial quando entidades, DTOs ou configurações mudam entre sprints.

**Por que `-Dmaven.test.skip=true`?** Os testes unitários (SolApplicationTests) carregam o contexto Spring completo, o que exige conexão com Oracle e Keycloak. No contexto de deploy, esses pré-requisitos são validados pelos smoke tests do próprio script.

---

### Passo 3 — Reinício do Serviço

**Código:**
```powershell
if ($null -ne $svc) {
    Start-Service -Name $ServiceName
} else {
    # Modo dev: java -jar direto
    Start-Process -FilePath "$JavaHome\bin\java.exe" ...
}
```

**O que aconteceu:** O `$svc` foi capturado no Passo 1 (serviço existia), portanto `Start-Service` foi chamado. O NSSM iniciou o Java com os parâmetros configurados:
```
-Xms256m -Xmx1g -Dspring.profiles.active=prod -Dserver.port=8080 -jar C:\SOL\backend\target\sol-backend-1.0.0.jar
```

O perfil `prod` ativa as configurações de `application.yml` (Oracle XEPDB1, Keycloak `http://localhost:8180`, MinIO `http://localhost:9000`).

---

### Passo 4 — Aguardo de Inicialização

**Código:**
```powershell
Write-Step "Aguardando $WaitSeconds segundos para inicializacao do Spring Boot"
Start-Sleep -Seconds $WaitSeconds   # 30 segundos
```

**O que aconteceu:** 30 segundos de espera. Durante esse tempo, o Spring Boot realizou:
1. Scan de componentes e injeção de dependências
2. Inicialização do HikariCP (pool de conexões Oracle)
3. Execução do `ddl-auto: update` — Hibernate verificou o schema `SOL` e adicionou as colunas novas de `ARQUIVO_ED` (`bucket_minio`, `content_type`, `tamanho`, `id_usuario_upload`) se não existissem
4. Download do JWKS do Keycloak (`http://localhost:8180/realms/sol/protocol/openid-connect/certs`)
5. Inicialização do `MinioClient` (estabelece o cliente HTTP OkHttp, mas não faz conexões ainda)
6. Tomcat pronto na porta 8080

**Por que 30 segundos e não menos?** O `ddl-auto: update` com a Sprint 4 adicionando colunas a tabelas existentes pode ser mais lento que nas sprints anteriores. O valor conservador previne falhas no health check por inicialização incompleta.

---

### Passo 5 — Health Check

**Código:**
```powershell
for ($i = 1; $i -le 5; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) { ...; $healthy = $true; break }
    } catch {
        Write-WARN "Tentativa $i falhou -- aguardando 10s..."
        Start-Sleep -Seconds 10
    }
}
if (-not $healthy) { Write-FAIL "Health check falhou"; exit 1 }
```

**O que aconteceu:** HTTP 200 na primeira tentativa. O `HealthController` responde `{"status":"UP"}` sem autenticação (configurado como público no `SecurityConfig`).

**Por que até 5 tentativas?** Garante resiliência: se o Spring Boot ainda estiver inicializando na tentativa 1 (ex: ddl-auto mais lento), as tentativas 2-5 (com 10s de intervalo) absorvem a variação.

---

### Passo 6 — Login

**Código:**
```powershell
$loginBody = @{
    username = $AdminUser       # "sol-admin"
    password = $AdminPassword   # "Admin@SOL2026"
} | ConvertTo-Json

$tokenResponse = Invoke-RestMethod -Uri "$BaseUrl/auth/login" -Method POST ...
$accessToken = $tokenResponse.access_token
$authHeader  = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }
```

**O que aconteceu:** O `AuthService.login()` repassou as credenciais ao Keycloak via ROPC (`grant_type=password`, `client_id=sol-frontend`). O Keycloak retornou um JWT RS256 com `expires_in=3600`. O script extraiu o `access_token` e montou o header de autorização para os passos seguintes.

**Diferença em relação à Sprint 3:** Na Sprint 3, o bug de senha (`Admin@Sol2026` vs `Admin@SOL2026`) foi corrigido previamente. Na Sprint 4 o script já veio com a senha correta.

---

### Passo 7 — POST /licenciamentos (RASCUNHO)

**Código:**
```powershell
$licBody = @{
    tipo           = "PPCI"
    areaConstruida = 500.00
    alturaMaxima   = 10.00
    numPavimentos  = 3
    tipoOcupacao   = "Comercial - Loja"
    usoPredominante = "Comercial"
    endereco       = @{
        cep        = $TestCep      # "90010100" (após correção)
        logradouro = $TestLogradouro
        numero     = $TestNumero
        ...
    }
    responsavelTecnicoId = $null
    responsavelUsoId     = $null
    licenciamentoPaiId   = $null
} | ConvertTo-Json -Depth 5
```

**O que aconteceu internamente:**

```
POST /licenciamentos  →  LicenciamentoController.create()
                              │
                         LicenciamentoService.create()
                         1. Persiste Endereco (INSERT SOL.ENDERECO)
                         2. Persiste Licenciamento com status=RASCUNHO
                            (INSERT SOL.LICENCIAMENTO)
                         3. Retorna LicenciamentoDTO
                              │
                         HTTP 201 Created
                         Location: /api/licenciamentos/6
                         Body: { "id": 6, "status": "RASCUNHO", ... }
```

O `sol-admin` tem role `ADMIN`, e o endpoint está configurado com `@PreAuthorize("hasAnyRole('CIDADAO', 'RT', 'ADMIN')")`.

**Por que `responsavelTecnicoId = null`?** O wizard P03 permite criar o licenciamento sem RT definido (pode ser preenchido depois). A validação de negócio (RN-P03-003: RT obrigatório antes da submissão) não está implementada ainda — apenas a RN-P03-002 (PPCI obrigatório) está ativa nesta sprint.

---

### Passo 8 — POST /arquivos/upload (Multipart)

**Código:**
```powershell
# Cria PDF mínimo válido
$pdfMinimo = @"
%PDF-1.0
1 0 obj<</Type /Catalog/Pages 2 0 R>>endobj
...
%%EOF
"@
$tmpPdf = [System.IO.Path]::GetTempFileName() + ".pdf"
[System.IO.File]::WriteAllText($tmpPdf, $pdfMinimo)

$arquivoCriado = Invoke-MultipartUpload `
    -Uri "$BaseUrl/arquivos/upload" `
    -FilePath $tmpPdf `
    -FieldNameFile "file" `
    -Fields @{
        licenciamentoId = "$($licCriado.id)"
        tipoArquivo     = "PPCI"
    } `
    -BearerToken $accessToken
```

**A função `Invoke-MultipartUpload`** foi implementada no próprio script usando `System.Net.Http.HttpClient` (compatível com PowerShell 5.1, que não suporta `Invoke-RestMethod -Form` natively):

```powershell
function Invoke-MultipartUpload {
    Add-Type -AssemblyName System.Net.Http
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.DefaultRequestHeaders.Authorization = [AuthHeader]::new("Bearer", $BearerToken)
    $multipart = [System.Net.Http.MultipartFormDataContent]::new()
    # Adiciona o arquivo
    $fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
    $fileContent.Headers.ContentType = MediaTypeHeaderValue.Parse("application/pdf")
    $multipart.Add($fileContent, $FieldNameFile, [Path]::GetFileName($FilePath))
    # Adiciona campos de texto
    foreach ($key in $Fields.Keys) {
        $multipart.Add([StringContent]::new($Fields[$key]), $key)
    }
    $task = $httpClient.PostAsync($Uri, $multipart)
    $task.Wait()
    return $task.Result.Content.ReadAsStringAsync().Result | ConvertFrom-Json
}
```

**O que aconteceu internamente (quando funcionou):**

```
POST /arquivos/upload  →  ArquivoController.upload()
                              │ @RequestPart("file") MultipartFile
                              │ @RequestParam("licenciamentoId") Long
                              │ @RequestParam("tipoArquivo") TipoArquivo
                              │ @AuthenticationPrincipal Jwt
                              │
                         ArquivoService.upload()
                         1. RN-ARQ-001: file não vazio ✓
                         2. RN-ARQ-002: tamanho ≤ 50MB ✓ (301 bytes)
                         3. RN-ARQ-003: contentType "application/pdf" ✓
                         4. Carrega Licenciamento id=6 do Oracle
                         5. Busca usuarioUpload por keycloakId (sol-admin não tem
                            registro local → usuarioUpload = null)
                         6. Gera objectKey:
                            "licenciamentos/6/PPCI/25c72ff9-..._tmpE7F1.tmp.pdf"
                         7. MinioService.upload(bucket, objectKey, stream, contentType, size)
                            → PUT http://localhost:9000/sol-arquivos/licenciamentos/6/...
                            → HTTP 200 MinIO OK
                         8. INSERT SOL.ARQUIVO_ED (metadados)
                         9. Retorna ArquivoEDDTO
                              │
                         HTTP 201 Created
                         Location: /api/arquivos/2
```

**Sobre o nome do arquivo de teste:** O script cria um arquivo temporário com `GetTempFileName()` que gera um nome como `tmp3CA.tmp`, depois concatena `.pdf` → `tmp3CA.tmp.pdf`. O `sanitizarNome()` em `ArquivoService` mantém esse nome como chave no MinIO (caracteres permitidos: `a-zA-Z0-9._\-`). O nome original do arquivo fica em `NOME_ARQUIVO` no Oracle.

**Tamanho 301 bytes:** O arquivo PDF mínimo criado pelo script tem exatamente 301 bytes quando serializado pelo PowerShell com `WriteAllText` (encoding default do sistema). Esse valor aparece na saída: `tamanho=301 bytes`.

---

### Passo 9 — GET /licenciamentos/{id}/arquivos

**Código:**
```powershell
$listaArquivos = Invoke-RestMethod `
    -Uri "$BaseUrl/licenciamentos/$($licCriado.id)/arquivos" `
    -Headers $authHeader -TimeoutSec 10
Write-OK "Lista OK -- $($listaArquivos.Count) arquivo(s) encontrado(s)"
$listaArquivos | ForEach-Object {
    Write-Host "    id=$($_.id) tipo=$($_.tipoArquivo) nome=$($_.nomeArquivo)"
}
```

**O que aconteceu:**

```
GET /licenciamentos/6/arquivos  →  ArquivoController.findByLicenciamento()
                                        │
                                   ArquivoService.findByLicenciamento(6)
                                   → arquivoEDRepository.findByLicenciamentoId(6)
                                   → retorna [ArquivoED(id=2)]
                                        │
                                   HTTP 200: [{ id: 2, tipoArquivo: "PPCI",
                                               nomeArquivo: "tmpE7F1.tmp.pdf", ... }]
```

**Por que essa rota está aninhada em `/licenciamentos/{id}/arquivos`?**
É uma rota RESTful de recurso aninhado: os arquivos pertencem a um licenciamento, e a URL reflete essa hierarquia. Alternativamente, poderia ser `GET /arquivos?licenciamentoId=6`, mas a forma aninhada é mais expressiva para o consumidor da API.

---

### Passo 10 — GET /arquivos/{id}/download-url

**Código:**
```powershell
$urlResp = Invoke-RestMethod `
    -Uri "$BaseUrl/arquivos/$($arquivoCriado.id)/download-url" `
    -Headers $authHeader -TimeoutSec 10
```

**O que aconteceu:**

```
GET /arquivos/2/download-url  →  ArquivoController.getDownloadUrl(2)
                                      │
                                 ArquivoService.getPresignedUrl(2)
                                 1. busca ArquivoED id=2 no Oracle
                                 2. MinioService.getPresignedUrl(bucket, objectKey, 3600)
                                    → GET pré-assinado válido 1 hora
                                      http://localhost:9000/sol-arquivos/licenciamentos/6/PPCI/
                                      25c72ff9-..._tmpE7F1.tmp.pdf?X-Amz-Algorithm=...&
                                      X-Amz-Credential=sol-app%2F20260328%2Fus-east-1%2Fs3%2F
                                      aws4_request&X-Amz-Date=...&X-Amz-Expires=3600&
                                      X-Amz-Signature=...
                                      │
                                 HTTP 200: { "url": "http://..." }
```

**Como funciona a URL pré-assinada?**

O MinIO gera uma URL que inclui as credenciais de acesso embutidas como query parameters assinados com AWS SigV4. Qualquer cliente HTTP que tenha essa URL pode fazer um `GET` direto ao MinIO nos próximos 3600 segundos, **sem precisar de autenticação**. Isso permite que o Angular forneça ao usuário um link direto para download do PDF no browser, sem que o backend precise funcionar como proxy do arquivo.

A URL expira após 1 hora — configuração em `ArquivoService.PRESIGNED_EXPIRY_SEGUNDOS = 3600`.

---

### Passo 11 — POST /licenciamentos/{id}/submeter

**Código:**
```powershell
$licSubmetido = Invoke-RestMethod `
    -Uri "$BaseUrl/licenciamentos/$($licCriado.id)/submeter" `
    -Method POST -Headers $authHeader -TimeoutSec 15
```

**O que aconteceu internamente:**

```
POST /licenciamentos/6/submeter  →  LicenciamentoController.submeter(6, jwt)
                                         │
                                    LicenciamentoService.submeter(6, keycloakId)
                                    │
                                    ├─ RN-P03-001: status == RASCUNHO ✓
                                    │
                                    ├─ RN-P03-002: quantidade de PPCIs no Oracle:
                                    │  arquivoEDRepository.findByLicenciamentoIdAndTipoArquivo(6, PPCI)
                                    │  → 1 arquivo encontrado ✓
                                    │
                                    ├─ licenciamento.setStatus(ANALISE_PENDENTE)
                                    │  UPDATE SOL.LICENCIAMENTO SET STATUS='ANALISE_PENDENTE'
                                    │  WHERE ID_LICENCIAMENTO=6
                                    │
                                    └─ MarcoProcesso.builder()
                                         .tipoMarco(SUBMISSAO)
                                         .licenciamento(licenciamento)
                                         .usuario(null)  ← sol-admin sem registro local
                                         .observacao("Licenciamento submetido para analise via P03.
                                                      Arquivos PPCI: 1")
                                       INSERT SOL.MARCO_PROCESSO
                                         │
                                    HTTP 200: { "id": 6, "status": "ANALISE_PENDENTE", ... }
```

**Por que o marco foi registrado com `usuario = null`?**
O `sol-admin` foi criado diretamente no Keycloak e não tem registro na tabela `SOL.USUARIO`. O `LicenciamentoService.submeter()` tenta localizar o usuário via `usuarioRepository.findByKeycloakId(keycloakId).orElse(null)`. O `null` é aceito — o campo `ID_USUARIO` em `MARCO_PROCESSO` é nullable. Em produção, o usuário que submete sempre terá registro local (criado via `POST /cadastro/rt` ou `POST /cadastro/ru`).

**Regra de negócio RN-P03-002 — Por que exige PPCI?**
O PPCI (Plano de Proteção Contra Incêndio) é o documento central do processo de licenciamento no CBM-RS. Submeter sem ele seria um erro de negócio grave — o analista não teria o que avaliar. A validação na camada de serviço garante que essa condição seja verificada antes de qualquer transição de estado.

---

### Passo 12 — Verificação de Status

**Código:**
```powershell
$licAtual = Invoke-RestMethod `
    -Uri "$BaseUrl/licenciamentos/$($licCriado.id)" `
    -Headers $authHeader -TimeoutSec 10
if ($licAtual.status -eq "ANALISE_PENDENTE") {
    Write-OK "Status verificado -- ANALISE_PENDENTE (correto)"
} else {
    Write-WARN "Status inesperado -- $($licAtual.status)"
}
```

**O que aconteceu:** `GET /licenciamentos/6` retornou `status = "ANALISE_PENDENTE"`. Essa verificação dupla (primeiro via retorno do POST /submeter, depois via GET independente) garante que a mudança de status foi efetivamente persistida no Oracle e é lida corretamente pela query SELECT subsequente.

---

### Passo 13 — Limpeza Oracle

**Código:**
```powershell
$sqlDelete = @"
DELETE FROM sol.arquivo_ed WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.marco_processo WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.boleto WHERE id_licenciamento = $($licCriado.id);
DELETE FROM sol.licenciamento WHERE id_licenciamento = $($licCriado.id);
COMMIT;
EXIT;
"@
& "C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe" -S "/ as sysdba" "@$tmpSql"
```

**O que aconteceu:** As quatro tabelas filhas (`ARQUIVO_ED`, `MARCO_PROCESSO`, `BOLETO`) foram limpas antes do `LICENCIAMENTO`, respeitando as foreign keys. A ordem inversa das dependências é necessária: deletar `LICENCIAMENTO` primeiro falharia com `ORA-02292: integrity constraint violated - child record found`.

**Nota sobre o MinIO:** O script observa explicitamente:
```powershell
# Nota: o objeto no MinIO ja foi removido ao deletar ArquivoED via Oracle,
# mas como deletamos direto no Oracle sem passar pelo DELETE /arquivos/{id},
# o objeto no bucket pode permanecer. Limpar manualmente se necessario:
# mc.exe rm sol-minio/sol-arquivos/licenciamentos/<id>/ --recursive
```

Isso é correto: o `ArquivoService.delete()` remove do MinIO **e** do Oracle em sequência. Mas a limpeza via `sqlplus` direto só remove do Oracle. O objeto de teste ficará no bucket `sol-arquivos` como órfão até limpeza manual. Em produção, a exclusão sempre passa pelo endpoint `DELETE /arquivos/{id}`.

---

### Passo 14 — Resultado Final

**Código:**
```powershell
Write-Step "Sprint 4 concluida"
Write-Host "  Fluxos verificados:" -ForegroundColor Cyan
Write-Host "    P03 -- Criacao de Licenciamento (RASCUNHO)"
Write-Host "    P03 -- Upload de PPCI (multipart -> MinIO -> Oracle)"
Write-Host "    P03 -- Listagem de arquivos do licenciamento"
Write-Host "    P03 -- URL pre-assinada MinIO (1h)"
Write-Host "    P03 -- Submissao (RASCUNHO -> ANALISE_PENDENTE + marco SUBMISSAO)"
exit 0
```

`exit 0` — deploy concluído com sucesso.

---

## Arquitetura Implementada na Sprint 4

### ArquivoController e ArquivoService

O `ArquivoController` expõe 7 endpoints:

| Método | Path | Auth | Descrição |
|---|---|---|---|
| `POST` | `/arquivos/upload` | Autenticado | Upload multipart → MinIO → Oracle |
| `GET` | `/arquivos/{id}` | Autenticado | Metadados do arquivo |
| `GET` | `/arquivos/{id}/download` | Autenticado | Stream direto do arquivo |
| `GET` | `/arquivos/{id}/download-url` | Autenticado | URL pré-assinada (1h) |
| `DELETE` | `/arquivos/{id}` | ADMIN/CIDADAO/RT | Remove MinIO + Oracle |
| `GET` | `/licenciamentos/{id}/arquivos` | Autenticado | Lista arquivos do licenciamento |
| `GET` | `/licenciamentos/{id}/arquivos?tipo=PPCI` | Autenticado | Filtra por tipo |

O `ArquivoService.upload()` implementa as seguintes regras de negócio:

```
RN-ARQ-001: arquivo não pode ser vazio (file.isEmpty())
RN-ARQ-002: tamanho máximo 50 MB (file.getSize() > 50*1024*1024)
RN-ARQ-003: tipos MIME aceitos:
  - application/pdf
  - image/jpeg / image/png / image/tiff
  - application/zip / application/x-zip-compressed
  - application/vnd.dwg / application/octet-stream
  Fallback: arquivos .pdf com MIME genérico são aceitos como PDF
RN-ARQ-004: falha de armazenamento no MinIO
```

**Chave de objeto no MinIO:**
```
licenciamentos/{licenciamentoId}/{tipoArquivo}/{uuid}_{nomeSeguro}
Exemplo: licenciamentos/6/PPCI/25c72ff9-9835-4ab0-bb58-..._ppci_projeto.pdf
```

O prefixo com `licenciamentoId` e `tipoArquivo` facilita listagem e remoção por prefixo (`mc rm --recursive`) e organiza visualmente o bucket no console MinIO.

### MinioService

Wrapper de baixo nível sobre o `MinioClient` (SDK Java). Não conhece regras de negócio — apenas traduz exceções do SDK:

```
upload()         → PUT object (PutObjectArgs com stream + size + contentType)
download()       → GET object stream (GetObjectArgs)
delete()         → DELETE object (RemoveObjectArgs)
getPresignedUrl() → URL GET pré-assinada (GetPresignedObjectUrlArgs, method=GET)
objectExists()   → HEAD object (StatObjectArgs)
```

O método `getPresignedUrl` usa `TimeUnit.SECONDS` como unidade, com o SDK gerenciando a lógica de expiração na URL gerada.

### LicenciamentoService — Novos Métodos

**`create(LicenciamentoCreateDTO dto)`:**
- Persiste `Endereco` separadamente (entity independente com própria sequence)
- Cria `Licenciamento` com `status = RASCUNHO`, `ativo = true`, `isentoTaxa = false`
- Vincula opcionalmente RT, RU e licenciamento pai

**`submeter(Long id, String keycloakId)`:**
```
RN-P03-001: status == RASCUNHO (caso contrário: BusinessException)
RN-P03-002: qty de PPCI ≥ 1 (caso contrário: BusinessException)
→ status = ANALISE_PENDENTE
→ INSERT MARCO_PROCESSO (tipo=SUBMISSAO, observacao="...PPCI: N")
```

**`validarTransicaoStatus()`:** Máquina de estados completa implementada com `switch` expression do Java 21:

```java
boolean transicaoValida = switch (atual) {
    case RASCUNHO         → novo == ANALISE_PENDENTE;
    case ANALISE_PENDENTE → novo == EM_ANALISE || novo == EXTINTO;
    case EM_ANALISE       → novo == CIA_EMITIDO || novo == DEFERIDO || novo == INDEFERIDO;
    case CIA_EMITIDO      → novo == CIA_CIENCIA || novo == SUSPENSO;
    // ... (12 estados totais)
    case EXTINTO, INDEFERIDO, RENOVADO → false;  // estados finais
};
```

### LicenciamentoController — Novos Endpoints

| Método | Path | Roles | Descrição |
|---|---|---|---|
| `POST` | `/licenciamentos` | CIDADAO/RT/ADMIN | Cria licenciamento (inicia wizard P03) |
| `GET` | `/licenciamentos/{id}` | Autenticado | Busca por ID |
| `GET` | `/licenciamentos/meus` | CIDADAO/RT | Licenciamentos do usuário autenticado |
| `POST` | `/licenciamentos/{id}/submeter` | CIDADAO/RT/ADMIN | RASCUNHO → ANALISE_PENDENTE |
| `PATCH` | `/licenciamentos/{id}/status` | ADMIN/ANALISTA/INSPETOR/CHEFE | Transição manual de status |
| `DELETE` | `/licenciamentos/{id}` | CIDADAO/RT/ADMIN | Soft delete (somente RASCUNHO) |

### Máquina de Estados do Licenciamento

```
RASCUNHO
  └─► ANALISE_PENDENTE  (P03 — submeter, requer PPCI)
        └─► EM_ANALISE  (analista inicia análise)
              ├─► CIA_EMITIDO  (Comunicado de Inadequação emitido)
              │     ├─► CIA_CIENCIA  (RT tomou ciência)
              │     │     ├─► EM_ANALISE  (retorna para nova análise)
              │     │     └─► RECURSO_PENDENTE
              │     └─► SUSPENSO
              ├─► DEFERIDO  (análise aprovada)
              │     ├─► VISTORIA_PENDENTE
              │     │     └─► EM_VISTORIA
              │     │           ├─► CIV_EMITIDO
              │     │           └─► PRPCI_EMITIDO
              │     └─► PRPCI_EMITIDO  (Projeto PPCI aprovado)
              │           └─► APPCI_EMITIDO  (Auto de Vistoria emitido)
              │                 ├─► SUSPENSO
              │                 ├─► RENOVADO  (estado final)
              │                 └─► EXTINTO   (estado final)
              └─► INDEFERIDO  (estado final)

RECURSO_PENDENTE → EM_RECURSO → DEFERIDO | INDEFERIDO
SUSPENSO → EXTINTO
```

---

## Análise do Bug MinIO — Investigação Detalhada

Esta seção documenta o raciocínio e as etapas de diagnóstico do problema mais complexo da Sprint 4.

### Sintoma

```
HTTP 422 - Falha ao armazenar arquivo no MinIO:
Falha ao fazer upload para MinIO [bucket=sol-arquivos key=...]: Access Denied.
```

### Hipóteses testadas em ordem

| # | Hipótese | Teste | Resultado |
|---|---|---|---|
| 1 | Credenciais erradas | `mc admin user info sol-minio sol-app` | ✗ Credenciais OK, policy ativa |
| 2 | Bucket não existe ou sem permissão | `mc cp` com `sol-app` | ✗ Upload funcionou normalmente |
| 3 | SDK antigo usa `STREAMING-*` rejeitado pelo novo MinIO | Raw PUT com SigV4 real hash | ✗ Funciona — MinIO aceita ambos |
| 4 | SDK antigo usa `UNSIGNED-PAYLOAD` rejeitado | Raw PUT com `UNSIGNED-PAYLOAD` | ✗ Funciona |
| 5 | SDK 8.5.11 tem bug de compatibilidade | Upgrade para 8.5.17 | ✗ Ainda falha |
| 6 | Proxy ou JVM option interferindo | Check NSSM AppEnvironmentExtra | ✗ Nenhum proxy |
| **7** | **`GetBucketLocation` faltando na policy** | **`mc admin trace --call s3`** | **✓ 403 Forbidden capturado** |

### O que o `mc admin trace` revelou

```
2026-03-28T12:47:27.881 [403 Forbidden] s3.GetBucketLocation
  localhost:9000/sol-arquivos?location=  127.0.0.1  ↑116B ↓303B
```

O MinIO Java SDK faz uma chamada **prévia** `GET /{bucket}?location=` (mapeada para `s3:GetBucketLocation`) antes de qualquer operação de objeto. O objetivo é descobrir dinamicamente a região do bucket para usar no signing. Quando essa chamada retorna 403 (permissão ausente), o SDK interpreta como falha geral de autorização e lança `MinioException("Access Denied.")`.

### Por que o `mc` (Go SDK) não tinha esse problema?

O Go SDK do MinIO (`minio-go`) trata o 403 em `GetBucketLocation` como "região desconhecida, usar padrão" e continua com o upload. É uma diferença de implementação entre os dois SDKs — o Go SDK é mais tolerante a falhas de pré-verificação.

### Por que o `07-minio-buckets.ps1` não incluiu `s3:GetBucketLocation`?

O script de setup (Sprint 0) foi escrito com base nos exemplos mínimos de policy da documentação MinIO, que cobrem apenas as operações de dados (`GetObject`, `PutObject`, `DeleteObject`, `ListBucket`). O `GetBucketLocation` é uma operação de **metadados de bucket**, não de dados, e frequentemente é omitido em exemplos básicos porque a maioria dos SDKs Go/Python não o chama.

### Actions adicionadas à policy

```json
"s3:GetBucketLocation"        ← causa raiz do bug
"s3:AbortMultipartUpload"     ← necessário para uploads grandes (> 10 MB)
"s3:ListMultipartUploadParts" ← necessário para resume de uploads interrompidos
```

`AbortMultipartUpload` e `ListMultipartUploadParts` foram adicionadas preventivamente: arquivos PPCI de projetos complexos podem facilmente ultrapassar 10 MB (parte size do `MinioService`), ativando o multipart upload do SDK, que exige essas ações.

### Sobre o BOM UTF-8

A primeira tentativa de criar o arquivo de policy usou `Set-Content` do PowerShell 5.1:
```powershell
Set-Content -Path $policyFile -Value $policyJson
```

No PowerShell 5.1 (Windows), `Set-Content` sem `-Encoding` usa Unicode (UTF-16 LE). Com `-Encoding utf8`, adiciona BOM (`EF BB BF` = `ï»¿`). O `mc.exe` tentou interpretar o JSON e falhou no primeiro byte não-ASCII:

```
mc.exe: <ERROR> Unable to create new policy:
invalid character 'ï' looking for beginning of value.
```

A solução foi usar a ferramenta `Write` do Claude Code para criar o arquivo, que produz UTF-8 sem BOM — compatível com o parser JSON do `mc`.

---

## Resultado dos Smoke Tests

| # | Passo | Teste | Status | Dados |
|---|---|---|---|---|
| 6 | Login | `POST /auth/login` | ✅ OK | `expires_in=3600s` |
| 7 | Criar licenciamento | `POST /licenciamentos` | ✅ OK | `id=6, status=RASCUNHO` |
| 8 | Upload PDF | `POST /arquivos/upload` | ✅ OK | `arquivoId=2, tamanho=301B` |
| 9 | Listar arquivos | `GET /licenciamentos/6/arquivos` | ✅ OK | `1 arquivo(s)` |
| 10 | URL pré-assinada | `GET /arquivos/2/download-url` | ✅ OK | URL MinIO gerada (1h) |
| 11 | Submeter | `POST /licenciamentos/6/submeter` | ✅ OK | `status=ANALISE_PENDENTE` |
| 12 | Verificar status | `GET /licenciamentos/6` | ✅ OK | `ANALISE_PENDENTE confirmado` |
| 13 | Limpeza | `sqlplus DELETE` | ✅ OK | Oracle limpo |

**Todos os 8 smoke tests passaram na execução final.**

---

## Estado Final do Sistema

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SOL Backend v1.0.0                          │
│                    (Spring Boot 3.3.4, Java 21)                     │
├─────────────────────────────────────────────────────────────────────┤
│  Serviço Windows: SOL-Backend        Status: RUNNING                │
│  JAR: C:\SOL\backend\target\sol-backend-1.0.0.jar                  │
│  URL: http://localhost:8080/api                                      │
│  MinIO SDK: 8.5.17 (atualizado nesta sprint)                        │
├─────────────────────────────────────────────────────────────────────┤
│  ENDPOINTS DISPONÍVEIS                                               │
│                                                                      │
│  [PUBLIC]   GET  /health                                             │
│  [PUBLIC]   POST /auth/login                                         │
│  [PUBLIC]   POST /auth/refresh                                       │
│  [PUBLIC]   POST /cadastro/rt                                        │
│  [PUBLIC]   POST /cadastro/ru                                        │
│                                                                      │
│  [AUTH]     GET  /auth/me                                            │
│  [AUTH]     POST /auth/logout                                        │
│  [AUTH]     POST /licenciamentos         (CIDADAO/RT/ADMIN)          │
│  [AUTH]     GET  /licenciamentos/{id}                                │
│  [AUTH]     POST /licenciamentos/{id}/submeter                       │
│  [AUTH]     GET  /licenciamentos/{id}/arquivos                       │
│  [AUTH]     POST /arquivos/upload                                    │
│  [AUTH]     GET  /arquivos/{id}/download-url                         │
│  [AUTH]     GET  /arquivos/{id}/download                             │
│  [AUTH]     DELETE /arquivos/{id}                                    │
│  [ADMIN]    GET  /licenciamentos (paginado)                          │
│  [ADMIN]    GET  /usuarios                                           │
│  [SWAGGER]  GET  /swagger-ui/index.html                              │
├─────────────────────────────────────────────────────────────────────┤
│  MINIO                                                               │
│  Servidor: 2025-09-07T16:13:09Z    localhost:9000   ✅              │
│  Bucket: sol-arquivos (+ sol-appci, sol-guias, sol-laudos, ...)     │
│  Policy sol-app-policy: GetBucketLocation, ListBucket, Get/Put/     │
│                         Delete, AbortMultipart, ListMultipart        │
├─────────────────────────────────────────────────────────────────────┤
│  PRÓXIMAS SPRINTS                                                    │
│                                                                      │
│  Sprint 5: Análise do licenciamento (CIA, deferimento) — P04/P05    │
│  Sprint 6: Vistoria e emissão de APPCI — P06/P07                    │
│  Sprint 7: Geração de PDF (iText 5) e boleto — P08/P09              │
│  Sprint N: Integração SEI (Outbox Pattern)                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

*Relatório gerado automaticamente pelo Claude Code em 2026-03-28.*
*Script base: `Y:\infra\scripts\sprint4-deploy.ps1` (`\\CBM-QCG-238\SOL`)*
*Documentos relacionados: [[Sprint-1-Diario-Completo]], [[Sprint-2-Diario-Completo]], [[Sprint-3-Diario-Completo]]*
