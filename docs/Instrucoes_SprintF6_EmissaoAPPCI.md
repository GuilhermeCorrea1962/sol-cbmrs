# Sprint F6 — Emissao de APPCI (P08)

## Visao Geral

A Sprint F6 implementa o modulo de **Emissao de APPCI** (Processo P08) no frontend Angular 18 do sistema SOL. Este modulo permite que administradores e chefes de segurança (`ADMIN`, `CHEFE_SSEG_BBM`) emitam o Alvara de Prevencao e Protecao Contra Incendio (APPCI) para processos cujo PrPCI ja foi aprovado na vistoria presencial.

A F6 tambem corrige o warning NG8011 acumulado desde a Sprint F3 no componente `licenciamento-novo.component.ts`.

### Posicao no fluxo do processo principal

```
[F3] ANALISE_PENDENTE
        |
[F4] EM_ANALISE -> CIA_EMITIDO (loop) -> deferir
        |
[F5] VISTORIA_PENDENTE -> EM_VISTORIA -> CIV_EMITIDO (loop) -> aprovar
        |
[F6] PRPCI_EMITIDO --> POST /emitir-appci --> APPCI_EMITIDO
```

Apos F6, o fluxo principal de licenciamento PPCI esta completo no frontend. Os processos do tipo PSPCIM ja encerravam em `DEFERIDO` na F4 (sem vistoria).

### Perfis com acesso ao modulo

| Perfil | Acesso |
|---|---|
| `ADMIN` | Fila de APPCI, emissao |
| `CHEFE_SSEG_BBM` | Idem ADMIN (acumulado com analise e vistoria) |
| Demais perfis | Sem acesso (roleGuard retorna 403) |

---

## Arquivos criados/modificados

### Novos arquivos

| Arquivo | Tipo | Descricao |
|---|---|---|
| `frontend/src/app/core/models/appci.model.ts` | Model (DTO) | Interface `AppciEmitirDTO` |
| `frontend/src/app/pages/appci/appci-fila/appci-fila.component.ts` | Componente | Fila paginada de processos PRPCI_EMITIDO |
| `frontend/src/app/pages/appci/appci-detalhe/appci-detalhe.component.ts` | Componente | Tela de emissao do APPCI |
| `infra/scripts/sprint-f6-deploy.ps1` | Script PowerShell | Script de deploy com 7 etapas |
| `logs/run-sprint-f6.ps1` | Script PowerShell | Launcher que captura output em log |

### Arquivos modificados

| Arquivo | Modificacao |
|---|---|
| `frontend/src/app/core/services/licenciamento.service.ts` | +2 metodos F6: `getFilaAppci`, `emitirAppci` |
| `frontend/src/app/app.routes.ts` | Rota `/app/appci` com `children` pattern (fila + detalhe) |
| `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts` | `podeEmitirAppci` + botao "Emitir APPCI" para `PRPCI_EMITIDO` |
| `frontend/src/app/pages/licenciamentos/licenciamento-novo/licenciamento-novo.component.ts` | Correcao NG8011: `<ng-container>` no botao "Confirmar e Enviar" |

---

## Script de Deploy — Etapas detalhadas

O script principal e `infra/scripts/sprint-f6-deploy.ps1`. Executa **7 etapas sequenciais**. Se qualquer etapa bloqueante falhar, o script para com `exit 1`.

### Etapa 1 — Pre-verificacao do ambiente

**O que faz:** Verifica Node.js, npm, existencia do diretorio `C:\SOL\frontend` e do `package.json`. Tambem verifica o pre-requisito da Sprint F5 (presenca de `vistoria.model.ts`).

**Por que e necessario:** Garante que o ambiente de build esta correto antes de qualquer operacao. Se o Node.js nao estiver no PATH ou o projeto Angular nao existir, as etapas seguintes falhariam com erros confusos. A verificacao do pre-requisito F5 previne executar F6 em um ambiente onde F5 nunca foi aplicada.

