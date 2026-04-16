# CLAUDE.md — Projeto SOL (Sistema Online de Licenciamento) — CBM-RS

## O que é o SOL

*SOL* = *Sistema Online de Licenciamento* do CBMRS (Corpo de Bombeiros Militar do Rio Grande do Sul).

Sistema web para gestão de licenciamentos para prevenção e proteção contra incêndio (PPCI — Plano de Prevenção e Proteção Contra Incêndio) para estabelecimentos no RS.

---

## Stack Tecnológico — Infraestrutura Atual (Servidor)

| Camada | Tecnologia | Versão | Porta |
|---|---|---|---|
| Framework | Spring Boot | 3.3.4 | — |
| Linguagem | Java | 21 (Eclipse Adoptium) | — |
| ORM | Hibernate | 6.5 | — |
| Banco de Dados | Oracle XE | 21c, schema SOL | 1521 |
| Autenticação | Keycloak | 24.0.3, realm sol | 8180 |
| Armazenamento | MinIO | 2025-09-07 | 9000 |
| Proxy Reverso | Nginx | 1.26.2 | 80 |
| E-mail (dev) | MailHog | 1.0.1 | 1025/8025 |

## Stack Original (Ainda em Produção)

- *Backend:* Java EE (JAX-RS REST, CDI, JPA/Hibernate, EJB) em WildFly/JBoss
- *Autenticação:* OAuth2/OIDC via SOE PROCERGS (meu.rs.gov.br)
- *ECM:* Alfresco (documentos, nodeRef em identificadorAlfresco)
- *Integrações:* SEI (API SOAP, polling), PROCERGS (boletos), Alfresco (ECM)

## Frontend

- *Framework:* Angular 18.2
- *UI:* Angular Material 18.2
- *OAuth:* angular-oauth2-oidc 17 (Implicit Flow OIDC)

---

## Processos (P01–P14) — 160+ Regras de Negócio Documentadas

| ID | Nome | Status | RNs |
|---|---|---|---|
| P01 | Login via OIDC | ✅ Completo | RN-01 a RN-24 |
| P02 | Cadastro de RT | ✅ Completo | RN-P02-01 a RN-P02-14 |
| P03 | Submissão PPCI (Wizard) | ✅ Completo | RN-P03-N1+ |
| P04 | Análise Técnica (ATEC) | ✅ Completo | RN-25+ |
| P05 | Ciência de Recurso | ✅ Completo | RN-051+ |
| P06 | Isenção de Taxa | ✅ Completo | RN-061+ |
| P07 | Vistoria Presencial | ✅ Completo | RN-061+ |
| P08 | Emissão PRPCI | ✅ Completo | RN-061+ |
| P09 | Troca de RT | ✅ Completo | RN-073+ |
| P10 | Recurso CIA/CIV | ✅ Completo | RN-073 a RN-089 |
| P11 | Pagamento de Boleto | ✅ Completo | RN-090 a RN-108 |
| P12 | Extinção | ✅ Completo | RN-109 a RN-120 |
| P13 | Jobs Automáticos | ✅ Completo | RN-121 a RN-140 |
| P14 | Renovação | ✅ Completo | RN-141 a RN-160 |

---

## Sprints Frontend (F1–F9)

F1: Dashboard Cidadão | F2: Wizard PPCI | F3: Fila ATEC | F4: Emissão CIA/CIV | F5: Vistoria | F6: APPCI | F7: Recurso | F8: Troca RT | F9: Relatórios

---

## Documentação Completa (em /docs/)

- *BPMNs:* P01-P14_*.bpmn (4 raias: Cidadão/RT/Inspetor/Sistema) via Camunda Modeler
- *Requisitos:* Requisitos_P*.md (stack atual + stack moderna) — 14 processos × 2 versões = 28 arquivos
- *Descritivos:* Descritivo_P*.md (explicações de cada elemento, rastreabilidade RN, tabelas)
- *Análises:* Impacto normas, oportunidades de racionalização, design UX, DDL PostgreSQL, integração SEI

---

## Normas Incorporadas

*RTCBMRS N.º 01/2024 + RT Implantação SOL 4ª Ed:*
- FIFO distribuição | 30 dias úteis recurso | 30 dias re-vistoria
- PrPCI obrigatório | 5 laudos vistoria | Anexo D
- Validade APPCI: 2 anos (público) / 5 anos (residencial)
- Suspensão automática: CIA 6 meses + CIV 2 anos

---

## Integrações Externas

| Sistema | Tipo | Autenticação | Status |
|---|---|---|---|
| *SEI* | API SOAP | SiglaSistema + IdentificacaoServico | Outbox assíncrono, 12 eventos mapeados |
| *PROCERGS* | Boletos + OAuth2 | OAuth2/OIDC | Banrisul, CNAB 240, SOE |
| *Alfresco* | ECM | nodeRef | Documentos PPCI, ARTs, laudos |

---

## Estado Completo

✅ *Todos os 14 processos:* BPMN detalhado + Requisitos (2 stacks) + Descritivo
✅ *160+ Regras de Negócio:* Mapeadas, documentadas, referenciadas em BPMNs
✅ *9 Sprints Frontend:* Componentes e telas definidas
✅ *Integrações:* SEI (16 seções), PROCERGS (boletos), Alfresco (ECM)
✅ *Infraestrutura:* Oracle, Keycloak, MinIO, Nginx, Scripts PowerShell deploy

---

*Projeto unificado master (infraestrutura) + main (processos)*  
*2026-04-16*
