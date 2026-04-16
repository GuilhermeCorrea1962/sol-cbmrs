# Fluxograma Detalhado — P01: Autenticação e Controle de Acesso
## SOL/CBM-RS — Stack Atual (Angular + Java EE + OIDC Implicit Flow)

**Versão:** 2.0
**Data:** 2026-03-18
**Escopo:** Interações de tela, respostas do sistema, classes, métodos, RNs e trechos de código

---

## Legenda de Notação

```
[USUÁRIO] → ação que o usuário executa na interface
[SISTEMA] → reação automática do sistema (Angular ou backend)
[IdP]     → ação do Provedor de Identidade PROCERGS (meu.rs.gov.br)
[BACKEND] → execução no WildFly/Java EE
────────── → fluxo principal
─ ─ ─ ─ ─ → fluxo alternativo / condicional
```

---

## Visão Macro do Processo

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                    P01 — Autenticação SOL/CBM-RS                     │
 │                                                                      │
 │  Bootstrap → Verificação token → [sem token] → IdP → token_received  │
 │                                                    ↓                 │
 │              verificaCadastro() → Roteamento → Notificações          │
 │                                                    ↓                 │
 │           Uso do sistema → Silent Refresh → Logout                   │
 └──────────────────────────────────────────────────────────────────────┘
```

---

## FASE 1 — Bootstrap da Aplicação Angular

### Objetivo
Inicializar o `AppComponent`, carregar a configuração de autenticação do servidor e montar o cliente OIDC. Nenhuma tela é exibida ao usuário enquanto a configuração não estiver pronta.

---

### 1.1 — Usuário navega para a URL do sistema

```
[USUÁRIO] Digita ou acessa a URL:
          https://<host>/solcbm/app  (ou equivalente)
          Elemento: barra de endereço do navegador
```

```
[SISTEMA] Angular inicializa a SPA:
          ├─ index.html carregado
          ├─ main.js / vendor.js executados
          ├─ AppModule bootstrap
          └─ AppComponent.ngOnInit() disparado
```

**Tela neste momento:**
O usuário vê a tela de loading — `<app-loading id="loading">` —
porque `isReady = false` no template:

```html
<!-- app.component.html -->
<app-sidenav *ngIf="isReady; else loading">
  ...
</app-sidenav>

<ng-template #loading>
  <app-loading id="loading"></app-loading>   <!-- spinner exibido enquanto isReady=false -->
</ng-template>
```

**RN acionada:** RN-11 (isReady controla exibição — usuário nunca vê conteúdo parcial)

---

### 1.2 — Carregamento dinâmico da configuração

```
[SISTEMA] AppComponent.ngOnInit()
          └─ configService.getConfig()  →  GET /solcbm/api/v1/config
                                            (ou endpoint de configuração)
```

**Classe/Método:** `AppComponent.ngOnInit()` → `AppConfigService.getConfig()`
**Arquivo:** `src/app/app.component.ts`

```typescript
// app.component.ts — ngOnInit (simplificado)
ngOnInit() {
  this.configService.getConfig().pipe(
    finalize(() => this.isReady = true)   // RN-11: só libera após config
  ).subscribe(config => {
    // Grava flags de features no store
    this.licenciamentoHabilitado = config.licenciamentoHabilitado;
    this.tamanhoMaxArquivo       = config.tamanhoMaxArquivo;

    // Monta redirectUri com base no host atual
    config.authConfig.redirectUri = window.location.origin
                                    + config.authConfig.redirectUri;
    config.authConfig.postLogoutRedirectUri  = config.authConfig.redirectUri;
    config.authConfig.silentRefreshRedirectUri =
                      config.authConfig.redirectUri + '/silent-refresh.html';

    this.configureAuth(config.authConfig);   // → FASE 1.3
  });
}
```

**RN acionada:** RF-FE-01 — `isReady` permanece `false` até `finalize()` ser chamado.

---

### 1.3 — Configuração do cliente OIDC (OAuthService)

```
[SISTEMA] AppComponent.configureAuth(authConfig)
          ├─ oauthService.configure(authConfig)
          ├─ oauthService.setStorage(authStorage)          // localStorage['appToken']
          ├─ oauthService.tokenValidationHandler = new NullValidationHandler()
          ├─ oauthService.setupAutomaticSilentRefresh()    // → FASE 8
          ├─ Registra listener: 'session_terminated'
          ├─ Registra listener: 'token_received'
          └─ Verifica claims existentes → ramificação (1.4a ou 1.4b)
