# CLAUDE.md — Contexto do Projeto SOL

## O que é o SOL

**SOL** = **Sistema Online de Licenciamento** do CBMRS (Corpo de Bombeiros Militar do Rio Grande do Sul).

Sistema de gestão de licenciamentos para prevenção e proteção contra incêndio (PPCI — Plano de Prevenção e Proteção Contra Incêndio) para estabelecimentos no RS. Permite que Responsáveis Técnicos (RT) submetam solicitações, que são analisadas, vistoriadas e aprovadas por analistas e inspetores do CBMRS.

## Stack Tecnológico

| Camada | Tecnologia |
|---|---|
| **Frontend** | Angular + angular-oauth2-oidc (Implicit Flow OIDC) + Angular Material |
| **Backend** | Java EE (JAX-RS REST, CDI, JPA/Hibernate, EJB) em WildFly/JBoss |
| **Banco de dados** | Oracle (confirmado) / PostgreSQL (proposto para modernização) |
| **Autenticação** | OAuth2/OIDC via SOE PROCERGS (`meu.rs.gov.br`) |
| **ECM** | Alfresco (integração de documentos, nodeRef em `identificadorAlfresco`) |
| **Integração** | SOL ↔ SEI (API SOAP, polling, padrão Outbox assíncrono) |

## Processos (P01–P14)

| Processo | Nome | Status | Responsáveis |
|---|---|---|---|
| **P01** | Login via OIDC | ✅ Completo | Cidadão/RT |
| **P02** | Cadastro de Responsável Técnico (RT) | ✅ Completo | Cidadão |
| **P03** | Submissão de PPCI (Wizard) | ✅ Completo | RT/Proprietário |
| **P04** | Análise Técnica (ATEC) | ✅ Completo | Analista/ADMIN |
| **P05** | Ciência de Recurso | ✅ Completo | Sistema (notificação 30d) |
| **P06** | Isenção de Taxa | ✅ Completo | RT + ADMIN |
| **P07** | Vistoria Presencial | ✅ Completo | Inspetor |
| **P08** | Emissão de PRPCI (Parecer) | ✅ Completo | Inspetor |
| **P09** | Troca de Responsável Técnico | ✅ Completo | RT/ADMIN |
| **P10** | Recurso contra CIA/CIV | ✅ Completo | RT/Analista/ADMIN |
| **P11** | Pagamento de Boleto | ✅ Completo | Cidadão + PROCERGS |
| **P12** | Extinção de Licenciamento | ✅ Completo | Cidadão/ADMIN |
| **P13** | Jobs Automáticos (timers, suspensão) | ✅ Completo | Sistema |
| **P14** | Renovação de Licenciamento | ✅ Completo | Cidadão/Inspetor/ADMIN |

## Sprints Frontend (F1–F9)

| Sprint | Nome | Status | Componentes |
|---|---|---|---|
| **F1** | Dashboard Cidadão | ✅ Completo | Menu principal, detalhe licenciamento |
| **F2** | Wizard Submissão PPCI | ✅ Completo | Formulário multi-step |
| **F3** | Fila ATEC (Análise Técnica) | ✅ Completo | Tabela paginada, painel de análise |
| **F4** | Emissão CIA/CIV | ✅ Completo | Painel de decisão para analista |
| **F5** | Vistoria Presencial | ✅ Completo | Fila inspetor, painel de ações |
| **F6** | Emissão APPCI | ✅ Completo | Fila ADMIN, botão de emissão |
| **F7** | Recurso CIA/CIV | ✅ Completo | Fila ANALISTA, votação por comissão |
| **F8** | Troca de Envolvidos (RT) | ✅ Completo | Fila ADMIN, aceitar/rejeitar |
| **F9** | Relatórios e Dashboard | ✅ Completo | Menu relatórios, filtros avançados, exportação CSV |

## Regras de Negócio (RNs) — Completo (173+ RNs)

### P01 — Login e Autenticação (RN-01 a RN-24)

