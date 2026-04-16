# Sprint F6 — Emissao de APPCI

**Status:** ✅ Completo  
**Processo:** P08 — Emissao de APPCI  
**Rota:** `/app/appci` (ADMIN, CHEFE_SSEG_BBM)  
**Roles:** ADMIN, CHEFE_SSEG_BBM

---

## Descricao da Sprint

Implementa fila de emissao de APPCI (Alvara de Prevencao e Protecao Contra Incendio) para ADMIN. O sistema exibe licenciamentos em status PRPCI_EMITIDO aguardando emissao do alvara. ADMIN emite o APPCI, que gera automaticamente a validade (2 ou 5 anos conforme RTCBMRS N.01/2024).

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **AppciComponent** | `frontend/src/app/pages/appci/appci-fila/appci-fila.component.ts` | Fila de processos em PRPCI_EMITIDO |
| **AppciDetalheComponent** | `frontend/src/app/pages/appci/appci-detalhe/appci-detalhe.component.ts` | Detalhe com panel de emissao de APPCI |

---

## Fila (appci-fila)

**Colunas:**
- Numero PPCI
- Tipo
- Municipio
- Area
- Data entrada da vistoria
- Acoes

**Filtro:** Status == PRPCI_EMITIDO

**Ordenacao:** dataCriacao ASC (FIFO)

---

## Detalhe (appci-detalhe)

### Painel de leitura
- Numero e validade do PrPCI
- Dados do estabelecimento
- Resultado da vistoria (laudos)
- Status atual (PRPCI_EMITIDO)

### Painel de emissao APPCI

**Botao "Emitir APPCI"**
- POST /api/licenciamentos/{id}/emitir-appci
- Backend calcula automaticamente:
  - Data de validade: +2 anos (PPCI com risco baixo) ou +5 anos (conforme ocupacao)
  - Numero do APPCI (sequencial com versionamento)
- Transicao: PRPCI_EMITIDO → APPCI_EMITIDO
- Gera documento PDF do alvara (opcional download)

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/licenciamentos/fila-appci` | Fila paginada, ordenada por dataCriacao ASC |
| POST | `/api/licenciamentos/{id}/emitir-appci` | Emite APPCI com calculo automatico de validade |

---

## Calculo da validade (RN-087)

- **Ocupacao baixo risco:** +2 anos
- **Ocupacao risco moderado/alto:** +5 anos
- Data de vencimento: armazenada em `dtValidadeAppci`

---

## Saidas do APPCI

- Numero do alvara (automatico)
- Data de emissao (data atual)
- Data de vencimento (calculada)
- PDF para impressao (opcional)

---

## Estados suportados

- PRPCI_EMITIDO (aguardando emissao de alvara)
- APPCI_EMITIDO (alvara emitido e valido)
- ALVARA_VENCIDO (almejado apos +2/5 anos de APPCI_EMITIDO)

---

## Status de implementacao

| Item | Status |
|---|---|
| Fila FIFO | ✅ Completo |
| Emissao APPCI | ✅ Completo |
| Calculo automatico validade | ✅ Implementado no backend |
| Download PDF | ✅ Implementado no backend |

---

## Proxima etapa

Sprint F7 — Fila de recurso CIA/CIV (para ANALISTA/ADMIN).
