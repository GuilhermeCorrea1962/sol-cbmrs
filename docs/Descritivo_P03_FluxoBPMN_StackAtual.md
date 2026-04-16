# Texto Descritivo do Fluxo BPMN — P03: Wizard de Nova Solicitação de Licenciamento

**Sistema:** SOL — Sistema Online de Licenciamento / CBM-RS
**Documento de referência:** `P03_Wizard_Solicitacao_Licenciamento_Detalhado.bpmn`
**Requisitos de origem:** `Requisitos_P03_SubmissaoPPCI_StackAtual.md`
**Stack de referência:** Java EE — JAX-RS · CDI · EJB @Stateless · JPA/Hibernate · Alfresco · WildFly
**Data:** 2026-03-06

---

## 1. Visão Geral do Processo

O Processo P03 — **Wizard de Nova Solicitação de Licenciamento** — é o fluxo central do sistema SOL. Representa a jornada completa que um estabelecimento percorre desde o momento em que o Responsável pelo Uso (RU) decide formalizar um pedido de licenciamento de segurança contra incêndio até o instante em que essa solicitação está pronta para ser distribuída a um analista do Corpo de Bombeiros Militar do Rio Grande do Sul (CBM-RS).

O processo é organizado em quatro fases distintas, cada uma com responsável, tecnologia e propósito claros:

| Fase | Nome | Ator principal | Estado do licenciamento |
|---|---|---|---|
| 1 | Wizard (formulário guiado) | Cidadão (RU) | `RASCUNHO` |
| 2 | Submissão automatizada | Sistema SOL (Backend Java EE) | `AGUARDANDO_ACEITE` |
| 3 | Aceites individuais dos envolvidos | RT e Proprietário | `AGUARDANDO_ACEITE` |
| 4 | Transição para análise | Sistema SOL (Backend Java EE) | `AGUARDANDO_DISTRIBUICAO` / `AGUARDANDO_PAGAMENTO` / `ANALISE_INVIABILIDADE_PENDENTE` |

O diagrama BPMN está estruturado em quatro raias horizontais (lanes), refletindo a separação de responsabilidades da arquitetura real do sistema:

| Raia | Ator / Sistema | Tecnologia | Responsabilidade |
|---|---|---|---|
| **Cidadão (RU)** | Responsável pelo Uso | Frontend Angular (autenticado via SOE PROCERGS) | Preenchimento do wizard, revisão e aceite do termo |
| **Responsável Técnico (RT)** | Profissional habilitado | Frontend Angular (autenticado via SOE PROCERGS) | Revisão da solicitação e aceite formal do termo de análise |
| **Proprietário** | Proprietário do imóvel | Frontend Angular (autenticado via SOE PROCERGS) | Aceite formal do termo de análise |
| **Sistema SOL (Automatizado)** | Backend Java EE | WildFly · JAX-RS · EJB · JPA/Hibernate · Alfresco | Persistência, geração de número, transições de estado, marcos, notificações |

---

## 2. Evento de Início — Cidadão Inicia Nova Solicitação

**Elemento BPMN:** `P03D_Start` (Start Event, raia Cidadão)

O fluxo se inicia quando o cidadão, já autenticado no sistema SOL por meio do SOE PROCERGS (OAuth2/OIDC), navega até a opção "Nova Solicitação" no portal. O evento de início representa o momento exato em que há a intenção formal de protocolar um pedido de licenciamento de segurança contra incêndio.

**Por que assim:** O evento de início é simples (sem gatilho externo) porque a criação de uma nova solicitação é uma ação iniciada exclusivamente por vontade do cidadão, sem depender de convocação, prazo ou notificação sistêmica. A autenticação prévia via SOE PROCERGS é uma pré-condição do sistema operacional — o frontend Angular já possui o token JWT com o CPF do usuário antes de qualquer ação do wizard.

---

## 3. Fase 1 — Wizard: Formulário Guiado em 7 Etapas

### 3.1 Conceito do Wizard

O wizard é um formulário multi-etapa com persistência automática de progresso. A cada etapa concluída, o campo `NRO_PASSO` da tabela `CBM_LICENCIAMENTO` é atualizado com o número da etapa seguinte. Isso garante que, se o cidadão fechar o navegador e retornar dias depois, o sistema o reposicione exatamente onde parou — sem perda de dados. A consulta `GET /licenciamentos/{id}` retorna o licenciamento com o campo `passo` preenchido, e o frontend restaura o estado da interface.

Esse comportamento é diretamente decorrente da regra RN-P03-004 e da natureza stateless do backend Java EE: o servidor não mantém sessão de formulário — toda a continuidade é garantida pelo banco de dados relacional.

---

### 3.2 Etapa 1 — Selecionar Tipo de Atividade e Enquadramento

**Elemento BPMN:** `P03D_T01` (User Task, raia Cidadão)

O cidadão seleciona o tipo de licenciamento (`TipoLicenciamento`) que corresponde à natureza da atividade do estabelecimento. Os valores possíveis são: PPCI, PSPCIM, CLCB, PSPCIB, EVENTO\_TEMPORARIO, EVENTO\_PIROTECNICO e CONSTRUCAO\_PROVISORIA.

Ao confirmar a seleção, o frontend envia uma requisição `POST /licenciamentos` ao backend. O método `LicenciamentoCidadaoRN.incluir()` é invocado, criando o registro principal do licenciamento com os seguintes valores iniciais obrigatórios:

