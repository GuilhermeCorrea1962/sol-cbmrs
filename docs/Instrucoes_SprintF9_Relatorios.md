# Sprint F9 — Relatorios (P-REL)

**Data:** 2026-04-13
**Pre-requisito:** Sprints F1-F8 concluidas
**Processo:** P-REL — Modulo de Relatorios e Dashboard

---

## Contexto do processo

O modulo de Relatorios oferece ao ADMIN e ao CHEFE_SSEG_BBM uma visao consolidada
de todos os licenciamentos no sistema, com filtros avancados e exportacao CSV.

A Sprint F9 implementa:

1. **Menu de Relatorios** (`/app/relatorios`) — landing page com painel de resumo
   por status e cards de acesso a cada relatorio disponivel.
2. **Relatorio de Licenciamentos por Periodo** (`/app/relatorios/licenciamentos`) —
   tabela filtravel e paginada com exportacao CSV.

### Endpoints consumidos

| Metodo | Endpoint | Descricao |
|---|---|---|
| GET | `/api/relatorios/resumo-status` | Agrega licenciamentos por status (painel do menu) |
| GET | `/api/relatorios/licenciamentos` | Lista paginada com filtros aplicados |
| GET | `/api/relatorios/licenciamentos/csv` | Exporta resultado filtrado como arquivo CSV |

### Acesso (RBAC)

Somente `ADMIN` e `CHEFE_SSEG_BBM` acessam `/app/relatorios` e seus filhos.
O `roleGuard` na rota pai protege toda a arvore.

---

## Arquivos da Sprint F9

### Novos arquivos

| Arquivo em C:\SOL | Tipo | Descricao |
|---|---|---|
| `frontend\src\app\core\models\relatorio.model.ts` | NOVO | DTOs: RelatorioLicenciamentosRequest, RelatorioLicenciamentosItem, RelatorioResumoStatus* |
| `frontend\src\app\core\services\relatorio.service.ts` | NOVO | Service dedicado com getLicenciamentos, getResumoStatus, exportarCSV |
| `frontend\src\app\pages\relatorios\relatorios-menu\relatorios-menu.component.ts` | NOVO | Landing page com painel de resumo e cards de relatorios |
| `frontend\src\app\pages\relatorios\relatorio-licenciamentos\relatorio-licenciamentos.component.ts` | NOVO | Relatorio filtravel com tabela paginada e exportacao CSV |
| `infra\scripts\sprint-f9-deploy.ps1` | NOVO | Script de deploy 7 etapas |
| `logs\run-sprint-f9.ps1` | NOVO | Launcher com captura de log |

### Arquivos modificados

| Arquivo em C:\SOL | Tipo | Modificacao |
|---|---|---|
| `frontend\src\app\app.routes.ts` | ATUALIZADO | Rota /relatorios: placeholder not-found -> children com relatorios-menu e relatorio-licenciamentos |

---

## Instrucao para o Claude Code no servidor

```
Copie para C:\SOL os arquivos da Sprint F9 listados abaixo (criar diretorios novos conforme necessario):

NOVOS:
- C:\SOL\frontend\src\app\core\models\relatorio.model.ts
- C:\SOL\frontend\src\app\core\services\relatorio.service.ts
- C:\SOL\frontend\src\app\pages\relatorios\relatorios-menu\relatorios-menu.component.ts
- C:\SOL\frontend\src\app\pages\relatorios\relatorio-licenciamentos\relatorio-licenciamentos.component.ts
- C:\SOL\infra\scripts\sprint-f9-deploy.ps1
- C:\SOL\logs\run-sprint-f9.ps1

ATUALIZADO (substituir conteudo):
- C:\SOL\frontend\src\app\app.routes.ts

Apos copiar todos os arquivos, execute:
  powershell -ExecutionPolicy Bypass -File "C:\SOL\logs\run-sprint-f9.ps1"

Resultado esperado: exit code 0, sem warnings de budget CSS, sem warnings NG8011.
Relatorio gerado em: C:\SOL\logs\sprint-f9-relatorio-deploy.md
```

