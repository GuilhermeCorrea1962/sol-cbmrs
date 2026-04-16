# Texto Descritivo do Fluxo BPMN — P02: Cadastro de Usuário / Responsável Técnico
## Stack Atual (Java EE 7 / WildFly / arqjava4)

**Documento de referência:** `SOL_CBM_RS_Processo_P02_StackAtual.bpmn`
**Requisitos de origem:** `Requisitos_P02_CadastroUsuario_StackAtual.md`

---

## 1. Visão Geral da Modelagem

O Processo P02 governa o ciclo completo de cadastro do **Responsável Técnico (RT)** no sistema SOL/CBM-RS. Ele é composto por duas jornadas com atores distintos, modeladas em um único pool com quatro raias:

| Jornada | Ator | Objetivo |
|---|---|---|
| **J1 — Autoatendimento** | Cidadão (RT) | Criar perfil profissional, anexar documentos e submeter para análise |
| **J2 — Back-office** | Analista CBM | Assumir, analisar e decidir sobre o cadastro submetido |

As duas jornadas são **desacopladas**: J1 não aciona J2 diretamente. A comunicação ocorre exclusivamente pelo campo `status` da tabela `CBM_USUARIO`. Quando J1 finaliza com sucesso, o status muda para `ANALISE_PENDENTE(1)`; o analista enxerga esse cadastro em sua fila de trabalho ao acessar o módulo administrativo.

O diagrama tem **30 elementos de fluxo**, **49 sequence flows**, **6 anotações de regras de negócio** e cobre **14 regras de negócio** (RN-P02-01 a RN-P02-14).

---

## 2. Pool e Raias — Arquitetura do Diagrama

O BPMN está estruturado em **1 pool** com **4 raias horizontais** (lanes):

| Raia | Ator / Sistema | y no diagrama | Responsabilidade |
|---|---|---|---|
| `Lane_RT` | Responsável Técnico — Frontend Angular (J1) | y=0..380 | Interações do cidadão: formulários, uploads, submissão |
| `Lane_IDP` | IdP Estadual — PROCERGS / SOE | y=380..570 | Autenticação federada SSO; emissão do token Bearer |
| `Lane_BE` | Backend Java EE — WildFly · JAX-RS · EJB | y=570..900 | Regras de negócio, persistência, notificações |
| `Lane_AN` | Analista CBM — Frontend Angular (J2) | y=900..1300 | Back-office: assumir análise, julgar documentos, registrar decisão |

**Por que uma única pool com quatro raias e não dois pools separados para J1 e J2?**
J1 e J2 compartilham o mesmo backend (mesma aplicação Java EE, mesmo banco de dados) e a mesma infra de autenticação (IdP PROCERGS). Usar dois pools implicaria Message Flows entre pools, o que criaria falsa impressão de que os processos se comunicam por mensagens em tempo real — o que não ocorre. A separação em raias dentro de um único pool reflete com precisão que ambas as jornadas operam sobre o mesmo sistema, desacopladas apenas pelo estado do banco de dados.

**Por que a raia `Lane_BE` é compartilhada entre J1 e J2?**
Todos os endpoints REST do P02 pertencem à mesma aplicação WildFly. O Backend não tem raias separadas por jornada — os EJBs `UsuarioRN`, `UsuarioConclusaoCadastroRN` e `AnaliseCadastroRN` coexistem no mesmo container. As tasks de BE para J1 são posicionadas na parte superior da raia (y≈635) e as de J2 na parte inferior (y≈790), tornando a divisão visual clara sem introduzir ambiguidade arquitetural.

**Por que a `Lane_IDP` existe apenas para J1 e não para J2?**
A autenticação SOE de J2 é idêntica à de J1 (mesmo IdP, mesmo fluxo OAuth2 Implicit). Repetir o fluxo de autenticação em J2 tornaria o diagrama redundante sem acrescentar informação. O evento de início `SE_J2` assume implicitamente que o analista já está autenticado.

---

## 3. Jornada J1 — Responsável Técnico (Autoatendimento)

### 3.1 Evento de Início: SE_J1

**O que representa:** O cidadão abre o sistema SOL/CBM-RS no navegador. É o momento em que o processo P02 se inicia do ponto de vista do RT.

**Por que assim:** O evento de início simples (sem gatilho externo) reflete que o cadastro é iniciado por vontade própria do cidadão, sem convite ou notificação prévia. Qualquer pessoa pode acessar e tentar se cadastrar — não há pré-condição de perfil ou cadastro anterior.

---

### 3.2 Fase 0 — Autenticação SOE (T_RT_001, T_IDP_001, T_IDP_002)

**Elementos:** `T_RT_001` (userTask, Lane_RT) → `T_IDP_001` (serviceTask, Lane_IDP) → `T_IDP_002` (serviceTask, Lane_IDP)

**O que representa:**

`T_RT_001` — O usuário abre o Angular SPA. O `OAuthService` (library `angular-oauth2-oidc`) detecta que não há token válido em `localStorage[appToken]` e redireciona o navegador para o endpoint de autorização do IdP PROCERGS: `meu.rs.gov.br/oauth2/authorize?response_type=token&client_id=SOLCBM&scope=openid+profile`.

`T_IDP_001` — O IdP recebe as credenciais do cidadão (usuário/senha) e verifica: usuário ativo, senha correta, conta não bloqueada. Se já existe sessão SSO ativa (cookie de sessão válido), o IdP executa este passo de forma transparente, sem exibir a tela de login.

`T_IDP_002` — O IdP gera o `access_token` JWT com os claims do usuário: `sub` (ID SOE), `name` (nome completo), `cpf` (claim customizado PROCERGS), `email`, `roles` (perfis atribuídos). O token é retornado via redirect para a SPA no fragmento da URL: `#access_token=<jwt>&token_type=bearer&expires_in=3600`. O Angular extrai o token do fragmento e persiste em `localStorage[appToken]`.

**Por que separar T_IDP_001 e T_IDP_002?**
Validar credenciais (verificar identidade) e emitir token (gerar prova de identidade) são operações conceitualmente distintas. A separação evidencia que o IdP tem duas responsabilidades: autenticação e autorização. Permite também documentar nos elementos o que cada fase produz: T_IDP_001 produz uma sessão válida; T_IDP_002 produz o token Bearer que a aplicação SOL usará em todas as requisições subsequentes.

**Por que o fluxo cruza de Lane_RT para Lane_IDP e volta?**
O fluxo de sequência descendo de `T_RT_001` para `T_IDP_001` cruza a fronteira de raia, representando visualmente que a autenticação ocorre em um sistema externo (meu.rs.gov.br), fora do controle do SOL/CBM-RS. A subida de volta de `T_IDP_002` para `T_RT_002` indica que, após a autenticação, o controle retorna para o frontend Angular — o token agora está disponível e as chamadas ao backend podem começar.

**Papel do backend neste momento:**
Cada requisição REST ao WildFly chega com `Authorization: Bearer {token}`. A anotação `@SOEAuthRest` (arqjava4) intercepta a requisição, valida o token com o IdP e popula `SessionMB.getUser()` e `CidadaoSessionMB.getCidadaoED()` com os dados do usuário. O IdP é consultado em cada requisição — o SOL não armazena senhas nem gerencia sessões próprias.

---

### 3.3 Fase 1 — Consulta e Bifurcação (T_RT_002, T_BE_002, GW_RT_001)

