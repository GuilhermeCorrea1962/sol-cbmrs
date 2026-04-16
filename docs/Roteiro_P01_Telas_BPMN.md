# Roteiro Ilustrado — P01: Autenticação no Sistema SOL/CBM-RS

**Referência de telas:** `Apresentação COMPLETA do sistema SOL.pdf` — páginas 56–57
**Referência BPMN:** `SOL_CBM_RS_Processo_P01_StackAtual.bpmn`
**Referência técnica:** `Fluxograma_P01_Autenticacao.md`
**Data:** 2026-03-05

---

## Visão Geral do Processo

O P01 é o processo que permite a qualquer usuário — cidadão, Responsável Técnico (RT) ou bombeiro CBMRS — acessar o Sistema SOL com segurança. O processo envolve **4 participantes** distribuídos em raias no BPMN:

| Raia BPMN | Participante | Papel |
|---|---|---|
| **Lane_FE** | Frontend Angular (SPA) | Orquestra o fluxo de autenticação, armazena token, redireciona |
| **Lane_IdP** | Identity Provider (SOE PROCERGS / meu.rs.gov.br) | Valida identidade e emite token JWT |
| **Lane_BE** | Backend SOL (Java EE REST) | Verifica cadastro do usuário no sistema SOL |
| *(implícito)* | Usuário (RT / CBMRS) | Interage com as telas |

O fluxo completo do ponto de vista do usuário percorre **3 telas principais** identificadas no PDF e **4 desfechos possíveis** dependendo do status de cadastro.

---

## Mapa das Telas × Tarefas BPMN

```
TELA PDF p.57 (lado esquerdo)          TELA PDF p.57 (lado direito)
┌─────────────────────────┐            ┌──────────────────────────┐
│  Portal Público SOL     │ ──────────>│  SOE PROCERGS (IdP)      │
│  [Acessar como cidadão] │ clique     │  [Org/Usuário/Senha]     │
│  [Acessar como CBMRS]   │            │  [Entrar]                │
└─────────────────────────┘            └──────────────────────────┘
         T_FE_001 / T_FE_002                    T_FE_003 / T_IdP_*
                                                        │
                                    ┌──────────┬────────┴───────┐
                                    ▼          ▼                ▼
                              [INCOMPLETO] [PENDENTE]      [APROVADO]
                              → P02       → Aguarda        → Home SOL
                              T_FE_010    T_FE_011         T_FE_012
```

---

## PASSO 1 — Usuário acessa o portal SOL

**Tarefa BPMN:** `T_FE_001` — *Carregar SPA e configurar OIDC*
**Raia:** Frontend Angular
**Tela:** Nenhuma interação visual — carregamento automático da aplicação

**O que acontece internamente:**
O Angular inicializa o `AppComponent`, que chama `configureAuth()` para conectar ao IdP. Nesta etapa:
- É feito o download do **discovery document** do SOE PROCERGS (`.well-known/openid-configuration`)
- O silent refresh automático é configurado
- O listener de eventos `token_received` é registrado

**Do ponto de vista do usuário:** O navegador exibe a URL do portal SOL. A tela que aparece é a **Tela P01-01** (página 57, lado esquerdo do PDF).

---

## PASSO 2 — Tela P01-01: Portal Público SOL

> **Localização no PDF:** Página 57 — painel esquerdo

Esta é a tela de entrada do sistema. Ela não exige login para ser exibida, mas todo conteúdo interno está protegido.

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│    [Logo SOL-CBMRS]                                 │
│                                                     │
│    ┌────────────────────────────────────┐           │
│    │  Acessar como cidadão  [LARANJA]   │           │  ← Botão principal
│    └────────────────────────────────────┘           │
│                                                     │
│    Acessar como CBMRS                               │  ← Link para bombeiros
│                                                     │
│    Consulta pública | Legislação | Perguntas freq.  │  ← Área pública
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Elementos e seus papéis no processo:

#### Botão "Acessar como cidadão" (laranja)
- **Quem usa:** RT, cidadão, qualquer pessoa com cadastro no Gov.RS
- **Tarefa BPMN ativada:** `T_FE_002` — *Iniciar fluxo OAuth (initImplicitFlow)*
- **O que faz:** Aciona `oauthService.initImplicitFlow()` no Angular, que constrói a URL de autorização do SOE PROCERGS com os parâmetros:
  - `client_id`: `209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s`
  - `response_type`: `token`
  - `scope`: `openid public_profile email name cpf birthdate phone_number`
  - `redirect_uri`: URL do portal SOL
- **Resultado:** O navegador é **redirecionado para o SOE PROCERGS** (Tela P01-02)

#### Link "Acessar como CBMRS"
- **Quem usa:** Bombeiros militares, analistas, gestores CBMRS
- **Tarefa BPMN ativada:** `T_FE_002` — mesmo mecanismo OAuth, mesma tela do SOE PROCERGS
- **Diferença:** O perfil retornado pelo IdP identificará o usuário como interno, e o backend concederá permissões de back-office
- **Resultado:** Idêntico ao "Acessar como cidadão" — redireciona para Tela P01-02

#### Links de acesso público ("Consulta pública", "Legislação", "Perguntas frequentes")
- **Quem usa:** Qualquer pessoa, sem necessidade de login
- **Papel no BPMN:** Fora do fluxo principal do P01 — não ativam nenhuma tarefa de autenticação
- **Função:** Permitem consulta ao portal sem autenticação, via rotas não protegidas pelo `UsuarioAutenticadoGuard`

---

## PASSO 3 — Redirecionamento para o IdP (automático)

**Tarefa BPMN:** `T_FE_002` → `T_IdP_001` *(processo interno, sem tela SOL)*
**Raia:** Frontend Angular → Identity Provider

Após o clique em qualquer botão de acesso, o navegador sai do portal SOL e vai para o SOE PROCERGS. Esta transição é automática e imperceptível — o usuário vê a URL mudar para o domínio do IdP estadual.

**Parâmetros enviados na URL:**
```
https://meu.rs.gov.br/oauth/authorize?
  response_type=token
  &client_id=209_ooyx4ldpd8g4o444s880s00oc4g8go8o48k84cwsgs4ok0w4s
  &redirect_uri=https://sol.cbm.rs.gov.br/
  &scope=openid public_profile email name cpf birthdate phone_number
```

---

## PASSO 4 — Tela P01-02: SOE PROCERGS — Autenticação

> **Localização no PDF:** Página 57 — painel direito

Esta tela é **externa ao sistema SOL** — é a tela do IdP estadual (PROCERGS). O SOL não controla nem renderiza esta tela; ela é responsabilidade do SOE.

