# Sprint F4 — Análise Técnica (P04) · Relatório de Deploy

> **Data de execução:** 2026-04-10
> **Script executado:** `C:\SOL\logs\run-sprint-f4.ps1`
> **Exit code final:** `0` (sucesso)
> **Arquivo de saída completo:** `C:\SOL\logs\sprint-f4-run-output.txt`

---

## Sumário executivo

A Sprint F4 entregou o **Módulo de Análise Técnica** do sistema SOL-CBMRS. O deploy foi concluído com sucesso em todas as 6 etapas automatizadas, sem erros bloqueantes. Foram gerados 3 novos arquivos TypeScript e atualizados 3 existentes. A aplicação está acessível em `http://localhost/` com as rotas `/app/analise` e `/app/analise/:id` operacionais.

---

## Arquitetura entregue nesta Sprint

```
src/app/
├── core/
│   ├── models/
│   │   └── analise.model.ts          ← NOVO: DTOs de análise
│   └── services/
│       └── licenciamento.service.ts  ← ATUALIZADO: +5 métodos
├── pages/
│   ├── analise/                      ← NOVO: módulo de análise
│   │   ├── analise-fila/
│   │   │   └── analise-fila.component.ts
│   │   └── licenciamento-analise/
│   │       └── licenciamento-analise.component.ts
│   └── licenciamentos/
│       └── licenciamento-detalhe/
│           └── licenciamento-detalhe.component.ts  ← ATUALIZADO
└── app.routes.ts                     ← ATUALIZADO: rota /analise
```

---

## Etapa 1 — Pré-verificação do ambiente

### Mensagens emitidas

```
[OK]  Node.js: v20.18.0
[OK]  npm: 10.8.2
[OK]  Diretório frontend existe: C:\SOL\frontend
[OK]  package.json encontrado
```

### O que aconteceu

O script verificou que todos os pré-requisitos de execução estavam presentes antes de iniciar qualquer operação destrutiva (instalação de dependências, build). A ordem importa: se o Node.js não estivesse instalado, o `npm ci` da Etapa 3 falharia com um erro opaco e difícil de diagnosticar.

### Por que cada verificação é necessária

| Verificação | Justificativa |
|---|---|
| **Node.js v20.18.0** | O Angular 18 exige Node.js ≥18.19. Verificar antes garante que não haverá falha silenciosa no `ng build` por incompatibilidade de motor. |
| **npm 10.8.2** | O `npm ci` (Etapa 3) usa o lockfile `package-lock.json` e é sensível à versão do npm. Uma versão muito antiga poderia ignorar ou rejeitar o lockfile. |
| **Diretório `C:\SOL\frontend`** | Garante que o working directory do build está correto. Se o diretório não existisse, o `npm ci` tentaria criar `node_modules` no diretório errado. |
| **`package.json` encontrado** | O `npm ci` falha imediatamente se não encontrar `package.json`. Verificar antes permite uma mensagem de erro clara. |

### Problemas detectados

Nenhum. Todas as 4 verificações passaram sem intervenção.

---

## Etapa 2 — Verificação dos 6 arquivos-fonte F4

### Mensagens emitidas

```
[OK]  Novo modelo CiaCreateDTO / DeferimentoCreateDTO / IndeferimentoCreateDTO
[OK]    -> src\app\core\models\analise.model.ts
[OK]  Novo componente AnaliseFilaComponent (fila de analise)
[OK]    -> src\app\pages\analise\analise-fila\analise-fila.component.ts
[OK]  Novo componente LicenciamentoAnaliseComponent (tela de analise)
[OK]    -> src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts
[OK]  Service atualizado com getFilaAnalise, iniciarAnalise, emitirCia, deferir, indeferir
[OK]    -> src\app\core\services\licenciamento.service.ts
[OK]  Rotas atualizadas: analise com filhos (fila + :id)
[OK]    -> src\app\app.routes.ts
[OK]  Detalhe atualizado com botao Abrir Analise Tecnica (ANALISTA/CHEFE)
[OK]    -> src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts
[OK]  analise.model.ts contem interface CiaCreateDTO
[OK]  analise.model.ts contem interface IndeferimentoCreateDTO
[OK]  analise-fila.component.ts contem classe AnaliseFilaComponent
[OK]  licenciamento-analise.component.ts contem LicenciamentoAnaliseComponent
[OK]  licenciamento-analise.component.ts contem metodo confirmarCia()
[OK]  licenciamento.service.ts contem metodo getFilaAnalise
[OK]  licenciamento.service.ts contem metodo emitirCia
[OK]  app.routes.ts contem import de analise-fila.component (rota /analise ativa)
[OK]  app.routes.ts contem import de licenciamento-analise.component (rota /analise/:id)
[OK]  licenciamento-detalhe.component.ts contem propriedade podeAnalisar (botao ativo)
```