**Elementos:** `T_RT_002` (userTask) → `T_BE_002` (serviceTask) → `GW_RT_001` (exclusive gateway)

**O que representa:**

`T_RT_002` — Com o token disponível, o Angular extrai o CPF dos claims OIDC e dispara automaticamente `GET /usuarios/{cpf}`. O header `Authorization: Bearer {token}` é injetado pelo `HttpAuthorizationInterceptor` em toda requisição cujo URL contém `AppSettings.baseUrl`. O frontend aguarda a resposta para decidir o próximo passo.

`T_BE_002` — `UsuarioRN.consultaPorCpf(String cpf)`, anotado com `@TransactionAttribute(SUPPORTS)`. A transação SUPPORTS é adequada aqui: é uma leitura pura; se já existir uma transação aberta, participa; caso contrário, não abre uma nova (evita overhead). O método consulta `CBM_USUARIO` via `UsuarioBD`, carrega todas as coleções associadas (graduações, especializações, endereços, arquivo RG), aplica o workaround de fuso horário em `dtNascimento.set(Calendar.HOUR, 12)` para evitar problema de conversão UTC→BRT, e consulta o `InstrutorRN` para preencher dados de credenciamento (se o CPF corresponde a um instrutor vinculado). Retorna o `Usuario` DTO completo ou null (→ 204 No Content) se o CPF não está cadastrado.

`GW_RT_001` — Gateway exclusivo com duas saídas:
- **"Não" (204 No Content):** CPF não cadastrado → `T_RT_003` (formulário novo, `POST /usuarios`)
- **"Sim" (200 OK + DTO):** CPF existe → `T_RT_004` (pré-preenche formulário, `PUT /usuarios/{id}`)

**Por que consultar o CPF antes de exibir qualquer formulário?**
Dois motivos críticos: (a) **Unicidade:** o CPF é uma chave única de negócio (`constraint` de banco — RN-P02-02). Verificar antes evita que o usuário preencha tudo e só descubra o erro ao salvar. (b) **Continuidade:** o RT que já iniciou o cadastro em outra sessão deve ver seus dados pré-preenchidos. Sem essa consulta prévia, seria impossível distinguir "novo usuário" de "usuário retornando para completar o cadastro".

**Por que o gateway é exclusivo (XOR) e não paralelo ou inclusivo?**
A resposta da consulta é binária e mutuamente exclusiva: ou o CPF existe ou não existe — nunca os dois ao mesmo tempo. O gateway exclusivo é o único elemento BPMN semanticamente correto para representar esta decisão.

---

### 3.4 Fase 2 — Formulário Novo ou Edição (T_RT_003, T_RT_004, GW_RT_002)

**Elementos:** `T_RT_003` (userTask, acima), `T_RT_004` (userTask, abaixo), `GW_RT_002` (exclusive gateway — merge)

**O que representa:**

`T_RT_003` (branch "Não" — novo cadastro): O Angular exibe o formulário em branco, pré-preenchido apenas com nome e e-mail extraídos dos claims OIDC. O cidadão preenche todos os campos obrigatórios: nome, CPF, data de nascimento, nome da mãe, e-mail, telefone principal. O status **não é enviado pelo frontend** — o backend sempre força `INCOMPLETO` ao criar (RF-U-01). Esta task está posicionada **acima** da linha central da raia RT para indicar visualmente que é o "caminho novo, divergente para cima".

`T_RT_004` (branch "Sim" — edição): O Angular recebe o `Usuario` DTO completo da consulta e pré-preenche todos os campos, incluindo: graduações com arquivos já vinculados (exibindo nome do arquivo), especializações, endereços. O `ctrDthAtu` do DTO é armazenado internamente no Angular — será enviado no próximo `PUT` para o controle de concorrência (RN-P02-01). Esta task está posicionada **abaixo** da linha central para indicar visualmente o "caminho de retorno/edição".

`GW_RT_002` — Gateway exclusivo de **merge** (convergência): reúne os dois caminhos sem nenhuma lógica adicional. A partir daqui o fluxo é idêntico para ambos os casos.

**Por que posicionar T_RT_003 acima e T_RT_004 abaixo?**
A convenção visual no BPMN de posicionar o caminho positivo/novo acima e o caminho de retorno/alternativo abaixo orienta o leitor intuitivamente. Quem vê o diagrama identifica imediatamente a bifurcação sem precisar ler os rótulos. Esta mesma convenção é aplicada consistentemente em outros gateways do processo (GW_RT_003, GW_AN_001).

**Por que usar um gateway de merge explícito (GW_RT_002) em vez de conectar T_RT_003 e T_RT_004 diretamente em T_RT_005?**
Em BPMN, ter dois incoming flows em uma task sem gateway de merge é tecnicamente válido mas semanticamente impreciso — algumas ferramentas interpretam como AND join. O gateway de merge explícito comunica com clareza: "aqui os dois caminhos convergem, e apenas um deles chega por vez". É um contrato formal de modelagem que previne ambiguidade.

---

### 3.5 Fase 3 — Salvamento de Dados Pessoais (T_RT_005, T_BE_003)

**Elementos:** `T_RT_005` (userTask) → `T_BE_003` (serviceTask)

**O que representa:**

`T_RT_005` — O cidadão confirma o preenchimento e clica em "Salvar". O Angular monta o `Usuario` DTO e envia via:
- `POST /usuarios` (novo cadastro — sem `id`)
- `PUT /usuarios/{id}` (edição — com `id` e `ctrDthAtu`)

`T_BE_003` — `UsuarioRN.incluir()` ou `UsuarioRN.alterar()`, ambos com `@TransactionAttribute(REQUIRED)`.

**Caso `POST` — `incluir()`:**
1. `usuario.setStatus(StatusCadastro.INCOMPLETO)` — força status inicial independente do que o cliente enviar
2. `BuilderUsuarioED.build(usuario)` → `UsuarioED`
3. `usuarioBD.inclui(ed)` → `INSERT INTO CBM_USUARIO` (sequência `CBM_ID_USUARIO_SEQ`)
4. `GraduacaoUsuarioRN.incluirGraduacoesUsuario(ed, lista)` — filtra itens com `graduacao.id == null` (RN-P02-13: graduações sem tipo definido são ignoradas para evitar registros inválidos)
5. `EspecializacaoUsuarioRN.incluirEspecializacoesUsuario(...)` → `CBM_ESPECIALIZACAO_USUARIO`
6. `EnderecoUsuarioRN.incluirEnderecosUsuario(...)` → `CBM_ENDERECO_USUARIO`
7. Retorna `Usuario` DTO → HTTP 201 Created

**Erro de CPF duplicado (RN-P02-02):** `PersistenceException` causada por `ConstraintViolationException` é capturada em `processaErroBD()`. Se `constraintName != null && !isEmpty` → HTTP 400 com `bundle.getMessage(USUARIO_CPF_JA_CADASTRADO, cpfFormatado, email)`.

