# Sprint F9 — Relatorios (P-REL)

**Status:** ✅ Completo  
**Pre-requisito:** Sprints F1-F8 concluidas  
**Processo:** P-REL — Modulo de Relatorios e Dashboard

---

## Descricao da Sprint

O modulo de Relatorios oferece ao ADMIN e ao CHEFE_SSEG_BBM uma visao consolidada de todos os licenciamentos no sistema, com filtros avancados e exportacao CSV.

Sprint F9 implementa:

1. **Menu de Relatorios** (`/app/relatorios`) — landing page com painel de resumo por status e cards de acesso a cada relatorio disponivel.
2. **Relatorio de Licenciamentos por Periodo** (`/app/relatorios/licenciamentos`) — tabela filtravel e paginada com exportacao CSV.

---

## Componentes implementados

| Componente | Arquivo | Funcionalidade |
|---|---|---|
| **RelatoriosMenuComponent** | `frontend/src/app/pages/relatorios/relatorios-menu/relatorios-menu.component.ts` | Landing page com painel de resumo e cards de relatorios |
| **RelatorioLicenciamentosComponent** | `frontend/src/app/pages/relatorios/relatorio-licenciamentos/relatorio-licenciamentos.component.ts` | Relatorio filtravel com tabela paginada e exportacao CSV |
| **RelatorioService** | `frontend/src/app/core/services/relatorio.service.ts` | Service dedicado para endpoints de relatorios |
| **RelatorioModel** | `frontend/src/app/core/models/relatorio.model.ts` | DTOs de relatorios |

---

## Menu de Relatorios (`/app/relatorios`)

### Painel de resumo
- Chama `getResumoStatus()` no `ngOnInit`
- Se endpoint falhar (backend nao implementado), painel e silenciosamente omitido (graceful degradation)
- Exibe mini-cards coloridos com contagem por status

### Grid de cards

| Card | Status | Acao |
|---|---|---|
| Licenciamentos por Periodo | ✅ Ativo | Navega para /app/relatorios/licenciamentos |
| Vistorias Realizadas | 🟡 Em breve | Desabilitado |
| APPCI Emitidos | 🟡 Em breve | Desabilitado |
| Pendencias Criticas | 🟡 Em breve | Desabilitado |

---

## Relatorio de Licenciamentos (`/app/relatorios/licenciamentos`)

### Formulario de filtros

| Campo | Tipo | Validacao |
|---|---|---|
| Data de inicio | Date picker | Opcional |
| Data de fim | Date picker | Opcional |
| Status | Select | Opcional (dropdown com 20 status) |
| Municipio | Text input | Opcional |
| Tipo | Select | Opcional (PPCI / PSPCIM / Todos) |

**Botoes:**
- "Buscar" — executa relatorio com filtros
- "Limpar" — reseta formulario e tabela
- "Exportar CSV" — baixa resultado atual em .csv

### Tabela de resultados

**Colunas:**
- Numero PPCI
- Tipo
- Status (badge colorida)
- Municipio
- Area (m²)
- Responsavel Tecnico
- Data de entrada
- Acoes (abrir detalhe)

**Paginacao:** 50 registros/pagina, opcoes [20, 50, 100]

**Ordenacao:** dataCriacao DESC (mais recentes primeiro)

### Estados visuais

| Estado | Apresentacao |
|---|---|
| Carregando | Spinner com "Consultando..." |
| Sem resultados (apos busca) | Icone search_off + mensagem "Nenhum licenciamento encontrado" |
| Com dados | Tabela MatTable + Paginador |

---

## Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/relatorios/resumo-status` | Agrega licenciamentos por status (painel do menu) |
| GET | `/api/relatorios/licenciamentos` | Lista paginada com filtros aplicados |
| GET | `/api/relatorios/licenciamentos/csv` | Exporta resultado filtrado como arquivo CSV (Blob) |

---

## Modelos de dados

### RelatorioLicenciamentosRequest
```typescript
{
  dataInicio?: string;      // yyyy-MM-dd
  dataFim?: string;         // yyyy-MM-dd
  status?: string;          // StatusLicenciamento
  municipio?: string;       // filtro ILIKE
  tipo?: string;            // 'PPCI' | 'PSPCIM' | ''
}
```

### RelatorioLicenciamentosItem
```typescript
{
  id: number;
  numeroPpci: string | null;
  tipo: string;
  status: string;
  municipio: string;
  areaConstruida: number | null;
  dataCriacao: string;      // ISO-8601
  dataAtualizacao: string;  // ISO-8601
  nomeRT: string | null;
}
```

### RelatorioResumoStatusResponse
```typescript
{
  totalGeral: number;
  itens: [
    {
      status: string;
      label: string;
      quantidade: number;
      percentual: number;
    }
  ];
  dataGeracao: string;      // ISO-8601
}
```

---

## Fluxo de interacao

1. **Ao abrir `/app/relatorios/licenciamentos`:**
   - Carrega automaticamente (sem filtros) os 50 licenciamentos mais recentes
   - Evita tela vazia inicial

2. **Usuario preenche filtros e clica "Buscar":**
   - Executa GET /api/relatorios/licenciamentos com query params
   - Reinicia na pagina 0 do paginador

3. **Usuario clica "Limpar":**
   - Reseta formulario
   - Limpa a tabela (exige nova busca)

4. **Usuario clica "Exportar CSV":**
   - Chama GET /api/relatorios/licenciamentos/csv com filtros atuais
   - Backend retorna Blob
   - Componente aciona download via `URL.createObjectURL()` + elemento `<a>`
   - Arquivo: `relatorio-licenciamentos-YYYY-MM-DD.csv`

5. **Usuario clica icone de detalhe em uma linha:**
   - Navega para `/app/licenciamentos/:id`

---

## Acesso (RBAC)

- **Rota:** `/app/relatorios` (ADMIN, CHEFE_SSEG_BBM)
- **Guard:** `roleGuard` na rota pai protege ambos os filhos
- Usuarios sem esses roles recebem erro 403 ou redirecionamento

---

## Status de implementacao

| Item | Status |
|---|---|
| Menu de relatorios | ✅ Completo |
| Painel de resumo | ✅ Completo (graceful degradation) |
| Tabela de licenciamentos | ✅ Completo |
| Filtros avancados | ✅ Completo |
| Paginacao | ✅ Completo |
| Exportacao CSV | ✅ Completo |
| Service dedicado | ✅ Completo |
| DTOs | ✅ Completo |
| Lazy loading rotas | ✅ Completo |

---

## Proxima etapa

Sprint F10+ — Novas funcionalidades ou modulos adicionais conforme backlog.