---

## Detalhamento de cada etapa do script de deploy

### Etapa 1 — Pre-verificacao do ambiente

Verifica:
- Node.js disponivel no PATH
- Diretorio `C:\SOL\frontend` existe
- `package.json` presente
- Pre-requisito F8: `troca-envolvidos.model.ts` presente (garante que F1-F8 foram executadas)

**Por que:** Abortar cedo evita desperdicar 3-5 minutos de build em ambiente incompleto.
Aborta com exit 1 se qualquer pre-requisito estiver ausente.

### Etapa 2 — Verificacao dos fontes F9

Verifica a presenca dos 4 novos arquivos TypeScript e 5 marcadores:

| Verificacao | Arquivo | Marcador |
|---|---|---|
| DTO presente | relatorio.model.ts | string `RelatorioLicenciamentosItem` |
| Secao F9 | relatorio.service.ts | string `Sprint F9` |
| Seletor menu | relatorios-menu.component.ts | string `sol-relatorios-menu` |
| Metodo CSV | relatorio-licenciamentos.component.ts | string `exportarCSV` |
| Rota atualizada | app.routes.ts | string `relatorios-menu` |

**Por que:** Detecta arquivos ausentes ou conteudo truncado antes do build,
economizando tempo e produzindo mensagem de erro precisa.

### Etapa 3 — npm ci

Executa `npm ci` no diretorio do frontend para garantir instalacao deterministica
das dependencias Angular/Material conforme `package-lock.json`.

**Por que:** Preferido a `npm install` em ambientes CI/CD; falha se o lock file
estiver desatualizado, protegendo contra drift de dependencias.

### Etapa 4 — Build de producao

Executa `npx ng build --configuration production`.

Apos o build, o script verifica automaticamente:
- Warnings `exceeded maximum budget` (CSS acima do limite configurado)
- Warnings `NG8011` (elementos desconhecidos no template Angular)
- Numero de chunks JS gerados

**Por que F9 nao deve gerar warnings NG8011:**
- `relatorios-menu` e `relatorio-licenciamentos` importam todos os modulos
  Material necessarios no array `imports[]` do proprio componente (standalone pattern).
- Todos os `@if/@else` com `<mat-spinner>` usam `<ng-container>` wrapper.
- Nenhum elemento HTML customizado e usado sem importacao explicita.

**Por que F9 nao deve gerar warnings de budget CSS:**
- Ambos os componentes usam `styles: [``]` inline sem arquivos .scss separados.
- O CSS adicionado e minimo: classes utilitarias de layout e cards (< 15 regras cada).

**Por que a contagem de chunks deve aumentar em 2-3:**
- `relatorios-menu` e `relatorio-licenciamentos` sao lazy-loaded via `loadComponent`.
  Cada componente gera um chunk separado pelo Angular CLI. O total esperado e
  aproximadamente 42-43 chunks (F8 tinha 40).

### Etapa 5 — Deploy para Nginx

Copia todos os arquivos de `C:\SOL\frontend\dist\sol-frontend\browser\` para
`C:\nginx\html\sol\`, sobrescrevendo os arquivos existentes da sprint anterior.

**Por que sobrescrever:** O Angular CLI gera nomes de chunk com hash de conteudo
(ex: `main.abc123.js`). A cada build os hashes mudam; e necessario substituir
os arquivos antigos para que o navegador sirva a versao correta.

### Etapa 6 — Reinicializacao do Nginx e smoke test

Reinicia o servico Nginx (`sol-nginx` ou `nginx`) e faz uma requisicao HTTP GET
a `http://localhost/`. Espera HTTP 200.

**Por que:** Confirma que o Nginx esta servindo o `index.html` correto. Nao valida
autenticacao nem backend — esses sao testados manualmente apos o deploy.

### Etapa 7 — Relatorio de deploy