**Caso `PUT` — `alterar()`:**
1. `usuarioBD.consulta(id)` → `UsuarioED`
2. **RN-P02-01 (controle de concorrência):** `if status != INCOMPLETO AND ed.getCtrDthAtu().compareTo(usuario.getCtrDthAtu()) != 0` → HTTP 409 CONFLICT. A verificação é **desabilitada para INCOMPLETO** porque o usuário pode ter múltiplas sessões abertas antes mesmo de ter enviado o cadastro para análise.
3. Atualiza campos do ED
4. **Algoritmo de diff de graduações (RN-P02-12):** Para cada `GraduacaoUsuarioED` no banco, busca correspondente na lista enviada por `idGraduacaoUsuario` OU `graduacao.id`. Se encontrado e alterado: atualiza (excluindo arquivo se o tipo mudou). Se não encontrado: exclui registro e arquivo. Itens novos na lista: insere via `incluirGraduacoesUsuario()` (filtrando `id == null` — RN-P02-13).
5. `usuarioBD.altera(ed)` → `UPDATE CBM_USUARIO SET ctrDthAtu = now()`
6. Retorna `Usuario` DTO com `mensagemStatus = "Alterações realizadas com sucesso."` → HTTP 200

**Por que separar T_RT_005 (ação do usuário) de T_BE_003 (processamento no servidor)?**
A separação entre raia do RT e raia do BE explicita visualmente a fronteira cliente-servidor. Quem lê o diagrama vê claramente que o salvamento não é trivial: `T_BE_003` concentra lógica de negócio complexa (concorrência, diff de graduações, constraint de CPF) que seria invisível se o endpoint fosse representado como um único elemento na raia do RT. Desenvolvedores que trabalham no backend identificam imediatamente seus pontos de responsabilidade.

**Anotação TA_001** (posicionada acima de T_BE_003): documenta RN-P02-01 e RN-P02-02 diretamente no diagrama para que o leitor não precise consultar o documento de requisitos para entender as regras mais críticas deste passo.

---

### 3.6 Fase 4A — Upload do Documento RG (T_RT_006, T_BE_004)

**Elementos:** `T_RT_006` (userTask) → `T_BE_004` (serviceTask)

**O que representa:**

`T_RT_006` — O cidadão seleciona seu documento de identidade (RG, CNH ou equivalente) no dispositivo. O Angular envia o arquivo via `multipart/form-data`:
- `POST /usuarios/{idUsuario}/arquivo-rg` (novo upload)
- `PUT /usuarios/{idUsuario}/arquivo-rg` (substituição)

`T_BE_004` — `UsuarioRN.incluirArquivoRG()` ou `alterarArquivoRG()`.

**`incluirArquivoRG()`:**
1. `usuarioBD.consulta(idUsuario)` → `UsuarioED`
2. **RN-P02-04:** `if usuarioED.getArquivoRG() != null` → HTTP 400 + `USUARIO_ARQUIVO_ERRO_DUPLICADO`. A verificação de duplicata impede que o endpoint POST seja chamado duas vezes por engano (ex: duplo clique), evitando registros órfãos de arquivo.
3. `arquivoRN.incluirArquivo(inputStream, nomeArquivo, TipoArquivo.USUARIO)` → persiste binário em `CBM_ARQUIVO`
4. `usuarioED.setArquivoRG(arquivoED)`
5. `usuarioBD.altera(usuarioED)` → `UPDATE CBM_USUARIO SET NRO_INT_ARQUIVO_RG = ?`
6. Retorna `Arquivo` DTO `{id, nomeArquivo}` → HTTP 201

**`alterarArquivoRG()`:** Reutiliza o `ArquivoED` existente — apenas atualiza o binário e o nome.

**CRITICIDADE:** `arquivoRG` é verificado por `concluirCadastro()` (RN-P02-03). Se nulo quando o usuário clicar em "Enviar para análise", o status retornará `INCOMPLETO`. Esta task é também o **destino do loop-back** de `T_RT_010` (ver seção 3.9).

**Por que o upload de arquivo é uma tarefa separada do salvamento dos dados pessoais?**
Dois motivos técnicos: (a) Arquivos binários exigem `Content-Type: multipart/form-data`, que não pode ser combinado com JSON no mesmo request. (b) O upload pode falhar independentemente dos dados textuais (arquivo grande, conexão instável). Separar os dois permite que o usuário reenvie somente o arquivo sem precisar reenviar os dados pessoais já salvos com sucesso.

---

### 3.7 Fase 4B — Graduações e Comprovantes (T_RT_007, T_BE_005)

**Elementos:** `T_RT_007` (userTask) → `T_BE_005` (serviceTask)

**O que representa:**

`T_RT_007` — O cidadão informa suas graduações profissionais (CREA, CRM, OAB, CAU, etc.):
- Seleciona o tipo de graduação (`CBM_GRADUACAO`)
- Informa o número do registro profissional (`idProfissional`)
- Informa o estado emissor (`estadoEmissor`)
- Faz upload do comprovante via `POST /usuarios/{id}/graduacoes/{idGraduacao}/arquivo`
- Pode substituir um comprovante via `PUT /usuarios/{id}/graduacoes/{idGraduacao}/arquivo`

`T_BE_005` — Processa os uploads de comprovante de graduação:

**`incluirArquivoDocProfissional()`:**
1. `GraduacaoUsuarioRN.consulta(idUsuario, idGraduacao)` → `GraduacaoUsuarioED`
2. **RN-P02-04:** `if getArquivoIdProfissional() != null` → HTTP 400 (duplicado)
3. `arquivoRN.incluirArquivo(..., TipoArquivo.USUARIO)` → `CBM_ARQUIVO`
4. `graduacaoUsuarioED.setArquivoIdProfissional(arquivoED)`
5. `graduacaoUsuarioRN.altera(ed)` → `UPDATE CBM_GRADUACAO_USUARIO`
6. Retorna `Arquivo` DTO → HTTP 201

**Algoritmo de diff de graduações (RN-P02-12)** — executado via `PUT /usuarios/{id}`:
Para cada `GraduacaoUsuarioED` no banco, busca correspondente na lista recebida:
- Encontrado sem mudança → mantém sem alteração
- Encontrado com mudança em `estadoEmissor`, `idProfissional` ou tipo de graduação → atualiza via `compararGraduacoes()`; se o tipo mudou (`idGraduacaoUsuario` difere de `ed.getId()`), o arquivo antigo é excluído primeiro
- Não encontrado no banco → exclui o registro e o arquivo vinculado (`arquivoIdProfissional`)
- Novo na lista (não existe no banco) → insere via `incluirGraduacoesUsuario()` filtrando `graduacao.id == null` (RN-P02-13)

**CRITICIDADE:** Para **cada** `GraduacaoUsuarioED` sem `arquivoIdProfissional`, `concluirCadastro()` retornará `INCOMPLETO` (RN-P02-03). Este é o segundo bloqueador de submissão.

**Por que o algoritmo de diff e não apagar e recriar tudo?**
Recriar todas as graduações a cada `PUT` destruiria os uploads já realizados: um `GraduacaoUsuarioED` deletado leva consigo a referência ao `ArquivoED` do comprovante, que seria perdida permanentemente. O diff garante que apenas as alterações efetivas sejam aplicadas, preservando os arquivos já enviados com sucesso.

**Anotação TA_003** (posicionada acima de T_BE_005): documenta RN-P02-12 e RN-P02-13 diretamente no diagrama.

---

### 3.8 Fase 4C — Especializações e Endereços (T_RT_008, T_BE_006)

**Elementos:** `T_RT_008` (userTask) → `T_BE_006` (serviceTask)

**O que representa:**

`T_RT_008` — O cidadão informa especializações adicionais (pós-graduações, cursos técnicos específicos em PPCI) e endereços de atuação profissional.
- Especialização: seleciona tipo, opcionalmente faz upload de comprovante via `POST/PUT /usuarios/{id}/especializacoes/{idEsp}/arquivo`
- Endereço: informa tipo (`TipoEndereco` enum) e indica se deseja usar endereço residencial (`usarResidencial`)
- Ambos salvos via `PUT /usuarios/{id}`