```

**Classe/Método:** `AppComponent.configureAuth()`
**Arquivo:** `src/app/app.component.ts`

```typescript
// app.component.ts — configureAuth (simplificado)
configureAuth(authConfig: AuthConfig) {
  this.oauthService.configure(authConfig);
  this.oauthService.setStorage(this.authStorage);           // RF-FE-03
  this.oauthService.tokenValidationHandler = new NullValidationHandler(); // RN-02

  const claims = this.oauthService.getIdentityClaims();    // checa localStorage

  if (claims) {
    // Sessão anterior existente
    const name = claims['name'];
    this.oauthService.loadDiscoveryDocumentAndLogin();
    if (this.oauthService.hasValidAccessToken()) {
      this.verificaCadastro();                              // → FASE 5
    }
  } else {
    // Primeiro acesso — tenta silenciosamente processar redirect
    this.oauthService.loadDiscoveryDocumentAndTryLogin()
      .then(() => this.router.initialNavigation())
      .catch(() => this.router.initialNavigation());
  }

  this.oauthService.setupAutomaticSilentRefresh();          // RF-FE-10

  this.oauthService.events.subscribe(e => {
    if (e.type === 'session_terminated') {
      console.log('Your session has been terminated!');     // RN-23
    }
    if (e.type === 'token_received') {
      this.oauthService.loadUserProfile()
        .then(() => this.verificaCadastro());               // → FASE 5
    }
  });
}
```

**RN acionadas:**
- RN-02: `NullValidationHandler` — JWT não validado no frontend (assinatura ignorada)
- RN-03: Token armazenado em `localStorage['appToken']` via `AuthStorageService`
- RN-23: `session_terminated` apenas loga no console

---

## FASE 2 — Armazenamento do Token (AuthStorageService)

### Objetivo
Persistir todas as chaves OIDC em um único objeto JSON no localStorage, mantendo compatibilidade com a interface da biblioteca `angular-oauth2-oidc`.

**Classe:** `AuthStorageService`
**Arquivo:** `src/app/auth-storage.service.ts`
**Chave do localStorage:** `appToken`

```typescript
// auth-storage.service.ts (simplificado)
export class AuthStorageService implements OAuthStorage {

  constructor() {
    // Inicializa objeto vazio se não existir
    if (!localStorage.getItem('appToken')) {
      localStorage.setItem('appToken', '{}');               // RN-03
    }
  }

  getItem(key: string): string | null {
    const store = JSON.parse(localStorage.getItem('appToken'));
    return store[key] || null;
  }

  setItem(key: string, data: string): void {
    const store = JSON.parse(localStorage.getItem('appToken'));
    store[key] = data;                     // acumula; não substitui o objeto inteiro
    localStorage.setItem('appToken', JSON.stringify(store));
  }

  removeItem(key: string): void {
    const store = JSON.parse(localStorage.getItem('appToken'));
    delete store[key];
    localStorage.setItem('appToken', JSON.stringify(store));
  }

  clean(): void {
    localStorage.removeItem('appToken'); // usado no logout — RN RF-FE-09
  }
}
```

**Estrutura armazenada:**
```json
// localStorage['appToken']:
{
  "access_token":  "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "id_token":      "eyJ...",
  "expires_at":    "1711234567000",
  "token_type":    "bearer",
  "nonce":         "abc123",
  "session_state": "xyz"
}
```

**RN acionada:** RN-03 — token armazenado como JSON agregador em `appToken`.

---

## FASE 3 — Redirecionamento para o IdP (Login)

### Ramificação: sem token válido e sem claims

```
[SISTEMA] OAuthService detecta ausência de token →
          initImplicitFlow() ou loadDiscoveryDocumentAndTryLogin()
          └─ Monta URL de autorização:
             https://meu.hml.rs.gov.br/oauth2/authorize
               ?response_type=token
               &client_id=209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s
               &redirect_uri=https://<host>/solcbm/app
               &scope=openid public_profile email name cpf birthdate phone_number
               &state=%2Fsome-state%3Bp1%3D1%3Bp2%3D2
          └─ Navegador é redirecionado (HTTP 302) para o IdP
```

### Ramificação: usuário clica em "Entrar" explicitamente

```
[USUÁRIO] Clica no botão "Entrar" na barra superior
          Elemento: <a id="btnLogin" (click)="login()"> Entrar </a>
          Localização: page-header.component.html (desktop)
                       menu.component.html (mobile — <app-menu-item loginEvent>)
```

```
[SISTEMA] page-header.component → emite eventLogin
          ↓
          app.component → login()
          └─ oauthService.initImplicitFlow('/some-state;p1=1;p2=2')
```

**Classe/Método:** `AppComponent.login()`
**Arquivo:** `src/app/app.component.ts`

```typescript
login() {
  this.oauthService.initImplicitFlow('/some-state;p1=1;p2=2'); // RF-FE-08
}
```

**RN acionada:** RN-01 — autenticação obrigatoriamente via OIDC Implicit Flow.

---

## FASE 4 — Autenticação no IdP PROCERGS

### Objetivo
O Provedor de Identidade (IdP) estadual autentica o cidadão e emite o token. O SOL/CBM-RS não tem acesso às credenciais.

**Tela exibida:** página do IdP PROCERGS (`meu.hml.rs.gov.br`)

```
[IdP]    Exibe formulário de login PROCERGS:
         ├─ Campo: usuário (CPF ou login estadual)
         ├─ Campo: senha
         └─ Botão: "Entrar"

[USUÁRIO] Preenche credenciais e clica "Entrar"
          Elementos: campos do IdP — não controlados pelo SOL

