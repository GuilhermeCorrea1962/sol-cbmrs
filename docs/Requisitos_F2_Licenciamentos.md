# Sprint F2 — Listagem de Licenciamentos

**Status:** ✅ Completo  
**Processo:** P02-P14 (visualizacao agregada)  
**Rota:** `/app/licenciamentos` (todos autenticados)  
**Roles:** CIDADAO, RT, ANALISTA, INSPETOR, ADMIN, CHEFE_SSEG_BBM

---

## Descricao da Sprint

Implementa a página inicial do usuario autenticado, exibindo lista paginada dos licenciamentos aos quais ele tem acesso (por papel e proprietario). Usuarios veem seus proprios licenciamentos; ADMIN ve todos.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **LicenciamentosComponent** | `frontend/src/app/pages/licenciamentos/licenciamentos.component.ts` | Fila paginada com filtros basicos e navegacao para detalhe |

---

## Tabela de listagem

**Colunas:**
- Numero PPCI (ou '—' se em rascunho)
- Tipo (PPCI / PSPCIM)
- Status (badge colorida)
- Municipio
- Area (m²)
- Data entrada
- Acoes (ver detalhe)

**Paginacao:** 10 registros/pagina, com opcoes de 20, 50

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/meus` | Lista paginada do usuario autenticado |

---

## Filtros (basicos)

- Status (opcional)
- Municipio (opcional)
- Ordenacao: dataCriacao DESC (mais recente primeiro)

---

## Estados visuais

| Estado | Apresentacao |
|---|---|
| Carregando | Spinner |
| Sem resultados | Mensagem "Nenhum licenciamento encontrado" |
| Com dados | Tabela MatTable paginada |

---

## Navegacao

- Clicar linha → `/app/licenciamentos/:id` (detalhe)
- Botao "Novo" → `/app/licenciamentos/novo` (F3)

---

## Status de implementacao

| Item | Status |
|---|---|
| Tabela MatTable | ✅ Completo |
| Paginacao | ✅ Completo |
| Filtros basicos | ✅ Completo |
| Loading/empty states | ✅ Completo |
| Navegacao | ✅ Completo |

---

## Proxima etapa

Sprint F3 — Criacao e submissao de novo licenciamento (wizard).
