# Sprint F2 — Modulo de Licenciamentos: Instrucoes de Execucao

**Sistema:** SOL — Sistema Online de Licenciamento | CBM-RS
**Sprint:** F2 (segunda sprint frontend)
**Pre-requisito:** Sprint F1 concluida com sucesso (Angular Material, shell, guards, build pipeline)
**Data:** 2026-04-06

---

## Visao Geral

A Sprint F2 implementa o **Modulo de Licenciamentos** — a primeira tela de negocio real do sistema SOL apos a fundacao tecnica estabelecida pela Sprint F1. Ela entrega ao usuario autenticado com perfil CIDADAO (ou qualquer outro perfil) a capacidade de visualizar seus processos de licenciamento PPCI e PSPCIM, com lista paginada e tela de detalhe.

Esta sprint nao adiciona novos pacotes npm. Todos os modulos Angular Material necessarios (MatTable, MatPaginator, MatCard, MatButton, MatIcon, MatTooltip) ja estavam instalados na Sprint F1 como parte do `@angular/material: ^18.2.0`.

---

## Arquivos produzidos pela Sprint F2

### Novos arquivos Angular

| Arquivo | Descricao |
|---|---|
| `src/app/core/models/licenciamento.model.ts` | Interfaces TypeScript e constantes de label/cor por status |
| `src/app/core/services/licenciamento.service.ts` | Service HTTP para os endpoints `/api/licenciamentos/meus` e `/api/licenciamentos/{id}` |
| `src/app/pages/licenciamentos/licenciamentos.component.ts` | Tela de lista paginada de licenciamentos do usuario |
| `src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts` | Tela de detalhe de um licenciamento (dados da edificacao, endereco, prazos) |

### Arquivos modificados

| Arquivo | O que mudou |
|---|---|
| `src/app/app.routes.ts` | Rota `/licenciamentos` substituida: de `NotFoundComponent` (placeholder F1) para estrutura com filhos reais (`LicenciamentosComponent` e `LicenciamentoDetalheComponent`) |

### Script de deploy

