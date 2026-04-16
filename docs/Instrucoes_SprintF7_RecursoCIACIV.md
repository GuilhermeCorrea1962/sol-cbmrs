# Sprint F7 — Recurso CIA/CIV (P10)

**Processo:** P10 — Recurso contra CIA ou CIV
**Pre-requisito:** Sprints F1 a F6 + Manutencao F3 executadas com sucesso
**Verificacao de pre-requisito:** presenca de `appci.model.ts` no servidor

---

## Contexto do processo

Quando o Analista emite um CIA (Comunicado de Inconformidade na Analise, Sprint F4) ou o Inspetor emite um CIV (Comunicado de Inconformidade na Vistoria, Sprint F5), o Responsavel Tecnico (RT) tem o direito de contestar esse ato administrativo por meio de um **recurso**. O P10 implementa o fluxo completo: do protocolo pelo RT ate a decisao final pela comissao.

### Fluxo de status

```
CIA_EMITIDO ou CIV_EMITIDO
    |
    | RT submete recurso (justificativa)
    v
RECURSO_SUBMETIDO
    |           |
    | Admin      | Admin
    | aceita     | recusa
    v           v
RECURSO_EM_ANALISE    CIA_EMITIDO / CIV_EMITIDO (retorna)
    |
    | Analistas votam (cada um: DEFERIDO ou INDEFERIDO)
    |
    | Admin registra decisao final
    v
RECURSO_DEFERIDO               RECURSO_INDEFERIDO
(licenciamento volta ao fluxo)  (CIA/CIV e mantido)
```

### Regra de negocio critica (RN-089)

Enquanto houver um recurso ativo (`RECURSO_SUBMETIDO` ou `RECURSO_EM_ANALISE`), o licenciamento fica **bloqueado** para nova analise ou vistoria. O backend e responsavel por fazer cumprir essa regra.

---

## Arquivos a copiar para o servidor

Copie a pasta `C:\SOL\` inteira **ou** os arquivos abaixo individualmente para os mesmos caminhos relativos em `C:\SOL\` no servidor:

### Novos arquivos (nao existem no servidor)

| Arquivo local | Caminho no servidor |
|---|---|
| `frontend\src\app\core\models\recurso.model.ts` | `C:\SOL\frontend\src\app\core\models\recurso.model.ts` |
| `frontend\src\app\pages\recurso\recurso-fila\recurso-fila.component.ts` | `C:\SOL\frontend\src\app\pages\recurso\recurso-fila\recurso-fila.component.ts` |
| `frontend\src\app\pages\recurso\recurso-detalhe\recurso-detalhe.component.ts` | `C:\SOL\frontend\src\app\pages\recurso\recurso-detalhe\recurso-detalhe.component.ts` |
| `infra\scripts\sprint-f7-deploy.ps1` | `C:\SOL\infra\scripts\sprint-f7-deploy.ps1` |
| `logs\run-sprint-f7.ps1` | `C:\SOL\logs\run-sprint-f7.ps1` |

### Arquivos modificados (substituir no servidor)

| Arquivo local | Caminho no servidor |
|---|---|
| `frontend\src\app\core\services\licenciamento.service.ts` | `C:\SOL\frontend\src\app\core\services\licenciamento.service.ts` |
| `frontend\src\app\app.routes.ts` | `C:\SOL\frontend\src\app\app.routes.ts` |
| `frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` | `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-detalhe\licenciamento-detalhe.component.ts` |

---

## Instrucao para o Claude Code no servidor

```
Execute o script de deploy da Sprint F7:
  C:\SOL\logs\run-sprint-f7.ps1

