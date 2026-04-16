# Fluxograma Detalhado – P01: Autenticação no Sistema SOL/CBM-RS

---

## 1. Objetivo do Caso de Uso

Autenticar o usuário (Cidadão, Responsável Técnico ou ADM/Fiscal) no sistema SOL via protocolo **OpenID Connect (OIDC) / OAuth2 Implicit Flow**, delegando a identidade ao provedor centralizado do Estado do RS (`meu.rs.gov.br`).
Após autenticação bem-sucedida, o sistema verifica o cadastro do usuário na base do SOL e redireciona para a área correta conforme seu perfil e situação de cadastro.

---

## 2. Atores

| Ator | Descrição |
|------|-----------|
| Cidadão / RT | Usuário final que acessa o portal SOL |
| ADM / Fiscal CBM | Usuário interno com perfil administrativo |
| Sistema SOL (Frontend Angular) | SPA Angular responsável pela orquestração da autenticação |
| Identity Provider (IdP) | `https://meu.hml.rs.gov.br` — provedor OIDC do RS |
| Backend SOL (Java EE) | API REST que valida e gerencia dados do usuário |

---

## 3. Pré-condições

- O usuário possui conta ativa no portal `meu.rs.gov.br`.
- Para RT: o usuário possui CPF registrado no sistema SOL (cadastro pode estar em qualquer status).
- Para ADM/Fiscal: usuário cadastrado via SOE (Sistema Operacional Estadual).

---

## 4. Fluxo Principal — Passo a Passo

---

### ETAPA 1 — Acesso Inicial ao Portal SOL

**Ação do usuário:** Digita a URL do portal SOL no navegador ou clica em link de acesso.

**Tela:** Tela inicial / splash do portal SOL
**Elemento de tela:** Nenhuma interação — carregamento automático da SPA.

**Sistema responde:**

1. Angular carrega `AppModule` e instancia `AppComponent`.
2. `AppComponent.ngOnInit()` invoca `configureAuth()`.

```
Classe:  AppComponent  (src/app/app.component.ts)
Método:  configureAuth()
```

**O que `configureAuth()` faz:**
- Configura `OAuthService` com parâmetros de `auth.config.ts`:
  - `issuer`: `https://meu.hml.rs.gov.br`
  - `clientId`: `209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s`
  - `redirectUri`: URL atual da SPA
  - `scope`: `openid public_profile email name cpf birthdate phone_number`
  - `responseType`: `token` (Implicit Flow)
  - `sessionChecksEnabled`: `true`
- Chama `loadDiscoveryDocument()` para buscar `.well-known/openid-configuration` do IdP.
- Ativa **silent refresh** (`setupAutomaticSilentRefresh()`).
- Registra listeners de eventos:
  - `session_terminated` → redireciona para `/login`
  - `token_received` → invoca `verificaCadastro()`

**Regra de Negócio:** RN-AUTH-001 — Toda sessão deve ser iniciada via OIDC com o IdP estadual.

---

### ETAPA 2 — Verificação de Token Existente (Guard de Rota)

**Ação do usuário:** Tenta navegar para qualquer rota protegida (ex.: `/home`, `/processos`).

**Tela:** (rota interceptada antes de renderizar qualquer tela)
**Elemento de tela:** Não visível ao usuário.

**Sistema responde:**

`UsuarioAutenticadoGuard.canActivate()` é acionado pelo Router Angular.

```
Classe:  UsuarioAutenticadoGuard
         (projects/cbm-shared/src/guards/usuario-autenticado.guard.ts)
Método:  canActivate(route, state)
```

**Lógica do guard (3 caminhos):**

| Condição | Ação |
|----------|------|
| Sem token E sem identity claims | Chama `oauthService.initImplicitFlow()` → redireciona para IdP |
| Sem token E com identity claims pendentes | Chama `oauthService.loadDiscoveryDocumentAndLogin()` |
| Com token E sem nome nas claims | Chama `oauthService.loadUserProfile()` → tenta recuperar perfil |
| Com token E com nome nas claims | Retorna `true` → permite navegação |

**Regra de Negócio:** RN-AUTH-002 — Nenhuma rota interna é acessível sem token OIDC válido.

---

### ETAPA 3 — Redirecionamento para o IdP (Login Gov RS)

**Ação do usuário:** Preenche CPF/senha (ou usa certificado digital) na tela do IdP estadual.

**Tela:** Portal `meu.rs.gov.br` (tela externa — fora do SOL)
**Elementos de tela (externos ao SOL):**
- Campo: **CPF** (`input[name=cpf]`)
- Campo: **Senha** (`input[type=password]`)
- Botão: **Entrar** (`button[type=submit]`)
- Link: **Esqueci minha senha**
- Link: **Cadastre-se no Gov.RS**

