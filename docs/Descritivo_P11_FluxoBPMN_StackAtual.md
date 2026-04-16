# Descritivo do Fluxo BPMN — P11: Pagamento e Geração de Boleto
## Sistema SOL — CBM-RS | Stack Atual Java EE

---

## Sumário

1. [Visão geral do processo](#1-visão-geral-do-processo)
2. [Estrutura do BPMN: pools, raias e participantes](#2-estrutura-do-bpmn-pools-raias-e-participantes)
3. [Pool P11-A — Fase 1: Pré-condições e validações (RN-090, RN-091, RN-092)](#3-pool-p11-a--fase-1-pré-condições-e-validações)
4. [Pool P11-A — Fase 2: Cálculo da taxa e montagem do boleto (RN-093 a RN-100)](#4-pool-p11-a--fase-2-cálculo-da-taxa-e-montagem-do-boleto)
5. [Pool P11-A — Fase 3: Integração com PROCERGS/Banrisul (RN-101)](#5-pool-p11-a--fase-3-integração-com-procergsbanrisul)
6. [Pool P11-A — Fase 4: Marco, download e pagamento externo (RN-102, RN-103)](#6-pool-p11-a--fase-4-marco-download-e-pagamento-externo)
7. [Pool P11-B — Fluxo 1: Job de vencimento de boletos (RN-104)](#7-pool-p11-b--fluxo-1-job-de-vencimento-de-boletos)
8. [Pool P11-B — Fluxo 2: Job de confirmação de pagamento CNAB 240 (RN-105 a RN-108)](#8-pool-p11-b--fluxo-2-job-de-confirmação-de-pagamento-cnab-240)
9. [Justificativas das decisões de modelagem](#9-justificativas-das-decisões-de-modelagem)
10. [Diagrama de estados das entidades principais](#10-diagrama-de-estados-das-entidades-principais)
11. [Referência cruzada: elementos BPMN x classes Java EE](#11-referência-cruzada-elementos-bpmn-x-classes-java-ee)
12. [Tabelas de banco de dados afetadas por processo](#12-tabelas-de-banco-de-dados-afetadas-por-processo)

---

## 1. Visão geral do processo

O processo P11 — **Pagamento e Geração de Boleto** — é o mecanismo transversal pelo qual o sistema SOL cobra do cidadão as taxas devidas pelo licenciamento. É chamado de processo transversal porque não pertence a um único ponto do ciclo de vida do licenciamento: ele é acionado toda vez que o licenciamento alcança um dos três estados de aguardo de pagamento, independentemente de qual processo anterior o conduziu a esse estado.

O P11 tem natureza **assíncrona**: o cidadão gera e paga o boleto em um fluxo (P11-A), mas a confirmação do pagamento ocorre horas depois, por um job automático (P11-B), sem qualquer interação do cidadão. Esta assincronicidade é uma característica central da arquitetura do processo e está explicitamente documentada no BPMN.

### Estados disparadores

O P11-A é acionado quando o licenciamento alcança:

| `SituacaoLicenciamento`           | Tipo de boleto gerado                                   |
|-----------------------------------|---------------------------------------------------------|
| `AGUARDANDO_PAGAMENTO`            | `TAXA_ANALISE`, `TAXA_REANALISE` ou `TAXA_UNICA`       |
| `AGUARDANDO_PAGAMENTO_VISTORIA`   | `TAXA_VISTORIA`                                         |
| `AGUARDANDO_PAGAMENTO_RENOVACAO`  | `TAXA_RENOVACAO`                                        |

### Subprocessos

| Subprocesso | Gatilho | Responsável principal |
|---|---|---|
| **P11-A — Geração de Boleto** | Ação deliberada do cidadão no frontend Angular | `BoletoLicenciamentoRN.gerarBoleto` |
| **P11-B — Job Vencimento** | Timer `@Schedule(hour="12/12")` automático | `BoletoSituacaoBatchRN.atualizaSituacao` |
| **P11-B — Job CNAB 240** | Timer `@Schedule(hour="*/12")` automático | `EJBTimerService.verificaPagamentoBanrisul` |

**Pré-condição (P11-A):** `SituacaoLicenciamento` em um dos três estados `AGUARDANDO_PAGAMENTO*`.

**Pós-condições possíveis:**

| Via | Estado do boleto | Estado do licenciamento |
|---|---|---|
| Geração bem-sucedida (P11-A) | `BoletoED.situacao = EM_ABERTO` | Permanece em `AGUARDANDO_PAGAMENTO*` |
| Vencimento (P11-B Job 1) | `BoletoED.situacao = VENCIDO` | Permanece em `AGUARDANDO_PAGAMENTO*` |
| Confirmação pagamento (P11-B Job 2) | `BoletoED.situacao = PAGO` | Transita para próximo estado (conforme RN-108) |

---

## 2. Estrutura do BPMN: pools, raias e participantes

O BPMN do P11 é organizado em **dois pools** (`bpmn:collaboration`), cada um representando um processo tecnicamente distinto com gatilhos e responsabilidades diferentes. A separação em dois pools — ao invés de um único processo com múltiplos start events — é uma decisão deliberada de modelagem que reflete a realidade da implementação: os dois contextos de execução (ação do cidadão e jobs automáticos) são gerenciados por classes Java completamente diferentes e não compartilham estado transacional.

### Pool P11-A: Geração de Boleto

O pool P11-A é organizado em **três raias**, cada uma representando um participante distinto:

#### Raia 1 — Cidadão / RT / Proprietário

Representa o usuário externo autenticado via SOE PROCERGS (Implicit Flow OIDC). O pagador pode ser o Responsável Técnico, o Responsável pelo Uso ou o Proprietário do estabelecimento — todos identificados pelo campo `idUsuarioSoe Long` extraído do token de autenticação. Esta raia contém exclusivamente `UserTask`s, pois toda ação do cidadão requer intervenção humana: listar responsáveis, solicitar o boleto, fazer o download do PDF e efetuar o pagamento.

A decisão de incluir a tarefa de pagamento externo (`UT_EfetuarPagamento`) nesta raia — mesmo sendo uma ação que ocorre fora do sistema SOL — é justificada pela necessidade de documentar a divisão de responsabilidades: o P11-A encerra seu trabalho quando o boleto é entregue ao cidadão; a confirmação é responsabilidade do P11-B.

#### Raia 2 — Sistema SOL (Backend Java EE)

Contém toda a lógica de negócio executada pelo backend: validações, cálculo de taxa, persistência, registro de marco e geração de PDF. A maioria dos elementos são `ServiceTask`s que representam métodos EJB `@Stateless` executados em transação `@TransactionAttribute(REQUIRED)`.

Esta raia também hospeda os três eventos de fim de erro (`End_Erro400`, `End_ErroBloqueio`, `End_ErroIntegracao`), posicionados na raia do Sistema porque os erros são detectados e sinalizados pelo backend — não pelo cidadão ou pelo serviço externo.

#### Raia 3 — PROCERGS / Banrisul (Serviço Externo)

Representa o serviço intermediário da PROCERGS que encapsula o SOAP do Banrisul em uma API REST com segurança JWT/JWE. A presença desta raia explícita no BPMN serve um propósito fundamental: tornar visível a **dependência de infraestrutura externa** no processo de geração de boleto. Uma falha no PROCERGS/Banrisul (representada pelo gateway `GW_IntegracaoOK` e pelo `End_ErroIntegracao`) interrompe todo o processo — o cidadão não consegue gerar o boleto e precisa tentar novamente. Sem esta raia, essa dependência ficaria oculta dentro de uma ServiceTask genérica.

### Pool P11-B: Confirmação de Pagamento

O pool P11-B é organizado em **duas raias**:

#### Raia 1 — EJBTimerService (@Singleton @Startup @Schedule)

Hospeda os dois eventos de início com timer (`Start_Timer_Vencimento` e `Start_Timer_CNAB`). Cada start event representa um método `@Schedule` em uma classe EJB distinta, ambos disparados a cada 12 horas. A raia separa claramente a responsabilidade de **disparo automático** (EJBTimerService) da responsabilidade de **processamento** (raia Sistema).

#### Raia 2 — Sistema SOL (Backend Java EE)

Contém todas as ServiceTasks e sub-processos de processamento automático: validação de diretórios, listagem de arquivos, sub-processo multi-instância de processamento CNAB e envio de e-mail de erro.

---

## 3. Pool P11-A — Fase 1: Pré-condições e validações

### 3.1 Start_P11A — Licenciamento em AGUARDANDO_PAGAMENTO*

O processo P11-A inicia com um **StartEvent simples** posicionado na raia do Cidadão. A escolha por um evento de início simples (e não um evento de mensagem, como seria o caso se o P11-A fosse disparado por outro processo) reflete o comportamento real do sistema: o cidadão acessa ativamente o painel do licenciamento no frontend Angular e vê o estado `AGUARDANDO_PAGAMENTO*`. O sistema não dispara uma notificação automática para o P11-A — é o cidadão quem toma a iniciativa de gerar o boleto.

O asterisco em `AGUARDANDO_PAGAMENTO*` é uma notação propositalmente genérica para cobrir os três estados possíveis de disparo sem criar três start events separados no diagrama. A documentação inline do elemento detalha os três estados reais.

### 3.2 UT_ListarResponsaveis — Listar responsáveis para pagamento

**O que faz:** o frontend Angular chama `GET /licenciamentos/{idLic}/reponsaveis-pagamento` para exibir a lista de pessoas disponíveis para figurar como pagador no boleto — RTs, RUs e Proprietários.

**Por que foi modelado como UserTask separada de UT_SolicitarBoleto:** há uma distinção funcional importante entre listar (consulta de dados) e solicitar (ação com efeito de negócio). A listagem de responsáveis é uma consulta pura — sem efeitos colaterais, repetível, não transacional. A solicitação do boleto dispara toda a cadeia de validação e integração bancária. Separar as duas tarefas documenta essa distinção e reflete a UX real do sistema: o cidadão primeiro vê a lista, depois seleciona e confirma.

Adicionalmente, para renovação de APPCI, existe um endpoint diferente (`GET /reponsaveis-pagamento-renovacao`) com filtro por `TipoResponsabilidadeTecnica.RENOVACAO_APPCI`. Modelar a tarefa de listagem separadamente facilita a identificação desse ponto de variação comportamental.

### 3.3 UT_SolicitarBoleto — Selecionar responsável e solicitar geração do boleto

**O que faz:** o cidadão seleciona o responsável pagador e aciona a geração do boleto via `POST /licenciamentos/{idLic}/pagamentos/boleto/` com o DTO contendo `tipo`, `id` (boleto anterior opcional) e `responsavel` (com `tipo`, `cpfCnpj`, `nome`, `cpfProcurador`).

**Por que foi modelado com `camunda:formKey`:** a existência do formKey indica à equipe de desenvolvimento que há um formulário específico associado a esta tarefa — o cidadão não apenas clica num botão, mas preenche dados estruturados (seleciona o responsável, confirma o tipo de boleto). Esta distinção é relevante para o design da interface.

### 3.4 ST_ValidarPrecond — Validar pré-condições e cancelar isenção solicitada (RN-090, RN-091)

**O que faz:** esta `ServiceTask` na raia Sistema executa as primeiras validações do processo, implementadas em `BoletoLicenciamentoRN.gerarBoleto()`:

- **RN-090** (`BoletoLicenciamentoRNVal.validaSituacaoLicenciamento`): verifica compatibilidade entre o `TipoBoleto` solicitado e a `SituacaoLicenciamento` atual. Um boleto `TAXA_VISTORIA` só pode ser gerado quando o licenciamento está em `AGUARDANDO_PAGAMENTO_VISTORIA`, por exemplo. Incompatibilidade → HTTP 400.
- **RN-090 complemento** (`validaTipoBoleto`): `TAXA_REANALISE` exige que o licenciamento já tenha número (indicando que passou pela análise técnica ao menos uma vez).
- **RN-091** (cancelamento de isenção): se `licenciamento.situacaoIsencao == SOLICITADA`, cancela a solicitação de isenção (`isencao = false`, `situacaoIsencao = null`) antes de continuar. O raciocínio é que ao optar por pagar, o cidadão abandona implicitamente a isenção pendente.

**Por que RN-091 está consolidado nesta ServiceTask e não em uma tarefa separada:** a cancelamento de isenção é uma ação preparatória que ocorre no início do método `gerarBoleto()`, dentro da mesma transação. Não há ponto de verificação humana entre a solicitação do boleto e o cancelamento da isenção — é um efeito colateral automático e imediato da solicitação. Separar em uma tarefa distinta criaria a falsa impressão de que há uma etapa intermediária onde a isenção ainda poderia ser preservada.

### 3.5 GW_PrecondOK — Gateway de validação de pré-condições

**O que representa:** gateway exclusivo que bifurca com base no resultado das validações RN-090 e RN-091.

**Por que foi modelado como gateway explícito (e não implícito no fluxo da ServiceTask):** na implementação real, a falha nas validações é sinalizada por uma exceção `WebApplicationRNException(HTTP 400)`. O processo não bifurca por um gateway — ele lança uma exceção. Porém, modelar a bifurcação como gateway no BPMN serve a um propósito pedagógico fundamental: torna visível ao leitor do diagrama que há **dois caminhos possíveis** saindo da validação. Sem o gateway, o fluxo de erro seria invisível no diagrama — apenas um evento de fim isolado sem conexão clara com o fluxo principal. A modelagem com gateway explícito segue a convenção adotada em todos os outros processos do projeto SOL (P04, P07, P10) para representar bifurcações condicionais baseadas em exceções de negócio.

### 3.6 ST_VerifBoletoAnterior — Verificar boleto vigente anterior (RN-092)

**O que faz:** verifica se já existe um boleto anterior para este licenciamento, este responsável e este tipo de boleto que bloqueie a geração de um novo.

**A lógica de bloqueio varia por tipo:**
- Para `TAXA_ANALISE` e `TAXA_UNICA`: tanto `EM_ABERTO` quanto `PAGO` bloqueiam (o cidadão não deve gerar um segundo boleto se já há um em aberto ou se já pagou).
- Para `TAXA_VISTORIA` e `TAXA_RENOVACAO`: apenas `EM_ABERTO` bloqueia (um boleto PAGO de vistoria não impede a geração de outro, pois pode haver múltiplas vistorias no ciclo de vida).
- `TAXA_REANALISE` está **isenta desta verificação** (o cidadão pode ter pago a reanálise anterior e precisar de outro boleto após nova reprovação).

**Por que esta etapa está em uma ServiceTask separada de ST_ValidarPrecond:** embora ambas sejam validações, elas têm natureza e foco distintos. A RN-090 valida o estado do licenciamento (sem consultar boletos). A RN-092 valida a existência de boletos anteriores (sem consultar o estado do licenciamento). A separação reflete a modularidade da implementação (`BoletoLicenciamentoRNVal.validaSituacaoBoletoAnteriorParaPagador` é um método distinto) e facilita o rastreamento individual de cada validação na documentação e nos testes.

### 3.7 GW_BloqueioAnterior — Gateway de boleto bloqueante

**O que representa:** bifurca com base na presença de boleto bloqueante (saída "Bloqueado") ou na ausência deste (saída "Pode gerar"). Os eventos de fim de erro (`End_Erro400` e `End_ErroBloqueio`) são posicionados acima dos gateways correspondentes, seguindo a convenção visual de ramificações de erro subindo verticalmente no diagrama — tornando imediatamente legível que são desvios do fluxo principal, não fins normais.

---

## 4. Pool P11-A — Fase 2: Cálculo da taxa e montagem do boleto

### 4.1 ST_CalcularMontarBoleto — Calcular taxa, montar e pré-persistir boleto (RN-093 a RN-100)

**O que faz:** esta `ServiceTask` é a mais densa do P11-A. Ela concentra oito regras de negócio distintas (RN-093 a RN-100) que, no código, estão distribuídas entre `BoletoLicenciamentoRN.registrarBoleto()` e `BoletoRN.buildBoletoEDLicenciamento()`. Todas ocorrem em uma única transação `@REQUIRED`.

**As oito regras consolidadas nesta tarefa:**

1. **RN-093** — Fórmula de cálculo: `valorBoleto = round(qtdUPF × valorUPF, 2, HALF_EVEN)`. O método de cálculo de `qtdUPF` varia por tipo de boleto (veja tabela nos requisitos).
2. **RN-094** — Regra dos 50% para vistoria: aplica metade da taxa quando o licenciamento já teve uma vistoria do mesmo tipo e não houve APPCI emitido posteriormente.
3. **RN-095** — Compensação na reanálise: calcula o delta de UPFs entre a análise atual e a anterior paga, gerando um valor de compensação que é somado ao 50% da taxa de reanálise.
4. **RN-096** — Regra dos 50% para renovação: aplica metade quando a última vistoria encerrada foi reprovada.
5. **RN-097** — Geração do Nosso Número e Seu Número: realiza um INSERT, lê o ID gerado pela sequence Oracle, calcula o DV módulo 11 e faz um UPDATE para persistir o `nossoNumero` completo.
6. **RN-098** — Prazo de vencimento: 30 dias corridos a partir da data de emissão no fuso `GMT-03:00`.
7. **RN-099** — Desnormalização do pagador: copia nome, CPF/CNPJ e endereço do responsável para os campos do `BoletoED`, garantindo que as informações do pagador permaneçam intactas mesmo que o cadastro do usuário mude no futuro.
8. **RN-100** — Seleção do beneficiário: identifica a conta bancária do CBM-RS responsável pela arrecadação, com base no código IBGE do município do licenciamento.

**Por que oito regras estão em uma única ServiceTask:** esta é a decisão de modelagem mais controversa do P11. A justificativa fundamental é o **atomismo transacional**. Todas estas operações ocorrem dentro de um único método Java com `@TransactionAttribute(REQUIRED)`. Se qualquer uma delas falhar (por exemplo, se o valor da UPF não estiver cadastrado, ou se o endereço do pagador não for encontrado), a transação inteira é revertida — nenhum `BoletoED` é persistido parcialmente. Fragmentar em oito ServiceTasks criaria a expectativa incorreta de que cada regra poderia falhar independentemente, quando na realidade são etapas de uma única unidade de trabalho atômica.

Adicionalmente, a fragmentação tornaria o diagrama ilegível e perderia o foco no fluxo de negócio (que é: "calcular e montar o boleto") em favor dos detalhes de implementação. O BPMN não é o lugar adequado para documentar o algoritmo de cálculo do DV módulo 11 — esse nível de detalhe pertence ao documento de requisitos e ao código-fonte. A documentação inline desta ServiceTask no BPMN referencia as RNs e aponta para as classes Java, servindo como índice de rastreabilidade.

---

## 5. Pool P11-A — Fase 3: Integração com PROCERGS/Banrisul

### 5.1 ST_RegistrarBoletoPROCERGS — Registrar boleto no Banrisul via PROCERGS (RN-101)

**O que faz:** chama o serviço intermediário PROCERGS para registrar o boleto no banco Banrisul e obter o `codigoBarras` e a `linhaDigitavel` necessários para o pagamento. O fluxo de integração envolve seis etapas: montagem de XML JAXB, codificação Base64, encapsulamento JSON, assinatura HMAC-SHA256, criptografia JWE, POST HTTP, decodificação da resposta e extração dos campos.

**Por que esta ServiceTask está na raia PROCERGS e não na raia Sistema:** a raia define **quem é responsável pela execução** da tarefa. Embora o código Java (classe `BoletoIntegracaoProcergs`) execute no servidor WildFly do SOL, o trabalho efetivo de registrar o boleto — validar os dados, gerar o código de barras, registrar o título no Banrisul — é realizado pelo serviço PROCERGS/Banrisul. O servidor SOL apenas formata a requisição e interpreta a resposta. Posicionar esta tarefa na raia PROCERGS comunica que este passo tem uma **dependência de disponibilidade de um sistema externo**: se o PROCERGS estiver fora do ar, este passo falhará independentemente do estado do sistema SOL.

Esta é uma decisão de modelagem com impacto direto em operações e monitoramento: a equipe que mantém o sistema precisa saber que o P11-A tem uma dependência crítica em serviço externo, e o BPMN deve comunicar isso visivelmente.

**Por que o log de integração (CBM_LOG_GERA_BOLETO) é registrado nesta tarefa:** toda tentativa de integração — sucesso ou falha — é registrada na tabela `CBM_LOG_GERA_BOLETO` com os XMLs de envio e retorno. Isso não é uma ação de negócio, mas de auditoria técnica. A documentação desta ServiceTask menciona explicitamente este comportamento porque ele é essencial para diagnóstico de problemas em produção.

### 5.2 GW_IntegracaoOK — Gateway de resultado da integração

**O que representa:** bifurca com base no retorno da integração. Código de retorno PROCERGS diferente de `"3"` → OK. Código `"3"` ou falha de comunicação → HTTP 500.

**Por que o evento de fim de erro está na raia Sistema e não na raia PROCERGS:** o `End_ErroIntegracao` representa o encerramento do processo do ponto de vista do sistema SOL — é o backend que recebe a exceção, formata a resposta HTTP 500 e encerra o processamento. O fato de a causa raiz estar no PROCERGS é um detalhe que está na documentação do evento de fim, não na sua posição no diagrama.

---

## 6. Pool P11-A — Fase 4: Marco, download e pagamento externo

### 6.1 ST_PersistirMarco — Registrar marco de auditoria (RN-102)

**O que faz:** registra o marco de auditoria da geração do boleto em `CBM_LICENCIAMENTO_MARCO`. O tipo de marco varia conforme o tipo de boleto: `BOLETO_VISTORIA` para `TAXA_VISTORIA`, `BOLETO_VISTORIA_RENOVACAO_PPCI` para `TAXA_RENOVACAO`, e `BOLETO_ATEC` para os demais tipos. O texto complementar do marco contém o valor nominal do boleto formatado em R$.

**Por que o marco é registrado após a integração e não antes:** registrar o marco antes da integração criaria um registro de auditoria para uma operação que ainda pode falhar. Se a integração PROCERGS falhar após o registro do marco, haveria um marco indicando que um boleto foi gerado quando, na prática, o boleto está incompleto (sem código de barras). A sequência correta é: integração bem-sucedida → marco. Esta é a mesma lógica aplicada em todos os outros processos do SOL que registram marcos após ações com dependência externa.

**Resposta ao frontend:** após o marco, o método `gerarBoleto()` retorna o `BoletoLicenciamento` DTO com HTTP 201, incluindo os dados do boleto que o frontend usa para exibir o código de barras e a linha digitável ao cidadão.

### 6.2 UT_DownloadBoleto — Fazer download do PDF do boleto (RN-103)

**O que faz:** o cidadão aciona o download do PDF do boleto via `GET /licenciamentos/{idLic}/pagamentos/boleto/{idBoletoLic}`. A RN-103 valida que o boleto pertence ao licenciamento informado (HTTP 404 se não encontrado) e que não está VENCIDO (HTTP 400 se vencido). O PDF é gerado via JasperReports com o template `/reports/boleto.jasper` e inclui todos os dados do beneficiário (CBM-RS) e do pagador (desnormalizados do `BoletoED`).

**Por que a validação de boleto VENCIDO aparece no download e não na geração:** no momento da geração, o boleto recém-criado está necessariamente `EM_ABERTO`. O vencimento só é processado pelo job P11-B horas depois. Assim, a validação de vencimento faz sentido apenas no download — o cidadão pode tentar baixar o PDF de um boleto que venceu enquanto ele não completava o processo de pagamento.

### 6.3 UT_EfetuarPagamento e End_BoletoEmitido

**UT_EfetuarPagamento** é uma `UserTask` que representa a ação de pagamento do cidadão fora do sistema SOL (internet banking, caixa eletrônico, agência bancária). A tarefa está na raia do Cidadão porque é de sua responsabilidade exclusiva — o sistema SOL não participa deste passo.

**End_BoletoEmitido** indica que o P11-A está concluído do ponto de vista do sistema: o boleto foi gerado, o PDF está disponível para download, e o sistema aguarda que o Banrisul confirme o pagamento via arquivo CNAB 240 (processado pelo P11-B). O estado do licenciamento não muda no P11-A — permanece em `AGUARDANDO_PAGAMENTO*`.

---

## 7. Pool P11-B — Fluxo 1: Job de vencimento de boletos

### 7.1 Start_Timer_Vencimento — Evento de início com timer

**O que representa:** um `TimerStartEvent` com cron `0 0,12 * * *` (00:00 e 12:00 diariamente), correspondendo à anotação EJB `@Schedule(hour="12/12")`. Está posicionado na raia `EJBTimerService` para explicitar que o disparo é automático e gerenciado pelo servidor WildFly — não há intervenção humana.

### 7.2 ST_JobVencimento — Atualizar boletos vencidos (RN-104)

**O que faz:** `BoletoSituacaoBatchRN.atualizaSituacao()` calcula a data limite de vencimento (data atual − N dias, onde N vem do parâmetro `numero.dias.situacao.vencimento`, default 2), busca todos os boletos com `situacao = EM_ABERTO` e `dataVencimento ≤ dataLimite`, e os atualiza para `VENCIDO`.

**Por que usa a data atual menos N dias e não a data de vencimento exata:** o parâmetro de dias de tolerância é uma salvaguarda operacional — garante que boletos que venceram "no limite" (por exemplo, no dia corrente, dependendo do horário de execução do job) não sejam marcados como vencidos prematuramente. O parâmetro é configurável via `CBM_PARAMETRO_BOLETO`, o que permite ajuste sem redeploy da aplicação.

**Impacto em outros processos:** boletos marcados como VENCIDO bloqueiam o download do PDF (RN-103) e obrigam o cidadão a gerar um novo boleto. Isso cria um loop implícito no P11-A: se o boleto do cidadão vencer, ele precisará reiniciar o P11-A para gerar um substituto.

---

## 8. Pool P11-B — Fluxo 2: Job de confirmação de pagamento CNAB 240

### 8.1 Start_Timer_CNAB — Evento de início com timer

**O que representa:** um `TimerStartEvent` separado de `Start_Timer_Vencimento`, correspondendo ao método `EJBTimerService.verificaPagamentoBanrisul()` com `@Schedule(minute="0", hour="*/12")`. Embora ambos os timers executem a cada 12 horas, estão em classes EJB distintas e representam responsabilidades independentes — daí a modelagem como dois start events separados na mesma pool.

### 8.2 ST_ValidarDiretorios — Validar diretórios de entrada e destino

**O que faz:** verifica a existência dos diretórios configurados em `PropriedadesEnum.CAMINHO_ARQUIVO_ENTRADA_BANRISUL` e `CAMINHO_ARQUIVO_PROCESSADOS_BANRISUL`. Se qualquer diretório não existir ou não estiver configurado, lança `RuntimeException` e interrompe o job.

**Por que esta tarefa foi modelada explicitamente:** a validação de diretórios é um ponto de falha operacional crítico — se os diretórios de rede não estiverem montados (o que pode acontecer após reinicialização do servidor), o job falhará silenciosamente (exceto por log de erro no WildFly). Tornar esta etapa visível no BPMN documenta este risco operacional para a equipe de infraestrutura.

### 8.3 ST_ListarArquivos e GW_HaArquivos

**ST_ListarArquivos** lista todos os arquivos no diretório de entrada. **GW_HaArquivos** verifica se há arquivos para processar. A saída "Não" (`End_SemArquivos`) representa a situação normal em dias sem movimento bancário — o job encerra sem processar nada.

**Por que há um gateway explícito em vez de tratar o array vazio dentro do sub-processo:** a situação "sem arquivos" é um estado distinto do estado "houve processamento" e merece seu próprio evento de fim. Documentar este caminho explicitamente ajuda a equipe de operações a entender que a ausência de processamento é normal e esperada, não um sinal de problema.

### 8.4 SP_ProcessarArquivos — Sub-processo multi-instância serial

**O que faz:** itera sobre cada arquivo CNAB 240 do diretório, executando cinco passos para cada um: (A) verificar tamanho, (B) ler linhas, (C) parsear CNAB 240, (D) processar cada registro de liquidação, (E) mover arquivo para destino.

**Por que foi modelado como sub-processo colapsado:** o processamento de cada arquivo envolve múltiplas etapas (parse, loop de registros, liquidação, despacho por origem) que, se expandidas no diagrama principal, tornariam o fluxo ilegível. O sub-processo colapsado mantém a clareza do fluxo principal enquanto a riqueza técnica — incluindo as cinco fases detalhadas, as transições de estado (RN-108), o `@REQUIRES_NEW` por registro e o tratamento de cada tipo de boleto — está documentada no campo `<documentation>` do elemento.

**Por que multi-instance serial e não paralelo:** o processamento paralelo de arquivos CNAB criaria risco de condições de corrida em atualizações do mesmo `BoletoED` (se o mesmo boleto aparecer em dois arquivos) e em atualizações da `SituacaoLicenciamento`. O processamento serial garante atomicidade: um arquivo é completamente processado antes do próximo começar.

**O papel do `@TransactionAttribute(REQUIRES_NEW)`:** cada chamada a `PagamentoBoletoRN.processaRetorno()` executa em uma transação completamente nova. Isso significa que a falha no processamento de um registro CNAB (por exemplo, valor divergente) não reverte o processamento dos registros anteriores do mesmo arquivo. Esta é uma decisão de resiliência: é preferível confirmar os registros corretos e registrar os erros do que reverter tudo por causa de um registro problemático.

**As transições de estado RN-108** representam a etapa mais crítica do P11-B: é aqui que o pagamento se torna visível para o ciclo de vida do licenciamento. Após a liquidação do boleto, o licenciamento sai do estado `AGUARDANDO_PAGAMENTO*` e avança para o próximo estado (geralmente `AGUARDANDO_DISTRIBUICAO` ou `AGUARDANDO_DISTRIBUICAO_VISTORIA`), desbloqueando o processo seguinte no fluxo do licenciamento.

**A lógica de ramificação em RN-108 é complexa** porque considera três variáveis independentes: (1) a situação atual do licenciamento, (2) o tipo de boleto, e (3) características do licenciamento (PPCI vs PSPCIM, endereço novo, inviabilidade técnica pendente). Esta complexidade é intencional e reflete a diversidade de caminhos possíveis no ciclo de vida de um licenciamento — cada combinação resulta em uma transição de estado distinta.

### 8.5 GW_HouvErros, ST_EnviarEmailErro e End_CNAB

**GW_HouvErros** verifica se a lista de erros coletados durante o processamento está não vazia. Em caso afirmativo, **ST_EnviarEmailErro** notifica o administrador com os detalhes dos erros (nossoNumero não encontrado, valor divergente, boleto já pago). O **End_CNAB** representa a conclusão do job — com ou sem erros, pois o e-mail é uma notificação, não uma correção.

**Por que o e-mail é enviado após o processamento e não durante:** enviar um e-mail para cada registro com erro individual criaria spam e tornaria o diagnóstico difícil. Acumular todos os erros e enviar um e-mail consolidado ao final é mais operacionalmente útil.

---

## 9. Justificativas das decisões de modelagem

### 9.1 Dois pools ao invés de um processo com múltiplos start events

A separação do P11 em dois pools (`bpmn:collaboration`) reflete a realidade técnica da implementação: P11-A é acionado por ação humana síncrona (HTTP request) enquanto P11-B é acionado por timer assíncrono (EJB `@Schedule`). Colocar ambos em um único processo com múltiplos start events criaria a impressão incorreta de que compartilham contexto, estado ou transação — o que não ocorre. A separação em pools é a representação BPMN mais fidedigna de processos com natureza e gatilhos fundamentalmente distintos.

### 9.2 Três raias no Pool P11-A (incluindo raia PROCERGS)

A inclusão de uma raia dedicada ao serviço externo PROCERGS/Banrisul é incomum nos outros processos do SOL (que geralmente têm raias apenas para atores humanos e o sistema interno). A decisão é justificada pela centralidade da integração bancária no P11: a geração do boleto não existe sem o código de barras retornado pelo Banrisul. Tornar esta dependência visível no diagrama — e não escondê-la dentro de uma ServiceTask do sistema — é fundamental para que a equipe compreenda o perfil de risco do processo.

### 9.3 Oito regras de negócio em uma única ServiceTask (ST_CalcularMontarBoleto)

Conforme explicado na seção 4.1, a consolidação das RNs 093-100 em uma única ServiceTask reflete o atomismo transacional: todas as operações ocorrem em uma única transação EJB e não podem ser parcialmente aplicadas. O princípio adotado em todos os processos do SOL é "uma ServiceTask por transação EJB", e este princípio prevalece aqui.

### 9.4 Sub-processo colapsado para processamento CNAB com multi-instance serial

O sub-processo colapsado `SP_ProcessarArquivos` encapsula o loop de processamento de arquivos sem expor os detalhes no diagrama principal. A multi-instance serial garante que os arquivos são processados um a um, evitando condições de corrida. A documentação inline do sub-processo contém a descrição completa dos cinco passos e das regras de negócio RN-106 a RN-108.

### 9.5 Dois start events separados no Pool P11-B

Os dois fluxos do P11-B (job de vencimento e job de confirmação CNAB) foram modelados como dois start events separados — não como um único start event com gateway paralelo. A razão é que são métodos em classes EJB distintas (`BoletoSituacaoBatchRN` e `EJBTimerService`) com comportamentos completamente independentes. Um pode falhar sem afetar o outro. Modelar com gateway paralelo implicaria que ambos sempre executam juntos em sincronicidade, o que não é o caso.

### 9.6 Eventos de fim de erro posicionados acima dos gateways

Os três eventos de fim de erro no Pool P11-A (`End_Erro400`, `End_ErroBloqueio`, `End_ErroIntegracao`) estão posicionados acima dos gateways correspondentes, criando um padrão visual vertical onde o caminho de erro sobe enquanto o caminho feliz continua horizontalmente. Esta convenção visual — adotada consistentemente em P04, P07 e P10 — permite identificar instantaneamente o fluxo principal (horizontal) e os desvios de erro (verticais) sem precisar ler os rótulos.

---

## 10. Diagrama de estados das entidades principais

### SituacaoBoleto (BoletoED.situacao)

```
[criado em ST_CalcularMontarBoleto + ST_RegistrarBoletoPROCERGS]
      |
      v
  EM_ABERTO ──────────────────────────────> VENCIDO
      |                                         ^
      |                                  [ST_JobVencimento: dataVencimento + N dias]
      | [SP_ProcessarArquivos: codMovimento="06"]
      v
    PAGO
```

### SituacaoLicenciamento (mudanças após P11-B Job 2 — RN-108)

```
AGUARDANDO_PAGAMENTO
(TAXA_ANALISE/REANALISE — PPCI, geral)
      |
      v
AGUARDANDO_DISTRIBUICAO         ← P04 (nova distribuição para análise técnica)

AGUARDANDO_PAGAMENTO
(TAXA_ANALISE/REANALISE — PPCI, endereço novo)
      |
      v
ANALISE_ENDERECO_PENDENTE

AGUARDANDO_PAGAMENTO
(TAXA_ANALISE/REANALISE — PPCI, inviabilidade)
      |
      v
ANALISE_INVIABILIDADE_PENDENTE

AGUARDANDO_PAGAMENTO
(TAXA_ANALISE/REANALISE — PSPCIM, geral)
      |
      v
AGUARDANDO_DISTRIBUICAO         ← P04 (análise única PSPCIM)

AGUARDANDO_PAGAMENTO_VISTORIA
(TAXA_VISTORIA)
      |
      v
AGUARDANDO_DISTRIBUICAO_VISTORIA ← P07 (nova vistoria)

AGUARDANDO_PAGAMENTO_RENOVACAO
(TAXA_RENOVACAO)
      |
      v
AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO ← renovação de APPCI
```

---

## 11. Referência cruzada: elementos BPMN x classes Java EE

| Elemento BPMN | Tipo | Classe Java EE | Método | Endpoint REST |
|---|---|---|---|---|
| Start_P11A | StartEvent | — | — | — |
| UT_ListarResponsaveis | UserTask | `LicenciamentoResponsavelPagamentoRN` | `listaPorLicenciamento()` | `GET /licenciamentos/{id}/reponsaveis-pagamento` |
| UT_SolicitarBoleto | UserTask | — | — | `POST /licenciamentos/{id}/pagamentos/boleto/` |
| ST_ValidarPrecond | ServiceTask | `BoletoLicenciamentoRN` | `gerarBoleto()` (início) | — |
| | | `BoletoLicenciamentoRNVal` | `validaSituacaoLicenciamento()` + `validaTipoBoleto()` | — |
| GW_PrecondOK | ExclusiveGateway | — | — | — |
| End_Erro400 | EndEvent (Error) | — | — | HTTP 400 |
| ST_VerifBoletoAnterior | ServiceTask | `BoletoLicenciamentoRN` | `validarBoletoVencido()` | — |
| | | `BoletoLicenciamentoRNVal` | `validaSituacaoBoletoAnteriorParaPagador()` | — |
| GW_BloqueioAnterior | ExclusiveGateway | — | — | — |
| End_ErroBloqueio | EndEvent (Error) | — | — | HTTP 400 |
| ST_CalcularMontarBoleto | ServiceTask | `BoletoLicenciamentoRN` | `registrarBoleto()` | — |
| | | `BoletoRN` | `buildBoletoEDLicenciamento()`, `getNossoNumero()`, `getDataVencimento()` | — |
| | | `TaxaLicenciamentoRN` | `calculaTaxaAnaliseLicenciamento()`, `calculaTaxaVistoriaLicenciamento()`, etc. | — |
| | | `ValorUPFRN` | `getValorAtualUPF()` | — |
| | | `EnderecoUsuarioRN` | `listarEnderecosUsuario()` | — |
| | | `CidadeRN` | `consultaPorNroMunicipioIBGE()` | — |
| ST_RegistrarBoletoPROCERGS | ServiceTask | `BoletoIntegracaoProcergs` | `registrarBoleto()` | POST PROCERGS (externo) |
| GW_IntegracaoOK | ExclusiveGateway | — | — | — |
| End_ErroIntegracao | EndEvent (Error) | — | — | HTTP 500 |
| ST_PersistirMarco | ServiceTask | `BoletoLicenciamentoRN` | `incluiMarco()` | — |
| | | `LicenciamentoMarcoInclusaoRN` | `incluir()` | — |
| UT_DownloadBoleto | UserTask | `BoletoLicenciamentoRN` | `downloadBoleto()` | `GET /licenciamentos/{id}/pagamentos/boleto/{idBoleto}` |
| | | `BoletoRN` | `gerarPdfBoletoLicenciamento()` | — |
| UT_EfetuarPagamento | UserTask | — | — | — (ação externa) |
| End_BoletoEmitido | EndEvent | — | — | — |
| Start_Timer_Vencimento | TimerStartEvent | `BoletoSituacaoBatchRN` | `atualizaSituacao()` | — |
| ST_JobVencimento | ServiceTask | `BoletoSituacaoBatchRN` | `atualizaSituacao()` | — |
| End_Vencimento | EndEvent | — | — | — |
| Start_Timer_CNAB | TimerStartEvent | `EJBTimerService` | `verificaPagamentoBanrisul()` | — |
| ST_ValidarDiretorios | ServiceTask | `EJBTimerService` | `verificaPagamentoBanrisul()` (início) | — |
| ST_ListarArquivos | ServiceTask | `EJBTimerService` | `verificaPagamentoBanrisul()` | — |
| GW_HaArquivos | ExclusiveGateway | — | — | — |
| End_SemArquivos | EndEvent | — | — | — |
| SP_ProcessarArquivos | SubProcess | `PagamentoBoletoRN` | `processaRetorno()` | — |
| | | `ParserCnab240` | `processaLinhasArquivo()` | — |
| | | `PagamentoBoletoRNVal` | `validar()` | — |
| | | `PagamentoBoletoLicenciamentoRN` | `atualizaStatusAposBoletoPago()` | — |
| GW_HouvErros | ExclusiveGateway | — | — | — |
| ST_EnviarEmailErro | ServiceTask | `EJBTimerService` | `enviarEmail()` via `EmailService` | — |
| End_CNAB | EndEvent | — | — | — |

---

## 12. Tabelas de banco de dados afetadas por processo

### Pool P11-A

| Tabela Oracle | Operações | Contexto |
|---|---|---|
| `CBM_LICENCIAMENTO` | UPDATE (IS_ISENCAO, TP_SITUACAO_ISENCAO) | RN-091 — cancelamento de isenção solicitada |
| `CBM_BOLETO` | INSERT (criação) + UPDATE (nossoNumero após sequence) | RN-097 — Nosso Número e Seu Número |
| `CBM_BOLETO` | UPDATE (TXT_CODIGO_BARRAS, TXT_LINHA_DIGITAVEL) | RN-101 — resultado integração PROCERGS |
| `CBM_BOLETO_LICENCIAMENTO` | INSERT | Vínculo boleto ↔ licenciamento com TipoBoleto e qtdUPF |
| `CBM_LOG_GERA_BOLETO` | INSERT (sucesso ou erro) | RN-101 — log de toda tentativa de integração |
| `CBM_LICENCIAMENTO_MARCO` | INSERT | RN-102 — marco de auditoria da geração |
| `CBM_PARAMETRO_BOLETO` | SELECT (somente leitura) | Valor da UPF e parâmetros de cálculo |
| `CBM_BENEFICIARIO` | SELECT (somente leitura) | RN-100 — seleção do beneficiário por IBGE |

### Pool P11-B — Job Vencimento

| Tabela Oracle | Operações | Contexto |
|---|---|---|
| `CBM_BOLETO` | UPDATE (TP_SITUACAO = 'VENCIDO') | RN-104 — boletos vencidos |
| `CBM_PARAMETRO_BOLETO` | SELECT (somente leitura) | Parâmetro `numero.dias.situacao.vencimento` |

### Pool P11-B — Job CNAB 240

| Tabela Oracle | Operações | Contexto |
|---|---|---|
| `CBM_BOLETO` | UPDATE (TP_SITUACAO = 'PAGO', DATA_PAGAMENTO, TXT_NOME_ARQUIVO_RETORNO) | RN-106 — liquidação |
| `CBM_LICENCIAMENTO` | UPDATE (SIT_LICENCIAMENTO) | RN-108 — transição de estado após pagamento |
| `CBM_SITUACAO_LICENCIAMENTO` | INSERT (histórico de situações via TrocaEstado CDI) | RN-108 — rastreio histórico |
| `CBM_LICENCIAMENTO_MARCO` | INSERT | RN-108 — marcos de liquidação (LIQUIDACAO_ATEC, LIQUIDACAO_VISTORIA, etc.) |

---

*Documento gerado em 2026-03-13*
*Referência: arquivo `P11_PagamentoBoleto_StackAtual.bpmn`*
*Projeto: Licitação SOL — CBM-RS*