| RN | Descrição |
|---|---|
| **RN-01** | Fluxo Implicit Flow OIDC: cliente inicia `initImplicitFlow()` → redirect para IdP → token retorna em fragment URL |
| **RN-02** | `NullValidationHandler`: não valida assinatura JWT no cliente; apenas extrai claims (design deliberado para Implicit Flow) |
| **RN-03** | Token persistido em `localStorage['appToken']` após extração de claims |
| **RN-04** | `AuthGuard.canActivate()` sempre retorna `true`; proteção real ocorre no backend via Bearer token validation |
| **RN-05** | `HttpAuthorizationInterceptor` adiciona `Authorization: Bearer {token}` em todas as requisições para `AppSettings.baseUrl` |
| **RN-06** | E-mail claims ≠ BD E status ≠ EM_ANALISE? → sincroniza e-mail automaticamente (bloqueado em EM_ANALISE para proteger integridade de análise) |
| **RN-07** | Após sincronização de e-mail, chama `alteraProprietario(cpf, email, 'F')` em sistema externo (best-effort, sem bloqueio) |
| **RN-08** | Usuário não encontrado no BD → HTTP 404; status INCOMPLETO → navega para `/cadastro`; status EM_ANALISE → aguarda análise |
| **RN-11** | Control de concorrência via `ctrDthAtu` (CAS) detecta conflitos de atualização simultânea → HTTP 409 CONFLICT |
| **RN-18** | `ContainerRequestFilter` valida Bearer token em cada requisição JAX-RS (segurança em profundidade) |
| **RN-19** | Workaround de timezone: `dtNascimento.set(Calendar.HOUR, 12)` previne exibição incorreta em fusos negativos |
| **RN-20** | `UsuarioRN.consultaPorCpf()` retorna usuário completo com status e todos os campos |
| **RN-23** | OAuthService configurado com `NullValidationHandler` na inicialização (`configureAuth()`) |
| **RN-24** | `getNotificacoes()` falha silenciosamente → retorna lista vazia (graceful degradation) |

### P02 — Cadastro de Responsável Técnico (RN-P02-01 a RN-P02-14)

| RN | Descrição |
|---|---|
| **RN-P02-01** | Controle de concorrência na alteração: verifica `ctrDthAtu` (CAS) quando status ≠ INCOMPLETO → HTTP 409 se divergente |
| **RN-P02-02** | CPF único por usuário: violação de constraint capturada como `ConstraintViolationException` → HTTP 400 |
| **RN-P02-03** | Validação de completude na submissão: status `ANALISE_PENDENTE` apenas se RG + arquivos de profissional de todas as graduações presentes |
| **RN-P02-04** | Arquivo único por entidade: se já existe arquivo vinculado → HTTP 400; atualização via endpoints `PUT` |
| **RN-P02-05** | Validação de campos na abertura de análise: `id`, `status`, `ctrDthAtu` obrigatórios → HTTP 400 se null |
| **RN-P02-06** | Controle de concorrência na abertura: compara `ctrDthAtu` antes de assumir análise → HTTP 409 se divergente |
| **RN-P02-07** | Registro de análise criado somente para `ANALISE_PENDENTE`: re-abertura não cria novo registro |
| **RN-P02-08** | Vinculação da análise ao analista logado: ID SOE e nome extraídos de `sessionMB` e armazenados |
| **RN-P02-09** | Notificação ao usuário na abertura: envia notificação interna (sem e-mail) com status `EM_ANALISE` |
| **RN-P02-10** | Autorização para alterar status: apenas analista que assumiu OU permissão CENTRALADM/EDITAR → HTTP 403 se não autorizado |
| **RN-P02-11** | Mapeamento de status: CANCELADO→ANALISE_PENDENTE (sem e-mail), APROVADO/REPROVADO→status equivalente (com e-mail) |
| **RN-P02-12** | Algoritmo de diff para graduações: compara por ID, detecta mudanças, exclui arquivo se ID diferir |
| **RN-P02-13** | Graduações com ID null são ignoradas: filtradas antes de inserção |
| **RN-P02-14** | Verificação de RT válido: status `APROVADO` E pelo menos uma graduação vinculada |

### P03 — Wizard de Submissão PPCI (RN-P03-N1 a RN-P03-N7)