[IdP]    Valida credenciais internamente:
         ├─ Verifica usuário ativo no cadastro estadual
         ├─ Compara hash de senha
         └─ Verifica conta não bloqueada
```

### 4.1 — Emissão do Access Token

```
[IdP]    Autenticação bem-sucedida →
         Gera JWT (access_token) com claims:
           sub   = ID único SOE
           name  = nome completo
           cpf   = CPF (claim customizado PROCERGS)
           email = e-mail cadastrado no IdP
           roles = perfis (RT, ANALISTA_CBM, CENTRALADM...)

         Redireciona para o redirect_uri da SPA via fragment:
           https://<host>/solcbm/app
             #access_token=eyJ...
             &token_type=bearer
             &expires_in=3600
             &state=%2Fsome-state%3Bp1%3D1%3Bp2%3D2
```

```
[SISTEMA] OAuthService (angular-oauth2-oidc) detecta o fragment na URL →
          Extrai access_token
          ├─ authStorage.setItem('access_token', 'eyJ...')
          ├─ authStorage.setItem('expires_at', '...')
          └─ Dispara evento 'token_received'
```

---

## FASE 5 — Captura do Token e Verificação de Cadastro

### 5.1 — Evento token_received

```
[SISTEMA] Listener em AppComponent.configureAuth():
          evento 'token_received' disparado
          └─ oauthService.loadUserProfile()
             → GET https://meu.hml.rs.gov.br/userinfo
               Authorization: Bearer {access_token}
             → Popula claims: { cpf, name, email, ... }
             └─ verificaCadastro()     → FASE 5.2
```

---

### 5.2 — Método verificaCadastro()

**Objetivo:** Verificar se o usuário autenticado no IdP já tem cadastro no SOL e em qual estado está, direcionando-o para a tela correta.

**Classe/Método:** `AppComponent.verificaCadastro()`

```typescript
// app.component.ts — verificaCadastro (simplificado)
verificaCadastro() {
  const claims = this.oauthService.getIdentityClaims();
  if (!claims) return;                              // sem claims: encerra

  this.user  = claims['name'];                     // nome exibido no header
  const cpf  = claims['cpf'];
  const email = claims['email'];
  this.isReady = false;                            // exibe loading (RN-11)

  this.cadastroUsuarioService.buscarUsuario(cpf)   // GET /usuarios/{cpf}
    .subscribe({
      next: (usuario) => {
        // Sincroniza e-mail se divergente e status != EM_ANALISE (RN-06)
        if (email !== usuario.email
            && usuario.status !== StatusCadastroUsuarioEnum.EM_ANALISE) {
          this.atualizarUsuario(usuario);          // → FASE 6
        }

        this.setUsuarioLocalStorage(usuario);

        const status = StatusCadastroUsuarioEnum[usuario.status];
        if (status === StatusCadastroUsuarioEnum.INCOMPLETO) {
          this.router.navigate(['/cadastro']);      // RN-08
          return;
        }

        this.isReady = true;
        this.router.initialNavigation();
        this.getNotificacoes();                    // → FASE 7
      },
      error: (err) => {
        if (err.status === 404) {
          this.router.navigate(['/cadastro']);     // RN-08: não cadastrado
        } else {
          setTimeout(() => {
            this.alertService.show({ titulo: 'Erro', mensagem: 'Erro inesperado.' });
            this.isReady = true;
          }, 50);
        }
      }
    });
}
```

**Tela durante verificaCadastro:**
`isReady = false` → spinner `<app-loading id="loading">` exibido.

---

### 5.3 — Chamada backend: GET /usuarios/{cpf}

```
[SISTEMA] cadastroUsuarioService.buscarUsuario(cpf)
          └─ HttpClient GET  /solcbm/api/v1/usuarios/{cpf}
             Header: Authorization: Bearer eyJ...   (HttpAuthorizationInterceptor)
```

**Interceptor:** `HttpAuthorizationInterceptor`
**Arquivo:** `projects/cbm-shared/src/services/interceptors/http-authorization.interceptor.ts`

```typescript
// http-authorization.interceptor.ts (simplificado)
async handleAccess(req: HttpRequest<any>, next: HttpHandler): Promise<HttpEvent<any>> {
  let headers = {};
  req.headers.keys().forEach(key => headers[key] = req.headers.get(key));

  if (req.url.indexOf(AppSettings.baseUrl) !== -1) {  // RN-05: só URLs do backend
    const token = this.oauthService.getAccessToken();
    headers['Authorization'] = 'Bearer ' + token;
  }

  const authReq = req.clone({ setHeaders: headers });
  return next.handle(authReq).toPromise();
}
```

**RN acionada:** RN-05 — token injetado somente em `AppSettings.baseUrl = "/solcbm/api/v1"`.

---

### 5.4 — Processamento backend: UsuarioRN.consultaPorCpf()

```
[BACKEND] UsuarioRestImpl → GET /usuarios/{cpf}
          └─ @SOEAuthRest: valida Bearer token via introspecção no IdP
             └─ CidadaoSessionMB.setCidadaoED(...)  (populado com claims)
                └─ UsuarioRN.consultaPorCpf(cpf)