**Sistema IdP responde:**
- Valida credenciais.
- Emite **Access Token (JWT)** e **ID Token**.
- Redireciona de volta para `redirectUri` do SOL com token no fragmento de URL (`#access_token=...`).

**Regra de Negócio (IdP):** Credenciais inválidas → IdP exibe mensagem de erro. Três tentativas falhas podem bloquear acesso no IdP.

---

### ETAPA 4 — Recebimento e Armazenamento do Token

**Ação do usuário:** Nenhuma — ocorre automaticamente após o redirect.

**Tela:** URL do SOL com fragmento `#access_token=...` na barra de endereço.
**Elemento de tela:** Loading spinner (se implementado) ou tela em branco momentânea.

**Sistema responde:**

`OAuthService` (biblioteca `angular-oauth2-oidc`) processa o fragmento da URL:
1. Extrai e valida `access_token` e `id_token`.
2. Dispara evento `token_received`.
3. `AppComponent` recebe o evento e invoca `verificaCadastro()`.

**Armazenamento do token:**

```
Classe:  AuthStorageService
         (src/app/auth-storage.service.ts)
Método:  setItem(key: string, data: string)
Storage: localStorage['appToken'] = JSON.stringify({ access_token, id_token, expires_at, ... })
```

**Regra de Negócio:** RN-AUTH-003 — Token é armazenado em `localStorage` sob a chave `appToken`. Expiração é controlada por `expires_at` (timestamp Unix).

---

### ETAPA 5 — Verificação do Cadastro do Usuário no SOL

**Ação do usuário:** Nenhuma — ocorre automaticamente.

**Tela:** Tela de carregamento / loading.
**Elemento de tela:** Spinner ou barra de progresso (componente de loading global).

**Sistema responde:**

```
Classe:  AppComponent  (src/app/app.component.ts)
Método:  verificaCadastro()
```

**O que `verificaCadastro()` faz:**

1. Extrai **CPF** e **e-mail** das identity claims do `OAuthService`:
   ```typescript
   const claims = this.oauthService.getIdentityClaims();
   const cpf    = claims['cpf'];
   const email  = claims['email'];
   ```

2. Chama o serviço Angular de usuário:
   ```
   Classe:  UsuarioCidadaoService  (ou CadastroUsuarioService)
   Método:  consultaPorCpf(cpf: string): Observable<Usuario>
   ```

3. Faz requisição HTTP ao backend:
   ```
   GET /usuarios?cpf={cpf}
   Header: Authorization: Bearer {access_token}   ← injetado por HttpAuthorizationInterceptor
   ```

**Interceptor de autorização:**

```
Classe:  HttpAuthorizationInterceptor
         (projects/cbm-shared/src/services/interceptors/http-authorization.interceptor.ts)
Método:  intercept(req, next)
Lógica:  Se URL contém AppSettings.baseUrl → clona request com header Authorization: Bearer <token>
```

---

### ETAPA 6A — Usuário NÃO encontrado (status 404) ou Cadastro INCOMPLETO

**Condição:** Backend retorna 404 ou `{ status: "INCOMPLETO" }`.

**Tela:** Página de cadastro do RT/Cidadão
**Rota:** `/cadastro`
**Elementos de tela:**
- Formulário multi-etapa de cadastro (gerenciado por `CadastroUsuarioGuard` / wizard P02)

**Sistema responde:**

```
Classe:  AppComponent
Método:  verificaCadastro()
Ação:    this.router.navigate(['/cadastro'])
```

**Regra de Negócio:** RN-CAD-001 — Usuário autenticado sem cadastro ou com cadastro INCOMPLETO é redirecionado obrigatoriamente para completar o cadastro antes de usar o sistema.

---

### ETAPA 6B — Cadastro em ANALISE_PENDENTE ou EM_ANALISE

**Condição:** Backend retorna `{ status: "ANALISE_PENDENTE" }` ou `{ status: "EM_ANALISE" }`.

**Tela:** Tela de aguardo de aprovação
**Rota:** `/aguardando-aprovacao` (ou equivalente)
**Elementos de tela:**
- Mensagem informativa: *"Seu cadastro está em análise. Aguarde a aprovação."*
- Botão: **Sair** (`logout`)

**Sistema responde:**

```
Classe:  AppComponent
Método:  verificaCadastro()
Ação:    this.router.navigate(['/aguardando-aprovacao'])
```

