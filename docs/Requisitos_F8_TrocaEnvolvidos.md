# Sprint F8 — Troca de Envolvidos

**Status:** ✅ Completo  
**Processo:** P09 — Troca de Responsavel Tecnico (RT)  
**Rota:** `/app/trocas` (ADMIN, CHEFE_SSEG_BBM)  
**Roles:** ADMIN, CHEFE_SSEG_BBM (fila/detalhe); RT/CIDADAO (inline form)

---

## Descricao da Sprint

Implementa funcionalidade de troca de Responsavel Tecnico (RT) em um licenciamento ativo. RT pode solicitar sua saida; ADMIN aceita ou rejeita. Quando aceita, backend notifica novo RT para associacao.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **TrocaFilaComponent** | `frontend/src/app/pages/troca-envolvidos/troca-fila/troca-fila.component.ts` | Fila de trocas pendentes (ADMIN/CHEFE_SSEG_BBM) |
| **TrocaDetalheComponent** | `frontend/src/app/pages/troca-envolvidos/troca-detalhe/troca-detalhe.component.ts` | Detalhe com panel de aceitar/rejeitar |
| **Inline form em licenciamento-detalhe** | `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/...` | RT solicita troca (opcional) |

---

## Fila (troca-fila)

**Colunas:**
- Numero PPCI
- Tipo
- Status
- Municipio
- Area
- Data entrada
- Acoes

**Filtro:** `trocaPendente == true` (licenciamentos com solicitacao de troca pendente)

**Ordenacao:** dataAtualizacao ASC (FIFO)

---

## Detalhe (troca-detalhe)

### Painel de leitura
- Dados do licenciamento
- RT atual
- Justificativa da troca (preenchida pelo RT)
- Status da solicitacao

### Painel de acoes (ADMIN, CHEFE_SSEG_BBM)

**Formulario Aceitar Troca**
- Campo: observacao (opcional)
- POST /api/licenciamentos/{id}/aceitar-troca
- Efeito: backend notifica novo RT para associacao; `trocaPendente` permanece true ate confirmacao

**Formulario Rejeitar Troca**
- Campo: motivo (obrigatorio, min 20 chars)
- POST /api/licenciamentos/{id}/rejeitar-troca
- Efeito: `trocaPendente = false`; RT permanece no licenciamento

---

## Inline form em licenciamento-detalhe

**Botao "Solicitar Troca de RT"** (visivel apenas para RT autenticado)
- Visivel quando: `!podeGerenciar && !trocaPendente && isStatusAtivoParaTroca`
- Campo: justificativa (min 30 chars, obrigatorio)
- POST /api/licenciamentos/{id}/solicitar-troca
- Efeito: `trocaPendente = true`
- RN-089: Bloqueado se recurso ativo

**Estados apos inline form:**
- Antes: botao "Solicitar Troca"
- Depois: panel info "Solicitacao de troca em andamento" (readonly)
- ADMIN ve em `/app/trocas` e decide

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/fila-troca` | Fila paginada (trocaPendente == true) |
| POST | `/api/licenciamentos/{id}/solicitar-troca` | RT solicita saida |
| POST | `/api/licenciamentos/{id}/aceitar-troca` | ADMIN aceita troca |
| POST | `/api/licenciamentos/{id}/rejeitar-troca` | ADMIN rejeita troca |

---

## Modelo de dados (LicenciamentoDTO)

Novos campos adicionados:
- `trocaPendente: boolean` — indica se ha solicitacao pendente
- `justificativaTroca: string | null` — justificativa preenchida pelo RT

---

## Estados e transicoes

```
Normal flow:
  trocaPendente = false
    ↓ (RT solicita)
  trocaPendente = true (aguardando ADMIN)
    ↓ (ADMIN aceita)
  trocaPendente = true (backend notifica novo RT)
    ↓ (novo RT confirma — fora do escopo F8)
  trocaPendente = false

ou

  trocaPendente = true (aguardando ADMIN)
    ↓ (ADMIN rejeita)
  trocaPendente = false
```

---

## Validacoes

- Justificativa: min 30 chars para solicitar
- Motivo rejeicao: min 20 chars
- Bloqueio se recurso ativo (RN-089)
- Bloqueio se status terminal (EXTINTO, RENOVADO, DEFERIDO, etc.)

---

## Status de implementacao

| Item | Status |
|---|---|
| Fila trocas pendentes | ✅ Completo |
| Painel aceitar/rejeitar | ✅ Completo |
| Inline form em detalhe | ✅ Completo |
| Notificacao novo RT (backend) | ✅ Implementado |
| RN-089 bloqueio | ✅ Implementado |

---

## Proxima etapa

Sprint F9 — Modulo de Relatorios (ADMIN/CHEFE_SSEG_BBM).
