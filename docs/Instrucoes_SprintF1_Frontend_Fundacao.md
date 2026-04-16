# Sprint F1 — Frontend Foundation: Instrucoes de Execucao

**Sistema:** SOL — Sistema Online de Licenciamento | CBM-RS
**Sprint:** F1 (primeira sprint frontend)
**Data:** 2026-04-02
**Servidor destino:** `C:\SOL\` (acessivel remotamente via `Y:\`)

---

## Visao Geral

A Sprint F1 estabelece a **fundacao completa do frontend Angular** sobre a qual todas as sprints seguintes (F2–F9) serao construidas. Ela nao entrega funcionalidades de negocio visiveis ao usuario final, mas disponibiliza a estrutura tecnica sem a qual nenhuma outra tela poderia existir: autenticacao, controle de acesso por perfil, layout com sidebar e toolbar, e o pipeline de build + deploy automatizado.

---

## Arquivos produzidos pela Sprint F1

### Novos arquivos Angular

| Arquivo | Descricao |
|---|---|
| `src/app/core/services/auth.service.ts` | Servico central de autenticacao: encapsula OAuthService, extrai roles do JWT |
| `src/app/core/guards/auth.guard.ts` | Guard de rota: redireciona para /login se nao houver token valido |
| `src/app/core/guards/role.guard.ts` | Guard de perfil (RBAC): libera acesso por role declarado na rota |
| `src/app/layout/shell/shell.component.ts` | Layout principal: sidebar escura + toolbar vermelha + router-outlet |
| `src/app/shared/components/loading/loading.component.ts` | Spinner de carregamento reutilizavel (overlay semi-transparente) |
| `src/app/shared/components/error-alert/error-alert.component.ts` | Alerta de erro inline reutilizavel (banner com botao de fechar) |
| `src/app/pages/dashboard/dashboard.component.ts` | Painel inicial com cards filtrados pelo perfil do usuario logado |
| `src/app/pages/not-found/not-found.component.ts` | Pagina 404 com botao de retorno ao painel |

### Arquivos modificados

| Arquivo | Mudanca |
|---|---|
| `src/app/app.routes.ts` | Estrutura completa de rotas: shell autenticado, guards, placeholders F2–F9 |
| `src/app/app.config.ts` | Adicionado Material 18, animacoes asincronas; removido hash routing |
| `src/app/app.component.ts` | Navegacao automatica para `/app/dashboard` apos login bem-sucedido |
| `src/styles.scss` | Tema Angular Material M3 com paleta CBM-RS (vermelho #cc0000) |
| `package.json` | Adicionado `@angular/material@18` e `@angular/cdk@18` |
| `src/app/pages/home/home.component.ts` | Simplificado: redireciona para dashboard ou login conforme estado |

### Scripts de infraestrutura

| Arquivo | Descricao |
|---|---|
| `infra/nginx/nginx.conf` | Configuracao Nginx Sprint F1: cache de assets, headers de seguranca, keepalive backend |
| `infra/scripts/sync-frontend-to-server.ps1` | Sincroniza arquivos da maquina local (C:\SOL) para o servidor (Y:\) corretamente |
| `infra/scripts/sprint-f1-deploy.ps1` | Deploy completo no servidor: npm install, build Angular, atualiza Nginx, verifica HTTP |

---

## Sequencia de execucao

A Sprint F1 e executada em dois momentos distintos: primeiro na **maquina local** (sincronizacao dos arquivos), depois no **servidor** (build e deploy).

```
Maquina local                          Servidor (C:\SOL = Y:\)
      |                                        |
      |-- sync-frontend-to-server.ps1 -------> |  (copia arquivos corretamente)
      |                                        |
      |                         sprint-f1-deploy.ps1
      |                                        |-- npm install
      |                                        |-- ng build --configuration production
      |                                        |-- atualiza nginx.conf
      |                                        |-- reinicia SOL-Nginx
      |                                        |-- verifica HTTP 200
