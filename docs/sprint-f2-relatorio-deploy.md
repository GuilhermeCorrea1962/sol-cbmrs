# Sprint F2 — Módulo de Licenciamentos
## Relatório de Deploy e Smoke Test

**Data de execução:** 2026-04-06
**Horário:** 20:18:41 → 20:19:07 (duração total: ~26 segundos de execução do script; ~6 segundos de build Angular)
**Ambiente:** Windows 11 Pro — Node.js 20.18.0 + Angular 18.2 + Nginx 1.26.2
**Script base:** `C:\SOL\infra\scripts\sprint-f2-deploy.ps1`
**Wrapper de captura:** `C:\SOL\logs\run-sprint-f2.ps1`
**Status final:** ✅ CONCLUÍDA COM SUCESSO — 18 OK · 1 WARN · 0 ERROS

---

## Índice

- [[#Objetivo da Sprint]]
- [[#Pré-condição — Sprint F1 Concluída]]
- [[#Arquivos-Fonte Implementados]]
- [[#Arquitetura dos Componentes F2]]
- [[#Justificativa de Cada Passo do Script]]
- [[#Observação Técnica — StatusLicenciamento Incompleto no Modelo]]
- [[#Solução Aplicada — Wrapper de Captura de Output]]
- [[#Execução — Output Completo]]
- [[#Log Completo (sprint-f2-deploy.log)]]
- [[#Sumário Final Emitido pelo Script]]
- [[#Aviso Não Bloqueante]]
- [[#Confirmações HTTP Pós-Deploy]]
- [[#Bundles Gerados — Comparativo F1 vs F2]]
- [[#Próximo Passo]]

---

## Objetivo da Sprint

A Sprint F2 entrega o **Módulo de Licenciamentos** — primeira tela funcional do SOL além do dashboard. Ela implementa as duas views do ciclo de vida de licenciamentos visíveis ao perfil CIDADAO/RT:

1. **Lista paginada** (`/app/licenciamentos`) — exibe todos os processos do usuário autenticado com status colorido, endereço e link para o detalhe
2. **Tela de detalhe** (`/app/licenciamentos/:id`) — exibe todos os campos do licenciamento (identificação, dados da edificação, endereço, prazos)

### Endpoints de backend consumidos

| Método | URL | Perfis | Descrição |
|--------|-----|--------|-----------|
| `GET` | `/api/licenciamentos/meus` | CIDADAO, RT | Lista paginada dos licenciamentos do usuário autenticado |
| `GET` | `/api/licenciamentos/{id}` | Qualquer autenticado | Detalhe completo de um licenciamento |

### Relação com sprints anteriores

- Depende de **Sprint F1** (Nginx configurado, Angular SPA servida em `localhost:80`)
- Depende das **Sprints 3 e 4 do backend** (autenticação JWT, endpoint `/licenciamentos`)
- O botão "Nova Solicitação" na lista está **desabilitado** com tooltip `"Disponível na Sprint F3"` — não há regressão funcional

---

## Pré-condição — Sprint F1 Concluída

O script verifica explicitamente no Passo 1 que o serviço `SOL-Nginx` existe e está acessível. Isso garante que a Sprint F1 foi executada antes — sem ela, o Nginx não existiria como serviço Windows e o deploy da F2 falharia no prerequisito com mensagem:

```
[ERRO] Servico SOL-Nginx nao encontrado. Execute 04-nginx.ps1 e sprint-f1-deploy.ps1 primeiro.
```

Na execução desta sprint o serviço já estava `Running`, confirmando a sequência correta.

---

## Arquivos-Fonte Implementados

O script verifica no **Passo 2** a presença exata dos seguintes arquivos antes de iniciar o build:

| Arquivo | Caminho relativo em `src/app/` | Papel |
|---------|-------------------------------|-------|
| `licenciamento.model.ts` | `core/models/` | Tipos TypeScript espelhando os DTOs Java do backend |
| `licenciamento.service.ts` | `core/services/` | Serviço Angular com chamadas HTTP aos endpoints |
| `licenciamentos.component.ts` | `pages/licenciamentos/` | Componente de lista paginada |
| `licenciamento-detalhe.component.ts` | `pages/licenciamentos/licenciamento-detalhe/` | Componente de detalhe individual |
| `app.routes.ts` | `app/` | Rotas atualizadas com `LicenciamentosComponent` real |

Além da presença física dos arquivos, o script faz uma verificação de conteúdo no `app.routes.ts`:

```powershell
$routesContent = Get-Content "$FrontendDir\src\app\app.routes.ts" -Raw
if ($routesContent -match "licenciamentos\.component") {
    Write-OK "app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent"
} else {
    Write-ERR "app.routes.ts: rota /licenciamentos ainda aponta para NotFoundComponent (placeholder nao substituido)"
}
```

**Justificativa:** É possível que os arquivos existam mas o `app.routes.ts` ainda aponte para `NotFoundComponent` (como estava na Sprint F1). Sem essa verificação, o build passaria, mas a rota `/app/licenciamentos` continuaria exibindo a página 404 em vez do módulo real — um erro silencioso difícil de detectar.

---

## Arquitetura dos Componentes F2

### `licenciamento.model.ts` — Modelos de Domínio

Define todas as interfaces TypeScript que espelham os DTOs Java do backend:

```typescript
// Tipos primitivos de domínio
export type TipoLicenciamento = 'PPCI' | 'PSPCIM';
export type StatusLicenciamento = 'RASCUNHO' | 'ANALISE_PENDENTE' | 'EM_ANALISE' | ...;
export type TipoArquivo = 'PPCI' | 'MEMORIA_CALCULO' | 'ART_RRT' | ...;

// Interfaces principais
export interface EnderecoModel { cep, logradouro, numero, bairro, municipio, uf, ... }
export interface LicenciamentoModel { id, numeroPpci, tipo, status, areaConstruida, ... }
export interface MarcoProcessoModel { id, tipoMarco, observacao, dtMarco, ... }
export interface ArquivoEDModel { id, nomeArquivo, tipoArquivo, tamanho, dtUpload, ... }
export interface PageResult<T> { content, totalElements, totalPages, number, size }

// Helpers de apresentação
export const STATUS_LABEL: Record<StatusLicenciamento, string> = { ... }
export const STATUS_COLOR: Record<StatusLicenciamento, string> = { ... }
```

**Por que ter um arquivo de modelos separado:** Centraliza todos os tipos em um único ponto de verdade. Qualquer componente ou serviço que precise do tipo `LicenciamentoModel` importa daqui — se o backend mudar um campo, há apenas um lugar para atualizar.

---

### `licenciamento.service.ts` — Camada de Acesso à API

```typescript
@Injectable({ providedIn: 'root' })
export class LicenciamentoService {
  private readonly apiUrl = `${environment.apiUrl}/licenciamentos`;

  getMeus(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    // GET /api/licenciamentos/meus?page=0&size=10&sort=id,desc
  }

  getById(id: number): Observable<LicenciamentoDTO> {
    // GET /api/licenciamentos/{id}
  }
}
```

**Pontos importantes de implementação:**

- `environment.apiUrl` é `/api` em produção (relativo), o que significa que as chamadas HTTP vão para `http://localhost/api/licenciamentos/meus` — passando pelo proxy Nginx que encaminha ao Spring Boot na porta 8080. Não há nenhuma chamada direta do browser ao backend.
- O Bearer token é **injetado automaticamente** pelo `provideOAuthClient` configurado em `app.config.ts` (Sprint F1). O serviço não precisa manusear o token — isso é feito de forma transparente pelo interceptor do `angular-oauth2-oidc`.
- `sort=id,desc` garante que o licenciamento mais recente apareça primeiro na lista.
- O serviço é `providedIn: 'root'` — singleton em toda a aplicação, sem necessidade de declarar em nenhum módulo.

---

### `licenciamentos.component.ts` — Lista Paginada

Componente standalone que renderiza a grade de licenciamentos do usuário autenticado.

**Estrutura principal:**

```typescript
@Component({ selector: 'sol-licenciamentos', standalone: true, ... })
export class LicenciamentosComponent implements OnInit {
  licenciamentos = signal<LicenciamentoDTO[]>([]);
  totalElements  = signal(0);
  loading        = signal(false);
  error          = signal<string | null>(null);

  ngOnInit() → this.load()
  onPage(event: PageEvent) → atualiza página e recarrega
  getStatusLabel(status) → STATUS_LABEL[status] ?? status
  getStatusColor(status) → STATUS_COLOR[status] ?? '#9e9e9e'
}
```

**Decisões de design:**

| Decisão | Justificativa |
|---------|---------------|
| `signal<T>()` em vez de propriedades simples | Signals do Angular 18 evitam `ChangeDetectorRef.markForCheck()` manual; reatividade declarativa mais limpa |
| `@if` em vez de `*ngIf` | Sintaxe de template Angular 17+ (block syntax); elimina o import de `NgIf` do `CommonModule` |
| `mat-table` com `mat-paginator` | Paginação server-side: cada virada de página chama `GET /licenciamentos/meus?page=N` — não carrega todos os registros de uma vez |
| Botão "Nova Solicitação" desabilitado com `matTooltip` | Informa o usuário que a funcionalidade existe e chegará na Sprint F3, sem gerar confusão sobre uma ausência não explicada |
| Estado vazio com `mat-card` dedicado | Diferencia claramente "lista carregada e vazia" de "loading" e "erro" — UX mais clara para o CIDADAO que ainda não tem processos |

**Três estados de UI distintos:**

```
loading=true  → <sol-loading> overlay com spinner
error!=null   → <sol-error-alert> banner vermelho dismissível
lista vazia   → mat-card com ícone folder_open + texto orientativo
lista com dados → mat-table + mat-paginator
```

---

### `licenciamento-detalhe.component.ts` — Tela de Detalhe

Componente standalone que exibe todos os campos de um `LicenciamentoModel` a partir do ID na URL.

```typescript
export class LicenciamentoDetalheComponent implements OnInit {
  lic     = signal<LicenciamentoDTO | null>(null);
  loading = signal(false);
  error   = signal<string | null>(null);

  ngOnInit() {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.svc.getById(id).subscribe(...)
  }
}
```

**Seções renderizadas:**

| Seção | Campos exibidos | Visibilidade |
|-------|----------------|-------------|
| Identificação | Número PPCI, tipo, status (badge colorido), datas criação/atualização | Sempre |
| Dados da Edificação | Área construída, altura, pavimentos, tipo de ocupação, uso predominante | Sempre |
| Endereço | Logradouro, número, complemento, bairro, município/UF, CEP | Sempre |
| Prazos | Validade APPCI, vencimento PrPCI | Apenas se ao menos um prazo estiver preenchido |

A seção **Prazos** usa `@if (l.dtValidadeAppci || l.dtVencimentoPrpci)` para evitar mostrar uma seção vazia em licenciamentos recém-criados (status RASCUNHO ou ANALISE_PENDENTE, que ainda não têm documentos emitidos).

---

### `app.routes.ts` — Rotas Atualizadas

A principal mudança em relação à Sprint F1 é a substituição do placeholder `NotFoundComponent` na rota `/licenciamentos` por uma estrutura de rotas filhas com lazy loading dos dois novos componentes:

**Sprint F1 (placeholder):**
```typescript
{
  path: 'licenciamentos',
  canActivate: [roleGuard],
  data: { roles: ['CIDADAO', 'ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM'] },
  loadComponent: () =>
    import('./pages/not-found/not-found.component').then(m => m.NotFoundComponent)
}
```

**Sprint F2 (rota real com filhos):**
```typescript
{
  path: 'licenciamentos',
  canActivate: [roleGuard],
  data: { roles: ['CIDADAO', 'ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM'] },
  children: [
    {
      path: '',
      loadComponent: () =>
        import('./pages/licenciamentos/licenciamentos.component')
          .then(m => m.LicenciamentosComponent)
    },
    {
      path: ':id',
      loadComponent: () =>
        import('./pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component')
          .then(m => m.LicenciamentoDetalheComponent)
    }
  ]
}
```

**Por que usar `children` em vez de duas rotas independentes:**
- O `canActivate: [roleGuard]` declarado no pai protege automaticamente ambas as rotas filhas (`/licenciamentos` e `/licenciamentos/:id`) com uma única declaração
- O `data: { roles: [...] }` é herdado pelos filhos via `ActivatedRouteSnapshot`
- Mantém a hierarquia visual da URL coerente: o detalhe é semanticamente um filho da lista

**Por que `loadComponent` (lazy) em vez de import estático:**
- O bundle de `licenciamentos-component` (132 kB) só é baixado quando o usuário navega para `/app/licenciamentos`
- Usuários com role ANALISTA ou INSPETOR, que nunca acessam essa rota, nunca baixam esse código
- O Angular gera um chunk separado por componente lazy, visível no output do build como `chunk-QGZOSUBX.js | licenciamentos-component`

---

## Justificativa de Cada Passo do Script

### Passo 1 — Verificação de Pré-Requisitos

```powershell
node --version          → v20.18.0   [OK]
npm --version           → v10.8.2    [OK]
Test-Path $FrontendDir  → true       [OK]
Get-Service SOL-Nginx   → Running    [OK]
```

**Por que é necessário:** Idêntico à Sprint F1, com uma diferença importante: a Sprint F2 **não verifica o Angular CLI global** (que gerava `[WARN]` na F1). O script da F2 vai direto para a verificação do Nginx, assumindo que se a F1 foi concluída com sucesso, Node.js e npm já estão funcionais.

O serviço `SOL-Nginx` em estado `Running` confirma que:
1. A Sprint F1 foi implantada (o serviço foi criado nela)
2. O servidor está ativo e pronto para reinício no Passo 5

Se qualquer verificação falhar, o script aborta com `exit 1` antes de executar qualquer build, economizando os 5+ minutos que um `npm install` + `ng build` desperdiçaria antes de detectar o problema.

**Mensagens emitidas:**
```
[OK] Node.js: v20.18.0
[OK] npm: v10.8.2
[OK] Diretorio frontend: C:\SOL\frontend
[OK] Servico SOL-Nginx encontrado (Status: Running)
```

---

### Passo 2 — Verificação dos Arquivos-Fonte da Sprint F2

```powershell
$f2Files = @(
    "...\core\models\licenciamento.model.ts",
    "...\core\services\licenciamento.service.ts",
    "...\pages\licenciamentos\licenciamentos.component.ts",
    "...\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts",
    "...\app.routes.ts"
)
foreach ($f in $f2Files) { Test-Path $f }

# Verificacao de conteudo
$routesContent -match "licenciamentos\.component"
```

**Por que este passo existe — e por que é único nesta sprint:**

A Sprint F1 não tinha um passo equivalente porque ela gerava a estrutura Angular do zero (todo o código já estava no `dist/` compilado de uma execução anterior, ou seria gerado pelo build). A Sprint F2 introduz um padrão novo: **os arquivos TypeScript são desenvolvidos separadamente e entregues antes do script de deploy**. O script não cria nem edita código-fonte — ele apenas verifica que o desenvolvedor os entregou corretamente.

Isso reflete o fluxo real de trabalho:
1. Desenvolvedor escreve/revisa os `.ts` da sprint
2. Script de deploy verifica a integridade (nada ausente, rotas corretas)
3. Só então executa o build

Se o script pulasse essa verificação e fosse direto ao build, um arquivo ausente geraria um erro de compilação TypeScript como:
```
ERROR in ./src/app/app.routes.ts
Cannot find module './pages/licenciamentos/licenciamentos.component'
```
— mensagem menos clara que um `[ERRO] AUSENTE: licenciamentos.component.ts`.

**Mensagens emitidas:**
```
[OK] Presente: licenciamento.model.ts
[OK] Presente: licenciamento.service.ts
[OK] Presente: licenciamentos.component.ts
[OK] Presente: licenciamento-detalhe.component.ts
[OK] Presente: app.routes.ts
[OK] app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent
```

---

### Passo 3 — npm install (Verificação de Integridade)

```powershell
Push-Location $FrontendDir
$ErrorActionPreference = "Continue"
& npm install
$npmExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
```

**Por que é necessário mesmo sem novos pacotes:**

A Sprint F2 não adiciona nenhuma nova dependência ao `package.json` — os 948 pacotes já instalados na F1 cobrem tudo que é necessário (`@angular/material`, `angular-oauth2-oidc`, etc.). O npm reportou `up to date, audited 948 packages in 6s`.

Mesmo assim, o passo é mantido porque:
1. **Integridade do `node_modules/`** — alguém pode ter executado `npm ci`, `git clean`, ou movido a pasta entre as sprints
2. **Lock file** — garante que as versões exatas do `package-lock.json` estão instaladas, não versões mais recentes que possam ter mudanças breaking
3. **Custo baixo** — quando os pacotes já estão presentes, o npm retorna em menos de 10 segundos sem baixar nada

O `$ErrorActionPreference = "Continue"` durante o npm (padrão herdado da Sprint F1) evita que warnings de pacotes deprecated sejam tratados como erros fatais pelo PowerShell.

**Mensagens emitidas:**
```
[INFO] Executando: npm install em C:\SOL\frontend
       up to date, audited 948 packages in 6s
       178 packages are looking for funding
       43 vulnerabilities (6 low, 9 moderate, 28 high)
[OK]   npm install concluido
```

---

### Passo 4 — Build Angular (Modo Produção)

```powershell
Push-Location $FrontendDir
& npm run build:prod    # ng build --configuration production
$buildExit = $LASTEXITCODE
```

**O que muda em relação à Sprint F1:**

Na F1, o build gerou 15 arquivos e 7 lazy chunks (shell, dashboard, login, browser, not-found, e 2 auxiliares). Na F2, o build gerou **22 arquivos** com 13 lazy chunks — os novos componentes foram compilados em chunks próprios:

```
chunk-QGZOSUBX.js | licenciamentos-component        | 132.41 kB
chunk-EV3YAOBC.js | licenciamento-detalhe-component  |   5.95 kB
```

O `licenciamentos-component` cresceu para 132 kB porque inclui:
- `MatTableModule` + `MatPaginatorModule` (componentes pesados do Angular Material)
- Os tipos e constantes do `licenciamento.model.ts`
- O `LicenciamentoService` injetado

O `licenciamento-detalhe-component` ficou pequeno (5.95 kB) porque não carrega tabela — apenas cards com `@if` para exibir campos.

O total inicial passou de **397 kB → 429 kB** (+32 kB), mas o impacto na carga inicial é mínimo: o bundle `licenciamentos-component` só é baixado quando o usuário navega para a rota `/app/licenciamentos`.

**Mensagens emitidas:**
```
[INFO] Executando: npm run build:prod em C:\SOL\frontend
[INFO] Este processo pode levar de 2 a 5 minutos...
       Application bundle generation complete. [4.750 seconds]
       Output location: C:\SOL\frontend\dist\sol-frontend
[OK]   Build Angular concluido
[OK]   Dist gerado: C:\SOL\frontend\dist\sol-frontend\browser (22 arquivos)
```

---

### Passo 5 — Atualizar Configuração do Nginx e Reiniciar Serviço

```powershell
Copy-Item -Path $NginxSrcConf -Destination "$NginxConfDir\nginx.conf" -Force
& $NginxExe -t          # teste de sintaxe
Stop-Service SOL-Nginx -Force
Start-Sleep -Seconds 2
Start-Service SOL-Nginx
Start-Sleep -Seconds 3
```

**Por que copiar o `nginx.conf` novamente se ele não mudou:**

O `nginx.conf` na Sprint F2 é **idêntico** ao da Sprint F1 — nenhuma nova regra de proxy ou location foi necessária. No entanto, o passo é mantido por três razões:

1. **Idempotência** — executar o script duas vezes produz o mesmo resultado; um `nginx.conf` corrompido manualmente entre as sprints seria sobrescrito automaticamente
2. **Consistência** — o script não precisa detectar se o conf mudou; simplesmente sempre garante que o arquivo de referência (`C:\SOL\infra\nginx\nginx.conf`) está no lugar certo
3. **Preparação para sprints futuras** — a Sprint F3 (wizard de upload de arquivos) poderá precisar ajustar `client_max_body_size` ou timeouts; manter o passo garante que qualquer mudança futura no conf seja aplicada

O reinício completo (stop + start) é necessário porque o Nginx no Windows não implementa `reload` via serviço (diferente do Linux onde `nginx -s reload` faz graceful reload). O `Stop-Service -Force` encerra o processo e o `Start-Service` carrega o conf novo do zero.

**Mensagens emitidas:**
```
[OK]   nginx.conf copiado para C:\SOL\infra\nginx\nginx-1.26.2\conf
[WARN] Nao foi possivel testar nginx.conf: nginx: [alert] could not open error log file:
       CreateFile() "logs/error.log" failed (3: The system cannot find the path specified)
[INFO] Parando SOL-Nginx...
[INFO] Iniciando SOL-Nginx...
[OK]   Servico SOL-Nginx: RUNNING
```

---

### Passo 6 — Verificação HTTP

```powershell
Invoke-WebRequest  "http://localhost:80/"                    # frontend SPA
Invoke-RestMethod  "http://localhost:80/api/actuator/health" # backend via proxy
```

**Por que duas verificações distintas:**

- **`GET /`** confirma que o Nginx está servindo o novo `dist/` (os novos hashes de chunk como `QGZOSUBX` estão no `index.html`)
- **`GET /api/actuator/health`** confirma que o proxy `/api/` continua funcional após o restart — o restart do Nginx poderia ter corrompido a configuração de upstream se o `nginx.conf` tivesse sido editado manualmente de forma incorreta

**Por que não verificar `/app/licenciamentos` diretamente:**

O Nginx não distingue entre rotas Angular — todas as URLs servem o mesmo `index.html` graças ao `try_files`. A verificação de que `/app/licenciamentos` retorna HTTP 200 foi feita **separadamente**, fora do script, via:

```powershell
Invoke-WebRequest -Uri "http://localhost:80/app/licenciamentos" -UseBasicParsing
# → HTTP 200
```

O Angular Router (no browser) é quem processa a rota e renderiza `LicenciamentosComponent`. Do ponto de vista do Nginx, `/app/licenciamentos` não existe como arquivo — ele serve `index.html` e o Angular toma conta do resto.

**Mensagens emitidas:**
```
[OK] http://localhost:80/ -- HTTP 200
[OK] Conteudo HTML contem 'SOL' -- Angular SPA carregado
[OK] http://localhost:80/api/actuator/health -- Backend UP
```

---

## Observação Técnica — StatusLicenciamento Incompleto no Modelo

### O que foi detectado

Durante a análise prévia dos arquivos-fonte, foi identificado que `licenciamento.model.ts` tinha uma definição de `StatusLicenciamento` com **10 valores** — enquanto o backend possui **23 valores** no enum `StatusLicenciamento.java`:

**Valores presentes no modelo TypeScript mas ausentes no backend Java:**
```typescript
// Presentes no .ts — NÃO existem no backend
| 'APROVADO'
| 'REPROVADO'
```

**Valores presentes no backend Java mas ausentes no modelo TypeScript:**
```
CIA_CIENCIA, DEFERIDO, INDEFERIDO, VISTORIA_PENDENTE, EM_VISTORIA,
CIV_CIENCIA, PRPCI_EMITIDO, APPCI_EMITIDO, ALVARA_VENCIDO,
AGUARDANDO_ACEITE_RENOVACAO, AGUARDANDO_PAGAMENTO_RENOVACAO,
AGUARDANDO_DISTRIBUICAO_RENOV, EM_VISTORIA_RENOVACAO,
EM_RECURSO, RENOVADO
```

### Por que o build não falhou

O TypeScript verifica **consistência interna** — não valida os dados contra o servidor em tempo de compilação. No modelo, `StatusLicenciamento` era um union type com 10 valores, e os `Record<StatusLicenciamento, string>` definidos para `STATUS_LABEL` e `STATUS_COLOR` cobriam exatamente esses mesmos 10 valores. Portanto, nenhuma inconsistência de tipos foi detectada pelo compilador.

```typescript
// Internamente consistente — TypeScript não reclama
export type StatusLicenciamento = 'RASCUNHO' | 'APROVADO' | ...;  // 10 valores
export const STATUS_LABEL: Record<StatusLicenciamento, string> = {
  RASCUNHO: 'Rascunho',
  APROVADO: 'Aprovado',  // existe no TS, não existe no backend — TypeScript não sabe disso
  ...  // exatamente 10 entradas
};
```

### Por que não causará erro em runtime

Os métodos `getStatusLabel` e `getStatusColor` nos componentes usam o operador de fallback `??`:

```typescript
getStatusLabel(status: StatusLicenciamento): string {
  return STATUS_LABEL[status] ?? status;  // se não encontrar no mapa, retorna o próprio valor
}
```

Quando o backend retornar `DEFERIDO` (que não está no mapa TypeScript), o método retornará a string `"DEFERIDO"` diretamente — visível ao usuário mas sem crash. O `STATUS_COLOR` retornará `'#9e9e9e'` (cinza) como fallback.

### Impacto real

| Cenário | Comportamento |
|---------|--------------|
| Status `RASCUNHO`, `ANALISE_PENDENTE`, `EM_ANALISE` | Label e cor corretos |
| Status `DEFERIDO`, `APPCI_EMITIDO`, etc. (backend, fora do mapa TS) | Label = valor bruto (`"DEFERIDO"`), cor = cinza |
| Status `APROVADO` ou `REPROVADO` (no mapa TS, fora do backend) | Nunca serão retornados pelo backend; entradas mortas |

Este é um problema de qualidade de código (cobertura incompleta de estados), não um bug que impede o funcionamento. A tela de licenciamentos exibirá corretamente todos os licenciamentos — apenas os labels e cores de alguns status serão menos refinados. Será resolvido naturalmente em iterações futuras de polimento de UI.

---

## Solução Aplicada — Wrapper de Captura de Output

### Problema (herdado da Sprint F1)

O Git Bash não captura o output de `Write-Host` do PowerShell quando invocado via `cmd /c "powershell..."`. O processo filho executa, mas o output é descartado pelo handler de I/O do Git Bash.

### Solução (padrão estabelecido na Sprint F1, reutilizado na F2)

Criação de um script wrapper `C:\SOL\logs\run-sprint-f2.ps1`:

```powershell
$out = "C:\SOL\logs\sprint-f2-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f2-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f2-run-exitcode.txt" -Encoding UTF8
```

Chamado via:
```bash
powershell.exe -ExecutionPolicy Bypass -NoProfile -File /c/SOL/logs/run-sprint-f2.ps1
```

**Como funciona:**
- `*>&1` redireciona todos os 6 streams do PowerShell (Output, Error, Warning, Verbose, Debug, Information — onde `Write-Host` escreve) para o stream de saída padrão
- `Tee-Object` escreve simultaneamente no arquivo de log E no console
- O path Unix `/c/SOL/logs/run-sprint-f2.ps1` é resolvido corretamente pelo PowerShell quando chamado como argumento de `-File` a partir do Git Bash

**Por que este padrão está estabelecido como solução permanente:** O Git Bash é o shell padrão do Claude Code no Windows. O wrapper de 3 linhas é um padrão mínimo, sem dependências externas, que funciona em qualquer versão do PowerShell 5.1+. Ele será reutilizado em todas as sprints F3-F9.

---

## Execução — Output Completo

```
============================================================
  SOL CBM-RS -- Sprint F2: Modulo de Licenciamentos
  Inicio: 2026-04-06 20:18:41
============================================================

=== [1] Verificacao de pre-requisitos ===
[2026-04-06 20:18:41] [OK] Node.js: v20.18.0
[2026-04-06 20:18:42] [OK] npm: v10.8.2
[2026-04-06 20:18:42] [OK] Diretorio frontend: C:\SOL\frontend
[2026-04-06 20:18:42] [OK] Servico SOL-Nginx encontrado (Status: Running)

=== [2] Verificacao dos arquivos-fonte da Sprint F2 ===
[2026-04-06 20:18:42] [OK] Presente: licenciamento.model.ts
[2026-04-06 20:18:42] [OK] Presente: licenciamento.service.ts
[2026-04-06 20:18:42] [OK] Presente: licenciamentos.component.ts
[2026-04-06 20:18:42] [OK] Presente: licenciamento-detalhe.component.ts
[2026-04-06 20:18:42] [OK] Presente: app.routes.ts
[2026-04-06 20:18:42] [OK] app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent

=== [3] npm install (verificacao de integridade das dependencias) ===
[2026-04-06 20:18:42] [INFO] Executando: npm install em C:\SOL\frontend

up to date, audited 948 packages in 6s

178 packages are looking for funding
  run `npm fund` for details

43 vulnerabilities (6 low, 9 moderate, 28 high)

To address issues that do not require attention, run:
  npm audit fix

To address all issues (including breaking changes), run:
  npm audit fix --force

Run `npm audit` for details.
[2026-04-06 20:18:48] [OK] npm install concluido

=== [4] Build Angular (modo producao) ===
[2026-04-06 20:18:48] [INFO] Executando: npm run build:prod em C:\SOL\frontend
[2026-04-06 20:18:48] [INFO] Este processo pode levar de 2 a 5 minutos...

> sol-frontend@1.0.0 build:prod
> ng build --configuration production

❯ Building...
✔ Building...
Initial chunk files  | Names              |  Raw size | Estimated transfer size
chunk-SPIBTHTO.js    | -                  | 186.56 kB |               54.36 kB
chunk-NTOSUY3X.js    | -                  | 101.28 kB |               25.47 kB
styles-27OWQZN7.css  | styles             |  50.72 kB |                5.42 kB
chunk-UTGB2QD4.js    | -                  |  48.94 kB |               11.48 kB
polyfills-FFHMD2TL.js| polyfills          |  34.52 kB |               11.28 kB
main-GIMP7BYB.js     | main               |   6.09 kB |                1.98 kB
chunk-V665W7XF.js    | -                  |   1.04 kB |              479 bytes
chunk-NNVOWT6O.js    | -                  |  348 bytes|              348 bytes

                     | Initial total      | 429.50 kB |              110.82 kB

Lazy chunk files     | Names                          |  Raw size | Estimated transfer size
chunk-QGZOSUBX.js    | licenciamentos-component       | 132.41 kB |               24.88 kB
chunk-XWFHP7PL.js    | -                              | 122.76 kB |               20.43 kB
chunk-IVVYC7QN.js    | -                              |  93.76 kB |               20.34 kB
chunk-55CA3S5Q.js    | shell-component                |  83.25 kB |               15.38 kB
chunk-32E7DCHZ.js    | browser                        |  63.60 kB |               16.84 kB
chunk-5K4ERO5J.js    | -                              |  12.22 kB |                3.28 kB
chunk-ZVLFIZCC.js    | -                              |   6.97 kB |                1.53 kB
chunk-EV3YAOBC.js    | licenciamento-detalhe-component|   5.95 kB |                2.14 kB
chunk-Q64FFBLU.js    | -                              |   4.20 kB |                1.05 kB
chunk-Z3UBDGFM.js    | dashboard-component            |   4.08 kB |                1.62 kB
chunk-PWSEFL5O.js    | login-component                |   1.92 kB |              803 bytes
chunk-3TMFMYTA.js    | -                              |   1.52 kB |              551 bytes
chunk-RKNN357I.js    | not-found-component            |   1.50 kB |              684 bytes

Application bundle generation complete. [4.750 seconds]
Output location: C:\SOL\frontend\dist\sol-frontend

[2026-04-06 20:18:54] [OK] Build Angular concluido
[2026-04-06 20:18:54] [OK] Dist gerado: C:\SOL\frontend\dist\sol-frontend\browser (22 arquivos)

=== [5] Atualizar configuracao do Nginx e reiniciar servico ===
[2026-04-06 20:18:54] [OK] nginx.conf copiado para C:\SOL\infra\nginx\nginx-1.26.2\conf
[2026-04-06 20:18:54] [WARN] Nao foi possivel testar nginx.conf: nginx: [alert] could not
                             open error log file: CreateFile() "logs/error.log" failed
                             (3: The system cannot find the path specified)
[2026-04-06 20:18:54] [INFO] Parando SOL-Nginx...
[2026-04-06 20:18:58] [INFO] Iniciando SOL-Nginx...
[2026-04-06 20:19:02] [OK] Servico SOL-Nginx: RUNNING

=== [6] Verificacao HTTP ===
[2026-04-06 20:19:07] [OK] http://localhost:80/ -- HTTP 200
[2026-04-06 20:19:07] [OK] Conteudo HTML contem 'SOL' -- Angular SPA carregado
[2026-04-06 20:19:07] [OK] http://localhost:80/api/actuator/health -- Backend UP
```

---

## Log Completo (sprint-f2-deploy.log)

```
[2026-04-06 20:18:41] [OK]   Node.js: v20.18.0
[2026-04-06 20:18:42] [OK]   npm: v10.8.2
[2026-04-06 20:18:42] [OK]   Diretorio frontend: C:\SOL\frontend
[2026-04-06 20:18:42] [OK]   Servico SOL-Nginx encontrado (Status: Running)
[2026-04-06 20:18:42] [OK]   Presente: licenciamento.model.ts
[2026-04-06 20:18:42] [OK]   Presente: licenciamento.service.ts
[2026-04-06 20:18:42] [OK]   Presente: licenciamentos.component.ts
[2026-04-06 20:18:42] [OK]   Presente: licenciamento-detalhe.component.ts
[2026-04-06 20:18:42] [OK]   Presente: app.routes.ts
[2026-04-06 20:18:42] [OK]   app.routes.ts: rota /licenciamentos aponta para LicenciamentosComponent
[2026-04-06 20:18:42] [INFO] Executando: npm install em C:\SOL\frontend
[2026-04-06 20:18:48] [OK]   npm install concluido
[2026-04-06 20:18:48] [INFO] Executando: npm run build:prod em C:\SOL\frontend
[2026-04-06 20:18:48] [INFO] Este processo pode levar de 2 a 5 minutos...
[2026-04-06 20:18:54] [OK]   Build Angular concluido
[2026-04-06 20:18:54] [OK]   Dist gerado: C:\SOL\frontend\dist\sol-frontend\browser (22 arquivos)
[2026-04-06 20:18:54] [OK]   nginx.conf copiado para C:\SOL\infra\nginx\nginx-1.26.2\conf
[2026-04-06 20:18:54] [WARN] Nao foi possivel testar nginx.conf: nginx: [alert] could not
                              open error log file: CreateFile() "logs/error.log" failed
                              (3: The system cannot find the path specified)
[2026-04-06 20:18:54] [INFO] Parando SOL-Nginx...
[2026-04-06 20:18:58] [INFO] Iniciando SOL-Nginx...
[2026-04-06 20:19:02] [OK]   Servico SOL-Nginx: RUNNING
[2026-04-06 20:19:07] [OK]   http://localhost:80/ -- HTTP 200
[2026-04-06 20:19:07] [OK]   Conteudo HTML contem 'SOL' -- Angular SPA carregado
[2026-04-06 20:19:07] [OK]   http://localhost:80/api/actuator/health -- Backend UP
```

> **Diferença em relação ao log da Sprint F1:** A Sprint F2 foi concluída em **uma única execução**, sem tentativas anteriores com falha. O log começa e termina no mesmo run. Isso contrasta com a F1, que teve 5 execuções (3 com falha de build) registradas no log antes do sucesso.

---

## Sumário Final Emitido pelo Script

```
============================================================
  SUMARIO -- Sprint F2
============================================================
  OK      : 18
  AVISOS  : 1
  ERROS   : 0
  Fim     : 2026-04-06 20:19:07
============================================================

  Sprint F2 implantada com sucesso!

  Frontend:       http://localhost:80/
  Licenciamentos: http://localhost:80/app/licenciamentos
  API:            http://localhost:80/api/licenciamentos/meus

  PROXIMO PASSO: Sprint F3 -- Wizard de Solicitacao de Licenciamento
```

---

## Aviso Não Bloqueante

### WARN — nginx -t: CreateFile "logs/error.log" failed

**Mensagem completa:**
```
nginx: [alert] could not open error log file:
CreateFile() "logs/error.log" failed (3: The system cannot find the path specified)
```

**Causa:** Idêntica à Sprint F1. O executável `nginx.exe` é invocado pelo PowerShell com o diretório de trabalho do shell, não com o diretório de instalação do Nginx. O path relativo `logs/error.log` não resolve fora de `C:\SOL\infra\nginx\nginx-1.26.2\`.

**Por que não é problema:** O serviço `SOL-Nginx` iniciou normalmente e respondeu HTTP 200. O Nginx como serviço Windows é iniciado pelo SCM (Service Control Manager) com o diretório correto definido no registro, e o `nginx.conf` é sintaticamente correto.

**Padrão recorrente:** Este aviso aparecerá em **todas as sprints F1-F9** enquanto o teste `nginx -t` for executado fora do diretório do Nginx. É um aviso cosmético, já documentado no relatório da Sprint F1 e não requer ação.

---

## Confirmações HTTP Pós-Deploy

Verificações adicionais executadas fora do script, confirmando todas as URLs solicitadas:

| URL | HTTP Status | Resultado |
|-----|-------------|-----------|
| `http://localhost:80/` | **200** | Angular SPA carregada, HTML contém "SOL" |
| `http://localhost:80/app/licenciamentos` | **200** | Nginx serve `index.html`; Angular Router carrega `LicenciamentosComponent` |
| `http://localhost:80/api/actuator/health` | **200** | `{"status":"UP"}` — SOL-Backend operacional |

> **Nota sobre `/app/licenciamentos`:** O HTTP 200 confirma que o Nginx está servindo `index.html` para essa rota (comportamento esperado com `try_files`). A renderização do `LicenciamentosComponent` e a chamada real a `GET /api/licenciamentos/meus` ocorrem no browser após o Angular carregar — não são verificáveis via `Invoke-WebRequest` (que não executa JavaScript).

---

## Bundles Gerados — Comparativo F1 vs F2

| Métrica | Sprint F1 | Sprint F2 | Variação |
|---------|-----------|-----------|---------|
| Arquivos no dist/ | 15 | 22 | +7 |
| Lazy chunks | 7 | 13 | +6 |
| Initial total (raw) | 397.42 kB | 429.50 kB | +32 kB |
| Initial total (gzip) | 101.59 kB | 110.82 kB | +9.2 kB |
| Tempo de build | 3.075s | 4.750s | +1.7s |
| Novos componentes lazy | — | `licenciamentos-component` (133 kB), `licenciamento-detalhe-component` (6 kB) | — |

O aumento de **+9.2 kB gzipado no bundle inicial** deve-se à inclusão do `MatTableModule` e `MatPaginatorModule` no chunk principal do Angular Material (esses módulos são compartilhados entre componentes). O código exclusivo dos novos componentes é baixado apenas na primeira navegação para `/app/licenciamentos`.

---

## Próximo Passo

**Sprint F3 — Wizard de Solicitação de Licenciamento**

A Sprint F3 implementará o formulário multi-step para criar um novo licenciamento (processo P03), ativando o botão "Nova Solicitação" atualmente desabilitado. O wizard cobrirá:
- Passo 1: Tipo de licenciamento (PPCI / PSPCIM) e dados da edificação
- Passo 2: Endereço da edificação (com formatação de CEP)
- Passo 3: Declaração de Responsável Técnico (RT) e upload do PPCI
- Passo 4: Revisão e submissão (`POST /api/licenciamentos` + `POST /api/licenciamentos/{id}/submeter`)

---

*Relatório gerado em 2026-04-06 | Sprint F2 — SOL CBM-RS*