| RN | Descrição |
|---|---|
| **RN-P03-N1** | Alerta obrigatório de imutabilidade no Passo 2 (localização): exibe aviso de que endereço não pode ser alterado após envio |
| **RN-P03-N2** | Edição do Passo 1 por usuários externos em estado editável: permite que RT/Proprietário corrijam tipo de atividade antes do envio |
| **RN-P03-N3** | Campo de número de assentos para edificações do Grupo F: obrigatório se ocupação = F |
| **RN-P03-N4** | Novas classes de risco e tipos de risco na Etapa 5: mapeamento conforme RTCBMRS N.º 01/2024 |
| **RN-P03-N5** | Campo de upload de prancha de fachadas na Etapa 6: obrigatório para PPCI (opcional para PSPCIM) |
| **RN-P03-N6** | QR code de autenticação no APPCI: gerado após emissão, armazena verificação com Alfresco |
| **RN-P03-N7** | Reanalise deve verificar apenas os itens da CIA anterior: backend filtra itens para análise conforme CIA emitida |

### P04 — Análise Técnica (RN-P04-N1 a RN-P04-N6)

| RN | Descrição |
|---|---|
| **RN-P04-N1** | Exibir nome de analista responsável nos marcos de licenciamento: rastreabilidade de quem fez cada análise |
| **RN-P04-N2** | Inviabilidade técnica para edificações do Grupo M-5: bloqueio especial se grupo enquadra em critério de inviabilidade |
| **RN-P04-N3** | Reanalise resultados apos CIA anterior: apenas itens reprovados na CIA anterior são re-analisados |
| **RN-P04-N4** | Distribuição automática com critério FIFO (Ordem Cronológica de Protocolo): fila ordenada por `dataCriacao ASC` |
| **RN-P04-N5** | Cobrança de medida de segurança com inviabilidade técnica aprovada: cálculo diferenciado de taxa |
| **RN-P04-N6** | Coluna "Descricao" no histórico de documentos: rastreio de versões e modificações |

### P05 — Ciência de Recurso (RN-P05-N1 a RN-P05-N5)

| RN | Descrição |
|---|---|
| **RN-P05-N1** | Lembretes automáticos de ciência do CIA/CIV (D+7, D+20, D+27): jobs notificam em datas específicas |
| **RN-P05-N2** | Prazo do recurso calculado em dias úteis (Tabela Feriados): excluindo fins de semana e feriados estaduais |
| **RN-P05-N3** | Modal de alerta ao tentar editar recurso em 2ª instância: aviso de que prazo é mais curto (15d vs 30d) |
| **RN-P05-N4** | Bloquear novo recurso quando já existe um em aberto: `IND_RECURSO_BLOQUEADO='S'` impede submissão |
| **RN-P05-N5** | Cancelamento de aceite na fase AGUARDANDO_ACEITE: permite desfazer aceite antes de todos aceitarem |

### P06 — Isenção de Taxa (RN-P06-N1 a RN-P06-N5)

| RN | Descrição |
|---|---|
| **RN-P06-N1** | Granularização da isenção em 5 tipos por fase do processo: SUBMISSAO, ANALISE, VISTORIA, REANALISE, RENOVACAO |
| **RN-P06-N2** | Regras de isenção atualizadas para FACT vencido (P06-B): cidadão deve renovar FACT antes de solicitar isenção |
| **RN-P06-N3** | Novo fluxo P06-C: isenção de taxa na renovação de alvará: análise manual (não automática) |
| **RN-P06-N4** | Bloquear nova solicitação de vistoria após 30 dias da ciência do CIV: força aceitar inconformidades ou recorrer |
| **RN-P06-N5** | Tabela de isenção registrado nos marcos e rastreabilidade: cada solicitação é um marco auditável |

### P07 — Vistoria Presencial (RN-P07-N1 a RN-P07-N6)

| RN | Descrição |
|---|---|
| **RN-P07-N1** | Tipos de isenção na vistoria de renovação: permite isenção sob certas condições (ex: APPCI vigente há menos de 2 anos) |
| **RN-P07-N2** | Marcos do licenciamento visíveis ao usuário externo (versão filtrada): mostra apenas marcos públicos (VIS_EXTERNO) |
| **RN-P07-N3** | Bloquear nova vistoria e suspender processo após 30 dias da ciência do CIV: força resolução de inconformidades |
| **RN-P07-N4** | Distribuição automática de vistorias com critério FIFO: fila ordenada por `dataCriacao ASC` |
| **RN-P07-N5** | Laudos técnicos obrigatórios para solicitação de vistoria: 5 tipos de laudo conforme ocupação |
| **RN-P07-N6** | Suspensão automática após 2 anos sem movimentação com CA/CIV: bloqueio de re-vistoria até desbloqueio manual |

