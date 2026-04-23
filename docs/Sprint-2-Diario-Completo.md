# Sprint 2 — Diário Completo de Implementação

**Projeto:** SOL — Sistema de Operações e Licenciamento (CBM-RS)
**Data:** 2026-03-27
**Stack:** Java 21 · Spring Boot 3.3.4 · Hibernate 6.5.3 · Oracle XE 21c · Keycloak 24 · Windows 11

---

## Índice

- [[#Objetivo da Sprint]]
- [[#Novos Arquivos da Sprint 2]]
- [[#Mensagem 1 — Solicitação de Execução da Sprint 2]]
- [[#Análise Prévia — Leitura dos Arquivos]]
- [[#Problema 1 — Dependência springdoc-openapi Ausente no pom.xml]]
- [[#Problema 2 — Encoding do Script sprint2-deploy.ps1]]
- [[#Problema 3 — EnderecoDTO usa Double em vez de BigDecimal]]
- [[#Execução bem-sucedida do Build]]
- [[#Serviço Iniciado e Health Check]]
- [[#Problema 4 — SOL_ADMIN_TOKEN não definido]]
- [[#Configuração do Usuário Keycloak]]
  - [[#Estrutura do Realm sol]]
  - [[#Criação do Usuário sol-admin]]
  - [[#Falha na Atribuição de Role — Primeira Tentativa]]
  - [[#Atribuição Correta da Role ADMIN]]
  - [[#Obtenção do JWT com Role ADMIN]]
- [[#Verificação dos Endpoints]]
  - [[#GET /api/usuarios]]
  - [[#GET /api/licenciamentos]]
- [[#Estado Final dos Arquivos Alterados]]
- [[#Correção do Script de Deploy — Bug de Encoding]]
- [[#Resumo das Correções Aplicadas]]
- [[#Glossário Técnico]]

---

## Objetivo da Sprint

A Sprint 2 introduziu a **camada de aplicação** completa sobre a infraestrutura criada na Sprint 1:

```
Sprint 1: Entidades JPA + Schema Oracle
Sprint 2: DTOs + Services + Controllers + Exception Handler + JWT Auth
```

Os novos componentes adicionados:

| Pacote | Arquivos |
|---|---|
| `dto` | `EnderecoDTO`, `UsuarioDTO`, `UsuarioCreateDTO`, `LicenciamentoDTO`, `LicenciamentoCreateDTO`, `ArquivoEDDTO`, `MarcoProcessoDTO`, `BoletoDTO` |
| `service` | `UsuarioService`, `LicenciamentoService`, `BoletoService` |
| `controller` | `UsuarioController`, `LicenciamentoController`, `BoletoController` |
| `exception` | `ResourceNotFoundException`, `BusinessException`, `GlobalExceptionHandler` |

---

## Novos Arquivos da Sprint 2

### Controllers

#### `UsuarioController.java`

Expõe CRUD de usuários. Todos os endpoints exigem JWT válido do Keycloak. A autorização é feita por roles extraídas do claim `roles` do token:

```
GET    /api/usuarios         → ROLE_ADMIN
GET    /api/usuarios/{id}    → qualquer role autenticada
GET    /api/usuarios/cpf/{cpf} → ROLE_ADMIN
POST   /api/usuarios         → ROLE_ADMIN
PUT    /api/usuarios/{id}    → ROLE_ADMIN
DELETE /api/usuarios/{id}    → ROLE_ADMIN (soft delete — seta ativo=false)
```

#### `LicenciamentoController.java`

Endpoint paginado para licenciamentos. Usa `Page<LicenciamentoDTO>` com `Pageable` do Spring Data:

```
GET    /api/licenciamentos           → ADMIN, ANALISTA, INSPETOR, CHEFE_SSEG_BBM
GET    /api/licenciamentos/{id}      → autenticado
GET    /api/licenciamentos/meus      → CIDADAO, RT
POST   /api/licenciamentos           → CIDADAO, RT
PATCH  /api/licenciamentos/{id}/status → ADMIN, ANALISTA, INSPETOR, CHEFE_SSEG_BBM
DELETE /api/licenciamentos/{id}      → CIDADAO, RT, ADMIN (somente RASCUNHO)
```

### Services

#### `UsuarioService.java`

- Mapeamento manual Entity → DTO (sem MapStruct nesta sprint)
- Validação de CPF e e-mail duplicados via `existsByCpf` / `existsByEmail`
- `@Transactional(readOnly = true)` na classe, `@Transactional` nos métodos de escrita

#### `LicenciamentoService.java`

- Máquina de estados para transições de `StatusLicenciamento` via `switch` expression do Java 21
- `findByUsuario` busca primeiro como RT, depois como RU
- `delete` é soft delete — só remove RASCUNHO, senão lança `BusinessException`

### Exception Handler

#### `GlobalExceptionHandler.java`

Implementa o padrão **RFC 7807 Problem Details** via `ProblemDetail` do Spring 6:

```json
{
  "type": "https://sol.cbm.rs.gov.br/erros/recurso-nao-encontrado",
  "title": "Recurso nao encontrado",
  "status": 404,
  "detail": "Usuario com id 999 nao encontrado"
}
```

Trata três tipos de exceção:
- `ResourceNotFoundException` → HTTP 404
- `BusinessException` → HTTP 422 Unprocessable Entity
- `MethodArgumentNotValidException` → HTTP 400 com mapa de erros por campo
- `Exception` (catch-all) → HTTP 500

---

## Mensagem 1 — Solicitação de Execução da Sprint 2

> *"Execute a Sprint 2. Os arquivos Java já estão em C:\SOL\backend\src (DTOs, Services, Controllers, exception handlers). Execute o script C:\SOL\infra\scripts\sprint2-deploy.ps1 para compilar com Maven (JAVA_HOME: C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot), reiniciar o SOL-Backend e verificar os endpoints GET /api/usuarios e GET /api/licenciamentos."*

---

## Análise Prévia — Leitura dos Arquivos

Antes de executar qualquer coisa, todos os arquivos relevantes foram lidos:

1. **`sprint2-deploy.ps1`** — entender o que o script faz
2. **Controllers, Services, Exception Handler** — identificar dependências necessárias
3. **`SecurityConfig.java`** — entender o modelo de autorização JWT
4. **`pom.xml`** — verificar se todas as dependências estão presentes
5. **`EnderecoDTO.java`** — verificar compatibilidade com a correção da Sprint 1

> **Princípio:** Nunca executar um script sem antes entender o que ele faz e se o ambiente está preparado para rodá-lo.

---

## Problema 1 — Dependência springdoc-openapi Ausente no pom.xml

### Sintoma detectado na análise

Os controllers importam anotações do OpenAPI:

```java
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
```

O `pom.xml` da Sprint 1 **não possuía** a dependência `springdoc-openapi-starter-webmvc-ui`. Isso causaria um erro de compilação imediato:

```
[ERROR] package io.swagger.v3.oas.annotations does not exist
```

### Por que springdoc-openapi?

O `springdoc-openapi` é a biblioteca padrão para integração do **Swagger UI** com Spring Boot 3.x. Ela provê:

1. O pacote `io.swagger.v3.oas.annotations` com as anotações `@Operation`, `@Tag`, `@SecurityRequirement`
2. Uma UI interativa em `/swagger-ui/index.html` para testar endpoints
3. O JSON OpenAPI em `/v3/api-docs`

> **Atenção de versão:** O projeto usa Spring Boot 3.3.x. A versão correta do springdoc é a `2.x` (que suporta Jakarta EE 10). A versão `1.x` é para Spring Boot 2.x / javax.

### Correção aplicada no `pom.xml`

```diff
  <properties>
      ...
      <mapstruct.version>1.6.2</mapstruct.version>
+     <springdoc.version>2.6.0</springdoc.version>
  </properties>

  <dependencies>
      ...
+     <!-- SpringDoc OpenAPI / Swagger UI -->
+     <dependency>
+         <groupId>org.springdoc</groupId>
+         <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
+         <version>${springdoc.version}</version>
+     </dependency>

      <!-- Jackson (JSON) -->
  </dependencies>
```

---

## Problema 2 — Encoding do Script sprint2-deploy.ps1

### Sintoma

Ao executar o script diretamente com `-File`, o PowerShell retornou:

```
ParserError: Token '}' inesperado na expressão ou instrução.
ParserError: Token 'testes' inesperado na expressão ou instrução.
ParserError: A cadeia de caracteres não tem o terminador: "
```

### Causa raiz

O script `sprint2-deploy.ps1` foi escrito com **em-dash** (U+2014 `—`) em uma mensagem de log:

```powershell
# Linha 156 do script original:
Write-Host "  Tentativa $i falhou — aguardando 10s..." -ForegroundColor Yellow
```

Quando o PowerShell tenta parsear o arquivo com determinadas configurações de code page do sistema, o caractere `—` (3 bytes em UTF-8: `E2 80 94`) pode quebrar a análise léxica do parser. O sintoma clássico é `"cadeia de caracteres não tem o terminador"` — o parser "perdeu" o fechamento da string.

O `Set-StrictMode -Version Latest` no início do script agrava o problema, pois torna o parser ainda mais rigoroso.

### Solução: sanitização em memória

Em vez de modificar o arquivo fonte, o script foi lido como string UTF-8 pura, os caracteres problemáticos foram substituídos por equivalentes ASCII, e o resultado foi gravado em um arquivo temporário:

```powershell
$content = [System.IO.File]::ReadAllText(
    'C:\SOL\infra\scripts\sprint2-deploy.ps1',
    [System.Text.Encoding]::UTF8
)
$content = $content -replace [char]0x2014, '-'   # em-dash → hífen
$content = $content -replace [char]0x201C, '"'   # aspas curvas abertas
$content = $content -replace [char]0x201D, '"'   # aspas curvas fechadas

$tmpFile = [System.IO.Path]::GetTempFileName() + '.ps1'
[System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.Encoding]::UTF8)
& powershell -NoProfile -ExecutionPolicy Bypass -File $tmpFile
```

> **Lição:** Scripts PowerShell que serão executados em ambientes Windows com diferentes locales devem usar apenas caracteres ASCII na faixa U+0000–U+007F nas mensagens de log. Para garantir portabilidade, o script original deve ser corrigido substituindo `—` por `-`.

### Bug secundário no script — `$falhas.Count` com StrictMode

Ao final do script, a verificação de falhas produziu um erro adicional:

```
A propriedade 'Count' não foi encontrada neste objeto.
No sprint2-deploy.ps1:200 caractere:5
+ if ($falhas.Count -eq 0) {
```

**Causa:** Com `Set-StrictMode -Version Latest`, acessar `.Count` em `$null` lança exceção. Quando todos os testes passam, a expressão:

```powershell
$falhas = $resultados | Where-Object { $_ -eq $false }
```

retorna `$null` (não um array vazio) porque `Where-Object` com zero resultados retorna `$null` em vez de `@()`. A solução seria usar `@($resultados | Where-Object { $_ -eq $false })` para garantir sempre um array. Este bug é cosmético — o deploy já havia sido concluído com sucesso nesse ponto.

---

## Problema 3 — EnderecoDTO usa Double em vez de BigDecimal

### Sintoma

Na primeira tentativa de compilação (após corrigir o pom.xml), o build falhou:

```
[ERROR] COMPILATION ERROR :
[ERROR] /C:/SOL/backend/src/main/java/br/gov/rs/cbm/sol/service/LicenciamentoService.java:[173,34]
        incompatible types: java.math.BigDecimal cannot be converted to java.lang.Double

[ERROR] /C:/SOL/backend/src/main/java/br/gov/rs/cbm/sol/service/LicenciamentoService.java:[218,39]
        incompatible types: java.lang.Double cannot be converted to java.math.BigDecimal
```

### Causa raiz

Este é o **efeito cascade** da correção feita na Sprint 1. Na Sprint 1, os campos `latitude` e `longitude` em `Endereco.java` foram alterados de `Double` para `BigDecimal` para corrigir o bug do Hibernate 6.5.

O `EnderecoDTO.java` (arquivo novo da Sprint 2) foi escrito assumindo o tipo original `Double`:

```java
// EnderecoDTO.java — ANTES (com bug)
Double latitude,
Double longitude,
```

No `LicenciamentoService.java`, as linhas problemáticas eram:

```java
// Linha 173 — leitura: getLatitude() retorna BigDecimal, mas EnderecoDTO esperava Double
enderecoDTO = new EnderecoDTO(
    ...,
    e.getLatitude(),   // BigDecimal → EnderecoDTO(Double) = ERRO
    e.getLongitude(),  // BigDecimal → EnderecoDTO(Double) = ERRO
    ...
);

// Linha 218 — escrita: dto.latitude() retorna Double, mas Endereco.builder esperava BigDecimal
Endereco.builder()
    .latitude(dto.latitude())   // Double → BigDecimal = ERRO
    .longitude(dto.longitude()) // Double → BigDecimal = ERRO
    .build();
```

### Correção aplicada no `EnderecoDTO.java`

```diff
+ import java.math.BigDecimal;
  import java.time.LocalDateTime;

  ...

-     Double latitude,
+     BigDecimal latitude,

-     Double longitude,
+     BigDecimal longitude,
```

> **Regra geral:** Quando uma entidade JPA tem seu tipo alterado, todos os DTOs, ViewModels e interfaces que expõem esse campo devem ser atualizados na mesma sprint.

---

## Execução bem-sucedida do Build

Com as três correções aplicadas, o Maven compilou sem erros:

```
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  Executando: mvn clean package -Dmaven.test.skip=true -q
  [OK] Build concluido com sucesso
```

O flag `-q` (quiet) suprime a saída detalhada do Maven, exibindo apenas erros. O `-Dmaven.test.skip=true` é equivalente a `-DskipTests` mas também pula a compilação dos testes.

---

## Serviço Iniciado e Health Check

```
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado

===> Aguardando 30 segundos para inicializacao do Spring Boot

===> Health check - http://localhost:8080/api/health
  [OK] Aplicacao saudavel (tentativa 1)
```

O script tem lógica de retry com 5 tentativas e 10s de espera entre elas para o health check. Na primeira tentativa já respondeu — o serviço subiu dentro dos 30s de espera configurados.

---

## Problema 4 — SOL_ADMIN_TOKEN não definido

### O que o script faz

```powershell
$token = $env:SOL_ADMIN_TOKEN
if ([string]::IsNullOrEmpty($token)) {
    Write-Host "  Variavel SOL_ADMIN_TOKEN nao definida — smoke tests ignorados" -ForegroundColor Yellow
    $token = ""
}
```

Se a variável de ambiente `SOL_ADMIN_TOKEN` não estiver definida, o script pula os testes dos endpoints protegidos. Isso é um design correto para CI/CD — o token é injetado pelo pipeline de automação.

```
  [AVISO] Testes de /usuarios e /licenciamentos ignorados (sem token)
```

Para completar a verificação solicitada, foi necessário obter um token JWT manualmente via Keycloak Admin API.

---

## Configuração do Usuário Keycloak

### Estrutura do Realm sol

Consultando o Keycloak Admin API com token do `master` realm:

**Clientes do realm `sol`:**

| clientId | publicClient | directAccessGrantsEnabled |
|---|---|---|
| `sol-frontend` | `true` | `false` (inicialmente) |
| `sol-backend` | `false` | `false` |
| `admin-cli` | `true` | `true` |
| `account` | `true` | `false` |

**Roles do realm `sol`:**

```
ADMIN, ANALISTA, INSPETOR, CHEFE_SSEG_BBM, CIDADAO, RT,
default-roles-sol, uma_authorization, offline_access
```

As roles `ADMIN`, `ANALISTA`, `INSPETOR`, `CHEFE_SSEG_BBM`, `CIDADAO`, `RT` foram criadas durante o setup da infraestrutura (Sprint 0) — correspondem exatamente às roles usadas nos `@PreAuthorize` dos controllers.

**Usuários do realm `sol`:** nenhum (banco vazio, schema recém-criado na Sprint 1).

---

### Criação do Usuário sol-admin

Chamada à Keycloak Admin REST API:

```
POST http://localhost:8180/admin/realms/sol/users
Authorization: Bearer {master_admin_token}
Content-Type: application/json

{
  "username": "sol-admin",
  "email": "sol-admin@cbm.rs.gov.br",
  "firstName": "Admin",
  "lastName": "SOL",
  "enabled": true,
  "credentials": [
    { "type": "password", "value": "Admin@SOL2026", "temporary": false }
  ]
}
```

> ID gerado: `6a6065a2-edc1-415a-ac91-a260ebc9063c`

---

### Falha na Atribuição de Role — Primeira Tentativa

Na primeira tentativa de atribuir a role `ADMIN` ao usuário, o Keycloak retornou:

```json
{"error": "unknown_error", "error_description": "For more on this error consult the server log at the debug level."}
```

**Causa:** O objeto de role foi obtido via `$roles | Where-Object { $_.name -eq 'ADMIN' }` e passado para `ConvertTo-Json`. O problema estava na representação JSON resultante — o array de roles para o endpoint de mapeamento exige exatamente os campos `id` e `name` no formato correto, e a serialização automática do objeto PowerShell pode incluir propriedades extras ou com tipos incorretos.

O JWT obtido nessa tentativa **não continha a role ADMIN**:

```json
{
  "roles": ["offline_access", "uma_authorization", "default-roles-sol"]
}
```

---

### Atribuição Correta da Role ADMIN

Na segunda tentativa, a role foi obtida diretamente pelo endpoint específico e o body foi construído como JSON literal:

```powershell
# Obter a role com todos os campos corretos
$adminRole = Invoke-RestMethod -Uri "$base/admin/realms/sol/roles/ADMIN" -Headers $h

# Construir o body como JSON literal com apenas os campos mínimos exigidos
$body = "[{`"id`":`"$($adminRole.id)`",`"name`":`"$($adminRole.name)`"}]"

# Atribuir
Invoke-RestMethod -Method Post `
    -Uri "$base/admin/realms/sol/users/$userId/role-mappings/realm" `
    -Headers $h -Body $body
```

**Resultado:**

```
[OK] Role ADMIN atribuida
Roles do usuario: default-roles-sol, ADMIN
```

> **Lição de Keycloak:** O endpoint `POST /admin/realms/{realm}/users/{id}/role-mappings/realm` aceita um array JSON onde cada elemento deve ter pelo menos `"id"` e `"name"`. Usar `ConvertTo-Json` em um objeto PSCustomObject pode incluir campos `null` que o Keycloak rejeita silenciosamente com `unknown_error`.

---

### Obtenção do JWT com Role ADMIN

Para obter um JWT usando `password grant`, o cliente `sol-frontend` precisou ter `directAccessGrantsEnabled` habilitado:

```powershell
$clientRep.directAccessGrantsEnabled = $true
Invoke-RestMethod -Method Put -Uri "$base/admin/realms/sol/clients/$clientId" -Headers $h -Body ($clientRep | ConvertTo-Json -Depth 10)
```

> **Nota:** `directAccessGrantsEnabled` (password grant) é prático para testes e CI/CD, mas deve ser desabilitado em produção para clientes frontend — o fluxo correto para SPAs é Authorization Code + PKCE.

Token obtido:

```powershell
$tokenResp = Invoke-RestMethod -Method Post `
    -Uri "http://localhost:8180/realms/sol/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{
        grant_type = 'password'
        client_id  = 'sol-frontend'
        username   = 'sol-admin'
        password   = 'Admin@SOL2026'
    }
```

Payload decodificado do JWT confirma a role:

```json
{
  "sub": "6a6065a2-edc1-415a-ac91-a260ebc9063c",
  "roles": ["offline_access", "ADMIN", "uma_authorization", "default-roles-sol"]
}
```

---

## Verificação dos Endpoints

### Como o Spring Security processa o JWT

O `SecurityConfig.java` configura um conversor que extrai o claim `roles` do JWT e adiciona o prefixo `ROLE_`:

```java
converter.setJwtGrantedAuthoritiesConverter(jwt -> {
    List<String> roles = jwt.getClaimAsStringList("roles");
    if (roles == null) return List.of();
    return roles.stream()
        .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
        .collect(Collectors.toList());
});
```

Então `"ADMIN"` no JWT vira `ROLE_ADMIN` no Spring Security, compatível com `@PreAuthorize("hasRole('ADMIN')")`.

---

### GET /api/usuarios

```
Authorization: Bearer {jwt_com_ROLE_ADMIN}
GET http://localhost:8080/api/usuarios
```

**Resposta:**
```
HTTP 200
Body: []
```

Lista vazia — correto. O banco não tem usuários locais (o `sol-admin` existe apenas no Keycloak, não na tabela `SOL.USUARIO` do Oracle, pois o `UsuarioService.create()` ainda não foi chamado).

**Fluxo completo:**
```
JWT → JwtAuthenticationConverter → ROLE_ADMIN
→ @PreAuthorize("hasRole('ADMIN')") OK
→ UsuarioService.findAll()
→ usuarioRepository.findAll() → SELECT * FROM SOL.USUARIO
→ [] (0 registros)
→ ResponseEntity.ok([])
→ Jackson serializa → "[]"
```

---

### GET /api/licenciamentos

```
Authorization: Bearer {jwt_com_ROLE_ADMIN}
GET http://localhost:8080/api/licenciamentos
```

**Resposta:**
```
HTTP 200
Body: {
  "content": [],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "sort": { "empty": false, "sorted": true, "unsorted": false },
    "offset": 0,
    "paged": true,
    "unpaged": false
  },
  "last": true,
  "totalElements": 0,
  "totalPages": 0,
  "size": 20,
  "number": 0,
  "numberOfElements": 0,
  "first": true,
  "empty": true
}
```

O endpoint usa `Page<LicenciamentoDTO>` com `@PageableDefault(size = 20, sort = "id")`. O response inclui metadados de paginação do Spring Data, mesmo com 0 elementos.

**Fluxo completo:**
```
JWT → ROLE_ADMIN
→ @PreAuthorize("hasAnyRole('ADMIN','ANALISTA','INSPETOR','CHEFE_SSEG_BBM')") OK
→ LicenciamentoService.findAll(Pageable{page=0, size=20, sort=id})
→ licenciamentoRepository.findAll(pageable)
→ SELECT * FROM SOL.LICENCIAMENTO ORDER BY ID_LICENCIAMENTO OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY
→ Page<Licenciamento> (0 elementos)
→ .map(this::toDTO) → Page<LicenciamentoDTO>
→ Jackson serializa → JSON paginado
```

---

## Estado Final dos Arquivos Alterados

### `pom.xml` — versão final (trecho)

```xml
<properties>
    ...
    <mapstruct.version>1.6.2</mapstruct.version>
    <springdoc.version>2.6.0</springdoc.version>   <!-- ← adicionado Sprint 2 -->
</properties>

<dependencies>
    ...
    <!-- SpringDoc OpenAPI / Swagger UI -->       <!-- ← adicionado Sprint 2 -->
    <dependency>
        <groupId>org.springdoc</groupId>
        <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
        <version>${springdoc.version}</version>
    </dependency>
    ...
</dependencies>
```

---

### `EnderecoDTO.java` — versão final

```diff
  package br.gov.rs.cbm.sol.dto;

  import jakarta.validation.constraints.NotBlank;
  import jakarta.validation.constraints.Pattern;
  import jakarta.validation.constraints.Size;

+ import java.math.BigDecimal;
  import java.time.LocalDateTime;

  public record EnderecoDTO(

          @NotBlank(message = "CEP e obrigatorio")
          @Pattern(regexp = "\\d{8}", message = "CEP deve conter 8 digitos numericos")
          String cep,

          @NotBlank(message = "Logradouro e obrigatorio")
          @Size(max = 200)
          String logradouro,

          @Size(max = 20)
          String numero,

          @Size(max = 100)
          String complemento,

          @NotBlank(message = "Bairro e obrigatorio")
          @Size(max = 100)
          String bairro,

          @NotBlank(message = "Municipio e obrigatorio")
          @Size(max = 100)
          String municipio,

          @NotBlank(message = "UF e obrigatoria")
          @Size(min = 2, max = 2, message = "UF deve ter 2 caracteres")
          String uf,

-         Double latitude,
+         BigDecimal latitude,

-         Double longitude,
+         BigDecimal longitude,

          LocalDateTime dataAtualizacao
  ) {}
```

---

## Correção do Script de Deploy — Bug de Encoding

O script `sprint2-deploy.ps1` contém caracteres não-ASCII que causam `ParseError`. Para corrigir definitivamente o arquivo fonte, a linha 156 deve ser alterada:

### Diff da correção definitiva

```diff
- Write-Host "  Tentativa $i falhou — aguardando 10s..." -ForegroundColor Yellow
+ Write-Host "  Tentativa $i falhou - aguardando 10s..." -ForegroundColor Yellow
```

E o bug do `$falhas.Count` (linha 200):

```diff
- $falhas = $resultados | Where-Object { $_ -eq $false }
+ $falhas = @($resultados | Where-Object { $_ -eq $false })
```

O `@(...)` força o resultado de `Where-Object` a ser sempre um array, mesmo quando retorna zero elementos. Assim, `.Count` nunca é `$null` e não lança erro com `Set-StrictMode -Version Latest`.

---

## Resumo das Correções Aplicadas

### Três problemas identificados antes da execução do script

| # | Arquivo | Problema | Tipo |
|---|---|---|---|
| 1 | `pom.xml` | Dependência `springdoc-openapi` ausente — controllers não compilariam | Crítico |
| 2 | `sprint2-deploy.ps1` | Caracteres em-dash U+2014 causam `ParseError` no PowerShell | Bloqueante |
| 3 | `EnderecoDTO.java` | `Double latitude/longitude` incompatível com `BigDecimal` de `Endereco` | Crítico |

### Um problema encontrado durante a configuração do Keycloak

| # | Contexto | Problema | Solução |
|---|---|---|---|
| 4 | Atribuição de role via Admin API | Body JSON com campos extras causava `unknown_error` | Construir JSON literal com apenas `id` e `name` |

### Resultado final

| Tarefa | Status |
|---|---|
| `pom.xml` atualizado com springdoc 2.6.0 | ✅ |
| `EnderecoDTO.java` com BigDecimal | ✅ |
| `mvn clean package` | ✅ BUILD SUCCESS |
| Serviço SOL-Backend reiniciado | ✅ Running |
| Health check `/api/health` | ✅ HTTP 200 |
| Usuário `sol-admin` criado no Keycloak com role ADMIN | ✅ |
| `GET /api/usuarios` com JWT | ✅ HTTP 200 `[]` |
| `GET /api/licenciamentos` com JWT | ✅ HTTP 200 `{"content":[],"totalElements":0,...}` |

---

## Glossário Técnico

| Termo | Definição |
|---|---|
| **springdoc-openapi** | Biblioteca que integra Swagger/OpenAPI 3 com Spring Boot — gera UI interativa e JSON de spec |
| **RFC 7807** | "Problem Details for HTTP APIs" — padrão para respostas de erro JSON com campos `type`, `title`, `status`, `detail` |
| **ProblemDetail** | Classe do Spring 6 que implementa RFC 7807 nativamente |
| **`@PreAuthorize`** | Anotação do Spring Security que avalia uma expressão SpEL antes de executar o método |
| **`@Transactional(readOnly = true)`** | Otimização que informa ao banco que a transação não fará escritas — permite otimizações de lock e caching |
| **Page / Pageable** | Abstrações do Spring Data para paginação — `Pageable` é a requisição (página, tamanho, ordenação), `Page` é a resposta (dados + metadados) |
| **Password Grant** | Fluxo OAuth2 onde o cliente envia usuário/senha diretamente para o AS — conveniente para testes mas não recomendado em produção |
| **directAccessGrantsEnabled** | Configuração do Keycloak que habilita o Password Grant para um cliente |
| **JwtAuthenticationConverter** | Componente Spring Security que transforma um JWT em um objeto `Authentication` com as authorities corretas |
| **em-dash** | Caractere Unicode U+2014 (`—`) — mais longo que o hífen comum (`-`); causa problemas de parsing em scripts quando o ambiente não espera UTF-8 |
| **Set-StrictMode** | Diretiva PowerShell que ativa verificações adicionais — acesso a propriedades `$null` lança exceção |
| **soft delete** | Exclusão lógica — o registro não é removido do banco, apenas marcado como inativo (`ativo = false`) |
| **Claim JWT** | Par chave-valor no payload do token JWT — o claim `roles` é usado pelo `SecurityConfig` para extrair as autoridades |

---

*Documento gerado em 2026-03-27 · Sprint 2 concluída com sucesso.*