`T_BE_006` — `EspecializacaoUsuarioRN.alterarEspecializacoesUsuario()` + `EnderecoUsuarioRN.alterarEnderecosUsuario()`:

Especializações: lógica análoga ao diff de graduações — compara lista recebida vs banco, insere/atualiza/exclui conforme necessário. Tabela `CBM_ESPECIALIZACAO_USUARIO` (sequência `CBM_ID_ESPEC_USUARIO_SEQ`). Comprovante de especialização: `incluirArquivoEspecializacao()` com mesma regra de duplicata (RN-P02-04).

Endereços: `EnderecoUsuarioRN.alterarEnderecosUsuario()`. O campo `IND_USAR_RESIDENCIAL` é persistido como `CHAR(1)` com valores `'S'`/`'N'` via `SimNaoBooleanConverter` (JPA `AttributeConverter<Boolean, String>`). O campo `endereco` aponta para `CBM_ENDERECO` (tabela de logradouros com CEP). Tabela: `CBM_ENDERECO_USUARIO` (sequência `CBM_ID_ENDERECO_USUARIO_SEQ`).

**IMPORTANTE — Especializações NÃO bloqueam a submissão:**
`UsuarioConclusaoCadastroRN.concluirCadastro()` verifica apenas `arquivoRG` e os arquivos de cada graduação (RN-P02-03). Especializações são dados complementares — o RT pode não ter especialização formal e ainda assim ser credenciado. Esta assimetria entre graduação (obrigatória) e especialização (opcional) reflete a regulamentação técnica do CBM-RS.

**Por que separar especializações e endereços de graduações em tarefas distintas?**
Embora todos passem pelo mesmo endpoint `PUT /usuarios/{id}`, os EJBs responsáveis são diferentes (`EspecializacaoUsuarioRN`, `EnderecoUsuarioRN`, `GraduacaoUsuarioRN`). A separação em tarefas visuais distintas no BPMN mapeia cada task a um contexto de negócio claro e facilita a manutenção: um desenvolvedor que precise modificar a lógica de endereços sabe exatamente qual tarefa do BPMN corresponde ao seu código.

---

### 3.9 Fase 5 — Submissão e Verificação de Completude (T_RT_009, T_BE_007, GW_RT_003)

**Elementos:** `T_RT_009` (userTask) → `T_BE_007` (serviceTask) → `GW_RT_003` (exclusive gateway)

**O que representa:**

`T_RT_009` — O cidadão clica em "Enviar para análise". O Angular envia `PATCH /usuarios/{id}` (sem body — apenas o path param é necessário). O verbo PATCH é semanticamente correto: não substitui o recurso inteiro, apenas transiciona seu estado.

`T_BE_007` — `UsuarioConclusaoCadastroRN.concluirCadastro(Long idUsuario)`. Esta é a **operação mais crítica da Jornada J1**, anotada com `@Permissao(desabilitada = true)` (qualquer usuário autenticado pode executar — não requer perfil administrativo):

1. `statusCadastro = StatusCadastro.ANALISE_PENDENTE` — valor inicial otimista
2. `usuarioBD.consulta(idUsuario)` → `UsuarioED` (com join fetch do `arquivoRG`)
3. **Verificação RG (RN-P02-03, 1ª condição):** `if arquivoRG == null → statusCadastro = INCOMPLETO`
4. **Verificação graduações (RN-P02-03, 2ª condição):** Para cada `GraduacaoUsuarioED`: `if getArquivoIdProfissional() == null → statusCadastro = INCOMPLETO`
5. `usuarioED.setStatus(statusCadastro)` + `usuarioED.setMensagemStatus(null)` (limpa justificativa de reprovação anterior, se existir)
6. `usuarioBD.altera(usuarioED)` → `UPDATE CBM_USUARIO`
7. `notificacaoRN.notificar(usuarioED, statusMessage, ContextoNotificacaoEnum.CADASTRO)` — notificação interna, **SEM e-mail**
8. Se `statusCadastro == ANALISE_PENDENTE`: verifica `InstrutorED` por CPF; se status `APROVADO` ou `VENCIDO` → `instrutorHistoricoRN.incluirEdicao(instrutor)` (rastreia histórico de edição do credenciamento)
9. Retorna `Status` DTO: `{statusCadastro, ctrDthAtu, mensagem}` → HTTP 200

O campo `ctrDthAtu` retornado é o novo timestamp gerado pelo `UPDATE` — o Angular atualiza seu valor interno sem precisar fazer uma nova chamada `GET`.

`GW_RT_003` — Gateway exclusivo com duas saídas:
- **"INCOMPLETO":** → `T_RT_010` (exibe pendências + loop-back)
- **"ANALISE_PENDENTE":** → `T_RT_011` (confirmação de sucesso) → `EE_J1`

**Por que a verificação de completude é feita no servidor e não no cliente?**
Segurança e confiabilidade. Se a validação fosse apenas no Angular, um cliente malicioso poderia enviar `PATCH /usuarios/{id}` diretamente via `curl`, forçando o status `ANALISE_PENDENTE` sem os documentos necessários. O servidor re-verifica tudo independentemente do que o cliente faz — o status resultante é uma decisão do servidor, não uma afirmação do cliente.

**Por que o `PATCH` e não o `PUT`?**
O verbo `PUT` substitui o recurso completo. `PATCH` aplica uma modificação parcial. Aqui apenas o campo `status` (e indiretamente `mensagemStatus` e `ctrDthAtu`) é modificado — o recurso `Usuario` completo permanece intacto. O uso de `PUT` para esta operação seria semanticamente incorreto e poderia confundir desenvolvedores futuros que tentassem entender o protocolo da API.

**Anotação TA_002** (posicionada acima de T_BE_007): documenta RN-P02-03 e RN-P02-04 diretamente no diagrama.

---

### 3.10 Fase 6 — Loop de Correção e Confirmação (T_RT_010, T_RT_011, EE_J1)

**Elementos:** `T_RT_010` (userTask, acima), `T_RT_011` (userTask, abaixo), `EE_J1` (end event)

**O que representa:**

`T_RT_010` (branch INCOMPLETO — posicionado acima): O Angular exibe as pendências identificadas pelo servidor: "Documento de identidade não enviado" e/ou "Comprovante da graduação [X] não enviado". O fluxo de saída `SF_024` retorna diretamente para `T_RT_006` (upload do RG) via uma seta retrógrada roteada pelo **topo do diagrama** (y=20, acima de `Lane_RT`). Este loop-back é o único fluxo que percorre o diagrama da direita para a esquerda na Jornada J1.

**Por que o loop-back vai para T_RT_006 e não para o início?**
Eficiência para o usuário. Ele já preencheu seus dados pessoais (T_RT_005) e esses foram persistidos com sucesso. Forçar um retorno ao início significaria re-processar passos já concluídos. O retorno direto para T_RT_006 permite que o usuário complete apenas o que está faltando — os documentos ausentes — sem redigitar nada.

`T_RT_011` (branch ANALISE_PENDENTE — posicionado abaixo): O Angular exibe a tela de confirmação com a mensagem `bundle["usuario.cadastro.status.ANALISE_PENDENTE"]` = "Seu cadastro foi enviado para análise." O cidadão é informado de que deve aguardar e que receberá uma notificação com o resultado.

