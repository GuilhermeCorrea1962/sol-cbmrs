# Descritivo do Fluxo BPMN — P14: Renovação de Licenciamento (APPCI/Alvará)
## Stack Atual (Java EE 7 · EJB 3.2 · CDI · JAX-RS · JPA/Hibernate · Oracle · WildFly)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P14 — Renovação de Licenciamento (APPCI/Alvará)
**Arquivo BPMN:** `P14_RenovacaoLicenciamento_StackAtual.bpmn`
**Data:** 2026-03-16
**Regras de Negócio cobertas:** RN-141 a RN-160

---

## Sumário

1. [Visão geral do modelo](#1-visão-geral-do-modelo)
2. [Decisão de estrutura: pool único com quatro raias](#2-decisão-de-estrutura-pool-único-com-quatro-raias)
3. [Fase 1 — Iniciação da Renovação](#3-fase-1--iniciação-da-renovação)
   - 3.1 [SE_Inicio — Start Event](#31-se_inicio--start-event-none)
   - 3.2 [T_IniciarRenovacao — User Task](#32-t_iniciarRenovacao--user-task)
   - 3.3 [T_ValidarElegibilidade — Service Task](#33-t_validarelegibilidade--service-task)
   - 3.4 [GW_ValidacaoOK — Exclusive Gateway](#34-gw_validacaook--exclusive-gateway)
   - 3.5 [EE_NaoPermitida — End Event](#35-ee_naopermitida--end-event)
   - 3.6 [T_MudarAguardandoAceite — Service Task](#36-t_mudaraguardandoaceite--service-task)
4. [Fase 2 — Aceite do Anexo D](#4-fase-2--aceite-do-anexo-d)
   - 4.1 [T_AceitarAnexoD — User Task (dupla entrada)](#41-t_aceitaranexod--user-task-dupla-entrada)
   - 4.2 [GW_DecisaoAceite — Exclusive Gateway](#42-gw_decisaoaceite--exclusive-gateway)
   - 4.3 [T_RollbackEstado — Service Task](#43-t_rollbackestado--service-task)
   - 4.4 [EE_CancelRenovacao — End Event](#44-ee_cancelrenovacao--end-event)
   - 4.5 [T_MudarAguardandoPagamento — Service Task](#45-t_mudaraguardandopagamento--service-task)
5. [Fase 3 — Pagamento ou Isenção da Taxa de Vistoria](#5-fase-3--pagamento-ou-isenção-da-taxa-de-vistoria)
   - 5.1 [GW_IsencaoOuPagamento — Exclusive Gateway](#51-gw_isencaoupagamento--exclusive-gateway)
   - 5.2 [T_SolicitarIsencao — User Task](#52-t_solicitarisencao--user-task)
   - 5.3 [T_AnalisarIsencao — User Task](#53-t_analisarisencao--user-task)
   - 5.4 [GW_IsencaoAprovada — Exclusive Gateway](#54-gw_isencaoaprovada--exclusive-gateway)
   - 5.5 [T_GerarBoleto — Service Task (dupla entrada)](#55-t_gerarboleto--service-task-dupla-entrada)
   - 5.6 [T_PagarBoleto — User Task](#56-t_pagarboleto--user-task)
   - 5.7 [T_ConfirmarPagamento — Service Task](#57-t_confirmarpagamento--service-task)
   - 5.8 [GW_MergeAntesDist — Exclusive Gateway (merge)](#58-gw_mergeantesDist--exclusive-gateway-merge)
   - 5.9 [T_MudarAguardandoDistribuicao — Service Task](#59-t_mudaraguardandodistribuicao--service-task)
6. [Fase 4 — Distribuição da Vistoria de Renovação](#6-fase-4--distribuição-da-vistoria-de-renovação)
   - 6.1 [T_DistribuirVistoria — User Task](#61-t_distribuirvistoria--user-task)
   - 6.2 [T_MudarEmVistoriaRenovacao — Service Task](#62-t_mudaremvistoriarenovacao--service-task)
7. [Fase 5 — Execução da Vistoria de Renovação](#7-fase-5--execução-da-vistoria-de-renovação)
   - 7.1 [T_RealizarVistoria — User Task](#71-t_realizarvistoria--user-task)
   - 7.2 [T_EnviarRelatorioVistoria — User Task](#72-t_enviarrelatoriovistoria--user-task)
   - 7.3 [T_HomologarVistoria — User Task](#73-t_homologarvistoria--user-task)
   - 7.4 [GW_VistoriaAprovada — Exclusive Gateway](#74-gw_vistoriaaprovada--exclusive-gateway)
8. [Fase 6A — Conclusão: Deferido](#8-fase-6a--conclusão-deferido--alvara_vigente)
   - 8.1 [T_EmitirAPPCI — Service Task](#81-t_emitirappci--service-task)
   - 8.2 [T_CienciaAPPCI — User Task](#82-t_cienciaappci--user-task)
   - 8.3 [EE_AlvaraVigente — End Event](#83-ee_alvaravigente--end-event)
9. [Fase 6B — Conclusão: Indeferido / CIV](#9-fase-6b--conclusão-indeferido--civ)
   - 9.1 [T_EmitirCIV — Service Task](#91-t_emitirciv--service-task)
   - 9.2 [T_CienciaCIV — User Task](#92-t_cienciaciv--user-task)
   - 9.3 [GW_RecursoCIV — Exclusive Gateway](#93-gw_recursociv--exclusive-gateway)
   - 9.4 [EE_RecursoSolicitado — End Event](#94-ee_recursosolitado--end-event)
   - 9.5 [T_MudarCIVParaAguardandoAceite — Service Task e loop de retorno](#95-t_mudarcivparaaguardandoaceite--service-task-e-loop-de-retorno)
10. [Tabela de rastreabilidade](#10-tabela-de-rastreabilidade)
11. [Justificativas consolidadas de modelagem](#11-justificativas-consolidadas-de-modelagem)

---

## 1. Visão geral do modelo

O BPMN do processo P14 representa a **Renovação de Licenciamento de APPCI** (Alvará de Prevenção e Proteção Contra Incêndio) para estabelecimentos cujo alvará se encontra em vigor (`ALVARA_VIGENTE`) ou recentemente vencido (`ALVARA_VENCIDO`). É o processo mais longo do SOL em termos de atores envolvidos: **cidadão ou RT, CBMRS Admin, CBMRS Inspetor e o próprio Sistema** participam em sequência ao longo de seis fases distintas.

Ao contrário do P03 (primeira submissão de PPCI), o P14 não inclui análise técnica — o PPCI já foi aprovado em ciclo anterior. O P14 percorre um fluxo exclusivo: aceite de termo (Anexo D), pagamento ou isenção de taxa de vistoria, realização e homologação da vistoria, e emissão de novo APPCI. A emissão do novo alvará encerra o processo com `ALVARA_VIGENTE`. Uma vistoria reprovada gera CIV e ativa um **loop de retorno**, pelo qual o cidadão pode reiniciar a renovação após corrigir as inconformidades.

O diagrama está organizado como uma **colaboração BPMN 2.0** (`<bpmn:collaboration id="Collab_P14">`) com **um único pool** (`Pool_P14`) e **quatro raias horizontais** (swim lanes), cada uma representando um ator técnico distinto. Todos os 33 elementos do processo foram documentados com `<bpmn:documentation>` detalhado contendo: classe Java, assinatura do método, atributo `camunda:class`, SQL Oracle, marcos de auditoria (`TipoMarco`) e referências às RNs. O arquivo exporta com `exporter="Camunda Modeler" exporterVersion="5.19.0"` e abre diretamente no Camunda Modeler.

---

## 2. Decisão de estrutura: pool único com quatro raias

### Por que um único pool?

O P14 é um processo de negócio **coeso e contínuo**: um mesmo licenciamento percorre sequencialmente todas as fases, e cada handoff entre atores é um ponto de passagem do mesmo token de processo. Usar pools separados (um por ator) exigiria Message Flows entre eles, o que tornaria o diagrama mais complexo sem acrescentar fidelidade ao modelo — na implementação real não há troca de mensagens assíncronas entre subsistemas independentes, mas sim chamadas síncronas EJB dentro de um único servidor WildFly.

A colaboração com um único pool e raias horizontais é o padrão canônico do BPMN 2.0 para representar um processo onde diferentes papéis humanos e sistema automatizado colaboram sobre o mesmo objeto de negócio (o licenciamento).

### Por que quatro raias?

| Raia | Ator | Responsabilidade |
|---|---|---|
| `Lane_Cidadao` | Cidadão / RT Renovação | Ações iniciadas pelo usuário externo (portal Angular) |
| `Lane_Admin` | CBMRS Admin | Análise de isenção, distribuição e homologação da vistoria |
| `Lane_Inspetor` | CBMRS Inspetor | Realização e envio do laudo de vistoria |
| `Lane_Sistema` | Sistema (EJB / CDI) | Transições de estado, geração de documentos, jobs automáticos |

A raia `Lane_Sistema` existe porque várias operações críticas — transições de `SituacaoLicenciamento` via `TrocaEstadoLicenciamentoRN`, geração de boleto, confirmação de pagamento CNAB 240 — são executadas sem interação humana direta. Modelá-las na raia do ator que as dispara (cidadão ou admin) seria tecnicamente incorreto: quem efetivamente executa a lógica é o EJB stateless no servidor, não o usuário. Separar essas operações em `Lane_Sistema` deixa explícito quem detém a responsabilidade de cada passo.

### Por que não Boundary Error Events?

O modelo não utiliza `<bpmn:error>` nem Boundary Error Events. O tratamento de erros em P14 é feito integralmente em Java: `@TransactionAttribute(REQUIRED)` garante rollback transacional em falhas; a `@SegurancaEnvolvidoInterceptor` lança `BusinessException` antes de qualquer modificação de estado; `LicenciamentoRenovacaoRNVal` valida pré-condições e lança exceção com mensagem i18n que o frontend trata. Adicionar Boundary Error Events criaria a falsa impressão de que o BPMN escalonaria erros para um tratador externo — o que não acontece. Adicionalmente, a experiência de P12 demonstrou que erros de posicionamento do elemento `<bpmn:error>` causam falha de parse no Camunda Modeler; a decisão de eliminar esses elementos em P13 foi mantida em P14.

---

## 3. Fase 1 — Iniciação da Renovação

Esta fase agrupa os elementos que verificam a elegibilidade do licenciamento e realizam a transição de estado que sinaliza ao sistema que o processo de renovação foi iniciado.

---

### 3.1 SE_Inicio — Start Event (None)

**Raia:** `Lane_Cidadao`
**ID BPMN:** `SE_Inicio`

O Start Event None representa o momento em que o cidadão ou RT decide iniciar a renovação ao acessar o portal Angular e localizar o licenciamento na lista "Minhas Renovações". Não há timer nem mensagem disparando o evento — trata-se de uma ação voluntária do usuário. O sistema exibe na lista apenas os licenciamentos em estados elegíveis, determinados por `SituacaoLicenciamento.retornaSituacoesRenovacao()`, que retorna `[ALVARA_VIGENTE, ALVARA_VENCIDO]`.

**Motivo da escolha de Start Event None:** o processo P14 é sempre iniciado por vontade do usuário, não por agendamento automático. A notificação de vencimento próximo (enviada pelo P13) é um gatilho externo que leva o cidadão ao portal, mas não dispara o processo em si. O Start Event None captura exatamente essa semântica: o processo começa quando e somente quando o usuário age. A raia `Lane_Cidadao` foi escolhida para este elemento porque o usuário é o ponto de entrada do fluxo.

**Conexão com P13:** o P13 (Jobs Automáticos) envia notificações aos 90, 59 e 29 dias antes do vencimento do APPCI, preparando o cidadão para iniciar esta renovação. O P14 não depende tecnicamente do P13 — pode ser iniciado a qualquer momento enquanto o licenciamento estiver elegível.

**RN-141:** somente licenciamentos em `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` são apresentados como renováveis.

---

### 3.2 T_IniciarRenovacao — User Task

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_IniciarRenovacao`
**`camunda:assignee`:** `cidadao_rt`

Esta User Task representa a leitura prévia pelo usuário dos dados do licenciamento e do Termo Anexo D antes de confirmar o início da renovação. Neste ponto, dois endpoints REST são invocados pelo frontend:

1. `GET /licenciamento/{idLic}/termo-anexo-d-renovacao` — `TermoLicenciamentoRN.retornoCienciaETermoRenovacao()` — exibe o conteúdo do Termo Anexo D.
2. `GET /licenciamento/{idLic}/reponsaveis-pagamento-renovacao` — `LicenciamentoResponsavelPagamentoRN.listaResponsaveisParaPagamentoRenovacao()` — lista os responsáveis habilitados para pagamento.

O endpoint de listagem de responsáveis filtra exclusivamente RTs com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI`, diferindo do método padrão que filtra por `TipoResponsabilidadeTecnica.EXECUCAO`. O nome do endpoint preserva o erro tipográfico do código-fonte (`reponsaveis` com um único `s`).

**Motivo da User Task:** a leitura e compreensão do Termo Anexo D é uma ação consciente do usuário. Não há automação possível: o cidadão precisa visualizar o documento antes de decidir se inicia ou não a renovação. A User Task é o elemento BPMN adequado para qualquer ação que requer intervenção humana.

**RNs cobertas:** RN-143 (RT RENOVACAO_APPCI obrigatório), RN-144 (tipo exclusivo para renovação).

---

### 3.3 T_ValidarElegibilidade — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_ValidarElegibilidade`
**`camunda:class`:** `com.procergs.solcbm.licenciamentorenovacao.LicenciamentoRenovacaoRNVal`

Esta Service Task representa as validações de back-end que ocorrem antes de qualquer modificação de estado, executadas pelo EJB `LicenciamentoRenovacaoRNVal`. São três validações em sequência:

1. **`validarSituacaoParaEdicao()`:** aceita `ALVARA_VENCIDO`, `ALVARA_VIGENTE`, `AGUARDANDO_ACEITE_RENOVACAO` e `CIV`. Qualquer outra situação lança `BusinessException` com a chave i18n `"licenciamento.renovacao.situacao.invalida"`.
2. **`validarResponsaveisTecnicos()`:** verifica que existe pelo menos um RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` cujo CPF corresponde ao CPF do usuário logado. Sem isso, lança `"licenciamento.renovacao.sem.responsavel.tecnico"`.
3. **`@SegurancaEnvolvidoInterceptor`:** CDI interceptor declarado na classe `LicenciamentoRenovacaoCidadaoRN` que verifica o vínculo do usuário como envolvido no licenciamento antes de qualquer método ser executado.

**Motivo de ser uma Service Task na raia do Sistema:** as validações são lógica de servidor pura — executadas pelo EJB stateless no WildFly, sem interface gráfica. Colocá-las na raia do cidadão transmitia a ideia errada de que é o usuário que valida. A raia `Lane_Sistema` deixa claro que é o back-end que rejeita ou aprova a continuidade.

**Motivo de ser separada de `T_IniciarRenovacao`:** a validação de elegibilidade é tecnicamente distinta do gesto de "clicar em Renovar". A separação permite que o diagrama mostre explicitamente onde o back-end exerce controle de segurança, tornando o BPMN útil também como documentação de auditoria e segurança (RN-143, RN-144).

---

### 3.4 GW_ValidacaoOK — Exclusive Gateway

**Raia:** `Lane_Sistema`
**ID BPMN:** `GW_ValidacaoOK`
**Condições:**
- `[Sim]` → `T_MudarAguardandoAceite`
- `[Não]` → `EE_NaoPermitida`

Este gateway representa o resultado da validação de elegibilidade. A condição `[Não]` é atingida quando o EJB lança `BusinessException`, que o container JAX-RS mapeia para resposta HTTP 4xx com mensagem de erro exibida pelo frontend. A condição `[Sim]` representa o caminho feliz onde todas as validações passaram.

**Motivo do Gateway Exclusivo (XOR):** exatamente um dos dois caminhos é tomado — ou a validação passou ou não passou. Não existe estado intermediário. Um gateway paralelo seria semanticamente incorreto porque os dois caminhos jamais são ativados simultaneamente para a mesma instância.

---

### 3.5 EE_NaoPermitida — End Event

**Raia:** `Lane_Sistema`
**ID BPMN:** `EE_NaoPermitida`

End Event None que representa o encerramento prematuro do processo por falha de validação. O licenciamento permanece no estado em que estava (`ALVARA_VIGENTE` ou `ALVARA_VENCIDO`) sem nenhuma modificação. O frontend exibe a mensagem de erro ao usuário.

**Motivo de ser um End Event na raia Sistema:** a falha é detectada e gerenciada pelo back-end, não pelo usuário. Posicionar este evento na raia `Lane_Sistema` deixa claro que a decisão de encerrar partiu da lógica de validação do servidor. O End Event None (e não de Erro) é apropriado porque, do ponto de vista do processo, o fluxo simplesmente terminou — a exceção foi tratada e comunicada ao usuário antes de chegar a este ponto.

**RNs cobertas:** RN-141, RN-143.

---

### 3.6 T_MudarAguardandoAceite — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_MudarAguardandoAceite`
**`camunda:class`:** `TrocaEstadoLicenciamentoAlvaraVigenteParaAguardandoAceiteRenovacaoRN` ou `TrocaEstadoLicenciamentoAlvaraVencidoParaAguardandoAceiteRenovacaoRN`

Esta Service Task representa a transição formal de `SituacaoLicenciamento` do licenciamento para `AGUARDANDO_ACEITE_RENOVACAO`. Dois EJBs distintos são possíveis, resolvidos em tempo de execução pelo mecanismo CDI Qualifier:

- **De `ALVARA_VIGENTE`:** `@TrocaEstadoLicenciamentoQualifier(trocaEstado = ALVARA_VIGENTE_PARA_AGUARDANDO_ACEITE_RENOVACAO)`
- **De `ALVARA_VENCIDO`:** `@TrocaEstadoLicenciamentoQualifier(trocaEstado = ALVARA_VENCIDO_PARA_AGUARDANDO_ACEITE_RENOVACAO)`

Ambos seguem o padrão `TrocaEstadoLicenciamentoBaseRN.atualizaSituacaoLicenciamento()`: (1) consulta o `LicenciamentoED`, (2) insere registro em `SITUACAO_LICENCIAMENTO` com a nova situação e timestamp, (3) seta `licenciamentoED.setSituacao(AGUARDANDO_ACEITE_RENOVACAO)`, (4) executa `entityManager.merge()`. O marco `TipoMarco.ACEITE_ANEXOD_RENOVACAO` é inserido em seguida com `TipoResponsavelMarco.SISTEMA`.

**Motivo de ser uma Service Task explícita, e não embutida na User Task anterior:** a transição de estado é uma operação do sistema com efeito no banco de dados (`INSERT` em `SITUACAO_LICENCIAMENTO` e `UPDATE` em `LICENCIAMENTO`). Separar a tarefa do usuário ("iniciar renovação") da tarefa do sistema ("alterar situação no banco") respeita o princípio de responsabilidade única e deixa explícito, no diagrama, onde o estado persistente é modificado. Isso facilita o diagnóstico de problemas: se o licenciamento chegou a `AGUARDANDO_ACEITE_RENOVACAO` no banco mas a UI não avançou, sabe-se que o problema está entre `T_ValidarElegibilidade` e `T_MudarAguardandoAceite`.

**RNs cobertas:** RN-142, RN-145.

---

## 4. Fase 2 — Aceite do Anexo D

Esta fase modela o momento central do processo de renovação: o cidadão decide formalmente se aceita ou recusa os termos de renovação (Anexo D). A fase tem dois desdobramentos — confirmação ou cancelamento — e recebe um segundo fluxo de entrada proveniente do loop de renovação após CIV, tornando `T_AceitarAnexoD` o único elemento do diagrama com duas entradas distintas.

---

### 4.1 T_AceitarAnexoD — User Task (dupla entrada)

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_AceitarAnexoD`
**`camunda:assignee`:** `cidadao_rt`
**Fluxos de entrada:**
1. `SF_T_MudarAguardandoAceite_T_AceitarAnexoD` — caminho normal (nova renovação)
2. `SF_T_MudarCIVParaAguardandoAceite_T_AceitarAnexoD` — caminho de loop após CIV

Esta User Task representa a leitura e decisão do cidadão ou RT sobre o Termo Anexo D de Renovação. A situação do licenciamento neste ponto é sempre `AGUARDANDO_ACEITE_RENOVACAO`. Três operações REST estão associadas a esta tarefa:

- `GET /licenciamento/{idLic}/termo-anexo-d-renovacao` → `TermoLicenciamentoRN.retornoCienciaETermoRenovacao()` — exibe o termo para leitura.
- `PUT /licenciamento/{idLic}/termo-anexo-d-renovacao` → `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao()` — confirma o aceite, aciona a mudança de situação.
- `DELETE /licenciamento/{idLic}/termo-anexo-d-renovacao` → `TermoLicenciamentoRN.removeAceiteAnexoDRenovacao(idLic, true)` — cancela o aceite, aciona o rollback de estado.

O campo Oracle `IND_ACEITE_RENOVACAO CHAR(1)` é atualizado via `SimNaoBooleanConverter`: `'S'` para aceite confirmado, `'N'` para cancelado.

**Motivo da dupla entrada:** no loop de renovação após CIV, o cidadão que decide reiniciar o processo retorna exatamente a este ponto — ele precisa reler e aceitar novamente o Anexo D porque as condições do licenciamento podem ter mudado (vistoria reprovada registrada). Usar um único elemento `T_AceitarAnexoD` com duas entradas é tecnicamente correto em BPMN 2.0 (um exclusive gateway de merge implícito) e evita duplicação de elementos idênticos no diagrama. Criar dois elementos separados seria redundante e aumentaria o risco de divergência de documentação.

**RNs cobertas:** RN-145, RN-146.

---

### 4.2 GW_DecisaoAceite — Exclusive Gateway

**Raia:** `Lane_Cidadao`
**ID BPMN:** `GW_DecisaoAceite`
**Condições:**
- `[Confirmou]` → `T_MudarAguardandoPagamento` (Sistema)
- `[Cancelou]` → `T_RollbackEstado` (Sistema)

Este gateway bifurca o fluxo conforme a decisão do cidadão sobre o Anexo D. A condição `[Confirmou]` é ativada pelo `PUT` no endpoint; a condição `[Cancelou]` é ativada pelo `DELETE`. Os dois caminhos convergem para raias diferentes: o caminho de confirmação desce para `Lane_Sistema` (serviço que altera o estado para `AGUARDANDO_PAGAMENTO_RENOVACAO`); o caminho de cancelamento também desce para `Lane_Sistema` (serviço que executa o rollback). Ambas as transições de estado são responsabilidade do sistema, não do usuário.

**Motivo do Gateway Exclusivo:** o usuário toma uma decisão binária — ou confirma ou cancela. Não há estado intermediário nem concorrência entre os caminhos.

**RNs cobertas:** RN-146, RN-147.

---

### 4.3 T_RollbackEstado — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_RollbackEstado`
**`camunda:class`:** `com.procergs.solcbm.licenciamentorenovacao.LicenciamentoRenovacaoCidadaoRN`

Esta Service Task representa a lógica condicional de rollback executada pelo método `getTrocaEstadoAnteriorRenovacao(Long idLicenciamento)`. O método consulta duas fontes de dados e, com base nelas, decide qual `TrocaEstadoLicenciamentoRN` aplicar:

```
Calendar validadeAlvara = appciRN.consultaDataValidadeAlvara(idLicenciamento)
VistoriaED ultimaVistoria = vistoriaRN.consultaUltimaVistoriaEncerrada(idLicenciamento)

if (ultimaVistoria != null AND ultimaVistoria.status == REPROVADO)
    → AGUARDANDO_ACEITE_RENOVACAO → CIV
      @TrocaEstadoLicenciamentoQualifier(AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV)

else if (Calendar.getInstance().after(validadeAlvara))
    → AGUARDANDO_ACEITE_RENOVACAO → ALVARA_VENCIDO
      @TrocaEstadoLicenciamentoQualifier(AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VENCIDO)

else
    → AGUARDANDO_ACEITE_RENOVACAO → ALVARA_VIGENTE
      @TrocaEstadoLicenciamentoQualifier(AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VIGENTE)
```

Esta lógica de três vias foi modelada como uma única Service Task, e não como um gateway adicional, porque a decisão é tomada **dentro** do método Java — o BPMN não tem visibilidade direta sobre qual dos três `TrocaEstado` será chamado. Expor essa lógica interna como um gateway BPMN exigiria que o motor de processo conhecesse o estado do banco de dados antes de avaliar a condição, o que não é viável na stack atual sem um mecanismo de variáveis de processo (que não existe nesta implementação EJB pura). O `<bpmn:documentation>` documenta integralmente a lógica para que os desenvolvedores compreendam o comportamento sem precisar inspecionar o código.

**Motivo de ser uma Service Task separada de `GW_DecisaoAceite`:** o rollback envolve operações de banco de dados (`INSERT` em `SITUACAO_LICENCIAMENTO`, `UPDATE` em `LICENCIAMENTO`). Separar a decisão de negócio (gateway) da execução técnica (service task) mantém o princípio de responsabilidade única e facilita a rastreabilidade.

**RN-147.**

---

### 4.4 EE_CancelRenovacao — End Event

**Raia:** `Lane_Sistema`
**ID BPMN:** `EE_CancelRenovacao`

End Event None que representa o encerramento do processo de renovação por escolha voluntária do cidadão. O licenciamento retorna ao seu estado anterior (`ALVARA_VIGENTE`, `ALVARA_VENCIDO` ou `CIV`), sem nenhuma penalidade. O processo pode ser reiniciado a qualquer momento enquanto o licenciamento permanecer em um estado elegível.

**Motivo de ser posicionado na raia Sistema:** o encerramento ocorre após a Service Task de rollback, que é uma operação de sistema. Posicionar este End Event na raia `Lane_Sistema` mantém a coerência: o último ator a agir foi o sistema (executando o rollback), não o usuário. Este padrão — End Event na raia do último ator — é usado em todo o diagrama.

---

### 4.5 T_MudarAguardandoPagamento — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_MudarAguardandoPagamento`
**`camunda:class`:** `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAguardandoPagamentoRenovacaoRN`

Esta Service Task representa a transição `AGUARDANDO_ACEITE_RENOVACAO → AGUARDANDO_PAGAMENTO_RENOVACAO`, disparada internamente por `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao()` ao receber o `PUT` do frontend. O EJB implementa o CDI qualifier `@TrocaEstadoLicenciamentoQualifier(trocaEstado = AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_PAGAMENTO_RENOVACAO)` e insere o marco `TipoMarco.BOLETO_VISTORIA_RENOVACAO_PPCI` com `TipoResponsavelMarco.SISTEMA`.

Após esta transição, o fluxo sobe da raia `Lane_Sistema` de volta para a raia `Lane_Cidadao`, onde o usuário toma a próxima decisão (isenção ou pagamento).

**Motivo de ser uma Service Task separada de `T_AceitarAnexoD`:** novamente, a separação entre ação do usuário (aceite do termo) e efeito no sistema (alteração de situação no banco) é fundamental para rastreabilidade. O aceite do termo e a mudança de situação ocorrem em chamadas técnicas distintas e com responsabilidades diferentes.

**RN-148.**

---

## 5. Fase 3 — Pagamento ou Isenção da Taxa de Vistoria

Esta é a fase mais complexa do diagrama em termos de caminhos alternativos. O cidadão pode ou não solicitar isenção da taxa de vistoria. Se solicitar, um administrador do CBMRS analisa e decide. Aprovada a isenção, o pagamento é dispensado. Reprovada (ou não solicitada), o cidadão paga via boleto bancário CNAB 240. Os dois caminhos convergem antes da distribuição da vistoria.

---

### 5.1 GW_IsencaoOuPagamento — Exclusive Gateway

**Raia:** `Lane_Cidadao`
**ID BPMN:** `GW_IsencaoOuPagamento`
**Condições:**
- `[Sim, solicita isenção]` → `T_SolicitarIsencao`
- `[Não, paga diretamente]` → `T_GerarBoleto`

Este gateway bifurca o fluxo com base na decisão do cidadão de solicitar ou não isenção da taxa de vistoria de renovação. A decisão é registrada no campo Oracle `IND_SOLICITACAO_ISENCAO_RENOVACAO CHAR(1)` via `SimNaoBooleanConverter`. O endpoint `PUT /licenciamento/{idLic}/solicitacaoIsencao` com `@AutorizaEnvolvido` é o ponto de entrada, chamando `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao()`.

O caminho `[Não]` salta diretamente para `T_GerarBoleto`, que está posicionado **à direita** no diagrama — ou seja, após o bloco de isenção. A sequência flow `SF_GW_Isencao_T_GerarBoleto` usa waypoints que contornam o bloco inteiro de isenção pela parte inferior do diagrama, evitando sobreposição visual com os elementos do caminho de isenção.

**Motivo do Gateway Exclusivo:** a decisão é mutuamente exclusiva — ou o cidadão solicita isenção ou não solicita. Não há cenário em que ambos os caminhos sejam percorridos.

**RN-149.**

---

### 5.2 T_SolicitarIsencao — User Task

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_SolicitarIsencao`
**`camunda:assignee`:** `cidadao_rt`

O cidadão ou RT preenche e submete o formulário de solicitação de isenção de taxa de vistoria de renovação, incluindo justificativa e documentação comprobatória. O endpoint `PUT /licenciamento/{idLic}/solicitacaoIsencao` é chamado com `solicitacaoRenovacao=true` para distinguir da isenção padrão do P06. O campo `IND_SOLICITACAO_ISENCAO_RENOVACAO` é setado como `'S'` no Oracle. O marco `TipoMarco.SOLICITACAO_ISENCAO_RENOVACAO` é inserido com `TipoResponsavelMarco.SISTEMA`.

**Motivo de ser uma User Task separada de `GW_IsencaoOuPagamento`:** o gateway representa apenas a decisão de solicitar ou não. A User Task representa o ato de preenchimento e submissão do formulário, que envolve múltiplas interações com a interface — escolha de documentos, preenchimento de campos, upload de anexos. São etapas conceitualmente distintas.

**RN-149.**

---

### 5.3 T_AnalisarIsencao — User Task

**Raia:** `Lane_Admin`
**ID BPMN:** `T_AnalisarIsencao`
**`camunda:assignee`:** `cbmrs_admin`

O CBMRS Admin analisa a documentação submetida pelo cidadão e decide se a isenção é deferida ou indeferida. Os critérios de aprovação incluem tipo de uso do estabelecimento (filantrópico, público), enquadramento em decreto estadual de isenção e completude da documentação. O resultado é registrado no campo `IND_ISENCAO_RENOVACAO CHAR(1)` do Oracle.

Esta tarefa está posicionada na raia `Lane_Admin`, cruzando o fluxo que veio de `Lane_Cidadao`. A sequência flow de `T_SolicitarIsencao` (Cidadão) para `T_AnalisarIsencao` (Admin) cruza horizontalmente, representando o handoff entre o cidadão e o servidor público.

**Motivo de ser uma User Task:** a análise de isenção requer julgamento humano — o administrador avalia documentos, verifica enquadramento legal e toma uma decisão discricionária dentro dos critérios estabelecidos. Não há regra automática aplicável no sistema.

**RN-150.**

---

### 5.4 GW_IsencaoAprovada — Exclusive Gateway

**Raia:** `Lane_Admin`
**ID BPMN:** `GW_IsencaoAprovada`
**Condições:**
- `[Aprovada]` → `GW_MergeAntesDist` (Sistema) — pula o pagamento de boleto.
- `[Reprovada]` → `T_GerarBoleto` (Sistema) — o cidadão deve pagar.

Este gateway implementa a decisão da análise de isenção. O caminho `[Aprovada]` salta diretamente para o gateway de merge anterior à distribuição (`GW_MergeAntesDist`), dispensando completamente o ciclo de boleto. O caminho `[Reprovada]` converge com o caminho direto de pagamento em `T_GerarBoleto`.

A sequência flow `[Aprovada]` cobre uma distância horizontal significativa no diagrama (de `GW_IsencaoAprovada` diretamente até `GW_MergeAntesDist`), passando sobre os elementos de boleto — o que é correto: visualmente representa o "atalho" que dispensa o pagamento.

**Motivo do Gateway Exclusivo:** isenção aprovada e isenção reprovada são mutuamente exclusivas.

**RN-150.**

---

### 5.5 T_GerarBoleto — Service Task (dupla entrada)

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_GerarBoleto`
**`camunda:class`:** `com.procergs.solcbm.boleto.BoletoRN`
**Fluxos de entrada:**
1. `SF_GW_Isencao_T_GerarBoleto` — cidadão não solicitou isenção.
2. `SF_GW_IsencaoReprovada_T_GerarBoleto` — isenção foi solicitada e reprovada.

Esta Service Task gera o boleto bancário para pagamento da taxa de vistoria de renovação. O EJB `BoletoRN` integra com a PROCERGS para geração de boleto CNAB 240 (Banrisul/GRU). O valor é calculado com base nos parâmetros do PPCI (área construída, tipo de ocupação). Os dados gerados incluem nosso número, código de barras, vencimento e o PDF do boleto, armazenado no Alfresco com `identificadorAlfresco` (nodeRef no formato `workspace://SpacesStore/{uuid}`). O marco `TipoMarco.BOLETO_VISTORIA_RENOVACAO_PPCI` é inserido com `TipoResponsavelMarco.SISTEMA`.

**Motivo da dupla entrada:** os dois caminhos que chegam a `T_GerarBoleto` resultam em exatamente a mesma operação — gerar um boleto para o cidadão pagar. Duplicar o elemento apenas para ter uma entrada por caminho não agregaria informação e tornaria o diagrama maior sem benefício. A dupla entrada em uma Service Task sem gateway de merge explícito é válida em BPMN 2.0: o gateway de merge implícito (exclusive) garante que apenas um token chegue por vez.

**RN-151.**

---

### 5.6 T_PagarBoleto — User Task

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_PagarBoleto`
**`camunda:assignee`:** `cidadao_rt`

O cidadão realiza o pagamento do boleto por canais bancários externos (banco, internet banking, correspondente bancário). Esta User Task representa o **período de espera** pelo pagamento — o licenciamento permanece em `AGUARDANDO_PAGAMENTO_RENOVACAO` até que o retorno bancário CNAB 240 confirme a liquidação. Não há ação técnica do sistema durante este período além de manter o estado.

A sequência flow de `T_GerarBoleto` (Sistema) para `T_PagarBoleto` (Cidadão) sobe da raia `Lane_Sistema` para `Lane_Cidadao`, representando que o sistema entregou o boleto ao cidadão, que agora é o ator responsável.

**Motivo de ser uma User Task:** embora o pagamento ocorra fora do sistema SOL (no banco), o cidadão é o único que pode realizá-lo. A User Task representa essa responsabilidade. O fato de que a confirmação não é feita pelo cidadão mas sim pelo job P13 é documentado explicitamente no `<bpmn:documentation>`, prevenindo confusão.

**RNs cobertas:** RN-151, RN-152.

---

### 5.7 T_ConfirmarPagamento — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_ConfirmarPagamento`
**`camunda:class`:** `com.procergs.solcbm.boleto.LiquidacaoBoletoJobRN`

Esta Service Task representa o processamento do retorno bancário CNAB 240 pelo job automático do P13 (Pool 2, `@Schedule(hour="0", minute="31")`). O EJB `LiquidacaoBoletoJobRN` lê o arquivo de retorno da PROCERGS/Banrisul, localiza o boleto correspondente pelo nosso número, marca-o como liquidado no Oracle (`ST_LIQUIDADO = 'S'`, `DT_LIQUIDACAO = SYSDATE`) e aciona a mudança de situação do licenciamento. O marco `TipoMarco.LIQUIDACAO_VISTORIA_RENOVACAO` é inserido com `TipoResponsavelMarco.SISTEMA`.

**Motivo de ser uma Service Task separada de `T_PagarBoleto`:** o pagamento pelo cidadão e a confirmação pelo sistema são dois eventos tecnicamente distintos, ocorrendo em momentos diferentes (o pagamento pode ocorrer em qualquer momento do dia; a confirmação é processada pelo job às 00:31). Separar os dois elementos torna explícito o mecanismo de integração bancária e evita a confusão de que o cidadão confirma o pagamento manualmente no sistema.

**RN-152.**

---

### 5.8 GW_MergeAntesDist — Exclusive Gateway (merge)

**Raia:** `Lane_Sistema`
**ID BPMN:** `GW_MergeAntesDist`
**Fluxos de entrada:**
1. `SF_GW_IsencaoAprovada_GW_MergeAntesDist` — isenção aprovada (sem boleto).
2. `SF_T_ConfirmarPagamento_GW_MergeAntesDist` — pagamento confirmado por retorno bancário.

Gateway de convergência (merge) que unifica os dois caminhos que levam à fase de distribuição: isenção aprovada (que pula o boleto) e confirmação de pagamento de boleto. Após este gateway, o processo segue exclusivamente para `T_MudarAguardandoDistribuicao`.

**Motivo do Gateway Exclusivo como merge:** em cada instância de processo, exatamente um dos dois caminhos é percorrido — ou houve isenção ou houve pagamento. Um gateway paralelo de merge exigiria que ambas as entradas chegassem simultaneamente, o que nunca ocorre. O gateway exclusivo como merge é o padrão correto para convergência de caminhos alternativos mutuamente exclusivos.

---

### 5.9 T_MudarAguardandoDistribuicao — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_MudarAguardandoDistribuicao`
**`camunda:class`:** `TrocaEstadoLicenciamentoAguardandoPagamentoRenovacaoParaAguardandoDistribuicaoRenovacaoRN`

Esta Service Task representa a transição `AGUARDANDO_PAGAMENTO_RENOVACAO → AGUARDANDO_DISTRIBUICAO_RENOV`, disparada pela confirmação de liquidação (job P13) ou pela aprovação de isenção (Admin). O EJB implementa `@TrocaEstadoLicenciamentoQualifier(trocaEstado = AGUARDANDO_PAGAMENTO_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO_RENOV)` e executa o padrão `atualizaSituacaoLicenciamento()`.

**RNs cobertas:** RN-152, RN-153.

---

## 6. Fase 4 — Distribuição da Vistoria de Renovação

Esta fase é a mais curta do diagrama: o administrador do CBMRS designa um inspetor e o sistema registra a vistoria e altera a situação do licenciamento.

---

### 6.1 T_DistribuirVistoria — User Task

**Raia:** `Lane_Admin`
**ID BPMN:** `T_DistribuirVistoria`
**`camunda:assignee`:** `cbmrs_admin`

O CBMRS Admin designa um inspetor disponível para realizar a vistoria de renovação. A ação cria uma `VistoriaED` com `TipoVistoria.VISTORIA_RENOVACAO` (ordinal 3 no enum) e associa o inspetor escolhido. A criação da vistoria é seguida imediatamente pela mudança de situação do licenciamento para `EM_VISTORIA_RENOVACAO`.

A sequência flow de `T_MudarAguardandoDistribuicao` (Sistema) para `T_DistribuirVistoria` (Admin) sobe da raia `Lane_Sistema` para `Lane_Admin`, representando o handoff do sistema para o administrador.

**Motivo de User Task:** a seleção do inspetor adequado requer conhecimento da disponibilidade da equipe, localização do estabelecimento e competência técnica do inspetor para o tipo de ocupação — decisão humana que o sistema não pode tomar automaticamente.

**RNs cobertas:** RN-153, RN-154.

---

### 6.2 T_MudarEmVistoriaRenovacao — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_MudarEmVistoriaRenovacao`
**`camunda:class`:** `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN`

Esta Service Task representa a transição `AGUARDANDO_DISTRIBUICAO_RENOV → EM_VISTORIA_RENOVACAO`, disparada após a distribuição pelo Admin. O EJB insere o marco `TipoMarco.DISTRIBUICAO_VISTORIA_RENOV` com `TipoResponsavelMarco.BOMBEIROS`, usando o qualifier `@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.BOMBEIROS)`. Após a transição, o fluxo desce da raia `Lane_Sistema` para `Lane_Inspetor`.

O marco `DISTRIBUICAO_VISTORIA_RENOV` é inserido neste momento, e não durante a User Task do Admin, porque a inserção de marcos de auditoria é responsabilidade do Sistema — o Admin apenas executa a ação de negócio, e o sistema registra o evento com timestamp e responsável.

**RN-154.**

---

## 7. Fase 5 — Execução da Vistoria de Renovação

Esta é a fase de maior especialização técnica do diagrama: o inspetor do CBMRS realiza a vistoria presencial e envia o laudo, que é homologado pelo administrador. O resultado da homologação define o desfecho do processo.

---

### 7.1 T_RealizarVistoria — User Task

**Raia:** `Lane_Inspetor`
**ID BPMN:** `T_RealizarVistoria`
**`camunda:assignee`:** `cbmrs_inspetor`

O CBMRS Inspetor designado visita o estabelecimento e verifica a conformidade das medidas de segurança contra incêndio conforme o PPCI aprovado anteriormente. A vistoria usa `TipoVistoria.VISTORIA_RENOVACAO` (ordinal 3), distinto de `TipoVistoria.PPCI` usado em novas submissões. O inspetor registra itens conformes e não-conformes, tira fotos (armazenadas no Alfresco) e prepara o laudo. Ao concluir a verificação in loco, o status da `VistoriaED` transita de `EM_VISTORIA` para `EM_APROVACAO_RENOVACAO`. Os marcos `ENVIO_VISTORIA_RENOVACAO`, `ACEITE_VISTORIA_RENOVACAO` e `FIM_ACEITES_VISTORIA_RENOVACAO` cobrem o ciclo de agendamento e aceite da data da vistoria.

**Motivo de User Task em `Lane_Inspetor`:** a vistoria presencial é necessariamente uma ação humana que ocorre fisicamente no estabelecimento. O inspetor usa o sistema SOL apenas para registrar o resultado — a execução real é presencial.

**RNs cobertas:** RN-155, RN-156.

---

### 7.2 T_EnviarRelatorioVistoria — User Task

**Raia:** `Lane_Inspetor`
**ID BPMN:** `T_EnviarRelatorioVistoria`
**`camunda:assignee`:** `cbmrs_inspetor`

O inspetor preenche e envia formalmente o laudo/relatório de vistoria no sistema SOL. O laudo contém: itens conformes, descrição detalhada das não-conformidades (se houver), fotos e evidências (upload para Alfresco) e o parecer final (Conforme / Não Conforme). Após o envio, o laudo fica disponível para o Admin homologar. A `VistoriaED` permanece em `EM_APROVACAO_RENOVACAO` aguardando a decisão.

**Motivo de ser separada de `T_RealizarVistoria`:** a realização física da vistoria (presença no estabelecimento) e o preenchimento formal do laudo no sistema são momentos distintos. O inspetor pode realizar a vistoria e preencher o laudo horas depois, ao retornar à base. Separar os dois elementos reflete essa realidade operacional e estabelece claramente onde se encerra a atividade de campo e começa a atividade de registro.

**RNs cobertas:** RN-155, RN-156.

---

### 7.3 T_HomologarVistoria — User Task

**Raia:** `Lane_Admin`
**ID BPMN:** `T_HomologarVistoria`
**`camunda:assignee`:** `cbmrs_admin`

O CBMRS Admin revisa o laudo enviado pelo inspetor e homologa o resultado da vistoria de renovação, decidindo entre deferir ou indeferir. A homologação aciona dois mecanismos distintos dependendo do resultado:

**Se deferido:**
- `TrocaEstadoVistoria` altera `VistoriaED.status` para `StatusVistoria.ENCERRADO`.
- Marco `TipoMarco.HOMOLOG_VISTORIA_RENOV_DEFERIDO` é inserido com `TipoResponsavelMarco.BOMBEIROS`.
- O processo avança para emissão do novo APPCI.

**Se indeferido:**
- `TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN` é executado:
  ```java
  @TrocaEstadoVistoriaQualifier(trocaEstado = EM_APROVACAO_RENOVACAO_PARA_EM_VISTORIA)
  @Override trocaEstado(Long idVistoria) {
      VistoriaED v = atualizaStatusVistoria(idVistoria); // → EM_VISTORIA
      licenciamentoMarcoInclusaoRN.inclui(HOMOLOG_VISTORIA_RENOV_INDEFERIDO, v.getLicenciamento());
      return v;
  }
  ```
- Marco `TipoMarco.HOMOLOG_VISTORIA_RENOV_INDEFERIDO` é inserido com `TipoResponsavelMarco.BOMBEIROS`.
- O processo avança para emissão de CIV.

A sequência flow de `T_EnviarRelatorioVistoria` (Inspetor) para `T_HomologarVistoria` (Admin) sobe da raia `Lane_Inspetor` para `Lane_Admin`, representando o handoff do resultado da vistoria do inspetor para o administrador homologador.

**Motivo de User Task:** a homologação é um ato administrativo que requer revisão humana do laudo — o administrador pode discordar do inspetor, solicitar complementações ou retificar o resultado com base em critérios normativos. Não é possível automatizar essa decisão.

**RNs cobertas:** RN-156, RN-157.

---

### 7.4 GW_VistoriaAprovada — Exclusive Gateway

**Raia:** `Lane_Admin`
**ID BPMN:** `GW_VistoriaAprovada`
**Condições:**
- `[Deferido]` → `T_EmitirAPPCI` (Sistema)
- `[Indeferido]` → `T_EmitirCIV` (Sistema)

Este gateway é o ponto de bifurcação entre os dois desfechos possíveis da fase 5 e, consequentemente, do processo inteiro. O caminho `[Deferido]` inicia o encerramento bem-sucedido; o caminho `[Indeferido]` inicia o encerramento com CIV, que abre a possibilidade de loop de renovação.

Os dois caminhos saem de `Lane_Admin` e descem para `Lane_Sistema`, onde ficam posicionados `T_EmitirAPPCI` e `T_EmitirCIV`. O BPMN usa duas sequências flow com waypoints distintos: o caminho `[Deferido]` desce diretamente para o `T_EmitirAPPCI` (área superior de `Lane_Sistema`); o caminho `[Indeferido]` desce e contorna para `T_EmitirCIV` (área inferior de `Lane_Sistema`), evitando sobreposição visual.

**Motivo do Gateway Exclusivo:** os dois resultados são mutuamente exclusivos — a vistoria é deferida ou indeferida, nunca ambos.

---

## 8. Fase 6A — Conclusão: Deferido → ALVARA_VIGENTE

---

### 8.1 T_EmitirAPPCI — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_EmitirAPPCI`
**`camunda:class`:** `com.procergs.solcbm.appci.AppciRN`

Esta Service Task representa a emissão do novo APPCI/Alvará de Prevenção e Proteção Contra Incêndio de renovação. O EJB `AppciRN` gera o APPCI usando o DTO `AppciRenovacaoDTO`:

```java
@Getter @Setter @Builder
public class AppciRenovacaoDTO {
  Integer numeroPedido;   // Número sequencial do pedido de renovação
  String  validade;       // Data de validade (nova)
  String  inicioVigencia; // Data de início da vigência
  String  fimVigencia;    // Data de fim da vigência (geralmente +1 ano)
}
```

O documento PDF é gerado e armazenado no Alfresco com `identificadorAlfresco` (nodeRef no formato `workspace://SpacesStore/{uuid}`). O marco `TipoMarco.LIBERACAO_RENOV_APPCI` é inserido com `TipoResponsavelMarco.SISTEMA`. Se houver documentos complementares associados, o marco `TipoMarco.EMISSAO_DOC_COMPLEMENTAR_RENOV` é inserido adicionalmente.

A sequência flow de `GW_VistoriaAprovada` (Admin) para `T_EmitirAPPCI` (Sistema) cruzou as raias descendo de Admin para Sistema, representando que a decisão humana de deferimento aciona automaticamente a emissão pelo sistema.

**Motivo de ser uma Service Task separada da homologação:** a emissão do APPCI é uma operação técnica distinta — geração de PDF, cálculo de validade, inserção no banco Oracle e gravação no Alfresco. Separar emissão e homologação no BPMN permite identificar com precisão onde falhas ocorrem: se o APPCI não foi gerado mas a homologação ocorreu, o problema está em `T_EmitirAPPCI`, não em `T_HomologarVistoria`.

**RN-158.**

---

### 8.2 T_CienciaAPPCI — User Task

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_CienciaAPPCI`
**`camunda:assignee`:** `cidadao_rt`

O cidadão ou RT toma ciência do novo APPCI emitido e confirma o recebimento no sistema. A implementação usa o padrão `LicenciamentoCienciaCidadaoBaseRN` via a classe `AppciCienciaCidadaoRenovacaoRN`:

```java
@LicenciamentoCienciaQualifier(
  tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.APPCI_RENOV)
@Override boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc) {
  return true; // Ciência de APPCI sempre aprovada automaticamente
}
@Override TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
  return TipoMarco.CIENCIA_APPCI_RENOVACAO;
}
@Override SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
  return SituacaoLicenciamento.ALVARA_VIGENTE;
}
```

O método `isLicenciamentoCienciaAprovado()` retorna `true` incondicionalmente, o que significa que o ato de ciência sempre resulta em aprovação — o cidadão não pode "reprovar" a ciência de um APPCI. O `getProximoStatusLicenciamentoCienciaReprovado()` retorna `ALVARA_VIGENTE` porque, mesmo que o cidadão discorde, a situação do licenciamento muda para `ALVARA_VIGENTE`. O endpoint é `PUT /licenciamento/{idLic}/ciencia/APPCI_RENOV` com `@AutorizaEnvolvido`. O marco `TipoMarco.CIENCIA_APPCI_RENOVACAO` é inserido com `TipoResponsavelMarco.SISTEMA`.

A sequência flow de `T_EmitirAPPCI` (Sistema) para `T_CienciaAPPCI` (Cidadão) sobe da raia `Lane_Sistema` para `Lane_Cidadao`, representando que o sistema entregou o APPCI e o cidadão é o próximo responsável.

**Motivo da User Task de ciência:** a ciência formal do cidadão é um requisito jurídico — o alvará emitido deve ser explicitamente recebido pelo responsável. Mesmo que tecnicamente a situação já seja `ALVARA_VIGENTE` com a emissão, a ciência registra o momento em que o responsável tomou conhecimento do novo documento.

**RN-159.**

---

### 8.3 EE_AlvaraVigente — End Event

**Raia:** `Lane_Cidadao`
**ID BPMN:** `EE_AlvaraVigente`

End Event None que representa o encerramento bem-sucedido do processo P14. A situação final do licenciamento é `ALVARA_VIGENTE`. O novo APPCI está disponível para download e o estabelecimento está regularizado pelo próximo ciclo (geralmente 1 ano). O P13 continuará monitorando este licenciamento e enviará novas notificações próximo ao próximo vencimento.

**Motivo de ser posicionado na raia Cidadão:** a última ação foi do cidadão (ciência do APPCI). O End Event na raia do último ator ativo é um padrão de modelagem consistente em todo o diagrama.

**RNs cobertas:** RN-141, RN-158, RN-159.

---

## 9. Fase 6B — Conclusão: Indeferido / CIV

Esta fase trata do encerramento por indeferimento da vistoria. O cidadão recebe e toma ciência do CIV, e então decide entre solicitar recurso (encerrando o P14 com encaminhamento para P10) ou aceitar o CIV e reiniciar a renovação após corrigir as inconformidades (loop de retorno ao início da Fase 2).

---

### 9.1 T_EmitirCIV — Service Task

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_EmitirCIV`
**`camunda:class`:** `com.procergs.solcbm.vistoria.CIVRenovacaoRN`

Esta Service Task representa a emissão do Comunicado de Inconformidade na Vistoria (CIV) de renovação, disparada após o indeferimento da homologação. O CIV lista as não-conformidades identificadas pelo inspetor que impedem a renovação do alvará. O documento PDF é gerado e armazenado no Alfresco. O marco `TipoMarco.VISTORIA_RENOVACAO_CIV` é inserido com `TipoResponsavelMarco.BOMBEIROS`. Uma notificação por e-mail é enviada ao cidadão/RT com o CIV em PDF.

`T_EmitirCIV` está posicionado na área inferior da raia `Lane_Sistema` (coordenada y maior que `T_EmitirAPPCI`), de modo que os dois service tasks de emissão coexistam visualmente na mesma coluna x sem sobreposição, separados verticalmente. Essa disposição reflete claramente que são caminhos alternativos (um ou outro, nunca ambos) dentro do mesmo espaço horizontal do diagrama.

**Motivo de ser separado de `T_HomologarVistoria`:** a emissão do CIV é uma operação técnica autônoma (geração de PDF, gravação em Alfresco, notificação por e-mail) que ocorre após a decisão humana de indeferimento. Separar as duas etapas mantém o princípio de separação entre decisão humana e execução automatizada.

**RN-157.**

---

### 9.2 T_CienciaCIV — User Task

**Raia:** `Lane_Cidadao`
**ID BPMN:** `T_CienciaCIV`
**`camunda:assignee`:** `cidadao_rt`

O cidadão ou RT toma ciência formal do CIV emitido e lê as não-conformidades identificadas. O endpoint `PUT /licenciamento/{idLic}/ciencia/CIENCIA_CIV_RENOVACAO` é chamado com `@AutorizaEnvolvido`. O marco `TipoMarco.CIENCIA_CIV_RENOVACAO` é inserido com `TipoResponsavelMarco.SISTEMA`. Após a ciência, a situação do licenciamento muda para `CIV`.

`T_CienciaCIV` está posicionado na área inferior da raia `Lane_Cidadao` (coordenada y maior que `T_CienciaAPPCI`), espelhando a disposição vertical de `T_EmitirCIV` na raia Sistema. Essa consistência vertical entre raias facilita a leitura horizontal do fluxo: o leitor identifica imediatamente que os elementos superiores são do caminho deferido e os inferiores são do caminho indeferido.

**Motivo da ciência formal:** assim como no caso do APPCI, a ciência do CIV é um requisito jurídico. O cidadão precisa confirmar que tomou conhecimento das não-conformidades e das implicações para o estabelecimento.

**RNs cobertas:** RN-157, RN-160.

---

### 9.3 GW_RecursoCIV — Exclusive Gateway

**Raia:** `Lane_Cidadao`
**ID BPMN:** `GW_RecursoCIV`
**Condições:**
- `[Sim, recurso P10]` → `EE_RecursoSolicitado`
- `[Não, reinicia renovação]` → `T_MudarCIVParaAguardandoAceite` (Sistema)

Este é o gateway de decisão mais importante da fase de indeferimento. O cidadão, após tomar ciência do CIV, decide entre dois caminhos:

1. **Recurso:** discorda da avaliação e entra com recurso formal (processo P10 — Recurso CIA/CIV). O P14 é encerrado; o P10 assume a responsabilidade. A situação do licenciamento transita para `RECURSO_EM_ANALISE_1_CIV` (visível em `retornaSituacoesMinhasRenovacoes()`).
2. **Reiniciar renovação:** aceita o CIV, corrige as não-conformidades no estabelecimento e decide reiniciar o processo de renovação. O sistema transita para `AGUARDANDO_ACEITE_RENOVACAO` e o fluxo retorna a `T_AceitarAnexoD`.

**Motivo do Gateway Exclusivo:** as duas opções são mutuamente exclusivas — o cidadão faz uma escolha deliberada entre recurso e reinício da renovação.

**RNs cobertas:** RN-157, RN-160.

---

### 9.4 EE_RecursoSolicitado — End Event

**Raia:** `Lane_Cidadao`
**ID BPMN:** `EE_RecursoSolicitado`

End Event None que representa o encerramento do P14 com encaminhamento para o P10 (Recurso CIA/CIV). O P14 não tem mais responsabilidade sobre o fluxo a partir deste ponto. O resultado do P10 (deferimento ou indeferimento do recurso) determinará a situação futura do licenciamento.

**Motivo de ser posicionado na raia Cidadão:** a iniciativa de solicitar recurso é do cidadão. O último ator a agir foi o cidadão (ao escolher o recurso no gateway). O End Event na raia do ator responsável pela decisão final é consistente com o padrão adotado no diagrama.

**RN-160.**

---

### 9.5 T_MudarCIVParaAguardandoAceite — Service Task e loop de retorno

**Raia:** `Lane_Sistema`
**ID BPMN:** `T_MudarCIVParaAguardandoAceite`
**`camunda:class`:** `TrocaEstadoLicenciamentoCIVParaAguardandoAceiteRenovacaoRN`

Esta Service Task representa a transição `CIV → AGUARDANDO_ACEITE_RENOVACAO`, executada quando o cidadão decide reiniciar a renovação após corrigir as inconformidades. O EJB implementa `@TrocaEstadoLicenciamentoQualifier(trocaEstado = CIV_PARA_AGUARDANDO_ACEITE_RENOVACAO)` e usa o padrão `atualizaSituacaoLicenciamento()`. Após a transição, o fluxo retorna ao elemento `T_AceitarAnexoD` — esta é a única sequência flow "para trás" (backwards) do diagrama.

**O loop de retorno no DI:** a sequência flow `SF_T_MudarCIVParaAguardandoAceite_T_AceitarAnexoD` usa waypoints externos ao pool para evitar colisão com os elementos existentes. O caminho percorre:

```
(3840, 813) → esquerda → (200, 813) → abaixo do pool → (200, 970)
→ direita → (1060, 970) → acima → (1060, 199) → T_AceitarAnexoD
```

Essa rota externa é o padrão canônico do BPMN 2.0 para representar loops de retorno em diagramas horizontais: o flow desce abaixo do pool, percorre a parte inferior e sobe de volta ao elemento destino. O waypoint `y=970` está abaixo do limite inferior do pool (`y=920`), o que é válido em BPMN DI — as sequences flows podem ter waypoints fora das bounds do pool.

**Motivo de ser uma Service Task explícita (e não um link ou evento):** o retorno ao aceite do Anexo D envolve uma transição real de estado no banco de dados. Um Intermediate Link Event seria esteticamente mais limpo, mas não representaria a operação de banco associada. A Service Task com `<bpmn:documentation>` completo é mais fiel ao código e mais útil como documentação.

**Importante para o ciclo de rollback:** ao reiniciar a renovação a partir do estado `CIV`, a lógica `getTrocaEstadoAnteriorRenovacao()` — se o cidadão cancelar o aceite do Anexo D nesta segunda tentativa — retornará `AGUARDANDO_ACEITE_RENOVACAO → CIV`, porque a última `VistoriaED` encerrada tem `StatusVistoria.REPROVADO`. Isso está documentado no `<bpmn:documentation>` de `T_RollbackEstado` para alertar os desenvolvedores.

**RN-160.**

---

## 10. Tabela de rastreabilidade

| Elemento BPMN | Tipo | Raia | Classe / Método Java | Tabela Oracle principal | RNs |
|---|---|---|---|---|---|
| `SE_Inicio` | Start Event | Cidadão | `LicenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacao()` | `LICENCIAMENTO` | RN-141 |
| `T_IniciarRenovacao` | User Task | Cidadão | `TermoLicenciamentoRN.retornoCienciaETermoRenovacao()` | `APPCI`, `RESPONSAVEL_TECNICO` | RN-143, RN-144 |
| `T_ValidarElegibilidade` | Service Task | Sistema | `LicenciamentoRenovacaoRNVal.validarSituacaoParaEdicao()` + `validarResponsaveisTecnicos()` | `LICENCIAMENTO`, `RESPONSAVEL_TECNICO` | RN-141, RN-143, RN-144 |
| `GW_ValidacaoOK` | Gateway | Sistema | — (resultado do EJB) | — | RN-141, RN-143 |
| `EE_NaoPermitida` | End Event | Sistema | — | — | RN-141, RN-143 |
| `T_MudarAguardandoAceite` | Service Task | Sistema | `TrocaEstado*AlvaraVigente/VencidoParaAguardandoAceiteRenovacaoRN` | `SITUACAO_LICENCIAMENTO`, `LICENCIAMENTO` | RN-142, RN-145 |
| `T_AceitarAnexoD` | User Task (2 entradas) | Cidadão | `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao()` / `removeAceiteAnexoDRenovacao()` | `LICENCIAMENTO` | RN-145, RN-146 |
| `GW_DecisaoAceite` | Gateway | Cidadão | — (decisão do usuário) | — | RN-146, RN-147 |
| `T_RollbackEstado` | Service Task | Sistema | `LicenciamentoRenovacaoCidadaoRN.getTrocaEstadoAnteriorRenovacao()` | `SITUACAO_LICENCIAMENTO`, `LICENCIAMENTO`, `VISTORIA`, `APPCI` | RN-147 |
| `EE_CancelRenovacao` | End Event | Sistema | — | — | RN-147 |
| `T_MudarAguardandoPagamento` | Service Task | Sistema | `TrocaEstado*AguardandoAceiteRenovacaoParaAguardandoPagamentoRenovacaoRN` | `SITUACAO_LICENCIAMENTO`, `LICENCIAMENTO` | RN-148 |
| `GW_IsencaoOuPagamento` | Gateway | Cidadão | `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao()` | `LICENCIAMENTO` (campo `IND_SOLICITACAO_ISENCAO_RENOVACAO`) | RN-149 |
| `T_SolicitarIsencao` | User Task | Cidadão | `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao()` | `LICENCIAMENTO` | RN-149 |
| `T_AnalisarIsencao` | User Task | Admin | — (análise manual) | `LICENCIAMENTO` (campo `IND_ISENCAO_RENOVACAO`) | RN-150 |
| `GW_IsencaoAprovada` | Gateway | Admin | — (resultado da análise) | — | RN-150 |
| `T_GerarBoleto` | Service Task (2 entradas) | Sistema | `BoletoRN` | `BOLETO`, `APPCI` (para cálculo de taxa) | RN-151 |
| `T_PagarBoleto` | User Task | Cidadão | — (banco externo) | — | RN-151, RN-152 |
| `T_ConfirmarPagamento` | Service Task | Sistema | `LiquidacaoBoletoJobRN` (job P13) | `BOLETO` | RN-152 |
| `GW_MergeAntesDist` | Gateway (merge) | Sistema | — | — | — |
| `T_MudarAguardandoDistribuicao` | Service Task | Sistema | `TrocaEstado*AguardandoPagamentoRenovacaoParaAguardandoDistribuicaoRenovacaoRN` | `SITUACAO_LICENCIAMENTO` | RN-152, RN-153 |
| `T_DistribuirVistoria` | User Task | Admin | — (seleção de inspetor) | `VISTORIA` | RN-153, RN-154 |
| `T_MudarEmVistoriaRenovacao` | Service Task | Sistema | `TrocaEstado*AguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN` | `SITUACAO_LICENCIAMENTO` | RN-154 |
| `T_RealizarVistoria` | User Task | Inspetor | — (visita presencial) | `VISTORIA` | RN-155, RN-156 |
| `T_EnviarRelatorioVistoria` | User Task | Inspetor | — (preenchimento de laudo) | `VISTORIA`, `ARQUIVO` (Alfresco) | RN-155, RN-156 |
| `T_HomologarVistoria` | User Task | Admin | `TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN` | `VISTORIA` | RN-156, RN-157 |
| `GW_VistoriaAprovada` | Gateway | Admin | — (decisão de homologação) | — | RN-156, RN-157 |
| `T_EmitirAPPCI` | Service Task | Sistema | `AppciRN` | `APPCI`, `ARQUIVO` (Alfresco) | RN-158 |
| `T_CienciaAPPCI` | User Task | Cidadão | `AppciCienciaCidadaoRenovacaoRN` | `SITUACAO_LICENCIAMENTO` | RN-159 |
| `EE_AlvaraVigente` | End Event | Cidadão | — | — | RN-141, RN-158, RN-159 |
| `T_EmitirCIV` | Service Task | Sistema | `CIVRenovacaoRN` | `CIV`, `ARQUIVO` (Alfresco) | RN-157 |
| `T_CienciaCIV` | User Task | Cidadão | `LicenciamentoCienciaCidadaoRN` (`CIENCIA_CIV_RENOVACAO`) | `SITUACAO_LICENCIAMENTO`, `CIV` | RN-157, RN-160 |
| `GW_RecursoCIV` | Gateway | Cidadão | — (decisão do cidadão) | — | RN-157, RN-160 |
| `EE_RecursoSolicitado` | End Event | Cidadão | — (P10 assume) | — | RN-160 |
| `T_MudarCIVParaAguardandoAceite` | Service Task | Sistema | `TrocaEstado*CIVParaAguardandoAceiteRenovacaoRN` | `SITUACAO_LICENCIAMENTO` | RN-160 |

---

## 11. Justificativas consolidadas de modelagem

### J1 — Pool único com quatro raias em vez de múltiplos pools

A escolha de um pool único com quatro raias horizontais reflete a natureza do P14 como um processo coeso: um único objeto de negócio (o licenciamento) percorre todas as fases, e os handoffs entre atores são pontos de passagem do mesmo token, não trocas de mensagens entre sistemas independentes. Em BPMN 2.0, múltiplos pools implicam Message Flows assíncronos — modelo adequado para sistemas desacoplados (e.g., SOL comunicando com sistema bancário via fila), mas incorreto para representar chamadas síncronas EJB dentro do mesmo servidor WildFly.

### J2 — Service Tasks para cada transição de SituacaoLicenciamento

O modelo usa uma Service Task explícita para cada transição `TrocaEstadoLicenciamentoRN` em vez de embutir a mudança de estado na documentação de uma User Task adjacente. Essa decisão decorre de dois princípios:

1. **Rastreabilidade de falhas:** se o estado no banco não mudou mas a UI avançou, ou vice-versa, o diagrama aponta exatamente qual Service Task é responsável pela inconsistência.
2. **Fidelidade arquitetural:** o padrão CDI Qualifier (`@TrocaEstadoLicenciamentoQualifier`) é um mecanismo sofisticado que merece representação explícita. A Service Task com `camunda:class` documentando o qualifier deixa evidente que há uma indireção polimórfica na implementação Java.

### J3 — T_AceitarAnexoD e T_GerarBoleto com dupla entrada

Dois elementos possuem mais de uma sequência flow de entrada: `T_AceitarAnexoD` (caminho normal e loop após CIV) e `T_GerarBoleto` (sem isenção e isenção reprovada). Em ambos os casos, criar elementos duplicados apenas para ter uma entrada por caminho produziria um diagrama maior sem acréscimo de informação. Em BPMN 2.0, múltiplas entradas em um elemento sem gateway de merge explícito são tratadas como merge exclusivo implícito — correto nestes casos porque os caminhos são mutuamente exclusivos.

### J4 — Loop de retorno após CIV com waypoints externos ao pool

A sequência flow de `T_MudarCIVParaAguardandoAceite` para `T_AceitarAnexoD` percorre o exterior do pool (waypoints com `y=970`, abaixo do limite `y=920` do pool). Esta é a técnica canônica de BPMN 2.0 para representar loops de retorno em diagramas horizontais sem cruzar elementos existentes. A alternativa — um Link Event ou Sub-processo — esconderia a natureza do loop e reduziria a rastreabilidade. O `<bpmn:documentation>` de `T_MudarCIVParaAguardandoAceite` alerta sobre o comportamento de rollback diferenciado na segunda tentativa de renovação (quando a última vistoria está `REPROVADO`).

### J5 — T_EmitirAPPCI e T_EmitirCIV na mesma coluna com separação vertical

Os dois service tasks de emissão (`T_EmitirAPPCI` e `T_EmitirCIV`) ocupam a mesma coluna horizontal (`x ≈ 3640`) mas posições verticais distintas dentro de `Lane_Sistema`. Essa disposição deixa visualmente evidente que são caminhos alternativos: ambos partem de `GW_VistoriaAprovada` e ambos resultam em emissão de documento, mas de tipos opostos. A separação vertical dentro da mesma raia e coluna é o padrão para caminhos mutuamente exclusivos que executam a mesma categoria de operação.

### J6 — T_CienciaAPPCI e T_CienciaCIV em sub-areas verticais de Lane_Cidadao

Analogamente, `T_CienciaAPPCI` e `T_CienciaCIV` ocupam a área superior (`y ≈ 79`) e inferior (`y ≈ 179`) da raia `Lane_Cidadao`, respectivamente. Essa consistência vertical entre as raias `Lane_Sistema` e `Lane_Cidadao` — elementos deferidos em cima, indeferidos em baixo — facilita a leitura: o leitor identifica o caminho deferido pela posição superior dos elementos e o caminho indeferido pela posição inferior, mesmo sem ler os rótulos.

### J7 — Ausência de Boundary Error Events

Conforme explicado na seção 2, não há `<bpmn:error>` nem Boundary Error Events no modelo. O tratamento de erros é integralmente feito em Java via `BusinessException`, `@TransactionAttribute` e validações antecipadas. Usar Boundary Error Events criaria a impressão incorreta de que o motor BPMN trata os erros — o que não ocorre nesta implementação EJB pura sem um motor BPMN de processo (como Camunda Engine) em execução.

### J8 — GW_MergeAntesDist como explicit merge gateway

O gateway `GW_MergeAntesDist` é explicitado no diagrama, embora tecnicamente pudesse ser eliminado conectando os dois caminhos diretamente a `T_MudarAguardandoDistribuicao`. A manutenção do gateway explícito serve a dois propósitos:

1. **Clareza semântica:** deixa inequívoco que os dois caminhos (isenção aprovada e pagamento confirmado) convergem em um único ponto antes de avançar. Um leitor que não conheça a regra de merge implícito do BPMN poderia se confundir ao ver duas entradas diretas em um service task.
2. **Rastreabilidade:** o gateway tem `<bpmn:documentation>` que explica os dois caminhos que convergem, facilitando a compreensão do fluxo sem consultar o código.

### J9 — Segmentação em seis fases como estrutura narrativa

O diagrama segmenta o processo em seis fases (`<!-- ===== FASE N ===== -->`) nos comentários XML. Essa segmentação não é um elemento BPMN — é puramente documental — mas serve como guia de navegação no XML para desenvolvedores e auditores. Cada fase corresponde a uma etapa de negócio claramente distinta (iniciação, aceite, pagamento, distribuição, vistoria, conclusão), e os elementos agrupados em cada fase compartilham a mesma `SituacaoLicenciamento` no licenciamento durante sua execução. Isso torna o XML auto-documentado e reduz o custo de manutenção.
