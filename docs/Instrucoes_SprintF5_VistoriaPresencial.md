# Sprint F5 — Vistoria Presencial (P07)

## Visao Geral

A Sprint F5 implementa o modulo de **Vistoria Presencial** (Processo P07) no frontend Angular 18 do sistema SOL. O modulo permite que inspetores e chefes de segurança (`INSPETOR`, `CHEFE_SSEG_BBM`) gerenciem os processos de licenciamento que aguardam ou estao em andamento de vistoria presencial.

### Fluxo implementado

```
VISTORIA_PENDENTE
      |
      | POST /iniciar-vistoria
      v
  EM_VISTORIA  (ou EM_VISTORIA_RENOVACAO — processos P14)
      |
      |--- POST /civ ---------> CIV_EMITIDO   (loop-back: RT corrige e re-agenda)
      |
      `--- POST /aprovar-vistoria --> PRPCI_EMITIDO
```

### Perfis com acesso ao modulo

| Perfil | Acesso |
|---|---|
| `INSPETOR` | Fila de vistoria, iniciar, emitir CIV, aprovar |
| `CHEFE_SSEG_BBM` | Idem INSPETOR (acumulado com analise tecnica) |
| Demais perfis | Sem acesso (roleGuard retorna 403) |

---

## Arquivos criados/modificados

### Novos arquivos

| Arquivo | Tipo | Descricao |
|---|---|---|
| `frontend/src/app/core/models/vistoria.model.ts` | Model (DTO) | Interfaces `CivItemCreateDTO`, `CivCreateDTO`, `AprovacaoVistoriaCreateDTO` |
| `frontend/src/app/pages/vistoria/vistoria-fila/vistoria-fila.component.ts` | Componente | Fila paginada de processos de vistoria |
| `frontend/src/app/pages/vistoria/vistoria-detalhe/vistoria-detalhe.component.ts` | Componente | Tela de acao de vistoria (iniciar / CIV / aprovar) |
| `infra/scripts/sprint-f5-deploy.ps1` | Script PowerShell | Script de deploy com 6 etapas de verificacao |
| `logs/run-sprint-f5.ps1` | Script PowerShell | Launcher que captura output em arquivo de log |

### Arquivos modificados

| Arquivo | Modificacao |
|---|---|
| `frontend/src/app/core/services/licenciamento.service.ts` | Adicionados 4 metodos F5: `getFilaVistoria`, `iniciarVistoria`, `emitirCiv`, `aprovarVistoria` |
| `frontend/src/app/app.routes.ts` | Rota `vistorias` convertida de placeholder para `children` pattern (fila + detalhe) |
| `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts` | Adicionados `podeVistoriar` e botao "Abrir Vistoria" |
| `frontend/src/app/pages/analise/licenciamento-analise/licenciamento-analise.component.ts` | Correcao NG8011: `@else` blocks com 2 nos raiz encapsulados em `<ng-container>` |

---

## Script de Deploy — Etapas detalhadas

O script principal e `infra/scripts/sprint-f5-deploy.ps1`. Ele executa **6 etapas sequenciais**. Se qualquer etapa falhar, o script para e reporta o erro com `exit 1`.

### Etapa 1 — Criar estrutura de diretorios

**O que faz:** Cria os diretorios das novas paginas de vistoria, caso nao existam.

```
frontend/src/app/pages/vistoria/
frontend/src/app/pages/vistoria/vistoria-fila/
frontend/src/app/pages/vistoria/vistoria-detalhe/
```

**Por que e necessario:** O Angular nao cria automaticamente subdiretorios ao fazer deploy. Se os diretorios nao existirem, a copia dos arquivos `.component.ts` na etapa seguinte falharia silenciosamente ou com erro de caminho invalido.

**Esperado:** `New-Item` cria os 3 diretorios com `-Force` (idempotente — nao falha se ja existirem).

---

### Etapa 2 — Copiar arquivos-fonte para o servidor

**O que faz:** Copia os arquivos TypeScript novos e modificados da pasta de deploy para os caminhos definitivos no projeto Angular.

Arquivos copiados:
- `vistoria.model.ts` → `core/models/`
- `vistoria-fila.component.ts` → `pages/vistoria/vistoria-fila/`
- `vistoria-detalhe.component.ts` → `pages/vistoria/vistoria-detalhe/`
- `licenciamento.service.ts` (versao F5) → `core/services/`
- `app.routes.ts` (versao F5) → `src/app/`
- `licenciamento-detalhe.component.ts` (versao F5) → `pages/licenciamentos/licenciamento-detalhe/`
- `licenciamento-analise.component.ts` (versao F5, correcao NG8011) → `pages/analise/licenciamento-analise/`

**Por que e necessario:** Os arquivos sao gerados na maquina local (`C:\SOL\`) e precisam ser transferidos para o servidor onde o projeto Angular esta hospedado antes de qualquer compilacao.

**Esperado:** Todos os 7 arquivos copiados com sucesso sem erros de acesso ou caminho.

---

### Etapa 3 — Verificar presenca dos arquivos criticos

**O que faz:** Verifica se os arquivos-chave foram copiados corretamente e se contem os identificadores esperados. Sao realizadas as seguintes verificacoes:

| Arquivo | Verificacao |
|---|---|
| `vistoria.model.ts` | Contem `CivCreateDTO` E `AprovacaoVistoriaCreateDTO` |
| `vistoria-fila.component.ts` | Contem `VistoriaFilaComponent` |
| `vistoria-detalhe.component.ts` | Contem `VistoriaDetalheComponent` E `confirmarCiv()` |
| `licenciamento.service.ts` | Contem `getFilaVistoria`, `emitirCiv`, `iniciarVistoria` |
| `app.routes.ts` | Contem `vistoria-fila.component` E `vistoria-detalhe.component` |
| `licenciamento-detalhe.component.ts` | Contem `podeVistoriar` |
| `licenciamento-analise.component.ts` | Contem `<ng-container>` (confirmacao da correcao NG8011) |

**Por que e necessario:** Garante que a copia nao foi truncada, que o arquivo correto foi sobrescrito e que a logica de negocio principal esta presente antes de iniciar a compilacao (que e demorada). Evita compilar codigo incompleto.

**Esperado:** Nenhuma verificacao deve falhar. Se alguma falhar, o script exibe qual verificacao falhou e encerra com `exit 1`.

---

### Etapa 4 — Executar `npm install`

**O que faz:** Executa `npm install` no diretorio do projeto Angular para garantir que todas as dependencias declaradas em `package.json` estao instaladas.

**Por que e necessario:** Em ambientes de servidor, especialmente apos clones ou deployments, o `node_modules` pode estar desatualizado ou incompleto. Esta etapa e uma salvaguarda — se as dependencias ja estiverem corretas, o comando e rapido (alguns segundos). Se houver alguma dependencia faltando, ela sera instalada agora em vez de causar erro de compilacao.

**Esperado:** `npm install` conclui com `0 vulnerabilities` (ou aviso aceitavel). Saida capturada no log.

---

### Etapa 5 — Compilar o projeto (`ng build`)

**O que faz:** Executa `ng build --configuration=production` no diretorio do projeto Angular.

**Por que e necessario:** A compilacao:
1. Verifica erros de TypeScript (tipos incorretos, imports faltando, etc.)
2. Verifica o template HTML (NG8011, expressoes invalidas, diretivas desconhecidas)
3. Gera os bundles JavaScript otimizados para producao
4. Aplica tree-shaking para remover codigo nao utilizado

O sucesso da compilacao e a evidencia definitiva de que o codigo-fonte esta correto. Nenhuma verificacao manual substitui uma compilacao limpa.

**Esperado:** Build concluido sem erros. Arquivos gerados em `dist/sol-frontend/`. Avisos de budget de CSS sao aceitaveis (nao bloqueantes). O exit code deve ser `0`.

---

### Etapa 6 — Gerar relatorio de deploy

**O que faz:** Gera o arquivo `C:\SOL\logs\sprint-f5-relatorio-deploy.md` com:
- Data e hora da execucao
- Lista de arquivos implantados com status
- Resultado das verificacoes da Etapa 3
- Confirmacao do build
- Proximas acoes sugeridas (configurar backend, testar fluxo P07)

**Por que e necessario:** O relatorio serve como registro auditavel do deploy. Em projetos com multiplos ambientes e sprints sequenciais, e essencial saber o que foi implantado, quando e com qual resultado. O relatorio tambem e usado para sincronizar a maquina local com o estado do servidor (identificar quais arquivos foram modificados pelo Claude no servidor durante a execucao).

**Esperado:** Arquivo `.md` gerado com data/hora corretos e lista de status `OK` para cada item.

---

## Como executar no servidor

### Pre-requisitos

1. Os arquivos da Sprint F5 devem estar disponiveis no servidor no caminho de staging definido no script (ex: `C:\SOL\staging\sprint-f5\`)
2. Node.js e npm instalados e no PATH
3. Angular CLI instalado globalmente (`npm install -g @angular/cli`) ou disponivel via `npx`
4. Permissao de escrita nos diretorios do projeto Angular

### Instrucao para o Claude Code no servidor

Cole o seguinte comando no Claude Code do servidor:

```
Execute o script de deploy da Sprint F5:
  C:\SOL\logs\run-sprint-f5.ps1