`EE_J1` — A Jornada J1 termina. O cidadão não tem mais ação a tomar no processo P02 neste momento. O campo `CBM_USUARIO.status = ANALISE_PENDENTE(1)` e o cadastro aparecerá na fila do analista.

---

## 4. Transição J1 → J2: Desacoplamento via Banco de Dados

**Elemento:** `TA_006` (text annotation) associada a `SE_J2`

Este é o ponto de maior importância arquitetural do processo P02: J1 e J2 são **completamente desacopladas no nível de aplicação**. Não existe nenhum evento de mensagem, nenhuma chamada de serviço, nenhuma fila assíncrona que notifique ativamente o analista quando um cadastro é submetido.

O mecanismo é puramente relacional: quando `concluirCadastro()` muda `CBM_USUARIO.status` para `ANALISE_PENDENTE`, este registro passa a ser retornado pela query de `listarCadastrosEmAnalise()` — mas somente quando o analista decide acessar o sistema e listar sua fila.

**Por que modelar este desacoplamento com uma anotação e não com um Message Flow?**
Um Message Flow entre `EE_J1` e `SE_J2` implicaria comunicação direta em tempo real entre os dois processos — o que não ocorre. O Message Flow criaria uma dependência formal que não existe no código. A anotação de texto é o recurso BPMN correto para documentar uma relação não-sequencial e assíncrona: esclarece o comportamento sem distorcer a semântica do fluxo.

---

## 5. Jornada J2 — Analista CBM (Back-office)

### 5.1 Evento de Início: SE_J2

**O que representa:** O analista do CBM-RS acessa o sistema SOL com suas credenciais SOE e navega para o módulo administrativo de análise de cadastros. A autenticação SOE ocorre da mesma forma que em J1 (não está representada para evitar repetição).

**Pré-condição:** O analista deve ter a permissão `VERIFICARCADASTRO/LISTAR` atribuída ao seu perfil no IdP estadual. Sem ela, o endpoint `GET /adm/analise-cadastros/em-analise` retornará HTTP 403.

---

### 5.2 Fase 7 — Listar e Selecionar Cadastros (T_AN_001, T_BE_008, T_AN_002)

**Elementos:** `T_AN_001` (userTask) → `T_BE_008` (serviceTask) → `T_AN_002` (userTask)

**O que representa:**

`T_AN_001` — O analista acessa a tela de análise de cadastros. O Angular chama `GET /adm/analise-cadastros/em-analise`. Esta task é também o **destino do loop-back** de `GW_AN_003` quando uma análise é cancelada.

`T_BE_008` — `AnaliseCadastroRN.listarCadastrosEmAnalise(AnaliseCadastroED)`, `@Permissao(objeto="VERIFICARCADASTRO", acao="LISTAR")`, `@TransactionAttribute(SUPPORTS)`.

O filtro é construído automaticamente no recurso REST antes de chamar o EJB:
```java
filtro.setIdUsuarioSoe(Long.parseLong(sessionMB.getUser().getId()));
filtro.setStatus(StatusAnalise.EM_ANALISE);
```
Este filtro **duplo** é fundamental: (1) `idUsuarioSoe` garante que cada analista vê apenas **sua própria fila de trabalho** — os cadastros que ele mesmo assumiu. (2) `StatusAnalise.EM_ANALISE` garante que somente análises em andamento são exibidas, excluindo as já concluídas (APROVADO, REPROVADO, CANCELADO).

Retorno: `List<Cadastro>` com campos: `id`, `nome`, `cpf`, `email`, `ctrDthInc`, `ctrDthAtu`, `possuiGraduacao`, `status`, `idAnalise`.

`T_AN_002` — O analista visualiza a lista e seleciona um cadastro. Esta é uma ação puramente de interface — não envolve chamada ao backend. O analista pode priorizar pelos metadados visíveis (data de submissão, indicador de graduação).

**Por que o filtro por `idUsuarioSoe` e não exibir todos os cadastros em análise?**
Organização operacional e controle de responsabilidade. Se todos os analistas vissem a mesma fila global, seria inevitável que dois analistas trabalhassem simultaneamente no mesmo cadastro — ou que ninguém trabalhasse em nenhum porque "outro vai pegar". O modelo de fila individual (cada analista vê o que assumiu) garante rastreabilidade clara: cada análise tem um responsável formal, identificado pelo `idUsuarioSoe` armazenado em `CBM_ANALISE_CADASTRO`.

---

### 5.3 Fase 8 — Assumir Análise (T_AN_003, T_BE_009)

**Elementos:** `T_AN_003` (userTask) → `T_BE_009` (serviceTask)

**O que representa:**

`T_AN_003` — O analista clica em "Assumir análise". O Angular envia `POST /adm/analise-cadastros` com o `Cadastro` DTO: `{id, status, ctrDthAtu}`. O `ctrDthAtu` foi recebido na listagem anterior e é reenviado agora para controle de concorrência.

`T_BE_009` — `AnaliseCadastroRN.incluirAnaliseCadastro(Cadastro)`, `@Permissao(objeto="VERIFICARCADASTRO", acao="EDITAR")`, `@TransactionAttribute(REQUIRED)`. Esta é a operação mais complexa de J2:

**RN-P02-05 — Validação de campos obrigatórios:**
`id`, `status` e `ctrDthAtu` não podem ser nulos → HTTP 400. Esta validação impede requisições malformadas antes de qualquer acesso ao banco.

**RN-P02-06 — Controle de concorrência na abertura:**
```java
if (ed.getCtrDthAtu().compareTo(cadastro.getCtrDthAtu()) != 0)
    throw new WebApplicationRNException(..., 409 CONFLICT);
```
Se dois analistas tentarem assumir o mesmo cadastro simultaneamente, o que chegar segundo verá `ctrDthAtu` divergente (o primeiro já atualizou o registro) e receberá HTTP 409.

**RN-P02-07 — Registro criado apenas para ANALISE_PENDENTE:**
Se `usuario.status == ANALISE_PENDENTE`: cria novo `AnaliseCadastroED` em `CBM_ANALISE_CADASTRO`. Se o cadastro já está `EM_ANALISE` (foi assumido antes, cancelado e re-assumido), **não cria novo registro** — reutiliza o contexto existente. Em ambos os casos a notificação é enviada e o status é atualizado.

**RN-P02-08 — Vinculação ao analista:**
```java
analiseED.setIdUsuarioSoe(Long.parseLong(sessionMB.getUser().getId()));
analiseED.setNomeUsuario(sessionMB.getUser().getNome());
```
O registro de análise "pertence" formalmente ao analista que o assumiu.

**RN-P02-09 — Notificação interna ao cidadão (sem e-mail):**
`notificacaoRN.notificar(usuarioED, msg, ContextoNotificacaoEnum.CADASTRO)` com `enviarEmail = false`. O cidadão é informado no painel interno de que seu cadastro está sendo analisado, mas não recebe e-mail neste momento — o e-mail só é enviado quando a decisão final for proferida.

Retorno: HTTP 201 + header `Location: /adm/analise-cadastros/{idRetorno}`.

**Anotação TA_004** (posicionada abaixo de T_BE_009): documenta RN-P02-05 a RN-P02-09 diretamente no diagrama.

---

### 5.4 Fase 9 — Análise dos Documentos e Decisão (T_AN_004, GW_AN_001)

**Elementos:** `T_AN_004` (userTask), `GW_AN_001` (exclusive gateway — 3 saídas)