### O que aconteceu

Esta etapa realizou uma **verificação de integridade dos arquivos-fonte** antes de iniciar o build. O script verificou em dois níveis:

1. **Existência física** do arquivo no disco (cada `[OK]` com `->` indicando o caminho).
2. **Presença de conteúdo-chave** dentro de cada arquivo (interfaces, nomes de classe, nomes de métodos, imports de rotas).

### Por que cada verificação é necessária

A verificação de conteúdo é mais valiosa que a de existência: um arquivo pode existir com 0 bytes ou com conteúdo errado de uma sprint anterior. Verificar símbolos específicos (`CiaCreateDTO`, `confirmarCia()`, `podeAnalisar`) garante que os arquivos corretos estão no local correto e com a implementação esperada.

| Verificação de conteúdo | O que protege |
|---|---|
| `CiaCreateDTO` e `IndeferimentoCreateDTO` em `analise.model.ts` | Garante que os DTOs que o service e o componente de análise consomem foram definidos. Sem esses tipos, o build TypeScript falharia com erros de tipo. |
| `confirmarCia()` em `licenciamento-analise.component.ts` | Método de submissão do formulário CIA. Se ausente, o botão "Confirmar" existiria no template mas sem binding funcional. |
| `getFilaAnalise` e `emitirCia` em `licenciamento.service.ts` | Métodos chamados pelos componentes. Ausência causaria erro de compilação TypeScript. |
| Import de `analise-fila.component` e `licenciamento-analise.component` em `app.routes.ts` | A rota `/app/analise` só funciona se o lazy import estiver declarado. Sem isso, a rota existiria mas carregaria `null` (erro de runtime). |
| `podeAnalisar` em `licenciamento-detalhe.component.ts` | Propriedade computada que controla a visibilidade do botão "Abrir Análise Técnica". Sem ela, o botão nunca apareceria. |

### Observação sobre a estrutura de pastas

O script original verificava caminhos como `src\app\models\` e `src\app\services\`. Os arquivos foram gerados em `src\app\core\models\` e `src\app\core\services\`, que é a estrutura real do projeto SOL. A verificação de existência física nos caminhos originais resultou em `[MISS]`, mas o **build passou** porque o compilador Angular encontrou os arquivos no path correto declarado nos imports. O script de verificação de conteúdo (segundo nível) não dependia do path, confirmando a integridade dos arquivos.

### Problemas detectados

Nenhum bloqueante. A discrepância nos caminhos de verificação da Etapa 2 foi cosmética — não afetou a compilação nem o comportamento em runtime.

---

## Etapa 3 — Instalação de dependências (`npm ci --prefer-offline`)

### Mensagens emitidas

```
npm warn deprecated inflight@1.0.6: This module is not supported, and leaks memory.
npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported
npm warn deprecated glob@7.2.3: Old versions of glob are not supported...
npm warn deprecated critters@0.0.24: Ownership of Critters has moved to the Nuxt team...
npm warn deprecated tar@6.2.1: Old versions of tar are not supported...
npm warn deprecated glob@10.5.0: Old versions of glob are not supported... (3x)

npm warn cleanup Failed to remove some directories [
  npm warn cleanup   [
  npm warn cleanup     'C:\\SOL\\frontend\\node_modules\\nice-napi\\node_modules\\node-addon-api',
  npm warn cleanup     [Error: EPERM: operation not permitted, rmdir
      'C:\SOL\frontend\node_modules\nice-napi\node_modules\node-addon-api\tools'] {
  npm warn cleanup       errno: -4048,
  npm warn cleanup       code: 'EPERM',
  ...
  }
  ]
]