**Esperado:** Todas as verificacoes retornam `[OK]`. Se `vistoria.model.ts` nao existir, o script aborta com orientacao para executar a Sprint F5 primeiro.

---

### Etapa 2 — Verificacao dos arquivos-fonte da Sprint F6

**O que faz:** Verifica a presenca e o conteudo dos 7 arquivos modificados pela F6:

| Arquivo | Verificacao de conteudo |
|---|---|
| `appci.model.ts` | Contem `AppciEmitirDTO` |
| `appci-fila.component.ts` | Contem `AppciFilaComponent` |
| `appci-detalhe.component.ts` | Contem `AppciDetalheComponent` E `confirmarEmissao()` |
| `licenciamento.service.ts` | Contem `getFilaAppci` E `emitirAppci` |
| `app.routes.ts` | Contem `appci-fila.component` E `appci-detalhe.component` |
| `licenciamento-detalhe.component.ts` | Contem `podeEmitirAppci` |
| `licenciamento-novo.component.ts` | Contem `ng-container` (correcao NG8011) |

**Por que e necessario:** Valida que os arquivos foram colocados corretamente antes de iniciar o build (que e demorado). Evita compilar codigo incompleto ou desatualizado.

**Esperado:** Todas as verificacoes retornam `[OK]`. Qualquer falha aborta o script.

---

### Etapa 3 — npm ci

**O que faz:** Executa `npm ci --prefer-offline` para instalar as dependencias do projeto Angular de forma limpa e deterministica.

**Por que e necessario:** `npm ci` usa exatamente as versoes do `package-lock.json`, ao contrario de `npm install` que pode atualizar versoes menores. Em ambiente de servidor, isso garante reproducibilidade. O flag `--prefer-offline` usa o cache local quando possivel, evitando downloads desnecessarios.

**Esperado:** Saida com `added X packages` e exit code 0. Se o `node_modules/@angular/core` ja existir e `npm ci` retornar exit code diferente de 0 por erro de rede, o script prossegue (fallback seguro).

---

### Etapa 4 — Build de producao

**O que faz:** Executa `npx ng build --configuration production` no diretorio do projeto Angular.

**Por que e necessario:** A compilacao de producao:
1. Verifica todos os tipos TypeScript (erros de importacao, tipos incompativeis)
2. Verifica os templates HTML (NG8011 e outros erros de template)
3. Aplica tree-shaking — remove codigo nao utilizado
4. Gera bundles otimizados com hash de conteudo em `dist/sol-frontend/browser/`
5. Confirma que o novo modulo `appci` foi incluido no bundle (chunks com `appci` no nome)

A correcao do NG8011 em `licenciamento-novo.component.ts` sera validada aqui — se ainda houver o aviso, aparecera no output mas nao bloqueia o build.

**Esperado:** Build em 3-6 segundos, exit code 0, sem erros TypeScript. O numero total de chunks deve ser 33+ (era 31 apos F5; F6 adiciona 2 novos chunks para appci-fila e appci-detalhe). Avisos de budget CSS de componentes anteriores sao aceitaveis.

---

### Etapa 5 — Deploy dos assets para o Nginx

**O que faz:** Copia recursivamente os arquivos do diretorio `dist/sol-frontend/browser/` para `C:\nginx\html\sol`. Cria o diretorio de destino se nao existir.

**Por que e necessario:** O Nginx serve os arquivos estaticos diretamente de `C:\nginx\html\sol`. Sem esta etapa, o build seria gerado mas a aplicacao rodando no navegador ainda seria a versao anterior (pre-F6).

**Esperado:** Todos os arquivos copiados com sucesso. `index.html` presente em `C:\nginx\html\sol` apos a copia.

---

### Etapa 6 — Reinicializacao do Nginx e smoke test

**O que faz:** Tenta reiniciar o servico Windows `sol-nginx` (ou `nginx` como fallback). Aguarda 3 segundos e verifica se o servico esta em estado `Running`. Em seguida, executa um smoke test HTTP GET em `http://localhost/` e verifica se retorna HTTP 200.

