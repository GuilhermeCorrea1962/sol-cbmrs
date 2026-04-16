# Descritivo do Fluxo BPMN — P09 Troca de Envolvidos (Stack Atual Java EE)

**Arquivo BPMN:** `P09_TrocaEnvolvidos_StackAtual.bpmn`
**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Stack:** Java EE · JAX-RS · CDI · JPA/Hibernate · EJB `@Stateless` · SOE PROCERGS · Alfresco ECM · Oracle

---

## Sumario

1. [Visao Geral do Processo](#1-visao-geral-do-processo)
2. [Estrutura do Pool, Raias e Justificativa de Modelagem](#2-estrutura-do-pool-raias-e-justificativa-de-modelagem)
3. [Fase 1 — Consulta e Preenchimento da Solicitacao](#3-fase-1--consulta-e-preenchimento-da-solicitacao)
   - 3.1 [Evento de Inicio e Contexto de Entrada](#31-evento-de-inicio-e-contexto-de-entrada)
   - 3.2 [Pesquisa do Licenciamento e Consulta de Pre-condicoes](#32-pesquisa-do-licenciamento-e-consulta-de-pre-condicoes)
   - 3.3 [Verificacao de Pre-condicoes no Backend (RN02 / RN03)](#33-verificacao-de-pre-condicoes-no-backend-rn02--rn03)
   - 3.4 [Gateway: Pode Iniciar Troca?](#34-gateway-pode-iniciar-troca)
   - 3.5 [Evento de Fim de Erro: Licenciamento Bloqueado](#35-evento-de-fim-de-erro-licenciamento-bloqueado)
   - 3.6 [Preenchimento do Formulario de Solicitacao](#36-preenchimento-do-formulario-de-solicitacao)
   - 3.7 [Validacao de Regras de Negocio (RN01 a RN05)](#37-validacao-de-regras-de-negocio-rn01-a-rn05)
   - 3.8 [Gateway: Dados Validos?](#38-gateway-dados-validos)
   - 3.9 [Evento de Fim de Erro: Erro de Validacao](#39-evento-de-fim-de-erro-erro-de-validacao)
   - 3.10 [Upload dos Arquivos do Novo RT ao Alfresco ECM](#310-upload-dos-arquivos-do-novo-rt-ao-alfresco-ecm)
   - 3.11 [Persistencia da TrocaEnvolvidoED e Registros Filhos](#311-persistencia-da-trocaenvolvidoed-e-registros-filhos)
   - 3.12 [Criacao dos Registros de Autorizacao por Proprietario (RN06)](#312-criacao-dos-registros-de-autorizacao-por-proprietario-rn06)
   - 3.13 [Marco SOLICITA_TROCA_ENVOLVIDO](#313-marco-solicita_troca_envolvido)
   - 3.14 [Notificacao dos Proprietarios](#314-notificacao-dos-proprietarios)
4. [Fase 2 — Autorizacao pelos Proprietarios](#4-fase-2--autorizacao-pelos-proprietarios)
   - 4.1 [Tarefa de Consulta do Proprietario](#41-tarefa-de-consulta-do-proprietario)
   - 4.2 [Tarefa de Decisao do Proprietario](#42-tarefa-de-decisao-do-proprietario)
   - 4.3 [Gateway: Proprietario Autorizou?](#43-gateway-proprietario-autorizou)
   - 4.4 [Gravacao da Autorizacao (IND_AUTORIZADO=S)](#44-gravacao-da-autorizacao-ind_autorizados)
   - 4.5 [Marco APROVA_TROCA_ENVOLVIDO](#45-marco-aprova_troca_envolvido)
   - 4.6 [Gateway: Todos os Proprietarios Autorizaram?](#46-gateway-todos-os-proprietarios-autorizaram)
   - 4.7 [Rejeicao pelo Proprietario](#47-rejeicao-pelo-proprietario)
5. [Eventos de Boundary: Cancelamento e Reforco de Notificacao](#5-eventos-de-boundary-cancelamento-e-reforco-de-notificacao)
   - 5.1 [BoundaryEvent Interrompente: Cancelamento da Troca](#51-boundaryevent-interrompente-cancelamento-da-troca)
   - 5.2 [BoundaryEvent Nao-Interrompente: Reforco de Notificacao](#52-boundaryevent-nao-interrompente-reforco-de-notificacao)
6. [Fase 3 — Efetivacao da Troca](#6-fase-3--efetivacao-da-troca)
   - 6.1 [Estrutura da Efetivacao: Tres Gateways Condicionais em Serie](#61-estrutura-da-efetivacao-tres-gateways-condicionais-em-serie)
   - 6.2 [Processamento da Troca de RT (Matriz 31 Combinacoes)](#62-processamento-da-troca-de-rt-matriz-31-combinacoes)
   - 6.3 [Processamento da Troca de RU](#63-processamento-da-troca-de-ru)
   - 6.4 [Processamento da Troca de Proprietarios](#64-processamento-da-troca-de-proprietarios)
   - 6.5 [Finalizacao da Aprovacao e Evento de Fim APROVADO](#65-finalizacao-da-aprovacao-e-evento-de-fim-aprovado)
7. [Fluxos Cross-Lane e Decisoes de Roteamento Visual](#7-fluxos-cross-lane-e-decisoes-de-roteamento-visual)
8. [Maquina de Estados, Marcos e Rastreabilidade de Auditoria](#8-maquina-de-estados-marcos-e-rastreabilidade-de-auditoria)
9. [Seguranca e Controle de Acesso](#9-seguranca-e-controle-de-acesso)

---

## 1. Visao Geral do Processo

O processo P09 — Troca de Envolvidos — permite que um licenciamento ativo no sistema SOL tenha os seus atores vinculados substituidos sem que seja necessario cancelar e abrir um novo licenciamento. Os "envolvidos" de um licenciamento sao tres categorias de pessoas:

- **RT (Responsavel Tecnico):** o engenheiro ou arquiteto credenciado no CBMRS que assina tecnica e juridicamente o projeto de prevencao contra incendio.
- **RU (Responsavel pelo Uso):** o responsavel operacional pelo estabelecimento ou edificacao.
- **Proprietarios:** os detentores juridicos do imovel, cujas identidades sao registradas no licenciamento para fins de responsabilizacao.

A necessidade de troca surge por varios motivos praticos: o RT pode encerrar sua relacao com o cliente, o RU pode mudar, ou a propriedade pode ser vendida ou inventariada. Sem o processo P09, qualquer mudanca de envolvido exigiria a reativacao do processo completo, o que acarretaria custos e prazos desnecessarios.

### Estrutura em tres fases

O processo se organiza em tres fases sequenciais e logicamente dependentes:

| Fase | Descricao | Ator Principal |
|---|---|---|
| 1 — Solicitacao | Solicitante preenche e submete os dados da troca desejada | RT, RU ou Proprietario |
| 2 — Autorizacao | Cada proprietario vinculado ao licenciamento aprova ou rejeita a troca | Proprietarios |
| 3 — Efetivacao | O sistema atualiza os registros do licenciamento conforme os novos dados | Sistema SOL Backend |

A dependencia entre as fases e obrigatoria: a Fase 2 so inicia apos a conclusao da Fase 1, e a Fase 3 so inicia apos a conclusao unanime da Fase 2. Qualquer proprietario que rejeite a troca encerra o processo sem efetivacao. O solicitante pode cancelar a qualquer momento durante a Fase 2.

### Por que a autorizacao dos proprietarios e obrigatoria?

A exigencia da autorizacao de todos os proprietarios antes da efetivacao decorre de principios de responsabilidade juridica: a substituicao de um RT ou de um RU altera quem responde tecnicamente pelo projeto perante o CBMRS e, potencialmente, perante o Ministerio Publico em caso de incidentes. A autorizacao coletiva dos proprietarios garante que nenhum envolvido seja substituido de forma unilateral, protegendo os interesses de todos os titulares do imovel.

---

## 2. Estrutura do Pool, Raias e Justificativa de Modelagem

### Decisao de usar um unico Pool com tres Raias

Diferentemente do P08 — que foi modelado com dois Pools independentes porque representa dois sub-processos com entradas de estado distintas —, o P09 e modelado como **um unico Pool** com tres raias horizontais. A razao e que o P09 e um unico fluxo continuo, com um unico evento de inicio, sem bifurcacoes de entrada baseadas em estado anterior. O processo sempre percorre as tres fases na mesma ordem para qualquer tipo de troca (RT, RU ou Proprietario).

### Raia 1: Solicitante (RT / RU / Proprietario)

Posicionada no topo (y=60 a y=190 no diagrama), esta raia contem exclusivamente os `UserTask` relacionados ao solicitante: a pesquisa do licenciamento e o preenchimento do formulario de solicitacao. O solicitante pode ser qualquer dos tres tipos de envolvido, o que justifica o nome composto da raia. Essa flexibilidade e proposital: o sistema SOL nao restringe quem pode iniciar o pedido de troca, desde que o usuario esteja autenticado via SOE PROCERGS e vinculado ao licenciamento.

### Raia 2: Proprietarios (Autorizadores)

Posicionada no meio (y=190 a y=320), esta raia contem as duas `UserTask` da fase de autorizacao e o gateway de decisao que representa a escolha do proprietario. A separacao dos proprietarios em raia propria e uma decisao de modelagem importante: deixa claro que a autorizacao e uma responsabilidade de um ator diferente do solicitante, com acesso e momento de interacao distintos. O solicitante nao autoriza a si mesmo.

Tambem e nesta raia que os dois `BoundaryEvent` sao anotados graficamente, pois ambos estao "grudados" na `UserTask` de decisao do proprietario, que pertence a esta raia.

### Raia 3: Sistema SOL Backend

Posicionada na base (y=320 a y=740), esta raia e a mais larga e contem o maior numero de elementos. Toda a logica de validacao, persistencia, controle de estado e processamento condicionado esta aqui como `ServiceTask`. Cada `ServiceTask` contem o atributo `camunda:class` apontando para o EJB `@Stateless` real que implementa a operacao, o que torna o diagrama diretamente rastreavel ao codigo-fonte.

A altura de 420px para esta raia (contra 130px para cada uma das outras) nao e arbitraria: a Fase 3 de efetivacao precisa acomodar tres triplas de gateways + tasks + gateways de convergencia dispostos horizontalmente, alem dos subnos de rejeicao e cancelamento dispostos verticalmente no setor inferior da raia.

### Dimensoes do Pool

O pool tem largura de 3790px, substancialmente maior que os processos P07 (3100px) e P08 (2700px). Essa largura e necessaria porque a Fase 3 adiciona seis gateways extras e tres tasks de processamento condicional — todos em sequencia horizontal — que nao tinham correspondente nos processos anteriores.

---

## 3. Fase 1 — Consulta e Preenchimento da Solicitacao

### 3.1 Evento de Inicio e Contexto de Entrada

O evento de inicio **`StartEvent_P09`** ("Solicitante acessa modulo de Troca de Envolvidos") esta posicionado na raia do Solicitante, no extremo esquerdo do pool. Seu posicionamento reflete que a iniciativa parte sempre de um usuario externo — nenhum processo interno do CBMRS aciona automaticamente uma troca de envolvidos. O sistema e reativo: ele responde a uma solicitacao humana.

O evento de inicio e do tipo "None" (circulo simples sem marcador), o que indica que o processo e ativado por acesso direto do usuario ao modulo, sem mensagem de correlacao nem temporizador. Isso e correto porque o P09 nao e ativado por nenhum outro processo SOL: ele e autossuficiente e pode ser iniciado a qualquer momento por qualquer envolvido com permissao de acesso ao licenciamento.

**Contexto de entrada:** o solicitante acessa o frontend Angular pelo caminho `/licenciamentos/{idLic}/troca-envolvidos/nova`. O token JWT emitido pelo SOE PROCERGS ja contem o CPF do usuario, que sera usado em todas as verificacoes de identidade subsequentes.

### 3.2 Pesquisa do Licenciamento e Consulta de Pre-condicoes

A primeira `UserTask`, **`Task_BuscarLicenciamento`** ("Pesquisar licenciamento e consultar envolvidos atuais"), representa a tela inicial do modulo de troca. Nela o solicitante seleciona ou informa o numero do licenciamento para o qual deseja solicitar a troca e visualiza o estado atual dos envolvidos.

O endpoint chamado e:
```
GET /licenciamentos/{idLic}/troca-envolvidos
```
implementado por `LicenciamentoTrocaEnvolvidoRest.listar()`. A resposta exibe os dados do RT atual (nome, CPF, tipo de responsabilidade), do RU atual e da lista de proprietarios. Essa etapa e essencial para que o solicitante entenda o que esta mudando — o formulario de troca e contextual aos dados exibidos aqui.

**Por que separar a consulta do preenchimento em dois UserTasks?** Porque sao interacoes distintas com objetivos diferentes. O primeiro serve para o usuario confirmar que encontrou o licenciamento correto e entender o estado atual antes de tomar qualquer decisao. O segundo e onde a acao de mudanca de fato ocorre. Fundir os dois em um unico formulario tornaria a interface confusa e aumentaria o risco de alteracoes acidentais.

O fluxo de saida desta task (SF2) cruza de raia — vai da raia do Solicitante para a raia do Backend — porque a acao subsequente e automatica: o sistema valida se o licenciamento pode de fato receber uma troca antes de exibir o formulario.

### 3.3 Verificacao de Pre-condicoes no Backend (RN02 / RN03)

A `ServiceTask` **`Task_ConsultaLicenciamento`** ("Consultar licenciamento e verificar pre-condicoes") e executada pelo EJB `ConsultaTrocaEnvolvidoLicenciamentoRN`. Esta tarefa faz duas verificacoes criticas antes de qualquer interacao com o usuario:

**RN02 — Situacao do licenciamento permite troca?**
Consulta `CBM_LICENCIAMENTO.SIT_LICENCIAMENTO` e verifica se o valor e um dos estados em que a troca de envolvidos e permitida pelo CBMRS. Nao seria aceitavel, por exemplo, iniciar uma troca enquanto o licenciamento esta em `AGUARDANDO_PAGAMENTO` ou `CANCELADO`.

**RN03 — Nao existe troca ja em andamento?**
```sql
SELECT COUNT(*) FROM CBM_TROCA_ENVOLVIDO
WHERE ID_LICENCIAMENTO = ? AND SIT_TROCA = 'SOLICITADO'
```
Se retornar valor maior que zero, ja existe uma solicitacao pendente de autorizacao para este licenciamento. Permitir uma segunda troca simultanea criaria conflito de dados: dois conjuntos de novos envolvidos concorrentes, duas filas de autorizacao paralelas. O sistema bloqueia isso preventivamente.

**Por que o backend valida em vez de confiar na interface?** Porque o frontend Angular exibe o botao "Solicitar troca" com base no estado visivel na tela, mas o estado pode ter mudado enquanto o usuario navegava. Um segundo usuario pode ter submetido uma troca entre o momento em que o primeiro usuario abriu a pagina e o momento em que clicou em "Continuar". A validacao no backend e a unica fonte confiavel de verdade.

O fluxo de saida (SF3) e direto para o gateway de pre-condicao, sem retorno a raia do Solicitante — o usuario nao participa desta etapa.

### 3.4 Gateway: Pode Iniciar Troca?

O gateway exclusivo **`GW_PodeIniciar`** ("Pode iniciar troca?") bifurca o fluxo com base no resultado das validacoes RN02 e RN03. A modelagem como gateway exclusivo e correta: ou o licenciamento esta liberado, ou nao esta. Nao ha estado intermediario.

- **Sim (SF5_liberado):** o fluxo sobe de volta a raia do Solicitante (cross-lane UP) para o formulario de preenchimento. O waypoint explicito `(690, 505) → (690, 125) → (760, 125)` faz a seta subir verticalmente dentro da coluna X=690, cruzar para a esquerda da raia do Solicitante e entrar no formulario pela esquerda, evitando sobrepor a seta sobre outros elementos.

- **Nao (SF4_bloqueado):** o fluxo desce dentro da propria raia do Backend para o evento de fim de erro.

### 3.5 Evento de Fim de Erro: Licenciamento Bloqueado

O **`EndEvent_LicBloqueado`** ("Licenciamento bloqueado — troca nao permitida") encerra o processo com um `ErrorEventDefinition`, codigo `LICENCIAMENTO_BLOQUEADO`. A escolha de um evento de fim de erro, e nao de um evento de fim simples, e intencional: distingue visualmente que o processo terminou por violacao de regra de negocio, nao por conclusao normal. No codigo, a excecao `SolNegocioException` correspondente e capturada pelo `ExceptionMapper` JAX-RS, que converte em HTTP 422 com mensagem descritiva.

O evento esta posicionado abaixo do gateway (y=652), fora da linha principal de fluxo (y=530), para nao criar congestionamento visual na raia do Backend.

### 3.6 Preenchimento do Formulario de Solicitacao

A `UserTask` **`Task_PreencherSolicitacao`** ("Preencher dados da solicitacao de troca") e o coração da interacao do solicitante com o sistema. O `camunda:formKey="troca-envolvidos/nova"` identifica o formulario Angular que sera renderizado.

O formulario permite informar, de forma independente, qualquer combinacao dos tres tipos de envolvido:

**Para o novo RT:** o solicitante informa o CPF e o tipo de responsabilidade tecnica. O frontend realiza uma chamada sincrona de verificacao:
```
GET /troca-envolvidos/cpf/{cpf}/responsabilidade/{tipo}
```
que confirma se o CPF informado esta cadastrado no sistema com o status APROVADO. Essa verificacao em tempo real no formulario da feedback imediato ao usuario, antes mesmo da submissao — uma pratica de UX que evita erros comuns. Alem disso, o formulario permite fazer upload dos arquivos do novo RT (ART ou RRT), que sao documentos obrigatorios para habilitacao tecnica.

**Para o novo RU:** apenas o CPF do responsavel pelo uso.

**Para os novos proprietarios:** lista de CPFs dos proprietarios que substituirao ou complementarao os atuais.

As regras de negocio RN01 (pelo menos um envolvido alterado), RN04 (novo RT com status APROVADO) e RN05 (novo RT diferente do atual) sao exibidas como mensagens de validacao no formulario mas serao revalidadas no backend antes da persistencia — principio de defesa em profundidade.

O fluxo de saida (SF6) cruza de raia para baixo ao ser submetido, indo da raia do Solicitante para a raia do Backend, representando a chamada HTTP `POST /licenciamentos/{idLic}/troca-envolvidos` que carrega todos os dados do formulario.

### 3.7 Validacao de Regras de Negocio (RN01 a RN05)

A `ServiceTask` **`Task_ValidarSolicitacao`** ("Validar regras de negocio da solicitacao") invoca a classe `SolicitaTrocaEnvolvidoLicenciamentoRN` em sua fase de validacao. Esta e a ultima barreira antes de qualquer escrita no banco de dados. As cinco regras sao aplicadas em sequencia:

| Regra | Verificacao | Motivo |
|---|---|---|
| RN01 | Pelo menos um dos campos (novo RT, novo RU, novos proprietarios) foi preenchido | Impede submissoes vazias que nao mudariam nada no licenciamento |
| RN02 | `CBM_LICENCIAMENTO.SIT_LICENCIAMENTO` ainda esta em estado permitido | Revalida porque o estado pode ter mudado desde a consulta inicial |
| RN03 | Nao existe `CBM_TROCA_ENVOLVIDO.SIT_TROCA='SOLICITADO'` para o licenciamento | Revalida pela mesma razao — condição de corrida possivel |
| RN04 | Novo RT tem `StatusCadastro=APROVADO` (valor 3 em `CBM_STATUS_CADASTRO`) | RT nao aprovado nao pode assumir responsabilidade tecnica |
| RN05 | CPF do novo RT e diferente do CPF do RT atual em `CBM_RESPONSAVEL_TECNICO_LICEN` | Trocar um RT por ele mesmo e uma operacao invalida e sem sentido |

A revalidacao de RN02 e RN03 no backend, mesmo tendo sido verificadas em `Task_ConsultaLicenciamento`, e necessaria porque entre a consulta e a submissao do formulario pode ter ocorrido uma mudanca de estado por outro processo concorrente.

### 3.8 Gateway: Dados Validos?

O gateway exclusivo **`GW_ValidacaoOk`** ("Dados validos? RN01-RN05") apresenta duas saidas:

- **Nao (SF8_invalido):** desce para o evento de fim de erro. Nao ha loop-back para o formulario, ao contrario do que ocorre no P08. Essa e uma decisao de modelagem deliberada: falhas nas validacoes de RN02/RN03 indicam conflito de estado, nao erro de preenchimento — o usuario deve reiniciar o fluxo com informacoes atualizadas. Falhas em RN01/RN04/RN05 retornam mensagens de erro via HTTP 422, e o frontend Angular, ao receber o erro, mantem o formulario aberto com as mensagens correspondentes (comportamento implementado no frontend, nao no BPMN).

- **Sim (SF9_valido):** prossegue para o upload dos arquivos no Alfresco.

### 3.9 Evento de Fim de Erro: Erro de Validacao

O **`EndEvent_ErroValidacao`** ("Erro de validacao — retorno ao formulario") encerra com `ErrorEventDefinition`, codigo `ERRO_VALIDACAO_SOLICITACAO`. Semanticamente, este evento sinaliza que o processo BPMN foi encerrado por violacao de regra, mas a perspectiva do usuario e diferente: o formulario permanece visivel no frontend com os erros destacados. O BPMN representa o ciclo de vida do processo no servidor, nao a experiencia completa de navegacao do usuario.

### 3.10 Upload dos Arquivos do Novo RT ao Alfresco ECM

A `ServiceTask` **`Task_UploadAlfresco`** ("Enviar arquivos do novo RT ao Alfresco ECM") invoca `ArquivoRN.incluir()`. Esta e a primeira operacao de escrita em dado duravel do processo, e ela acontece **antes** da criacao dos registros relacionais de troca. A sequencia e intencional:

1. Gravar o arquivo no Alfresco primeiro garante que o `nodeRef` esteja disponivel antes de criar o `TrocaRTED` que vai referencia-lo.
2. Se o upload ao Alfresco falhar (por timeout, indisponibilidade do ECM ou arquivo invalido), nenhum dado fica gravado no Oracle em estado inconsistente — a transacao JPA ainda nao foi iniciada.

O `nodeRef` retornado pelo Alfresco tem o formato `workspace://SpacesStore/{UUID}` e e gravado no campo `CBM_ARQUIVO.IDENTIFICADOR_ALFRESCO` (maximo 150 caracteres, `@NotNull`). O binario nunca entra no banco Oracle — apenas o ponteiro logico para o repositorio de documentos.

O `TipoArquivo.EDIFICACAO` determina que o arquivo sera organizado no Alfresco sob a hierarquia `grp:familia=Documentos de Edificacao`, consistentemente com todos os outros documentos do licenciamento.

### 3.11 Persistencia da TrocaEnvolvidoED e Registros Filhos

A `ServiceTask` **`Task_CriarTroca`** ("Persistir TrocaEnvolvidoED + filhos") e a principal operacao de escrita do processo. O EJB `SolicitaTrocaEnvolvidoLicenciamentoRN` executa um conjunto de inserts encadeados dentro de uma unica transacao JPA:

```
INSERT CBM_TROCA_ENVOLVIDO
  (ID, ID_LICENCIAMENTO, SIT_TROCA='SOLICITADO', DTH_SOLICITACAO, CPF_SOLICITANTE)

Se RT informado:
  INSERT CBM_TROCA_RT (ID, ID_TROCA_ENVOLVIDO, CPF_RT, TIPO_RESPONSABILIDADE)

Se RU informado:
  INSERT CBM_TROCA_RU (ID, ID_TROCA_ENVOLVIDO, CPF_RU)

Para cada proprietario informado:
  INSERT CBM_TROCA_PROPRIETARIO (ID, ID_TROCA_ENVOLVIDO, CPF_PROPRIETARIO)
```

O registro principal `TrocaEnvolvidoED` e anotado com `@Audited` (Hibernate Envers), o que significa que toda mudanca de estado sera rastreada na tabela `CBM_TROCA_ENVOLVIDO_AUD`. O campo `SIT_TROCA` inicia em `SOLICITADO` — o primeiro valor da maquina de estados `SituacaoTrocaEnvolvido`.

**Por que criar registros filhos separados em vez de campos diretos na TrocaEnvolvidoED?** Porque a troca pode envolver qualquer combinacao de envolvidos: apenas RT, apenas proprietarios, RT e RU simultaneamente, etc. Campos opcionais na tabela principal criariam uma estrutura esparsa e dificulteriam as queries condicionais da Fase 3. As tabelas filhas permitem verificar a presenca de cada tipo de troca com um simples `COUNT(*)`.

### 3.12 Criacao dos Registros de Autorizacao por Proprietario (RN06)

A `ServiceTask` **`Task_CriarAutorizacoes`** ("Criar TrocaAutorizacaoED por proprietario") e uma tarefa separada, embora pertenca ao mesmo EJB que a anterior. A separacao no BPMN reflete a separacao logica e conceitual da operacao: enquanto `Task_CriarTroca` registra *o que vai mudar*, `Task_CriarAutorizacoes` inicia *o processo de aprovacao dessa mudanca*.

**RN06 — Logica de autorizacao coletiva:**

Para cada `LicenciamentoProprietarioED` vinculado ao licenciamento, o sistema cria um registro:
```sql
INSERT CBM_TROCA_AUTORIZACAO
  (ID, ID_TROCA_ENVOLVIDO, ID_PROPRIETARIO, IND_AUTORIZADO=NULL)
```

O campo `IND_AUTORIZADO` comeca com valor `NULL`, que representa "pendente de resposta". O `SimNaoBooleanConverter` do sistema mapeia os tres estados possiveis: `NULL` (pendente), `'S'` (autorizado) e `'N'` (rejeitado).

A efetivacao da troca somente e permitida quando **todos** os registros de autorizacao tiverem `IND_AUTORIZADO='S'`. Um unico registro com `'N'` encerra o processo como reprovado. Essa regra de unanimidade e o que justifica o loop-back da Fase 2.

**Por que unanimidade em vez de maioria?** A troca de envolvidos tem implicacoes juridicas para cada proprietario individualmente. Um proprietario dissidente pode ter razoes legitimas para nao concordar com a substituicao do RT, por exemplo. A regra de unanimidade protege o direito de veto de cada titular.

### 3.13 Marco SOLICITA_TROCA_ENVOLVIDO

A `ServiceTask` **`Task_MarcoSolicita`** ("Registrar marco SOLICITA_TROCA_ENVOLVIDO") invoca `LicenciamentoMarcoInclusaoRN` para gravar o primeiro registro no historico de marcos do licenciamento:

```sql
INSERT CBM_LICENCIAMENTO_MARCO
  (ID, ID_LICENCIAMENTO, TIPO_MARCO='SOLICITA_TROCA_ENVOLVIDO', DTH_MARCO, CPF_USUARIO)
```

**Por que registrar um marco aqui?** Os marcos do licenciamento formam o diario oficial do processo para fins de auditoria, relatorios gerenciais e eventual contestacao administrativa. O marco `SOLICITA_TROCA_ENVOLVIDO` registra com precisao o momento em que a solicitacao foi submetida, quem a submeteu e a data/hora exata. Isso e especialmente importante porque a solicitacao de troca tem consequencias no prazo de validade do licenciamento e pode ser objeto de recurso.

### 3.14 Notificacao dos Proprietarios

A `ServiceTask` **`Task_NotificarProprietarios`** ("Notificar cada proprietario para autorizar a troca") invoca `NotificaTrocaEnvolvidoRN.notificaEnvolvidos()`. O metodo consulta todos os registros criados em `CBM_TROCA_AUTORIZACAO` e, para cada proprietario com `IND_AUTORIZADO IS NULL`, envia:

- Uma notificacao interna no sistema SOL (registrada em `CBM_NOTIFICACAO`).
- Um e-mail com link direto para a tela de autorizacao: `GET /licenciamentos/{idLic}/troca-envolvidos/{id}/autorizacao`.

O fluxo de saida (SF14) cruza de raia para cima, passando do Backend para a raia dos Proprietarios. Os waypoints `(1915,530) → (1940,530) → (1940,255) → (1960,255)` deslocam a seta para a direita antes de subir, evitando sobrepor a linha sobre a borda vertical do pool da fase anterior.

---

## 4. Fase 2 — Autorizacao pelos Proprietarios

### 4.1 Tarefa de Consulta do Proprietario

A `UserTask` **`Task_ProprietarioConsulta`** ("Consultar detalhes da solicitacao de troca") e a primeira interacao da Fase 2 e e o no mais complexo em termos de conectividade do diagrama: recebe tres fluxos de entrada diferentes:

| Fluxo | Origem | Ocorrencia |
|---|---|---|
| SF14 | `Task_NotificarProprietarios` | Primeira vez que um proprietario acessa |
| SF21_loop | `GW_TodosAutorizaram` | Cada vez que um proprietario autorizou e ainda ha pendentes |
| SF40 | `Task_ReforcarNotificacao` | Apos o solicitante ter reenviado notificacoes |

Esta multiplicidade de entradas e uma consequencia da logica de autorizacao sequencial adotada: o BPMN modela o ciclo de autorizacao como uma sequencia de visitas individuais de proprietarios, com loop-back apos cada autorizacao bem-sucedida. Na pratica, proprietarios distintos podem responder em ordens e momentos diferentes, mas o BPMN abstrai essa concorrencia em um fluxo linear para fins de documentacao.

Os endpoints consultados sao:
```
GET /licenciamentos/{idLic}/troca-envolvidos/{id}/autorizacao
GET /licenciamentos/{idLic}/troca-envolvidos/{id}/autorizacao/arquivos
```
O primeiro retorna os dados estruturados da troca (envolvidos atuais e propostos). O segundo permite download dos arquivos do novo RT armazenados no Alfresco, para que o proprietario possa avaliar as credenciais tecnicas do novo responsavel antes de decidir.

### 4.2 Tarefa de Decisao do Proprietario

A `UserTask` **`Task_ProprietarioDecide`** ("Autorizar ou rejeitar a troca de envolvidos") recebe a decisao efetiva do proprietario. E a task que suporta os dois `BoundaryEvent` — a escolha de anexar os eventos a esta task, e nao a de consulta, e deliberada: o cancelamento e o reforco de notificacao so fazem sentido enquanto o proprietario esta no momento de decisao, nao antes.

**RN07 — Verificacao de identidade do autorizador:**
O endpoint `PUT .../autorizar` verifica que o CPF do usuario logado corresponde a um `ID_PROPRIETARIO` em `CBM_TROCA_AUTORIZACAO` com `IND_AUTORIZADO IS NULL`. Um proprietario que ja respondeu nao pode mudar sua resposta, e um usuario nao-proprietario nao pode registrar autorizacao.

**RN08 — Unicidade de resposta:**
A verificacao de `IND_AUTORIZADO IS NULL` antes do UPDATE garante que a resposta so pode ser registrada uma vez. Tentativas de dupla autorizacao sao bloqueadas pelo backend com excecao de negocio.

### 4.3 Gateway: Proprietario Autorizou?

O gateway exclusivo **`GW_Resposta`** ("Proprietario autorizou?") esta posicionado na raia dos Proprietarios, imediatamente apos a task de decisao. Sua posicao na raia do ator que acabou de decidir e semanticamente correta: a bifurcacao e consequencia direta da escolha do proprietario.

- **Sim (SF17_sim):** desce cross-lane para `Task_GravarAutorizacaoS` na raia do Backend. Os waypoints `(2340,280) → (2340,530) → (2410,530)` fazem a seta descer verticalmente pela coluna X=2340, cruzar a fronteira de raias em y=320, e entrar na task pelo lado esquerdo.

- **Nao (SF18_nao):** sai pela direita do gateway `(2365,255)`, percorre horizontalmente ate x=2395, desce ate y=660 (nivel das tasks de rejeicao na parte inferior da raia do Backend), e conecta-se a `Task_GravarRejeicaoN`. Esse roteamento em "L invertido" e necessario para nao cruzar sobre as tasks da linha principal de autorizacao.

### 4.4 Gravacao da Autorizacao (IND_AUTORIZADO=S)

A `ServiceTask` **`Task_GravarAutorizacaoS`** ("Gravar autorizacao: IND_AUTORIZADO=S") invoca `AutorizacaoTrocaEnvolvidoRN.autoriza()`:

```sql
UPDATE CBM_TROCA_AUTORIZACAO
  SET IND_AUTORIZADO = 'S', DTH_AUTORIZACAO = SYSDATE
  WHERE ID_TROCA_ENVOLVIDO = ? AND ID_PROPRIETARIO = ?
```

O `SimNaoBooleanConverter` converte o `Boolean true` Java para a string `'S'` no Oracle. A gravacao da `DTH_AUTORIZACAO` junto com o status e importante para auditoria: o historico deve mostrar nao apenas que cada proprietario autorizou, mas exatamente quando.

### 4.5 Marco APROVA_TROCA_ENVOLVIDO

A `ServiceTask` **`Task_MarcoAprova`** registra o marco `APROVA_TROCA_ENVOLVIDO` por cada autorizacao individual recebida. A escolha de registrar este marco a cada autorizacao — e nao apenas uma vez apos a autorizacao unanime — e importante para rastreabilidade: o historico do licenciamento deve mostrar a ordem e o momento de cada autorizacao individual, especialmente quando ha multiplos proprietarios.

Este marco nao altera a `SIT_TROCA` na `TrocaEnvolvidoED` — ela permanece `SOLICITADO` enquanto nem todos autorizaram. A mudanca de estado para `APROVADO` so ocorre na Fase 3, apos a efetivacao completa.

### 4.6 Gateway: Todos os Proprietarios Autorizaram?

O gateway exclusivo **`GW_TodosAutorizaram`** ("Todos os proprietarios autorizaram?") e o elemento central da logica de loop da Fase 2. A consulta executada e:

```sql
SELECT COUNT(*) FROM CBM_TROCA_AUTORIZACAO
WHERE ID_TROCA_ENVOLVIDO = ?
  AND (IND_AUTORIZADO IS NULL OR IND_AUTORIZADO = 'N')
```

Se o resultado for zero, todos os registros tem `IND_AUTORIZADO='S'` e o fluxo avanca para a Fase 3.

Se for maior que zero, ainda ha proprietarios pendentes. O fluxo retorna (SF21_loop) a `Task_ProprietarioConsulta` via loop-back com os waypoints:
```
(2785, 505) → (2785, 155) → (2040, 155) → (2040, 215)
```
A seta sobe ate y=155, que e a area de "passagem" acima da raia do Solicitante (y=60 a y=190). Passar por y=155 significa que a seta fica dentro do espaco da raia do Solicitante mas acima de qualquer elemento, criando um caminho visual limpo de retorno. Em seguida desce ate y=215, que e o topo da raia dos Proprietarios onde a task de consulta esta localizada.

**Por que o loop-back passa pela raia do Solicitante?** Porque nao ha espaco acima do nivel y=155 sem cruzar a borda do pool. O waypoint y=155 e escolhido por estar dentro dos limites da raia do Solicitante (y=60 a y=190) mas acima de qualquer elemento dela (centro em y=125). E a unica rota que nao colide com elementos existentes.

### 4.7 Rejeicao pelo Proprietario

A `ServiceTask` **`Task_GravarRejeicaoN`** ("Gravar rejeicao, reprovar troca, registrar marco e notificar") executa quatro operacoes em uma unica transacao, representando o carater terminal e irreversivel da rejeicao:

1. **UPDATE autorizacao:** `IND_AUTORIZADO='N'`, `DTH_AUTORIZACAO=SYSDATE` em `CBM_TROCA_AUTORIZACAO`.
2. **UPDATE troca:** `SIT_TROCA='REPROVADO'`, `DTH_REPROVACAO=SYSDATE` em `CBM_TROCA_ENVOLVIDO`.
3. **INSERT marco:** `TIPO_MARCO='REPROVA_TROCA_ENVOLVIDO'` em `CBM_LICENCIAMENTO_MARCO`.
4. **INSERT notificacao:** e-mail e notificacao interna ao solicitante informando a reprovacao.

**Por que agrupar todas essas operacoes em uma unica ServiceTask?** Porque sao operacoes atomicas: nao faz sentido reprovar a troca sem notificar o solicitante, e nao faz sentido notificar sem ter reprovado primeiro. Se qualquer uma das operacoes falhar, a transacao JPA faz rollback de todas — o sistema nunca fica em estado parcialmente reprovado.

O evento de fim **`EndEvent_Reprovado`** ("Troca REPROVADA") e um evento de fim simples, nao de erro — a rejeicao e um desfecho valido e esperado do processo, nao uma excecao.

---

## 5. Eventos de Boundary: Cancelamento e Reforco de Notificacao

### 5.1 BoundaryEvent Interrompente: Cancelamento da Troca

O **`BoundaryEvent_Cancelamento`** e um evento de boundary de mensagem com `cancelActivity="true"`. Fica fixado na borda inferior-esquerda de `Task_ProprietarioDecide`. O atributo `cancelActivity="true"` significa que, ao ser ativado, ele interrompe imediatamente a task a qual esta vinculado e cancela qualquer token de processo que esteja dentro dela.

**RN10 — Apenas o solicitante original pode cancelar:**
A verificacao e `CBM_TROCA_ENVOLVIDO.CPF_SOLICITANTE == CPF do usuario logado`. Proprietarios, outros RTs ou outros usuarios nao podem cancelar em nome do solicitante.

**RN11 — So cancela enquanto SOLICITADO:**
O cancelamento e bloqueado se `SIT_TROCA != 'SOLICITADO'`, o que e um estado impossivel de ocorrer durante a Fase 2 mas e verificado por robustez.

O fluxo de saida (SF37) vai da borda inferior do evento de boundary `(2162,313)` diretamente para cima da task de cancelamento na raia do Backend: `(2162,313) → (2038,313) → (2038,600)`. A seta vai para a esquerda ate alinhar com o centro horizontal da task de cancelamento (x=2038) e desce ate o topo da task. A travessia da fronteira de raias (que ocorre em y=320) e cruzada verticalmente neste percurso.

A `ServiceTask` **`Task_GravarCancelamento`** executa:
```sql
UPDATE CBM_TROCA_ENVOLVIDO
  SET SIT_TROCA = 'CANCELADO', DTH_CANCELAMENTO = SYSDATE
  WHERE ID = ?
```
O evento de fim **`EndEvent_Cancelado`** ("Troca CANCELADA") encerra o processo. Nao ha marco de auditoria separado para o cancelamento — o campo `DTH_CANCELAMENTO` junto com `SIT_TROCA='CANCELADO'` ja e suficiente para o historico de auditoria do Hibernate Envers.

### 5.2 BoundaryEvent Nao-Interrompente: Reforco de Notificacao

O **`BoundaryEvent_ReforcoNotificacao`** e um evento de boundary de mensagem com `cancelActivity="false"`. Fica fixado na borda inferior-direita de `Task_ProprietarioDecide`, ao lado do evento de cancelamento. O atributo `cancelActivity="false"` e o que o torna "nao-interrompente": ao ser ativado, ele **nao** cancela a task principal — ela continua aguardando a decisao do proprietario enquanto o reforco e processado em paralelo.

Visualmente, a borda do simbolo do evento nao-interrompente e tracejada (em oposicao a borda solida do evento interrompente), sinalizando aos leitores do BPMN que o fluxo principal nao e interrompido.

**RN12 — Reenvio seletivo:**
O metodo `NotificaTrocaEnvolvidoRN.reforcarSolicitacao()` consulta apenas os registros com `IND_AUTORIZADO IS NULL`:
```sql
SELECT * FROM CBM_TROCA_AUTORIZACAO
WHERE ID_TROCA_ENVOLVIDO = ? AND IND_AUTORIZADO IS NULL
```
Proprietarios que ja responderam (S ou N) nao recebem reenvio — o reforco e direcionado apenas aos pendentes.

O fluxo de saida (SF39) vai de `(2259,313)` para `(2263,313)` (pequeno deslocamento horizontal) e desce para `(2263,600)`, chegando ao topo de `Task_ReforcarNotificacao`. Esta task processa o reenvio e, ao concluir, o fluxo (SF40) retorna a `Task_ProprietarioConsulta` via loop-back:
```
(2185, 640) → (1945, 640) → (1945, 255) → (1960, 255)
```
Este loop-back percorre horizontalmente pela parte inferior da raia do Backend, sobe ate o nivel y=255 (centro da raia dos Proprietarios) e conecta-se a task de consulta pela esquerda.

**Por que modelar o reforco como boundary nao-interrompente em vez de uma acao separada do solicitante?** Porque o reforco ocorre em paralelo ao estado de espera da decisao do proprietario — o processo nao "pausa" enquanto o reenvio acontece. A notificacao e um evento lateral que nao altera o fluxo principal. O boundary nao-interrompente e exatamente o mecanismo BPMN projetado para representar esse tipo de evento lateral.

---

## 6. Fase 3 — Efetivacao da Troca

### 6.1 Estrutura da Efetivacao: Tres Gateways Condicionais em Serie

A Fase 3 e a mais complexa em termos de estrutura BPMN. Apos a autorizacao unanime de todos os proprietarios, o sistema precisa atualizar os dados do licenciamento para cada tipo de envolvido que foi solicitado na troca. Como cada tipo de envolvido e independente dos outros e a troca pode envolver qualquer combinacao deles, a Fase 3 e modelada como tres triplas identicas em estrutura:

```
GW_TemTroca{X} → Task_ProcessarTroca{X} → GW_Join{X}
         └──────────────────────────────────┘ (skip se nao ha Troca{X})
```

Cada tripla funciona assim:
- O gateway de abertura (`GW_TemTroca*`) verifica se existe o tipo de troca correspondente.
- Se sim: executa a task de processamento e prossegue para o gateway de convergencia.
- Se nao: bypassa a task via arco de skip e vai direto ao gateway de convergencia.
- O gateway de convergencia (`GW_Join*`) recebe ambos os fluxos (com processamento e sem) e une o caminho.

Todos os arcos de skip percorrem y=455, uma linha horizontal acima da linha principal de tarefas (y=490–570). Isso cria um "corredor superior" visualmente distinto para os fluxos de bypass, sem cruzar sobre as tasks.

Os gateways de convergencia sao modelados como `exclusiveGateway` sem nome (diamante X sem rotulo), pois sua funcao e puramente estrutural — reunir dois caminhos mutuamente exclusivos. O uso de gateway exclusivo para convergencia e correto quando apenas um dos caminhos esta ativo por vez, o que e exatamente o caso aqui.

### 6.2 Processamento da Troca de RT (Matriz 31 Combinacoes)

A `ServiceTask` **`Task_ProcessarTrocaRT`** ("Processar troca de RT — matriz 31 combinacoes") invoca `ProcessaTrocaRtRN`. Esta e a task mais sofisticada do processo em termos de logica de negocio.

A complexidade vem do fato de que um licenciamento pode ter multiplos RTs vinculados, cada um com um `TipoResponsabilidadeTecnica` diferente (ex: RT de Projeto, RT de Execucao, RT de Instalacoes Hidraulicas). A troca nao e simplesmente "substituir o RT antigo pelo novo": depende de como os tipos de responsabilidade se relacionam entre si.

A classe `ProcessaTrocaRtRN` implementa uma matriz com 31 combinacoes possiveis de tipos de responsabilidade, e para cada combinacao determina qual `AcaoTrocaRT` aplicar:

| AcaoTrocaRT | Descricao |
|---|---|
| `IGNORA` | Nenhuma alteracao para este tipo de responsabilidade |
| `INCLUI` | Inclui o novo RT para este tipo (nao havia RT anterior) |
| `REMOVE_RT` | Remove o RT atual sem substituir por outro |
| `ATUALIZA_SOMENTE_TIPO` | Mantem o mesmo RT mas atualiza o tipo de responsabilidade |
| `ATUALIZA_TIPO_SUBSTITUI_ARQUIVOS` | Atualiza tipo e substitui os arquivos (ART/RRT) pelos novos |
| `ATUALIZA_TIPO_ADICIONA_ARQUIVOS` | Atualiza tipo e adiciona os novos arquivos sem remover os anteriores |

A separacao em seis acoes distintas permite que o sistema gerencie adequadamente os arquivos vinculados a cada tipo de responsabilidade no Alfresco, sem excluir documentos que ainda tem validade juridica para outros tipos de responsabilidade.

### 6.3 Processamento da Troca de RU

A `ServiceTask` **`Task_ProcessarTrocaRU`** ("Processar troca de RU") e relativamente simples em comparacao com a de RT. O Responsavel pelo Uso tem apenas uma instancia por licenciamento e nao tem arquivos vinculados. A operacao e um UPDATE direto:

```sql
UPDATE CBM_RESPONSAVEL_USO
  SET CPF_RU = ?, DTH_ATUALIZACAO = SYSDATE
  WHERE ID_LICENCIAMENTO = ?
```

A simplicidade justifica uma ServiceTask propria, separada das demais, por razao de modularidade: o codigo de processamento de RU nao deve estar misturado com o de RT ou de proprietarios, facilitando manutencao e testes unitarios de cada `RN` individualmente.

### 6.4 Processamento da Troca de Proprietarios

A `ServiceTask` **`Task_ProcessarTrocaProprietario`** ("Processar troca de Proprietarios") invoca `ProcessaTrocaProprietarioRN`, que gerencia a lista de proprietarios como um conjunto: compara os proprietarios atuais (em `CBM_LICENCIAMENTO_PROPRIETARIO`) com os proprietarios da solicitacao (em `CBM_TROCA_PROPRIETARIO`) e executa as operacoes necessarias:

- `INSERT` para proprietarios novos que nao existiam antes.
- `DELETE` para proprietarios removidos da lista.
- `UPDATE` quando ha atualizacao de dados de um proprietario existente.

Esta task vem por ultimo na sequencia dos tres processamentos condicionais porque a alteracao de proprietarios tem a maior complexidade de dados relacionais e e a menos frequente na pratica. Encerrar com ela permite que o processo de RT (o mais frequente) seja concluido antes.

### 6.5 Finalizacao da Aprovacao e Evento de Fim APROVADO

A `ServiceTask` **`Task_FinalizarAprovacao`** ("Finalizar efetivacao: APROVADO + marco REALIZA_TROCA + notificacao") e o ultimo passo de escrita do processo. Suas tres operacoes sao:

1. **UPDATE de estado:**
   ```sql
   UPDATE CBM_TROCA_ENVOLVIDO
     SET SIT_TROCA = 'APROVADO', DTH_APROVACAO = SYSDATE
     WHERE ID = ?
   ```
   Este e o unico momento em que `SIT_TROCA` muda de `SOLICITADO` para `APROVADO`. A mudanca ocorre somente apos todos os processamentos condicionais terem sido concluidos, garantindo que os dados de envolvidos ja foram efetivamente atualizados nas tabelas do licenciamento.

2. **INSERT do marco `REALIZA_TROCA_ENVOLVIDO`:** registra o momento exato em que a troca foi efetivada, completando o historico de marcos: `SOLICITA` (inicio) → `APROVA(s)` (cada autorizacao parcial) → `REALIZA` (efetivacao final).

3. **INSERT da notificacao final:** o solicitante recebe confirmacao de que a troca foi concluida, com data/hora e lista de envolvidos atualizados.

O evento de fim **`EndEvent_Aprovado`** ("Troca APROVADA e efetivada") e um evento de fim simples com borda grossa — o desfecho esperado e positivo do processo.

---

## 7. Fluxos Cross-Lane e Decisoes de Roteamento Visual

O diagrama do P09 contem varios fluxos que cruzam fronteiras de raias, cada um com waypoints explicitamente definidos para garantir legibilidade. A tabela abaixo resume as decisoes de roteamento mais importantes:

| Fluxo | Rota | Justificativa do roteamento |
|---|---|---|
| SF2 (Buscar → Consultar) | Desce de y=165 ate y=530 e vai para direita ate x=485 | Task de consulta esta diretamente abaixo na mesma coluna X |
| SF5 (GW_PodeIniciar → Preencher) | Sobe de y=505 ate y=125 e vai para direita ate x=760 | Volta a raia do solicitante pela mesma coluna antes de avancar |
| SF6 (Preencher → Validar) | Desce de y=165 ate y=490 | Mesma coluna X, cruza as tres raias verticalmente |
| SF14 (Notificar → Consultar prop.) | Va para direita ate x=1940, sobe ate y=255, entra em x=1960 | Margem de 25px antes de subir evita sobreposicao com borda da task |
| SF21_loop (todos autorizam: loop-back) | Sobe ate y=155, vai esquerda ate x=2040, desce ate y=215 | Passa pelo espaco vazio acima dos elementos da raia do solicitante |
| SF37 (Cancelamento) | Vai esquerda ate x=2038, desce ate y=600 | Alinha com o centro X da task de cancelamento antes de descer |
| SF40 (Reforco: loop-back) | Vai esquerda ate x=1945, sobe ate y=255, entra em x=1960 | Simetrico ao SF14 mas na direcao oposta |

---

## 8. Maquina de Estados, Marcos e Rastreabilidade de Auditoria

### Maquina de estados da TrocaEnvolvidoED

O campo `SIT_TROCA` em `CBM_TROCA_ENVOLVIDO` percorre a seguinte maquina de estados ao longo do P09:

```
SOLICITADO
    |----[unanime S]----> APROVADO (fim normal)
    |----[qualquer N]---> REPROVADO (fim por rejeicao)
    |----[cancelamento]-> CANCELADO (fim por cancelamento)
```

O estado inicial `SOLICITADO` e definido em `Task_CriarTroca` (Fase 1). As transicoes para os estados finais ocorrem em tasks especificas da Fase 2 (`Task_GravarRejeicaoN`, `Task_GravarCancelamento`) e da Fase 3 (`Task_FinalizarAprovacao`).

A anotacao `@Audited` (Hibernate Envers) na `TrocaEnvolvidoED` garante que cada mudanca de `SIT_TROCA` e registrada automaticamente em `CBM_TROCA_ENVOLVIDO_AUD` com timestamp e usuario responsavel.

### Marcos de auditoria registrados durante o P09

| Marco | Task que registra | Momento |
|---|---|---|
| `SOLICITA_TROCA_ENVOLVIDO` | `Task_MarcoSolicita` | Ao concluir a Fase 1 com sucesso |
| `APROVA_TROCA_ENVOLVIDO` | `Task_MarcoAprova` | A cada proprietario que autoriza (pode ser registrado N vezes) |
| `REPROVA_TROCA_ENVOLVIDO` | `Task_GravarRejeicaoN` | Quando qualquer proprietario rejeita |
| `REALIZA_TROCA_ENVOLVIDO` | `Task_FinalizarAprovacao` | Apos efetivacao completa na Fase 3 |

O marco `CANCELADO` nao e registrado em `CBM_LICENCIAMENTO_MARCO` — o cancelamento e rastreado diretamente via `DTH_CANCELAMENTO` em `CBM_TROCA_ENVOLVIDO` e pela auditoria Envers.

### Separacao entre aprovacao parcial e efetivacao

Uma das decisoes de design mais importantes do P09 e que a aprovacao de um proprietario individual (`Task_MarcoAprova`) nao efetiva a troca. Somente apos a ultima autorizacao — quando `GW_TodosAutorizaram` retorna COUNT=0 — o fluxo avanca para a Fase 3. Isso significa que, durante toda a Fase 2, os dados do licenciamento permanecem inalterados: o RT antigo continua ativo, o RU antigo continua ativo. A troca e atomica: ou acontece completamente (apos unanimidade), ou nao acontece.

---

## 9. Seguranca e Controle de Acesso

### Verificacoes de identidade nos endpoints

Cada endpoint do P09 implementa verificacoes de identidade conforme o papel esperado do usuario:

| Endpoint | Verificacao de identidade |
|---|---|
| `POST /licenciamentos/{idLic}/troca-envolvidos` | Usuario deve ser envolvido do licenciamento |
| `PUT .../autorizar` | CPF logado deve corresponder a ID_PROPRIETARIO em CBM_TROCA_AUTORIZACAO |
| `PUT .../rejeitar` | Mesma verificacao do autorizar |
| `PUT /troca-envolvidos/{id}/cancelar` | CPF logado deve ser CBM_TROCA_ENVOLVIDO.CPF_SOLICITANTE |
| `PUT .../reforcar-notificacao` | CPF logado deve ser CBM_TROCA_ENVOLVIDO.CPF_SOLICITANTE |

### Autenticacao via SOE PROCERGS

Todos os endpoints sao protegidos pelo token JWT emitido pelo SOE PROCERGS (meu.rs.gov.br). O `@AutorizaEnvolvido` e o `SegurancaEnvolvidoInterceptor` do sistema SOL validam o token e extraem o CPF do usuario logado, que e usado em todas as verificacoes de RN07, RN10, RN11 e RN12 descritas acima.

### Controle de acessos entre raias

A separacao de raias no diagrama nao e apenas estetica — ela reflete fronteiras reais de controle de acesso:

- Elementos na raia do Solicitante so sao acessiveis por usuarios que iniciaram a solicitacao ou que tem vinculo com o licenciamento.
- Elementos na raia dos Proprietarios so sao acessiveis por usuarios cujo CPF consta em `CBM_TROCA_AUTORIZACAO` para a troca em questao.
- Elementos na raia do Backend nunca sao expostos diretamente ao usuario — sao automatismos internos executados como consequencia das acoes das raias superiores.

---

## Rastreabilidade: Elementos do BPMN x Codigo-Fonte

| Elemento BPMN | Tipo | Classe EJB / Endpoint | Tabela Principal |
|---|---|---|---|
| `Task_BuscarLicenciamento` | UserTask | `GET /licenciamentos/{idLic}/troca-envolvidos` | `CBM_TROCA_ENVOLVIDO` |
| `Task_ConsultaLicenciamento` | ServiceTask | `ConsultaTrocaEnvolvidoLicenciamentoRN` | `CBM_LICENCIAMENTO` |
| `Task_PreencherSolicitacao` | UserTask | `GET /troca-envolvidos/cpf/{cpf}/responsabilidade/{tipo}` | — |
| `Task_ValidarSolicitacao` | ServiceTask | `SolicitaTrocaEnvolvidoLicenciamentoRN` (validacao) | `CBM_STATUS_CADASTRO` |
| `Task_UploadAlfresco` | ServiceTask | `ArquivoRN.incluir()` | `CBM_ARQUIVO` |
| `Task_CriarTroca` | ServiceTask | `SolicitaTrocaEnvolvidoLicenciamentoRN.solicitar()` | `CBM_TROCA_ENVOLVIDO` |
| `Task_CriarAutorizacoes` | ServiceTask | `SolicitaTrocaEnvolvidoLicenciamentoRN.incluiAutorizacoes()` | `CBM_TROCA_AUTORIZACAO` |
| `Task_MarcoSolicita` | ServiceTask | `LicenciamentoMarcoInclusaoRN` | `CBM_LICENCIAMENTO_MARCO` |
| `Task_NotificarProprietarios` | ServiceTask | `NotificaTrocaEnvolvidoRN.notificaEnvolvidos()` | `CBM_NOTIFICACAO` |
| `Task_ProprietarioConsulta` | UserTask | `GET .../autorizacao` e `.../autorizacao/arquivos` | `CBM_TROCA_AUTORIZACAO` |
| `Task_ProprietarioDecide` | UserTask | `PUT .../autorizar` ou `PUT .../rejeitar` | `CBM_TROCA_AUTORIZACAO` |
| `Task_GravarAutorizacaoS` | ServiceTask | `AutorizacaoTrocaEnvolvidoRN.autoriza()` | `CBM_TROCA_AUTORIZACAO` |
| `Task_MarcoAprova` | ServiceTask | `LicenciamentoMarcoInclusaoRN` | `CBM_LICENCIAMENTO_MARCO` |
| `GW_TodosAutorizaram` | ExclusiveGW | `AutorizacaoTrocaEnvolvidoRN.verificaTodosAutorizaram()` | `CBM_TROCA_AUTORIZACAO` |
| `Task_GravarRejeicaoN` | ServiceTask | `AutorizacaoTrocaEnvolvidoRN.rejeita()` | `CBM_TROCA_ENVOLVIDO` |
| `Task_GravarCancelamento` | ServiceTask | `CancelaTrocaEnvolvidoRN.cancela()` | `CBM_TROCA_ENVOLVIDO` |
| `Task_ReforcarNotificacao` | ServiceTask | `NotificaTrocaEnvolvidoRN.reforcarSolicitacao()` | `CBM_NOTIFICACAO` |
| `Task_ProcessarTrocaRT` | ServiceTask | `ProcessaTrocaRtRN` | `CBM_RESPONSAVEL_TECNICO_LICEN` |
| `Task_ProcessarTrocaRU` | ServiceTask | `ProcessaTrocaRuRN` | `CBM_RESPONSAVEL_USO` |
| `Task_ProcessarTrocaProprietario` | ServiceTask | `ProcessaTrocaProprietarioRN` | `CBM_LICENCIAMENTO_PROPRIETARIO` |
| `Task_FinalizarAprovacao` | ServiceTask | `AutorizacaoTrocaEnvolvidoRN.efetivar()` | `CBM_TROCA_ENVOLVIDO` |
| `BoundaryEvent_Cancelamento` | Msg Interrompente | `PUT /troca-envolvidos/{id}/cancelar` | `CBM_TROCA_ENVOLVIDO` |
| `BoundaryEvent_ReforcoNotificacao` | Msg Nao-Interrompente | `PUT .../reforcar-notificacao` | `CBM_NOTIFICACAO` |