Gera `C:\SOL\logs\sprint-f9-relatorio-deploy.md` com:
- Data/hora, status (SUCESSO ou ERROS: N)
- Numero de chunks JS
- Warnings detectados (budget, NG8011)
- Tabela de arquivos novos e modificados
- Tabela de rotas implementadas
- Tabela de endpoints consumidos

---

## Arquitetura dos componentes implementados

### relatorio.model.ts

Define 4 interfaces DTO alinhadas com os endpoints backend de P-REL:

```typescript
RelatorioLicenciamentosRequest  { dataInicio?, dataFim?, status?, municipio?, tipo? }
RelatorioLicenciamentosItem     { id, numeroPpci, tipo, status, municipio, areaConstruida,
                                  dataCriacao, dataAtualizacao, nomeRT }
RelatorioResumoStatusItem       { status, label, quantidade, percentual }
RelatorioResumoStatusResponse   { totalGeral, itens[], dataGeracao }
```

**Por que DTO separado (nao reusar LicenciamentoDTO):**
O `RelatorioLicenciamentosItem` e um subconjunto do `LicenciamentoDTO` projetado
para performance em listas longas — omite campos como `endereco` completo,
`justificativaRecurso`, etc. Usar o DTO completo sobrecarregaria a rede e o parse.

### relatorio.service.ts

Service dedicado (nao adicionado ao `LicenciamentoService` existente) por tres razoes:
1. Endpoints em `/api/relatorios/*` — recurso REST diferente de `/api/licenciamentos/*`.
2. Responsabilidade separada: leitura agregada vs. operacoes de negocio.
3. Facilita substituicao futura por modulo de BI sem afetar o servico principal.

Tres metodos:
- `getLicenciamentos(filtro, page, size)` — GET paginado com query params condicionais
- `getResumoStatus()` — GET simples, sem filtros
- `exportarCSV(filtro)` — GET com `responseType: 'blob'`; o componente aciona o download

### relatorios-menu.component.ts (seletor: sol-relatorios-menu)

Rota: `/app/relatorios` (index da area de relatorios).

Dois blocos visuais:
1. **Painel de resumo** — chama `getResumoStatus()` no `ngOnInit`. Se o endpoint
   retornar erro (backend nao implementado), o painel e silenciosamente omitido
   (graceful degradation via `error: () => carregandoResumo.set(false)`).
   Exibe mini-cards coloridos com a contagem por status.
2. **Grid de cards de relatorio** — um card ativo ("Licenciamentos por Periodo")
   e tres cards desabilitados ("Em breve") para vistorias, APPCI e pendencias.

**Por que placeholders "em breve":**
Antecipam as funcionalidades futuras no UI sem bloquear o deploy.
O admin ve o escopo completo do modulo desde o inicio.

### relatorio-licenciamentos.component.ts (seletor: sol-relatorio-licenciamentos)

Rota: `/app/relatorios/licenciamentos`.

Fluxo de interacao:
1. Ao abrir, executa `buscar()` automaticamente (`ngOnInit`) sem filtros —
   mostra os 50 registros mais recentes. Isso evita a tela vazia inicial.
2. Usuario preenche filtros e clica "Buscar" — reinicia na pagina 0.
3. "Limpar" reseta o formulario e limpa a tabela (exige nova busca explicitita).
4. "Exportar CSV" chama `exportarCSV()` com o filtro atual e aciona download via
   `URL.createObjectURL(blob)` + elemento `<a>` programatico.
5. Icone de detalhe em cada linha navega para `/app/licenciamentos/:id`.

**Paginacao:** `MatPaginator` com `pageSize` padrao 50 e opcoes [20, 50, 100].
O evento `(page)` atualiza `paginaAtual` e chama `executarBusca()`.

**Filtro de datas:** usa `MatDatepickerModule` + `MatNativeDateModule`.
O `FormGroup` armazena `Date | null`; o metodo `buildFiltro()` converte para
`string` ISO (`yyyy-MM-dd`) antes de enviar ao servico.