### P08 — Emissão de APPCI/PRPCI (RN-P08-N1 a RN-P08-N3)

| RN | Descrição |
|---|---|
| **RN-P08-N1** | Upload de múltiplos arquivos no PRPCI: permite anexação de ARTs, memoriais descritivos |
| **RN-P08-N2** | Revisão das permissões para aceite do Anexo D: validação de responsáveis antes de prosseguir |
| **RN-P08-N3** | APPCI somente emitido após quitação de todas as taxas e multas: bloqueio se débito pendente |

### P09 — Troca de Responsável Técnico (RN-P09-N1 a RN-P09-N2)

| RN | Descrição |
|---|---|
| **RN-P09-N1** | Preservar RT/ART aprovados no Tipo de Responsavel Técnico: vincular histórico de RTs |
| **RN-P09-N2** | Upload de ART/RRT de invalidabilidade obrigatório apenas na primeira vez: subsequentes podem reutilizar ART |

### P10 — Recurso contra CIA/CIV (RN-073 a RN-089)

| RN | Descrição |
|---|---|
| **RN-073** | `tipoSolicitacao` deve pertencer ao enum `{INTEGRAL, PARCIAL}` |
| **RN-074** | `tipoRecurso` deve pertencer ao enum `{CORRECAO_DE_ANALISE, CORRECAO_DE_VISTORIA}` |
| **RN-075** | Instância calculada corretamente: não pode abrir 2ª instância sem conclusão da 1ª |
| **RN-076** | `fundamentacaoLegal` obrigatória (não nula, não vazia) — recurso sem fundamentação é inadmissível |
| **RN-077** | `NRO_INT_ARQUIVO_CIA_CIV` deve existir e pertencer ao licenciamento informado |
| **RN-078** | Prazo de 1ª instância: `ChronoUnit.DAYS.between(dataCia, now()) <= 30` (revalidado no backend) |
| **RN-079** | Prazo de 2ª instância: `ChronoUnit.DAYS.between(dataConclusao1a, now()) <= 15` (revalidado no backend) |
| **RN-080** | `idUsuarioSoe` do solicitante deve ser um dos envolvidos do licenciamento (impede recursos por terceiros) |
| **RN-081** | Não pode existir recurso em situação ativa para o mesmo licenciamento e instância (impede paralelos) |
| **RN-082** | `IND_RECURSO_BLOQUEADO` do licenciamento não deve ser `'S'` (revalidado no backend) |
| **RN-083** | Responsáveis Técnicos elegíveis para co-assinar variam conforme `tipoRecurso` |
| **RN-084** | Unanimidade obrigatória: todos os co-signatários devem votar IGUAL (Deferido ou Indeferido) |
| **RN-085** | Cancelamento de recurso permitido apenas se status = `AGUARDANDO_APROVACAO_ENVOLVIDOS` |
| **RN-086** | Recusa de um co-signatário interrompe votação → volta para `AGUARDANDO_APROVACAO_ENVOLVIDOS` |
| **RN-087** | Habilitação para edição via `habilitarEdicao()` permite retornar à edição antes do envio aos co-signatários |
| **RN-088** | Notificação por e-mail enviada a todos os envolvidos em cada etapa (submissão, co-assinatura, decisão) |
| **RN-089** | Indeferimento em 2ª instância ativa permanentemente `IND_RECURSO_BLOQUEADO='S'` → bloqueia futuros recursos para aquele licenciamento |

### P11 — Pagamento de Boleto (RN-090 a RN-108)

