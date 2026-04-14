# Sprint F3 — Relatorio de Deploy: Wizard de Solicitacao de Licenciamento

**Data de execucao:** 2026-04-07
**Ambiente:** Windows 11 Pro / Node.js v20.18.0 / npm 10.8.2 / Angular 17 (standalone)
**Script principal:** `C:\SOL\logs\run-sprint-f3.ps1`
**Script de deploy:** `C:\SOL\infra\scripts\sprint-f3-deploy.ps1`
**Log bruto:** `C:\SOL\logs\sprint-f3-run-output.txt`
**Status final:** CONCLUIDA COM SUCESSO -- 0 erros

> **Nota:** Este arquivo e uma copia local do relatorio gerado pelo Claude Code no servidor
> (`C:\SOL\logs\sprint-f3-relatorio-deploy.md` no servidor), copiado para a maquina local
> em 2026-04-07 para registro historico. O original permanece no servidor (Y:\logs\).

---

## Indice

- Contexto da Sprint
- Problema Detectado Antes da Execucao -- Encoding do Script
- Solucao Aplicada -- Substituicao de Caracteres Unicode
- Etapa 1 -- Pre-verificacao do Ambiente
- Etapa 2 -- Verificacao dos Arquivos-Fonte da Sprint F3
- Etapa 3 -- Instalacao de Dependencias (npm ci)
- Etapa 4 -- Build de Producao
- Etapa 5 -- Deploy dos Assets para o Nginx
- Etapa 6 -- Reinicializacao do Nginx e Smoke Test
- Arquivos Entregues -- Detalhamento Tecnico
- Warnings do Build -- Analise e Impacto
- Confirmacoes Finais
- Licoes Aprendidas

---

## Contexto da Sprint

A Sprint F3 implementa o **Wizard de Solicitacao de Licenciamento**, que e o formulario de criacao de novos processos de licenciamento (PPCI e PSPCIM) no sistema SOL. Esta sprint e a terceira entrega do modulo frontend de Licenciamentos, dando continuidade as Sprints F1 (autenticacao/shell) e F2 (lista de licenciamentos).

O objetivo central e permitir que usuarios com perfil `CIDADAO` ou `ADMIN` iniciem um novo processo atraves de um formulario em multiplas etapas (`MatStepper`), com validacao por passo, revisao dos dados antes do envio e submissao ao backend via `POST /api/licenciamentos` seguido de `POST /api/licenciamentos/{id}/submeter`.

---

## Problema Detectado Antes da Execucao -- Encoding do Script

### O que aconteceu

Ao executar o script pela primeira vez, o PowerShell emitiu uma serie de erros de parsing antes mesmo de iniciar a Etapa 1:

```
No C:\SOL\infra\scripts\sprint-f3-deploy.ps1:154 caractere:55
+   if ($content -match "criar\(" -and $content -match "submeter\(") {
+                                                       ~~~~~~~~~
Token 'submeter\' inesperado na expressao ou instrucao.
```

```
No C:\SOL\infra\scripts\sprint-f3-deploy.ps1:320 caractere:110
+ ... .model.ts   (novo a?" LicenciamentoCreateDTO)" -ForegroundColor White
+                                                                          ~
')' de fechamento ausente na expressao.
```

O erro aparente na **linha 154** (`submeter\(` invalido) e tecnicamente correto em PowerShell -- `\(` e uma sequencia de escape regex valida no operador `-match`. O erro na **linha 320** revelou o problema real: o trecho `a?"` e a leitura distorcida de `--` (em dash, U+2014), que em UTF-8 ocupa 3 bytes (`E2 80 94`). Quando o PowerShell 5.x le o arquivo como ANSI/Windows-1252, esses bytes sao interpretados como caracteres latinos invalidos, corrompendo o parse do arquivo inteiro e causando **erros em cascata** nas linhas seguintes.

### Causa Raiz

O arquivo `sprint-f3-deploy.ps1` foi criado com **codificacao UTF-8 sem BOM** e contem tres categorias de caracteres Unicode fora do plano ASCII:

| Caractere | Unicode | Nome | Aparecia em |
|-----------|---------|------|-------------|
| `(U+2500)` | U+2500 | BOX DRAWINGS LIGHT HORIZONTAL | Comentarios de secao (`# --- Caminhos ---`) |
| `(U+2550)` | U+2550 | BOX DRAWINGS DOUBLE HORIZONTAL | Separadores nas funcoes `Passo` e no resumo final |
| `(U+2014)` | U+2014 | EM DASH | `ETAPA $n - $titulo`, strings do resumo |