O script chama C:\SOL\infra\scripts\sprint-f5-deploy.ps1 e grava todo o output em
C:\SOL\logs\sprint-f5-run-output.txt e o exit code em C:\SOL\logs\sprint-f5-run-exitcode.txt.

Apos a execucao, leia o arquivo de output e o relatorio gerado em
C:\SOL\logs\sprint-f5-relatorio-deploy.md e informe:
1. Se houve erros em alguma etapa
2. Quais arquivos foram criados/modificados no servidor
3. Se o build Angular concluiu com sucesso
```

### Verificacao manual pos-deploy

Apos a execucao do script, verificar no navegador:

1. Acessar `/app/vistorias` como usuario INSPETOR — deve exibir a fila de vistoria
2. Acessar um processo com status `VISTORIA_PENDENTE` — deve exibir botao "Iniciar Vistoria"
3. Clicar em "Iniciar Vistoria" — status deve mudar para `EM_VISTORIA`
4. Com status `EM_VISTORIA`, os botoes "Emitir CIV" e "Aprovar Vistoria" devem aparecer
5. Emitir CIV — formulario de itens de nao-conformidade deve ser exibido e submetido
6. Na tela de detalhe do licenciamento (`/app/licenciamentos/:id`), processos com `VISTORIA_PENDENTE` / `EM_VISTORIA` / `EM_VISTORIA_RENOVACAO` devem exibir o botao "Abrir Vistoria"

---

## Detalhes tecnicos dos componentes

### `vistoria.model.ts`

Define os DTOs de criacao para os endpoints de vistoria:

- **`CivItemCreateDTO`**: um item de nao-conformidade (`descricao` obrigatoria, `normaReferencia` opcional)
- **`CivCreateDTO`**: payload completo do CIV (`itens[]`, `observacaoGeral?`, `prazoCorrecaoEmDias`)
- **`AprovacaoVistoriaCreateDTO`**: payload da aprovacao (`observacao?` — laudo opcional, max 5000 chars)

### `VistoriaFilaComponent`

- Selector: `sol-vistoria-fila`
- Rota: `/app/vistorias`
- Tabela com colunas: `numero`, `tipo`, `status`, `municipio`, `area`, `entrada`, `acoes`
- Paginacao MatPaginator com `pageSize=10`
- Ordenacao FIFO (`sort=dataCriacao,asc`)
- Exibe processos nos status: `VISTORIA_PENDENTE`, `EM_VISTORIA`, `EM_VISTORIA_RENOVACAO`

### `VistoriaDetalheComponent`

- Selector: `sol-vistoria-detalhe`
- Rota: `/app/vistorias/:id`
- Signal `acaoAtiva: 'civ' | 'aprovar' | null` controla qual formulario esta expandido
- `VISTORIA_PENDENTE` → botao unico "Iniciar Vistoria" (POST `/iniciar-vistoria`)
- `EM_VISTORIA` / `EM_VISTORIA_RENOVACAO` → dois botoes toggle:
  - "Emitir CIV" → `FormArray<FormGroup>` identico ao CIA da F4
  - "Aprovar Vistoria" → textarea opcional de laudo
- Apos CIV: recarrega o licenciamento (permanece na tela — inspetor pode emitir novo CIV se necessario)
- Apos Aprovacao: navega para `/app/vistorias` (processo concluido)

### Correcao NG8011 em `licenciamento-analise.component.ts`

O warning NG8011 ocorre quando um bloco `@if`/`@else` dentro de um componente com content projection (como `mat-raised-button`) contem multiplos nos raiz. O Angular Material 18 projeta o conteudo de botoes por slot, e multiplos nos raiz quebram a projecao.

**Antes (gerando NG8011):**
```html
@else {
  <mat-icon>play_circle</mat-icon>
  Iniciar Analise
}
```

**Depois (corrigido):**
```html
@else {
  <ng-container>
    <mat-icon>play_circle</mat-icon>
    Iniciar Analise
  </ng-container>
}
```

O `<ng-container>` nao gera elemento DOM — e apenas um no logico que unifica os filhos em um unico no raiz para o compilador Angular, sem alterar o HTML renderizado ou a aparencia visual.

Esta correcao foi aplicada nos 4 botoes de acao da tela de analise tecnica: "Iniciar Analise", "Confirmar CIA", "Confirmar Deferimento" e "Confirmar Indeferimento".

---

## Dependencias e pre-requisitos do backend

Para que o modulo F5 funcione completamente, o backend Java EE deve expor os seguintes endpoints (ja documentados em `Requisitos_P07_VistoriaPresencial_StackAtual.md`):

| Endpoint | Metodo | Descricao |
|---|---|---|
| `/api/licenciamentos/fila-vistoria` | GET | Retorna lista paginada (VISTORIA_PENDENTE, EM_VISTORIA, EM_VISTORIA_RENOVACAO) |
| `/api/licenciamentos/{id}/iniciar-vistoria` | POST | Transicao VISTORIA_PENDENTE → EM_VISTORIA |
| `/api/licenciamentos/{id}/civ` | POST | Emite CIV; transicao EM_VISTORIA → CIV_EMITIDO |
| `/api/licenciamentos/{id}/aprovar-vistoria` | POST | Aprova vistoria; transicao EM_VISTORIA → PRPCI_EMITIDO |

Todos os endpoints requerem autenticacao Bearer (token OIDC do SOE PROCERGS) e perfil `INSPETOR` ou `CHEFE_SSEG_BBM` no claim de roles.

---

## Arquivos a copiar para o servidor

| Caminho relativo a `C:\SOL\` | Tipo |
|---|---|
| `frontend/src/app/core/models/vistoria.model.ts` | NOVO |
| `frontend/src/app/pages/vistoria/vistoria-fila/vistoria-fila.component.ts` | NOVO |
| `frontend/src/app/pages/vistoria/vistoria-detalhe/vistoria-detalhe.component.ts` | NOVO |
| `frontend/src/app/core/services/licenciamento.service.ts` | ATUALIZADO |
| `frontend/src/app/app.routes.ts` | ATUALIZADO |
| `frontend/src/app/pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component.ts` | ATUALIZADO |
| `frontend/src/app/pages/analise/licenciamento-analise/licenciamento-analise.component.ts` | ATUALIZADO (NG8011) |
| `infra/scripts/sprint-f5-deploy.ps1` | NOVO |
| `logs/run-sprint-f5.ps1` | NOVO |
