# Descritivo do Fluxo BPMN — P13: Jobs Automáticos do Sistema
## Stack Atual (Java EE 7 · EJB 3.2 · Oracle · WildFly)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P13 — Jobs Automáticos do Sistema (Renovação de Alvarás)
**Arquivo BPMN:** `P13_JobsAutomaticos_StackAtual.bpmn`
**Data:** 2026-03-16
**Regras de Negócio cobertas:** RN-121 a RN-140

---

## Sumário

1. [Visão geral do modelo](#1-visão-geral-do-modelo)
2. [Decisão de estrutura: três pools independentes](#2-decisão-de-estrutura-três-pools-independentes)
3. [Pool 1 — Rotina Diária de Alvarás (00:01)](#3-pool-1--rotina-diária-de-alvarás-0001)
   - 3.1 [Timer Start Event](#31-timer-start-event-start_rotinadiaria)
   - 3.2 [ST_ConsultaAlvarasVencidos](#32-service-task-st_consultaalvarasvencidos--p13-a)
   - 3.3 [GW_TemAlvaraVencido](#33-gateway-exclusivo-gw_temalvaravencido)
   - 3.4 [SP_ProcessaAlvara — Sub-processo Multi-instance](#34-sub-processo-multi-instance-sp_processaalvara--p13-a)
   - 3.5 [GW_JoinAlvara](#35-gateway-exclusivo-de-junção-gw_joinalvara)
   - 3.6 [ST_NotificaAVencer90](#36-service-task-st_notificaavencer90--p13-b)
   - 3.7 [ST_NotificaAVencer59](#37-service-task-st_notificaavencer59--p13-b)
   - 3.8 [ST_NotificaAVencer29](#38-service-task-st_notificaavencer29--p13-b)
   - 3.9 [ST_NotificaVencidos](#39-service-task-st_notificavencidos--p13-c)
   - 3.10 [ST_RegistraRotina](#310-service-task-st_registrarotina)
   - 3.11 [End Event](#311-end-event-end_rotinadiaria)
4. [Pool 2 — Envio de Notificações por E-mail (00:31)](#4-pool-2--envio-de-notificações-por-e-mail-0031)
   - 4.1 [Timer Start Event](#41-timer-start-event-start_envioemails)
   - 4.2 [ST_ConsultaNotificacoesPendentes](#42-service-task-st_consultanotificacoespendentes)
   - 4.3 [GW_TemNotificacao](#43-gateway-exclusivo-gw_temnotificacao)
   - 4.4 [SP_ProcessaNotificacoes — Sub-processo Multi-instance](#44-sub-processo-multi-instance-sp_processanotificacoes--p13-d)
   - 4.5 [ST_RegistraRotinaEmail](#45-service-task-st_registrarotinaemail)
   - 4.6 [End Event](#46-end-event-end_envioemails)
5. [Pool 3 — Verificação de Pagamento Banrisul (a cada 12h)](#5-pool-3--verificação-de-pagamento-banrisul-a-cada-12h)
   - 5.1 [Timer Start Event](#51-timer-start-event-start_banrisul)
   - 5.2 [ST_BuscaArquivosCNAB](#52-service-task-st_buscaarquivoscnab)
   - 5.3 [GW_TemArquivoCNAB](#53-gateway-exclusivo-gw_temarquivocnab)
   - 5.4 [SP_ProcessaArquivoCNAB — Sub-processo Multi-instance Parallel](#54-sub-processo-multi-instance-parallel-sp_processaarquivocnab--p13-e)
   - 5.5 [End Event](#55-end-event-end_banrisul)
6. [Tabela de rastreabilidade](#6-tabela-de-rastreabilidade)
7. [Justificativas consolidadas de modelagem](#7-justificativas-consolidadas-de-modelagem)

---

## 1. Visão geral do modelo

O BPMN do processo P13 representa o conjunto de **jobs automáticos agendados** que sustentam o ciclo de renovação de alvarás (APPCIs) no SOL. Diferentemente de todos os processos anteriores (P01–P12), **P13 não possui User Tasks nem participação humana direta**: todo o fluxo é disparado por eventos de tempo e executado pela infraestrutura do servidor de aplicação WildFly, sem nenhuma autenticação OAuth2/OIDC e sem endpoints REST de entrada.

O modelo é organizado como uma **colaboração BPMN 2.0** (`<bpmn:collaboration id="Collaboration_P13">`) contendo **três pools independentes**, cada um representando um agrupamento de jobs com o mesmo agendamento de timer. Essa colaboração não possui Message Flows entre os pools, pois os três conjuntos de jobs são completamente independentes entre si do ponto de vista de dados e transações.

A adoção de pools independentes em vez de um pool único com múltiplos start events reflete a realidade técnica: cada `@Schedule` é um método distinto no EJBTimerService, com contexto transacional, escopo de execução e responsabilidade completamente separados.

---

## 2. Decisão de estrutura: três pools independentes

### Por que três pools?

Na implementação Java, o `EJBTimerService` declara **três métodos** anotados com `@Schedule` com agendamentos distintos:

| Pool no BPMN | Método Java | Agendamento | Jobs contidos |
|---|---|---|---|
| Pool 1 — `Pool_RotinaDiaria` | `notificaAlvarasVencimento()` | `hour="0", minute="1"` — 00:01 diário | P13-A, P13-B, P13-C |
| Pool 2 — `Pool_EnvioEmails` | `enviarNotificacaoLicenciamento()` | `hour="0", minute="31"` — 00:31 diário | P13-D |
| Pool 3 — `Pool_Banrisul` | `verificaPagamentoBanrisul()` | `minute="0", hour="*/12"` — a cada 12h | P13-E |

Colocar esses três grupos em um único pool violaria a fidelidade ao modelo de execução real: cada `@Schedule` abre uma transação e executa independentemente dos demais. Em BPMN 2.0, um processo com múltiplos Timer Start Events independentes representa exatamente essa separação. A opção por três pools distintos, cada qual com seu próprio processo BPMN, torna o diagrama mais legível e facilita a manutenção isolada de cada grupo de jobs.

### Por que sub-processos expanded multi-instance?

Para os trechos onde o sistema itera sobre uma lista de elementos (lista de licenciamentos vencidos, fila de notificações, lista de arquivos CNAB), optou-se por **sub-processos expanded** com marcação multi-instance (`<bpmn:multiInstanceLoopCharacteristics>`). A razão é dupla:

1. **Fidelidade ao código:** os três jobs utilizam laços `for` ou iterações funcionais, processando cada elemento de forma independente. O sub-processo multi-instance é o elemento BPMN canonicamente correto para representar esse padrão.
2. **Visibilidade interna:** ao contrário de um sub-processo collapsed (caixa fechada), o sub-processo expanded exibe todos os elementos internos, permitindo que o diagrama sirva também como documentação de implementação, sem exigir que o leitor abra um segundo diagrama.

### Por que não Boundary Events de erro?

O modelo não utiliza `<bpmn:error>` nem Boundary Error Events. A razão é técnica e arquitetural: o tratamento de erros em P13 é feito inteiramente dentro do código Java (blocos `try/catch`). A estratégia de resiliência é diferente por job:

- **P13-A:** falha em um licenciamento não reverte os demais — garantido por `@TransactionAttribute(REQUIRES_NEW)` no container EJB (RN-139).
- **P13-D:** falha no envio SMTP é registrada como `ERRO` no banco e a notificação é reprocessada na execução seguinte (retry automático pelo próprio job — RN-135).
- **P13-E:** falha no processamento CNAB é logada e o arquivo permanece no diretório de entrada para reprocessamento (RN-136).

Adicionar Boundary Error Events ao BPMN criaria uma falsa impressão de que o processo escalonaria o erro para um tratador BPMN externo, o que não ocorre. Além disso, o erro verificado no arquivo P12 (elementos `<bpmn:error>` posicionados incorretamente dentro de `<bpmn:process>` em vez de dentro de `<bpmn:definitions>`) reforçou a decisão de eliminar completamente esses elementos no P13.

---

## 3. Pool 1 — Rotina Diária de Alvarás (00:01)

**Nome no BPMN:** `Pool_RotinaDiaria`
**Processo:** `Process_P13_RotinaDiaria`
**Método Java:** `EJBTimerService.notificaAlvarasVencimento()`
**Raias:** `Lane_EJBTimer_A` (orquestração) · `Lane_LicenciamentoRN` (lógica de negócio)

Este pool é o mais complexo do modelo. Ele contém os jobs P13-A (atualização de situação), P13-B (notificação de vencimento próximo em três horizontes temporais) e P13-C (notificação pós-vencimento), que são executados sequencialmente dentro de um único disparo de timer às 00:01.

A raia `Lane_EJBTimer_A` representa o `EJBTimerService`, responsável pelo disparo do timer e pelo sequenciamento de alto nível. A raia `Lane_LicenciamentoRN` reúne os EJBs stateless que executam a lógica real: `LicenciamentoBD`, `LicenciamentoRN`, `AppciRN` e `RotinaRN`.

---

### 3.1 Timer Start Event — `Start_RotinaDiaria`

**Raia:** `Lane_EJBTimer_A`
**Cron expression (Quartz/Quartz-like):** `0 1 0 * * ?` (equivalente ao `@Schedule(hour="0", minute="1")`)

O Timer Start Event representa o disparo automático do método `notificaAlvarasVencimento()` pelo EJB Timer Service do WildFly. Ele é configurado com `persistent=false`, o que significa que o timer **não sobrevive a reinicializações do servidor**: se o WildFly for reinicializado antes das 00:01, o timer será recriado na inicialização e o job executará na próxima ocorrência das 00:01 — não haverá tentativa de compensar execuções perdidas (RN-137).

**Motivo da escolha:** o Timer Start Event é o elemento BPMN 2.0 semanticamente correto para representar um processo que é iniciado exclusivamente por um evento de tempo recorrente, sem nenhuma mensagem ou sinal externo. A documentação `<bpmn:documentation>` desse elemento registra a anotação Java completa e a sequência interna das chamadas, servindo de referência para operação e manutenção.

---

### 3.2 Service Task — `ST_ConsultaAlvarasVencidos` (P13-A)

**Raia:** `Lane_LicenciamentoRN`
**Classe:** `LicenciamentoBD`
**Método:** `consultaAlvaraVencido()`
**Transação:** `@TransactionAttribute(REQUIRED)`

Esta service task representa a primeira operação real do job P13-A: consultar no banco Oracle todos os licenciamentos elegíveis para vencimento. A query utiliza Hibernate Criteria API com dois critérios combinados:

- **Critério principal (TB_LICENCIAMENTO):** `DSC_SITUACAO = 'ALVARA_VIGENTE'`
- **Subcritério correlacionado (TB_APPCI):** `DAT_VALIDADE <= SYSDATE` e `IND_VERSAO_VIGENTE = 'S'`

O campo `IND_VERSAO_VIGENTE` é do tipo `CHAR(1)` no Oracle e é mapeado via `SimNaoBooleanConverter`. Por isso, a query Hibernate usa a String literal `"S"` e não o booleano Java `true`. Esse detalhe é documentado explicitamente no `<bpmn:documentation>` da task, pois é uma armadilha recorrente para desenvolvedores que desconhecem o conversor (RN-122).

O resultado é uma `List<LicenciamentoED>` que alimenta a etapa seguinte.

**Motivo da escolha de Service Task:** a operação é executada automaticamente pelo sistema, sem interação humana. O atributo `camunda:class` registra a classe responsável, tornando o diagrama rastreável ao código-fonte.

---

### 3.3 Gateway Exclusivo — `GW_TemAlvaraVencido`

**Condições:**
- `[Sim] lista não vazia` → `SF_GW_ProcessaAlvara` — entra no sub-processo multi-instance
- `[Não] lista vazia` → `SF_GW_SemAlvara` — pula P13-A, vai direto para as notificações

Este gateway verifica se `consultaAlvaraVencido()` retornou algum licenciamento. A separação em dois caminhos é necessária porque o sub-processo multi-instance não deve ser instanciado com uma coleção vazia — isso causaria comportamento indefinido em alguns motores BPMN e tornaria o modelo impreciso (RN-121).

**Motivo da escolha de Gateway Exclusivo (XOR):** exatamente um dos dois caminhos é tomado — ou há alvarás vencidos ou não há. Um gateway paralelo seria semanticamente incorreto, pois ambas as saídas nunca são ativadas simultaneamente.

---

### 3.4 Sub-processo Multi-instance — `SP_ProcessaAlvara` (P13-A)

**Tipo:** Sequential Multi-instance (`isSequential="true"`)
**Iteração:** uma instância por `LicenciamentoED` da lista retornada por `consultaAlvaraVencido()`
**Transação por instância:** `@TransactionAttribute(REQUIRES_NEW)` implícito pelo container EJB (RN-139)

Este sub-processo expanded representa o laço `for (LicenciamentoED obj : alvaras)` do método `verificaValidadeAlvara()`. Para cada licenciamento vencido identificado, quatro operações são executadas sequencialmente dentro do sub-processo.

A escolha por **sequential** (em vez de parallel) reflete o código real: o laço Java é sequencial. Um parallel multi-instance geraria transações simultâneas no Oracle, com risco de conflito de lock nas linhas de `TB_LICENCIAMENTO`. O isolamento de transação por instância garante que uma falha em um licenciamento não reverte as alterações já confirmadas nos licenciamentos anteriores (RN-139).

#### 3.4.1 — `ST_RegistraHistSituacao`

**Classe:** `LicenciamentoSituacaoHistRN`
**Método:** `inclui(LicenciamentoSituacaoHistED)`

Registra a transição de situação como auditoria permanente em `TB_LICENCIAMENTO_SITUACAO_HIST`. O objeto é construído com o builder `BuilderLicenciamentoSituacaoHistED`, capturando:

- `situacaoAnterior = ALVARA_VIGENTE`
- `situacaoAtual = ALVARA_VENCIDO`
- `dthSituacaoAtual = Calendar.getInstance()` (momento atual)
- `dthSituacaoAnterior = obj.getCtrDthAtu()` (timestamp da última alteração do licenciamento)

**Motivo de ser a primeira task:** o histórico deve ser gravado antes da alteração da entidade principal, garantindo que, em caso de falha parcial, o estado anterior seja sempre rastreável. A ordem é parte do padrão de auditoria do sistema SOL: registrar o histórico com a situação anterior e só depois alterar a entidade (RN-123).

#### 3.4.2 — `ST_AlteraSituacaoVencido`

**Classe:** `LicenciamentoRN`
**Método:** `altera(LicenciamentoED)` via `entityManager.merge()`

Altera o campo `DSC_SITUACAO` em `TB_LICENCIAMENTO` de `ALVARA_VIGENTE` para `ALVARA_VENCIDO`. Esta é a transição principal de estado do licenciamento (RN-121). O `entityManager.merge()` gera um `UPDATE TB_LICENCIAMENTO SET DSC_SITUACAO = 'ALVARA_VENCIDO', CTR_DTH_ATU = SYSTIMESTAMP WHERE ID = :id`.

**Motivo de ser a segunda task (após o histórico):** garantir que, se o merge falhar, o registro de histórico já tenha sido gravado e possa ser consultado para diagnóstico da falha.

#### 3.4.3 — `ST_MarcaAppciNaoVigente`

**Classe:** `AppciRN`
**Método:** `alteraIndVersaoVigenteAppciVencido(LicenciamentoED)`

Itera sobre todos os APPCIs associados ao licenciamento e marca cada um com `IND_VERSAO_VIGENTE = 'N'` (via `SimNaoBooleanConverter`). O código Java usa `setIndVersaoVigente("N")`, não um booleano, pois o campo no Oracle é `CHAR(1)` (RN-124).

**Motivo:** o APPCI vencido não deve ser considerado vigente em nenhuma outra consulta do sistema. Marcar explicitamente a não-vigência é necessário porque queries em `TB_APPCI` frequentemente filtram por `IND_VERSAO_VIGENTE = 'S'` para localizar o APPCI ativo de um licenciamento — sem essa marcação, o APPCI vencido continuaria aparecendo como vigente.

#### 3.4.4 — `ST_MarcaDocCompNaoVigente`

**Classe:** `AppciDocComplementarRN`
**Método:** `alteraIndVersaoVigenteAppciDocComplementarVencido(LicenciamentoED)`

Análogo ao passo anterior, mas opera em `TB_APPCI_DOC_COMPLEMENTAR`. Documentos complementares do APPCI (ARTs, memoriais descritivos) também perdem a vigência junto com o APPCI principal (RN-124).

**Motivo de ser a última task do sub-processo:** os documentos complementares são dependentes do APPCI. Somente após o APPCI ter sido marcado como não-vigente faz sentido propagar essa marcação para seus documentos associados, preservando a coerência da hierarquia de dados.

---

### 3.5 Gateway Exclusivo de Junção — `GW_JoinAlvara`

Este gateway XOR reunifica os dois caminhos que saem de `GW_TemAlvaraVencido`:
- O caminho que passou pelo sub-processo `SP_ProcessaAlvara` (havia alvarás vencidos).
- O caminho que pulou o sub-processo (não havia alvarás vencidos — `SF_GW_SemAlvara`).

A partir deste ponto, o fluxo é único e sempre executa as quatro service tasks de notificação (P13-B e P13-C), independentemente de ter havido ou não alvarás vencidos a processar.

**Motivo de usar XOR Join:** exatamente um dos dois caminhos de entrada estará ativo em qualquer execução. Um Parallel Join bloquearia aguardando ativação de ambas as entradas, o que nunca ocorreria — o processo ficaria suspenso indefinidamente.

---

### 3.6 Service Task — `ST_NotificaAVencer90` (P13-B)

**Classe:** `LicenciamentoRN`
**Método:** `notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLICITAR_RENOVACAO_90)`
**Transação:** `@TransactionAttribute(REQUIRES_NEW)`

Esta service task representa a primeira chamada de notificação do job P13-B. Ela identifica todos os licenciamentos com APPCI vigente cuja `DAT_VALIDADE` esteja **entre 90 e 91 dias a partir de hoje** e que ainda não tenham recebido o marco `NOTIFICACAO_SOLICITAR_RENOVACAO_90` após a última execução bem-sucedida da rotina.

O mecanismo de controle é o **baseline temporal** (RN-140): o método consulta `TB_ROTINA` para obter o `DTH_FIM_EXECUCAO` da última rotina `GERAR_NOTIFICACAO_ALVARA_VENCIDO` com situação `CONCLUIDA`. Este timestamp é o `dataBase` que define a janela de processamento — licenciamentos cujo marco de interesse já foi registrado **após** o `dataBase` são ignorados, evitando re-notificação. Se nenhuma execução anterior for encontrada, o `dataBase` é definido como `SYSDATE - 1`.

Para cada licenciamento elegível, o método:
1. Cria um registro em `TB_LICENCIAMENTO_NOTIFICACAO` com `DSC_SITUACAO_ENVIO = 'PENDENTE'` — consumido pelo Pool 2 (P13-D).
2. Registra o marco `NOTIFICACAO_SOLICITAR_RENOVACAO_90` em `TB_LICENCIAMENTO_MARCO`.

A notificação por e-mail **não é enviada aqui** — apenas enfileirada. O envio real ocorre no Pool 2 (RN-125).

**Motivo da task separada para cada horizonte temporal:** cada chamada a `notificaAlvaraAVencer` executa em `@TransactionAttribute(REQUIRES_NEW)`, portanto em transação independente. Se a notificação de 90 dias falhar, as de 59 e 29 dias ainda serão executadas. Representar cada chamada como uma service task distinta torna explícita essa separação transacional no diagrama.

---

### 3.7 Service Task — `ST_NotificaAVencer59` (P13-B)

**Método:** `notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_59)`

Idêntico ao passo anterior, mas para o horizonte de **59 dias** antes do vencimento. O nome do marco (`PRAZO_VENCIDO_59`) indica que, neste ponto, o prazo preferencial de solicitação de renovação (60 dias) já passou — esta é uma notificação de urgência moderada.

A query Oracle filtra `DAT_VALIDADE BETWEEN SYSDATE + 59 AND SYSDATE + 60`. A mesma lógica de baseline temporal é aplicada (RN-126, RN-140).

---

### 3.8 Service Task — `ST_NotificaAVencer29` (P13-B)

**Método:** `notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_SOLIC_RENOV_PRAZO_VENCIDO_29)`

Horizonte de **29 dias** antes do vencimento. Notificação crítica — o alvará vencerá em menos de um mês e o processo de renovação ainda não foi iniciado (RN-127, RN-140).

---

### 3.9 Service Task — `ST_NotificaVencidos` (P13-C)

**Método:** `notificaAlvaraAVencer(TipoMarco.NOTIFICACAO_ALVARA_VENCIDO)`

Esta service task representa o job P13-C. Diferentemente das três anteriores (que notificam sobre vencimento **futuro**), esta notifica sobre vencimento **ocorrido**: alvarás cujo `DSC_SITUACAO` já foi transitado para `ALVARA_VENCIDO` pelo job P13-A e que ainda não receberam o marco `NOTIFICACAO_ALVARA_VENCIDO` após o último baseline temporal.

A lógica interna é a mesma: enfileira uma notificação em `TB_LICENCIAMENTO_NOTIFICACAO` com status `PENDENTE` e registra o marco. O envio ocorre pelo Pool 2 (RN-128).

**Motivo de estar no Pool 1 e não no Pool 2:** P13-C é parte do método `notificaAlvarasVencimento()` do `EJBTimerService` — o mesmo método que dispara P13-A e P13-B. O Pool 2 é um job **separado**, disparado 30 minutos depois, responsável apenas pelo envio SMTP das notificações enfileiradas. Essa separação de responsabilidades é uma decisão arquitetural do sistema: a geração das notificações (quais licenciamentos envolver, qual marco registrar) ocorre às 00:01; o envio por SMTP (que depende de infraestrutura de e-mail externa) é feito às 00:31 como processo independente, com retry independente.

---

### 3.10 Service Task — `ST_RegistraRotina`

**Classe:** `RotinaRN`
**Método:** `iniciaRotinaDeAlvaraVencido()` (registra conclusão da rotina)

Registra em `TB_ROTINA` que a rotina `GERAR_NOTIFICACAO_ALVARA_VENCIDO` foi concluída, preenchendo `DTH_FIM_EXECUCAO = SYSTIMESTAMP` e `DSC_SITUACAO = 'CONCLUIDA'`.

Este timestamp é o **baseline temporal** que será consultado na próxima execução pelas service tasks de notificação (P13-B e P13-C) para determinar a janela de processamento (RN-140). É um mecanismo crítico de idempotência: mesmo que o servidor tenha ficado offline por vários dias, na próxima execução o sistema processará apenas licenciamentos cujos marcos não foram registrados desde a última execução bem-sucedida — sem duplicar notificações já enfileiradas.

**Motivo de ser a última task antes do End Event:** o registro de conclusão só faz sentido após todas as operações de notificação terem sido tentadas. Registrar o timestamp antes colocaria um `DTH_FIM_EXECUCAO` prematuro, que poderia ser usado como baseline por uma execução seguinte antes de o job ter concluído de fato — causando janelas cegas de notificação.

---

### 3.11 End Event — `End_RotinaDiariaOk`

**Raia:** `Lane_EJBTimer_A`

Encerra a execução do método `notificaAlvarasVencimento()`. O container EJB libera todos os recursos transacionais. Não há ação específica neste evento — ele marca o término normal do processo BPMN e serve como ponto de conclusão visual do diagrama.

---

## 4. Pool 2 — Envio de Notificações por E-mail (00:31)

**Nome no BPMN:** `Pool_EnvioEmails`
**Processo:** `Process_P13_EnvioEmails`
**Método Java:** `EJBTimerService.enviarNotificacaoLicenciamento()`
**Raias:** `Lane_EJBTimer_D` · `Lane_NotificacaoRN_D`

Este pool representa o job P13-D, responsável pelo envio efetivo por SMTP das notificações geradas pelo Pool 1. É disparado 30 minutos depois (00:31) para garantir que o Pool 1 tenha concluído antes de o envio ser tentado.

---

### 4.1 Timer Start Event — `Start_EnvioEmails`

**Cron expression:** `0 31 0 * * ?`
**Anotação Java:** `@Schedule(hour="0", minute="31", persistent=false)`

Dispara diariamente às 00:31. O intervalo de 30 minutos em relação ao Pool 1 não é garantido por dependência BPMN (não há Message Flow entre os pools), mas por design de agendamento: na prática, o Pool 1 raramente leva mais de alguns minutos para executar, e os 30 minutos de margem são suficientes para cobrir picos de carga (RN-138).

---

### 4.2 Service Task — `ST_ConsultaNotificacoesPendentes`

**Classe:** `LicenciamentoNotificacaoRN`
**Método:** fase inicial de `enviarNotificacoesLicenciamentosPorEmail()`

Busca em `TB_LICENCIAMENTO_NOTIFICACAO` todos os registros com `DSC_SITUACAO_ENVIO IN ('PENDENTE', 'ERRO')`. O status `ERRO` está incluído para implementar o **retry automático**: notificações que falharam no envio SMTP em execuções anteriores são reprocessadas na próxima execução do job (RN-129, RN-135).

---

### 4.3 Gateway Exclusivo — `GW_TemNotificacao`

- `[Sim] lista não vazia` → entra no sub-processo `SP_ProcessaNotificacoes`
- `[Não] lista vazia` → segue diretamente para o End Event

Verifica se há notificações a processar. O raciocínio é o mesmo do `GW_TemAlvaraVencido` do Pool 1: o sub-processo multi-instance não deve ser instanciado com coleção vazia.

---

### 4.4 Sub-processo Multi-instance — `SP_ProcessaNotificacoes` (P13-D)

**Tipo:** Sequential Multi-instance (`isSequential="true"`)
**Iteração:** uma instância por `LicenciamentoNotificacaoED` da lista

O envio de e-mails é sequential para evitar sobrecarga do servidor SMTP e para que falhas individuais possam ser tratadas de forma isolada — um erro de SMTP em uma notificação não afeta o processamento das demais.

#### 4.4.1 — `ST_ResolveTemplate`

Resolve o template de e-mail com base no `TipoMarco` da notificação. Cada tipo de marco corresponde a um template distinto, populado com dados do licenciamento (número do PPCI, data de vencimento, dados do RT e RU) para gerar o corpo HTML do e-mail (RN-131).

**Motivo de ser etapa separada:** isolar a resolução do template do envio SMTP facilita o teste unitário de cada parte e permite que, em caso de falha na montagem do template, a notificação seja marcada como `ERRO` antes de qualquer operação de rede.

#### 4.4.2 — `ST_EnviaEmailSMTP`

**Componente:** JavaMail via JNDI `java:jboss/mail/Default` (configurado no WildFly)
**Operação:** `Session.getDefaultInstance()` → construção do `MimeMessage` → `Transport.send()`

Envia o e-mail ao RT e ao RU do licenciamento. Remetente, assunto e destinatários são derivados dos dados do licenciamento. A chamada ao servidor SMTP pode falhar por timeout, autenticação ou indisponibilidade (RN-130).

#### 4.4.3 — `GW_EnvioOK`

**Tipo:** Gateway Exclusivo
- `[Sucesso]` → `ST_MarcarEnviado`
- `[Falha SMTP]` → `ST_MarcarErro`

Representa o `try/catch` em torno do `Transport.send()`. Se ocorrer qualquer exceção, o fluxo segue para marcar a notificação como `ERRO`; se o envio for bem-sucedido, segue para `ENVIADO`.

**Motivo de usar Gateway e não Boundary Event:** o erro é tratado internamente no mesmo fluxo da iteração — não há escalonamento para fora do sub-processo. Um Boundary Event seria semanticamente incorreto, pois interromperia o sub-processo ao invés de registrar o erro e continuar para a próxima notificação.

#### 4.4.4 — `ST_MarcarEnviado` e `ST_MarcarErro`

**Sucesso:** `UPDATE TB_LICENCIAMENTO_NOTIFICACAO SET DSC_SITUACAO_ENVIO = 'ENVIADO', DTH_ENVIO = SYSTIMESTAMP WHERE ID = :id`

**Falha:** `UPDATE TB_LICENCIAMENTO_NOTIFICACAO SET DSC_SITUACAO_ENVIO = 'ERRO', DSC_ERRO = :mensagemExcecao WHERE ID = :id`

O registro da mensagem de exceção é fundamental para diagnóstico operacional. A notificação com status `ERRO` será automaticamente reprocessada na próxima execução do job P13-D (RN-129, RN-135).

---

### 4.5 Service Task — `ST_RegistraRotinaEmail`

Registra em `TB_ROTINA` a conclusão do job P13-D com `DTH_FIM_EXECUCAO`. Este timestamp pode ser consultado por monitoramento operacional para verificar que o job de e-mails está executando dentro do intervalo esperado.

---

### 4.6 End Event — `End_EnvioEmails`

Encerra a execução do método `enviarNotificacaoLicenciamento()`. Todas as notificações foram processadas — enviadas com sucesso ou marcadas como erro para retry na próxima execução.

---

## 5. Pool 3 — Verificação de Pagamento Banrisul (a cada 12h)

**Nome no BPMN:** `Pool_Banrisul`
**Processo:** `Process_P13_Banrisul`
**Método Java:** `EJBTimerService.verificaPagamentoBanrisul()`
**Raias:** `Lane_EJBTimer_E` · `Lane_PagamentoBoletoRN`

Este pool representa o job P13-E, responsável por processar arquivos CNAB 240 do Banrisul para confirmar pagamentos de boletos emitidos pelo sistema SOL. É disparado a cada 12 horas (00:00 e 12:00) porque o processamento de pagamentos é sensível ao tempo — um pagamento confirmado mais cedo desbloqueia o andamento do licenciamento mais rapidamente.

---

### 5.1 Timer Start Event — `Start_Banrisul`

**Cron expression:** `0 0 */12 * * ?`
**Anotação Java:** `@Schedule(minute="0", hour="*/12", persistent=false)`

Dispara às 00:00 e às 12:00 todos os dias. A frequência de 12 horas é justificada pelo prazo de compensação bancária — os arquivos CNAB de retorno do Banrisul são gerados em dois lotes diários (RN-136).

---

### 5.2 Service Task — `ST_BuscaArquivosCNAB`

**Classe:** `PagamentoBoletoRN`
**Método:** fase inicial de `verificaPagamentoBanrisul()`

Lista os arquivos CNAB 240 disponíveis no diretório configurado (propriedade de sistema ou JNDI) que ainda não foram processados. O Banrisul disponibiliza esses arquivos via SFTP ou diretório de rede compartilhado (RN-136).

---

### 5.3 Gateway Exclusivo — `GW_TemArquivoCNAB`

- `[Sim] arquivos disponíveis` → entra no sub-processo `SP_ProcessaArquivoCNAB`
- `[Não] nenhum arquivo` → encerra

Se nenhum arquivo CNAB estiver disponível, o job simplesmente encerra sem fazer nada. Esse é o comportamento esperado em boa parte das execuções das 12:00, quando os arquivos do Banrisul podem não ter chegado ainda.

---

### 5.4 Sub-processo Multi-instance Parallel — `SP_ProcessaArquivoCNAB` (P13-E)

**Tipo:** Parallel Multi-instance (`isSequential="false"`)
**Iteração:** uma instância por arquivo CNAB disponível

Diferentemente dos sub-processos dos Pools 1 e 2, este é **parallel** — múltiplos arquivos CNAB podem ser processados simultaneamente. Isso é seguro porque cada arquivo corresponde a um lote de boletos distinto, sem sobreposição de dados entre arquivos. O paralelismo reduz o tempo total de processamento quando múltiplos arquivos estão acumulados (RN-136).

#### 5.4.1 — `ST_ParseaCNAB`

Lê e faz o parsing do arquivo CNAB 240 conforme o layout padrão Febraban/Banrisul, segmentos T e U. Os campos posicionais são extraídos linha a linha, produzindo uma lista de registros de pagamento confirmado: nosso número (identificador do boleto no SOL), valor pago e data de pagamento.

#### 5.4.2 — `ST_ProcessaPagamentos`

Para cada registro de pagamento confirmado extraído do arquivo CNAB:
1. Localiza o boleto em `TB_PAGAMENTO_BOLETO` pelo nosso número.
2. Atualiza `DSC_SITUACAO = 'PAGO'` e `DTH_PAGAMENTO` com a data do arquivo CNAB.
3. Avança a situação do licenciamento associado conforme o fluxo de renovação.
4. Registra marco de pagamento confirmado em `TB_LICENCIAMENTO_MARCO`.

(RN-133, RN-134)

#### 5.4.3 — `ST_MoveArquivoProcessado`

Após o processamento bem-sucedido, move o arquivo CNAB do diretório de entrada para um diretório de arquivos processados. Isso evita reprocessamento na próxima execução do job. Se ocorrer erro durante o processamento, o arquivo permanece no diretório de entrada e será reprocessado na execução seguinte (RN-136).

**Motivo de ser a última task:** o arquivo só deve ser movido após todos os pagamentos terem sido processados com sucesso. Mover antes exporia o sistema a perda de registros de pagamento em caso de falha parcial na leitura do arquivo.

---

### 5.5 End Event — `End_Banrisul`

Encerra a execução do método `verificaPagamentoBanrisul()`. Todos os arquivos CNAB disponíveis foram processados e movidos. Os pagamentos confirmados foram registrados e as situações dos licenciamentos avançaram conforme a lógica de renovação.

---

## 6. Tabela de Rastreabilidade

| Elemento BPMN | ID no XML | Classe Java | Método | Tabela Oracle | RNs |
|---|---|---|---|---|---|
| Timer Start Pool 1 | `Start_RotinaDiaria` | `EJBTimerService` | `notificaAlvarasVencimento()` | — | RN-137 |
| Consultar alvarás vencidos | `ST_ConsultaAlvarasVencidos` | `LicenciamentoBD` | `consultaAlvaraVencido()` | `TB_LICENCIAMENTO`, `TB_APPCI` | RN-121, RN-122 |
| Gateway alvarás existem? | `GW_TemAlvaraVencido` | — | — | — | RN-121 |
| Sub-processo por alvará | `SP_ProcessaAlvara` | `LicenciamentoRN` | `verificaValidadeAlvara()` | (múltiplas) | RN-121 a 124, RN-139 |
| Registrar histórico situação | `ST_RegistraHistSituacao` | `LicenciamentoSituacaoHistRN` | `inclui()` | `TB_LICENCIAMENTO_SITUACAO_HIST` | RN-123 |
| Atualizar situação VENCIDO | `ST_AlteraSituacaoVencido` | `LicenciamentoRN` | `altera()` | `TB_LICENCIAMENTO` | RN-121 |
| Marcar APPCIs não vigentes | `ST_MarcaAppciNaoVigente` | `AppciRN` | `alteraIndVersaoVigenteAppciVencido()` | `TB_APPCI` | RN-124 |
| Marcar Docs não vigentes | `ST_MarcaDocCompNaoVigente` | `AppciDocComplementarRN` | `alteraIndVersaoVigenteAppciDocComplementarVencido()` | `TB_APPCI_DOC_COMPLEMENTAR` | RN-124 |
| Gateway XOR Join | `GW_JoinAlvara` | — | — | — | — |
| Notificar 90 dias | `ST_NotificaAVencer90` | `LicenciamentoRN` | `notificaAlvaraAVencer(90)` | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` | RN-125, RN-140 |
| Notificar 59 dias | `ST_NotificaAVencer59` | `LicenciamentoRN` | `notificaAlvaraAVencer(59)` | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` | RN-126, RN-140 |
| Notificar 29 dias | `ST_NotificaAVencer29` | `LicenciamentoRN` | `notificaAlvaraAVencer(29)` | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` | RN-127, RN-140 |
| Notificar vencidos | `ST_NotificaVencidos` | `LicenciamentoRN` | `notificaAlvaraAVencer(VENCIDO)` | `TB_LICENCIAMENTO_NOTIFICACAO`, `TB_LICENCIAMENTO_MARCO` | RN-128, RN-140 |
| Registrar rotina Pool 1 | `ST_RegistraRotina` | `RotinaRN` | `iniciaRotinaDeAlvaraVencido()` | `TB_ROTINA` | RN-140 |
| Timer Start Pool 2 | `Start_EnvioEmails` | `EJBTimerService` | `enviarNotificacaoLicenciamento()` | — | RN-138 |
| Consultar notificações pendentes | `ST_ConsultaNotificacoesPendentes` | `LicenciamentoNotificacaoRN` | `enviarNotificacoesLicenciamentosPorEmail()` | `TB_LICENCIAMENTO_NOTIFICACAO` | RN-129, RN-135 |
| Sub-processo por notificação | `SP_ProcessaNotificacoes` | `LicenciamentoNotificacaoRN` | (interno) | `TB_LICENCIAMENTO_NOTIFICACAO` | RN-129 a 135 |
| Resolver template e-mail | `ST_ResolveTemplate` | `LicenciamentoNotificacaoRN` | resolveTemplate() | — | RN-131 |
| Enviar e-mail SMTP | `ST_EnviaEmailSMTP` | JavaMail / JNDI | `Transport.send()` | — | RN-130 |
| Gateway envio OK? | `GW_EnvioOK` | — | — | — | RN-129, RN-135 |
| Marcar como ENVIADO | `ST_MarcarEnviado` | `LicenciamentoNotificacaoRN` | `altera()` | `TB_LICENCIAMENTO_NOTIFICACAO` | RN-129 |
| Marcar como ERRO | `ST_MarcarErro` | `LicenciamentoNotificacaoRN` | `altera()` | `TB_LICENCIAMENTO_NOTIFICACAO` | RN-135 |
| Registrar rotina Pool 2 | `ST_RegistraRotinaEmail` | `RotinaRN` | (registraConclusao) | `TB_ROTINA` | — |
| Timer Start Pool 3 | `Start_Banrisul` | `EJBTimerService` | `verificaPagamentoBanrisul()` | — | RN-136 |
| Buscar arquivos CNAB | `ST_BuscaArquivosCNAB` | `PagamentoBoletoRN` | `verificaPagamentoBanrisul()` | — | RN-136 |
| Gateway CNAB existem? | `GW_TemArquivoCNAB` | — | — | — | RN-136 |
| Sub-processo por arquivo CNAB | `SP_ProcessaArquivoCNAB` | `PagamentoBoletoRN` | (interno) | `TB_PAGAMENTO_BOLETO`, `TB_LICENCIAMENTO`, `TB_LICENCIAMENTO_MARCO` | RN-133, RN-134, RN-136 |
| Parsear arquivo CNAB | `ST_ParseaCNAB` | `PagamentoBoletoRN` | parseaCNAB() | — | RN-136 |
| Processar pagamentos | `ST_ProcessaPagamentos` | `PagamentoBoletoRN` | processaPagamentos() | `TB_PAGAMENTO_BOLETO`, `TB_LICENCIAMENTO` | RN-133, RN-134 |
| Mover arquivo processado | `ST_MoveArquivoProcessado` | `PagamentoBoletoRN` | moveArquivo() | — | RN-136 |

---

## 7. Justificativas consolidadas de modelagem

### J1 — Três pools independentes em vez de um pool único

Os três métodos `@Schedule` do `EJBTimerService` têm agendamentos, responsabilidades e isolamento transacional completamente distintos. Representá-los em um único pool com múltiplos Timer Start Events violaria a separação de contextos e dificultaria a leitura do diagrama. Três pools tornam explícita a independência entre os agrupamentos de jobs e facilitam a manutenção isolada: uma equipe pode alterar o job P13-D sem precisar navegar pelo fluxo de P13-E.

### J2 — Sub-processos expanded em vez de collapsed

Os sub-processos `SP_ProcessaAlvara`, `SP_ProcessaNotificacoes` e `SP_ProcessaArquivoCNAB` são representados com elementos internos visíveis (expanded). Isso serve dupla função: (a) documenta a lógica interna de cada iteração diretamente no diagrama, e (b) permite que o revisor do BPMN verifique a ordem exata das operações sem precisar consultar o código-fonte separadamente.

### J3 — Sequential vs. Parallel multi-instance

- **P13-A e P13-D: sequential.** Os laços Java são sequenciais, e a sequencialidade no BPMN reflete isso com precisão. Paralelismo em P13-A criaria risco de deadlock no Oracle (múltiplas transações atualizando a mesma linha de `TB_LICENCIAMENTO` simultaneamente). Paralelismo em P13-D sobrecarregaria o servidor SMTP.
- **P13-E: parallel.** Arquivos CNAB distintos operam em conjuntos de boletos disjuntos — não há risco de conflito de dados entre eles. O paralelismo reduz o tempo total de processamento quando há múltiplos arquivos acumulados.

### J4 — Ausência de Boundary Error Events

P13 trata erros internamente via Java (try/catch, `@TransactionAttribute(REQUIRES_NEW)`, atualização de status no banco). Adicionar Boundary Error Events criaria falsa expectativa de tratamento BPMN externo. Adicionalmente, o posicionamento incorreto de `<bpmn:error>` dentro de `<bpmn:process>` — detectado como erro nas linhas 528–529 do BPMN do P12 — reforçou a decisão de não usar esses elementos no P13.

### J5 — Gateway exclusivo antes de cada sub-processo multi-instance

Um sub-processo multi-instance instanciado com coleção vazia tem comportamento indefinido em alguns motores BPMN e é considerado má prática de modelagem. Os gateways `GW_TemAlvaraVencido`, `GW_TemNotificacao` e `GW_TemArquivoCNAB` protegem os sub-processos contra essa condição, tornando o modelo robusto e portável entre diferentes implementações de motor BPMN.

### J6 — ST_RegistraRotina como última tarefa do Pool 1

O registro de conclusão em `TB_ROTINA` é feito por último, após todos os jobs P13-A, P13-B e P13-C terem sido executados. O timestamp `DTH_FIM_EXECUCAO` gerado é o baseline temporal usado pela **próxima execução** do pool para determinar quais licenciamentos já foram notificados (RN-140). Registrar esse timestamp antes da conclusão dos jobs produziria um baseline prematuro, com risco de lacunas de notificação.

### J7 — Duas raias por pool

Cada pool tem apenas duas raias: uma para o `EJBTimerService` (orquestrador/disparo do timer) e uma para os EJBs de negócio (`LicenciamentoRN`, `LicenciamentoNotificacaoRN`, `PagamentoBoletoRN`). Essa granularidade é suficiente para comunicar a separação de responsabilidades sem criar raias excessivas que tornariam o diagrama ilegível. Uma terceira raia para a camada de persistência (`LicenciamentoBD`) foi considerada e descartada, pois `LicenciamentoBD` é chamado internamente por `LicenciamentoRN` e não é um participante autônomo no fluxo BPMN.

### J8 — persistent=false documentado nos Timer Start Events

O atributo `persistent=false` dos timers EJB é documentado no `<bpmn:documentation>` do Timer Start Event de cada pool. Essa informação é operacionalmente crítica: reinicializações do WildFly durante a madrugada (janelas de manutenção) causam perda da execução do job naquele dia. A documentação no diagrama alerta a equipe de infraestrutura sobre essa limitação e a necessidade de monitorar `TB_ROTINA` para detectar execuções ausentes (RN-137).

---

*Documento gerado em 2026-03-16. Corresponde ao arquivo `P13_JobsAutomaticos_StackAtual.bpmn` e ao documento de requisitos `Requisitos_P13_JobsAutomaticos_StackAtual.md`. Regras de Negócio: RN-121 a RN-140.*