- `situacao = RASCUNHO` — o licenciamento existe no sistema mas ainda não foi protocolado
- `fase = PROJETO` — fase padrão para novas solicitações
- `passo = 1` — posição atual no wizard
- `numero = null` — o número público do licenciamento só é gerado na submissão
- `diasAnaliseAnterior = 0` — não há análise anterior
- `recursoBloqueado = false` — o cidadão ainda pode solicitar recurso

Imediatamente após a criação, o sistema registra dois eventos encadeados: o primeiro é a gravação do histórico de situação via `LicenciamentoSituacaoHistRN`, que documenta a transição inicial para `RASCUNHO`; o segundo é a criação do marco `RASCUNHO_LICENCIAMENTO` via `LicenciamentoMarcoRN.criaMarcoPorTipo()`, registrado na tabela `CBM_LICENCIAMENTO_MARCO`. O marco representa o registro permanente e auditável do instante exato em que a solicitação foi criada.

**Por que assim:** A separação entre a UserTask (ação do cidadão) e as operações automáticas do sistema (criação do rascunho, histórico, marco) reflete a arquitetura real do sistema: o cidadão clica em "Avançar" no frontend, que faz uma chamada REST; o backend EJB Stateless executa toda a lógica de criação dentro de uma única transação JTA. O campo `passo` garante que a progressão seja idempotente — se a chamada falhar e for repetida, o sistema pode verificar o estado atual antes de criar duplicatas.

---

### 3.3 Gateway — Tipo de Licenciamento Exige Responsável Técnico?

**Elemento BPMN:** `P03D_GW_PPCI` (Exclusive Gateway, raia Cidadão)
**Condição:** `tipo == PPCI || tipo == PSPCIM`

Imediatamente após a conclusão da Etapa 1, o fluxo passa por um gateway exclusivo que verifica se o tipo de licenciamento escolhido exige a vinculação de um Responsável Técnico (RT).

- **Sim (PPCI ou PSPCIM):** o fluxo segue para a Etapa 3 (Vincular RT). Esses dois tipos representam edificações de médio e grande porte, que por norma legal exigem a responsabilidade técnica de um profissional habilitado (engenheiro ou arquiteto).
- **Não (CLCB, PSPCIB, EVENTO\_TEMPORARIO e outros):** o fluxo avança diretamente para o gateway de junção (`P03D_GW_JoinT03`), ignorando a Etapa 3. Esses tipos envolvem estabelecimentos de baixo risco ou atividades pontuais, nos quais a legislação não exige RT.

**Por que assim:** O gateway representa uma regra de negócio crítica do domínio (RN-P03-011). Modelar essa decisão como um gateway exclusivo no BPMN deixa explícita a bifurcação do fluxo, tornando a regra visível para a equipe de desenvolvimento sem necessidade de ler o código-fonte. O desenvolvedor que implementar este trecho sabe exatamente onde inserir o bloco condicional `if (tipo == PPCI || tipo == PSPCIM)` em `LicenciamentoCidadaoRN.incluir()`.

---

### 3.4 Etapa 2 — Dados do Estabelecimento, Empresa e Proprietários

**Elemento BPMN:** `P03D_T02` (User Task, raia Cidadão)

O cidadão informa os dados do estabelecimento que será licenciado. Esta etapa envolve três sub-cadastros independentes mas relacionados:

**Estabelecimento (`EstabelecimentoED`):** representa a atividade comercial ou institucional do imóvel. Um único licenciamento pode vincular múltiplos estabelecimentos — por exemplo, um shopping center com áreas de uso misto. O endpoint `PUT /licenciamentos/{id}/estabelecimentos/{idEst}` é usado para cada estabelecimento.

**Proprietário (`LicenciamentoProprietarioED` → `ProprietarioED`):** representa o titular do imóvel. A entidade `LicenciamentoProprietarioED` é a tabela associativa entre o licenciamento e o proprietário, e é nela que ficará registrado, mais adiante, o aceite formal do proprietário ao termo de licenciamento.

**Procurador (`ProcuradorED`):** se o Responsável pelo Uso ou o Proprietário não puder agir pessoalmente, designa um procurador, cujo arquivo de procuração é enviado via upload. O procurador fica vinculado à entidade do representado (`ResponsavelUsoED.procurador` ou `LicenciamentoProprietarioED.procurador`), e será ele quem realizará o aceite formal em nome do representado nas etapas seguintes. O arquivo da procuração é armazenado inteiramente no Alfresco ECM; o sistema SOL armazena apenas o identificador do nó no repositório (`identificadorAlfresco`, campo `@NotNull`, máximo 150 caracteres, na tabela `CBM_ARQUIVO`).

Ao avançar, o campo `passo` é atualizado para `3` via `PUT /licenciamentos/{id}`.

**Por que assim:** A separação entre estabelecimento, proprietário e procurador em entidades JPA distintas segue o princípio de responsabilidade única e facilita a auditoria independente de cada vínculo. A entidade `LicenciamentoProprietarioED` implementa a interface `EnvolvidoAceite`, o que permite que o sistema aplique o mesmo mecanismo de aceite (Consumer/Predicate em `TermoLicenciamentoRN`) a proprietários, RTs e RUs de forma polimórfica, sem duplicação de lógica.

---

### 3.5 Etapa 3 — Vincular Responsável Técnico (condicional: PPCI e PSPCIM)

**Elemento BPMN:** `P03D_T03` (User Task, raia Cidadão — branch superior do gateway)