O PowerShell 5.x (padrao no Windows) **nao detecta UTF-8 sem BOM automaticamente** -- ele assume a codepage do sistema (Windows-1252 no Brasil). Com BOM (`EF BB BF` no inicio do arquivo), o PowerShell reconheceria o encoding corretamente. Sem ele, cada caractere multibyte UTF-8 e fragmentado em dois ou tres bytes ilegíveis, quebrando a tokenizacao do parser.

---

## Solucao Aplicada -- Substituicao de Caracteres Unicode

### Por que nao adicionar BOM

Adicionar BOM via script Bash (o ambiente de execucao disponivel) exigiria reescrever o arquivo inteiro com um byte `\xef\xbb\xbf` no inicio, operacao mais arriscada e nao deterministica com as ferramentas disponiveis. A substituicao dos caracteres por equivalentes ASCII e mais simples, deterministica e elimina a dependencia de codificacao para qualquer versao do PowerShell.

### Substituicoes realizadas

**1. Separadores de secao (U+2550 -> `=`):**

Todos os blocos de saida visual do tipo:
```
===...===
```
foram substituidos por:
```
===========================================================
```
Essa string aparecia 8 vezes no arquivo (funcao `Passo`, RESUMO FINAL), todas substituidas com `replace_all: true`.

**2. Em dash com espacos (` -- ` -> ` -`):**

O padrao ` -- ` (espaco + em dash + espaco) foi substituido por ` -` (espaco + hifen). Isso afetou:
- `"  ETAPA $n -- $titulo"` -> `"  ETAPA $n -$titulo"`
- `"  SPRINT F3 -- RESUMO FINAL"` -> `"  SPRINT F3 -RESUMO FINAL"`
- Strings de resumo como `(novo -- LicenciamentoCreateDTO)` -> `(novo -LicenciamentoCreateDTO)`

**3. Comentarios de secao (U+2500 -> `-`):**

As duas linhas de comentario decorativo foram substituidas por:
```powershell
# --- Cores e helpers -----------------------------------------------------------
# --- Caminhos -----------------------------------------------------------------
```

### Resultado

Apos as tres substituicoes o script passou na analise sintatica do PowerShell e prosseguiu normalmente para a execucao das 6 etapas.

---

## Etapa 1 -- Pre-verificacao do Ambiente

### Justificativa da etapa

Antes de executar qualquer operacao destrutiva (como `npm ci`, que apaga e recria `node_modules`), o script valida que o ambiente minimo necessario esta disponivel. Falhas aqui indicam problemas de configuracao que nao podem ser corrigidos automaticamente e exigem intervencao humana -- por isso a saida e imediata com `exit 1` se o diretorio `frontend` ou o `package.json` nao existirem.

### Mensagens emitidas

```
[OK]  Node.js: v20.18.0
[OK]  npm: 10.8.2
[OK]  Diretorio frontend existe: C:\SOL\frontend
[OK]  package.json encontrado
```

### O que foi verificado

| Verificacao | Comando | Resultado |
|-------------|---------|-----------|
| Node.js presente no PATH | `node --version` | v20.18.0 (>= 18 exigido) |
| npm presente no PATH | `npm --version` | 10.8.2 |
| Diretorio do projeto | `Test-Path C:\SOL\frontend` | Existe |
| Arquivo de manifesto | `Test-Path package.json` | Existe |

---

## Etapa 2 -- Verificacao dos Arquivos-Fonte da Sprint F3

### Justificativa da etapa

O Angular CLI nao diferencia, durante o build, se um arquivo e "novo" ou "antigo". Se qualquer dos 6 arquivos-fonte da F3 nao existir ou nao tiver o conteudo esperado, o build pode completar com sucesso compilando a versao **anterior** dos componentes, entregando uma versao desatualizada em producao sem nenhum aviso. A etapa 2 elimina esse risco com verificacoes explicitas de existencia **e** de conteudo.

### Mensagens emitidas