```
┌──────────────────────────────────────────────────────────┐
│                  [Logo SOE PROCERGS]                     │
│                                                          │
│  ┌──────────┬───────────┬────────────┬──────────────┐   │
│  │Organização│  E-mail  │ Documento  │  Certificado │   │  ← Abas de login
│  └──────────┴───────────┴────────────┴──────────────┘   │
│                                                          │
│  Organização: [ cbm              ▼ ]                    │  ← Campo Organização
│  Usuário:     [                    ]                    │  ← Campo Usuário
│  Senha:       [                    ]                    │  ← Campo Senha
│                                                          │
│               [      Entrar       ]                     │  ← Botão submissão
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Elementos e seus papéis no processo:

#### Abas de seleção de método de login
- **Aba "Organização"** — selecionada por padrão para usuários CBMRS; exige org + usuário + senha
- **Aba "E-mail"** — acesso pelo e-mail Gov.RS (para RT/cidadão)
- **Aba "Documento"** — acesso por CPF (para RT/cidadão)
- **Aba "Certificado"** — acesso por certificado digital A3
- **Papel no BPMN:** Variações da mesma tarefa `T_IdP_001` — *Apresentar formulário de login ao usuário*
- **Regra de negócio:** Cada aba ativa um mecanismo diferente de verificação de identidade no IdP; o resultado (token JWT) é equivalente para todos

#### Campo "Organização"
- **Valor típico:** `cbm` (para bombeiros militares) ou em branco (para cidadãos usando outra aba)
- **Papel no BPMN:** Parâmetro da tarefa `T_IdP_001`; identifica o realm/tenant no SOE PROCERGS
- **Validação:** Feita pelo IdP — organização inválida retorna erro antes mesmo da senha

#### Campo "Usuário"
- **Valor:** Nome de usuário corporativo (para CBMRS) ou identificador pessoal (para cidadãos)
- **Papel no BPMN:** Parâmetro da tarefa `T_IdP_001`

#### Campo "Senha"
- **Tipo:** `input[type=password]` — valor mascarado
- **Papel no BPMN:** Parâmetro da tarefa `T_IdP_001` — credencial secreta
- **Regra de negócio (IdP):** 3 tentativas falhas → bloqueio temporário no IdP (não no SOL)

#### Botão "Entrar"
- **Tarefa BPMN ativada:** `T_IdP_002` — *Validar credenciais e emitir token*
- **O que acontece:**
  1. IdP valida usuário e senha
  2. Se válidos: gera **Access Token (JWT)** + **ID Token** com as claims do usuário (`cpf`, `email`, `name`, `birthdate`)
  3. IdP redireciona de volta para o `redirect_uri` do SOL com o token no fragmento da URL: `https://sol.cbm.rs.gov.br/#access_token=eyJ...`
- **Se credenciais inválidas:** IdP exibe mensagem de erro na própria tela — o fluxo BPMN não avança

#### Gateway BPMN: autenticação no IdP
| Resultado | Condição | Próximo passo |
|---|---|---|
| Sucesso | Credenciais corretas | Redireciona para SOL com token → Passo 5 |
| Falha | Usuário/senha errados | Mensagem de erro no IdP — usuário tenta novamente |
| Bloqueio | 3+ falhas | Conta bloqueada no IdP — fora do controle do SOL |

---

## PASSO 5 — Recebimento do Token (automático)

**Tarefa BPMN:** `T_FE_003` — *Processar callback e armazenar token*
**Raia:** Frontend Angular
**Tela:** URL do SOL com fragmento `#access_token=...` — tela em branco ou spinner por instantes

**O que acontece internamente:**
1. O Angular detecta o fragmento `#access_token=...` na URL
2. `OAuthService` extrai e valida o token JWT
3. Dispara evento `token_received`
4. `AppComponent` responde ao evento chamando `verificaCadastro()`
5. Token armazenado em `localStorage['appToken']` via `AuthStorageService.setItem()`

**Do ponto de vista do usuário:** Tela do portal SOL pisca brevemente enquanto o token é processado. O usuário não precisa fazer nada.

---

## PASSO 6 — Verificação do Cadastro no SOL (automático)

**Tarefa BPMN:** `T_BE_001` — *Consultar usuário por CPF no backend*
**Raia:** Frontend Angular → Backend SOL (Java EE)
**Tela:** Spinner de carregamento (se implementado)

**O que acontece internamente:**
1. Angular extrai o CPF das identity claims do token: `claims['cpf']`
2. Faz requisição ao backend:
   ```
   GET /usuarios?cpf={cpf}
   Authorization: Bearer {access_token}
   ```
3. `HttpAuthorizationInterceptor` injeta automaticamente o header `Authorization` em toda requisição ao backend
4. Backend (`UsuarioRestImpl`) consulta o banco via `UsuarioRN.consultaPorCpf()`
5. Retorna o objeto usuário com o campo `statusCadastro`

**Gateway BPMN `GW_FE_001`:** Ramificação por status de cadastro

---

## PASSO 7 — Desfechos Possíveis (Gateway de Status)