Executada apenas quando o tipo de licenciamento é PPCI ou PSPCIM. O cidadão pesquisa e seleciona o(s) RT(s) que assinarão técnicamente a solicitação. O RT pesquisado deve ter cadastro aprovado no sistema (processo P02 concluído com `StatusCadastro.APROVADO`).

Para cada RT vinculado, o cidadão define o tipo de responsabilidade técnica (`TipoResponsabilidadeTecnica`):

| Valor | Significado |
|---|---|
| `PROJETO` | RT responsável apenas pela elaboração do projeto PPCI |
| `EXECUCAO` | RT responsável pela execução das medidas de segurança |
| `PROJETO_EXECUCAO` | RT responsável por projeto e execução |

O campo `aceite` de cada `ResponsavelTecnicoED` é inicializado como `false` — o aceite formal ocorrerá apenas após a submissão (Fase 3).

Cada RT deve ter ao menos um arquivo de ART/RRT vinculado, enviado via `POST /licenciamentos/{id}/rt/{idRT}/arquivo` e armazenado no Alfresco. O sistema admite múltiplos RTs (por exemplo, um arquiteto responsável pelo projeto e um engenheiro responsável pela execução), cada um com seu conjunto de documentos e tipo de responsabilidade. Cada RT vinculado precisará aceitar individualmente o termo de análise após a submissão.

Ao avançar, `passo = 4`.

**Por que assim:** O posicionamento desta etapa como branch condicional (em vez de sempre presente) corresponde diretamente à regra de negócio RN-P03-011. O BPMN torna visível que a Etapa 3 é um desvio opcional, não um passo sempre obrigatório. A inicialização de `aceite = false` é intencional e importante: garante que nenhum RT seja considerado como havendo aceitado a responsabilidade técnica sem ter passado pelo fluxo formal de aceite.

---

### 3.6 Gateway de Junção — Retorno ao Fluxo Principal

**Elemento BPMN:** `P03D_GW_JoinT03` (Exclusive Gateway, raia Cidadão)

Este gateway une os dois caminhos que vieram do gateway de decisão anterior: o caminho que passou pela Etapa 3 (com RT) e o caminho que a ignorou (sem RT). A partir deste ponto, todos os tipos de licenciamento seguem o mesmo fluxo para as Etapas 4, 5, 6 e 7.

**Por que assim:** Em BPMN, um gateway exclusivo de saída deve ser correspondido por um gateway exclusivo de junção. Sem ele, o fluxo ficaria ambíguo — não seria possível saber de quantas entradas a tarefa seguinte pode receber tokens. O gateway de junção é tecnicamente necessário para a corretude do modelo e visualmente útil para indicar onde a divergência termina.

---

### 3.7 Etapa 4 — Endereço e Localização do Estabelecimento

**Elemento BPMN:** `P03D_T04` (User Task, raia Cidadão)

O cidadão informa o endereço completo do estabelecimento a ser licenciado. Os dados de localização são armazenados na entidade `LocalizacaoED` (tabela `CBM_LOCALIZACAO`), que contém:

- Referência a `EnderecoLicenciamentoED` (endereço estruturado com logradouro, número, município, código IBGE)
- Coordenadas geográficas de dois tipos: as obtidas automaticamente a partir do endereço digitado (`latitudeEndereco`, `longitudeEndereco`) e as ajustadas manualmente pelo cidadão em um mapa interativo (`latitudeMapa`, `longitudeMapa`)
- Indicador de isolamento de risco (`isolamentoRisco`, campo Boolean persistido como `S/N` via `SimNaoBooleanConverter`)

Durante o preenchimento desta etapa, o sistema realiza automaticamente uma verificação via `GET /licenciamentos/{id}/endereco-existente`: consulta se já existe outro licenciamento ativo no mesmo endereço. Se existir, o cidadão recebe um alerta visual — mas não um bloqueio, pois é legítimo que um mesmo endereço tenha múltiplos licenciamentos ativos (por exemplo, prédio comercial com vários estabelecimentos).

O cidadão pode também anexar um comprovante de endereço via `POST /licenciamentos/{id}/localizacao/{idLoc}/arquivo`. O arquivo binário vai para o Alfresco ECM, e apenas o `identificadorAlfresco` (nodeRef) é persistido no banco de dados.

Ao avançar, `passo = 5`.

**Por que assim:** A separação entre coordenadas do endereço e coordenadas do mapa decorre de uma necessidade operacional do CBM-RS: o endereço digitado pelo cidadão pode ter georreferenciamento impreciso, e o ajuste manual no mapa garante que a equipe de vistoria saiba exatamente onde o imóvel está localizado. A verificação de endereço existente é uma validação de negócio — não uma validação técnica — e por isso não bloqueia: o CBM-RS precisa ser informado de sobreposições para avaliar, mas não cabe ao sistema tomar a decisão automaticamente.

---

### 3.8 Etapa 5 — Dados da Edificação

**Elemento BPMN:** `P03D_T05` (User Task, raia Cidadão)

Esta é a etapa de maior volume de dados do wizard. O cidadão descreve as características físicas, construtivas e de uso da edificação. Os dados são organizados em três grupos de entidades:

**Características da Edificação (`CaracteristicaED`):** armazena os dados físicos do imóvel. Os campos obrigatórios são: tipo de edificação (`TipoEdificacao`), período de construção (`TipoPeriodoConstrucao`), área construída total (m²), número de pavimentos acima do solo (mínimo 1), altura ascendente (do piso mais elevado, em metros), população total do estabelecimento e se o imóvel é regularizado. Existem ainda dezenas de campos opcionais que descrevem características construtivas especiais, tipos de instalações, operações industriais, transformadores elétricos e tempos de resistência ao fogo.