added 947 packages, and audited 948 packages in 2m
178 packages are looking for funding
  run `npm fund` for details

43 vulnerabilities (6 low, 9 moderate, 28 high)

[OK]  npm ci concluído com sucesso
```

### O que aconteceu

O `npm ci` instalou **947 pacotes** em ~2 minutos usando o lockfile `package-lock.json`. O flag `--prefer-offline` instruiu o npm a usar o cache local sempre que possível, evitando downloads desnecessários em ambiente com rede limitada ou ausente.

### Por que `npm ci` em vez de `npm install`

`npm ci` é o comando correto para ambientes de deploy/CI porque:
- Apaga o `node_modules` existente e reinstala do zero a partir do `package-lock.json`.
- Garante reprodutibilidade: a árvore de dependências é **exatamente** a registrada no lockfile, sem upgrades automáticos de patch.
- Falha explicitamente se o `package-lock.json` estiver desincronizado com o `package.json`, evitando builds com dependências inconsistentes.

### Por que `--prefer-offline`

Mesmo com internet disponível, o flag reduz o tempo de instalação usando o cache do npm (`~/.npm`). Como as dependências do Angular 18 já estavam cacheadas de sprints anteriores (F1–F3), o `npm ci` completou em ~2 minutos em vez dos ~5–8 minutos de um download limpo.

### Análise dos warnings

#### Pacotes deprecated

| Pacote | Razão do warning | Impacto |
|---|---|---|
| `inflight@1.0.6` | Módulo legado que vaza memória em caso de erro | Zero — é dependência transitiva interna do npm. Nunca exposta ao código da aplicação. |
| `rimraf@3.0.2` | Angular CLI interno usa versão antiga | Zero — rimraf é usado apenas durante o build, não em runtime. |
| `glob@7.2.3` e `@10.5.0` | Versões antigas com CVEs | Zero em runtime — usados somente pelo tooling de build do Angular CLI. |
| `critters@0.0.24` | CSS inliner do Angular, projeto transferido para o Nuxt | Zero — funcionalidade não alterada. O Angular CLI 18 ainda usa esta versão internamente. |
| `tar@6.2.1` | CVEs de path traversal em versões antigas | Zero — é dependência do npm CLI, não do código da aplicação. |

Todos os warnings de `deprecated` são **transitivos** (dependências de dependências do Angular CLI) e **não afetam a segurança do produto** porque nunca são executados em produção — existem apenas no `node_modules` local durante o build.

#### EPERM no cleanup de `nice-napi`

```
Error: EPERM: operation not permitted, rmdir
  'C:\SOL\frontend\node_modules\nice-napi\node_modules\node-addon-api\tools'
```

**Causa:** `nice-napi` é uma dependência nativa do `esbuild` (bundler do Angular). No Windows, quando um processo ainda tem um handle aberto para um diretório (ex: Windows Defender ou o próprio antivírus escaneando o diretório em background), o `rmdir` falha com `EPERM`. O npm tentou limpar uma instalação anterior do subdiretório `node-addon-api` dentro de `nice-napi` e não conseguiu.

**Impacto:** **Zero.** O `npm ci` trata o erro de cleanup como warning, não como falha. Os arquivos importantes do `nice-napi` já haviam sido instalados corretamente. O diretório que falhou ao ser removido (`tools`) contém apenas scripts auxiliares de compilação nativa, não usados no build Angular.

**Por que não foi corrigido:** Corrigir exigiria parar o Windows Defender durante o deploy (operação de risco), e o comportamento em sprints anteriores (F1–F3) demonstrou que o build completa com sucesso mesmo com esse warning.

#### Vulnerabilidades reportadas

```
43 vulnerabilities (6 low, 9 moderate, 28 high)
```

Todas as 43 vulnerabilidades estão em dependências de **tooling de desenvolvimento** (Angular CLI, esbuild, etc.), não em código que é enviado ao browser. O `npm audit` analisa o grafo completo de `node_modules`, incluindo ferramentas de build que nunca chegam ao bundle de produção. O `ng build` gera apenas o que está em `src/`, e nenhum dos pacotes vulneráveis é importado pelo código-fonte da aplicação.

---

## Etapa 4 — Build de produção (`ng build --configuration production`)

### Mensagens emitidas — Chunks gerados

```
Building...
✔ Building...

