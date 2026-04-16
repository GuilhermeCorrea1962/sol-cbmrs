# Sprint F4 -- Analise Tecnica (P04)

**Data de criacao:** 2026-04-07
**Ultima atualizacao:** 2026-04-07
**Sprint anterior:** F3 -- Wizard de Solicitacao de Licenciamento
**Objetivo:** Implementar o modulo de Analise Tecnica que permite a ANALISTA e CHEFE_SSEG_BBM visualizar a fila de processos, assumir um processo para analise, emitir CIA, deferir e indeferir (processo P04 do BPMN).

---

## Estado atual da sprint

> **Situacao em 2026-04-07:** Todos os arquivos-fonte foram gerados localmente em `C:\SOL` e sincronizados com o drive `Y:\` (servidor). O deploy no servidor ainda nao foi executado -- aguarda execucao do script `run-sprint-f4.ps1`.

### Mapa de progresso

| Etapa | Responsavel | Status |
|---|---|---|
| Gerar arquivos-fonte Angular em `C:\SOL` | Claude Code (local) | **CONCLUIDO** |
| Gerar scripts de deploy/sync em `C:\SOL` | Claude Code (local) | **CONCLUIDO** |
| Sincronizar `C:\SOL` -> `Y:\` | Claude Code (local) | **CONCLUIDO** (2026-04-08) |
| Executar `run-sprint-f4.ps1` no servidor | Claude Code (servidor) | **PENDENTE** |
| Verificar HTTP 200 + fila e analise funcionando | Humano | **PENDENTE** |

---

## Inventario de arquivos -- estado verificado

### C:\SOL (maquina local) -- SINCRONIZADO

| Caminho completo | Tipo | Verificado |
|---|---|---|
| `C:\SOL\frontend\src\app\core\models\analise.model.ts` | NOVO | Sim |
| `C:\SOL\frontend\src\app\pages\analise\analise-fila\analise-fila.component.ts` | NOVO | Sim |
| `C:\SOL\frontend\src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts` | NOVO | Sim |
| `C:\SOL\frontend\src\app\core\services\licenciamento.service.ts` | ATUALIZADO | Sim |
| `C:\SOL\frontend\src\app\app.routes.ts` | ATUALIZADO | Sim |
| `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` | ATUALIZADO | Sim |
| `C:\SOL\infra\scripts\sprint-f4-deploy.ps1` | NOVO | Sim |
| `C:\SOL\logs\run-sprint-f4.ps1` | NOVO | Sim |

### Y:\ (servidor) -- SINCRONIZADO

| Caminho em Y:\ | Copiado em |
|---|---|
| `Y:\frontend\src\app\core\models\analise.model.ts` | 2026-04-07 |
| `Y:\frontend\src\app\pages\analise\analise-fila\analise-fila.component.ts` | 2026-04-07 |
| `Y:\frontend\src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts` | 2026-04-07 |
| `Y:\frontend\src\app\core\services\licenciamento.service.ts` | 2026-04-07 |
| `Y:\frontend\src\app\app.routes.ts` | 2026-04-07 |
| `Y:\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` | 2026-04-07 |
| `Y:\infra\scripts\sprint-f4-deploy.ps1` | 2026-04-07 |
| `Y:\logs\run-sprint-f4.ps1` | 2026-04-07 |

---

## Visao geral da sprint

| Item | Detalhe |
|---|---|
| Rotas novas | `/app/analise` (fila) + `/app/analise/:id` (analise) |
| Roles permitidas | `ANALISTA`, `CHEFE_SSEG_BBM` |
| Componentes novos | 2 (`AnaliseFilaComponent` + `LicenciamentoAnaliseComponent`) |
| Modelo novo | 1 (`analise.model.ts` com 3 DTOs) |
| Arquivos atualizados | 3 (service, routes, detalhe) |
| Endpoints novos consumidos | 5 (`fila-analise`, `iniciar-analise`, `cia`, `deferir`, `indeferir`) |
| Scripts de infraestrutura | 2 (deploy + launcher) |

---

## Instrucoes de execucao

### Passo 1 -- Sincronizar arquivos para o servidor

> **JA CONCLUIDO** em 2026-04-08. Todos os 8 arquivos F4 foram gravados diretamente em `Y:\` pelo Claude Code (local).

| Arquivo em Y:\ | Situacao |
|---|---|
| `Y:\frontend\src\app\core\models\analise.model.ts` | Gravado em 2026-04-08 |
| `Y:\frontend\src\app\pages\analise\analise-fila\analise-fila.component.ts` | Gravado em 2026-04-08 |
| `Y:\frontend\src\app\pages\analise\licenciamento-analise\licenciamento-analise.component.ts` | Gravado em 2026-04-08 |
| `Y:\frontend\src\app\core\services\licenciamento.service.ts` | Gravado em 2026-04-08 |
| `Y:\frontend\src\app\app.routes.ts` | Atualizado em 2026-04-08 |
| `Y:\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` | Atualizado em 2026-04-08 |
| `Y:\infra\scripts\sprint-f4-deploy.ps1` | Gravado em 2026-04-08 |
| `Y:\logs\run-sprint-f4.ps1` | Gravado em 2026-04-08 |

---

### Passo 2 -- Executar o deploy no servidor

> **PENDENTE** -- este e o proximo passo a executar.

**Via Claude Code no servidor** (recomendado):

```
Execute o script C:\SOL\logs\run-sprint-f4.ps1 para fazer o deploy da Sprint F4
(Analise Tecnica).