**Regra de Negócio:** RN-CAD-002 — Usuário com cadastro pendente de análise não pode acessar funcionalidades de licenciamento.

---

### ETAPA 6C — Cadastro APROVADO

**Condição:** Backend retorna `{ status: "APROVADO" }`.

**Sub-etapa:** Verifica se e-mail do IdP difere do e-mail cadastrado no SOL. Se divergente:

```
PUT /usuarios/{id}   (atualiza e-mail)
Classe Backend:  UsuarioRestImpl  (@Path("/usuarios"))
Método Backend:  alterar(id, usuario)
RN Backend:      UsuarioRN.alterar(id, usuario)
Validação:       Concorrência por ctrDthAtu — lança HTTP 409 se divergente
```

**Tela:** Home do sistema SOL / Dashboard principal
**Rota:** `/home` ou `/processos`
**Elementos de tela (após login completo):**
- Menu de navegação lateral/superior com opções conforme perfil:
  - Cidadão/RT: **Meus Processos**, **Novo Licenciamento**, **Consultas**
  - ADM/Fiscal: **Gerenciar Processos**, **Análise Técnica**, **Relatórios**
- Avatar / nome do usuário logado (extraído das claims: `claims['name']`)
- Botão: **Sair** (logout)

**Sistema responde:**

```
Classe:  AppComponent
Método:  verificaCadastro()
Ação:    this.router.navigate(['/home'])
```

---

### ETAPA 6D — Cadastro REPROVADO

**Condição:** Backend retorna `{ status: "REPROVADO" }`.

**Tela:** Tela de notificação de reprovação
**Elementos de tela:**
- Mensagem: *"Seu cadastro foi reprovado. Entre em contato com o CBM-RS."*
- Motivo da reprovação (se disponível)
- Botão: **Sair**

---

### ETAPA 7 — Backend: Validação da Sessão por Requisição

Para cada requisição autenticada subsequente, o backend valida o token:

```
Classe:  CidadaoSessionMB
         (src/main/java/com/procergs/solcbm/seguranca/CidadaoSessionMB.java)
Escopo:  @RequestScoped
Método:  getCidadaoED() → retorna CidadaoED com nome, cpf, email, permissões, papéis
```

**Entidade de domínio:**

```
Classe:  CidadaoED
Campos:  nome, cpf, dtNascimento, email, telefone
         Set<PermissaoED> permissoes
         List<TipoPapel>  papeis
```

**Controle de permissões (backend):**

```
Anotação:  @Permissao(objeto="X", acao="Y")
Classe:    CidadaoSessionMB.hasPermission(objeto, acao)
```

---

### ETAPA 8 — Logout

**Ação do usuário:** Clica no botão **Sair** na navbar.

**Tela:** Qualquer tela logada
**Elemento de tela:** Botão **Sair** / ícone de logout (menu superior ou lateral)

**Sistema responde:**

```
Classe:  AppComponent
Método:  logout()
Ações:   1. oauthService.logOut()    → invalida token no IdP, limpa session OIDC
          2. authStorage.clean()      → remove 'appToken' do localStorage
          3. Router redireciona para  /login ou tela inicial
```

```
Classe:  AuthStorageService
Método:  clean()
Ação:    localStorage.removeItem('appToken')
```

**Regra de Negócio:** RN-AUTH-004 — O logout deve invalidar o token tanto no IdP quanto no localStorage local, prevenindo uso indevido de tokens residuais.

---

## 5. Fluxo Visual (Sequência Resumida)

```
Usuário                    Frontend Angular              IdP (meu.rs.gov.br)     Backend SOL
   |                            |                               |                      |
   |-- Acessa URL SOL --------> |                               |                      |
   |                            |-- configureAuth() ----------->|                      |
   |                            |   loadDiscoveryDocument()     |                      |
   |                            |                               |                      |
   |                            |-- initImplicitFlow() -------> |                      |
   |<-- Redireciona para IdP ---|                               |                      |
   |                            |                               |                      |
   |-- Login (CPF + Senha) ---> |                               |                      |
   |                            |                               |-- Valida credenciais |
   |                            |                               |                      |
   |<-- Redirect com token ---- |<----- access_token + id_token-|                      |
   |                            |                               |                      |
   |                            |-- Armazena token (localStorage['appToken'])           |
   |                            |                               |                      |
   |                            |-- verificaCadastro() -------> |          GET /usuarios?cpf=
   |                            |                               |                      |-- consultaPorCpf()
   |                            |                               |                      |   UsuarioRN
   |                            |<----------------------------------------------- retorna Usuario
   |                            |                               |                      |
   |  [Status INCOMPLETO]  --> router.navigate(['/cadastro'])   |                      |
   |  [Status PENDENTE]    --> router.navigate(['/aguardando']) |                      |
   |  [Status APROVADO]    --> router.navigate(['/home'])       |                      |
   |  [Status REPROVADO]   --> router.navigate(['/reprovado'])  |                      |
   |                            |                               |                      |
   |<-- Tela conforme perfil ---|                               |                      |
```

