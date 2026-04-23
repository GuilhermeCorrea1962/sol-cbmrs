# Sprint 3 — Diário Completo de Execução

**Projeto:** SOL — Sistema Online de Licenciamento do CBM-RS
**Data de execução:** 2026-03-28
**Sprint:** 3 de N
**Responsável:** Guilherme
**Executor (IA):** Claude Code (claude-sonnet-4-6)
**Script base:** `C:\SOL\infra\scripts\sprint3-deploy.ps1`

---

## Índice

- [[#Contexto da Sprint 3]]
- [[#Arquivos Java Entregues]]
- [[#Análise Prévia ao Deploy]]
  - [[#Bug Detectado — Senha Incorreta no Script de Deploy]]
  - [[#Verificação do Direct Access Grants]]
- [[#Correções Aplicadas Antes do Deploy]]
- [[#Execução do Script sprint3-deploy.ps1]]
  - [[#Passo 1 — Parada do Serviço]]
  - [[#Passo 2 — Compilação Maven]]
  - [[#Passo 3 — Reinício do Serviço]]
  - [[#Passo 4 — Aguardo de Inicialização]]
  - [[#Passo 5 — Health Check]]
  - [[#Passo 6 — Smoke Test P01 — POST /auth/login]]
  - [[#Passo 7 — Smoke Test P01 — GET /auth/me]]
  - [[#Passo 8 — Smoke Test P01 — POST /auth/refresh]]
  - [[#Passo 9 — Smoke Test P02 — POST /cadastro/rt]]
  - [[#Passo 10 — Verificação no Banco Oracle]]
  - [[#Passo 11 — Limpeza do Usuário de Teste]]
  - [[#Passo 12 — Smoke Test P01 — POST /auth/logout]]
  - [[#Passo 13 — Resultado Final]]
- [[#Saída Completa do Script]]
- [[#Arquitetura Implementada na Sprint 3]]
  - [[#AuthController e AuthService — Fluxo P01]]
  - [[#CadastroController e CadastroService — Fluxo P02]]
  - [[#KeycloakAdminService]]
  - [[#SecurityConfig — Rotas Públicas e Extração de Roles]]
  - [[#KeycloakConfig — Configuração do Admin Client]]
- [[#Dependências Adicionadas]]
- [[#Resultado dos Smoke Tests]]
- [[#Problemas Detectados e Soluções]]
- [[#Estado Final do Sistema]]

---

## Contexto da Sprint 3

A Sprint 3 do projeto SOL implementou os dois primeiros fluxos de negócio que envolvem identidade de usuários:

- **P01 — Autenticação:** login via Keycloak ROPC (Resource Owner Password Credentials), refresh de token, endpoint `/auth/me` e logout com revogação de sessão.
- **P02 — Cadastro:** registro de Responsável Técnico (RT) e Responsável pelo Uso (RU/Cidadão) com criação simultânea no banco Oracle local e no realm `sol` do Keycloak.

As Sprints 1 e 2 já haviam entregue a infraestrutura completa (Oracle XE, Keycloak, MinIO, Nginx), a camada de entidades JPA, repositórios, DTOs, serviços base e os primeiros controllers (`UsuarioController`, `LicenciamentoController`, `BoletoController`).

A Sprint 3 acrescentou:

| Arquivo novo | Responsabilidade |
|---|---|
| `AuthController.java` | Endpoints `/auth/*` — proxy para o Keycloak |
| `AuthService.java` | Lógica ROPC: login, refresh, logout, me |
| `CadastroController.java` | Endpoints `/cadastro/rt` e `/cadastro/ru` |
| `CadastroService.java` | Saga simplificada: Oracle + Keycloak em consistência eventual |
| `KeycloakAdminService.java` | Wraper do Keycloak Admin Client para CRUD de usuários |
| `KeycloakConfig.java` | Bean `Keycloak` autenticado no master realm |
| `LoginRequestDTO.java` | DTO de entrada para o login |
| `TokenResponseDTO.java` | DTO que mapeia a resposta de token do Keycloak |
| `UserInfoDTO.java` | DTO retornado pelo `/auth/me` |

---

## Arquivos Java Entregues

Os arquivos foram disponibilizados em `C:\SOL\backend\src` antes do início da Sprint. A estrutura completa do projeto no momento do deploy era:

```
C:\SOL\backend\src\main\java\br\gov\rs\cbm\sol\
├── SolApplication.java
├── config\
│   ├── KeycloakConfig.java          ← NOVO Sprint 3
│   ├── MinioConfig.java
│   └── SecurityConfig.java          ← ATUALIZADO Sprint 3
├── controller\
│   ├── AuthController.java          ← NOVO Sprint 3
│   ├── BoletoController.java
│   ├── CadastroController.java      ← NOVO Sprint 3
│   ├── HealthController.java
│   ├── LicenciamentoController.java
│   └── UsuarioController.java
├── dto\
│   ├── ArquivoEDDTO.java
│   ├── BoletoDTO.java
│   ├── EnderecoDTO.java
│   ├── LicenciamentoCreateDTO.java
│   ├── LicenciamentoDTO.java
│   ├── LoginRequestDTO.java         ← NOVO Sprint 3
│   ├── MarcoProcessoDTO.java
│   ├── TokenResponseDTO.java        ← NOVO Sprint 3
│   ├── UserInfoDTO.java             ← NOVO Sprint 3
│   ├── UsuarioCreateDTO.java
│   └── UsuarioDTO.java
├── entity\ [...]
├── exception\ [...]
├── repository\ [...]
└── service\
    ├── AuthService.java             ← NOVO Sprint 3
    ├── BoletoService.java
    ├── CadastroService.java         ← NOVO Sprint 3
    ├── KeycloakAdminService.java    ← NOVO Sprint 3
    ├── LicenciamentoService.java
    └── UsuarioService.java
```

---

## Análise Prévia ao Deploy

Antes de executar qualquer script, foi realizada uma leitura completa dos arquivos críticos para detectar problemas que pudessem inviabilizar o deploy ou os smoke tests.

### Bug Detectado — Senha Incorreta no Script de Deploy

**Arquivo:** `C:\SOL\infra\scripts\sprint3-deploy.ps1`
**Linha:** 147

Ao comparar o script de deploy com o script de setup do usuário de teste (`setup-test-user.ps1`), foi identificada uma divergência de capitalização na senha do usuário `sol-admin`:

| Arquivo | Valor da senha |
|---|---|
| `setup-test-user.ps1` linha 26 | `Admin@SOL2026` |
| `setup-test-user.ps1` linha 68 | `Admin@SOL2026` |
| `sprint3-deploy.ps1` linha 147 | `Admin@Sol2026` ← **INCORRETO** |

A diferença é `SOL` (maiúsculo) versus `Sol` (misto). Senhas no Keycloak são case-sensitive. Se o script fosse executado sem essa correção, o smoke test P01 falharia imediatamente com HTTP 401 (`invalid_grant`) no endpoint `POST /auth/login`, interrompendo todos os testes subsequentes.

**Impacto sem a correção:**

```
===> Smoke test P01 -- POST /auth/login
  [FALHA] Login falhou: Response status code does not indicate success: 401 (Unauthorized).
  [AVISO] Verifique se o usuario sol-admin existe no realm sol e se Direct Access Grants
          esta habilitado no client sol-frontend
```

O script encerraria com `exit 1` nesse ponto, sem executar P02.

### Verificação do Direct Access Grants

O pré-requisito documentado no cabeçalho do `sprint3-deploy.ps1` (linhas 18-19) exige que o client `sol-frontend` no realm `sol` tenha o atributo `directAccessGrantsEnabled = true`.

Esse atributo foi habilitado na Sprint 2 via `setup-test-user.ps1`, mas como uma boa prática e por ser pré-requisito explícito da Sprint 3, o estado foi verificado e reconfirmado via Keycloak Admin API antes do deploy:

```
Client UUID localizado: 31b4d123-8d2b-45fa-91b6-da0906971541
directAccessGrantsEnabled atual: True
PUT aplicado com sucesso
Verificação pós-PUT: directAccessGrantsEnabled = true ✓
```

**Por que esse atributo é necessário?**

O fluxo ROPC (Resource Owner Password Credentials) — usado pelo `AuthService` no backend — é um grant type do OAuth 2.0 onde o cliente envia diretamente o username e a senha do usuário final para o endpoint de token do Keycloak (`/realms/sol/protocol/openid-connect/token`). O Keycloak só aceita esse grant type se o client que está fazendo a requisição tiver `directAccessGrantsEnabled = true`. Sem isso, o Keycloak retorna `unauthorized_client` mesmo com credenciais corretas.

---

## Correções Aplicadas Antes do Deploy

### Correção 1 — Senha no sprint3-deploy.ps1

**Arquivo:** `C:\SOL\infra\scripts\sprint3-deploy.ps1`
**Tipo:** Correção de bug (typo de capitalização)

```diff
- username = "sol-admin"; password = "Admin@Sol2026"
+ username = "sol-admin"; password = "Admin@SOL2026"
```

**Justificativa:** A senha `Admin@SOL2026` foi definida em `setup-test-user.ps1` durante a Sprint 2. O `sprint3-deploy.ps1` foi escrito com `Admin@Sol2026`, diferença que passa despercebida visualmente mas causa falha de autenticação. A correção garante que o smoke test P01 consiga obter um token JWT válido.

### Correção 2 — Habilitação do Direct Access Grants

**Tipo:** Pré-requisito de infraestrutura (via Keycloak Admin API)

Executado via PowerShell antes do script de deploy:

```powershell
# 1. Obter token admin do master realm
$masterToken = (Invoke-RestMethod -Method Post `
    -Uri "http://localhost:8180/realms/master/protocol/openid-connect/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type='password'; client_id='admin-cli';
             username='admin'; password='Keycloak@Admin2026' }
).access_token

$h = @{ Authorization = "Bearer $masterToken"; 'Content-Type' = 'application/json' }

# 2. Localizar UUID do client sol-frontend
$clients = Invoke-RestMethod `
    -Uri "http://localhost:8180/admin/realms/sol/clients?clientId=sol-frontend" `
    -Headers $h
$clientUUID = $clients[0].id   # 31b4d123-8d2b-45fa-91b6-da0906971541

# 3. Ler representação atual e setar flag
$clientRep = Invoke-RestMethod `
    -Uri "http://localhost:8180/admin/realms/sol/clients/$clientUUID" `
    -Headers $h
$clientRep.directAccessGrantsEnabled = $true

# 4. PUT com representação completa
Invoke-RestMethod -Method Put `
    -Uri "http://localhost:8180/admin/realms/sol/clients/$clientUUID" `
    -Headers $h `
    -Body ($clientRep | ConvertTo-Json -Depth 20 -Compress)

# 5. Verificação
$verify = Invoke-RestMethod `
    -Uri "http://localhost:8180/admin/realms/sol/clients/$clientUUID" `
    -Headers $h
# $verify.directAccessGrantsEnabled == $true ✓
```

**Justificativa do PUT com representação completa:** A Keycloak Admin REST API exige que o body do `PUT /admin/realms/{realm}/clients/{id}` contenha a representação **completa** do client, não apenas os campos alterados (não é um PATCH parcial). Enviar apenas `{ "directAccessGrantsEnabled": true }` resultaria na zeragem de todos os outros atributos do client. Por isso é necessário: (1) fazer GET para obter o objeto completo, (2) alterar apenas o campo desejado, (3) fazer PUT com o objeto inteiro.

---

## Execução do Script sprint3-deploy.ps1

O script foi executado via:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SOL\infra\scripts\sprint3-deploy.ps1"
```

A flag `-ExecutionPolicy Bypass` é necessária no ambiente Windows do CBM-RS pois a política de execução padrão pode bloquear scripts não assinados. `-NoProfile` evita que o perfil pessoal do PowerShell interfira nas variáveis de ambiente configuradas pelo script.

---

### Passo 1 — Parada do Serviço

**Saída:**
```
===> Parando servico SOL-Backend
  [OK] Servico parado
```

**O que aconteceu:** O script verificou se o serviço Windows `SOL-Backend` existia e estava em execução (`Get-Service`). Como estava rodando (iniciado na Sprint 2), executou `Stop-Service -Force` e aguardou 5 segundos para garantir que o processo Java liberou o JAR e as portas.

**Por que é necessário parar antes de compilar/reinstalar?**

No Windows, o JVM mantém o arquivo JAR aberto enquanto o serviço está ativo. Se o Maven tentasse sobrescrever `sol-backend-1.0.0.jar` com o arquivo em uso, o build falharia com `Access denied` ou `The process cannot access the file because it is being used by another process`. A parada antecipada garante que o Maven pode sobrescrever o JAR livremente.

---

### Passo 2 — Compilação Maven

**Saída:**
```
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso
```

**O que aconteceu:**

1. O script definiu `$env:JAVA_HOME` e adicionou o `bin` do JDK 21 no `$env:PATH` da sessão corrente.
2. Verificou se existia `mvnw.cmd` (Maven Wrapper) em `C:\SOL\backend\`. Existindo, usou-o; caso contrário, usaria o `mvn` global.
3. Executou `mvnw.cmd clean package -Dmaven.test.skip=true -q`:
   - `clean`: removeu o diretório `target/` anterior, garantindo um build limpo sem artefatos de sprints anteriores.
   - `package`: compilou todo o código-fonte, processou anotações (Lombok + MapStruct via `maven-compiler-plugin`), gerou o JAR executável em `target/sol-backend-1.0.0.jar`.
   - `-Dmaven.test.skip=true`: pulou a execução dos testes unitários (a validação funcional é feita pelos smoke tests do próprio script).
   - `-q` (quiet): suprimiu logs de INFO do Maven, exibindo apenas erros.

**Dependências novas compiladas na Sprint 3:**

- `keycloak-admin-client:24.0.3` — biblioteca cliente para a Keycloak Admin REST API, usada pelo `KeycloakAdminService` para criar usuários e atribuir roles programaticamente.
- Todas as demais dependências já estavam presentes no `pom.xml` desde as sprints anteriores.

---

### Passo 3 — Reinício do Serviço

**Saída:**
```
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
```

**O que aconteceu:** Como o serviço Windows `SOL-Backend` existia (foi parado no Passo 1), o script executou `Start-Service`. O serviço está configurado para executar o novo JAR em `C:\SOL\backend\target\sol-backend-1.0.0.jar` com o perfil Spring `prod`.

**Caminho alternativo (modo dev):** Se o serviço não existisse (ambiente de desenvolvimento sem o NSSM instalado), o script iniciaria o JAR diretamente com `Start-Process java.exe -jar ...`, exibindo `[AVISO] Servico nao registrado -- JAR iniciado diretamente (modo dev)`. Esse caminho não foi acionado.

---

### Passo 4 — Aguardo de Inicialização

**Saída:** *(silencioso — apenas aguarda)*
```
===> Aguardando 30 segundos para inicializacao do Spring Boot
```

**O que aconteceu:** `Start-Sleep -Seconds 30`. O Spring Boot com Hibernate (validação do schema Oracle), Spring Security (download do JWKS do Keycloak na inicialização), e MinIO (verificação de buckets) leva entre 15 e 25 segundos para estar completamente funcional. Os 30 segundos garantem margem de segurança.

**Por que o Spring Security demora mais na Sprint 3?** Na inicialização, o `spring-boot-starter-oauth2-resource-server` faz uma requisição HTTP para `http://localhost:8180/realms/sol/.well-known/openid-configuration` para obter o `jwks_uri` e faz um segundo GET para `http://localhost:8180/realms/sol/protocol/openid-connect/certs` para baixar as chaves públicas de verificação de JWT. Se o Keycloak estiver lento, essa fase pode atrasar a inicialização.

---

### Passo 5 — Health Check

**Saída:**
```
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
```

**O que aconteceu:** O script tentou até 5 vezes (com intervalo de 10s entre tentativas) fazer `GET http://localhost:8080/api/health`. Na primeira tentativa obteve HTTP 200, confirmando que o Spring Boot estava completamente inicializado e respondendo.

**Endpoint `/health`:** implementado pelo `HealthController`, declarado como público no `SecurityConfig` (`.requestMatchers("/health", "/actuator/health").permitAll()`). Retorna `{"status":"UP"}` sem exigir autenticação.

---

### Passo 6 — Smoke Test P01 — POST /auth/login

**Saída:**
```
===> Smoke test P01 -- POST /auth/login
  [OK] Login OK -- access_token obtido (expira em 3600s)
```

**Body enviado:**
```json
{
  "username": "sol-admin",
  "password": "Admin@SOL2026"
}
```

**O que aconteceu internamente:**

```
Script  ──POST──►  AuthController.login()
                       │
                   AuthService.login()
                       │
                   RestTemplate POST ──► Keycloak
                   /realms/sol/protocol/openid-connect/token
                   [grant_type=password, client_id=sol-frontend,
                    username=sol-admin, password=Admin@SOL2026, scope=openid]
                       │
                   Keycloak valida credenciais e retorna
                   { access_token, refresh_token, expires_in: 3600, ... }
                       │
                   AuthService retorna TokenResponseDTO
                       │
                   AuthController retorna HTTP 200
```

O `access_token` é um JWT assinado com RS256 pelo Keycloak. O `expires_in: 3600` indica validade de 1 hora. O `refresh_token` tem validade de 30 minutos (configuração padrão do realm `sol`).

**Por que o script capturou `$tokenResponse.expires_in`?** Para validar que o campo está presente e com valor coerente, confirmando que o `TokenResponseDTO` mapeou corretamente todos os campos da resposta do Keycloak com as anotações `@JsonProperty`.

---

### Passo 7 — Smoke Test P01 — GET /auth/me

**Saída:**
```
===> Smoke test P01 -- GET /auth/me
  [OK] /auth/me OK -- keycloakId=6a6065a2-edc1-415a-ac91-a260ebc9063c
                      roles=offline_access,ADMIN,uma_authorization,default-roles-sol
```

**O que aconteceu internamente:**

```
Script  ──GET──►  AuthController.me(@AuthenticationPrincipal Jwt jwt)
                      │
                  O Spring Security intercepta a requisição:
                  1. Extrai o Bearer token do header Authorization
                  2. Verifica assinatura RS256 usando as chaves públicas do Keycloak (JWKS)
                  3. Valida issuer (http://localhost:8180/realms/sol), exp, nbf
                  4. Injeta o Jwt no parâmetro do método
                      │
                  AuthService.me(jwt)
                  1. Extrai sub (keycloakId) = "6a6065a2-..."
                  2. Extrai claim "roles" = ["offline_access","ADMIN","uma_authorization","default-roles-sol"]
                  3. Tenta encontrar o usuário local pelo keycloakId
                     → sol-admin foi criado diretamente no Keycloak, não tem registro Oracle
                  4. Fallback: retorna UserInfoDTO com dados dos claims JWT
                      │
                  HTTP 200: { id: null, keycloakId: "6a6065a2-...", nome: "Admin SOL",
                               email: "sol-admin@cbm.rs.gov.br", tipoUsuario: null,
                               roles: ["offline_access","ADMIN",...] }
```

**Observação sobre o fallback:** O `sol-admin` foi criado diretamente no Keycloak pelo `setup-test-user.ps1`, sem registro correspondente na tabela `SOL.USUARIO` do Oracle. O `AuthService.me()` trata esse cenário: ao não encontrar o usuário por `keycloakId` no banco local, retorna um `UserInfoDTO` populado apenas com os dados do JWT (nome e e-mail extraídos dos claims `name` e `email`). O campo `id` retorna `null`, o que é esperado e correto para usuários administrativos do Keycloak.

---

### Passo 8 — Smoke Test P01 — POST /auth/refresh

**Saída:**
```
===> Smoke test P01 -- POST /auth/refresh
  [OK] Refresh OK -- novo access_token obtido
```

**O que aconteceu:** O `refresh_token` obtido no Passo 6 foi enviado para `POST /auth/refresh?refreshToken=<valor>`. O `AuthService.refresh()` repassou para o Keycloak com `grant_type=refresh_token`, obtendo um novo par `access_token` / `refresh_token`. O script substituiu o token corrente pelo novo para os testes subsequentes.

**Por que testar o refresh?** O fluxo ROPC emite tokens de curta duração. Em produção, o Angular chamará `/auth/refresh` automaticamente antes de cada requisição quando o token estiver próximo de expirar. Validar esse endpoint no deploy garante que o `client_id` está correto e que o Keycloak aceita o grant type `refresh_token` para o client `sol-frontend`.

---

### Passo 9 — Smoke Test P02 — POST /cadastro/rt

**Saída:**
```
===> Smoke test P02 -- POST /cadastro/rt
  [OK] RT criado -- id=1 keycloakId=ce513485-a0a6-4538-a168-ac8b599882af
```

**Body enviado:**
```json
{
  "cpf": "00000000191",
  "nome": "RT Smoke Test Sprint3",
  "email": "rt.teste.sprint3@sol.cbm.rs.gov.br",
  "telefone": "51900000000",
  "tipoUsuario": "RT",
  "senha": "Sprint3@Teste2026",
  "numeroRegistro": "CREA-RS 999999",
  "tipoConselho": "CREA",
  "especialidade": "Engenharia Civil"
}
```

**O que aconteceu internamente:**

```
Script  ──POST──►  CadastroController.registrarRT()
                       │
                   CadastroService.registrar()  [@Transactional]
                   │
                   ├─ 1. UsuarioService.create()
                   │      • Verifica CPF 00000000191 — não existe → OK
                   │      • Verifica email — não existe → OK
                   │      • INSERT INTO SOL.USUARIO
                   │        (cpf, nome, email, telefone, tipo_usuario,
                   │         status_cadastro='INCOMPLETO', numero_registro,
                   │         tipo_conselho, especialidade, ativo=true)
                   │      • Retorna UsuarioDTO com id=1, keycloakId=null
                   │
                   ├─ 2. KeycloakAdminService.createUser()
                   │      • UserRepresentation: username=00000000191,
                   │        email=rt.teste..., firstName="RT Smoke Test Sprint3"
                   │      • CredentialRepresentation: password=Sprint3@Teste2026, temporary=false
                   │      • POST /admin/realms/sol/users → HTTP 201
                   │      • Location: .../users/ce513485-a0a6-4538-a168-ac8b599882af
                   │      • keycloakId = "ce513485-..."
                   │      • assignRealmRole(realmResource, "ce513485-...", "RT")
                   │        GET /admin/realms/sol/roles/RT → RoleRepresentation
                   │        POST /admin/realms/sol/users/ce513485-.../role-mappings/realm
                   │
                   ├─ 3. UPDATE SOL.USUARIO SET keycloak_id='ce513485-...' WHERE id_usuario=1
                   │
                   └─ 4. Retorna UsuarioDTO com id=1, keycloakId='ce513485-...'
                              │
                   CadastroController retorna HTTP 201 Created
                   Location: http://localhost:8080/api/usuarios/1
```

**Por que `status_cadastro = INCOMPLETO`?** A Sprint 3 implementa apenas o registro inicial do RT. Nas sprints seguintes, o RT precisará completar seu perfil (upload de documentos, validação de conselho profissional) para ter o status promovido a `ATIVO`. O status `INCOMPLETO` indica que o usuário existe no sistema mas ainda não pode submeter licenciamentos.

**Estratégia de consistência (Saga simplificada):** Como o Oracle e o Keycloak são sistemas distintos, não é possível envolvê-los em uma única transação ACID. A estratégia adotada foi:

1. O `@Transactional` do Spring envolve apenas o Oracle.
2. A chamada ao Keycloak ocorre dentro do contexto transacional mas **antes do commit**.
3. Se o Keycloak falhar, a exceção propaga → Spring faz rollback do INSERT Oracle → consistência mantida.
4. Se o INSERT Oracle falhar **após** o Keycloak ter criado o usuário → `deleteUser()` é chamado como compensação (rollback manual do Keycloak).
5. O único caso sem compensação automática é falha após o commit Oracle e antes do retorno ao controller (janela de milissegundos) — aceitável para o MVP.

---

### Passo 10 — Verificação no Banco Oracle

**Saída:**
```
===> Verificando usuario RT no banco -- GET /api/usuarios/1
  [OK] Usuario local verificado -- cpf=00000000191 status=INCOMPLETO
```

**O que aconteceu:** O script fez `GET /api/usuarios/1` com o Bearer token do `sol-admin` (que tem role `ADMIN`, autorizada pelo `UsuarioController`). Confirmou que:
- O registro existe no Oracle com `id_usuario = 1`
- O CPF `00000000191` foi persistido corretamente
- O `status_cadastro` é `INCOMPLETO`, conforme esperado para um RT recém-registrado
- O `keycloakId` foi preenchido (`ce513485-...`), confirmando que o Passo 3 do `CadastroService` (UPDATE) foi executado

---

### Passo 11 — Limpeza do Usuário de Teste

**Saída:**
```
===> Limpeza -- removendo usuario de teste
  [OK] Usuario removido do Keycloak (ce513485-a0a6-4538-a168-ac8b599882af)
  [OK] Usuario removido do Oracle (id=1)
```

**O que aconteceu:**

**Keycloak:**
```powershell
# Novo token de admin do master realm
$masterToken = Get-MasterToken

# DELETE /admin/realms/sol/users/ce513485-a0a6-4538-a168-ac8b599882af
Invoke-RestMethod `
    -Uri "http://localhost:8180/admin/realms/sol/users/ce513485-..." `
    -Method DELETE `
    -Headers @{ Authorization = "Bearer $masterToken" }
```

**Oracle (via sqlplus):**
```sql
DELETE FROM sol.usuario WHERE id_usuario = 1;
COMMIT;
EXIT;
```

O arquivo SQL temporário foi criado em `$env:TEMP`, executado via `sqlplus -S "/ as sysdba"` e removido após a execução (`Remove-Item -Force`).

**Por que limpar?** O CPF `00000000191` e o e-mail `rt.teste.sprint3@sol.cbm.rs.gov.br` são fixos no script. Sem limpeza, a segunda execução do deploy falharia no Passo 9 com `BusinessException("RN-002", "CPF já cadastrado no sistema")` ao tentar inserir o mesmo CPF novamente.

---

### Passo 12 — Smoke Test P01 — POST /auth/logout

**Saída:**
```
===> Smoke test P01 -- POST /auth/logout
  [OK] Logout OK -- sessao encerrada
```

**O que aconteceu:** `POST /auth/logout?refreshToken=<valor>` com o refresh token original (do Passo 6, não o renovado no Passo 8). O `AuthService.logout()` enviou ao Keycloak:

```
POST /realms/sol/protocol/openid-connect/logout
Body: client_id=sol-frontend&refresh_token=<valor>
```

O Keycloak revogou a sessão associada ao refresh token. Tentativas futuras de usar esse refresh token para obter novos access tokens retornarão HTTP 400 `invalid_grant`.

**Nota sobre o access_token:** O JWT de acesso permanece válido até seu `exp` (1 hora). O logout no Keycloak ROPC **não invalida o access_token** — isso é uma limitação inerente ao padrão JWT stateless. Em produção, o Angular deve descartar o token localmente ao fazer logout. Para revogação imediata de access_token em produção, seria necessário implementar um token blacklist (Redis) — ponto de backlog para sprints futuras.

---

### Passo 13 — Resultado Final

**Saída:**
```
===> Sprint 3 concluida

  Fluxos verificados:
    P01 -- Login (ROPC), refresh, /me, logout
    P02 -- Cadastro RT (local + Keycloak)

  Deploy da Sprint 3 concluido com sucesso!
```

O script encerrou com `exit 0` (código de saída zero = sucesso).

---

## Saída Completa do Script

A seguir a saída integral do `sprint3-deploy.ps1` conforme exibida no terminal:

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

===> Smoke test P01 -- POST /auth/login
  [OK] Login OK -- access_token obtido (expira em 3600s)

===> Smoke test P01 -- GET /auth/me
  [OK] /auth/me OK -- keycloakId=6a6065a2-edc1-415a-ac91-a260ebc9063c roles=offline_access,ADMIN,uma_authorization,default-roles-sol

===> Smoke test P01 -- POST /auth/refresh
  [OK] Refresh OK -- novo access_token obtido

===> Smoke test P02 -- POST /cadastro/rt
  [OK] RT criado -- id=1 keycloakId=ce513485-a0a6-4538-a168-ac8b599882af

===> Verificando usuario RT no banco -- GET /api/usuarios/1
  [OK] Usuario local verificado -- cpf=00000000191 status=INCOMPLETO

===> Limpeza -- removendo usuario de teste
  [OK] Usuario removido do Keycloak (ce513485-a0a6-4538-a168-ac8b599882af)
  [OK] Usuario removido do Oracle (id=1)

===> Smoke test P01 -- POST /auth/logout
  [OK] Logout OK -- sessao encerrada

===> Sprint 3 concluida

  Fluxos verificados:
    P01 -- Login (ROPC), refresh, /me, logout
    P02 -- Cadastro RT (local + Keycloak)

  Deploy da Sprint 3 concluido com sucesso!
```

---

## Arquitetura Implementada na Sprint 3

### AuthController e AuthService — Fluxo P01

O `AuthController` expõe quatro endpoints no path `/auth`:

| Método | Path | Autenticação | Descrição |
|---|---|---|---|
| `POST` | `/auth/login` | Pública | Recebe `LoginRequestDTO`, retorna `TokenResponseDTO` |
| `POST` | `/auth/refresh` | Pública | Recebe `refreshToken` como query param, retorna novo `TokenResponseDTO` |
| `POST` | `/auth/logout` | Bearer JWT | Revoga `refreshToken` no Keycloak, retorna HTTP 204 |
| `GET` | `/auth/me` | Bearer JWT | Retorna `UserInfoDTO` com dados do JWT + banco local |

O `AuthService` atua como **Backend-for-Frontend (BFF)**: o Angular não comunica diretamente com o Keycloak — toda a troca de tokens passa pelo backend SOL. Isso centraliza a lógica de autenticação e evita que o `client_secret` (se existisse) ficasse exposto no frontend.

**Padrão ROPC e suas implicações:**

O Resource Owner Password Credentials é considerado legado no OAuth 2.1 (substituído pelo Authorization Code Flow com PKCE). No contexto do SOL CBM-RS, seu uso é adequado porque:

1. A aplicação é um sistema interno de governo, não um marketplace OAuth com múltiplos authorization servers.
2. O backend age como intermediário — o `refresh_token` nunca é exposto diretamente ao JavaScript do browser.
3. Testes automatizados de CI/CD exigem login sem interação humana (redirect flow é inviável em automação).

### CadastroController e CadastroService — Fluxo P02

O `CadastroController` expõe dois endpoints em `/cadastro`:

| Método | Path | Autenticação | Descrição |
|---|---|---|---|
| `POST` | `/cadastro/rt` | Pública | Registra Responsável Técnico |
| `POST` | `/cadastro/ru` | Pública | Registra Responsável pelo Uso / Cidadão |

Ambos recebem `UsuarioCreateDTO` e delegam para `CadastroService.registrar()`. A diferença entre RT e RU está no campo `tipoUsuario` do DTO (`"RT"` ou `"CIDADAO"`), que determina a role atribuída no Keycloak e os campos obrigatórios de negócio (validados em sprints futuras).

O `CadastroService` implementa uma **Saga simplificada de dois passos**:

```
[ Oracle INSERT ]  ──────────────────────────────────────────────────────────┐
      │                                                                        │
      ▼                                                                        │ @Transactional
[ Keycloak createUser() ]                                                      │
      │                                                                        │
      ├── Sucesso ──► [ Oracle UPDATE keycloak_id ] ──► COMMIT ───────────────┘
      │
      └── Falha ──► BusinessException("KC-002") ──► ROLLBACK Oracle (automático)
                                                          │
                                                    (Keycloak não chegou a criar
                                                     o usuário neste caso)

Caso especial: INSERT Oracle OK + Keycloak OK + UPDATE keycloak_id FALHA
      └──► ROLLBACK Oracle (automático) + deleteUser() no Keycloak (compensação manual)
```

### KeycloakAdminService

Wrapper sobre o `keycloak-admin-client` (biblioteca oficial Keycloak para Java). Autentica no realm `master` com as credenciais do `admin-cli` configuradas em `application.yml`. Expõe:

- `createUser()`: cria o usuário e atribui a role em sequência
- `assignRealmRole()`: atribui realm role a um usuário existente
- `deleteUser()`: remove usuário (compensação de saga)
- `resetPassword()`: redefine senha (P02 — "esqueci minha senha", próximas sprints)
- `setEnabled()`: habilita/desabilita usuário (P12 — suspensão de licenciamento)

A extração do `keycloakId` após a criação é feita pelo header `Location` da resposta HTTP 201:

```java
String location = response.getHeaderString("Location");
// Ex: http://localhost:8180/admin/realms/sol/users/ce513485-a0a6-4538-a168-ac8b599882af
String keycloakId = location.substring(location.lastIndexOf('/') + 1);
// ce513485-a0a6-4538-a168-ac8b599882af
```

### SecurityConfig — Rotas Públicas e Extração de Roles

Atualizada na Sprint 3 para liberar os novos endpoints:

```java
.authorizeHttpRequests(auth -> auth
    .requestMatchers("/health", "/actuator/health").permitAll()
    .requestMatchers("/auth/login", "/auth/refresh").permitAll()      // NOVO
    .requestMatchers("/cadastro/rt", "/cadastro/ru").permitAll()      // NOVO
    .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
    .anyRequest().authenticated())
```

O JWT converter extrai roles do claim personalizado `"roles"` (configurado no Keycloak como protocol mapper no realm `sol`) e adiciona o prefixo `ROLE_` para compatibilidade com `@PreAuthorize("hasRole('ADMIN')")`:

```java
converter.setJwtGrantedAuthoritiesConverter(jwt -> {
    List<String> roles = jwt.getClaimAsStringList("roles");
    return roles.stream()
        .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
        .collect(Collectors.toList());
});
```

**Por que o claim é `"roles"` e não `"realm_access.roles"`?** O Keycloak por padrão coloca as realm roles em `realm_access.roles` (objeto aninhado). O realm `sol` foi configurado na Sprint 2 com um protocol mapper do tipo `User Realm Role` que publica as roles diretamente em `"roles"` (claim de nível raiz), simplificando o código de extração no Spring Security.

### KeycloakConfig — Configuração do Admin Client

```java
@Bean
public Keycloak keycloakAdminClient() {
    return KeycloakBuilder.builder()
            .serverUrl("http://localhost:8180")
            .realm("master")                  // Admin sempre autentica no master
            .clientId("admin-cli")            // Client público do master realm
            .username("admin")
            .password("Keycloak@Admin2026")
            .build();
}
```

O bean é `singleton` por padrão no Spring — uma única instância do client gerencia um pool de conexões HTTP para todas as chamadas ao Keycloak Admin API durante o ciclo de vida da aplicação.

---

## Dependências Adicionadas

A Sprint 3 não adicionou novas dependências ao `pom.xml` além das já previstas desde o início do projeto:

```xml
<!-- Já presente no pom.xml desde Sprint 0 -->
<dependency>
    <groupId>org.keycloak</groupId>
    <artifactId>keycloak-admin-client</artifactId>
    <version>24.0.3</version>
</dependency>
```

Todas as demais dependências necessárias (`spring-boot-starter-oauth2-resource-server`, `spring-boot-starter-security`, `spring-boot-starter-web`) já faziam parte do `pom.xml` original.

---

## Resultado dos Smoke Tests

| # | Teste | Endpoint | Resultado | Observação |
|---|---|---|---|---|
| 6 | P01 Login | `POST /auth/login` | ✅ OK | `expires_in=3600s` |
| 7 | P01 Me | `GET /auth/me` | ✅ OK | keycloakId + 4 roles no JWT |
| 8 | P01 Refresh | `POST /auth/refresh` | ✅ OK | Novo access_token obtido |
| 9 | P02 Cadastro RT | `POST /cadastro/rt` | ✅ OK | `id=1`, `keycloakId=ce513485-...` |
| 10 | P02 Verificação | `GET /usuarios/1` | ✅ OK | `cpf=00000000191`, `status=INCOMPLETO` |
| 11a | Limpeza Keycloak | DELETE via Admin API | ✅ OK | Usuario removido |
| 11b | Limpeza Oracle | `sqlplus DELETE` | ✅ OK | Linha removida e committed |
| 12 | P01 Logout | `POST /auth/logout` | ✅ OK | Sessão revogada |

**Todos os 8 smoke tests passaram sem falhas ou avisos.**

---

## Problemas Detectados e Soluções

### Problema 1 — Typo de capitalização na senha do `sol-admin`

| Atributo | Valor |
|---|---|
| **Arquivo afetado** | `C:\SOL\infra\scripts\sprint3-deploy.ps1`, linha 147 |
| **Tipo** | Bug de regressão — typo introduzido na escrita do script |
| **Severidade** | Crítica — causaria falha imediata com `exit 1` no smoke test P01 |
| **Causa raiz** | A senha `Admin@SOL2026` (todo caps em "SOL") foi digitada como `Admin@Sol2026` (mixed case) no script de deploy, enquanto o `setup-test-user.ps1` usa consistentemente `Admin@SOL2026` |
| **Detecção** | Análise prévia comparando os dois scripts antes de executar o deploy |
| **Solução** | Correção direta no arquivo com `Edit` antes de executar o script |
| **Correção aplicada** | `password = "Admin@Sol2026"` → `password = "Admin@SOL2026"` |

### Problema 2 — Necessidade de confirmar Direct Access Grants

| Atributo | Valor |
|---|---|
| **Arquivo afetado** | Configuração do Keycloak (não é código-fonte) |
| **Tipo** | Pré-requisito de infraestrutura explicitado no cabeçalho do script |
| **Severidade** | Crítica — sem `directAccessGrantsEnabled=true`, o fluxo ROPC retorna `unauthorized_client` |
| **Estado encontrado** | `directAccessGrantsEnabled = true` (já havia sido habilitado na Sprint 2) |
| **Solução** | Verificação e reconfirmação via Keycloak Admin API (GET + PUT idempotente) |
| **Resultado** | Confirmado ativo. O passo foi executado de forma idempotente — se já estivesse habilitado, o PUT não causava efeito colateral |

---

## Estado Final do Sistema

Após o deploy da Sprint 3, o sistema SOL CBM-RS está no seguinte estado:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SOL Backend v1.0.0                          │
│                    (Spring Boot 3.3.4, Java 21)                     │
├─────────────────────────────────────────────────────────────────────┤
│  Serviço Windows: SOL-Backend        Status: RUNNING                │
│  JAR: C:\SOL\backend\target\sol-backend-1.0.0.jar                  │
│  URL: http://localhost:8080/api                                      │
│  Log: C:\SOL\logs\sol-backend.log                                   │
├─────────────────────────────────────────────────────────────────────┤
│  ENDPOINTS DISPONÍVEIS                                               │
│                                                                      │
│  [PUBLIC]  GET  /health                                              │
│  [PUBLIC]  POST /auth/login                                          │
│  [PUBLIC]  POST /auth/refresh                                        │
│  [PUBLIC]  POST /cadastro/rt                                         │
│  [PUBLIC]  POST /cadastro/ru                                         │
│  [SWAGGER] GET  /swagger-ui/index.html                              │
│                                                                      │
│  [ADMIN]   GET  /usuarios                                            │
│  [ADMIN]   GET  /usuarios/{id}                                       │
│  [BEARER]  GET  /auth/me                                             │
│  [BEARER]  POST /auth/logout                                         │
│  [PAGINADO] GET /licenciamentos  (ADMIN/ANALISTA/INSPETOR/CHEFE)    │
├─────────────────────────────────────────────────────────────────────┤
│  INFRAESTRUTURA                                                      │
│                                                                      │
│  Oracle XE 21c   localhost:1521/XEPDB1   schema: SOL   ✅           │
│  Keycloak 24     localhost:8180           realm: sol    ✅           │
│  MinIO           localhost:9000                         ✅           │
│  Nginx           localhost:80                           ✅           │
├─────────────────────────────────────────────────────────────────────┤
│  PRÓXIMAS SPRINTS                                                    │
│                                                                      │
│  Sprint 4: Submissão de Licenciamento (P03/P04)                     │
│  Sprint 5: Upload de documentos para MinIO (P05)                    │
│  Sprint 6: Geração de boleto e PDF (P06/P07)                        │
│  Sprint N: Integração SEI (Outbox Pattern)                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

*Relatório gerado automaticamente pelo Claude Code em 2026-03-28.*
*Script base: `C:\SOL\infra\scripts\sprint3-deploy.ps1`*
*Documentos relacionados: [[Sprint-1-Diario-Completo]], [[Sprint-2-Diario-Completo]]*
