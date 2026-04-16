# Descritivo do Fluxo BPMN — P04: Análise Técnica de Licenciamento (ATEC)
## Sistema SOL — CBM-RS | Stack Atual Java EE

---

## Sumário

1. [Visão geral do processo](#1-visão-geral-do-processo)
2. [Estrutura do BPMN: raias e participantes](#2-estrutura-do-bpmn-raias-e-participantes)
3. [Fase 1 — Distribuição da análise](#3-fase-1--distribuição-da-análise)
4. [Fase 2 — Registro de resultados da análise técnica](#4-fase-2--registro-de-resultados-da-análise-técnica)
5. [Fase 3 — Via CIA: emissão do Comunicado de Inconformidade](#5-fase-3--via-cia-emissão-do-comunicado-de-inconformidade-na-análise)
6. [Fase 4 — Via CA: envio para homologação](#6-fase-4--via-ca-envio-para-homologação)
7. [Fase 5 — Homologação pelo Coordenador CBM-RS](#7-fase-5--homologação-pelo-coordenador-cbm-rs)
8. [Fase 6a — Deferimento PPCI: geração do Certificado de Aprovação](#8-fase-6a--deferimento-ppci-geração-do-certificado-de-aprovação)
9. [Fase 6b — Deferimento PSPCIM: geração do APPCI e Documento Complementar](#9-fase-6b--deferimento-pspcim-geração-do-appci-e-documento-complementar)
10. [Cancelamento administrativo](#10-cancelamento-administrativo)
11. [Justificativas das decisões de modelagem](#11-justificativas-das-decisões-de-modelagem)
12. [Diagrama de estados das entidades principais](#12-diagrama-de-estados-das-entidades-principais)
13. [Referência cruzada: elementos BPMN x classes Java EE](#13-referência-cruzada-elementos-bpmn-x-classes-java-ee)

---

## 1. Visão geral do processo

O processo P04 — **Análise Técnica de Licenciamento (ATEC)** — representa o núcleo técnico do sistema SOL. É neste processo que o CBM-RS, por meio de seus analistas e coordenadores, avalia tecnicamente o Plano de Prevenção e Proteção Contra Incêndio (PPCI) ou o Programa Simplificado de Prevenção Contra Incêndio e Pânico em Monumentos (PSPCIM) submetido pelo Responsável Técnico.

O processo tem início imediatamente após a conclusão do processo P03, quando o licenciamento alcança a situação `AGUARDANDO_DISTRIBUICAO`. A partir daí, o fluxo percorre obrigatoriamente as seguintes macro-etapas:

1. **Distribuição:** o Coordenador CBM-RS seleciona o licenciamento e atribui um analista.
2. **Análise:** o analista registra o resultado para cada um dos 11 tipos de item técnico.
3. **Decisão técnica:** o analista decide entre emitir um CIA (reprovação) ou enviar para homologação (aprovação).
4. **Homologação:** o Coordenador avalia os resultados e defere ou indefere a análise.
5. **Emissão de documentos:** se deferida, o sistema gera automaticamente os documentos finais — CA (PPCI) ou APPCI + Documento Complementar (PSPCIM) — e os armazena no Alfresco ECM.

O processo admite ainda dois desvios de percurso: o **indeferimento da homologação** (que devolve a análise ao analista para revisão, em loop) e o **cancelamento administrativo** (que interrompe a análise e devolve o licenciamento para nova distribuição).

**Pré-condição:** `SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO`

**Pós-condições possíveis:**

| Via | Status da análise | Situação do licenciamento | Documento gerado |
|---|---|---|---|
| CIA | `REPROVADO` | `AGUARDANDO_CIENCIA` | `cia_analise_tecnica.pdf` |
| CA PPCI | `APROVADO` | `CA` | `ca_nova_analise_tecnica.pdf` ou `ca_existente_analise_tecnica.pdf` |
| APPCI PSPCIM | `APROVADO` | `ALVARA_VIGENTE` | `appci_analise_tecnica.pdf` + `DocComplementar.pdf` |
| Cancelamento | `CANCELADA` | `AGUARDANDO_DISTRIBUICAO` | (nenhum) |

---

## 2. Estrutura do BPMN: raias e participantes

O BPMN do P04 é organizado em um único pool horizontal com quatro raias (lanes), cada uma representando um participante distinto no processo. A separação por raias é uma decisão de modelagem fundamental: ela torna imediatamente visível **quem executa cada passo**, evitando ambiguidades sobre responsabilidades e refletindo com fidelidade a estrutura de permissões implementada no código via `@Permissao(objeto, acao)` do SOE PROCERGS.

### Raia 1 — Coordenador CBM-RS

Representa o servidor com perfil de coordenação dentro do Corpo de Bombeiros. É o ator responsável por dois momentos críticos do processo: a **distribuição** (início) e a **homologação** (conclusão). Ambas as responsabilidades estão protegidas por permissões distintas no sistema (`acao="DISTRIBUIR"` e `acao="HOMOLOGAR"`), o que justifica mantê-las na mesma raia mas em fases separadas no diagrama. O coordenador não analisa o mérito técnico — ele distribui o trabalho e valida a decisão do analista.

### Raia 2 — Analista CBM-RS

Representa o servidor técnico designado pelo coordenador para realizar a análise. Toda a atividade central do processo — o registro dos resultados técnicos para cada tipo de item — ocorre nesta raia. O analista é o único com permissão `acao="ANALISAR"` sobre a análise técnica a ele atribuída, garantida pela validação `AnaliseLicenciamentoTecnicaRN.validaIsAnaliseAssociadaUsuarioItem()` a cada operação de salvamento.

### Raia 3 — RT / Proprietário (Notificações e Documentos)

Esta raia não representa atores que tomam ações dentro do P04 em si, mas os destinatários dos documentos gerados ao final do processo. Os três eventos de fim do processo estão posicionados nesta raia para indicar que, ao término, o resultado produzido (CIA, CA ou APPCI) é direcionado ao RT e ao proprietário. Do ponto de vista de modelagem, posicionar os eventos de fim nesta raia torna explícita a natureza do produto final do processo: um documento com efeito jurídico-administrativo entregue ao requerente.

### Raia 4 — Sistema SOL (Backend Java EE)

Representa todas as operações automáticas executadas pela aplicação sem intervenção humana direta: validações de negócio, criação de entidades, transições de estado, geração de documentos PDF, armazenamento no Alfresco e registro de marcos. Esta raia é intencionalmente a mais densa do diagrama, pois o sistema SOL executa uma cadeia complexa de operações em cada transição de estado do licenciamento.

---

## 3. Fase 1 — Distribuição da análise

### 3.1 Evento de início: licenciamento em AGUARDANDO_DISTRIBUICAO

O processo se inicia com um **StartEvent simples** posicionado na raia do Coordenador. A escolha por um evento de início simples (em vez de um evento de mensagem ou timer) reflete a natureza do acionamento: o coordenador acessa ativamente o sistema para verificar os licenciamentos pendentes. Não há um gatilho automático externo — é uma ação deliberada do coordenador.

O evento representa o estado no qual o licenciamento se encontra (`SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO`) e serve como lembrete de pré-condição para a equipe de desenvolvimento: o processo P04 só pode ser iniciado se o licenciamento estiver nesta situação.

### 3.2 T01 — Consultar licenciamentos pendentes de distribuição

**O que faz:** o coordenador acessa uma lista paginada de licenciamentos disponíveis para distribuição. A lista é filtrada automaticamente pelo sistema com base na competência geográfica do coordenador logado (municípios autorizados por seu perfil de acesso).

**Por que foi modelado:** esta tarefa foi representada como uma `UserTask` separada — e não fundida com a tarefa de seleção — porque ela corresponde a uma tela e a um endpoint REST distintos no sistema (`GET /adm/distribuicao-analise/`). O coordenador pode examinar múltiplos licenciamentos antes de decidir qual distribuir. Modelar como tarefa separada preserva essa possibilidade de navegação e reflete o comportamento real da interface.

A separação também facilita a rastreabilidade: é nesta tarefa que o coordenador consulta o DTO `LicenciamentoAnaliseTecnica` com informações de prioridade e data de submissão, fundamentais para a tomada de decisão de qual licenciamento atender primeiro.

### 3.3 T02 — Selecionar licenciamento e atribuir analista

**O que faz:** após identificar o licenciamento a distribuir, o coordenador seleciona o analista responsável. O sistema oferece a lista de analistas disponíveis para aquele licenciamento via `GET /adm/distribuicao-analise/analistas-disponiveis/{idLicenciamento}`, retornando o DTO `AnalistaDisponivelDTO` com nome, batalhão e quantidade de análises em andamento de cada analista — dados que apoiam a decisão de equilíbrio de carga.

**Por que foi modelado:** esta é uma `UserTask` com `camunda:formKey="distribuicao-analise-form"`, representando o formulário de atribuição. A distinção entre T01 (consulta) e T02 (seleção e confirmação) é importante porque as regras de negócio mais críticas da fase de distribuição (RN-P04-D01, D02, D03) são verificadas apenas no momento da confirmação — ou seja, ao acionar T03. Manter as duas tarefas separadas deixa claro que as validações ocorrem na transição T02→T03, não na listagem.

### 3.4 T03 — Executar distribuição: criar AnaliseTecnicaED e transitar estado

**O que faz:** esta `ServiceTask` concentra toda a lógica de negócio da distribuição, executada pela classe `AnaliseLicenciamentoTecnicaDistribuicaoRN`, método `incluir()`. Em sequência, o sistema: (1) valida as regras de negócio D01 a D03 via `AnaliseLicenciamentoTecnicaDistribuicaoRNVal`; (2) cria o registro `AnaliseLicenciamentoTecnicaED` com `status = EM_ANALISE` e os dados do analista e da data de distribuição; (3) transita a situação do licenciamento de `AGUARDANDO_DISTRIBUICAO` para `EM_ANALISE` via `TrocaEstadoLicenciamentoRN`; (4) registra o marco `TipoMarco.DISTRIBUICAO_ANALISE` via `LicenciamentoMarcoInclusaoRN`.

**Por que foi modelado como uma única ServiceTask:** embora o método `incluir()` execute múltiplas operações, todas elas ocorrem dentro de uma única transação `@TransactionAttribute(REQUIRED)`. Distribuí-las em múltiplas ServiceTasks criaria a falsa impressão de que são etapas separadas que poderiam falhar individualmente — o que não corresponde à realidade técnica. O atomismo transacional justifica a consolidação em uma única tarefa no BPMN.

A documentação inline desta tarefa detalha cada passo da RN, as tabelas afetadas (`ANAL_LIC_TECNICA`, `LICENCIAMENTO`, `LICEN_MARCO`) e o comportamento em caso de erro (lança `BusinessException` → HTTP 422, o coordenador permanece em T02 com mensagem de feedback). Esta informação é essencial para a equipe de desenvolvimento entender o contrato de erro da operação.

---

## 4. Fase 2 — Registro de resultados da análise técnica

### 4.1 T07 — Acessar licenciamento em análise técnica

**O que faz:** o analista designado acessa sua lista de análises em andamento e seleciona o licenciamento para iniciar o trabalho técnico. O sistema retorna os dados completos da análise, incluindo os resultados já registrados em sessões anteriores (se houver), via `AnaliseLicenciamentoTecnicaResultadoRN.efetuaConsultaComResultados()`.

**Por que foi modelado:** esta tarefa é o **ponto de entrada duplo** do processo para o analista: ele chega aqui tanto no início da análise (vindo de T03) quanto após um indeferimento em homologação (vindo de T23I via loop back). O BPMN representa isso com dois fluxos de entrada (`SF_T03_T07` e `SF_T23I_T07`) convergindo em T07, sem a necessidade de um gateway de junção, pois o comportamento da tarefa é idêntico nos dois casos. A documentação desta tarefa explicita o campo `AnaliseLicenciamentoTecnicaED.indeferimentoHomolog`, que exibe ao analista a justificativa do coordenador quando a chegada é via indeferimento.

### 4.2 SP — Sub-processo colapsado: registrar resultados dos 11 tipos de item

**O que faz:** este sub-processo colapsado representa a etapa central e mais extensa do P04. O analista percorre os 11 tipos de item de análise técnica (`TipoItemAnaliseTecnica`) e para cada um registra o resultado (`APROVADO` ou `REPROVADO`) com as justificativas correspondentes (NCS — Normas de Controle e Segurança) quando aplicável.

Os 11 tipos, em ordem de exibição, são:
1. RT (Responsável Técnico)
2. RU (Responsável pelo Uso)
3. PROPRIETARIO
4. TIPO_EDIFICACAO
5. OCUPACAO
6. ISOLAMENTO_RISCO
7. GERAL
8. MEDIDA_SEGURANCA
9. MEDIDA_SEGURANCA_OUTRA
10. RISCO_ESPECIFICO
11. ELEMENTO_GRAFICO

Para cada item, o backend resolve a implementação correta via `ResultadoAnaliseTecnicaStrategyResolver.getStrategy(tipoItemAnaliseTecnica)`, obtendo uma das 11 implementações da interface `ResultadoAnaliseTecnicaStrategy`. Este **Strategy Pattern** permite que cada tipo de item tenha sua própria lógica de validação, consulta, inclusão, edição e exclusão de justificativas, sem que a classe principal da RN precise conhecer as particularidades de cada tipo.

**Por que foi modelado como sub-processo colapsado:** a representação colapsada é uma decisão deliberada de clareza visual. Se os 11 itens fossem expandidos no diagrama principal, o fluxo do P04 se tornaria incompreensível — cada item teria pelo menos uma UserTask e uma ServiceTask, resultando em mais de 22 elementos adicionais apenas para o ciclo de análise. O colapso preserva a legibilidade do diagrama principal enquanto toda a riqueza técnica está documentada no campo `<documentation>` do sub-processo, onde estão descritos o Strategy Pattern, os endpoints REST, o funcionamento do upsert (consultar → excluir justificativas → editar ou incluir), e o tratamento especial do item `MEDIDA_SEGURANCA_OUTRA`.

**Evento de fronteira (BE_Cancelar):** o sub-processo recebe um boundary event de interrupção (tipo erro), posicionado em sua borda inferior. Esse evento representa a possibilidade de cancelamento administrativo da análise enquanto ela está em andamento. O posicionamento na borda inferior do sub-processo é convencional no Camunda Modeler para eventos de interrupção, e o `cancelActivity="true"` garante que, ao ser acionado, o sub-processo é encerrado imediatamente, sem aguardar sua conclusão normal.

### 4.3 T13 — Visualizar rascunho CIA e decidir conclusão da análise

**O que faz:** ao concluir o registro de todos os resultados, o analista acessa esta tela para revisar o conjunto da análise antes de tomar a decisão final. O sistema oferece o download do rascunho da CIA (`DocumentoCiaAnaliseRascunhoRN.gerar()`) — um PDF sem número de autenticação que permite ao analista verificar exatamente como o documento ficará se ele optar pela reprovação. Também é possível baixar o rascunho do CA para verificar os dados do certificado em caso de aprovação.

**Por que foi modelado:** esta tarefa existe como etapa explícita porque ela representa um momento de **reflexão e revisão** antes de um ato irrevogável. A emissão formal da CIA ou o envio para homologação não podem ser desfeitos no fluxo normal — o analista precisa ter certeza antes de confirmar. Modelar esta etapa como uma tarefa separada documenta esse ponto de verificação como requisito de negócio, não apenas como detalhe de interface.

Nesta tarefa também é possível preencher o campo `outraInconformidade` (texto livre), que permite ao analista registrar inconformidades não cobertas pelos 11 tipos padrão. Este campo influencia diretamente a decisão no GW02.

### 4.4 GW02 — Gateway de decisão: CIA ou CA?

**O que faz:** este gateway exclusivo representa a decisão do analista entre duas vias mutuamente excludentes: emitir o Comunicado de Inconformidade na Análise (CIA) ou encaminhar para homologação visando a emissão do Certificado de Aprovação (CA) ou APPCI.

**Por que foi modelado como gateway exclusivo:** a decisão é binária e as duas alternativas são incompatíveis — um licenciamento não pode ao mesmo tempo ser reprovado e aprovado. O gateway exclusivo (`X`) traduz exatamente esta semântica. As duas saídas são nomeadas `CIA (inconformidades)` e `CA (aprovado)` para tornar a intenção imediatamente legível no diagrama.

Embora a condição técnica seja a existência de itens `REPROVADO` ou de `outraInconformidade`, a decisão final é operacionalizada pelo analista via botão na tela — o que justifica que o gateway seja precedido por uma UserTask (T13) e não por uma ServiceTask de avaliação automática.

---

## 5. Fase 3 — Via CIA: emissão do Comunicado de Inconformidade na Análise

### 5.1 T14C — Confirmar emissão de CIA

**O que faz:** o analista revisa as inconformidades identificadas e confirma formalmente a emissão do CIA. Nesta etapa, pode ainda editar o campo `outraInconformidade` para refinar o texto das inconformidades não classificadas. Ao confirmar, o sistema dispara o processo de geração do documento via `POST /adm/analise-tecnica/{idAnaliseTecnica}/cia`.

**Por que foi modelado como UserTask separada de GW02:** a confirmação da CIA é um ato de **responsabilidade técnica e administrativa** do analista. O sistema não emite a CIA automaticamente ao detectar itens reprovados — é o analista quem decide, de forma consciente e deliberada, emiti-la. Esta separação garante que há um passo humano explícito antes de um documento com efeito jurídico ser gerado, o que é fundamental em um sistema que produz atos administrativos do Corpo de Bombeiros.

### 5.2 T15C — Executar lógica CIA: validar, gerar PDF, concluir (REPROVADO)

**O que faz:** esta ServiceTask concentra toda a cadeia de processamento da CIA, executada por `AnaliseLicenciamentoTecnicaCIARN.salvarAnaliseCIA()` em uma única transação. A sequência é: (1) validar regras RN-P04-C01 a C03; (2) gerar a lista de inconformidades por tipo via Strategy Pattern; (3) gerar número de autenticação (`ArquivoRN.gerarNumeroAutenticacao()`); (4) gerar o PDF autenticado via `DocumentoCiaAnaliseAutenticadoRN`; (5) armazenar no Alfresco e persistir `ArquivoED` com `identificadorAlfresco`; (6) setar `status = REPROVADO`; (7) excluir todos os `ResultadoAtecED` da análise; (8) registrar o marco `TipoMarco.ATEC_CIA`; (9) transitar o licenciamento para `AGUARDANDO_CIENCIA`; (10) desbloquear recurso se aplicável.

**Por que toda a cadeia está em uma única ServiceTask:** assim como em T03, a justificativa é o atomismo transacional. Todas essas operações são executadas dentro de uma única transação `@TransactionAttribute(REQUIRED)` no EJB `AnaliseLicenciamentoTecnicaCIARN`. Se qualquer passo falhar (por exemplo, se o Alfresco estiver indisponível), a transação inteira é revertida e nenhum efeito parcial persiste no banco. Fragmentar essa cadeia em múltiplas ServiceTasks no BPMN criaria a expectativa incorreta de que cada passo é uma unidade de trabalho independente.

A documentação inline desta tarefa é especialmente detalhada porque ela combina três subsistemas distintos: a RN de análise, o módulo de geração de PDF autenticado e o Alfresco ECM. Isso é fundamental para que a equipe que implementará o novo sistema compreenda a dependência entre esses módulos.

### 5.3 End_CIA — CIA emitido (REPROVADO / AGUARDANDO_CIENCIA)

**O que representa:** o evento de fim posicionado na raia RT/Proprietário indica que o produto deste ramo do processo — o CIA — é entregue ao Responsável Técnico e ao proprietário. O estado final é `StatusAnaliseLicenciamentoTecnica.REPROVADO` para a análise e `SituacaoLicenciamento.AGUARDANDO_CIENCIA` para o licenciamento. O próximo processo no ciclo de vida é o P05 — Ciência do CIA pelo RT.

**Por que na raia RT e não na raia Sistema:** a posição do EndEvent na raia do RT é uma decisão deliberada de modelagem para tornar evidente quem recebe o resultado do processo. Tecnicamente, o sistema executa a geração do documento — mas o processo termina, do ponto de vista do negócio, quando o RT é notificado e o documento está disponível. A raia do RT como ponto de chegada reforça essa perspectiva orientada ao cliente do serviço.

---

## 6. Fase 4 — Via CA: envio para homologação

### 6.1 T14A — Confirmar envio para homologação

**O que faz:** o analista confirma que todos os 11 tipos de item foram avaliados positivamente e que a análise está pronta para revisão do coordenador. A confirmação aciona `POST /adm/analise-tecnica/{idAnaliseTecnica}/ca`.

**Por que foi modelado:** assim como na confirmação da CIA, esta UserTask existe para registrar o ato deliberado do analista de encaminhar a análise para homologação. É o momento em que o analista assume a responsabilidade técnica pela aprovação do projeto — uma decisão que não deve ser automatizada. A separação entre GW02 (decisão) e T14A (confirmação) preserva um passo de confirmação explícito.

### 6.2 T15A — Executar preparação CA: validar, nota, marco, EM_APROVACAO

**O que faz:** esta ServiceTask executa a lógica de `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()`: (1) valida RN-P04-A01 a A03 (analista correto, status correto, todos os itens com resultado registrado); (2) conclui a nota de serviço vinculada à distribuição via `NotaRN.concluirNota()`; (3) registra o marco correspondente ao tipo de licenciamento (`TipoMarco.ATEC_CA` para PPCI, `TipoMarco.ATEC_APPCI` para PSPCIM); (4) atualiza o status da análise para `EM_APROVACAO`.

**Ponto técnico importante:** neste momento, a `SituacaoLicenciamento` do licenciamento **permanece EM_ANALISE**. A transição da situação do licenciamento só ocorre no momento do deferimento pelo coordenador (T26D ou T24S). Isso é explicitado na documentação do elemento para evitar confusão com o status da `AnaliseLicenciamentoTecnicaED` (que muda para `EM_APROVACAO`). A distinção entre o estado da análise e o estado do licenciamento é um ponto de implementação sutil e crítico.

**Por que foi modelado como ServiceTask consolidada:** novamente, as operações (validação, nota, marco, status) ocorrem na mesma transação EJB. A regra RN-P04-A03 — todos os 11 tipos de item devem ter resultado registrado — é uma validação prévia essencial que, se falhar, reverte tudo sem efeito parcial.

---

## 7. Fase 5 — Homologação pelo Coordenador CBM-RS

### 7.1 T20 — Consultar análises pendentes de homologação

**O que faz:** o coordenador acessa a lista de análises com `status = EM_APROVACAO`, filtrada pelos municípios de sua competência. O endpoint `GET /adm/analise-tecnica-hom/` utiliza `AnaliseLicenciamentoTecnicaHomRN.listaAnalisePendentesHomologacao()`.

**Por que foi modelado:** esta tarefa é o espelho de T01 na fase de distribuição. Ela existe porque o coordenador pode ter múltiplas análises pendentes de homologação e precisa selecionar qual revisar. Modelar a listagem como uma tarefa explícita (e não como parte de T21) documenta que há um estado de espera e seleção antes da revisão, o que é relevante para entender o fluxo de trabalho real dos coordenadores do CBM-RS.

### 7.2 T21 — Revisar resultados completos e documentos da análise

**O que faz:** o coordenador examina em detalhe todos os 11 resultados registrados pelo analista, podendo também baixar os rascunhos do CIA e do CA para verificar os documentos que serão emitidos. O endpoint `GET /adm/analise-tecnica-hom/{idAnaliseTecnica}/resultado` retorna o DTO completo com todos os `ResultadoAtecDTO`.

**Por que foi modelado:** a revisão do coordenador é substancialmente diferente da consulta inicial à lista (T20). Em T21, o coordenador mergulha nos dados técnicos da análise e forma sua opinião sobre a adequação do trabalho do analista. Separar as tarefas de "selecionar" (T20) e "revisar em detalhe" (T21) reflete a UX real do sistema e torna clara a sequência de navegação esperada: lista → seleção → detalhe → decisão.

### 7.3 GW05 — Decisão de homologação: deferir ou indeferir

**O que faz:** gateway exclusivo que bifurca o fluxo conforme a decisão do coordenador.

**Por que foi modelado como gateway exclusivo:** as opções são mutuamente excludentes e há apenas duas possibilidades — deferir ou indeferir. A simplicidade do gateway exclusivo traduz com precisão essa semântica binária. As saídas são nomeadas `Deferir` e `Indeferir` para que o diagrama seja autoexplicativo mesmo sem conhecimento técnico do sistema.

### 7.4 T22I — Confirmar indeferimento com justificativa

**O que faz:** quando o coordenador decide indeferir, esta UserTask o obriga a fornecer uma justificativa textual para a devolução. A justificativa é obrigatória e é armazenada em `AnaliseLicenciamentoTecnicaED.indeferimentoHomolog` — ela será exibida ao analista quando este retornar à análise em T07.

**Por que foi modelado como UserTask separada do GW05:** o indeferimento sem justificativa seria operacionalmente inútil — o analista não saberia o que corrigir. A existência de uma tarefa explícita de confirmação com campo de justificativa obrigatório é um requisito de negócio que precisa estar visível no BPMN, e não apenas documentado em texto. A presença desta UserTask no diagrama comunica à equipe de desenvolvimento que o frontend deve exibir um formulário com campo obrigatório antes de chamar o endpoint de indeferimento.

### 7.5 T23I — Executar indeferimento: EM_ANALISE + marco + concluir nota

**O que faz:** `AnaliseLicenciamentoTecnicaHomRN.indeferir()` executa: (1) status análise → `EM_ANALISE`; (2) salva `indeferimentoHomolog`; (3) registra dados do coordenador na análise (nome, id, data de homologação); (4) registra marco `TipoMarco.HOMOLOG_ATEC_INDEFERIDO`; (5) conclui a nota de serviço.

**Ponto técnico crítico:** a `SituacaoLicenciamento` **não muda** no indeferimento. O licenciamento permanece em `EM_ANALISE`. Isso é intencional: o licenciamento não retorna para uma situação anterior — ele continua em análise, apenas com o analista precisando revisar seu trabalho. Este detalhe, explicitado na documentação do elemento, é fundamental para evitar bugs de implementação.

**Por que o fluxo retorna a T07 (loop back) e não a um novo evento de início:** o retorno ao T07 é modelado como um fluxo de sequência comum (não como um evento de sinalização ou mensagem). Isso reflete a realidade técnica: não há nenhum mecanismo assíncrono no sistema para notificar o analista — ele simplesmente volta a encontrar a análise em `EM_ANALISE` quando acessar sua lista. O loop back via fluxo de sequência direto é a representação mais fidedigna desse comportamento.

---

## 8. Fase 6a — Deferimento PPCI: geração do Certificado de Aprovação

### 8.1 GW06 — Tipo de licenciamento: PPCI ou PSPCIM?

**O que faz:** o primeiro gateway após a decisão de deferir bifurca o fluxo com base no tipo de licenciamento. PPCI gera um CA (Certificado de Aprovação); PSPCIM gera um APPCI (Alvará de Prevenção e Proteção Contra Incêndio) acompanhado de Documento Complementar.

**Por que foi modelado:** a bifurcação por tipo de licenciamento é um dos pontos mais importantes do processo, pois os documentos gerados, os marcos registrados e as situações de destino são completamente diferentes para cada tipo. O gateway torna explícita essa diferença fundamental no diagrama. No código, essa bifurcação está implementada na condicional `if (licenciamento.getTipo() == TipoLicenciamento.PPCI)` dentro de `AnaliseLicenciamentoTecnicaHomRN.deferir()`.

### 8.2 GW07 — Tipo de edificação: A_CONSTRUIR ou Existente?

**O que faz:** para o ramo PPCI, um segundo gateway verifica o tipo de edificação para determinar qual template de CA deve ser utilizado. Edificações `A_CONSTRUIR` recebem o modelo `ca_nova_analise_tecnica.pdf`; edificações existentes recebem `ca_existente_analise_tecnica.pdf`.

**Por que foi modelado:** a distinção entre CA de edificação nova e existente é um requisito funcional do sistema que impacta diretamente o conteúdo do documento gerado. Modelar este gateway explicita para a equipe de desenvolvimento que há **duas implementações distintas** do gerador de CA (`DocumentoCaNovaAnaliseAutenticadoRN` e `DocumentoCaExistenteAnaliseAutenticadoRN`), ambas injetadas via qualificador CDI `@DocumentoCaQualifier`. Sem este gateway no BPMN, um desenvolvedor poderia não perceber a necessidade de tratar os dois casos.

### 8.3 T24D e T25D — Gerar CA Nova / CA Existente

**O que fazem:** cada tarefa executa a cadeia de geração de documento para seu respectivo tipo: (1) gera número de autenticação; (2) gera o PDF via a implementação correspondente de `DocumentoCaAnaliseAutenticadoRN`; (3) armazena no Alfresco via `ArquivoRN.incluirArquivo()`, obtendo o `identificadorAlfresco` (nodeRef); (4) persiste o `ArquivoED` no banco.

**Por que foram modeladas como ServiceTasks separadas (e não como uma única com lógica interna):** a separação reflete a realidade do código — são classes e métodos distintos, com lógica de geração de PDF diferente. Consolidar em uma única ServiceTask mascararia essa distinção e dificultaria o entendimento de qual classe o desenvolvedor precisa implementar para cada caso. A separação no BPMN serve como guia de implementação.

### 8.4 GW08 — Join da bifurcação de edificação

**O que faz:** gateway exclusivo de junção que une os dois caminhos (CA nova e CA existente) antes de seguir para a conclusão do deferimento.

**Por que foi modelado:** em BPMN 2.0, boas práticas exigem que toda bifurcação tenha um gateway de junção correspondente. O GW08 deixa claro que, independentemente do tipo de edificação, o fluxo converge para a mesma conclusão (T26D). A ausência deste gateway criaria ambiguidade sobre como os dois caminhos se unem e poderia levar a implementações incorretas com fluxos paralelos não intencionais.

### 8.5 T26D — Concluir deferimento PPCI: APROVADO → CA

**O que faz:** esta é a tarefa de maior impacto do ramo PPCI. Em uma única transação, `AnaliseLicenciamentoTecnicaHomRN.deferir()` executa: (1) define `status = APROVADO` na análise; (2) associa o `ArquivoED` do CA à análise; (3) registra dados do coordenador (nome, id, data de homologação); (4) exclui todos os `ResultadoAtecED` da análise (limpeza pós-aprovação); (5) registra marco `TipoMarco.HOMOLOG_ATEC_DEFERIDO` com referência ao arquivo; (6) transita o licenciamento de `EM_ANALISE` para `CA`; (7) ativa o recurso do licenciamento via `LicenciamentoAdmRN.ativarRecurso()`.

**Por que a exclusão de resultados ocorre na aprovação:** a remoção dos `ResultadoAtecED` após a aprovação é uma decisão de design do sistema original que merece destaque. Os resultados são dados de trabalho do analista, necessários apenas durante o processo de análise. Após a emissão do CA — que é o documento oficial —, os dados intermediários são removidos para evitar acúmulo desnecessário no banco. O documento Alfresco (CA) é o registro permanente da decisão.

**Por que este passo está na ServiceTask e não distribuído em múltiplas:** o mesmo argumento do atomismo transacional aplicado em T03, T15C e T15A. Estas operações formam uma unidade indivisível de negócio: ou todas ocorrem (deferimento bem-sucedido) ou nenhuma persiste (rollback em caso de falha).

### 8.6 GW09 — Integrar com LAI?

**O que faz:** gateway que verifica se o sistema LAI (Lei de Acesso à Informação) deve ser notificado sobre a aprovação. A condição, conforme o código-fonte, é `analise.getLicenciamento().getSituacao().equals(SituacaoLicenciamento.CA)`.

**Por que foi modelado como gateway (e não incorporado em T26D):** a integração com o LAI é uma responsabilidade externa e opcional, cuja presença no fluxo depende de uma condição específica. Modelar como gateway explicita que esta integração pode ou não ocorrer, e documenta a condição de ativação. Isso é relevante para testes (cenários com e sem integração LAI devem ser testados) e para manutenção (a condição pode ser revisada independentemente do resto do fluxo de deferimento).

### 8.7 T30D — Cadastrar demanda LAI

**O que faz:** integra o licenciamento aprovado ao sistema estadual de transparência ativa (LAI), chamando `LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaAnalise()`.

**Por que foi modelado como ServiceTask separada:** a integração com o LAI é uma dependência externa ao SOL — ela envolve comunicação com outro sistema do Estado. Isolá-la em uma ServiceTask distinta documenta essa dependência de forma explícita, facilita a sua substituição ou desativação sem impacto no restante do fluxo de deferimento, e torna claro que falhas nessa integração precisam ser tratadas de forma específica (não devem reverter o deferimento como um todo).

### 8.8 End_CA — CA gerado e disponível

O processo termina neste evento quando o CA foi gerado, armazenado no Alfresco, e o licenciamento está em `SituacaoLicenciamento.CA`. O próximo processo no ciclo de vida é o P06 — Ciência do CA pelo RT.

---

## 9. Fase 6b — Deferimento PSPCIM: geração do APPCI e Documento Complementar

### 9.1 T23S — Gerar APPCI e Documento Complementar

**O que faz:** esta ServiceTask encapsula a geração dos dois documentos específicos do licenciamento PSPCIM. Para o APPCI: gera o PDF via `DocumentoAPPCIAnaliseAutenticadoRN`, armazena no Alfresco, calcula a validade via `CalculoValidadeAppciRN.getPrazoValidadeEmAnos()`, cria a entidade `AppciED` via `FactoryAppci.criar()` com `ciencia = false` (convertido para `'N'` pelo `SimNaoBooleanConverter`) e persiste via `AppciRN.inclui()`. Para o Documento Complementar: segue o mesmo fluxo de geração, armazenamento e persistência via `AppciDocComplementarRN.inclui()`.

**Por que os dois documentos estão em uma única ServiceTask:** a geração do APPCI e do Documento Complementar são parte do mesmo ato de deferimento para PSPCIM — eles são produzidos na mesma operação e na mesma transação. Separá-los em duas ServiceTasks distintas criaria a implicação incorreta de que um poderia ser gerado sem o outro. A cohesão semântica justifica a consolidação.

**Por que a entidade AppciED tem `ciencia = false` neste momento:** o campo `ciencia` indica se o RT já tomou ciência formalmente do APPCI. No momento da geração, o RT ainda não foi notificado — a ciência ocorrerá em processo posterior. O `SimNaoBooleanConverter` (`Boolean → 'S'/'N'`) é um detalhe de implementação relevante que a equipe precisa conhecer, pois é um padrão usado em várias entidades do sistema e pode causar erros sutis se ignorado.

### 9.2 T24S — Concluir deferimento PSPCIM: APROVADO → ALVARA_VIGENTE

**O que faz:** executa a conclusão do deferimento para PSPCIM: define `status = APROVADO`, registra dois marcos distintos (`HOMOLOG_ATEC_APPCI` e `EMISSAO_DOC_COMPLEMENTAR`), transita o licenciamento de `EM_ANALISE` para `ALVARA_VIGENTE`, e ativa o recurso do licenciamento.

**Por que dois marcos distintos:** os marcos `HOMOLOG_ATEC_APPCI` e `EMISSAO_DOC_COMPLEMENTAR` correspondem a documentos distintos gerados em momentos formalmente separados (embora tecnicamente simultâneos). O rastreamento histórico exige que cada documento tenha seu próprio marco, permitindo que auditorias e consultas identifiquem exatamente quando cada documento foi emitido e quem o autorizou.

**Por que a situação final é ALVARA_VIGENTE e não CA:** licenciamentos PSPCIM geram um Alvará de funcionamento (APPCI) que entra em vigor imediatamente após a aprovação. O estado `ALVARA_VIGENTE` reflete essa realidade jurídica distinta do PPCI (que vai para o estado `CA`, indicando que o certificado foi emitido mas pode haver outros passos antes do início das atividades). Esta diferença de estados é fundamental para os processos subsequentes do sistema.

### 9.3 End_APPCI — APPCI e Documento Complementar disponíveis

O processo termina com o licenciamento em `ALVARA_VIGENTE`, o APPCI disponível no Alfresco e a entidade `AppciED` persistida com `ciencia = 'N'`. O próximo passo é a ciência formal do RT sobre o APPCI.

---

## 10. Cancelamento administrativo

### 10.1 BE_Cancelar — Boundary event de interrupção

**O que representa:** um evento de fronteira de interrupção (tipo erro, `cancelActivity="true"`) posicionado na borda do sub-processo SP. Ele pode ser acionado a qualquer momento enquanto o sub-processo está em execução — ou seja, enquanto o analista está registrando os resultados dos itens.

**Por que `cancelActivity="true"` e não `false` (não-interruptivo):** o cancelamento administrativo é uma operação drástica que deve encerrar imediatamente toda atividade em andamento no sub-processo. Um boundary event não-interruptivo permitiria que o sub-processo continuasse em paralelo após o cancelamento, o que seria semanticamente incorreto — não faz sentido continuar registrando resultados de uma análise que foi cancelada. O `cancelActivity="true"` garante que o sub-processo é encerrado instantaneamente.

**Por que tipo erro e não mensagem ou sinal:** o cancelamento administrativo representa uma situação de exceção no fluxo normal — uma intervenção que interrompe o curso esperado do processo. O tipo erro é o mais semanticamente próximo dessa ideia de "exceção que interrompe o fluxo normal". Do ponto de vista de implementação, o cancelamento é acionado via endpoint REST (`DELETE /adm/analise-tecnica/{idAnaliseTecnica}/cancelar`) pelo administrador, não por um evento assíncrono ou mensagem inter-processo.

### 10.2 T_Cancel — Executar cancelamento administrativo

**O que faz:** `AnaliseLicenciamentoTecnicaCancelamentoAdmRN.cancela()` executa: (1) valida que a análise está em `EM_ANALISE`; (2) exclui todos os `ResultadoAtecED` e `JustificativaNcs` da análise; (3) conclui a nota de serviço; (4) define `status = CANCELADA`; (5) transita o licenciamento de volta para `AGUARDANDO_DISTRIBUICAO`; (6) registra o marco `TipoMarco.CANCELA_DISTRIBUICAO_ANALISE`.

**Por que o licenciamento retorna para AGUARDANDO_DISTRIBUICAO:** o cancelamento administrativo anula o trabalho da análise, mas não cancela o licenciamento em si. O processo de licenciamento do requerente continua — o CBM-RS apenas precisa realizar uma nova distribuição, possivelmente para um analista diferente. O retorno para `AGUARDANDO_DISTRIBUICAO` é a forma de reinserir o licenciamento na fila de distribuição sem perder o histórico do processo anterior.

### 10.3 End_Cancelado — Análise cancelada

O processo termina com `StatusAnaliseLicenciamentoTecnica = CANCELADA` e `SituacaoLicenciamento = AGUARDANDO_DISTRIBUICAO`. O licenciamento está disponível para nova distribuição, reiniciando o P04 do início.

---

## 11. Justificativas das decisões de modelagem

Esta seção consolida as principais decisões de modelagem e seus fundamentos, para referência em futuras extensões ou revisões do diagrama.

### 11.1 Uma ServiceTask por transação EJB

Ao longo do P04, sempre que múltiplas operações de banco e negócio ocorrem dentro de um único método EJB `@Stateless` com `@TransactionAttribute(REQUIRED)`, elas são representadas por uma única ServiceTask no BPMN. Isso reflete o atomismo transacional: ou todas as operações da tarefa são concluídas com sucesso, ou nenhuma persiste. Representar cada operação como uma ServiceTask separada criaria a falsa impressão de que cada passo é uma unidade de trabalho independente, o que poderia induzir a erros de implementação.

### 11.2 Sub-processo colapsado para os 11 itens de análise

A decisão de usar um sub-processo colapsado para os 11 tipos de item foi baseada em dois critérios: (a) clareza visual — expandir os 11 itens no diagrama principal tornaria o fluxo ilegível; (b) cohesão semântica — o registro de resultados é uma fase homogênea do processo (todos os itens seguem o mesmo padrão de ciclo de vida), adequada para representação como uma unidade de trabalho com comportamento interno documentado em texto.

### 11.3 Loop back direto para T07 após indeferimento

O retorno da análise ao analista após indeferimento foi modelado como um fluxo de sequência direto (T23I → T07) em vez de um evento de sinalização ou mensagem. Isso reflete o comportamento real do sistema: não há mecanismo de notificação assíncrona implementado — o analista simplesmente encontra a análise em `EM_ANALISE` ao acessar sua lista. O loop direto é a representação mais honesta com a implementação existente.

### 11.4 Separação entre status da análise e situação do licenciamento

Ao longo do descritivo, foi enfatizada a distinção entre `StatusAnaliseLicenciamentoTecnica` (estado da entidade `AnaliseLicenciamentoTecnicaED`) e `SituacaoLicenciamento` (estado da entidade `LicenciamentoED`). Essas são entidades independentes com ciclos de vida próprios que mudam em momentos diferentes do processo. O BPMN não tenta representar ambos os estados simultaneamente — isso seria impraticável visualmente — mas a documentação inline de cada elemento especifica qual dos dois estados muda em cada tarefa.

### 11.5 Eventos de fim na raia RT

A posição dos três eventos de fim (CIA, CA, APPCI) na raia do RT/Proprietário é uma escolha deliberada para comunicar que os produtos do processo são documentos entregues ao requerente. Do ponto de vista estritamente técnico, os documentos são gerados pelo Sistema SOL — mas do ponto de vista do negócio, o processo termina quando o requerente tem acesso ao resultado.

### 11.6 Dois documentos separados para PSPCIM (T23S)

A geração do APPCI e do Documento Complementar foram consolidadas em uma única ServiceTask porque são produzidos na mesma operação e transação. No entanto, dois marcos distintos são registrados (T24S), refletindo o fato de que cada documento tem relevância jurídica e rastreabilidade independentes. Esta separação marco/documento é um padrão recorrente no sistema SOL.

### 11.7 Fluxo de retorno do loop de indeferimento

O fluxo de retorno (SF_T23I_T07) percorre um longo caminho horizontal na base da raia Sistema para retornar ao T07 na raia Analista. Esta é a única seta de sentido inverso no diagrama e foi modelada com waypoints explícitos para evitar sobreposição com outros elementos. Em Camunda Modeler, setas de loop que cruzam múltiplas raias são sempre visualmente desafiadoras — a escolha de rotear pela base do diagrama é a que minimiza o cruzamento com outros fluxos.

---

## 12. Diagrama de estados das entidades principais

### StatusAnaliseLicenciamentoTecnica (entidade AnaliseLicenciamentoTecnicaED)

```
[criada em T03]
      |
      v
 EM_ANALISE ───────────────────────────────> CANCELADA
      |                                         ^
      | [T15A: salvarAnaliseCA()]                |
      v                                         |
 EM_APROVACAO                          [T_Cancel: cancela()]
      |
      | [T23I: indeferir()]
      v          \
 EM_ANALISE       [T26D/T24S: deferir()]
(loop back)              |
                         v
                      APROVADO

      | [T15C: salvarAnaliseCIA()]
      v
   REPROVADO
```

### SituacaoLicenciamento (entidade LicenciamentoED — mudanças no P04)

```
AGUARDANDO_DISTRIBUICAO
      |
      | [T03: trocaEstado AGUARDANDO_DISTRIBUICAO → EM_ANALISE]
      v
  EM_ANALISE ──────────────────────────> AGUARDANDO_DISTRIBUICAO
      |                                         ^
      |                                  [T_Cancel: cancela()]
      | [T15C: salvarAnaliseCIA()]
      v
AGUARDANDO_CIENCIA

      | [T26D: deferir() PPCI]
      v
    CA

      | [T24S: deferir() PSPCIM]
      v
ALVARA_VIGENTE
```

---

## 13. Referência cruzada: elementos BPMN x classes Java EE

| Elemento BPMN | Tipo | Classe Java EE | Método | Endpoint REST |
|---|---|---|---|---|
| Start_P04 | StartEvent | — | — | — |
| T01_ConsultarPendentes | UserTask | `AnaliseLicenciamentoTecnicaDistribuicaoRN` | `listaAnalisePendentesDistribuicao()` | `GET /adm/distribuicao-analise/` |
| T02_SelecionarDistribuir | UserTask | — | — | `GET /adm/distribuicao-analise/analistas-disponiveis/{id}` |
| T03_ExecutarDistribuicao | ServiceTask | `AnaliseLicenciamentoTecnicaDistribuicaoRN` | `incluir()` | `POST /adm/distribuicao-analise/` |
| T07_AcessarAnalise | UserTask | `AnaliseLicenciamentoTecnicaConsultaRN` | `listaAnalises()` | `GET /adm/analise-tecnica/` |
| SP_RegistrarResultados | SubProcess | `ResultadoAnaliseTecnicaSalvarRN` | `salvarResultado()` | `POST /adm/analise-tecnica/resultado` |
| BE_Cancelar | BoundaryEvent | — | — | `DELETE /adm/analise-tecnica/{id}/cancelar` |
| T_Cancel_Executar | ServiceTask | `AnaliseLicenciamentoTecnicaCancelamentoAdmRN` | `cancela()` | `DELETE /adm/analise-tecnica/{id}/cancelar` |
| T13_VisualizarRascunhoCIA | UserTask | `AnaliseLicenciamentoTecnicaDocumentoRN` | `downloadRascunhoCIA()` | `GET /adm/analise-tecnica/{id}/rascunho-cia` |
| GW02_ResultadoAnalise | ExclusiveGateway | — | — | — |
| T14C_ConfirmarCIA | UserTask | — | — | `POST /adm/analise-tecnica/{id}/cia` |
| T15C_ExecutarCIA | ServiceTask | `AnaliseLicenciamentoTecnicaCIARN` | `salvarAnaliseCIA()` | `POST /adm/analise-tecnica/{id}/cia` |
| T14A_ConfirmarCA | UserTask | — | — | `POST /adm/analise-tecnica/{id}/ca` |
| T15A_ExecutarCA | ServiceTask | `AnaliseLicenciamentoTecnicaCARN` | `salvarAnaliseCA()` | `POST /adm/analise-tecnica/{id}/ca` |
| T20_ConsultarPendentesHom | UserTask | `AnaliseLicenciamentoTecnicaHomRN` | `listaAnalisePendentesHomologacao()` | `GET /adm/analise-tecnica-hom/` |
| T21_RevisarAnalise | UserTask | `AnaliseLicenciamentoTecnicaHomRN` | `consultaComResultados()` | `GET /adm/analise-tecnica-hom/{id}/resultado` |
| GW05_DeferirIndeferir | ExclusiveGateway | — | — | — |
| T22I_ConfirmarIndeferimento | UserTask | — | — | `POST /adm/analise-tecnica-hom/{id}/indeferir` |
| T23I_ExecutarIndeferimento | ServiceTask | `AnaliseLicenciamentoTecnicaHomRN` | `indeferir()` | `POST /adm/analise-tecnica-hom/{id}/indeferir` |
| GW06_TipoLicDefer | ExclusiveGateway | — | `LicenciamentoED.getTipo()` | — |
| GW07_TipoEdif | ExclusiveGateway | — | `LicenciamentoED.getCaracteristica().getEdificacao()` | — |
| T24D_GerarCANovo | ServiceTask | `AnaliseLicenciamentoTecnicaDocumentoRN` | `incluirCANovo()` | — |
| T25D_GerarCAExistente | ServiceTask | `AnaliseLicenciamentoTecnicaDocumentoRN` | `incluirCAExistente()` | — |
| GW08_JoinEdif | ExclusiveGateway | — | — | — |
| T26D_ConcluirDeferPPCI | ServiceTask | `AnaliseLicenciamentoTecnicaHomRN` | `deferir()` (PPCI) | `POST /adm/analise-tecnica-hom/{id}/deferir` |
| GW09_LAI | ExclusiveGateway | — | `getLicenciamento().getSituacao()` | — |
| T30D_CadastrarLAI | ServiceTask | `LicenciamentoIntegracaoLaiRN` | `cadastrarDemandaUnicaAnalise()` | — |
| T23S_GerarAPPCI | ServiceTask | `AnaliseLicenciamentoTecnicaDocumentoRN` | `incluirDocumentoAPPCI()` + `incluirDocumentoComplementarAnalise()` | — |
| T24S_ConcluirDeferPSPCIM | ServiceTask | `AnaliseLicenciamentoTecnicaHomRN` | `deferir()` (PSPCIM) | `POST /adm/analise-tecnica-hom/{id}/deferir` |
| End_CIA | EndEvent | — | — | — |
| End_CA | EndEvent | — | — | — |
| End_APPCI | EndEvent | — | — | — |
| End_Cancelado | EndEvent | — | — | — |

---

*Documento gerado em 2026-03-09*
*Referência: arquivo `P04_AnaliseTecnica_ATEC_StackAtual.bpmn`*
*Projeto: Licitação SOL — CBM-RS*