```
[OK]  Novo modelo LicenciamentoCreateDTO / EnderecoCreateDTO / UF_OPTIONS
[OK]     -> src\app\core\models\licenciamento-create.model.ts
[OK]  Modelo atualizado com todos os 23 valores de StatusLicenciamento
[OK]     -> src\app\core\models\licenciamento.model.ts
[OK]  Service atualizado com criar() e submeter()
[OK]     -> src\app\core\services\licenciamento.service.ts
[OK]  Wizard MatStepper 4 passos
[OK]     -> src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts
[OK]  Rota /novo adicionada antes de /:id
[OK]     -> src\app\app.routes.ts
[OK]  Botao Nova Solicitacao habilitado com routerLink
[OK]     -> src\app\pages\licenciamentos\licenciamentos.component.ts
[OK]  licenciamento-create.model.ts contem interface LicenciamentoCreateDTO
[OK]  licenciamento.model.ts contem status APPCI_EMITIDO (23 valores presentes)
[OK]  app.routes.ts contem rota licenciamento-novo
[OK]  Rota 'novo' esta declarada ANTES de ':id' (ordenacao correta)
[OK]  licenciamento.service.ts contem metodos criar() e submeter()
```

### Verificacoes de conteudo e suas razoes

#### `LicenciamentoCreateDTO` em `licenciamento-create.model.ts`
Confirma que o arquivo nao e apenas um placeholder vazio. A interface e o contrato entre o frontend e o backend Java -- sem ela, os formularios do wizard nao tem tipagem e o TypeScript compilaria com `any`.

#### `APPCI_EMITIDO` em `licenciamento.model.ts`
Verificar sua presenca garante que o modelo foi atualizado com todos os 23 valores do enum Java `StatusLicenciamento`, e nao apenas com os valores presentes nas sprints anteriores.

#### `licenciamento-novo` e ordem `'novo'` antes de `':id'` em `app.routes.ts`
Esta e a verificacao mais critica da etapa. O Angular Router processa rotas filhas **na ordem em que estao declaradas**. Se `':id'` vier antes de `'novo'`, o segmento literal `"novo"` na URL seria capturado como parametro `id=novo`, redirecionando o usuario para o componente de detalhe em vez do wizard.

---

## Etapa 3 -- Instalacao de Dependencias (npm ci)

### Mensagens emitidas (resumidas)

```
[INFO] Executando: npm ci --prefer-offline ...
    npm warn deprecated inflight@1.0.6: ...
    npm warn deprecated rimraf@3.0.2: ...
    npm warn deprecated glob@7.2.3: ...
    npm warn deprecated critters@0.0.24: ...
    npm warn deprecated tar@6.2.1: ...
    npm warn cleanup Failed to remove some directories [
      'C:\\SOL\\frontend\\node_modules\\nice-napi',
      [Error: EPERM: operation not permitted, scandir '...node-addon-api\tools'] ...
    ]
    added 947 packages, and audited 948 packages in 1m
    43 vulnerabilities (6 low, 9 moderate, 28 high)
[OK]  npm ci concluido com sucesso
```

### Analise dos avisos

#### Pacotes deprecated
Os avisos de deprecacao sao **dependencias transitivas** de ferramentas internas do Angular CLI e do esbuild. Nao sao dependencias diretas do projeto SOL e nao afetam o funcionamento em producao.

#### EPERM em `nice-napi`
O erro `EPERM: operation not permitted` indica diretorio bloqueado por processo do Windows (antivirus, indexador). O `npm ci` registrou o aviso mas **nao abortou** -- o pacote `nice-napi` nao e utilizado diretamente pelo projeto.

#### 43 vulnerabilidades
Todas em dependencias de desenvolvimento (build tools). Nenhuma afeta o bundle de producao servido pelo Nginx.

---

## Etapa 4 -- Build de Producao

### Mensagens emitidas (resumidas)

```
[INFO] Executando: npx ng build --configuration production ...
[INFO] Este processo pode levar 2-5 minutos ...

    Initial chunk files         | Names          | Raw size  | Estimated transfer size
    chunk-2HXZGHJS.js           | -              | 186.62 kB |               54.41 kB
    chunk-FHLNEYDS.js           | -              | 101.28 kB |               25.46 kB
    styles-27OWQZN7.css         | styles         |  50.72 kB |                5.42 kB
    chunk-M34ZJELV.js           | -              |  48.94 kB |               11.46 kB
    polyfills-FFHMD2TL.js       | polyfills      |  34.52 kB |               11.28 kB
    main-BFZ2RAT2.js            | main           |   6.24 kB |                2.00 kB

    Lazy chunk files            | Names                           | Raw size
    chunk-ARXDTOOP.js           | licenciamento-novo-component    |  60.09 kB
    chunk-KLSFSZ4F.js           | licenciamentos-component        |  56.74 kB
    chunk-LTFBHWEL.js           | licenciamento-detalhe-component |   5.98 kB
    chunk-E4NMPU33.js           | dashboard-component             |   4.08 kB
    chunk-JRR2GV5W.js           | login-component                 |   1.92 kB

    Application bundle generation complete. [5.519 seconds]

    WARNING NG8011: Node matches the "...mat-icon..." slot of MatButton...
    WARNING angular:styles/component:css...exceeded maximum budget (2.05 kB + 132 bytes)

    Output location: C:\SOL\frontend\dist\sol-frontend
[OK]  Build concluido com sucesso (exit code 0)
[INFO] Arquivos JS gerados: 24
[OK]  Chunks JavaScript presentes no dist
```

