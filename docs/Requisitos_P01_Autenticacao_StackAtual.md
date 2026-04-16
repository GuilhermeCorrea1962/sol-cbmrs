# Especificação de Requisitos — P01: Autenticação e Controle de Acesso
## Sistema SOL/CBM-RS — Stack Atual (Java EE + Angular + OIDC Implicit Flow)

**Versão:** 1.0
**Data:** 2026-03-04
**Destinatário:** Equipe de Desenvolvimento Java
**Processo:** P01 — Autenticação, Autorização e Gerenciamento de Sessão
**Base:** Código-fonte SOLCBM.FrontEnd16-06 / SOLCBM.BackEnd16-06

> **Nota:** Este documento descreve os requisitos do sistema **mantendo a stack tecnológica atual**:
> Angular + `angular-oauth2-oidc` (Implicit Flow) no frontend,
> Java EE (JAX-RS + EJB + CDI + JPA) no backend,
> servidor de aplicação WildFly/JBoss.
> Não há alteração de tecnologia, apenas documentação completa dos comportamentos exigidos.

---

## Índice

1. [Visão Geral e Objetivos](#1-visão-geral-e-objetivos)
2. [Glossário](#2-glossário)
3. [Requisitos Funcionais — Frontend](#3-requisitos-funcionais--frontend)
4. [Requisitos Funcionais — Backend](#4-requisitos-funcionais--backend)
5. [Regras de Negócio](#5-regras-de-negócio)
6. [Modelo de Dados](#6-modelo-de-dados)
7. [Contratos de API REST](#7-contratos-de-api-rest)
8. [Stack Tecnológica](#8-stack-tecnológica)
9. [Requisitos Não Funcionais](#9-requisitos-não-funcionais)
10. [Critérios de Aceitação](#10-critérios-de-aceitação)
11. [Restrições e Premissas](#11-restrições-e-premissas)

---

## 1. Visão Geral e Objetivos

### 1.1 Contexto

O sistema SOL (Sistema de Outorga de Licenciamento) do CBM-RS gerencia o ciclo completo de licenciamento de segurança contra incêndio. O processo P01 é a porta de entrada de todos os demais: sem autenticação válida, nenhuma operação de licenciamento é executável.

### 1.2 Objetivos do P01

1. Autenticar o usuário via OIDC Implicit Flow, delegando ao provedor de identidade estadual.
2. Verificar o status do cadastro do usuário na base SOL após autenticação.
3. Direcionar o usuário à tela correta conforme seu status de cadastro.
4. Sincronizar dados do usuário (e-mail) com as claims do IdP quando divergentes.
5. Autorizar chamadas à API backend via token Bearer em cada requisição.
6. Controlar permissões de acesso por objeto/ação conforme o perfil do usuário.

### 1.3 Atores

| Ator | Identificação | Acesso |
|------|--------------|--------|
| **Cidadão / RT** | CPF autenticado no IdP estadual | Portal público e funcionalidades conforme status de cadastro |
| **Fiscal CBM** | CPF + perfil SOE (Sistema Operacional Estadual) | Análise técnica, laudos |
| **ADM CBM** | CPF + perfil SOE | Gestão de cadastros, distribuição |
| **Sistema SOL** | Backend Java EE | Valida token em cada requisição via `CidadaoSessionMB` |
| **IdP Estadual** | `meu.hml.rs.gov.br` (homologação) | Autentica e emite tokens OIDC |

---

## 2. Glossário

| Termo | Definição |
|-------|-----------|
| **OIDC** | OpenID Connect — protocolo de identidade sobre OAuth 2.0 |
| **Implicit Flow** | Fluxo OAuth 2.0 onde o token é retornado diretamente no fragmento de URL após redirect |
| **Access Token** | JWT emitido pelo IdP, armazenado em `localStorage['appToken']`, usado como Bearer nas chamadas API |
| **Claims** | Atributos do usuário presentes no payload do JWT: `cpf`, `name`, `email`, `sub` |
| **`CidadaoSessionMB`** | Bean CDI `@RequestScoped` que carrega o contexto de segurança do usuário para cada requisição |
| **`CidadaoED`** | Entity Data do cidadão autenticado: nome, cpf, email, permissões, papéis |
| **`PermissaoED`** | Tripla `(SISTEMA="SOLCBM", objeto, acao)` que representa uma permissão específica |
| **`TipoPapel`** | Enum que representa o papel do usuário no sistema (cidadão, fiscal, ADM, etc.) |
| **`StatusCadastro`** | Enum de estados do cadastro: INCOMPLETO, ANALISE_PENDENTE, EM_ANALISE, APROVADO, REPROVADO |
| **`ctrDthAtu`** | Timestamp de última atualização — usado para controle de concorrência otimista |
| **`@Permissao`** | Anotação Java EE customizada que declara o par (objeto, ação) necessário para executar um método |
| **`@SOEAuthRest`** | Anotação customizada para endpoints acessíveis apenas por usuários autenticados via SOE |
| **SOE** | Sistema Operacional Estadual — sistema de usuários internos do governo do RS |
| **RT** | Responsável Técnico — profissional habilitado que representa o estabelecimento no licenciamento |
| **`NullValidationHandler`** | Implementação da biblioteca `angular-oauth2-oidc` que desabilita a validação local do JWT no frontend |
| **Silent Refresh** | Mecanismo de renovação automática do token via `<iframe>` oculto, sem interação do usuário |

---

## 3. Requisitos Funcionais — Frontend

---

### RF-FE-01 — Carregamento Dinâmico da Configuração de Autenticação

**Prioridade:** Crítica
**Classe:** `AppComponent` (`src/app/app.component.ts`)
**Método:** `ngOnInit()` → `configService.getConfig()`

**Descrição:** Ao inicializar, o `AppComponent` deve buscar a configuração de autenticação via `AppConfigService.getConfig()` antes de configurar o `OAuthService`. A configuração retornada pelo servidor inclui o objeto `authConfig` com `issuer`, `clientId`, `redirectUri` e demais parâmetros OIDC.

**Comportamento obrigatório:**
- `redirectUri` deve ser construído como: `window.location.origin + authConfig.redirectUri`
- Se a URL atual contiver contexto (verificado por `isUrlContexto()`), o `redirectUri` deve ser ajustado via `substituiContexto()`
- `postLogoutRedirectUri` deve ser igual ao `redirectUri`
- `silentRefreshRedirectUri` deve ser: `redirectUri + '/silent-refresh.html'`
- O flag `isReady` deve permanecer `false` até a configuração ser obtida (`finalize(() => this.isReady = true)`)
- Após carregar a config, os flags `licenciamentoHabilitado`, `riscoMedioHabilitado` e `tamanhoMaxArquivo` devem ser gravados nos stores respectivos

**Critério de Aceitação:** Sistema não exibe conteúdo ao usuário enquanto a configuração não é carregada. Configuração de autenticação é sempre obtida do servidor, nunca hardcoded.

---

### RF-FE-02 — Configuração do OAuthService (Implicit Flow)

**Prioridade:** Crítica
**Classe:** `AppComponent`
**Método:** `configureAuth(authConfig: AuthConfig)`

**Descrição:** O método `configureAuth()` configura o `OAuthService` da biblioteca `angular-oauth2-oidc` para operar com Implicit Flow.

**Comportamento obrigatório — exatamente na seguinte ordem:**
1. `oauthService.configure(authConfig)` — aplica a configuração recebida
2. `oauthService.setStorage(authStorage)` — usa `AuthStorageService` como storage (localStorage)
3. `oauthService.tokenValidationHandler = new NullValidationHandler()` — **desabilita validação local do JWT**
4. Verifica se há claims existentes (`getIdentityClaims()`):
   - **Se há claims:** extrai `name`, chama `loadDiscoveryDocumentAndLogin()`, e se há token válido chama `verificaCadastro()`
   - **Se não há claims:** chama `loadDiscoveryDocumentAndTryLogin()` e em seguida (tanto em sucesso quanto em falha) chama `router.initialNavigation()`
5. `oauthService.setupAutomaticSilentRefresh()` — ativa renovação automática de token
6. Registra listener para evento `session_terminated` — loga mensagem no console
7. Registra listener para evento `token_received` — chama `oauthService.loadUserProfile()` e depois `verificaCadastro()`

**Parâmetros de configuração obrigatórios (provenientes do ambiente):**
- `issuer`: URL do IdP (ex.: `https://meu.hml.rs.gov.br`)
- `clientId`: ID do cliente OIDC registrado no IdP
- `scope`: `openid public_profile email name cpf birthdate phone_number`
- `sessionChecksEnabled`: `false`
- `showDebugInformation`: `true` (habilitado para facilitar diagnóstico)

**Critério de Aceitação:** `NullValidationHandler` é usado — a validação de assinatura do JWT **não** é realizada no frontend. O comportamento de login/renovação respeita exatamente a lógica de ramificação acima.

---

### RF-FE-03 — Armazenamento do Token em localStorage

**Prioridade:** Crítica
**Classe:** `AuthStorageService` (`src/app/auth-storage.service.ts`)

**Descrição:** O `AuthStorageService` implementa a interface de storage da biblioteca `angular-oauth2-oidc`, persistindo todos os dados de sessão OIDC em uma única chave do `localStorage` chamada `appToken`.

**Comportamento obrigatório:**

| Método | Comportamento |
|--------|--------------|
| `constructor()` | Verifica se `localStorage['appToken']` existe; se não, cria com `'{}'` |
| `getItem(key)` | Parse do JSON em `localStorage['appToken']`, retorna `store[key]` ou `null` |
| `setItem(key, data)` | Parse do JSON, atribui `store[key] = data`, serializa de volta ao localStorage |
| `removeItem(key)` | Parse do JSON, deleta `store[key]`, serializa de volta |
| `clean()` | Chama `localStorage.removeItem('appToken')` — remove todo o objeto |

**Estrutura em localStorage:**
```json
// localStorage['appToken']:
{
  "access_token": "eyJ...",
  "id_token": "eyJ...",
  "expires_at": "1234567890000",
  "token_type": "bearer",
  "nonce": "...",
  "session_state": "..."
}
```

**Critério de Aceitação:** Múltiplas chamadas a `setItem` acumulam chaves dentro do mesmo objeto JSON — não substituem o objeto inteiro. `clean()` remove completamente o objeto do localStorage.

---

### RF-FE-04 — Guard de Rotas Autenticadas

**Prioridade:** Crítica
**Classe:** `UsuarioAutenticadoGuard` (`projects/cbm-shared/src/guards/usuario-autenticado.guard.ts`)

**Descrição:** Guard Angular que protege rotas que requerem autenticação. Implementa `CanActivate`.

**Comportamento obrigatório:**
- `canActivate()` **sempre retorna `true`** — não bloqueia a navegação Angular
- O método `verificaLogin()` é chamado internamente com a seguinte lógica de ramificação:

```
claims = oauthService.getIdentityClaims()
hasToken = oauthService.hasValidAccessToken()

SE (não hasToken E não claims)  → oauthService.initImplicitFlow()
SE (não hasToken E tem claims)  → oauthService.loadDiscoveryDocumentAndLogin()
SE (hasToken E não claims.name) → oauthService.loadUserProfile()
ELSE                            → (token e claims presentes, nenhuma ação)
```

**Implicação arquitetural importante:** Como o guard sempre retorna `true`, a proteção real de acesso é feita pelo próprio `OAuthService` (que redireciona para o IdP quando não há token) e pela lógica de `verificaCadastro()` no `AppComponent`.

**Critério de Aceitação:** Usuário sem token ao tentar acessar rota protegida é redirecionado ao IdP via `initImplicitFlow()`. A rota Angular não é bloqueada em nível de guard — o redirecionamento acontece via protocolo OIDC.

---

### RF-FE-05 — Interceptor de Autorização HTTP

**Prioridade:** Crítica
**Classe:** `HttpAuthorizationInterceptor` (`projects/cbm-shared/src/services/interceptors/http-authorization.interceptor.ts`)

**Descrição:** Interceptor Angular HTTP que adiciona o header `Authorization: Bearer {token}` em todas as requisições destinadas ao backend SOL.

**Comportamento obrigatório:**
- Intercepta toda requisição HTTP da aplicação
- **Condição de injeção:** `request.url.indexOf(AppSettings.baseUrl) !== -1`
  - Se a URL da requisição contiver `AppSettings.baseUrl` → adiciona o header Authorization
  - Caso contrário → passa a requisição sem modificação (chamadas a APIs externas não recebem o token)
- Preserva todos os headers existentes da requisição original (`request.headers.keys()`)
- Adiciona: `Authorization: Bearer ` + `oauthService.getAccessToken()`
- A implementação usa `async/await` internamente convertido para `Observable` via `fromPromise()`

**Critério de Aceitação:** Chamada a qualquer endpoint sob `AppSettings.baseUrl` contém `Authorization: Bearer eyJ...`. Chamada a URL externa (ex.: IdP para discovery document) não recebe o header.

---

### RF-FE-06 — Verificação de Cadastro Pós-Login

**Prioridade:** Crítica
**Classe:** `AppComponent`
**Método:** `verificaCadastro()`

**Descrição:** Após a obtenção do token OIDC (evento `token_received`), o sistema verifica o cadastro do usuário no SOL usando o CPF extraído das claims.

**Comportamento obrigatório — fluxo completo:**

```
claims = oauthService.getIdentityClaims()
SE não claims → retorna (encerra)

user = claims['name']    // exibe nome no header
cpf  = claims['cpf']
email = claims['email']
isReady = false          // exibe loading

cadastroUsuarioService.buscarUsuario(cpf)
  → Sucesso (usuário encontrado):
      usuario = retorno
      SE (email das claims ≠ usuario.email)
         E (usuario.status ≠ 'EM_ANALISE')
         → atualizarUsuario(usuario)   // sincroniza email
      setUsuarioLocalStorage(usuario)
      status = StatusCadastroUsuarioEnum[usuario.status]
      SE (status === INCOMPLETO)
         → router.navigate(['/cadastro'])
         → retorna
      isReady = true
      router.initialNavigation()
      getNotificacoes()

  → Erro 404 (não cadastrado):
      → router.navigate(['/cadastro'])

  → Outro erro:
      → setTimeout 50ms → alertService.show({ titulo: 'Erro', mensagem: 'Erro inesperado.' })
      → isReady = true
      → ao clicar OK → router.navigate(['/'])
```

**Critério de Aceitação:**
- Usuário com status INCOMPLETO ou não cadastrado (404) é redirecionado para `/cadastro`
- Usuário com qualquer outro status (ANALISE_PENDENTE, EM_ANALISE, APROVADO, REPROVADO) tem `initialNavigation()` chamado normalmente
- O e-mail **não** é sincronizado quando o status é EM_ANALISE

---

### RF-FE-07 — Sincronização de E-mail com o IdP

**Prioridade:** Alta
**Classe:** `AppComponent`
**Método:** `atualizarUsuario(usuario: Usuario)`

**Descrição:** Quando o e-mail registrado no SOL difere do e-mail nas claims OIDC (e o status não é EM_ANALISE), o sistema atualiza automaticamente o e-mail do usuário.

**Comportamento obrigatório:**
1. Atualiza `usuario.email` com o e-mail das claims
2. Chama `cadastroUsuarioService.salvar(usuario)` → `PUT /usuarios/{id}`
3. Na resposta de sucesso de `salvar()`, chama `cadastroUsuarioService.alteraProprietario(cpf, email, 'F')`
   - `'F'` indica pessoa física
   - Este método sincroniza o proprietário em outro sistema integrado
4. Erros em `alteraProprietario` são ignorados silenciosamente (sem alerta ao usuário)
5. `loadingService.dismiss` é chamado no `finalize` de `salvar()`

**Critério de Aceitação:** Usuário que alterou e-mail no IdP terá o e-mail atualizado no próximo login, exceto quando status é EM_ANALISE. A integração com `alteraProprietario` é chamada após o sucesso do `salvar`.

---

### RF-FE-08 — Login Explícito

**Prioridade:** Alta
**Classe:** `AppComponent`
**Método:** `login()`

**Descrição:** Método chamado por botão de login explícito na interface (quando disponível).

**Comportamento:**
```typescript
login() {
  this.oauthService.initImplicitFlow('/some-state;p1=1;p2=2');
}
```

O parâmetro de state é fixo: `'/some-state;p1=1;p2=2'`.

**Critério de Aceitação:** Clique no botão "Entrar" redireciona o browser para o IdP via Implicit Flow.

---

### RF-FE-09 — Logout

**Prioridade:** Alta
**Classe:** `AppComponent`
**Método:** `logout(redireciona: boolean)`

**Descrição:** Encerra a sessão do usuário.

**Comportamento obrigatório:**
```typescript
logout(redireciona: boolean) {
  if (redireciona) {
    this.oauthService.logoutUrl = window.location.origin + '/solcbm/app';
  }
  this.oauthService.logOut();
  this.authStorage.clean();
}
```

- Se `redireciona = true`: define `logoutUrl` para `/solcbm/app` antes de deslogar
- `oauthService.logOut()` invalida a sessão no IdP (se `end_session_endpoint` disponível) e limpa o OAuthService
- `authStorage.clean()` remove `localStorage['appToken']` completamente

**Critério de Aceitação:** Após logout, `localStorage['appToken']` não existe. Tentativa de acessar rota protegida inicia novo fluxo de autenticação.

---

### RF-FE-10 — Silent Refresh Automático

**Prioridade:** Alta
**Classe:** `AppComponent` via `OAuthService`
**Método:** `oauthService.setupAutomaticSilentRefresh()`

**Descrição:** O sistema deve renovar automaticamente o token antes de sua expiração usando um `<iframe>` oculto que faz novo Implicit Flow sem interrupção do usuário.

**Comportamento obrigatório:**
- `setupAutomaticSilentRefresh()` é chamado em `configureAuth()` incondicionalmente
- O arquivo `silent-refresh.html` deve estar disponível em `{redirectUri}/silent-refresh.html`
- Em caso de falha no silent refresh, o sistema não toma ação automática (o evento `session_terminated` pode ser disparado pelo IdP)
- O listener de `session_terminated` faz apenas `console.log('Your session has been terminated!')` — sem ação de navegação

**Critério de Aceitação:** Token renovado automaticamente enquanto sessão no IdP está ativa. Log `'Your session has been terminated!'` aparece no console quando a sessão IdP expira.

---

### RF-FE-11 — Controle de Estado de Carregamento (isReady)

**Prioridade:** Alta
**Classe:** `AppComponent`
**Flag:** `isReady: boolean`

**Descrição:** O flag `isReady` controla a exibição do conteúdo principal vs. tela de loading.

**Transições de estado obrigatórias:**

| Evento | Estado de `isReady` |
|--------|-------------------|
| `ngOnInit()` inicia | `false` (via `setUsuarioLocalStorage(null)`) |
| `configService.getConfig()` completa (`finalize`) | `true` |
| `NavigationStart` ou `GuardsCheckEnd` | `false` |
| `NavigationEnd`, `NavigationCancel` ou `GuardsCheckStart` | `true` |
| `verificaCadastro()` inicia chamada API | `false` |
| Usuário INCOMPLETO/404: antes de `navigate(['/cadastro'])` | permanece `false` |
| Usuário com outro status: após `router.initialNavigation()` | `true` |
| Erro inesperado na verificação | `true` (após setTimeout de 50ms) |

**Critério de Aceitação:** Usuário nunca vê conteúdo parcialmente carregado. A tela de loading permanece enquanto operações assíncronas estão em curso.

---

### RF-FE-12 — Consulta e Exibição de Notificações

**Prioridade:** Média
**Classe:** `AppComponent`
**Método:** `getNotificacoes()` e `onSelectNotificacao(notificacao)`

**Descrição:** Após autenticação bem-sucedida (usuário com status diferente de INCOMPLETO), o sistema carrega as notificações pendentes do usuário.

**Comportamento obrigatório:**
- `notificacaoService.consultarNotificacoes()` é chamado após `router.initialNavigation()`
- Erros na consulta de notificações são tratados com `handleErrorAndContinue([])` — falha não interrompe o login
- Ao selecionar uma notificação:
  1. Remove da lista local (`filter(noti => noti.id !== notificacao.id)`)
  2. Marca como lida (`notificacao.lida = true`)
  3. Chama `notificacaoService.alterarNotificacao(notificacao)` — persiste no backend
  4. Navega para a rota correspondente ao `contexto` da notificação:

| Contexto | Rota |
|----------|------|
| `CADASTRO` | `/cadastro` |
| `INSTRUTOR` | `/cadastro` |
| `LICENCIAMENTO_ACEITE` | `/licenciamento/meus-licenciamentos` |
| `LICENCIAMENTO` | `/licenciamento/meus-licenciamentos` |
| `FACT` | `/fact/minhas-solicitacoes` |
| `RECURSO` | `/licenciamento/meus-recursos` |

**Critério de Aceitação:** Falha ao carregar notificações não bloqueia o acesso ao sistema. Notificação marcada como lida persiste no backend.

---

## 4. Requisitos Funcionais — Backend

---

### RF-BE-01 — Contexto de Segurança por Requisição (CidadaoSessionMB)

**Prioridade:** Crítica
**Classe:** `CidadaoSessionMB` (`com.procergs.solcbm.seguranca`)
**Escopo CDI:** `@RequestScoped` / `@Named`

**Descrição:** Para cada requisição HTTP recebida pelo backend, deve existir uma instância de `CidadaoSessionMB` carregada com os dados do cidadão autenticado. Este bean é o único ponto de verdade sobre quem está fazendo a requisição.

**Comportamento obrigatório:**
- `getCidadaoED()` / `setCidadaoED(CidadaoED)` — getter/setter do contexto do cidadão
- `isUsuarioLogado(String cpf)` — compara o CPF fornecido com o CPF do `CidadaoED` corrente; retorna `Boolean`
- `hasPermission(String objeto, String acao)` — verifica se `getCidadaoED().getPermissoes()` contém `new PermissaoED("SOLCBM", objeto, acao)`
- Constante `SISTEMA = "SOLCBM"` — identificador do sistema no conjunto de permissões

**Premissa de inicialização:** Um filtro/interceptor JAX-RS (não incluído neste escopo) popula o `CidadaoSessionMB` a partir do token Bearer recebido no header `Authorization` antes de qualquer método de negócio ser executado.

**Critério de Aceitação:** Qualquer EJB que injete `CidadaoSessionMB` e chame `getCidadaoED()` obtém o contexto do usuário da requisição atual, sem compartilhamento entre requisições concorrentes.

---

### RF-BE-02 — Entidade de Dados do Cidadão (CidadaoED)

**Prioridade:** Crítica
**Classe:** `CidadaoED` (`com.procergs.solcbm.seguranca`)

**Descrição:** Objeto de transferência de dados do cidadão autenticado, populado a partir do token OIDC e/ou do banco de dados SOL.

**Campos obrigatórios:**

| Campo | Tipo | Fonte |
|-------|------|-------|
| `nome` | `String` | Claims OIDC (`name`) |
| `cpf` | `String` | Claims OIDC (`cpf`) |
| `dtNascimento` | `Calendar` | Claims OIDC (`birthdate`) |
| `email` | `String` | Claims OIDC (`email`) |
| `telefone` | `String` | Claims OIDC (`phone_number`) |
| `permissoes` | `Set<PermissaoED>` | Base SOL / SOE (inicializado como `HashSet` vazio) |
| `papeis` | `List<TipoPapel>` | Base SOL / SOE |

**Métodos obrigatórios:**
- `nullInstance()` — método factory estático que retorna instância com `email = ""` (usado para evitar NullPointerException antes da sessão ser populada)
- `setPapeis(TipoPapel... papeis)` — aceita varargs; inicializa lista se nula; adiciona cada papel
- `setPapeis(List<TipoPapel> papeis)` — sobrecarga que substitui a lista inteira

**Critério de Aceitação:** `CidadaoED.nullInstance()` nunca retorna `null` — retorna objeto com email vazio. `hasPermission()` em instância `null` não é chamado — a verificação usa o `getCidadaoED()` que deve sempre retornar um `CidadaoED` válido.

---

### RF-BE-03 — Consulta de Usuário por CPF

**Prioridade:** Crítica
**Classe:** `UsuarioRN` (`com.procergs.solcbm.usuario`)
**Método:** `consultaPorCpf(String cpf)`
**Transação:** `@TransactionAttribute(SUPPORTS)` — participativo, sem exigir transação ativa

**Descrição:** Consulta completa de um usuário pelo CPF, retornando todos os dados associados necessários para o frontend.

**Comportamento obrigatório:**
1. Se `cpf == null` → retorna `null` (sem exceção)
2. Consulta `UsuarioED` via `usuarioBD.consultarPorCpf(cpf)`
3. Se `usuarioED == null` → retorna `null`
4. Aplica workaround de timezone: `usuarioED.getDtNascimento().set(Calendar.HOUR, 12)`
5. Consulta `InstrutorED` via `instrutorRN.buscaInstrutorPorCPF(cpf)`
6. Monta objeto `Usuario` via `BuilderUsuario.of()` com todos os campos:
   - Dados básicos: id, nome, cpf, rg, estadoEmissor, dtNascimento, nomeMae, email, telefone1, telefone2
   - Status e mensagem
   - Timestamps: ctrDthInc, ctrDthAtu
   - Coleções: enderecos, graduacoes, especializacoes (via RNs respectivos)
   - Arquivo RG: id e nomeArquivo (usando `Optional` para evitar NPE se arquivoRG for null)
   - Dados de instrutor (se existir): diasParaVencerCredenciamento, alertaVencimento, dataVencimentoCredenciamento

**Critério de Aceitação:** Retorna `null` para CPF nulo ou não encontrado. Para usuário existente, retorna objeto `Usuario` completo com todas as coleções carregadas.

---

### RF-BE-04 — Consulta de Usuário por E-mail

**Prioridade:** Alta
**Classe:** `UsuarioRN`
**Método:** `consultaPorEmail(String email)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Descrição:** Consulta usuário por e-mail, com restrição de segurança: apenas o próprio usuário logado pode consultar pelo seu próprio e-mail.

**Comportamento obrigatório:**
1. Se `email == null` → retorna `null`
2. Compara `email` (ignorando espaços, case insensitive) com `cidadaoSessionMB.getCidadaoED().getEmail()`
   - Se divergente → lança `WebApplicationRNException` com `Response.Status.NOT_FOUND`
3. Consulta `usuarioBD.consultarPorEmail(email)`
4. Se não encontrado → retorna `null`
5. Monta `Usuario` com: dados básicos + graduações + especializações + endereços + arquivoRG

**Critério de Aceitação:** Usuário A tentando consultar e-mail do usuário B recebe HTTP 404. Usuário consultando seu próprio e-mail recebe dados completos.

---

### RF-BE-05 — Inclusão de Novo Usuário

**Prioridade:** Crítica
**Classe:** `UsuarioRN`
**Método:** `incluir(Usuario usuario)`
**Transação:** `@TransactionAttribute(REQUIRED)` (herdado da classe)

**Descrição:** Cria novo usuário no banco de dados com status INCOMPLETO.

**Comportamento obrigatório:**
1. Define `usuario.setStatus(StatusCadastro.INCOMPLETO)` — **obrigatório, independente do status enviado**
2. Converte para `UsuarioED` via `toUsuarioED(usuario)` — monta a entidade com todos os campos
3. Persiste via `inclui(UsuarioED)` que envolve `usuarioBD.inclui(ed)` em tratamento de exceção
4. Inclui coleções associadas (na ordem):
   - `graduacaoUsuarioRN.incluirGraduacoesUsuario(ed, usuario.getGraduacoes())`
   - `especializacaoUsuarioRN.incluirEspecializacoesUsuario(ed, usuario.getEspecializacoes())`
   - `enderecoUsuarioRN.incluirEnderecosUsuario(ed, usuario.getEnderecos())`
5. Retorna `toUsuario(ed)` — o objeto persistido convertido

**Tratamento de erro de banco (ConstraintViolationException):**
- Se a exceção tiver `constraintName` não nulo e não vazio → mensagem: `bundle.getMessage(USUARIO_CPF_JA_CADASTRADO, cpfFormatado, email)`
- Caso contrário → mensagem: `bundle.getMessage(VIOLACAO_BD)`
- Sempre lança `WebApplicationRNException` com `Response.Status.BAD_REQUEST`

**Critério de Aceitação:** Novo usuário sempre criado com status INCOMPLETO. CPF duplicado retorna HTTP 400 com mensagem informativa contendo CPF formatado e e-mail.

---

### RF-BE-06 — Alteração de Usuário com Controle de Concorrência

**Prioridade:** Crítica
**Classe:** `UsuarioRN`
**Método:** `alterar(Long id, Usuario usuario)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Descrição:** Atualiza os dados de um usuário existente com proteção contra edição concorrente.

**Comportamento obrigatório:**
1. Busca o `UsuarioED` atual via `getEDAtualizado(id, usuario)` — copia campos do `usuario` para o ED
2. **Verificação de concorrência (somente se status ≠ INCOMPLETO):**
   - Se `usuarioED.getCtrDthAtu()` e `usuario.getCtrDthAtu()` não são nulos
   - E `usuarioED.getCtrDthAtu().compareTo(usuario.getCtrDthAtu()) != 0`
   - → Lança `WebApplicationRNException` com `"analise.data_atualizacao.divergente"` e `Response.Status.CONFLICT`
3. Atualiza graduações, especializações e endereços via seus respectivos RNs
4. Recarrega as coleções após atualização (`listarGraduacoesUsuario`, `listarEspecializacoesUsuario`, `listarEnderecosUsuario`)
5. Persiste via `altera(usuarioED)`
6. Define `usuario.setMensagemStatus("Alterações realizadas com sucesso.")`
7. Retorna o `usuario` com as coleções atualizadas

**Campos atualizados por `getEDAtualizado`:** nome, cpf, rg, estadoEmissor, dtNascimento, nomeMae, email, telefone1, telefone2, status

**Critério de Aceitação:** Dois usuários editando o mesmo registro simultaneamente — o segundo a salvar recebe HTTP 409. Usuário com status INCOMPLETO pode ser alterado sem verificação de concorrência.

---

### RF-BE-07 — Conclusão do Cadastro

**Prioridade:** Crítica
**Classe:** `UsuarioConclusaoCadastroRN` (`com.procergs.solcbm.usuario`)
**Método:** `concluirCadastro(Long idUsuario)`
**Anotação:** `@Permissao(desabilitada = true)` — endpoint não exige permissão específica
**Transação:** `@TransactionAttribute(REQUIRED)`

**Descrição:** Determina se o cadastro está completo e transiciona o status para ANALISE_PENDENTE ou mantém INCOMPLETO.

**Comportamento obrigatório — algoritmo de validação:**

```
statusCadastro = ANALISE_PENDENTE  // presume completo

usuarioED = usuarioRN.consulta(idUsuario)

SE usuarioED.getArquivoRG() == null
  → statusCadastro = INCOMPLETO

graduacoesUsuario = graduacaoUsuarioRN.lista(pesquisaED)
PARA CADA graduacaoUsuarioED em graduacoesUsuario:
  SE graduacaoUsuarioED.getArquivoIdProfissional() == null
    → statusCadastro = INCOMPLETO

usuarioED.setStatus(statusCadastro)
usuarioED.setMensagemStatus(null)
usuarioED = usuarioRN.altera(usuarioED)

statusMessage = bundle.getMessage("usuario.cadastro.status." + statusCadastro)
notificacaoRN.notificar(usuarioED, statusMessage, ContextoNotificacaoEnum.CADASTRO)

SE statusCadastro == ANALISE_PENDENTE:
  instrutor = instrutorRN.buscaInstrutorPorCPF(usuarioED.getCpf())
  SE instrutor != null
     E instrutor.getStatus() != null
     E (status == APROVADO OU status == VENCIDO):
    → instrutorHistoricoRN.incluirEdicao(instrutor)  // registra edição do instrutor

Retorna Status com:
  - statusCadastro
  - ctrDthAtu (atualizado)
  - mensagem (internacionalizada)
```

**Critério de Aceitação:**
- Usuário sem arquivo RG → status INCOMPLETO, mesmo que tenha graduações
- Usuário com arquivo RG mas com pelo menos uma graduação sem documento profissional → INCOMPLETO
- Usuário com arquivo RG e todas as graduações com documentos → ANALISE_PENDENTE
- Notificação é sempre enviada ao usuário independente do status resultante

---

### RF-BE-08 — Validação de RT Válido

**Prioridade:** Alta
**Classe:** `UsuarioRN`
**Método:** `isUsuarioLogadoRtValido()` e `isUsuarioRTAprovado(String cpf)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Descrição:** Verifica se o usuário logado (ou um CPF específico) é um Responsável Técnico válido para operar no sistema.

**Critério de RT válido (ambos os métodos usam a mesma lógica):**
```java
StatusCadastro.APROVADO.equals(ed.getStatus())
AND
!graduacaoUsuarioRN.listarGraduacoesUsuario(ed).isEmpty()
```

**Ou seja:** status deve ser APROVADO **e** o usuário deve ter pelo menos uma graduação cadastrada.

**Método `isUsuarioAprovado(String cpf)`:** verifica apenas o status APROVADO, sem checar graduações.

**Critério de Aceitação:** Usuário APROVADO sem graduações retorna `false` para `isUsuarioRtValido`. Usuário APROVADO com pelo menos uma graduação retorna `true`.

---

### RF-BE-09 — Upload e Download de Arquivos do Usuário

**Prioridade:** Alta
**Classe:** `UsuarioRN` + `UsuarioRestImpl`

**Descrição:** O sistema gerencia três categorias de arquivos vinculados ao cadastro do usuário, todos via upload multipart.

**Categorias de arquivo:**

| Categoria | Endpoints | Constraint |
|-----------|----------|-----------|
| RG do Usuário | POST/GET/PUT `/usuarios/{idUsuario}/arquivo-rg` | Apenas 1 por usuário — POST falha com 400 se já existir |
| Doc. Profissional da Graduação | POST/GET/PUT `/usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | Apenas 1 por graduação — POST falha com 400 se já existir |
| Arquivo de Especialização | POST/GET/PUT `/usuarios/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | Apenas 1 por especialização — POST falha com 400 se já existir |

**Comportamento obrigatório para upload (POST):**
1. Verifica se arquivo já existe — se sim, lança `WebApplicationRNException` com `USUARIO_ARQUIVO_ERRO_DUPLICADO` e HTTP 400
2. Persiste arquivo via `ArquivoRN.incluirArquivo(inputStream, nomeArquivo, TipoArquivo.USUARIO)`
3. Vincula ao entity (usuário, graduação ou especialização)
4. Persiste o vínculo

**Comportamento para atualização (PUT):**
- **Não verifica** duplicidade — sobrescreve o arquivo existente diretamente

**Comportamento para download (GET):**
- Retorna `InputStream` com `@Produces("application/octet-stream")`

**Critério de Aceitação:** Segundo upload de arquivo RG para o mesmo usuário retorna HTTP 400. PUT de arquivo existente é bem-sucedido.

---

### RF-BE-10 — Consulta de Usuário pelo Usuário Logado

**Prioridade:** Alta
**Classe:** `UsuarioRN`
**Método:** `getUsuarioLogado()`

**Descrição:** Retorna o `UsuarioED` do usuário que está executando a requisição atual, usando o CPF do `CidadaoSessionMB`.

```java
public UsuarioED getUsuarioLogado() {
  return usuarioBD.consultarPorCpf(cidadaoSessionMB.getCidadaoED().getCpf());
}
```

**Critério de Aceitação:** Método sempre retorna o usuário correspondente ao token Bearer da requisição atual, sem necessidade de passar o CPF como parâmetro.

---

### RF-BE-11 — Listagem de Analistas por Batalhão, Objeto e Ação

**Prioridade:** Média
**Classe:** `UsuarioRN`
**Método:** `analistasPorObjetoAcao(String objeto, String acao)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Descrição:** Retorna lista de analistas disponíveis no batalhão do usuário logado, filtrados pelo par (objeto, ação) de permissão, enriquecidos com a quantidade de FACTs em análise de cada um.

**Comportamento obrigatório:**
1. `usuarioSoeRN.getNumeroBatalhaoUsuarioLogado()` — obtém batalhão do usuário logado (retorna `Optional<Long>`)
2. Se batalhão presente: `usuarioSoeRN.listaAnalistasPorBatalhaoObjetoAcao(numBatalhao, objeto, acao)` — lista analistas SOE
3. Para cada analista: `facUtilRN.quantidadeFactEmAnalisePorUsuarioSoe(usuarioSoeDTO.getCodUsuario())` — contabiliza FACTs
4. Monta lista de `UsuarioAnalisaFactDTO` com: `usuario` (UsuarioSoeDTO) + `quantFact`

**Critério de Aceitação:** Se usuário logado não tem batalhão (`Optional.empty()`), retorna lista vazia. Lista retornada é enriquecida com quantidade de FACTs por analista.

---

### RF-BE-12 — Controle de Transações e Concorrência

**Prioridade:** Crítica
**Classe:** `UsuarioRN` (e demais RNs)

**Descrição:** Define o comportamento transacional padrão de todos os métodos de negócio.

**Regras obrigatórias:**

| Tipo de operação | `@TransactionAttribute` | Comportamento |
|-----------------|------------------------|---------------|
| Leitura simples (consulta, listagem, download) | `SUPPORTS` | Participa de transação se existente; sem transação se chamado isoladamente |
| Escrita (incluir, alterar, excluir) | `REQUIRED` | Exige transação ativa; cria nova se não existir |
| Método especial `inclui(UsuarioED)` | `REQUIRED` explícito | Garante própria transação com tratamento de constraint |

**Regra de concorrência otimista:**
- Campo `ctrDthAtu` (timestamp de última atualização) é comparado antes de cada `alterar`
- Se o `ctrDthAtu` do objeto recebido difere do banco → HTTP 409 CONFLICT
- Esta verificação é **omitida** quando status é INCOMPLETO (cadastro em preenchimento)

**Critério de Aceitação:** Chamadas de leitura não criam transações desnecessariamente. Chamadas de escrita sempre operam dentro de transação.

---

### RF-BE-13 — Verificação de Sessão Ativa

**Prioridade:** Média
**Classe:** `UsuarioRN`
**Método:** `hasSession()`

**Descrição:** Verifica se há uma sessão de usuário ativa na requisição corrente.

```java
public Boolean hasSession() {
  return cidadaoSessionMB.getCidadaoED() != null;
}
```

**Critério de Aceitação:** Retorna `false` quando `CidadaoSessionMB` não foi populado (requisição não autenticada ou falha na extração do token). Retorna `true` quando `CidadaoED` está presente.

---

### RF-BE-14 — Formatação de Data de Vencimento de Credenciamento

**Prioridade:** Baixa
**Classe:** `UsuarioRN`
**Método:** `formataDataVencimentoCredenciamento(Calendar dtVencimento)`

**Descrição:** Formata a data de vencimento do credenciamento do instrutor para exibição no frontend.

**Comportamento:**
- Se `dtVencimento != null` → formata como `dd/MM/yyyy` usando `DateTimeFormatter`; converte `Calendar` para `LocalDate` respeitando o timezone original
- Se `dtVencimento == null` → retorna `null`

**Critério de Aceitação:** Data `Calendar` com timezone é corretamente convertida para `LocalDate` usando `ZoneId` do próprio objeto antes de formatar.

---

## 5. Regras de Negócio

| ID | Regra | Implementação |
|----|-------|--------------|
| **RN-01** | Autenticação obrigatoriamente via OIDC Implicit Flow contra IdP estadual | `AppComponent.login()` → `initImplicitFlow()` |
| **RN-02** | Token validado sem verificação de assinatura no frontend | `NullValidationHandler` configurado no `OAuthService` |
| **RN-03** | Token armazenado em `localStorage['appToken']` como JSON agregador | `AuthStorageService` |
| **RN-04** | Guard de rota sempre permite navegação Angular — proteção real é via OIDC | `UsuarioAutenticadoGuard.canActivate()` retorna `true` incondicionalmente |
| **RN-05** | Interceptor injeta Bearer token somente em URLs que contêm `AppSettings.baseUrl` | `HttpAuthorizationInterceptor` |
| **RN-06** | E-mail das claims só sincronizado se status ≠ EM_ANALISE | `verificaCadastro()` — condição explícita |
| **RN-07** | Sincronização de e-mail dispara `alteraProprietario` como efeito colateral | `atualizarUsuario()` após `salvar()` |
| **RN-08** | Usuário com status INCOMPLETO ou não encontrado (404) → redirecionar para `/cadastro` | `verificaCadastro()` |
| **RN-09** | Novo usuário sempre criado com status INCOMPLETO | `UsuarioRN.incluir()` |
| **RN-10** | CPF duplicado retorna HTTP 400 com mensagem contendo CPF formatado e e-mail | `UsuarioRN.processaErroBD()` via ConstraintViolationException |
| **RN-11** | Concorrência verificada por `ctrDthAtu` somente quando status ≠ INCOMPLETO | `UsuarioRN.alterar()` |
| **RN-12** | Conclusão de cadastro: arquivo RG obrigatório; documento profissional obrigatório por graduação | `UsuarioConclusaoCadastroRN.concluirCadastro()` |
| **RN-13** | Conclusão com documentos completos → ANALISE_PENDENTE; incompleto → INCOMPLETO | `UsuarioConclusaoCadastroRN.concluirCadastro()` |
| **RN-14** | Notificação enviada ao usuário em qualquer transição de status (INCOMPLETO ou ANALISE_PENDENTE) | `notificacaoRN.notificar()` em `concluirCadastro()` |
| **RN-15** | Se usuário é instrutor APROVADO ou VENCIDO ao concluir cadastro → registrar edição no histórico de instrutor | `instrutorHistoricoRN.incluirEdicao()` |
| **RN-16** | RT válido = status APROVADO + pelo menos uma graduação cadastrada | `UsuarioRN.isUsuarioRTAprovado()` |
| **RN-17** | Upload de arquivo (POST) falha com 400 se arquivo já existir; atualização (PUT) não verifica | `UsuarioRN.incluirArquivoRG()` etc. |
| **RN-18** | Permissão verificada como tripla (SISTEMA="SOLCBM", objeto, acao) | `CidadaoSessionMB.hasPermission()` |
| **RN-19** | Workaround de timezone: `dtNascimento.set(Calendar.HOUR, 12)` aplicado em todas as consultas | `UsuarioRN.consultaPorCpf()` e `toUsuario()` |
| **RN-20** | Pesquisa por CPF remove pontos e traços automaticamente se o termo bate com regex de CPF | `UsuarioRN.verificaMascarasPesquisa()` |
| **RN-21** | Consulta por e-mail: usuário só pode consultar o próprio e-mail; outro e-mail retorna 404 | `UsuarioRN.consultaPorEmail()` |
| **RN-22** | Analistas listados filtrados pelo batalhão do usuário logado | `UsuarioRN.analistasPorObjetoAcao()` |
| **RN-23** | Evento `session_terminated` apenas loga; sem ação de redirecionamento automático | `AppComponent.configureAuth()` listener |
| **RN-24** | Notificações carregadas após login; falha no carregamento não interrompe acesso | `getNotificacoes()` com `handleErrorAndContinue([])` |

---

## 6. Modelo de Dados

### 6.1 Entidade `UsuarioED` (campos inferidos do código)

```
id              Long        PK, auto-gerado
nome            String      Nome completo
cpf             String      CPF (11 dígitos, UNIQUE)
rg              String      Número do RG
estadoEmissor   String      UF emissora do RG
dtNascimento    Calendar    Data de nascimento
nomeMae         String      Nome da mãe
email           String      E-mail
telefone1       String      Telefone principal
telefone2       String      Telefone alternativo
status          StatusCadastro  Enum do status do cadastro
mensagemStatus  String      Mensagem explicativa do status atual
arquivoRG       ArquivoED   FK para o arquivo do RG (nullable)
ctrDthInc       Calendar    Timestamp de criação (auto)
ctrDthAtu       Calendar    Timestamp de última atualização (auto, para concorrência)
```

### 6.2 Enum `StatusCadastro`

| Valor | Significado |
|-------|-------------|
| `INCOMPLETO` | Cadastro criado mas documentos não enviados ou insuficientes |
| `ANALISE_PENDENTE` | Todos os documentos enviados, aguardando fila de análise |
| `EM_ANALISE` | Em análise por ADM — e-mail não sincronizado neste estado |
| `APROVADO` | Cadastro aprovado — usuário habilitado como RT |
| `REPROVADO` | Cadastro reprovado — usuário não habilitado |

### 6.3 Entidade `CidadaoED` (contexto de sessão, não persistida)

```
nome            String
cpf             String
dtNascimento    Calendar
email           String
telefone        String
permissoes      Set<PermissaoED>   { (SOLCBM, objeto, acao) }
papeis          List<TipoPapel>
```

### 6.4 Coleções Associadas a UsuarioED

| Entidade | RN Responsável | Descrição |
|----------|---------------|-----------|
| `GraduacaoUsuarioED` | `GraduacaoUsuarioRN` | Graduações profissionais; cada uma com `arquivoIdProfissional` |
| `EspecializacaoUsuarioED` | `EspecializacaoUsuarioRN` | Especializações; cada uma com `arquivo` |
| `EnderecoUsuarioED` | `EnderecoUsuarioRN` | Endereços do usuário |

---

## 7. Contratos de API REST

Base path: `/usuarios` — `@Produces(APPLICATION_JSON)` / `@Consumes(APPLICATION_JSON)` por padrão

### 7.1 Endpoints de Usuário (`UsuarioRestImpl`)

| Método HTTP | Path | Parâmetros | Retorno | Observações |
|-------------|------|-----------|---------|-------------|
| `GET` | `/usuarios/{cpf}` | Path: `cpf` | `200 Usuario` ou `404 null` | Consulta por CPF como path param |
| `POST` | `/usuarios/` | Body: `Usuario` | `201 Usuario` | Cria usuário; status forçado para INCOMPLETO |
| `PUT` | `/usuarios/{id}` | Path: `id` (Long), Body: `Usuario` | `200 Usuario` | Atualiza; verificação de concorrência por `ctrDthAtu` |
| `PATCH` | `/usuarios/{id}` | Path: `id` (Long) | `200 Status` | Conclui cadastro; valida documentos e transiciona status |
| `GET` | `/usuarios/` | Query: `cpf` | `200 Usuario` | Consulta por CPF como query param (mesmo resultado) |
| `GET` | `/usuarios/isUsuarioRtValido` | — | `200 boolean` | Verifica se usuário logado é RT válido |
| `GET` | `/usuarios/{cpf}/credenciamento` | Path: `cpf` | `200 AnaliseInstrutor` | Consulta credenciamento do instrutor |

### 7.2 Endpoints de Arquivo RG

| Método HTTP | Path | Content-Type | Retorno |
|-------------|------|-------------|---------|
| `POST` | `/usuarios/{idUsuario}/arquivo-rg` | `multipart/form-data` | `200 Arquivo` — falha 400 se já existe |
| `GET` | `/usuarios/{idUsuario}/arquivo-rg` | — | `application/octet-stream` (InputStream) |
| `PUT` | `/usuarios/{idUsuario}/arquivo-rg` | `multipart/form-data` | `200 Arquivo` |

### 7.3 Endpoints de Documento Profissional (Graduação)

| Método HTTP | Path | Content-Type | Retorno |
|-------------|------|-------------|---------|
| `POST` | `/usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | `multipart/form-data` | `200 Arquivo` — falha 400 se já existe |
| `GET` | `/usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | — | `application/octet-stream` |
| `PUT` | `/usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | `multipart/form-data` | `200 Arquivo` |

### 7.4 Endpoints de Arquivo de Especialização

| Método HTTP | Path | Content-Type | Retorno |
|-------------|------|-------------|---------|
| `POST` | `/usuarios/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | `multipart/form-data` | `200 Arquivo` — falha 400 se já existe |
| `GET` | `/usuarios/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | — | `application/octet-stream` |
| `PUT` | `/usuarios/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | `multipart/form-data` | `200 Arquivo` |

### 7.5 DTO `Usuario` (campos relevantes para P01)

```json
{
  "id":           123,
  "nome":         "João da Silva",
  "cpf":          "00000000000",
  "rg":           "1234567",
  "estadoEmissor": "RS",
  "dtNascimento": "1990-01-15",
  "nomeMae":      "Maria da Silva",
  "email":        "joao@email.com",
  "telefone1":    "51999999999",
  "telefone2":    null,
  "status":       "APROVADO",
  "mensagemStatus": null,
  "ctrDthInc":    "2024-01-01T10:00:00",
  "ctrDthAtu":    "2024-01-20T14:00:00",
  "arquivoRG":    { "id": 1, "nomeArquivo": "rg.pdf" },
  "graduacoes":   [...],
  "especializacoes": [...],
  "enderecos":    [...],
  "diasParaVencerCredenciamento": null,
  "alertaVencimento": null,
  "dataVencimentoCredenciamento": null
}
```

### 7.6 DTO `Status` (retorno de `PATCH /usuarios/{id}`)

```json
{
  "statusCadastro": "ANALISE_PENDENTE",
  "ctrDthAtu":      "2024-01-20T14:30:00",
  "mensagem":       "Cadastro enviado para análise com sucesso."
}
```

---

## 8. Stack Tecnológica

### 8.1 Frontend

| Componente | Tecnologia | Versão |
|-----------|-----------|--------|
| Framework | Angular | Conforme `package.json` existente |
| Autenticação OIDC | `angular-oauth2-oidc` | Conforme `package.json` existente |
| Fluxo OAuth | **Implicit Flow** | Mantido (não migrar para Authorization Code) |
| Validação JWT | `NullValidationHandler` | **Sem validação local** de assinatura |
| Storage | `localStorage['appToken']` | JSON agregador de todas as chaves OIDC |
| Interceptor HTTP | `HttpAuthorizationInterceptor` | Injeção de Bearer token por URL |
| Guard | `UsuarioAutenticadoGuard` | Sempre retorna `true`; inicia fluxo OIDC se necessário |

### 8.2 Backend

| Componente | Tecnologia | Notas |
|-----------|-----------|-------|
| Runtime | Java EE (JEE 7 ou 8) | WildFly / JBoss |
| REST | JAX-RS (RESTEasy) | Inferido por import `org.jboss.resteasy` |
| Injeção de Dependência | CDI (`@Inject`, `@Named`, `@RequestScoped`) | |
| EJBs | `@Stateless`, `@TransactionAttribute` | Camada de negócio |
| Persistência | JPA + `UsuarioBD` (DAO pattern) | |
| Segurança customizada | `@Permissao(objeto, acao)` | Anotação própria `com.procergs.arqjava4` |
| Internacionalização | `MessageProvider` (`com.procergs.arqjava4.context`) | Bundle de mensagens |
| Multipart upload | RESTEasy `MultipartFormDataInput` | |
| Integração SOE | `UsuarioSoeRN`, `@SOEAuthRest` | Sistema de usuários internos |

### 8.3 Configuração de Ambiente (Frontend)

```typescript
// environment.ts (dev) / environment.prod.ts (prod)
export const environment = {
  production: false,
  oidIssuer:      'https://meu.hml.rs.gov.br',   // IdP estadual
  oidClientId:    '209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s',
  redirectUriPath: '/solcbm/app'
};
```

---

## 9. Requisitos Não Funcionais

### RNF-01 — Compatibilidade de Browser

- O sistema deve funcionar nos browsers que suportam `localStorage` e ES2015+
- `localStorage` é obrigatório — o sistema não funciona em modo de navegação privada em browsers que bloqueiam localStorage (comportamento atual não alterado)

### RNF-02 — Segurança (mantendo stack atual)

- `NullValidationHandler` mantido — **não há validação de assinatura JWT no frontend** (decisão arquitetural existente)
- `sessionChecksEnabled: false` mantido — sessões do IdP não são verificadas ativamente
- O backend é responsável por toda validação de autenticidade do token
- Token Bearer transmitido em HTTP (requer HTTPS em produção obrigatoriamente)
- Tokens sensíveis (`access_token`, `id_token`) são armazenados em `localStorage` — risco de XSS existente e mantido
- Mitigação do risco de XSS: aplicação Angular com Content Security Policy adequada no servidor web

### RNF-03 — Desempenho

- Inicialização da aplicação deve concluir carregamento da config OIDC em menos de 2 segundos
- Verificação de cadastro (`GET /usuarios?cpf=`) deve responder em menos de 500ms (P95)
- Silent refresh deve ocorrer sem percepção do usuário

### RNF-04 — Manutenibilidade

- Toda configuração de autenticação (issuer, clientId) deve residir nos arquivos `environment.ts` — nunca hardcoded em componentes
- `AppConfigService.getConfig()` é o ponto único de carregamento de config em runtime; configuração não deve ser duplicada
- A anotação `@Permissao` deve ser usada consistentemente em todos os métodos de negócio que requerem autorização

### RNF-05 — Compatibilidade com Infraestrutura Existente

- O servidor de aplicação é WildFly/JBoss — nenhuma dependência incompatível com este servidor deve ser introduzida
- A integração com `arqjava4` (framework interno PROCERGS: `MessageProvider`, `PermissaoED`, `@Permissao`) deve ser mantida
- A integração SOE (`UsuarioSoeRN`, `@SOEAuthRest`) deve ser mantida para usuários internos

### RNF-06 — Tratamento de Erros

- Exceções de negócio devem usar `WebApplicationRNException` com o `Response.Status` adequado
- Constraint violation de CPF duplicado deve retornar HTTP 400 com mensagem legível (CPF formatado + e-mail)
- Conflito de concorrência deve retornar HTTP 409
- Erros inesperados no frontend exibem dialog `{ titulo: 'Erro', mensagem: 'Erro inesperado.' }` — sem expor detalhes técnicos

### RNF-07 — Internacionalização (i18n)

- Todas as mensagens de negócio devem usar `bundle.getMessage(chave, parâmetros...)` — sem strings hardcoded
- Chaves de mensagem de status do cadastro seguem padrão: `usuario.cadastro.status.{StatusCadastro}`
- Mensagens de erro de constraint seguem: `usuario.erro.cpf.jacadastrado`, `violacao.banco.de.dados`, `arquivo.erro.duplicado`

---

## 10. Critérios de Aceitação

### CA-01 — Login completo (caminho feliz)
- [ ] Usuário acessa o portal e é redirecionado ao IdP via Implicit Flow
- [ ] Após login no IdP, retorna ao portal com token no fragmento de URL
- [ ] `AuthStorageService` persiste token em `localStorage['appToken']`
- [ ] `verificaCadastro()` é chamado e consulta `GET /usuarios?cpf={cpf}`
- [ ] Usuário APROVADO: `router.initialNavigation()` é chamado e notificações são carregadas

### CA-02 — Primeiro acesso (usuário não cadastrado)
- [ ] Backend retorna HTTP 404 para CPF não encontrado
- [ ] `verificaCadastro()` detecta erro 404 e navega para `/cadastro`

### CA-03 — Usuário com status INCOMPLETO
- [ ] Backend retorna `{ status: "INCOMPLETO" }`
- [ ] `verificaCadastro()` navega para `/cadastro`

### CA-04 — Sincronização de e-mail
- [ ] E-mail nas claims difere do banco e status ≠ EM_ANALISE → `atualizarUsuario()` é chamado
- [ ] `cadastroUsuarioService.salvar()` atualiza o e-mail no banco
- [ ] `alteraProprietario()` é chamado após o salvar com sucesso
- [ ] Status EM_ANALISE → e-mail NÃO é sincronizado

### CA-05 — Conclusão de cadastro com documentos completos
- [ ] Usuário com arquivoRG e todos os documentos profissionais → status ANALISE_PENDENTE
- [ ] Notificação enviada ao usuário
- [ ] Se instrutor APROVADO/VENCIDO → histórico registrado

### CA-06 — Conclusão de cadastro com documentos incompletos
- [ ] Usuário sem arquivoRG → status INCOMPLETO
- [ ] Usuário com graduação sem documento profissional → status INCOMPLETO
- [ ] Notificação enviada mesmo com status INCOMPLETO

### CA-07 — Validação de RT
- [ ] Usuário APROVADO com graduações → `isUsuarioRtValido()` retorna `true`
- [ ] Usuário APROVADO sem graduações → `isUsuarioRtValido()` retorna `false`
- [ ] Usuário ANALISE_PENDENTE → `isUsuarioRtValido()` retorna `false`

### CA-08 — Controle de concorrência
- [ ] Dois clientes editando o mesmo usuário (status ≠ INCOMPLETO) — o segundo recebe HTTP 409
- [ ] Edição de usuário INCOMPLETO sem verificação de `ctrDthAtu`

### CA-09 — Upload duplicado
- [ ] Segundo POST de arquivo RG para o mesmo usuário retorna HTTP 400 com mensagem `USUARIO_ARQUIVO_ERRO_DUPLICADO`
- [ ] PUT de arquivo existente é bem-sucedido (sobrescreve)

### CA-10 — CPF duplicado
- [ ] POST de novo usuário com CPF já existente retorna HTTP 400 com CPF formatado e e-mail na mensagem

### CA-11 — Logout
- [ ] `oauthService.logOut()` é chamado
- [ ] `authStorage.clean()` remove `localStorage['appToken']`
- [ ] Tentativa de acesso após logout → `initImplicitFlow()` é disparado

### CA-12 — Intercepção de requisições
- [ ] Chamada HTTP a URL contendo `AppSettings.baseUrl` recebe `Authorization: Bearer eyJ...`
- [ ] Chamada HTTP a URL externa não recebe o header Authorization

---

## 11. Restrições e Premissas

### 11.1 Restrições

- **Implicit Flow é mantido.** Não deve ser substituído por Authorization Code + PKCE nesta versão.
- **`NullValidationHandler` é mantido.** A validação de assinatura do JWT não é realizada no frontend.
- **`sessionChecksEnabled: false` é mantido.** Não há verificação ativa de sessão do IdP.
- **`localStorage` como storage** — sem migração para cookies HttpOnly nesta versão.
- **Framework `arqjava4` da PROCERGS** — dependências como `MessageProvider`, `@Permissao`, `PermissaoED` são mantidas.
- **Servidor de aplicação WildFly/JBoss** — nenhuma dependência Spring deve ser introduzida.
- O guard `UsuarioAutenticadoGuard` **não deve bloquear** navegação Angular (sempre retorna `true`).

### 11.2 Premissas

- O IdP `meu.hml.rs.gov.br` (homologação) / IdP de produção fornece as claims: `cpf`, `name`, `email`, `sub`, `birthdate`, `phone_number`.
- O filtro de autenticação do backend (responsável por popular `CidadaoSessionMB`) já existe e está funcionando — sua implementação não é escopo do P01.
- `AppSettings.baseUrl` está corretamente configurado para apontar para o backend SOL.
- O arquivo `silent-refresh.html` existe no diretório estático da aplicação Angular.
- `alteraProprietario` é um serviço existente de integração com outro sistema — sua implementação não é escopo do P01.

### 11.3 Fora do Escopo do P01

- Implementação do filtro JAX-RS que popula `CidadaoSessionMB` a partir do token Bearer.
- Endpoints administrativos de gestão de cadastros (`/adm/cadastros`) — escopo do P02.
- Lógica interna de `GraduacaoUsuarioRN`, `EspecializacaoUsuarioRN`, `EnderecoUsuarioRN`.
- Lógica de `InstrutorRN` e `InstrutorHistoricoRN`.
- Lógica de `NotificacaoRN`.
- Implementação do `ArquivoRN` (persistência de arquivos binários).
- Implementação do `UsuarioSoeRN` (integração SOE).

---

*Documento elaborado em: 2026-03-04*
*Base: código-fonte exato de SOLCBM.FrontEnd16-06 / SOLCBM.BackEnd16-06*
*Processo de referência: P01 — Autenticação no Sistema SOL/CBM-RS*
*Stack: Angular + angular-oauth2-oidc (Implicit Flow) + Java EE (JAX-RS + EJB + CDI + JPA) + WildFly*