O script realiza as seguintes etapas:
1. Pre-verificacao do ambiente (Node.js, npm, diretorios)
2. Verificacao dos 6 arquivos-fonte F4 (existencia + conteudo)
3. npm ci --prefer-offline
4. ng build --configuration production
5. Deploy dos assets para C:\nginx\html\sol
6. Restart do servico Nginx + smoke test HTTP 200

Ao final, confirme:
- HTTP 200 em http://localhost/
- Rota /app/analise acessivel apos login como ANALISTA ou CHEFE_SSEG_BBM
- Tabela de processos exibida (fila de analise)
- Rota /app/analise/:id carrega a tela com painel de acoes
```

**Via execucao manual no servidor:**

```powershell
# No servidor, abrir PowerShell como Administrador:
C:\SOL\logs\run-sprint-f4.ps1
```

Log completo em `C:\SOL\logs\sprint-f4-run-output.txt`.
Exit code em `C:\SOL\logs\sprint-f4-run-exitcode.txt`.

---

## Detalhes tecnicos dos arquivos

### 1. `analise.model.ts` (NOVO)

**Por que e necessario:**
As acoes de analise (CIA, deferimento, indeferimento) exigem DTOs especificos que nao existem no `licenciamento.model.ts` (que define apenas os tipos de leitura). Separar em arquivo proprio segue o mesmo principio adotado em F3 com `licenciamento-create.model.ts` vs `licenciamento.model.ts`.

**Conteudo:**

```typescript
// Item de inconformidade em um CIA
export interface CiaItemCreateDTO {
  descricao: string;          // Obrigatoria, max 500 chars
  normaReferencia?: string;   // Ex: "RTCBMRS N.01/2024 Art. 15", max 200 chars
}

// Payload para POST /api/licenciamentos/{id}/cia
// Transicao: EM_ANALISE -> CIA_EMITIDO
export interface CiaCreateDTO {
  itens: CiaItemCreateDTO[];  // Min 1 item
  observacaoGeral?: string;
  prazoCorrecaoEmDias: number; // Padrao 30, min 1, max 365
}

// Payload para POST /api/licenciamentos/{id}/deferir
// Transicao: EM_ANALISE -> VISTORIA_PENDENTE (PPCI) ou DEFERIDO (PSPCIM)
export interface DeferimentoCreateDTO {
  observacao?: string;        // Opcional, max 2000 chars
}