```

---

## Passo 1 — Sincronizar arquivos para o servidor

### Script: `sync-frontend-to-server.ps1`

**Onde executar:** maquina local (nao no servidor)

```powershell
cd C:\SOL\infra\scripts
powershell -ExecutionPolicy Bypass -File sync-frontend-to-server.ps1
```

**Por que este script existe:**
O mapeamento de rede Y:\ aponta para C:\SOL no servidor. Ao tentar copiar diretorios inteiros usando `Copy-Item -Recurse` com um destino ja existente, o PowerShell cria uma subpasta com o mesmo nome dentro do destino (ex: `layout\layout\shell\` em vez de `layout\shell\`). O script `sync-frontend-to-server.ps1` evita esse comportamento copiando **cada arquivo individualmente** para o caminho exato, apos criar a estrutura de diretorios necessaria.

**O que o script faz, passo a passo:**

1. **Verifica acesso ao servidor** — testa se `Y:\frontend` esta acessivel antes de qualquer operacao.

2. **Remove pastas duplicadas** — verifica e remove eventuais subpastas aninhadas incorretamente (`layout\layout\`, `pages\dashboard\dashboard\`, etc.) que possam ter sido criadas por copias anteriores.

3. **Cria estrutura de diretorios** — cria no servidor todos os diretorios necessarios:
   - `src/app/core/services/`
   - `src/app/core/guards/`
   - `src/app/layout/shell/`
   - `src/app/shared/components/loading/`
   - `src/app/shared/components/error-alert/`
   - `src/app/pages/dashboard/`
   - `src/app/pages/not-found/`

4. **Copia cada arquivo individualmente** — transfere todos os arquivos novos e modificados da Sprint F1 da maquina local para o servidor, arquivo por arquivo, garantindo que cada um va para o caminho correto.

5. **Exibe o comando de deploy** — ao final, mostra o comando exato a executar no servidor para iniciar o build.

**O que esperar:**
```
[OK] Servidor acessivel: Y:\frontend
[OK] Removido: Y:\frontend\src\app\layout\layout   (se existia)
[OK] src\app\core\services\auth.service.ts
[OK] src\app\core\guards\auth.guard.ts
[OK] src\app\core\guards\role.guard.ts
[OK] src\app\layout\shell\shell.component.ts
[OK] src\app\shared\components\loading\loading.component.ts
[OK] src\app\shared\components\error-alert\error-alert.component.ts
[OK] src\app\pages\dashboard\dashboard.component.ts
[OK] src\app\pages\not-found\not-found.component.ts
[OK] src\app\app.routes.ts
[OK] src\app\app.config.ts
[OK] src\app\app.component.ts
[OK] src\styles.scss
[OK] package.json

  Execute agora no SERVIDOR:
  powershell -ExecutionPolicy Bypass -Command "& 'C:\SOL\infra\scripts\sprint-f1-deploy.ps1'"