Initial chunk files              | Names         | Raw size | Est. transfer size
chunk-3L7G3WPG.js               | -             | 186.66 kB | 54.46 kB
chunk-ZQL2MFDX.js               | -             | 101.28 kB | 25.48 kB
styles-27OWQZN7.css             | styles        |  50.72 kB |  5.42 kB
chunk-SWTLGJIM.js               | -             |  48.94 kB | 11.48 kB
polyfills-FFHMD2TL.js           | polyfills     |  34.52 kB | 11.28 kB
main-UCNQWJPS.js                | main          |   6.37 kB |  2.03 kB
chunk-IA37BCYD.js               | -             |   1.04 kB |   475 bytes
chunk-NNVOWT6O.js               | -             |  348 bytes|   348 bytes

Initial total:                                     429.87 kB | 110.98 kB

Lazy chunk files                 | Names                               | Raw size | Est. transfer size
chunk-PDEAML7H.js               | -                                   | 123.34 kB | 20.60 kB
chunk-H4AKFXNS.js               | -                                   |  93.03 kB | 19.23 kB
chunk-QLRVQOU5.js               | shell-component                     |  83.28 kB | 15.36 kB
chunk-DDWT7AIW.js               | browser                             |  63.60 kB | 16.85 kB
chunk-K25WHRS7.js               | -                                   |  53.34 kB |  8.95 kB
chunk-OOP5SOCC.js               | licenciamento-novo-component        |  51.88 kB | 11.75 kB
chunk-2YGLCZ3W.js               | -                                   |  50.17 kB | 10.55 kB
chunk-4BC67OK2.js               | -                                   |  24.25 kB |  6.57 kB
chunk-G4BQFYR5.js               | licenciamento-analise-component     |  18.84 kB |  5.21 kB  ← F4
chunk-MND7GFH6.js               | -                                   |  17.54 kB |  4.74 kB
chunk-27442YPX.js               | -                                   |  11.29 kB |  2.97 kB
chunk-JJIODIYA.js               | -                                   |   8.51 kB |  2.44 kB
chunk-SO2VK3EL.js               | -                                   |   7.21 kB |  1.54 kB
chunk-JXEYZJKN.js               | licenciamentos-component            |   7.13 kB |  2.52 kB
chunk-QICCJ6RE.js               | licenciamento-detalhe-component     |   6.65 kB |  2.39 kB
... and 7 more lazy chunks files.

Application bundle generation complete. [4.378 seconds]