**Ocupações (`OcupacaoED`):** lista as atividades desenvolvidas no imóvel (comercial varejista, escola, hospital, etc.). Ao menos uma ocupação é obrigatória. As ocupações determinam quais medidas de segurança são exigíveis para a edificação.

**Especificações de Risco e Segurança:** a `EspecificacaoRiscoED` descreve os tipos de risco identificados no imóvel (materiais inflamáveis, explosivos, etc.), e a `EspecificacaoSegurancaED` descreve o conjunto de medidas de segurança contra incêndio planejadas (sprinklers, extintores, saídas de emergência, etc.). Se houver declaração de inviabilidade técnica (situação em que as medidas de segurança legalmente exigidas não podem ser aplicadas ao imóvel), isso é registrado na `EspecificacaoSegurancaED` e influenciará a transição de estado após os aceites.

O cidadão pode também fazer upload de uma planta geral do imóvel associada à `CaracteristicaED` via `POST /licenciamentos/{id}/caracteristicas/{idCar}/arquivo`. Esse arquivo vai para o Alfresco.

Ao avançar, `passo = 6`.

**Por que assim:** O volume de dados desta etapa é justificado pela complexidade técnica e legal das normas de segurança contra incêndio: o CBM-RS precisa de todas essas informações para calcular quais medidas de proteção são obrigatórias para cada edificação, de acordo com as Instruções Técnicas do CBMRS. A separação em três entidades JPA distintas (`CaracteristicaED`, `EspecificacaoRiscoED`, `EspecificacaoSegurancaED`) segue o princípio de coesão — cada entidade tem um propósito bem definido e pode ser alterada, versionada ou auditada de forma independente.

---

### 3.9 Etapa 6 — Upload de Documentos Obrigatórios (Elementos Gráficos)

**Elemento BPMN:** `P03D_T06` (User Task, raia Cidadão)

O cidadão faz o upload dos documentos técnicos exigidos pelo CBM-RS para análise. Cada documento é representado por uma instância de `ElementoGraficoED` vinculada a um `ArquivoED`. Os documentos típicos incluem plantas baixas, plantas de situação, memoriais descritivos e os arquivos ART/RRT da inviabilidade técnica (quando aplicável).

O tipo e a obrigatoriedade de cada documento dependem do `TipoLicenciamento` e do grupo de ocupação informados nas etapas anteriores. O enum `TipoElementoGrafico` centraliza essa classificação. O sistema disponibiliza endpoints para todas as operações necessárias sobre os documentos: criação da lista (`PUT /elementos-graficos`), upload do arquivo (`POST /elementos-graficos/{id}/arquivo`), substituição de arquivo enviado incorretamente (`PUT /elementos-graficos/{id}/arquivo`), download para conferência (`GET /elementos-graficos/{id}/arquivo`) e validação de disponibilidade para upload (`GET /elementos-graficos/{id}/arquivo/validar-upload`).

A exclusão de um documento não elimina o registro — é uma exclusão lógica: o campo `situacao` muda de `ATIVO` para `INATIVO`, e os campos `dataExclusao` e `idUsuarioExclusao` são preenchidos. O histórico de versões é mantido em `ElementoGraficoHistoricoED`.

Antes de avançar para a Etapa 7, o sistema executa uma validação obrigatória (RN-P03-063): verifica se todos os `ElementoGraficoED` exigíveis para o tipo de licenciamento e grupo de ocupação estão com `situacao = ATIVO` e com `identificadorAlfresco` preenchido (prova de que o arquivo foi efetivamente enviado ao Alfresco). Se algum documento obrigatório estiver ausente, o avanço é bloqueado.

Ao avançar, `passo = 7`.

**Por que assim:** O armazenamento dos arquivos binários exclusivamente no Alfresco ECM, com apenas o nodeRef no banco de dados relacional, é uma decisão arquitetural fundamental do sistema atual. Ela mantém o banco de dados enxuto, evita problemas de desempenho com BLOBs em consultas relacionais e aproveita os recursos de versionamento, controle de acesso e indexação do Alfresco. A validação de completude antes de avançar é uma regra de qualidade de dados — garante que nenhuma solicitação chegue à análise sem o conjunto mínimo de documentação exigida por lei.

---

### 3.10 Etapa 7 — Revisão, Leitura do Termo e Aceite pelo RU

**Elemento BPMN:** `P03D_T07` (User Task, raia Cidadão)

A última etapa do wizard apresenta ao cidadão um resumo completo de todos os dados informados nas etapas anteriores, para revisão final. Em seguida, o sistema exibe o **Termo de Licenciamento** específico para aquele tipo de licenciamento e perfil de envolvido.

O texto do termo é recuperado via `GET /licenciamentos/{id}/termo`, que aciona `TermoLicenciamentoRN.get(idLicenciamento)`. Esse método determina qual termo exibir consultando a tabela `CBM_TERMO_LICENCIAMENTO` com dois critérios: o `tpEnvolvido` (no caso do RU, o valor `RU` ou `AMBOS`) e o `tpLicenciamento` (o tipo de licenciamento da solicitação). Isso garante que termos específicos para cada combinação de tipo e envolvido sejam exibidos corretamente.

O cidadão lê o termo e clica em "Aceitar e Submeter". Esse clique dispara uma chamada `PUT /licenciamentos/{id}/termo`, que invoca `TermoLicenciamentoRN.confirmaAceiteAnalise(idLicenciamento)`. O fluxo transacional que começa neste momento é o ponto de virada do processo: a solicitação deixa de ser um rascunho e passa a ser um protocolo formal perante o CBM-RS.