| RN | Descrição |
|---|---|
| **RN-090** | Pré-condição: `SituacaoLicenciamento` deve ser compatível com `TipoBoleto` solicitado (ex: TAXA_VISTORIA só em AGUARDANDO_PAGAMENTO_VISTORIA) |
| **RN-091** | Se `licenciamento.situacaoIsencao == SOLICITADA`, cancela automaticamente ao gerar boleto |
| **RN-092** | Verificação de boleto vigente anterior: evita gerações duplicadas para o mesmo tipo e pagador |
| **RN-093** | Cálculo de valor: `valorBoleto = round(qtdUPF × valorUPF, 2, HALF_EVEN)` conforme tipo de boleto |
| **RN-094** | Regra dos 50% em vistoria: aplica metade da taxa se já houve vistoria do mesmo tipo sem APPCI posterior |
| **RN-095** | Compensação na reanálise: calcula delta de UPFs entre análise atual e anterior, somado aos 50% da taxa |
| **RN-096** | Regra dos 50% em renovação: aplica metade quando última vistoria encerrada foi reprovada |
| **RN-097** | Geração de Nosso Número: INSERT com sequence Oracle + UPDATE com DV módulo 11 |
| **RN-098** | Prazo de vencimento: 30 dias corridos a partir de emissão, fuso GMT-03:00 |
| **RN-099** | Desnormalização do pagador: copia nome, CPF/CNPJ e endereço para campos do `BoletoED` (garante integridade histórica) |
| **RN-100** | Seleção de beneficiário: identifica conta CBM-RS responsável por arrecadação com base em código IBGE do município |
| **RN-101** | Integração PROCERGS/Banrisul: REST com JWT/JWE; retorna código de barras e linha digitável |
| **RN-102** | Marco de auditoria registrado na geração do boleto (rastreabilidade via `TB_LICENCIAMENTO_MARCO`) |
| **RN-103** | Download PDF: valida boleto pertence ao licenciamento, não vencido; gera via JasperReports |
| **RN-104** | Job de vencimento: marca boletos com `dtVencimento <= hoje` como VENCIDO (dispara 2x/dia) |
| **RN-105** | Job de confirmação CNAB 240: processa arquivo retorno do Banrisul (dispara 2x/dia, às 00:01 e 12:01) |
| **RN-106** | Processamento CNAB: identifica registro liquidado (`COD_MOVIMENTO = 06`), valida duplicidade e valor |
| **RN-107** | Validação retorno: confronta valor CNAB com valor esperado; rejeita se divergente |
| **RN-108** | Transição de estado após pagamento: `AGUARDANDO_PAGAMENTO_*` → próximo estado conforme tipo de boleto e características do licenciamento |

### P12 — Extinção de Licenciamento (RN-109 a RN-120)

| RN | Descrição |
|---|---|
| **RN-109** | Situações incondicionalmente bloqueadoras: EXTINTO, CANCELADO_PENDENTE, CANCELADO_DEFINITIVO, etc. (lista completa em `ExtincaoService`) |
| **RN-110** | Situações bloqueadoras sem análise: requerem análise manual de ADMIN para extinção |
| **RN-111** | Se RT solicita, efetiva diretamente (sem etapa de aceite de si mesmo); outros atores requerem aceite do RT |
| **RN-112** | ADMIN extingue diretamente (sem etapa de aceite RT) via endpoint separado `/adm/licenciamentos/{id}/extinguir` |
| **RN-113** | Extinção automática cancela todos os processos paralelos ativos (recursos, trocas, etc.) |
| **RN-114** | EXTINTO é estado terminal: licenciamento não pode sofrer nenhuma alteração posterior |
| **RN-115** | Verificação de `TrocaEnvolvidoED` em situação de avaliação ativa bloqueia extinção |
| **RN-116** | Rejeição de extinção necessita motivo; restaura situação anterior do licenciamento |
| **RN-117** | Historicidade: cada transição de estado registrada em `TB_SITUACAO_LICENCIAMENTO` com timestamp |
| **RN-118** | Notificação enviada a todos os envolvidos (RT, RU) quando extinção é efetivada |
| **RN-119** | Inviabilidade técnica encerra automaticamente durante extinção (limpeza de dados correlatos) |
| **RN-120** | Auditoria completa: marcos com tipo, descrição e visibilidade registrados em cada etapa |

### P13 — Jobs Automáticos (RN-121 a RN-140)

