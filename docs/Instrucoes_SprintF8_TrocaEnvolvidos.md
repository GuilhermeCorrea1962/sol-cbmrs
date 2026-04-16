# Sprint F8 — Troca de Envolvidos (P09)

**Data:** 2026-04-13
**Pre-requisito:** Sprints F1-F7 + Manutencao F3 concluidas
**Processo:** P09 — Troca de Envolvidos (RT solicita saida; Admin aprova/rejeita)

---

## Contexto do processo

O P09 trata da substituicao do Responsavel Tecnico (RT) em um licenciamento ativo.
O RT atual pode solicitar sua propria saida a qualquer momento durante o fluxo de
licenciamento (exceto em status terminais como EXTINTO, APPCI_EMITIDO, etc.).
A solicitacao e analisada pelo administrador (ADMIN/CHEFE_SSEG_BBM), que pode:

- **Aceitar**: o sistema notifica o novo RT para que ele se associe ao licenciamento.
- **Rejeitar**: a solicitacao e cancelada; o RT permanece no licenciamento.

### Diagrama de status (campo trocaPendente)

```
RT solicita -> trocaPendente = true
Admin aceita -> aguarda novo RT (trocaPendente ainda true ate confirmacao)
Admin rejeita -> trocaPendente = false
```

### Restricao RN-089 (bloqueio durante recurso)

Se houver recurso ativo (status RECURSO_SUBMETIDO ou RECURSO_EM_ANALISE), o
backend bloqueia a solicitacao de troca. O frontend so apresenta o botao em
status ativos nao terminais; o backend e a ultima linha de defesa.

---

## Arquivos da Sprint F8

### Novos arquivos

| Arquivo em C:\SOL | Tipo | Descricao |
|---|---|---|
| `frontend\src\app\core\models\troca-envolvidos.model.ts` | NOVO | DTOs: TrocaSolicitarDTO, TrocaAceitarDTO, TrocaRejeitarDTO |
| `frontend\src\app\pages\troca-envolvidos\troca-fila\troca-fila.component.ts` | NOVO | Tabela de trocas pendentes (ADMIN/CHEFE) |
| `frontend\src\app\pages\troca-envolvidos\troca-detalhe\troca-detalhe.component.ts` | NOVO | Aceitar/rejeitar solicitacao (ADMIN/CHEFE) |
| `infra\scripts\sprint-f8-deploy.ps1` | NOVO | Script de deploy 7 etapas |
| `logs\run-sprint-f8.ps1` | NOVO | Launcher com captura de log |

### Arquivos modificados

| Arquivo em C:\SOL | Tipo | Modificacao |
|---|---|---|
| `frontend\src\app\core\models\licenciamento.model.ts` | ATUALIZADO | +trocaPendente, +justificativaTroca no LicenciamentoDTO |
| `frontend\src\app\core\services\licenciamento.service.ts` | ATUALIZADO | +secao Sprint F8 com 4 metodos |
| `frontend\src\app\app.routes.ts` | ATUALIZADO | +rota /app/trocas com filhos lazy |
| `frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` | ATUALIZADO | +formulario Solicitar Troca + painel info |

---

## Instrucao para o Claude Code no servidor

```
Copie para C:\SOL os arquivos da Sprint F8 listados abaixo (criar diretorios novos conforme necessario):

NOVOS:
- C:\SOL\frontend\src\app\core\models\troca-envolvidos.model.ts
- C:\SOL\frontend\src\app\pages\troca-envolvidos\troca-fila\troca-fila.component.ts
- C:\SOL\frontend\src\app\pages\troca-envolvidos\troca-detalhe\troca-detalhe.component.ts
- C:\SOL\infra\scripts\sprint-f8-deploy.ps1
- C:\SOL\logs\run-sprint-f8.ps1

ATUALIZADOS (substituir conteudo):
- C:\SOL\frontend\src\app\core\models\licenciamento.model.ts
- C:\SOL\frontend\src\app\core\services\licenciamento.service.ts
- C:\SOL\frontend\src\app\app.routes.ts
- C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts

Apos copiar todos os arquivos, execute:
  powershell -ExecutionPolicy Bypass -File "C:\SOL\logs\run-sprint-f8.ps1"

Resultado esperado: exit code 0, sem warnings de budget CSS, sem warnings NG8011.
Relatorio gerado em: C:\SOL\logs\sprint-f8-relatorio-deploy.md
```

---

## Detalhamento de cada etapa do script de deploy

### Etapa 1 — Pre-verificacao do ambiente

Verifica:
- Node.js disponivel no PATH
- Diretorio `C:\SOL\frontend` existe
- `package.json` presente
- Pre-requisito F7: `recurso.model.ts` presente (garante que F1-F7 foram executadas)

**Por que:** Evita falhas silenciosas causadas por ambiente incompleto.
Aborta com exit 1 se qualquer pre-requisito estiver ausente.

