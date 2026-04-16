# MEMORY — Projeto Licitação SOL / CBM-RS

## Diretório de trabalho
`C:\Users\Administrador\Downloads\Licitação SOL`

## Contexto geral
Projeto de levantamento e documentação de requisitos/processos do sistema SOL (Sistema Online de Licenciamento) do Corpo de Bombeiros Militar do Rio Grande do Sul (CBMRS). Trabalho feito em múltiplas sessões.

## Stack tecnológica identificada
- **Frontend:** Angular + angular-oauth2-oidc (Implicit Flow OIDC)
- **Backend:** Java EE (JAX-RS REST, CDI, JPA/Hibernate, EJB)
- **IdP:** SOE PROCERGS / meu.rs.gov.br (OAuth2/OIDC estadual)
- **BD:** Relacional (Oracle — confirmado pelo DDL real)
- **Servidor:** WildFly/JBoss (inferido pela stack Java EE)
- **ECM:** Alfresco (campo `identificadorAlfresco` = nodeRef em `ArquivoED`)

## Fontes de código
- `SOLCBM.BackEnd16-06\` — código Java EE do backend
- `SOLCBM.FrontEnd16-06\` — código Angular do frontend
- `X:\CBM\Sistema SEI\Projeto SOL\Apresentação COMPLETA do sistema SOL.pdf` — 225 páginas (LIDO INTEGRALMENTE)

## Conceitos técnicos e padrões de código
Ver `memory/conceitos-tecnicos.md` para: SimNaoBooleanConverter, padrão de camadas, segurança, Alfresco, TipoMarco por processo, estrutura BPMN, P09 conceitos específicos.

---

## Arquivos produzidos

### BPMNs

| Arquivo | Processo | Versão |
|---|---|---|
| `SOL_CBM_RS_Processos_P1a4.bpmn` | P01–P04 | inicial multi-processo |
| `SOL_CBM_RS_Processos_P5a10.bpmn` | P05–P10 | inicial |
| `SOL_CBM_RS_Processo_P01_StackAtual.bpmn` | P01 Login | **detalhada** — 4 raias FE/IdP/BE/usuário |
| `SOL_CBM_RS_Processo_P02_StackAtual.bpmn` | P02 Cadastro RT | **detalhada** — 4 raias |
| `P03_Wizard_Solicitacao_Licenciamento_Detalhado.bpmn` | P03 Wizard | **detalhada** — 4 raias, Camunda Modeler |
| `P04_AnaliseTecnica_ATEC_StackAtual.bpmn` | P04 Análise Técnica | **detalhada** — 4 raias, sub-processo colapsado 11 itens, boundary cancel, 4 end events |
| `P05_CienciaRecurso_StackAtual.bpmn` | P05 Ciência Recurso | **detalhada** — 4 raias |
| `P06_IsencaoTaxa_StackAtual.bpmn` | P06 Isenção de Taxa | **detalhada** — 2 pools (P06-A + P06-B), 4 raias |
| `P07_VistoriaPresencial_StackAtual.bpmn` | P07 Vistoria | **detalhada** — 4 raias, 4 end events, 2 loop-backs |
| `P08_EmissaoPRPCI_StackAtual.bpmn` | P08 PRPCI | **detalhada** — 2 pools (P08-A + P08-B), 2 raias cada |
| `P09_TrocaEnvolvidos_StackAtual.bpmn` | P09 Troca Envolvidos | **detalhada** — 1 pool, 3 raias, loop autorização, boundary cancel |
| `P10_Recurso_StackAtual.bpmn` | P10 Recurso CIA/CIV | **detalhada** — 4 raias, 8 fases, 2 boundary events (Recusa/Cancel), 3 end deferido/indeferido |
| `P11_PagamentoBoleto_StackAtual.bpmn` | P11 Pagamento Boleto | **detalhada** — 2 pools (P11-A + P11-B), P11-A: 3 raias (Cidadão/Sistema/PROCERGS), P11-B: 2 raias (EJBTimer/Sistema), 2 timer starts, sub-processo multi-instance serial |
| `P12_ExtincaoLicenciamento_StackAtual.bpmn` | P12 Extinção Licenciamento | **detalhada** — 1 pool, 3 raias (Cidadão/Sistema/Admin), 2 start events, boundary cancel, 5 end events, 6 gateways |
| `P14_RenovacaoLicenciamento_StackAtual.bpmn` | P14 Renovação Licenciamento | **detalhada** — 1 pool, 4 raias (Cidadão/Admin/Inspetor/Sistema), 33 elementos, 6 fases, loop CIV→AceitarAnexoD, dupla entrada T_AceitarAnexoD e T_GerarBoleto |
| `SOL_CBM_RS_Processo_P04.bpmn` … `P14.bpmn` | P04, P06–P14 | versões iniciais simples |

### Documentos de Requisitos

| Arquivo | Conteúdo |
|---|---|
| `Requisitos_P01_Autenticacao_StackAtual.md` | P01 stack atual |
| `Requisitos_P01_Autenticacao_Java.md` | P01 stack moderna |
| `Requisitos_P02_CadastroUsuario_StackAtual.md` | P02 stack atual (12 seções) |
| `Requisitos_P02_CadastroUsuario_Java.md` | P02 stack moderna |
| `Requisitos_P03_SubmissaoPPCI_StackAtual.md` | P03 stack atual (14 seções) |
| `Requisitos_P03_SubmissaoPPCI_Java.md` | P03 stack moderna |
| `Requisitos_P04_AnaliseTecnica_StackAtual.md` | P04 stack atual |
| `Requisitos_P04_AnaliseTecnica_Java.md` | P04 stack moderna |
| `Requisitos_P05_CienciaRecurso_StackAtual.md` | P05 stack atual |
| `Requisitos_P05_CienciaRecurso_Java.md` | P05 stack moderna |
| `Requisitos_P06_IsencaoTaxa_StackAtual.md` | P06 stack atual (14 seções) |
| `Requisitos_P06_IsencaoTaxa_JavaModerna.md` | P06 stack moderna |
| `Requisitos_P07_VistoriaPresencial_StackAtual.md` | P07 stack atual (15 seções) |
| `Requisitos_P07_VistoriaPresencial_JavaModerna.md` | P07 stack moderna (15 seções) |
| `Requisitos_P08_EmissaoPRPCI_StackAtual.md` | P08 stack atual (15 seções) |
| `Requisitos_P08_EmissaoPRPCI_JavaModerna.md` | P08 stack moderna (15 seções) |
| `Requisitos_P09_TrocaEnvolvidos_StackAtual.md` | P09 stack atual (15 seções) |
| `Requisitos_P09_TrocaEnvolvidos_JavaModerna.md` | P09 stack moderna (15 seções) |
| `Requisitos_P10_Recurso_StackAtual.md` | P10 stack atual (14 seções) |
| `Requisitos_P10_Recurso_JavaModerna.md` | P10 stack moderna (15 seções) |
| `Requisitos_P11_PagamentoBoleto_StackAtual.md` | P11 stack atual (12 seções, RN-090 a RN-108) |
| `Requisitos_P11_PagamentoBoleto_JavaModerna.md` | P11 stack moderna (15 seções, RN-090 a RN-106) |
| `Requisitos_P12_ExtincaoLicenciamento_StackAtual.md` | P12 stack atual (15 seções, RN-109 a RN-120) |
| `Requisitos_P12_ExtincaoLicenciamento_JavaModerna.md` | P12 stack moderna (15 seções, RN-109 a RN-120, sem PROCERGS) |
| `Requisitos_P13_JobsAutomaticos_JavaModerna.md` | P13 stack moderna (15 seções, RN-121 a RN-140, Spring Boot 3 · Spring Scheduler · ShedLock · Thymeleaf · PostgreSQL) |
| `Requisitos_P14_RenovacaoLicenciamento_JavaModerna.md` | P14 stack moderna (v1.1, Spring Boot 3.x · Spring Data JPA · Flyway · PostgreSQL) |

### Descritivos de BPMN

| Arquivo | Conteúdo |
|---|---|
| `Descritivo_P02_FluxoBPMN_StackAtual.md` | P02 — 6 seções, 28 passos |
| `Descritivo_P03_FluxoBPMN_StackAtual.md` | P03 — 8 seções |
| `Descritivo_P04_FluxoBPMN_StackAtual.md` | P04 — 13 seções (6 fases: distribuição, análise, CIA, CA, homologação, deferimento PPCI/PSPCIM, cancelamento) |
| `Descritivo_P05_FluxoBPMN_StackAtual.md` | P05 — 12 seções |
| `Descritivo_P06_FluxoBPMN_StackAtual.md` | P06 — 9 seções |
| `Descritivo_P07_FluxoBPMN_StackAtual.md` | P07 — 10 seções |
| `Descritivo_P08_FluxoBPMN_StackAtual.md` | P08 — 9 seções (P08-A + P08-B, TrocaEstado, marcos, rastreabilidade) |
| `Descritivo_P09_FluxoBPMN_StackAtual.md` | P09 — 9 seções (3 fases, boundary events, matriz RT, maquina estados, rastreabilidade) |
| `Descritivo_P10_FluxoBPMN_StackAtual.md` | P10 — 14 seções (8 fases, 2 boundary events, loop unanimidade, 2 GWs em cascata, bloqueio RN-089) |
| `Descritivo_P11_FluxoBPMN_StackAtual.md` | P11 — 12 seções (2 pools, P11-A: 4 fases + 3 raias, P11-B: 2 fluxos timer, RN-090 a RN-108, CNAB 240) |
| `Descritivo_P12_FluxoBPMN_StackAtual.md` | P12 — 12 seções (2 fluxos: cidadão + admin, boundary cancel, 5 end events, diagrama de estados, ref cruzada) |
| `Descritivo_P14_FluxoBPMN_StackAtual.md` | P14 — 11 seções (6 fases: iniciação, aceite Anexo D, pagamento/isenção, distribuição, vistoria, deferimento/CIV), tabela rastreabilidade 34 linhas, 9 justificativas J1–J9 — **ÚLTIMO PRODUZIDO** |

### Outros

| Arquivo | Conteúdo |
|---|---|
| `Fluxograma_P01_Autenticacao.md` | Fluxograma técnico P01 (Angular+Java) |
| `Roteiro_P01_Telas_BPMN.md` | Roteiro P01 com ASCII art telas × BPMN |
| `Mapeamento_Telas_P01_P02_PDF.md` | Mapeamento PDF → BPMN para P01/P02 |
| `Roteiro_Processos_Internos_SOL.md` | Roteiro geral dos processos |
| `Matriz_Rastreabilidade_Regras_Negocio_SOL.md` | Matriz de rastreabilidade RNs |
| `Analise_Impacto_Normas_RTCBMRS_01_2024_e_SOL_4ed.md` | Análise de impacto das normas vigentes sobre todos os documentos produzidos |
| `Analise_Oportunidades_Racionalizacao_Processos.md` | Oportunidades de racionalização (corrigido com normas: FIFO A2, ciência 30 dias B1, re-vistoria 30 dias E2, jobs suspensão A3, validade APPCI B4) |
| `Design_UX_SistemaSOL_Moderno.md` | Proposta de design UX (atualizado com 8 novas telas normativas: campos imutáveis, 5 laudos, Anexo D, PrPCI, recurso bloqueado, SUSPENSO, interdição, validade APPCI) |
| `DDL_PostgreSQL_SistemaSOL_Moderno.sql` | DDL PostgreSQL (Bloco 18: SUSPENSO enum, tabela feriado, funções dias_uteis, trigger Passo 2, calcular_validade_appci, Anexo D, prpci, perfis CHEFE_SSEG_BBM) |
| `Integracao_SOL_SEI_Especificacao_Tecnica.md` | Especificação técnica completa da integração SOL ↔ SEI (16 seções, 750 linhas): SeiGatewayService, outbox, mapeamento 12 eventos, DDL integracao_sei, polling, resiliência |

---

## Estado dos processos

| Processo | BPMN simples | BPMN detalhado | Req. Stack Atual | Req. Java Moderna | Descritivo |
|---|---|---|---|---|---|
| P01 Login | ✅ | ✅ | ✅ | ✅ | ✅ (fluxograma) |
| P02 Cadastro RT | ✅ | ✅ | ✅ | ✅ | ✅ |
| P03 Wizard PPCI | ✅ | ✅ | ✅ | ✅ | ✅ |
| P04 Análise Técnica | ✅ | ✅ | ✅ | ✅ | ✅ |
| P05 Ciência Recurso | ✅ | ✅ | ✅ | ✅ | ✅ |
| P06 Isenção Taxa | ✅ | ✅ | ✅ | ✅ | ✅ |
| P07 Vistoria | ✅ | ✅ | ✅ | ✅ | ✅ |
| P08 PRPCI | ✅ | ✅ | ✅ | ✅ | ✅ |
| P09 Troca Envolvidos | ✅ | ✅ | ✅ | ✅ | ✅ |
| P10 Recurso CIA/CIV | ✅ | ✅ | ✅ | ✅ | ✅ |
| P11 Pagamento Boleto | ✅ | ✅ | ✅ | ✅ | ✅ |
| P12 Extinção Licenciamento | ✅ | ✅ | ✅ | ✅ | ✅ |
| P13 Jobs Automáticos | ✅ | ✅ | ✅ | ✅ | ✅ |
| P14 Renovação Licenciamento | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Conceitos-chave do domínio

- **PPCI:** Plano de Prevenção e Proteção Contra Incêndio
- **RT:** Responsável Técnico (engenheiro/arquiteto credenciado)
- **RU:** Responsável pelo Uso (proprietário/responsável do estabelecimento)
- **CIA:** Comunicado de Inconformidade na Análise
- **CIV:** Comunicado de Inconformidade na Vistoria
- **APPCI:** Alvará de Prevenção e Proteção Contra Incêndio
- **FACT:** Formulário de Atendimento e Consulta Técnica
- **StatusCadastro enum:** INCOMPLETO(0) → ANALISE_PENDENTE(1) → EM_ANALISE(2) → APROVADO(3) / REPROVADO(4)
- **Numeração PPCI:** `[Tipo][Sequencial 8d][Lote 2L][Versão 3d]` ex: `A 00000361 AA 001`

---

## Feedback de processo

- [Fluxo de deploy das Sprints](feedback_sprint_deploy.md) — Y:\ descontinuado; entregar lista de arquivos + instrucao para Claude no servidor

## Preferências do usuário

- Documentos em português (pt-BR), sem emojis
- Formato Markdown com tabelas
- BPMNs: raias separadas por participante técnico (Cidadão/RT/Proprietário/Sistema)
- Descritivos BPMN: explicar cada elemento E a justificativa da decisão de modelagem
- BPMNs Camunda Modeler: usar `camunda:class`, `camunda:assignee`, `camunda:formKey`, `<documentation>` com RNs, endpoints, tabelas e campos

## Próximas tarefas prováveis

1. **Roteiro ilustrado P02** — mesmo modelo do `Roteiro_P01_Telas_BPMN.md` (pendente há várias sessões)
2. **Integração SOL ↔ SEI** — especificação técnica produzida; próximo passo seria detalhar o BPMN da integração ou o módulo P15 de integração

## Notas de estado

- P12 está 100% completo (stack atual + Java moderna + BPMN + descritivo). RNs: RN-109 a RN-120.
- P13 está 100% completo (Requisitos stack atual + Requisitos Java Moderna + BPMN detalhado + Descritivo). RNs: RN-121 a RN-140.
- P14 está 100% completo (Requisitos stack atual + Requisitos Java Moderna v1.1 + BPMN detalhado + Descritivo). Sprint 14 executada no servidor com 25 OK, 0 erros.
- P14 = Renovação de Licenciamento (LicenciamentoRenovacaoCidadaoRN, AppciRenovacaoDTO, TipoVistoria.VISTORIA_RENOVACAO)
- RNs de P14: RN-121 em diante (numeração a confirmar na próxima sessão)
- **Integração SOL ↔ SEI:** SEI usa API SOAP (SeiWS.php), não REST. Auth por SiglaSistema + IdentificacaoServico. Sem webhook — polling obrigatório. SOL é operacional; SEI recebe documentos finais (APPCI, CIA, laudos, decisões de recurso) via padrão Outbox assíncrono. Tabela: `sol.integracao_sei`. Componente: `SeiGatewayService`. 12 eventos mapeados (P03, P04, P07, P08, P10, P12, P14). SEI-RS administrado pela PROCERGS.
- **Normas incorporadas (sessão 23/03/2026):** RTCBMRS N.º 01/2024 + RT de Implantação SOL 4ª Ed. Correções: FIFO distribuição, 30 dias úteis recurso, 30 dias re-vistoria, PPCI bloqueado durante recurso. Novos requisitos: PrPCI obrigatório antes APPCI, 5 laudos vistoria, Anexo D, validade APPCI 2/5 anos, CHEFE_SSEG_BBM, suspensão automática CIA (6 meses) e CA/CIV (2 anos).