**Por que e necessario:** O Nginx precisa ser reiniciado para recarregar os novos arquivos de cache e aplicar eventuais mudancas na configuracao. O smoke test confirma que a aplicacao esta acessivel antes de declarar sucesso.

**Esperado:** Servico reiniciado e em estado `Running`. GET retorna HTTP 200.

---

### Etapa 7 — Gerar relatorio de deploy

**O que faz:** Gera o arquivo `C:\SOL\logs\sprint-f6-relatorio-deploy.md` com:
- Data e hora da execucao
- Status geral (SUCESSO ou quantidade de erros)
- Numero de chunks JS gerados
- Tabelas com todos os arquivos implantados e seus status
- Rotas disponiveis apos F6
- Endpoints consumidos
- Proximas acoes sugeridas

**Por que e necessario:** Registro auditavel do deploy. Permite identificar facilmente quais arquivos foram criados no servidor durante a execucao (importante para sincronizacao com a maquina local). Esta etapa estava ausente na Sprint F5 e foi adicionada nesta sprint.

**Esperado:** Arquivo `.md` gerado em `C:\SOL\logs\sprint-f6-relatorio-deploy.md`.

---

## Como executar no servidor

### Pre-requisitos

1. Sprint F5 executada com sucesso (`vistoria.model.ts` presente no servidor)
2. Node.js 18+ e npm no PATH
3. Angular CLI disponivel via `npx` (no `node_modules/.bin`)
4. Nginx configurado e em execucao

### Instrucao para o Claude Code no servidor

```
Execute o script de deploy da Sprint F6:
  C:\SOL\logs\run-sprint-f6.ps1

O script chama C:\SOL\infra\scripts\sprint-f6-deploy.ps1 e grava todo o output em
C:\SOL\logs\sprint-f6-run-output.txt e o exit code em C:\SOL\logs\sprint-f6-run-exitcode.txt.

Apos a execucao, leia o arquivo de output e o relatorio gerado em
C:\SOL\logs\sprint-f6-relatorio-deploy.md e informe:
1. Se houve erros em alguma etapa
2. Quais arquivos foram criados/modificados no servidor
3. Se o build Angular concluiu com sucesso
4. Quantos chunks JS foram gerados (esperado: 33 ou mais)
```

### Verificacao manual pos-deploy

1. Acessar `/app/appci` como usuario ADMIN ou CHEFE_SSEG_BBM — deve exibir a fila de emissao
2. Acessar um processo com status `PRPCI_EMITIDO` — deve exibir o painel "Emissao do APPCI"
3. Clicar em "Emitir APPCI" — formulario de laudo opcional deve aparecer
4. Confirmar a emissao — deve navegar para `/app/appci` (processo concluido)
5. Na tela de detalhe do licenciamento (`/app/licenciamentos/:id`), processos com `PRPCI_EMITIDO` devem exibir o botao "Emitir APPCI" para ADMIN/CHEFE_SSEG_BBM
6. Submeter um novo licenciamento — o warning NG8011 nao deve mais aparecer no console do browser

---

## Detalhes tecnicos dos componentes

### `appci.model.ts`

Define o DTO de criacao para o endpoint de emissao:

- **`AppciEmitirDTO`**: payload minimalista com `observacao?` (max 5000 chars)
- A validade do APPCI (2 anos para ocupacoes nao-habituais, 5 anos para demais) e calculada automaticamente pelo backend com base no `tipoOcupacao` da edificacao, conforme RTCBMRS N.01/2024. O frontend nao envia nem calcula a validade.

### `AppciFilaComponent`

- Selector: `sol-appci-fila`
- Rota: `/app/appci`
- Tabela com colunas: `numero`, `tipo`, `status`, `municipio`, `area`, `entrada`, `acoes`
- Paginacao MatPaginator com `pageSize=10`
- Exibe apenas processos com status: `PRPCI_EMITIDO`
- Icone de acao: `workspace_premium` (Material Icons)

