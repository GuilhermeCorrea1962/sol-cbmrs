# Sprint F7 — Recurso CIA/CIV

**Status:** ✅ Completo (com 1 warning NG8102 nao bloqueante)  
**Processo:** P10 — Recurso contra CIA ou CIV  
**Rota:** `/app/recursos` (ANALISTA, ADMIN, CHEFE_SSEG_BBM)  
**Roles:** ANALISTA, ADMIN, CHEFE_SSEG_BBM

---

## Descricao da Sprint

Implementa fila de recursos contra CIA (Comunicado de Inconformidade na Analise) ou CIV (Comunicado de Inconformidade na Vistoria). RT submete recurso; ADMIN triagem; comissao vota (unanimidade obrigatoria); ADMIN decide.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **RecursoComponent** | `frontend/src/app/pages/recurso/recurso-fila/recurso-fila.component.ts` | Fila de processos em RECURSO_SUBMETIDO e RECURSO_EM_ANALISE |
| **RecursoDetalheComponent** | `frontend/src/app/pages/recurso/recurso-detalhe/recurso-detalhe.component.ts` | Detalhe com panel de triagem, votacao ou decisao |
| **Inline form em licenciamento-detalhe** | `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/...` | RT submete recurso inline (RN-089: bloqueado se recurso ativo) |

---

## Fila (recurso-fila)

**Colunas:**
- Numero PPCI
- Tipo
- Status
- Municipio
- Area
- Data entrada
- Acoes

**Filtro:** Status IN [RECURSO_SUBMETIDO, RECURSO_EM_ANALISE]

**Ordenacao:** dataAtualizacao ASC (FIFO)

---

## Detalhe (recurso-detalhe)

### Painel de leitura
- Dados do licenciamento
- Comunicado original (CIA ou CIV) + descricao
- Justificativa do recurso (preenchida pelo RT)
- Status atual

### Painel de triagem (ADMIN, RECURSO_SUBMETIDO)

**Botao "Aceitar Recurso"**
- POST /api/licenciamentos/{id}/aceitar-recurso
- Transicao: RECURSO_SUBMETIDO → RECURSO_EM_ANALISE
- Habilita votacao da comissao

**Botao "Recusar Recurso"**
- POST /api/licenciamentos/{id}/recusar-recurso + motivo
- Transicao: RECURSO_SUBMETIDO → CIA_EMITIDO ou CIV_EMITIDO (retorna ao status anterior)

### Painel de votacao (ANALISTA, RECURSO_EM_ANALISE)

**Formulario Voto**
- Radio buttons: Deferido / Indeferido
- POST /api/licenciamentos/{id}/votar-recurso
- RN-088: Unanimidade obrigatoria (todos os membros presentes devem votar igual)
- Backend controla quorum e unanimidade

**Estados possiveis apos votacao:**
- Aguardando mais votos (display: "N/M membros votaram")
- Todos votaram + unanimidade alcancada → Habilita botao "Decidir"
- Todos votaram + SEM unanimidade → Bloqueia decisao (necessaria outra rodada)

### Painel de decisao (ADMIN, RECURSO_EM_ANALISE)

**Botao "Decidir Recurso"** (aparece apenas se unanimidade)
- Seleciona: Deferido / Indeferido
- POST /api/licenciamentos/{id}/decidir-recurso
- Transicao: RECURSO_EM_ANALISE → RECURSO_DEFERIDO ou RECURSO_INDEFERIDO
- Se DEFERIDO: retorna ao fluxo normal (EM_ANALISE ou EM_VISTORIA)
- Se INDEFERIDO: CIA/CIV original e mantido; RT pode iniciar novo processo

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/fila-recurso` | Fila paginada, ordenada por dataAtualizacao ASC |
| POST | `/api/licenciamentos/{id}/submeter-recurso` | RT submete recurso (RN-089: bloqueado se recurso ativo) |
| POST | `/api/licenciamentos/{id}/aceitar-recurso` | ADMIN aceita para analise |
| POST | `/api/licenciamentos/{id}/recusar-recurso` | ADMIN recusa na triagem |
| POST | `/api/licenciamentos/{id}/votar-recurso` | ANALISTA vota (unanimidade RN-088) |
| POST | `/api/licenciamentos/{id}/decidir-recurso` | ADMIN registra decisao final |

---

## Inline form em licenciamento-detalhe

**Botao "Solicitar Recurso"** (visivel em CIA_EMITIDO ou CIV_EMITIDO)
- Visivel apenas para RT autenticado
- Campo: justificativa (min 30 chars, obrigatorio)
- POST /api/licenciamentos/{id}/submeter-recurso
- Apos submit: Transicao CIA_EMITIDO/CIV_EMITIDO → RECURSO_SUBMETIDO
- RN-089: Bloqueado se ja existe recurso ativo em qualquer status RECURSO_*

---

## Regras de negocio

| RN | Descricao | Implementacao |
|---|---|---|
| RN-088 | Unanimidade na votacao obrigatoria | Backend valida; frontend mostra bloqueio se SEM unanimidade |
| RN-089 | PPCI bloqueado para nova analise enquanto recurso ativo | Backend; frontend exibe botao "Recurso em andamento" |
| RN-090 a RN-108 | Prazos de ciencia (30 dias) | Backend; frontend mostra data limite |

---

## Estados suportados

- CIA_EMITIDO (permite submissao de recurso)
- CIV_EMITIDO (permite submissao de recurso)
- RECURSO_SUBMETIDO (aguardando triagem de ADMIN)
- RECURSO_EM_ANALISE (votacao da comissao em progresso)
- RECURSO_DEFERIDO (recurso aceito; retorna ao fluxo normal)
- RECURSO_INDEFERIDO (recurso negado; CIA/CIV original se mantem)

---

## Warnings conhecidos

- **NG8102** em `recurso-detalhe.component.ts:72` — nullish coalescing em campo nao-nullable (nao bloqueante, residual)

---

## Status de implementacao

| Item | Status |
|---|---|
| Fila FIFO | ✅ Completo |
| Triagem (aceitar/recusar) | ✅ Completo |
| Votacao com unanimidade | ✅ Completo |
| Decisao final | ✅ Completo |
| Inline form em detalhe | ✅ Completo |
| RN-089 bloqueio | ✅ Implementado |

---

## Proxima etapa

Sprint F8 — Troca de Envolvidos (ADMIN/CHEFE_SSEG_BBM).
