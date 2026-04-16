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

## Regras de Negócio (RNs) — Completo

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

| P01 | P05 | P06 | P07 | P08 | P09 | P10 | P11 | P12 | P13 | P14 |
|---|---|---|---|---|---|---|---|---|---|---|
| RN-01 a RN-24 | — | — | — | — | — | RN-073 a RN-089 | RN-090 a RN-108 | RN-109 a RN-120 | RN-121 a RN-140 | RN-141 a RN-160 |

---

**Total: 160 Regras de Negócio documentadas**

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
