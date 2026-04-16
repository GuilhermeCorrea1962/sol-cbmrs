# Sprint F5 — Vistoria Presencial

**Status:** ✅ Completo  
**Processo:** P07 — Vistoria Presencial  
**Rota:** `/app/vistorias` (INSPETOR, CHEFE_SSEG_BBM)  
**Roles:** INSPETOR, CHEFE_SSEG_BBM

---

## Descricao da Sprint

Implementa fila de vistoria presencial para INSPETOR. O sistema exibe licenciamentos em status VISTORIA_PENDENTE, EM_VISTORIA e EM_VISTORIA_RENOVACAO. Inspetor pode:
1. Assumir vistoria (VISTORIA_PENDENTE → EM_VISTORIA)
2. Emitir CIV — Comunicado de Inconformidade na Vistoria (EM_VISTORIA → CIV_EMITIDO)
3. Aprovar vistoria e emitir PrPCI (EM_VISTORIA → PRPCI_EMITIDO)

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **VistoriaComponent** | `frontend/src/app/pages/vistoria/vistoria-fila/vistoria-fila.component.ts` | Fila de processos em VISTORIA_PENDENTE, EM_VISTORIA |
| **VistoriaDetalheComponent** | `frontend/src/app/pages/vistoria/vistoria-detalhe/vistoria-detalhe.component.ts` | Detalhe com panel de CIV, aprovacao ou PrPCI |

---

## Fila (vistoria-fila)

**Colunas:**
- Numero PPCI
- Tipo
- Status
- Municipio
- Area
- Data entrada
- Acoes

**Ordenacao:** dataCriacao ASC (FIFO)

---

## Detalhe (vistoria-detalhe)

### Painel de leitura
- Dados do licenciamento
- Resultado da analise tecnica anterior
- Status atual

### Painel de acoes

**Botao "Assumir"** (se VISTORIA_PENDENTE)
- POST /api/licenciamentos/{id}/iniciar-vistoria
- Transicao: VISTORIA_PENDENTE → EM_VISTORIA

**Formulario CIV** (se EM_VISTORIA)
- Campo: descricao da inconformidade (obrigatorio, min 50 chars)
- POST /api/licenciamentos/{id}/civ
- Transicao: EM_VISTORIA → CIV_EMITIDO

**Formulario Aprovacao Vistoria** (se EM_VISTORIA)
- Campos: 5 laudos tecnicos (upload ou text fields)
- POST /api/licenciamentos/{id}/aprovar-vistoria
- Transicao: EM_VISTORIA → PRPCI_EMITIDO
- Backend gera automaticamente o PrPCI (Parecer de Regularizacao PPCI)

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/fila-vistoria` | Fila paginada, ordenada por dataCriacao ASC |
| POST | `/api/licenciamentos/{id}/iniciar-vistoria` | Assume a vistoria |
| POST | `/api/licenciamentos/{id}/civ` | Emite CIV |
| POST | `/api/licenciamentos/{id}/aprovar-vistoria` | Aprova e gera PrPCI |

---

## Estados suportados

- VISTORIA_PENDENTE (aguardando vistoria)
- EM_VISTORIA (vistoria em progresso)
- EM_VISTORIA_RENOVACAO (renovacao de alvara — P14)
- CIV_EMITIDO (inconformidade encontrada)
- PRPCI_EMITIDO (parecer ok, aguardando emissao de APPCI)

---

## Status de implementacao

| Item | Status |
|---|---|
| Fila FIFO | ✅ Completo |
| Painel de acoes | ✅ Completo |
| Upload de laudos | ✅ Completo |
| Geracao automatica PrPCI | ✅ Implementado no backend |

---

## Proxima etapa

Sprint F6 — Fila de emissao de APPCI (para ADMIN).