**O que representa:**

`T_AN_004` — O analista visualiza em detalhe o cadastro assumido. O Angular chama `GET /adm/analise-cadastros/{id}` (`@Permissao(VERIFICARCADASTRO, CONSULTAR)`) e oferece acesso aos documentos via downloads:
- `GET /usuarios/{id}/arquivo-rg` — documento de identidade
- `GET /usuarios/{id}/graduacoes/{g}/arquivo` — comprovante de cada graduação
- `GET /usuarios/{id}/especializacoes/{e}/arquivo` — comprovante de especialização

O analista avalia: autenticidade do RG, validade dos registros profissionais (número de CREA/CRM/etc. no sistema do conselho), consistência dos dados pessoais com os documentos. Esta é uma **decisão humana** — o sistema SOL não implementa nenhuma automação de análise documental.

`GW_AN_001` — Gateway exclusivo com 3 saídas, refletindo exatamente os valores do enum `StatusAnalise`:
- **APROVADO** (saída acima) → `T_AN_005`
- **REPROVADO** (saída ao centro) → `T_AN_006`
- **CANCELAR** (saída abaixo) → `T_AN_007`

**Por que 3 saídas e não 2 (aprovado/reprovado)?**
O cancelamento é uma necessidade operacional real: analistas podem assumir o cadastro errado, precisar liberar para outro analista ou precisar de mais tempo. Sem o cancelamento, um cadastro "preso" em `EM_ANALISE` associado a um analista ausente ficaria indefinidamente bloqueado.

**Por que a task T_AN_004 pertence à raia do Analista e não à raia do BE?**
A análise de documentos é uma **decisão humana**, não automatizável. Colocá-la na raia do analista comunica exatamente isso: o sistema apenas apresenta os dados; o julgamento é do profissional do CBM. Uma `serviceTask` na raia do BE implicaria automação — o que seria semanticamente incorreto.

---

### 5.5 Fase 10 — Confirmação da Decisão (T_AN_005, T_AN_006, T_AN_007, GW_AN_002)

**Elementos:** `T_AN_005` (acima), `T_AN_006` (centro), `T_AN_007` (abaixo), `GW_AN_002` (merge)

**O que representa:**

`T_AN_005` (APROVADO): O Angular exibe tela de confirmação. Campos necessários: nenhum adicional — a aprovação não requer justificativa.

`T_AN_006` (REPROVADO): O Angular exibe campo de texto para preenchimento da **justificativa obrigatória**. A justificativa é o único campo adicional entre as três branches. Ela será exibida ao cidadão como `mensagemStatus` na tela de status do seu cadastro — ele precisa saber exatamente o motivo para poder corrigir e resubmeter.

`T_AN_007` (CANCELAR): O Angular exibe tela de confirmação do cancelamento. O analista confirma que deseja liberar o cadastro de volta para a fila `ANALISE_PENDENTE`. Nenhum campo adicional.

`GW_AN_002` — Gateway exclusivo de merge: converge os três caminhos antes do registro formal da decisão no backend.

**Por que separar as tasks de confirmação de cada decisão antes do registro no backend?**
Porque cada decisão tem uma interface de usuário diferente (T_AN_006 tem campo de justificativa, T_AN_005 e T_AN_007 não têm). Representar as três como tarefas distintas deixa claro no BPMN que existem três formulários de confirmação distintos — informação relevante para o desenvolvedor do frontend que implementará cada tela.

**Por que o merge com GW_AN_002 em vez de conectar diretamente T_AN_005/006/007 em T_AN_008?**
A mesma razão da GW_RT_002: o merge explícito comunica com clareza que os três caminhos convergem aqui e que T_AN_008 recebe exatamente um fluxo de cada vez. Evita ambiguidade de interpretação do diagrama.

---

### 5.6 Fase 11 — Registro da Decisão (T_AN_008, T_BE_010)

**Elementos:** `T_AN_008` (userTask) → `T_BE_010` (serviceTask)

**O que representa:**

`T_AN_008` — O analista clica em "Confirmar". O Angular envia `PUT /adm/analise-cadastros/{id}` com `AnaliseCadastro` DTO: `{status: StatusAnalise, justificativa: String}`.

`T_BE_010` — `AnaliseCadastroRN.alterarStatusAnaliseCadastro(Long id, AnaliseCadastro)`, `@Permissao(VERIFICARCADASTRO, EDITAR)`, `@TransactionAttribute(REQUIRED)`:

**RN-P02-10 — Verificação de autoria:**
```java
boolean isAnalista = analiseED.getIdUsuarioSoe().toString()
                       .equals(sessionMB.getUser().getId());
boolean isSupervisor = sessionMB.hasPermission("CENTRALADM", "EDITAR");
if (!isAnalista && !isSupervisor) → throw WebApplicationRNException(403 FORBIDDEN)
```
Apenas o analista que assumiu a análise ou um supervisor com perfil `CENTRALADM/EDITAR` pode alterar o resultado. Isso previne que analista A modifique análises abertas pelo analista B — o que seria uma violação de responsabilidade formal.

**RN-P02-11 — Mapeamento `StatusAnalise` → `StatusCadastro` + e-mail:**

| StatusAnalise (entrada) | StatusCadastro (resultado) | Envia e-mail |
|---|---|---|
| CANCELADO | ANALISE_PENDENTE(1) | Não |
| APROVADO | APROVADO(3) | Sim |
| REPROVADO | REPROVADO(4) | Sim |
| EM_ANALISE | EM_ANALISE(2) | Não |

`mudarStatusCadastro()` executa: `usuario.mensagemStatus = justificativa` + `notificacaoRN.notificar(usuario, msg, CADASTRO, enviarEmail, statusCadastro.name())`.

**Anotação TA_005** (posicionada abaixo de T_BE_010): documenta RN-P02-10 e RN-P02-11 diretamente no diagrama.

---

### 5.7 Fase 12 — Loop de Cancelamento e Resultado Final (GW_AN_003, T_AN_009, T_BE_011, EE_J2)

**Elementos:** `GW_AN_003` → `T_AN_009` + `T_BE_011` → `EE_J2`; e `GW_AN_003` → `T_AN_001` (loop-back)

**O que representa:**

`GW_AN_003` — Gateway exclusivo com duas saídas:
- **"Sim" (CANCELADO):** loop-back para `T_AN_001` — o analista volta à lista para selecionar outro cadastro
- **"Não" (APROVADO ou REPROVADO):** continua para `T_AN_009`

O loop-back `SF_046` é roteado pelo **topo da `Lane_AN`** (y=912), cruzando toda a largura do diagrama da direita para a esquerda. Este fluxo retrógrado é o único de J2 e está posicionado acima dos demais elementos para máxima visibilidade.

`T_AN_009` — O Angular exibe ao analista: "Cadastro aprovado." ou "Cadastro reprovado." com os detalhes da decisão.

`T_BE_011` — `NotificacaoRN.notificar(...)` com `enviarEmail = true` (APROVADO ou REPROVADO). O cidadão recebe:
- Notificação interna no sistema (tabela `CBM_NOTIFICACAO`)
- E-mail via SMTP PROCERGS: assunto "SOL/CBM-RS — Resultado do cadastro de RT", body com mensagem e justificativa (se reprovado)

`EE_J2` — Fim da Jornada J2. Estado final: `CBM_USUARIO.status = APROVADO(3)` ou `REPROVADO(4)`.