### `AppciDetalheComponent`

- Selector: `sol-appci-detalhe`
- Rota: `/app/appci/:id`
- Signal `formularioAberto: boolean` controla visibilidade do formulario de confirmacao
- Status `PRPCI_EMITIDO`: exibe descricao + botao "Emitir APPCI" que abre o formulario
- Status `APPCI_EMITIDO`: exibe painel informativo verde (processo ja concluido)
- Apos confirmacao: navega para `/app/appci` (lista principal)
- Borda do painel de acao: `2px solid #1976d2` (azul — diferente do laranja da vistoria)

### Correcao NG8011 em `licenciamento-novo.component.ts`

Warning acumulado desde a Sprint F3. O botao "Confirmar e Enviar" no Passo 4 do wizard tinha dois nos raiz no bloco `@if` e `@else`:

**Antes (NG8011):**
```html
@if (saving()) {
  <mat-spinner ...></mat-spinner>
  Enviando...
} @else {
  <mat-icon>send</mat-icon>
  Confirmar e Enviar
}
```

**Depois (corrigido):**
```html
@if (saving()) {
  <ng-container>
    <mat-spinner ...></mat-spinner>
    Enviando...
  </ng-container>
} @else {
  <ng-container>
    <mat-icon>send</mat-icon>
    Confirmar e Enviar
  </ng-container>
}
```

Com esta correcao, todos os warnings NG8011 conhecidos do projeto estao resolvidos:
- F4/F5: `licenciamento-analise.component.ts` (4 botoes) — corrigido na F5
- F6: `licenciamento-novo.component.ts` (1 botao) — corrigido nesta sprint

---

## Dependencias e pre-requisitos do backend

Para que o modulo F6 funcione completamente, o backend deve expor:

| Endpoint | Metodo | Descricao |
|---|---|---|
| `/api/licenciamentos/fila-appci` | GET | Lista paginada com status `PRPCI_EMITIDO` |
| `/api/licenciamentos/{id}/emitir-appci` | POST | Transicao `PRPCI_EMITIDO` -> `APPCI_EMITIDO`; calcula validade |

Autenticacao: Bearer token OIDC (SOE PROCERGS). Roles requeridas: `ADMIN` ou `CHEFE_SSEG_BBM`.

---

## Arquivos a copiar para o servidor

| Caminho relativo a `C:\SOL\` | Tipo |
|---|---|
| `frontend/src/app/core/models/appci.model.ts` | NOVO |
| `frontend/src/app/pages/appci/appci-fila/appci-fila.component.ts` | NOVO |
| `frontend/src/app/pages/appci/appci-detalhe/appci-detalhe.component.ts` | NOVO |
| `frontend/src/app/core/services/licenciamento.service.ts` | ATUALIZADO (+2 metodos F6) |
| `frontend/src/app/app.routes.ts` | ATUALIZADO (rota /appci) |
| `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts` | ATUALIZADO (podeEmitirAppci) |
| `frontend/src/app/pages/licenciamentos/licenciamento-novo/licenciamento-novo.component.ts` | ATUALIZADO (correcao NG8011) |
| `infra/scripts/sprint-f6-deploy.ps1` | NOVO |
| `logs/run-sprint-f6.ps1` | NOVO |

---

## Estado do projeto apos F6

| Sprint | Processo | Status |
|---|---|---|
| F1 | Setup/Auth | Concluida |
| F2 | Leitura de licenciamentos | Concluida |
| F3 | Criacao e submissao (wizard) | Concluida |
| F4 | Analise Tecnica (P04) | Concluida |
| F5 | Vistoria Presencial (P07) | Concluida |
| F6 | Emissao de APPCI (P08) | **Esta sprint** |
| F7 | Gestao de Usuarios | Placeholder |
| F8 | (a definir) | Pendente |
| F9 | Relatorios | Placeholder |

O fluxo principal PPCI esta completo no frontend apos F6:
**Submissao (F3) → Analise (F4) → Vistoria (F5) → APPCI (F6)**