### Etapa 2 — Verificacao dos fontes F8

Verifica a presenca dos 3 novos arquivos TypeScript e 4 marcadores nos arquivos
modificados:

| Verificacao | Arquivo | Marcador |
|---|---|---|
| Campo trocaPendente | licenciamento.model.ts | string `trocaPendente` |
| Secao F8 | licenciamento.service.ts | string `Sprint F8` |
| Rota trocas | app.routes.ts | string `troca-fila` |
| Formulario troca | licenciamento-detalhe.component.ts | string `podeSubmeterTroca` |

**Por que:** Se qualquer arquivo foi copiado incorretamente ou o conteudo
esta truncado, o build vai falhar com erros de compilacao TypeScript.
A etapa 2 detecta isso antes de desperdicar 3-5 minutos no build.

### Etapa 3 — npm ci

Executa `npm ci` no diretorio do frontend para garantir que todas as dependencias
Angular/Material estao instaladas em versoes exatas do `package-lock.json`.

**Por que:** Preferido a `npm install` em ambientes de CI/CD pois e deterministico
e falha se o `package-lock.json` estiver desatualizado (protege contra drift).

### Etapa 4 — Build de producao

Executa `npx ng build --configuration production`.

Apos o build, o script verifica automaticamente:
- Warnings `exceeded maximum budget` (CSS acima do limite configurado)
- Warnings `NG8011` (elementos desconhecidos no template Angular)
- Numero de chunks JS gerados (indicador de saude do bundle)

**Por que F8 nao deve gerar warnings NG8011:**
- `troca-fila` e `troca-detalhe` importam todos os modulos Material necessarios
  no array `imports[]` do proprio componente (standalone pattern).
- Todos os `@if/@else` com `<mat-spinner>` usam `<ng-container>` wrapper,
  conforme correcao aplicada na Manutencao F3.

**Por que F8 nao deve gerar warnings de budget CSS:**
- Os componentes usam CSS inline (styles: [``]) sem arquivos .scss separados.
- O CSS adicionado em `licenciamento-detalhe` e minimo (5 regras: troca-action-bar,
  troca-form-card, troca-info-card, troca-info-row, troca-info-row mat-icon).

### Etapa 5 — Deploy para Nginx

Copia todos os arquivos de `C:\SOL\frontend\dist\sol-frontend\browser\` para
`C:\nginx\html\sol\`, sobrescrevendo os arquivos existentes da sprint anterior.

**Por que sobrescrever:** O Angular CLI gera nomes de chunk com hash de conteudo
(ex: `main.abc123.js`). A cada build, os hashes mudam. E necessario substituir
os arquivos antigos para que o navegador sirva a versao correta.

### Etapa 6 — Reinicializacao do Nginx e smoke test

Reinicia o servico Nginx (`sol-nginx` ou `nginx`) e faz uma requisicao HTTP GET
a `http://localhost/`. Espera HTTP 200.

**Por que o smoke test e necessario:** Confirma que o Nginx esta servindo o
`index.html` correto. Um HTTP 200 garante que o SPA esta acessivel; nao valida
a autenticacao nem o backend (esses sao testados manualmente apos o deploy).

### Etapa 7 — Relatorio de deploy

Gera `C:\SOL\logs\sprint-f8-relatorio-deploy.md` com:
- Data/hora, status (SUCESSO ou ERROS: N)
- Numero de chunks JS
- Warnings detectados (budget, NG8011)
- Tabela de arquivos novos e modificados
- Tabela de endpoints consumidos

**Por que:** Permite rastreabilidade de qual versao foi deployada e quando.
Util para auditoria e para diagnostico de regressoes.

---

## Arquitetura dos componentes implementados

### troca-envolvidos.model.ts

Define 3 interfaces DTO alinhadas com os endpoints backend de P09:

```typescript
TrocaSolicitarDTO  { justificativa: string }          // min 30 chars
TrocaAceitarDTO   { observacao?: string }             // opcional
TrocaRejeitarDTO  { motivo: string }                  // min 20 chars
```

### troca-fila.component.ts (seletor: sol-troca-fila)

Tabela Material com 7 colunas: numero, tipo, status, municipio, area, entrada, acoes.
Consome `getFilaTrocaPendente()` que chama `GET /api/licenciamentos/fila-troca`.
Estado vazio mostra icone `people` com mensagem descritiva.
Cada linha e clicavel e navega para `/app/trocas/:id`.

**Acesso:** Somente ADMIN e CHEFE_SSEG_BBM (`roleGuard` na rota pai `/app/trocas`).

### troca-detalhe.component.ts (seletor: sol-troca-detalhe)

Controla 2 acoes com `type AcaoAtiva = 'aceitar' | 'rejeitar' | null`:

| Condicao | Painel exibido |
|---|---|
| `podeGerenciar && l.trocaPendente && acaoAtiva === null` | Botoes Aceitar / Rejeitar |
| `acaoAtiva === 'aceitar'` | Form com observacao opcional + Confirmar Aceite |
| `acaoAtiva === 'rejeitar'` | Form com motivo obrigatorio (min 20) + Confirmar Rejeicao |
| `!l.trocaPendente` | Painel info "solicitacao ja processada" |

Apos aceitar ou rejeitar: navega de volta para `/app/trocas`.
Aceitar atualiza o lic no signal antes de navegar (reflexo imediato na UI).

### licenciamento-detalhe.component.ts — modificacoes F8

Adicoes ao componente ja existente (que ja tem F7 — Submeter Recurso):

**Novo campo:**
```typescript
readonly podeSubmeterTroca = !this.auth.hasAnyRole([...staff roles...]);
private readonly STATUSES_TERMINAL_TROCA = new Set([...]);
```

**Novo metodo helper:**
```typescript
isStatusAtivoParaTroca(status: string): boolean {
  return !this.STATUSES_TERMINAL_TROCA.has(status);
}
```

**Logica do template (3 estados):**

| Condicao | Exibicao |
|---|---|
| `podeSubmeterTroca && isStatusAtivoParaTroca && !l.trocaPendente && !trocaAberta()` | Botao "Solicitar Troca de RT" (stroked, color=primary) |
| `podeSubmeterTroca && isStatusAtivoParaTroca && !l.trocaPendente && trocaAberta()` | Card expandido com textarea (min 30 chars) + botoes Cancelar/Enviar |
| `podeSubmeterTroca && isStatusAtivoParaTroca && l.trocaPendente` | Card informativo laranja "aguardando aprovacao" |

**Justificativa para formulario inline (nao nova rota):**
O RT nao tem acesso a `/app/trocas` (rota exclusiva ADMIN/CHEFE). Criar uma rota
separada para o RT comprometeria o RBAC. O formulario inline em `licenciamento-detalhe`
(ja acessivel ao RT) e a abordagem correta, identica ao padrao do F7 (Recurso).

---

## Estado do frontend apos Sprint F8

| Sprint | Processo | Rota | Roles |
|---|---|---|---|
| F1 | Infra/Login | /login | publica |
| F2 | Licenciamentos | /app/licenciamentos | todos |
| F3 | Novo Licenciamento | /app/licenciamentos/novo | CIDADAO, ADMIN |
| F4 | Analise Tecnica | /app/analise | ANALISTA, CHEFE_SSEG_BBM |
| F5 | Vistoria | /app/vistorias | INSPETOR, CHEFE_SSEG_BBM |
| F6 | APPCI | /app/appci | ADMIN, CHEFE_SSEG_BBM |
| F7 | Recurso CIA/CIV | /app/recursos | ANALISTA, ADMIN, CHEFE_SSEG_BBM |
| **F8** | **Troca de Envolvidos** | **/app/trocas** | **ADMIN, CHEFE_SSEG_BBM** |

---

## Resultado esperado apos execucao bem-sucedida

```
ETAPA 1 - Pre-verificacao do ambiente
  [OK]  Node.js: v20.x.x
  [OK]  Diretorio frontend: C:\SOL\frontend
  [OK]  package.json encontrado
  [OK]  Pre-requisito F7: recurso.model.ts presente

ETAPA 2 - Verificacao dos fontes F8
  [OK]  Presente: src\app\core\models\troca-envolvidos.model.ts
  [OK]  Presente: src\app\pages\troca-envolvidos\troca-fila\troca-fila.component.ts
  [OK]  Presente: src\app\pages\troca-envolvidos\troca-detalhe\troca-detalhe.component.ts
  [OK]  licenciamento.model.ts: campo trocaPendente presente
  [OK]  licenciamento.service.ts: secao F8 presente
  [OK]  app.routes.ts: rota /trocas presente
  [OK]  licenciamento-detalhe.component.ts: formulario Solicitar Troca presente

ETAPA 3 - npm ci
  [OK]  npm ci concluido

ETAPA 4 - Build de producao
  [OK]  Nenhum warning de budget CSS
  [OK]  Nenhum warning NG8011
  [OK]  Build concluido com sucesso (exit code 0)
  [INFO] Chunks JS gerados: 38+

ETAPA 5 - Deploy dos assets
  [OK]  index.html copiado para C:\nginx\html\sol

ETAPA 6 - Nginx e smoke test
  [OK]  Servico nginx reiniciado
  [OK]  HTTP 200 OK - aplicacao acessivel

ETAPA 7 - Relatorio
  [OK]  Relatorio gerado: C:\SOL\logs\sprint-f8-relatorio-deploy.md

  SPRINT F8 CONCLUIDA COM SUCESSO
```
