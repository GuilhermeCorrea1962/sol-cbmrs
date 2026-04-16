# Descritivo do Fluxo BPMN — P01: Autenticação e Verificação de Cadastro
## Stack Atual (Angular · Java EE · OIDC Implicit Flow · CBM-RS SOL)

**Processo:** P01 — Autenticação, Autorização e Verificação de Cadastro
**Arquivo BPMN:** `SOL_CBM_RS_Processo_P01_StackAtual.bpmn`
**Data:** 2026-03-17

---

## Sumário

1. [Visão Geral da Modelagem](#1-visão-geral-da-modelagem)
2. [Estrutura do Diagrama: Pool e Raias](#2-estrutura-do-diagrama-pool-e-raias)
3. [Fase 0 — Inicialização da Aplicação Angular](#3-fase-0--inicialização-da-aplicação-angular)
4. [Fase 1 — Discovery Document e Verificação de Token Existente](#4-fase-1--discovery-document-e-verificação-de-token-existente)
5. [Fase 2A — Fluxo Sem Token: Redirect ao IdP e Autenticação do Usuário](#5-fase-2a--fluxo-sem-token-redirect-ao-idp-e-autenticação-do-usuário)
6. [Fase 2B — Processamento do Token (JOIN das Duas Vias)](#6-fase-2b--processamento-do-token-join-das-duas-vias)
7. [Fase 3 — Verificação de Cadastro no SOL (Frontend → Backend)](#7-fase-3--verificação-de-cadastro-no-sol-frontend--backend)
8. [Fase 4 — Análise de Status e Roteamento](#8-fase-4--análise-de-status-e-roteamento)
9. [Fase 5 — Sincronização Condicional de E-mail](#9-fase-5--sincronização-condicional-de-e-mail)
10. [Fase 6 — Inicialização do Dashboard](#10-fase-6--inicialização-do-dashboard)
11. [Eventos de Fim: Três Desfechos Possíveis](#11-eventos-de-fim-três-desfechos-possíveis)
12. [Justificativas de Modelagem](#12-justificativas-de-modelagem)
13. [Diagrama de Estados do Cadastro (StatusCadastro)](#13-diagrama-de-estados-do-cadastro-statuscadastro)
14. [Referência Cruzada: Elementos BPMN × Código](#14-referência-cruzada-elementos-bpmn--código)

---

## 1. Visão Geral da Modelagem

O BPMN do processo P01 modela a **porta de entrada obrigatória de todo o sistema SOL**: sem autenticação válida, nenhuma operação de licenciamento é executável. O processo abrange desde o momento em que o usuário acessa a URL do sistema até o instante em que o dashboard é exibido — ou, nas vias alternativas, até o redirecionamento para o cadastro ou a falha no IdP.

O P01 é tecnicamente o processo mais transversal do sistema: ele envolve três sistemas distintos (Angular SPA, IdP estadual PROCERGS e backend Java EE), dois protocolos (OIDC Implicit Flow e JAX-RS REST com Bearer token) e cinco decisões de ramificação. Toda a complexidade desse fluxo está distribuída em apenas duas classes Angular (`AppComponent` e `AuthStorageService`) e duas classes Java (`CidadaoSessionMB` e `UsuarioRN`), o que torna o BPMN especialmente valioso para tornar implícito em explícito.

A modelagem cobre integralmente os seguintes aspectos:

- O ciclo completo do Implicit Flow OIDC — do redirect ao IdP até a extração de claims.
- O mecanismo de armazenamento de token em `localStorage['appToken']` via `AuthStorageService`.
- A validação do token no backend por `ContainerRequestFilter` a cada requisição.
- A decisão de roteamento baseada no `StatusCadastro` do usuário retornado pelo banco.
- A sincronização automática e condicional do e-mail entre IdP e banco de dados.
- O carregamento de notificações pós-login com tolerância a falha.
- Todos os 24 RNs de P01 são referenciados diretamente nos elementos do diagrama.

---

## 2. Estrutura do Diagrama: Pool e Raias

### Pool: `P01 — Autenticação e Verificação de Cadastro | SOL/CBM-RS`

O diagrama utiliza **um único pool** com **quatro raias horizontais**, refletindo os quatro participantes técnicos do processo: o usuário humano, a aplicação Angular rodando no browser, o IdP estadual externo e o backend Java EE.

A escolha de um único pool em vez de múltiplos pools (com Message Flows entre eles) se justifica pela natureza do Implicit Flow: todos os passos são parte do mesmo processo de negócio do ponto de vista do SOL. Os fluxos de sequência que cruzam raias representam chamadas HTTP, redirects de browser e respostas — o que é visualmente mais claro com sequence flows cross-lane do que com message flows entre pools separados, dado que o Camunda Modeler não executa este processo (ele é `isExecutable="false"`).

---

### Raia 1: `Cidadão / RT / Fiscal (Usuário)`

Contém apenas uma user task (`UT_USR_001`): o preenchimento de credenciais no formulário do IdP. Esta raia existe para deixar explícito que há **uma ação humana real** no meio do fluxo — o usuário precisa interagir com o formulário do IdP antes que qualquer token seja emitido.

**Por que separar em raia própria:** Sem esta raia, o formulário do IdP e a validação de credenciais pareceriam processos automáticos acontecendo internamente ao IdP. A raia do usuário torna legível, para qualquer leitor do diagrama, que neste ponto o sistema está aguardando uma ação externa humana.

---

### Raia 2: `Frontend Angular (angular-oauth2-oidc / Implicit Flow / AuthStorageService)`

É a raia mais populosa: contém o start event, doze tarefas de serviço, quatro gateways e dois eventos de fim. Representa tudo que a aplicação Angular processa no browser do usuário.

**Por que a maioria dos elementos está nesta raia:** O Angular é o orquestrador do P01. Ele inicia o processo, decide quando redirecionar ao IdP, quando chamar o backend, qual rota exibir após login e quando o processo está concluído. O backend e o IdP são chamados pelo Angular e respondem a ele — logo, a lógica de decisão e o estado do processo residem no frontend.

---

### Raia 3: `IdP Estadual (meu.hml.rs.gov.br / PROCERGS / SOE)`

Contém quatro tarefas de serviço, um gateway e um evento de fim de erro. Representa o servidor de identidade estadual que autentica o usuário e emite o token.

**Por que o IdP tem raia própria e não é representado como tarefa única:** O IdP executa três operações distintas e independentes — retornar o Discovery Document, apresentar o formulário de login e emitir o token. Colapsar isso em uma única tarefa esconderia a complexidade do protocolo OIDC e tornaria invisível o ponto de falha mais comum do processo (credenciais inválidas no IdP).

---

### Raia 4: `Backend Java EE (WildFly / JAX-RS / EJB / CDI / JPA — Oracle)`

Contém quatro tarefas de serviço e um gateway. Representa o servidor de aplicação WildFly recebendo e processando as requisições HTTP vindas do Angular.

**Por que o backend tem raia própria:** As tarefas do backend são `@TransactionAttribute` EJBs com responsabilidades muito específicas — filtro de segurança, consulta ao banco, montagem de DTO, persistência. Separá-las visualmente deixa claro que toda chamada ao backend implica uma validação de Bearer token pelo `ContainerRequestFilter` antes de qualquer lógica de negócio ser executada.

---

## 3. Fase 0 — Inicialização da Aplicação Angular

### `SE_001` — Start Event: "Usuário acessa URL do sistema SOL no browser"

**O que representa:** O instante em que o browser carrega a aplicação Angular SPA — seja pela digitação da URL, clique em um link ou refresh da página. O Angular bootstraps o `AppComponent`, que invoca `ngOnInit()` imediatamente.

**Por que é um start event simples:** O processo é iniciado por navegação de browser — não há mensagem, sinal ou timer. O start event simples é o elemento correto para este tipo de gatilho.

**Por que está na raia do Frontend e não na raia do Usuário:** Tecnicamente, é o browser que carrega o Angular, não o usuário que "aciona" um botão. O start event representa o bootstrap da aplicação, que é responsabilidade da raia Frontend.

---

### `T_FE_001` — `AppConfigService.getConfig()` — Obtém configuração OIDC do servidor

**O que representa:** A primeira operação executada pelo `AppComponent.ngOnInit()` — buscar no servidor as configurações de autenticação antes de qualquer interação com o OAuthService. Retorna o objeto `authConfig` (`issuer`, `clientId`, `redirectUri`, `scope`) além dos flags de negócio (`licenciamentoHabilitado`, `riscoMedioHabilitado`, `tamanhoMaxArquivo`).

**Por que esta tarefa existe antes de qualquer lógica OIDC:** A configuração não é embutida no código Angular (`environment.ts`) de forma hardcoded. Ela é carregada dinamicamente do servidor a cada inicialização, garantindo que mudanças de ambiente (de homologação para produção, por exemplo) não exijam rebuild da aplicação. Além disso, o `redirectUri` é construído dinamicamente como `window.location.origin + authConfig.redirectUri`, permitindo que o mesmo build funcione em diferentes contextos de URL.

**Relação com `isReady`:** Durante esta chamada, `isReady = false` — a aplicação exibe um spinner e bloqueia a renderização do conteúdo até que a configuração seja recebida. O `finalize()` da chamada reseta este flag.

---

### `T_FE_002` — `AppComponent.configureAuth()` — Configura OAuthService, NullValidationHandler e listeners

**O que representa:** A segunda operação do `ngOnInit()`, que configura completamente a biblioteca `angular-oauth2-oidc` antes de qualquer interação com o IdP. Esta é a tarefa mais complexa da fase de inicialização porque executa seis operações em sequência obrigatória.

**Por que `NullValidationHandler` é configurado aqui (RN-02):** O handler padrão da biblioteca tentaria validar criptograficamente a assinatura do JWT usando o JWKS do IdP. O IdP estadual não disponibiliza um endpoint JWKS acessível pelo SPA, ou o certificado não é compatível com a validação client-side. A solução adotada é desabilitar a validação local e delegar essa responsabilidade ao backend, que valida o JWT a cada requisição via `ContainerRequestFilter`. O `NullValidationHandler` apenas decodifica o payload Base64 do token sem verificar a assinatura.

**Por que `setupAutomaticSilentRefresh()` é configurado aqui (RF-FE-10):** O Silent Refresh é o mecanismo que renova o token automaticamente antes de sua expiração, usando um `<iframe>` oculto que executa um novo Implicit Flow silenciosamente (sem redirecionar o browser). Se não fosse configurado neste momento, o token expiraria durante a sessão do usuário, obrigando-o a fazer login novamente. A configuração aqui garante que o mecanismo esteja ativo desde o início da sessão.

**Por que dois listeners são registrados aqui:**
- Listener `session_terminated`: registra apenas um `console.log`. A decisão de não redirecionar automaticamente ao logout é arquitetural — o sistema confia que o Silent Refresh tentará renovar a sessão antes de encerrar, e a expiração definitiva é tratada pelo próprio browser ao tentar uma próxima chamada.
- Listener `token_received`: dispara `loadUserProfile()` seguido de `verificaCadastro()`. Este é o ponto de entrada principal após qualquer autenticação bem-sucedida — tanto no primeiro login quanto após um Silent Refresh.

**Por que a lógica de ramificação `getIdentityClaims()` está aqui:** `configureAuth()` verifica se já há claims presentes no `localStorage['appToken']` (sessão existente). Se houver, chama `loadDiscoveryDocumentAndLogin()` diretamente em vez de `loadDiscoveryDocumentAndTryLogin()`. Esta distinção garante que usuários com sessão ativa não precisem passar pela tela de login do IdP.

---

## 4. Fase 1 — Discovery Document e Verificação de Token Existente

### `T_IDP_001` — IdP retorna Discovery Document

**O que representa:** A resposta do IdP ao pedido de `loadDiscoveryDocument()`. O OAuthService faz um `GET /.well-known/openid-configuration` para o IdP e recebe o JSON com todos os endpoints OIDC: `authorization_endpoint`, `token_endpoint`, `userinfo_endpoint`, `end_session_endpoint` e `jwks_uri`.

**Por que esta tarefa está na raia do IdP e não na raia do Frontend:** A tarefa representa a operação do IdP de servir sua configuração pública — o IdP é o ator que "executa" esta tarefa ao responder a requisição. O Angular apenas iniciou a chamada (modelado como o fluxo vindo de `T_FE_002`). Esta separação deixa claro que o Angular depende do IdP estar disponível neste ponto.

**Por que a tarefa está posicionada antes do gateway `GW_FE_001`:** O Discovery Document precisa ser carregado antes de qualquer verificação de token, pois sem os endpoints OIDC não é possível executar nem o `initImplicitFlow()` (que precisa do `authorization_endpoint`) nem o `tryLoginImplicitFlow()` (que precisa do `jwks_uri` para referência).

---

### `GW_FE_001` — Gateway: "access_token presente no localStorage['appToken']?"

**O que representa:** A decisão central da fase de inicialização: o Angular verifica se já há um token válido armazenado (`hasValidAccessToken()` e `getIdentityClaims()`). Esta verificação é executada pelo `UsuarioAutenticadoGuard.verificaLogin()`.

**Por que é um gateway exclusivo (XOR) e não paralelo:** Exatamente um dos dois caminhos é percorrido — ou o usuário tem token (sessão existente) e segue direto para o processamento, ou não tem token e precisa se autenticar no IdP. Nunca os dois caminhos simultâneos.

**Caminho NÃO (sem token):** Segue para `T_FE_003` — o Angular inicia o Implicit Flow redirecionando o browser ao IdP. Este é o caminho do primeiro acesso ou de sessão expirada.

**Caminho SIM (com token):** Segue diretamente para `T_FE_004` via um fluxo de sequência que passa acima de toda a área de autenticação do IdP (waypoints em y=145, acima das raias do IdP e do Usuário). Este "salto" visual representa que o usuário não precisa interagir com o IdP quando já possui sessão ativa.

**Por que `canActivate()` sempre retorna `true` (RN-04):** O Guard não bloqueia a rota Angular. A proteção real acontece via protocolo OIDC: se o token é inválido ou ausente, o próprio OAuthService redireciona o browser para o IdP. Esta abordagem é deliberada — o Angular não tem papel de "portão de segurança", pois toda segurança real está no backend validando o Bearer token a cada requisição.

---

## 5. Fase 2A — Fluxo Sem Token: Redirect ao IdP e Autenticação do Usuário

Esta fase é percorrida apenas quando `GW_FE_001` retorna NÃO — o usuário não tem token válido.

### `T_FE_003` — `oauthService.initImplicitFlow()` — Redirect ao IdP

**O que representa:** O Angular monta a URL de autorização do Implicit Flow e redireciona o browser para o IdP. Após este ponto, a aplicação Angular "encerra" — o browser navega para fora do domínio do SOL e só retornará após a autenticação.

**Por que Implicit Flow e não Authorization Code Flow:** A stack atual usa Implicit Flow porque a aplicação é um SPA sem capacidade de manter um segredo de cliente seguro no backend (o token é retornado diretamente no browser). O Authorization Code Flow com PKCE seria a evolução correta (stack moderna), mas a stack atual mantém o Implicit Flow por compatibilidade com o IdP estadual configurado.

**O `state` fixo (`'/some-state;p1=1;p2=2'`) como RN-documentada:** O parâmetro `state` deveria normalmente conter a rota original que o usuário tentou acessar, para redirecionar de volta após o login. A implementação atual usa um valor fixo — uma limitação conhecida da stack atual que não afeta a segurança (o `state` ainda protege contra CSRF), mas impede o "deep linking" pós-login.

**Por que esta tarefa está na raia do Frontend:** Embora o resultado seja o browser navegando para o IdP, quem monta a URL e dispara o redirect é o código Angular (`OAuthService.initImplicitFlow()`). A tarefa representa a ação do Angular, não a navegação do browser em si.

---

### `T_IDP_002` — IdP exibe formulário de autenticação

**O que representa:** O browser chegou ao IdP (`meu.hml.rs.gov.br`) e o IdP renderiza seu formulário de login — CPF e senha para cidadãos, ou login SOE para servidores estaduais.

**Por que esta tarefa existe na raia do IdP:** O IdP é responsável por apresentar e servir o formulário. O SOL não tem controle sobre esta tela — não pode personalizar o layout, os campos nem as mensagens de erro. Esta separação deixa explícito que o SOL é um _Relying Party_ e o IdP é o provedor de identidade soberano.

**Fluxo de sequência cruzando múltiplas raias:** O fluxo de `T_FE_003` (Frontend) desce para `T_IDP_002` (IdP), depois sobe para `UT_USR_001` (Usuário), depois desce de volta para `T_IDP_003` (IdP). Este padrão "zigue-zague" cross-lane representa fielmente o protocolo: o Angular redireciona ao IdP → IdP apresenta formulário ao usuário → usuário submete credenciais → IdP valida.

---

### `UT_USR_001` — User Task: "Usuário preenche credenciais no IdP"

**O que representa:** A ação humana central do processo de autenticação — o usuário preenche CPF e senha (ou usa certificado digital) no formulário do IdP e clica em "Entrar".

**Por que é uma User Task e não uma Service Task:** Em BPMN, `UserTask` é o elemento para representar trabalho realizado por um humano com suporte de sistema. O formulário do IdP é exibido por um sistema (o IdP), mas preenchido por um humano — portanto, User Task é o tipo correto. Modelar como Service Task implicaria processamento automático, o que seria semanticamente incorreto.

**Por que está na raia do Usuário e não na raia do IdP:** A _ação_ de preencher e submeter as credenciais é do usuário. O formulário pertence ao IdP, mas a atividade pertence ao usuário. Esta distinção é importante para análise de responsabilidades: o tempo de espera neste ponto é aguardando o usuário, não o sistema.

---

### `T_IDP_003` — IdP valida credenciais e perfis SOE

**O que representa:** O processamento interno do IdP após o usuário submeter o formulário. O IdP consulta o diretório SOE/LDAP, verifica a senha, carrega os papéis e perfis do usuário e decide se emite ou não o token.

**Por que esta tarefa existe separada do formulário (`T_IDP_002`):** São responsabilidades distintas do IdP. `T_IDP_002` é a apresentação da interface (UI), `T_IDP_003` é o processamento de negócio. Separar evidencia que a falha pode ocorrer em dois momentos diferentes — o formulário pode ser exibido corretamente mas a validação falhar.

---

### `GW_IDP_001` — Gateway: "Credenciais válidas no IdP?"

**O que representa:** O resultado da validação no IdP — autenticado ou rejeitado.

**Caminho NÃO → `EE_IDP_001` (Autenticação negada):** O processo P01 encerra neste ponto no SOL. O browser permanece na página de erro do IdP. O usuário pode tentar novamente. O SOL não recebe nenhuma notificação desta falha — o protocolo OIDC não prevê callback de falha.

**Caminho SIM → `T_IDP_004`:** O IdP procede à emissão do token.

**Por que é gateway no IdP e não no Frontend:** A decisão acontece dentro do sistema do IdP — o SOL não tem visibilidade deste processamento. Posicionar o gateway na raia do IdP documenta que este é um ponto de decisão externo ao controle da equipe que mantém o SOL.

---

### `EE_IDP_001` — End Event de Erro: "Autenticação negada no IdP"

**O que representa:** O encerramento do processo P01 quando as credenciais são inválidas. Este é o único desfecho de falha no IdP.

**Por que é um Error End Event:** O cancelamento por credencial inválida representa uma condição excepcional do processo — não é o fluxo normal esperado. O Error End Event comunica visualmente que o processo encerrou de forma não-planejada, diferente dos end events normais.

**Por que o processo "termina" aqui e não retorna ao formulário:** Em BPMN de processo, representamos o fluxo de negócio, não o loop de UI. O IdP pode apresentar novamente o formulário (loop interno ao IdP), mas do ponto de vista do processo SOL, uma falha de autenticação encerra o P01 — o usuário precisará iniciar um novo ciclo.

---

### `T_IDP_004` — IdP emite access_token e redireciona de volta

**O que representa:** A emissão do token OIDC pelo IdP via Implicit Flow. O IdP monta a URL de callback com o `access_token` no fragmento (`#`) e redireciona o browser de volta para o `redirectUri` da aplicação Angular.

**Por que o token vai no fragmento da URL e não no corpo da resposta:** Esta é a característica central do Implicit Flow — o token é retornado no fragmento da URL (`#access_token=eyJ...`). O fragmento não é enviado para o servidor (fica apenas no browser), garantindo que o backend da aplicação (ou qualquer proxy intermediário) não registre o token nos logs de acesso HTTP.

**Por que esta tarefa está na raia do IdP:** A emissão do token e o redirect são operações executadas pelo IdP — o Angular é apenas o destino do redirect, não o executor desta ação.

---

## 6. Fase 2B — Processamento do Token (JOIN das Duas Vias)

### `T_FE_004` — `oauthService.tryLoginImplicitFlow()` — Ponto de convergência (JOIN)

**O que representa:** O ponto de convergência entre os dois caminhos de `GW_FE_001`. Este elemento recebe dois fluxos de sequência:
1. O fluxo vindo do IdP (`T_IDP_004`) após autenticação bem-sucedida.
2. O fluxo vindo diretamente de `GW_FE_001` (SIM — token existente em localStorage).

**Por que o JOIN está aqui e não em um gateway de merge explícito:** O `T_FE_004` executa `tryLoginImplicitFlow()`, que é a operação correta em ambos os casos. Quando há token no fragment da URL, ela extrai e processa o token. Quando não há fragment (sessão existente), ela verifica o token no localStorage. Colocar o merge no próprio task de serviço é válido em BPMN e evita um gateway desnecessário que não representa decisão alguma.

**Por que o fluxo "sessão existente" passa ACIMA da área de autenticação (waypoints em y=145):** O fluxo de sequência que vai de `GW_FE_001` diretamente para `T_FE_004` precisa visualmente "pular" toda a área das raias do Usuário, IdP e da fase de autenticação. Usar waypoints em y=145 (dentro da faixa superior da raia Frontend, acima de todos os outros elementos) torna este bypass imediatamente legível — qualquer leitor entende que o caminho "sessão ativa" não passa pelo IdP.

**Relação com `token_received`:** Quando o fragment contém um token novo, `tryLoginImplicitFlow()` dispara o evento interno `token_received`, que aciona o listener registrado em `T_FE_002`. Esse listener chama `loadUserProfile()` e depois `verificaCadastro()`. Esta cadeia de eventos assíncronos é representada no BPMN como a sequência `T_FE_004 → T_FE_005 → T_FE_006 → T_FE_007 → T_FE_008`.

---

### `T_FE_005` — `NullValidationHandler` — Extrai claims sem validar assinatura JWT (RN-02)

**O que representa:** A extração das claims do JWT (name, cpf, email, phone_number, birthdate) sem verificar criptograficamente a assinatura do token.

**Por que esta tarefa existe explicitamente no BPMN:** RN-02 é uma decisão arquitetural crítica e não óbvia — normalmente, um sistema OIDC validaria a assinatura do JWT no cliente. Tornar esta etapa explícita como tarefa separada serve para documentar:
1. Que a validação não acontece no frontend.
2. Que isso é intencional e motivado pela incompatibilidade do IdP estadual com a validação client-side.
3. Que a validação real ocorre no backend a cada requisição (referenciada em `T_BE_001`).

**Risco documentado:** Se o token for forjado e inserido manualmente no localStorage, o frontend aceitaria as claims sem questionar. A proteção real está no backend — o `ContainerRequestFilter` valida o JWT com a chave pública do IdP antes de qualquer operação.

---

### `T_FE_006` — `AuthStorageService.setItem()` — Persiste token em localStorage['appToken'] (RN-03)

**O que representa:** A persistência do token e das claims em `localStorage['appToken']` como um objeto JSON agregador. O `AuthStorageService` implementa a interface `OAuthStorage` da biblioteca `angular-oauth2-oidc`, substituindo o storage padrão.

**Por que um storage customizado em vez do padrão da biblioteca:** O storage padrão da biblioteca distribui as chaves OIDC diretamente no `localStorage` (ex: `access_token`, `id_token` como entradas separadas). O `AuthStorageService` agrega todas sob uma única chave `appToken`, facilitando:
1. O `clean()` — basta um `localStorage.removeItem('appToken')` para limpar toda a sessão.
2. Evitar colisões de chave com outras bibliotecas que possam usar nomes similares no localStorage.
3. Inspecionar toda a sessão OIDC em um único objeto durante depuração.

**Estrutura persistida:**
```json
{
  "access_token": "eyJhbGc...",
  "id_token": "eyJhbGc...",
  "expires_at": "1710000000000",
  "token_type": "bearer",
  "nonce": "abc123...",
  "session_state": "xxxxxxxx"
}
```

---

### `T_FE_007` — `oauthService.loadUserProfile()` — GET /userinfo

**O que representa:** A chamada ao endpoint `userinfo` do IdP para obter as claims do usuário autenticado. Mesmo que algumas claims já estejam no `id_token`, esta chamada garante dados frescos e completos.

**Por que esta chamada é necessária se o token já contém claims:** Dependendo da configuração do IdP, nem todas as claims desejadas estão no token (por limitação de tamanho ou política de privacidade). O endpoint `userinfo` retorna o conjunto completo. Além disso, permite detectar mudanças de dados do usuário no IdP que possam ter ocorrido desde a emissão do token.

**Por que a tarefa está na raia do Frontend:** A chamada é feita pelo `OAuthService` Angular, usando o `access_token` como Bearer. O IdP responde, mas a responsabilidade de iniciar e processar a resposta é do Angular.

---

## 7. Fase 3 — Verificação de Cadastro no SOL (Frontend → Backend)

### `T_FE_008` — `AppComponent.verificaCadastro()` — Inicia verificação com isReady=false

**O que representa:** O ponto em que o Angular, já com o token e as claims em mãos, consulta o backend SOL para saber se o usuário existe no banco e qual é o status do seu cadastro.

**Por que `isReady = false` é definido aqui:** O flag `isReady` controla se o conteúdo principal da aplicação é exibido. Durante a chamada ao backend, o usuário deve ver apenas o spinner de loading — não deve ter acesso parcial à interface enquanto o status do cadastro não é conhecido. Definir `isReady = false` no início de `verificaCadastro()` garante que qualquer navegação anterior não deixe conteúdo visível.

**Por que esta tarefa está no Frontend e não no Backend:** `verificaCadastro()` é um método do `AppComponent` — ele extrai as claims locais, define `isReady`, e dispara a chamada HTTP. A tarefa representa a preparação e o despacho da requisição, não o processamento no servidor.

**Relação com o interceptor (RN-05):** A chamada `buscarUsuario(cpf)` que `verificaCadastro()` emite passa pelo `HttpAuthorizationInterceptor`, que adiciona `Authorization: Bearer {token}` automaticamente. O interceptor age em todas as requisições cujas URLs contêm `AppSettings.baseUrl` — URLs externas (como as do IdP) não recebem o header.

---

### `T_BE_001` — `JAX-RS ContainerRequestFilter` — Valida Bearer, popula CidadaoSessionMB

**O que representa:** O filtro de segurança que intercepta TODA requisição HTTP ao backend antes de qualquer EJB ou endpoint ser executado. É o mecanismo central de autenticação do lado servidor.

**Por que esta tarefa está na raia do Backend:** A validação do JWT e a criação do `CidadaoED` são operações do servidor. O Angular apenas envia o token — quem decide se ele é válido é o backend.

**Por que esta tarefa é separada das demais tarefas do backend:** O `ContainerRequestFilter` executa em um estágio diferente do ciclo de vida JAX-RS — antes do dispatch do método de negócio. Representá-lo como tarefa separada documenta que:
1. Toda requisição ao backend, sem exceção, passa por esta validação.
2. O `CidadaoSessionMB` (`@RequestScoped`) é populado aqui e disponível para injeção em qualquer EJB da mesma requisição.
3. A falha aqui retorna HTTP 401 antes de qualquer acesso ao banco de dados.

**Por que `CidadaoED.nullInstance()` é mencionado:** Este método factory existe para evitar `NullPointerException` em componentes que injetam `CidadaoSessionMB` antes de ele ser populado (em testes, por exemplo). O `nullInstance()` retorna um `CidadaoED` com `email = ""`, garantindo que `getCidadaoED()` nunca retorne `null`.

---

### `T_BE_002` — `UsuarioRN.consultaPorCpf(cpf)` — Consulta completa do usuário

**O que representa:** A consulta ao banco Oracle para localizar o `UsuarioED` pelo CPF e montar o objeto `Usuario` completo com todas as coleções associadas.

**Por que `@TransactionAttribute(SUPPORTS)` e não `REQUIRED`:** A consulta é somente-leitura — não há escrita no banco. `SUPPORTS` participa de uma transação existente se houver, mas não cria uma nova desnecessariamente. Isso economiza recursos de pool de conexão para operações de leitura.

**Por que o workaround de timezone (RN-19) é documentado:** O ajuste `dtNascimento.set(Calendar.HOUR, 12)` é uma correção necessária para evitar que a data de nascimento apareça como o dia anterior em fusos horários negativos (UTC-3, por exemplo). Sem este ajuste, uma data salva como `1990-01-15T00:00:00Z` seria exibida como `1990-01-14` no Brasil. Documentar este detalhe técnico no BPMN garante que qualquer desenvolvedor que toque neste código entenda o porquê.

**Por que as coleções (endereços, graduações, especializações) são carregadas aqui:** O `verificaCadastro()` no Angular usa `usuario.status` para rotear o usuário — os demais dados são usados imediatamente pelo dashboard e pelo componente de notificações. Carregar tudo em uma única chamada evita múltiplos round-trips ao backend logo após o login.

---

### `GW_BE_001` — Gateway: "Usuário encontrado no BD SOL?"

**O que representa:** A decisão baseada no retorno de `consultaPorCpf()` — o CPF existe na tabela `USUARIO` ou não.

**Caminho NÃO (HTTP 404):** O fluxo de sequência cruza múltiplas raias (de BE para FE) e vai diretamente para `T_FE_009` (navigate para `/cadastro`). Este fluxo cross-lane de longa distância (cruzando a raia do IdP) representa o retorno HTTP 404 ao Angular.

**Caminho SIM (HTTP 200):** Segue para `T_BE_003` que monta o objeto `Usuario` completo e o retorna ao Angular.

**Por que o caminho 404 vai diretamente para `T_FE_009` e não para um gateway FE intermediário:** O comportamento ante um 404 é determinístico — sempre navegar para `/cadastro`. Não há decisão adicional necessária no Frontend para este caso. Rotar o 404 diretamente para `T_FE_009` evita um gateway desnecessário e torna o diagrama mais limpo.

---

### `T_BE_003` — Retorna Usuario completo (HTTP 200)

**O que representa:** A serialização do objeto `Usuario` como JSON e o retorno HTTP 200 para o Angular. Esta tarefa é a conclusão bem-sucedida do ciclo de chamada FE → BE → FE da fase de verificação.

**Por que esta tarefa existe separada do gateway:** O gateway `GW_BE_001` decide se o usuário foi encontrado. `T_BE_003` executa o trabalho de montar o DTO completo — inclui o workaround de timezone, o carregamento das coleções e a formatação do `AnaliseInstrutor` se aplicável. São responsabilidades distintas, daí a separação.

---

## 8. Fase 4 — Análise de Status e Roteamento

### `GW_FE_002` — Gateway: "Status do cadastro retornado pelo backend?"

**O que representa:** A decisão de roteamento central do P01 — para onde o usuário vai após o login, baseado no `status` do cadastro retornado pelo backend.

**Recebe dois fluxos de entrada:**
1. De `T_BE_003` (usuário encontrado, HTTP 200) — o `usuario.status` está disponível.
2. De `GW_BE_001` via `T_FE_009` (para o caso 404) — mas note que o 404 vai diretamente para `T_FE_009`, não para `GW_FE_002`.

Na prática, `GW_FE_002` recebe apenas o fluxo de `T_BE_003` (usuário encontrado), e avalia o `status`:

**Caminho INCOMPLETO → `T_FE_009`:** O cadastro existe mas está incompleto (documentos não enviados). Vai para `/cadastro` para completar o P02.

**Caminho outros status (ANALISE_PENDENTE, EM_ANALISE, APROVADO, REPROVADO) → `GW_FE_003`:** O usuário tem acesso ao sistema. Segue para verificação de e-mail.

**Por que REPROVADO também permite acesso:** Um usuário com cadastro reprovado ainda pode acessar o sistema para consultar o motivo da reprovação, submeter novo cadastro ou acompanhar o processo. Bloquear o acesso ao sistema inteiro para REPROVADO seria uma política mais restritiva do que a implementada.

---

### `T_FE_009` — `router.navigate(['/cadastro'])` — Redireciona para o P02

**O que representa:** O redirecionamento do Angular para a rota `/cadastro`, que carrega o `CadastroUsuarioComponent` (P02). Esta tarefa recebe dois fluxos de entrada — 404 (usuário não existe) e INCOMPLETO (cadastro incompleto).

**Por que um único task para dois casos (404 e INCOMPLETO):** O comportamento é idêntico nos dois casos — `router.navigate(['/cadastro'])`. Usar um gateway de merge antes de `T_FE_009` seria redundante. Em BPMN, uma tarefa pode ter múltiplos fluxos de entrada sem necessidade de gateway de convergência explícito quando o comportamento é uniforme.

**Relação com isReady:** `isReady` permanece `false` durante este redirecionamento — o loading não é removido. O P02 assumirá o controle e definirá seu próprio estado de carregamento.

---

### `EE_FE_002` — End Event: "Usuário → /cadastro (P02 iniciado)"

**O que representa:** O encerramento do P01 via caminho alternativo — o usuário é novo ou tem cadastro incompleto e precisa completar o P02 antes de acessar o sistema principal.

**Por que este end event existe na raia do Frontend e não na raia do Usuário:** É o Angular que executou o redirecionamento — `router.navigate()` é uma operação do Angular, não do usuário. O usuário verá o resultado (tela de cadastro), mas a ação de navegar é do sistema.

---

## 9. Fase 5 — Sincronização Condicional de E-mail

### `GW_FE_003` — Gateway: "email claims ≠ BD E status ≠ EM_ANALISE?" (RN-06)

**O que representa:** A verificação de divergência entre o e-mail registrado no IdP (nas claims OIDC) e o e-mail registrado no banco SOL. A sincronização só ocorre se as duas condições forem verdadeiras simultaneamente.

**Por que a sincronização de e-mail é um gateway separado e não parte de `GW_FE_002`:** São decisões logicamente independentes. `GW_FE_002` decide se o usuário pode acessar o sistema (por status de cadastro). `GW_FE_003` decide se há uma discrepância de dados que precisa ser corrigida. Misturar as duas lógicas em um único gateway tornaria o fluxo mais difícil de ler e de testar.

**Por que status `EM_ANALISE` bloqueia a sincronização (RN-06):** Quando o cadastro está em análise por um administrador do CBM-RS, o ADM pode estar comparando o e-mail histórico com documentos físicos. Uma alteração automática de e-mail durante a análise poderia criar inconsistência entre o cadastro sob revisão e o novo e-mail. A regra protege a integridade do processo de análise.

**Caminho SIM → `T_FE_010`:** E-mail divergente e sincronização permitida.

**Caminho NÃO → `T_FE_011`:** E-mail igual ou status EM_ANALISE. A rota desvia por cima de `T_FE_010` (waypoints em y=215, acima da tarefa de sincronização), unindo-se em `T_FE_011`.

---

### `T_FE_010` — `AppComponent.atualizarUsuario()` — Sincroniza e-mail via PUT /usuarios/{id}

**O que representa:** A atualização do e-mail do usuário no banco SOL para refletir o e-mail atual do IdP. Também dispara um efeito colateral em sistema externo via `alteraProprietario()`.

**Por que a sincronização é automática e silenciosa:** O usuário não é perguntado sobre a atualização de e-mail. O e-mail do IdP é considerado a fonte autoritativa de verdade (o usuário pode ter atualizado no portal estadual), e o SOL sincroniza automaticamente. Forçar o usuário a confirmar esta mudança a cada login com e-mail diferente seria uma fricção desnecessária.

**Por que `alteraProprietario()` é chamado após `salvar()` (RN-07):** O SOL integra com outro sistema (não identificado explicitamente no código) que mantém um cadastro de proprietários. A chamada `alteraProprietario(cpf, email, 'F')` garante que este sistema externo também seja atualizado. O parâmetro `'F'` indica pessoa física. Erros nesta integração são ignorados silenciosamente — a sincronização com o sistema externo é "best effort", não bloqueante.

---

### `T_BE_004` — `UsuarioRN.alterar(id, usuario)` — Persiste o e-mail atualizado

**O que representa:** A persistência da mudança de e-mail no banco Oracle, via `UPDATE USUARIO SET EMAIL=:email, CTR_DTH_ATU=NOW() WHERE ID=:id`.

**Por que a verificação de concorrência (`ctrDthAtu`) se aplica aqui (RN-11):** Se outro processo estiver modificando o mesmo `UsuarioED` simultaneamente (ex: um ADM alterando dados durante análise), o `ctrDthAtu` diferente detectará o conflito e retornará HTTP 409 CONFLICT. Isso previne que a atualização de e-mail silencie uma alteração administrativa concorrente.

**Por que a verificação é omitida para status INCOMPLETO:** Um usuário com cadastro INCOMPLETO está no meio do processo de preenchimento — múltiplas edições simultâneas são esperadas e controladas pelo próprio formulário de cadastro, não pelo controle de concorrência do `ctrDthAtu`.

**Cross-lane de subida (T_BE_004 → T_FE_011):** O fluxo de retorno da sincronização sobe da raia do Backend para a raia do Frontend representando o retorno HTTP 200 com o objeto `Usuario` atualizado. O waypoint em x=3470 garante que este fluxo entre em `T_FE_011` pela esquerda, não colidindo visualmente com o fluxo vindo de `GW_FE_003`.

---

## 10. Fase 6 — Inicialização do Dashboard

### `T_FE_011` — `setUsuarioLocalStorage()` + `router.initialNavigation()` + isReady=true

**O que representa:** O ponto de convergência final antes do dashboard ser exibido. Recebe dois fluxos:
1. De `GW_FE_003` (sem sincronização necessária).
2. De `T_BE_004` (após sincronização bem-sucedida de e-mail).

**Por que três operações são agrupadas em uma única tarefa:** Estas três ações são atomicamente parte do mesmo passo lógico — "finalizar o processo de login e exibir o sistema". Separá-las em três tarefas distintas seria granularidade excessiva sem valor informativo adicional.

**`setUsuarioLocalStorage(usuario)`:** Persiste o objeto `Usuario` no localStorage para que todos os componentes Angular filhos possam acessar os dados do usuário logado sem precisar consultar o backend a cada renderização.

**`router.initialNavigation()`:** Instrui o Angular a processar a rota originalmente solicitada. Se o usuário tentou acessar `/licenciamento/meus-licenciamentos`, esta chamada iniciará a navegação para lá agora que a autenticação está completa.

**`isReady = true`:** Remove o spinner de loading e exibe o conteúdo principal da aplicação. Este é o momento em que o usuário vê o sistema pela primeira vez após o login.

---

### `T_FE_012` — `getNotificacoes()` — Carrega notificações com tolerância a falha (RN-24)

**O que representa:** A consulta ao backend para carregar as notificações pendentes do usuário — alertas de renovação, comunicados de inconformidade, atualizações de status de cadastro, etc.

**Por que esta tarefa vem depois de `isReady = true` e não antes:** As notificações não são críticas para o acesso ao sistema. O usuário já pode navegar enquanto as notificações são carregadas. Bloquear o dashboard aguardando notificações seria uma penalização de UX desnecessária.

**Por que falhas são ignoradas silenciosamente (RN-24):** `handleErrorAndContinue([])` retorna uma lista vazia em caso de erro. A ausência de notificações não impede o uso do sistema — é apenas um dado de conveniência. Mostrar uma mensagem de erro de notificações logo após o login seria uma experiência negativa desproporcional à gravidade do problema.

**O mecanismo de roteamento por contexto de notificação:** Ao clicar em uma notificação, o Angular remove-a da lista local (feedback imediato sem aguardar o servidor), marca como lida e persiste via `alterarNotificacao()`, depois navega para a rota correspondente ao contexto. Esta sequência representa uma estratégia de "optimistic update" — o UI responde imediatamente, enquanto a persistência ocorre assincronamente.

---

## 11. Eventos de Fim: Três Desfechos Possíveis

O P01 possui três eventos de fim, cada um representando um desfecho distinto:

| End Event | Raia | Condição | Status do processo |
|---|---|---|---|
| `EE_FE_001` — Dashboard apresentado | Frontend | Autenticação + cadastro OK | Sucesso — P01 completo |
| `EE_FE_002` — Usuário → /cadastro | Frontend | Usuário novo (404) ou INCOMPLETO | Redirecionamento — P02 iniciado |
| `EE_IDP_001` — Autenticação negada | IdP | Credenciais inválidas no IdP | Falha — processo encerrado no IdP |

**Por que três end events e não um único end event com múltiplas condições:** Cada desfecho representa um estado final diferente do processo e comunica diferentes consequências para o usuário e para o sistema. Um único end event genérico não transmitiria essa distinção. Em BPMN, múltiplos end events são o padrão recomendado quando existem desfechos semanticamente distintos.

---

## 12. Justificativas de Modelagem

### J1 — Por que um único pool com quatro raias?

O processo P01, embora envolva o IdP como sistema externo, é do ponto de vista do SOL um processo único e coordenado pelo Angular. Usar um pool separado para o IdP (com Message Flows) implicaria que o IdP é um parceiro de negócio igual ao SOL — o que não reflete a realidade. O IdP é um provedor de serviço que o SOL consome via protocolo padrão. A raia do IdP dentro do pool único expressa que o IdP é um participante técnico do processo, não um processo de negócio independente.

### J2 — Por que fluxos cross-lane ao invés de Message Flows?

Num BPMN de colaboração com múltiplos pools, Message Flows representariam as chamadas HTTP entre sistemas. Com um único pool e raias, os fluxos cross-lane representam a mesma semântica de forma mais compacta. A escolha de pool único com raias é preferível aqui porque não há processos independentes e assíncronos — tudo faz parte do mesmo processo de autenticação linear.

### J3 — Por que o Silent Refresh não aparece como loop no BPMN?

O Silent Refresh é um mecanismo de background contínuo, configurado em `T_FE_002` e ativo durante toda a sessão. Modelá-lo como um loop explícito no BPMN exigiria uma sub-rotina ou um evento de borda de timer em loop — adicionando complexidade visual que obscureceria o fluxo principal. A decisão foi documentar o Silent Refresh dentro das `<documentation>` de `T_FE_002` e `T_FE_012` (onde o contexto de "sessão ativa" é estabelecido), sem poluir o fluxo principal com um sub-processo de renovação.

### J4 — Por que `GW_BE_001` tem o caminho 404 indo diretamente para `T_FE_009` sem passar por `GW_FE_002`?

O 404 tem um único desfecho possível: navegar para `/cadastro`. Não há decisão adicional que o Frontend precise tomar ao receber um 404. Passar o 404 por `GW_FE_002` criaria um gateway com apenas uma rota real de saída para o caso 404 — o que seria um "pseudo-gateway" sem valor decisório. O fluxo direto `GW_BE_001 → T_FE_009` é mais honesto semanticamente.

### J5 — Por que as tarefas do Backend estão posicionadas verticalmente alinhadas com as tarefas do Frontend que as chamam?

`T_FE_008` e `T_BE_001` estão no mesmo x (x≈2360). `T_FE_010` e `T_BE_004` estão no mesmo x (x≈3280). Este alinhamento vertical permite que os fluxos cross-lane sejam linhas retas verticais (sem curvatura horizontal), tornando imediatamente visível que o Frontend chama o Backend naquele ponto específico do processo. É uma convenção de layout que facilita a rastreabilidade entre chamada HTTP e processamento backend.

### J6 — Por que o `HttpAuthorizationInterceptor` não aparece como tarefa separada?

O interceptor é um mecanismo transversal (AOP-like) — ele age sobre todas as requisições HTTP que o Angular faz para o backend, sem ser chamado explicitamente pelo código de negócio. Modelá-lo como tarefa separada em cada chamada HTTP seria redundante e poluiria o diagrama. A decisão foi documentá-lo dentro das tarefas que fazem chamadas ao backend (`T_FE_008` e `T_FE_010`), registrando que RN-05 está ativo.

---

## 13. Diagrama de Estados do Cadastro (StatusCadastro)

O enum `StatusCadastro` define o ciclo de vida do cadastro do usuário. O P01 lê este status (via `GET /usuarios/{cpf}`) e roteia o usuário conforme o estado atual:

```
                       ┌─────────────────┐
    [Usuário cria       │                 │
     cadastro via P02]  │   INCOMPLETO    │◄── Estado inicial de todo novo usuário (RF-BE-05)
                        │                 │    Documentos não enviados ou insuficientes
                        └────────┬────────┘
                                 │
                       [concluirCadastro() com documentos completos — RF-BE-07]
                                 │
                        ┌────────▼────────┐
                        │                 │
                        │ ANALISE_PENDENTE│ ◄── Aguardando fila de análise do ADM
                        │                 │
                        └────────┬────────┘
                                 │
                       [ADM assume análise — P04]
                                 │
                        ┌────────▼────────┐
                        │                 │
                        │   EM_ANALISE    │ ◄── Não sincroniza e-mail (RN-06)
                        │                 │
                        └───┬─────────┬───┘
                            │         │
             [ADM aprova]   │         │  [ADM reprova]
                            │         │
                   ┌────────▼─┐   ┌───▼────────┐
                   │          │   │            │
                   │ APROVADO │   │ REPROVADO  │
                   │          │   │            │
                   └──────────┘   └────────────┘
                   RT válido para      Acesso ao
                   licenciamento       sistema mantido
                   (P03, P06, etc.)    (não pode ser RT)
```

**Como o P01 usa este diagrama de estados:**
- `INCOMPLETO` ou `404` → `T_FE_009` (navigate para P02)
- `ANALISE_PENDENTE`, `EM_ANALISE`, `APROVADO`, `REPROVADO` → `GW_FE_003` (verificação de e-mail)
- `EM_ANALISE` especificamente → não sincroniza e-mail (RN-06)

---

## 14. Referência Cruzada: Elementos BPMN × Código

| Elemento BPMN | ID | Classe / Método | RNs |
|---|---|---|---|
| Start — Usuário acessa URL | `SE_001` | `AppComponent.ngOnInit()` | RN-01 |
| Obtém config OIDC do servidor | `T_FE_001` | `AppConfigService.getConfig()` | RF-FE-01 |
| Configura OAuthService / NullValidationHandler | `T_FE_002` | `AppComponent.configureAuth()` | RN-02, RN-23, RF-FE-10 |
| IdP retorna Discovery Document | `T_IDP_001` | `GET /.well-known/openid-configuration` | RF-FE-02 |
| Token presente? | `GW_FE_001` | `OAuthService.hasValidAccessToken()` | RN-04 |
| initImplicitFlow() | `T_FE_003` | `OAuthService.initImplicitFlow()` | RN-01, RF-FE-08 |
| IdP exibe formulário autenticação | `T_IDP_002` | IdP — authorization_endpoint | — |
| Usuário preenche credenciais | `UT_USR_001` | Ação humana no IdP | — |
| IdP valida credenciais | `T_IDP_003` | IdP — validação interna | — |
| Credenciais válidas? | `GW_IDP_001` | IdP — decisão de emissão | — |
| Autenticação negada | `EE_IDP_001` | Erro do IdP | — |
| IdP emite access_token | `T_IDP_004` | IdP — Implicit Flow response | RN-01 |
| tryLoginImplicitFlow() (JOIN) | `T_FE_004` | `OAuthService.tryLoginImplicitFlow()` | RF-FE-02 |
| NullValidationHandler — extrai claims | `T_FE_005` | `NullValidationHandler` | RN-02 |
| AuthStorageService — persiste token | `T_FE_006` | `AuthStorageService.setItem()` | RN-03 |
| loadUserProfile() | `T_FE_007` | `OAuthService.loadUserProfile()` | RF-FE-02 |
| verificaCadastro() | `T_FE_008` | `AppComponent.verificaCadastro()` | RF-FE-06, RN-05 |
| ContainerRequestFilter — valida Bearer | `T_BE_001` | `CidadaoSessionMB` (JAX-RS Filter) | RF-BE-01, RN-18 |
| UsuarioRN.consultaPorCpf() | `T_BE_002` | `UsuarioRN.consultaPorCpf(cpf)` | RF-BE-03, RN-19, RN-20 |
| Usuário encontrado no BD? | `GW_BE_001` | `UsuarioRestImpl` → null → 404 | RN-08 |
| Retorna Usuario completo | `T_BE_003` | `BuilderUsuario.of()` | RF-BE-03, RN-19 |
| Status do cadastro? | `GW_FE_002` | `StatusCadastroUsuarioEnum[status]` | RN-08 |
| navigate('/cadastro') | `T_FE_009` | `Router.navigate(['/cadastro'])` | RN-08 |
| End — Usuário → /cadastro | `EE_FE_002` | — | — |
| email diverge E status ≠ EM_ANALISE? | `GW_FE_003` | Comparação claims vs usuario.email | RN-06 |
| atualizarUsuario() — sincroniza email | `T_FE_010` | `AppComponent.atualizarUsuario()` | RN-06, RN-07 |
| UsuarioRN.alterar() — persiste email | `T_BE_004` | `UsuarioRN.alterar(id, usuario)` | RF-BE-06, RN-11 |
| setLocalStorage + initialNavigation | `T_FE_011` | `AppComponent.inicializarSessao()` | RF-FE-11 |
| getNotificacoes() | `T_FE_012` | `AppComponent.getNotificacoes()` | RF-FE-12, RN-24 |
| End — Dashboard apresentado | `EE_FE_001` | — | — |

---

*Documento gerado a partir da análise do código-fonte `SOLCBM.FrontEnd16-06` e `SOLCBM.BackEnd16-06` e do BPMN `SOL_CBM_RS_Processo_P01_StackAtual.bpmn`.*