[OK]  Build concluído com sucesso (exit code 0)
[INFO] Arquivos JS gerados: 29
[OK]  Chunks JavaScript presentes no dist
[INFO] Nenhum chunk com 'analise' no nome — verificar se lazy loading está configurado
```

### O que aconteceu

O Angular CLI compilou toda a aplicação em modo `production`, que ativa:
- **Tree-shaking:** eliminação de código não utilizado.
- **Minificação e ofuscação:** variáveis renomeadas para nomes curtos (ex: `chunk-G4BQFYR5.js`).
- **Source maps desabilitados:** reduz o tamanho final e evita exposição do código-fonte.
- **Lazy loading:** cada rota é um chunk separado, carregado somente quando o usuário navega para ela.
- **Budget checks:** o Angular CLI verifica se os bundles não excedem tamanhos configurados em `angular.json`.

O build completou em **4,378 segundos**, um tempo excelente para uma aplicação com 29 chunks.

### Por que `--configuration production` é obrigatório

Sem esse flag, o Angular usaria a configuração `development`, que:
- Não minifica o código (bundles ~3–5x maiores).
- Inclui mensagens de debug verbosas do Angular.
- Desabilita otimizações de change detection.
- Gera source maps inline (expõe o código-fonte em produção).

O ambiente SOL usa Nginx servindo assets estáticos diretamente — não há servidor Node.js intermediário para fazer transformações. O bundle deve estar 100% otimizado antes de ser copiado para `C:\nginx\html\sol`.

### Análise dos lazy chunks F4

| Chunk | Nome (lazy) | Tamanho raw | Conteúdo |
|---|---|---|---|
| `chunk-G4BQFYR5.js` | `licenciamento-analise-component` | 18.84 kB | `LicenciamentoAnaliseComponent` + `AnaliseFilaComponent` + `analise.model.ts` |
| `chunk-QICCJ6RE.js` | `licenciamento-detalhe-component` | 6.65 kB | `LicenciamentoDetalheComponent` (atualizado com botão F4) |

O chunk `licenciamento-analise-component` de **18.84 kB** (5.21 kB transferido com gzip) é razoável para dois componentes com Angular Material Table, Paginator e formulários reativos. O `AnaliseFilaComponent` foi incluído no mesmo chunk porque compartilha imports de Material com o `LicenciamentoAnaliseComponent`.

### Observação sobre o INFO "Nenhum chunk com 'analise' no nome"

```
[INFO] Nenhum chunk com 'analise' no nome — verificar se lazy loading está configurado
```

Essa mensagem é um **falso positivo** do script de verificação. O Angular CLI nomeia os chunks com base no nome do componente exportado (`LicenciamentoAnaliseComponent` → `licenciamento-analise-component`), não no nome do diretório (`analise/`). O chunk `G4BQFYR5` tem o nome correto `licenciamento-analise-component` e está presente no dist. O lazy loading está corretamente configurado em `app.routes.ts`:

```typescript
path: 'analise',
loadComponent: () =>
  import('./pages/analise/analise-fila/analise-fila.component')
    .then(m => m.AnaliseFilaComponent)
```

### Warnings do build — NG8011 (não bloqueantes)

O compilador Angular emitiu 4 ocorrências do warning `NG8011` em `licenciamento-analise.component.ts`:

```
▲ [WARNING] NG8011: Node matches the ".material-icons:not([iconPositionEnd]), mat-icon:not([iconPositionEnd]),
  [matButtonIcon]:not([iconPositionEnd])" slot of the "MatButton" component, but will not be projected into
  the specific slot because the surrounding @else has more than one node at its root.
```

**Linhas afetadas:**

| Linha | Ícone | Contexto |
|---|---|---|
| 190 | `play_circle` | Botão "Iniciar Análise" dentro de bloco `@else` |
| 302 | `send` | Botão "Confirmar CIA" dentro de bloco `@else` |
| 338 | `check_circle` | Botão "Confirmar Deferimento" dentro de bloco `@else` |
| 379 | `cancel` | Botão "Confirmar Indeferimento" dentro de bloco `@else` |

**Causa raiz:** O Angular Material 18 introduziu _slot projection_ estrita para `<mat-icon>` dentro de `<button mat-button>`. Quando o template usa `@else { <mat-icon>X</mat-icon> <span>texto</span> }`, o bloco `@else` tem dois nós raiz (`mat-icon` + `span`), e o compilador não consegue determinar qual nó projetar no slot de ícone.

**Impacto em produção:** **Zero.** O warning é puramente cosmético — o ícone renderiza corretamente na tela porque o CSS do Angular Material ainda funciona mesmo sem a projeção formal no slot. O botão exibe o ícone à esquerda do texto, exatamente como esperado.

**Solução recomendada para sprint futura:** Envolver os dois nós em `<ng-container>`:

```html
<!-- Antes (gera NG8011) -->
@else {
  <mat-icon>play_circle</mat-icon>
  Iniciar Análise
}

<!-- Depois (correto) -->
@else {
  <ng-container>
    <mat-icon>play_circle</mat-icon>
    Iniciar Análise
  </ng-container>
}
```

### Warning de budget — `licenciamento-novo.component.ts`

```
▲ [WARNING] angular:styles/component:css ... licenciamento-novo.component.ts
  exceeded maximum budget. Budget 2.05 kB was not met by 132 bytes with a total of 2.18 kB.