```

**Classe/Método:** `UsuarioRN.consultaPorCpf(String cpf)`
**Arquivo:** `SOLCBM.BackEnd16-06/.../usuario/UsuarioRN.java`

```java
// UsuarioRN.java — consultaPorCpf (simplificado)
@TransactionAttribute(TransactionAttributeType.SUPPORTS)  // RF-BE-12
public Usuario consultaPorCpf(String cpf) {
  if (cpf == null) return null;

  UsuarioED usuarioED = usuarioBD.consultarPorCpf(cpf);
  if (usuarioED == null) return null;       // → 404 no REST

  // RN-19: workaround timezone UTC/BRT
  usuarioED.getDtNascimento().set(Calendar.HOUR, 12);

  // Monta DTO completo com todas as coleções
  return BuilderUsuario.of(usuarioED)
    .comEnderecos(enderecoUsuarioRN.listarEnderecosUsuario(usuarioED))
    .comGraduacoes(graduacaoUsuarioRN.listarGraduacoesUsuario(usuarioED))
    .comEspecializacoes(especializacaoUsuarioRN.listarEspecializacoesUsuario(usuarioED))
    .comArquivoRG(Optional.ofNullable(usuarioED.getArquivoRG())
                          .map(a -> new Arquivo(a.getId(), a.getNomeArquivo()))
                          .orElse(null))
    .build();
}
```

**RN acionadas:**
- RF-BE-03: retorna `null` → REST retorna `404` se CPF não encontrado
- RN-19: workaround timezone `Calendar.HOUR = 12`

---

### 5.5 — Roteamento pós-verificação

```
Resultado da chamada GET /usuarios/{cpf}:

┌──────────────────────────────────────────────────────────────────────┐
│  HTTP 404 (não cadastrado)                                           │
│  └─ router.navigate(['/cadastro'])       [RN-08]                    │
│     Tela: formulário de cadastro         ────────────────────────   │
│                                                                      │
│  HTTP 200, status = INCOMPLETO                                       │
│  └─ router.navigate(['/cadastro'])       [RN-08]                    │
│     Tela: formulário de cadastro                                     │
│                                                                      │
│  HTTP 200, status = ANALISE_PENDENTE | EM_ANALISE                   │
│  │          | APROVADO | REPROVADO                                   │
│  ├─ isReady = true  → <app-sidenav> exibido                         │
│  ├─ router.initialNavigation()                                       │
│  └─ getNotificacoes()                    → FASE 7                   │
│     Tela: tela principal correspondente à rota                       │
└──────────────────────────────────────────────────────────────────────┘
```

**Tela exibida após verificação bem-sucedida:**

```html
<!-- app.component.html — estado isReady=true -->
<app-sidenav *ngIf="isReady; else loading" #sidenav [opened]="menu.menuOpened">
  <div side-content>
    <app-menu #menu
      [user]="user"                           <!-- nome do usuário logado -->
      [licenciamentoHabilitado]="licenciamentoHabilitado"
      (loginEvent)="login()"
      (logoutEvent)="logout(false)">
    </app-menu>
  </div>
  <div main-content>
    <app-page-header
      [user]="user"
      [notificacoes]="notificacoes"
      (eventLogin)="login()"
      (eventLogout)="logout($event)"
      (eventSelectNotificacao)="onSelectNotificacao($event)">
    </app-page-header>
    <router-outlet></router-outlet>     <!-- conteúdo da rota atual -->
    <app-page-footer></app-page-footer>
  </div>