```

---

## Passo 2 — Executar o deploy no servidor

### Script: `sprint-f1-deploy.ps1`

**Onde executar:** no servidor (terminal do servidor ou sessao remota)

```powershell
powershell -ExecutionPolicy Bypass -Command "& 'C:\SOL\infra\scripts\sprint-f1-deploy.ps1'"
```

O script executa 6 passos sequenciais com verificacao automatica ao final.

---

### Passo 1 do script: Verificacao de pre-requisitos

**O que faz:** Verifica se todos os pre-requisitos estao presentes antes de iniciar qualquer operacao que demande tempo.

Verifica:
- **Node.js** — necessario para executar o npm e o Angular CLI
- **npm** — gerenciador de pacotes do Node, usado para instalar dependencias
- **Angular CLI** — compilador Angular (`ng build`)
- **Diretorio `C:\SOL\frontend`** — confirma que os arquivos sincronizados chegaram corretamente
- **Servico `SOL-Nginx`** — o Nginx precisa existir como servico Windows para ser reiniciado ao final

**Por que e necessario:** Se qualquer pre-requisito estiver ausente, o script aborta imediatamente com mensagem clara, evitando falhas parciais dificeis de diagnosticar em etapas posteriores.

**O que esperar:**
```
[OK] Node.js: v20.18.0
[OK] npm: v10.8.2
[WARN] Angular CLI global nao encontrado. Tentando com npx durante o build.
[OK] Diretorio frontend: C:\SOL\frontend
[OK] Servico SOL-Nginx encontrado (Status: Running)
```

O aviso sobre o Angular CLI global e normal — o build usa o CLI instalado localmente no projeto via `node_modules/.bin/ng`, ativado pelo script `npm run build:prod`.

---

### Passo 2 do script: npm install

**O que faz:** Executa `npm install` no diretorio `C:\SOL\frontend`, instalando os dois novos pacotes declarados no `package.json` da Sprint F1 — `@angular/material@18` e `@angular/cdk@18` — e verificando a integridade de todas as dependencias existentes.

**Por que e necessario:** O `package.json` foi atualizado para incluir o Angular Material. Sem o `npm install`, o compilador TypeScript nao encontrara os modulos (`Cannot find module '@angular/material/toolbar'`) e o build falhara.

**Detalhe tecnico:** O script usa `$LASTEXITCODE` para detectar falha real do npm, em vez de `try/catch` com redirecionamento de stderr. Isso e necessario porque o npm escreve avisos de deprecacao em stderr, e o PowerShell com `$ErrorActionPreference = "Stop"` interpretaria esses avisos como erros terminantes — o que causaria falso positivo. O exit code 0 significa sucesso, independentemente dos avisos exibidos.

**O que esperar:**
```
added 2 packages, and audited 948 packages in 14s
178 packages are looking for funding
43 vulnerabilities (...)
[OK] npm install concluido com sucesso
```

Os avisos de vulnerabilidade e funding sao informativos e nao afetam o funcionamento do sistema. O numero exato de pacotes adicionados pode variar conforme o estado anterior do `node_modules`.

**Tempo estimado:** 10 a 30 segundos (dependencias ja parcialmente instaladas de execucoes anteriores).

---

### Passo 3 do script: Build Angular (modo producao)

**O que faz:** Executa `ng build --configuration production`, que realiza:
- Compilacao TypeScript para JavaScript ES2022
- Resolucao de todos os imports de modulos Angular e Material
- Aplicacao do tema SCSS (Material M3 + tokens CBM-RS)
- Tree-shaking: elimina codigo nao utilizado
- Minificacao e compressao dos bundles JS/CSS
- Geracao de hashes nos nomes dos arquivos (ex: `main.a3f9b1.js`) para cache-busting automatico
- Saida em `C:\SOL\frontend\dist\sol-frontend\browser\`

**Por que e necessario:** O Nginx serve arquivos estaticos — nao interpreta TypeScript. O build transforma o codigo-fonte em arquivos HTML/JS/CSS prontos para producao. O modo `production` aplica todas as otimizacoes que garantem carregamento rapido no navegador.

**Detalhe tecnico:** O script define `$ErrorActionPreference = "Continue"` antes do build e verifica `$LASTEXITCODE` ao final, pelo mesmo motivo do passo anterior: o Angular CLI pode escrever avisos em stderr sem que isso signifique falha.

**O que esperar:** Saida verbosa do Angular CLI listando cada arquivo gerado com seu tamanho. O build bem-sucedido termina sem linhas `[ERROR]`. Avisos de budget (tamanho de bundle) podem aparecer — sao informativos.

**Arquivo chave gerado:** `C:\SOL\frontend\dist\sol-frontend\browser\index.html`

**Tempo estimado:** 2 a 4 minutos.

---

### Passo 4 do script: Atualizar configuracao do Nginx

**O que faz:**
1. Copia `C:\SOL\infra\nginx\nginx.conf` para `C:\SOL\infra\nginx\nginx-1.26.2\conf\nginx.conf` (diretorio efetivo de configuracao do Nginx instalado)
2. Executa `nginx.exe -t` para validar a sintaxe antes de aplicar

**Por que e necessario:** O `nginx.conf` da Sprint F1 adiciona melhorias em relacao ao instalado na Sprint 0:
- **Cache de longa duracao para assets com hash** (`expires 1y; Cache-Control: public, immutable`): o navegador nao busca novamente arquivos cujo nome ja contem hash — reduz drasticamente o trafego em acessos subsequentes
- **Headers de seguranca HTTP**: `X-Frame-Options: SAMEORIGIN` (anti-clickjacking), `X-Content-Type-Options: nosniff` (anti-MIME sniffing), `Referrer-Policy`
- **Keep-alive no upstream backend**: reutiliza conexoes TCP entre Nginx e Spring Boot, melhorando desempenho sob carga
- **HTML5 routing**: `try_files $uri $uri/ /index.html` serve o `index.html` para qualquer rota nao encontrada nos arquivos estaticos, necessario para o Angular Router funcionar sem hash (`#`)

