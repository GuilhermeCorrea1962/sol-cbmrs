# Sprint F3 — Novo Licenciamento (Wizard)

**Status:** ✅ Completo  
**Processo:** P03 — Submissao de PPCI/PSPCIM  
**Rota:** `/app/licenciamentos/novo` (CIDADAO, ADMIN)  
**Roles:** CIDADAO, RT, ADMIN

---

## Descricao da Sprint

Implementa wizard multi-passo para criacao e submissao de novo licenciamento. Usuario preenche dados do estabelecimento, seleciona tipo (PPCI/PSPCIM), aceita termos e submete para analise.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **LicenciamentoNovoComponent** | `frontend/src/app/pages/licenciamentos/licenciamento-novo/licenciamento-novo.component.ts` | Wizard com multiplos passos |

---

## Passos do wizard

| Passo | Nome | Campos |
|---|---|---|
| 1 | Tipo de licenciamento | PPCI / PSPCIM (radio buttons) |
| 2 | Endereco | Logradouro, numero, complemento, bairro, municipio, UF, CEP |
| 3 | Dados do estabelecimento | Area construida (m²), altura maxima, num pavimentos, ocupacao, uso predominante |
| 4 | Dados do responsavel | Nome, CNPJ/CPF, contato (auto-preenchido se RT) |
| 5 | Termo de aceite | Checkbox "Declaro que as informacoes sao verdadeiras" |
| 6 | Confirmacao | Resumo dos dados + botao "Submeter" |

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| POST | `/api/licenciamentos` | Cria em status RASCUNHO |
| POST | `/api/licenciamentos/{id}/submeter` | Submete para ANALISE_PENDENTE |

---

## Validacoes

- CEP: formato valido + busca de endereco (viacep ou API estadual)
- Area: numero positivo
- Altura: numero positivo
- Pavimentos: numero inteiro > 0
- Responsavel: CNPJ ou CPF valido (quando nao RT)
- Aceite: obrigatorio para submissao

---

## Estados do licenciamento

- RASCUNHO (apos POST /licenciamentos)
- ANALISE_PENDENTE (apos POST /submeter)

---

## Status de implementacao

| Item | Status |
|---|---|
| Wizard multi-passo | ✅ Completo |
| Validacao de campos | ✅ Completo |
| Persistencia em rascunho | ✅ Completo |
| Submissao | ✅ Completo |
| Navegacao (voltar/avancar) | ✅ Completo |

---

## Proxima etapa

Sprint F4 — Fila de analise tecnica (para ANALISTA).
