# Descritivo do Fluxo BPMN — P05: Ciência do CIA/CIV e Recurso Administrativo
## Stack Atual (Java EE — sem alterações tecnológicas)

**Arquivo BPMN:** `P05_CienciaRecurso_StackAtual.bpmn`
**Ferramenta alvo:** Camunda Modeler 5.0.0
**Data:** 2026-03-09
**Projeto:** Sistema SOL — Corpo de Bombeiros Militar do Rio Grande do Sul (CBM-RS)

---

## Sumário

1. [Visão Geral e Escopo do Processo](#1-visão-geral-e-escopo-do-processo)
2. [Estrutura Geral do BPMN](#2-estrutura-geral-do-bpmn)
3. [Fase 1 — Ciência do CIA/CIV/APPCI](#3-fase-1--ciência-do-ciacivappci)
4. [Fase 2 — Registro do Recurso Administrativo](#4-fase-2--registro-do-recurso-administrativo)
5. [Fase 3 — Aceites dos Envolvidos](#5-fase-3--aceites-dos-envolvidos)
6. [Fase 4 — Distribuição para Analista](#6-fase-4--distribuição-para-analista)
7. [Fase 5 — Análise do Recurso (1ª e 2ª Instância)](#7-fase-5--análise-do-recurso-1ª-e-2ª-instância)
8. [Fase 6 — Geração do Relatório e Atualização de Estado](#8-fase-6--geração-do-relatório-e-atualização-de-estado)
9. [Fase 7 — Ciência da Resposta do Recurso](#9-fase-7--ciência-da-resposta-do-recurso)
10. [Fase 8 — Resultado Final e Opção de Segunda Instância](#10-fase-8--resultado-final-e-opção-de-segunda-instância)
11. [Decisões de Modelagem Transversais](#11-decisões-de-modelagem-transversais)
12. [Tabelas de Referência](#12-tabelas-de-referência)

---

## 1. Visão Geral e Escopo do Processo

O processo P05 encapsula duas sub-jornadas que ocorrem sequencialmente e são interdependentes no ciclo de vida de um licenciamento PPCI do CBM-RS.

### Sub-jornada A — Ciência do CIA/CIV

Após a emissão de um Comunicado de Inconformidade na Análise (CIA) ou Comunicado de Inconformidade na Vistoria (CIV) — ou de um Alvará de Prevenção e Proteção Contra Incêndio (APPCI) aprovado —, o cidadão deve registrar formalmente sua ciência. Essa ciência pode ser:

- **Manual:** o cidadão acessa o portal SOL e confirma via endpoint REST.
- **Automática:** um job EJB Timer (`@Schedule`) é acionado após 30 dias sem ciência manual e registra a ciência em nome do sistema (`SOLCBM`).

A ciência cobre cinco tipos de documentos (`TipoLicenciamentoCiencia`): `ATEC`, `INVIABILIDADE`, `CIV`, `APPCI` e `APPCI_RENOV`. Cada tipo é atendido por uma implementação concreta de EJB `@Stateless`, resolvida em tempo de execução pelo CDI via `@LicenciamentoCienciaQualifier`.

### Sub-jornada B — Recurso Administrativo

Após ciência de CIA ou CIV **reprovado**, o cidadão pode interpor recurso administrativo. O recurso possui duas instâncias:

- **1ª instância:** prazo de 30 dias após a ciência; análise individual pelo analista designado.
- **2ª instância:** prazo de 15 dias após a ciência da resposta da 1ª instância, cabível apenas quando a 1ª instância foi indeferida ou deferida parcialmente; análise por colegiado de até dois avalistaes.

O processo interno envolve distribuição pelo coordenador CBM-RS, análise individual ou colegiada, emissão de despacho, geração de PDF autenticado via JasperReports armazenado no Alfresco, e nova rodada de ciência da resposta pelo cidadão.

### Pré-condição e entrada no processo

O P05 tem início imediatamente após o processo P04 (Análise Técnica ATEC ou de Inviabilidade) ou após o processo de Vistoria, quando o documento resultante (CIA ou CIV ou APPCI) é emitido pelo CBM-RS. A situação do licenciamento em `AGUARDANDO_CIENCIA` (ou equivalente) é o gatilho para este processo.

---

## 2. Estrutura Geral do BPMN

### Pool e processo

O BPMN utiliza **um único pool** nomeado "P05 — Ciência CIA/CIV e Recurso Administrativo", referenciando o processo `Process_P05` com `isExecutable=false` (documentação de arquitetura, não para execução direta no Camunda Engine).

**Justificativa do pool único:** o P05 representa um único processo de negócio contínuo que envolve múltiplos participantes internos ao CBM-RS e o cidadão. A separação em pools distintos só se justificaria se houvesse troca de mensagens entre processos independentes. Aqui, todos os atores compartilham o mesmo contexto do licenciamento — o pool único com raias é a representação correta.

### Raias (Lanes)

O processo é dividido em quatro raias, cada uma representando um participante técnico-funcional:

| Raia | ID | Participante | Papel |
|---|---|---|---|
| Cidadão | `Lane_Cidadao` | RT / RU / Proprietário | Confirma ciência, preenche recurso, confirma aceite, toma ciência da resposta |
| Coordenador CBM-RS | `Lane_Coordenador` | Coordenador | Consulta a fila de recursos, seleciona analista, confirma ou cancela distribuição |
| Analista CBM-RS | `Lane_Analista` | Analista designado | Analisa o recurso individualmente ou coordena o colegiado da 2ª instância |
| Sistema SOL | `Lane_Sistema` | Backend Java EE | Executa todas as transições de estado, persistências, geração de PDF, marcos e jobs automáticos |

**Justificativa das quatro raias:** cada raia corresponde a um perfil de usuário com permissões distintas no framework `arqjava4` (anotações `@Permissao`) e papéis distintos no fluxo. Separar visualmente o Coordenador do Analista é fundamental porque as responsabilidades são diferentes: o Coordenador distribui os recursos, o Analista os avalia. O Sistema aparece em raia própria para tornar explícitas as ServiceTasks automáticas (persistências, marcos, geração de relatórios, jobs), que não envolvem interação humana.

### Tipos de elementos utilizados

| Tipo BPMN | Uso no P05 |
|---|---|
| StartEvent | 1 evento inicial |
| UserTask | 12 tarefas com interação humana |
| ServiceTask | 14 tarefas automáticas do sistema |
| ExclusiveGateway | 13 gateways (splits de decisão + joins) |
| BoundaryEvent (Timer) | 2 eventos de timer (30 dias ciência CIA/CIV e 30 dias ciência da resposta) |
| EndEvent | 9 eventos de fim (cada saída de estado do processo) |

### Convenção de nomenclatura

- UserTasks: prefixo `T` + número sequencial + nome descritivo da ação do ator
- ServiceTasks: mesmo prefixo + nome da classe/método do EJB
- Gateways: prefixo `GW` + número + nome da decisão
- Timers: prefixo `Tmr_` + descrição
- EndEvents: prefixo `End_` + estado resultante

### Documentação inline dos elementos

Cada elemento BPMN contém um bloco `<documentation><![CDATA[...]]></documentation>` com:
- Classe EJB e método Java executado
- Endpoint REST correspondente
- Tabelas JPA afetadas
- Regras de negócio aplicáveis
- Constantes relevantes

Essa documentação inline é essencial para que o BPMN funcione como referência técnica viva, sem necessidade de consultar simultaneamente o código-fonte.

---

## 3. Fase 1 — Ciência do CIA/CIV/APPCI

Esta fase cobre os elementos de `Start_P05` até `GW04_OptaRecurso` (exclusive o caminho do recurso).

### Start_P05 — Evento de início

**Elemento:** StartEvent (sem definição de evento, início simples)
**Raia:** Cidadão

Representa o momento em que o licenciamento possui um CIA, CIV ou APPCI emitido e a ciência do cidadão ainda não foi registrada. A situação do licenciamento neste ponto é `AGUARDANDO_CIENCIA` (para análise/inviabilidade) ou equivalente para CIV/APPCI.

**Decisão de modelagem:** utiliza-se StartEvent simples (não baseado em mensagem ou timer) porque o P05 é iniciado por condição de estado já presente no banco de dados, não por evento externo assíncrono. O disparo é conceptual — qualquer licenciamento com `ciencia=null` e CIA/CIV emitido está, por definição, neste estado inicial.

---

### T01 — Acessar CIA/CIV/APPCI pendente de ciência

**Elemento:** UserTask
**Raia:** Cidadão
**`camunda:formKey`:** `licenciamento-ciencia-documento`
**`camunda:assignee`:** `${cidadaoRT_RU_Proprietario}`

O cidadão acessa o portal SOL e visualiza o documento pendente de ciência. O sistema exibe as informações do CIA, CIV ou APPCI: número do PPCI, endereço do imóvel, tipo do documento, PDF armazenado no Alfresco (download via `GET /recurso-arquivos/download/{idArquivo}` → `ArquivoRN.toInputStream(arquivoED)`), data de emissão e prazo para ciência automática.

A implementação concreta do EJB responsável é resolvida pelo CDI com base no `TipoLicenciamentoCiencia`:

| Tipo | Implementação de ciência manual |
|---|---|
| `ATEC` | `AnaliseLicenciamentoTecnicaCienciaCidadaoRN` |
| `INVIABILIDADE` | `AnaliseLicInviabilidadeCienciaCidadaoRN` |
| `CIV` | `CivCienciaCidadaoRN` |
| `APPCI` | `AppciCienciaCidadaoRN` |
| `APPCI_RENOV` | `AppciCienciaCidadaoRenovacaoRN` |

**Decisão de modelagem:** a tarefa de visualização do documento foi modelada separadamente da tarefa de confirmação de ciência (T02) para representar fielmente que há uma fase de leitura/download antes da confirmação formal. No BPMN, cada UserTask representa uma intenção de ação distinta do cidadão.

---

### T02 — Confirmar ciência do CIA/CIV/APPCI

**Elemento:** UserTask com BoundaryEvent Timer (30 dias)
**Raia:** Cidadão
**`camunda:formKey`:** `licenciamento-ciencia-confirmar`

O cidadão confirma a ciência clicando no botão "Confirmar ciência" no portal. O endpoint REST chama `LicenciamentoCienciaCidadaoBaseRN.efetuarCiencia(LicenciamentoCiencia)`, que executa:

1. `usuarioED = usuarioRN.getUsuarioLogado()` — obtém o usuário local SOL vinculado ao CPF do SOE.
2. `aplicarCienciaBase(lc)` — seta `ciencia=true` e `dthCiencia=dataAtualHelper.getDataAtual()`.
3. `lc.setUsuarioCiencia(usuarioED)` — registra o responsável humano pela confirmação.
4. `alteraLicenciamentoCiencia(lc)` — persiste via BD específico de cada tipo.
5. `atualizarLicenciamento(lc)` — transita a situação do licenciamento conforme resultado.
6. `licenciamentoMarcoCidadaoRN.incluiComArquivo(getTipoMarco(), licenciamento, arquivo)` — insere marco de ciência com `tipoResponsavel=CIDADAO` na tabela `LICEN_MARCO`.

O marco registrado depende do tipo e resultado do documento:

| Tipo | Resultado | Marco |
|---|---|---|
| ATEC | aprovado | `CIENCIA_CA_ATEC` |
| ATEC | reprovado | `CIENCIA_CIA_ATEC` |
| INVIABILIDADE | aprovado | `CIENCIA_CA_INVIABILIDADE` |
| INVIABILIDADE | reprovado | `CIENCIA_CIA_INVIABILIDADE` |
| CIV | definitiva | `CIENCIA_CIV` |
| CIV | renovação | `CIENCIA_CIV_RENOVACAO` |
| APPCI | — | `CIENCIA_APPCI` |
| APPCI_RENOV | — | `CIENCIA_APPCI_RENOVACAO` |

**Decisão de modelagem:** a tarefa T02 é a principal porta de saída do cidadão — ela pode ser completada pelo próprio cidadão (caminho normal) ou interrompida pelo timer (caminho alternativo). O `cancelActivity=true` no BoundaryEvent garante que, ao disparar o timer, a tarefa T02 é cancelada e o fluxo segue para T03B. Esse padrão "UserTask com BoundaryEvent Timer interrompível" é o idioma BPMN correto para representar prazos com ação substituta automática.

---

### Tmr_30DiasCiencia — Timer de ciência automática (30 dias)

**Elemento:** BoundaryEvent Timer, `cancelActivity=true`
**Raia:** Cidadão (anexado a T02)
**`timeDuration`:** `P30D`

Representa o disparo do job de ciência automática após 30 dias sem ciência manual.

**Implementação real no código-fonte:** o timer BPMN é uma representação abstrata. A implementação concreta é o método `efetuaCienciaAutomatica()` da classe `LicenciamentoCienciaBatchRN`, anotado com `@Schedule(hour="12/12", persistent=false)`. O job executa às 12:00 e às 24:00 (hora do servidor WildFly). A constante `DIAS_PERIODO_VERIFICACAO = -30` define a janela de verificação: são buscados todos os licenciamentos com `ciencia=null` e `dthStatus <= dataAtual - 30 dias`.

A proteção `BatchUtil.isServerEnabled(logger)` impede a execução em ambientes não habilitados (QA, desenvolvimento), evitando que ciências automáticas sejam registradas inadvertidamente fora de produção. Em caso de exceção, um e-mail é enviado para o endereço configurado em `PropriedadesEnum.EMAIL_DESTINATARIO_ERRO_JOB` e o servidor não é derrubado.

**Decisão de modelagem:** a escolha entre BoundaryEvent Timer e EventBasedGateway foi deliberada. O BPMN 2.0 exige que as saídas de um EventBasedGateway apontem para IntermediateCatchEvents ou ReceiveTasks — não para UserTasks. Como o fluxo após o timer é uma ServiceTask do sistema (T03B), o BoundaryEvent Timer com `cancelActivity=true` é a construção correta e mais expressiva.

---

### T03A — Registrar ciência manual

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.licenciamentociencia.LicenciamentoCienciaCidadaoBaseRN`

Representa o processamento backend desencadeado pela confirmação do cidadão em T02. As operações já foram descritas em T02 — esta ServiceTask torna explícito no diagrama o passo de persistência, que ocorre dentro da mesma transação EJB da confirmação.

**Tabelas afetadas:** `ANAL_LIC_TECNICA`, `ANAL_LIC_INVIABILIDADE`, `CBM_VISTORIA` ou `CBM_APPCI` (UPDATE dos campos `ciencia`, `dthCiencia`, `usuarioCiencia`); `LICEN_MARCO` (INSERT do marco de ciência); tabelas `*_AUD` via Hibernate Envers.

---

### T03B — Registrar ciência automática

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.licenciamentociencia.LicenciamentoCienciaBatchRN`

Representa o processamento do job batch. A diferença fundamental em relação à ciência manual é que **não há `usuarioCiencia`** preenchido (o campo `usuarioCiencia` na entidade fica nulo), pois é uma ação do sistema. O marco registrado em `LICEN_MARCO` tem `tipoResponsavel=SISTEMA` e `usuarioSoeNome="SOLCBM"`. Os marcos automáticos têm sufixo `_AUTO_` para distinção auditória:

| Tipo | Marco automático |
|---|---|
| ATEC aprovado | `CIENCIA_AUTO_CA_ATEC` |
| ATEC reprovado | `CIENCIA_AUTO_CIA_ATEC` |
| INVIABILIDADE aprovado | `CIENCIA_AUTO_CA_INVIABILIDADE` |
| INVIABILIDADE reprovado | `CIENCIA_AUTO_CIA_INVIABILIDADE` |
| CIV | `CIENCIA_AUTO_CIV` |

**Observação:** `APPCI` e `APPCI_RENOV` não possuem ciência automática via batch — por definição, o APPCI é sempre aprovado e pressupõe ação mais imediata do cidadão.

---

### GW01 — Join da ciência (manual ou automática)

**Elemento:** ExclusiveGateway (usado como join/merge)
**Raia:** Sistema

Converge os fluxos de T03A (ciência manual) e T03B (ciência automática). Em BPMN 2.0, quando um ExclusiveGateway tem múltiplas entradas e uma única saída, funciona como merge (OR-join implícito): qualquer um dos caminhos de entrada que chegue aqui avança o fluxo.

**Decisão de modelagem:** o ExclusiveGateway foi preferido ao Parallel Join porque exatamente **um** dos caminhos é tomado: ou o cidadão confirmou manualmente (e o timer não disparou), ou o timer disparou (e a tarefa T02 foi cancelada). Nunca ambos simultaneamente.

---

### T04 — Atualizar situação do licenciamento

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.licenciamentociencia.LicenciamentoCienciaBaseRN`

Executa `LicenciamentoCienciaBaseRN.atualizarLicenciamento(LicenciamentoCiencia lc)`, que atualiza a situação do licenciamento conforme o resultado do documento:

| Tipo de ciência | Resultado | Nova situação do licenciamento |
|---|---|---|
| ATEC | reprovado | `NCA` |
| INVIABILIDADE | reprovado | `NCA` |
| CIV | reprovado | `CIV` |
| ATEC / INVIABILIDADE | aprovado | situação anterior (CA já gerado no P04) |
| CIV | aprovado | `ALVARA_VIGENTE` |
| APPCI / APPCI_RENOV | — | `ALVARA_VIGENTE` |

Há ainda uma salvaguarda para licenciamentos extintos: se `situacao == EXTINGUIDO`, o método mantém `EXTINGUIDO` independentemente do resultado do documento, pois o licenciamento já foi encerrado por outro motivo.

**Decisão de modelagem:** T04 foi modelado como ServiceTask separada (e não fundida em T03A/T03B) para explicitar que a atualização da situação do licenciamento é uma operação distinta — em código, é o método `atualizarLicenciamento()` da classe base abstrata, chamado após `alteraLicenciamentoCiencia()` e antes do registro do marco. Tornar isso explícito no BPMN facilita rastrear onde as transições de estado do licenciamento ocorrem.

---

### GW02 — Documento aprovado?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Verifica `isLicenciamentoCienciaAprovado(lc)`:
- **Caminho "aprovado":** segue para GW03 (determinar tipo de aprovação).
- **Caminho "reprovado":** segue para GW04 (cidadão decide se interpõe recurso).

Para APPCI e APPCI_RENOV, o método retorna `true` hardcoded — nunca há recurso cabível para estes tipos.

---

### GW03 — Tipo de aprovação?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Diferencia o encerramento do processo conforme o tipo de documento aprovado:
- **APPCI / APPCI_RENOV:** licenciamento transita para `ALVARA_VIGENTE` → `End_AlvaraVigente`.
- **ATEC / INVIABILIDADE / CIV aprovados:** Certificado de Aprovação (CA) já emitido no P04 → `End_AprovadoCA`.

**Decisão de modelagem:** os dois EndEvents distintos (`End_AlvaraVigente` e `End_AprovadoCA`) representam resultados operacionalmente diferentes: o alvará vigente é a conclusão definitiva do licenciamento, enquanto o CA aprovado representa aprovação técnica que ainda pode ter desdobramentos administrativos (emissão de APPCI). Mantê-los separados facilita rastrear qual caminho levou ao encerramento do P05.

---

### GW04 — Cidadão decide interpor recurso?

**Elemento:** ExclusiveGateway (split e também ponto de entrada do loop de 2ª instância)
**Raia:** Cidadão

Ponto de decisão crucial: o cidadão, após ciência de CIA/CIV **reprovado**, decide se interpõe recurso administrativo. O prazo é de 30 dias após a ciência (`PRAZO_SOLICITAR_RECURSO_1_INSTANCIA = 30`).

Este gateway também recebe o fluxo de retorno do GW13 (loop de 2ª instância), quando o cidadão decide interpor recurso na segunda instância com `instancia=2`.

- **Sem recurso / prazo expirado:** `End_SemRecurso`.
- **Interpõe recurso:** `T05_PreencherRecurso`.

---

## 4. Fase 2 — Registro do Recurso Administrativo

### T05 — Preencher formulário do recurso administrativo

**Elemento:** UserTask
**Raia:** Cidadão
**`camunda:formKey`:** `recurso-preencher-form`

O cidadão preenche o formulário do recurso administrativo. Os campos obrigatórios do `RecursoDTO` são:

| Campo | Tipo | Regra |
|---|---|---|
| `idLicenciamento` | `Long` | ID do licenciamento contestado (obrigatório) |
| `idArquivoCiaCiv` | `Long` | ID do CIA ou CIV contestado (obrigatório) |
| `instancia` | `Integer` | 1 ou 2 (obrigatório, RN-P05-R04) |
| `tipoRecurso` | Enum | `CORRECAO_DE_ANALISE` ou `CORRECAO_DE_VISTORIA` (obrigatório) |
| `tipoSolicitacao` | Enum | `INTEGRAL` ou `PARCIAL` (obrigatório) |
| `fundamentacaoLegal` | `String` | Texto não-blank (obrigatório, RN-P05-R01) |
| `cpfRts[]` / `cpfRus[]` / `cpfProprietarios[]` | listas | Ao menos um CPF no conjunto (RN-P05-R03) |

Na 2ª instância (fluxo vindo do loop GW13), os campos `instancia=2` e os CPFs dos envolvidos são os mesmos do recurso original.

---

### T06B — Anexar documentos de suporte ao recurso

**Elemento:** UserTask
**Raia:** Cidadão
**`camunda:formKey`:** `recurso-anexar-documentos`

Etapa opcional: o cidadão pode fazer upload de documentos adicionais que suportem a argumentação do recurso.

**Endpoint REST:** `POST /recurso-arquivos/{recursoId}/upload` (multipart/form-data)
**Classe:** `RecursoArquivoRest`
**Fluxo interno:**
1. Recebe o arquivo via multipart.
2. `ArquivoRN.incluirArquivo(ArquivoED)` → upload para o Alfresco → obtém nodeRef.
3. Cria `RecursoArquivoED` vinculando o recurso ao arquivo.
4. Persiste `RecursoArquivoED` → INSERT em `CBM_RECURSO_ARQUIVO`.

O campo `identificadorAlfresco` da entidade `ArquivoED` armazena o nodeRef do Alfresco (máx 150 chars, `@NotNull`). O binário nunca vai para o banco relacional.

**Decisão de modelagem:** a tarefa de upload de documentos foi modelada como UserTask separada de T05 (preenchimento do formulário) para representar que são interações distintas no frontend Angular. Em termos de sequência, o upload ocorre após o preenchimento inicial e antes da submissão final. Modelar as duas juntas em uma única UserTask ocultaria essa distinção relevante.

---

### T06 — Validar e registrar recurso

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.recurso.RecursoRN`

**Endpoint REST:** `POST /recursos` → `RecursoRest`
**Método:** `RecursoRN.registra(RecursoDTO dto)`

A validação é executada por `RecursoRNVal.valida(dto)`:
- Campos obrigatórios nulos → HTTP 400 com mensagem `MSG_CAMPOS_OBRIGATORIOS`.
- Nenhum CPF de envolvido → HTTP 400 com mensagem `MSG_ENVOLVIDOS_NAO_INFORMADOS`.

Após validação, o `RecursoED` é criado com `situacao = SituacaoRecurso.AGUARDANDO_APROVACAO_ENVOLVIDOS` (ordinal 0 no BD, coluna `TP_SITUACAO`). Os envolvidos são criados nas tabelas de solicitação correspondentes (`CBM_SOLICITACAO_RT`, `CBM_SOLICITACAO_RU`, `CBM_SOLICITACAO_PROPRIETARIO`).

A resposta é HTTP 201 com `RecursoResponseDTO`.

---

## 5. Fase 3 — Aceites dos Envolvidos

### T07 — Confirmar aceite ou recusar o recurso

**Elemento:** UserTask
**Raia:** Cidadão
**`camunda:formKey`:** `recurso-aceite-form`
**`camunda:assignee`:** `${envolvidos}`

Cada envolvido listado no `RecursoED` (RT, RU e/ou Proprietário) deve confirmar ou recusar individualmente o recurso.

**Endpoint de aceite:** `PUT /recursos/{recursoId}` → `RecursoRN.alterarRecurso(Long id, RecursoDTO dto)`
**Endpoint de recusa:** `PUT /recursos/{recursoId}/recusar` → `RecursoRN.recusar(Long id)`

Regras de aceite aplicadas por `RecursoRN.alterarRecurso()`:
- Somente envolvidos listados por CPF podem confirmar (RN-P05-A01).
- Aceite confirmado não pode ser desfeito (RN-P05-A02).
- Quando todos confirmam: `situacao = AGUARDANDO_DISTRIBUICAO`, `dataEnvioAnalise = now()`, marcos `ENVIO_RECURSO_ANALISE` e `FIM_ACEITES_RECURSO_ANALISE` (RN-P05-A03/A04).
- Se qualquer envolvido recusar: `RecursoRN.recusar()` → `situacao = CANCELADO` (RN-P05-A05).

O cidadão pode ainda cancelar voluntariamente o recurso (`DELETE /recursos/{recursoId}/cancelar`) ou salvar rascunho (`PUT /recursos/{recursoId}/salvar`).

**Decisão de modelagem:** os aceites de múltiplos envolvidos foram representados como uma única UserTask (e não como um Parallel Gateway com múltiplas branches) porque na implementação real o processo é assíncrono e iterativo: cada envolvido acessa o portal individualmente e confirma em momentos distintos. O GW05 subsequente avalia o estado consolidado — não é necessário (nem correto em termos de semântica Java EE) modelar cada aceite individual como branch paralela no BPMN.

---

### GW05 — Todos os envolvidos confirmaram aceite?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Avalia o resultado consolidado dos aceites:
- **Qualquer recusa:** `T08_CancelarRecurso` → `End_RecursoCancelado`.
- **Todos aceitaram:** `T09_ConcluirAceites` → fase de distribuição.

A verificação é executada dentro de `RecursoRN.alterarRecurso()`: quando o último aceite é confirmado, a situação do recurso é automaticamente alterada para `AGUARDANDO_DISTRIBUICAO`.

---

### T08 — Cancelar recurso (CANCELADO)

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.recurso.RecursoRN`

**Método:** `RecursoRN.recusar(Long id)`
Seta `RecursoED.situacao = SituacaoRecurso.CANCELADO` (ordinal 4) e persiste via `RecursoBD.altera()`. Marco de recusa é registrado em `CBM_RECURSO_MARCO`.

**`End_RecursoCancelado`:** o recurso cancelado não impede que o cidadão registre novo recurso dentro do prazo remanescente — essa é uma possibilidade não modelada no P05 atual, pois dependeria de nova iteração iniciada pelo cidadão.

---

### T09 — Concluir aceites e transitar para AGUARDANDO_DISTRIBUICAO

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.recurso.RecursoRN`

Consolida os aceites e avança o recurso:
1. `recursoED.setSituacao(SituacaoRecurso.AGUARDANDO_DISTRIBUICAO)` (ordinal 1).
2. `recursoED.setDataEnvioAnalise(LocalDateTime.now())`.
3. Persiste via `RecursoBD.altera()`.
4. Marco `ENVIO_RECURSO_ANALISE` inserido em `CBM_RECURSO_MARCO` e em `LICEN_MARCO`.

---

## 6. Fase 4 — Distribuição para Analista

### T10 — Consultar recursos aguardando distribuição

**Elemento:** UserTask
**Raia:** Coordenador CBM-RS
**`camunda:formKey`:** `recurso-distribuicao-lista`

**Permissão:** `@Permissao(objeto="DISTRIBUICAOANALISE", acao="DISTRIBUIR")`
**Endpoint REST:** `GET /adm/recurso-analise/distribuicao-listar`
**Classe:** `RecursoAnaliseRestImpl` (com `@SOEAuthRest`)
**Método RN:** `RecursoAdmRN.listaParaDistribuicao()`

O coordenador visualiza a fila de recursos com `SituacaoRecurso.AGUARDANDO_DISTRIBUICAO`, filtrável por `instancia`, `tipoRecurso` e paginação.

Esta tarefa é também o ponto de retorno do loop de cancelamento de distribuição (fluxo de T12C → T10), quando o coordenador cancela uma distribuição já executada e o recurso volta à fila.

---

### T11 — Selecionar analista e confirmar distribuição

**Elemento:** UserTask
**Raia:** Coordenador CBM-RS
**`camunda:formKey`:** `recurso-distribuicao-selecionar`

O coordenador consulta a lista de analistas disponíveis (`GET /adm/recurso-analise/analistas-disponivel?codBatalhao=X`) com quantidade de processos em andamento e seleciona o analista. O formulário submete `RecursoDistribuicaoAnaliseDTO` com uma lista de `recursoId[]` e o `usuarioSoeId` do analista.

---

### GW_CancDistrib — Confirmar ou cancelar distribuição?

**Elemento:** ExclusiveGateway (split)
**Raia:** Coordenador

O coordenador pode confirmar ou cancelar a distribuição:
- **Confirmar:** `T12_ExecutarDistribuicao`.
- **Cancelar:** `T12C_CancelarDistribuicao` → retorno a T10.

O cancelamento de distribuição (`cancelarDistribuicaoRecurso`) também pode ocorrer após a distribuição ter sido executada — neste caso, o coordenador acessa o recurso já distribuído e cancela manualmente. O loop T12C → T10 representa ambos os cenários.

**Decisão de modelagem:** modelar o cancelamento como loop (T12C retorna a T10) é semanticamente correto: o coordenador cancela e o recurso volta à fila, reiniciando o ciclo de seleção. Um loop explícito é mais legível do que um gateway separado com múltiplas saídas.

---

### T12C — Cancelar distribuição

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.recurso.adm.RecursoAdmRN`

**Método:** `cancelarDistribuicaoRecurso(Long recursotId)`
**Endpoint:** `PUT /adm/recurso-analise/{recursotId}/cancelar-distribuicao`
**Permissão:** `@Permissao(objeto="DISTRIBUICAOANALISE", acao="CANCELAR")`

Passos executados:
1. `recursoED.setIdUsuarioSoe(null)` — remove o analista designado.
2. `recursoED.setSituacao(SituacaoRecurso.AGUARDANDO_DISTRIBUICAO)` — retorna à fila.
3. Se `instancia == 2`: exclui todos os `AvalistaRecursoED` e o `AnaliseRecursoED` vinculados — pois na 2ª instância, o colegiado pode ter sido parcialmente constituído antes do cancelamento.
4. Marco `CANCELA_DISTRIBUICAO_ANALISE_RECURSO` em `CBM_RECURSO_MARCO` e em `LICEN_MARCO`.

---

### T12 — Executar distribuição para analista (EM_ANALISE)

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.recurso.adm.RecursoAdmRN`

**Método:** `distribuirRecurso(RecursoDistribuicaoAnaliseDTO dto)`
**Endpoint:** `PUT /adm/recurso-analise/distribuicoes-recurso`
**Permissão:** `@Permissao(objeto="DISTRIBUICAOANALISE", acao="DISTRIBUIR")`

Para cada recurso na lista:
1. `recursoED.setIdUsuarioSoe(dto.usuarioSoeId)` — associa o analista (coluna `NRO_INT_USUARIO_SOE`).
2. `recursoED.setSituacao(SituacaoRecurso.EM_ANALISE)` (ordinal 3).
3. Persiste via `recursoRN.altera()`.
4. Marco `DISTRIBUICAO_ANALISE_RECURSO` em `CBM_RECURSO_MARCO` e `LICEN_MARCO` (responsável `BOMBEIROS`).

A operação suporta distribuição em lote: múltiplos `recursoId[]` podem ser distribuídos ao mesmo analista em uma única requisição.

---

## 7. Fase 5 — Análise do Recurso (1ª e 2ª Instância)

### T13 — Acessar recurso para análise

**Elemento:** UserTask
**Raia:** Analista CBM-RS
**`camunda:formKey`:** `recurso-analise-detalhe`

**Permissão:** `@Permissao(objeto="ANALISERECURSO", acao="ANALISAR")`
**Endpoint (lista):** `GET /adm/recurso-analise/pendentes-listar` — lista recursos `EM_ANALISE` do analista logado (identificado por `SessionMB.getUser().getId()`).
**Endpoint (detalhe):** `GET /adm/recurso-analise/{recursoId}` — retorna `RecursoResponseDTO` com todos os dados do recurso, envolvidos, arquivos e histórico.

O analista pode visualizar o CIA/CIV contestado (download via Alfresco) e os documentos anexados pelo cidadão.

---

### GW06 — 1ª ou 2ª instância?

**Elemento:** ExclusiveGateway (split)
**Raia:** Analista

Verifica `RecursoED.instancia`:
- `instancia == 1` → caminho de análise individual (1ª instância).
- `instancia == 2` → caminho de análise por colegiado (2ª instância).

**Decisão de modelagem:** o gateway separa explicitamente os dois subcaminhos porque os fluxos são substancialmente diferentes: na 1ª instância há análise individual direta; na 2ª instância há a criação do colegiado, votação de avalistaes e loop de votação antes do despacho final. Fundir os dois numa única UserTask obscureceria essa diferença fundamental de processo.

---

### Sub-fluxo 1ª Instância: T14 → T15

#### T14 — Analisar recurso e redigir despacho individual

**Elemento:** UserTask
**Raia:** Analista
**`camunda:formKey`:** `recurso-analise-1-instancia`

O analista estuda os documentos, redige o despacho (texto HTML via editor rico do Angular) e seleciona a decisão (`StatusRecurso`):

| Valor | Código no BD | Significado |
|---|---|---|
| `DEFERIDO_TOTAL` | `T` | Recurso integralmente acolhido |
| `DEFERIDO_PARCIAL` | `P` | Recurso parcialmente acolhido |
| `INDEFERIDO` | `I` | Recurso negado |

Os dados são coletados em `AnaliseRecursoDTO` (campos `recursoId`, `despacho`, `decisao`).

---

#### T15 — Concluir análise 1ª instância

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.analiserecurso.AnaliseRecursoAdmRN`

**Método:** `analisarRecurso(AnaliseRecursoDTO dto)`
**Endpoint:** `POST /adm/recurso-analise`
**Permissão:** `@Permissao(objeto="ANALISERECURSO", acao="ANALISAR")`

Passos executados:
1. Valida `despacho` (não-blank) e `decisao` (não-nulo) → HTTP 400 se inválidos.
2. Executa `deferimentoTotal1Instancia(recursoED, dto)`:
   - `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_VISTORIA`: cria nova `VistoriaED` (nova rodada de vistoria), licenciamento transita para `AGUARDANDO_DISTRIBUICAO_RENOV` ou `AGUARDA_DISTRIBUICAO_VISTORIA`.
   - `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_ANALISE`: cancela o CIA/CIV (`status=CANCELADA/CANCELADO`), licenciamento transita para `AGUARDANDO_DISTRIBUICAO`.
   - Nos demais casos: licenciamento retorna para `NCA` (análise) ou `CIV` (vistoria).
3. Cria `AnaliseRecursoED` com `situacao=ANALISE_CONCLUIDA`, `ciencia=false` (colunas `TP_SITUACAO` STRING, `IND_CIENCIA='N'`), `status=dto.getDecisao()` (ordinal).
4. `recursoED.setSituacao(SituacaoRecurso.ANALISE_CONCLUIDA)` (ordinal 2).
5. Marco `RESPOSTA_RECURSO` em `CBM_RECURSO_MARCO` e `LICEN_MARCO` (responsável `BOMBEIROS`).
6. Chama `geraRelatorioAnalise()` → gera PDF JasperReports e salva no Alfresco (ver Fase 6).

**Decisão de modelagem:** T15 foi separado de T14 porque representa a transação de backend completa, incluindo múltiplas operações de persistência e geração de PDF. Fundir com T14 obscureceria quais operações acontecem no browser e quais no servidor.

---

### Sub-fluxo 2ª Instância: T14B → T15B (loop) → T16B → T17B → T18B

#### T14B — Criar colegiado (selecionar até 2 avalistaes)

**Elemento:** UserTask
**Raia:** Analista
**`camunda:formKey`:** `recurso-colegiado-criar`

**Endpoint:** `POST /adm/recurso-analise/colegiado`
**Classe RN:** `AvalistaRecursoAdmRN.criarColegiado(AnaliseRecursoColegiadoDTO dto)`

Validações:
- `recursoId != null`, `usuariosSoeId` não-vazio, `usuariosSoeId.size() <= 2`, `recursoED.instancia == 2`.

Passos:
1. Cria `AnaliseRecursoED` com `situacao = AGUARDANDO_AVALIACAO_COLEGIADO` (STRING no BD) e `idUsuarioSoe` do analista logado.
2. Para cada `idUsuarioSoe` da lista: cria `AvalistaRecursoED` com `aceite=false` (`IND_ACEITE='N'`).
3. Marco `ENVIO_PARA_COLEGIADO` em `CBM_RECURSO_MARCO` e `LICEN_MARCO` (responsável `BOMBEIROS`).

O coordenador pode remover um avalistaantes de iniciar a votação (`DELETE /adm/recurso-analise/remover-avalista/{idAvalista}` → marco `EXCLUSAO_MEMBRO_JUNTA_TECNICA`, responsável `SISTEMA`, `usuarioSoeNome="SOLCBM"`).

---

#### T15B — Avalistaes do colegiado votam (concordo / não concordo)

**Elemento:** UserTask (com fluxo de entrada de retorno do GW07)
**Raia:** Analista
**`camunda:formKey`:** `recurso-colegiado-votacao`

Cada membro do colegiado vota individualmente:

- **Concordo:** `PUT /adm/recurso-analise/recurso/{recursoId}` → `AvalistaRecursoAdmRN.concordoColegiado()` → `avalista.setAceite(true)` (`'S'`).
- **Não concordo:** `PUT /adm/recurso-analise/avalista-nao-concordo/{recursoId}` com `AvalistaRecursoDTO.justificativaNaoConcordo` (max 4000 chars) → `aceite=false` (`'N'`).

Em ambos os casos, marco `ANALISE_RECURSO_COLEGIADO` é registrado (responsável `BOMBEIROS`). Quando o último avalista confirma (todos com `aceite != null`), o método `concordoColegiado()` detecta que todos votaram e adiciona automaticamente o marco `FIM_ANALISE_RECURSO_COLEGIADO` (responsável `SISTEMA`, `usuarioSoeNome="SOLCBM"`).

O campo `AvalistaRecursoED.aceite` usa `SimNaoBooleanConverter` (Boolean ↔ `'S'/'N'`), com semântica triestatal: `null = não votou`, `false/'N' = discordou`, `true/'S' = concordou`.

---

#### GW07 — Todos os avalistaes do colegiado votaram?

**Elemento:** ExclusiveGateway (split com loop)
**Raia:** Sistema

Verifica se todos os `AvalistaRecursoED` da `AnaliseRecursoED` possuem `aceite != null`:
- **Nem todos votaram:** retorna para T15B (loop — cada avalistavota individualmente).
- **Todos votaram:** avança para T16B.

**Decisão de modelagem:** o loop explícito GW07 → T15B modela a natureza assíncrona e iterativa da votação do colegiado: cada avalistaadiciona seu voto em chamadas REST independentes. O gateway verifica a condição de completude a cada voto. Essa construção é mais fiel à implementação real do que um Parallel Gateway com duas branches (que implicaria execução simultânea no motor BPMN).

---

#### T16B — Registrar marco FIM_ANALISE_RECURSO_COLEGIADO

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.avalistaanaliserecurso.AvalistaRecursoAdmRN`

Representa o marco automático registrado quando o último avalista confirma voto. O marco `FIM_ANALISE_RECURSO_COLEGIADO` tem `tipoResponsavel=SISTEMA` e `usuarioSoeNome="SOLCBM"`.

**Decisão de modelagem:** embora esse marco seja registrado dentro da lógica de `concordoColegiado()` (mesma chamada que T15B), ele foi modelado como ServiceTask separada para tornar visível no BPMN que há um evento sistêmico de conclusão do colegiado — um marco significativo do processo que deve ser rastreável na trilha de auditoria.

---

#### T17B — Redigir despacho e decisão final da 2ª instância

**Elemento:** UserTask
**Raia:** Analista
**`camunda:formKey`:** `recurso-analise-2-instancia`

O analista/coordenador consulta os votos do colegiado (incluindo justificativas de discordância), redige o despacho final em HTML (editor rico Angular) e seleciona a decisão (`StatusRecurso`: `DEFERIDO_TOTAL`, `DEFERIDO_PARCIAL` ou `INDEFERIDO`).

---

#### T18B — Concluir análise 2ª instância

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.analiserecurso.AnaliseRecursoAdmRN`

**Método:** `analisarSegundaInstancia(AnaliseRecursoDTO dto)`
**Endpoint:** `POST /adm/recurso-analise/segunda-instancia`

Diferenças em relação ao T15 (1ª instância):
- Usa o `AnaliseRecursoED` **já existente** (criado em T14B com `AGUARDANDO_AVALIACAO_COLEGIADO`), atualizando `despacho`, `status`, `situacao` e `dataConclusaoAnalise`.
- Marco registrado: `RESPOSTA_RECURSO_2` (não `RESPOSTA_RECURSO`).
- Lógica de `deferimentoTotal2Instancia()` é análoga à da 1ª instância.

---

### GW08 — Análise concluída (1ª ou 2ª instância)

**Elemento:** ExclusiveGateway (join/merge)
**Raia:** Sistema

Converge os fluxos de T15 (1ª instância) e T18B (2ª instância). Em ambos os casos, `AnaliseRecursoED.situacao = ANALISE_CONCLUIDA` e o próximo passo é gerar o relatório PDF.

---

## 8. Fase 6 — Geração do Relatório e Atualização de Estado

### T19 — Gerar relatório PDF da análise (JasperReports + Alfresco)

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.analiserecurso.AnaliseRecursoAdmRN`

**Método:** `geraRelatorioAnalise(AnaliseRecursoED ed)` — chamado internamente ao final de `analisarRecurso()` e `analisarSegundaInstancia()`.

Passos:
1. `arquivoRN.gerarNumeroAutenticacao()` → gera código único de autenticidade do documento.
2. `documentoRelatorioAnaliseRecursoRN.gera(AnaliseRecursoRelatorioDTO)` → JasperReports gera `InputStream` do PDF com campos como número PPCI, envolvidos, fundamentação legal (após `unescapeHTML()`), despacho (após `unescapeHTML()`), logos CBM-RS e RS, instância, decisão textual e código de autenticação.
3. `arquivoRN.incluirArquivo(arquivoED)` → upload do PDF para o Alfresco → obtém nodeRef → persiste `ArquivoED` com `identificadorAlfresco` (tabela `ARQUIVO`).
4. `ed.setArquivo(arquivoSalvo)` + `altera(ed)` → vincula o arquivo PDF ao `AnaliseRecursoED` (coluna `NRO_INT_ARQUIVO`).

O nome do arquivo segue o padrão `ca_analise_recurso_{instancia}_instancia.pdf`. O `unescapeHTML()` converte tags HTML do editor rico (ex.: `<strong>` → `<b>`) para compatibilidade com o JasperReports, que processa apenas HTML básico.

O download está disponível via `GET /recurso-arquivos/download-analise/{idRecurso}`.

**Decisão de modelagem:** a geração do relatório foi modelada como ServiceTask separada (mesmo sendo chamada internamente em T15/T18B) para tornar explícito no fluxo um passo relevante: a geração do documento oficial autenticado é um evento de negócio significativo, com impacto em Alfresco e no `AnaliseRecursoED`. Sua visibilidade no BPMN facilita o rastreamento de problemas (por exemplo, falha de comunicação com o Alfresco) na linha do tempo do processo.

---

### T20 — Atualizar estado do licenciamento conforme decisão

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.analiserecurso.AnaliseRecursoAdmRN`

Consolida as transições de estado do licenciamento já executadas dentro de T15/T18B (`deferimentoTotal1Instancia/2`). A ServiceTask representa explicitamente que, a esta altura do processo, o licenciamento já está no estado correto conforme a decisão:

| Decisão | Tipo de Recurso | Nova situação do licenciamento |
|---|---|---|
| `DEFERIDO_TOTAL + INTEGRAL` | `CORRECAO_DE_ANALISE` | `AGUARDANDO_DISTRIBUICAO` (CIA/CIV cancelado) |
| `DEFERIDO_TOTAL + INTEGRAL` | `CORRECAO_DE_VISTORIA` | `AGUARDA_DISTRIBUICAO_VISTORIA` ou `AGUARDANDO_DISTRIBUICAO_RENOV` |
| `DEFERIDO_PARCIAL` ou `INDEFERIDO` | `CORRECAO_DE_ANALISE` | `NCA` |
| `DEFERIDO_PARCIAL` ou `INDEFERIDO` | `CORRECAO_DE_VISTORIA` | `CIV` |

Em todos os casos, `RecursoED.situacao = ANALISE_CONCLUIDA` e `AnaliseRecursoED.ciencia = false` (aguardando ciência do cidadão).

---

## 9. Fase 7 — Ciência da Resposta do Recurso

### T21 — Tomar ciência da resposta do recurso

**Elemento:** UserTask com BoundaryEvent Timer (30 dias)
**Raia:** Cidadão
**`camunda:formKey`:** `recurso-ciencia-resposta`

O cidadão visualiza o despacho e a decisão do recurso, faz download do PDF gerado (`GET /recurso-arquivos/download-analise/{idRecurso}`) e confirma a ciência.

**Endpoint para ciência manual:** o frontend chama o endpoint que aciona `AnaliseRecursoRN.alterar(AnaliseRecursoED)`:
1. `analiseRecursoED.setDthCienciaAtec(Calendar.getInstance())` — registra data/hora da ciência (coluna `DTH_CIENCIA_ATEC`).
2. `analiseRecursoED.setIdUsuarioCiencia(usuarioRN.getUsuarioLogado().getId())` — registra o usuário que tomou ciência.
3. `analiseRecursoED.setCiencia(true)` → `SimNaoBooleanConverter` → `'S'` na coluna `IND_CIENCIA`.
4. `altera(analiseRecursoED)` → UPDATE em `CBM_ANALISE_RECURSO`.
5. Marco `CIENCIA_RECURSO` em `CBM_RECURSO_MARCO` (responsável `CIDADAO`) e em `LICEN_MARCO`.

Neste método, `@Permissao(desabilitada=true)` indica que a verificação de permissão do framework `arqjava4` está suprimida — qualquer cidadão envolvido pode registrar a ciência sem checagem de papel específico.

---

### Tmr_30DiasCienciaResp — Timer de ciência automática da resposta (30 dias)

**Elemento:** BoundaryEvent Timer, `cancelActivity=true`
**Raia:** Cidadão (anexado a T21)
**`timeDuration`:** `P30D`

A implementação real é a chamada `recursoCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite)` dentro do mesmo job `LicenciamentoCienciaBatchRN.efetuaCienciaAutomatica()`. A classe `RecursoCienciaAutomaticaRN` consulta `AnaliseRecursoBD.listarPendentesDeCiencia(dataLimite)`:

```sql
SELECT ar FROM AnaliseRecursoED ar
WHERE ar.ciencia = false
  AND ar.situacao = 'ANALISE_CONCLUIDA'
  AND ar.dataConclusaoAnalise <= :dataLimite
```

Para cada `AnaliseRecursoED` encontrado:
1. `analiseRecursoED.setCiencia(true)` e `setDthCienciaAtec(now())`.
2. Persiste via `analiseRecursoBD.altera()`.
3. Marco `CIENCIA_RECURSO` em `CBM_RECURSO_MARCO` (responsável `SISTEMA`, `usuarioSoeNome="SOLCBM"`) e em `LICEN_MARCO`.

**Decisão de modelagem:** o mesmo padrão de BoundaryEvent Timer (utilizado em T02) é aplicado aqui. A consistência de modelagem facilita a compreensão: toda ciência com prazo de 30 dias possui o mesmo idioma BPMN.

---

### T22 — Registrar ciência manual da resposta

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.analiserecurso.AnaliseRecursoRN`

Representa o processamento backend após confirmação manual em T21.

---

### T22B — Ciência automática da resposta

**Elemento:** ServiceTask
**Raia:** Sistema
**`camunda:class`:** `com.procergs.solcbm.licenciamentociencia.LicenciamentoCienciaBatchRN`

Representa o processamento do job `RecursoCienciaAutomaticaRN`. Diferença em relação à ciência manual: sem `idUsuarioCiencia` (campo não preenchido), marco com `tipoResponsavel=SISTEMA`.

---

### GW09 — Join da ciência da resposta (manual ou automática)

**Elemento:** ExclusiveGateway (join)
**Raia:** Sistema

Converge os fluxos de T22 (manual) e T22B (automática) para seguir ao gateway de resultado.

---

## 10. Fase 8 — Resultado Final e Opção de Segunda Instância

### GW10 — Qual é o resultado da análise?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Verifica `AnaliseRecursoED.status` (coluna `TP_STATUS`, ordinal de `StatusRecurso`):
- `DEFERIDO_TOTAL` → GW11 (verificar tipo de deferimento).
- `DEFERIDO_PARCIAL` ou `INDEFERIDO` → GW12 (verificar se foi 2ª instância).

---

### GW11 — Tipo de deferimento total?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Diferencia os encadeamentos pós-deferimento total:
- `CORRECAO_DE_VISTORIA + DEFERIDO_TOTAL`: nova vistoria criada em T15/T18B → `T23_CriarNovaVistoria` → `End_NovaVistoria`.
- `CORRECAO_DE_ANALISE + DEFERIDO_TOTAL`: CIA/CIV cancelado, licenciamento volta à distribuição → `T24_CancelarCIACIV` → `End_VoltaDistribuicao`.
- Outros casos de deferimento total: `End_DeferidoTotal`.

**Justificativa dos EndEvents distintos:** cada saída representa uma consequência operacional diferente para o licenciamento. `End_NovaVistoria` indica que o P05 encerra com uma nova vistoria em curso; `End_VoltaDistribuicao` indica que o licenciamento retornou ao início da análise técnica. Esses estados distintos são relevantes para rastreabilidade e para entendimento de quais processos subsequentes são ativados.

---

### GW12 — Foi 2ª instância?

**Elemento:** ExclusiveGateway (split)
**Raia:** Sistema

Quando o recurso foi `DEFERIDO_PARCIAL` ou `INDEFERIDO`:
- `instancia == 2` → `End_P05` (processo encerrado; não há 3ª instância).
- `instancia == 1` → GW13 (cidadão pode optar pela 2ª instância).

---

### GW13 — Cidadão opta pela 2ª instância?

**Elemento:** ExclusiveGateway (split)
**Raia:** Cidadão

O cidadão, após ciência de resposta indeferida (total ou parcialmente) na 1ª instância, decide se interpõe recurso de 2ª instância. O prazo é de 15 dias (`PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15`).

- **Não interpõe / prazo expirado:** `End_SemSegInstancia`.
- **Interpõe 2ª instância:** fluxo retorna a GW04 com `instancia=2`.

**Decisão de modelagem — loop de volta ao GW04:** o loop de retorno de GW13 a GW04 (com waypoints roteados acima do pool para evitar sobreposição com os demais fluxos) foi preferido à duplicação do sub-processo de registro/aceites/distribuição/análise. A reutilização do mesmo conjunto de tarefas com `instancia=2` respeita o princípio DRY (Don't Repeat Yourself) no BPMN e é fiel à implementação real: o código Java trata os dois casos no mesmo fluxo, diferenciando apenas pelo valor do campo `instancia`. Uma sub-rotina ou Call Activity também seria uma opção válida, mas adicionaria complexidade estrutural desnecessária para um BPMN de documentação.

---

## 11. Decisões de Modelagem Transversais

### Padrão CDI Qualifier para resolução de implementações

O processo P05 utiliza extensivamente o padrão **Template Method + CDI Qualifier** para resolver qual implementação concreta de EJB é acionada em cada tipo de ciência. No BPMN, isso é representado nas ServiceTasks pela classe base abstrata (ex.: `LicenciamentoCienciaCidadaoBaseRN`), com nota documentada no `<documentation>` indicando que a implementação concreta é resolvida em runtime via `@LicenciamentoCienciaQualifier`.

Essa decisão mantém o BPMN legível (uma única ServiceTask por operação) sem ocultar a complexidade real — a documentação inline explica a indireção via CDI.

### SimNaoBooleanConverter e campos triestados

Vários campos booleanos no P05 utilizam `SimNaoBooleanConverter` (Boolean ↔ `'S'/'N'`): `AvalistaRecursoED.aceite`, `AnaliseRecursoED.ciencia`, `RecursoED` (diversos indicadores). O valor `null` (coluna sem valor) representa "não votou" / "ainda não registrou ciência", distinção relevante para as queries de ciência automática.

### Raias e permissões

Cada raia no BPMN corresponde a um conjunto de permissões `@Permissao(objeto, acao)` do framework `arqjava4`. As permissões estão documentadas em cada elemento BPMN relevante e na seção de segurança dos requisitos. A correlação raia ↔ permissão é:

| Raia | Permissões principais |
|---|---|
| Cidadão | `@AutorizaEnvolvido` (ciência) |
| Coordenador | `DISTRIBUICAOANALISE/DISTRIBUIR`, `DISTRIBUICAOANALISE/CANCELAR` |
| Analista | `ANALISERECURSO/ANALISAR`, `ANALISERECURSO/LISTAR`, `RECURSO/CONSULTAR` |
| Sistema | `@Permissao(desabilitada=true)` (jobs e operações automáticas) |

### Auditoria Hibernate Envers

As entidades principais do P05 (`RecursoED`, `AnaliseRecursoED`, `AvalistaRecursoED`) são anotadas com `@Audited`, gerando tabelas `*_AUD` automaticamente via Hibernate Envers. Toda alteração de estado é auditada sem instrumentação adicional no código de negócio.

### Dois TimerBoundaryEvents com a mesma duração

Os timers `Tmr_30DiasCiencia` (na ciência do CIA/CIV) e `Tmr_30DiasCienciaResp` (na ciência da resposta do recurso) ambos usam `P30D`. No entanto, são implementados por classes distintas e consultam tabelas diferentes. A mesma duração não implica a mesma consulta — a `LicenciamentoCienciaBatchRN` processa múltiplos tipos em sequência e inclui tanto a ciência do CIA/CIV quanto a ciência da resposta do recurso (`RecursoCienciaAutomaticaRN`).

---

## 12. Tabelas de Referência

### Enumerações relevantes

| Enumeração | Valores |
|---|---|
| `SituacaoRecurso` | `RASCUNHO(5)`, `AGUARDANDO_APROVACAO_ENVOLVIDOS(0)`, `AGUARDANDO_DISTRIBUICAO(1)`, `EM_ANALISE(3)`, `ANALISE_CONCLUIDA(2)`, `CANCELADO(4)` |
| `StatusRecurso` (decisão final) | `DEFERIDO_TOTAL("T")`, `DEFERIDO_PARCIAL("P")`, `INDEFERIDO("I")` |
| `SituacaoAnaliseRecursoEnum` | `EM_ANALISE`, `AGUARDANDO_AVALIACAO_COLEGIADO`, `ANALISE_CONCLUIDA` (STRING no BD) |
| `TipoLicenciamentoCiencia` | `ATEC`, `INVIABILIDADE`, `CIV`, `APPCI`, `APPCI_RENOV` |
| `TipoRecurso` | `CORRECAO_DE_ANALISE("A")`, `CORRECAO_DE_VISTORIA("V")` |
| `TipoSolicitacaoRecurso` | `INTEGRAL("I")`, `PARCIAL("P")` |

### Tabelas do banco de dados

| Tabela | Entidade JPA | Sequence | Papel no P05 |
|---|---|---|---|
| `CBM_RECURSO` | `RecursoED` | `CBM_ID_RECURSO_SEQ` | Entidade principal do recurso |
| `CBM_ANALISE_RECURSO` | `AnaliseRecursoED` | `CBM_ID_ANALISE_RECURSO_SEQ` | Análise e despacho (1ª e 2ª instância) |
| `CBM_RECURSO_MARCO` | `RecursoMarcoED` | `CBM_ID_RECURSO_MARCO_SEQ` | Trilha de auditoria do recurso |
| `CBM_RECURSO_ARQUIVO` | `RecursoArquivoED` | `CBM_ID_RECURSO_ARQUIVO_SEQ` | Vínculos entre recurso e arquivos |
| `CBM_AVALISTA_RECURSO` | `AvalistaRecursoED` | `CBM_ID_AVALISTA_RECURSO_SEQ` | Membros e votos do colegiado |
| `ARQUIVO` | `ArquivoED` | — | Referência de arquivos no Alfresco |
| `LICEN_MARCO` | `LicenciamentoMarcoED` | — | Trilha de auditoria do licenciamento |
| `LICENCIAMENTO` | `LicenciamentoED` | — | Atualização de situação |

### Marcos registrados no P05

| Marco (`TipoMarco`) | Fase | Responsável | Visibilidade |
|---|---|---|---|
| `CIENCIA_CIA_ATEC` / `CIENCIA_CA_ATEC` | Fase 1 (manual) | CIDADAO | PUBLICO |
| `CIENCIA_CIA_INVIABILIDADE` / `CIENCIA_CA_INVIABILIDADE` | Fase 1 (manual) | CIDADAO | PUBLICO |
| `CIENCIA_CIV` / `CIENCIA_CIV_RENOVACAO` | Fase 1 (manual) | CIDADAO | PUBLICO |
| `CIENCIA_APPCI` / `CIENCIA_APPCI_RENOVACAO` | Fase 1 (manual) | CIDADAO | PUBLICO |
| `CIENCIA_AUTO_CIA_ATEC` / `CIENCIA_AUTO_CA_ATEC` | Fase 1 (automático) | SISTEMA | PUBLICO |
| `CIENCIA_AUTO_CIA_INVIABILIDADE` / `CIENCIA_AUTO_CA_INVIABILIDADE` | Fase 1 (automático) | SISTEMA | PUBLICO |
| `CIENCIA_AUTO_CIV` | Fase 1 (automático) | SISTEMA | PUBLICO |
| `ENVIO_RECURSO_ANALISE` / `FIM_ACEITES_RECURSO_ANALISE` | Fase 3 | CIDADAO | PUBLICO |
| `DISTRIBUICAO_ANALISE_RECURSO` | Fase 4 | BOMBEIROS | BOMBEIROS |
| `CANCELA_DISTRIBUICAO_ANALISE_RECURSO` | Fase 4 (cancelamento) | BOMBEIROS | BOMBEIROS |
| `ENVIO_PARA_COLEGIADO` | Fase 5 (2ª inst.) | BOMBEIROS | BOMBEIROS |
| `ANALISE_RECURSO_COLEGIADO` | Fase 5 (votação) | BOMBEIROS | PUBLICO |
| `FIM_ANALISE_RECURSO_COLEGIADO` | Fase 5 (2ª inst.) | SISTEMA | PUBLICO |
| `RESPOSTA_RECURSO` | Fase 5 (1ª inst.) | BOMBEIROS | PUBLICO |
| `RESPOSTA_RECURSO_2` | Fase 5 (2ª inst.) | BOMBEIROS | PUBLICO |
| `DOCUMENTO_CIA_CIV_CANCELADO` | Fase 6 (deferimento total) | SISTEMA | PUBLICO |
| `CIENCIA_RECURSO` | Fase 7 (manual) | CIDADAO | PUBLICO |
| `CIENCIA_RECURSO` | Fase 7 (automático) | SISTEMA | PUBLICO |

### Constantes de negócio relevantes

| Constante | Valor | Classe | Uso |
|---|---|---|---|
| `PRAZO_SOLICITAR_RECURSO_1_INSTANCIA` | 30 dias | `LicenciamentoCidadaoRN` | Prazo para interpor 1ª instância |
| `PRAZO_SOLICITAR_RECURSO_2_INSTANCIA` | 15 dias | `LicenciamentoCidadaoRN` | Prazo para interpor 2ª instância |
| `DIAS_PERIODO_VERIFICACAO` | -30 | `LicenciamentoCienciaBatchRN` | Janela do job de ciência automática |
| `RECURSO_1_INSTANCIA` | 1 | `AnaliseRecursoAdmRN` | Constante da 1ª instância |
| `RECURSO_2_INSTANCIA` | 2 | `AnaliseRecursoAdmRN` | Constante da 2ª instância |
| `NOME_RESPONSAVEL_SISTEMA` | `"SOLCBM"` | `RecursoCienciaAutomaticaRN` | Nome do sistema em marcos automáticos |

### Endpoints REST por fase

| Fase | Endpoint | Método | Classe REST |
|---|---|---|---|
| 1 — Ciência | `GET /recurso-arquivos/download/{idArquivo}` | cidadão baixa CIA/CIV | `RecursoArquivoRest` |
| 2 — Registro | `POST /recursos` | registrar recurso | `RecursoRest` |
| 2 — Registro | `POST /recurso-arquivos/{recursoId}/upload` | anexar documentos | `RecursoArquivoRest` |
| 3 — Aceites | `PUT /recursos/{recursoId}` | confirmar aceite | `RecursoRest` |
| 3 — Aceites | `PUT /recursos/{recursoId}/recusar` | recusar aceite | `RecursoRest` |
| 4 — Distribuição | `GET /adm/recurso-analise/distribuicao-listar` | listar para distribuir | `RecursoAnaliseRestImpl` |
| 4 — Distribuição | `PUT /adm/recurso-analise/distribuicoes-recurso` | distribuir | `RecursoAnaliseRestImpl` |
| 4 — Distribuição | `PUT /adm/recurso-analise/{id}/cancelar-distribuicao` | cancelar distribuição | `RecursoAnaliseRestImpl` |
| 5 — Análise 1ª | `POST /adm/recurso-analise` | analisar 1ª instância | `RecursoAnaliseRestImpl` |
| 5 — Análise 2ª | `POST /adm/recurso-analise/colegiado` | criar colegiado | `RecursoAnaliseRestImpl` |
| 5 — Análise 2ª | `PUT /adm/recurso-analise/recurso/{recursoId}` | avalistavota concordo | `RecursoAnaliseRestImpl` |
| 5 — Análise 2ª | `PUT /adm/recurso-analise/avalista-nao-concordo/{recursoId}` | avalistavota discorda | `RecursoAnaliseRestImpl` |
| 5 — Análise 2ª | `POST /adm/recurso-analise/segunda-instancia` | analisar 2ª instância | `RecursoAnaliseRestImpl` |
| 6 — Relatório | `GET /recurso-arquivos/download-analise/{idRecurso}` | baixar PDF análise | `RecursoArquivoRest` |
| 7 — Ciência resp. | _(endpoint via `AnaliseRecursoRN.alterar`)_ | confirmar ciência resposta | _(LicenciamentoRest)_ |
