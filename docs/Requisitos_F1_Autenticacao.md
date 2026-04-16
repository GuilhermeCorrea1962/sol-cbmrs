# Sprint F1 — Autenticacao e Login

**Status:** ✅ Completo  
**Processo:** P01 — Login  
**Rota:** `/login` (publica)  
**Roles:** Nenhum (publica)

---

## Descricao da Sprint

Implementa a tela de login integrada com o provedor de identidade estadual (SOE PROCERGS/meu.rs.gov.br) via OAuth2 Implicit Flow OIDC. O usuario e redirecionado para autenticacao externa e retorna com token JWT.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **LoginComponent** | `frontend/src/app/pages/login/login.component.ts` | Tela de login com botao "Entrar com meu.rs" |

---

## Fluxo de autenticacao

```
1. Usuario acessa /login
   ↓
2. Clica "Entrar com meu.rs"
   ↓
3. Redireciona para SOE PROCERGS
   ↓
4. Usuario faz login
   ↓
5. SOE retorna com token JWT
   ↓
6. LoginComponent armazena token
   ↓
7. Redireciona para /app/licenciamentos
```

---

## Endpoints consumidos

| Metodo | Endpoint | Tipo |
|---|---|---|
| Redirect | `https://meu.rs.gov.br/oauth2/authorize` | OIDC (externo) |
| POST | `/api/auth/token` | Token Exchange (backend) |

---

## Tecnologias

- **Frontend:** Angular 18 standalone + `angular-oauth2-oidc`
- **Seguranca:** OAuth2 Implicit Flow OIDC
- **Armazenamento:** SessionStorage (token JWT)

---

## Status de implementacao

| Item | Status |
|---|---|
| Tela de login | ✅ Completo |
| Integracao OAuth2 OIDC | ✅ Completo |
| Armazenamento de token | ✅ Completo |
| Redirecionamento apos login | ✅ Completo |
| Guard de rotas protegidas | ✅ Implementado em F2+ |

---

## Proxima etapa

Sprint F2 — Listagem de licenciamentos do usuario autenticado.