**O que esperar:**
```
[OK] nginx.conf copiado para C:\SOL\infra\nginx\nginx-1.26.2\conf
[OK] Sintaxe do nginx.conf: OK
```

---

### Passo 5 do script: Reiniciar servico SOL-Nginx

**O que faz:** Para completamente o servico Windows `SOL-Nginx` e o reinicia, forcando o Nginx a:
- Reler o `nginx.conf` atualizado
- Servir os novos arquivos estaticos do Angular do diretorio `dist/`

**Por que e necessario:** O Nginx carrega a configuracao apenas na inicializacao. Sem reiniciar, o servico continuaria usando a configuracao e o build anteriores, mesmo que os arquivos no disco tenham mudado.

**Por que Stop + Start (nao apenas Restart):** O `Stop-Service` aguarda o encerramento completo do processo antes de retornar, garantindo que nao ha processo residual com a porta 80 ocupada quando o `Start-Service` e chamado.

**O que esperar:**
```
[OK] Servico SOL-Nginx: RUNNING
```

---

### Passo 6 do script: Verificacao HTTP

**O que faz:** Realiza duas requisicoes HTTP para confirmar que o sistema esta funcionando de ponta a ponta apos o deploy:

1. `GET http://localhost:80/` — verifica que o Angular SPA esta sendo servido corretamente
2. `GET http://localhost:80/api/actuator/health` — verifica que o proxy `/api/` continua encaminhando para o Spring Boot

**Por que e necessario:** Confirma que o build foi bem-sucedido, que o Nginx esta servindo os arquivos corretos e que o `nginx.conf` atualizado nao quebrou o proxy para o backend.

**O que esperar:**
```
[OK] http://localhost:80/ -- HTTP 200
[OK] Conteudo HTML contem 'SOL' -- Angular SPA carregado
[OK] http://localhost:80/api/actuator/health -- Backend UP
```

---

### Sumario final esperado

```
============================================================
  SUMARIO -- Sprint F1
============================================================
  OK      : 12
  AVISOS  : 2
  ERROS   : 0
  Fim     : 2026-04-02 HH:MM:SS
============================================================

  Sprint F1 implantada com sucesso!

  Frontend:  http://localhost:80/
  API:       http://localhost:80/api/
  Keycloak:  http://localhost:8180/
```

Os 2 avisos tipicos sao: Angular CLI global ausente (nao critico) e diretorio de conf do Nginx nao encontrado (se a versao instalada for diferente). Ambos nao impedem o funcionamento.

---

## Verificacao manual apos o deploy

Acesse de uma maquina na rede local:

### 1. Tela de login

Abra: `http://10.62.2.40/` (ou `http://192.168.1.30/`)

**Esperado:** Tela com titulo "SOL — Sistema Online de Licenciamento | CBM-RS" e botao "Entrar com credenciais SOL".

### 2. Fluxo de autenticacao

Clique em "Entrar com credenciais SOL". O navegador redireciona para o Keycloak em `http://10.62.2.40:8180/`. Faca login com `sol-admin` / `Admin@SOL2026`.

**Esperado:** Keycloak redireciona de volta para o SOL. O Angular processa o authorization code (PKCE Code Flow), obtem o access token e navega automaticamente para `/app/dashboard`.

### 3. Dashboard

**Esperado:** Pagina com saudacao ao usuario, mensagem de perfil ("Voce esta acessando como Administrador do sistema SOL") e cards de acesso rapido filtrados pelos roles do usuario logado.

### 4. Shell (sidebar + toolbar)

**Esperado:** Sidebar lateral escura com o logo SOL/CBM-RS e menu de navegacao filtrado por perfil. Toolbar vermelha CBM-RS com icone de usuario e menu de logout.

### 5. Guard de autenticacao

Em aba anonima, acesse diretamente `http://10.62.2.40/app/dashboard`.

**Esperado:** Redirecionamento imediato para `/login` — o `authGuard` intercepta a navegacao antes de renderizar qualquer conteudo da area autenticada.

---

## Arquitetura tecnica

### Fluxo de autenticacao (PKCE Code Flow)