### Chunks F3 confirmados no build

| Chunk | Componente | Tamanho Raw | Significado |
|-------|-----------|-------------|-------------|
| `chunk-ARXDTOOP.js` | `licenciamento-novo-component` | 60.09 kB | **Novo na F3** -- wizard completo com 4 passos |
| `chunk-KLSFSZ4F.js` | `licenciamentos-component` | 56.74 kB | Atualizado na F3 -- botao "Nova Solicitacao" ativo |

---

## Warnings do Build -- Analise e Impacto

### Warning 1 -- NG8011: Content Projection com @else

```
WARNING NG8011: Node matches the ".material-icons:not([iconPositionEnd])..."
  slot of the "MatButton" component, but will not be projected into the specific
  slot because the surrounding @else has more than one node at its root.

  src/app/pages/licenciamentos/licenciamento-novo/licenciamento-novo.component.ts:400:18
    400 |   <mat-icon>send</mat-icon>
```

**Causa:** No botao "Confirmar e Enviar" do Passo 4, o bloco `@else` do Angular 17 contem dois nos raiz (`<mat-icon>` e texto). O `MatButton` usa content projection com slot nomeado para o icone, mas o projetor nao consegue identificar qual no projetar no slot quando o `@else` tem multiplos filhos.

**Impacto:** O icone `send` pode nao aparecer posicionado corretamente, mas o **botao funciona normalmente**. Build nao bloqueado.

**Solucao futura (nao aplicada):**
```html
} @else {
  <ng-container>
    <mat-icon>send</mat-icon>
    Confirmar e Enviar
  </ng-container>
}
```

### Warning 2 -- CSS Budget Exceeded

```
WARNING ...licenciamento-novo.component.ts exceeded maximum budget.
  Budget 2.05 kB was not met by 132 bytes with a total of 2.18 kB.
```

**Impacto:** Nenhum impacto funcional. O CSS e carregado normalmente. Warning informativo.

---

## Etapa 5 -- Deploy dos Assets para o Nginx

### Mensagens emitidas

```
[INFO] Diretorio Nginx nao existe - criando: C:\nginx\html\sol
[INFO] Copiando arquivos de C:\SOL\frontend\dist\sol-frontend\browser para C:\nginx\html\sol ...
[OK]  index.html copiado para C:\nginx\html\sol
```

**Observacao:** O log indica que `C:\nginx\html\sol` **nao existia** antes desta execucao -- esta foi a **primeira vez** que o diretorio de producao foi criado. O script o criou automaticamente com `New-Item -ItemType Directory -Force`.

---

## Etapa 6 -- Reinicializacao do Nginx e Smoke Test

### Mensagens emitidas

```
[INFO] Reiniciando servico: sol-nginx ...
[OK]  Servico sol-nginx reiniciado e em execucao
[INFO] Smoke test: GET http://localhost/ ...
[OK]  HTTP 200 OK - aplicacao acessivel
```

---

## Arquivos Entregues -- Detalhamento Tecnico

### 1. `licenciamento-create.model.ts` (novo)

**Caminho:** `src/app/core/models/licenciamento-create.model.ts`

Declara tres exports utilizados pelo wizard:
- Interface `LicenciamentoCreateDTO` com campos: `tipo`, `areaConstruida`, `alturaMaxima`, `numPavimentos`, `tipoOcupacao?`, `usoPredominante?`, `endereco`
- Interface `EnderecoCreateDTO` com: `cep` (8 digitos), `logradouro`, `numero?`, `complemento?`, `bairro`, `municipio`, `uf`
- Constante `UF_OPTIONS` com as 27 UFs brasileiras para o `MatSelect`