**Por que o loop-back vai para T_AN_001 e não para SE_J2?**
Porque o analista **já está autenticado** e **já está no módulo administrativo**. Retornar ao evento de início implicaria reconexão, re-autenticação e re-navegação — passos desnecessários e que não refletem o comportamento real do sistema. O retorno direto para a listagem de cadastros é a experiência correta: o analista simplesmente vê a lista atualizada e pode selecionar o próximo cadastro.

**Por que T_BE_011 é modelado como tarefa separada de T_BE_010?**
`T_BE_010` registra a decisão (`UPDATE CBM_ANALISE_CADASTRO` + `mudarStatusCadastro()`). `T_BE_011` representa a **notificação ao cidadão** — que conceitualmente ocorre após a decisão ser registrada. Na implementação, `notificacaoRN.notificar()` é chamado dentro de `mudarStatusCadastro()`, mas separar visualmente no BPMN deixa claro que são **duas responsabilidades distintas**: uma é interna (registro), a outra é externa (comunicação ao usuário). Isso facilita a compreensão e futura manutenção — ex: se o mecanismo de notificação mudar, o desenvolvedor sabe exatamente qual elemento do diagrama é afetado.

---

## 6. Camada de Backend — Padrão Cross-Lane

Em todo o BPMN do P02, o padrão de comunicação frontend ↔ backend segue uma convenção visual consistente:

**Descida (request):** O fluxo de sequência sai da raia do RT ou AN pela parte inferior da task e desce até a raia BE, chegando pela parte superior da task de backend correspondente.

**Subida (response):** O fluxo sai da raia BE pelo lado direito da task, vai horizontalmente até o `x` da próxima task do frontend e sobe até entrar pela parte inferior dessa task.

Este padrão — "desce reto, volta pela direita" — é aplicado em todos os 10 pares RT/AN ↔ BE do diagrama. O leitor identifica visualmente que cada par de tasks alinhadas verticalmente forma um ciclo requisição-resposta. A consistência elimina a necessidade de leitura dos rótulos para compreender o fluxo de dados.

---

## 7. Máquina de Estados do Processo P02

O P02 controla dois enums de estado interdependentes:

### 7.1 `StatusCadastro` — `CBM_USUARIO.status`

```
INCOMPLETO(0)
    │
    ├──[concluirCadastro: arquivoRG ou graduação sem arquivo]──→ INCOMPLETO(0) (permanece)
    │
    └──[concluirCadastro: todos os docs presentes]
          │
          ▼
   ANALISE_PENDENTE(1)
          │
          └──[incluirAnaliseCadastro: analista assume]
                │
                ▼
         EM_ANALISE(2)
                │
                ├──[alterarStatus: APROVADO]  ──→ APROVADO(3)          [e-mail]
                ├──[alterarStatus: REPROVADO] ──→ REPROVADO(4)         [e-mail]
                └──[alterarStatus: CANCELADO] ──→ ANALISE_PENDENTE(1)  [sem e-mail]
                                                        │
                                                        └──[loop: volta à fila J2]
```

### 7.2 `StatusAnalise` — `CBM_ANALISE_CADASTRO.status`

```
EM_ANALISE(1)
    │
    ├──→ CANCELADO(2)   → CBM_USUARIO: ANALISE_PENDENTE
    ├──→ APROVADO(3)    → CBM_USUARIO: APROVADO
    └──→ REPROVADO(4)   → CBM_USUARIO: REPROVADO
```

Cada transição de estado visível no BPMN corresponde a uma chamada de método Java específica — a rastreabilidade é bidirecional.

---

## 8. Justificativas de Modelagem

### J1 — Por que usar 1 pool e não 2 pools (J1 e J2 separados)?

J1 e J2 compartilham o mesmo banco, o mesmo backend e a mesma autenticação. Dois pools implicariam Message Flows, que representam comunicação direta entre processos — o que não existe aqui. O desacoplamento real (via banco de dados) é documentado pela anotação `TA_006`, não por Message Flows.

### J2 — Por que o Backend ocupa faixa dupla (y=635 para J1, y=790 para J2)?

As tasks de BE para J1 e J2 precisam coexistir na mesma raia (`Lane_BE`) porque pertencem ao mesmo servidor WildFly. Posicioná-las em alturas diferentes dentro da raia BE (superior para J1, inferior para J2) preserva a correspondência visual entre cada task de frontend e sua contraparte de backend sem misturar os contextos das duas jornadas.

### J3 — Por que o loop-back de T_RT_010 vai para T_RT_006 e não para GW_RT_002?

Se o loop fosse para `GW_RT_002` (antes de T_RT_005), o usuário teria que re-executar o salvamento dos dados pessoais — que já foi concluído com sucesso. O retorno direto para T_RT_006 (upload do RG) é o ponto mínimo de retomada: o usuário completa apenas o que falta (documentos), sem retrabalho.

### J4 — Por que `PATCH /usuarios/{id}` e não `PUT`?

`PUT` substitui o recurso inteiro. `PATCH` aplica modificação parcial. A operação `concluirCadastro()` modifica apenas o estado do usuário (`status`, `mensagemStatus`, `ctrDthAtu`) sem alterar nenhum dado pessoal. O uso de `PATCH` é semanticamente preciso e segue a RFC 5789.

### J5 — Por que GW_AN_001 tem 3 saídas e não GW_AN_001 bifurca e outro gateway separa?

Três saídas de um único gateway exclusivo é a forma mais limpa de representar uma decisão mutuamente exclusiva com N opções. Introduzir gateways aninhados para separar a branch de cancelamento adicionaria complexidade visual sem benefício semântico — as três saídas de `StatusAnalise` são exatamente o que existe na enumeração do código.

### J6 — Por que T_BE_011 (notificação) é separado de T_BE_010 (registro da decisão)?

Responsabilidades distintas: T_BE_010 persiste a decisão no banco (operação de escrita). T_BE_011 comunica a decisão ao cidadão (operação de saída). Separar os dois permite que o leitor entenda que a persistência e a notificação são dois efeitos colaterais distintos do processo de decisão — e que a notificação poderia ser alterada ou desacoplada no futuro sem impactar a persistência.

### J7 — Por que o filtro de `listarCadastrosEmAnalise()` inclui o `idUsuarioSoe`?

Controle de responsabilidade operacional. Cada analista tem sua própria fila de trabalho. Sem o filtro por `idUsuarioSoe`, a listagem mostraria análises de todos os analistas — causando conflitos, confusão e potencial duplicação de trabalho. O modelo de "fila individual" garante que cada análise tem um responsável formal e rastreável.

### J8 — Por que RN-P02-04 (arquivo único) impede POST duplicado e não simplesmente sobrescreve?

Sobrescrever silenciosamente poderia causar perda de dados: o arquivo anterior seria descartado sem que o usuário fosse informado. A rejeição com HTTP 400 é explícita — o usuário deve usar o endpoint `PUT` se quiser substituir, o que implica uma intenção consciente de substituição. Esta distinção semântica entre "criar" e "substituir" é fundamental para auditoria (o CBM pode querer rastrear quantas vezes um documento foi substituído).

### J9 — Por que a `Lane_IDP` existe apenas para J1?

A autenticação de J2 é idêntica à de J1 (mesmo IdP, mesmo fluxo). Repetir o fluxo de autenticação em J2 tornaria o diagrama desnecessariamente longo sem acrescentar informação nova. A convenção adotada é: o IdP aparece apenas uma vez (em J1, que é a primeira jornada descrita), e J2 assume implicitamente que o analista está autenticado ao iniciar.

