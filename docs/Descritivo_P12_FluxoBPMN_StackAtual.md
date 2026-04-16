# Descritivo do Fluxo BPMN — P12: Extinção de Licenciamento
## Stack Atual (Java EE · CBM-RS SOL)

**Processo:** P12 — Extinção de Licenciamento
**Arquivo BPMN:** `P12_ExtincaoLicenciamento_StackAtual.bpmn`
**Data:** 2026-03-13

---

## Sumário

1. [Visão Geral da Modelagem](#1-visão-geral-da-modelagem)
2. [Estrutura do Diagrama: Pool e Raias](#2-estrutura-do-diagrama-pool-e-raias)
3. [Fluxo A — Cidadão Solicita Extinção: Fase de Entrada e Validação](#3-fluxo-a--cidadão-solicita-extinção-fase-de-entrada-e-validação)
4. [Fluxo A — Fase de Decisão: RT Ativo e Perfil do Solicitante](#4-fluxo-a--fase-de-decisão-rt-ativo-e-perfil-do-solicitante)
5. [Fluxo A — Etapa de Aceite do RT](#5-fluxo-a--etapa-de-aceite-do-rt)
6. [Fluxo A — Extinção Direta e Conclusão](#6-fluxo-a--extinção-direta-e-conclusão)
7. [Fluxo B — Administrador Extingue Diretamente](#7-fluxo-b--administrador-extingue-diretamente)
8. [Fluxo B — Administrador Cancela Extinção Pendente](#8-fluxo-b--administrador-cancela-extinção-pendente)
9. [Justificativas de Modelagem](#9-justificativas-de-modelagem)
10. [Diagrama de Estados do Licenciamento (P12)](#10-diagrama-de-estados-do-licenciamento-p12)
11. [Referência Cruzada: Elementos BPMN × Código Java](#11-referência-cruzada-elementos-bpmn--código-java)
12. [Tabelas de Banco de Dados Afetadas](#12-tabelas-de-banco-de-dados-afetadas)

---

## 1. Visão Geral da Modelagem

O BPMN do processo P12 modela a **extinção formal de um licenciamento** no SOL — a operação que encerra permanentemente o ciclo de vida de um PPCI ou PSPCIM, transitando sua situação para `EXTINGUIDO`.

A modelagem captura dois fluxos principais, estruturalmente distintos:

- **Fluxo A:** Iniciado pelo cidadão (RT, RU ou Proprietário). Inclui etapa condicional de aceite do RT quando o solicitante não é o próprio RT. Possui três desfechos: extinção efetivada, extinção recusada (pelo RT) ou extinção cancelada (pelo cidadão).
- **Fluxo B:** Iniciado pelo Administrador do CBM-RS. Extinção direta sem etapa de aceite, e também a operação de cancelamento de extinção pendente pelo administrador.

O diagrama usa **um único pool** com **três raias** (Cidadão, Sistema SOL, Administrador), tornando explícita a separação de responsabilidades entre o ator humano, o processamento do backend e o papel administrativo.

---

## 2. Estrutura do Diagrama: Pool e Raias

### Pool: `P12 — Extinção de Licenciamento`

Um único pool foi escolhido porque todos os participantes compartilham o mesmo processo de negócio. Não há integração com sistema externo autônomo (diferente de P11, que integra com PROCERGS/Banrisul) — logo, não há segundo pool.

### Raia 1: `Cidadão (RT / RU / Proprietário)`

Contém os eventos de início e as user tasks associadas ao portal do cidadão: solicitação de extinção, aceite/recusa pelo RT e cancelamento pelo cidadão. Esta raia representa o que o usuário humano vê e faz na interface Angular.

**Motivo:** Separar visualmente o que é ação humana do que é processamento automático do backend, facilitando o entendimento por equipes de frontend e de produto.

### Raia 2: `Sistema SOL (Backend Java EE)`

Contém todas as service tasks (EJBs), gateways de decisão e end events que representam processamento automático do servidor: validações, troca de estado, cancelamento de recursos, registros de marcos e envio de notificações.

**Motivo:** O backend concentra toda a lógica transacional. Isolá-lo em raia própria evidencia que cada service task é uma transação EJB `@Required` e que o sistema opera de forma transparente ao usuário.

### Raia 3: `Administrador CBM-RS`

Contém o fluxo alternativo do portal de administração: start event, user task de confirmação, e o fluxo de cancelamento admin. O administrador tem um caminho independente que bypassa a etapa de aceite do RT.

**Motivo:** O papel do administrador tem semântica distinta — extingue diretamente, sem necessidade de aceite. Separar em raia deixa isso imediatamente legível no diagrama sem necessidade de ler a documentação técnica.

---

## 3. Fluxo A — Cidadão Solicita Extinção: Fase de Entrada e Validação

### `Start_P12` — Start Event: "Cidadão solicita extinção"

**O que representa:** O momento em que o cidadão autenticado via SOE PROCERGS aciona a opção de extinguir o licenciamento no portal Angular.

**Por que é um start event simples (não mensagem):** O processo é iniciado por ação direta do usuário na interface — não há mensagem assíncrona nem sinal externo. Um start event simples é o elemento correto para ações de usuário em portais web.

---

### `UT_SolicitarExtincao` — User Task: "Confirmar pedido de extinção"

**O que representa:** O modal de confirmação exibido pelo `ModalExtincaoLicenciamentoComponent` no Angular. O cidadão clica em "Extinguir" e dispara `POST /licenciamentos/{idLic}/extinguir`.

**Por que é User Task e não apenas um gateway:** Em BPMN, a interação com o usuário deve ser representada por User Task. O clique no botão não é instantâneo — há uma etapa de decisão do usuário (confirmar ou cancelar o modal). Modelar como User Task documenta explicitamente esse momento de interação.

---

### `ST_ValidarSituacao` — Service Task: "Validar situação do licenciamento"

**O que representa:** A chamada ao EJB `LicenciamentoCidadaoExtincaoRNVal.validarExtinguir()`, que verifica se a `SituacaoLicenciamento` atual permite extinção. Implementa RN-109 (situações incondicionalmente bloqueadoras) e RN-110 (situações bloqueadoras sem análise).

**Por que é separado em Service Task própria:** A validação da situação é uma operação de consulta com potencial de lançar exceção de negócio — não deve ser embutida no gateway. Separar em Service Task deixa claro que há lógica executável nesse ponto e permite que a documentação do elemento referencie as regras de negócio específicas.

---

### `GW_SituacaoValida` — Gateway Exclusivo: "Situação permite extinção?"

**O que representa:** A bifurcação baseada no resultado da validação: situação válida (fluxo continua) ou inválida (end event de erro).

**Por que é gateway exclusivo e não gateway de eventos:** A decisão é baseada em dado do banco de dados (situação do licenciamento), não em evento assíncrono. O gateway exclusivo (XOR) é o padrão correto para decisões baseadas em estado interno.

**Tratamento do caminho "Não":** A sequência flui para `End_ErroSituacao` (Error End Event), modelado com marcador de erro BPMN. Isso sinaliza que o processo termina com exceção de negócio — o backend retorna HTTP 422 e o Angular exibe a mensagem de erro no modal.

**Motivo do Error End Event:** Na stack atual, `NegocioException` é lançada e mapeada para HTTP 422 via `ExceptionMapper` JAX-RS. O Error End Event documenta que este é um encerramento excepcional, não uma conclusão normal do processo.

---

### `ST_VerificarTrocaEnvolvido` — Service Task: "Verificar troca de envolvido pendente"

**O que representa:** Consulta ao `TrocaEnvolvidoDAO` para verificar se há `TrocaEnvolvidoED` em situação de avaliação ativa para o licenciamento (RN-115).

**Por que é uma service task separada e não parte da validação anterior:** A verificação de troca de envolvido é uma consulta a uma entidade completamente distinta (`CBM_TROCA_ENVOLVIDO`), com semântica de bloqueio diferente das regras de situação. Separar em task própria permite rastrear individualmente esse ponto de verificação e facilita diagnóstico de falhas em ambiente de produção.

---

### `GW_TrocaEnvolvidoPendente` — Gateway Exclusivo: "Troca de envolvido em avaliação?"

**O que representa:** Bifurcação baseada na existência de troca de envolvido pendente.

**Caminho "Sim":** End Event de erro com código `EXTINCAO_BLOQUEADA_TROCA_ENVOLVIDO`. Este bloqueio é independente da situação do licenciamento — mesmo um licenciamento em situação válida não pode ser extinguido se houver troca em andamento.

**Caminho "Não":** Prossegue para o cancelamento automático de recursos.

---

### `ST_CancelarRecursosPendentes` — Service Task: "Cancelar recursos pendentes (automático)"

**O que representa:** A operação `RecursoRN.cancelarPorExtincao(idLicenciamento)` que cancela automaticamente todos os recursos (`RecursoED`) do licenciamento em situação de análise pendente, registrando marco `RECURSO_CANCELADO_EXTINCAO` para cada um.

**Por que ocorre antes da decisão sobre RT:** O cancelamento de recursos é uma pré-condição para qualquer caminho de extinção — seja direto ou com etapa de aceite do RT. Posicioná-lo antes do gateway de decisão sobre o RT evita duplicação da lógica nos dois caminhos e garante que recursos são sempre cancelados antes de qualquer transição de estado do licenciamento.

**Por que é automático e não requer confirmação:** A RN-113 define que o cancelamento é automático. O cidadão não precisa confirmar individualmente cada recurso — a extinção implica o encerramento de todos os processos paralelos ativos.

---

## 4. Fluxo A — Fase de Decisão: RT Ativo e Perfil do Solicitante

### `GW_TemRTAtivo` — Gateway Exclusivo: "Há RT ativo no licenciamento?"

**O que representa:** Verificação da existência de `ResponsavelTecnicoED` com situação `ATIVO` vinculado ao licenciamento.

**Por que é necessário:** A existência de RT ativo determina se a extinção requer etapa de aceite. Sem RT ativo, a extinção pode ser efetivada diretamente por qualquer ator cidadão.

**Caminho "Não":** O processo vai direto para `ST_ExtinguirDireto` — não há etapa de aceite.

**Caminho "Sim":** Passa para o próximo gateway, que verifica o perfil do solicitante.

---

### `GW_SolicitanteEhRT` — Gateway Exclusivo: "Solicitante é o RT?"

**O que representa:** Comparação entre o CPF do usuário autenticado (extraído do token OIDC) e o CPF do RT ativo vinculado ao licenciamento.

**Por que é necessário este segundo gateway:** A RN-111 distingue dois sub-casos quando há RT ativo: se o próprio RT solicita a extinção, ela é efetivada diretamente (sem etapa de aceite de si mesmo); se outro ator solicita, o RT precisa se manifestar. Dois gateways em cascata mantêm cada decisão coesa e legível.

**Caminho "Sim (RT solicitou)":** Vai para `ST_ExtinguirDireto`.
**Caminho "Não (RU/Proprietário)":** Vai para `ST_AguardarAceiteRT`.

---

## 5. Fluxo A — Etapa de Aceite do RT

### `ST_AguardarAceiteRT` — Service Task: "Aguardar aceite do RT"

**O que representa:** A transação EJB que:
1. Atualiza a situação do licenciamento para `AGUARDANDO_ACEITES_EXTINCAO`.
2. Grava `solicitanteExtincao = false` no `ResponsavelTecnicoED`.
3. Registra o marco `AGUARDANDO_ACEITE_EXTINCAO`.
4. Envia e-mail ao RT informando que há uma solicitação de extinção aguardando sua manifestação.

**Por que transita para o intermediário e não diretamente para EXTINGUIDO:** A regra de negócio exige o aceite explícito do RT. O estado `AGUARDANDO_ACEITES_EXTINCAO` serve como estado de suspensão do processo, sinalizando a todos os sistemas e atores que há uma ação pendente do RT.

---

### `UT_AceitarRecusarExtincao` — User Task: "RT: aceitar, recusar ou cancelar extinção"

**O que representa:** A interação do RT com o portal Angular ao visualizar a solicitação pendente de extinção no `ModalExtincaoLicenciamentoComponent` (versão RT). O RT tem três opções:
- **Aceitar** a extinção (caminho "Aceita" no gateway).
- **Recusar** (PUT `/recusa-extincao`).
- **Cancelar** (disponível também para RU/Proprietário via Boundary Event).

**Por que User Task e não Intermediate Event:** O RT é um ator humano realizando uma ação consciente e deliberada. User Task documenta isso corretamente e permite atribuição de responsável (`camunda:assignee`).

---

### `BoundaryCancel_AguardaAceite` — Boundary Event de Cancelamento

**O que representa:** O evento gerado quando o cidadão (RU ou Proprietário) cancela a solicitação de extinção enquanto o RT ainda não se manifestou. O evento cancela a User Task corrente e direciona o fluxo para `ST_CancelarExtincaoCidadao`.

**Por que Boundary Event e não apenas um caminho de saída da User Task:** O cancelamento pelo cidadão pode ocorrer em qualquer momento enquanto o processo aguarda o RT — é um evento assíncrono que interrompe a espera. O Boundary Cancel Event modela exatamente essa semântica de interrupção assíncrona, que é diferente de uma decisão tomada dentro da User Task.

**Por que `cancelActivity="true"`:** Ao cancelar, a User Task corrente deve ser encerrada — o RT não precisa mais se manifestar. O `cancelActivity="true"` instrui o engine a interromper a task.

---

### `End_AguardandoAceite` — End Event: "Notificado RT — aguardando resposta"

**O que representa:** O fim da etapa de solicitação do ponto de vista do solicitante (RU/Proprietário). O processo está suspenso aguardando o RT, mas do ponto de vista do fluxo de solicitação, a ação do cidadão está concluída.

**Nota de modelagem:** Este End Event não representa o fim do processo — o licenciamento permanece em `AGUARDANDO_ACEITES_EXTINCAO`. Na prática, o processo BPMN como um todo só termina quando o RT se manifesta ou quando o cidadão cancela. Esta modelagem reflete a natureza assíncrona da espera.

---

### `GW_DecisaoRT` — Gateway Exclusivo: "Decisão do RT?"

**O que representa:** Bifurcação baseada na ação tomada pelo RT:
- **"Aceita":** vai para `ST_EfetivarExtincaoAposAceite`.
- **"Recusa":** vai para `ST_RecusarExtincao`.

**Por que exclusivo e não paralelo:** O RT toma uma única decisão — aceitar ou recusar. São caminhos mutuamente exclusivos.

---

### `ST_EfetivarExtincaoAposAceite` — Service Task: "Efetivar extinção após aceite do RT"

**O que representa:** O EJB `TrocaEstadoLicenciamentoParaExtinguidoRN.trocaEstado()` chamado após aceite do RT:
1. Atualiza situação para `EXTINGUIDO`.
2. Grava `aceiteExtincao = true` e `dthAceiteExtincao = now()` no `ResponsavelTecnicoED`.
3. Registra marco `EXTINCAO`.

**Por que é uma Service Task separada de `ST_ExtinguirDireto`:** Embora ambas efetivem a extinção, o aceite do RT envolve campos adicionais no `ResponsavelTecnicoED` — gravar o aceite e a data. A separação permite documentar essas diferenças nos atributos `<documentation>` do elemento.

---

### `ST_RecusarExtincao` — Service Task: "Registrar recusa da extinção"

**O que representa:** O EJB `LicenciamentoCidadaoExtincaoRN.recusa()`:
1. Grava `aceiteExtincao = false` e `dthAceiteExtincao = now()` no `ResponsavelTecnicoED`.
2. Restaura a situação anterior do licenciamento (RN-117).
3. Registra marco `RECUSA_EXTINCAO`.

**Por que o processo não simplesmente "desfaz" o estado:** A recusa não é um rollback técnico — é uma transição de estado intencional e auditável. O marco `RECUSA_EXTINCAO` garante rastreabilidade completa, e a situação anterior restaurada é persistida via lógica de negócio, não via rollback de banco.

**End Event `End_ExtincaoRecusada`:** Encerra o fluxo com situação restaurada. Não é um Error End Event — a recusa é um desfecho válido e esperado do processo.

---

### `ST_CancelarExtincaoCidadao` — Service Task: "Cancelar extinção (cidadão)"

**O que representa:** O EJB `LicenciamentoCidadaoExtincaoRN.cancelar()`:
1. Restaura a situação anterior.
2. Zera `aceiteExtincao`, `solicitanteExtincao` e `dthAceiteExtincao` no `ResponsavelTecnicoED`.
3. Registra marco `CANCELAMENTO_EXTINCAO`.

**Por que zera os campos enquanto a recusa apenas grava o valor:** O cancelamento encerra totalmente o processo de extinção, limpando todos os dados relacionados para que uma nova solicitação possa ser feita no futuro. A recusa do RT também encerra, mas mantém o registro da recusa para fins de auditoria.

---

## 6. Fluxo A — Extinção Direta e Conclusão

### `ST_ExtinguirDireto` — Service Task: "Extinguir licenciamento diretamente"

**O que representa:** O caminho em que não há etapa de aceite: RT é o solicitante, ou não há RT ativo. O EJB `TrocaEstadoLicenciamentoParaExtinguidoRN.trocaEstado()` é chamado diretamente:
1. Atualiza situação para `EXTINGUIDO`.
2. Registra marco `EXTINCAO`.

**Por que recebe dois fluxos de entrada (sem RT e RT solicitante):** Ambos os casos convergem no mesmo comportamento de negócio. Fusão via múltiplas `<incoming>` em uma única Service Task simplifica o modelo sem perder semântica.

---

### `ST_NotificarExtincao` — Service Task: "Notificar todos os envolvidos (extinção)"

**O que representa:** O EJB `NotificacaoRN.notificar()` enviando e-mail a RT, RU e Proprietários. Recebe dois fluxos de entrada: extinção direta e extinção após aceite do RT.

**Por que é uma task separada e não embutida nas tasks de extinção:** A notificação é uma operação secundária que não deve interferir na transação de persistência da extinção. Separar permite, em implementações futuras, torná-la assíncrona sem modificar a lógica de extinção.

---

### `End_Extinto` — End Event: "Licenciamento EXTINGUIDO"

**O que representa:** O encerramento bem-sucedido do processo P12 com o licenciamento em estado `EXTINGUIDO`. Este é um estado terminal — o licenciamento não pode mais sofrer nenhuma alteração (RN-114).

---

## 7. Fluxo B — Administrador Extingue Diretamente

### `Start_Admin` — Start Event: "Administrador inicia extinção"

**O que representa:** O Administrador do CBM-RS acessa o portal de administração e seleciona um licenciamento para extinguir.

**Por que é um Start Event separado e não uma lane adicional no mesmo fluxo:** O fluxo do Administrador tem semântica fundamentalmente diferente: ele extingue diretamente (RN-112), sem etapa de aceite do RT, e usa um endpoint diferente (`/adm/licenciamentos/{idLic}/extinguir`). Modelar como fluxo separado (com start event próprio na raia Admin) deixa isso imediatamente claro.

---

### `UT_ExtinguirAdmin` — User Task: "Admin confirma extinção no sistema"

**O que representa:** A interação do administrador no portal admin Angular — confirmação via modal antes de chamar `POST /adm/licenciamentos/{idLic}/extinguir`.

---

### `ST_ValidarSituacaoAdmin` → `GW_SituacaoValidaAdmin`

**O que representa:** As mesmas validações de RN-109 e RN-110 aplicadas ao fluxo cidadão. O Administrador não tem privilégio para extinguir em situações bloqueadoras — as regras de negócio são universais.

**Por que modelar a validação novamente:** Em BPMN, os fluxos do pool devem ser autocontidos. Reutilizar elementos entre raias (apontar para service tasks da raia Sistema) criaria arestas cruzando raias desnecessariamente, dificultando a leitura. A repetição da validação no fluxo admin é intencional e documenta que o admin passa pelas mesmas verificações.

---

### `ST_ExtinguirAdmin` — Service Task: "Extinguir licenciamento (admin, direto)"

**O que representa:** A mesma `TrocaEstadoLicenciamentoParaExtinguidoRN`, mas chamada via `extingueAdm()`. A extinção ocorre sem qualquer verificação de aceite de RT.

**Por que diferente do fluxo cidadão:** O método `extingueAdm()` no EJB não verifica o perfil do solicitante nem a existência de RT ativo. Isso está codificado na lógica do método — o BPMN reflete esse comportamento, tornando o bypass explícito e documentado.

---

## 8. Fluxo B — Administrador Cancela Extinção Pendente

### `UT_CancelarExtincaoAdmin` → `ST_CancelarExtincaoAdmin` → `ST_NotificarCancelamentoAdmin` → `End_CanceladoAdmin`

**O que representa:** O Administrador pode cancelar uma extinção que está em `AGUARDANDO_ACEITES_EXTINCAO` (quando foi solicitada por um cidadão e aguarda o RT). O endpoint é `PUT /adm/licenciamentos/{idLic}/cancelar-extincao`.

**Por que modelar como fluxo independente na raia Admin:** O cancelamento pelo administrador é uma ação administrativa de gestão, distinta do cancelamento pelo próprio cidadão. Modelar na raia Admin documenta que este caminho exige perfil administrativo e usa endpoint diferente.

**Por que não há start event formal para o cancelamento admin:** O cancelamento admin não tem trigger de entrada no processo (ele é iniciado pela disponibilidade do botão na interface, condicionada ao estado `AGUARDANDO_ACEITES_EXTINCAO`). A User Task `UT_CancelarExtincaoAdmin` representa o ponto de entrada deste sub-fluxo.

---

## 9. Justificativas de Modelagem

### J1 — Por que um único pool com três raias em vez de dois pools

P12 não integra com sistema externo autônomo (diferente de P11 com PROCERGS). Cidadão, Sistema e Administrador são participantes do mesmo processo de negócio do SOL. Múltiplos pools seriam usados apenas se houvesse um participante externo independente com processo próprio.

### J2 — Por que dois start events e não um com gateway

Os fluxos do cidadão e do administrador têm pontos de entrada distintos (portais e endpoints diferentes), regras de autorização diferentes e comportamentos de negócio distintos. Dois start events tornam imediatamente legível que estes são caminhos alternativos, não caminhos do mesmo fluxo.

### J3 — Por que o estado AGUARDANDO_ACEITES_EXTINCAO é modelado como suspend (User Task) e não como Intermediate Event

O estado `AGUARDANDO_ACEITES_EXTINCAO` requer uma ação humana ativa do RT — não é apenas uma espera por evento externo. User Task é o elemento correto para representar "aguardar ação de um ator". Um Intermediate Event seria adequado se o sistema estivesse esperando uma mensagem ou sinal externo sem ação humana explícita.

### J4 — Por que o Boundary Cancel Event em vez de apenas uma transição de saída da User Task

O cancelamento pelo cidadão é assíncrono — pode ocorrer em qualquer momento enquanto a User Task do RT está ativa. O Boundary Event modela exatamente essa interrupção assíncrona. Uma transição de saída comum da User Task implicaria que o cidadão cancelaria como resultado da ação do RT, o que é semanticamente incorreto.

### J5 — Por que Service Tasks separadas para validação e troca de estado

Cada Service Task representa uma transação EJB `@Required`. A validação (`LicenciamentoCidadaoExtincaoRNVal`) e a troca de estado (`TrocaEstadoLicenciamentoParaExtinguidoRN`) são EJBs distintos com responsabilidades distintas. Fundir em uma única task ocultaria a separação de responsabilidades do código Java.

### J6 — Por que Error End Events para situação inválida e troca de envolvido

No sistema atual, esses casos são tratados como `NegocioException` → HTTP 422. O Error End Event em BPMN é o análogo direto de uma exceção de negócio — sinaliza que o processo termina em estado de erro, não em conclusão normal. Usar End Event simples ocultaria a natureza excepcional desses desfechos.

### J7 — Por que `ST_CancelarRecursosPendentes` antes dos gateways de RT

O cancelamento automático de recursos é invariante — ocorre independentemente do caminho de extinção (com ou sem RT, cidadão ou admin). Posicioná-lo antes dos gateways garante que só é executado uma vez e que nenhum caminho o ignora.

### J8 — Por que `ST_NotificarExtincao` recebe dois fluxos de entrada

Extinção direta (RT ou sem RT) e extinção após aceite do RT resultam no mesmo estado final (`EXTINGUIDO`) e no mesmo conjunto de notificações. Convergir em uma única Service Task de notificação elimina duplicação de lógica no modelo e no código.

---

## 10. Diagrama de Estados do Licenciamento (P12)

```
[QUALQUER ESTADO VÁLIDO]
(APROVADO, ALVARA_VIGENTE, ALVARA_VENCIDO,
 e RASCUNHO/AGUARDANDO_PAGAMENTO/AGUARDANDO_ACEITE quando há análise)
        |
        |─── Cidadão (RT/sem RT) ou Admin solicita extinção
        |                    |
        |                    v
        |        [AGUARDANDO_ACEITES_EXTINCAO]
        |              |            |
        |         RT aceita    RT recusa / cidadão cancela
        |              |            |
        v              v            v
  [EXTINGUIDO]   [EXTINGUIDO]  [ESTADO ANTERIOR RESTAURADO]
  (direto)       (após aceite)
```

### Estados bloqueadores para extinção

| Categoria | Situações |
|---|---|
| **Incondicionais (sempre bloqueiam)** | `ANALISE_INVIABILIDADE_PENDENTE`, `AGUARDA_DISTRIBUICAO_VISTORIA`, `ANALISE_ENDERECO_PENDENTE`, `AGUARDANDO_DISTRIBUICAO`, `EM_ANALISE`, `EM_VISTORIA`, `RECURSO_EM_ANALISE_*_CIA/CIV`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO`, `EXTINGUIDO` |
| **Condicionais (bloqueiam sem análise)** | `RASCUNHO`, `AGUARDANDO_PAGAMENTO`, `AGUARDANDO_ACEITE` |
| **Permitem extinção** | `APROVADO`, `ALVARA_VIGENTE`, `ALVARA_VENCIDO`; e os condicionais quando há análise registrada |

---

## 11. Referência Cruzada: Elementos BPMN × Código Java

| Elemento BPMN | ID | Classe Java | Método | Endpoint REST |
|---|---|---|---|---|
| Start_P12 | `Start_P12` | — | — | POST `/licenciamentos/{id}/extinguir` |
| UT_SolicitarExtincao | `UT_SolicitarExtincao` | `ModalExtincaoLicenciamentoComponent` (FE) | — | — |
| ST_ValidarSituacao | `ST_ValidarSituacao` | `LicenciamentoCidadaoExtincaoRNVal` | `validarExtinguir()` | — |
| GW_SituacaoValida | `GW_SituacaoValida` | — | — | — |
| ST_VerificarTrocaEnvolvido | `ST_VerificarTrocaEnvolvido` | `LicenciamentoCidadaoExtincaoRN` | `validarTrocaEnvolvido()` | — |
| ST_CancelarRecursosPendentes | `ST_CancelarRecursosPendentes` | `RecursoRN` | `cancelarPorExtincao()` | — |
| GW_TemRTAtivo | `GW_TemRTAtivo` | `LicenciamentoCidadaoExtincaoRN` | `temRTAtivo()` | — |
| GW_SolicitanteEhRT | `GW_SolicitanteEhRT` | `LicenciamentoCidadaoExtincaoRN` | `solicitanteEhRT()` | — |
| ST_AguardarAceiteRT | `ST_AguardarAceiteRT` | `LicenciamentoCidadaoExtincaoRN` | `extingue()` (caminho B) | — |
| UT_AceitarRecusarExtincao | `UT_AceitarRecusarExtincao` | `ModalExtincaoLicenciamentoComponent` (FE, modo RT) | — | PUT `/recusa-extincao` |
| BoundaryCancel | `BoundaryCancel_AguardaAceite` | — | — | PUT `/cancelar-extincao` |
| ST_EfetivarExtincaoAposAceite | `ST_EfetivarExtincaoAposAceite` | `TrocaEstadoLicenciamentoParaExtinguidoRN` | `trocaEstado()` | — |
| ST_RecusarExtincao | `ST_RecusarExtincao` | `LicenciamentoCidadaoExtincaoRN` | `recusa()` | PUT `/recusa-extincao` |
| ST_ExtinguirDireto | `ST_ExtinguirDireto` | `TrocaEstadoLicenciamentoParaExtinguidoRN` | `trocaEstado()` | — |
| ST_NotificarExtincao | `ST_NotificarExtincao` | `NotificacaoRN` | `notificar()` | — |
| ST_CancelarExtincaoCidadao | `ST_CancelarExtincaoCidadao` | `LicenciamentoCidadaoExtincaoRN` | `cancelar()` | PUT `/cancelar-extincao` |
| Start_Admin | `Start_Admin` | — | — | POST `/adm/licenciamentos/{id}/extinguir` |
| UT_ExtinguirAdmin | `UT_ExtinguirAdmin` | `ModalExtincaoLicenciamentoComponent` (ADM) | — | — |
| ST_ExtinguirAdmin | `ST_ExtinguirAdmin` | `TrocaEstadoLicenciamentoParaExtinguidoRN` | `trocaEstado()` | — |
| UT_CancelarExtincaoAdmin | `UT_CancelarExtincaoAdmin` | — | — | PUT `/adm/licenciamentos/{id}/cancelar-extincao` |
| ST_CancelarExtincaoAdmin | `ST_CancelarExtincaoAdmin` | `LicenciamentoCidadaoExtincaoRN` | `cancelarAdm()` | — |

---

## 12. Tabelas de Banco de Dados Afetadas

| Operação | Tabelas Oracle escritas | Tabelas Oracle lidas |
|---|---|---|
| Validar situação | — | `CBM_LICENCIAMENTO`, `CBM_ANALISE_TECNICA`, `CBM_ANALISE_ISENCAO` |
| Verificar troca envolvido | — | `CBM_TROCA_ENVOLVIDO` |
| Cancelar recursos | `CBM_RECURSO`, `CBM_LICENCIAMENTO_MARCO` | `CBM_RECURSO` |
| Aguardar aceite RT | `CBM_LICENCIAMENTO`, `CBM_RESPONSAVEL_TECNICO`, `CBM_LICENCIAMENTO_MARCO` | `CBM_RESPONSAVEL_TECNICO` |
| Efetivar extinção | `CBM_LICENCIAMENTO`, `CBM_RESPONSAVEL_TECNICO`, `CBM_LICENCIAMENTO_MARCO` | — |
| Extinção direta | `CBM_LICENCIAMENTO`, `CBM_LICENCIAMENTO_MARCO` | — |
| Recusar extinção | `CBM_LICENCIAMENTO`, `CBM_RESPONSAVEL_TECNICO`, `CBM_LICENCIAMENTO_MARCO` | — |
| Cancelar extinção | `CBM_LICENCIAMENTO`, `CBM_RESPONSAVEL_TECNICO`, `CBM_LICENCIAMENTO_MARCO` | — |
| Notificar envolvidos | — | `CBM_USUARIO`, `CBM_RESPONSAVEL_TECNICO`, `CBM_RESPONSAVEL_USO`, `CBM_PROPRIETARIO` |