| RN | Descrição |
|---|---|
| **RN-121** | Apenas `APPCI_EMITIDO` é elegível para verificação de vencimento; renovações têm status separado |
| **RN-122** | Critério de vencimento: `dtValidadeAppci <= hoje` (conversão booleana via `SimNaoBooleanConverter`) |
| **RN-123** | Historicidade: registra situação anterior antes de alterar entidade principal |
| **RN-124** | Alvará vencido marca `IND_VERSAO_VIGENTE='N'` em `TB_APPCI` e `TB_APPCI_DOC_COMPLEMENTAR` |
| **RN-125** | Notificação 90 dias: `dtValidadeAppci == dataBase + 90` (job P13-B, às 00:31) |
| **RN-126** | Notificação 59 dias: `dtValidadeAppci == dataBase + 59` (mesma lógica) |
| **RN-127** | Notificação 29 dias: `dtValidadeAppci == dataBase + 29` (crítica, menos de um mês) |
| **RN-128** | Notificação vencimento: enfileira após licenciamento realmente vencido |
| **RN-129** | Envio e-mail: reprocessa status `PENDENTE` e `ERRO` (retry automático) |
| **RN-130** | E-mail SMTP: falha logada como `ERRO`, reprocessada na execução seguinte |
| **RN-131** | Template e-mail resolvido conforme `TipoMarco` (VENCIMENTO_ALVARA, AVENCER_90D, etc.) |
| **RN-132** | Destinatários: RT e RU do licenciamento (invalidos ignorados com LOG WARN) |
| **RN-133** | Processamento CNAB: parseia arquivo conforme padrão CNAB 240 |
| **RN-134** | Pagamento registrado com `DATA_PAGAMENTO` e nome de arquivo de retorno |
| **RN-135** | Retry automático: notificações com `ERRO` reprocessadas sem limite explícito |
| **RN-136** | Job CNAB: dispara 2x/dia (00:00 e 12:00), processa files em paralelo, move processados para diretório separado |
| **RN-137** | Timer EJB: `persistent=false` → não sobrevive reinicializações (job perdido = sem compensação de execuções ausentes) |
| **RN-138** | Intervalo de 30 minutos entre Pool 1 (00:01) e Pool 2 (00:31) é de design, não BPMN-obrigatório |
| **RN-139** | Isolamento de transação por licenciamento: falha em um não reverte alterações de outros (multi-instance sequencial, `REQUIRES_NEW` implícito) |
| **RN-140** | Baseline temporal: `DTH_FIM_EXECUCAO` de última rotina CONCLUIDA determina janela de processamento (idempotência de notificações) |

### P14 — Renovação de Licenciamento (RN-141 a RN-160)

| RN | Descrição |
|---|---|
| **RN-141** | Elegibilidade: apenas `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` são renováveis |
| **RN-142** | Transição imediata: após aceite do termo → `AGUARDANDO_ACEITE_ANEXO_D_RENOVACAO` |
| **RN-143** | RT RENOVACAO_APPCI obrigatório: não pode renovar se RT atual não tem credencial ativa |
| **RN-144** | Tipo exclusivo: `TipoLicenciamento.RENOVACAO_*` distinto de `PPCI` e `PSPCIM` |
| **RN-145** | Anexo D obrigatório: documento de regularização do estabelecimento deve ser aceito para prosseguir |
| **RN-146** | Rejeição de Anexo D: retorna a estado anterior, permite re-edição |
| **RN-147** | Cancelamento em qualquer etapa anterior ao pagamento: rollback para `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` |
| **RN-148** | Após aceite Anexo D → transição para `AGUARDANDO_PAGAMENTO_RENOVACAO` ou `AGUARDANDO_ANALISE_ISENCAO_RENOVACAO` |
| **RN-149** | Gateway: cidadão opta por **Solicitar Isenção** ou **Gerar Boleto** |
| **RN-150** | Isenção na renovação: análise manual de ADMIN (não automática como P06); aprova ou nega explicitamente |
| **RN-151** | Após aprovação isenção → `AGUARDANDO_DISTRIBUICAO_RENOVACAO` (dispensa pagamento) |
| **RN-152** | Boleto geração: cálculo conforme regras de taxa de renovação (RN-096 de P11) |
| **RN-153** | Após pagamento boleto → `AGUARDANDO_DISTRIBUICAO_RENOVACAO` |
| **RN-154** | Distribuição automática: licenciamento distribuído para inspetor conforme critérios (carga, disponibilidade) |
| **RN-155** | Vistoria de renovação: `TipoVistoria.VISTORIA_RENOVACAO` (processo simplificado em relação a vistoria inicial) |
| **RN-156** | Resultado vistoria: Deferimento (novo alvará) ou CIV (retorna para análise de inconformidades) |
| **RN-157** | Deferimento: gera PrPCI e transição para `PRPCI_EMITIDO_RENOVACAO` → depois APPCI via P06 |
| **RN-158** | CIV: transição de volta para análise; RT deve resolver inconformidades e resubmeter |
| **RN-159** | Nova submissão após CIV: ciclo de vistoria → deferimento/CIV se repete até deferimento |
| **RN-160** | Alvará renovado herda dados de vencimento conforme ocupação (RN-087 de P06): +2 anos (risco baixo) ou +5 anos (moderado/alto) |