| Arquivo | Localizacao |
|---|---|
| `sprint-f2-deploy.ps1` | `C:\SOL\infra\scripts\` (local) e `C:\SOL\infra\scripts\` (servidor via Y:\) |

---

## Sequencia de execucao

### Fase 1 — Verificar que os arquivos estao no servidor

Os arquivos desta sprint foram escritos diretamente no drive Y:\ (mapeamento de rede para `C:\SOL` no servidor). Nao e necessario executar um script de copia separado.

Para confirmar que todos os arquivos chegaram ao servidor, execute no PowerShell local:

```powershell
@(
  "Y:\frontend\src\app\core\models\licenciamento.model.ts",
  "Y:\frontend\src\app\core\services\licenciamento.service.ts",
  "Y:\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts",
  "Y:\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts",
  "Y:\frontend\src\app\app.routes.ts",
  "Y:\infra\scripts\sprint-f2-deploy.ps1"
) | ForEach-Object { [PSCustomObject]@{ Arquivo = $_; Presente = (Test-Path $_) } } | Format-Table
```

Todos os seis arquivos devem retornar `True`.

### Fase 2 — Executar o deploy no servidor

Acesse o servidor e execute (ou passe ao Claude Code no servidor):

```powershell
powershell -ExecutionPolicy Bypass -File C:\SOL\infra\scripts\sprint-f2-deploy.ps1
```

Ou, para capturar o output em arquivo de log:

```powershell
$out = "C:\SOL\logs\sprint-f2-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f2-deploy.ps1" *>&1 | Tee-Object -FilePath $out
```

---

## Descricao detalhada de cada etapa do script

### Etapa 1 — Verificacao de pre-requisitos

**O que faz:** Verifica que Node.js, npm e o servico `SOL-Nginx` estao disponiveis no servidor.

**Por que e necessaria:** A ausencia de qualquer um desses elementos impede todas as etapas seguintes. O script aborta imediatamente se encontrar erros aqui, evitando falhas silenciosas mais adiante.

**O que e esperado:**
```
[OK] Node.js: v20.x.x
[OK] npm: v10.x.x
[OK] Diretorio frontend: C:\SOL\frontend
[OK] Servico SOL-Nginx encontrado (Status: Running)
```

---

### Etapa 2 — Verificacao dos arquivos-fonte da Sprint F2

**O que faz:** Verifica que os quatro novos arquivos TypeScript existem em disco e que o `app.routes.ts` ja foi atualizado (contem a string `licenciamentos.component`, indicando que o placeholder foi substituido).

**Por que e necessaria:** O build Angular falha silenciosamente (ou gera a aplicacao errada) se os arquivos estiverem faltando ou se o `app.routes.ts` ainda apontar para `NotFoundComponent`. Esta etapa detecta o problema antes de iniciar o build de 3-5 minutos.

**O que e esperado:**
```
[OK] Presente: licenciamento.model.ts
[OK] Presente: licenciamento.service.ts
[OK] Presente: licenciamentos.component.ts
[OK] Presente: licenciamento-detalhe.component.ts
[OK] Presente: app.routes.ts
[OK] app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent
```

---

### Etapa 3 — npm install

**O que faz:** Executa `npm install` no diretorio `C:\SOL\frontend`.

**Por que e necessaria:** Mesmo sem novos pacotes, o `npm install` garante que o `node_modules` esta integro e sincronizado com o `package-lock.json`. Em um servidor Windows, eventuais inconsistencias de symlinks ou permissoes sao corrigidas automaticamente por esta etapa.

**Nota tecnica:** O script usa `$ErrorActionPreference = "Continue"` durante o npm install e verifica `$LASTEXITCODE` em vez de `try/catch`. Isso evita que avisos de deprecacao emitidos pelo npm no stderr sejam tratados erroneamente como erros fatais pelo PowerShell.

**O que e esperado:**
```
[OK] npm install concluido
```

---

### Etapa 4 — Build Angular (modo producao)

**O que faz:** Executa `npm run build:prod` (equivale a `ng build --configuration production`) no diretorio do frontend.

**Por que e necessaria:** O build de producao realiza: compilacao TypeScript com verificacao de tipos, tree-shaking (remocao de codigo nao utilizado), minificacao de JavaScript e CSS, e geracao dos arquivos estaticos finais em `C:\SOL\frontend\dist\sol-frontend\browser\`.

**O que e esperado:**
```
[OK] Build Angular concluido
[OK] Dist gerado: C:\SOL\frontend\dist\sol-frontend\browser\ (N arquivos)
```

Se ocorrer erro de compilacao TypeScript, o script exibe o codigo de saida e aborta. Os erros mais comuns e suas causas:

| Erro TypeScript | Causa provavel |
|---|---|
| `Cannot find module '../../core/services/licenciamento.service'` | Arquivo ausente ou caminho errado |
| `Property 'getMeus' does not exist` | Versao errada do service (verificar conteudo do arquivo) |
| `Type 'PageEvent' is not assignable` | MatPaginatorModule nao importado no componente |
| `signal is not exported from '@angular/core'` | Angular < 17 (deve ser 18) |

---

### Etapa 5 — Atualizar nginx.conf e reiniciar SOL-Nginx

**O que faz:** Copia o arquivo `C:\SOL\infra\nginx\nginx.conf` para o diretorio de configuracao do Nginx instalado (`nginx-1.26.2\conf\`), testa a sintaxe com `nginx -t` e reinicia o servico Windows `SOL-Nginx`.

**Por que e necessaria:** O Nginx serve os arquivos estaticos do Angular gerados pelo build. Sem reinicializar o servico, o Nginx continuaria servindo o build anterior (Sprint F1). O `nginx.conf` da Sprint F1 ja inclui a regra `try_files $uri /index.html` necessaria para o roteamento HTML5 do Angular — portanto esta etapa e essencialmente uma confirmacao de que a configuracao esta correta.

**O que e esperado:**
```
[OK] nginx.conf copiado para C:\SOL\infra\nginx\nginx-1.26.2\conf
[OK] Sintaxe nginx.conf: OK
[OK] Servico SOL-Nginx: RUNNING
```

---

### Etapa 6 — Verificacao HTTP

**O que faz:** Faz duas requisicoes HTTP:
1. `GET http://localhost:80/` — verifica que o Nginx esta respondendo com HTTP 200 e que o HTML contem a string `SOL` (indicando que o Angular foi carregado)
2. `GET http://localhost:80/api/actuator/health` — verifica que o proxy reverso do Nginx continua encaminhando `/api/` para o backend Spring Boot