**Por que assim:** A leitura e aceite do termo no próprio wizard (e não em uma tela separada posterior) é uma decisão de UX e de validade jurídica: o cidadão só pode submeter a solicitação após ter formalmente lido e concordado com os termos do licenciamento. A busca dinâmica do termo por tipo de envolvido e tipo de licenciamento, em vez de um texto fixo, permite que o CBM-RS atualize os termos sem alterar código-fonte — apenas atualizando registros na tabela `CBM_TERMO_LICENCIAMENTO`.

Após a conclusão desta etapa, nenhum dado da solicitação pode mais ser alterado pelo cidadão (RN-P03-074). Se o cidadão identificar um erro após a submissão, precisará acionar `LicenciamentoCidadaoRN.alterar()`, que reinicia o wizard ao passo 1 e remove todos os aceites já registrados — pois qualquer mudança de dados invalida os aceites existentes.

---

## 4. Fase 2 — Submissão Automatizada (Sistema SOL)

### 4.1 Service Task de Submissão

**Elemento BPMN:** `P03D_ST_Submissao` (Service Task, raia Sistema SOL)
**Classe:** `TermoLicenciamentoRN.confirmaAceiteAnalise()`

A tarefa de submissão é acionada automaticamente pelo aceite do RU na Etapa 7. Ela representa um bloco de operações executado em uma única transação JTA gerenciada pelo contêiner WildFly. As operações são:

**1. Registro do aceite do RU:** o Consumer `CONFIRMA_ACEITE_ANALISE` é aplicado ao `ResponsavelUsoED` do usuário logado, definindo `aceite = true` (campo `ACEITE = 'S'` no banco de dados via `SimNaoBooleanConverter`).

**2. Geração do número do licenciamento (RN-P03-073):** o número público é gerado no formato `[Tipo][Sequencial 8d][Lote 2L][Versão 3d]` — por exemplo, `A 00000361 AA 001`. Esse número é único, imutável após a geração e serve como identificador público do processo. Ele é gerado por `LicenciamentoNumeroRN`, que utiliza a sequence do banco de dados (`CBM_ID_LICENCIAMENTO_SEQ`) para o componente sequencial e uma lógica de lote para os componentes alfabéticos. O campo `COD_LICENCIAMENTO` da tabela `CBM_LICENCIAMENTO` recebe o valor e passa a ter restrição `UNIQUE`.

**3. Transição de situação para `AGUARDANDO_ACEITE`:** `LicenciamentoSituacaoHistRN.salva(ed, AGUARDANDO_ACEITE)` atualiza o campo `TP_SITUACAO` em `CBM_LICENCIAMENTO` e registra o histórico da transição na tabela `CBM_LICENCIAMENTO_SITU_HIST`. A partir deste instante, a solicitação está visivelmente na fila de "Aguardando Aceite" para os demais envolvidos.

**4. Criação do marco `ACEITE_ANALISE` para o RU:** `LicenciamentoMarcoRN.criaMarcoPorTipo(ed, TipoMarco.ACEITE_ANALISE)` registra um novo marco na tabela `CBM_LICENCIAMENTO_MARCO`, documentando o instante exato do aceite do RU com o usuário e o timestamp.

**5. Notificação dos demais envolvidos:** `NotificacaoRN.notificaEnvolvidosNovos(ed)` envia comunicações (tipicamente por e-mail) para todos os RTs vinculados e para os Proprietários, informando que há uma solicitação aguardando o aceite deles e fornecendo o link de acesso ao sistema.

**Por que assim:** Concentrar todas essas operações em uma única transação JTA garante consistência: se qualquer uma delas falhar, nenhuma das outras é persistida. O EJB `@Stateless` com `@TransactionAttribute(REQUIRED)` permite que o contêiner WildFly gerencie automaticamente o rollback em caso de exceção. A geração do número de licenciamento sendo parte da mesma transação evita que exista uma solicitação sem número público após a submissão.

---

### 4.2 Gateway de Split Paralelo — Início dos Aceites

**Elemento BPMN:** `P03D_GW_SplitAc` (Parallel Gateway, raia Sistema SOL)

Após a conclusão da submissão automatizada, o fluxo se divide em dois branches paralelos e independentes: um para o aceite do Responsável Técnico (RT) e outro para o aceite do Proprietário. O RU já aceitou na Etapa 7, portanto não aparece neste split.

**Por que assim:** O gateway paralelo (e não exclusivo) é usado aqui porque os dois aceites são efetivamente simultâneos e independentes — o RT e o Proprietário acessam o sistema em momentos diferentes, sem uma ordem definida entre eles. O BPMN não pode impor uma sequência onde não existe uma. O uso de um gateway paralelo reflete fielmente o comportamento real do sistema: ambos recebem notificação ao mesmo tempo e podem aceitar em qualquer ordem.

---

## 5. Fase 3 — Aceites Individuais dos Envolvidos

### 5.1 Aceite do Responsável Técnico (RT)

**Elemento BPMN:** `P03D_T09_RT` (User Task, raia RT)

O RT recebe, por e-mail, uma notificação informando que há uma solicitação aguardando seu aceite. Ele acessa o sistema SOL com seu próprio CPF (autenticação independente via SOE PROCERGS), localiza a solicitação em "Minhas Solicitações" e revisa todos os dados informados pelo cidadão.

