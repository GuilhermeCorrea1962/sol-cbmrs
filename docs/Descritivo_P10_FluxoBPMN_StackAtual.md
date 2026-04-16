# Descritivo do Fluxo BPMN — P10 Recurso Administrativo CIA/CIV (Stack Atual Java EE)

**Arquivo BPMN:** `P10_Recurso_StackAtual.bpmn`
**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Stack:** Java EE · JAX-RS · CDI · JPA/Hibernate · EJB `@Stateless` · SOE PROCERGS · Alfresco ECM · Oracle

---

## Sumario

1. [Visao Geral do Processo](#1-visao-geral-do-processo)
2. [Estrutura do Pool, Raias e Justificativa de Modelagem](#2-estrutura-do-pool-raias-e-justificativa-de-modelagem)
3. [Fase 1 — Acesso ao Modulo e Consulta de Pre-condicoes](#3-fase-1--acesso-ao-modulo-e-consulta-de-pre-condicoes)
   - 3.1 [Evento de Inicio e Contexto de Entrada](#31-evento-de-inicio-e-contexto-de-entrada)
   - 3.2 [Selecao do Licenciamento e Visualizacao da CIA/CIV](#32-selecao-do-licenciamento-e-visualizacao-da-ciaciju)
   - 3.3 [Verificacao de Pre-condicoes no Backend (RN-075/078/079/082)](#33-verificacao-de-pre-condicoes-no-backend-rn-075078079082)
   - 3.4 [Gateway: Pode Abrir Recurso?](#34-gateway-pode-abrir-recurso)
   - 3.5 [Evento de Fim de Erro: Recurso Bloqueado](#35-evento-de-fim-de-erro-recurso-bloqueado)
4. [Fase 2 — Preenchimento e Validacao do Formulario](#4-fase-2--preenchimento-e-validacao-do-formulario)
   - 4.1 [Preenchimento do Formulario de Recurso](#41-preenchimento-do-formulario-de-recurso)
   - 4.2 [Validacao Completa das Regras de Negocio (RN-073 a RN-082)](#42-validacao-completa-das-regras-de-negocio-rn-073-a-rn-082)
   - 4.3 [Gateway: Dados Validos?](#43-gateway-dados-validos)
   - 4.4 [Evento de Fim de Erro: Erro de Validacao](#44-evento-de-fim-de-erro-erro-de-validacao)
5. [Fase 3 — Upload de Documentos e Persistencia do Recurso em RASCUNHO](#5-fase-3--upload-de-documentos-e-persistencia-do-recurso-em-rascunho)
   - 5.1 [Upload de Documentos Comprobatorios ao Alfresco ECM](#51-upload-de-documentos-comprobatorios-ao-alfresco-ecm)
   - 5.2 [Persistencia do RecursoED em CBM_RECURSO](#52-persistencia-do-recursoed-em-cbm_recurso)
   - 5.3 [Filtragem dos Co-signatarios por TipoRecurso (RN-083)](#53-filtragem-dos-co-signatarios-por-tiporecurso-rn-083)
6. [Fase 4 — Envio do Recurso para Aceite dos Co-signatarios](#6-fase-4--envio-do-recurso-para-aceite-dos-co-signatarios)
   - 6.1 [Confirmacao e Envio pelo Solicitante](#61-confirmacao-e-envio-pelo-solicitante)
   - 6.2 [Registro do Envio no Backend: Transicao de Estado e Marcos](#62-registro-do-envio-no-backend-transicao-de-estado-e-marcos)
7. [Fase 5 — Aceite dos Co-signatarios e Unanimidade](#7-fase-5--aceite-dos-co-signatarios-e-unanimidade)
   - 7.1 [Tarefa de Decisao do Co-signatario](#71-tarefa-de-decisao-do-co-signatario)
   - 7.2 [Gateway: Todos Aceitaram? (Unanimidade — RN-084)](#72-gateway-todos-aceitaram-unanimidade--rn-084)
8. [Eventos de Boundary: Recusa e Cancelamento](#8-eventos-de-boundary-recusa-e-cancelamento)
   - 8.1 [BoundaryEvent Interrompente: Recusa de Aceite (RN-086)](#81-boundaryevent-interrompente-recusa-de-aceite-rn-086)
   - 8.2 [BoundaryEvent Interrompente: Cancelamento do Recurso (RN-085)](#82-boundaryevent-interrompente-cancelamento-do-recurso-rn-085)
9. [Fase 6 — Unanimidade, AGUARDANDO_DISTRIBUICAO e Situacao do Licenciamento](#9-fase-6--unanimidade-aguardando_distribuicao-e-situacao-do-licenciamento)
   - 9.1 [Registro de Unanimidade e Criacao de CBM_ANALISE_RECURSO](#91-registro-de-unanimidade-e-criacao-de-cbm_analise_recurso)
   - 9.2 [Atualizacao da SituacaoLicenciamento (RN-075)](#92-atualizacao-da-situacaolicenciamento-rn-075)
   - 9.3 [Notificacao dos Analistas CBM (RN-088)](#93-notificacao-dos-analistas-cbm-rn-088)
10. [Fase 7 — Analise pelo Analista CBM-RS](#10-fase-7--analise-pelo-analista-cbm-rs)
    - 10.1 [Distribuicao do Recurso para o Analista](#101-distribuicao-do-recurso-para-o-analista)
    - 10.2 [Registro do Despacho Tecnico](#102-registro-do-despacho-tecnico)
    - 10.3 [Conclusao da Analise e Registro do Resultado](#103-conclusao-da-analise-e-registro-do-resultado)
11. [Fase 8 — Resultado e Encerramento](#11-fase-8--resultado-e-encerramento)
    - 11.1 [Gateway: Status da Analise?](#111-gateway-status-da-analise)
    - 11.2 [Gateway: Qual Instancia foi Indeferida?](#112-gateway-qual-instancia-foi-indeferida)
    - 11.3 [Encerramento com Deferimento](#113-encerramento-com-deferimento)
    - 11.4 [Encerramento com Indeferimento em 1a Instancia](#114-encerramento-com-indeferimento-em-1a-instancia)
    - 11.5 [Bloqueio e Encerramento com Indeferimento em 2a Instancia (RN-089)](#115-bloqueio-e-encerramento-com-indeferimento-em-2a-instancia-rn-089)
12. [Fluxos Cross-Lane e Decisoes de Roteamento Visual](#12-fluxos-cross-lane-e-decisoes-de-roteamento-visual)
13. [Maquina de Estados, Marcos e Rastreabilidade de Auditoria](#13-maquina-de-estados-marcos-e-rastreabilidade-de-auditoria)
14. [Seguranca e Controle de Acesso](#14-seguranca-e-controle-de-acesso)

---

## 1. Visao Geral do Processo

O processo P10 — Recurso Administrativo CIA/CIV — e o mecanismo legal pelo qual um solicitante (RT, RU ou Proprietario vinculado a um licenciamento) contesta formalmente uma decisao do CBMRS registrada na forma de CIA (Comunicado de Inconformidade na Analise) ou CIV (Comunicado de Inconformidade na Vistoria).

A CIA e emitida ao final de uma analise tecnica que constatou inconformidades no projeto PPCI submetido. A CIV e emitida ao final de uma vistoria presencial que constatou irregularidades na edificacao. Em ambos os casos, o estabelecimento permanece sem o APPCI (Alvara de Prevencao e Protecao Contra Incendio) enquanto as inconformidades nao forem sanadas ou contestadas com exito. O recurso administrativo e o instrumento que permite ao solicitante apresentar argumentos tecnicos e documentos comprobatorios para reverter ou mitigar a decisao do CBMRS sem necessidade de corrigir fisicamente as inconformidades apontadas.

### Duas instancias hierarquicas

O recurso no sistema SOL e organizado em duas instancias sequenciais e hierarquicamente distintas:

| Instancia | Julgador | Prazo para interpor | Prazo para julgamento |
|---|---|---|---|
| 1a instancia | Chefe da secao tecnica CBM | 30 dias corridos apos CIA/CIV | Interno ao CBM |
| 2a instancia | Comandante / Colegiado CBM | 15 dias corridos apos conclusao da 1a | Interno ao CBM |

O prazo de 30 dias para a 1a instancia e definido pela constante `PRAZO_SOLICITAR_1_INSTANCIA = 30` em `RecursoRN`. O prazo de 15 dias para a 2a instancia e definido pela constante `PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15`. Ambas as constantes estao declaradas como campos `private static final int` na classe EJB `RecursoRN`.

### Estrutura em oito fases

O processo se organiza em oito fases logicamente dependentes, todas mapeadas no BPMN com comentarios XML explicitos:

| Fase | Descricao | Ator Principal |
|---|---|---|
| 1 — Acesso e Consulta | Solicitante acessa o modulo; sistema verifica pre-condicoes | Solicitante / Backend |
| 2 — Preenchimento | Solicitante preenche formulario e backend valida RNs | Solicitante / Backend |
| 3 — Persistencia | Upload Alfresco, criacao do RecursoED (RASCUNHO), filtragem | Backend |
| 4 — Envio | Solicitante confirma envio; backend registra transicao de estado | Solicitante / Backend |
| 5 — Aceites | Co-signatarios decidem; loop de unanimidade | Co-signatarios / Backend |
| 6 — Unanimidade | Backend registra AGUARDANDO_DISTRIBUICAO, atualiza licenciamento | Backend |
| 7 — Analise | Analista CBM assume, registra despacho e conclui | Analista CBM |
| 8 — Resultado | Backend registra resultado; notifica; encerra (deferido ou indeferido) | Backend |

### Por que o consenso dos co-signatarios e obrigatorio?

A exigencia de unanimidade de todos os co-signatarios (RN-084) antes do envio para analise decorre da natureza juridica do recurso: trata-se de uma manifestacao formal de contestacao perante o CBMRS, que pode ter consequencias legais para todos os envolvidos vinculados ao licenciamento. Um RT de execucao nao pode ser forcado a assinar um recurso que questiona a analise tecnica de projeto (responsabilidade do RT de projeto); da mesma forma, proprietarios nao podem ser representados sem consentimento expresso. O sistema implementa isso por meio da coluna `IND_ACEITE` (persistida como `CHAR(1)` via `SimNaoBooleanConverter`) na tabela de aceites do recurso, que deve ter valor `'S'` para todos os registros antes de qualquer avanco de estado.

---

## 2. Estrutura do Pool, Raias e Justificativa de Modelagem

### Decisao de usar um unico Pool com quatro raias

O P10 e modelado como **um unico Pool** com quatro raias horizontais, diferentemente do P08 (dois Pools independentes para sub-processos de estados distintos) e do P06 (dois Pools para fluxos que podem ocorrer em paralelo). A decisao de usar um unico Pool e justificada porque o P10 e um processo continuo com um unico ponto de inicio, uma sequencia determinista de fases e um conjunto claramente delimitado de atores. Nao ha ramificacao de entrada baseada em estado preexistente que justificaria Pools separados.

A escolha de **quatro raias** em vez de tres (como no P09) e justificada pela presenca de um quarto ator com responsabilidade clara e distinta: o Analista CBM-RS, que opera no backend administrativo com endpoints completamente diferentes (`/adm/recursos`, `/adm/recurso-analise`) e com permissoes de acesso distintas dos demais atores. Fundir o Analista CBM com o Sistema Backend numa mesma raia obscureceria qual parte do fluxo e interacao humana (userTask) e qual e processamento automatico (serviceTask).

### Raia 1: Solicitante (RT / RU / Proprietario)

Posicionada no topo (`y=60` a `y=200` no diagrama, altura 140px), esta raia contem os tres `UserTask` relacionados exclusivamente ao ator que inicia e acompanha o recurso: selecao do licenciamento, preenchimento do formulario e confirmacao do envio. O nome composto da raia ("RT / RU / Proprietario") e intencional: o sistema SOL permite que qualquer envolvido vinculado ao licenciamento inicie o recurso, desde que autenticado via SOE PROCERGS com token JWT valido. O `camunda:assignee="${solicitante}"` nos `UserTask` desta raia representa esse ator polimorfico.

### Raia 2: Co-Signatarios (RTs / RU / Proprietarios envolvidos)

Posicionada abaixo da raia do Solicitante (`y=200` a `y=340`, altura 140px), esta raia contem o `UserTask` de decisao de aceite — o unico ponto de interacao dos co-signatarios com o processo — e os dois `BoundaryEvent` que estao graficamente "grudados" nesse task. A separacao em raia propria e necessaria por tres razoes:

1. Os co-signatarios sao atores distintos do solicitante, com momento de interacao diferente (recebem notificacao por email e acessam o sistema em seguida).
2. A unanimidade de aceites e uma condicao de negocio que envolve multiplos atores da mesma categoria, o que justifica uma raia dedicada.
3. Os `BoundaryEvent` precisam estar na mesma raia do `UserTask` ao qual estao anexados — colocar o evento de recusa e o de cancelamento na raia do Backend ou do Solicitante seria graficamente incorreto e semanticamente enganoso.

### Raia 3: Sistema SOL Backend (Java EE / WildFly)

Posicionada no meio inferior (`y=340` a `y=580`, altura 240px), esta e a raia mais populosa do diagrama, com 27 elementos: seis `ServiceTask` na fase de criacao do recurso, dois gateways de pre-condicao, dois gateways de encerramento, todas as tarefas de processamento dos boundary events, e as tarefas de resultado da analise. A altura de 240px — contra 140px para cada uma das raias de atores humanos — e necessaria para acomodar tanto o fluxo principal horizontal (y≈460) quanto as ramificacoes de encerramento das instancias de indeferimento (y≈495-540) e os subnos de recusa e cancelamento (y≈490-540) dispostos verticalmente abaixo do fluxo principal.

Cada `ServiceTask` desta raia possui `camunda:class` apontando para o EJB `@Stateless` real: `RecursoRN`, `RecursoRNVal`, ou `ArquivoRN`. Isso torna o diagrama diretamente rastreavel ao codigo-fonte sem necessidade de documentacao adicional de mapeamento.

### Raia 4: Analista CBM-RS

Posicionada na base (`y=580` a `y=840`, altura 260px), esta raia contem os tres `UserTask` da fase de analise administrativa. A separacao em raia propria e justificada porque:

1. O analista acessa o sistema pelo modulo administrativo, com endpoints completamente distintos (`/adm/recursos`, `/adm/recurso-analise`).
2. O `camunda:assignee="${analistaCBM}"` identifica um perfil de usuario diferente (servidor do CBMRS, nao cidadao ou RT externo).
3. A fase de analise ocorre completamente fora do alcance do solicitante — uma raia propria torna isso visualmente imediato.

A altura generosa de 260px nao e necessaria para o numero de elementos (apenas tres tasks horizontais), mas cria espacamento visual adequado que facilita a leitura do diagrama, especialmente nos pontos de cruzamento de raias em que as setas da fase de analise sobem da raia do Analista para os gateways na raia do Backend.

### Dimensoes do Pool

O Pool tem largura de 4520px — a maior de todos os processos documentados ate P10. Essa largura e ditada pela fase 8 (resultado e encerramento), que adiciona dois gateways em cascata (`GW_StatusRecurso` → `GW_Instancia`) seguidos de tres ramificacoes paralelas de encerramento que se estendem horizontalmente em direcoes distintas. O P09, para comparacao, tem 3790px — o P10 adiciona cerca de 730px apenas para acomodar a logica de deferimento/indeferimento e o bloqueio de recurso da 2a instancia.

---

## 3. Fase 1 — Acesso ao Modulo e Consulta de Pre-condicoes

### 3.1 Evento de Inicio e Contexto de Entrada

O evento de inicio **`StartEvent_P10`** ("Solicitante acessa modulo de Recurso Administrativo") esta posicionado na extremidade esquerda da raia do Solicitante. E um evento de inicio do tipo "None" (circulo simples), indicando que o processo e iniciado por acao direta do usuario no sistema — nao ha mensagem de correlacao, temporizador nem sinal disparador. O processo P10 nao e acionado automaticamente por nenhum outro processo SOL; ele e reativo e depende de uma decisao consciente do solicitante de contestar a CIA ou CIV.

O contexto de entrada pressupoe que o licenciamento ja possui uma CIA ou CIV emitida. O frontend Angular apresenta a opcao de recurso a partir da pagina de detalhes do licenciamento, no momento em que a situacao do licenciamento e compativel com a existencia de inconformidades registradas. A rota de entrada e `/licenciamentos/{idLic}/recursos/novo`.

O token JWT emitido pelo SOE PROCERGS ja esta presente na sessao do usuario e contem o identificador `idUsuarioSoe` (tipo `Long`), que sera propagado em todas as chamadas de API subsequentes como parametro de autoria e identidade — garantindo que cada operacao seja rastreavel ao ator humano que a executou.

### 3.2 Selecao do Licenciamento e Visualizacao da CIA/CIV

A primeira `UserTask`, **`Task_AcessarRecurso`** ("Selecionar licenciamento e consultar CIA/CIV disponivel para recurso"), representa a tela de entrada do modulo de recurso. O solicitante seleciona o licenciamento e visualiza a CIA ou CIV que sera objeto do recurso.

O endpoint chamado e:
```
GET /recursos?idLicenciamento={id}
```
implementado por `RecursoRest.listar()`. A resposta exibe: numero do licenciamento, tipo da inconformidade (CIA ou CIV), data de emissao, prazo restante para recurso (calculado com base nas constantes `PRAZO_SOLICITAR_1_INSTANCIA` e `PRAZO_SOLICITAR_RECURSO_2_INSTANCIA`), instancia disponivel para o licenciamento (1a ou 2a), e o historico de recursos anteriores (se houver).

**Por que esta etapa existe antes do formulario?** Porque o solicitante precisa confirmar qual CIA ou CIV esta contestando antes de preencher qualquer dado. Um licenciamento pode ter CIAs emitidas em momentos distintos por analises parciais sucessivas, e o campo `NRO_INT_ARQUIVO_CIA_CIV` (que referencia a analise ou vistoria especifica contestada) precisa ser claramente identificado antes que o formulario seja aberto. Abrir o formulario de recurso sem essa contextualizacao previa levaria a erros de associacao — o solicitante poderia contestar a CIA errada.

O fluxo de saida desta task (SF02) desce da raia do Solicitante para a raia do Backend, representando a chamada ao backend para verificar as pre-condicoes antes de apresentar o formulario.

### 3.3 Verificacao de Pre-condicoes no Backend (RN-075/078/079/082)

A `ServiceTask` **`Task_ConsultarLicenciamento`** ("Verificar pre-condicoes: prazo, recursoBloqueado, instancia") e executada pelo EJB `RecursoRNVal`. Esta tarefa realiza quatro verificacoes criticas antes que o formulario seja exibido ao solicitante:

**RN-075 — Calcular a instancia disponivel:**
```sql
SELECT COUNT(*) FROM CBM_RECURSO
WHERE NRO_INT_LICENCIAMENTO = ? AND NRO_INSTANCIA = 1 AND TP_SITUACAO != 'CA'
```
Se o resultado for 0, nenhuma 1a instancia foi utilizada — o recurso disponivel e o de 1a instancia. Se o resultado for maior que 0, o recurso de 1a instancia ja foi utilizado (e nao foi cancelado), portanto a unica opcao e a 2a instancia — desde que ainda esteja dentro do prazo.

**RN-078 — Prazo para 1a instancia:**
```java
ChronoUnit.DAYS.between(dataCia, LocalDate.now()) <= PRAZO_SOLICITAR_1_INSTANCIA // 30 dias
```
O prazo e calculado a partir da data de emissao da CIA ou CIV. Se o prazo expirou, o sistema bloqueia o acesso ao formulario.

**RN-079 — Prazo para 2a instancia:**
```java
ChronoUnit.DAYS.between(dataConclusao1aInstancia, LocalDate.now()) <= PRAZO_SOLICITAR_RECURSO_2_INSTANCIA // 15 dias
```
Aplicavel apenas quando a 2a instancia e solicitada. O prazo e contado a partir da data de conclusao da analise da 1a instancia.

**RN-082 — Verificar IND_RECURSO_BLOQUEADO:**
```sql
SELECT IND_RECURSO_BLOQUEADO FROM CBM_LICENCIAMENTO WHERE NRO_INT_LICENCIAMENTO = ?
```
A coluna `IND_RECURSO_BLOQUEADO` e persistida como `CHAR(1)` e convertida para `Boolean` pelo `SimNaoBooleanConverter` (padrao do sistema SOL: `'S'` = `true`, `'N'`/`NULL` = `false`). Se o valor for `true`, o sistema lanca `WebApplicationRNException` com a mensagem `bundle.getMessage("recurso.bloqueado.para.recurso")` e status HTTP `406 NOT_ACCEPTABLE`.

**Por que estas verificacoes sao feitas antes de exibir o formulario?** Para evitar que o usuario preencha um formulario extenso com fundamentacao legal e documentos comprobatorios para em seguida descobrir que o recurso e inadmissivel por motivos estruturais como prazo expirado ou bloqueio definitivo. A experiencia de usuario e melhor quando os bloqueios sao apresentados antes da interacao, nao apos ela.

### 3.4 Gateway: Pode Abrir Recurso?

O gateway exclusivo **`GW_PodeRecursar`** ("Pode abrir recurso? prazo / bloqueio / instancia") bifurca o fluxo com base no resultado das verificacoes:

- **Sim (SF05_liberado):** o fluxo sobe da raia do Backend para a raia do Solicitante, apresentando o formulario de preenchimento do recurso. O waypoint `(700, 435) → (700, 130) → (785, 130)` garante que a seta suba verticalmente dentro da mesma coluna X antes de cruzar horizontalmente para o formulario, evitando sobreposicao visual com outros elementos.

- **Nao (SF04_bloqueado):** o fluxo desce para o evento de fim de erro, dentro da propria raia do Backend, indicando que o processo encerrou por violacao de pre-condicao antes mesmo do preenchimento.

### 3.5 Evento de Fim de Erro: Recurso Bloqueado

O **`EndEvent_RecursoBloqueado`** encerra o processo com `ErrorEventDefinition` de codigo `RECURSO_BLOQUEADO`. A escolha de evento de fim de erro, e nao de fim simples, e deliberada: permite distinguir visualmente que o encerramento nao e um resultado normal do processo, mas uma falha de admissibilidade.

As causas que levam a este fim sao:
- Prazo de 30 dias expirado (RN-078, 1a instancia).
- Prazo de 15 dias expirado (RN-079, 2a instancia).
- `IND_RECURSO_BLOQUEADO='S'` no licenciamento (RN-082), que e ativado permanentemente quando a 2a instancia e indeferida (RN-089).

O elemento esta posicionado abaixo do gateway (y=515 contra y=435 do gateway), fora da linha horizontal de fluxo, para nao criar congestionamento visual.

---

## 4. Fase 2 — Preenchimento e Validacao do Formulario

### 4.1 Preenchimento do Formulario de Recurso

A `UserTask` **`Task_PreencherFormulario`** ("Preencher formulario de recurso: tipo, instancia, fundamentacao, documentos") e o ponto central de interacao do solicitante com o processo P10. O `camunda:formKey="recursos/novo"` identifica o componente Angular responsavel pelo formulario.

Os campos do formulario correspondem diretamente as colunas da entidade `RecursoED` (tabela `CBM_RECURSO`):

| Campo do formulario | Coluna Oracle | Enum / Tipo |
|---|---|---|
| Tipo de recurso | `TP_RECURSO VARCHAR2(1)` | `TipoRecurso`: `'A'`=CORRECAO_DE_ANALISE / `'V'`=CORRECAO_DE_VISTORIA |
| Tipo de solicitacao | `TP_SOLICITACAO VARCHAR2(1)` | `TipoSolicitacaoRecurso`: `'I'`=INTEGRAL / `'P'`=PARCIAL |
| Fundamentacao legal | `TXT_FUNDAMENTACAO_LEGAL CLOB` | Texto livre obrigatorio |
| CIA/CIV contestada | `NRO_INT_ARQUIVO_CIA_CIV NUMBER` | FK para `CBM_ANALISE` (CIA) ou `CBM_VISTORIA` (CIV) |
| Instancia | `NRO_INSTANCIA NUMBER(1)` | Calculado pelo sistema (RN-075), exibido ao usuario |
| Documentos comprobatorios | Upload multipart | Persistidos via Alfresco (fase seguinte) |

O campo **tipo de solicitacao** (INTEGRAL ou PARCIAL) tem implicacao direta na revisao que o CBMRS fara se o recurso for deferido: INTEGRAL significa que o solicitante contesta toda a CIA/CIV; PARCIAL significa que contesta apenas alguns itens especificos das inconformidades apontadas. A separacao permite que o CBMRS dimensione o esforco de revisao antes mesmo de distribuir o recurso para analise.

O campo **fundamentacao legal** (`TXT_FUNDAMENTACAO_LEGAL`, persistido como `CLOB` no Oracle) e a peca central do recurso: e o argumento tecnico-juridico do solicitante. Sua obrigatoriedade (RN-076) reflete que um recurso sem fundamentacao nao e um recurso — e uma reclamacao sem base formal.

O fluxo de saida (SF06) desce da raia do Solicitante para a raia do Backend, representando a submissao do formulario via chamada HTTP `POST /recursos`.

### 4.2 Validacao Completa das Regras de Negocio (RN-073 a RN-082)

A `ServiceTask` **`Task_ValidarDados`** ("Validar regras de negocio do formulario") invoca `RecursoRNVal` para aplicar todas as dez regras de validacao antes de qualquer escrita no banco de dados:

| Regra | Verificacao | Motivo tecnico |
|---|---|---|
| RN-073 | `tipoSolicitacao` pertence ao enum `TipoSolicitacaoRecurso` {INTEGRAL, PARCIAL} | Impede valores arbitrarios que quebrariam a logica de revisao |
| RN-074 | `tipoRecurso` pertence ao enum `TipoRecurso` {CORRECAO_DE_ANALISE, CORRECAO_DE_VISTORIA} | Impede recurso sem identificacao do objeto contestado |
| RN-075 | Instancia calculada corretamente; nao pode abrir 2a sem conclusao da 1a | Impede salto de instancia que tornaria o processo juridicamente nulo |
| RN-076 | `fundamentacaoLegal != null && !fundamentacaoLegal.trim().isEmpty()` | Recurso sem fundamentacao e inadmissivel formalmente |
| RN-077 | `NRO_INT_ARQUIVO_CIA_CIV` existe e pertence ao licenciamento informado | Impede contestacao de CIA/CIV de outro licenciamento |
| RN-078 | `ChronoUnit.DAYS.between(dataCia, now()) <= 30` | Revalida prazo (pode ter mudado desde a consulta inicial) |
| RN-079 | `ChronoUnit.DAYS.between(dataConclusao1a, now()) <= 15` | Revalida prazo de 2a instancia |
| RN-080 | `idUsuarioSoe` do solicitante e um dos envolvidos do licenciamento | Impede abertura de recurso por terceiros nao vinculados |
| RN-081 | Nao existe recurso em situacao ativa para o mesmo licenciamento e instancia | Impede dois recursos paralelos para a mesma CIA/CIV e instancia |
| RN-082 | `IND_RECURSO_BLOQUEADO` do licenciamento nao e `'S'` | Revalida bloqueio (pode ter sido ativado desde a consulta inicial) |

A revalidacao de RN-078, RN-079 e RN-082 — ja verificadas em `Task_ConsultarLicenciamento` — e necessaria porque entre a consulta inicial e a submissao do formulario pode ter passado tempo suficiente para o prazo expirar ou outro processo ter ativado o bloqueio. Essa dupla validacao implementa o principio de **defesa em profundidade**: o frontend exibe restricoes, mas o backend nunca confia cegamente no que recebeu.

### 4.3 Gateway: Dados Validos?

O gateway exclusivo **`GW_ValidacaoOk`** bifurca:

- **Valido (SF09_valido):** prossegue para o upload dos documentos e persistencia. O waypoint direciona o fluxo para a direita dentro da raia do Backend.

- **Invalido (SF08_invalido):** desce para o evento de fim de erro, dentro da raia do Backend. O frontend recebe a lista de violacoes e as exibe inline no formulario (highlight nos campos invalidos com mensagens especificas de cada RN violada).

### 4.4 Evento de Fim de Erro: Erro de Validacao

O **`EndEvent_ErroValidacao`** encerra o processo com `ErrorEventDefinition` de codigo `ERRO_VALIDACAO_RECURSO`. Nenhum dado e persistido quando este fim e atingido — nao ha registro em `CBM_RECURSO`, `CBM_ARQUIVO` ou `CBM_RECURSO_ARQUIVO`.

A separacao deste fim de erro em relacao ao `EndEvent_RecursoBloqueado` e intencional: o primeiro representa bloqueio estrutural (prazo, bloqueio definitivo) que impede ate mesmo o acesso ao formulario; o segundo representa validacao de dados do formulario que pode ser corrigida pelo proprio solicitante. Os dois fins de erro, embora visualmente similares, representam classes de problema distintas com diferentes possibilidades de recuperacao.

---

## 5. Fase 3 — Upload de Documentos e Persistencia do Recurso em RASCUNHO

### 5.1 Upload de Documentos Comprobatorios ao Alfresco ECM

A `ServiceTask` **`Task_UploadDocumentos`** ("Enviar documentos comprobatorios ao Alfresco ECM") invoca `ArquivoRN.incluir()` para persistir os arquivos no repositorio ECM Alfresco antes de criar o registro do recurso no banco relacional Oracle.

**Por que o upload ao Alfresco precede a criacao do RecursoED?** Por integridade referencial: a entidade `RecursoArquivoED` (tabela `CBM_RECURSO_ARQUIVO`) tem como chaves estrangeiras tanto `NRO_INT_RECURSO` (do recurso recentemente criado) quanto `NRO_INT_ARQUIVO` (do arquivo recem persistido no Oracle apos upload no Alfresco). Se o upload falhasse apos a criacao do recurso, haveria um recurso orphao sem documentos e sem mecanismo automatico de limpeza. Ao persistir o Alfresco primeiro, uma falha nesta etapa nao deixa registros parciais no Oracle.

O retorno do Alfresco e o `nodeRef` no formato `workspace://SpacesStore/{UUID}`, que e gravado na coluna `IDENTIFICADOR_ALFRESCO VARCHAR2(150)` da entidade `ArquivoED` (tabela `CBM_ARQUIVO`). Esta coluna e `@NotNull` — sem o nodeRef do Alfresco, o arquivo nao pode ser persistido no Oracle.

Esta tarefa e executada apenas quando ha arquivos no corpo multipart da requisicao. Se o solicitante nao enviou documentos (o formulario pode permitir recurso sem anexos, dependendo do tipo), a tarefa e uma operacao no-op (zero iteracoes).

### 5.2 Persistencia do RecursoED em CBM_RECURSO

A `ServiceTask` **`Task_CriarRecurso`** ("Persistir RecursoED em CBM_RECURSO com situacao RASCUNHO") invoca `RecursoRN.incluir()` para criar o registro principal do recurso no banco de dados Oracle.

O mapeamento completo das colunas persistidas e:

| Coluna Oracle | Valor | Origem |
|---|---|---|
| `NRO_INT_RECURSO` | Gerado por `CBM_ID_RECURSO_SEQ` | Sequence Oracle |
| `NRO_INT_LICENCIAMENTO` | ID do licenciamento | Parametro da requisicao |
| `NRO_INSTANCIA` | 1 ou 2 | Calculado por RN-075 |
| `TP_SITUACAO` | `'R'` | `SituacaoRecurso.RASCUNHO` |
| `TP_RECURSO` | `'A'` ou `'V'` | `TipoRecurso` do formulario |
| `TP_SOLICITACAO` | `'I'` ou `'P'` | `TipoSolicitacaoRecurso` do formulario |
| `TXT_FUNDAMENTACAO_LEGAL` | Texto do solicitante | Campo CLOB do formulario |
| `NRO_INT_ARQUIVO_CIA_CIV` | ID da CIA ou CIV | Selecionado na tela inicial |
| `NRO_INT_USUARIO_SOE` | `idUsuarioSoe` do solicitante | Token JWT SOE PROCERGS |
| `CTR_DTH_INC` | `LocalDateTime.now()` | Timestamp de auditoria |

A situacao inicial `'R'` (RASCUNHO) significa que o recurso foi criado mas ainda nao foi enviado para os co-signatarios. O solicitante pode editar e cancelar um recurso em RASCUNHO sem restricoes. Esta e a unica situacao em que o recurso e "invisivel" para o backend administrativo do CBMRS — analistas nao veem recursos em RASCUNHO na sua fila de distribuicao.

Neste mesmo metodo, os registros de `RecursoArquivoED` (tabela `CBM_RECURSO_ARQUIVO`) sao criados para associar cada arquivo Alfresco ao recurso recem-criado, usando a sequence `CBM_ID_RECURSO_ARQUIVO_SEQ`.

### 5.3 Filtragem dos Co-signatarios por TipoRecurso (RN-083)

A `ServiceTask` **`Task_FiltrarCoSignatarios`** ("Filtrar co-signatarios por TipoRecurso e criar aceites") implementa a regra mais sofisticada do processo P10 no que diz respeito a identidade dos co-signatarios.

A RN-083 determina que os Responsaveis Tecnicos elegíveis para co-assinar o recurso variam conforme o tipo de recurso:

```java
List<ResponsavelTecnicoED> rts = licenciamentoED.getResponsaveisTecnicos().stream()
  .filter(r ->
    (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.EXECUCAO)
      && recursoDTO.getTipoRecurso() == TipoRecurso.CORRECAO_DE_VISTORIA)
    || (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.PROJETO)
      && recursoDTO.getTipoRecurso() == TipoRecurso.CORRECAO_DE_ANALISE)
    || (r.getTipoResponsabilidadeTecnica().equals(TipoResponsabilidadeTecnica.PROJETO_EXECUCAO)))
  .collect(Collectors.toList());
```

A logica de filtragem pode ser resumida na tabela:

| TipoRecurso | RT PROJETO | RT EXECUCAO | RT PROJETO_EXECUCAO |
|---|---|---|---|
| CORRECAO_DE_ANALISE (CIA) | Sim | Nao | Sim |
| CORRECAO_DE_VISTORIA (CIV) | Nao | Sim | Sim |

**Por que essa distincao existe?** Porque a responsabilidade tecnica e particionada por fase do processo de licenciamento. O RT de PROJETO e responsavel tecnico pelo desenho e calculo do PPCI — e quem deve responder por uma inconformidade identificada na analise documental (CIA). O RT de EXECUCAO e responsavel pela implementacao fisica das medidas de prevencao — e quem deve responder por uma inconformidade identificada na vistoria presencial (CIV). O RT de PROJETO_EXECUCAO acumula ambas as responsabilidades e, portanto, e sempre elegivel. Forcar um RT de execucao a co-assinar um recurso sobre a analise documental (que nao e sua responsabilidade) seria juridicamente inadequado.

Alem dos RTs filtrados, os co-signatarios incluem o RU e todos os Proprietarios do licenciamento, que devem ser notificados e devem consentir com a contestacao por representarem o interesse do imovel perante o CBMRS.

---

## 6. Fase 4 — Envio do Recurso para Aceite dos Co-signatarios

### 6.1 Confirmacao e Envio pelo Solicitante

A `UserTask` **`Task_EnviarRecurso`** ("Revisar resumo e confirmar envio do recurso para aceite dos co-signatarios") representa a tela de revisao e confirmacao antes do envio formal. O solicitante visualiza um resumo do recurso (tipo, instancia, fundamentacao, lista de documentos, lista de co-signatarios) e confirma a acao de envio.

Esta tarefa e o ultimo ponto de controle exclusivo do solicitante antes que o processo se torne dependente de terceiros. Apos o envio, o recurso passa a estado `AGUARDANDO_APROVACAO_ENVOLVIDOS` e so pode ser revertido para edicao por meio de `habilitarEdicao()` (RN-087) ou cancelado (RN-085, enquanto ainda em `AGUARDANDO_APROVACAO_ENVOLVIDOS`).

**Por que existe um `UserTask` de confirmacao separado do preenchimento?** Porque o preenchimento (Fase 2) e o ato de compor o recurso; o envio (Fase 4) e o ato de comprometer-se formalmente com ele. A separacao permite que o solicitante salve o recurso em RASCUNHO e retorne para revisar e completar em sessoes distintas, sem que o recurso seja automaticamente enviado apos o preenchimento inicial.

O endpoint de envio e `POST /recursos/{id}/enviar`, implementado por `RecursoRest.enviar()`, que invoca `RecursoRN.enviar(idRecurso, idUsuarioSoe)`.

Nesta mesma task, o solicitante pode acionar `DELETE /recursos/{id}/cancelar` (cancelar em RASCUNHO, RN-085) ou `PUT /recursos/{id}/habilitar-edicao` (retornar para edicao de AGUARDANDO_APROVACAO_ENVOLVIDOS para RASCUNHO, RN-087). Essas opcoes nao sao modeladas como elementos BPMN separados antes do envio porque representam saidas laterais de uma UserTask que o usuario pode abandonar a qualquer momento — modelar cada possivel saida de uma UserTask geraria um grafo excessivamente complexo sem ganho semantico real.

### 6.2 Registro do Envio no Backend: Transicao de Estado e Marcos

A `ServiceTask` **`Task_RegistrarEnvio`** ("Registrar envio: AGUARDANDO_APROVACAO_ENVOLVIDOS + marco + notificacao co-signatarios") processa o envio no backend com tres acoes sequenciais dentro da mesma transacao JTA:

**Acao 1 — Transicao de estado:**
```sql
UPDATE CBM_RECURSO SET TP_SITUACAO = 'E' WHERE NRO_INT_RECURSO = ?
```
`'E'` representa `SituacaoRecurso.AGUARDANDO_APROVACAO_ENVOLVIDOS`. A partir deste momento, o recurso e visivel para os co-signatarios mas ainda nao esta na fila de analise do CBMRS.

**Acao 2 — Registro de marco:**
```sql
INSERT INTO CBM_RECURSO_MARCO (
  NRO_INT_RECURSO_MARCO, NRO_INT_RECURSO, COD_TP_MARCO,
  COD_TP_VISIBILIDADE, DTH_MARCO, NRO_INT_USUARIO_SOE
) VALUES (
  CBM_ID_RECURSO_MARCO_SEQ.NEXTVAL, ?, ACEITE_RECURSO_ANALISE,
  INTERNO, SYSDATE, ?
)
```
`TipoMarco.ACEITE_RECURSO_ANALISE` e persistido como valor ordinal (`@Enumerated(EnumType.ORDINAL)` em `RecursoMarcoED`). Este marco documenta o momento exato em que o recurso foi enviado para aceite, criando uma trilha de auditoria imutavel.

**Acao 3 — Notificacao por email (RN-088):**
Todos os co-signatarios identificados na fase anterior recebem email com assunto `'Recurso {numero} aguarda sua assinatura'`, informando o prazo disponivel para aceite e o link para acesso ao sistema.

---

## 7. Fase 5 — Aceite dos Co-signatarios e Unanimidade

### 7.1 Tarefa de Decisao do Co-signatario

A `UserTask` **`Task_CoSignatarioDecide`** ("Co-signatario revisa o recurso e decide: aceitar ou recusar") e o no central da fase de aceites. Ela possui **duas entradas** (`SF14` vinda do `Task_RegistrarEnvio` e `SF16_pendente` vinda do `GW_TodosAceitaram` para o loop de unanimidade) e **uma saida** direta para o gateway de unanimidade, alem de dois `BoundaryEvent` anexados.

O `camunda:assignee="${coSignatario}"` indica que esta task e atribuida a um ator da categoria co-signatario — diferente do solicitante. Na pratica, o processo aguarda neste no enquanto qualquer co-signatario nao se manifestou.

O co-signatario tem tres opcoes:

**Aceitar** (`PUT /recursos/{id}/aceitar`): `RecursoRN.aceitar(idRecurso, idUsuarioSoe)` localiza o registro de aceite do usuario na tabela de aceites e seta `IND_ACEITE = 'S'` (via `SimNaoBooleanConverter`, que converte `true` para o caractere `'S'` no Oracle). O recurso permanece em `AGUARDANDO_APROVACAO_ENVOLVIDOS`; o processo retorna para o gateway de unanimidade.

**Recusar** (`PUT /recursos/{id}/recusar`): aciona o `BoundaryEvent_Recusa` (detalhado na Secao 8.1). O processo abandona a task e segue pelo caminho de recusa.

**Cancelar** (`DELETE /recursos/{id}/cancelar`): aciona o `BoundaryEvent_Cancelamento` (detalhado na Secao 8.2). O processo abandona a task e segue pelo caminho de cancelamento.

A task e modelada com **duas entradas** (e nao como um subprocesso de loop explicito) porque o loop de aceites no P10 e um loop de controle externo — cada iteracao do loop representa a manifestacao de um ator humano diferente, e o backend e quem rastreia quantos ainda faltam. O BPMN modela o comportamento do sistema, nao a implementacao interna; um loop explicito com contadores seria mais complexo sem ser mais expressivo.

### 7.2 Gateway: Todos Aceitaram? (Unanimidade — RN-084)

O gateway exclusivo **`GW_TodosAceitaram`** ("Todos os co-signatarios aceitaram? — RN-084 unanimidade") implementa a verificacao de unanimidade requerida pela RN-084.

A verificacao e realizada pelo backend com a consulta:
```sql
SELECT COUNT(*) FROM tabela_aceites
WHERE NRO_INT_RECURSO = ? AND (IND_ACEITE IS NULL OR IND_ACEITE = 'N')
```
- Se o resultado e **0** (nenhum pendente): todos aceitaram — fluxo segue por `SF17_unanimidade` para `Task_RegistrarUnanimidade`.
- Se o resultado e **maior que 0** (ha pendentes): fluxo retorna por `SF16_pendente` para `Task_CoSignatarioDecide`, aguardando a manifestacao do proximo co-signatario.

O **loop-back** `SF16_pendente` e a principal caracteristica arquitetural desta fase. No diagrama, o waypoint do loop percorre o caminho `(2440, 435) → (2440, 270) → (2345, 270)`, subindo verticalmente da raia do Backend para a raia dos Co-signatarios antes de retornar ao task. Essa rota evita que a seta de retorno sobreponha o fluxo principal horizontal e torna imediatamente visivel, ao leitor do diagrama, que o processo esta em um ciclo de espera.

---

## 8. Eventos de Boundary: Recusa e Cancelamento

### 8.1 BoundaryEvent Interrompente: Recusa de Aceite (RN-086)

O **`BoundaryEvent_Recusa`** e um evento de mensagem interrompente (`cancelActivity="true"`, `messageRef="Msg_RecusaAceite"`) anexado ao lado direito-inferior de `Task_CoSignatarioDecide`. Quando acionado, ele interrompe imediatamente a tarefa de decisao — cancelando todos os aceites que ja tinham sido dados por outros co-signatarios — e direciona o fluxo para `Task_SistemaRegistraRecusa`.

A **`Task_SistemaRegistraRecusa`** ("Registrar recusa: RASCUNHO + marco RECURSO_RECUSADO + notificar solicitante") executa `RecursoRN.recusar()`, que por sua vez chama `efetuarRecusas()`:

1. `UPDATE CBM_RECURSO SET TP_SITUACAO = 'R' WHERE NRO_INT_RECURSO = ?` (retorna para RASCUNHO, nao para CANCELADO).
2. Zera `IND_ACEITE = NULL` para todos os co-signatarios (reinicia o ciclo).
3. Insere marco `TipoMarco.RECURSO_RECUSADO` em `CBM_RECURSO_MARCO`.
4. Envia notificacao ao solicitante informando quem recusou (RN-088).

**Por que a recusa retorna para RASCUNHO e nao cancela o recurso?** Porque a recusa de aceite por um co-signatario nao representa uma decisao do solicitante de desistir do recurso — representa um desacordo interno entre os envolvidos. O solicitante pode editar a fundamentacao legal ou os documentos para convencer o co-signatario, ativar `habilitarEdicao()` (RN-087) e reenviar. Retornar para CANCELADO seria punir o solicitante pela recusa de terceiros, impedindo-o de corrigir e reenviar dentro do prazo disponivel.

O **`EndEvent_Recusado`** ("Recurso retornado para RASCUNHO") nao e um fim definitivo do processo: o solicitante pode reabrir o recurso, editá-lo e reenviar — desde que o prazo ainda nao tenha expirado. O BPMN o modela como fim porque, neste fluxo especifico (ciclo de aceites), o processo encerrou; o reenvio seria tecnicamente o inicio de um novo ciclo, ativando novamente o fluxo a partir de `Task_EnviarRecurso`.

### 8.2 BoundaryEvent Interrompente: Cancelamento do Recurso (RN-085)

O **`BoundaryEvent_Cancelamento`** e um evento de mensagem interrompente (`cancelActivity="true"`, `messageRef="Msg_CancelamentoRecurso"`) anexado ao lado esquerdo-inferior de `Task_CoSignatarioDecide`. A separacao visual dos dois boundary events nos lados opostos do task nao e arbitraria: o evento de recusa (lado direito) representa uma acao de um co-signatario; o evento de cancelamento (lado esquerdo) representa uma acao do solicitante. Essa disposicao facilita a leitura do diagrama por quem nao conhece o processo.

A **`Task_CancelarRecurso`** executa `RecursoRN.cancelarRecurso()`, que aplica a pre-condicao da RN-085:

```java
if (!(situacao.equals(AGUARDANDO_APROVACAO_ENVOLVIDOS) || situacao.equals(RASCUNHO))) {
  throw new WebApplicationRNException(
    bundle.getMessage("recurso.status.invalido"), Response.Status.BAD_REQUEST);
}
```

Seguida das acoes:
1. `UPDATE CBM_RECURSO SET TP_SITUACAO = 'CA'` (`SituacaoRecurso.CANCELADO`).
2. Marco `TipoMarco.RECURSO_CANCELADO`.
3. Marco especifico por tipo: `TipoMarco.CANCELAMENTO_RECURSO_CIA` ou `TipoMarco.CANCELAMENTO_RECURSO_CIV`.
4. Notificacao a todos os envolvidos (RN-088).

**Por que o cancelamento e definitivo enquanto a recusa nao e?** Porque o cancelamento e uma decisao voluntaria e soberana do solicitante de desistir do recurso. Nao ha mecanismo de "desfazer cancelamento" porque seria semanticamente contraditorio — o ato de cancelar expressa a intenção de encerrar. O solicitante pode abrir um novo recurso se ainda estiver dentro do prazo.

O **`EndEvent_Cancelado`** e um fim simples (sem marcador de erro), porque o cancelamento e um encerramento normal do processo pela vontade do solicitante — nao uma falha de sistema ou violacao de regra.

---

## 9. Fase 6 — Unanimidade, AGUARDANDO_DISTRIBUICAO e Situacao do Licenciamento

### 9.1 Registro de Unanimidade e Criacao de CBM_ANALISE_RECURSO

A `ServiceTask` **`Task_RegistrarUnanimidade`** ("Registrar unanimidade: AGUARDANDO_DISTRIBUICAO + marcos + AnaliseRecursoED") executa quatro operacoes atomicas dentro da mesma transacao JTA:

**Operacao 1 — Transicao de estado:**
```sql
UPDATE CBM_RECURSO
  SET TP_SITUACAO = 'D', DTH_ENVIO_ANALISE = SYSDATE
WHERE NRO_INT_RECURSO = ?
```
`'D'` = `SituacaoRecurso.AGUARDANDO_DISTRIBUICAO`. `DTH_ENVIO_ANALISE` (coluna `TIMESTAMP`) registra o momento exato em que o recurso entrou na fila de distribuicao — dado relevante para calculos de prazo interno do CBMRS.

**Operacao 2 — Marco de conclusao de aceites:**
```sql
INSERT INTO CBM_RECURSO_MARCO (COD_TP_MARCO = TipoMarco.FIM_ACEITES_RECURSO_ANALISE, ...)
```

**Operacao 3 — Marco de envio para analise:**
```sql
INSERT INTO CBM_RECURSO_MARCO (COD_TP_MARCO = TipoMarco.ENVIO_RECURSO_ANALISE, ...)
```

A existencia de dois marcos distintos (FIM_ACEITES e ENVIO_RECURSO_ANALISE) reflete que sao eventos distintos cronologicamente possiveis de rastrear: a unanimidade dos aceites pode ter ocorrido antes do processamento da transicao de estado. A trilha de auditoria registra ambos os momentos.

**Operacao 4 — Criacao da AnaliseRecursoED:**
```sql
INSERT INTO CBM_ANALISE_RECURSO (
  NRO_INT_ANALISE_RECURSO, NRO_INT_RECURSO, TP_STATUS,
  IND_CIENCIA, NRO_INT_USUARIO_SOE, CTR_DTH_INC
) VALUES (
  CBM_ID_ANALISE_RECURSO_SEQ.NEXTVAL, ?, 'EM_ANALISE',
  'N', NULL, SYSDATE
)
```
`IND_CIENCIA = 'N'` (via `SimNaoBooleanConverter`: `false` → `'N'`) indica que o analista ainda nao deu ciencia da conclusao. `NRO_INT_USUARIO_SOE = NULL` porque o analista ainda nao foi designado (ocorrera na distribuicao). `TP_STATUS` e persistido como `STRING` (nao ordinal) usando `@Enumerated(EnumType.STRING)` em `AnaliseRecursoED`.

**Por que criar o CBM_ANALISE_RECURSO ja na unanimidade, e nao na distribuicao?** Para garantir que o registro de analise exista antes da distribuicao, permitindo que o analista que distribuir o recurso encontre um registro para atualizar (via `UPDATE`) em vez de criar um novo (via `INSERT`). Isso simplifica o codigo da distribuicao e evita condicoes de corrida em ambientes com multiplos analistas competindo pela distribuicao do mesmo recurso.

### 9.2 Atualizacao da SituacaoLicenciamento (RN-075)

A `ServiceTask` **`Task_AtualizarSituacaoLic`** implementa o metodo `RecursoRN.retornaNovaSituacaoLicenciamento()`, que define como o licenciamento e classificado enquanto o recurso esta em analise.

A logica produce quatro valores possiveis para `CBM_LICENCIAMENTO.SIT_LICENCIAMENTO`:

```java
if (TipoRecurso.CORRECAO_DE_ANALISE.equals(recursoED.getTipoRecurso())) {
  return recursoED.getInstancia().equals(RECURSO_1_INSTANCIA)
    ? SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIA
    : SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIA;
}
return recursoED.getInstancia().equals(RECURSO_1_INSTANCIA)
  ? SituacaoLicenciamento.RECURSO_EM_ANALISE_1_CIV
  : SituacaoLicenciamento.RECURSO_EM_ANALISE_2_CIV;
```

| Tipo | Instancia | SituacaoLicenciamento |
|---|---|---|
| CIA | 1a | `RECURSO_EM_ANALISE_1_CIA` |
| CIA | 2a | `RECURSO_EM_ANALISE_2_CIA` |
| CIV | 1a | `RECURSO_EM_ANALISE_1_CIV` |
| CIV | 2a | `RECURSO_EM_ANALISE_2_CIV` |

**Por que o licenciamento precisa de quatro valores distintos para "em recurso"?** Porque o painel de gestao do CBMRS usa `SIT_LICENCIAMENTO` como filtro primario para exibir e organizar os licenciamentos em suas diferentes filas de trabalho. Um analista de CIA de 1a instancia ve apenas `RECURSO_EM_ANALISE_1_CIA` na sua fila; um membro do colegiado de 2a instancia ve `RECURSO_EM_ANALISE_2_CIA` ou `RECURSO_EM_ANALISE_2_CIV`. Ter um unico valor generico "EM_RECURSO" exigiria filtros adicionais e tornaria a interface administrativa mais complexa.

### 9.3 Notificacao dos Analistas CBM (RN-088)

A `ServiceTask` **`Task_NotificarCBM`** encerra a Fase 6 enviando email de notificacao aos analistas do CBMRS habilitados para distribuir e analisar recursos. O conteudo inclui o numero do licenciamento, tipo de recurso (CIA ou CIV), instancia (1a ou 2a), nome do solicitante (recuperado do SOE PROCERGS) e data de envio.

Esta notificacao e necessaria porque o sistema SOL nao tem um mecanismo de "push" para o modulo administrativo: os analistas sao notificados proativamente por email para que acessem o sistema e distribuam o recurso, evitando que recursos fiquem aguardando indefinidamente na fila sem que nenhum analista perceba.

---

## 10. Fase 7 — Analise pelo Analista CBM-RS

### 10.1 Distribuicao do Recurso para o Analista

A `UserTask` **`Task_AnalistaDistribui`** ("Analista CBM distribui recurso para si e registra inicio da analise") representa o ato do analista de assumir o recurso da fila de distribuicao.

O endpoint e `POST /adm/recursos/{id}/distribuir`, implementado por `RecursoAdmRest.distribuir()`, que executa:
1. `UPDATE CBM_RECURSO SET TP_SITUACAO = 'A'` (`SituacaoRecurso.EM_ANALISE`).
2. `UPDATE CBM_ANALISE_RECURSO SET NRO_INT_USUARIO_SOE = :idAnalistaSoe, TP_STATUS = 'EM_ANALISE'`.

A fila de distribuicao e consultada via `GET /adm/recursos?situacao=AGUARDANDO_DISTRIBUICAO`, que retorna os recursos ordenados por data de envio (`DTH_ENVIO_ANALISE`). O `RecursoResponseDTO` neste contexto inclui campos como `numeroAnalise` (numero sequencial da analise), `ultimaAnalisePor` (nome do analista, resolvido via SOE PROCERGS a partir do `NRO_INT_USUARIO_SOE`) e `qtdDiasRecurso` (dias corridos desde o envio).

**Por que o analista "distribui para si" em vez de um supervisor distribuir para um analista?** A implementacao atual do SOL permite auto-distribuicao, o que e adequado para a estrutura de trabalho do CBMRS onde os analistas sao responsaveis por gerenciar sua propria carga de trabalho. Uma versao futura poderia adicionar distribuicao por supervisor, mas a stack atual nao implementa isso.

Para recursos de 2a instancia, `TP_STATUS` pode transitar para `SituacaoAnaliseRecursoEnum.AGUARDANDO_AVALIACAO_COLEGIADO` durante a analise, quando o caso precisa ser levado ao colegiado antes da conclusao. Este estado intermediario nao altera o fluxo BPMN principal mas esta documentado no `<documentation>` do elemento correspondente.

### 10.2 Registro do Despacho Tecnico

A `UserTask` **`Task_AnalistaRegistraDespacho`** ("Analista CBM registra despacho e posicao tecnica") representa o trabalho intelectual central da analise: o analista estuda o recurso, compara os argumentos do solicitante com os criterios tecnicos da CIA/CIV contestada, e formula sua posicao.

O endpoint e `PUT /adm/recurso-analise/{id}`, que atualiza `CBM_ANALISE_RECURSO`:
- `TXT_DESPACHO CLOB` — texto do despacho tecnico.
- `NRO_INT_ARQUIVO NUMBER` — FK para arquivo de relatorio ou laudo em PDF, se houver.
- `TP_STATUS VARCHAR2` — pode ser alterado para `AGUARDANDO_AVALIACAO_COLEGIADO` se necessario.

O analista pode salvar rascunhos do despacho multiplas vezes antes de concluir, porque `PUT /adm/recurso-analise/{id}` e uma operacao de sobrescrita sem mudanca de estado do recurso principal.

### 10.3 Conclusao da Analise e Registro do Resultado

A `UserTask` **`Task_AnalistaConcluiAnalise`** ("Analista CBM conclui analise: registra status final DEFERIDO/INDEFERIDO") e o ponto de virada do processo: e aqui que o resultado e registrado definitivamente.

O endpoint e `PUT /adm/recurso-analise/{id}/concluir`, que atualiza:

**Em CBM_ANALISE_RECURSO:**
- `TP_STATUS = 'ANALISE_CONCLUIDA'` (`SituacaoAnaliseRecursoEnum.ANALISE_CONCLUIDA`).
- `CTR_DTH_CONCLUSAO_ANALISE = LocalDateTime.now()`.

**Em CBM_RECURSO:**
- `TP_SITUACAO = 'C'` (`SituacaoRecurso.ANALISE_CONCLUIDA`).
- `TP_STATUS` (campo distinto de `TP_SITUACAO`): o resultado final pelo enum `StatusRecurso`:

| Valor | Significado | Implicacao |
|---|---|---|
| `'T'` | DEFERIDO_TOTAL | CIA/CIV sera revisada integralmente pelo CBMRS |
| `'P'` | DEFERIDO_PARCIAL | CIA/CIV sera revisada nos itens contestados |
| `'I'` | INDEFERIDO | CIA/CIV mantem-se; recurso superior possivel (1a) ou processo encerrado (2a) |

A **ciencia do analista** e registrada por endpoint separado: `POST /adm/recurso-analise/{id}/ciencia`, que seta `IND_CIENCIA = 'S'` (via `SimNaoBooleanConverter`), `DTH_CIENCIA_ATEC = LocalDateTime.now()` e `NRO_INT_USUARIO_CIENCIA = idUsuarioSoe` do analista. Esta ciencia pode ocorrer antes ou apos a conclusao, e representa a confirmacao formal do analista de que tomou conhecimento e responsabilidade pelo resultado.

---

## 11. Fase 8 — Resultado e Encerramento

### 11.1 Gateway: Status da Analise?

O gateway exclusivo **`GW_StatusRecurso`** ("Status da analise? TP_STATUS em CBM_RECURSO") recebe o fluxo vindo da raia do Analista CBM (cross-lane de baixo para cima) e bifurca com base no campo `TP_STATUS`:

- **DEFERIDO_TOTAL (`'T'`) ou DEFERIDO_PARCIAL (`'P'`)** → `SF29_deferido` para `Task_ConcluirDeferimento`.
- **INDEFERIDO (`'I'`)** → `SF30_indeferido` para `GW_Instancia`.

A fusao dos dois tipos de deferimento numa unica saida do gateway e justificada porque as acoes de encerramento sao as mesmas para DEFERIDO_TOTAL e DEFERIDO_PARCIAL do ponto de vista do processo P10: registro de marco, notificacao e encerramento. A diferenca entre total e parcial sera tratada no processo subsequente de revisao da CIA/CIV pelo CBMRS, que e fora do escopo do P10.

### 11.2 Gateway: Qual Instancia foi Indeferida?

O gateway exclusivo **`GW_Instancia`** ("Qual instancia foi indeferida? NRO_INSTANCIA") diferencia o tratamento com base em `CBM_RECURSO.NRO_INSTANCIA`:

- **1a instancia (`NRO_INSTANCIA = 1`)** → `SF31_1aInstancia` para `Task_ConcluirIndeferido1a`. O solicitante tem direito a interpor recurso de 2a instancia dentro de 15 dias (RN-079).

- **2a instancia (`NRO_INSTANCIA = 2`)** → `SF32_2aInstancia` para `Task_SistemaBloqueiaRecurso`. O processo encerra definitivamente; nenhum recurso adicional pode ser interposto.

A separacao deste gateway em relacao ao `GW_StatusRecurso` — em vez de um gateway unico com tres saidas — e uma decisao de modelagem deliberada: um gateway com tres saidas (DEFERIDO, INDEFERIDO-1a, INDEFERIDO-2a) criaria a impressao de que o sistema conhece antecipadamente a instancia ao determinar o status, o que nao e verdade — o status (deferido/indeferido) e determinado primeiro, e somente se indeferido a instancia importa. Dois gateways em cascata representam fielmente essa logica de decisao sequencial.

### 11.3 Encerramento com Deferimento

A `ServiceTask` **`Task_ConcluirDeferimento`** registra o marco de conclusao com visibilidade externa (`TipoVisibilidade.EXTERNO`) e envia notificacao a todos os envolvidos (RN-088):
- DEFERIDO_TOTAL: `'Recurso deferido integralmente. A CIA/CIV sera revisada.'`
- DEFERIDO_PARCIAL: `'Recurso parcialmente deferido. Revisao parcial da CIA/CIV.'`

O **`EndEvent_Deferido`** e um evento de fim simples (sem marcador de erro), porque o deferimento e um encerramento positivo do processo. O licenciamento aguarda a revisao da CIA/CIV pelo CBMRS, que e tratada em processo separado fora do escopo do P10.

### 11.4 Encerramento com Indeferimento em 1a Instancia

A `ServiceTask` **`Task_ConcluirIndeferido1a`** notifica todos os envolvidos com informacao clara sobre o prazo de 15 dias para a 2a instancia, incluindo a data-base de calculo (data de conclusao da analise). `IND_RECURSO_BLOQUEADO` permanece `'N'` — o solicitante conserva o direito de recorrer.

O **`EndEvent_Indeferido1a`** e um evento de fim simples. Embora seja um resultado desfavoravel para o solicitante, e um encerramento previsto e normal do processo nesta instancia — o sistema cumpriu sua funcao de processar o recurso e registrar o resultado.

### 11.5 Bloqueio e Encerramento com Indeferimento em 2a Instancia (RN-089)

Este e o caminho mais consequente do processo P10, pois produz um efeito permanente e irreversivel no licenciamento.

A `ServiceTask` **`Task_SistemaBloqueiaRecurso`** ("Bloquear novos recursos: UPDATE IND_RECURSO_BLOQUEADO=S") executa:
```sql
UPDATE CBM_LICENCIAMENTO
  SET IND_RECURSO_BLOQUEADO = 'S'
WHERE NRO_INT_LICENCIAMENTO = ?
```
A coluna `IND_RECURSO_BLOQUEADO CHAR(1)` usa o mesmo `SimNaoBooleanConverter` que outras colunas booleanas do sistema SOL: `true` → `'S'`, `false` → `'N'`/`NULL`. O valor `'S'` e permanente — nao ha endpoint ou fluxo que o reverta.

**Por que esta tarefa e separada de `Task_ConcluirIndeferido2a`?** Por clareza semantica e pela possibilidade de tratamento diferenciado de erros: o bloqueio do licenciamento e uma operacao de alta criticidade que nao deve ser misturada com o envio de notificacoes. Se o bloqueio falhar por qualquer motivo (ex: timeout de banco), a transacao e revertida sem que notificacoes incorretas sejam enviadas. Separar as tarefas permite que o sistema de monitoramento identifique exatamente em qual etapa uma eventual falha ocorreu.

A `ServiceTask` **`Task_ConcluirIndeferido2a`** notifica todos os envolvidos com mensagem definitiva: `'O recurso foi indeferido em 2a e ultima instancia. A CIA/CIV emitida e definitiva. Nenhum novo recurso pode ser interposto.'`. Tambem atualiza `SIT_LICENCIAMENTO` do licenciamento de volta para CIA ou CIV emitida (a CIA/CIV passa a ser definitiva).

O **`EndEvent_Indeferido2a`** e o fim mais terminal do processo: o licenciamento permanece com a CIA/CIV, o `IND_RECURSO_BLOQUEADO` e permanentemente `'S'`, e qualquer tentativa futura de abrir recurso sera bloqueada pela RN-082 na primeira etapa de consulta de pre-condicoes.

---

## 12. Fluxos Cross-Lane e Decisoes de Roteamento Visual

O BPMN do P10 possui sete cruzamentos de raia (cross-lane sequence flows), cada um representando uma transicao entre responsabilidades de atores distintos:

| Fluxo | De | Para | Direcao | Semantica |
|---|---|---|---|---|
| SF02 | Solicitante | Backend | Baixo | Submissao do licenciamento selecionado para verificacao |
| SF05 | Backend | Solicitante | Cima | Liberacao do formulario apos pre-condicoes validadas |
| SF06 | Solicitante | Backend | Baixo | Submissao do formulario para validacao |
| SF12 | Backend | Solicitante | Cima | Exibicao da tela de confirmacao de envio |
| SF13 | Solicitante | Backend | Baixo | Confirmacao de envio processada no backend |
| SF14 | Backend | Co-signatarios | Cima | Aviso aos co-signatarios de aceite pendente |
| SF15 | Co-signatarios | Backend | Baixo | Decisao do co-signatario processada pelo backend |
| SF25 | Backend | AnalistaCBM | Baixo | Recurso disponivel na fila do analista |
| SF28 | AnalistaCBM | Backend | Cima | Resultado da analise processado pelo backend |

O **loop-back** `SF16_pendente` (de `GW_TodosAceitaram` de volta para `Task_CoSignatarioDecide`) usa o waypoint `(2440, 435) → (2440, 270) → (2345, 270)` para subir verticalmente da raia do Backend ate a raia dos Co-signatarios antes de retornar ao task. Esta rota foi escolhida em vez de uma rota que passasse pela raia do Solicitante (acima) porque manter o loop dentro das duas raias envolvidas na fase de aceites e mais legivel — o leitor do diagrama ve imediatamente que o loop e exclusivo entre co-signatarios e backend, sem envolvimento do solicitante.

Os **boundary events** e seus fluxos descendentes (SF20_Recusa para `Task_SistemaRegistraRecusa` e SF21_Cancelamento para `Task_CancelarRecurso`) foram posicionados na area inferior da raia do Backend (`y≈490-540`), abaixo do fluxo principal horizontal (`y≈420-470`). Essa disposicao verticalmente escalonada evita que as setas de excecao se sobreponham ao fluxo principal e permite ao leitor identificar rapidamente que sao caminhos alternativos, nao parte da sequencia normal.

---

## 13. Maquina de Estados, Marcos e Rastreabilidade de Auditoria

### Maquina de Estados de CBM_RECURSO (TP_SITUACAO)

```
RASCUNHO ('R')
  ├── enviar() ──────────────────────────> AGUARDANDO_APROVACAO_ENVOLVIDOS ('E')
  │                                         ├── efetuarRecusas() ─────────────> RASCUNHO ('R')  [loop]
  │                                         ├── cancelarRecurso() ────────────> CANCELADO ('CA')
  │                                         └── unanimidade aceites ──────────> AGUARDANDO_DISTRIBUICAO ('D')
  └── cancelarRecurso() ─────────────────> CANCELADO ('CA')

AGUARDANDO_DISTRIBUICAO ('D')
  └── distribuir() ──────────────────────> EM_ANALISE ('A')

EM_ANALISE ('A')
  └── concluirAnalise() ─────────────────> ANALISE_CONCLUIDA ('C')

CANCELADO ('CA')                           [terminal]
ANALISE_CONCLUIDA ('C')                    [terminal — resultado em TP_STATUS]
```

### Maquina de Estados de CBM_ANALISE_RECURSO (TP_STATUS)

```
EM_ANALISE
  ├── (2a instancia) ─────────────────────> AGUARDANDO_AVALIACAO_COLEGIADO
  │                                           └── retorno do colegiado ────────> EM_ANALISE
  └── concluirAnalise() ─────────────────> ANALISE_CONCLUIDA
```

### Marcos registrados em CBM_RECURSO_MARCO

| Momento | TipoMarco | Visibilidade | Responsavel |
|---|---|---|---|
| Envio para aceites | `ACEITE_RECURSO_ANALISE` | INTERNO | RecursoRN.enviar() |
| Co-signatario recusa | `RECURSO_RECUSADO` | INTERNO | RecursoRN.recusar() |
| Solicitante habilita edicao | `RECURSO_EDITADO` | INTERNO | RecursoRN.habilitarEdicao() |
| Cancelamento pelo solicitante | `RECURSO_CANCELADO` | INTERNO | RecursoRN.cancelarRecurso() |
| Cancelamento CIA | `CANCELAMENTO_RECURSO_CIA` | EXTERNO | RecursoRN.cancelarRecurso() |
| Cancelamento CIV | `CANCELAMENTO_RECURSO_CIV` | EXTERNO | RecursoRN.cancelarRecurso() |
| Unanimidade de aceites | `FIM_ACEITES_RECURSO_ANALISE` | INTERNO | RecursoRN.enviarParaAnalise() |
| Envio para analise CBM | `ENVIO_RECURSO_ANALISE` | EXTERNO | RecursoRN.enviarParaAnalise() |

A persistencia dos marcos usa `@Enumerated(EnumType.ORDINAL)` para o campo `COD_TP_MARCO` em `RecursoMarcoED` — o valor numerico do enum e gravado no Oracle, nao o nome. `TipoVisibilidade` segue o mesmo padrao ordinal. Isso significa que a ordem das declaracoes nos enums Java e significativa e imutavel: renomear ou reordenar os valores quebraria a consistencia com os dados historicos.

### Rastreabilidade de Auditoria

Cada operacao de negocio em `RecursoRN` recebe o `idUsuarioSoe` do ator responsavel e o propaga para as colunas de auditoria das entidades afetadas (`NRO_INT_USUARIO_SOE` em `CBM_RECURSO`, `CBM_ANALISE_RECURSO`, `CBM_RECURSO_MARCO`). O `idUsuarioSoe` e do tipo `Long` e corresponde ao identificador do usuario no SOE PROCERGS — sistema estadual de autenticacao. A resolucao do nome do usuario para exibicao (`ultimaAnalisePor` em `RecursoResponseDTO`) e feita em tempo de consulta via chamada ao SOE, nao por desnormalizacao no banco.

---

## 14. Seguranca e Controle de Acesso

### Autenticacao via SOE PROCERGS

Todos os endpoints do processo P10 — tanto cidadao (`/recursos`) quanto admin (`/adm/recursos`, `/adm/recurso-analise`) — exigem token JWT valido emitido pelo SOE PROCERGS (meu.rs.gov.br). O token e enviado como Bearer no cabecalho `Authorization` de cada requisicao HTTP. O backend WildFly valida a assinatura e a expiracao do token antes de executar qualquer logica de negocio.

### Segregacao de Endpoints por Perfil

O sistema SOL implementa segregacao de acesso por prefixo de rota:

| Prefixo | Ator | Operacoes |
|---|---|---|
| `/recursos` | Cidadao (RT, RU, Proprietario) | Criar, editar, enviar, aceitar, recusar, cancelar recurso |
| `/adm/recursos` | Analista CBM-RS | Listar fila, distribuir, consultar |
| `/adm/recurso-analise` | Analista CBM-RS | Salvar despacho, concluir analise, registrar ciencia |

A separacao de raias no BPMN entre "Solicitante", "Co-signatarios", "Sistema Backend" e "Analista CBM" reflete diretamente essa segregacao de endpoints — cada raia humana corresponde a um conjunto de endpoints com autorizacao diferente.

### Validacao de Identidade nas Operacoes Criticas

O campo `idUsuarioSoe` extraido do token JWT e comparado com os envolvidos do licenciamento (RN-080) antes que qualquer operacao de aceite ou recusa seja processada. Um co-signatario nao pode aceitar nem recusar um recurso do qual nao e co-signatario, mesmo que possua um token JWT valido. O backend verifica:
```sql
SELECT COUNT(*) FROM tabela_aceites
WHERE NRO_INT_RECURSO = ? AND NRO_INT_USUARIO_SOE = :idUsuarioJwt
```
antes de processar qualquer alteracao de aceite.

### Protecao contra Bloqueio Definitivo

O campo `IND_RECURSO_BLOQUEADO` (RN-089) e uma protecao de seguranca de dados alem de uma regra de negocio: uma vez que um recurso de 2a instancia e indeferido, o sistema garante que nenhuma API — nem mesmo endpoints administrativos — pode criar um novo recurso para aquele licenciamento sem que o `IND_RECURSO_BLOQUEADO` seja verificado primeiro (RN-082). Isso impede que erros de programacao ou chamadas API manuais por administradores contornem inadvertidamente a decisao definitiva do CBMRS.