</app-sidenav>
```

---

## FASE 6 — Sincronização de E-mail (condicional)

### Objetivo
Quando o e-mail registrado no SOL diverge do e-mail nas claims OIDC, o sistema atualiza automaticamente (exceto quando o cadastro está EM_ANALISE).

**Condição de ativação:**
`email_claims ≠ usuario.email` **E** `usuario.status ≠ EM_ANALISE`

**Classe/Método:** `AppComponent.atualizarUsuario()`

```typescript
// app.component.ts — atualizarUsuario (simplificado)
atualizarUsuario(usuario: Usuario) {
  usuario.email = this.oauthService.getIdentityClaims()['email']; // atualiza localmente

  this.cadastroUsuarioService.salvar(usuario)   // PUT /usuarios/{id}
    .pipe(finalize(() => this.loadingService.dismiss()))
    .subscribe(() => {
      // Sincroniza proprietário no sistema integrado (RN-07)
      this.cadastroUsuarioService
        .alteraProprietario(usuario.cpf, usuario.email, 'F')
        .subscribe({ error: () => {} });         // erros silenciosos (RN-07)
    });
}
```

**Backend ativado:**
`PUT /usuarios/{id}` → `UsuarioRN.alterar(Long id, Usuario)`
Verificação de concorrência (`ctrDthAtu`) — RN-11.

**RN acionadas:**
- RN-06: e-mail só sincronizado se `status ≠ EM_ANALISE`
- RN-07: `alteraProprietario('F')` chamado após `salvar()` com erros silenciosos

---

## FASE 7 — Carregamento de Notificações

### Objetivo
Carregar as notificações pendentes do usuário após autenticação bem-sucedida.

**Classe/Método:** `AppComponent.getNotificacoes()`

```typescript
// app.component.ts — getNotificacoes (simplificado)
getNotificacoes() {
  this.notificacaoService.consultarNotificacoes()
    .pipe(
      catchError(() => handleErrorAndContinue([]))  // RN-24: falha não bloqueia
    )
    .subscribe(notificacoes => {
      this.notificacoes = notificacoes;
    });
}
```

**Tela — exibição das notificações:**

```html
<!-- page-header.component.html — sino de notificações -->
<div *ngIf="user && isCidadao" class="btn-group notification" dropdown>

  <!-- Botão sino com badge de quantidade -->
  <a id="btnNotificacoes" dropdownToggle class="btn-notify">
    <span id="spanQuantidadeNotificacoes"
          *ngIf="qtdNotificacoes"
          class="badge">
      {{qtdNotificacoes}}               <!-- número de notificações não lidas -->
    </span>
    <i class="fa fa-bell fa-lg fa-fw icon"></i>
  </a>

  <!-- Dropdown com lista de notificações -->
  <ul id="dropdownNotificacoes"
      *dropdownMenu
      class="dropdown-menu dropdown-menu-right">
    <li *ngFor="let notificacao of notificacoes; let i=index"
        id="notificacao-{{i}}"
        (click)="onSelectNotificacao(notificacao)">
      {{ notificacao.mensagem }}
    </li>
  </ul>
</div>
```

### 7.1 — Seleção de notificação pelo usuário

```
[USUÁRIO] Clica no ícone <i class="fa fa-bell"> (id="btnNotificacoes")
          → dropdown #dropdownNotificacoes abre

[USUÁRIO] Clica em uma notificação (id="notificacao-N")
          → onSelectNotificacao(notificacao) disparado
```

```typescript
// page-header.component.ts — onSelectNotificacao (simplificado)
onSelectNotificacao(notificacao: Notificacao) {
  this.notificacoes = this.notificacoes.filter(n => n.id !== notificacao.id);
  notificacao.lida = true;
  this.notificacaoService.alterarNotificacao(notificacao).subscribe(); // persiste no backend

  // Roteamento pelo contexto (RF-FE-12)
  const rotas = {
    'CADASTRO':               '/cadastro',
    'INSTRUTOR':              '/cadastro',
    'LICENCIAMENTO_ACEITE':   '/licenciamento/meus-licenciamentos',
    'LICENCIAMENTO':          '/licenciamento/meus-licenciamentos',
    'FACT':                   '/fact/minhas-solicitacoes',
    'RECURSO':                '/licenciamento/meus-recursos',
  };
  this.router.navigate([rotas[notificacao.contexto]]);
}
```

**RN acionada:** RN-24 — falha no carregamento de notificações não bloqueia o acesso.

---

## FASE 8 — Proteção de Rotas (UsuarioAutenticadoGuard)

### Objetivo
Garantir que rotas protegidas só sejam acessadas por usuários com token válido, iniciando novo fluxo OIDC quando necessário.

**Classe:** `UsuarioAutenticadoGuard`
**Arquivo:** `projects/cbm-shared/src/guards/usuario-autenticado.guard.ts`

```typescript
// usuario-autenticado.guard.ts
@Injectable({ providedIn: 'root' })
export class UsuarioAutenticadoGuard implements CanActivate {

  canActivate(): boolean {
    this.verificaLogin();
    return true;   // RN-04: guard SEMPRE retorna true — proteção real é via OIDC
  }

  private verificaLogin(): void {
    const claims    = this.oauthService.getIdentityClaims();
    const hasToken  = this.oauthService.hasValidAccessToken();

    if (!hasToken && !claims) {
      this.oauthService.initImplicitFlow();              // → FASE 3
    } else if (!hasToken && claims) {
      this.oauthService.loadDiscoveryDocumentAndLogin();
    } else if (hasToken && !claims?.['name']) {
      this.oauthService.loadUserProfile();
    }
    // else: token + claims presentes — nenhuma ação
  }
}
```

**Configuração das rotas protegidas:**

```typescript
// app.routes.ts (simplificado)
const routes: Routes = [
  { path: '',           redirectTo: 'licenciamento', pathMatch: 'full' },
  {
    path: 'licenciamento',
    canActivate: [UsuarioAutenticadoGuard, LicenciamentoHabilitadoGuard],
    loadChildren: () => import('./licenciamento/...')
  },
  {
    path: 'cadastro',
    canActivate: [UsuarioAutenticadoGuard],
    loadChildren: () => import('./cadastro/...')
  },
  { path: '**', redirectTo: 'licenciamento' }
];