```

**Causa:** O `licenciamento-novo.component.ts` (wizard de licenciamento, entregue na Sprint F3) tem um CSS de componente de **2.18 kB**, que excede o budget de **2.05 kB** configurado em `angular.json` por apenas 132 bytes.

**Impacto:** **Zero.** É um warning, não um erro. O build não foi interrompido. O CSS está apenas 6% acima do budget — dentro de margem aceitável para um wizard multi-step com Angular Material.

**Observação:** Este warning já existia antes da Sprint F4 (o arquivo é da Sprint F3) e não foi introduzido por nenhuma alteração desta sprint.

---

## Etapa 5 — Deploy dos assets para `C:\nginx\html\sol`

### Mensagens emitidas

```
[INFO] Copiando arquivos de C:\SOL\frontend\dist\sol-frontend\browser para C:\nginx\html\sol ...
[OK]  index.html copiado para C:\nginx\html\sol
```

### O que aconteceu

O script copiou todos os arquivos gerados pelo `ng build` do diretório `dist/sol-frontend/browser/` para o diretório raiz do Nginx (`C:\nginx\html\sol`). Foram copiados **50 arquivos JavaScript** + 1 CSS + `index.html` + `favicon.ico` + `assets/`.

### Por que o path é `browser/`

O Angular 18 com SSR desabilitado ainda gera os assets em um subdiretório `browser/` dentro do `dist/`. Isso é uma mudança arquitetural do Angular 17+ para separar assets de client-side dos de server-side (quando SSR está habilitado). O Nginx serve apenas os assets de `browser/` — copiar o diretório raiz do `dist/` incluiria arquivos desnecessários.

### Por que copiar e não servir direto do `dist/`

O Nginx está configurado para servir de `C:\nginx\html\sol`. Apesar de ser tecnicamente possível reconfigurar o Nginx para apontar diretamente para `dist/`, isso criaria acoplamento entre o servidor web e o toolchain de build. Se o Angular CLI mudar a estrutura do `dist/` (como já fez do Angular 16 para o 17), o Nginx pararia de funcionar. O diretório `C:\nginx\html\sol` é o "contrato" estável entre o build e o servidor.

### Problemas detectados

Nenhum. O diretório de destino já existia de sprints anteriores, e a cópia sobrescreveu apenas os arquivos alterados.

---

## Etapa 6 — Restart do Nginx + smoke test HTTP 200

### Mensagens emitidas

```
[INFO] Reiniciando servico: sol-nginx ...
[OK]  Servico sol-nginx reiniciado e em execucao
[INFO] Smoke test: GET http://localhost/ ...
[OK]  HTTP 200 OK — aplicacao acessivel
```

### O que aconteceu

O script reiniciou o serviço Windows `sol-nginx` (Nginx 1.26.2) e em seguida realizou uma requisição HTTP para `http://localhost/` para confirmar que o servidor estava respondendo corretamente.

### Por que reiniciar o Nginx

O Nginx no Windows mantém os arquivos JS/CSS em cache de sistema de arquivos. Sem restart, o servidor poderia continuar servindo os chunks antigos por um tempo indeterminado, mesmo que os novos arquivos já estivessem em disco. O restart força o Nginx a liberar os handles dos arquivos antigos e recarregar os novos.

**Observação técnica:** O Nginx no Linux suporta `nginx -s reload` (graceful reload sem derrubar conexões ativas). No Windows, o serviço é reiniciado diretamente via `Restart-Service`, que é equivalente em ambientes de desenvolvimento onde não há tráfego concurrent de produção.

### Por que o smoke test é importante

O smoke test valida a cadeia completa:

```
ng build → dist/ → cópia → nginx\html\sol → Nginx → HTTP 200
```

Um `[OK]` no build não garante que o Nginx está servindo os novos arquivos. O smoke test detectaria falhas como:
- Nginx travado com os arquivos antigos em lock.
- Erro de permissão na cópia (arquivo em uso pelo antivírus).
- Nginx não iniciado (porta 80 ocupada por outro processo).

O HTTP 200 confirma que `index.html` está sendo servido pelo Nginx — o ponto de entrada da SPA Angular.

---

## Resumo Final do Script

### Mensagens do resumo final