Apos a execucao, leia o relatorio em C:\SOL\logs\sprint-f7-relatorio-deploy.md e informe:
1. Se todas as 7 etapas concluiram sem erros
2. Se houve warnings de budget CSS ou NG8011 no build
3. Quantos chunks JS foram gerados
4. Se o smoke test retornou HTTP 200
```

---

## Detalhamento das etapas do script

### Etapa 1 — Pre-verificacao do ambiente

**O que faz:** Verifica Node.js no PATH, diretorio `C:\SOL\frontend`, `package.json` e a presenca de `appci.model.ts` (confirma que F6 esta presente).

**Por que e necessaria:** Impede que o build falhe por razoes de ambiente (Node nao instalado, caminho errado) ou por pre-requisito ausente. O `appci.model.ts` foi escolhido como marcador porque foi o ultimo arquivo novo criado em F6.

**O que esperar:** 4 linhas `[OK]`. Se `appci.model.ts` estiver ausente, o script aborta com instrucao para executar F1-F6 antes.

---

### Etapa 2 — Verificacao dos fontes F7

**O que faz:** Confirma que os 3 novos arquivos TypeScript foram copiados para o servidor. Tambem verifica se a secao F7 foi adicionada ao `licenciamento.service.ts` (busca pelo comentario `Sprint F7`), se a rota `/recursos` esta em `app.routes.ts` e se o formulario de recurso esta em `licenciamento-detalhe.component.ts`.

**Por que e necessaria:** Evita compilar um build incompleto. Se um dos arquivos estiver ausente, o `ng build` falharia com erros de modulo nao encontrado ou referencia indefinida — erros menos claros do que "arquivo ausente". A verificacao antecipada da mensagem de erro mais direta.

**O que esperar:**
```
[OK] Presente: src\app\core\models\recurso.model.ts
[OK] Presente: src\app\pages\recurso\recurso-fila\recurso-fila.component.ts
[OK] Presente: src\app\pages\recurso\recurso-detalhe\recurso-detalhe.component.ts
[OK] licenciamento.service.ts: secao F7 presente
[OK] app.routes.ts: rota /recursos presente
[OK] licenciamento-detalhe.component.ts: formulario Submeter Recurso presente
```

---

### Etapa 3 — npm ci

**O que faz:** Executa `npm ci` para garantir que todas as dependencias do `package.json` estao instaladas na versao exata do `package-lock.json`.

**Por que e necessaria:** O `npm ci` e mais seguro que `npm install` em ambientes de CI/CD porque usa o lockfile e falha se houver divergencia. Garante reproducibilidade do build entre maquinas. E necessario sempre que o `package.json` pode ter mudado entre sprints.

**O que esperar:** Saida do npm sem erros. Pode levar 1-3 minutos na primeira execucao ou quando o `node_modules` nao existe.

---

### Etapa 4 — Build de producao

**O que faz:** Executa `npx ng build --configuration production`, que compila o Angular com otimizacoes, tree-shaking e minificacao. Detecta e reporta warnings de budget CSS e NG8011.

**Por que e necessaria:** E a etapa principal — converte o codigo TypeScript/HTML/CSS em chunks JavaScript otimizados para producao. A flag `--configuration production` ativa AOT (Ahead-of-Time compilation), minificacao e remocao de codigo de desenvolvimento.

**O que esperar:**
- `[OK] Nenhum warning de budget CSS` — se o CSS de todos os componentes estiver dentro dos limites do `angular.json`
- `[OK] Nenhum warning NG8011` — se todos os templates com `@if`/`@else` tiverem um unico no raiz em cada bloco
- `[OK] Build concluido com sucesso (exit code 0)`
- `[INFO] Chunks JS gerados: XX` — esperado em torno de 36-38 chunks (F6 gerou 34; F7 adiciona 2 novos lazy chunks)

**Nota sobre novos chunks:** Cada `loadComponent` lazy no `app.routes.ts` gera um chunk JS separado. A Sprint F7 adiciona 2 novas rotas lazy (`recurso-fila` e `recurso-detalhe`), portanto o total de chunks deve aumentar em ~2 em relacao a F6.

---

### Etapa 5 — Deploy para Nginx

**O que faz:** Copia recursivamente todos os arquivos de `dist\sol-frontend\browser` para `C:\nginx\html\sol`, criando subdiretorios conforme necessario. Verifica que `index.html` chegou ao destino.

**Por que e necessaria:** O Nginx serve os arquivos estaticos do frontend a partir de `C:\nginx\html\sol`. Sem esta etapa, o build novo ficaria em `dist\` mas o usuario continuaria vendo a versao anterior.

**O que esperar:**
```
[INFO] Copiando arquivos de C:\SOL\frontend\dist\sol-frontend\browser para C:\nginx\html\sol ...
[OK] index.html copiado para C:\nginx\html\sol
```

---

### Etapa 6 — Reinicializacao do Nginx e smoke test

**O que faz:** Reinicia o servico Nginx (tenta `sol-nginx` primeiro, depois `nginx`) para que ele carregue os novos arquivos. Executa um `GET http://localhost/` e verifica HTTP 200.

**Por que e necessaria:** O Nginx pode ter o `index.html` anterior em cache de processo. O restart garante que o novo `index.html` seja servido. O smoke test confirma que a aplicacao esta respondendo corretamente apos o restart.

**O que esperar:**
```
[OK] Servico nginx reiniciado
[OK] HTTP 200 OK - aplicacao acessivel
```

---

### Etapa 7 — Relatorio de deploy