RouterModule.forRoot(routes, {
  useHash: true,               // hash-based routing (#/licenciamento)
  initialNavigation: false     // controlado manualmente por AppComponent
})
```

**RN acionada:** RN-04 — guard retorna `true` incondicionalmente; proteção real via OIDC redirect.

---

## FASE 9 — Controle de Autorização no Backend

### Objetivo
Validar o token Bearer em cada requisição e popular o contexto de segurança `CidadaoSessionMB` com os dados do usuário.

```
[BACKEND] Requisição REST recebida com header:
          Authorization: Bearer eyJhbGci...

          @SOEAuthRest (arqjava4 filter):
          ├─ Introspecta token no IdP
          ├─ Extrai claims (cpf, name, email, roles, permissoes)
          └─ Popula CidadaoSessionMB.setCidadaoED(cidadaoED)
                                               ↓
          Método de negócio executado com contexto disponível
```

**Classe:** `CidadaoSessionMB`
**Arquivo:** `SOLCBM.BackEnd16-06/.../seguranca/CidadaoSessionMB.java`

```java
// CidadaoSessionMB.java
@Named
@RequestScoped                               // nova instância por requisição
public class CidadaoSessionMB {

  private CidadaoED cidadaoED;
  public static final String SISTEMA = "SOLCBM";

  public CidadaoED getCidadaoED()              { return cidadaoED; }
  public void setCidadaoED(CidadaoED ed)       { this.cidadaoED = ed; }

  // Verifica se o CPF informado é do usuário logado
  public Boolean isUsuarioLogado(String cpf) {
    return cidadaoED != null && cidadaoED.getCpf().equals(cpf);
  }

  // Verifica permissão: tripla (SOLCBM, objeto, acao)  [RN-18]
  public Boolean hasPermission(String objeto, String acao) {
    return cidadaoED != null &&
           cidadaoED.getPermissoes().contains(
             new PermissaoED(SISTEMA, objeto, acao)
           );
  }
}
```

### 9.1 — Verificação de permissão por anotação @Permissao

```java
// Exemplo de uso da anotação no EJB
@Permissao(objeto = "VERIFICARCADASTRO", acao = "EDITAR")
public AnaliseCadastro incluirAnaliseCadastro(Cadastro cadastro) {
  // Interceptor verifica: cidadaoSessionMB.hasPermission("VERIFICARCADASTRO","EDITAR")
  // Se false → HTTP 403 FORBIDDEN
  ...
}
```

**RN acionada:** RN-18 — permissão verificada como tripla `(SISTEMA="SOLCBM", objeto, acao)`.

---

## FASE 10 — Silent Refresh Automático

### Objetivo
Renovar o access_token antes do vencimento via `<iframe>` oculto, sem interação do usuário.

```
[SISTEMA] OAuthService.setupAutomaticSilentRefresh()
          (chamado em configureAuth())

          Antes da expiração do token:
          └─ Cria <iframe> oculto apontando para:
             https://meu.hml.rs.gov.br/oauth2/authorize
               ?response_type=token
               &prompt=none        (sem tela de login)
               &redirect_uri=https://<host>/solcbm/app/silent-refresh.html

          └─ silent-refresh.html recebe o fragment com novo token:
             parent.postMessage(location.hash, location.origin);

          └─ OAuthService processa o postMessage e atualiza localStorage['appToken']
```

**Arquivo:** `src/silent-refresh.html`

```html
<!-- silent-refresh.html -->
<script>
  parent.postMessage(location.hash, location.origin);
</script>
```

**Comportamento em falha:**
- Se o silent refresh falhar (sessão expirada no IdP): evento `session_terminated` disparado
- Listener registrado em `configureAuth()` faz apenas `console.log('Your session has been terminated!')`
- **Sem redirecionamento automático** (RN-23)

**Tela neste momento:** o usuário não percebe nada — o `<iframe>` é invisível.

---

## FASE 11 — Logout

### Objetivo
Encerrar a sessão do usuário no SOL e no IdP, removendo todos os dados de sessão do localStorage.

**Ponto de entrada no template:**

```html
<!-- page-header.component.html — desktop -->
<ul id="dropdownUsuario" *dropdownMenu class="dropdown-menu">
  <li>
    <a id="linkCadastro" class="dropdown-item"
       (click)="onNavegarCadastro()">Sua conta</a>
  </li>
  <li>
    <a class="dropdown-item"
       (click)="logout(false)">Sair</a>     <!-- redireciona=false -->
  </li>
</ul>
<a (click)="logout(false)">
  <i class="fa fa-sign-out fa-lg fa-fw icon"></i>   <!-- ícone de saída -->
</a>

<!-- menu.component.html — mobile -->
<app-menu-item (eventClick)="onLogout()"
               [item]="sairMenuItem">      <!-- label: "Sair", icon: sign-out -->