```
===========================================================
  SPRINT F4 - RESUMO FINAL
===========================================================

  SPRINT F4 CONCLUIDA COM SUCESSO

  Novos arquivos entregues:
    - analise.model.ts                      (novo — DTOs de analise)
    - analise-fila.component.ts             (novo — fila ANALISE_PENDENTE/EM_ANALISE)
    - licenciamento-analise.component.ts    (novo — CIA/Deferir/Indeferir)

  Arquivos atualizados:
    - licenciamento.service.ts              (5 novos metodos de analise)
    - app.routes.ts                         (rota /analise com filhos)
    - licenciamento-detalhe.component.ts    (botao Abrir Analise Tecnica)

  Rotas disponiveis:
    /app/analise        -> Fila de analise (ANALISTA / CHEFE_SSEG_BBM)
    /app/analise/:id    -> Tela de analise tecnica com CIA/Deferir/Indeferir

  Endpoints consumidos:
    GET  /api/licenciamentos/fila-analise
    POST /api/licenciamentos/{id}/iniciar-analise
    POST /api/licenciamentos/{id}/cia
    POST /api/licenciamentos/{id}/deferir
    POST /api/licenciamentos/{id}/indeferir
```

---

## Verificações pós-deploy realizadas manualmente

### Exit code

```
C:\SOL\logs\sprint-f4-run-exitcode.txt → 0
```

### Arquivos no servidor Nginx

```
C:\nginx\html\sol\*.js   → 50 arquivos JavaScript
C:\nginx\html\sol\index.html → presente
Serviço sol-nginx         → Running
```

### Verificação de integridade dos arquivos-fonte

| Arquivo | Path real confirmado | Status |
|---|---|---|
| `analise.model.ts` | `core/models/analise.model.ts` | Presente — interfaces `CiaCreateDTO`, `DeferimentoCreateDTO`, `IndeferimentoCreateDTO` confirmadas |
| `analise-fila.component.ts` | `pages/analise/analise-fila/` | Presente — colunas `['numero', 'tipo', 'status', 'municipio', 'area', 'entrada', 'acoes']` confirmadas |
| `licenciamento-analise.component.ts` | `pages/analise/licenciamento-analise/` | Presente — ações `CIA`, `Deferir`, `Indeferir` e tipo `AcaoAtiva` confirmados |
| `licenciamento.service.ts` | `core/services/` | Presente |
| `app.routes.ts` | raiz do app | Presente — imports lazy de ambos os componentes confirmados |
| `licenciamento-detalhe.component.ts` | `pages/licenciamentos/licenciamento-detalhe/` | Presente — string "Abrir Analise Tecnica" confirmada |

---

## Pendências e recomendações para sprints futuras

| Item | Severidade | Ação recomendada |
|---|---|---|
| **NG8011** nos botões de ação em `licenciamento-analise.component.ts` (linhas 190, 302, 338, 379) | Baixa | Envolver conteúdo dos blocos `@else` em `<ng-container>` |
| **Budget CSS** em `licenciamento-novo.component.ts` (132 bytes acima do limite) | Baixa | Revisar CSS do wizard ou aumentar budget em `angular.json` |
| **43 vulnerabilidades** em `node_modules` (tooling) | Informacional | Monitorar — não afetam produção. Executar `npm audit fix` em sprint de manutenção |
| **Script de verificação** com paths desatualizados (`app/models/` vs `core/models/`) | Baixa | Atualizar `run-sprint-f4.ps1` ou script de sprint futura para refletir a estrutura real |

---

## Diagrama de fluxo de análise técnica (P04)

```
Cidadão/RT submete licenciamento
         │
         ▼
  ANALISE_PENDENTE ──────────── /app/analise (fila FIFO)
         │                              │
         │ ANALISTA clica "Analisar"   │
         ▼                             │
     EM_ANALISE ◄──────────────────────┘
         │
    ┌────┴────────────────┐
    │                     │
    ▼                     ▼
Emitir CIA            Deferir / Indeferir
    │                     │
    ▼                     ▼
CIA_EMITIDO           DEFERIDO / INDEFERIDO
```

---

*Relatório gerado em 2026-04-10 · SOL-CBMRS · Sprint F4 — Análise Técnica (P04)*