```
Navegador              Angular (SPA)         Keycloak :8180      Backend :8080
    |                       |                     |                    |
    |-- GET http://IP/ ---> |                     |                    |
    |                       |-- authGuard          |                    |
    |                       |   nao autenticado    |                    |
    |<-- redirect /login    |                     |                    |
    |                       |                     |                    |
    |-- clica Entrar -----> |                     |                    |
    |                       |-- initCodeFlow() --> |                    |
    |<-- redirect Keycloak  |                     |                    |
    |-- login ----------->  |                     |                    |
    |                       |              code=X  |                    |
    |<-- redirect /?code=X  |                     |                    |
    |-- GET / ----------->  |                     |                    |
    |                       |-- tryLogin()         |                    |
    |                       |-- POST /token -----> |                    |
    |                       |<-- access_token ---- |                    |
    |                       |-- navigate /app/dashboard                 |
    |<-- dashboard          |                     |                    |
    |                       |                     |                    |
    |-- acao usuario -----> |                     |                    |
    |                       |-- GET /api/... (Bearer token) ---------> |
    |                       |<-- 200 JSON --------------------------------|
```

### Estrutura de rotas

```
/                      → redirect para /app/dashboard
/login                 → LoginComponent          (publica, sem guard)
/app                   → ShellComponent          (canActivate: authGuard)
  /app/dashboard       → DashboardComponent      (todos os perfis)
  /app/licenciamentos  → [Sprint F2]             (roles: todos autenticados)
  /app/analise         → [Sprint F3/F4]          (roles: ANALISTA, CHEFE_SSEG_BBM)
  /app/vistorias       → [Sprint F5]             (roles: INSPETOR, CHEFE_SSEG_BBM)
  /app/usuarios        → [Sprint F7]             (roles: ADMIN)
  /app/relatorios      → [Sprint F9]             (roles: ADMIN, CHEFE_SSEG_BBM)
/**                    → NotFoundComponent        (404)
```

### Roles do sistema SOL

| Role Keycloak | Perfil | Acesso principal |
|---|---|---|
| `CIDADAO` | RT / RU / Proprietario | Meus Licenciamentos, Wizard P03 |
| `ANALISTA` | Analista tecnico CBMRS | Fila de Analise, P04, P05, P06, P10 |
| `INSPETOR` | Inspetor de vistoria | Vistorias P07, P08, P14 |
| `CHEFE_SSEG_BBM` | Chefe de Secao | Analise + Vistorias + Relatorios |
| `ADMIN` | Administrador | Tudo: usuarios, configuracoes, relatorios |

### Como os roles chegam ao frontend

O Keycloak publica os roles no access token JWT no campo `realm_access.roles`. O `AuthService` decodifica o payload Base64URL do JWT no browser (sem chamada de rede) e retorna o array de roles. O `authGuard` e o `roleGuard` consultam o `AuthService` de forma sincrona, sem latencia.

```typescript
// auth.service.ts — decodificacao do JWT no browser
const padded = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
const payload = JSON.parse(atob(padded));
return payload.realm_access?.roles ?? [];
```

### Tema Angular Material M3

O `styles.scss` aplica o tema Material M3 com `mat.$red-palette` (vermelho CBM-RS) como cor primaria. O M3 gera automaticamente todas as variantes tonais (container, on-container, surface, etc.) a partir da cor base. Alem do tema, o arquivo define tokens CSS customizados (`--cbm-*`, `--status-*`) que serao utilizados pelos componentes das sprints F2–F9 para exibir badges de status de licenciamento com as cores corretas.

### Por que HTML5 routing (sem `#` na URL)?

O `app.config.ts` usa `provideRouter(routes)` sem `withHashLocation`. O Nginx esta configurado com `try_files $uri $uri/ /index.html`, que serve o `index.html` para qualquer rota nao encontrada nos arquivos estaticos. Isso e o que o Angular Router precisa para funcionar em modo HTML5: todas as rotas (`/app/dashboard`, `/login`, etc.) retornam o `index.html` e o router Angular resolve a rota no browser. As URLs ficam limpas (sem `/#/`), o que tambem e necessario para o `redirectUri` do Keycloak apontar corretamente para `window.location.origin + '/'`.

---

## Resolucao de problemas

### Build falha: `Cannot find module '../../core/services/auth.service'`

**Causa:** Existe um arquivo `.ts` em um caminho duplicado (ex: `layout/layout/shell/`) com import relativo invalido. Isso ocorre quando `Copy-Item -Recurse` e executado com destino ja existente, criando subpastas aninhadas.

**Solucao:** Execute o `sync-frontend-to-server.ps1` na maquina local — ele remove as pastas duplicadas e copia os arquivos nos caminhos corretos.

