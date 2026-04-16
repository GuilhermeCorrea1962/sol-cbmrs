# Descritivo do Fluxo BPMN — P08 Emissão e Aceite do PRPCI (Stack Atual Java EE)

**Arquivo BPMN:** `P08_EmissaoPRPCI_StackAtual.bpmn`
**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Stack:** Java EE · JAX-RS · CDI · JPA/Hibernate · EJB `@Stateless` · SOE PROCERGS · Alfresco ECM

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Estrutura de Pools, Raias e Justificativa de Modelagem](#2-estrutura-de-pools-raias-e-justificativa-de-modelagem)
3. [Sub-processo P08-A — Emissão Normal do PRPCI pelo RT](#3-sub-processo-p08-a--emissão-normal-do-prpci-pelo-rt)
   - 3.1 [Evento de Início e Contexto de Entrada](#31-evento-de-início-e-contexto-de-entrada)
   - 3.2 [Tarefa do RT: Upload do Arquivo PRPCI](#32-tarefa-do-rt-upload-do-arquivo-prpci)
   - 3.3 [Validação do Arquivo e da Situação do Licenciamento](#33-validação-do-arquivo-e-da-situação-do-licenciamento)
   - 3.4 [Gateway de Decisão: Arquivo e Situação Válidos?](#34-gateway-de-decisão-arquivo-e-situação-válidos)
   - 3.5 [Loop-back: Reenvio pelo RT em Caso de Erro](#35-loop-back-reenvio-pelo-rt-em-caso-de-erro)
   - 3.6 [Armazenamento no Alfresco ECM](#36-armazenamento-no-alfresco-ecm)
   - 3.7 [Persistência do PrpciED no Banco Relacional](#37-persistência-do-prpcied-no-banco-relacional)
   - 3.8 [Transição de Estado: AGUARDANDO_PRPCI → ALVARA_VIGENTE](#38-transição-de-estado-aguardando_prpci--alvara_vigente)
   - 3.9 [Evento de Fim: APPCI Normal Emitido](#39-evento-de-fim-appci-normal-emitido)
4. [Sub-processo P08-B — Aceite do PRPCI pelo RU/Proprietário (Renovação)](#4-sub-processo-p08-b--aceite-do-prpci-pelo-ruproprietário-renovação)
   - 4.1 [Evento de Início e Contexto de Entrada](#41-evento-de-início-e-contexto-de-entrada)
   - 4.2 [Tarefa do RU: Acesso ao Painel do Licenciamento](#42-tarefa-do-ru-acesso-ao-painel-do-licenciamento)
   - 4.3 [Verificação de Elegibilidade para Aceite](#43-verificação-de-elegibilidade-para-aceite)
   - 4.4 [Gateway de Decisão: Usuário Habilitado para Aceite?](#44-gateway-de-decisão-usuário-habilitado-para-aceite)
   - 4.5 [Evento de Fim de Erro: Sem Permissão](#45-evento-de-fim-de-erro-sem-permissão)
   - 4.6 [Retorno Cross-Lane e Tarefa de Aceite pelo RU](#46-retorno-cross-lane-e-tarefa-de-aceite-pelo-ru)
   - 4.7 [Validação dos Dados do Aceite](#47-validação-dos-dados-do-aceite)
   - 4.8 [Gateway de Decisão: Aceite Válido?](#48-gateway-de-decisão-aceite-válido)
   - 4.9 [Registro do Aceite na VistoriaED](#49-registro-do-aceite-na-vistoriaed)
   - 4.10 [Transição de Estado: AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE](#410-transição-de-estado-aguardando_aceite_prpci--alvara_vigente)
   - 4.11 [Evento de Fim: APPCI de Renovação Emitido](#411-evento-de-fim-appci-de-renovação-emitido)
5. [Máquinas de Estado, Marcos de Auditoria e TrocaEstado CDI](#5-máquinas-de-estado-marcos-de-auditoria-e-trocaestado-cdi)
6. [Segurança e Controle de Acesso](#6-segurança-e-controle-de-acesso)
7. [Integração com o Alfresco ECM](#7-integração-com-o-alfresco-ecm)
8. [Diferenças e Semelhanças entre P08-A e P08-B](#8-diferenças-e-semelhanças-entre-p08-a-e-p08-b)
9. [Rastreabilidade: Elementos do BPMN × Código-Fonte](#9-rastreabilidade-elementos-do-bpmn--código-fonte)

---

## 1. Visão Geral do Processo

O processo P08 representa a **etapa terminal do ciclo de licenciamento** no sistema SOL. É o único processo que leva o licenciamento ao estado definitivo `ALVARA_VIGENTE`, que corresponde à emissão efetiva do APPCI (Alvará de Prevenção e Proteção Contra Incêndio) e encerra formalmente a obrigação principal do ciclo iniciado no P03.

O P08 é sempre precedido pelo P07 (Vistoria Presencial). A forma como o P07 termina é que determina qual dos dois sub-fluxos do P08 será acionado:

- Se a vistoria foi do tipo **DEFINITIVA ou PARCIAL** e o resultado foi **aprovado**, o P07 transiciona o licenciamento para `AGUARDANDO_PRPCI`, ativando o **P08-A**. Neste caso, o RT (Responsável Técnico) deve fazer o upload do documento PRPCI em PDF.

- Se a vistoria foi do tipo **RENOVACAO** e o resultado foi **aprovado**, o P07 transiciona para `AGUARDANDO_ACEITE_PRPCI`, ativando o **P08-B**. Neste caso, o RU (Responsável pelo Uso) ou o Proprietário do imóvel deve conceder um aceite eletrônico.

Essa bifurcação não é representada dentro do P08 em si, mas é resultado direto das classes `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci` e `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci`, que pertencem ao P07 e ativam cada pool do P08 de forma mutuamente exclusiva.

A escolha de modelar o P08 com **dois pools independentes** na mesma colaboração (`Collab_P08`) foi intencional: os dois sub-processos não se comunicam, não compartilham dados em tempo real e nunca ocorrem simultaneamente para o mesmo licenciamento. São fluxos distintos que convergem para o mesmo estado final.

---

## 2. Estrutura de Pools, Raias e Justificativa de Modelagem

### Decisão de usar dois Pools (não dois Sub-Processos dentro de um único Pool)

A primeira decisão de modelagem foi se usar um único pool com um gateway de bifurcação no início, ou dois pools independentes. Optou-se por **dois pools** porque:

1. Os atores são diferentes: P08-A é protagonizado pelo RT; P08-B é protagonizado pelo RU/Proprietário. São personas com perfis de acesso distintos no SOE PROCERGS.
2. Os endpoints REST são diferentes: P08-A usa `PUT /prpci/{idLic}` (multipart com arquivo); P08-B usa `PUT /prpci/{idLic}/termo/{idVistoria}/aceite-prpci` (JSON sem arquivo).
3. O estado de entrada é diferente (`AGUARDANDO_PRPCI` vs `AGUARDANDO_ACEITE_PRPCI`), o que implica que nunca há dúvida sobre qual fluxo executar — o próprio estado do licenciamento determina o caminho.
4. Manter dois pools facilita a leitura independente de cada sub-processo, que é como a equipe técnica e os gestores do CBM-RS percebem esses fluxos na prática.

### Estrutura de Raias em cada Pool

Cada pool possui **duas raias horizontais**:

- **Raia superior — Cidadão (RT ou RU/Proprietário):** contém as tarefas humanas (`UserTask`) que representam a interação do ator externo com o frontend Angular. Posicionada no topo para manter a convenção do projeto: atores externos ficam acima dos internos.

- **Raia inferior — Sistema SOL Backend:** contém as tarefas de serviço (`ServiceTask`) que representam a execução de código Java EE no servidor WildFly. Cada `ServiceTask` tem o atributo `camunda:class` apontando para a classe EJB real (`@Stateless`) que implementa a lógica de negócio.

A separação entre as duas raias torna imediatamente visível qual parte de cada operação é responsabilidade do usuário (interação humana no navegador) e qual é automática (processamento servidor). Os fluxos que cruzam o limite de raias representam chamadas HTTP entre o frontend e o backend.

---

## 3. Sub-processo P08-A — Emissão Normal do PRPCI pelo RT

### 3.1 Evento de Início e Contexto de Entrada

O Pool P08-A começa com o evento de início **`Start_AguardandoPrpci`**, posicionado na raia superior (RT). O nome do evento — "Licenciamento em AGUARDANDO_PRPCI" — não é arbitrário: reflete exatamente o valor do campo `SIT_LICENCIAMENTO` na tabela `CBM_LICENCIAMENTO` que aciona este fluxo.

**Por que o evento de início fica na raia do RT?** Porque, assim que o licenciamento entra em `AGUARDANDO_PRPCI`, a ação imediata esperada é do RT: ele recebe uma notificação por e-mail e deve acessar o sistema para realizar o upload. O evento de início na raia do RT sinaliza visualmente que a "bola está com o RT" desde o primeiro momento.

A transição para `AGUARDANDO_PRPCI` foi realizada pela classe `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci` (no P07). Além de mudar a situação, essa classe já fechou o período `EM_VISTORIA`, abriu o período `AGUARDANDO_PRPCI` na tabela `CBM_SIT_LICENCIAMENTO` e disparou a notificação ao RT. Portanto, ao iniciar o P08-A, todos esses pré-requisitos já estão garantidos.

### 3.2 Tarefa do RT: Upload do Arquivo PRPCI

A `UserTask` **`UT_UploadPrpci`** ("RT seleciona e envia arquivo PRPCI") representa a interação humana central do P08-A. O RT acessa a tela de detalhe do licenciamento no frontend Angular, navega até a aba "PRPCI", seleciona o arquivo PDF e clica em "Enviar PRPCI".

Essa ação dispara uma chamada HTTP:
```
PUT /prpci/{idLic}
Content-Type: multipart/form-data
Authorization: Bearer {token_SOE}
Campo do formulário: "file" → arquivo PDF
```

A escolha de `PUT` (e não `POST`) reflete a semântica REST adotada no sistema SOL: o recurso PRPCI de um licenciamento é identificado pelo ID do licenciamento, e a operação é idempotente no sentido de que cada licenciamento possui exatamente um PRPCI ativo. O método `PUT` no endpoint `/prpci/{idLic}` é tratado por `PrpciRestImpl.inclui()`, que por sua vez delega para `PrpciCidadaoRN.inclui()`.

**Por que UserTask e não ServiceTask aqui?** Porque a tarefa exige ação humana explícita: o RT precisa localizar e selecionar o arquivo PDF correto no seu computador. Não há automatismo possível — é uma decisão do ator.

### 3.3 Validação do Arquivo e da Situação do Licenciamento

Logo após a submissão, ainda antes de qualquer persistência, o fluxo passa da raia do RT para a raia do Backend (cruzando o limite de raias em y≈190 no diagrama). A `ServiceTask` **`ST_ValidarUpload`** ("Validar arquivo e situação do licenciamento") invoca a classe `PrpciRNVal`, um EJB `@Stateless` responsável exclusivamente pelas validações do PRPCI.

São realizadas quatro verificações em `validaIncluiPrpci()`:

- **RN01 — Situação correta:** o licenciamento deve estar em `AGUARDANDO_PRPCI`. Esta validação existe porque um usuário mal-intencionado ou com múltiplas abas abertas poderia tentar fazer upload em momento inoportuno. A verificação protege a integridade da máquina de estados.

- **RN02 — Arquivo não nulo e não vazio:** previne o envio de arquivos corrompidos ou uploads interrompidos que chegaram com tamanho zero.

- **RN03 — Extensão e MIME type PDF:** o PRPCI deve ser um documento PDF (`application/pdf`). O sistema não aceita imagens, planilhas ou outros formatos, porque o documento tem valor jurídico-técnico e deve ser legível de forma padronizada.

- **RN04 — Vistoria concluída existente:** verifica que existe uma `VistoriaED` vinculada ao licenciamento com status `CONCLUIDA`. Esta validação impede upload de PRPCI em cenários onde a vistoria foi revertida ou está em estado inconsistente.

**Por que uma classe separada para validações (`PrpciRNVal`) em vez de validar dentro de `PrpciRN`?** O padrão do projeto SOL separa a lógica de validação da lógica de execução para facilitar testes unitários e reutilização. `PrpciRNVal` é injetada por CDI tanto em `PrpciCidadaoRN` (fluxo P08-A) quanto no fluxo de aceite (P08-B), evitando duplicação de código.

### 3.4 Gateway de Decisão: Arquivo e Situação Válidos?

O gateway exclusivo **`GW_UploadValido`** ("Arquivo e situação válidos?") representa a bifurcação lógica após a validação. Há dois caminhos:

- **Sim (`${arquivoValido == true}`):** nenhuma `SolNegocioException` foi lançada por `PrpciRNVal`. O fluxo prossegue para a gravação no Alfresco.

- **Não (`${arquivoValido == false}`):** `PrpciRNVal` lançou `SolNegocioException`, o `ExceptionMapper` JAX-RS converteu em HTTP 422, e o frontend Angular exibiu a mensagem de erro ao RT. O fluxo retorna para `UT_UploadPrpci`.

A modelagem como **gateway exclusivo** (diamante com "X") é correta porque as duas saídas são mutuamente exclusivas: ou o arquivo é válido ou não é. Um gateway paralelo seria errado aqui, pois não há execução simultânea de caminhos.

### 3.5 Loop-back: Reenvio pelo RT em Caso de Erro

O fluxo de retorno **`Flow_GW_Nao_Reupload`** representa uma das decisões de modelagem mais cuidadosas do P08-A. O loop-back reconecta o gateway `GW_UploadValido` de volta à `UT_UploadPrpci`, mas como essa reconexão é **cross-lane** (o gateway está na raia Backend e o UserTask está na raia RT), foi necessário definir waypoints explícitos para evitar sobreposição visual com os outros elementos:

```
(530, 365) → (530, 190) → (375, 190) → (375, 155)
```

O fluxo sobe verticalmente até a fronteira entre as raias (y=190), percorre horizontalmente para a esquerda até o eixo X do UserTask (x=375), e desce até o UserTask em y=155. O resultado visual é uma seta que contorna todos os elementos do Backend pelo lado esquerdo, deixando o diagrama legível.

**Por que modelar o loop explicitamente em vez de apenas exibir um erro e encerrar?** Porque o processo de upload do PRPCI é iterativo por natureza: o RT pode ter selecionado o arquivo errado, um arquivo corrompido ou um formato incorreto. Encerrar o processo por um erro de upload seria prejudicial ao licenciamento — obrigaria reabrir o processo por via administrativa. O loop permite que o RT corrija o problema sem intervenção do CBM-RS.

### 3.6 Armazenamento no Alfresco ECM

Após aprovação das validações, a `ServiceTask` **`ST_IncluirArquivoAlfresco`** ("Armazenar PRPCI no Alfresco ECM") invoca `ArquivoRN.incluir()`. Esta é uma etapa crítica de infraestrutura: o arquivo PDF nunca é armazenado no banco de dados relacional Oracle — apenas seu **nodeRef** (identificador externo no Alfresco) é persistido.

O Alfresco ECM é o repositório de conteúdo empresarial da arquitetura SOL. Para o PRPCI, o arquivo é armazenado com os seguintes metadados CMIS:

| Metadado Alfresco | Valor |
|---|---|
| `grp:organizacao` | `CBM` |
| `grp:familia` | `Documentos de Edificação` |
| `grp:categoria` | `Licenciamento` |
| `grp:subcategoria` | `Documentos` |
| Enum usado | `TipoArquivo.EDIFICACAO` |

O retorno de `ArquivoRN.incluir()` é uma instância de `ArquivoED` já persistida no Oracle, com o campo `TXT_IDENTIFICADOR_ALFRESCO` preenchido com o nodeRef no formato `workspace://SpacesStore/{UUID}`. Essa entidade é auditada pelo Hibernate Envers: cada versão do `ArquivoED` fica registrada na tabela `CBM_ARQUIVO_AUD`.

**Por que primeiro gravar no Alfresco e só depois criar o `PrpciED`?** Porque o `PrpciED` tem uma FK obrigatória (`NRO_INT_ARQUIVO`) para o `ArquivoED`. A ordem de persistência é imposta pelo modelo de dados: o arquivo precisa existir antes que o PRPCI possa referenciar o arquivo.

### 3.7 Persistência do PrpciED no Banco Relacional

A `ServiceTask` **`ST_CriarPrpciED`** ("Persistir PrpciED com FK para ArquivoED") invoca `PrpciRN.inclui()` (ou `PrpciCidadaoRN.inclui()` — dependendo da camada de delegação), que cria e persiste a entidade `PrpciED` na tabela `CBM_PRPCI`.

Esta etapa estabelece o vínculo entre os três eixos do licenciamento:
- **`CBM_PRPCI.NRO_INT_LICENCIAMENTO`** → aponta para o licenciamento
- **`CBM_PRPCI.NRO_INT_ARQUIVO`** → aponta para o arquivo no Alfresco (via `ArquivoED`)
- **`CBM_PRPCI.NRO_INT_LOCALIZACAO`** → cópia da localização da edificação no momento do upload

A cópia da localização (`LocalizacaoED`) no momento do upload é importante por rastreabilidade histórica: se o endereço da edificação for alterado futuramente, o PRPCI registrado ainda refletirá a localização vigente na época da emissão.

A anotação `@Permissao(objeto="PRPCI", acao="INCLUIR")` na classe `PrpciRN` garante que apenas usuários com a permissão correta podem executar esta operação. O interceptor `SegurancaEnvolvidoInterceptor`, configurado via `@Interceptors`, verifica tanto o papel do usuário quanto o vínculo dele com o licenciamento específico.

### 3.8 Transição de Estado: AGUARDANDO_PRPCI → ALVARA_VIGENTE

A `ServiceTask` **`ST_TrocaEstadoNormal`** é a mais complexa do P08-A. Ela invoca a classe `TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente`, qualificada pelo CDI com `@TrocaEstadoLicenciamentoEnum(AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE)`. Esta é uma classe de "orquestração de estado" que executa uma sequência precisa e atômica de operações de banco de dados:

**Sequência de operações:**

1. **Fecha o período atual:** atualiza `CBM_SIT_LICENCIAMENTO` com `DT_FIM = SYSDATE` onde a situação é `AGUARDANDO_PRPCI` e `DT_FIM IS NULL`. Este mecanismo de "período aberto" é o padrão do SOL para manter o histórico completo de todas as situações pelas quais um licenciamento passou, com data de início e fim de cada uma.

2. **Abre o novo período:** insere uma nova linha em `CBM_SIT_LICENCIAMENTO` com situação `ALVARA_VIGENTE` e `DT_INICIO = SYSDATE`.

3. **Atualiza o campo desnormalizado:** atualiza `CBM_LICENCIAMENTO.SIT_LICENCIAMENTO = 'ALVARA_VIGENTE'`. Este campo existe por performance: evita um JOIN com `CBM_SIT_LICENCIAMENTO` para descobrir a situação atual.

4. **Registra Marco UPLOAD_PRPCI:** insere em `CBM_MARCO_LICENCIAMENTO` o marco `TipoMarco.UPLOAD_PRPCI` com data atual e referência ao `ArquivoED` do PRPCI. Os marcos são o "log de negócio" do licenciamento — permitem reconstruir a linha do tempo completa de eventos relevantes. **Importante:** se por algum motivo o `PrpciED` não tiver arquivo vinculado, o campo `ID_ARQUIVO` do marco fica `NULL` — o sistema tolera essa condição, conforme indicado no código.

5. **Cria o APPCI:** instancia e persiste um `AppciED` com `indVersaoVigente='S'` e `indRenovacao='N'` na tabela `CBM_APPCI`. O `AppciED` é o próprio Alvará digital. A flag `indVersaoVigente='S'` marca este APPCI como o vigente (pode haver histórico de APPCIs anteriores do mesmo licenciamento).

6. **Registra Marco LIBERACAO_APPCI:** insere o marco `TipoMarco.LIBERACAO_APPCI` em `CBM_MARCO_LICENCIAMENTO`. Este marco marca o momento exato em que o APPCI ficou disponível, dado importante para fins de auditoria, controle de prazo de validade e eventual fiscalização.

**Por que tudo isso em uma única `ServiceTask`?** Porque todas essas operações formam uma **unidade atômica de negócio**: ou todas ocorrem, ou nenhuma ocorre (são executadas dentro da mesma transação JTA do WildFly). Separar em múltiplas tasks introduziria risco de inconsistência — o licenciamento poderia ficar em estado intermediário se houvesse falha no meio do processo.

### 3.9 Evento de Fim: APPCI Normal Emitido

O evento de fim **`End_AlvaraVigenteNormal`** representa o encerramento bem-sucedido do P08-A. O licenciamento está em `ALVARA_VIGENTE`, o APPCI foi emitido com `indRenovacao='N'`, e os dois marcos (`UPLOAD_PRPCI` e `LIBERACAO_APPCI`) foram registrados. O RT pode agora baixar o APPCI pelo frontend Angular, e uma notificação por e-mail é disparada informando a disponibilidade do documento.

---

## 4. Sub-processo P08-B — Aceite do PRPCI pelo RU/Proprietário (Renovação)

### 4.1 Evento de Início e Contexto de Entrada

O Pool P08-B começa com o evento de início **`Start_AguardandoAceitePrpci`** ("Licenciamento em AGUARDANDO_ACEITE_PRPCI"). O contexto de ativação é diferente do P08-A: este sub-processo é acionado por licenciamentos de **renovação**, onde a vistoria foi do tipo `VISTORIA_RENOVACAO`.

A classe `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci` (executada no encerramento do P07 para vistorias de renovação) transicionou o licenciamento de `EM_VISTORIA` para `AGUARDANDO_ACEITE_PRPCI`. Ao fazer isso, disparou uma notificação ao RU/Proprietário informando que o PRPCI da renovação está disponível para aceite eletrônico.

**Por que o fluxo de renovação exige aceite eletrônico em vez de upload?** Porque na renovação de APPCI, o CBM-RS já verificou presencialmente que o estabelecimento atende às normas. O PRPCI de renovação é um documento que formaliza a continuidade da conformidade — ele não exige a elaboração de um novo plano técnico pelo RT. O aceite pelo RU/Proprietário tem caráter de declaração formal de ciência e concordância com a renovação.

### 4.2 Tarefa do RU: Acesso ao Painel do Licenciamento

A `UserTask` **`UT_AcessarPainel`** ("RU/Proprietário acessa painel do licenciamento") representa o momento em que o RU autenticado no SOE PROCERGS acessa a tela de detalhe do licenciamento e visualiza a aba "Aceite PRPCI".

O frontend Angular apresenta ao usuário:
- Um botão "Verificar elegibilidade" → chama `GET /prpci/{idLic}/pode-aceite-prpci`
- O status atual do licenciamento
- O PRPCI disponível para download/leitura

Esta tarefa existe no BPMN porque representa uma interação real do usuário: ele precisa navegar ativamente até o licenciamento correto, ler o PRPCI e tomar a decisão de aceitar. Não é uma ação passiva.

### 4.3 Verificação de Elegibilidade para Aceite

A `ServiceTask` **`ST_ConsultarPermissao`** ("Verificar elegibilidade para aceite do PRPCI") invoca `PrpciCidadaoRN.verificaPermissoesUsuario()`. Este é um endpoint de **consulta prévia** — o frontend chama `GET /prpci/{idLic}/pode-aceite-prpci` antes de exibir o botão de aceite, para verificar se o usuário logado tem direito de realizar a operação.

Esta verificação tripla é necessária porque o aceite tem requisitos cumulativos:

**Verificação 1 — Papel do usuário:** o sistema verifica se o CPF do usuário logado (obtido do token SOE) corresponde a algum dos papéis autorizados para aceite:
- RU (`ResponsavelUsoED`) vinculado ao licenciamento
- Procurador do RU com representação ativa
- Proprietário pessoa física (`isProprietarioPF`)
- Procurador do Proprietário com representação ativa

Esta verificação é necessária porque múltiplos usuários podem ter acesso ao licenciamento (RT, analistas do CBM-RS), mas apenas os envolvidos com o papel de responsabilidade pelo imóvel podem conceder aceite.

**Verificação 2 — Situação do licenciamento:** deve ser `AGUARDANDO_ACEITE_PRPCI`. Esta verificação defende contra condições de corrida: outro usuário poderia ter completado o aceite entre o momento em que o RU acessou o painel e o momento em que clicou em "Aceitar".

**Verificação 3 — APPCI gerado:** `PrpciBD.buscarAppcis()` deve retornar ao menos um `AppciED` com `indVersaoVigente='S'` para o licenciamento. Esta verificação garante que a TrocaEstado do P07 criou o APPCI corretamente antes de permitir o aceite.

### 4.4 Gateway de Decisão: Usuário Habilitado para Aceite?

O gateway exclusivo **`GW_PodeAceitar`** bifurca o fluxo em dois caminhos:

- **Sim (`${podeAceitar == true}`):** todas as verificações passaram. O fluxo deve retornar para a raia do RU (cross-lane) para que ele realize o aceite propriamente dito.

- **Não (`${podeAceitar == false}`):** alguma verificação falhou. O fluxo encerra imediatamente em `End_SemPermissao` com HTTP 403 Forbidden.

**Por que verificar permissão antes de exibir o formulário de aceite (em vez de verificar somente no momento do POST)?** Esta é uma prática de UX defensivo: não expor ao usuário uma ação que ele não pode completar. Se o RU não tem permissão, o frontend Angular nem deve exibir o botão "Aceitar PRPCI", evitando frustração e chamadas desnecessárias ao servidor.

### 4.5 Evento de Fim de Erro: Sem Permissão

O evento de fim de erro **`End_SemPermissao`** ("Aceite negado — usuário sem permissão") usa um `bpmn:errorEventDefinition` para sinalizar que o processo encerrou por uma condição de exceção (não por fluxo normal). O código de erro `SEM_PERMISSAO_ACEITE_PRPCI` permite rastrear este encerramento em logs e relatórios.

O licenciamento permanece em `AGUARDANDO_ACEITE_PRPCI` — nenhuma alteração de estado ocorre. O RU pode, por exemplo, contatar o CBM-RS para verificar por que não possui permissão, ou verificar se está usando o CPF correto no login SOE.

### 4.6 Retorno Cross-Lane e Tarefa de Aceite pelo RU

Quando `GW_PodeAceitar` decide pelo caminho "Sim", o fluxo **`Flow_GW_Pode_Sim`** retorna da raia Backend para a raia do RU. Este é um fluxo **cross-lane de baixo para cima**, que exigiu waypoints explícitos para evitar sobreposição visual:

```
(580, 965) → (715, 965) → (715, 735)
```

O fluxo segue horizontalmente para a direita até x=715 (passando pelo eixo vertical do UserTask de aceite), depois sobe cruzando o limite de raia em y≈770 e conecta ao UserTask `UT_ConcederAceite` na raia do RU.

**Por que o RU precisa de uma segunda UserTask (`UT_ConcederAceite`) após a verificação?** Porque a verificação de elegibilidade (`ST_ConsultarPermissao`) é uma operação de consulta — ela não realiza o aceite. O aceite em si é uma ação ativa e intencional do RU: ele lê o texto do PRPCI, compreende as implicações e clica em "Confirmar Aceite". Este momento de decisão consciente do usuário deve ser modelado como uma UserTask separada. Além disso, um fluxo de UX bem desenhado pode exibir um modal de confirmação com o texto do termo, exigindo que o usuário confirme explicitamente.

### 4.7 Validação dos Dados do Aceite

Após o RU confirmar o aceite no frontend, a `ServiceTask` **`ST_ValidarAceite`** ("Validar dados do aceite") invoca `PrpciRNVal.validaAceitePrpci()`. Mesmo que o sistema já tenha verificado elegibilidade em `ST_ConsultarPermissao`, esta segunda validação é necessária por **segurança de camada**: a validação de elegibilidade pode ter sido feita segundos ou minutos antes, e as condições podem ter mudado.

As validações específicas do aceite incluem:

- **RN05:** situação ainda é `AGUARDANDO_ACEITE_PRPCI` (não mudou desde a consulta prévia)
- **RN06:** a `VistoriaED` informada existe e pertence ao licenciamento
- **RN07:** `VistoriaED.aceitePrpci == null` — o aceite ainda não foi concedido (campo `IND_ACEITE_PRPCI` em `CBM_VISTORIA` está `NULL` ou `'N'`). A validação usa o `SimNaoBooleanConverter`, que mapeia `null`/`'N'` → `false` e `'S'` → `true`.
- **RN08:** o usuário continua sendo elegível (mesma verificação do GW_PodeAceitar)

A RN07 é especialmente importante: sem ela, um usuário poderia chamar o endpoint de aceite duas vezes (por duplo clique ou erro de rede), resultando em dois registros de aceite inconsistentes.

### 4.8 Gateway de Decisão: Aceite Válido?

O gateway exclusivo **`GW_AceiteValido`** bifurca entre:

- **Sim (`${aceiteValido == true}`):** o aceite pode ser registrado. Fluxo segue para `ST_RegistrarAceiteVistoria`.
- **Não (`${aceiteValido == false}`):** dados inválidos → `End_ErroAceite` com HTTP 422 Unprocessable Entity.

O evento `End_ErroAceite` usa `bpmn:errorEventDefinition` com código `ERRO_VALIDACAO_ACEITE_PRPCI`, analogamente ao `End_SemPermissao`, para distinguir este tipo de encerramento em logs e monitoramento.

### 4.9 Registro do Aceite na VistoriaED

A `ServiceTask` **`ST_RegistrarAceiteVistoria`** ("Registrar aceite na VistoriaED") é o ponto de convergência do aceite eletrônico. O método `PrpciCidadaoRN.aceitePrpci()` (anotado com `@Permissao(objeto="PRPCI", acao="INCLUIR")`) executa três atualizações na entidade `VistoriaED`:

```
vistoria.setAceitePrpci(true)
    → CBM_VISTORIA.IND_ACEITE_PRPCI = 'S'   (SimNaoBooleanConverter)

vistoria.setNroIntUsuarioAceitePrpci(usuario.getNroInterno())
    → CBM_VISTORIA.NRO_INT_USUARIO_ACEITE_PRPCI = {nro_interno_SOE}

vistoria.setDtAceitePrpci(Calendar.getInstance())
    → CBM_VISTORIA.DT_ACEITE_PRPCI = SYSDATE
```

**Por que o aceite é gravado na `VistoriaED` e não em uma entidade separada?** Porque o aceite é um atributo da vistoria de renovação: ele formaliza que o interessado reconhece o resultado da vistoria e concorda com a renovação do APPCI. A `VistoriaED` é a entidade que representa o evento da vistoria; faz sentido semântico que o aceite seja um atributo dessa mesma entidade.

O campo `NRO_INT_USUARIO_ACEITE_PRPCI` registra o número interno do usuário SOE que concedeu o aceite. Este dado é essencial para auditoria: em caso de disputa jurídica sobre a validade do aceite, o sistema pode identificar exatamente quem e quando aceitou o PRPCI.

### 4.10 Transição de Estado: AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE

A `ServiceTask` **`ST_TrocaEstadoRenovacao`** invoca `TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN`, qualificada por `@TrocaEstadoLicenciamentoEnum(AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE)`. As operações são análogas às do P08-A, com duas diferenças fundamentais:

1. **Marco diferente:** em vez de `UPLOAD_PRPCI`, registra `TipoMarco.ACEITE_PRPCI` (linha 114 de `TipoMarco.java`). O marco não referencia arquivo, pois não há upload neste fluxo.

2. **APPCI de renovação:** o `AppciED` criado tem `indRenovacao='S'` (diferente do P08-A onde é `'N'`). Este flag distingue APPCIs de primeira emissão de APPCIs de renovação, o que é relevante para relatórios gerenciais e para o controle de prazo de validade diferenciado.

3. **Marco de liberação diferente:** registra `TipoMarco.LIBERACAO_RENOV_APPCI` (linha 115 de `TipoMarco.java`) em vez de `LIBERACAO_APPCI`.

A sequência completa de operações atômicas dentro desta TrocaEstado:
1. Fecha período `AGUARDANDO_ACEITE_PRPCI`
2. Abre período `ALVARA_VIGENTE`
3. Atualiza campo desnormalizado `SIT_LICENCIAMENTO`
4. Registra Marco `ACEITE_PRPCI`
5. Cria `AppciED` com `indRenovacao='S'`
6. Registra Marco `LIBERACAO_RENOV_APPCI`

### 4.11 Evento de Fim: APPCI de Renovação Emitido

O evento de fim **`End_AlvaraVigenteRenovacao`** encerra o P08-B. O licenciamento está em `ALVARA_VIGENTE`, o APPCI de renovação foi emitido, os três registros-chave foram realizados (`CBM_VISTORIA.IND_ACEITE_PRPCI='S'`, marcos `ACEITE_PRPCI` e `LIBERACAO_RENOV_APPCI`). Uma notificação por e-mail informa ao RU/Proprietário que o APPCI de renovação está disponível para download.

---

## 5. Máquinas de Estado, Marcos de Auditoria e TrocaEstado CDI

O P08 envolve quatro classes `TrocaEstado` CDI distintas, sendo duas de entrada (disparadas pelo P07) e duas internas ao P08:

### TrocaEstados de Entrada (disparadas pelo P07, iniciam o P08)

| Classe | Qualificador CDI | Transição | Pool Ativado |
|---|---|---|---|
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci` | `EM_VISTORIA_PARA_AGUARDANDO_PRPCI` | `EM_VISTORIA → AGUARDANDO_PRPCI` | P08-A |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci` | `EM_VISTORIA_PARA_AGUARDANDO_ACEITE_PRPCI` | `EM_VISTORIA → AGUARDANDO_ACEITE_PRPCI` | P08-B |

### TrocaEstados Internas ao P08

| Classe | Qualificador CDI | Transição | ServiceTask |
|---|---|---|---|
| `TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente` | `AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE` | `AGUARDANDO_PRPCI → ALVARA_VIGENTE` | `ST_TrocaEstadoNormal` |
| `TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN` | `AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE` | `AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE` | `ST_TrocaEstadoRenovacao` |

### Marcos registrados no P08

| Marco | `TipoMarco` | Linha em `TipoMarco.java` | Arquivo? | Sub-processo |
|---|---|---|---|---|
| Upload do PRPCI | `UPLOAD_PRPCI` | 62 | Sim (ArquivoED — nodeRef Alfresco) | P08-A |
| Liberação do APPCI normal | `LIBERACAO_APPCI` | 52 | Não | P08-A |
| Aceite eletrônico do PRPCI | `ACEITE_PRPCI` | 114 | Não | P08-B |
| Liberação do APPCI de renovação | `LIBERACAO_RENOV_APPCI` | 115 | Não | P08-B |

### Diagrama de Máquina de Estados

```
P07 (Vistoria Normal aprovada)
       │
       ▼
EM_VISTORIA ──[TrocaEstado A]──► AGUARDANDO_PRPCI
                                        │
                          RT faz upload do PRPCI
                                        │
                             [TrocaEstado Normal]
                                        │
                                        ▼
                                 ALVARA_VIGENTE   ◄── P08-A
                                        ▲
                             [TrocaEstado Renovação]
                                        │
                          RU concede aceite eletrônico
                                        │
EM_VISTORIA ──[TrocaEstado B]──► AGUARDANDO_ACEITE_PRPCI
       │
       (Vistoria Renovação aprovada)
```

---

## 6. Segurança e Controle de Acesso

A segurança do P08 é implementada em duas camadas independentes e complementares:

### Camada 1 — Interceptor de Envolvido (nível REST)

A anotação `@AutorizaEnvolvido` nos endpoints REST (`PrpciRestImpl`) ativa o `SegurancaEnvolvidoInterceptor` para verificar que o usuário autenticado (identificado pelo CPF extraído do token JWT SOE) é um **envolvido no licenciamento** — ou seja, está relacionado ao processo como RT, RU, Proprietário ou Procurador. Esta verificação impede que um usuário autenticado qualquer no SOE acesse dados de licenciamentos que não lhe dizem respeito.

### Camada 2 — Permissão Funcional (nível EJB)

A anotação `@Permissao(objeto="PRPCI", acao="INCLUIR")` nos métodos `inclui()` e `aceitePrpci()` de `PrpciCidadaoRN` verifica se o perfil do usuário possui a permissão funcional específica para operar com PRPCI. Essa permissão é configurada nas tabelas de controle de acesso do SOL e pode ser gerenciada pelo administrador do sistema.

### Papéis autorizados por operação

| Operação | Endpoint | Papéis Autorizados |
|---|---|---|
| Upload PRPCI (P08-A) | `PUT /prpci/{idLic}` | RT envolvido no licenciamento |
| Consulta de elegibilidade (P08-B) | `GET /prpci/{idLic}/pode-aceite-prpci` | RU, Procurador RU, Proprietário PF, Procurador Proprietário |
| Aceite PRPCI (P08-B) | `PUT /prpci/{idLic}/termo/{idVistoria}/aceite-prpci` | RU, Procurador RU, Proprietário PF, Procurador Proprietário |

---

## 7. Integração com o Alfresco ECM

O Alfresco ECM (Enterprise Content Management) é o repositório central de arquivos do sistema SOL. A integração no P08-A segue um padrão bem estabelecido no projeto:

**Princípio fundamental:** o conteúdo binário (bytes do PDF) **nunca é armazenado no banco relacional Oracle**. O Oracle armazena apenas metadados e o identificador externo do arquivo. Isso garante que o banco relacional não cresça de forma descontrolada com conteúdo binário, e que o gerenciamento de versões e retenção de documentos fique a cargo do Alfresco, que é especializado nisso.

**Fluxo de gravação:**

```
1. PrpciRestImpl.inclui() recebe FormDataBodyPart (arquivo + metadados)
      │
2. ArquivoRN.incluir() cria ArquivoED com identificadorAlfresco = "0" (placeholder)
   → INSERT em CBM_ARQUIVO
      │
3. ArquivoRN chama cliente CMIS (Apache Chemistry OpenCMIS)
   → POST para Alfresco AtomPub endpoint
   → Alfresco cria nó na pasta CBM/Documentos de Edificação/Licenciamento/Documentos
   → Retorna nodeRef: "workspace://SpacesStore/{UUID}"
      │
4. ArquivoRN atualiza identificadorAlfresco com o nodeRef retornado
   → UPDATE CBM_ARQUIVO SET TXT_IDENTIFICADOR_ALFRESCO = 'workspace://SpacesStore/{UUID}'
      │
5. ArquivoED retornado (com ID e nodeRef) para PrpciCidadaoRN.inclui()
```

**Fluxo de leitura (quando RT/RU baixa o PRPCI):**

```
1. Frontend Angular chama GET /arquivo/{idArquivo}
2. Backend consulta CBM_ARQUIVO.TXT_IDENTIFICADOR_ALFRESCO pelo ID
3. ArquivoRN chama Alfresco CMIS com o nodeRef → obtém InputStream
4. Backend retorna arquivo como octet-stream para o browser
```

---

## 8. Diferenças e Semelhanças entre P08-A e P08-B

| Aspecto | P08-A (Upload PRPCI) | P08-B (Aceite PRPCI) |
|---|---|---|
| **Situação de entrada** | `AGUARDANDO_PRPCI` | `AGUARDANDO_ACEITE_PRPCI` |
| **Ator principal** | RT (Responsável Técnico) | RU/Proprietário |
| **Tipo de vistoria que origina** | DEFINITIVA ou PARCIAL | RENOVACAO |
| **Ação central** | Upload de arquivo PDF | Aceite eletrônico (sem arquivo) |
| **Endpoint principal** | `PUT /prpci/{idLic}` (multipart) | `PUT /prpci/{idLic}/termo/{idVistoria}/aceite-prpci` |
| **Classe de validação** | `PrpciRNVal.validaIncluiPrpci()` | `PrpciRNVal.validaAceitePrpci()` |
| **Alfresco ECM** | Sim — ArquivoED criado | Não — sem upload |
| **PrpciED criado** | Sim | Não |
| **VistoriaED modificada** | Não | Sim (3 campos de aceite) |
| **APPCI criado** | `indRenovacao='N'` | `indRenovacao='S'` |
| **Marcos registrados** | `UPLOAD_PRPCI` + `LIBERACAO_APPCI` | `ACEITE_PRPCI` + `LIBERACAO_RENOV_APPCI` |
| **Loop-back de erro** | Sim (arquivo inválido → reenvio) | Não |
| **Verificação cross-lane** | Não (fluxo direto) | Sim (Backend→RU após autorização) |
| **Situação de saída** | `ALVARA_VIGENTE` | `ALVARA_VIGENTE` |
| **Número de UserTasks** | 1 | 2 |
| **Número de ServiceTasks** | 3 | 4 |
| **Gateways** | 1 | 2 |
| **Eventos de fim** | 1 (normal) | 3 (1 normal + 2 erro) |

A semelhança mais importante entre os dois sub-processos é o **estado final**: ambos encerram em `ALVARA_VIGENTE` com um APPCI gerado. Isso reflete o princípio de que, independentemente do caminho percorrido (emissão normal ou renovação), o produto entregue ao cidadão é o mesmo — um Alvará de Prevenção e Proteção Contra Incêndio válido.

---

## 9. Rastreabilidade: Elementos do BPMN × Código-Fonte

| Elemento BPMN | Tipo | Classe/Método Java | Tabela(s) BD |
|---|---|---|---|
| `Start_AguardandoPrpci` | StartEvent | `TrocaEstado...EmVistoriaParaAguardandoPrpci` | `CBM_SIT_LICENCIAMENTO`, `CBM_LICENCIAMENTO` |
| `UT_UploadPrpci` | UserTask | `PrpciRestImpl.inclui()` (endpoint) | — |
| `ST_ValidarUpload` | ServiceTask | `PrpciRNVal.validaIncluiPrpci()` | `CBM_LICENCIAMENTO`, `CBM_VISTORIA` |
| `GW_UploadValido` | ExclusiveGateway | `SolNegocioException` (ausência/presença) | — |
| `Flow_GW_Nao_Reupload` | SequenceFlow (loop) | Retorno HTTP 422 ao Angular | — |
| `ST_IncluirArquivoAlfresco` | ServiceTask | `ArquivoRN.incluir()` | `CBM_ARQUIVO`, `CBM_ARQUIVO_AUD` |
| `ST_CriarPrpciED` | ServiceTask | `PrpciRN.inclui()` / `PrpciCidadaoRN.inclui()` | `CBM_PRPCI` |
| `ST_TrocaEstadoNormal` | ServiceTask | `TrocaEstado...AguardandoPrpciParaAlvaraVigente` | `CBM_SIT_LICENCIAMENTO`, `CBM_LICENCIAMENTO`, `CBM_MARCO_LICENCIAMENTO`, `CBM_APPCI` |
| `End_AlvaraVigenteNormal` | EndEvent | — | — |
| `Start_AguardandoAceitePrpci` | StartEvent | `TrocaEstado...EmVistoriaParaAguardandoAceitePrpci` | `CBM_SIT_LICENCIAMENTO`, `CBM_LICENCIAMENTO` |
| `UT_AcessarPainel` | UserTask | `GET /prpci/{idLic}/pode-aceite-prpci` (Angular) | — |
| `ST_ConsultarPermissao` | ServiceTask | `PrpciCidadaoRN.verificaPermissoesUsuario()` | `CBM_LICENCIAMENTO`, `CBM_APPCI` |
| `GW_PodeAceitar` | ExclusiveGateway | `PrpciPodeAceiteDTO.podeAceitar` | — |
| `End_SemPermissao` | EndEvent (Error) | `SolNegocioException` → HTTP 403 | — |
| `UT_ConcederAceite` | UserTask | `PUT /prpci/{idLic}/termo/{idVistoria}/aceite-prpci` (Angular) | — |
| `ST_ValidarAceite` | ServiceTask | `PrpciRNVal.validaAceitePrpci()` | `CBM_LICENCIAMENTO`, `CBM_VISTORIA` |
| `GW_AceiteValido` | ExclusiveGateway | `SolNegocioException` (ausência/presença) | — |
| `End_ErroAceite` | EndEvent (Error) | `SolNegocioException` → HTTP 422 | — |
| `ST_RegistrarAceiteVistoria` | ServiceTask | `PrpciCidadaoRN.aceitePrpci()` | `CBM_VISTORIA` (3 campos) |
| `ST_TrocaEstadoRenovacao` | ServiceTask | `TrocaEstado...AguardandoAceitePrpciParaAlvaraVigenteRN` | `CBM_SIT_LICENCIAMENTO`, `CBM_LICENCIAMENTO`, `CBM_MARCO_LICENCIAMENTO`, `CBM_APPCI` |
| `End_AlvaraVigenteRenovacao` | EndEvent | — | — |