### P05–P09 — Regras Suplementares

| RN | Descrição |
|---|---|
| **RN-087** | Cálculo de validade APPCI: +2 anos (risco baixo) ou +5 anos (risco moderado/alto) — RTCBMRS N.º 01/2024 |

---

## Matriz de Rastreabilidade RN × Processo

| Processo | RNs | Quantidade |
|---|---|---|
| **P01** | RN-01 a RN-24 | 24 |
| **P02** | RN-P02-01 a RN-P02-14 | 14 |
| **P03** | RN-P03-N1 a RN-P03-N7 | 7 |
| **P04** | RN-P04-N1 a RN-P04-N6 | 6 |
| **P05** | RN-P05-N1 a RN-P05-N5 | 5 |
| **P06** | RN-P06-N1 a RN-P06-N5 | 5 |
| **P07** | RN-P07-N1 a RN-P07-N6 | 6 |
| **P08** | RN-P08-N1 a RN-P08-N3 | 3 |
| **P09** | RN-P09-N1 a RN-P09-N2 | 2 |
| **P10** | RN-073 a RN-089 | 17 |
| **P11** | RN-090 a RN-108 | 19 |
| **P12** | RN-109 a RN-120 | 12 |
| **P13** | RN-121 a RN-140 | 20 |
| **P14** | RN-141 a RN-160 | 20 |

---

**Total: 173 Regras de Negócio documentadas**

## Roles/Permissões

| Role | Acesso |
|---|---|
| **ADMIN** | Gerenciamento completo (filas, decisões, relatórios) |
| **CHEFE_SSEG_BBM** | Relatórios, visão consolidada, algumas decisões |
| **ANALISTA** | Fila ATEC, votação de recurso |
| **INSPETOR** | Fila de vistoria, emissão de laudos |
| **RT** | Submissão PPCI, solicitação de recurso, troca |
| **CIDADAO** | Submissão inicial, acompanhamento, pagamento |

## Integração SEI

SOL integra-se com SEI (Sistema Eletrônico de Informações) via:
- API SOAP (SeiWS.php) — polling obrigatório (sem webhook)
- Autenticação: `SiglaSistema` + `IdentificacaoServico` (PROCERGS)
- Padrão: Outbox assíncrono para envio de documentos finais (APPCI, CIA, CIV, decisões)
- 12 eventos mapeados (P03, P04, P07, P08, P10, P12, P14)

## Documentação Completa

Todos os BPMNs, requisitos técnicos e descritivos estão em `C:\SOL\docs\`:
- `Requisitos_F*.md` — Especificações de cada sprint frontend
- `P*.bpmn` — Diagramas BPMN de cada processo (Camunda Modeler)
- `Descritivo_P*.md` — Fluxo detalhado com tabelas de rastreabilidade
- `DDL_PostgreSQL_SistemaSOL_Moderno.sql` — Schema atual

## Próximas Etapas Pendentes

1. **Deploy das Sprints F1–F9 em produção** — Validar no servidor
2. **P15 — Integração SOL ↔ SEI** — BPMN e especificação técnica (opcional)
3. **Modernização de stack** — Spring Boot 3 + PostgreSQL + Angular (proposto)
4. **Testes de integração** — Validar fluxos E2E em ambiente de staging
5. **Documentação de operações** — Runbooks, troubleshooting, oncall procedures

## Contatos Técnicos

- **Normas:** RTCBMRS N.º 01/2024 + RT de Implantação SOL 4ª Ed.
- **GitHub:** `https://github.com/GuilhermeCorrea1962/sol-cbmrs`
- **Servidor:** Y:\ (descontinuado; usar GitHub)
- **IdP:** `meu.rs.gov.br` (administrado por PROCERGS)
- **ECM:** Alfresco (integração de documentos)

---

**Última atualização:** 2026-04-16  
**Status do projeto:** Frente frontend em produção; backend estável; integração SEI em research.