</app-menu-item>
```

```
[USUÁRIO] Clica em "Sair" (dropdown #dropdownUsuario → item Sair)
          ou no ícone <i class="fa fa-sign-out">
          ou no item de menu mobile "Sair"
```

```
[SISTEMA] page-header.component → emite eventLogout(false)
          ↓
          app.component → logout(redireciona: boolean)
```

**Classe/Método:** `AppComponent.logout()`

```typescript
// app.component.ts — logout
logout(redireciona: boolean) {
  if (redireciona) {
    // Define URL para onde o IdP redirecionará após logout
    this.oauthService.logoutUrl = window.location.origin + '/solcbm/app';
  }
  this.oauthService.logOut();        // invalida sessão no IdP (end_session_endpoint)
  this.authStorage.clean();          // localStorage.removeItem('appToken')
}
```

**Efeito em localStorage:**
```
Antes:  localStorage['appToken'] = { access_token: "eyJ...", expires_at: "...", ... }
Depois: localStorage['appToken'] = undefined (removido completamente)
```

**RN acionadas:**
- RF-FE-09: `logoutUrl` definido apenas se `redireciona = true`
- RN-03: `authStorage.clean()` remove completamente o `appToken`

---

## FASE 12 — Reentrada: Sessão SSO Existente

### Objetivo
Usuário que já estava logado no IdP em outra aba ou sessão recente — não precisa digitar credenciais novamente.

```
[SISTEMA] Na inicialização, configureAuth() detecta claims existentes:
          claims = oauthService.getIdentityClaims()  → não nulo

          └─ oauthService.loadDiscoveryDocumentAndLogin()
             └─ Redireciona para o IdP com prompt=none (implícito)
                ├─ Se sessão SSO ativa: IdP retorna token sem tela de login
                └─ Se sessão SSO expirada: IdP exibe tela de login → FASE 3
```

**Tela neste momento:** spinner `<app-loading>` enquanto a validação ocorre.
**Resultado:** se o token for renovado com sucesso, o evento `token_received` dispara `verificaCadastro()`.

---

## FASE 13 — Controle de Estado isReady (Diagrama Completo)

### Objetivo
Garantir que o usuário nunca veja conteúdo parcialmente carregado.

```
Estado isReady ao longo do processo:

ngOnInit() inicia                    → isReady = false  (loading exibido)
configService.getConfig() finalize   → isReady = true
NavigationStart                      → isReady = false
NavigationEnd / NavigationCancel     → isReady = true
GuardsCheckEnd                       → isReady = false
GuardsCheckStart                     → isReady = true
verificaCadastro() inicia GET        → isReady = false
  ├─ status INCOMPLETO / 404         → navigate('/cadastro')  [isReady permanece false]
  ├─ status outro → initialNavigation → isReady = true
  └─ erro inesperado                 → isReady = true (após 50ms)
```

**Implementação no template:**
```html
<!-- EXIBIÇÃO CONTROLADA POR isReady -->
<app-sidenav *ngIf="isReady; else loading">
  <!-- toda a aplicação -->
</app-sidenav>

<ng-template #loading>
  <app-loading id="loading"></app-loading>
</ng-template>
```

---

## Tabela de Rastreabilidade Completa

| Fase | Ação do Usuário | Elemento de Tela | Classe/Método | RN(s) |
|------|----------------|-----------------|---------------|-------|
| 1.1 | Navega para URL | Barra de endereço | `AppComponent.ngOnInit()` | — |
| 1.2 | — (automático) | `<app-loading id="loading">` | `AppConfigService.getConfig()` | RF-FE-01, RN-11 |
| 1.3 | — (automático) | `<app-loading>` | `AppComponent.configureAuth()` | RN-02, RN-03, RN-23 |
| 3 | Clica "Entrar" | `<a id="btnLogin">` (desktop) / `loginMenuItem` (mobile) | `AppComponent.login()` → `initImplicitFlow()` | RN-01 |
| 4 | Preenche credenciais IdP | Campos do IdP PROCERGS | Externo (IdP) | — |
| 5.1 | — (automático) | `<app-loading>` | `OAuthService` evento `token_received` → `loadUserProfile()` | — |
| 5.2 | — (automático) | `<app-loading>` | `AppComponent.verificaCadastro()` | RN-06, RN-08, RN-11 |
| 5.3 | — (automático) | — | `HttpAuthorizationInterceptor` | RN-05 |
| 5.4 | — (automático) | — | `UsuarioRN.consultaPorCpf()` | RN-19, RF-BE-03 |
| 5.5a | — (automático) | Formulário `/cadastro` | `router.navigate(['/cadastro'])` | RN-08 |
| 5.5b | — (automático) | Tela principal + header com nome | `router.initialNavigation()` | RN-11 |
| 6 | — (automático) | — | `AppComponent.atualizarUsuario()` → `PUT /usuarios/{id}` | RN-06, RN-07 |
| 7 | Clica no ícone sino | `<a id="btnNotificacoes">` | `getNotificacoes()` → `notificacaoService` | RN-24 |
| 7.1 | Clica em notificação | `<li id="notificacao-N">` | `onSelectNotificacao()` | RF-FE-12 |
| 8 | Acessa rota protegida | `<router-outlet>` | `UsuarioAutenticadoGuard.canActivate()` | RN-04 |
| 9 | — (por requisição) | — | `CidadaoSessionMB.hasPermission()` + `@Permissao` | RN-18 |
| 10 | — (automático) | Invisível (iframe) | `oauthService.setupAutomaticSilentRefresh()` | RN-23 |
| 11 | Clica "Sair" | `<a class="dropdown-item">Sair</a>` / ícone `fa-sign-out` / `sairMenuItem` (mobile) | `AppComponent.logout()` | RN-03 |
| 12 | — (automático, sessão ativa) | `<app-loading>` | `loadDiscoveryDocumentAndLogin()` | — |
| 13 | Qualquer navegação | `<app-loading>` / conteúdo principal | `isReady` flag via Router events | RN-11 |

---

## Diagrama Textual do Fluxo Principal

```
USUÁRIO                      ANGULAR (Frontend)              IdP PROCERGS          BACKEND Java EE
   │                               │                               │                      │
   │── acessa URL ────────────────>│                               │                      │
   │                    ngOnInit() │                               │                      │
   │                    getConfig()│── GET /config ───────────────────────────────────────>│
   │<── <app-loading> ─────────────│<──────────────────────────────────────────────────────│
   │                    configureAuth()                            │                      │
   │                    [sem token]│                               │                      │
   │                    initImplicitFlow()                         │                      │
   │                               │── redirect ──────────────────>│                      │
   │<──────── tela de login IdP ───│              (PROCERGS)       │                      │
   │                               │                               │                      │
   │── preenche credenciais ───────────────────────────────────────>│                      │
   │                               │<── access_token (fragment) ───│                      │
   │<── <app-loading> ─────────────│                               │                      │
   │              token_received   │                               │                      │
   │              loadUserProfile()│─── GET /userinfo ─────────────>│                      │
   │                               │<── claims (cpf,name,email) ───│                      │
   │              verificaCadastro()                               │                      │
   │                               │── GET /usuarios/{cpf} ────────────────────────────────>│
   │                               │                               │   UsuarioRN            │
   │                               │                               │   .consultaPorCpf()    │
   │                               │<── 200 + Usuario DTO ─────────────────────────────────│
   │                               │                               │                      │
   │              [status=INCOMPLETO] → router.navigate('/cadastro')│                      │
   │<── formulário de cadastro ────│                               │                      │
   │              [status=APROVADO] → isReady=true, initialNavigation()                   │
   │<── tela principal + header ───│                               │                      │
   │                    getNotificacoes()                          │                      │
   │<── sino com badge ────────────│                               │                      │
   │                               │                               │                      │
   │── clica "Sair" ──────────────>│                               │                      │
   │                    logout()   │                               │                      │
   │                    logOut()   │── end_session ────────────────>│                      │
   │                    clean()    │ (remove localStorage['appToken'])                    │
   │<── tela de loading ───────────│                               │                      │
```

---

## Índice de Elementos de Tela × Ação × Classe

| ID do Elemento | Componente Angular | Ação do Usuário | Método Ativado |
|---------------|-------------------|----------------|----------------|
| `id="loading"` (app-loading) | `AppComponent` template | — (exibido automaticamente) | Controlado por `isReady` |
| `id="btnLogin"` | `page-header.component.html` | Clique "Entrar" (desktop) | `AppComponent.login()` → `initImplicitFlow()` |
| `loginMenuItem` | `menu.component.html` | Clique "Entrar" (mobile) | `MenuComponent.onLogin()` → emit `loginEvent` → `AppComponent.login()` |
| `id="btnUsuario"` | `page-header.component.html` | Clique no nome do usuário (dropdown) | Abre `#dropdownUsuario` |
| `id="dropdownUsuario"` | `page-header.component.html` | — (dropdown) | — |
| `id="linkCadastro"` | `page-header.component.html` | Clique "Sua conta" | `router.navigate(['/cadastro'])` |
| `class="dropdown-item"` Sair | `page-header.component.html` | Clique "Sair" | `PageHeaderComponent.logout(false)` → emit → `AppComponent.logout(false)` |
| `class="fa fa-sign-out"` | `page-header.component.html` | Clique ícone saída | `AppComponent.logout(false)` |
| `sairMenuItem` | `menu.component.html` | Clique "Sair" (mobile) | `MenuComponent.onLogout()` → emit → `AppComponent.logout(false)` |
| `id="btnNotificacoes"` | `page-header.component.html` | Clique ícone sino | Abre `#dropdownNotificacoes` |
| `id="spanQuantidadeNotificacoes"` | `page-header.component.html` | — (badge) | Exibido se `qtdNotificacoes > 0` |
| `id="dropdownNotificacoes"` | `page-header.component.html` | — (dropdown) | — |
| `id="notificacao-N"` | `page-header.component.html` | Clique em notificação | `onSelectNotificacao(notificacao)` |
| `<router-outlet>` | `app.component.html` | Navegação | Renderiza o componente da rota ativa |
| `<app-menu>` sidenav | `app.component.html` | Clique menu hamburger | `MenuComponent.menuToggle()` |