// Payload para POST /api/licenciamentos/{id}/indeferir
// Transicao: EM_ANALISE -> INDEFERIDO
export interface IndeferimentoCreateDTO {
  justificativa: string;      // Obrigatoria, min 20, max 2000 chars
}
```

**Correspondencia com o backend:**
```java
// Java backend -- CiaCreateDTO.java
public record CiaCreateDTO(
    @NotEmpty @Valid List<CiaItemDTO> itens,
    String observacaoGeral,
    @NotNull @Min(1) Integer prazoCorrecaoEmDias
) {}
```

---

### 2. `analise-fila.component.ts` (NOVO)

**Por que e necessario:**
ANALISTA e CHEFE_SSEG_BBM precisam de uma visao centralizada de todos os processos aguardando analise. A lista ja existe em `/app/licenciamentos`, mas ela exibe apenas os processos do usuario autenticado (endpoint `/meus`). A fila usa um endpoint dedicado (`/fila-analise`) que retorna todos os processos em ANALISE_PENDENTE e EM_ANALISE, ordenados por data de entrada (FIFO -- norma RTCBMRS).

**Rota:** `/app/analise`

**Endpoint:** `GET /api/licenciamentos/fila-analise?page=0&size=10&sort=dataCriacao,asc`

**Estrutura da tabela:**

| Coluna | Campo | Justificativa |
|---|---|---|
| Numero PPCI | `numeroPpci` | Identificador legivel do processo |
| Tipo | `tipo` | PPCI ou PSPCIM (fluxo difere no deferimento) |
| Status | `status` | Distingue ANALISE_PENDENTE de EM_ANALISE |
| Municipio | `endereco.municipio/uf` | Contexto geografico do CBMRS |
| Area (m2) | `areaConstruida` | Indicador de complexidade da analise |
| Entrada | `dataCriacao` | Data de submissao (base do criterio FIFO) |
| Acoes | -- | Botao "Analisar" -> `/app/analise/:id` |

**Estado vazio:** Exibe mensagem "Nenhum processo na fila" quando `content` e vazio -- evita tabela em branco.

---

### 3. `licenciamento-analise.component.ts` (NOVO)

**Por que e necessario:**
Implementa o processo P04 (Analise Tecnica do BPMN). O ANALISTA precisa de uma tela dedicada para:
1. Ver todos os dados do processo (edificacao, endereco)
2. Executar as acoes de analise sem sair da pagina

**Rota:** `/app/analise/:id`

**Fluxo de estados e acoes:**

```
Status = ANALISE_PENDENTE
  -> Botao "Iniciar Analise" (POST iniciar-analise)
  -> Recarrega o processo, status muda para EM_ANALISE

Status = EM_ANALISE
  -> Botao "Emitir CIA"   -> exibe formulario CIA inline
  -> Botao "Deferir"      -> exibe formulario de deferimento inline
  -> Botao "Indeferir"    -> exibe formulario de indeferimento inline

Apos CIA      -> status = CIA_EMITIDO, painel de acoes some
Apos Deferir  -> navega para /app/analise (fila)
Apos Indeferir -> navega para /app/analise (fila)
```

**Decisao de design -- formularios inline (sem Dialog):**
Os formularios de CIA, deferimento e indeferimento sao exibidos inline abaixo dos botoes de acao, usando um mecanismo de toggle (sinal `acaoAtiva`). Clicar no mesmo botao novamente fecha o formulario. Esta abordagem foi preferida ao `MatDialog` para evitar a complexidade de gerenciar dialogs em componentes standalone, e para manter o contexto do processo visivel enquanto o analista preenche os dados.

**FormArray no CIA:**
O CIA contem uma lista dinamica de inconformidades (`FormArray<FormGroup>`). O analista pode:
- Adicionar inconformidades com o botao "Adicionar inconformidade"
- Remover inconformidades (o ultimo item nao pode ser removido -- minimo 1)
- Para cada item: descricao (obrigatoria) + normaReferencia (opcional)

**Validacoes implementadas:**
- CIA: prazo min 1 / max 365, descricao de cada item obrigatoria
- Indeferimento: justificativa min 20 chars (evita justificativas vagas)
- Deferimento: observacao opcional (sem restricao obrigatoria)

---

### 4. `licenciamento.service.ts` (ATUALIZADO)

**5 novos metodos adicionados:**

| Metodo | Endpoint | Transicao de status |
|---|---|---|
| `getFilaAnalise(page, size)` | `GET /api/licenciamentos/fila-analise` | -- (leitura) |
| `iniciarAnalise(id)` | `POST /api/licenciamentos/{id}/iniciar-analise` | ANALISE_PENDENTE -> EM_ANALISE |
| `emitirCia(id, dto)` | `POST /api/licenciamentos/{id}/cia` | EM_ANALISE -> CIA_EMITIDO |
| `deferir(id, dto)` | `POST /api/licenciamentos/{id}/deferir` | EM_ANALISE -> VISTORIA_PENDENTE ou DEFERIDO |
| `indeferir(id, dto)` | `POST /api/licenciamentos/{id}/indeferir` | EM_ANALISE -> INDEFERIDO |

**Sobre o endpoint `/fila-analise`:**
O endpoint dedicado e preferido ao endpoint generico `GET /api/licenciamentos?status=...` por duas razoes:
1. Permite que o backend aplique as regras de RBAC especificamente para a fila de analise (um ANALISTA so ve os processos da sua regiao, por exemplo)
2. O ordenamento por `dataCriacao,asc` garante o criterio FIFO exigido pela RTCBMRS N.01/2024

---

### 5. `app.routes.ts` (ATUALIZADO)

**O que mudou:**
A rota `analise` foi convertida de um placeholder apontando para `NotFoundComponent` para uma rota com filhos (`children`), seguindo o mesmo padrao ja usado em `licenciamentos`.

```typescript
// ANTES (placeholder F2/F3):
{
  path: 'analise',
  canActivate: [roleGuard],
  data: { roles: ['ANALISTA', 'CHEFE_SSEG_BBM'] },
  loadComponent: () => import('...not-found...')...
}