**O que faz:** Gera o arquivo `C:\SOL\logs\sprint-f7-relatorio-deploy.md` com data/hora, status geral, contagem de chunks, warnings e tabelas de arquivos e endpoints.

**Por que e necessaria:** Cria um registro permanente do deploy para rastreabilidade. O relatorio e estruturado em Markdown para ser legivel no Obsidian ou em qualquer editor de texto.

**O que esperar:**
```
[OK] Relatorio gerado: C:\SOL\logs\sprint-f7-relatorio-deploy.md
```

---

## Detalhamento dos arquivos gerados

### `recurso.model.ts`

Define os 4 DTOs de entrada para as operacoes do recurso:

| DTO | Endpoint | Campos |
|---|---|---|
| `RecursoSubmeterDTO` | `POST /submeter-recurso` | `justificativa: string` (min 50 chars) |
| `RecursoRecusarDTO` | `POST /recusar-recurso` | `motivo: string` |
| `RecursoVotoDTO` | `POST /votar-recurso` | `decisao: 'DEFERIDO'\|'INDEFERIDO'`, `justificativa: string` (min 30 chars) |
| `RecursoDecisaoDTO` | `POST /decidir-recurso` | `decisao: 'DEFERIDO'\|'INDEFERIDO'`, `fundamentacao: string` (min 50 chars) |

---

### `recurso-fila.component.ts`

**Rota:** `/app/recursos`
**Roles:** `ANALISTA`, `ADMIN`, `CHEFE_SSEG_BBM`
**Endpoint consumido:** `GET /api/licenciamentos/fila-recurso`

Exibe uma tabela com os licenciamentos em status `RECURSO_SUBMETIDO` (aguardando triagem) e `RECURSO_EM_ANALISE` (votacao em andamento). Cada linha e clicavel e navega para `/app/recursos/:id`.

Colunas: numero, tipo, status (badge colorido), municipio, area construida, data de atualizacao, icone de acao.

---

### `recurso-detalhe.component.ts`

**Rota:** `/app/recursos/:id`
**Roles:** `ANALISTA`, `ADMIN`, `CHEFE_SSEG_BBM`

Componente de acao multiuso: o painel exibido depende do status do licenciamento e do perfil do usuario autenticado. Usa o tipo local `AcaoAtiva = 'recusar' | 'votar' | 'decidir' | null` para controlar qual formulario esta aberto.

| Status | Perfil | Painel exibido |
|---|---|---|
| `RECURSO_SUBMETIDO` | `ADMIN`/`CHEFE_SSEG_BBM` | Triagem: botoes Aceitar (POST direto) e Recusar (abre form com `motivo`) |
| `RECURSO_EM_ANALISE` | `ANALISTA`/`CHEFE_SSEG_BBM` | Votacao: abre form com radio Deferido/Indeferido e `justificativa` |
| `RECURSO_EM_ANALISE` | `ADMIN`/`CHEFE_SSEG_BBM` | Decisao final: abre form com radio e `fundamentacao` |
| `RECURSO_DEFERIDO` | qualquer | Painel verde com resultado |
| `RECURSO_INDEFERIDO` | qualquer | Painel vermelho com resultado |
| `RECURSO_SUBMETIDO` | sem podeTriar | Painel informativo "aguardando triagem" |

**Notas de implementacao:**
- `podeTriar = hasAnyRole(['ADMIN', 'CHEFE_SSEG_BBM'])` — triagem e decisao final
- `podeVotar = hasAnyRole(['ANALISTA', 'CHEFE_SSEG_BBM'])` — votacao da comissao
- `CHEFE_SSEG_BBM` pode fazer ambos (votar E triar), portanto vera os dois paineis quando o status for `RECURSO_EM_ANALISE`
- Apos `aceitar-recurso`: status atualizado in-place (sem navegar)
- Apos `recusar-recurso`, `votar-recurso`, `decidir-recurso`: navega de volta para `/app/recursos`

---

### Modificacao em `licenciamento.service.ts`

Adicionada a secao `// Sprint F7 -- Recurso CIA/CIV (P10)` com 6 novos metodos:

```typescript
getFilaRecurso(page?, size?)            // GET  /fila-recurso
submeterRecurso(id, dto)                // POST /{id}/submeter-recurso
aceitarRecurso(id)                      // POST /{id}/aceitar-recurso
recusarRecurso(id, dto)                 // POST /{id}/recusar-recurso
votarRecurso(id, dto)                   // POST /{id}/votar-recurso
decidirRecurso(id, dto)                 // POST /{id}/decidir-recurso
```

---

### Modificacao em `app.routes.ts`

