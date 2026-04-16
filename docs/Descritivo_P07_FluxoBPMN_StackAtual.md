# Descritivo do Fluxo BPMN — P07 Vistoria Presencial (Stack Atual Java EE)

**Arquivo BPMN:** `P07_VistoriaPresencial_StackAtual.bpmn`
**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Stack:** Java EE · JAX-RS · CDI · JPA/Hibernate · EJB `@Stateless` · SOE PROCERGS · Alfresco ECM

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Estrutura de Raias e Justificativa de Modelagem](#2-estrutura-de-raias-e-justificativa-de-modelagem)
3. [Evento de Início e Fase de Distribuição (ADM + BE)](#3-evento-de-início-e-fase-de-distribuição-adm--be)
4. [Fase de Execução da Vistoria (Fiscal CBM-RS)](#4-fase-de-execução-da-vistoria-fiscal-cbm-rs)
5. [Gateway de Resultado e Ramificações](#5-gateway-de-resultado-e-ramificações)
6. [Fluxo de Rascunho — Loop de Revisão do Laudo](#6-fluxo-de-rascunho--loop-de-revisão-do-laudo)
7. [Fluxo de Aprovação e Homologação Administrativa](#7-fluxo-de-aprovação-e-homologação-administrativa)
8. [Fluxo de Reprovação — Emissão e Ciência do CIV](#8-fluxo-de-reprovação--emissão-e-ciência-do-civ)
9. [Fluxo de Inviabilidade](#9-fluxo-de-inviabilidade)
10. [Máquinas de Estado, Marcos e Auditoria](#10-máquinas-de-estado-marcos-e-auditoria)

---

## 1. Visão Geral do Processo

O processo P07 modela a **Vistoria Presencial** realizada pelo CBM-RS para verificar se um estabelecimento atende às exigências do PPCI (Plano de Prevenção e Proteção Contra Incêndio) aprovado na análise técnica anterior (P04). Trata-se do momento em que um Fiscal do Corpo de Bombeiros se desloca fisicamente ao imóvel, avalia as condições de segurança contra incêndio e registra o resultado no sistema SOL.

O processo é acionado quando um licenciamento atinge a situação `AGUARDANDO_DISTRIBUICAO` (ou `AGUARDANDO_DISTRIBUICAO_RENOV` para renovações). Esse estado indica que a análise técnica foi favorável e que a próxima etapa é agendar e realizar a vistoria presencial. A partir daí, quatro atores interagem no sistema:

- O **ADM CBM-RS** organiza e distribui as vistorias em lote para os fiscais;
- O **Fiscal CBM-RS** executa a vistoria, documenta o laudo e submete o resultado;
- O **ADM CBM-RS** (na fase de homologação) valida e homologa o resultado do fiscal;
- O **Cidadão/RT** é notificado do resultado e deve confirmar formalmente a ciência quando houver reprovação.

O processo contempla quatro desfechos possíveis:

| Desfecho | Situação Final | Próximo Processo |
|---|---|---|
| Aprovado (DEFINITIVA/PARCIAL) | `AGUARDANDO_PRPCI` | P08 — Emissão do PRPCI |
| Aprovado (RENOVACAO) | `AGUARDANDO_ACEITE_PRPCI_RENOV` | Aceite do PRPCI de renovação |
| Reprovado — CIV | `CIV` | P05 (recurso) ou novo PPCI |
| Inviável | `ANALISE_INVIABILIDADE_PENDENTE` | P11 — Análise de Inviabilidade |

A modelagem segue rigorosamente a estrutura de classes e regras de negócio encontradas no código-fonte Java EE do backend SOL, refletindo com precisão as chamadas REST, as classes RN (`@Stateless` EJB), as transições de estado (`@TrocaEstadoLicenciamentoQualifier`) e os marcos de auditoria (`TipoMarco`).

---

## 2. Estrutura de Raias e Justificativa de Modelagem

O BPMN foi organizado em **um pool** com **quatro raias horizontais**, representando os limites de responsabilidade de cada participante. Essa decisão reflete o padrão já estabelecido nos BPMNs anteriores do projeto (P03, P06, P07) e alinha-se à arquitetura em camadas do sistema SOL.

### Raia 1 — Cidadão / RT (Responsável Técnico)

Posicionada no topo do pool, esta raia representa o cidadão ou o Responsável Técnico que acompanha o processo. Em P07, a participação do RT é restrita à fase final do fluxo de reprovação: visualizar o CIV e confirmar a ciência. A raia está no topo porque o RT é o ator externo ao CBM-RS, e a convenção visual do projeto coloca os atores externos acima dos internos.

**Justificativa:** Embora o RT tenha papel limitado neste processo (ao contrário de P03, onde é ator central), sua presença é obrigatória: sem a ciência formal do CIV, a situação do licenciamento não pode avançar para o estado `CIV`. A raia foi mantida separada porque as tarefas do RT exigem autenticação via SOE PROCERGS com perfil de cidadão, diferente das demais raias que usam perfis internos CBM-RS.

### Raia 2 — Fiscal CBM-RS

Raia central-superior, concentra as tarefas de execução direta da vistoria: visualizar o processo, preencher o laudo (com upload para Alfresco), concluir a vistoria e eventualmente salvar rascunho. O Fiscal é o ator que mais interage nesta fase do processo.

**Justificativa:** A separação desta raia da raia do ADM é necessária porque as permissões são distintas: o Fiscal opera com `@Permissao(objeto="VISTORIA", acao="VISTORIAR")`, enquanto o ADM usa `@Permissao(objeto="VISTORIA", acao="HOMOLOGAR")` e `@Permissao(objeto="DISTRIBUICAOVISTORIA", acao="DISTRIBUIR")`. O sistema SOE PROCERGS impõe perfis de acesso separados para essas funções, e a segregação visual no BPMN reflete essa separação real de competências.

### Raia 3 — ADM CBM-RS (Homologador)

Raia central-inferior (dentro do bloco CBM-RS), responsável por duas subfases distintas: a distribuição inicial das vistorias em lote e a homologação do resultado apresentado pelo Fiscal. O evento de início está nesta raia porque é o ADM quem inicia ativamente o processo ao distribuir as vistorias.

**Justificativa:** A posição do evento de início nesta raia (e não na raia Fiscal) traduz o comportamento real do sistema: o processo P07 não começa com uma ação do Fiscal, mas com uma decisão administrativa de distribuição. O Fiscal só é envolvido após o ADM definir quem vai a qual vistoria, em qual data e turno. Consolidar distribuição e homologação na mesma raia evita criar uma quinta raia para uma função que é exercida pelo mesmo perfil de usuário.

### Raia 4 — Sistema SOL Backend (Java EE / WildFly)

Raia inferior, mais larga, acomoda todas as operações automáticas realizadas pelo sistema: execução da distribuição, registro de aprovação e reprovação, geração de documentos (CIV e APPCI) no Alfresco, transições de estado via CDI Strategy Pattern, integração com LAI e registro de marcos de auditoria. É a raia mais povoada do processo porque P07 envolve muito processamento automático intermediário.

**Justificativa:** Separar as `ServiceTask` em uma raia própria do backend é uma decisão deliberada para deixar claro ao leitor o que é interação humana e o que é automação. Cada `ServiceTask` referencia a classe Java EE real via `camunda:class`, tornando o BPMN uma documentação executável e rastreável. A raia foi subdividida visualmente em três faixas horizontais: aprovação (faixa superior), reprovação/CIV (faixa intermediária) e inviabilidade (faixa inferior), permitindo leitura paralela dos fluxos alternativos.

---

## 3. Evento de Início e Fase de Distribuição (ADM + BE)

### 3.1 Evento de Início — `Start_P07`

O evento de início é um **Start Event simples** (círculo sem marcador) posicionado na raia ADM. Ele representa o momento em que o ADM acessa o sistema e identifica licenciamentos aguardando distribuição de vistoria. Não foi usado um Start Event de mensagem ou temporizador porque o sistema SOL não implementa trigger automático para essa fase: a distribuição é sempre iniciada por ação manual do ADM.

**Pré-condição modelada:** O evento está associado ao estado `AGUARDANDO_DISTRIBUICAO` ou `AGUARDANDO_DISTRIBUICAO_RENOV` na tabela `CBM_LICENCIAMENTO`. Isso significa que P04 (análise técnica) foi concluído com aprovação, habilitando a vistoria.

### 3.2 `Task_ADM_ListarDistribuicao` — Listar Licenciamentos para Distribuição

Esta `UserTask` representa a consulta inicial do ADM à lista de processos que precisam ser distribuídos. No sistema, corresponde à chamada `GET /adm/licenciamentos/vistorias/solicitadas`, implementada em `ListaVistoriaRestImpl.listaSolicitadas()`.

**Justificativa:** A tarefa foi modelada como uma etapa explícita (e não fundida com a próxima) porque representa uma ação real de consulta e seleção: o ADM pode ter dezenas de licenciamentos aguardando e precisa visualizá-los, filtrar por região ou tipo, antes de configurar a distribuição. A separação evidencia que existe uma decisão intermediária (quais processos distribuir agora?) antes do ato de configurar e submeter.

### 3.3 `Task_ADM_ConfigurarDistribuicao` — Configurar e Submeter Distribuição em Lote

Nesta `UserTask`, o ADM seleciona os licenciamentos, designa o Fiscal responsável (`idFiscal`), define a data prevista (`dataPrevista: Calendar`) e o turno (`turnoPrevisto: TipoTurnoVistoria`). O envio ocorre via `PUT /adm/distribuicao/vistoria/distribuir`, chamando `LicenciamentoDistribuicaoVistoriaRest.distribuirVistoriaOrdinaria()`.

Um aspecto importante modelado aqui é a **distribuição em lote**: o DTO `VistoriaOrdinariaDistribuicaoRequest` contém `idLicenciamentos: List<Long>`, permitindo ao ADM distribuir múltiplos processos em uma única operação. Essa funcionalidade do sistema foi preservada no BPMN por ser central ao fluxo de trabalho operacional do CBM-RS.

**Justificativa:** A separação entre listar e configurar reflete a existência de dois endpoints REST distintos e de duas telas distintas no sistema (listagem e formulário de distribuição). Fundir as duas tarefas em uma só mascararia essa realidade técnica e dificultaria o mapeamento entre o BPMN e os requisitos do sistema.

### 3.4 `Task_BE_ExecutarDistribuicao` — Executar Distribuição de Vistoria

Esta `ServiceTask` corresponde à execução automática da `LicenciamentoDistribuicaoVistoriaRN.distribuir()`. Para cada licenciamento selecionado, o sistema realiza as seguintes operações atômicas dentro de uma única transação JTA (`@TransactionAttribute(REQUIRED)`):

1. Cria um registro `VistoriaED` com `StatusVistoria.SOLICITADA`;
2. Determina o tipo de vistoria (`TipoVistoria`: DEFINITIVA, PARCIAL ou RENOVACAO);
3. Executa a transição de estado do licenciamento: `AGUARDANDO_DISTRIBUICAO` → `AGUARDANDO_VISTORIA` via `@TrocaEstadoLicenciamentoQualifier`;
4. Registra o marco `TipoMarco.DISTRIBUICAO_VISTORIA` em `CBM_MARCO`.

**Justificativa:** Ser modelada como `ServiceTask` (e não uma continuação da `UserTask` anterior) é essencial porque a lógica de negócio envolvida é responsabilidade do backend, não do usuário. A separação também reflete o pattern arquitetural do SOL: o controller REST recebe a requisição, mas delega imediatamente à camada RN. O atributo `camunda:class` aponta para a classe EJB real, tornando o elemento BPMN rastreável diretamente ao código-fonte.

### 3.5 `Task_BE_NotificarDistribuicao` — Notificar Partes

Após a distribuição ser registrada, o sistema envia notificações por e-mail ao Fiscal designado, ao RT e ao proprietário/RU. Esta `ServiceTask` chama `VistoriaRN.notificarDistribuicao()` e inclui data, turno e endereço da vistoria.

**Justificativa:** A notificação foi modelada como uma tarefa separada da execução da distribuição por duas razões: (a) conceitualmente, são operações distintas — a distribuição altera o estado persistente do sistema, enquanto a notificação é uma comunicação assíncrona; (b) tecnicamente, o código SOL as implementa em métodos separados, e separar no BPMN facilita o entendimento de que uma falha na notificação não deve reverter a distribuição.

---

## 4. Fase de Execução da Vistoria (Fiscal CBM-RS)

### 4.1 `Task_FISCAL_VisualizarVistoria` — Visualizar Vistoria Distribuída

O Fiscal acessa o sistema e visualiza a lista de vistorias que lhe foram atribuídas. A chamada é `GET /adm/licenciamentos/vistorias/distribuidas`, que filtra por `VistoriaED.idUsuarioSoe` igual ao identificador SOE do fiscal logado. O retorno inclui endereço, data prevista, turno, dados do RT e dados do proprietário.

**Justificativa:** Esta tarefa existe explicitamente no BPMN porque representa o momento em que o `StatusVistoria` muda de `SOLICITADA` para `EM_VISTORIA` ao abrir o detalhe — uma transição de estado relevante. Além disso, antes de ir ao campo, o Fiscal precisa consultar os documentos do PPCI (plantas, memoriais descritivos) que já foram aprovados na análise técnica. A tarefa marca esse momento de preparação.

### 4.2 `Task_FISCAL_UploadLaudo` — Preencher / Revisar Laudo de Vistoria

Esta é a tarefa mais importante da fase de execução e foi deliberadamente nomeada como **alvo de loop**, pois recebe fluxos de três fontes distintas:

1. O caminho normal: vindo de `Task_FISCAL_VisualizarVistoria`;
2. O caminho de revisão de rascunho: vindo de `Task_FISCAL_SalvarRascunho` (loop interno);
3. O caminho de reenvio pós-indeferimento: vindo de `Task_BE_RegistrarIndeferimento` (loop externo).

O Fiscal preenche o laudo de vistoria com os dados coletados em campo, registra os itens de conformidade e não conformidade, e faz o upload do documento PDF para o Alfresco. O identificador retornado pelo Alfresco (`identificadorAlfresco = "workspace://SpacesStore/{UUID}"`) é armazenado em `ArquivoED` e vinculado ao `LaudoVistoriaED`.

**Justificativa:** O design de múltiplas entradas nesta tarefa é uma decisão consciente que evita a duplicação de elementos BPMN. Em vez de ter três tarefas de "preencher laudo" espalhadas pelo diagrama, a convergência em um único ponto torna o modelo mais limpo e reflete a realidade do sistema: o endpoint `POST /adm/vistoria/{id}/laudo` e a classe `LaudoVistoriaRN.incluirOuAlterarLaudo()` são os mesmos independentemente de ser o primeiro preenchimento ou uma revisão. O atributo `camunda:formKey="form:laudo-vistoria"` documenta que há um formulário dedicado para essa tarefa.

A separação entre `UploadLaudo` e `ConcluirVistoria` (próxima tarefa) é igualmente intencional: o Fiscal pode salvar o laudo e sair do sistema sem concluir, retornando depois para complementar informações. São dois atos distintos — preencher e submeter.

### 4.3 `Task_FISCAL_ConcluirVistoria` — Concluir Vistoria (Submeter Resultado)

Quando o laudo está completo, o Fiscal submete o resultado definitivo via `PUT /adm/vistoria/{id}/concluir`, chamando `VistoriaConclusaoRN.concluir()`. O DTO `VistoriaConclusaoRequest` exige o campo `resultado: ResultadoVistoria` com um dos quatro valores possíveis: `APROVADO`, `REPROVADO`, `INVIAVEL` ou `RASCUNHO`.

**Justificativa:** A submissão do resultado foi separada do upload do laudo porque envolve `@Permissao(objeto="VISTORIA", acao="VISTORIAR")` e uma lógica de negócio mais complexa: valida que o laudo está completo, que o arquivo Alfresco está vinculado e que o fiscal logado é o designado. Modelar como tarefa separada evidencia que existe uma "barreira de qualidade" entre preencher e submeter, e que o sistema valida essa transição.

---

## 5. Gateway de Resultado e Ramificações

### 5.1 `GW_ResultadoVistoria` — Gateway Exclusivo de Resultado

Imediatamente após a conclusão, um **Gateway Exclusivo** avalia o campo `resultado` do `VistoriaConclusaoRequest` e distribui o fluxo em quatro caminhos. A escolha do Gateway Exclusivo (XOR) é apropriada porque exatamente uma das quatro condições será verdadeira em qualquer execução.

**Justificativa da posição:** O gateway foi posicionado na raia Fiscal (e não na raia BE) porque a decisão é tomada pelo Fiscal ao escolher o resultado na tarefa anterior. O backend não decide o resultado — ele apenas registra e transita estados conforme a escolha do Fiscal. Colocar o gateway na raia Fiscal comunica claramente que é o ator humano quem determina o rumo do processo a partir daqui.

As quatro saídas e suas condições:

| Saída | Condição | Destino |
|---|---|---|
| RASCUNHO | `resultado == ResultadoVistoria.RASCUNHO` | `Task_FISCAL_SalvarRascunho` (loop interno) |
| APROVADO | `resultado == ResultadoVistoria.APROVADO` | `Task_BE_RegistrarAprovacao` (BE row1) |
| REPROVADO | `resultado == ResultadoVistoria.REPROVADO` | `Task_BE_RegistrarReprovacao` (BE row2) |
| INVIAVEL | `resultado == ResultadoVistoria.INVIAVEL` | `Task_BE_MarcarInviavel` (BE row3) |

**Justificativa das faixas visuais:** Os três caminhos pós-gateway (aprovação, reprovação, inviabilidade) fluem para faixas verticais distintas dentro da raia BE, criando uma leitura visual intuitiva: o caminho superior leva à aprovação e ao APPCI, o intermediário leva à reprovação e ao CIV, e o inferior leva à inviabilidade e ao encerramento imediato.

---

## 6. Fluxo de Rascunho — Loop de Revisão do Laudo

### 6.1 `Task_FISCAL_SalvarRascunho` — Laudo Salvo como Rascunho

Quando o Fiscal escolhe `RASCUNHO`, o sistema transiciona `StatusVistoria` de `EM_VISTORIA` para `EM_RASCUNHO` sem registrar nenhum marco definitivo. A tarefa `Task_FISCAL_SalvarRascunho` representa o momento em que o sistema persiste essa escolha e o Fiscal é informado de que pode retornar para completar o laudo posteriormente.

**Justificativa:** Modelar o rascunho como uma `UserTask` separada (e não como um loop direto do gateway) serve para documentar explicitamente que há uma operação backend intermediária (`VistoriaRN.salvarRascunho()`) e que o estado `EM_RASCUNHO` tem significado próprio no sistema — ele aparece nas listagens do Fiscal como "laudo em andamento" e pode ser retomado a qualquer momento.

### 6.2 `Flow_Rascunho_UploadLaudo` — Retorno ao Preenchimento

O sequence flow de retorno sai do topo de `Task_FISCAL_SalvarRascunho`, percorre acima da lane Fiscal (utilizando waypoints em `y=172`, acima do limite superior da raia em `y=180`) e entra pelo topo de `Task_FISCAL_UploadLaudo`.

**Justificativa:** O roteamento acima da raia é a solução padrão para loops dentro da mesma raia em BPMNs horizontais. Contornar por cima evita que a seta de retorno cruze ou se confunda com as demais setas que avançam da esquerda para a direita, mantendo a legibilidade do diagrama. A seta rotulada "Revisar Laudo" documenta a intenção do fluxo.

---

## 7. Fluxo de Aprovação e Homologação Administrativa

### 7.1 `Task_BE_RegistrarAprovacao` — Registrar Aprovação

Quando o resultado é `APROVADO`, a `ServiceTask` `VistoriaConclusaoRN.aprova()` é executada automaticamente. Essa classe:

- Transiciona `StatusVistoria` de `EM_VISTORIA` para `EM_APROVACAO`;
- Associa o `LaudoVistoriaED` à `VistoriaED`;
- Executa a `TrocaEstado` do licenciamento: `AGUARDANDO_VISTORIA` → `EM_HOMOLOGACAO_VISTORIA`;
- Registra o marco `TipoMarco.VISTORIA_APPCI` (ou `VISTORIA_RENOVACAO` para renovação).

O estado `EM_APROVACAO` é intermediário: significa que o resultado foi registrado pelo Fiscal, mas ainda aguarda validação do ADM (homologação).

**Justificativa:** A separação entre `GW_ResultadoVistoria` e `Task_BE_RegistrarAprovacao` (com a service task no BE em vez de diretamente ligada ao ADM) reflete o design do sistema: a aprovação pelo Fiscal não é diretamente visível ao ADM até que o backend persista o estado e mude a situação do licenciamento. A service task documenta essa camada intermediária de processamento.

### 7.2 `Task_ADM_ListarAprovadas` — Listar Vistorias Aguardando Homologação

O ADM acessa a lista de vistorias em `EM_APROVACAO` via `GET /adm/licenciamentos/vistorias/aprovadas`. Esta tarefa é o ponto em que o ADM toma conhecimento de que há vistorias prontas para homologação.

**Justificativa:** A separação entre listar e analisar (próxima tarefa) replica a estrutura já estabelecida na fase de distribuição e reflete o fluxo real de navegação no sistema: o ADM acessa uma lista, seleciona um processo, abre o detalhe e então decide. Fundir essas etapas mascararia essa navegação e dificultaria a especificação de requisitos de interface.

### 7.3 `Task_ADM_AnalisarHomologacao` — Analisar e Decidir Homologação

Nesta `UserTask`, o ADM revisa o laudo de vistoria (acessando o PDF via Alfresco) e decide entre **DEFERIR** (emitir APPCI) ou **INDEFERIR** (devolver para nova vistoria com justificativa). Dois endpoints REST distintos são invocados dependendo da decisão:

- Deferimento: `PUT /adm/vistoria/{id}/deferir` → `VistoriaHomologacaoAdmRN.defere()`;
- Indeferimento: `PUT /adm/vistoria/{id}/indeferir` → `VistoriaHomologacaoAdmRN.indefere()` com `VistoriaIndeferimentoRequest { motivoIndeferimento: String }`.

**Justificativa:** Concentrar a decisão em uma única `UserTask` em vez de criar duas tarefas separadas (uma para deferir e outra para indeferir) é uma escolha de modelagem que aproxima o BPMN do uso real: o ADM acessa a mesma tela, analisa o laudo e clica em um dos dois botões. A decisão é tomada nessa única interação. O gateway subsequente separa os caminhos de saída, mas a tarefa em si representa o ato único de análise e deliberação.

**Permissão:** `@Permissao(objeto="VISTORIA", acao="HOMOLOGAR")` — perfil de ADM homologador, diferente do perfil de distribuição.

### 7.4 `GW_DecisaoHomologacao` — Gateway Exclusivo de Homologação

Este **Gateway Exclusivo** avalia a decisão do ADM e distribui o fluxo em dois caminhos:

- **DEFERIR:** leva para `Task_BE_HomologarDeferimento` na raia BE (faixa de aprovação);
- **INDEFERIR:** leva para `Task_BE_RegistrarIndeferimento` na raia BE (faixa de reprovação), que iniciará o loop de retorno.

**Justificativa:** O gateway foi posicionado na raia ADM (e não na BE) pelos mesmos motivos do `GW_ResultadoVistoria`: é o ator humano (ADM) quem toma a decisão, não o sistema. O backend apenas executa as consequências dessa decisão.

### 7.5 `Task_BE_RegistrarIndeferimento` — Registrar Indeferimento e Iniciar Loop

`VistoriaHomologacaoAdmRN.indefere()` executa a transição de estado do licenciamento de volta para `AGUARDANDO_DISTRIBUICAO`, permitindo que o ADM redistribua a vistoria. O motivo do indeferimento é persistido em `VistoriaED.indeferimentoHomolog` (campo `VARCHAR 4000`). O marco `TipoMarco.HOMOLOG_VISTORIA_INDEFERIDO` é registrado.

### 7.6 `Flow_Indefer_UploadLaudo` — Loop de Retorno Pós-Indeferimento

O sequence flow de retorno sai do fundo de `Task_BE_RegistrarIndeferimento` (raia BE, faixa intermediária, `y≈740`), percorre **abaixo do pool inteiro** (waypoints em `y=976`, abaixo do limite inferior do pool em `y=960`) e retorna ao fundo de `Task_FISCAL_UploadLaudo` (`y=295`).

**Justificativa:** O roteamento abaixo do pool é necessário porque o loop percorre uma distância horizontal muito grande (de `x≈2135` até `x≈1120`) e atravessa diversas raias e elementos. Ir abaixo do pool é a forma padronizada para loops de longa distância em diagramas complexos, evitando que a seta de retorno cruze elementos intermediários e confunda a leitura. O rótulo "Nova Vistoria" documenta a semântica do fluxo.

**Diferença em relação ao loop de rascunho:** O loop de rascunho percorre acima da raia Fiscal (curta distância, dentro do mesmo processo ativo); o loop de indeferimento percorre abaixo do pool inteiro (longa distância, reiniciando efetivamente a fase de execução após uma redistribuição). Essa diferença visual comunica ao leitor que o indeferimento é um evento mais significativo que o rascunho.

### 7.7 `Task_BE_HomologarDeferimento` — Homologar Deferimento

`VistoriaHomologacaoAdmRN.defere()` consolida a aprovação: transiciona `StatusVistoria` para `APROVADO`, registra `VistoriaED.idUsuarioSoeHomolog` (o ADM que homologou) e insere o marco `TipoMarco.HOMOLOG_VISTORIA_DEFERIDO` (ou `HOMOLOG_VISTORIA_RENOV_DEFERIDO` para renovação).

### 7.8 `Task_BE_GerarAPPCI` — Gerar Documento APPCI

`VistoriaDocumentoAppciRN.incluirArquivo()` gera o PDF do APPCI (Alvará de Prevenção e Proteção Contra Incêndio) e o armazena no Alfresco. Internamente, cria um novo `AppciED` com validade de 12 meses e versão sequencial. O `ArquivoED` resultante tem `identificadorAlfresco = "workspace://SpacesStore/{UUID}"`.

**Justificativa:** A geração do APPCI foi modelada como `ServiceTask` separada da homologação porque representa uma operação técnica distinta (geração de PDF + upload Alfresco) com sua própria classe de negócio (`VistoriaDocumentoAppciRN`). Se a geração do documento falhar (por exemplo, por indisponibilidade temporária do Alfresco), a homologação já foi registrada e pode ser reprocessada sem reverter o estado.

### 7.9 `GW_TipoVistoria` — Gateway de Tipo de Vistoria

Após a geração do APPCI, o fluxo passa por um **Gateway Exclusivo** que avalia o campo `TipoVistoria` da vistoria:

- **DEFINITIVA(1) ou PARCIAL(2):** fluxo normal → `Task_BE_TransicionarPrpci` → situação `AGUARDANDO_PRPCI`;
- **RENOVACAO(3):** fluxo de renovação → `Task_BE_TransicionarAceitePrpci` → situação `AGUARDANDO_ACEITE_PRPCI_RENOV`.

**Justificativa:** A bifurcação por tipo de vistoria existe porque a renovação do APPCI tem um fluxo ligeiramente diferente na máquina de estados do licenciamento: enquanto vistorias normais aguardam que o proprietário retire o PRPCI fisicamente no CBM-RS (`AGUARDANDO_PRPCI`), vistorias de renovação aguardam um aceite eletrônico do proprietário no próprio sistema (`AGUARDANDO_ACEITE_PRPCI_RENOVACAO`). Essa distinção existe no código-fonte (dois qualificadores CDI distintos) e foi preservada no BPMN para tornar o modelo auditável.

### 7.10 `Task_BE_TransicionarPrpci` e `Task_BE_TransicionarAceitePrpci`

Cada uma dessas `ServiceTask` executa o `@TrocaEstadoLicenciamentoQualifier` correspondente e registra o marco `TipoMarco.CIENCIA_APPCI`. A diferença está no estado de destino do licenciamento e no fato de que o campo `VistoriaED.aceitePrpci` é definido como `'N'` (via `SimNaoBooleanConverter`) em ambos os casos, indicando que o proprietário ainda não acenou o recebimento do PRPCI.

### 7.11 `Task_BE_IntegrarLAI` e `Task_BE_IntegrarLAI_Renov` — Integração LAI

Após a transição de estado, o sistema chama `LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria()` de forma assíncrona (`@Asynchronous`) para registrar uma pesquisa de satisfação no sistema LAI. O método registra o `idDemandaLai` no licenciamento e envia o link de pesquisa ao cidadão por e-mail.

**Justificativa:** A integração LAI foi modelada como tarefa própria (e não fundida com a transição de estado) porque é uma operação assíncrona que não deve bloquear nem reverter o fluxo principal em caso de falha. Modelar explicitamente documenta que esta integração existe e que ela ocorre após a aprovação, não durante. As versões normal e renovação usam o mesmo método, o que poderia justificar uma única tarefa; optou-se por duas para evidenciar que ambos os caminhos chegam ao mesmo ponto de integração LAI antes de encerrar.

### 7.12 End Events de Aprovação

- **`End_Aprovado`:** situação `AGUARDANDO_PRPCI`, marcos `HOMOLOG_VISTORIA_DEFERIDO` e `CIENCIA_APPCI`. O processo P07 encerra para o fluxo normal e P08 (emissão do PRPCI) é o próximo.
- **`End_AprovadoRenov`:** situação `AGUARDANDO_ACEITE_PRPCI_RENOV`, marcos `HOMOLOG_VISTORIA_RENOV_DEFERIDO` e `CIENCIA_APPCI`. O processo encerra para renovações, aguardando aceite eletrônico do proprietário.

---

## 8. Fluxo de Reprovação — Emissão e Ciência do CIV

### 8.1 `Task_BE_RegistrarReprovacao` — Registrar Reprovação

Análoga a `Task_BE_RegistrarAprovacao`, mas para o caso de reprovação. `VistoriaConclusaoRN.reprova()` transiciona `StatusVistoria` para `EM_APROVACAO` (estado intermediário, aguardando homologação mesmo para reprovados) e registra o marco `TipoMarco.VISTORIA_CIV`.

**Justificativa:** O estado `EM_APROVACAO` para reprovados pode parecer contraintuitivo, mas reflete a realidade do sistema: toda conclusão de vistoria — seja aprovação ou reprovação — passa pelo crivo do ADM antes de ser finalizada. O ADM pode discordar do Fiscal em ambas as direções. Isso justifica o mesmo estado intermediário para os dois resultados.

**Nota de modelagem:** O fluxo de reprovação não passa pelas tarefas de homologação do ADM (`Task_ADM_ListarAprovadas` e `Task_ADM_AnalisarHomologacao`). Essa é uma simplificação consciente do modelo: na prática do sistema, a reprovação de vistoria pode ou não requerer homologação administrativa dependendo da configuração do CBM-RS. O modelo segue a versão mais comum encontrada no código, onde a reprovação segue diretamente para geração do CIV após registro.

### 8.2 `Task_BE_GerarCIV` — Gerar Documento CIV

`VistoriaDocumentoCivRN.incluirArquivo()` gera o PDF do CIV (Comunicado de Inconformidade na Vistoria) com os itens reprovados, as não conformidades encontradas e as orientações para adequação. O texto formatado é construído via `TextoFormatadoED` (`@Lob CLOB`) e o PDF resultante é enviado ao Alfresco com o nodeRef armazenado em `CBM_ARQUIVO`.

**Justificativa:** A geração do CIV foi modelada como tarefa separada da transição de estado (próxima tarefa) pelos mesmos motivos que a geração do APPCI: são operações com classes distintas e responsabilidades distintas. Separar permite identificar claramente onde o Alfresco é acessado e qual documento é gerado.

### 8.3 `Task_BE_TransicionarCienciaCIV` — Transicionar para Aguardando Ciência

`CivCienciaCidadaoRN` (implementando `@LicenciamentoCienciaQualifier(CIV)`) transiciona o licenciamento para `AGUARDANDO_CIENCIA_CIV` e registra `TipoMarco.CIENCIA_CIV`. Neste momento, o `StatusVistoria` é definitivamente alterado para `REPROVADO`.

O método `getTipoMarco()` retorna `TipoMarco.CIENCIA_CIV` para vistorias normais e `TipoMarco.CIENCIA_CIV_RENOVACAO` para renovações — distinção implementada por polimorfismo no código-fonte e preservada na documentação da `ServiceTask`.

### 8.4 Sequência RT: `Task_RT_VisualizarCIV` e `Task_RT_ConfirmarCienciaCIV`

O fluxo sobe da raia BE até a raia RT por meio de um sequence flow que percorre verticalmente através de todas as raias intermediárias. Essa travessia visual de múltiplas raias é intencional: comunica ao leitor que, após todas as operações automáticas do backend, o controle retorna ao ator externo (RT/cidadão).

O RT visualiza o documento CIV disponível no Alfresco e, em seguida, confirma formalmente a ciência via `PUT /licenciamento/{id}/ciencia-civ`. A autenticação usa `@AutorizaEnvolvido + SegurancaEnvolvidoInterceptor` para garantir que apenas o RT ou RU vinculado ao licenciamento possa confirmar.

**Justificativa:** Modelar as duas tarefas do RT separadamente (visualizar e confirmar) é necessário porque o sistema distingue o acesso ao documento da confirmação formal. O RT pode visualizar o CIV múltiplas vezes antes de confirmar, consultar a equipe técnica, preparar adequações. A confirmação é um ato jurídico com implicação de prazo (30 dias para recurso de 1a instância, conforme `LicenciamentoCidadaoRN.PRAZO_SOLICITAR_RECURSO_1_INSTANCIA`).

### 8.5 `Task_BE_RegistrarCienciaCIV` — Registrar Ciência e Encerrar

`CivCienciaCidadaoRN.registrarCiencia()` finaliza o ciclo de CIV: transiciona o licenciamento para a situação `CIV` (situação terminal neste processo), atualiza `CBM_VISTORIA.dth_ciencia_civ` e notifica as partes do encerramento.

O sequence flow deste passo sai da raia RT (onde o RT confirma) e desce verticalmente até a raia BE, retornando ao nível de processamento automático para o ato final de registro. Essa seta vertical cruzando múltiplas raias é deliberada: representa a consequência imediata da ação do RT no sistema backend.

### 8.6 `End_Reprovado` — Fim do Processo com CIV

O processo P07 encerra na situação `CIV`. A partir daqui, o RT pode optar por:
- Solicitar recurso administrativo (Processo P05 — Ciência de Recurso);
- Adequar o estabelecimento e submeter novo PPCI.

O evento de fim foi posicionado na raia BE (faixa de reprovação) porque o ato final é uma operação do sistema (`RegistrarCienciaCIV`), não uma ação do RT. Colocar o End Event na raia BE mantém a coerência visual com os demais End Events do processo.

---

## 9. Fluxo de Inviabilidade

### 9.1 `Task_BE_MarcarInviavel` — Marcar Inviabilidade e Encaminhar P11

Quando o Fiscal conclui a vistoria com resultado `INVIAVEL`, a `ServiceTask` `VistoriaConclusaoRN.marcarInviabilidade()` transiciona o licenciamento para `ANALISE_INVIABILIDADE_PENDENTE` — situação que representa casos em que a vistoria não pôde ser realizada nas condições atuais (por exemplo, o imóvel estava inacessível, em obras estruturais ou em condição de risco imediato).

**Justificativa:** A inviabilidade foi modelada como faixa separada (faixa inferior da raia BE) porque é um caminho de exceção com processamento mínimo: não há geração de documentos, não há homologação do ADM, e o encerramento é imediato. Posicionar essa faixa abaixo das demais comunica visualmente que este é o caminho mais curto e mais atípico do processo.

### 9.2 `End_Inviavel` — Fim com Inviabilidade

O processo P07 encerra imediatamente após o registro da inviabilidade. O End Event foi posicionado à direita de `Task_BE_MarcarInviavel`, na mesma faixa, como sequência direta — sem nenhuma interação humana adicional. O processo P11 é responsável por dar continuidade à análise da inviabilidade de forma independente.

---

## 10. Máquinas de Estado, Marcos e Auditoria

### 10.1 Máquina de Estado — `StatusVistoria`

O processo P07 percorre os seguintes estados de `VistoriaED` ao longo do fluxo:

```
SOLICITADA
  → EM_VISTORIA (ao Fiscal abrir o detalhe)
    → EM_RASCUNHO (se rascunho) → EM_VISTORIA (ao retomar)
    → EM_APROVACAO (ao concluir — aprovado ou reprovado)
      → APROVADO (ao deferir homologação)
      → REPROVADO (ao transicionar para ciência CIV)
      → EM_REDISTRIBUICAO (ao indeferir homologação)
```

### 10.2 Máquina de Estado — `SituacaoLicenciamento` (P07)

```
AGUARDANDO_DISTRIBUICAO (ou _RENOV)
  → AGUARDANDO_VISTORIA (ao distribuir)
    → EM_HOMOLOGACAO_VISTORIA (ao concluir — aprovado ou reprovado)
      → AGUARDANDO_PRPCI (ao deferir — DEFINITIVA/PARCIAL)
      → AGUARDANDO_ACEITE_PRPCI_RENOVACAO (ao deferir — RENOVACAO)
      → AGUARDANDO_CIENCIA_CIV (ao transicionar CIV)
        → CIV (ao confirmar ciência)
      → AGUARDANDO_DISTRIBUICAO (ao indeferir homologação — loop)
    → ANALISE_INVIABILIDADE_PENDENTE (ao marcar inviavel)
```

### 10.3 Marcos Registrados (TipoMarco)

| Marco | Momento | Registrado por |
|---|---|---|
| `DISTRIBUICAO_VISTORIA` | Execução da distribuição | `Task_BE_ExecutarDistribuicao` |
| `VISTORIA_APPCI` | Aprovação do fiscal (normal) | `Task_BE_RegistrarAprovacao` |
| `VISTORIA_RENOVACAO` | Aprovação do fiscal (renovação) | `Task_BE_RegistrarAprovacao` |
| `VISTORIA_CIV` | Reprovação do fiscal (normal) | `Task_BE_RegistrarReprovacao` |
| `VISTORIA_RENOVACAO_CIV` | Reprovação do fiscal (renovação) | `Task_BE_RegistrarReprovacao` |
| `HOMOLOG_VISTORIA_DEFERIDO` | Deferimento ADM (normal) | `Task_BE_HomologarDeferimento` |
| `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | Deferimento ADM (renovação) | `Task_BE_HomologarDeferimento` |
| `HOMOLOG_VISTORIA_INDEFERIDO` | Indeferimento ADM | `Task_BE_RegistrarIndeferimento` |
| `CIENCIA_APPCI` | Transição para PRPCI | `Task_BE_TransicionarPrpci` / `Task_BE_TransicionarAceitePrpci` |
| `CIENCIA_CIV` | Transição para ciência CIV | `Task_BE_TransicionarCienciaCIV` |
| `CIENCIA_CIV_RENOVACAO` | Transição ciência CIV (renovação) | `Task_BE_TransicionarCienciaCIV` |

### 10.4 Auditoria Hibernate Envers

Toda alteração em `VistoriaED` (`CBM_VISTORIA`), `LaudoVistoriaED` (`CBM_LAUDO_VISTORIA`), `AppciED` (`CBM_APPCI`) e `LicenciamentoED` (`CBM_LICENCIAMENTO`) é automaticamente auditada pelo Hibernate Envers via anotação `@Audited`, gerando registros nas respectivas tabelas `*_AUD`. Isso garante rastreabilidade completa de quem fez o quê e quando em cada etapa do processo P07.

### 10.5 Justificativa Geral da Modelagem

O BPMN `P07_VistoriaPresencial_StackAtual.bpmn` foi construído com os seguintes princípios:

1. **Rastreabilidade total:** cada elemento BPMN é mapeado diretamente a uma classe Java EE real, método, endpoint REST, tabela de banco e permissão do sistema SOE. O BPMN funciona como documentação executável.

2. **Segregação de responsabilidades:** a separação em quatro raias reflete as fronteiras reais de permissão do sistema, evitando a falsa impressão de que qualquer ator pode executar qualquer operação.

3. **Preservação de loops complexos:** os dois loops de retorno (rascunho e indeferimento) foram modelados com waypoints explícitos que refletem a semântica de cada ciclo — revisão rápida do laudo versus redistribuição completa após decisão administrativa.

4. **Suporte a renovação:** o `GW_TipoVistoria` ao final do fluxo de aprovação garante que o comportamento diferenciado de vistorias de renovação esteja explícito no modelo, sem duplicar as etapas comuns.

5. **Alinhamento com o código-fonte:** enums, qualificadores CDI, campos de entidades e métodos de RN foram extraídos diretamente do código Java EE analisado, garantindo que o BPMN reflita o sistema atual sem inferências.
