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

## Regras de Negócio Principais (RNs)

- **RN-087** — Cálculo de validade APPCI: +2 anos (risco baixo) ou +5 anos (risco moderado/alto)
- **RN-088** — Unanimidade obrigatória na votação de recurso
- **RN-089** — PPCI bloqueado enquanto recurso ativo
- **RN-090 a RN-108** — Prazos de ciência (30 dias úteis, com suspensão em períodos de CIA/CIV)
- **RN-109 a RN-120** — Regras de extinção e suspensão automática
- **RN-121+** — Jobs automáticos, timers, calendarização

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