**Gerenciamento de estado (4 sinais):**
- `itens` — lista atual da tabela
- `totalRegistros` — total para o paginador
- `carregando` — exibe spinner enquanto aguarda resposta
- `pesquisaRealizada` — controla quando exibir o estado vazio (evita mostrar
  "nenhum resultado" antes de qualquer busca)

### app.routes.ts — modificacao F9

Substituicao da rota `/relatorios` que apontava para `NotFoundComponent`
(placeholder desde F1) pelo padrao children estabelecido nas sprints anteriores:

```
path: 'relatorios'
  ├── ''                 -> RelatoriosMenuComponent
  └── 'licenciamentos'   -> RelatorioLicenciamentosComponent
```

O `roleGuard` permanece no pai, protegendo ambos os filhos com uma unica declaracao.

---

## Estado do frontend apos Sprint F9

| Sprint | Processo | Rota | Roles |
|---|---|---|---|
| F1 | Infra/Login | /login | publica |
| F2 | Licenciamentos | /app/licenciamentos | todos |
| F3 | Novo Licenciamento | /app/licenciamentos/novo | CIDADAO, ADMIN |
| F4 | Analise Tecnica | /app/analise | ANALISTA, CHEFE_SSEG_BBM |
| F5 | Vistoria | /app/vistorias | INSPETOR, CHEFE_SSEG_BBM |
| F6 | APPCI | /app/appci | ADMIN, CHEFE_SSEG_BBM |
| F7 | Recurso CIA/CIV | /app/recursos | ANALISTA, ADMIN, CHEFE_SSEG_BBM |
| F8 | Troca de Envolvidos | /app/trocas | ADMIN, CHEFE_SSEG_BBM |
| **F9** | **Relatorios** | **/app/relatorios** | **ADMIN, CHEFE_SSEG_BBM** |

---

## Resultado esperado apos execucao bem-sucedida

```
SPRINT F9 - RELATORIOS (P-REL)
Deploy iniciado em: 2026-04-13 HH:MM:SS

ETAPA 1 - Pre-verificacao do ambiente
  [OK]   Node.js: v20.x.x
  [OK]   Diretorio frontend: C:\SOL\frontend
  [OK]   package.json encontrado
  [OK]   Pre-requisito F8: troca-envolvidos.model.ts presente

ETAPA 2 - Verificacao dos fontes F9
  [OK]   Presente: app\core\models\relatorio.model.ts
  [OK]   Presente: app\core\services\relatorio.service.ts
  [OK]   Presente: app\pages\relatorios\relatorios-menu\relatorios-menu.component.ts
  [OK]   Presente: app\pages\relatorios\relatorio-licenciamentos\relatorio-licenciamentos.component.ts
  [OK]   relatorio.model.ts: DTO RelatorioLicenciamentosItem presente
  [OK]   relatorio.service.ts: secao Sprint F9 presente
  [OK]   relatorios-menu.component.ts: seletor sol-relatorios-menu presente
  [OK]   relatorio-licenciamentos.component.ts: metodo exportarCSV presente
  [OK]   app.routes.ts: rota /relatorios com filho relatorios-menu presente

ETAPA 3 - npm ci
  [OK]   npm ci concluido

ETAPA 4 - Build de producao
  [OK]   Nenhum warning de budget CSS
  [OK]   Nenhum warning NG8011
  [OK]   Build concluido com sucesso (exit code 0)
  [INFO] Chunks JS gerados: 42+

ETAPA 5 - Deploy dos assets
  [OK]   Assets copiados para C:\nginx\html\sol
  [OK]   index.html copiado para C:\nginx\html\sol

ETAPA 6 - Nginx e smoke test
  [OK]   Servico sol-nginx reiniciado
  [OK]   HTTP 200 OK - aplicacao acessivel

ETAPA 7 - Relatorio
  [OK]   Relatorio gerado: C:\SOL\logs\sprint-f9-relatorio-deploy.md

  SPRINT F9 CONCLUIDA COM SUCESSO
```
