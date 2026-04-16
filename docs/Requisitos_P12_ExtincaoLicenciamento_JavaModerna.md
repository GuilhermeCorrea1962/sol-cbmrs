# Requisitos — P12: Extinção de Licenciamento
## Versão Java Moderna (sem dependência PROCERGS)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P12 — Extinção de Licenciamento
**Stack alvo:** Java 17+ · Spring Boot 3.x · Spring Security (OAuth2 Resource Server) · Spring Data JPA · Hibernate 6 · PostgreSQL · Spring Mail · Flyway
**Versão do documento:** 1.0
**Data:** 2026-03-13
**Referência de rastreabilidade:** US172 · `LicenciamentoCidadaoExtincaoRN` · `LicenciamentoCidadaoExtincaoRNVal` · `TrocaEstadoLicenciamentoParaExtinguidoRN`

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Atores e Papéis](#2-atores-e-papéis)
3. [Pré-condições e Contexto de Entrada](#3-pré-condições-e-contexto-de-entrada)
4. [Fluxo Principal — Extinção pelo Cidadão](#4-fluxo-principal--extinção-pelo-cidadão)
5. [Fluxo Alternativo — Extinção pelo Administrador](#5-fluxo-alternativo--extinção-pelo-administrador)
6. [Fluxo Alternativo — Recusa da Extinção (RT)](#6-fluxo-alternativo--recusa-da-extinção-rt)
7. [Fluxo Alternativo — Cancelamento da Extinção](#7-fluxo-alternativo--cancelamento-da-extinção)
8. [Regras de Negócio](#8-regras-de-negócio)
9. [API REST — Endpoints](#9-api-rest--endpoints)
10. [Modelo de Dados](#10-modelo-de-dados)
11. [Máquina de Estados do Licenciamento](#11-máquina-de-estados-do-licenciamento)
12. [Marcos de Auditoria](#12-marcos-de-auditoria)
13. [Notificações por E-mail](#13-notificações-por-e-mail)
14. [Segurança e Autorização](#14-segurança-e-autorização)
15. [Tratamento de Erros e Testes](#15-tratamento-de-erros-e-testes)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P12 trata da **extinção formal de um licenciamento** registrado no SOL. A extinção encerra permanentemente o ciclo de vida de um licenciamento — seja um PPCI (Plano de Prevenção e Proteção Contra Incêndio), um PSPCIM ou qualquer outro tipo amparado pelo sistema — marcando sua situação como `EXTINGUIDO` e notificando todos os envolvidos.

A extinção pode ser solicitada por atores do lado do cidadão (RT, RU, Proprietário) ou executada diretamente pelo Administrador do sistema. Quando o RT é parte do licenciamento e não é ele quem solicita a extinção, o processo inclui uma etapa de aceite: o licenciamento entra em estado intermediário `AGUARDANDO_ACEITES_EXTINCAO` até que o RT aceite, recuse ou cancele a solicitação.

### 1.2 Objetivos

- Permitir ao cidadão (RT, RU ou Proprietário) solicitar a extinção de um licenciamento ativo.
- Permitir ao Administrador extinguir diretamente um licenciamento, independentemente do status de aceite do RT.
- Garantir que a extinção só ocorra em situações válidas do licenciamento.
- Bloquear a extinção quando houver processos paralelos ativos incompatíveis (recurso em análise, troca de envolvidos em avaliação).
- Cancelar automaticamente recursos pendentes ao extinguir o licenciamento.
- Registrar marcos de auditoria para cada evento do processo.
- Notificar todos os envolvidos (RT, RU, Proprietários) ao final de cada transição.

### 1.3 Resultado esperado

Ao término do processo, o licenciamento está com situação `EXTINGUIDO`, todos os envolvidos foram notificados por e-mail, e a trilha de auditoria foi registrada com o marco `EXTINCAO`.

---

## 2. Atores e Papéis

| Ator | Descrição | Permissões no processo |
|---|---|---|
| **RT** (Responsável Técnico) | Engenheiro ou arquiteto credenciado vinculado ao licenciamento | Solicitar extinção; aceitar extinção solicitada por outro ator; recusar extinção; cancelar solicitação de extinção |
| **RU** (Responsável pelo Uso) | Proprietário ou responsável legal pelo estabelecimento | Solicitar extinção; cancelar solicitação de extinção |
| **Proprietário** | Proprietário do imóvel vinculado ao licenciamento | Solicitar extinção; cancelar solicitação de extinção |
| **Administrador** | Servidor do CBM-RS com perfil de administração | Extinguir diretamente (sem etapa de aceite do RT); cancelar extinção em andamento |
| **Sistema** | Componente automatizado | Registrar marcos; enviar notificações; cancelar recursos pendentes; atualizar situação |

---

## 3. Pré-condições e Contexto de Entrada

### 3.1 Pré-condições

- O licenciamento identificado por `idLicenciamento` deve existir no banco de dados.
- O ator autenticado deve ser um envolvido ativo no licenciamento (RT, RU ou Proprietário) ou possuir perfil de Administrador.
- O licenciamento não pode estar em uma situação que impeça a extinção (ver RN-109 e RN-110).
- Não pode haver solicitação de troca de envolvidos (`TrocaEnvolvido`) em avaliação para o licenciamento (ver RN-115).

### 3.2 Dados de entrada

| Dado | Tipo | Origem | Descrição |
|---|---|---|---|
| `idLicenciamento` | `Long` | Path variable (`/{idLicenciamento}`) | Identificador do licenciamento a ser extinguido |
| Token JWT | Header `Authorization: Bearer` | Cliente autenticado | Contém `sub` (CPF ou identificador do usuário) e roles/escopos |

---

## 4. Fluxo Principal — Extinção pelo Cidadão

### Fase 1 — Solicitação de Extinção

**Endpoint:** `POST /api/v1/licenciamentos/{idLicenciamento}/extinguir`
**Ator:** RT, RU ou Proprietário autenticado

**Passo 1 — Autenticação e autorização**
O sistema valida o token JWT no header `Authorization`. Confirma que o `sub` do token corresponde a um envolvido ativo no licenciamento (RT com `situacao = ATIVO`, RU ou Proprietário). Caso contrário, retorna HTTP 403.

**Passo 2 — Carregamento do licenciamento**
O sistema carrega a entidade `Licenciamento` com `id = idLicenciamento`. Se não existir, retorna HTTP 404.

**Passo 3 — Validação da situação (RN-109, RN-110)**
O sistema verifica se a situação atual do licenciamento permite extinção. As regras de validação diferenciam se já existe uma análise técnica registrada para o licenciamento:
- Se a situação estiver em lista de bloqueio incondicional → HTTP 422 com mensagem `licenciamento.extincao.invalida`.
- Se a situação estiver em lista de bloqueio condicional (sem análise) e não houver análise → HTTP 422.

**Passo 4 — Verificação de troca de envolvidos pendente (RN-115)**
O sistema verifica se há `TrocaEnvolvido` com situação em avaliação associada ao licenciamento. Se houver, retorna HTTP 422 com mensagem `licenciamento.extincao.invalida.troca.envolvidos`.

**Passo 5 — Cancelamento automático de recursos pendentes (RN-113)**
O sistema cancela automaticamente qualquer `Recurso` associado ao licenciamento que esteja em situação pendente de análise. Registra o marco `RECURSO_CANCELADO_EXTINCAO` para cada recurso cancelado.

**Passo 6 — Determinação do fluxo conforme envolvimento do RT (RN-111)**

*Caso A — Há RT ativo vinculado ao licenciamento e o solicitante não é o RT:*

- O sistema atualiza a situação do licenciamento para `AGUARDANDO_ACEITES_EXTINCAO`.
- Marca o campo `solicitanteExtincao = false` no `ResponsavelTecnico` correspondente ao usuário logado.
- Registra o marco `AGUARDANDO_ACEITE_EXTINCAO`.
- Envia notificação de e-mail ao RT informando que há uma solicitação de extinção aguardando seu aceite.
- Retorna HTTP 200 com DTO do licenciamento atualizado.

*Caso B — O solicitante é o próprio RT, ou não há RT ativo vinculado:*

- O sistema atualiza a situação do licenciamento para `EXTINGUIDO` (via `TrocaEstadoLicenciamentoParaExtinguidoRN`).
- Registra o marco `EXTINCAO`.
- Envia notificação de e-mail a todos os envolvidos (RT, RU, Proprietários).
- Retorna HTTP 200 com DTO do licenciamento atualizado.

---

## 5. Fluxo Alternativo — Extinção pelo Administrador

**Endpoint:** `POST /api/v1/adm/licenciamentos/{idLicenciamento}/extinguir`
**Ator:** Administrador do CBM-RS

**Passo 1 — Autenticação e autorização**
O sistema valida o token JWT e confirma que o usuário possui o perfil `ROLE_ADMIN` ou `ROLE_CBM_ADM`. Caso contrário, retorna HTTP 403.

**Passo 2 — Carregamento do licenciamento**
Idem ao Passo 2 do fluxo principal.

**Passo 3 — Validação da situação (RN-109, RN-110)**
Idem ao Passo 3 do fluxo principal. O Administrador está sujeito às mesmas regras de situação válida para extinção.

**Passo 4 — Verificação de troca de envolvidos pendente (RN-115)**
Idem ao Passo 4 do fluxo principal.

**Passo 5 — Cancelamento automático de recursos pendentes (RN-113)**
Idem ao Passo 5 do fluxo principal.

**Passo 6 — Extinção direta sem etapa de aceite do RT (RN-112)**
O Administrador tem poder de extinguir o licenciamento diretamente, independentemente de haver RT ativo e de seu aceite. O sistema:
- Atualiza a situação do licenciamento para `EXTINGUIDO`.
- Registra o marco `EXTINCAO`.
- Envia notificação de e-mail a todos os envolvidos (RT, RU, Proprietários).
- Retorna HTTP 200 com DTO do licenciamento atualizado.

---

## 6. Fluxo Alternativo — Recusa da Extinção (RT)

**Endpoint:** `PUT /api/v1/licenciamentos/{idLicenciamento}/recusa-extincao`
**Ator:** RT ativo vinculado ao licenciamento
**Situação esperada do licenciamento:** `AGUARDANDO_ACEITES_EXTINCAO`

**Passo 1 — Autenticação e autorização**
O sistema valida o token JWT e confirma que o usuário é o RT ativo do licenciamento. Caso contrário, retorna HTTP 403.

**Passo 2 — Validação da situação (RN-116)**
O sistema verifica que o licenciamento está em `AGUARDANDO_ACEITES_EXTINCAO`. Caso contrário, retorna HTTP 422.

**Passo 3 — Registro da recusa**
- O sistema atualiza o campo `aceiteExtincao = false` no `ResponsavelTecnico`.
- Restaura a situação anterior do licenciamento (situação antes do pedido de extinção) ou retorna para `APROVADO` conforme regra de negócio (ver RN-117).
- Registra o marco `RECUSA_EXTINCAO`.
- Envia notificação a todos os envolvidos informando a recusa.
- Retorna HTTP 200 com DTO atualizado.

---

## 7. Fluxo Alternativo — Cancelamento da Extinção

### 7.1 Cancelamento pelo Cidadão

**Endpoint:** `PUT /api/v1/licenciamentos/{idLicenciamento}/cancelar-extincao`
**Ator:** RT, RU ou Proprietário
**Situação esperada:** `AGUARDANDO_ACEITES_EXTINCAO`

**Passo 1 — Autenticação e autorização**
Valida que o ator é envolvido ativo no licenciamento.

**Passo 2 — Validação da situação (RN-116)**
Verifica que a situação é `AGUARDANDO_ACEITES_EXTINCAO`.

**Passo 3 — Registro do cancelamento**
- Restaura situação anterior do licenciamento (conforme RN-117).
- Limpa os campos de extinção no `ResponsavelTecnico` (zera `aceiteExtincao`, `solicitanteExtincao`, `dthAceiteExtincao`).
- Registra marco `CANCELAMENTO_EXTINCAO`.
- Envia notificação a todos os envolvidos.
- Retorna HTTP 200.

### 7.2 Cancelamento pelo Administrador

**Endpoint:** `PUT /api/v1/adm/licenciamentos/{idLicenciamento}/cancelar-extincao`
**Ator:** Administrador
**Situação esperada:** `AGUARDANDO_ACEITES_EXTINCAO`

Comportamento idêntico ao cancelamento pelo cidadão, porém sem restrição de ser envolvido do licenciamento. O Administrador pode cancelar extinções solicitadas por qualquer ator.

---

## 8. Regras de Negócio

### RN-109 — Situações que impedem extinção incondicionalmente

O licenciamento **não pode** ser extinguido quando estiver em nenhuma das seguintes situações, independentemente de existir análise técnica associada:

| Situação | Motivo do bloqueio |
|---|---|
| `ANALISE_INVIABILIDADE_PENDENTE` | Análise de inviabilidade em curso |
| `AGUARDA_DISTRIBUICAO_VISTORIA` | Vistoria aguardando distribuição |
| `ANALISE_ENDERECO_PENDENTE` | Análise de endereço em andamento |
| `AGUARDANDO_DISTRIBUICAO` | Aguardando distribuição para análise |
| `EM_ANALISE` | Em análise técnica ativa |
| `EM_VISTORIA` | Em vistoria presencial ativa |
| `RECURSO_EM_ANALISE_1_CIA` | Recurso de 1.ª instância CIA em análise |
| `RECURSO_EM_ANALISE_2_CIA` | Recurso de 2.ª instância CIA em análise |
| `RECURSO_EM_ANALISE_1_CIV` | Recurso de 1.ª instância CIV em análise |
| `RECURSO_EM_ANALISE_2_CIV` | Recurso de 2.ª instância CIV em análise |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | Aguardando distribuição para renovação |
| `EM_VISTORIA_RENOVACAO` | Em vistoria de renovação ativa |
| `EXTINGUIDO` | Já extinto (estado terminal) |

Ao tentar extinguir um licenciamento nessas situações, o sistema deve retornar HTTP 422 com código de erro `EXTINCAO_INVALIDA` e mensagem descritiva.

### RN-110 — Situações que impedem extinção apenas sem análise técnica

As situações a seguir impedem a extinção **somente se não existir nenhuma análise técnica registrada** para o licenciamento:

| Situação | Comportamento |
|---|---|
| `RASCUNHO` | Não pode extinguir se não há análise; pode extinguir se há análise |
| `AGUARDANDO_PAGAMENTO` | Idem |
| `AGUARDANDO_ACEITE` | Idem |

O sistema deve verificar a existência de ao menos um registro de análise técnica, análise de isenção, análise de endereço ou análise de inviabilidade vinculada ao licenciamento para determinar se a extinção é permitida.

### RN-111 — Extinção com RT ativo e envolvimento de aceite

Quando o licenciamento possui RT ativo (situação `ATIVO`) e o solicitante da extinção não é o próprio RT:

- A extinção não é efetivada imediatamente.
- O licenciamento entra em `AGUARDANDO_ACEITES_EXTINCAO`.
- O RT deve manifestar aceite ou recusa.
- O aceite do RT completa a extinção; a recusa reverte o estado.

Quando o solicitante é o próprio RT, a extinção é efetivada diretamente sem etapa de aceite.

Quando não há RT ativo vinculado ao licenciamento, a extinção é efetivada diretamente.

### RN-112 — Administrador efetua extinção direta

O Administrador do sistema pode extinguir qualquer licenciamento em situação válida diretamente, sem necessidade de aceite do RT. A extinção é processada e efetivada em uma única operação.

### RN-113 — Cancelamento automático de recursos pendentes

Ao extinguir um licenciamento (seja diretamente ou ao entrar em `AGUARDANDO_ACEITES_EXTINCAO`), o sistema deve cancelar automaticamente todos os `Recurso` associados ao licenciamento que estejam com situação de análise pendente. Para cada recurso cancelado, deve ser registrado o marco `RECURSO_CANCELADO_EXTINCAO`.

### RN-114 — Imutabilidade do licenciamento extinto

Um licenciamento com situação `EXTINGUIDO` não pode sofrer nenhuma alteração posterior (análises, vistorias, troca de envolvidos, emissão de boletos, emissão de APPCI/PRPCI). Qualquer tentativa de operação sobre licenciamento extinto deve retornar HTTP 422 com código `LICENCIAMENTO_EXTINGUIDO`.

### RN-115 — Bloqueio por troca de envolvidos em avaliação

Não é permitido extinguir um licenciamento que possua solicitação de `TrocaEnvolvido` com situação em avaliação (não concluída e não cancelada). O sistema deve retornar HTTP 422 com código `EXTINCAO_BLOQUEADA_TROCA_ENVOLVIDO`.

### RN-116 — Validação de estado para recusa e cancelamento

As operações de recusa (RT) e cancelamento (cidadão ou administrador) só são válidas quando o licenciamento estiver em `AGUARDANDO_ACEITES_EXTINCAO`. Qualquer tentativa em outro estado deve retornar HTTP 422 com código `OPERACAO_INVALIDA_SITUACAO`.

### RN-117 — Restauração da situação anterior após recusa ou cancelamento

Ao recusar ou cancelar uma solicitação de extinção, o sistema deve retornar o licenciamento à situação imediatamente anterior ao início do processo de extinção. O sistema deve armazenar a situação anterior no momento em que o licenciamento entra em `AGUARDANDO_ACEITES_EXTINCAO`, para possibilitar a restauração correta.

**Implementação recomendada:** Incluir coluna `situacao_anterior_extincao` na tabela `licenciamento`, preenchida ao entrar em `AGUARDANDO_ACEITES_EXTINCAO` e zerada ao concluir ou cancelar o processo.

### RN-118 — Campos de controle de extinção no Responsável Técnico

A entidade `ResponsavelTecnico` deve manter os seguintes campos de controle específicos para o processo de extinção:

| Campo | Tipo | Descrição |
|---|---|---|
| `aceiteExtincao` | `Boolean` | Indica se o RT aceitou (`true`), recusou (`false`) ou ainda não se manifestou (`null`) sobre a extinção |
| `solicitanteExtincao` | `Boolean` | Indica se o RT foi quem solicitou a extinção |
| `dthAceiteExtincao` | `LocalDateTime` | Data e hora em que o RT manifestou aceite ou recusa |

Esses campos devem ser zerados (nulos) ao cancelar uma solicitação de extinção ou ao concluir o processo.

### RN-119 — Notificação obrigatória a todos os envolvidos

Toda transição de estado relacionada ao processo de extinção (solicitação, aceite, recusa, cancelamento, conclusão) deve gerar notificação por e-mail a todos os envolvidos ativos do licenciamento:
- RT ativo (quando presente)
- RU ativo (quando presente)
- Proprietários ativos

O modelo de e-mail deve variar conforme o evento (ver Seção 13).

### RN-120 — Registro obrigatório de marco de auditoria

Toda transição de estado do processo de extinção deve gerar um marco de auditoria (`LicenciamentoMarco`) com o `TipoMarco` correspondente, o identificador do usuário responsável pela ação, a data e hora e a situação resultante do licenciamento.

---

## 9. API REST — Endpoints

### 9.1 Visão geral

Todos os endpoints são protegidos por autenticação OAuth2 com JWT (Bearer Token). A aplicação atua como **Resource Server** (`spring-security-oauth2-resource-server` + `spring-security-oauth2-jose`). O token é emitido por qualquer IdP compatível com OAuth2/OIDC configurado via `spring.security.oauth2.resourceserver.jwt.issuer-uri`.

**Prefixo base:** `/api/v1`
**Content-Type:** `application/json`
**Encoding:** UTF-8

### 9.2 Endpoints do Portal do Cidadão

#### POST `/api/v1/licenciamentos/{idLicenciamento}/extinguir`

Solicita extinção do licenciamento. Efetiva a extinção imediatamente quando o RT é o solicitante ou não há RT ativo; coloca em `AGUARDANDO_ACEITES_EXTINCAO` quando há RT ativo e o solicitante não é o RT.

| Atributo | Valor |
|---|---|
| Método HTTP | `POST` |
| Autenticação | Bearer JWT |
| Autorização | Envolvido ativo do licenciamento (RT, RU ou Proprietário) |
| Path variable | `idLicenciamento: Long` |
| Request body | Vazio |
| Response 200 | `LicenciamentoDTO` (situação atualizada) |
| Response 403 | Não autorizado |
| Response 404 | Licenciamento não encontrado |
| Response 422 | Situação inválida / Troca de envolvido pendente |

**Exemplo de resposta (situação intermediária):**
```json
{
  "id": 12345,
  "numeroPPCI": "A 00000361 AA 001",
  "situacao": "AGUARDANDO_ACEITES_EXTINCAO",
  "dataAtualizacao": "2026-03-13T14:30:00"
}
```

**Exemplo de resposta (extinção direta):**
```json
{
  "id": 12345,
  "numeroPPCI": "A 00000361 AA 001",
  "situacao": "EXTINGUIDO",
  "dataAtualizacao": "2026-03-13T14:30:00"
}
```

---

#### PUT `/api/v1/licenciamentos/{idLicenciamento}/recusa-extincao`

Permite ao RT recusar uma solicitação de extinção pendente.

| Atributo | Valor |
|---|---|
| Método HTTP | `PUT` |
| Autenticação | Bearer JWT |
| Autorização | RT ativo do licenciamento |
| Path variable | `idLicenciamento: Long` |
| Request body | Vazio |
| Response 200 | `LicenciamentoDTO` (situação restaurada) |
| Response 403 | Não autorizado (não é RT do licenciamento) |
| Response 404 | Licenciamento não encontrado |
| Response 422 | Licenciamento não está em `AGUARDANDO_ACEITES_EXTINCAO` |

---

#### PUT `/api/v1/licenciamentos/{idLicenciamento}/cancelar-extincao`

Permite ao cidadão (RT, RU ou Proprietário) cancelar uma solicitação de extinção pendente.

| Atributo | Valor |
|---|---|
| Método HTTP | `PUT` |
| Autenticação | Bearer JWT |
| Autorização | Envolvido ativo do licenciamento |
| Path variable | `idLicenciamento: Long` |
| Request body | Vazio |
| Response 200 | `LicenciamentoDTO` (situação restaurada) |
| Response 403 | Não autorizado |
| Response 404 | Licenciamento não encontrado |
| Response 422 | Licenciamento não está em `AGUARDANDO_ACEITES_EXTINCAO` |

---

### 9.3 Endpoints do Portal do Administrador

#### POST `/api/v1/adm/licenciamentos/{idLicenciamento}/extinguir`

Extinção direta pelo Administrador, sem necessidade de aceite do RT.

| Atributo | Valor |
|---|---|
| Método HTTP | `POST` |
| Autenticação | Bearer JWT |
| Autorização | `ROLE_ADMIN` ou `ROLE_CBM_ADM` |
| Path variable | `idLicenciamento: Long` |
| Request body | Vazio |
| Response 200 | `LicenciamentoDTO` (situacao = `EXTINGUIDO`) |
| Response 403 | Não autorizado |
| Response 404 | Licenciamento não encontrado |
| Response 422 | Situação inválida / Troca de envolvido pendente |

---

#### PUT `/api/v1/adm/licenciamentos/{idLicenciamento}/cancelar-extincao`

Cancela uma solicitação de extinção pendente.

| Atributo | Valor |
|---|---|
| Método HTTP | `PUT` |
| Autenticação | Bearer JWT |
| Autorização | `ROLE_ADMIN` ou `ROLE_CBM_ADM` |
| Path variable | `idLicenciamento: Long` |
| Request body | Vazio |
| Response 200 | `LicenciamentoDTO` (situação restaurada) |
| Response 422 | Licenciamento não está em `AGUARDANDO_ACEITES_EXTINCAO` |

---

#### GET `/api/v1/adm/licenciamentos/permissao-extincao`

Verifica se o usuário autenticado possui permissão para executar a ação de extinção.

| Atributo | Valor |
|---|---|
| Método HTTP | `GET` |
| Autenticação | Bearer JWT |
| Autorização | Qualquer usuário autenticado |
| Query params | `objeto: String` (default `EXTINCAO`); `acao: String` |
| Response 200 | `{ "possuiPermissao": true/false }` |

---

## 10. Modelo de Dados

### 10.1 Entidade principal: `Licenciamento`

Tabela: `licenciamento`

| Coluna | Tipo | Constraints | Descrição |
|---|---|---|---|
| `id` | `BIGINT` | PK, NOT NULL | Identificador único |
| `situacao` | `VARCHAR(60)` | NOT NULL | Situação atual (`SituacaoLicenciamento` enum) |
| `situacao_anterior_extincao` | `VARCHAR(60)` | NULL | Situação antes de entrar em `AGUARDANDO_ACEITES_EXTINCAO` — nova coluna para suporte ao P12 (RN-117) |
| `tipo_licenciamento` | `VARCHAR(20)` | NOT NULL | Tipo do licenciamento (PPCI, PSPCIM etc.) |
| `numero_ppci` | `VARCHAR(20)` | NULL | Número do documento gerado |
| `data_atualizacao` | `TIMESTAMP` | NOT NULL | Data/hora da última atualização |

*Nota: demais colunas omitidas; focam-se apenas as relevantes para P12.*

**Script Flyway (nova coluna):**
```sql
-- V12__add_situacao_anterior_extincao.sql
ALTER TABLE licenciamento
  ADD COLUMN situacao_anterior_extincao VARCHAR(60) NULL;

COMMENT ON COLUMN licenciamento.situacao_anterior_extincao
  IS 'Situação do licenciamento imediatamente antes de entrar em AGUARDANDO_ACEITES_EXTINCAO. Usada para restauração em caso de recusa ou cancelamento da extinção (P12, RN-117).';
```

---

### 10.2 Entidade: `ResponsavelTecnico`

Tabela: `responsavel_tecnico`

| Coluna | Tipo | Constraints | Descrição |
|---|---|---|---|
| `id` | `BIGINT` | PK | Identificador |
| `id_licenciamento` | `BIGINT` | FK → `licenciamento.id` | Licenciamento ao qual pertence |
| `cpf` | `VARCHAR(11)` | NOT NULL | CPF do RT |
| `situacao` | `VARCHAR(20)` | NOT NULL | Situação do vínculo RT-licenciamento (ATIVO, INATIVO etc.) |
| `aceite_extincao` | `BOOLEAN` | NULL | `true` = aceitou, `false` = recusou, `null` = não se manifestou (RN-118) |
| `solicitante_extincao` | `BOOLEAN` | NULL | Indica se o RT foi o solicitante da extinção (RN-118) |
| `dth_aceite_extincao` | `TIMESTAMP` | NULL | Data/hora da manifestação do RT (RN-118) |

*Mapeamento JPA:*
```java
@Entity
@Table(name = "responsavel_tecnico")
public class ResponsavelTecnico {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "seq_responsavel_tecnico")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "cpf", length = 11, nullable = false)
    private String cpf;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", length = 20, nullable = false)
    private SituacaoRT situacao;

    @Column(name = "aceite_extincao")
    private Boolean aceiteExtincao;

    @Column(name = "solicitante_extincao")
    private Boolean solicitanteExtincao;

    @Column(name = "dth_aceite_extincao")
    private LocalDateTime dthAceiteExtincao;

    // getters e setters omitidos
}
```

---

### 10.3 Entidade: `LicenciamentoMarco`

Tabela: `licenciamento_marco`

| Coluna | Tipo | Constraints | Descrição |
|---|---|---|---|
| `id` | `BIGINT` | PK | Identificador |
| `id_licenciamento` | `BIGINT` | FK → `licenciamento.id` | Licenciamento relacionado |
| `tipo_marco` | `VARCHAR(60)` | NOT NULL | Tipo de evento (`TipoMarco` enum) |
| `cpf_responsavel` | `VARCHAR(11)` | NULL | CPF do usuário que originou o evento |
| `data_hora` | `TIMESTAMP` | NOT NULL | Data/hora do evento |
| `situacao_resultante` | `VARCHAR(60)` | NULL | Situação do licenciamento após o evento |
| `descricao` | `TEXT` | NULL | Descrição complementar |

---

### 10.4 Enum `SituacaoLicenciamento` — valores relevantes para P12

```java
public enum SituacaoLicenciamento {
    RASCUNHO,
    AGUARDANDO_PAGAMENTO,
    AGUARDANDO_ACEITE,
    ANALISE_INVIABILIDADE_PENDENTE,
    AGUARDA_DISTRIBUICAO_VISTORIA,
    ANALISE_ENDERECO_PENDENTE,
    AGUARDANDO_DISTRIBUICAO,
    EM_ANALISE,
    EM_VISTORIA,
    RECURSO_EM_ANALISE_1_CIA,
    RECURSO_EM_ANALISE_2_CIA,
    RECURSO_EM_ANALISE_1_CIV,
    RECURSO_EM_ANALISE_2_CIV,
    AGUARDANDO_DISTRIBUICAO_RENOV,
    EM_VISTORIA_RENOVACAO,
    AGUARDANDO_ACEITES_EXTINCAO,  // Estado intermediário P12
    APROVADO,
    ALVARA_VIGENTE,
    ALVARA_VENCIDO,
    EXTINGUIDO                     // Estado terminal P12
}
```

---

### 10.5 Enum `TipoMarco` — valores relevantes para P12

```java
public enum TipoMarco {
    // ... outros marcos de processos anteriores ...
    EXTINCAO,
    AGUARDANDO_ACEITE_EXTINCAO,
    RECUSA_EXTINCAO,
    CANCELAMENTO_EXTINCAO,
    RECURSO_CANCELADO_EXTINCAO
}
```

---

### 10.6 DTO de Resposta

```java
public record LicenciamentoDTO(
    Long id,
    String numeroPPCI,
    SituacaoLicenciamento situacao,
    LocalDateTime dataAtualizacao
) {}
```

---

## 11. Máquina de Estados do Licenciamento

### 11.1 Transições relacionadas ao P12

```
[QUALQUER ESTADO VÁLIDO]
        |
        | POST /extinguir (RT solicitante, ou sem RT ativo)
        |
        v
   [EXTINGUIDO] ——————————————————————————————> (estado terminal)

[QUALQUER ESTADO VÁLIDO]
        |
        | POST /extinguir (RU/Proprietário/Admin, com RT ativo)
        |
        v
[AGUARDANDO_ACEITES_EXTINCAO]
        |                    |
        | RT aceita          | RT recusa / qualquer ator cancela
        v                    v
   [EXTINGUIDO]      [ESTADO ANTERIOR RESTAURADO]
                      (conforme coluna situacao_anterior_extincao)
```

### 11.2 Estados que bloqueiam extinção — diagrama de estados

```
Estados BLOQUEADORES (incondicionais):
  ANALISE_INVIABILIDADE_PENDENTE
  AGUARDA_DISTRIBUICAO_VISTORIA
  ANALISE_ENDERECO_PENDENTE
  AGUARDANDO_DISTRIBUICAO
  EM_ANALISE
  EM_VISTORIA
  RECURSO_EM_ANALISE_1_CIA / 2_CIA
  RECURSO_EM_ANALISE_1_CIV / 2_CIV
  AGUARDANDO_DISTRIBUICAO_RENOV
  EM_VISTORIA_RENOVACAO
  EXTINGUIDO

Estados BLOQUEADORES apenas sem análise:
  RASCUNHO
  AGUARDANDO_PAGAMENTO
  AGUARDANDO_ACEITE

Estados que PERMITEM extinção (com ou sem análise):
  APROVADO
  ALVARA_VIGENTE
  ALVARA_VENCIDO
  (E os estados do grupo "sem análise" quando há análise registrada)
```

---

## 12. Marcos de Auditoria

| Tipo de Marco | Evento que o origina | Ator responsável |
|---|---|---|
| `AGUARDANDO_ACEITE_EXTINCAO` | Licenciamento entra em `AGUARDANDO_ACEITES_EXTINCAO` após solicitação de extinção por RU/Proprietário | Cidadão solicitante |
| `EXTINCAO` | Licenciamento é efetivamente extinguido (`EXTINGUIDO`) | Cidadão solicitante ou Administrador |
| `RECUSA_EXTINCAO` | RT recusa a solicitação de extinção | RT |
| `CANCELAMENTO_EXTINCAO` | Cidadão ou Administrador cancela a solicitação de extinção | Cidadão ou Administrador |
| `RECURSO_CANCELADO_EXTINCAO` | Recurso ativo é cancelado automaticamente durante o processo de extinção | Sistema (automático) |

**Implementação do registro de marco:**
```java
@Service
@Transactional
public class ExtincaoService {

    private final LicenciamentoRepository licenciamentoRepo;
    private final LicenciamentoMarcoRepository marcoRepo;
    private final NotificacaoService notificacaoService;

    public void registrarMarco(Licenciamento licenciamento,
                               TipoMarco tipoMarco,
                               String cpfResponsavel) {
        LicenciamentoMarco marco = new LicenciamentoMarco();
        marco.setLicenciamento(licenciamento);
        marco.setTipoMarco(tipoMarco);
        marco.setCpfResponsavel(cpfResponsavel);
        marco.setDataHora(LocalDateTime.now());
        marco.setSituacaoResultante(licenciamento.getSituacao());
        marcoRepo.save(marco);
    }
}
```

---

## 13. Notificações por E-mail

### 13.1 Infraestrutura recomendada

Na stack moderna, sem PROCERGS, as notificações por e-mail devem ser enviadas via **Spring Mail** (`spring-boot-starter-mail`) com templates **Thymeleaf** (`spring-boot-starter-thymeleaf`). Não há dependência de nenhum serviço de e-mail estadual.

**Configuração (`application.yml`):**
```yaml
spring:
  mail:
    host: ${SMTP_HOST}
    port: ${SMTP_PORT:587}
    username: ${SMTP_USERNAME}
    password: ${SMTP_PASSWORD}
    properties:
      mail.smtp.auth: true
      mail.smtp.starttls.enable: true
```

### 13.2 Eventos e templates

| Evento | Template Thymeleaf | Destinatários |
|---|---|---|
| Solicitação de extinção (com etapa de aceite RT) | `email/extincao-aguardando-aceite-rt.html` | RT ativo |
| Extinção efetivada | `email/extincao-concluida.html` | RT, RU, todos os Proprietários ativos |
| Recusa de extinção pelo RT | `email/extincao-recusada.html` | RU, Proprietários e demais envolvidos |
| Cancelamento de extinção | `email/extincao-cancelada.html` | RT, RU, todos os Proprietários ativos |

### 13.3 Variáveis disponíveis nos templates

| Variável | Tipo | Descrição |
|---|---|---|
| `numeroPPCI` | `String` | Número do PPCI/PSPCIM |
| `enderecoLicenciamento` | `String` | Endereço do estabelecimento |
| `nomeResponsavel` | `String` | Nome do ator que realizou a ação |
| `dataEvento` | `String` | Data/hora formatada do evento |
| `linkSistema` | `String` | URL de acesso ao portal SOL |

### 13.4 Serviço de notificação

```java
@Service
public class NotificacaoService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;

    @Async
    public void enviarEmailExtincao(List<String> destinatarios,
                                   String templateName,
                                   Map<String, Object> variaveis) {
        Context context = new Context(new Locale("pt", "BR"));
        context.setVariables(variaveis);
        String conteudo = templateEngine.process(templateName, context);

        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, "UTF-8");
        helper.setTo(destinatarios.toArray(new String[0]));
        helper.setSubject(variaveis.get("assunto").toString());
        helper.setText(conteudo, true);
        mailSender.send(message);
    }
}
```

O envio de e-mail deve ser assíncrono (`@Async`) para não bloquear a transação principal.

---

## 14. Segurança e Autorização

### 14.1 Modelo de autenticação

A aplicação implementa o padrão **OAuth2 Resource Server** com validação de tokens JWT. Não há dependência do IdP PROCERGS/SOE. O IdP pode ser qualquer servidor compatível com OAuth2/OIDC (Keycloak, Auth0, Azure AD, etc.), configurado via:

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${OAUTH2_ISSUER_URI}
```

### 14.2 Controle de acesso por endpoint

| Endpoint | Roles permitidas | Verificação adicional |
|---|---|---|
| `POST /licenciamentos/{id}/extinguir` | Qualquer usuário autenticado | Deve ser envolvido ativo (RT, RU ou Proprietário) do licenciamento |
| `PUT /licenciamentos/{id}/recusa-extincao` | Qualquer usuário autenticado | Deve ser RT ativo do licenciamento |
| `PUT /licenciamentos/{id}/cancelar-extincao` | Qualquer usuário autenticado | Deve ser envolvido ativo do licenciamento |
| `POST /adm/licenciamentos/{id}/extinguir` | `ROLE_ADMIN`, `ROLE_CBM_ADM` | Nenhuma — admin tem acesso irrestrito |
| `PUT /adm/licenciamentos/{id}/cancelar-extincao` | `ROLE_ADMIN`, `ROLE_CBM_ADM` | Nenhuma |
| `GET /adm/licenciamentos/permissao-extincao` | Qualquer autenticado | Verifica permissão via tabela de permissões |

### 14.3 Verificação de envolvimento

A verificação de que o usuário autenticado é envolvido ativo do licenciamento deve ser implementada como um **Spring Security Method Security** (`@PreAuthorize`) em combinação com um `PermissionEvaluator`, ou como um aspecto (`@Aspect`) que intercepta chamadas de serviço.

**Exemplo com `@PreAuthorize`:**
```java
@PreAuthorize("@licenciamentoSecurity.isEnvolvidoAtivo(#idLicenciamento, authentication)")
@PostMapping("/{idLicenciamento}/extinguir")
public ResponseEntity<LicenciamentoDTO> extinguir(@PathVariable Long idLicenciamento) {
    // ...
}
```

```java
@Component("licenciamentoSecurity")
public class LicenciamentoSecurityEvaluator {

    private final EnvolvidoRepository envolvidoRepo;

    public boolean isEnvolvidoAtivo(Long idLicenciamento, Authentication auth) {
        String cpf = extractCpf(auth);
        return envolvidoRepo.existsEnvolvidoAtivo(idLicenciamento, cpf);
    }
}
```

### 14.4 Proteção contra modificação de licenciamento extinto (RN-114)

Implementar um interceptor de serviço (ou aspecto) que, antes de qualquer operação de modificação, verifique se o licenciamento está com situação `EXTINGUIDO` e, nesse caso, lance exceção de negócio com código `LICENCIAMENTO_EXTINGUIDO`.

---

## 15. Tratamento de Erros e Testes

### 15.1 Códigos de erro e respostas HTTP

| Código de Erro | HTTP Status | Mensagem (pt-BR) | Situação |
|---|---|---|---|
| `LICENCIAMENTO_NAO_ENCONTRADO` | 404 | "Licenciamento não encontrado." | `idLicenciamento` inexistente |
| `ACESSO_NEGADO` | 403 | "Acesso não autorizado para este licenciamento." | Usuário não é envolvido ativo |
| `EXTINCAO_INVALIDA` | 422 | "Licenciamento não pode ser extinguido na situação atual." | Situações bloqueadoras (RN-109, RN-110) |
| `EXTINCAO_BLOQUEADA_TROCA_ENVOLVIDO` | 422 | "Licenciamento não pode ser extinguido pois possui solicitação de troca de envolvido em avaliação." | Troca de envolvido pendente (RN-115) |
| `OPERACAO_INVALIDA_SITUACAO` | 422 | "Operação inválida para a situação atual do licenciamento." | Recusa/cancelamento fora de `AGUARDANDO_ACEITES_EXTINCAO` (RN-116) |
| `LICENCIAMENTO_EXTINGUIDO` | 422 | "Licenciamento encontra-se extinto e não pode ser modificado." | Tentativa de operação em licenciamento extinto (RN-114) |

**Formato padrão de erro:**
```json
{
  "timestamp": "2026-03-13T14:30:00",
  "status": 422,
  "error": "EXTINCAO_INVALIDA",
  "message": "Licenciamento não pode ser extinguido na situação atual.",
  "path": "/api/v1/licenciamentos/12345/extinguir"
}
```

Implementar via `@RestControllerAdvice`:
```java
@RestControllerAdvice
public class ExtincaoExceptionHandler {

    @ExceptionHandler(ExtincaoInvalidaException.class)
    public ResponseEntity<ErrorResponse> handleExtincaoInvalida(
            ExtincaoInvalidaException ex, HttpServletRequest req) {
        return ResponseEntity.unprocessableEntity()
            .body(new ErrorResponse(
                LocalDateTime.now(), 422, "EXTINCAO_INVALIDA",
                ex.getMessage(), req.getRequestURI()
            ));
    }
    // ... demais handlers
}
```

### 15.2 Cenários de teste obrigatórios

Os seguintes cenários devem ser cobertos por testes automatizados (JUnit 5 + Mockito para unitários; Spring Boot Test + Testcontainers para integração):

#### Cenários de extinção por cidadão:
- **TC-P12-01:** RT extingue licenciamento em `APROVADO` → situação muda para `EXTINGUIDO`, marco `EXTINCAO` registrado, e-mails enviados.
- **TC-P12-02:** RU extingue licenciamento com RT ativo → situação muda para `AGUARDANDO_ACEITES_EXTINCAO`, marco `AGUARDANDO_ACEITE_EXTINCAO` registrado, e-mail enviado ao RT.
- **TC-P12-03:** RT aceita extinção → situação muda para `EXTINGUIDO`, marco `EXTINCAO` registrado.
- **TC-P12-04:** RT recusa extinção → situação é restaurada para estado anterior (RN-117), marco `RECUSA_EXTINCAO` registrado.
- **TC-P12-05:** Tentativa de extinção em `EM_ANALISE` → HTTP 422, código `EXTINCAO_INVALIDA`.
- **TC-P12-06:** Tentativa de extinção em `RASCUNHO` sem análise → HTTP 422.
- **TC-P12-07:** Tentativa de extinção em `RASCUNHO` com análise → extinção permitida, situação muda para `EXTINGUIDO`.
- **TC-P12-08:** Extinção com recurso pendente → recurso cancelado automaticamente, marco `RECURSO_CANCELADO_EXTINCAO` registrado.
- **TC-P12-09:** Extinção com troca de envolvido em avaliação → HTTP 422, código `EXTINCAO_BLOQUEADA_TROCA_ENVOLVIDO`.
- **TC-P12-10:** Tentativa de operação em licenciamento já `EXTINGUIDO` → HTTP 422, código `LICENCIAMENTO_EXTINGUIDO`.
- **TC-P12-11:** Cancelamento de extinção por cidadão → situação restaurada, marco `CANCELAMENTO_EXTINCAO` registrado.
- **TC-P12-12:** Usuário não envolvido tenta extinguir → HTTP 403.

#### Cenários de extinção pelo administrador:
- **TC-P12-13:** Admin extingue licenciamento com RT ativo → extinção direta sem etapa de aceite, situação `EXTINGUIDO`.
- **TC-P12-14:** Admin extingue licenciamento em situação bloqueadora → HTTP 422.
- **TC-P12-15:** Admin cancela extinção pendente → situação restaurada, marco `CANCELAMENTO_EXTINCAO` registrado.

### 15.3 Estrutura recomendada dos componentes Spring

```
com.cbmrs.sol.p12
├── controller
│   ├── ExtincaoLicenciamentoController.java        // POST, PUT cidadão
│   └── ExtincaoLicenciamentoAdmController.java     // POST, PUT admin
├── service
│   ├── ExtincaoService.java                        // Orquestra o fluxo
│   ├── ExtincaoValidacaoService.java               // Validações RN-109 a RN-116
│   └── NotificacaoExtincaoService.java             // Envio de e-mails
├── repository
│   ├── LicenciamentoRepository.java
│   ├── ResponsavelTecnicoRepository.java
│   ├── LicenciamentoMarcoRepository.java
│   └── TrocaEnvolvidoRepository.java
├── domain
│   ├── Licenciamento.java                          // @Entity
│   ├── ResponsavelTecnico.java                     // @Entity
│   ├── LicenciamentoMarco.java                     // @Entity
│   ├── SituacaoLicenciamento.java                  // @Enum
│   └── TipoMarco.java                              // @Enum
├── dto
│   ├── LicenciamentoDTO.java                       // @Record response
│   └── ErrorResponse.java                          // @Record error
├── exception
│   ├── ExtincaoInvalidaException.java
│   ├── ExtincaoBloqueadaTrocaEnvolvidoException.java
│   ├── OperacaoInvalidaSituacaoException.java
│   └── LicenciamentoExtintoException.java
└── security
    └── LicenciamentoSecurityEvaluator.java         // @PreAuthorize evaluator
```

### 15.4 Dependências Maven relevantes

```xml
<dependencies>
    <!-- Spring Boot Starters -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-mail</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-thymeleaf</artifactId>
    </dependency>
    <!-- Banco de dados -->
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-core</artifactId>
    </dependency>
    <!-- Validação -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>
    <!-- Testes -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.springframework.security</groupId>
        <artifactId>spring-security-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>postgresql</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```

---

## Apêndice — Rastreabilidade: Stack Atual × Stack Moderna

| Componente Stack Atual (Java EE) | Equivalente Stack Moderna (Spring Boot) |
|---|---|
| `@Stateless` EJB | `@Service` + `@Transactional` Spring |
| `@Inject` CDI | `@Autowired` / construtor Spring |
| JAX-RS `@Path`, `@POST`, `@PUT` | Spring MVC `@RestController`, `@PostMapping`, `@PutMapping` |
| `@TransactionAttribute(REQUIRED)` | `@Transactional` (default `REQUIRED`) |
| `JPA EntityManager` | `JpaRepository` / `@Repository` Spring Data |
| `@Singleton` EJBTimer | Spring `@Scheduled` (N/A para P12) |
| SOE PROCERGS (IdP) | OAuth2 Resource Server com qualquer IdP compatível com OIDC |
| `messages.properties` + ResourceBundle | `MessageSource` Spring + `messages_pt_BR.properties` |
| WildFly/JBoss deploy | Spring Boot embedded Tomcat / jar executável |
| Oracle DDL (`VARCHAR2`, `NUMBER`) | PostgreSQL DDL (`VARCHAR`, `BIGINT`) |
| Liquibase changelogs | Flyway versioned migrations (`V__*.sql`) |
| `@AutorizaEnvolvido` interceptor CDI | `@PreAuthorize` com `SecurityEvaluator` Spring Security |
| `NotificacaoRN` + JavaMail API Java EE | `NotificacaoService` + Spring Mail (`JavaMailSender`) |
| Templates de e-mail em properties | Templates Thymeleaf (`src/main/resources/templates/email/`) |
| `SimNaoBooleanConverter` JPA | `AttributeConverter<Boolean, String>` JPA 2.1 (mantido) |


---

## 16. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 04 (ID1501, Demanda 25) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022 (item 6.3.2.1.1).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P12.

---

### RN-P12-N1 — Extinção como Único Caminho para Alterar Dados do Passo 2 🔴 P12-M1

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Correção 4 / Norma + ID1501 — RT de Implantação SOL-CBMRS item 6.3.2.1.1

**Descrição:** A RT de Implantação estabelece que a extinção é o **único meio legítimo** de corrigir os campos do Passo 2 (endereço, coordenadas, isolamento de risco) após o primeiro envio. O P12 deve suportar explicitamente esse caso de uso.

**Novo motivo de extinção:**

```java
public enum MotivoExtincao {
    SOLICITACAO_PROPRIETARIO        ("Solicitação do proprietário"),
    ENCERRAMENTO_ATIVIDADE          ("Encerramento da atividade"),
    DUPLICIDADE_PROTOCOLO           ("Duplicidade de protocolo"),
    CORRECAO_DADOS_PASSO2           ("Correção de dados do Passo 2 (endereço/isolamento de risco)"),
    // demais motivos existentes...
    OUTROS                          ("Outros");
}
```

**Mudança no fluxo — ao selecionar `CORRECAO_DADOS_PASSO2`:**

```
Cidadão seleciona motivo "Correção de dados do Passo 2"
        │
        ▼
Sistema exibe aviso normativo:
"Um novo processo deverá ser aberto com os dados corrigidos.
 As taxas pagas no processo atual NÃO serão reaproveitadas."
        │
   [Confirmar extinção] ──────────────────────────────────────────►
                                                           Extinção registrada
                                                                  │
                                                                  ▼
                                                   Sistema direciona para
                                                   início de novo Wizard P03
                                                   (pré-preenchido com dados
                                                    não alterados do Passo 1)
```

**Evento de fim da extinção por Passo 2:**
```java
// ExtincaoService.java — processar()
public void processarExtincao(Licenciamento lic, MotivoExtincao motivo) {
    // ... lógica de extinção existente ...
    
    if (MotivoExtincao.CORRECAO_DADOS_PASSO2.equals(motivo)) {
        // Preparar pré-preenchimento do novo processo
        DadosPreenchimentoWizard preenchimento = DadosPreenchimentoWizard.builder()
            .idLicenciamentoOrigem(lic.getId())
            .envolvidos(lic.getEnvolvidos())
            // NÃO incluir dados do Passo 2 — devem ser preenchidos novamente
            .build();
        return new ExtincaoResult(true, preenchimento);
    }
}
```

**Critérios de Aceitação:**
- [ ] CA-P12-N1a: Motivo "Correção de dados do Passo 2" aparece na lista de motivos de extinção
- [ ] CA-P12-N1b: Ao selecionar esse motivo, aviso normativo é exibido informando que taxas não são reaproveitadas
- [ ] CA-P12-N1c: Após extinção, sistema direciona para início de novo Wizard P03
- [ ] CA-P12-N1d: Novo wizard não pré-preenche os campos do Passo 2 (devem ser informados novamente)
- [ ] CA-P12-N1e: Marco do processo extinto registra: "Processo extinto para correção de dados do Passo 2"

---

### RN-P12-N2 — APPCIs Vencidos Permanecem Visíveis no Histórico 🟠 P12-M2

**Prioridade:** Alta  
**Origem:** Demanda 25 — Sprint 04 Hammer

**Descrição:** Atualmente APPCIs vencidos são removidos da listagem principal, tornando difícil a consulta histórica. O sistema deve manter APPCIs vencidos acessíveis na aba "Histórico".

**Mudança nas queries de listagem:**

```java
// LicenciamentoRepository.java

// Listagem ATIVA — apenas vigentes (comportamento existente, sem mudança)
@Query("SELECT l FROM Licenciamento l WHERE l.status = 'ALVARA_VIGENTE'")
List<Licenciamento> findAlvarasVigentes();

// Listagem HISTÓRICO — inclui vencidos (NOVO)
@Query("SELECT l FROM Licenciamento l WHERE l.status IN ('ALVARA_VIGENTE', 'ALVARA_VENCIDO')")
List<Licenciamento> findAlvarasParaHistorico();
```

**Mudança na tela de listagem:**

```typescript
// licenciamento-lista.component.ts
tabs = [
  { label: 'Processos Ativos',  query: { status: ['VIGENTE', 'EM_ANALISE', ...] } },
  { label: 'Histórico',         query: { status: ['ALVARA_VIGENTE', 'ALVARA_VENCIDO'] } },
];
```

**Critérios de Aceitação:**
- [ ] CA-P12-N2a: Aba "Histórico" exibe APPCIs com status `ALVARA_VIGENTE` e `ALVARA_VENCIDO`
- [ ] CA-P12-N2b: Listagem ativa continua filtrando apenas `ALVARA_VIGENTE`
- [ ] CA-P12-N2c: APPCI vencido exibe claramente o status "Vencido" e a data de vencimento

---

### Resumo das Mudanças P12 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P12-M1 | RN-P12-N1 | Extinção por necessidade de correção do Passo 2 — novo motivo (OBRIGATÓRIO) | 🔴 Crítica |
| P12-M2 | RN-P12-N2 | APPCIs vencidos permanecem visíveis no histórico (correção de comportamento) | 🟠 Alta |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprint 04 + Normas RTCBMRS*
