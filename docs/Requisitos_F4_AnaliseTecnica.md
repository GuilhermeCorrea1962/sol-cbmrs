# Sprint F4 — Analise Tecnica

**Status:** ✅ Completo  
**Processo:** P04 — Analise Tecnica (ATEC)  
**Rota:** `/app/analise` (ANALISTA, CHEFE_SSEG_BBM)  
**Roles:** ANALISTA, CHEFE_SSEG_BBM

---

## Descricao da Sprint

Implementa fila de analise tecnica para ANALISTA. O sistema exibe licenciamentos em status ANALISE_PENDENTE e EM_ANALISE. Analista pode:
1. Assumir processo (ANALISE_PENDENTE → EM_ANALISE)
2. Emitir CIA — Comunicado de Inconformidade na Analise (EM_ANALISE → CIA_EMITIDO)
3. Deferir analise (EM_ANALISE → VISTORIA_PENDENTE ou DEFERIDO)
4. Indeferir (EM_ANALISE → INDEFERIDO)

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **AnaliseComponent** | `frontend/src/app/pages/analise/analise-fila/analise-fila.component.ts` | Fila de processos em ANALISE_PENDENTE e EM_ANALISE |
| **AnaliseDetalheComponent** | `frontend/src/app/pages/analise/analise-detalhe/analise-detalhe.component.ts` | Detalhe com panel de CIA, deferimento ou indeferimento |

---

## Fila (analise-fila)

**Colunas:**
- Numero PPCI
- Tipo
- Status
- Municipio
- Area
- Data entrada
- Acoes

**Ordenacao:** dataCriacao ASC (FIFO — mais antigos primeiro)

---

## Detalhe (analise-detalhe)

### Painel de leitura
- Dados do licenciamento (endereco, area, tipo ocupacao, etc.)
- Dados do RT
- Status atual

### Painel de acoes

**Botao "Assumir"** (se ANALISE_PENDENTE)
- POST /api/licenciamentos/{id}/iniciar-analise
- Transicao: ANALISE_PENDENTE → EM_ANALISE

**Formulario CIA** (se EM_ANALISE)
- Campo: descricao da inconformidade (obrigatorio, min 50 chars)
- POST /api/licenciamentos/{id}/cia
- Transicao: EM_ANALISE → CIA_EMITIDO

**Formulario Deferimento** (se EM_ANALISE)
- Campo: tipo de ocupacao revisado (opcional)
- POST /api/licenciamentos/{id}/deferir
- Transicao: EM_ANALISE → VISTORIA_PENDENTE (PPCI) ou DEFERIDO (PSPCIM)

**Formulario Indeferimento** (se EM_ANALISE)
- Campo: motivo (obrigatorio, min 50 chars)
- POST /api/licenciamentos/{id}/indeferir
- Transicao: EM_ANALISE → INDEFERIDO

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/fila-analise` | Fila paginada, ordenada por dataCriacao ASC |
| POST | `/api/licenciamentos/{id}/iniciar-analise` | Assume o processo |
| POST | `/api/licenciamentos/{id}/cia` | Emite CIA |
| POST | `/api/licenciamentos/{id}/deferir` | Defere |
| POST | `/api/licenciamentos/{id}/indeferir` | Indefere |

---

## Status de implementacao

| Item | Status |
|---|---|
| Fila FIFO | ✅ Completo |
| Painel de acoes | ✅ Completo |
| Transicoes de estado | ✅ Completo |
| Validacoes de formulario | ✅ Completo |
| Sub-processo CIA (multi-instance) | ✅ Implementado no backend |

---

## Proxima etapa

Sprint F5 — Fila de vistoria presencial (para INSPETOR).