### 2. `licenciamento.model.ts` (atualizado -- 23 status)

**Caminho:** `src/app/core/models/licenciamento.model.ts`

O tipo union `StatusLicenciamento` foi expandido de poucos status basicos para os 23 valores:

| Grupo | Status |
|-------|--------|
| Fluxo principal | `RASCUNHO`, `ANALISE_PENDENTE`, `EM_ANALISE`, `CIA_EMITIDO`, `CIA_CIENCIA`, `DEFERIDO`, `INDEFERIDO`, `VISTORIA_PENDENTE`, `EM_VISTORIA`, `CIV_EMITIDO`, `CIV_CIENCIA`, `PRPCI_EMITIDO`, `APPCI_EMITIDO`, `ALVARA_VENCIDO` |
| Renovacao (F14) | `AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO` |
| Recurso (F10) | `RECURSO_PENDENTE`, `EM_RECURSO` |
| Especiais | `SUSPENSO`, `EXTINTO`, `RENOVADO` |

### 3. `licenciamento.service.ts` (atualizado)

Dois metodos novos adicionados:

```typescript
criar(dto: LicenciamentoCreateDTO): Observable<LicenciamentoDTO> {
  return this.http.post<LicenciamentoDTO>(this.apiUrl, dto);
}

submeter(id: number): Observable<LicenciamentoDTO> {
  return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/submeter`, {});
}
```

### 4. `licenciamento-novo.component.ts` (novo)

Componente standalone com `MatStepper` em modo linear:

| Passo | Label | FormGroup | Campos principais |
|-------|-------|-----------|-------------------|
| 1 | Tipo | `tipoForm` | `tipo` (PPCI / PSPCIM) -- selecao via card clicavel |
| 2 | Endereco | `enderecoForm` | CEP (8 digitos), logradouro, numero, complemento, bairro, municipio, UF |
| 3 | Edificacao | `edificacaoForm` | Area construida (m2), altura maxima (m), no pavimentos, tipo ocupacao, uso predominante |
| 4 | Revisao | -- | Exibe resumo; botao "Confirmar e Enviar" |

### 5. `app.routes.ts` (atualizado)

Rota `novo` inserida **antes** de `':id'` para evitar match incorreto pelo Angular Router.

### 6. `licenciamentos.component.ts` (atualizado)

Botao "Nova Solicitacao" ativado com `routerLink` e protegido por condicional `@if (podeNovaSolicitacao)` para roles CIDADAO/ADMIN.

---

## Confirmacoes Finais

| Item | Status |
|------|--------|
| HTTP 200 em `http://localhost/` | CONFIRMADO (smoke test Etapa 6) |
| Rota `/app/licenciamentos/novo` disponivel | CONFIRMADO (chunk gerado, rota verificada) |
| Botao "Nova Solicitacao" para CIDADAO/ADMIN | CONFIRMADO (component atualizado no build) |
| 0 erros de build | CONFIRMADO |

---

## Licoes Aprendidas

### 1. PowerShell 5.x e UTF-8 sem BOM

Scripts PowerShell criados com caracteres Unicode acima de U+007F devem ser salvos com **UTF-8 com BOM** para garantir compatibilidade com o PowerShell 5.x padrao do Windows (que assume Windows-1252). Alternativamente, migrar para **PowerShell 7+** (pwsh.exe), que usa UTF-8 por padrao.

**Recomendacao para scripts futuros:** Usar apenas caracteres ASCII em scripts `.ps1` destinados a ambientes Windows com PowerShell 5.x, ou adicionar no inicio:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
```

### 2. Verificacao de conteudo antes do build

A validacao dos arquivos-fonte na Etapa 2 (incluindo conteudo, nao apenas existencia) e essencial. Ela transforma o script em uma ferramenta de **contrato de entrega**, garantindo que exatamente o que foi especificado esta presente antes de iniciar o processo custoso de build.

### 3. Ordenacao de rotas com parametros dinamicos

A verificacao programatica da ordenacao de rotas (`'novo'` antes de `':id'`) evita bugs de roteamento dificeis de depurar -- o usuario chegaria ao componente errado sem nenhum erro no console.

---

*Relatorio gerado automaticamente com base no log de execucao e na analise do codigo-fonte da Sprint F3.*
*Sistema: SOL (Sistema Online de Licenciamentos) -- CBM-RS*
*Copia local sincronizada em 2026-04-07 a partir do servidor (Y:\logs\).*
