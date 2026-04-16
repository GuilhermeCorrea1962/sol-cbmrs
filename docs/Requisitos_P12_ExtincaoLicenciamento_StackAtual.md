# Requisitos — P12: Extinção de Licenciamento
## Versão Stack Atual (Java EE — CBM-RS SOL)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P12 — Extinção de Licenciamento
**Stack:** Java EE 7 · JAX-RS · CDI · EJB `@Stateless` · JPA/Hibernate · Oracle · WildFly/JBoss
**Versão do documento:** 1.0
**Data:** 2026-03-13
**Referência:** US172 · `LicenciamentoCidadaoExtincaoRN` · `LicenciamentoCidadaoExtincaoRNVal` · `TrocaEstadoLicenciamentoParaExtinguidoRN`

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
11. [Máquina de Estados](#11-máquina-de-estados)
12. [Marcos de Auditoria (TipoMarco)](#12-marcos-de-auditoria-tipmarco)
13. [Notificações por E-mail](#13-notificações-por-e-mail)
14. [Segurança e Autorização](#14-segurança-e-autorização)
15. [Classes e Componentes Java EE](#15-classes-e-componentes-java-ee)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P12 é responsável pela **extinção formal de um licenciamento** ativo no SOL. A extinção encerra permanentemente o ciclo de vida de um licenciamento (PPCI, PSPCIM ou outro tipo amparado pelo sistema), alterando sua `SituacaoLicenciamento` para `EXTINGUIDO`.

A extinção pode ser solicitada por atores do portal do cidadão (RT, RU ou Proprietário) ou executada diretamente por um Administrador do CBM-RS via portal de administração. Quando o RT está vinculado ao licenciamento e não é o solicitante, o processo exige aceite explícito do RT antes de efetivar a extinção — o licenciamento entra em estado intermediário `AGUARDANDO_ACEITES_EXTINCAO`.

### 1.2 Resultados possíveis

| Desfecho | Situação final |
|---|---|
| Extinção efetivada | `EXTINGUIDO` |
| Aguardando aceite do RT | `AGUARDANDO_ACEITES_EXTINCAO` (estado transitório) |
| Recusa pelo RT | Situação anterior restaurada |
| Cancelamento | Situação anterior restaurada |

### 1.3 Referência na base de código

| Componente | Localização |
|---|---|
| Regra de negócio principal | `com.procergs.solcbm.licenciamento.LicenciamentoCidadaoExtincaoRN` |
| Validação | `com.procergs.solcbm.licenciamento.LicenciamentoCidadaoExtincaoRNVal` |
| Troca de estado | `com.procergs.solcbm.licenciamento.trocaestado.TrocaEstadoLicenciamentoParaExtinguidoRN` |
| REST cidadão | `com.procergs.solcbm.remote.LicenciamentoRest` |
| REST administrador | `com.procergs.solcbm.remote.adm.LicenciamentoAdmRestImpl` |
| Testes BDD | `cucumber/ExcluirOuExtinguirLicenciamento/negocio/US172-ExcluirOuExtinguirLicenciamento.feature` |
| Changelog DB | `liquibase/changelog/s28.us172.changelog.xml` |

---

## 2. Atores e Papéis

| Ator | Perfil no sistema | Ações permitidas |
|---|---|---|
| **RT** (Responsável Técnico) | Usuário autenticado via SOE PROCERGS, credenciado como RT no licenciamento | Solicitar extinção; aceitar extinção solicitada por outro ator; recusar extinção; cancelar solicitação de extinção |
| **RU** (Responsável pelo Uso) | Usuário autenticado via SOE PROCERGS, vinculado como RU no licenciamento | Solicitar extinção; cancelar solicitação de extinção |
| **Proprietário** | Usuário autenticado via SOE PROCERGS, vinculado como proprietário no licenciamento | Solicitar extinção; cancelar solicitação de extinção |
| **Administrador** | Servidor do CBM-RS, perfil ADM no portal de administração | Extinguir diretamente (sem etapa de aceite RT); cancelar extinção em andamento; verificar permissão de extinção |
| **Sistema SOL** | Processo interno (EJB transacional) | Registrar marcos; enviar notificações; cancelar recursos pendentes; atualizar situação do licenciamento |

---

## 3. Pré-condições e Contexto de Entrada

### 3.1 Pré-condições

- O licenciamento identificado por `idLicenciamento` deve existir (`LicenciamentoED` com `id` correspondente).
- O usuário autenticado deve ser envolvido ativo do licenciamento (verificado via `@AutorizaEnvolvido` e `@SegurancaEnvolvidoInterceptor`).
- A situação atual do licenciamento deve permitir extinção (ver RN-109 e RN-110).
- Não pode haver `TrocaEnvolvido` em avaliação para o licenciamento (ver RN-115).

### 3.2 Dados de entrada

| Dado | Tipo | Origem | Observação |
|---|---|---|---|
| `idLic` | `Long` | Path variable JAX-RS | Identificador do licenciamento |
| Token de sessão OIDC | Header HTTP | SOE PROCERGS (meu.rs.gov.br) | Validado pelo interceptor `@SegurancaEnvolvidoInterceptor` |

---

## 4. Fluxo Principal — Extinção pelo Cidadão

**Endpoint:** `POST /licenciamentos/{idLic}/extinguir`
**Classe:** `LicenciamentoRest.extinguir(Long idLic)`
**EJB de negócio:** `LicenciamentoCidadaoExtincaoRN.extingue(Long idLicenciamento)`

### Passo 1 — Interceptação e autorização
O `@SegurancaEnvolvidoInterceptor` valida que o usuário autenticado é envolvido ativo do licenciamento. A anotação `@AutorizaEnvolvido` no método REST ativa esse interceptor. Em caso de falha, retorna HTTP 403.

### Passo 2 — Carregamento do licenciamento
O EJB carrega o `LicenciamentoED` via `EntityManager.find(LicenciamentoED.class, idLicenciamento)`. Se não encontrado, lança exceção mapeada para HTTP 404.

### Passo 3 — Validação da situação (RN-109, RN-110)
`LicenciamentoCidadaoExtincaoRNVal.validarExtinguir(licenciamento, existeAnalise)` verifica:
- Se a situação está em `SITUACOES_INVALIDAS` → lança `NegocioException` com mensagem `licenciamento.extincao.invalida`.
- Se a situação está em `SITUACOES_INVALIDAS_SEM_ANALISE` e não existe análise associada → lança `NegocioException`.

### Passo 4 — Verificação de troca de envolvidos pendente (RN-115)
O EJB consulta `TrocaEnvolvidoDAO` para verificar existência de `TrocaEnvolvido` em situação de avaliação para o licenciamento. Se houver, lança `NegocioException` com mensagem `licenciamento.extincao.invalida.troca.envolvidos`.

### Passo 5 — Cancelamento automático de recursos pendentes (RN-113)
`RecursoRN.cancelarPorExtincao(idLicenciamento)` cancela todos os recursos pendentes e registra o marco `RECURSO_CANCELADO_EXTINCAO` para cada um.

### Passo 6 — Decisão pelo perfil do solicitante e presença de RT (RN-111)

**Caso A — Solicitante é RT, ou não há RT ativo:**
- `TrocaEstadoLicenciamentoRN.trocaEstado(idLicenciamento, PARA_EXTINGUIDO)` é chamado.
- Situação do licenciamento atualizada para `EXTINGUIDO`.
- Marco `EXTINCAO` registrado.
- Notificação enviada a todos os envolvidos.

**Caso B — Solicitante não é RT e há RT ativo:**
- Situação do licenciamento atualizada para `AGUARDANDO_ACEITES_EXTINCAO`.
- Campo `solicitanteExtincao = false` gravado no `ResponsavelTecnicoED` do RT.
- Marco `AGUARDANDO_ACEITE_EXTINCAO` registrado.
- E-mail enviado ao RT solicitando aceite.

### Passo 7 — Resposta
O endpoint retorna HTTP 200 com o DTO do licenciamento atualizado (`LicenciamentoDTO`).

---

## 5. Fluxo Alternativo — Extinção pelo Administrador

**Endpoint:** `POST /adm/licenciamentos/{idLic}/extinguir`
**Classe:** `LicenciamentoAdmRestImpl.extinguir(Long idLic)`
**EJB de negócio:** `LicenciamentoCidadaoExtincaoRN.extingueAdm(Long idLicenciamento)`

Diferentemente do fluxo cidadão, o Administrador não está sujeito ao mecanismo de aceite do RT. O fluxo é idêntico ao Caso A do Passo 6 acima:
- Validações de situação (RN-109, RN-110) são aplicadas.
- Recursos pendentes são cancelados.
- Licenciamento é extinguido diretamente.
- Marco `EXTINCAO` registrado.
- Notificação enviada.

---

## 6. Fluxo Alternativo — Recusa da Extinção (RT)

**Endpoint:** `PUT /licenciamentos/{idLic}/recusa-extincao`
**Classe:** `LicenciamentoRest.recusaExtincao(Long idLic)`
**EJB de negócio:** `LicenciamentoCidadaoExtincaoRN.recusa(Long idLicenciamento)`

**Pré-condição:** Licenciamento em `AGUARDANDO_ACEITES_EXTINCAO`. O usuário autenticado é o RT ativo.

**Execução:**
1. Valida que a situação é `AGUARDANDO_ACEITES_EXTINCAO` (RN-116).
2. Grava `aceiteExtincao = false` e `dthAceiteExtincao = now()` no `ResponsavelTecnicoED`.
3. Restaura a situação anterior do licenciamento (RN-117).
4. Registra marco `RECUSA_EXTINCAO`.
5. Envia notificação a todos os envolvidos.
6. Retorna HTTP 200.

---

## 7. Fluxo Alternativo — Cancelamento da Extinção

### 7.1 Cancelamento pelo Cidadão

**Endpoint:** `PUT /licenciamentos/{idLic}/cancelar-extincao`
**Classe:** `LicenciamentoRest.cancelarExtincao(Long idLic)`
**EJB de negócio:** `LicenciamentoCidadaoExtincaoRN.cancelar(Long idLicenciamento)`

**Pré-condição:** Licenciamento em `AGUARDANDO_ACEITES_EXTINCAO`. Usuário é envolvido ativo.

**Execução:**
1. Valida que a situação é `AGUARDANDO_ACEITES_EXTINCAO` (RN-116).
2. Limpa campos de extinção no `ResponsavelTecnicoED` (zera `aceiteExtincao`, `solicitanteExtincao`, `dthAceiteExtincao`).
3. Restaura a situação anterior do licenciamento (RN-117).
4. Registra marco `CANCELAMENTO_EXTINCAO`.
5. Envia notificação a todos os envolvidos.
6. Retorna HTTP 200.

### 7.2 Cancelamento pelo Administrador

**Endpoint:** `PUT /adm/licenciamentos/{idLic}/cancelar-extincao`
**Classe:** `LicenciamentoAdmRestImpl.cancelarExtincao(Long idLic)`
**EJB de negócio:** `LicenciamentoCidadaoExtincaoRN.cancelarAdm(Long idLicenciamento)`

Comportamento idêntico ao cancelamento pelo cidadão. O Administrador pode cancelar extinções iniciadas por qualquer ator.

---

## 8. Regras de Negócio

### RN-109 — Situações que impedem extinção incondicionalmente

As seguintes situações do licenciamento impedem a extinção de forma absoluta (independentemente de existir análise técnica registrada). A lista é mantida na constante `LicenciamentoCidadaoExtincaoRNVal.SITUACOES_INVALIDAS`:

| Situação | Motivo do bloqueio |
|---|---|
| `ANALISE_INVIABILIDADE_PENDENTE` | Análise de inviabilidade em andamento |
| `AGUARDA_DISTRIBUICAO_VISTORIA` | Vistoria aguardando distribuição |
| `ANALISE_ENDERECO_PENDENTE` | Análise de endereço pendente |
| `AGUARDANDO_DISTRIBUICAO` | Aguardando distribuição para análise |
| `EM_ANALISE` | Em análise técnica ativa |
| `EM_VISTORIA` | Em vistoria presencial ativa |
| `RECURSO_EM_ANALISE_1_CIA` | 1.ª instância CIA em análise |
| `RECURSO_EM_ANALISE_2_CIA` | 2.ª instância CIA em análise |
| `RECURSO_EM_ANALISE_1_CIV` | 1.ª instância CIV em análise |
| `RECURSO_EM_ANALISE_2_CIV` | 2.ª instância CIV em análise |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | Aguardando distribuição para renovação |
| `EM_VISTORIA_RENOVACAO` | Em vistoria de renovação ativa |
| `EXTINGUIDO` | Já extinto (estado terminal) |

Ao tentar extinguir em situação inválida, o sistema lança `NegocioException` com chave `licenciamento.extincao.invalida`.

### RN-110 — Situações que impedem extinção somente sem análise técnica

As situações a seguir só impedem extinção quando **não existe nenhuma análise técnica** (técnica, isenção, endereço ou inviabilidade) registrada para o licenciamento. Quando existe análise, a extinção é permitida. Essas situações estão na constante `SITUACOES_INVALIDAS_SEM_ANALISE`:

| Situação |
|---|
| `RASCUNHO` |
| `AGUARDANDO_PAGAMENTO` |
| `AGUARDANDO_ACEITE` |

O parâmetro `existeAnalise: Boolean` é calculado antes de chamar o validador, consultando se há registro em qualquer das tabelas de análise (ATEC, isenção, endereço, inviabilidade).

### RN-111 — Etapa de aceite do RT

Quando o licenciamento possui RT com situação `ATIVO` e o solicitante da extinção **não é** o próprio RT (identificado pelo CPF do usuário autenticado):
- A extinção não é efetivada imediatamente.
- O licenciamento transita para `AGUARDANDO_ACEITES_EXTINCAO`.
- Somente o aceite explícito do RT (via `PUT /recusa-extincao` com aceite implícito na ausência de recusa) efetiva a extinção.

Quando o solicitante é o próprio RT ou não há RT ativo, a extinção é efetivada diretamente.

### RN-112 — Extinção direta pelo Administrador

O Administrador extingue diretamente, sem etapa de aceite do RT, chamando `extingueAdm()`. Mesmo com RT ativo vinculado, a extinção é efetivada na mesma transação.

### RN-113 — Cancelamento automático de recursos

Antes de efetivar qualquer transição de extinção (para `AGUARDANDO_ACEITES_EXTINCAO` ou diretamente para `EXTINGUIDO`), o sistema cancela automaticamente todos os `RecursoED` do licenciamento que estejam em situação de análise pendente. Para cada recurso cancelado, registra o marco `RECURSO_CANCELADO_EXTINCAO`.

### RN-114 — Imutabilidade do licenciamento extinto

Um licenciamento com situação `EXTINGUIDO` não pode ser alterado por nenhuma operação do sistema (análise, vistoria, boleto, troca de envolvidos, emissão de APPCI/PRPCI). Qualquer tentativa retorna `NegocioException` com chave `licenciamento.extinguido`.

### RN-115 — Bloqueio por troca de envolvidos em avaliação

Não é permitido extinguir licenciamento que possua `TrocaEnvolvidoED` em situação de avaliação ativa (não cancelada, não concluída). O sistema retorna `NegocioException` com chave `licenciamento.extincao.invalida.troca.envolvidos`.

### RN-116 — Validação de estado para recusa e cancelamento

As operações `recusa()` e `cancelar()` exigem que o licenciamento esteja em `AGUARDANDO_ACEITES_EXTINCAO`. Qualquer tentativa em outro estado retorna `NegocioException` com chave `licenciamento.operacao.invalida.situacao`.

### RN-117 — Restauração da situação anterior

Ao recusar ou cancelar a extinção, o sistema restaura a `SituacaoLicenciamento` à situação imediatamente anterior ao pedido de extinção. A situação anterior é persistida (campo `situacaoAnteriorExtincao` ou lida do histórico de situações em `CBM_LICENCIAMENTO_SITUACAO_HIST`) para garantir restauração correta.

### RN-118 — Campos de controle no `ResponsavelTecnicoED`

O `ResponsavelTecnicoED` mantém três campos específicos para controle da extinção:

| Campo (`ED`) | Coluna (Oracle) | Tipo | Converter | Descrição |
|---|---|---|---|---|
| `aceiteExtincao` | `IND_ACEITE_EXTINCAO` | `Boolean` | `SimNaoBooleanConverter` | `true` = aceitou, `false` = recusou, `null` = não manifestou |
| `solicitanteExtincao` | `SOLICITANTE_EXTINCAO` | `Boolean` | `SimNaoBooleanConverter` | Indica se o RT foi o solicitante da extinção |
| `dthAceiteExtincao` | `DTH_ACEITE_EXTINCAO` | `Calendar` | `@Temporal(TIMESTAMP)` | Data/hora da manifestação do RT |

Esses campos são zerados (nulos) ao cancelar ou concluir o processo de extinção.

### RN-119 — Notificação obrigatória

Toda transição de estado do processo P12 deve gerar notificação por e-mail a todos os envolvidos ativos (RT ativo, RU ativo, Proprietários ativos). O sistema usa `NotificacaoRN` para enviar e-mails com templates configurados em `messages.properties`.

| Evento | Chave do template |
|---|---|
| Extinção efetivada | `notificacao.email.template.licenciamento.EXTINGUIDO` |
| Aguardando aceite RT | `notificacao.email.template.licenciamento.AGUARDANDO_ACEITE_EXTINCAO` |
| Recusa de extinção | `notificacao.email.template.licenciamento.RECUSA_EXTINCAO` |
| Cancelamento de extinção | `notificacao.email.template.licenciamento.CANCELA_EXTINCAO` |

### RN-120 — Marco obrigatório por transição

Cada transição de estado do processo de extinção deve gerar um `LicenciamentoMarcoED` com o `TipoMarco` correspondente, CPF do responsável, data/hora e situação resultante.

---

## 9. API REST — Endpoints

### 9.1 Portal do Cidadão — `LicenciamentoRest`

**Base path:** `/licenciamentos`
**Autenticação:** Token OIDC via SOE PROCERGS / meu.rs.gov.br

| Método | Path | Anotação de autorização | EJB chamado | HTTP sucesso |
|---|---|---|---|---|
| `POST` | `/{idLic}/extinguir` | `@AutorizaEnvolvido` | `extingue(idLic)` | 200 |
| `PUT` | `/{idLic}/recusa-extincao` | `@AutorizaEnvolvido` | `recusa(idLic)` | 200 |
| `PUT` | `/{idLic}/cancelar-extincao` | `@AutorizaEnvolvido` | `cancelar(idLic)` | 200 |

**Mapeamento JAX-RS (trecho):**
```java
@POST
@Path("/{idLic}/extinguir")
@AutorizaEnvolvido
public Response extinguir(@PathParam("idLic") final Long idLic) {
    licenciamentoCidadaoExtincaoN.extingue(idLic);
    return Response.ok().build();
}

@PUT
@Path("/{idLic}/recusa-extincao")
@AutorizaEnvolvido
public Response recusaExtincao(@PathParam("idLic") final Long idLic) {
    licenciamentoCidadaoExtincaoN.recusa(idLic);
    return Response.ok().build();
}

@PUT
@Path("/{idLic}/cancelar-extincao")
@AutorizaEnvolvido
public Response cancelarExtincao(@PathParam("idLic") final Long idLic) {
    licenciamentoCidadaoExtincaoN.cancelar(idLic);
    return Response.ok().build();
}
```

### 9.2 Portal do Administrador — `LicenciamentoAdmRestImpl`

**Base path:** `/adm/licenciamentos`
**Autenticação:** Perfil administrativo PROCERGS

| Método | Path | EJB chamado | HTTP sucesso |
|---|---|---|---|
| `POST` | `/{idLic}/extinguir` | `extingueAdm(idLic)` | 200 |
| `PUT` | `/{idLic}/cancelar-extincao` | `cancelarAdm(idLic)` | 200 |
| `GET` | `/permissao-extincao` | `possuiPermissao(objeto, acao)` | 200 |

**Parâmetros do GET `/permissao-extincao`:**

| Param | Tipo | Default | Descrição |
|---|---|---|---|
| `objeto` | `@QueryParam String` | `"EXTINCAO"` | Objeto de permissão |
| `acao` | `@QueryParam String` | `""` | Ação a verificar |

**Resposta:** `{ "possuiPermissao": true/false }`

---

## 10. Modelo de Dados

### 10.1 Entidade `LicenciamentoED`

Tabela Oracle: `CBM_LICENCIAMENTO`

Campos relevantes para P12:

| Atributo (`ED`) | Coluna (Oracle) | Tipo | Descrição |
|---|---|---|---|
| `situacao` | `SIT_LICENCIAMENTO` | `VARCHAR2(60)` | `SituacaoLicenciamento` enum (armazenado como String) |
| `id` | `ID_LICENCIAMENTO` | `NUMBER(19)` | PK |

O campo de situação anterior à extinção pode ser inferido da tabela de histórico `CBM_LICENCIAMENTO_SITUACAO_HIST` ou, se implementado, de um campo específico adicionado via Liquibase.

### 10.2 Entidade `ResponsavelTecnicoED`

Tabela Oracle: `CBM_RESPONSAVEL_TECNICO`

| Atributo (`ED`) | Coluna (Oracle) | Tipo JPA | Converter |
|---|---|---|---|
| `aceiteExtincao` | `IND_ACEITE_EXTINCAO` | `Boolean` | `@Convert(converter = SimNaoBooleanConverter.class)` |
| `solicitanteExtincao` | `SOLICITANTE_EXTINCAO` | `Boolean` | `@Convert(converter = SimNaoBooleanConverter.class)` |
| `dthAceiteExtincao` | `DTH_ACEITE_EXTINCAO` | `Calendar` | `@Temporal(TemporalType.TIMESTAMP)` |

**Nota sobre `SimNaoBooleanConverter`:** Armazena `'S'` para `true` e `'N'` para `false` na coluna Oracle.

### 10.3 Entidade `LicenciamentoMarcoED`

Tabela Oracle: `CBM_PARAMETRO_MARCO` / `CBM_LICENCIAMENTO_MARCO` (tabela de instâncias de marcos)

| Atributo | Coluna | Tipo | Descrição |
|---|---|---|---|
| `tipoMarco` | `TIP_MARCO` | `VARCHAR2(60)` | `TipoMarco` enum |
| `cpfResponsavel` | `CPF_RESPONSAVEL` | `VARCHAR2(11)` | CPF do ator que gerou o marco |
| `dataHora` | `DTH_MARCO` | `TIMESTAMP` | Data/hora do evento |
| `situacaoResultante` | `SIT_RESULTANTE` | `VARCHAR2(60)` | Situação do licenciamento após o evento |

### 10.4 Enum `SituacaoLicenciamento` — valores P12

```java
// Situações permitidas para extinção (exemplos):
APROVADO, ALVARA_VIGENTE, ALVARA_VENCIDO,
// Com análise registrada:
RASCUNHO, AGUARDANDO_PAGAMENTO, AGUARDANDO_ACEITE

// Estado intermediário:
AGUARDANDO_ACEITES_EXTINCAO

// Estado terminal:
EXTINGUIDO
```

### 10.5 Enum `TipoMarco` — valores P12

```java
EXTINCAO,
AGUARDANDO_ACEITE_EXTINCAO,
RECUSA_EXTINCAO,
CANCELAMENTO_EXTINCAO,
RECURSO_CANCELADO_EXTINCAO
```

### 10.6 Script Liquibase — colunas adicionadas (US172)

Arquivo de referência: `s28.us172.changelog.xml`

```xml
<!-- Colunas adicionadas em CBM_RESPONSAVEL_TECNICO para o processo P12 -->
<addColumn tableName="CBM_RESPONSAVEL_TECNICO">
    <column name="IND_ACEITE_EXTINCAO" type="CHAR(1)">
        <constraints nullable="true"/>
    </column>
    <column name="SOLICITANTE_EXTINCAO" type="CHAR(1)">
        <constraints nullable="true"/>
    </column>
    <column name="DTH_ACEITE_EXTINCAO" type="TIMESTAMP">
        <constraints nullable="true"/>
    </column>
</addColumn>
```

---

## 11. Máquina de Estados

### 11.1 Transições do processo P12

```
[Estado válido: APROVADO / ALVARA_VIGENTE / ALVARA_VENCIDO / ...]
    |
    |-- POST /extinguir (RT ou sem RT ativo) -------> [EXTINGUIDO]
    |
    |-- POST /extinguir (RU/Proprietário, RT ativo) -> [AGUARDANDO_ACEITES_EXTINCAO]
                                                              |
                                                    .---------+---------.
                                                    |                   |
                                             RT aceita           RT recusa /
                                             (PUT /extinguir      qualquer ator
                                              ou implícito)        cancela
                                                    |                   |
                                              [EXTINGUIDO]    [Estado anterior
                                                               restaurado]
```

### 11.2 Estados bloqueadores para extinção

**Incondicionais (lista `SITUACOES_INVALIDAS`):**
`ANALISE_INVIABILIDADE_PENDENTE`, `AGUARDA_DISTRIBUICAO_VISTORIA`, `ANALISE_ENDERECO_PENDENTE`, `AGUARDANDO_DISTRIBUICAO`, `EM_ANALISE`, `EM_VISTORIA`, `RECURSO_EM_ANALISE_1_CIA`, `RECURSO_EM_ANALISE_2_CIA`, `RECURSO_EM_ANALISE_1_CIV`, `RECURSO_EM_ANALISE_2_CIV`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO`, `EXTINGUIDO`

**Condicionais sem análise (lista `SITUACOES_INVALIDAS_SEM_ANALISE`):**
`RASCUNHO`, `AGUARDANDO_PAGAMENTO`, `AGUARDANDO_ACEITE`

---

## 12. Marcos de Auditoria (TipoMarco)

| Marco | Situação do licenciamento após | Evento que origina |
|---|---|---|
| `AGUARDANDO_ACEITE_EXTINCAO` | `AGUARDANDO_ACEITES_EXTINCAO` | Solicitação de extinção (RU/Proprietário) quando há RT ativo |
| `EXTINCAO` | `EXTINGUIDO` | Extinção efetivada (RT solicitante, sem RT, ou admin) |
| `RECUSA_EXTINCAO` | Estado anterior restaurado | RT recusa a extinção |
| `CANCELAMENTO_EXTINCAO` | Estado anterior restaurado | Cidadão ou administrador cancela a extinção |
| `RECURSO_CANCELADO_EXTINCAO` | Sem alteração direta | Recurso pendente cancelado automaticamente pelo sistema |

---

## 13. Notificações por E-mail

### 13.1 Serviço responsável

`NotificacaoRN` (CDI bean) encapsula o envio de e-mails via `NotificacaoEmail` (JavaMail API sobre WildFly). Os templates são definidos em `messages.properties` como chaves de notificação.

### 13.2 Destinatários por evento

| Evento | Destinatários |
|---|---|
| Extinção efetivada | RT ativo, RU ativo, todos os Proprietários ativos |
| Aguardando aceite RT | RT ativo |
| Recusa de extinção | RU, Proprietários e demais envolvidos ativos |
| Cancelamento | RT ativo, RU ativo, todos os Proprietários ativos |

### 13.3 Chaves de mensagem relevantes (`messages.properties`)

| Chave | Texto (exemplo) |
|---|---|
| `licenciamento.extincao.invalida` | "Licenciamento não pode ser extinguido." |
| `licenciamento.extinguido` | "Licenciamento encontra-se extinto e não pode ser modificado." |
| `licenciamento.aguardando.aceite.extincao` | "Licenciamento encontra-se aguardando aceites de extinção." |
| `licenciamento.status.EXTINGUIDO` | "A requisição de licenciamento foi extinguida." |
| `licenciamento.status.EXTINGUIDO_RT` | "O licenciamento {0} foi solicitada a extinção pelo RT." |
| `licenciamento.extincao.CANCELAMENTO_EXTINCAO` | "A solicitação de extinção foi cancelada - {0}" |
| `licenciamento.extincao.invalida.troca.envolvidos` | "Licenciamento não pode ser extinguido pois possui solicitação de troca de envolvido em avaliação." |

---

## 14. Segurança e Autorização

### 14.1 IdP e autenticação

Autenticação via **SOE PROCERGS** (meu.rs.gov.br), utilizando protocolo OIDC com Implicit Flow (legado Angular). O backend valida o token JWT/OIDC emitido pelo SOE.

### 14.2 Interceptor de segurança

`@SegurancaEnvolvidoInterceptor` — interceptor CDI que valida, antes de executar qualquer operação sobre o licenciamento, que:
1. O usuário está autenticado (token válido).
2. O usuário é envolvido ativo do licenciamento (`RT`, `RU` ou `Proprietário` com situação `ATIVO`).

Ativado pela anotação `@AutorizaEnvolvido` nos métodos REST do portal do cidadão.

### 14.3 Autorização por perfil no portal administrativo

O portal de administração utiliza perfis gerenciados pelo PROCERGS. O endpoint `GET /permissao-extincao` retorna se o usuário autenticado possui a permissão (`objeto = "EXTINCAO"`, `acao = "EXTINGUIR"`) para exibir ou ocultar o botão de extinção na interface do administrador.

---

## 15. Classes e Componentes Java EE

### 15.1 EJB de regra de negócio — `LicenciamentoCidadaoExtincaoRN`

```java
@Stateless
@Interceptors(SegurancaEnvolvidoInterceptor.class)
public class LicenciamentoCidadaoExtincaoRN {

    @Inject
    private LicenciamentoCidadaoExtincaoRNVal validacao;

    @Inject
    private TrocaEstadoLicenciamentoRN trocaEstadoRN;

    @Inject
    private NotificacaoRN notificacaoRN;

    @Inject
    private RecursoRN recursoRN;

    @PersistenceContext
    private EntityManager em;

    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void extingue(Long idLicenciamento) {
        LicenciamentoED lic = em.find(LicenciamentoED.class, idLicenciamento);
        validacao.validarExtinguir(lic, existeAnalise(idLicenciamento));
        validarTrocaEnvolvido(idLicenciamento);
        recursoRN.cancelarPorExtincao(idLicenciamento);
        // Lógica de RT / não-RT ...
    }

    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void extingueAdm(Long idLicenciamento) { /* ... */ }

    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void recusa(Long idLicenciamento) { /* ... */ }

    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void cancelar(Long idLicenciamento) { /* ... */ }

    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void cancelarAdm(Long idLicenciamento) { /* ... */ }
}
```

### 15.2 EJB de validação — `LicenciamentoCidadaoExtincaoRNVal`

```java
@Stateless
public class LicenciamentoCidadaoExtincaoRNVal {

    private static final List<SituacaoLicenciamento> SITUACOES_INVALIDAS = Arrays.asList(
        ANALISE_INVIABILIDADE_PENDENTE, AGUARDA_DISTRIBUICAO_VISTORIA,
        ANALISE_ENDERECO_PENDENTE, AGUARDANDO_DISTRIBUICAO,
        EM_ANALISE, EM_VISTORIA,
        RECURSO_EM_ANALISE_1_CIA, RECURSO_EM_ANALISE_2_CIA,
        RECURSO_EM_ANALISE_1_CIV, RECURSO_EM_ANALISE_2_CIV,
        AGUARDANDO_DISTRIBUICAO_RENOV, EM_VISTORIA_RENOVACAO,
        EXTINGUIDO
    );

    private static final List<SituacaoLicenciamento> SITUACOES_INVALIDAS_SEM_ANALISE = Arrays.asList(
        RASCUNHO, AGUARDANDO_PAGAMENTO, AGUARDANDO_ACEITE
    );

    public void validarExtinguir(LicenciamentoED lic, Boolean existeAnalise) {
        if (SITUACOES_INVALIDAS.contains(lic.getSituacao())) {
            throw new NegocioException("licenciamento.extincao.invalida");
        }
        if (!existeAnalise && SITUACOES_INVALIDAS_SEM_ANALISE.contains(lic.getSituacao())) {
            throw new NegocioException("licenciamento.extincao.invalida");
        }
    }
}
```

### 15.3 EJB de troca de estado — `TrocaEstadoLicenciamentoParaExtinguidoRN`

```java
@Stateless
@TrocaEstadoLicenciamentoQualifier(trocaEstado = PARA_EXTINGUIDO)
public class TrocaEstadoLicenciamentoParaExtinguidoRN
        extends TrocaEstadoLicenciamentoBaseRN {

    @Override
    public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
        return SituacaoLicenciamento.EXTINGUIDO;
    }

    @Override
    @TransactionAttribute(TransactionAttributeType.REQUIRED)
    public void trocaEstado(Long idLicenciamento) {
        LicenciamentoED lic = em.find(LicenciamentoED.class, idLicenciamento);
        lic.setSituacao(EXTINGUIDO);
        registrarMarco(lic, TipoMarco.EXTINCAO);
        notificarEnvolvidos(lic);
    }
}
```

### 15.4 Frontend — `ModalExtincaoLicenciamentoComponent`

**Localização (portal cidadão):**
`SOLCBM.FrontEnd16-06/src/app/licenciamento/components/modal-extincao-licenciamento/modal-extincao-licenciamento.component.ts`

**Localização (portal adm):**
`SOLCBM.FrontEnd16-06/projects/solcbm-adm/src/app/licenciamento/components/modal-extincao-licenciamento/modal-extincao-licenciamento.component.ts`

**Responsabilidades:**
- Exibe modal de confirmação de extinção ao cidadão.
- Exibe modal de confirmação ao RT para aceite, recusa ou cancelamento.
- Chama endpoints REST correspondentes (`POST /extinguir`, `PUT /recusa-extincao`, `PUT /cancelar-extincao`).
- Trata estados da modal: `cancelar`, `extinguir`, `continuar`.
- Exibe mensagens específicas para o RT quando a extinção foi solicitada por outro ator.

### 15.5 Testes BDD — Cucumber

**Feature:** `US172-ExcluirOuExtinguirLicenciamento.feature`

Cenários cobertos:
- Extinção de licenciamento em situação válida → status `EXTINGUIDO`.
- Extinção bloqueada em `ALVARA_VIGENTE` sem análise.
- Extinção bloqueada em situações inválidas (`RASCUNHO`, `AGUARDANDO_ACEITE`, `AGUARDANDO_PAGAMENTO` sem análise).
- Extinção permitida com diferentes tipos de análise (isenção, endereço, inviabilidade, técnica).
- Exclusão (delete) para licenciamentos em rascunho (processo separado — não confundir com extinção).
- Exclusão bloqueada quando há análise registrada.

---

## 16. Complementos Normativos (RT de Implantação SOL-CBMRS 4ª Ed./2022)

Esta seção acrescenta regras de negócio derivadas da leitura direta da RT de Implantação SOL-CBMRS 4ª Edição/2022. Nenhuma regra anterior (RN-109 a RN-120) é revogada.

---

### RN-P12-N1 — Extinção para Alteração de Campos Imutáveis do Passo 2

**Base normativa:** item 6.3.2.1.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

Quando o proprietário ou o RT precisar corrigir campos que foram bloqueados após o primeiro envio do PPCI — especificamente o **endereço da edificação** e a **existência de isolamento de riscos** (campos do Passo 2 do wizard P03) — não é possível editar diretamente. O procedimento obrigatório é a **extinção do PPCI atual** seguida da abertura de novo processo.

**Requisitos de implementação:**

- O formulário de extinção deve disponibilizar o motivo `ADEQUACAO_DADOS_FUNDAMENTAIS` na lista de motivos de extinção.
- Ao selecionar esse motivo, o sistema deve exibir o seguinte aviso em destaque na interface do cidadão:

  > "Esta extinção **não gera estorno de taxas** caso a análise ou vistoria já tenham sido realizadas pelo CBM-RS (RT Implantação SOL, item 6.3.2.1.2)."

- Após a efetivação da extinção com motivo `ADEQUACAO_DADOS_FUNDAMENTAIS`, o sistema deve oferecer ao cidadão um botão **"Iniciar Novo Processo"** que abre o wizard P03 (Passo 1) com os seguintes dados **pré-carregados** do processo extinto:
  - Dados da edificação (exceto os campos que serão corrigidos: endereço e/ou isolamento de riscos).
  - Lista de responsáveis técnicos e responsáveis pelo uso.
  - Tipo de licenciamento (PPCI, PSPCIM etc.).
  - Medidas de segurança contra incêndio cadastradas.
- Os campos que motivaram a extinção (`enderecoEdificacao` e `possuiIsolamentoRiscos`) são deixados em branco para que o cidadão informe os dados corretos.
- O marco `EXTINCAO` deve registrar o motivo `ADEQUACAO_DADOS_FUNDAMENTAIS` no campo `motivoExtincao` (adicionar se não existir: `DSC_MOTIVO_EXTINCAO VARCHAR2(60)` em `CBM_LICENCIAMENTO`).

**Impacto nos enums e constantes:**

```java
// Enum de motivos de extinção (acrescentar valor):
public enum MotivoExtincaoLicenciamento {
    // ... valores existentes ...
    ADEQUACAO_DADOS_FUNDAMENTAIS  // novo — RT Implantação item 6.3.2.1.1
}
```

---

### RN-P12-N2 — Sem Estorno de Taxas em Extinção para Correção

**Base normativa:** item 6.3.2.1.2 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

No caso de extinção do PPCI para correção de campos imutáveis (motivo `ADEQUACAO_DADOS_FUNDAMENTAIS`), **não é possível solicitar o estorno dos pagamentos realizados** caso o serviço de análise técnica e/ou vistoria já tenha sido prestado pelo CBM-RS.

**Requisitos de implementação:**

- O sistema deve verificar, no momento do pedido de extinção com motivo `ADEQUACAO_DADOS_FUNDAMENTAIS`, se existe análise técnica (P04) ou vistoria (P07) concluída para o licenciamento.
- Se existir análise ou vistoria concluída, o sistema deve:
  1. Exibir aviso: "Não é possível solicitar estorno de taxas, pois o CBM-RS já prestou o serviço de análise e/ou vistoria."
  2. Prosseguir com a extinção normalmente (o aviso é informativo, não bloqueante).
  3. Não disponibilizar qualquer funcionalidade de solicitação de estorno ou reembolso no portal do cidadão para esse processo após a extinção.
- Se **não** existir análise ou vistoria concluída, as regras de estorno existentes no sistema (se houver) se aplicam normalmente.
- O campo `indEstornoPermitido` (ou lógica equivalente) deve retornar `false` quando o motivo de extinção for `ADEQUACAO_DADOS_FUNDAMENTAIS` e houver análise ou vistoria registrada.

---

*Seção 16 adicionada em 2026-03-20. Base normativa: RT de Implantação SOL-CBMRS 4ª Edição/2022 (itens 6.3.2.1.1 e 6.3.2.1.2).*