### Build falha: `Cannot find module '@angular/material/toolbar'`

**Causa:** `npm install` nao foi executado apos atualizar o `package.json`, ou o `node_modules` esta corrompido.

**Solucao:** Acesse `C:\SOL\frontend` no servidor e execute `npm install` manualmente.

### Build falha: `Budget exceeded`

**Causa:** O bundle inicial excedeu o limite de tamanho configurado no `angular.json`. Normal ao adicionar Angular Material.

**Solucao:** Ajuste os limites em `angular.json`:
```json
{ "type": "initial", "maximumWarning": "1MB", "maximumError": "2MB" }
```

### Nginx nao inicia apos o deploy

**Causa:** Erro de sintaxe no `nginx.conf` ou porta 80 ocupada por outro processo.

**Diagnostico:**
```powershell
netstat -ano | findstr ":80 "
Get-Content C:\SOL\logs\nginx-stderr.log -Tail 30
```

### Redirecionamento infinito para /login apos autenticacao

**Causa:** O `issuer-uri` em `application.yml` nao corresponde ao campo `iss` do JWT emitido pelo Keycloak. O Spring Boot rejeita o token e retorna 401; o frontend interpreta como nao autenticado e redireciona para login.

**Diagnostico:** Decodifique o JWT e compare o campo `iss` com o valor em `application.yml`:
```powershell
$body = "grant_type=password&client_id=sol-frontend&username=sol-admin&password=Admin@SOL2026"
$resp = Invoke-RestMethod "http://localhost:8180/realms/sol/protocol/openid-connect/token" `
        -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
$parts = $resp.access_token.Split(".")
$pad = 4 - ($parts[1].Length % 4)
$b64 = $parts[1] + ("=" * ($pad % 4))
([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json).iss
```

O valor retornado deve ser `http://localhost:8180/realms/sol` — identico ao `issuer-uri` em `application.yml`.

### Dashboard exibe cards errados ou sem conteudo

**Causa:** O usuario nao possui roles configurados no Keycloak ou o claim `realm_access.roles` esta ausente no token.

**Diagnostico:** Usando o payload decodificado acima, verifique:
```powershell
# Continuando o comando anterior:
($payload = ...) | Select-Object -ExpandProperty realm_access
```

O campo `roles` deve conter ao menos um dos valores: `CIDADAO`, `ANALISTA`, `INSPETOR`, `ADMIN`, `CHEFE_SSEG_BBM`.

---

## Pre-requisitos no servidor

Confirme antes de executar:

```powershell
# Todos os servicos devem estar Running
Get-Service SOL-Keycloak, sol-backend, SOL-MinIO, SOL-Nginx | Select-Object Name, Status

# Node.js 20+ e npm 10+
node --version
npm --version

# Backend respondendo
Invoke-RestMethod http://localhost:8080/api/actuator/health
```

---

## Proximos passos: Sprint F2

A Sprint F2 implementa o **Modulo de Licenciamentos do Cidadao**:
- Listagem paginada de licenciamentos (`GET /api/licenciamentos`)
- Wizard de criacao de licenciamento (P03: dados gerais, endereco, envolvidos, documentos)
- Visualizacao de detalhe e acompanhamento de status
- Upload de arquivos via MinIO

**Pre-requisito:** Sprint F1 concluida com 0 erros e verificacao manual aprovada.

---

## Referencias

| Documento | Local |
|---|---|
| Requisitos P03 Stack Java Moderna | `Requisitos_P03_SubmissaoPPCI_Java.md` |
| Requisitos P02 Stack Java Moderna | `Requisitos_P02_CadastroUsuario_Java.md` |
| Design UX sistema SOL | `Design_UX_SistemaSOL_Moderno.md` |
| DDL PostgreSQL completo | `DDL_PostgreSQL_SistemaSOL_Moderno.sql` |
| Script de sincronizacao | `C:\SOL\infra\scripts\sync-frontend-to-server.ps1` |
| Script de deploy | `C:\SOL\infra\scripts\sprint-f1-deploy.ps1` |
| Script de verificacao geral | `C:\SOL\infra\scripts\verify-sol.ps1` |
| Configuracao backend | `C:\SOL\backend\src\main\resources\application.yml` |
| Instrucoes Sprint F2 | (a ser criado) |
