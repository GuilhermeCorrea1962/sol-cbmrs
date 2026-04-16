# Descritivo do Fluxo BPMN — P06: Solicitação de Isenção de Taxa
## Stack Atual Java EE (sem alteração tecnológica)

**Versão:** 1.0
**Data:** 2026-03-10
**Projeto:** SOL — Sistema Online de Licenciamento / CBM-RS
**Processo:** P06 — Solicitação de Isenção de Taxa
**Arquivo BPMN:** `P06_IsencaoTaxa_StackAtual.bpmn`

---

## Sumário

1. [Visão Geral do Processo e Decisões de Estrutura](#1-visão-geral-do-processo-e-decisões-de-estrutura)
2. [Justificativa da Estrutura de Colaboração — Dois Pools](#2-justificativa-da-estrutura-de-colaboração--dois-pools)
3. [Justificativa das Quatro Raias (Lanes)](#3-justificativa-das-quatro-raias-lanes)
4. [P06-A — Isenção de Taxa de Licenciamento: Fluxo Completo](#4-p06-a--isenção-de-taxa-de-licenciamento-fluxo-completo)
   - 4.1 [Início do Processo](#41-início-do-processo)
   - 4.2 [Solicitação pelo Cidadão ou RT](#42-solicitação-pelo-cidadão-ou-rt)
   - 4.3 [Validação de Estado do Licenciamento](#43-validação-de-estado-do-licenciamento)
   - 4.4 [Gateway de Elegibilidade](#44-gateway-de-elegibilidade)
   - 4.5 [Criação da Análise de Isenção](#45-criação-da-análise-de-isenção)
   - 4.6 [Registro do Marco de Solicitação](#46-registro-do-marco-de-solicitação)
   - 4.7 [Gateway de Pré-análise Automática](#47-gateway-de-pré-análise-automática)
   - 4.8 [Caminho A — Pré-análise Automática de NCS](#48-caminho-a--pré-análise-automática-de-ncs)
   - 4.9 [Caminho B — Análise Manual pelo ADM CBM-RS](#49-caminho-b--análise-manual-pelo-adm-cbm-rs)
   - 4.10 [Troca de Estado do Licenciamento (Aprovação)](#410-troca-de-estado-do-licenciamento-aprovação)
   - 4.11 [Reprovação e Ciclo de Renovação](#411-reprovação-e-ciclo-de-renovação)
   - 4.12 [Notificações por E-mail via SOE PROCERGS](#412-notificações-por-e-mail-via-soe-procergs)
   - 4.13 [Eventos de Fim do P06-A](#413-eventos-de-fim-do-p06-a)
5. [P06-B — Isenção de Taxa de FACT: Fluxo Completo](#5-p06-b--isenção-de-taxa-de-fact-fluxo-completo)
   - 5.1 [Início do Processo FACT](#51-início-do-processo-fact)
   - 5.2 [Solicitação pelo Cidadão ou RT](#52-solicitação-pelo-cidadão-ou-rt)
   - 5.3 [Criação da Análise de Isenção do FACT](#53-criação-da-análise-de-isenção-do-fact)
   - 5.4 [Análise Manual pelo ADM CBM-RS](#54-análise-manual-pelo-adm-cbm-rs)
   - 5.5 [Aprovação: Geração do Número do FACT](#55-aprovação-geração-do-número-do-fact)
   - 5.6 [Reprovação do FACT — Decisão Final](#56-reprovação-do-fact--decisão-final)
   - 5.7 [Eventos de Fim do P06-B](#57-eventos-de-fim-do-p06-b)
6. [Máquinas de Estado Modeladas](#6-máquinas-de-estado-modeladas)
7. [Rastreabilidade dos Marcos (TipoMarco)](#7-rastreabilidade-dos-marcos-tipomarco)
8. [Diferenças Fundamentais entre P06-A e P06-B](#8-diferenças-fundamentais-entre-p06-a-e-p06-b)
9. [Padrões de Implementação Refletidos no BPMN](#9-padrões-de-implementação-refletidos-no-bpmn)

---

## 1. Visão Geral do Processo e Decisões de Estrutura

O Processo 06 (P06) do sistema SOL trata da **solicitação e análise de isenção da taxa de análise** cobrada pelo CBM-RS no processamento de pedidos de licenciamento de prevenção contra incêndio (PPCI) e de FACTs (Formulários de Atendimento e Consulta Técnica).

A cobrança dessas taxas é uma etapa que antecede a análise técnica pelo corpo de bombeiros. Em determinadas situações — como entidades filantrópicas, microempreendedores individuais (MEI) ou órgãos públicos — a legislação ou a política interna do CBM-RS permite a isenção do pagamento. O processo P06 é o mecanismo pelo qual o cidadão ou Responsável Técnico (RT) requer essa isenção, e pelo qual o analista administrativo do CBM-RS (ADM) ou o próprio sistema a concede ou nega.

O processo é composto por dois sub-processos completamente distintos em termos de entidades de banco de dados, regras de negócio e comportamento:

| Sub-processo | Objeto da isenção | Entidade principal | Tabela |
|---|---|---|---|
| **P06-A** | Taxa de análise do Licenciamento (PPCI) | `AnaliseLicenciamentoIsencaoED` | `CBM_ANALISE_LIC_ISENCAO` |
| **P06-B** | Taxa do FACT | `AnaliseFactIsencaoED` | `CBM_ANALISE_FACT_ISENCAO` |

Ambos compartilham o mesmo propósito de negócio, mas possuem entidades, endpoints, regras e comportamentos distintos o suficiente para justificar modelagem separada.

---

## 2. Justificativa da Estrutura de Colaboração — Dois Pools

O arquivo BPMN utiliza uma **colaboração com dois pools** (`Participant_P06A` e `Participant_P06B`), cada um referenciando um processo BPMN independente.

**Por que dois pools e não um único processo com subprocessos?**

A decisão de modelar P06-A e P06-B como pools separados numa colaboração decorre de três fatores técnicos identificados no código-fonte:

1. **Entidades de banco de dados completamente distintas.** `AnaliseLicenciamentoIsencaoED` e `AnaliseFactIsencaoED` não compartilham campos, tabelas ou repositórios. Não há herança nem interface comum entre elas.

2. **Regras de negócio divergentes em pontos-chave.** O P06-A possui pré-análise automática parametrizada (`APROVA_ISENCAOTAXA_PREANALISE`), mecanismo de renovação (`SOLICITADA_RENOV`) e prazo de correção (`IsencaoTaxaReanaliseRN.PRAZO_CORRECAO = 30L`). O P06-B não possui nenhum desses mecanismos — sua decisão é sempre manual e sempre final.

3. **Endpoints REST separados.** P06-A usa `/licenciamentos/{id}/solicitacaoIsencao` e `/adm/analise-licenciamentos-isencao`. P06-B usa `/facts/{id}/solicitacaoIsencao` e `/adm/analises-fact-isencao`. Não há sobreposição.

Dois pools permitem visualizar com clareza as especificidades de cada sub-processo sem contaminar um com os elementos do outro, ao mesmo tempo em que a colaboração evidencia que fazem parte do mesmo contexto funcional (isenção de taxa).

---

## 3. Justificativa das Quatro Raias (Lanes)

Cada pool é dividido em quatro raias horizontais, seguindo o mesmo padrão adotado nos processos P03 e P05:

| Raia | Ator/Sistema | Justificativa |
|---|---|---|
| **Cidadão / RT** | Usuário externo autenticado via SOE PROCERGS | Agrupa as `UserTask` de iniciativa do usuário externo: solicitar isenção e enviar comprovantes. Reflete o `@AutorizaEnvolvido` — apenas RT ou RU vinculados ao licenciamento têm acesso. |
| **Sistema SOL Backend** | EJB `@Stateless` + JAX-RS | Agrupa todas as `ServiceTask` automáticas que o servidor executa: validações, persistência, troca de estado do licenciamento, registro de marcos. Reflete o padrão de camadas `RestImpl → RN → BD → ED`. |
| **ADM CBM-RS** | Analista administrativo interno | Agrupa as `UserTask` de iniciativa do analista: listar pendentes e registrar a decisão. Reflete as permissões `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")` e `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")`. |
| **Alfresco / SOE PROCERGS** | ECM Alfresco + serviço de e-mail SOE | Agrupa as `ServiceTask` de integração com sistemas externos: upload de arquivos no Alfresco e envio de notificações por e-mail via SOE. Mantém visível a dependência de sistemas externos, que têm seu próprio ciclo de vida e possíveis falhas de integração. |

A separação em quatro raias é intencional para evidenciar, em licitação, que o sistema integra múltiplos componentes com responsabilidades distintas, cada um com requisitos não funcionais próprios (disponibilidade, segurança, timeout).

---

## 4. P06-A — Isenção de Taxa de Licenciamento: Fluxo Completo

### 4.1 Início do Processo

**Elemento:** `Start_P06A` — Evento de início simples (círculo).

O processo inicia quando um licenciamento se encontra na situação `AGUARDANDO_PAGAMENTO` e o cidadão ou RT decide solicitar isenção da taxa de análise em vez de efetuar o pagamento. Este evento de início foi modelado como **simples** (não como evento de mensagem ou sinal) porque, no sistema atual, não existe um mecanismo de disparo assíncrono: é o próprio usuário quem navega até a tela de isenção no portal SOL e clica em "Solicitar Isenção". O evento representa a condição pré-existente, não um gatilho técnico externo.

A pré-condição `LicenciamentoED.situacao = AGUARDANDO_PAGAMENTO` é anotada na documentação do elemento porque é a premissa de negócio para a elegibilidade, ainda que a verificação formal ocorra em tarefa posterior.

---

### 4.2 Solicitação pelo Cidadão ou RT

**Elemento:** `Task_RT_SolicitarIsencao` — `UserTask` na raia Cidadão / RT.

Esta tarefa representa a ação do usuário no portal Angular: preencher a justificativa da isenção e confirmar a solicitação. O formulário envia a requisição REST `POST /licenciamentos/{id}/solicitacaoIsencao` com o DTO `SolicitacaoIsencaoDTO`.

**Por que UserTask e não ServiceTask?**

A tarefa foi modelada como `UserTask` porque envolve julgamento humano — o cidadão precisa redigir uma justificativa explicando o motivo pelo qual entende fazer jus à isenção (enquadramento jurídico, porte da empresa, natureza da entidade). O sistema não decide automaticamente quem pode solicitar: qualquer RT ou RU vinculado ao licenciamento pode fazê-lo. A decisão sobre quem tem *direito* à isenção é tomada posteriormente pelo ADM ou pelo sistema de NCS.

A segurança desta tarefa é garantida pelo interceptor `@AutorizaEnvolvido`, que verifica, antes de processar a requisição, se o usuário autenticado via SOE PROCERGS (obtido de `SessionMB.getUsuario()`) é realmente RT ou RU do licenciamento informado. Caso não seja, o acesso é bloqueado antes mesmo de chegar ao RN.

---

### 4.3 Validação de Estado do Licenciamento

**Elemento:** `Task_BE_ValidarEstado` — `ServiceTask` na raia Sistema SOL Backend.
**Classe:** `AnaliseLicenciamentoIsencaoRNVal` (EJB `@Stateless`, `@AppInterceptor`).

Esta tarefa executa a validação de negócio antes de qualquer persistência. O método `validarPendenteIsencao()` realiza duas verificações:

1. **Estado do licenciamento:** confirma que `LicenciamentoED.situacao == SituacaoLicenciamento.AGUARDANDO_PAGAMENTO`. Somente neste estado faz sentido solicitar isenção — se o licenciamento já está em análise ou distribuído, a taxa já foi paga (ou o processo está em outro estágio).

2. **Ausência de solicitação ativa:** verifica que não existe `AnaliseLicenciamentoIsencaoED` com `situacaoIsencao == SOLICITADA` para o mesmo licenciamento. Esta verificação previne que o cidadão abra múltiplas solicitações simultâneas, o que geraria inconsistência no fluxo de análise.

**Por que a validação foi separada em uma classe própria (RNVal)?**

O padrão do sistema SOL separa as validações de pré-condição em classes `*RNVal` para permitir reutilização. O `AnaliseLicenciamentoIsencaoRN.inclui()` invoca `val.validarPendenteIsencao()` internamente, mas a classe validadora existe de forma independente para poder ser testada em isolamento e chamada por outros pontos do sistema. O BPMN reflete essa separação modelando a validação como uma tarefa distinta, tornando explícito para o leitor que há uma barreira formal antes da criação do registro.

Em caso de falha, o `RNVal` lança `WebApplicationException(Status.NOT_ACCEPTABLE)` com a chave `"licenciamento.isencao.naopendente"`, que o framework JAX-RS traduz em HTTP 406 para o Angular.

---

### 4.4 Gateway de Elegibilidade

**Elemento:** `GW_EstadoValido` — Gateway exclusivo (losango com X).

Este gateway modela a decisão de negócio que a validação anterior impõe:

- **[Sim — elegível]:** o fluxo continua normalmente para criar a análise de isenção.
- **[Não — HTTP 406]:** o fluxo encerra no evento de fim de erro `End_P06A_EstadoInvalido`.

**Nota de modelagem:** na implementação Java, a exceção é lançada *dentro* do `RNVal`, interrompendo o fluxo antes de retornar ao chamador. O gateway não corresponde a uma decisão explícita no código — ele é um artifício de modelagem BPMN para tornar visível, no diagrama, que existe uma bifurcação e que há um caminho de erro. A alternativa seria usar um evento de borda de erro na `ServiceTask`, mas isso tornaria o diagrama mais complexo visualmente sem adicionar clareza conceitual para o público de uma licitação.

O evento de fim `End_P06A_EstadoInvalido` foi modelado com `errorEventDefinition` (círculo preenchido com raio), sinalizando ao leitor que é um encerramento anormal, distinto dos encerramentos bem-sucedidos.

---

### 4.5 Criação da Análise de Isenção

**Elemento:** `Task_BE_CriarAnalise` — `ServiceTask` na raia Sistema SOL Backend.
**Classe:** `AnaliseLicenciamentoIsencaoRN` (EJB `@Stateless`, `@AppInterceptor`).

Após a validação, o sistema cria o registro de análise de isenção no banco de dados. A entidade `AnaliseLicenciamentoIsencaoED` é instanciada com os seguintes valores iniciais:

| Campo | Valor atribuído | Significado |
|---|---|---|
| `licenciamento` | referência ao `LicenciamentoED` | vincula a análise ao licenciamento solicitante |
| `dthSolicitacao` | `Calendar.getInstance()` | marca o momento exato da solicitação |
| `situacaoIsencao` | `TipoSituacaoIsencao.SOLICITADA` | estado inicial da máquina de estados da isenção |
| `analista` | `null` | ainda não foi atribuído a um analista |
| `dthAnalise` | `null` | ainda não houve análise |
| `statusAnalise` | `null` | decisão ainda não tomada |

**Por que modelar a criação separada da análise?**

A criação da análise foi separada da decisão (aprovação/reprovação) porque representam momentos distintos no tempo e com atores distintos. A criação ocorre imediatamente após a solicitação do cidadão (automática, síncrona). A decisão pode ocorrer minutos, horas ou dias depois, dependendo da carga de trabalho do ADM. Modelar como uma única tarefa obscureceria essa assincronicidade.

A auditoria Hibernate Envers gera automaticamente um registro em `CBM_ANALISE_LIC_ISENCAO_AUD` a cada persistência, garantindo rastreabilidade completa do ciclo de vida do registro.

---

### 4.6 Registro do Marco de Solicitação

**Elemento:** `Task_BE_MarcoSolicit` — `ServiceTask` na raia Sistema SOL Backend.
**Classe:** `MarcoRN` (EJB `@Stateless`).
**Marco registrado:** `TipoMarco.SOLICITACAO_ISENCAO`.

Imediatamente após criar a análise, o sistema registra um marco temporal na tabela `CBM_MARCO_LICENCIAMENTO`. Este marco serve a dois propósitos distintos:

1. **Auditoria e rastreabilidade:** o marco registra permanentemente que, naquele instante, aquele usuário (CPF) iniciou uma solicitação de isenção. Relatórios administrativos e consultas históricas dependem desse registro.

2. **Cálculo de prazo:** a classe `IsencaoTaxaReanaliseRN` usa os marcos para calcular cumulativamente o prazo de correção. A constante `PRAZO_CORRECAO = 30L` (dias) é aplicada ao intervalo entre o marco de ciência e o marco de conclusão da correção. Sem o marco de solicitação como âncora temporal, o cálculo de prazo seria impreciso.

**Por que o registro de marco é uma tarefa separada no BPMN?**

No código-fonte, o `MarcoRN.incluir()` é chamado dentro do `AnaliseLicenciamentoIsencaoRN.inclui()`. Todavia, modelar o marco como tarefa separada é uma decisão consciente de clareza do processo: para o leitor do BPMN (analista de negócio, gestor de contrato de licitação), o registro do marco é uma etapa com significado de negócio próprio. Colapsar tudo em uma única `ServiceTask` "Criar Análise + Registrar Marco" obscureceria a importância do rastreio temporal para o processo de controle de prazos.

---

### 4.7 Gateway de Pré-análise Automática

**Elemento:** `GW_PreAnalise` — Gateway exclusivo (losango com X).

Este é o **gateway mais estratégico** do P06-A. Ele determina se a análise da isenção será feita automaticamente pelo sistema ou manualmente por um analista ADM do CBM-RS.

A decisão baseia-se na consulta ao parâmetro de sistema:

```
ParametroNcsED.chave = 'APROVA_ISENCAOTAXA_PREANALISE'
Tabela: CBM_PARAMETRO_NCS
Valor: 'S' (true via SimNaoBooleanConverter) → automático
Valor: 'N' (false) → manual
```

**Por que esse parâmetro existe?**

O CBM-RS pode optar por ativar ou desativar a pré-análise automática por razões operacionais (período de alta demanda, política interna, mudança legislativa). Centralizar essa decisão em um parâmetro de banco de dados, em vez de hard-code, dá ao órgão autonomia para ajustar o comportamento sem necessidade de novo deploy do sistema.

**Por que gateway exclusivo e não paralelo?**

Os dois caminhos (automático e manual) são mutuamente exclusivos para uma mesma solicitação: ou o sistema avalia automaticamente, ou o ADM avalia manualmente. Nunca os dois ao mesmo tempo. Um gateway paralelo geraria os dois fluxos simultaneamente, o que não corresponde à realidade de negócio.

---

### 4.8 Caminho A — Pré-análise Automática de NCS

Quando `APROVA_ISENCAOTAXA_PREANALISE = 'S'`, o sistema executa a análise sem intervenção humana:

#### Task_BE_AvaliarNCS — Avaliação de Não Conformidades

**Classe:** `AnaliseLicenciamentoIsencaoRN` — bloco de avaliação NCS.

O sistema percorre a lista de `JustificativaNcsIsencaoED` associada à análise. Cada registro representa uma "Não Conformidade" (NCS) que o sistema deve verificar: por exemplo, se o requerente é MEI, se possui certidão de entidade filantrópica, se é órgão público, etc. Para cada NCS, consulta o `ParametroNcsED` correspondente para obter os critérios de avaliação.

A avaliação resulta em `StatusAnaliseLicenciamentoIsencao.APROVADO` ou `REPROVADO`.

A entidade `JustificativaNcsIsencaoED` usa `@ManyToOne` com `fetch = LAZY` para o `ParametroNcsED`, o que significa que os parâmetros são carregados sob demanda — comportamento adequado para o contexto de análise unitária de uma solicitação.

#### GW_NCSAprovado — Resultado da Pré-análise

Gateway exclusivo que direciona o fluxo conforme o resultado da avaliação de NCS.

**[Aprovado — automático]**

A sequência `Task_BE_AprovarAuto → Task_BE_MarcoAprovAuto → Task_SOE_NotifAprovAuto → End_P06A_AprovadoAuto` executa:

1. `situacaoIsencao = APROVADA`, `analista = "SISTEMA"` — o sistema é registrado como "analista" para identificar que foi pré-análise automática, distinguindo de uma análise humana no histórico.
2. Chamada ao `trocaEstadoLicenciamento()` — o licenciamento avança de `AGUARDANDO_PAGAMENTO` para `AGUARDANDO_DISTRIBUICAO`, pois a isenção elimina a necessidade de pagamento e o processo pode prosseguir para distribuição entre os analistas técnicos.
3. Marco `ANALISE_ISENCAO_APROVADO` registrado.
4. E-mail de aprovação enviado via SOE PROCERGS.

**[Reprovado — automático]**

A sequência `Task_BE_ReprovarAuto → Task_BE_MarcoReprovAuto → Task_SOE_NotifReprovAuto → End_P06A_ReprovadoAuto` executa:

1. `situacaoIsencao = REPROVADA`, `analista = "SISTEMA"`.
2. O licenciamento **permanece** em `AGUARDANDO_PAGAMENTO` — a reprovação da isenção significa que a taxa deve ser paga normalmente.
3. **NÃO** chama `trocaEstadoLicenciamento()` — este ponto é crítico: invocar a troca de estado incorretamente colocaria o licenciamento em distribuição sem pagamento, o que seria uma falha grave de negócio.
4. Marco `ANALISE_ISENCAO_REPROVADO` registrado.
5. E-mail de reprovação enviado.

---

### 4.9 Caminho B — Análise Manual pelo ADM CBM-RS

Quando `APROVA_ISENCAOTAXA_PREANALISE = 'N'`, o fluxo segue para análise humana, composto pelas seguintes etapas:

#### Task_ADM_ListarPendentes — Consulta da Fila de Isenções Pendentes

**Classe REST:** `AnaliseLicenciamentoIsencaoAdmRestImpl`.
**Endpoint:** `GET /adm/analise-licenciamentos-isencao`.
**Permissão:** `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")`.

O analista ADM acessa o painel administrativo e visualiza a lista de solicitações com `situacaoIsencao = SOLICITADA`. Esta tarefa representa o momento em que o analista "toma ciência" da demanda — ele escolhe qual solicitação analisar a seguir, podendo priorizar por data, tipo de estabelecimento ou outros critérios visíveis na interface.

**Nota de modelagem:** esta tarefa também é o ponto de retorno no ciclo de renovação (quando o cidadão solicita nova análise após reprovação). A `incoming` do fluxo `SF_GW_Renovacao_Sim` aponta para esta mesma tarefa, modelando corretamente que o ADM precisa "ver novamente" a solicitação na sua fila — desta vez com `situacaoIsencao = SOLICITADA_RENOV` — antes de analisar.

#### Task_RT_EnviarComprovante — Envio de Comprovante de Isenção (Opcional)

**Classe REST:** `ComprovanteIsencaoRestImpl`.
**Endpoint:** `POST /licenciamentos/{id}/comprovante-isencao`.
**Classe RN:** `ComprovanteIsencaoRN`.

Esta tarefa representa a possibilidade de o cidadão anexar documentos probatórios da isenção — certidão de MEI, declaração de entidade filantrópica, etc. É modelada como `UserTask` na raia do Cidadão / RT porque é uma ação voluntária do usuário, não um passo obrigatório do sistema.

**Por que essa tarefa está no fluxo entre "listar pendentes" e "analisar isenção"?**

No processo real, o cidadão pode enviar comprovantes a qualquer momento após solicitar a isenção e antes de o ADM concluir a análise. A posição no fluxo reflete a janela de oportunidade mais provável: após o ADM listar e consultar a solicitação (tornando o cidadão ciente de que precisa apresentar documentos), e antes de o ADM registrar a decisão final.

#### Task_Alf_UploadComprovante — Armazenamento no Alfresco

**Classe:** `ArquivoRN` (EJB `@Stateless`).

Após o cidadão submeter o arquivo, o sistema realiza o upload no Alfresco ECM:

1. Verifica se já existe um comprovante anterior para o licenciamento. Se sim, remove-o do Alfresco (`ArquivoRN.removerArquivo(nodeRef)`) antes de fazer o novo upload — garantindo que haja sempre no máximo um comprovante por licenciamento.
2. Faz o POST multipart para o Alfresco e obtém o `{ entry: { id: "{UUID}" } }`.
3. Constrói o `nodeRef`: `workspace://SpacesStore/{UUID}`.
4. Persiste `ComprovanteIsencaoED.identificadorAlfresco = nodeRef` no banco relacional.

**Por que esta tarefa está na raia Alfresco / SOE e não na raia Backend?**

A separação na raia `Alfresco / SOE PROCERGS` é uma decisão de clareza: embora o código que executa o upload seja um EJB Java no WildFly, o *efeito* dessa tarefa é a criação de um nó em um sistema externo (Alfresco). Colocar essa tarefa na raia Backend misturaria a lógica interna (persistência relacional) com a integração externa (ECM). A raia Alfresco sinaliza ao leitor — e ao avaliador técnico da licitação — que existe uma dependência de disponibilidade do Alfresco neste ponto do processo.

#### Task_ADM_AnalisarIsencao — Registro da Decisão pelo ADM

**Permissão:** `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")`.
**Endpoint:** `POST /adm/analise-licenciamentos-isencao`.

O analista ADM visualiza todos os dados pertinentes — dados do licenciamento, dados do estabelecimento, dados do RT, justificativa do cidadão, comprovantes no Alfresco — e registra sua decisão:

- `StatusAnaliseLicenciamentoIsencao.APROVADO` ou `REPROVADO`.
- Parecer obrigatório em ambos os casos (`RN_P06A_10`).
- Avaliação individual de cada NCS listado.

A obrigatoriedade do parecer serve como registro da motivação da decisão para fins de transparência administrativa e eventual recurso.

#### Task_BE_RegistrarDecisao — Persistência da Decisão

**Classe:** `AnaliseLicenciamentoIsencaoRN.inclui()`.

Esta é a tarefa central da análise manual. O método `inclui()` executa a sequência completa:

1. Revalida o estado do licenciamento (segunda chamada ao `RNVal`) — proteção contra race condition, caso o estado tenha mudado enquanto o ADM estava analisando.
2. Constrói a entidade com os dados do ADM (analista, data, parecer, statusAnalise, NCS).
3. Ramifica conforme a decisão:
   - **REPROVADO:** atualiza `situacaoIsencao = REPROVADA`, não altera o licenciamento.
   - **APROVADO:** atualiza `situacaoIsencao = APROVADA`, chama `trocaEstadoLicenciamento()`.
4. Persiste via `entityManager.merge()`.
5. Auditoria Envers registra o momento, o usuário e os valores anteriores/posteriores.

A revalidação no passo 1 é uma salvaguarda implementada no código real que o BPMN abstrai: o gateway `GW_EstadoValido` modelou essa verificação mais cedo no fluxo, mas o `inclui()` a repete internamente como defesa em profundidade.

---

### 4.10 Troca de Estado do Licenciamento (Aprovação)

**Elemento:** `Task_BE_TrocaEstadoAprov` — `ServiceTask`.
**Método:** `AnaliseLicenciamentoIsencaoRN.trocaEstadoLicenciamento()`.

Este método contém a lógica de decisão sobre qual `TrocaEstadoRN` invocar, usando qualificadores CDI:

```
if (licenciamento.hasEndereco() AND NOT licenciamento.isInviabilidade()):
    @TrocaEstadoEnderecoRN → AGUARDANDO_DISTRIBUICAO
else if (licenciamento.isInviabilidade()):
    @TrocaEstadoInviabilidadeRN → estado específico de inviabilidade
else:
    @TrocaEstadoPadraoRN → AGUARDANDO_DISTRIBUICAO
```

**Por que três implementações de TrocaEstadoRN?**

O padrão Strategy via CDI qualificadores resolve a variação de comportamento dependendo das características do licenciamento sem usar `if/else` espalhados pelo código. Licenciamentos de endereço, de inviabilidade e o caso padrão têm transições de estado ligeiramente diferentes. Centralizar essa lógica em classes especializadas é uma decisão de design do sistema atual que o BPMN reflete atribuindo o `camunda:class` à classe RN que orquestra as três estratégias, em vez de modelar três tarefas separadas para cada caso.

No BPMN, esse nível de detalhe (qual dos três qualificadores é usado) está documentado no `<documentation>` da tarefa, mas não se ramifica em três gateways — pois isso adicionaria complexidade visual sem corresponder a uma diferença observável no fluxo de negócio do ponto de vista do cidadão ou do ADM.

---

### 4.11 Reprovação e Ciclo de Renovação

Quando a análise manual resulta em `REPROVADO`, o fluxo executa:

1. `Task_BE_SituacaoReprovada`: atualiza `situacaoIsencao = REPROVADA`, registra o parecer do ADM, mantém o licenciamento em `AGUARDANDO_PAGAMENTO`.
2. `Task_BE_MarcoReprovManual`: registra `TipoMarco.ANALISE_ISENCAO_REPROVADO`.
3. `Task_SOE_NotifReprovManual`: envia e-mail de reprovação com motivo e orientação.
4. `GW_Renovacao`: pergunta se o cidadão deseja solicitar renovação.

#### Gateway GW_Renovacao — Mecanismo de Renovação

Este gateway é exclusivo do P06-A (não existe no P06-B) e reflete o mecanismo real implementado na classe `IsencaoTaxaReanaliseRN`:

- **[Sim — renovação]:** o cidadão pode apresentar novos documentos e pedir nova análise. O endpoint `PUT /adm/analise-licenciamentos-isencao/{id}` atualiza `situacaoIsencao = SOLICITADA_RENOV`, e o fluxo retorna à `Task_ADM_ListarPendentes`. O BPMN modela esse retorno como um arco de volta (*loop*) conectando o gateway ao topo da fila de análise manual, evidenciando que o processo é iterativo — pode haver múltiplos ciclos de reprovação e renovação.

- **[Não — encerrado]:** o processo termina definitivamente em `End_P06A_ReprovadoManual`. O cidadão deve efetuar o pagamento da taxa.

**Controle de prazo no ciclo de renovação:**

A classe `IsencaoTaxaReanaliseRN` implementa um cálculo cumulativo de prazos usando a constante `PRAZO_CORRECAO = 30L` dias. O sistema soma os intervalos entre marcos de ciência e correção ao longo de todos os ciclos, garantindo que o cidadão não exceda 30 dias de prazo acumulado para apresentar documentos corrigidos. Embora esse controle não seja modelado como um timer no BPMN (pois no sistema atual é verificado sob demanda, não por evento de tempo), o `<documentation>` da tarefa e do gateway o menciona explicitamente.

**Marcos de renovação:**

Quando a renovação é aprovada ou reprovada, os marcos usados são `ANALISE_ISENCAO_RENOV_APROVADO` e `ANALISE_ISENCAO_RENOV_REPROVADO` (em vez de `ANALISE_ISENCAO_APROVADO` e `ANALISE_ISENCAO_REPROVADO`), permitindo distinguir no histórico quais análises foram de primeira instância e quais foram resultado de renovação.

---

### 4.12 Notificações por E-mail via SOE PROCERGS

**Elementos:** `Task_SOE_NotifAprovAuto`, `Task_SOE_NotifReprovAuto`, `Task_SOE_NotifAprovManual`, `Task_SOE_NotifReprovManual`.
**Classe:** `LicenciamentoAdmNotificacaoRN` (EJB `@Stateless`).
**Método:** `notificarIsencaoDeTaxaRevisada(Long idLicenciamento, Boolean aprovado)`.

Todas as quatro notificações usam:
- Template: `"notificacao.email.template.licenciamento.isencao"`
- Assunto: `"notificacao.assunto.isencao.analisada"`

O único parâmetro que varia é `aprovado = true` (aprovação) ou `aprovado = false` (reprovação). O template é renderizado no servidor e o e-mail enviado via `SoeEmailService`, que se autentica no SOE PROCERGS com credenciais de serviço (`@SOEAuthRest`).

**Por que há quatro tarefas de notificação separadas e não uma única?**

Os quatro resultados possíveis (aprovado automático, reprovado automático, aprovado manual, reprovado manual) são modelados com tarefas de notificação separadas porque, embora usem o mesmo método, ocorrem em pontos diferentes do fluxo e em contextos distintos. Modelar uma única tarefa de notificação centralizada exigiria um gateway antes dela para determinar qual mensagem enviar — o que não simplificaria o diagrama. A separação mantém cada caminho do fluxo autocontido e legível de ponta a ponta.

---

### 4.13 Eventos de Fim do P06-A

O processo P06-A possui cinco eventos de fim, cada um com semântica própria:

| Evento | Situação final | Tipo BPMN |
|---|---|---|
| `End_P06A_EstadoInvalido` | Licenciamento não elegível (HTTP 406) | Fim de erro (`errorEventDefinition`) |
| `End_P06A_AprovadoAuto` | Isenção concedida por pré-análise automática | Fim normal |
| `End_P06A_ReprovadoAuto` | Isenção negada por pré-análise automática | Fim normal |
| `End_P06A_AprovadoManual` | Isenção concedida por análise manual do ADM | Fim normal |
| `End_P06A_ReprovadoManual` | Isenção negada definitivamente (sem renovação) | Fim normal |

O uso de múltiplos eventos de fim é uma decisão de modelagem deliberada: em vez de convergir todos os caminhos em um único fim, cada caminho tem seu próprio evento com documentação do estado resultante. Isso facilita a rastreabilidade — ao ler o diagrama, fica claro quais são os possíveis desfechos e qual estado o sistema fica em cada um deles.

---

## 5. P06-B — Isenção de Taxa de FACT: Fluxo Completo

O P06-B segue uma estrutura mais simples que o P06-A, pois não possui pré-análise automática nem mecanismo de renovação. É um fluxo linear de solicitação → análise manual → decisão → notificação.

### 5.1 Início do Processo FACT

**Elemento:** `Start_P06B` — Evento de início simples.

O processo inicia quando um FACT (Formulário de Atendimento e Consulta Técnica) está com taxa pendente e o cidadão ou RT decide solicitar isenção. O contexto de pré-condição é diferente do P06-A: no FACT, o estado `AGUARDANDO_PAGAMENTO_ISENCAO` já sinaliza que o processo está aguardando especificamente a isenção ou o pagamento — é uma situação de FACT criada com a flag de isenção pendente desde o início, distinto do licenciamento que chega ao estado `AGUARDANDO_PAGAMENTO` por um fluxo prévio de submissão técnica.

---

### 5.2 Solicitação pelo Cidadão ou RT

**Elemento:** `Task_RTB_SolicitarIsencaoFact` — `UserTask` na raia Cidadão / RT.
**Classe REST:** `AnaliseFactIsencaoRestImpl`.
**Endpoint:** `POST /facts/{id}/solicitacaoIsencao`.
**Método RN:** `AnaliseFactIsencaoRN.incluiCidadao()`.
**Segurança:** `@Permissao(desabilitada=true)`.

A anotação `@Permissao(desabilitada=true)` é uma particularidade notável do P06-B. No P06-A, o endpoint de solicitação é protegido por `@AutorizaEnvolvido`. No P06-B, a permissão está explicitamente desabilitada, o que significa que qualquer usuário autenticado pode acessar o endpoint (sem verificar se é RT ou RU daquele FACT específico). A validação de pertencimento ao FACT é feita pela lógica interna do RN, não pelo interceptor de segurança.

Essa diferença de implementação entre P06-A e P06-B é refletida na documentação das respectivas tarefas no BPMN, alertando para a distinção de mecanismo de controle de acesso.

---

### 5.3 Criação da Análise de Isenção do FACT

**Elemento:** `Task_BEB_CriarAnaliseFact` — `ServiceTask`.
**Classe:** `AnaliseFactIsencaoRN.incluiCidadao()`.

A entidade `AnaliseFactIsencaoED` é criada com `statusAnalise = StatusAnaliseFactIsencao.SOLICITADA`. Uma diferença importante em relação ao P06-A: a entidade `JustificativaNcsFactIsencaoED` (equivalente ao `JustificativaNcsIsencaoED` do P06-A) usa `@ManyToOne fetch=EAGER` para o `ParametroNcsED`, em vez de `LAZY`. Isso significa que ao carregar qualquer `JustificativaNcsFactIsencaoED`, os `ParametroNcsED` associados são carregados imediatamente no mesmo SELECT JOIN. Essa diferença de fetch strategy foi anotada no `<documentation>` da tarefa porque pode impactar performance em consultas que retornam muitos registros.

---

### 5.4 Análise Manual pelo ADM CBM-RS

O P06-B **não possui pré-análise automática**. Toda solicitação de isenção de FACT passa obrigatoriamente pela análise manual do ADM, o que simplifica o fluxo em relação ao P06-A: após o marco de solicitação, o fluxo vai diretamente para a fila do ADM.

#### Task_ADMB_ListarPendentesFact

**Endpoint:** `GET /adm/analises-fact-isencao`.
**Permissão:** `@Permissao(objeto="ISENCAOTAXA", acao="LISTAR")`.
**Método RN:** `AnaliseFactIsencaoRN.lista()`.
**Filtro:** `statusAnalise = StatusAnaliseFactIsencao.SOLICITADA`.

O ADM visualiza a lista de FACTs com isenção pendente, podendo também consultar os comprovantes enviados pelo cidadão via `GET /comprovantes-isencao-fact` e os retornos de solicitação via `GET /retornos-solicitacao-fact/fact/{idFact}` (endpoint da classe `RetornosSolicitacaoFactRestImpl`).

#### Task_ADMB_AnalisarIsencaoFact

**Endpoint:** `POST /adm/analises-fact-isencao`.
**Permissão:** `@Permissao(objeto="ISENCAOTAXA", acao="REVISAR")`.

O ADM registra a decisão via DTO `AnaliseFactIsencaoDTO`. A análise de NCS para FACT usa a entidade `JustificativaNcsFactIsencaoED` (carregada com EAGER, conforme mencionado).

#### Task_BEB_RegistrarDecisaoFact

**Classe:** `AnaliseFactIsencaoRN.inclui()`.

O método `inclui()` para FACT executa a lógica completa de persistência. A sequência diverge significativamente do P06-A na ramificação de aprovação:

**Se REPROVADO:**
- `factED.setIsencao(false)` → `IND_ISENCAO = 'N'` via `SimNaoBooleanConverter`.
- `factED.setSituacao(StatusFact.ISENCAO_REJEITADA)`.
- O FACT retorna à situação de cobrança normal. **Não há renovação.**

**Se APROVADO:**
- `factED.setIsencao(true)` → `IND_ISENCAO = 'S'`.
- `geraNumeroFactRN.gerarNumero(idFact)` — gera o número sequencial do FACT.
- `factED.setNrFact(numeroGerado)`.
- `factED.setSituacao(StatusFact.AGUARDANDO_DISTRIBUICAO)`.

O método `reprovarSolicitacaoIsencaoDeTaxaDeAnalise()` (existente no código) é um método distinto do `inclui()` para uso em cenários de recurso administrativo, onde o FACT fica em `AGUARDANDO_PAGAMENTO_ISENCAO` (não em `ISENCAO_REJEITADA`). O fluxo modelado no BPMN usa `inclui()` — a decisão final do ADM, não o recurso.

---

### 5.5 Aprovação: Geração do Número do FACT

**Elemento:** `Task_BEB_GerarNumeroFact` — `ServiceTask`.
**Classe:** `GeraNumeroFactRN` (EJB `@Stateless`).
**Método:** `gerarNumero(Long idFact)`.

A geração do número do FACT é um evento de significado operacional elevado: antes da aprovação da isenção, o FACT não possui número (campo `nrFact = null`). Após a aprovação, o número é gerado e o FACT entra na fila de distribuição dos analistas técnicos com identidade própria.

**Por que essa tarefa está separada da Task_BEB_AprovarFact?**

A separação segue o princípio de responsabilidade única: `Task_BEB_AprovarFact` atualiza o flag de isenção (`IND_ISENCAO = 'S'`), enquanto `Task_BEB_GerarNumeroFact` executa a lógica de numeração sequencial. São operações com propósitos distintos e que, em uma refatoração futura, poderiam ser implementadas por classes distintas. A separação no BPMN torna visível essa distinção para o avaliador técnico da licitação, que pode questionar como o sistema garante unicidade do número (via sequence Oracle/PostgreSQL ou MAX+1).

A regra `RN_P06B_20` é explícita: o número FACT gerado é permanente e não pode ser alterado após a aprovação.

---

### 5.6 Reprovação do FACT — Decisão Final

**Elemento:** `Task_BEB_ReprovarFact` — `ServiceTask`.

A reprovação do FACT é **definitiva**. Não existe mecanismo de renovação para isenção de FACT (diferente do P06-A, que permite `SOLICITADA_RENOV`). Após a reprovação:

- `factED.isencao = false` (`'N'`).
- `factED.situacao = StatusFact.ISENCAO_REJEITADA`.

O cidadão deve efetuar o pagamento normal da taxa do FACT para prosseguir.

**Por que não há renovação no P06-B?**

A ausência de renovação no P06-B reflete a regra de negócio do CBM-RS tal como implementada no código-fonte: a classe `IsencaoTaxaReanaliseRN` com `PRAZO_CORRECAO = 30L` não é utilizada em nenhum ponto da cadeia de chamadas do P06-B. Não há método equivalente a `atualizaSolicitacaoIsencao()` para FACT. O BPMN documenta essa ausência explicitamente nos eventos de fim e na documentação dos elementos de decisão.

---

### 5.7 Eventos de Fim do P06-B

| Evento | Situação final | Estado do FACT |
|---|---|---|
| `End_P06B_AprovadoFact` | Isenção FACT concedida | `isencao = true`, `nrFact = gerado`, `situacao = AGUARDANDO_DISTRIBUICAO` |
| `End_P06B_ReprovadoFact` | Isenção FACT negada (definitiva) | `isencao = false`, `situacao = ISENCAO_REJEITADA` |

---

## 6. Máquinas de Estado Modeladas

O BPMN documenta implicitamente as máquinas de estado das entidades principais. As transições são:

### P06-A — AnaliseLicenciamentoIsencaoED.situacaoIsencao (TipoSituacaoIsencao)

```
[início]
    │
    ▼
SOLICITADA ──(auto/manual aprovado)──▶ APROVADA
    │
    │──(auto/manual reprovado)──▶ REPROVADA ──(renovação)──▶ SOLICITADA_RENOV
                                                                    │
                                                          ◀─────────┘
                                                    (reinicia ciclo de análise)
```

### P06-A — LicenciamentoED.situacao (transição decorrente da aprovação)

```
AGUARDANDO_PAGAMENTO ──(isenção aprovada)──▶ AGUARDANDO_DISTRIBUICAO
AGUARDANDO_PAGAMENTO ──(isenção reprovada)──▶ AGUARDANDO_PAGAMENTO (permanece)
```

### P06-B — FactED.situacao (StatusFact)

```
AGUARDANDO_PAGAMENTO_ISENCAO ──(aprovado)──▶ AGUARDANDO_DISTRIBUICAO
AGUARDANDO_PAGAMENTO_ISENCAO ──(reprovado)──▶ ISENCAO_REJEITADA
```

### P06-B — FactED.isencao (SimNaoBooleanConverter)

```
null ou false ──(aprovado)──▶ true ('S' no BD)
null ou false ──(reprovado)──▶ false ('N' no BD)
```

A utilização do `SimNaoBooleanConverter` é uma decisão técnica do sistema atual para compatibilidade com um banco legado que armazena booleanos como caracteres `'S'/'N'`. O BPMN documenta essa conversão nos elementos relevantes para que o novo sistema licitado saiba que precisa tratar essa semântica.

---

## 7. Rastreabilidade dos Marcos (TipoMarco)

O processo P06 registra 10 marcos distintos ao longo de seu ciclo de vida. A tabela abaixo mapeia cada marco ao momento de registro e ao seu propósito:

### P06-A

| Marco | Quando é registrado | Propósito |
|---|---|---|
| `SOLICITACAO_ISENCAO` | Imediatamente após criação da `AnaliseLicenciamentoIsencaoED` | Âncora temporal para cálculo de prazo; rastreio de quando a solicitação foi feita |
| `ANALISE_ISENCAO_APROVADO` | Após aprovação (automática ou manual) e troca de estado | Confirma concessão da isenção; disparador para relatórios de isenções aprovadas |
| `ANALISE_ISENCAO_REPROVADO` | Após reprovação (automática ou manual) | Registra negativa para auditoria e eventual recurso |
| `ANALISE_ISENCAO_RENOV_APROVADO` | Após aprovação em ciclo de renovação | Distingue aprovações de primeira análise de aprovações em renovação |
| `ANALISE_ISENCAO_RENOV_REPROVADO` | Após reprovação em ciclo de renovação | Idem para negativas em renovação |
| `ENVIO_ATEC` | Em contexto de envio de parecer técnico (ATEC) | Marco relacionado a comunicações técnicas formais |

### P06-B

| Marco | Quando é registrado | Propósito |
|---|---|---|
| `SOLICITACAO_ISENCAO_FACT` | Após criação da `AnaliseFactIsencaoED` | Rastreio da data/hora da solicitação de isenção do FACT |
| `NRO_FACT` | Após `GeraNumeroFactRN.gerarNumero()` | Confirma que o número do FACT foi gerado; marco de identidade do processo |
| `ANALISE_ISENCAOFACT_APROVADO` | Após aprovação da isenção do FACT | Confirma concessão da isenção de taxa do FACT |
| `ANALISE_ISENCAOFACT_REPROVADO` | Após reprovação da isenção do FACT | Registra negativa definitiva para auditoria |

---

## 8. Diferenças Fundamentais entre P06-A e P06-B

A tabela abaixo consolida as diferenças que justificam a modelagem como dois pools separados:

| Característica | P06-A (Licenciamento) | P06-B (FACT) |
|---|---|---|
| **Entidade principal** | `AnaliseLicenciamentoIsencaoED` | `AnaliseFactIsencaoED` |
| **Tabela** | `CBM_ANALISE_LIC_ISENCAO` | `CBM_ANALISE_FACT_ISENCAO` |
| **Endpoint de solicitação** | `POST /licenciamentos/{id}/solicitacaoIsencao` | `POST /facts/{id}/solicitacaoIsencao` |
| **Segurança no endpoint** | `@AutorizaEnvolvido` | `@Permissao(desabilitada=true)` |
| **Pré-análise automática** | Sim (parâmetro `APROVA_ISENCAOTAXA_PREANALISE`) | Não — sempre manual |
| **Mecanismo de renovação** | Sim (`SOLICITADA_RENOV`, prazo 30 dias) | Não — decisão final |
| **Fetch do NCS** | `@ManyToOne fetch=LAZY` | `@ManyToOne fetch=EAGER` |
| **Troca de estado ao aprovar** | `trocaEstadoLicenciamento()` (3 estratégias CDI) | `factED.setSituacao(AGUARDANDO_DISTRIBUICAO)` direto |
| **Geração de número** | Não aplica (nrLicenciamento já existe) | Sim: `GeraNumeroFactRN.gerarNumero()` |
| **Flag de isenção** | `AnaliseLicenciamentoIsencaoED.situacaoIsencao` | `FactED.isencao` (`SimNaoBooleanConverter`) |
| **Estado ao reprovar** | `AGUARDANDO_PAGAMENTO` (permanece) | `ISENCAO_REJEITADA` |
| **Marcos registrados** | 5 tipos distintos (+ ENVIO_ATEC) | 4 tipos distintos |
| **Comprovante (Alfresco)** | `ComprovanteIsencaoED` / `ArquivoRN` | `ComprovanteIsencaoRN` / `ArquivoRN` (compartilham endpoint base) |

---

## 9. Padrões de Implementação Refletidos no BPMN

O BPMN do P06 documenta, em suas tarefas e anotações, os seguintes padrões de implementação do sistema SOL:

### Padrão de Camadas

Todas as `ServiceTask` usam o atributo `camunda:class` referenciando as classes `*RN` (Regras de Negócio, EJB `@Stateless`), nunca as classes `*RestImpl` ou `*BD`. Isso reflete o padrão correto de responsabilidade:

```
RestImpl (@Path) → RN (@Stateless) → BD (JPA/JPQL) → ED (@Entity)
```

### Padrão Strategy via CDI

A existência de três qualificadores CDI (`@TrocaEstadoEnderecoRN`, `@TrocaEstadoInviabilidadeRN`, `@TrocaEstadoPadraoRN`) para a operação de troca de estado é documentada na `Task_BE_TrocaEstadoAprov`. O BPMN não fragmenta essa lógica em três tarefas separadas, pois é um detalhe de implementação (Strategy) que não corresponde a três caminhos de negócio distintos do ponto de vista do usuário.

### SimNaoBooleanConverter

O conversor `Boolean ↔ 'S'/'N'` é documentado em todas as tarefas que operam sobre campos mapeados por ele (`FactED.isencao`, `JustificativaNcsIsencaoED.indAprovado`). Isso alerta o sistema licitado para a necessidade de manter compatibilidade com esse mapeamento ou migrar os dados durante a implantação.

### Auditoria Envers

A anotação `@Audited` nas entidades principais gera tabelas `*_AUD` automaticamente. O BPMN documenta esse comportamento nas tarefas de persistência, sinalizando que toda criação e alteração de `AnaliseLicenciamentoIsencaoED` e `AnaliseFactIsencaoED` produz registros auditáveis sem código adicional.

### Integração com Sistemas Externos

O BPMN usa a raia **Alfresco / SOE PROCERGS** para agrupar as tarefas de integração com sistemas externos, evidenciando duas dependências críticas de infraestrutura que o novo sistema licitado deverá atender:

- **Alfresco ECM:** armazenamento de documentos probatórios de isenção. A integração usa a API REST do Alfresco (Content Services Platform) com autenticação Basic. O nodeRef no formato `workspace://SpacesStore/{UUID}` é o identificador persistido no banco relacional.

- **SOE PROCERGS:** serviço de e-mail do Estado do Rio Grande do Sul. A integração usa `SoeEmailService` com autenticação via `@SOEAuthRest`. O template e o assunto são chaves de internacionalização resolvidas no servidor antes do envio.

---

*Documento produzido a partir da análise do código-fonte real em `SOLCBM.BackEnd16-06\` e do BPMN `P06_IsencaoTaxa_StackAtual.bpmn`.*
*Padrão de documentação: mesmo adotado em `Descritivo_P03_FluxoBPMN_StackAtual.md` e `Descritivo_P05_FluxoBPMN_StackAtual.md`.*