---

## 9. Tabela de Rastreabilidade — BPMN × Código × RNs

| ID BPMN | Nome do Elemento | Tipo | Classe Java / Endpoint | RNs |
|---|---|---|---|---|
| SE_J1 | Início J1 | Start Event | — | — |
| T_RT_001 | Acessar frontend e iniciar autenticação | userTask | `AppComponent.configureAuth()` · `OAuthService.initImplicitFlow()` | — |
| T_IDP_001 | Validar credenciais SOE | serviceTask | IdP PROCERGS — `meu.rs.gov.br` | — |
| T_IDP_002 | Emitir access_token e claims | serviceTask | IdP PROCERGS — `meu.rs.gov.br` | — |
| T_RT_002 | Consultar cadastro por CPF | userTask | `GET /usuarios/{cpf}` · `HttpAuthorizationInterceptor` | — |
| T_BE_002 | `consultaPorCpf()` | serviceTask | `UsuarioRN.consultaPorCpf()` · `@TransactionAttribute(SUPPORTS)` | — |
| GW_RT_001 | CPF já cadastrado? | gateway | 204 vs 200 | RN-P02-02 |
| T_RT_003 | Preencher formulário novo | userTask | Angular form · `POST /usuarios` | — |
| T_RT_004 | Editar cadastro existente | userTask | Angular form · `PUT /usuarios/{id}` | RN-P02-01 |
| GW_RT_002 | Merge novo/edição | gateway | — | — |
| T_RT_005 | Salvar dados pessoais | userTask | `POST /usuarios` ou `PUT /usuarios/{id}` | RN-P02-01, 02 |
| T_BE_003 | `incluir()` / `alterar()` | serviceTask | `UsuarioRN.incluir()` · `UsuarioRN.alterar()` · `@REQUIRED` | RN-P02-01, 02, 12, 13 |
| T_RT_006 | Upload / Substituição do RG | userTask | `POST/PUT /usuarios/{id}/arquivo-rg` (multipart) | RN-P02-04 |
| T_BE_004 | `incluirArquivoRG()` / `alterarArquivoRG()` | serviceTask | `UsuarioRN.incluirArquivoRG()` · `ArquivoRN.incluirArquivo()` | RN-P02-04 |
| T_RT_007 | Gerenciar graduações e comprovantes | userTask | `POST/PUT /usuarios/{id}/graduacoes/{g}/arquivo` | RN-P02-04, 12 |
| T_BE_005 | `incluirArquivoDocProfissional()` + diff | serviceTask | `UsuarioRN.incluirArquivoDocProfissional()` · `GraduacaoUsuarioRN.alterarGraduacoesUsuario()` | RN-P02-04, 12, 13 |
| T_RT_008 | Gerenciar especializações e endereços | userTask | `POST/PUT /usuarios/{id}/especializacoes/{e}/arquivo` · `PUT /usuarios/{id}` | — |
| T_BE_006 | `EspecializacaoUsuarioRN.alterar()` + `EnderecoUsuarioRN.alterar()` | serviceTask | `EspecializacaoUsuarioRN` · `EnderecoUsuarioRN` · `SimNaoBooleanConverter` | RN-P02-04 |
| T_RT_009 | Concluir cadastro | userTask | `PATCH /usuarios/{id}` · `@Permissao(desabilitada=true)` | RN-P02-03 |
| T_BE_007 | `concluirCadastro()` | serviceTask | `UsuarioConclusaoCadastroRN.concluirCadastro()` · `@REQUIRED` | RN-P02-03, 04 |
| GW_RT_003 | Status retornado? | gateway | `Status.statusCadastro` == INCOMPLETO vs ANALISE_PENDENTE | RN-P02-03 |
| T_RT_010 | Exibir pendências (INCOMPLETO) | userTask | Angular: exibe docs faltantes + loop-back para T_RT_006 | RN-P02-03 |
| T_RT_011 | Confirmação ANALISE_PENDENTE | userTask | Angular: tela de sucesso | — |
| EE_J1 | Fim J1 | End Event | `CBM_USUARIO.status = ANALISE_PENDENTE(1)` | — |
| SE_J2 | Início J2 | Start Event | Analista autenticado via SOE | — |
| T_AN_001 | Listar cadastros em análise | userTask | `GET /adm/analise-cadastros/em-analise` | — |
| T_BE_008 | `listarCadastrosEmAnalise()` | serviceTask | `AnaliseCadastroRN.listarCadastrosEmAnalise()` · `@LISTAR` · filtro idUsuarioSoe + EM_ANALISE | — |
| T_AN_002 | Selecionar cadastro | userTask | Angular: seleção da lista (sem BE) | — |
| T_AN_003 | Assumir análise | userTask | `POST /adm/analise-cadastros` · `@EDITAR` | RN-P02-05, 06 |
| T_BE_009 | `incluirAnaliseCadastro()` | serviceTask | `AnaliseCadastroRN.incluirAnaliseCadastro()` · `@REQUIRED` | RN-P02-05 a 09 |
| T_AN_004 | Analisar documentos | userTask | `GET /adm/analise-cadastros/{id}` + downloads de arquivos · `@CONSULTAR` | — |
| GW_AN_001 | Decisão do analista | gateway | StatusAnalise: APROVADO / REPROVADO / CANCELADO | — |
| T_AN_005 | Confirmar aprovação | userTask | Angular: confirmação (sem campo extra) | — |
| T_AN_006 | Reprovar + justificativa | userTask | Angular: campo justificativa obrigatório | — |
| T_AN_007 | Cancelar análise | userTask | Angular: confirmação de cancelamento | — |
| GW_AN_002 | Merge das 3 decisões | gateway | — | — |
| T_AN_008 | Registrar decisão | userTask | `PUT /adm/analise-cadastros/{id}` · `@EDITAR` | RN-P02-10 |
| T_BE_010 | `alterarStatusAnaliseCadastro()` + `mudarStatusCadastro()` | serviceTask | `AnaliseCadastroRN.alterarStatusAnaliseCadastro()` · `@REQUIRED` | RN-P02-10, 11 |
| GW_AN_003 | Análise cancelada? | gateway | CANCELADO vs APROVADO/REPROVADO | — |
| T_AN_009 | Exibir resultado ao analista | userTask | Angular: mensagem de confirmação | — |
| T_BE_011 | `NotificacaoRN.notificar()` | serviceTask | `NotificacaoRN.notificar(enviarEmail=true)` · SMTP PROCERGS | RN-P02-11 |
| EE_J2 | Fim J2 | End Event | `CBM_USUARIO.status = APROVADO(3)` ou `REPROVADO(4)` | — |
| TA_001 | Anotação: concorrência + CPF | Text Annotation | associada a T_BE_003 | RN-P02-01, 02 |
| TA_002 | Anotação: completude + arquivo duplicado | Text Annotation | associada a T_BE_007 | RN-P02-03, 04 |
| TA_003 | Anotação: diff graduações | Text Annotation | associada a T_BE_005 | RN-P02-12, 13 |
| TA_004 | Anotação: abertura de análise | Text Annotation | associada a T_BE_009 | RN-P02-05 a 09 |
| TA_005 | Anotação: autorização + mapeamento status | Text Annotation | associada a T_BE_010 | RN-P02-10, 11 |
| TA_006 | Anotação: transição J1→J2 | Text Annotation | associada a SE_J2 | RN-P02-14 |