O BPMN possui um **gateway exclusivo** que direciona o fluxo para 4 destinos diferentes com base no `StatusCadastro` retornado pelo backend:

### Desfecho A — Status: INCOMPLETO (ou usuário não encontrado)

**Tarefa BPMN:** `T_FE_010` — *Redirecionar para cadastro*
**Condição:** Backend retorna 404 (não encontrado) ou `StatusCadastro.INCOMPLETO (id=0)`

**O que o usuário vê:** É redirecionado automaticamente para o **início do P02** (Cadastro do RT), sem ver o dashboard do SOL. O processo P01 termina aqui com um evento de ligação ao P02.

**Regra de negócio:** RN-CAD-001 — Usuário autenticado sem cadastro completo não pode acessar licenciamentos.

---

### Desfecho B — Status: ANALISE_PENDENTE ou EM_ANALISE

**Tarefa BPMN:** `T_FE_011` — *Exibir tela de aguardo*
**Condição:** `StatusCadastro.ANALISE_PENDENTE (id=1)` ou `StatusCadastro.EM_ANALISE (id=2)`

**O que o usuário vê:**
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   [Ícone de relógio / análise]                          │
│                                                         │
│   "Seu cadastro está em análise."                       │
│   "Aguarde a aprovação pelo CBM-RS."                    │
│   "Em breve você será informado."                       │
│                                                         │
│                    [ Sair ]                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Identificado no PDF:** Tela P02-04 (pág. 13) exibe a mensagem equivalente: *"Seu cadastro foi enviado para análise, em breve você será informado sobre a sua solicitação de validação."*

**Regra de negócio:** RN-CAD-002 — Acesso às funcionalidades de licenciamento bloqueado até aprovação.

---

### Desfecho C — Status: APROVADO ✅

**Tarefa BPMN:** `T_FE_012` — *Redirecionar para home / dashboard*
**Condição:** `StatusCadastro.APROVADO (id=3)`

**Sub-verificação (antes do redirecionamento):**
O backend compara o e-mail do IdP com o e-mail cadastrado. Se divergirem:
```
PUT /usuarios/{id}    ← atualiza e-mail automaticamente
```
Isso garante que dados de contato fiquem sempre sincronizados com o Gov.RS.

**O que o usuário vê:** Dashboard principal do SOL — tela identificada nos menus do PDF (páginas 56-57):

```
┌─────────────────────────────────────────────────────────┐
│ [Logo SOL]                    [Nome do usuário] [Sair]  │
├──────────────┬──────────────────────────────────────────┤
│              │                                          │
│  Página      │                                          │
│  inicial     │         Área de conteúdo                │
│              │                                          │
│  Consulta    │   ┌──────────┐  ┌──────────┐           │
│  pública     │   │  Iniciar │  │  Meus    │           │
│              │   │licenci-  │  │licenci-  │           │
│  Perguntas   │   │amento    │  │mentos    │           │
│  frequentes  │   └──────────┘  └──────────┘           │
│              │                                          │
│  Meus        │                                          │
│  licencia-   │                                          │
│  mentos      │                                          │
│              │                                          │
│  Troca de    │                                          │
│  envolvidos  │                                          │
└──────────────┴──────────────────────────────────────────┘
```

**Elementos do dashboard e seus papéis:**
| Elemento | Papel no P01 |
|---|---|
| Nome do usuário (navbar superior) | Preenchido com `claims['name']` do token IdP — confirma autenticação bem-sucedida |
| Menu lateral | Construído conforme permissões retornadas por `CidadaoSessionMB.hasPermission()` |
| Botão "Sair" | Aciona `T_FE_013` (Logout) — encerra sessão |
| Opção "Meus licenciamentos" | Rota protegida por `UsuarioAutenticadoGuard` — só acessível após P01 completo |

---

### Desfecho D — Status: REPROVADO

**Tarefa BPMN:** `T_FE_013_alt` — *Exibir tela de reprovação*
**Condição:** `StatusCadastro.REPROVADO (id=4)`

