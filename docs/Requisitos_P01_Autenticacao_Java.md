# Especificação de Requisitos — P01: Autenticação e Controle de Acesso
## Sistema SOL/CBM-RS — Nova Versão (Stack Java Moderno)

**Versão:** 2.1
**Data:** 2026-03-25 *(atualizado com Hammer Sprints 01–04 + normas RTCBMRS 2024)*
**Destinatário:** Equipe de Desenvolvimento Java
**Processo:** P01 — Autenticação, Autorização e Gerenciamento de Sessão

---

## Índice

1. [Visão Geral e Objetivos](#1-visão-geral-e-objetivos)
2. [Glossário](#2-glossário)
3. [Requisitos Funcionais](#3-requisitos-funcionais)
4. [Requisitos Não Funcionais](#4-requisitos-não-funcionais)
5. [Modelo de Dados](#5-modelo-de-dados)
6. [Contratos de API REST](#6-contratos-de-api-rest)
7. [Regras de Negócio](#7-regras-de-negócio)
8. [Stack Tecnológica Recomendada](#8-stack-tecnológica-recomendada)
9. [Arquitetura de Segurança](#9-arquitetura-de-segurança)
10. [Critérios de Aceitação](#10-critérios-de-aceitação)
11. [Restrições e Premissas](#11-restrições-e-premissas)

---

## 1. Visão Geral e Objetivos

### 1.1 Contexto

O sistema SOL (Sistema de Outorga de Licenciamento) do CBM-RS controla o ciclo completo de licenciamento de segurança contra incêndio para estabelecimentos do Rio Grande do Sul. O processo P01 é o ponto de entrada obrigatório para todos os demais processos: sem autenticação válida, nenhuma operação de licenciamento pode ser realizada.

### 1.2 Objetivo do Processo P01

Prover autenticação segura, delegada a um provedor de identidade externo via protocolo OpenID Connect (OIDC), com as seguintes responsabilidades pós-autenticação:

1. Verificar se o usuário possui cadastro ativo no SOL.
2. Direcionar o usuário ao fluxo correto conforme seu status de cadastro.
3. Emitir token de sessão interno (JWT próprio do SOL) para uso nas demais APIs.
4. Controlar permissões de acesso por perfil (Cidadão, Responsável Técnico, Fiscal, ADM).

### 1.3 Atores do Sistema

| Ator | Identificação | Permissões |
|------|--------------|------------|
| **Cidadão** | CPF autenticado no IdP | Consultas públicas |
| **Responsável Técnico (RT)** | CPF + cadastro APROVADO no SOL | Wizard de licenciamento, acompanhamento de processos |
| **Fiscal CBM** | CPF + perfil FISCAL atribuído por ADM | Análise técnica, emissão de laudos |
| **ADM CBM** | CPF + perfil ADM atribuído por superusuário | Gestão de usuários, distribuição de análises |
| **Superusuário** | Configurado via seed no banco | Atribuição de papéis ADM/FISCAL |

---

## 2. Glossário

| Termo | Definição |
|-------|-----------|
| **OIDC** | OpenID Connect — protocolo de identidade sobre OAuth 2.0 |
| **IdP** | Identity Provider — serviço externo que autentica o usuário (ex.: Gov.BR, Keycloak próprio) |
| **Access Token** | JWT de curta duração que prova a identidade do usuário perante as APIs |
| **Refresh Token** | Token de longa duração usado para obter novos Access Tokens sem novo login |
| **Claims** | Atributos presentes no payload do JWT (cpf, name, email, roles…) |
| **RT** | Responsável Técnico — profissional habilitado que representa o estabelecimento no licenciamento |
| **Status de Cadastro** | Estado do cadastro do usuário no SOL: INCOMPLETO, ANALISE_PENDENTE, EM_ANALISE, APROVADO, REPROVADO |
| **RBAC** | Role-Based Access Control — controle de acesso baseado em papéis |
| **Guard** | Componente (backend ou frontend) que impede acesso a recursos sem autenticação/autorização válida |

---

## 3. Requisitos Funcionais

---

### RF-01 — Autenticação via OpenID Connect (OIDC)

**Prioridade:** Crítica
**Descrição:** O sistema deve autenticar usuários exclusivamente via protocolo OIDC Authorization Code Flow com PKCE, delegando a autenticação a um Identity Provider configurável.

**Detalhamento:**

- O sistema **não deve** armazenar senhas de usuários.
- O Identity Provider deve ser configurável via propriedades de ambiente (não hardcoded).
- O fluxo obrigatório é **Authorization Code Flow com PKCE** (substitui o Implicit Flow da versão atual, que é considerado inseguro pela RFC 9700).
- O sistema deve suportar qualquer IdP compatível com OIDC 1.0 (Keycloak, Gov.BR, Azure AD, Okta, etc.).
- As claims obrigatórias que o IdP deve fornecer são:
  - `sub` — identificador único do usuário no IdP
  - `cpf` — CPF do usuário (11 dígitos, sem pontuação)
  - `name` — Nome completo
  - `email` — Endereço de e-mail

**Critério de Aceitação:** Usuário consegue fazer login usando conta do IdP configurado. O sistema recebe o código de autorização, troca pelo token internamente (não no browser) e inicia sessão.

---

### RF-02 — Emissão de Token de Sessão Interno (JWT Próprio)

**Prioridade:** Crítica
**Descrição:** Após autenticação OIDC bem-sucedida, o backend do SOL deve emitir seu próprio JWT de sessão, independente do token do IdP.

**Motivação:** Desacoplar o sistema do IdP externo. O Access Token do IdP é usado apenas uma vez, na fronteira de entrada. Internamente, o SOL usa seu próprio token com claims específicas do negócio (perfis, permissões, status de cadastro).

**Detalhamento:**

O JWT interno deve conter:
```json
{
  "sub":      "uuid-interno-do-usuario",
  "cpf":      "00000000000",
  "nome":     "Nome Completo",
  "email":    "usuario@email.com",
  "perfis":   ["CIDADAO", "RT"],
  "status":   "APROVADO",
  "iss":      "https://sol.cbm.rs.gov.br",
  "aud":      "sol-api",
  "iat":      1234567890,
  "exp":      1234567890,
  "jti":      "uuid-único-do-token"
}
```

**Parâmetros do JWT interno:**

| Parâmetro | Valor |
|-----------|-------|
| Algoritmo de assinatura | RS256 (chave RSA 2048 bits mínimo) |
| Tempo de expiração (access) | 15 minutos |
| Tempo de expiração (refresh) | 8 horas (ou até logout) |
| Rotação de refresh token | Obrigatória a cada uso (refresh token rotation) |

**Critério de Aceitação:** Backend retorna `access_token` e `refresh_token` após autenticação OIDC. O `access_token` é validado por qualquer microsserviço SOL usando a chave pública.

---

### RF-03 — Verificação de Cadastro Pós-Login

**Prioridade:** Crítica
**Descrição:** Imediatamente após a emissão do token interno, o sistema deve verificar o status do cadastro do usuário e retornar a diretiva de roteamento ao frontend.

**Lógica:**

```
CPF extraído do token IdP
        │
        ▼
Consulta tabela USUARIO por CPF
        │
   ┌────┴──────────────────────────────────────┐
   │ Resultado                                 │
   └─────┬────────┬───────────┬────────────────┘
         │        │           │
       404      INCOMPLETO   ANALISE_PENDENTE
       (não     ou qualquer  EM_ANALISE
     cadastrado) status       │
         │        │           │
         └────────┘     status_code: AGUARDANDO
    status_code:              │
    CADASTRO_INCOMPLETO       ▼
         │              APROVADO
         ▼                    │
    redirecionar         status_code: ATIVO
    para /cadastro            │
                              ▼
                         REPROVADO
                              │
                         status_code: REPROVADO
```

**Response body após autenticação:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 900,
  "usuario": {
    "id": "uuid",
    "nome": "Nome Completo",
    "cpf": "00000000000",
    "email": "email@email.com",
    "perfis": ["RT"],
    "statusCadastro": "APROVADO"
  },
  "diretiva": "HOME"  // HOME | CADASTRO_INCOMPLETO | AGUARDANDO | REPROVADO
}
```

**Critério de Aceitação:** Para cada status de cadastro, o campo `diretiva` retorna o valor correto que o frontend usa para redirecionar sem lógica adicional.

---

### RF-04 — Sincronização Automática de E-mail com IdP

**Prioridade:** Alta
**Descrição:** Se o e-mail nas claims do IdP for diferente do e-mail cadastrado no SOL, o sistema deve atualizá-lo automaticamente durante o login.

**Detalhamento:**

- A sincronização ocorre de forma transparente, sem interação do usuário.
- Deve ser registrada em log de auditoria.
- Apenas o campo e-mail é sincronizado automaticamente — demais dados pessoais requerem ação explícita do usuário.
- Conflito de concorrência (usuário logado simultaneamente em dois devices) deve ser tratado com retry (máximo 3 tentativas com backoff).

**Critério de Aceitação:** Usuário que alterou e-mail no IdP tem o e-mail atualizado automaticamente no próximo login. Log de auditoria registra a alteração com timestamp e origem.

---

### RF-05 — Renovação Transparente de Token (Refresh)

**Prioridade:** Alta
**Descrição:** O frontend deve conseguir renovar o `access_token` sem exigir novo login do usuário, enquanto o `refresh_token` for válido.

**Detalhamento:**

- Endpoint `POST /auth/refresh` aceita o `refresh_token` e retorna novo par de tokens.
- O `refresh_token` usado é imediatamente invalidado (rotation).
- Se o `refresh_token` estiver expirado ou já tiver sido usado, retorna 401 com código `TOKEN_EXPIRADO`.
- O `refresh_token` é armazenado com hash (bcrypt ou SHA-256+salt) no banco — nunca em plaintext.

**Critério de Aceitação:** Sessão de 8 horas sem necessidade de re-login. Após 8 horas de inatividade, próxima requisição retorna 401 e frontend redireciona para login.

---

### RF-06 — Logout

**Prioridade:** Alta
**Descrição:** O logout deve invalidar a sessão tanto no SOL quanto (opcionalmente) no IdP.

**Detalhamento:**

- `POST /auth/logout` invalida o `refresh_token` no banco (inserção em lista de tokens revogados ou deleção do registro).
- O `access_token` não pode ser invalidado por ser stateless — expira naturalmente em 15 minutos. Por isso o tempo de expiração curto é crítico.
- O endpoint deve aceitar o `refresh_token` no body para invalidação explícita.
- Se o IdP suportar `end_session_endpoint` (OIDC RP-Initiated Logout), o backend deve chamar este endpoint para encerrar sessão no IdP também.

**Critério de Aceitação:** Após logout, qualquer uso do `refresh_token` retorna 401. O `access_token` existente expira em no máximo 15 minutos.

---

### RF-07 — Controle de Acesso Baseado em Perfis (RBAC)

**Prioridade:** Crítica
**Descrição:** Cada endpoint da API deve declarar explicitamente quais perfis têm acesso. Requisições sem o perfil adequado devem ser rejeitadas com HTTP 403.

**Perfis do sistema:**

| Perfil | Descrição | Atribuição |
|--------|-----------|------------|
| `CIDADAO` | Acesso apenas a consultas públicas | Automático no 1º login |
| `RT` | Responsável Técnico aprovado | Automático após aprovação do cadastro |
| `FISCAL` | Fiscal do CBM | Atribuído manualmente por ADM |
| `ADM` | Administrador do CBM | Atribuído por superusuário |
| `SUPERUSUARIO` | Administrador do sistema | Seed no banco de dados |

**Matriz de acesso por endpoint (exemplos):**

| Endpoint | CIDADAO | RT | FISCAL | ADM | SUPERUSUARIO |
|----------|---------|----|----|-----|---|
| `GET /consultas/publicas` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `POST /processos` | ✗ | ✓ | ✗ | ✗ | ✓ |
| `PUT /analises/{id}` | ✗ | ✗ | ✓ | ✓ | ✓ |
| `GET /adm/cadastros` | ✗ | ✗ | ✗ | ✓ | ✓ |
| `POST /adm/usuarios/{id}/perfis` | ✗ | ✗ | ✗ | ✗ | ✓ |

**Critério de Aceitação:** Requisição de RT para endpoint exclusivo de ADM retorna 403. Sem token retorna 401.

---

### RF-08 — Proteção Contra Uso Simultâneo de Refresh Token (Token Theft Detection)

**Prioridade:** Alta
**Descrição:** Se um `refresh_token` que já foi rotacionado for usado novamente, o sistema deve detectar possível roubo de token e invalidar toda a família de tokens do usuário.

**Detalhamento:**

- Cada `refresh_token` pertence a uma "família" (identificada por `family_id`).
- Ao rotacionar, novo token recebe o mesmo `family_id`.
- Se um token já rotacionado for apresentado, todos os tokens da família são invalidados.
- O usuário é forçado a fazer novo login completo.
- Evento é registrado em log de segurança com IP de origem.

**Critério de Aceitação:** Tentativa de reusar refresh token já rotacionado invalida toda a família e força re-login.

---

### RF-09 — Registro de Auditoria de Autenticação

**Prioridade:** Alta
**Descrição:** Todos os eventos de autenticação devem ser registrados em tabela de auditoria.

**Eventos a registrar:**

| Evento | Dados registrados |
|--------|-------------------|
| Login bem-sucedido | user_id, ip, user_agent, timestamp, idp_utilizado |
| Falha de autenticação | cpf tentado, ip, user_agent, motivo, timestamp |
| Logout | user_id, ip, timestamp |
| Refresh de token | user_id, ip, timestamp |
| Token theft detectado | user_id, ip, family_id, timestamp |
| Sincronização de e-mail | user_id, email_anterior, email_novo, timestamp |
| Alteração de perfil | user_id, perfil_adicionado/removido, feito_por, timestamp |

**Critério de Aceitação:** Tabela `audit_auth_log` contém registro para cada evento listado. Dados de IP e user-agent são armazenados. Registros são imutáveis (sem UPDATE/DELETE).

---

### RF-10 — Rate Limiting no Endpoint de Login

**Prioridade:** Alta
**Descrição:** O endpoint de callback OIDC e o endpoint de refresh devem ter limitação de taxa para prevenir ataques de força bruta.

**Limites:**

| Endpoint | Limite | Janela | Ação ao exceder |
|----------|--------|--------|-----------------|
| `GET /auth/callback` | 10 req | 1 minuto por IP | HTTP 429 + retry-after header |
| `POST /auth/refresh` | 30 req | 1 minuto por user_id | HTTP 429 |
| `POST /auth/logout` | 10 req | 1 minuto por user_id | HTTP 429 |

---

### RF-11 — Exposição de Chave Pública (JWKS Endpoint)

**Prioridade:** Crítica
**Descrição:** O backend deve expor um endpoint público com as chaves públicas RSA usadas para assinar os tokens internos, permitindo que outros microsserviços e o próprio frontend validem tokens localmente sem consultar o servidor de autenticação a cada requisição.

**Detalhamento:**

```
GET /.well-known/jwks.json

Response 200 OK (sem autenticação):
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "alg": "RS256",
      "kid": "sol-2024-01",       ← key ID para rotação
      "n":   "base64url-modulus",
      "e":   "AQAB"
    }
  ]
}
```

- O campo `kid` (Key ID) deve estar presente em cada JWT emitido no header (`"kid": "sol-2024-01"`).
- Quando houver rotação de chave, ambas as chaves (antiga e nova) devem estar presentes no JWKS durante o período de transição (mínimo 15 minutos — tempo de expiração máximo do access token).
- Resposta deve ter cache de 1 hora (`Cache-Control: public, max-age=3600`).
- O endpoint **não** requer autenticação.

**Critério de Aceitação:** Microsserviço isolado consegue validar um JWT emitido pelo SOL usando apenas a chave pública obtida do endpoint JWKS, sem conhecimento prévio da chave.

---

### RF-12 — Rotação Periódica de Chaves RSA (Key Rotation)

**Prioridade:** Alta
**Descrição:** As chaves RSA usadas para assinar tokens devem poder ser substituídas sem interrupção do serviço ou invalidação de sessões ativas.

**Detalhamento:**

- A rotação deve ser executável via endpoint administrativo ou via troca de variável de ambiente + restart.
- Durante a rotação, tokens assinados com a chave anterior continuam válidos até seu `exp` natural.
- O `kid` no header do JWT indica qual chave validar — o validador consulta o JWKS e seleciona a chave pelo `kid`.
- Frequência de rotação recomendada: a cada 90 dias (configurável).
- Evento de rotação deve ser registrado em log de auditoria.

**Critério de Aceitação:** Após rotação de chave, tokens emitidos antes da rotação (ainda dentro do prazo de expiração) continuam sendo aceitos. Tokens emitidos após a rotação são assinados com a nova chave.

---

### RF-13 — Bloqueio e Desbloqueio de Conta de Usuário

**Prioridade:** Alta
**Descrição:** ADM ou SUPERUSUARIO deve poder bloquear e desbloquear a conta de um usuário. Conta bloqueada não pode autenticar nem usar tokens já emitidos.

**Detalhamento:**

- `PATCH /adm/usuarios/{id}/status` com body `{ "acao": "BLOQUEAR", "motivo": "..." }`.
- Ao bloquear:
  1. O campo `status_conta` do usuário é alterado para `BLOQUEADO`.
  2. **Todos** os refresh tokens ativos do usuário são imediatamente revogados.
  3. Próxima requisição com access token do usuário bloqueado retorna 403 (o backend verifica status no banco — única exceção ao stateless).
  4. Evento registrado em auditoria com motivo e responsável.
- Ao desbloquear: status volta para o anterior ao bloqueio. Usuário precisará fazer novo login.

**Campo adicional na tabela `usuario`:**
```sql
status_conta VARCHAR(20) NOT NULL DEFAULT 'ATIVO'
-- ATIVO | BLOQUEADO
bloqueado_por    UUID REFERENCES usuario(id)
bloqueado_em     TIMESTAMPTZ
motivo_bloqueio  TEXT
```

**Critério de Aceitação:** Usuário bloqueado que tenta usar seu access token (ainda não expirado) recebe 403 com `"erro": "CONTA_BLOQUEADA"`. Após desbloqueio e novo login, acesso é restaurado normalmente.

---

### RF-14 — Validação de CPF

**Prioridade:** Alta
**Descrição:** O CPF recebido nas claims do IdP deve ser validado quanto ao formato e dígitos verificadores antes de qualquer operação no banco.

**Detalhamento:**

- Algoritmo de validação: módulo 11 (padrão da Receita Federal).
- CPF deve conter exatamente 11 dígitos numéricos (sem pontos, traços ou espaços).
- CPFs com todos os dígitos iguais (ex.: `00000000000`, `11111111111`) são inválidos.
- Se o CPF das claims for inválido, o login é rejeitado com HTTP 400 e evento registrado em auditoria.
- A validação é executada no método `AuthService.validarCpf(String cpf)`.

**Critério de Aceitação:** Tentativa de login com CPF `12345678900` (dígitos verificadores inválidos) retorna 400 com `"erro": "CPF_INVALIDO"`. CPF `00000000000` também retorna 400.

---

### RF-15 — Gerenciamento de Sessões Simultâneas

**Prioridade:** Média
**Descrição:** O sistema deve controlar e limitar o número de sessões simultâneas ativas por usuário.

**Detalhamento:**

- Limite padrão: **3 sessões simultâneas** por usuário (configurável por perfil).
- Uma sessão = um `family_id` de refresh token ativo.
- Quando o limite é atingido e o usuário faz novo login, a sessão mais antiga é automaticamente revogada (política FIFO).
- Alternativamente (configurável): rejeitar novo login com 409 e mensagem orientando o usuário a encerrar uma sessão existente.
- O endpoint `GET /auth/sessoes` (autenticado) lista as sessões ativas do usuário logado com: device (user-agent resumido), IP, data de criação.
- O endpoint `DELETE /auth/sessoes/{sessionId}` permite encerrar uma sessão específica remotamente.

**Critério de Aceitação:** Usuário com 3 sessões ativas ao fazer 4º login tem a sessão mais antiga encerrada automaticamente (ou recebe 409, conforme configuração). `GET /auth/sessoes` retorna apenas as sessões efetivamente ativas.

---

### RF-16 — Revogação em Massa de Tokens por Usuário

**Prioridade:** Alta
**Descrição:** Qualquer evento que comprometa a segurança de um usuário deve poder invalidar todas as suas sessões ativas imediatamente, independente do número de tokens ativos.

**Casos que disparam revogação em massa:**

| Gatilho | Responsável |
|---------|------------|
| Bloqueio de conta (RF-13) | ADM |
| Token theft detectado (RF-08) | Sistema automático |
| Solicitação explícita do usuário ("sair de todos os dispositivos") | Próprio usuário |
| Alteração de perfil crítica (ex.: remoção de perfil RT ou ADM) | ADM |

**Endpoint para "sair de todos os dispositivos":**
```
DELETE /auth/sessoes
Authorization: Bearer {access_token}

Response 204 No Content
```

**Critério de Aceitação:** Após revogação em massa, todas as tentativas de uso de refresh tokens do usuário retornam 401. O access token ainda válido expira naturalmente em até 15 minutos.

---

### RF-17 — Verificação de Status do Cadastro em Cada Renovação de Token

**Prioridade:** Alta
**Descrição:** No momento da renovação do access token via refresh, o sistema deve re-verificar o status atual do cadastro e dos perfis do usuário, garantindo que alterações administrativas (ex.: reprovação, bloqueio, alteração de perfil) reflitam imediatamente no próximo token emitido.

**Detalhamento:**

- A cada chamada ao `POST /auth/refresh`, o sistema consulta o banco para obter o status atual do usuário.
- O novo access token reflete o estado **atual** do usuário, não o estado no momento do login.
- Se o usuário foi bloqueado, o refresh retorna 403 em vez de novo token.
- Se o usuário foi reprovado, o refresh retorna novo token com diretiva `REPROVADO`.
- Se o perfil RT foi removido, o novo token não terá mais a role `RT`.

**Critério de Aceitação:** Usuário logado como RT que tem seu cadastro reprovado por um ADM obtém, na próxima chamada de refresh, um token sem a role RT e com `"statusCadastro": "REPROVADO"`.

---

### RF-18 — Configuração de CORS (Cross-Origin Resource Sharing)

**Prioridade:** Alta
**Descrição:** O backend deve configurar CORS de forma restritiva, permitindo apenas origens explicitamente autorizadas.

**Detalhamento:**

- Lista de origens permitidas configurável via variável de ambiente (`CORS_ALLOWED_ORIGINS`).
- Em desenvolvimento: `http://localhost:4200` (Angular dev server) permitido.
- Em produção: apenas o domínio oficial do sistema.
- Métodos permitidos: `GET, POST, PUT, PATCH, DELETE, OPTIONS`.
- Headers permitidos: `Authorization, Content-Type, X-Request-ID`.
- `credentials: true` habilitado para suporte a cookies de refresh token.
- Preflight (`OPTIONS`) deve retornar 200 com os headers corretos sem autenticação.

```yaml
# application.yml
sol:
  cors:
    allowed-origins: ${CORS_ALLOWED_ORIGINS:http://localhost:4200}
    max-age: 3600
```

**Critério de Aceitação:** Requisição de origem não autorizada recebe 403. Preflight de origem autorizada recebe 200 com headers `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`.

---

### RF-19 — Notificação por E-mail em Eventos Críticos de Segurança

**Prioridade:** Média
**Descrição:** O usuário deve ser notificado por e-mail quando eventos críticos de segurança ocorrem em sua conta.

**Eventos que disparam notificação:**

| Evento | Destinatário | Template |
|--------|-------------|---------|
| Login em novo IP/dispositivo | Usuário | "Detectamos acesso à sua conta de um novo dispositivo em {data} às {hora}. Se não foi você, acesse o sistema e encerre as sessões." |
| Token theft detectado (sessão invalidada) | Usuário | "Sua sessão foi encerrada por motivo de segurança. Faça login novamente." |
| Conta bloqueada | Usuário | "Sua conta foi bloqueada por {motivo}. Entre em contato com o CBM-RS." |
| Alteração de perfil | Usuário | "Seu perfil no sistema SOL foi atualizado: {perfil} {adicionado/removido}." |

**Implementação:**
- Envio assíncrono via fila de mensagens (ex.: RabbitMQ, SQS) — nunca bloqueia o fluxo principal.
- Template de e-mail configurável (HTML + texto puro).
- Serviço de e-mail configurável: SMTP genérico (`spring.mail.*`).
- Falha no envio de e-mail **não deve** bloquear o login ou logout do usuário.

**Critério de Aceitação:** Usuário recebe e-mail em até 60 segundos após o evento. Falha no serviço de e-mail é logada mas não interrompe a operação de autenticação.

---

### RF-20 — Endpoint de Introspection de Token (para Microsserviços Internos)

**Prioridade:** Média
**Descrição:** Outros microsserviços do ecossistema SOL que não possuam a chave pública localmente devem poder validar um token via endpoint de introspection.

**Detalhamento:**

```
POST /auth/introspect
Authorization: Basic {client_id:client_secret}   ← autenticação do microsserviço
Content-Type: application/x-www-form-urlencoded

token=eyJ...

Response 200 OK (token válido):
{
  "active":    true,
  "sub":       "uuid-usuario",
  "cpf":       "00000000000",
  "perfis":    ["RT"],
  "exp":       1234567890,
  "iss":       "https://sol.cbm.rs.gov.br"
}

Response 200 OK (token inválido ou expirado):
{
  "active": false
}
```

- Acesso ao endpoint restrito a `client_id` cadastrados na tabela `oauth_client`.
- Este endpoint é para uso exclusivo de microsserviços internos — nunca exposto publicamente.
- Preferir validação local via JWKS (RF-11); introspection é fallback para serviços que não conseguem implementar validação local.

**Critério de Aceitação:** Microsserviço com `client_id` válido recebe `active: true` para token válido e `active: false` para token expirado ou revogado. Microsserviço sem `client_id` recebe 401.

---

### RF-21 — Suporte a Múltiplos Identity Providers

**Prioridade:** Média
**Descrição:** O sistema deve suportar configuração de múltiplos IdPs simultaneamente, permitindo migração gradual ou atendimento a diferentes contextos de autenticação.

**Caso de uso:** Durante a transição do atual `meu.rs.gov.br` para o Gov.BR federal, ambos os IdPs devem funcionar em paralelo.

**Detalhamento:**

- Cada IdP é identificado por um `provider_id` (ex.: `govbr`, `keycloak-cbm`).
- O endpoint de login aceita parâmetro opcional: `GET /auth/login?provider=govbr`.
- Se não especificado, usa o IdP padrão configurado em `sol.auth.default-provider`.
- A tabela `usuario` armazena o `idp_sub` e o `idp_provider` para evitar colisões entre usuários de IdPs diferentes com o mesmo `sub`.
- O CPF permanece como identificador único — dois IdPs com o mesmo CPF são tratados como o mesmo usuário.

```sql
ALTER TABLE usuario ADD COLUMN idp_provider VARCHAR(50) DEFAULT 'govbr';
```

```yaml
sol:
  auth:
    default-provider: govbr
    providers:
      govbr:
        issuer-uri: ${GOVBR_ISSUER_URI}
        client-id:  ${GOVBR_CLIENT_ID}
      keycloak-cbm:
        issuer-uri: ${KEYCLOAK_ISSUER_URI}
        client-id:  ${KEYCLOAK_CLIENT_ID}
```

**Critério de Aceitação:** Usuário que se autentica via Gov.BR e usuário que se autentica via Keycloak CBM com o mesmo CPF acessam o mesmo registro de usuário no SOL.

---

### RF-22 — Expiração de Sessão por Inatividade (Sliding Window)

**Prioridade:** Média
**Descrição:** Além do tempo máximo de 8 horas (RF-05), o refresh token deve expirar após um período configurável de inatividade.

**Detalhamento:**

- Inatividade = nenhum uso do refresh token no período definido.
- Período padrão de inatividade: **2 horas** (configurável por perfil).
- A cada uso bem-sucedido do refresh token, o `expires_at` do novo token é recalculado: `NOW() + inactivity_timeout`.
- O `expires_at` nunca pode ultrapassar a data máxima de expiração da sessão (`session_created_at + max_session_duration`).

```
Exemplo:
  Sessão criada às 08:00. Max duração = 8h → expira às 16:00.
  Último uso do refresh às 13:00.
  Próximo refresh disponível até: min(13:00 + 2h = 15:00, 16:00) = 15:00.
  Se usuário não usar até 15:00 → sessão encerra por inatividade.
```

**Critério de Aceitação:** Usuário que deixa o sistema ocioso por mais de 2 horas tem seu refresh token expirado. Próxima tentativa de refresh retorna 401 com `"erro": "SESSAO_INATIVA"`.

---

### RF-23 — Conformidade com LGPD (Lei Geral de Proteção de Dados)

**Prioridade:** Alta
**Descrição:** O módulo de autenticação deve estar em conformidade com a LGPD (Lei 13.709/2018) no que diz respeito ao tratamento de dados pessoais de identificação.

**Detalhamento:**

**a) Direito ao Esquecimento (Art. 18, IV):**
- Endpoint `DELETE /usuarios/{id}` disponível para o próprio usuário ou ADM.
- O cadastro não é deletado fisicamente — é anonimizado (CPF, nome, e-mail substituídos por hash irreversível).
- Histórico de licenciamentos associado ao usuário deve ser preservado (requisito legal de guarda de documentos públicos) — apenas os dados pessoais são anonimizados.
- Todos os refresh tokens e sessões são revogados imediatamente.

**b) Direito de Acesso (Art. 18, I):**
- Endpoint `GET /usuarios/me/dados-pessoais` retorna todos os dados pessoais armazenados sobre o usuário logado, incluindo logs de auditoria que o referenciam.

**c) Portabilidade (Art. 18, V):**
- Endpoint `GET /usuarios/me/exportar` retorna os dados do usuário em formato JSON estruturado, disponível para download.

**d) Minimização de Dados:**
- O sistema armazena apenas os campos estritamente necessários para o processo de licenciamento.
- Logs de auditoria não armazenam tokens ou senhas — apenas IDs, IPs e eventos.

**e) Consentimento:**
- No primeiro login (criação de cadastro), o usuário deve aceitar explicitamente os Termos de Uso e a Política de Privacidade.
- Data e versão dos termos aceitos devem ser armazenadas.

```sql
ALTER TABLE usuario ADD COLUMN termos_aceitos_em   TIMESTAMPTZ;
ALTER TABLE usuario ADD COLUMN termos_versao        VARCHAR(20);
ALTER TABLE usuario ADD COLUMN anonimizado          BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE usuario ADD COLUMN anonimizado_em       TIMESTAMPTZ;
```

**Critério de Aceitação:** Usuário anonimizado não aparece em buscas por nome ou e-mail. CPF original não é recuperável após anonimização. Dados de licenciamento associados são preservados sem referência ao usuário identificado.

---

### RF-24 — Endpoint de Health Check de Autenticação

**Prioridade:** Alta
**Descrição:** O módulo de autenticação deve expor endpoints de saúde para uso por load balancers, sistemas de monitoramento e pipelines de CI/CD.

**Endpoints:**

```
GET /actuator/health
Response 200 (sistema saudável):
{
  "status": "UP",
  "components": {
    "db":    { "status": "UP" },
    "redis": { "status": "UP" },
    "idp":   { "status": "UP" }    ← verifica conectividade com IdP (JWKS endpoint)
  }
}

Response 503 (sistema degradado):
{
  "status": "DOWN",
  "components": {
    "db":    { "status": "DOWN", "details": { "error": "Connection refused" } },
    "redis": { "status": "UP" },
    "idp":   { "status": "UP" }
  }
}

GET /actuator/health/liveness    ← para Kubernetes liveness probe
GET /actuator/health/readiness   ← para Kubernetes readiness probe
```

**Critério de Aceitação:** Load balancer remove instância do pool quando `/actuator/health/readiness` retorna 503. Kubernetes reinicia pod quando `/actuator/health/liveness` retorna 503.

---

### RF-25 — Aceitação de Termos de Uso no Primeiro Acesso

**Prioridade:** Alta
**Descrição:** Na primeira autenticação de um usuário (CPF ainda não cadastrado no SOL), o sistema deve exigir a aceitação explícita dos Termos de Uso e da Política de Privacidade antes de criar o cadastro.

**Detalhamento:**

- Fluxo: Login no IdP → CPF não encontrado no SOL → retorna `diretiva: ACEITAR_TERMOS` → frontend exibe tela de termos → usuário aceita → `POST /auth/aceitar-termos` → cadastro criado → `diretiva: CADASTRO_INCOMPLETO`.
- O endpoint `POST /auth/aceitar-termos` recebe um token temporário emitido para esta etapa específica (não é o access token completo).
- Se o usuário fechar a tela sem aceitar, o cadastro **não** é criado.
- A versão dos termos aceitos é gravada no banco.

**Endpoints:**
```
GET /auth/termos-vigentes
Response 200:
{
  "versao":     "2024.1",
  "vigente_desde": "2024-01-01",
  "url_termos":  "https://sol.cbm.rs.gov.br/termos/2024.1.pdf",
  "url_privacidade": "https://sol.cbm.rs.gov.br/privacidade/2024.1.pdf"
}

POST /auth/aceitar-termos
Authorization: Bearer {temp_token}
{
  "versao_termos": "2024.1",
  "aceito":        true
}

Response 200:
{
  "access_token": "eyJ...",   ← token completo agora emitido
  "refresh_token": "eyJ...",
  "diretiva": "CADASTRO_INCOMPLETO"
}
```

**Critério de Aceitação:** Usuário que tenta pular a aceitação de termos (chamando endpoints protegidos com o `temp_token`) recebe 403. Apenas após `POST /auth/aceitar-termos` com `"aceito": true` o token completo é emitido.

---

## 4. Requisitos Não Funcionais

---

### RNF-01 — Desempenho

| Métrica | Valor alvo |
|---------|-----------|
| Tempo de resposta do endpoint de login (P95) | < 500ms |
| Tempo de resposta do endpoint de refresh (P95) | < 100ms |
| Tempo de resposta da validação de token (por requisição) | < 5ms (validação local, sem chamada de rede) |
| Usuários simultâneos suportados | 500 |

### RNF-02 — Segurança

- Tokens JWT assinados com RS256 (assimétrico) — chave privada nunca exposta.
- Chaves privadas armazenadas via variável de ambiente ou cofre de secrets (HashiCorp Vault, AWS Secrets Manager, etc.) — **nunca no código ou no repositório git**.
- Comunicação obrigatoriamente via HTTPS/TLS 1.2+ em todos os ambientes, incluindo desenvolvimento.
- Headers de segurança obrigatórios em todas as respostas:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Content-Security-Policy: default-src 'self'`
- Refresh tokens armazenados com hash SHA-256 no banco — nunca em plaintext.
- Logs não devem conter tokens, senhas ou dados sensíveis.

### RNF-03 — Disponibilidade

- Disponibilidade mínima: 99,5% no horário comercial (07h–19h dias úteis).
- O sistema deve ser stateless para permitir múltiplas instâncias sem compartilhamento de estado.
- Cache de chaves públicas do IdP (`JWKS`) deve ter TTL de 1 hora para reduzir dependência de rede.

### RNF-04 — Manutenibilidade

- Cobertura mínima de testes: 80% nas classes de segurança (`auth`, `security`).
- Testes de integração para todos os endpoints de autenticação.
- O IdP deve ser configurável sem recompilação (via `application.properties` / variáveis de ambiente).
- Código deve seguir princípio de responsabilidade única — classes de autenticação não devem conter regras de negócio de licenciamento.

### RNF-05 — Observabilidade

- Métricas expostas via endpoint `/actuator/metrics` (Spring Boot Actuator + Micrometer).
- Tracing distribuído com correlation ID (`X-Request-ID`) propagado em todos os logs e respostas.
- Logs estruturados em formato JSON (Logback + logstash-logback-encoder) com campos: `timestamp`, `level`, `traceId`, `spanId`, `userId`, `evento`, `ip`.
- Alertas obrigatórios:
  - Taxa de erro > 1% em endpoints de auth nos últimos 5 minutos.
  - Latência P99 > 2s em qualquer endpoint de auth.
  - Evento `TOKEN_THEFT` detectado (alerta imediato, sem agregação).
  - Falha de conectividade com IdP por mais de 30 segundos.
- Dashboard de métricas de autenticação deve incluir: logins/minuto, taxa de sucesso, sessões ativas, refresh/minuto, eventos de segurança.

### RNF-06 — Escalabilidade e Statelessness

- O serviço de autenticação deve ser **completamente stateless** entre instâncias. Nenhum dado de sessão deve residir em memória da instância.
- Estado compartilhado (refresh tokens, rate limiting, cache de JWKS) deve residir exclusivamente no Redis.
- O sistema deve escalar horizontalmente sem configuração adicional — adicionar instâncias não requer coordenação.
- Teste de carga mínimo: 500 usuários simultâneos fazendo login sem degradação de latência acima de 50%.

### RNF-07 — Conformidade com Padrões e Normas

| Padrão/Norma | Obrigatoriedade |
|---|---|
| RFC 6749 — OAuth 2.0 | Obrigatório |
| RFC 7636 — PKCE | Obrigatório |
| RFC 7519 — JWT | Obrigatório |
| RFC 7517 — JWK | Obrigatório |
| RFC 7662 — Token Introspection | Obrigatório (RF-20) |
| RFC 7009 — Token Revocation | Obrigatório |
| RFC 8414 — OAuth Server Metadata | Recomendado |
| OpenID Connect Core 1.0 | Obrigatório |
| OWASP Top 10 (2021) | Obrigatório — zero issues críticos ou altos |
| LGPD — Lei 13.709/2018 | Obrigatório (RF-23) |
| WCAG 2.1 nível AA | Recomendado (acessibilidade do frontend de login) |

### RNF-08 — Estratégia de Testes

| Tipo de Teste | Cobertura mínima | Ferramenta |
|---|---|---|
| Testes unitários (classes auth) | 80% | JUnit 5 + Mockito |
| Testes de integração (endpoints) | 100% dos endpoints listados no RF | Spring Boot Test + TestContainers |
| Testes de segurança estáticos (SAST) | Zero issues críticos/altos | SonarQube ou SpotBugs |
| Testes de penetração | Pelo menos 1 ciclo antes do go-live | OWASP ZAP ou profissional externo |
| Testes de carga | 500 usuários simultâneos por 10 minutos | k6 ou Gatling |

Exemplos de cenários de teste de integração obrigatórios:

```java
// Cenários mínimos para AuthController
@Test void loginComTokenValido_deveRetornarAccessToken()
@Test void loginComEstadoInvalido_deveRetornar400()
@Test void refreshComTokenValido_deveRotacionarToken()
@Test void refreshComTokenRevogado_deveRetornar401()
@Test void refreshComTokenReutilizado_deveRevogarFamilia()
@Test void logoutDeveInvalidarRefreshToken()
@Test void acessoSemToken_deveRetornar401()
@Test void acessoComPerfilInsuficiente_deveRetornar403()
@Test void usuarioBloqueado_deveRetornar403NoRefresh()
@Test void cpfInvalido_deveRetornar400()
@Test void limiteSessoesSimultaneas_deveRevogarMaisAntiga()
```

### RNF-09 — Retenção e Backup de Logs de Auditoria

- Logs da tabela `audit_auth_log` devem ser retidos por **5 anos** (requisito legal para sistemas públicos).
- Após 90 dias, registros podem ser movidos para armazenamento frio (ex.: tabela particionada por mês ou exportação para object storage).
- Backup diário do banco com retenção de 30 dias.
- O processo de backup deve incluir verificação de integridade (checksum).
- Acesso à tabela `audit_auth_log` deve ser restrito ao sistema — nenhum usuário humano pode executar DELETE ou UPDATE diretamente (via roles de banco).

```sql
-- Garantir imutabilidade no nível do banco:
REVOKE DELETE, UPDATE ON audit_auth_log FROM PUBLIC;
REVOKE DELETE, UPDATE ON audit_auth_log FROM sol_app_user;
-- Apenas INSERT e SELECT permitidos para o usuário da aplicação
```

### RNF-10 — Portabilidade e Independência de Infraestrutura

- O sistema deve ser executável em qualquer ambiente via Docker/OCI container.
- `Dockerfile` e `docker-compose.yml` devem ser fornecidos para ambiente de desenvolvimento local (Spring Boot + PostgreSQL + Redis).
- Variáveis de ambiente devem cobrir 100% das configurações sensíveis — zero segredos no repositório.
- A aplicação deve iniciar em menos de 30 segundos em hardware padrão (2 vCPU, 2GB RAM).
- Compatível com deploy em Kubernetes (manifestos `k8s/` devem ser fornecidos com Deployment, Service, ConfigMap, Secret, HPA).

---

## 5. Modelo de Dados

### 5.1 Entidade `usuario`

```sql
CREATE TABLE usuario (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cpf               CHAR(11)     NOT NULL UNIQUE,
    nome              VARCHAR(200) NOT NULL,
    email             VARCHAR(200) NOT NULL,
    email_verificado  BOOLEAN      NOT NULL DEFAULT FALSE,
    status_cadastro   VARCHAR(30)  NOT NULL DEFAULT 'INCOMPLETO',
    -- INCOMPLETO | ANALISE_PENDENTE | EM_ANALISE | APROVADO | REPROVADO
    motivo_reprovacao TEXT,
    idp_sub           VARCHAR(200),          -- 'sub' do IdP (para vincular conta)
    criado_em         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    atualizado_em     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    versao            BIGINT       NOT NULL DEFAULT 0  -- controle de concorrência otimista
);

-- Índices
CREATE INDEX idx_usuario_cpf     ON usuario(cpf);
CREATE INDEX idx_usuario_status  ON usuario(status_cadastro);
CREATE INDEX idx_usuario_idp_sub ON usuario(idp_sub);
```

### 5.2 Entidade `usuario_perfil`

```sql
CREATE TABLE usuario_perfil (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id    UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    perfil        VARCHAR(30)  NOT NULL,
    -- CIDADAO | RT | FISCAL | ADM | SUPERUSUARIO
    atribuido_por UUID         REFERENCES usuario(id),
    atribuido_em  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    ativo         BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_usuario_perfil UNIQUE (usuario_id, perfil)
);
```

### 5.3 Entidade `refresh_token`

```sql
CREATE TABLE refresh_token (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id    UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    token_hash    CHAR(64)     NOT NULL UNIQUE, -- SHA-256 hex do token
    family_id     UUID         NOT NULL,         -- agrupa família para token theft detection
    usado         BOOLEAN      NOT NULL DEFAULT FALSE,
    ip_origem     INET,
    user_agent    TEXT,
    criado_em     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expira_em     TIMESTAMPTZ  NOT NULL,
    revogado_em   TIMESTAMPTZ
);

CREATE INDEX idx_refresh_token_hash      ON refresh_token(token_hash);
CREATE INDEX idx_refresh_token_family    ON refresh_token(family_id);
CREATE INDEX idx_refresh_token_usuario   ON refresh_token(usuario_id);
CREATE INDEX idx_refresh_token_expira_em ON refresh_token(expira_em);
```

### 5.4 Entidade `audit_auth_log`

```sql
CREATE TABLE audit_auth_log (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id  UUID         REFERENCES usuario(id),
    evento      VARCHAR(50)  NOT NULL,
    -- LOGIN_OK | LOGIN_FALHA | LOGOUT | TOKEN_REFRESH | TOKEN_THEFT
    -- EMAIL_SYNC | PERFIL_ALTERADO | TOKEN_EXPIRADO
    ip_origem   INET,
    user_agent  TEXT,
    detalhe     JSONB,       -- dados adicionais do evento
    criado_em   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- Tabela append-only — sem UPDATE/DELETE permitido
CREATE INDEX idx_audit_auth_log_usuario  ON audit_auth_log(usuario_id);
CREATE INDEX idx_audit_auth_log_evento   ON audit_auth_log(evento);
CREATE INDEX idx_audit_auth_log_criado   ON audit_auth_log(criado_em DESC);
```

### 5.5 Diagrama Entidade-Relacionamento (texto)

```
usuario (1) ──── (N) usuario_perfil
usuario (1) ──── (N) refresh_token
usuario (1) ──── (N) audit_auth_log
```

---

## 6. Contratos de API REST

Base URL: `/api/v1`

---

### 6.1 Iniciar Login — Redireciona para IdP

```
GET /auth/login?redirect_uri={uri_final_pos_login}

Response: 302 Found
Location: https://idp.exemplo.com/oauth/authorize
          ?client_id=...
          &redirect_uri=https://sol.cbm.rs.gov.br/api/v1/auth/callback
          &response_type=code
          &scope=openid+cpf+email+name
          &state={state_opaco_csrf}
          &code_challenge={pkce_challenge}
          &code_challenge_method=S256
```

**Notas:**
- `state` deve ser gerado aleatoriamente e armazenado em cookie HttpOnly para validação CSRF.
- `code_challenge` é o hash SHA-256 do `code_verifier` (PKCE).

---

### 6.2 Callback OIDC — Troca Código por Tokens

```
GET /auth/callback?code={authorization_code}&state={state}

Processamento interno:
  1. Valida state contra o cookie
  2. POST para IdP: troca code por tokens (usando code_verifier)
  3. Valida id_token (assinatura, iss, aud, exp, nonce)
  4. Extrai CPF das claims
  5. Consulta/cria usuário no banco
  6. Emite JWT interno
  7. Redireciona para o frontend com tokens

Response: 302 Found
Location: {redirect_uri_original}#access_token=eyJ...&refresh_token=eyJ...
```

**Alternativa (recomendada para SPAs modernas):**
```
Response: 200 OK
Set-Cookie: refresh_token=eyJ...; HttpOnly; Secure; SameSite=Strict; Path=/auth/refresh
Content-Type: application/json

{
  "access_token": "eyJ...",
  "token_type":   "Bearer",
  "expires_in":   900,
  "usuario": {
    "id":              "550e8400-e29b-41d4-a716-446655440000",
    "nome":            "João da Silva",
    "cpf":             "00000000000",
    "email":           "joao@email.com",
    "perfis":          ["CIDADAO", "RT"],
    "statusCadastro":  "APROVADO"
  },
  "diretiva": "HOME"
}
```

**Valores do campo `diretiva`:**

| Valor | Condição | Ação esperada do frontend |
|-------|----------|--------------------------|
| `HOME` | Status APROVADO | Redirecionar para dashboard |
| `CADASTRO_INCOMPLETO` | Não cadastrado ou INCOMPLETO | Redirecionar para `/cadastro` |
| `AGUARDANDO_ANALISE` | ANALISE_PENDENTE ou EM_ANALISE | Exibir tela de aguardo |
| `REPROVADO` | REPROVADO | Exibir tela de reprovação com motivo |

---

### 6.3 Renovação de Token

```
POST /auth/refresh
Content-Type: application/json

{
  "refresh_token": "eyJ..."    // ou via cookie HttpOnly (preferencial)
}

Response 200 OK:
{
  "access_token":  "eyJ...",
  "refresh_token": "eyJ...",   // novo token — o anterior foi invalidado
  "token_type":    "Bearer",
  "expires_in":    900
}

Response 401 Unauthorized (token inválido/expirado):
{
  "erro":     "TOKEN_INVALIDO",
  "mensagem": "Refresh token inválido ou expirado. Faça login novamente."
}

Response 401 Unauthorized (token theft detectado):
{
  "erro":     "SESSAO_COMPROMETIDA",
  "mensagem": "Sessão inválida por motivo de segurança. Faça login novamente."
}
```

---

### 6.4 Logout

```
POST /auth/logout
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "refresh_token": "eyJ..."   // ou via cookie
}

Response 204 No Content
```

---

### 6.5 Informações do Usuário Logado

```
GET /auth/me
Authorization: Bearer {access_token}

Response 200 OK:
{
  "id":             "550e8400-...",
  "nome":           "João da Silva",
  "cpf":            "00000000000",
  "email":          "joao@email.com",
  "perfis":         ["CIDADAO", "RT"],
  "statusCadastro": "APROVADO",
  "criadoEm":       "2024-01-15T10:30:00Z",
  "atualizadoEm":   "2024-01-20T14:00:00Z"
}

Response 401 Unauthorized (token inválido ou expirado):
{
  "erro":     "NAO_AUTENTICADO",
  "mensagem": "Token inválido ou expirado."
}
```

---

### 6.6 Atribuição de Perfil (exclusivo SUPERUSUARIO / ADM)

```
POST /adm/usuarios/{usuarioId}/perfis
Authorization: Bearer {access_token_superusuario}
Content-Type: application/json

{
  "perfil": "FISCAL"
}

Response 200 OK:
{
  "usuarioId": "550e8400-...",
  "perfil":    "FISCAL",
  "ativo":     true,
  "atribuidoEm": "2024-01-20T14:00:00Z"
}

Response 403 Forbidden:
{
  "erro":     "SEM_PERMISSAO",
  "mensagem": "Apenas SUPERUSUARIO ou ADM podem atribuir perfis."
}
```

---

### 6.7 Padrão de Erro

Todos os erros seguem o formato RFC 7807 (Problem Details):

```json
{
  "type":      "https://sol.cbm.rs.gov.br/erros/token-invalido",
  "title":     "Token Inválido",
  "status":    401,
  "detail":    "O access token fornecido está expirado.",
  "instance":  "/api/v1/processos/123",
  "timestamp": "2024-01-20T14:00:00Z",
  "traceId":   "abc123def456"
}
```

---

## 7. Regras de Negócio

| ID | Regra | Detalhamento |
|----|-------|-------------|
| **RN-01** | Autenticação apenas via IdP externo | O sistema nunca armazena senha. Toda autenticação passa pelo IdP configurado. |
| **RN-02** | Rotas internas exigem JWT interno válido | Qualquer endpoint sob `/api/v1` (exceto `/auth/*` e `/publico/*`) exige `Authorization: Bearer {jwt_interno}`. |
| **RN-03** | CPF é o identificador primário | O CPF extraído das claims do IdP é o vínculo entre a identidade do IdP e o cadastro SOL. Não pode ser alterado após criação. |
| **RN-04** | Usuário sem cadastro recebe perfil CIDADAO automaticamente | No primeiro login, se não houver cadastro, o usuário é criado com status INCOMPLETO e perfil CIDADAO. |
| **RN-05** | RT só é ativado após aprovação administrativa | O perfil RT é concedido automaticamente quando o status do cadastro transita para APROVADO (processo P02). |
| **RN-06** | Perfis FISCAL e ADM são exclusivamente de atribuição manual | Apenas SUPERUSUARIO ou ADM podem conceder os perfis FISCAL e ADM. |
| **RN-07** | E-mail sincronizado automaticamente no login | Se o e-mail das claims do IdP diferir do cadastrado, o sistema atualiza silenciosamente e registra em auditoria. |
| **RN-08** | Refresh token é de uso único | Cada uso do refresh token gera um novo refresh token e invalida o anterior. |
| **RN-09** | Reutilização de refresh token revogado invalida toda a família | Indica possível roubo de token. Todos os tokens da família são imediatamente revogados. |
| **RN-10** | Access token expira em 15 minutos | Limita o tempo de exposição em caso de interceptação. |
| **RN-11** | Sessão máxima de 8 horas por refresh token | Após 8 horas, usuário deve se autenticar novamente no IdP. |
| **RN-12** | Logs de auditoria são imutáveis | Registros de auditoria não podem ser alterados ou excluídos por nenhuma interface do sistema. |
| **RN-13** | PKCE obrigatório | O fluxo Authorization Code deve usar PKCE (RFC 7636) para prevenir ataques de interception. |
| **RN-14** | State obrigatório para CSRF | O parâmetro `state` deve ser validado no callback para prevenir CSRF. |
| **RN-15** | Chaves privadas não podem estar no repositório | RSA private keys apenas via variáveis de ambiente ou cofre de segredos. |

---

## 8. Stack Tecnológica Recomendada

### 8.1 Backend

| Camada | Tecnologia | Versão mínima | Justificativa |
|--------|-----------|--------------|---------------|
| Framework | **Spring Boot** | 3.2+ | Padrão de mercado, suporte LTS até 2027 |
| Segurança OAuth2 | **Spring Security OAuth2 Resource Server** | (embutido no Spring Boot 3.2) | Validação de JWT nativa, filtros de segurança prontos |
| Segurança OAuth2 Client | **Spring Security OAuth2 Client** | (embutido) | Gerencia Authorization Code Flow + PKCE |
| Persistência | **Spring Data JPA + Hibernate** | Spring Boot 3.2 | ORM padrão, queries type-safe |
| Banco de dados | **PostgreSQL** | 15+ | JSONB, UUID nativo, robusto para produção |
| Migrations | **Flyway** | 10+ | Versionamento de schema, rollback controlado |
| Cache | **Redis** | 7+ | Rate limiting, cache de JWKS, revogação de tokens |
| Geração de JWT | **java-jwt (Auth0)** ou **nimbus-jose-jwt** | Última estável | Padrão de mercado para JWT em Java |
| Documentação de API | **SpringDoc OpenAPI (Swagger UI)** | 2.x | Geração automática de OpenAPI 3.1 |
| Observabilidade | **Spring Boot Actuator + Micrometer + OpenTelemetry** | — | Métricas, health check, tracing |
| Testes | **JUnit 5 + Mockito + TestContainers** | — | Testes unitários e de integração com banco real |

### 8.2 Exemplo de Estrutura de Pacotes

```
com.cbmrs.sol
├── auth
│   ├── config
│   │   ├── SecurityConfig.java          // configuração central do Spring Security
│   │   ├── OidcClientConfig.java        // configuração do client OIDC
│   │   └── JwtConfig.java               // configuração de emissão/validação do JWT interno
│   ├── controller
│   │   └── AuthController.java          // endpoints /auth/login, /callback, /refresh, /logout, /me
│   ├── service
│   │   ├── AuthService.java             // orquestra o fluxo de autenticação
│   │   ├── TokenService.java            // emite e valida JWT interno
│   │   ├── RefreshTokenService.java     // gerencia ciclo de vida do refresh token
│   │   └── AuditAuthService.java        // registra eventos de auditoria
│   ├── model
│   │   ├── Usuario.java                 // entidade JPA
│   │   ├── UsuarioPerfil.java           // entidade JPA
│   │   ├── RefreshToken.java            // entidade JPA
│   │   └── AuditAuthLog.java            // entidade JPA
│   ├── repository
│   │   ├── UsuarioRepository.java
│   │   ├── RefreshTokenRepository.java
│   │   └── AuditAuthLogRepository.java
│   ├── dto
│   │   ├── LoginResponseDTO.java
│   │   ├── RefreshRequestDTO.java
│   │   └── UsuarioResponseDTO.java
│   └── exception
│       ├── TokenInvalidoException.java
│       ├── SessaoComprometidaException.java
│       └── SemPermissaoException.java
└── shared
    ├── security
    │   ├── JwtAuthenticationFilter.java // valida JWT em cada requisição
    │   └── CurrentUser.java             // @CurrentUser annotation + resolver
    ├── config
    │   └── RateLimitingConfig.java
    └── exception
        └── GlobalExceptionHandler.java  // @RestControllerAdvice
```

### 8.3 Configuração por Ambiente

```yaml
# application.yml (valores via variável de ambiente em produção)

spring:
  security:
    oauth2:
      client:
        registration:
          idp-estadual:
            client-id:      ${OIDC_CLIENT_ID}
            client-secret:  ${OIDC_CLIENT_SECRET}
            scope:          openid,cpf,email,name
            redirect-uri:   ${APP_URL}/api/v1/auth/callback
            authorization-grant-type: authorization_code
        provider:
          idp-estadual:
            issuer-uri:     ${OIDC_ISSUER_URI}
            # Ex.: https://sso.govbr.gov.br/auth/realms/govbr
            # Ex.: https://keycloak.cbm.rs.gov.br/realms/sol

sol:
  auth:
    jwt:
      private-key:          ${JWT_PRIVATE_KEY}     # RSA PEM em variável de ambiente
      public-key:           ${JWT_PUBLIC_KEY}
      access-token-expiry:  PT15M                  # ISO-8601 duration
      refresh-token-expiry: PT8H
      issuer:               https://sol.cbm.rs.gov.br
      audience:             sol-api
```

### 8.4 Exemplo de Implementação — SecurityConfig

```java
@Configuration
@EnableMethodSecurity                // habilita @PreAuthorize nos controllers
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())       // stateless API — CSRF via state param no OIDC
            .sessionManagement(sm -> sm
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**").permitAll()
                .requestMatchers("/api/v1/publico/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.decoder(jwtDecoder())));   // valida JWT interno
        return http.build();
    }

    @Bean
    public JwtDecoder jwtDecoder() {
        // Usa a chave pública RSA do SOL para validar tokens emitidos pelo próprio SOL
        return NimbusJwtDecoder
            .withPublicKey(rsaPublicKey())
            .build();
    }
}
```

### 8.5 Exemplo de Controller com Autorização por Perfil

```java
@RestController
@RequestMapping("/api/v1/processos")
public class ProcessoController {

    // Apenas RT e ADM podem criar processos
    @PreAuthorize("hasAnyRole('RT', 'ADM', 'SUPERUSUARIO')")
    @PostMapping
    public ResponseEntity<ProcessoDTO> criar(...) { ... }

    // Apenas FISCAL, ADM podem registrar análise técnica
    @PreAuthorize("hasAnyRole('FISCAL', 'ADM', 'SUPERUSUARIO')")
    @PutMapping("/{id}/analise")
    public ResponseEntity<AnaliseDTO> registrarAnalise(...) { ... }
}
```

---

## 9. Arquitetura de Segurança

### 9.1 Fluxo Completo (Authorization Code + PKCE)

```
Browser/Frontend          Backend SOL           IdP (OIDC)           Banco de Dados
      │                       │                     │                      │
      │── GET /auth/login ───>│                     │                      │
      │                       │── Gera state, PKCE  │                      │
      │                       │── Armazena state     │                      │
      │<── 302 → IdP/authorize│                     │                      │
      │                       │                     │                      │
      │── Login no IdP ──────────────────────────>  │                      │
      │<── code + state ──────────────────────────  │                      │
      │                       │                     │                      │
      │── GET /auth/callback ─>│                    │                      │
      │   ?code=...&state=... │                     │                      │
      │                       │── Valida state       │                      │
      │                       │── POST /token ───────>│                    │
      │                       │   (code+verifier)    │                      │
      │                       │<── access+id token ──│                      │
      │                       │── Valida id_token    │                      │
      │                       │── Extrai CPF         │                      │
      │                       │── Consulta usuário ──────────────────────>  │
      │                       │<── usuário/status ───────────────────────   │
      │                       │── Emite JWT interno  │                      │
      │                       │── Salva refresh token ─────────────────── > │
      │                       │── Registra auditoria ─────────────────── >  │
      │<── access_token + diretiva
      │    (refresh via cookie HttpOnly)
```

### 9.2 Validação de Token em Cada Requisição

```
Requisição chega com Authorization: Bearer eyJ...
        │
        ▼
JwtAuthenticationFilter (Spring Security)
  1. Extrai token do header
  2. Valida assinatura RSA (chave pública local — sem chamada de rede)
  3. Valida exp, iss, aud
  4. Popula SecurityContextHolder com Authentication
        │
        ▼
@PreAuthorize("hasRole('RT')") — verifica roles das claims
        │
        ▼
Controller executa
```

**A validação é 100% local** — sem consulta ao banco ou ao IdP por requisição. Isso garante latência < 5ms na validação.

---

## 10. Critérios de Aceitação

### CA-01 — Login completo
- [ ] Usuário clica em "Entrar", é redirecionado para o IdP configurado
- [ ] Após login no IdP, é redirecionado de volta ao SOL
- [ ] Backend emite JWT interno com claims corretas
- [ ] Frontend recebe `diretiva` e redireciona para a tela correta
- [ ] Log de auditoria registra o evento `LOGIN_OK`

### CA-02 — Acesso negado sem token
- [ ] GET /api/v1/processos sem token retorna 401
- [ ] Body da resposta segue formato RFC 7807

### CA-03 — Acesso negado por perfil insuficiente
- [ ] RT tentando acessar /api/v1/adm/* retorna 403
- [ ] Log de auditoria **não** registra tentativas negadas (apenas logins)

### CA-04 — Refresh de token
- [ ] POST /auth/refresh com token válido retorna novo par de tokens
- [ ] Refresh token anterior é invalidado imediatamente
- [ ] POST /auth/refresh com token já usado retorna 401 (theft detection)
- [ ] Todos os tokens da família são revogados após theft detection

### CA-05 — Logout
- [ ] POST /auth/logout invalida o refresh token
- [ ] Tentativa de usar o refresh token após logout retorna 401
- [ ] Log de auditoria registra `LOGOUT`

### CA-06 — Sincronização de e-mail
- [ ] Usuário com e-mail diferente no IdP tem e-mail atualizado silenciosamente
- [ ] Log de auditoria registra `EMAIL_SYNC` com e-mail anterior e novo

### CA-07 — Rate limiting
- [ ] 11ª requisição em 1 minuto para /auth/callback retorna 429 com `Retry-After` header

### CA-08 — Usuário novo (primeiro login)
- [ ] Usuário sem cadastro é criado com status INCOMPLETO e perfil CIDADAO
- [ ] `diretiva` retornada é `CADASTRO_INCOMPLETO`
- [ ] Frontend redireciona para `/cadastro`

---

## 11. Restrições e Premissas

### 11.1 Restrições

- O sistema **não deve** depender de nenhuma biblioteca ou serviço exclusivo da PROCERGS.
- O IdP deve ser substituível por configuração (Gov.BR, Keycloak próprio do CBM, etc.) sem recompilação.
- Todo o código de autenticação deve estar encapsulado no módulo `auth` — sem vazamento de lógica de segurança para outros módulos.
- Dados de CPF, nome e e-mail são dados pessoais (LGPD) — devem ser tratados com controle de acesso adequado e logs não devem expô-los em plaintext.

### 11.2 Premissas

- O IdP externo é compatível com OIDC 1.0 e fornece as claims `cpf`, `name` e `email`.
- O banco de dados PostgreSQL é o banco primário — sem suporte a outros bancos nesta versão.
- O frontend é uma SPA (Angular, React ou similar) que consome a API REST.
- Ambiente de produção usa HTTPS obrigatoriamente.
- O segredo RSA (private key) é provisionado via variável de ambiente ou Kubernetes Secret — a equipe de infraestrutura é responsável por isso.

### 11.3 Fora do Escopo do P01

- Autenticação de sistemas externos (integrações B2B) — tratada em processo separado.
- Autenticação de usuários para consultas públicas sem login — Portal público não exige autenticação (P14).
- Gestão de usuários internos do CBM via SOE — a nova versão usa o próprio IdP para todos os atores.
- Recuperação de senha — delegada integralmente ao IdP.

---


---

## 12. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (ID3301, ID4501) e Análise de Impacto Normativo RTCBMRS N.º 01/2024 + RT de Implantação SOL-CBMRS 4ª ed./2022.  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P01.

---

### RF-26 — Detecção e Alerta de Navegador Desatualizado 🟡 P01-M1

**Prioridade:** Média  
**Origem:** Demanda 33 / ID3301 — Sprint 04 Hammer

**Descrição:** O sistema deve verificar a compatibilidade do navegador logo após a inicialização da aplicação Angular (Fase 0.5), antes do redirecionamento ao IdP. A verificação **não é bloqueante** — o usuário pode fechar o alerta e continuar.

**Detalhamento:**

A verificação ocorre dentro do método `configureAuth()` no `AppModule`, antes de qualquer chamada OIDC. A lógica é:

```
Inicialização Angular
        │
        ▼
[Fase 0.5] BrowserCompatibilityGuard.check()
        │
   ┌────┴───────────────────┐
   │ Navegador compatível?  │
   └────┬───────────────────┘
        │ NÃO
        ▼
  Exibir modal de alerta
  "Seu navegador está desatualizado.
   Para melhor experiência, use
   Chrome, Firefox ou Edge atualizados."
        │
   [Usuário fecha o modal]
        │
        ▼
   Continuar para redirect IdP
```

**Implementação:**

- Nova diretiva Angular `BrowserCompatibilityGuard` usando `ngx-device-detector` (já presente no `package.json`).
- Versões mínimas suportadas configuráveis via `app-config.json` (sem recompilação):

```json
{
  "browserMinVersions": {
    "chrome": 100,
    "firefox": 100,
    "edge": 100,
    "safari": 15
  }
}
```

- Registrar versão do navegador em log de telemetria (`INFO BrowserCompat: user-agent={ua}, compatible={true/false}`).
- O modal de alerta é exibido no máximo uma vez por sessão (flag em `sessionStorage`).

**Componente Angular:**

```typescript
@Injectable({ providedIn: 'root' })
export class BrowserCompatibilityGuard implements CanActivate {
  constructor(
    private deviceService: DeviceDetectorService,
    private dialog: MatDialog,
    private appConfig: AppConfigService
  ) {}

  canActivate(): Observable<boolean> {
    const browser = this.deviceService.browser;
    const version = parseInt(this.deviceService.browser_version);
    const minVersions = this.appConfig.get('browserMinVersions');
    const compatible = !minVersions[browser.toLowerCase()] ||
                       version >= minVersions[browser.toLowerCase()];
    if (!compatible && !sessionStorage.getItem('browserAlertShown')) {
      sessionStorage.setItem('browserAlertShown', 'true');
      return this.dialog.open(BrowserAlertDialogComponent).afterClosed()
               .pipe(map(() => true)); // não bloqueante
    }
    return of(true);
  }
}
```

**Critérios de Aceitação:**

- [ ] CA-26a: Navegador incompatível exibe modal de alerta não bloqueante
- [ ] CA-26b: Usuário consegue fechar o modal e prosseguir normalmente para o login
- [ ] CA-26c: O modal não aparece novamente na mesma sessão após ser fechado
- [ ] CA-26d: Versão do navegador é registrada em log de telemetria (`INFO` level)
- [ ] CA-26e: Versões mínimas suportadas são configuráveis via `app-config.json` sem recompilação

---

### RF-27 — Parametrização Centralizada da URL Base do Sistema 🟢 P01-M2

**Prioridade:** Baixa  
**Origem:** ID4501 — Sprint 04 Hammer

**Descrição:** A URL base do sistema deve ser parametrizada como variável de ambiente, substituindo a URL antiga `secweb.procergs.com.br/solcbm` pela nova URL `solcbm.rs.gov.br/solcbm` em todos os documentos emitidos e e-mails do sistema.

**Motivação:** A URL atual (`secweb.procergs.com.br/solcbm`) está hard-coded nos templates `.jrxml` dos relatórios JasperReports e nos templates de e-mail. Isso impede migração sem recompilação.

**Implementação — Backend:**

```yaml
# application.yml
app:
  url-base: ${APP_URL_BASE:https://solcbm.rs.gov.br/solcbm}
  url-autenticacao: ${APP_URL_BASE:https://solcbm.rs.gov.br/solcbm}/autenticacao
```

```java
@ConfigurationProperties(prefix = "app")
@Component
public class AppConfigProperties {
    private String urlBase;
    private String urlAutenticacao;
    // getters/setters
}
```

**Impacto nos relatórios JasperReports:**

- Todos os arquivos `.jrxml` devem usar o parâmetro `APP_URL_BASE` injetado pelo serviço de relatórios:

```java
// RelatorioService.java
Map<String, Object> params = new HashMap<>();
params.put("APP_URL_BASE", appConfig.getUrlBase());
params.put("APP_URL_AUTENTICACAO", appConfig.getUrlAutenticacao());
JasperFillManager.fillReport(report, params, connection);
```

**Impacto nos templates Thymeleaf (e-mails):**

```html
<!-- Em todos os templates de e-mail -->
<a th:href="${appConfig.urlBase}">Acessar o sistema SOL</a>
```

**Processos afetados:** P04 (CA/APPCI de análise), P07 (CIV/APPCI de vistoria), P14 (APPCI de renovação), todos os e-mails de notificação.

**Critérios de Aceitação:**

- [ ] CA-27a: Documentos emitidos (CA, APPCI, CIV) contêm a URL `solcbm.rs.gov.br/solcbm`
- [ ] CA-27b: E-mails enviados pelo sistema usam a URL parametrizada
- [ ] CA-27c: Alteração da URL **não requer recompilação** — apenas restart do serviço com nova variável de ambiente
- [ ] CA-27d: URL antiga `secweb.procergs.com.br/solcbm` não aparece em nenhum documento ou e-mail emitido

---

### Resumo das Mudanças P01 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P01-M1 | Novo RF-26 | Verificação de compatibilidade do navegador (Fase 0.5) | 🟡 Média |
| P01-M2 | Novo RF-27 | Parametrização centralizada da URL base como variável de ambiente | 🟢 Baixa |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 01–04*

*Documento elaborado em: 2026-03-04 (v2.0)*
*Base: análise do código-fonte SOLCBM.FrontEnd16-06 / SOLCBM.BackEnd16-06*
*Processo de referência: P01 — Autenticação no Sistema SOL/CBM-RS*