**Por que e necessaria:** Confirma que o deploy completo funcionou end-to-end, nao apenas que o build foi gerado. Uma falha aqui pode indicar: arquivo `index.html` nao copiado corretamente, Nginx nao reiniciado, ou backend inativo.

**O que e esperado:**
```
[OK] http://localhost:80/ -- HTTP 200
[OK] Conteudo HTML contem 'SOL' -- Angular SPA carregado
[OK] http://localhost:80/api/actuator/health -- Backend UP
```

---

## Arquitetura da Sprint F2

### Fluxo de dados — Lista de licenciamentos

```
Navegador (CIDADAO autenticado)
    |
    | Acessa /app/licenciamentos
    v
Angular Router
    |
    | authGuard: token JWT valido? (OAuthService)
    | roleGuard: tem role CIDADAO/ANALISTA/INSPETOR/ADMIN/CHEFE_SSEG_BBM?
    v
LicenciamentosComponent.ngOnInit()
    |
    | LicenciamentoService.getMeus(page=0, size=10)
    v
HttpClient -> GET /api/licenciamentos/meus?page=0&size=10&sort=id,desc
    |
    | Header: Authorization: Bearer <token JWT>
    | (injetado automaticamente pelo OAuthModule via provideOAuthClient)
    v
Backend Spring Boot -> LicenciamentoController.findMeus()
    |
    | Extrai keycloakId do JWT, busca licenciamentos do usuario
    v
PageResponse<LicenciamentoDTO> (JSON)
    |
    v
LicenciamentosComponent: exibe tabela MatTable + MatPaginator
```

### Estrutura de rotas apos Sprint F2

```
/                          → redirect para /app/dashboard
/login                     → LoginComponent (publica)
/app                       → ShellComponent (authGuard)
  /dashboard               → DashboardComponent
  /licenciamentos          → LicenciamentosComponent        ← NOVO (F2)
  /licenciamentos/:id      → LicenciamentoDetalheComponent  ← NOVO (F2)
  /analise                 → NotFoundComponent (placeholder F4)
  /vistorias               → NotFoundComponent (placeholder F5)
  /usuarios                → NotFoundComponent (placeholder F7)
  /relatorios              → NotFoundComponent (placeholder F9)
/**                        → NotFoundComponent (404)
```

### Palette de status dos licenciamentos