O RT lê o termo de análise específico para seu perfil — recuperado via `GET /licenciamentos/{id}/termo`, que agora retorna o termo com `tpEnvolvido = RT`. Após a leitura, o RT aceita formalmente via `PUT /licenciamentos/{id}/termo`, que aciona novamente `TermoLicenciamentoRN.confirmaAceiteAnalise()`. O Consumer `CONFIRMA_ACEITE_ANALISE` é aplicado ao `ResponsavelTecnicoED` do RT logado, definindo `aceite = true`. Um novo marco `ACEITE_ANALISE` é registrado para o RT.

Se há múltiplos RTs vinculados, **cada um** precisa aceitar individualmente. O Predicate `RETORNA_ACEITE_ANALISE` verifica o aceite de cada RT por separado.

**Por que assim:** A exigência de aceite individual de cada RT não é arbitrária: ao aceitar o termo, o profissional habilitado está formalmente assumindo a responsabilidade técnica pelo projeto e/ou execução das medidas de segurança. Trata-se de um ato com consequências jurídicas e profissionais (sujeito à fiscalização do CREA/CAU). O sistema precisa registrar individualmente quem aceitou, quando e em qual papel.

---

### 5.2 Gateway — RT Aceitou o Termo de Análise?

**Elemento BPMN:** `P03D_GW_RTAceit` (Exclusive Gateway, raia RT)

Após o RT interagir com a tarefa de aceite, o gateway verifica se o aceite foi confirmado:

- **Sim:** o campo `ResponsavelTecnicoED.aceite == true`. O token do branch do RT avança para o gateway de junção na raia Sistema.
- **Não (RT recusou):** o campo permanece `false` ou `null`. O fluxo termina com um End Event de terminação (`P03D_End_RTRec`), representando o bloqueio do processo.

**Por que assim:** A recusa do RT é modelada como um End Event de terminação porque, na prática, ela bloqueia indefinidamente o progresso do licenciamento — não há ação automática do sistema nesse caso. O licenciamento permanece em `AGUARDANDO_ACEITE`, e a única saída é o cidadão alterar os dados da solicitação (o que reinicia o wizard) ou o RT mudar de posição fora do sistema. Modelar isso como fim do fluxo é mais honesto do que fingir que há um caminho de retorno automático.

---

### 5.3 Fim — RT Recusou (Licenciamento Bloqueado)

**Elemento BPMN:** `P03D_End_RTRec` (End Event Terminate, raia RT)

Quando o RT formalmente recusa o termo, este End Event com terminação encerra o token do processo. O licenciamento permanece em `AGUARDANDO_ACEITE` indefinidamente, aguardando uma ação do cidadão ou negociação externa.

Para desbloquear a situação, o cidadão deve acionar `LicenciamentoCidadaoRN.alterar()`, que:
- Remove todos os aceites já registrados: Consumer `REMOVE_ACEITE_ANALISE` aplicado a todos os envolvidos
- Reinicia o wizard: `LicenciamentoED.setPasso(1)` (constante `NRO_PASSO`)

**Por que assim:** O End Event de terminação (símbolo do círculo preenchido) encerra toda a instância do processo, não apenas o token local. Isso reflete que, quando o RT recusa, não há como continuar o fluxo paralelo do Proprietário de forma significativa — ambos os branches precisam ser encerrados. Na implementação real, o sistema não "cancela" o licenciamento — mantém-o em `AGUARDANDO_ACEITE` — mas do ponto de vista do fluxo modelado, esse caminho não tem continuidade.

---

### 5.4 Aceite do Proprietário

**Elemento BPMN:** `P03D_T09_Prop` (User Task, raia Proprietário)

O Proprietário do imóvel recebe notificação por e-mail e acessa o sistema com seu próprio CPF (autenticação SOE PROCERGS). O processo é análogo ao do RT: o Proprietário lê o termo (com `tpEnvolvido = PROPRIETARIO` ou `AMBOS`) e aceita via `PUT /licenciamentos/{id}/termo`.

O Consumer `CONFIRMA_ACEITE_ANALISE` é aplicado ao `LicenciamentoProprietarioED` correspondente. A implementação defensiva do getter de aceite — `Optional.ofNullable(aceite).orElse(false)` — garante que um campo nulo não cause `NullPointerException` ao verificar o aceite.

Se o Proprietário age por Procurador, é o Procurador quem realiza o aceite no sistema, usando seu próprio CPF. O vínculo `LicenciamentoProprietarioED.procurador → ProcuradorED` registra essa representação.

**Por que assim:** A exigência do aceite do Proprietário tem fundamento no direito de propriedade: as medidas de segurança contra incêndio são instaladas no imóvel e podem implicar obras, reformas e custos ao proprietário. O aceite formal garante que o proprietário está ciente e concorda com as exigências que serão impostas. A possibilidade de procurador é uma realidade prática — muitos imóveis têm proprietários pessoas jurídicas, idosos, residentes no exterior, etc.

---

## 6. Fase 4 — Verificação de Aceites e Transição de Estado

### 6.1 Gateway de Join Paralelo — Todos os Aceites Concluídos

**Elemento BPMN:** `P03D_GW_JoinAc` (Parallel Gateway, raia Sistema SOL)

O gateway de junção paralela aguarda que ambos os branches anteriores entreguem seu token: o do RT (branch que passa por `P03D_GW_RTAceit` com resultado "Sim") e o do Proprietário (branch que sai de `P03D_T09_Prop`). Somente quando ambos chegam o fluxo avança.