**O que o usuário vê:**
```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   [Ícone de atenção]                                    │
│                                                         │
│   "Seu cadastro foi reprovado."                         │
│   "Entre em contato com o CBM-RS para mais informações."│
│                                                         │
│                    [ Sair ]                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Regra de negócio:** Usuário reprovado não pode reenviar cadastro automaticamente pelo portal — deve entrar em contato com o CBMRS para resolução.

---

## PASSO 8 — Logout

**Tarefa BPMN:** `T_FE_013` — *Encerrar sessão*
**Raia:** Frontend Angular
**Ativado por:** Botão "Sair" em qualquer tela logada

**O que acontece:**
1. `AppComponent.logout()` é chamado
2. `oauthService.logOut()` — invalida sessão no IdP e limpa cookies OIDC
3. `AuthStorageService.clean()` — remove `appToken` do `localStorage`
4. Router redireciona para a tela inicial (Tela P01-01)

**Regra de negócio:** RN-AUTH-004 — O logout é duplo: no IdP (sessão remota) e no localStorage (sessão local), garantindo que um token residual não permita acesso não autorizado.

---

## Diagrama de Sequência — Visão do Usuário × Telas

```
Usuário              Tela P01-01 (PDF p.57)    Tela P01-02 (PDF p.57)    Backend SOL
   │                 Portal SOL                SOE PROCERGS              Java EE REST
   │                      │                         │                        │
   ├─ acessa URL ────────>│                         │                        │
   │                      │── carrega SPA ──────────────────────────────────>│(discovery)
   │<─ Tela P01-01 ───────│                         │                        │
   │                      │                         │                        │
   ├─ clica [Acessar] ───>│                         │                        │
   │                      │── initImplicitFlow() ──>│                        │
   │<─ redireciona ───────│                         │                        │
   │                                                │                        │
   ├─ preenche [Usuário] ──────────────────────────>│                        │
   ├─ preenche [Senha] ─────────────────────────────>│                        │
   ├─ clica [Entrar] ───────────────────────────────>│                        │
   │                                                │── valida credenciais   │
   │<─ redirect com token ──────────────────────────│                        │
   │                                                                         │
   │── token recebido (automático) ─────────────────────────────────────────>│
   │                                                         GET /usuarios?cpf=
   │                                                                         │── consulta BD
   │                                                                         │
   │<─ status do cadastro ───────────────────────────────────────────────────│
   │                                                                         │
   ├─ [INCOMPLETO]  → Tela P02 (cadastro)
   ├─ [PENDENTE]    → Tela "Aguardando análise"
   ├─ [APROVADO]    → Tela Dashboard/Home
   └─ [REPROVADO]   → Tela "Cadastro reprovado"