---

## 6. Classes e Métodos — Resumo Consolidado

### Frontend (Angular)

| Classe | Arquivo | Método(s) Principal(is) |
|--------|---------|--------------------------|
| `AppComponent` | `src/app/app.component.ts` | `configureAuth()`, `verificaCadastro()`, `login()`, `logout()` |
| `AuthStorageService` | `src/app/auth-storage.service.ts` | `getItem()`, `setItem()`, `removeItem()`, `clean()` |
| `UsuarioAutenticadoGuard` | `projects/cbm-shared/src/guards/usuario-autenticado.guard.ts` | `canActivate()` |
| `HttpAuthorizationInterceptor` | `projects/cbm-shared/src/services/interceptors/http-authorization.interceptor.ts` | `intercept()` |
| `UsuarioCidadaoService` | `src/app/...` | `consultaPorCpf(cpf)` |

### Backend (Java EE)

| Classe | Pacote | Método(s) Principal(is) |
|--------|--------|--------------------------|
| `UsuarioRestImpl` | `...remote` | `GET /usuarios`, `PUT /usuarios/{id}` |
| `UsuarioRN` | `...usuario` | `consultaPorCpf()`, `alterar()`, `isUsuarioLogadoRtValido()` |
| `CidadaoSessionMB` | `...seguranca` | `getCidadaoED()`, `hasPermission()` |
| `CidadaoED` | `...seguranca` | Entidade com nome, cpf, permissões |

---

## 7. Regras de Negócio Ativadas

| ID | Regra | Etapa |
|----|-------|-------|
| RN-AUTH-001 | Autenticação obrigatoriamente via OIDC com IdP estadual (`meu.rs.gov.br`) | Etapa 1 |
| RN-AUTH-002 | Toda rota interna é protegida por `UsuarioAutenticadoGuard` | Etapa 2 |
| RN-AUTH-003 | Token armazenado em `localStorage['appToken']` como JSON | Etapa 4 |
| RN-AUTH-004 | Logout deve invalidar token no IdP E limpar localStorage | Etapa 8 |
| RN-CAD-001 | Usuário sem cadastro ou com status INCOMPLETO → redirecionar para `/cadastro` | Etapa 6A |
| RN-CAD-002 | Usuário com status ANALISE_PENDENTE/EM_ANALISE → acesso bloqueado até aprovação | Etapa 6B |
| RN-CAD-003 | Se e-mail do IdP difere do cadastrado → atualizar automaticamente via `PUT /usuarios/{id}` | Etapa 6C |
| RN-CAD-004 | Atualização de usuário verifica concorrência via campo `ctrDthAtu`; retorna HTTP 409 se divergente | Etapa 6C |
| RN-PERM-001 | Permissões por `@Permissao(objeto, acao)` verificadas em `CidadaoSessionMB.hasPermission()` | Etapa 7 |

---

## 8. Configuração OIDC (Referência)

```typescript
// src/app/auth.config.ts
export const authConfig: AuthConfig = {
  issuer:                 'https://meu.hml.rs.gov.br',
  clientId:               '209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s',
  redirectUri:            window.location.origin,
  responseType:           'token',
  scope:                  'openid public_profile email name cpf birthdate phone_number',
  sessionChecksEnabled:   true,
  showDebugInformation:   false,
  requireHttps:           true,
};
```

---

## 9. Endpoints REST Envolvidos no P01

| Método | Endpoint | Classe | Descrição |
|--------|----------|--------|-----------|
| `GET` | `/usuarios?cpf={cpf}` | `UsuarioRestImpl` | Consulta usuário por CPF após login |
| `PUT` | `/usuarios/{id}` | `UsuarioRestImpl` | Atualiza e-mail se divergente do IdP |
| `GET` | `/.well-known/openid-configuration` | IdP externo | Discovery document OIDC |
| `POST` | `/token` (IdP) | IdP externo | Implicit flow token endpoint |

---

*Documento gerado em: 2026-03-04*
*Processo: P01 – Autenticação no Sistema SOL/CBM-RS*
*Base de código analisada: SOLCBM.FrontEnd16-06 / SOLCBM.BackEnd16-06*