**Por que assim:** O gateway de junção paralela (join) é o mecanismo BPMN correto para sincronizar dois branches paralelos. Ele garante que o sistema não avance para a verificação final enquanto qualquer envolvido ainda não tiver concluído sua parte. Isso espelha a regra de negócio real: o campo `FIM_ACEITES_ANALISE` só pode ser gerado quando todos têm `aceite == true`.

---

### 6.2 Service Task — Verificar Todos os Aceites e Determinar Transição

**Elemento BPMN:** `P03D_ST_TodosAceit` (Service Task, raia Sistema SOL)
**Classe:** `TermoLicenciamentoRN.confirmaAceiteAnalise()`

Quando o último envolvido aceita (seja o RT, seja o Proprietário — dependendo de quem agiu por último), o sistema executa a verificação final. O Predicate `RETORNA_ACEITE_ANALISE = e -> Optional.ofNullable(e.getAceite()).orElse(false)` é aplicado a todos os envolvidos de todos os tipos (RTs, RUs, Proprietários). Somente se o resultado for `true` para todos o fluxo avança — caso contrário, a situação permanece `AGUARDANDO_ACEITE`.

Se todos confirmados:

1. `LicenciamentoMarcoRN.criaMarcoPorTipo(ed, TipoMarco.FIM_ACEITES_ANALISE)` — registra o marco do encerramento da fase de aceites.
2. O sistema determina a próxima transição de situação com base em três condições, verificadas em ordem de prioridade:
   - `LicenciamentoED.isencao == true` → transição para `AGUARDANDO_PAGAMENTO`
   - Inviabilidade técnica detectada → transição para `ANALISE_INVIABILIDADE_PENDENTE`
   - Caso padrão → transição para `AGUARDANDO_DISTRIBUICAO`
3. `LicenciamentoSituacaoHistRN.salva(ed, novaSituacao)` — persiste a mudança e registra histórico.
4. `NotificacaoRN.notifica(ed, ANALISTAS_CBMRS)` — notifica analistas CBM-RS sobre a nova solicitação disponível.

**Por que assim:** Centralizar toda a lógica de verificação e transição no método `confirmaAceiteAnalise` é uma decisão arquitetural que garante consistência: independente de qual envolvido fez o último aceite, o mesmo método é chamado e executa a mesma sequência de verificações. Isso evita duplicação de lógica e garante que os marcos e históricos sejam criados corretamente independente do caminho percorrido.

---

### 6.3 Gateway — Isenção de Taxa Solicitada?

**Elemento BPMN:** `P03D_GW_Isencao` (Exclusive Gateway, raia Sistema SOL)
**Condição:** `LicenciamentoED.isencao == true`

Após todos os aceites confirmados, o sistema verifica se o cidadão solicitou isenção da taxa de análise. O campo `IND_ISENCAO` na tabela `CBM_LICENCIAMENTO` é verificado (Boolean armazenado como `'S'/'N'` via `SimNaoBooleanConverter`).

- **Sim:** o fluxo vai para a transição `AGUARDANDO_PAGAMENTO`, e o campo `situacaoIsencao` é definido como `TipoSituacaoIsencao.SOLICITADA`.
- **Não:** o fluxo vai para a verificação de inviabilidade técnica.

**Por que assim:** A isenção de taxa tem prioridade sobre a verificação de inviabilidade porque são condições independentes e de tratamento diferente. Um licenciamento com isenção solicitada precisa aguardar a deliberação do CBM-RS sobre a isenção antes de ser distribuído para análise — daí o estado `AGUARDANDO_PAGAMENTO`. Se modelássemos isso como uma regra dentro da service task, a intenção ficaria oculta no código; ao expô-la como gateway, tornamos a regra de prioridade explícita e auditável.

---

### 6.4 Service Task — Transição para AGUARDANDO\_PAGAMENTO

**Elemento BPMN:** `P03D_ST_SitAgPag` (Service Task, raia Sistema SOL)

Quando isenção foi solicitada, o sistema:
- Atualiza `LicenciamentoED.situacao = AGUARDANDO_PAGAMENTO`
- Define `situacaoIsencao = TipoSituacaoIsencao.SOLICITADA` e `dthSolicitacaoIsencao = Calendar.getInstance()`
- Registra histórico via `LicenciamentoSituacaoHistRN`
- Cria o marco `SOLICITACAO_ISENCAO`

**Por que assim:** O campo `dthSolicitacaoIsencao` é necessário para calcular prazos de análise do pedido de isenção pelo CBM-RS. O marco `SOLICITACAO_ISENCAO` cria um registro permanente e auditável do momento do pedido, independente de futuras alterações no campo.

---

### 6.5 Fim — AGUARDANDO\_PAGAMENTO

**Elemento BPMN:** `P03D_End_AgPag` (End Event, raia Sistema SOL)

O P03 termina com o licenciamento em `AGUARDANDO_PAGAMENTO`. O CBM-RS analisará o pedido de isenção: se aprovado (`TipoSituacaoIsencao.APROVADA`), o licenciamento avança para `AGUARDANDO_DISTRIBUICAO`; se reprovado, o cidadão deve pagar o boleto gerado (`BoletoLicenciamentoED`).

---

### 6.6 Gateway — Inviabilidade Técnica Identificada?

**Elemento BPMN:** `P03D_GW_Inviab` (Exclusive Gateway, raia Sistema SOL)