// DEPOIS (F4 ativo):
{
  path: 'analise',
  canActivate: [roleGuard],
  data: { roles: ['ANALISTA', 'CHEFE_SSEG_BBM'] },
  children: [
    {
      path: '',              // /app/analise
      loadComponent: () => import('...analise-fila.component')...
    },
    {
      path: ':id',           // /app/analise/:id
      loadComponent: () => import('...licenciamento-analise.component')...
    }
  ]
}
```

**Protecao de roles no pai:**
O `canActivate: [roleGuard]` esta no pai (sem `loadComponent`), protegendo automaticamente ambas as rotas filhas. Nao e necessario repetir o guard em cada filho -- o Angular aplica o guard do pai para toda a arvore de filhos.

---

### 6. `licenciamento-detalhe.component.ts` (ATUALIZADO)

**O que mudou:**
- Importado `AuthService`
- Adicionada propriedade `readonly podeAnalisar = this.auth.hasAnyRole(['ANALISTA', 'CHEFE_SSEG_BBM'])`
- Adicionada barra de acao no topo do detalhe, visivel apenas quando:
  - Usuario e ANALISTA ou CHEFE_SSEG_BBM
  - Status do processo e `ANALISE_PENDENTE` ou `EM_ANALISE`
- O botao navega para `/app/analise/:id`

**Por que na tela de detalhe e nao apenas na fila:**
Um ANALISTA pode acessar o detalhe de um processo a partir de uma busca ou link direto. Nesse caso ele nao estaria navegando via fila. O botao garante que a acao de analise esta disponivel em qualquer ponto de entrada.

**Uso de `<a mat-raised-button>` com `[routerLink]`:**
Segue o mesmo padrao estabelecido em F3. O elemento `<a>` com aparencia de botao Material e semanticamente correto para navegacao e suporta Ctrl+Click para abrir em nova aba.

---

## Scripts de infraestrutura

### `sprint-f4-deploy.ps1` -- Script principal

**Localizacao:**
- Local: `C:\SOL\infra\scripts\sprint-f4-deploy.ps1`
- Servidor: `C:\SOL\infra\scripts\sprint-f4-deploy.ps1` (via Y:\)
- **Estado:** Presente. Nao executado ainda.
- **Encoding:** ASCII-only (licao aprendida com F3 -- sem Unicode).

**Verificacoes de conteudo na Etapa 2:**

| Arquivo | Verificacao | Razao |
|---|---|---|
| `analise.model.ts` | contem `CiaCreateDTO` | Interface base do CIA |
| `analise.model.ts` | contem `IndeferimentoCreateDTO` | Interface do indeferimento |
| `analise-fila.component.ts` | contem `AnaliseFilaComponent` | Confirma classe exportada |
| `licenciamento-analise.component.ts` | contem `LicenciamentoAnaliseComponent` | Confirma classe |
| `licenciamento-analise.component.ts` | contem `confirmarCia()` | Metodo central do CIA |
| `licenciamento.service.ts` | contem `getFilaAnalise` | Endpoint da fila |
| `licenciamento.service.ts` | contem `emitirCia` | Endpoint CIA |
| `app.routes.ts` | contem `analise-fila.component` | Rota /analise ativa (nao placeholder) |
| `app.routes.ts` | contem `licenciamento-analise.component` | Rota /analise/:id ativa |
| `licenciamento-detalhe.component.ts` | contem `podeAnalisar` | Botao ativo no detalhe |

---

### `run-sprint-f4.ps1` -- Launcher com captura de log

**Localizacoes:**
- Local: `C:\SOL\logs\run-sprint-f4.ps1`
- Servidor: `C:\SOL\logs\run-sprint-f4.ps1` (via Y:\)
- **Estado:** Presente. Nao executado ainda.

Saidas geradas apos execucao:
- `C:\SOL\logs\sprint-f4-run-output.txt` -- log completo
- `C:\SOL\logs\sprint-f4-run-exitcode.txt` -- exit code (0 = sucesso)

---

## Verificacao pos-deploy

### Cenario 1 -- Fila de analise acessivel para ANALISTA

1. Fazer login como ANALISTA
2. Acessar `/app/analise`
3. **Esperado:** tabela de processos com colunas Numero PPCI / Tipo / Status / Municipio / Area / Entrada / Acoes
4. **Esperado:** processos com status `ANALISE_PENDENTE` (laranja) e `EM_ANALISE` (azul) aparecem

### Cenario 2 -- Fila inacessivel para CIDADAO

1. Fazer login como CIDADAO
2. Acessar `/app/analise` (diretamente na URL)
3. **Esperado:** redirecionamento pelo `roleGuard` (403 ou redirect para dashboard)

### Cenario 3 -- Iniciar Analise

1. Login como ANALISTA
2. Na fila, clicar em "Analisar" em um processo com status `ANALISE_PENDENTE`
3. **Esperado:** tela de analise carregada, painel de acoes visivel com botao "Iniciar Analise"
4. Clicar em "Iniciar Analise"
5. **Esperado:** status atualizado para `EM_ANALISE`, tres botoes aparecem (CIA / Deferir / Indeferir)

### Cenario 4 -- Emitir CIA

1. Na tela de analise (status `EM_ANALISE`), clicar em "Emitir CIA"
2. **Esperado:** formulario inline aparece abaixo dos botoes
3. Preencher descricao da inconformidade, norma referencia (opcional), prazo (padrao 30)
4. Clicar em "Adicionar inconformidade" e preencher segundo item
5. Clicar em "Confirmar CIA"
6. **Esperado:** spinner no botao, chamada `POST /api/licenciamentos/{id}/cia`, status muda para `CIA_EMITIDO`, painel de acoes desaparece

### Cenario 5 -- Validacao do CIA (item sem descricao)

1. Clicar em "Emitir CIA"
2. Deixar o campo "Inconformidade 1" vazio e clicar em "Confirmar CIA"
3. **Esperado:** botao desabilitado (invalid form), campo com borda vermelha + mensagem de erro

### Cenario 6 -- Deferir

1. Na tela de analise (status `EM_ANALISE`), clicar em "Deferir"
2. **Esperado:** formulario de deferimento com campo observacao opcional e aviso sobre proximo status
3. Clicar em "Confirmar Deferimento"
4. **Esperado:** `POST /api/licenciamentos/{id}/deferir` e redirecionamento para `/app/analise`

### Cenario 7 -- Indeferir com validacao

1. Na tela de analise, clicar em "Indeferir"
2. Digitar apenas "curto" no campo justificativa (menos de 20 chars) e tentar confirmar
3. **Esperado:** botao desabilitado + mensagem "Justificativa deve ter ao menos 20 caracteres"
4. Preencher justificativa adequada e confirmar
5. **Esperado:** `POST /api/licenciamentos/{id}/indeferir` e redirect para `/app/analise`

### Cenario 8 -- Botao "Abrir Analise Tecnica" no detalhe

1. Login como ANALISTA
2. Acessar `/app/licenciamentos/{id}` de um processo `ANALISE_PENDENTE`
3. **Esperado:** botao "Abrir Analise Tecnica" (azul) visivel no topo direito
4. Login como CIDADAO, mesmo processo
5. **Esperado:** botao NAO aparece

### Cenario 9 -- Toggle de formulario (fechar sem confirmar)

1. Na tela de analise, clicar em "Emitir CIA"
2. Formulario abre
3. Clicar novamente em "Emitir CIA"
4. **Esperado:** formulario fecha (toggle -- sem necessidade de botao Cancelar)
5. Alternativamente, clicar em "Cancelar"
6. **Esperado:** formulario fecha, dados digitados sao descartados

---

## Proximos passos (Sprint F5)

A Sprint F5 corresponde ao processo P07 -- Vistoria Presencial.

Entregas previstas para F5:
- Fila de vistorias para `INSPETOR` e `CHEFE_SSEG_BBM`
- Agendamento de vistoria (data / hora / inspetor)
- Emissao de CIV (Comunicado de Inconformidade na Vistoria)
- Laudo de vistoria: aprovacao (-> PRPCI_EMITIDO) ou reprovacao (-> CIV_EMITIDO)

---

## Log de alteracoes

| Data | Versao | Descricao |
|---|---|---|
| 2026-04-07 | 1.0 | Criacao inicial -- Sprint F4 completa (3 novos + 3 atualizados + 2 scripts) |
| 2026-04-08 | 1.1 | Sincronizacao Y:\ concluida -- 8 arquivos gravados/atualizados no servidor; Passo 1 marcado como JA CONCLUIDO; removidas instrucoes de sync-f4-to-server.ps1 |
