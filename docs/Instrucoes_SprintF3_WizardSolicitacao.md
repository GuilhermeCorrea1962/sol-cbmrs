# Sprint F3 — Wizard de Solicitacao de Licenciamento

**Data de criacao:** 2026-04-07
**Ultima atualizacao:** 2026-04-07
**Sprint anterior:** F2 — Modulo de Licenciamentos (lista + detalhe)
**Objetivo:** Implementar o wizard MatStepper de 4 passos para criacao e envio de novas solicitacoes de licenciamento PPCI e PSPCIM (processo P03 do BPMN).

---

## Estado atual da sprint

> **Situacao em 2026-04-07:** Sprint F3 **DEPLOYADA COM SUCESSO** no servidor. Build concluido em 5.519s, 24 chunks JS gerados, HTTP 200 confirmado. O script apresentou falha de encoding (UTF-8 sem BOM) na primeira execucao -- corrigido pelo Claude Code no servidor antes do deploy. Script local e servidor agora estao sincronizados (versao ASCII-only).

### Mapa de progresso

| Etapa | Responsavel | Status |
|---|---|---|
| Gerar arquivos-fonte Angular em `C:\SOL` | Claude Code (local) | **CONCLUIDO** |
| Gerar scripts de deploy/sync em `C:\SOL` | Claude Code (local) | **CONCLUIDO** |
| Sincronizar `C:\SOL` → `Y:\` | Claude Code (local) | **CONCLUIDO** |
| Executar `run-sprint-f3.ps1` no servidor | Claude Code (servidor) | **CONCLUIDO** |
| Verificar HTTP 200 + wizard funcionando | Humano | **CONCLUIDO** |

---

## Inventario de arquivos — estado verificado

### C:\SOL (maquina local) — SINCRONIZADO

| Caminho completo | Tipo | Verificado |
|---|---|---|
| `C:\SOL\frontend\src\app\core\models\licenciamento-create.model.ts` | NOVO | Sim |
| `C:\SOL\frontend\src\app\core\models\licenciamento.model.ts` | ATUALIZADO | Sim |
| `C:\SOL\frontend\src\app\core\services\licenciamento.service.ts` | ATUALIZADO | Sim |
| `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts` | NOVO | Sim |
| `C:\SOL\frontend\src\app\app.routes.ts` | ATUALIZADO | Sim |
| `C:\SOL\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts` | ATUALIZADO | Sim |
| `C:\SOL\infra\scripts\sprint-f3-deploy.ps1` | NOVO | Sim |
| `C:\SOL\infra\scripts\sync-f3-to-server.ps1` | NOVO | Sim |
| `C:\SOL\logs\run-sprint-f3.ps1` | NOVO | Sim |

### Y:\ (servidor — C:\SOL no servidor) — SINCRONIZADO

| Caminho em Y:\ | Copiado em | Status |
|---|---|---|
| `Y:\frontend\src\app\core\models\licenciamento-create.model.ts` | 2026-04-07 | Presente (verificado via Glob) |
| `Y:\frontend\src\app\core\models\licenciamento.model.ts` | 2026-04-07 | Presente (verificado via Glob) |
| `Y:\frontend\src\app\core\services\licenciamento.service.ts` | 2026-04-07 | Presente |
| `Y:\frontend\src\app\pages\licenciamentos\licenciamento-novo\licenciamento-novo.component.ts` | 2026-04-07 | Presente (verificado via Glob) |
| `Y:\frontend\src\app\app.routes.ts` | 2026-04-07 | Presente |
| `Y:\frontend\src\app\pages\licenciamentos\licenciamentos.component.ts` | 2026-04-07 | Presente |
| `Y:\infra\scripts\sprint-f3-deploy.ps1` | 2026-04-07 | Presente (verificado via Glob) |
| `Y:\logs\run-sprint-f3.ps1` | 2026-04-07 | Presente |

> **Nota sobre o sync:** O script `sync-f3-to-server.ps1` foi criado para uso em sessoes futuras onde Y:\ precisar ser re-sincronizado. Nesta sessao o sync foi feito diretamente pelo Claude Code via ferramenta Write, arquivo a arquivo, com confirmacao de sucesso em cada escrita.

---

## Visao geral da sprint

| Item | Detalhe |
|---|---|
| Rota nova | `/app/licenciamentos/novo` |
| Roles permitidas | `CIDADAO`, `ADMIN` |
| Componente principal | `LicenciamentoNovoComponent` (4-step `MatStepper` linear) |
| Endpoints consumidos | `POST /api/licenciamentos` + `POST /api/licenciamentos/{id}/submeter` |
| Arquivos novos | 2 (modelo + componente) |
| Arquivos atualizados | 4 (model, service, routes, lista) |
| Scripts de infraestrutura | 3 (deploy, sync, launcher) |

---

## Instrucoes de execucao

### Passo 1 — Sincronizar arquivos para o servidor

> **JA CONCLUIDO nesta sessao.** Todos os arquivos foram escritos diretamente em Y:\ com confirmacao. Se Y:\ precisar ser re-sincronizado no futuro (ex.: apos nova edicao local), execute:

```powershell
# Na maquina local, com Y:\ mapeado:
C:\SOL\infra\scripts\sync-f3-to-server.ps1
```

O script `sync-f3-to-server.ps1` copia os 6 arquivos-fonte + `sprint-f3-deploy.ps1` + cria `run-sprint-f3.ps1` em Y:\.

---

### Passo 2 — Executar o deploy no servidor

> **JA CONCLUIDO em 2026-04-07.** Deploy executado pelo Claude Code no servidor com sucesso. Detalhes abaixo.

**Resultado da execucao:**

| Etapa | Resultado |
|---|---|
| Pre-verificacao | Node.js v20.18.0, npm 10.8.2 — OK |
| Verificacao dos 6 arquivos F3 | 13 verificacoes OK, 0 erros |
| npm ci | 947 pacotes instalados em ~1 min |
| ng build --configuration production | 5.519s, 24 chunks, exit code 0 |
| Deploy para C:\nginx\html\sol | Diretorio criado + index.html copiado |
| Restart sol-nginx + smoke test | HTTP 200 OK |

**Incidente durante a execucao — problema de encoding:**
O script `sprint-f3-deploy.ps1` foi criado com UTF-8 sem BOM contendo caracteres Unicode (U+2550 `=`, U+2500 `-`, U+2014 `--`). O PowerShell 5.x (padrao Windows) leu o arquivo como Windows-1252, corrompendo o parser e gerando erros em cascata. O Claude Code no servidor identificou a causa raiz e aplicou substituicoes ASCII antes de re-executar com sucesso. **O script local (`C:\SOL\infra\scripts\sprint-f3-deploy.ps1`) foi sincronizado com a versao corrigida em 2026-04-07.**

**Relatorio completo de execucao:**
`C:\SOL\logs\sprint-f3-relatorio-deploy.md` (copia local do relatorio gerado no servidor)

---

## Detalhes tecnicos dos arquivos

### 1. `licenciamento-create.model.ts` (NOVO)

**Por que e necessario:**
O modelo `licenciamento.model.ts` existente define apenas os tipos de leitura (`LicenciamentoDTO`). Para criacao e necessario um modelo separado que espelhe o Java record `LicenciamentoCreateDTO` do backend, com os campos exatos que o endpoint `POST /api/licenciamentos` espera receber.

**Conteudo:**
- Interface `LicenciamentoCreateDTO` com os campos: `tipo`, `areaConstruida`, `alturaMaxima`, `numPavimentos`, `tipoOcupacao?`, `usoPredominante?`, `endereco`
- Interface `EnderecoCreateDTO` com: `cep` (8 digitos), `logradouro`, `numero?`, `complemento?`, `bairro`, `municipio`, `uf`
- Constante `UF_OPTIONS` com as 27 UFs brasileiras para o `MatSelect` do formulario

**Correspondencia com o backend:**
```java
// Java backend — LicenciamentoCreateDTO.java
public record LicenciamentoCreateDTO(
    @NotNull TipoLicenciamento tipo,
    @DecimalMin("0.01") BigDecimal areaConstruida,
    @DecimalMin("0.01") BigDecimal alturaMaxima,
    @Positive Integer numPavimentos,
    @Size(max = 200) String tipoOcupacao,
    @Size(max = 200) String usoPredominante,
    @NotNull @Valid EnderecoDTO endereco,
    Long responsavelTecnicoId,   // reservado para sprint futura
    Long responsavelUsoId,        // reservado para sprint futura
    Long licenciamentoPaiId       // reservado para sprint futura
) {}
```

---

### 2. `licenciamento.model.ts` (ATUALIZADO)

**Por que e necessario:**
A versao F2 definia apenas 10 valores de `StatusLicenciamento`, cobrindo apenas os estados mais comuns. O backend Java possui 23 valores no enum. Sem a atualizacao, o TypeScript geraria erro de tipo para qualquer licenciamento retornado pelo servidor com um status nao mapeado.

**Valores adicionados (de 10 para 23):**
```
CIA_CIENCIA, DEFERIDO, INDEFERIDO, VISTORIA_PENDENTE, EM_VISTORIA,
CIV_CIENCIA, PRPCI_EMITIDO, APPCI_EMITIDO, ALVARA_VENCIDO,
AGUARDANDO_ACEITE_RENOVACAO, AGUARDANDO_PAGAMENTO_RENOVACAO,
AGUARDANDO_DISTRIBUICAO_RENOV, EM_VISTORIA_RENOVACAO, EM_RECURSO, RENOVADO
```

Os Records `STATUS_LABEL` e `STATUS_COLOR` foram atualizados com entradas para todos os 23 valores.

**Valores removidos da versao F2** (nao existem no backend):
```
APROVADO, REPROVADO
```

---

### 3. `licenciamento.service.ts` (ATUALIZADO)

**Por que e necessario:**
O `LicenciamentoService` existente tinha apenas metodos de leitura (`getMeus` e `getById`). O wizard precisa chamar dois endpoints de escrita:

| Metodo | Endpoint | Descricao |
|---|---|---|
| `criar(dto)` | `POST /api/licenciamentos` | Cria o rascunho; retorna `LicenciamentoDTO` com `id` gerado |
| `submeter(id)` | `POST /api/licenciamentos/{id}/submeter` | Muda status de `RASCUNHO` para `ANALISE_PENDENTE` |

**Fluxo no wizard:** o componente chama `criar()` e, no callback de sucesso, chama imediatamente `submeter()` com o `id` retornado. Se `submeter()` falhar, o usuario e redirecionado para o detalhe do rascunho sem perder os dados.

---

### 4. `licenciamento-novo.component.ts` (NOVO)

**Por que e necessario:**
Implementa o processo P03 (Wizard de Solicitacao de Licenciamento) mapeado no BPMN. O cidadao ou admin precisa de um fluxo guiado para preencher todos os dados obrigatorios antes de submeter o processo.

**Estrutura do MatStepper (linear):**

```
[ Tipo ] → [ Endereco ] → [ Edificacao ] → [ Revisao + Envio ]
```

**Passo 1 — Tipo:**
- Dois cards clicaveis: `PPCI` e `PSPCIM`
- `FormGroup: { tipo: ['', Validators.required] }`
- Card com icone, nome e descricao; borda destacada ao selecionar
- Icone de check verde aparece no card selecionado
- Botao "Proximo" desabilitado ate selecao ser feita

**Passo 2 — Endereco:**
- Campos: CEP (8 digitos, validacao por regex `\d{8}`), logradouro, numero, complemento, bairro, municipio, UF (MatSelect)
- UF pre-selecionada para "RS" (Rio Grande do Sul, contexto do CBMRS)
- Validacoes Angular Reactive Forms inline com `mat-error`
- `FormGroup` com `Validators.required` + `Validators.pattern` no CEP

**Passo 3 — Edificacao:**
- Campos: area construida (m², `min: 0.01`), altura maxima (m, `min: 0.01`), numero de pavimentos (`min: 1`)
- Campos opcionais: tipo de ocupacao (texto livre, max 200 chars), uso predominante
- Hint explicativo nos campos numericos

**Passo 4 — Revisao:**
- Exibe resumo dos 3 passos em cards separados (Tipo / Endereco / Edificacao)
- Aviso informativo sobre o fluxo: "sera criado em Rascunho e submetido para analise automaticamente"
- Botao "Confirmar e Enviar": chama `criar()` + `submeter()` em sequencia
- Spinner durante o envio; mensagem de erro via `ErrorAlertComponent` se falhar

**Decisao de design — submissao automatica:**
O wizard cria o rascunho e o submete em uma unica acao do usuario. Isso reflete o fluxo P03 onde a criacao e imediatamente seguida pelo envio para analise. O usuario nao precisa abrir o detalhe e clicar em "submeter" separadamente.

---

### 5. `app.routes.ts` (ATUALIZADO)

**Por que e necessario — ordenacao das rotas:**
O Angular Router faz matching de rotas de cima para baixo. Se a rota `/:id` fosse declarada antes de `/novo`, o segmento literal `"novo"` seria interpretado como um parametro `:id` e o `LicenciamentoDetalheComponent` seria carregado tentando buscar um licenciamento com `id = "novo"`, gerando erro 404 no backend.

**Configuracao adicionada:**
```typescript
// ANTES de { path: ':id', ... }
{
  path: 'novo',
  canActivate: [roleGuard],
  data: { roles: ['CIDADAO', 'ADMIN'] },
  loadComponent: () =>
    import('./pages/licenciamentos/licenciamento-novo/licenciamento-novo.component')
      .then(m => m.LicenciamentoNovoComponent)
}
```

**Guard de roles:** somente `CIDADAO` e `ADMIN` podem criar licenciamentos (conforme `@RolesAllowed` no backend). `ANALISTA`, `INSPETOR` e `CHEFE_SSEG_BBM` recebem 403 se tentarem acessar a rota.

---

### 6. `licenciamentos.component.ts` (ATUALIZADO)

**Por que e necessario:**
Na Sprint F2, o botao "Nova Solicitacao" foi entregue desabilitado (`disabled`) com tooltip explicativo. Agora que o wizard existe, o botao precisa ser ativado e navegar para `/app/licenciamentos/novo`.

**Mudancas:**
- Importado `AuthService`
- Propriedade calculada: `readonly podeNovaSolicitacao = this.auth.hasAnyRole(['CIDADAO', 'ADMIN'])`
- Botao substituido por `<a mat-raised-button routerLink="/app/licenciamentos/novo">` dentro de `@if (podeNovaSolicitacao)`
- Usuarios sem permissao (analistas, inspetores) nao veem o botao

---

## Scripts de infraestrutura — descricao e estado

### `sprint-f3-deploy.ps1` — Script principal (6 etapas)

**Localizacao:**
- Local: `C:\SOL\infra\scripts\sprint-f3-deploy.ps1`
- Servidor: `C:\SOL\infra\scripts\sprint-f3-deploy.ps1` (via Y:\)
- **Estado:** Presente em ambos os locais. **EXECUTADO COM SUCESSO em 2026-04-07.**
- **Versao:** ASCII-only (corrigido pelo Claude Code no servidor; local sincronizado em 2026-04-07). Versao original continha caracteres Unicode que causavam falha de parse no PS5.x.

**Etapa 1 — Pre-verificacao do ambiente**
- Verifica `node --version` e `npm --version`
- Confirma existencia de `C:\SOL\frontend` e `package.json`
- Aborta se o ambiente for invalido

**Etapa 2 — Verificacao dos arquivos-fonte**
- Confirma que todos os 6 arquivos F3 existem em disco
- Verificacoes de conteudo:
  - `licenciamento-create.model.ts` contem `LicenciamentoCreateDTO`
  - `licenciamento.model.ts` contem `APPCI_EMITIDO` (indicador dos 23 status)
  - `app.routes.ts` contem `licenciamento-novo` E `'novo'` aparece antes de `':id'`
  - `licenciamento.service.ts` contem `criar(` e `submeter(`
- Aborta se houver erros

**Etapa 3 — npm ci**
- Executa `npm ci --prefer-offline`
- Trata warnings do npm como nao-fatais (verifica `$LASTEXITCODE`, nao usa `ErrorActionPreference = Stop`)
- Fallback: verifica presenca de `node_modules/@angular/core`

**Etapa 4 — Build de producao**
- Executa `npx ng build --configuration production`
- Usa `npx` para evitar dependencia de Angular CLI global
- Verifica `dist\sol-frontend\browser\index.html` e arquivos `.js`

**Etapa 5 — Deploy para Nginx**
- Copia `dist\sol-frontend\browser\` para `C:\nginx\html\sol\` arquivo a arquivo
- Evita duplo-aninhamento (problema conhecido do `Copy-Item -Recurse` em diretorios existentes)

**Etapa 6 — Restart Nginx + smoke test**
- Tenta `Restart-Service sol-nginx`; fallback para `Restart-Service nginx`
- `Invoke-WebRequest http://localhost/` com timeout de 10s
- HTTP 200 = sucesso

---

### `sync-f3-to-server.ps1` — Script de sincronizacao local → servidor

**Localizacao:** `C:\SOL\infra\scripts\sync-f3-to-server.ps1`
**Estado:** Presente em `C:\SOL`. NAO copiado para Y:\ (nao e necessario no servidor).
**Quando usar:** Quando precisar re-sincronizar os arquivos F3 de C:\SOL para Y:\ em uma sessao futura (ex.: apos correcao de bug local).

O que o script faz:
1. Verifica se Y:\ esta acessivel
2. Cria diretorios necessarios em Y:\ se nao existirem
3. Copia os 6 arquivos-fonte Angular + `sprint-f3-deploy.ps1`
4. Cria `Y:\logs\run-sprint-f3.ps1` (launcher)
5. Exibe status de cada copia

> **Nota:** Nesta sessao o sync foi feito diretamente pelo Claude Code (Write em Y:\), sem necessidade de executar este script. Ele existe como alternativa para uso futuro.

---

### `run-sprint-f3.ps1` — Launcher com captura de log

**Localizacoes:**
- Local: `C:\SOL\logs\run-sprint-f3.ps1`
- Servidor: `C:\SOL\logs\run-sprint-f3.ps1` (via Y:\)
- **Estado:** Presente em ambos os locais. **EXECUTADO COM SUCESSO em 2026-04-07.**

**Conteudo do launcher:**
```powershell
$out = "C:\SOL\logs\sprint-f3-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f3-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f3-run-exitcode.txt" -Encoding UTF8
```

Saidas geradas apos execucao:
- `C:\SOL\logs\sprint-f3-run-output.txt` — log completo do deploy
- `C:\SOL\logs\sprint-f3-run-exitcode.txt` — exit code (0 = sucesso)

---

## Verificacao pos-deploy

Apos a execucao do script, verifique os seguintes cenarios:

### Cenario 1 — Botao habilitado para CIDADAO/ADMIN
1. Fazer login como CIDADAO
2. Acessar `/app/licenciamentos`
3. **Esperado:** botao "Nova Solicitacao" visivel e clicavel (verde, sem tooltip de bloqueio)

### Cenario 2 — Botao oculto para outros perfis
1. Fazer login como ANALISTA ou INSPETOR
2. Acessar `/app/licenciamentos`
3. **Esperado:** botao "Nova Solicitacao" NAO aparece

### Cenario 3 — Navegacao para o wizard
1. Clicar em "Nova Solicitacao" (ou acessar `/app/licenciamentos/novo`)
2. **Esperado:** tela do MatStepper com 4 abas no topo: Tipo | Endereco | Edificacao | Revisao

### Cenario 4 — Passo 1: selecao de tipo
1. Clicar no card "PPCI"
2. **Esperado:** card destacado com borda azul + icone de check verde; botao "Proximo" ativo

### Cenario 5 — Validacao do CEP
1. No Passo 2, digitar "1234" no campo CEP e tentar avancar
2. **Esperado:** mensagem de erro "CEP deve conter 8 digitos numericos"

### Cenario 6 — Revisao antes do envio
1. Preencher todos os passos e chegar ao Passo 4
2. **Esperado:** cards de revisao exibindo todos os dados informados corretamente

### Cenario 7 — Envio e redirecionamento
1. Clicar em "Confirmar e Enviar"
2. **Esperado:** spinner no botao, chamada `POST /api/licenciamentos` seguida de `POST /api/licenciamentos/{id}/submeter`, redirecionamento para `/app/licenciamentos/{id}` com status `ANALISE_PENDENTE`

### Cenario 8 — Rota /novo nao confunde /:id
1. Acessar `/app/licenciamentos/novo` como CIDADAO
2. **Esperado:** wizard exibido (NAO o componente de detalhe)

---

## Proximos passos (Sprint F4)

A Sprint F4 corresponde ao processo P04 — Analise Tecnica.

Entregas previstas para F4:
- Fila de analise para `ANALISTA` e `CHEFE_SSEG_BBM`
- Atribuicao de processo (mudanca de status `ANALISE_PENDENTE` → `EM_ANALISE`)
- Emissao de CIA (Comunicado de Inconformidade na Analise)
- Deferimento / Indeferimento com geracao de PrPCI

---

## Log de alteracoes

| Data | Versao | Descricao |
|---|---|---|
| 2026-04-07 | 1.0 | Criacao inicial -- Sprint F3 completa |
| 2026-04-07 | 1.1 | Atualizado com estado atual dos scripts: inventario C:\SOL e Y:\, mapa de progresso, status pendente do deploy no servidor |
| 2026-04-07 | 1.2 | Sprint F3 DEPLOYADA -- status CONCLUIDO em todas as etapas; incidente de encoding documentado; relatorio de deploy sincronizado; script local corrigido para ASCII-only |