```

---

## Matriz: Elemento de Tela × Tarefa BPMN × Efeito

| Tela | Elemento | Tarefa BPMN | Efeito no Processo |
|---|---|---|---|
| P01-01 | Botão "Acessar como cidadão" | `T_FE_002` | Inicia fluxo OAuth — redireciona para SOE PROCERGS |
| P01-01 | Link "Acessar como CBMRS" | `T_FE_002` | Idem — perfil interno reconhecido pelo IdP |
| P01-01 | Links públicos (Consulta, Legislação) | — | Fora do P01 — rotas sem autenticação |
| P01-02 | Aba "Organização" | `T_IdP_001` | Define realm de autenticação para usuários CBMRS |
| P01-02 | Aba "E-mail" | `T_IdP_001` | Alternativa para cidadãos com conta Gov.RS |
| P01-02 | Aba "Documento" (CPF) | `T_IdP_001` | Alternativa por CPF |
| P01-02 | Aba "Certificado" | `T_IdP_001` | Autenticação forte por certificado A3 |
| P01-02 | Campo "Organização" | `T_IdP_001` | Parametriza tenant no IdP (ex: "cbm") |
| P01-02 | Campo "Usuário" | `T_IdP_001` | Identifica o usuário no realm |
| P01-02 | Campo "Senha" | `T_IdP_001` | Credencial de autenticação |
| P01-02 | Botão "Entrar" | `T_IdP_002` | Submete credenciais → IdP valida e emite JWT |
| *(redirect)* | URL com `#access_token=` | `T_FE_003` | Angular processa token e dispara verificação |
| *(spinner)* | Loading / processamento | `T_FE_004` / `T_BE_001` | Consulta backend: GET /usuarios?cpf= |
| Dashboard | Nome do usuário (navbar) | `GW_FE_001` → `T_FE_012` | Confirma login completo — claim `name` do JWT |
| Dashboard | Menu lateral | `T_FE_012` | Construído conforme permissões do perfil |
| Dashboard | Botão "Sair" | `T_FE_013` | Encerra sessão no IdP e limpa localStorage |
| Aguardo | Mensagem "Em análise" | `T_FE_011` | StatusCadastro = ANALISE_PENDENTE ou EM_ANALISE |
| Aguardo | Botão "Sair" | `T_FE_013` | Logout (mesmo mecanismo) |

---

## Regras de Negócio Ativadas por Tela

| Tela / Passo | Regra | Descrição |
|---|---|---|
| P01-01 — qualquer botão de acesso | **RN-AUTH-001** | Autenticação obrigatória via OIDC com IdP estadual |
| P01-01 — rotas protegidas | **RN-AUTH-002** | Todas as rotas internas protegidas por `UsuarioAutenticadoGuard` |
| Redirect com token | **RN-AUTH-003** | Token armazenado em `localStorage['appToken']` |
| Gateway de status (Desfecho A) | **RN-CAD-001** | Usuário sem cadastro → redirecionado para P02 |
| Gateway de status (Desfecho B) | **RN-CAD-002** | Cadastro pendente → acesso bloqueado |
| Gateway de status (Desfecho C) | **RN-CAD-003** | E-mail IdP ≠ e-mail SOL → atualiza automaticamente |
| Dashboard — requisições | **RN-PERM-001** | Permissões verificadas por `CidadaoSessionMB.hasPermission()` |
| Botão "Sair" | **RN-AUTH-004** | Logout duplo: IdP + localStorage |

---

## Notas sobre Limitações das Telas no PDF

1. **Tela do IdP (SOE PROCERGS):** A tela mostrada no PDF (p.57) é uma versão simplificada/representativa. A tela real do SOE PROCERGS pode ter layout diferente, mas os elementos funcionais (abas, campos, botão) são os mesmos identificados.

2. **Dashboard pós-login:** O PDF (p.57) mostra o menu lateral do portal RT com itens como "Meus licenciamentos", "Troca de envolvidos", "Solicitação de FACT". Esses itens confirmam o estado de login completo (StatusCadastro.APROVADO), mas o layout exato do dashboard inicial não é detalhado separadamente.

3. **Telas de aguardo/reprovação:** Não aparecem em página específica com layout próprio no PDF. A mensagem de status ANALISE_PENDENTE aparece na tela P02-04 (pág. 13), dentro do contexto de cadastro. Para o roteiro do P01, o comportamento é deduzido pelo `StatusCadastro` enum e pelo código Angular.

4. **Tela de back-office CBMRS:** O fluxo de login para bombeiros internos usa as mesmas telas P01-01 (link "Acessar como CBMRS") e P01-02 (SOE PROCERGS com campo Organização = "cbm"). O dashboard resultante tem itens de menu diferentes (Licenciamento, Central de análise, etc.), visíveis nas páginas 58, 95, 137 do PDF.

---

*Documento gerado em: 2026-03-05*
*Processo: P01 – Autenticação no Sistema SOL/CBM-RS*
*Telas referenciadas: PDF "Apresentação COMPLETA do sistema SOL.pdf" — páginas 56–57*