Quando não há isenção, o sistema verifica se existe inviabilidade técnica declarada pelo RT ou identificada na `EspecificacaoSegurancaED`. Inviabilidade técnica ocorre quando as medidas de proteção contra incêndio legalmente exigíveis não podem ser fisicamente implementadas no imóvel.

- **Sim:** transição para `ANALISE_INVIABILIDADE_PENDENTE`.
- **Não:** transição para `AGUARDANDO_DISTRIBUICAO` (fluxo padrão).

**Por que assim:** A inviabilidade técnica requer deliberação especial do CBM-RS antes de qualquer análise formal. Distribuir o licenciamento para análise normal sem antes resolver a inviabilidade tornaria o trabalho do analista inócuo — ele analisaria um projeto que o próprio RT declarou ser inviável. O estado `ANALISE_INVIABILIDADE_PENDENTE` cria um processo apartado de deliberação.

---

### 6.7 Service Task e Fim — ANALISE\_INVIABILIDADE\_PENDENTE

**Elemento BPMN:** `P03D_ST_SitInviab` / `P03D_End_Inviab`

O campo `LicenciamentoED.inviabilidadeAprovada` é definido como `null` (pendente). O CBM-RS delibera:
- Se aprovada: `inviabilidadeAprovada = true` → avança para `AGUARDANDO_DISTRIBUICAO`
- Se não aprovada: `inviabilidadeAprovada = false` → licenciamento é extinto (`EXTINGUIDO`) via `LicenciamentoCidadaoExtincaoRN`

---

### 6.8 Service Task e Fim — AGUARDANDO\_DISTRIBUICAO (saída principal)

**Elemento BPMN:** `P03D_ST_SitAgDist` / `P03D_End_AgDist`

Este é o desfecho padrão e principal do P03. O licenciamento, com número gerado, todos os aceites confirmados e documentação completa, é situado como `AGUARDANDO_DISTRIBUICAO`. O sistema notifica os analistas CBM-RS que há uma nova solicitação disponível para distribuição.

A partir deste ponto, o processo P04 (Análise Técnica) assume. O analista recebe a solicitação, a análise é iniciada e o campo `dthEncaminhamentoAnalise` de `LicenciamentoED` será preenchido. Os resultados possíveis do P04 são:

| Resultado | Situação | Próximo processo |
|---|---|---|
| CA (Conformidade Atendida) | `CA` | APPCI emitido — P11 (Ciência do cidadão) |
| NCA (Não Conformidade Atendida) | `NCA` | Vistoria técnica — P07 |
| CIA (Conformidade Inatendida) | encaminha para extinção | Extinção via `LicenciamentoCidadaoExtincaoRN` |

---

## 7. Síntese das Decisões de Modelagem

A tabela abaixo consolida as principais decisões de design do BPMN e as justificativas técnicas e de negócio de cada uma:

| Decisão | Justificativa |
|---|---|
| 4 raias (Cidadão, RT, Proprietário, Sistema) | Reflete a separação real de responsabilidades: cada ator possui credenciais próprias, acessa o sistema em momentos independentes e tem impacto jurídico distinto no processo |
| Wizard com persistência no campo `passo` | O backend Java EE é stateless — toda a continuidade de sessão de formulário é garantida pelo banco relacional, sem memória no servidor |
| Gateway exclusivo após Etapa 1 para RT | A obrigatoriedade do RT é uma regra de negócio legal, não uma regra técnica. Expô-la como gateway torna o código e o processo igualmente compreensíveis |
| Gateway paralelo para aceites de RT e Proprietário | Os aceites são assíncronos por natureza — o BPMN não pode impor uma ordem onde não existe uma |
| End Event Terminate para RT recusou | A recusa do RT bloqueia o processo sem ação automática de desbloqueio — o fim do token representa corretamente a paralisia do fluxo |
| Isenção verificada antes de inviabilidade | A isenção e a inviabilidade são condições independentes, verificadas em sequência por prioridade de impacto no fluxo |
| Número do licenciamento gerado na submissão | O número público é o identificador formal do protocolo — deve existir somente quando o processo é formalmente iniciado (submissão), nunca durante o rascunho |
| Arquivos somente no Alfresco, `identificadorAlfresco` no BD | Separação de responsabilidades: BD relacional para dados estruturados e consultáveis, ECM para conteúdo binário versionado e auditável |
| Todos os marcos em `CBM_LICENCIAMENTO_MARCO` | Rastreabilidade completa e imutável do ciclo de vida — o marco é append-only, nunca sobrescrito |
| `SimNaoBooleanConverter` em campos Boolean | Compatibilidade com o esquema de banco legado (`'S'/'N'`) sem expor essa conversão às camadas superiores — o Java vê `Boolean`, o SQL vê `CHAR(1)` |

---

## 8. Estados do Licenciamento Cobertos pelo P03

```
RASCUNHO
  └─ (RU aceita o termo em Etapa 7 → submissão bem-sucedida)
      └─ AGUARDANDO_ACEITE
          ├─ (todos RT e Proprietários aceitaram + isencao = true)
          │   └─ AGUARDANDO_PAGAMENTO  →  saída P03 para processo de pagamento
          ├─ (todos aceitaram + inviabilidade técnica detectada)
          │   └─ ANALISE_INVIABILIDADE_PENDENTE  →  saída P03 para deliberação CBM-RS
          └─ (todos aceitaram + fluxo padrão)
              └─ AGUARDANDO_DISTRIBUICAO  →  SAÍDA PRINCIPAL P03 → entrada P04
```

---

*Fim do documento descritivo — P03: Wizard de Nova Solicitação de Licenciamento*