Adicionado bloco de rota antes do placeholder `usuarios`:

```typescript
{
  path: 'recursos',
  canActivate: [roleGuard],
  data: { roles: ['ANALISTA', 'ADMIN', 'CHEFE_SSEG_BBM'] },
  children: [
    { path: '',   loadComponent: () => import('./pages/recurso/recurso-fila/...') },
    { path: ':id', loadComponent: () => import('./pages/recurso/recurso-detalhe/...') }
  ]
}
```

O placeholder `usuarios` foi renomeado internamente para "Gestao de usuarios — placeholder ate Sprint futura" (o conteudo nao mudou, apenas o comentario).

---

### Modificacao em `licenciamento-detalhe.component.ts`

Adicionados ao componente:

1. **Imports novos:** `ReactiveFormsModule`, `MatFormFieldModule`, `MatInputModule`, `MatProgressSpinnerModule` (na lista `imports[]` do decorador), `FormBuilder`, `FormGroup`, `Validators` (nos imports TypeScript)

2. **Novos membros de classe:**
   - `readonly podeSubmeterRecurso = !this.auth.hasAnyRole(['ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM'])` — verdadeiro para RT/cidadao
   - `recursoAberto = signal(false)` — controla visibilidade do formulario
   - `salvandoRecurso = signal(false)` — controla estado do botao de submit
   - `recursoForm: FormGroup` — inicializado no `ngOnInit` com campo `justificativa` (required, minLength 50)

3. **Novo metodo:** `confirmarRecurso(id)` — chama `svc.submeterRecurso()`, atualiza o sinal `lic` com o novo status e fecha o formulario

4. **Template:** Bloco adicionado apos o botao "Emitir APPCI":
   - Guardado por `podeSubmeterRecurso && (status === 'CIA_EMITIDO' || status === 'CIV_EMITIDO')`
   - Primeiro estado: botao "Submeter Recurso" (color="warn")
   - Segundo estado (`recursoAberto()`): `<mat-card>` expandido com textarea e botoes Cancelar/Confirmar

**Justificativa da escolha de formulario inline:** O RT nao tem acesso a rota `/app/recursos` (protegida por roles de staff). Criar uma rota separada para RT exigiria ou ampliar o `roleGuard` ou criar uma rota publica — ambos comprometendo a separacao de perfis. O formulario inline na tela de detalhe, ja acessivel ao RT, e a solucao mais limpa.

---

## Resultado esperado apos execucao bem-sucedida

```
[OK] Pre-requisito F6: appci.model.ts presente
[OK] Presente: src\app\core\models\recurso.model.ts
[OK] Presente: src\app\pages\recurso\recurso-fila\recurso-fila.component.ts
[OK] Presente: src\app\pages\recurso\recurso-detalhe\recurso-detalhe.component.ts
[OK] licenciamento.service.ts: secao F7 presente
[OK] app.routes.ts: rota /recursos presente
[OK] licenciamento-detalhe.component.ts: formulario Submeter Recurso presente
[OK] npm ci concluido
[OK] Nenhum warning de budget CSS
[OK] Nenhum warning NG8011
[OK] Build concluido com sucesso (exit code 0)
[INFO] Chunks JS gerados: 36  (ou 37, dependendo do lazy splitting do Angular)
[OK] Chunks JavaScript presentes no dist
[OK] index.html copiado para C:\nginx\html\sol
[OK] Servico nginx reiniciado
[OK] HTTP 200 OK - aplicacao acessivel
[OK] Relatorio gerado: C:\SOL\logs\sprint-f7-relatorio-deploy.md
  SPRINT F7 CONCLUIDA COM SUCESSO
```

---

## Estado do frontend apos Sprint F7

| Sprint | Processo | Rota | Status |
|---|---|---|---|
| F1 | Login / Auth | `/login` | Concluido |
| F2 | Lista e detalhe de licenciamentos | `/app/licenciamentos` | Concluido |
| F3 | Wizard novo licenciamento | `/app/licenciamentos/novo` | Concluido |
| F4 | Analise Tecnica (CIA / deferir / indeferir) | `/app/analise` | Concluido |
| F5 | Vistoria Presencial (CIV / aprovar) | `/app/vistorias` | Concluido |
| F6 | Emissao de APPCI | `/app/appci` | Concluido |
| MF3 | Correcao budget CSS + NG8011 | — | Concluido |
| **F7** | **Recurso CIA/CIV** | **`/app/recursos`** | **Esta sprint** |
| — | Gestao de usuarios | `/app/usuarios` | Placeholder |
| — | Relatorios | `/app/relatorios` | Placeholder |