| Status | Label | Cor |
|---|---|---|
| RASCUNHO | Rascunho | Cinza (#9e9e9e) |
| ANALISE_PENDENTE | Analise Pendente | Laranja (#f39c12) |
| EM_ANALISE | Em Analise | Azul (#3498db) |
| APROVADO | Aprovado | Verde (#27ae60) |
| REPROVADO | Reprovado | Vermelho (#cc0000) |
| CIA_EMITIDO | CIA Emitido | Laranja escuro (#e67e22) |
| CIV_EMITIDO | CIV Emitido | Laranja escuro (#e67e22) |
| SUSPENSO | Suspenso | Roxo (#8e44ad) |
| EXTINTO | Extinto | Cinza escuro (#607d8b) |
| RECURSO_PENDENTE | Recurso Pendente | Verde-agua (#1abc9c) |

### Por que a rota `/licenciamentos` usa `children` sem `loadComponent` no pai

No Angular 18 com roteamento lazy, uma rota pode ter filhos sem ter um componente proprio. Neste caso, o `<router-outlet>` do `ShellComponent` (pai de `/app`) e que renderiza diretamente o filho ativo — seja a lista ou o detalhe. Isso evita a necessidade de um componente intermediario vazio apenas para conter um segundo `<router-outlet>`.

O `canActivate: [roleGuard]` declarado no pai (`/licenciamentos`) protege automaticamente todos os filhos, sem precisar repetir a declaracao em cada rota filha.

### Por que o token Bearer e injetado automaticamente

O `provideOAuthClient({ resourceServer: { allowedUrls: ['/api'], sendAccessToken: true } })` em `app.config.ts` registra um interceptor HTTP que, para toda requisicao cujo URL comece com `/api`, adiciona o header `Authorization: Bearer <token>`. O `LicenciamentoService` apenas usa o `HttpClient` normalmente — nao precisa gerenciar o token manualmente.

---

## Resultado esperado apos execucao bem-sucedida

Apos a conclusao do script com `0 erros`:

1. `http://localhost/app/licenciamentos` exibe a tabela de licenciamentos do usuario logado
2. Clicar no icone de olho em qualquer linha navega para `http://localhost/app/licenciamentos/{id}`
3. A tela de detalhe exibe quatro secoes: Identificacao, Dados da Edificacao, Endereco, Prazos
4. O botao "Voltar para a lista" retorna a `/app/licenciamentos`
5. O botao "Nova Solicitacao" aparece desabilitado com tooltip "Disponivel na Sprint F3"
6. Se o usuario nao tiver licenciamentos, exibe mensagem de lista vazia

---

## Solucao de problemas

### Erro: `NG0303: Can't bind to 'dataSource' that isn't a known property of 'table'`

**Causa:** `MatTableModule` nao foi importado no componente.
**Solucao:** Verificar o array `imports` em `licenciamentos.component.ts`.

### Erro: `NullInjectorError: No provider for HttpClient`

**Causa:** `provideHttpClient()` ausente em `app.config.ts`.
**Solucao:** Verificar se `app.config.ts` contem `provideHttpClient()` na lista de providers (foi adicionado na Sprint F1).

### HTTP 401 ao chamar `/api/licenciamentos/meus`

**Causa:** Token JWT nao esta sendo enviado ou expirou.
**Solucao:** Verificar `allowedUrls` em `app.config.ts` — deve conter `'/api'` ou o URL base da API.

### Rota `/app/licenciamentos` ainda exibe pagina 404

**Causa:** Build gerado antes da atualizacao do `app.routes.ts`, ou `app.routes.ts` nao foi atualizado corretamente.
**Solucao:** Verificar se `app.routes.ts` contem `licenciamentos.component` (Etapa 2 do script) e re-executar o build.

---

## Pre-requisitos

- [x] Sprint F1 concluida (Angular Material 18, shell, guards, nginx.conf, SOL-Nginx rodando)
- [x] SOL-Backend em execucao com endpoint `GET /api/licenciamentos/meus` funcional
- [x] Usuario de teste com role `CIDADAO` cadastrado no Keycloak realm `sol`
- [x] Drive Y:\ acessivel a partir da maquina local (para verificacao dos arquivos)

---

## Referencias

| Item | Localizacao |
|---|---|
| Script de deploy | `C:\SOL\infra\scripts\sprint-f2-deploy.ps1` |
| Model de licenciamento | `C:\SOL\frontend\src\app\core\models\licenciamento.model.ts` |
| Service HTTP | `C:\SOL\frontend\src\app\core\services\licenciamento.service.ts` |
| Componente lista | `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts` |
| Componente detalhe | `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` |
| Rotas atualizadas | `C:\SOL\frontend\src\app\app.routes.ts` |
| Log de deploy | `C:\SOL\logs\sprint-f2-deploy.log` (gerado no servidor) |
| Instrucoes Sprint F1 | `Instrucoes_SprintF1_Frontend_Fundacao.md` (mesma pasta) |
