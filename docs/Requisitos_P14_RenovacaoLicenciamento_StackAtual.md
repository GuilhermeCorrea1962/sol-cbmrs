# Requisitos — P14: Renovação de Licenciamento (APPCI/Alvará)
## Versão Stack Atual (Java EE 7 · EJB 3.2 · JAX-RS · CDI · JPA/Hibernate · Oracle · WildFly)

**Projeto:** SOL — Sistema Online de Licenciamento — CBM-RS
**Processo:** P14 — Renovação de Licenciamento
**Stack:** Java EE 7 · EJB 3.2 (`@Stateless` · `@TransactionAttribute`) · CDI (`@Inject` · `@Qualifier`) · JAX-RS · JPA/Hibernate (Criteria API) · Oracle · WildFly/JBoss
**Versão do documento:** 1.0
**Data:** 2026-03-16
**Referência no código-fonte:**
- `com.procergs.solcbm.licenciamentorenovacao.LicenciamentoRenovacaoCidadaoRN`
- `com.procergs.solcbm.licenciamentorenovacao.LicenciamentoRenovacaoRNVal`
- `com.procergs.solcbm.licenciamento.trocaestado.TrocaEstado*RenovacaoRN` (10 classes)
- `com.procergs.solcbm.licenciamentociencia.appci.AppciCienciaCidadaoRenovacaoRN`
- `com.procergs.solcbm.licenciamento.LicenciamentoResponsavelPagamentoRN`
- `com.procergs.solcbm.termolicenciamento.TermoLicenciamentoRN`
- `com.procergs.solcbm.remote.LicenciamentoRest` (endpoints de renovação)
- `com.procergs.solcbm.vistoria.TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN`
- `com.procergs.solcbm.dto.AppciRenovacaoDTO`
- `com.procergs.solcbm.enumeration.SituacaoLicenciamento` (métodos de renovação)

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Atores e Papéis](#2-atores-e-papéis)
3. [Pré-requisitos e Gatilhos](#3-pré-requisitos-e-gatilhos)
4. [Fase 1 — Iniciação da Renovação](#4-fase-1--iniciação-da-renovação)
5. [Fase 2 — Aceite ou Rejeição pelo Cidadão (Anexo D)](#5-fase-2--aceite-ou-rejeição-pelo-cidadão-anexo-d)
6. [Fase 3 — Pagamento ou Isenção da Taxa de Vistoria](#6-fase-3--pagamento-ou-isenção-da-taxa-de-vistoria)
7. [Fase 4 — Distribuição da Vistoria de Renovação](#7-fase-4--distribuição-da-vistoria-de-renovação)
8. [Fase 5 — Execução da Vistoria de Renovação](#8-fase-5--execução-da-vistoria-de-renovação)
9. [Fase 6 — Conclusão: Ciência do Novo APPCI ou CIV de Renovação](#9-fase-6--conclusão-ciência-do-novo-appci-ou-civ-de-renovação)
10. [Regras de Negócio](#10-regras-de-negócio)
11. [Máquina de Estados do Licenciamento](#11-máquina-de-estados-do-licenciamento)
12. [Marcos de Auditoria (TipoMarco)](#12-marcos-de-auditoria-tipomarco)
13. [Modelo de Dados (Oracle)](#13-modelo-de-dados-oracle)
14. [API REST — Endpoints JAX-RS](#14-api-rest--endpoints-jax-rs)
15. [Segurança e Autorização](#15-segurança-e-autorização)
16. [Notificações e E-mails](#16-notificações-e-e-mails)
17. [Classes, EJBs e Componentes](#17-classes-ejbs-e-componentes)
18. [Casos de Teste](#18-casos-de-teste)
19. [Comparativo com P03 (Primeira Submissão)](#19-comparativo-com-p03-primeira-submissão)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P14 trata da **renovação de licenciamento de APPCI** (Alvará de Prevenção e Proteção Contra Incêndio) para estabelecimentos que já possuem um alvará em vigor (`ALVARA_VIGENTE`) ou recentemente vencido (`ALVARA_VENCIDO`). É um processo distinto do P03 (primeira submissão de PPCI): não há análise técnica do projeto — o PPCI já foi aprovado anteriormente — e a renovação percorre um fluxo específico envolvendo aceite de termos (Anexo D), pagamento de taxa de vistoria e nova vistoria presencial.

O processo pode ser iniciado pelo próprio cidadão/RT ao acessar o portal, ou ser precedido pelas notificações automáticas de vencimento geradas pelo P13 (jobs de 90, 59 e 29 dias antes do vencimento).

### 1.2 Resultados possíveis

| Resultado | Situação final do licenciamento |
|---|---|
| Renovação aprovada — novo APPCI emitido | `ALVARA_VIGENTE` |
| Vistoria reprovada — CIV pendente de correção | `CIV` |
| Cidadão recusa renovação (alvará ainda vigente) | `ALVARA_VIGENTE` (sem alteração relevante) |
| Cidadão recusa renovação (alvará já vencido) | `ALVARA_VENCIDO` (permanece vencido) |
| Isenção de taxa de vistoria deferida | `AGUARDANDO_DISTRIBUICAO_RENOV` (pula pagamento) |
| Isenção de taxa de vistoria indeferida | `AGUARDANDO_PAGAMENTO_RENOVACAO` (deve pagar boleto) |

### 1.3 Diferenças em relação ao P03

| Aspecto | P03 (Primeira Submissão) | P14 (Renovação) |
|---|---|---|
| Estado de entrada | Novo licenciamento criado | `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` existente |
| Análise técnica | Sim (P04) | Não — PPCI já aprovado |
| Tipo de vistoria | `TipoVistoria.PPCI` | `TipoVistoria.VISTORIA_RENOVACAO` (valor ordinal 3) |
| RT obrigatório | Qualquer tipo de RT credenciado | Exclusivamente `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` |
| Aceite de termos | Não | Aceite obrigatório do Anexo D de Renovação |
| Emissão de APPCI | Processo P08 | Ao final da vistoria aprovada (ciência via `TipoLicenciamentoCiencia.APPCI_RENOV`) |
| Responsáveis para pagamento | RTs de execução + RU + Proprietário | Exclusivamente RT com `RENOVACAO_APPCI` + RU + Proprietário |

---

## 2. Atores e Papéis

| Ator | Papel no P14 |
|---|---|
| **Cidadão / RU** (Responsável pelo Uso) | Aceita ou recusa o processo de renovação; assina o Anexo D; pode solicitar isenção de taxa |
| **RT Renovação** | Responsável Técnico com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI`; único RT habilitado a gerenciar a renovação |
| **Proprietário PF** | Pode aceitar/recusar renovação e efetuar pagamento; identificado por CPF |
| **Proprietário PJ** | Identificado por CNPJ; representado por Procurador (CPF do procurador é o responsável de fato) |
| **Procurador** | Representante legal do Proprietário PJ; possui os mesmos poderes do proprietário no processo |
| **Inspetor CBMRS** | Recebe a distribuição da vistoria de renovação; realiza a vistoria presencial; registra resultado |
| **Admin CBMRS** | Distribui a vistoria para o inspetor; analisa solicitações de isenção; homologa resultado |
| **Sistema (WildFly/EJB)** | Envia notificações de vencimento via P13; confirma pagamentos via CNAB 240; registra marcos e transições de estado |

---

## 3. Pré-requisitos e Gatilhos

### 3.1 Pré-requisitos obrigatórios

- Licenciamento em situação `ALVARA_VIGENTE` **ou** `ALVARA_VENCIDO` (RN-141). Qualquer outra situação resulta em HTTP 406.
- Pelo menos um RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` vinculado ao licenciamento (RN-142).
- Usuário autenticado deve ser um dos seguintes envolvidos no licenciamento (RN-143):
  - RT com `RENOVACAO_APPCI`
  - RU (Responsável pelo Uso)
  - Proprietário (PF ou PJ via Procurador)

### 3.2 Gatilhos de início

| Gatilho | Descrição |
|---|---|
| **Automático via P13** | Job P13-B notifica o cidadão por e-mail 90, 59 ou 29 dias antes do vencimento; cidadão acessa o portal e inicia a renovação |
| **Manual (alvará vigente)** | Cidadão/RT acessa "Minhas Renovações" e solicita renovação antes do vencimento |
| **Manual (alvará vencido)** | P13-A transitou para `ALVARA_VENCIDO`; cidadão acessa o portal para renovar após o vencimento |

### 3.3 Verificação de elegibilidade

O endpoint `GET /licenciamentos/{idLic}/verificaAlvara` permite verificar se o alvará do licenciamento está próximo do vencimento e se o licenciamento é elegível para renovação. Este endpoint é também a base para o `AlvaraBatchServlet` acionado via Workload.

```java
// Filtro de situações elegíveis para renovação
SituacaoLicenciamento.retornaSituacoesRenovacao()
// Retorna: Arrays.asList(ALVARA_VIGENTE, ALVARA_VENCIDO)
```

---

## 4. Fase 1 — Iniciação da Renovação

### 4.1 Fluxo de iniciação

O cidadão ou RT acessa o portal SOL, navega até um licenciamento elegível e aciona a renovação. O sistema executa:

1. **Validação de situação** — `LicenciamentoRenovacaoRNVal.validarSituacaoParaEdicao(situacao)`: verifica que o licenciamento está em `ALVARA_VIGENTE`, `ALVARA_VENCIDO`, `AGUARDANDO_ACEITE_RENOVACAO` ou `CIV` (RN-141).

2. **Validação de permissão** — `LicenciamentoRenovacaoRNVal.validarResponsaveisTecnicosRenovacaoAppci(rus, rts, prop, cpf)`: verifica que o CPF do usuário autenticado corresponde a um RT `RENOVACAO_APPCI`, RU, Proprietário ou Procurador do licenciamento (RN-143).

3. **Validação de RT de renovação** — `LicenciamentoRenovacaoRNVal.validarResponsaveisTecnicos(rts, cpf)`: verifica que a lista de RTs contém ao menos um com `RENOVACAO_APPCI` e que o usuário logado possui esse tipo (RN-142).

4. **Transição de estado:**
   - `ALVARA_VIGENTE` → `AGUARDANDO_ACEITE_RENOVACAO`
     Via: `TrocaEstadoLicenciamentoAlvaraVigenteParaAguardandoAceiteVistoriaRenovacaoRN`
     Qualifier: `TrocaEstadoLicenciamentoEnum.ALVARA_VIGENTE_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO`
   - `ALVARA_VENCIDO` → `AGUARDANDO_ACEITE_RENOVACAO`
     Via: `TrocaEstadoLicenciamentoAlvaraVencidoParaAguardandoAceiteVistoriaRenovacaoRN`
     Qualifier: `TrocaEstadoLicenciamentoEnum.ALVARA_VENCIDO_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO`

5. **Registro de histórico** — `LicenciamentoSituacaoHistRN.inclui()` via `TrocaEstadoLicenciamentoBaseRN.atualizaSituacaoLicenciamento()` (padrão de todas as classes `TrocaEstado`).

6. **Notificação por e-mail** — `LicenciamentoCidadaoNotificacaoRN` envia notificação de inclusão de envolvido em renovação com template `notificacao.email.template.renovacao.incluido` (RN-160).

### 4.2 Listagem das renovações do usuário

**Endpoint:**
```
GET /licenciamentos/minha-solicitacoes-renovacao
```

**Parâmetros de consulta:**

| Parâmetro | Tipo | Default | Descrição |
|---|---|---|---|
| `ordenar` | String | `ctrDthInc` | Campo de ordenação |
| `ordem` | String | `asc` | Direção da ordenação (`asc`/`desc`) |
| `paginaAtual` | Integer | `0` | Número da página |
| `tamanho` | Integer | `20` | Tamanho da página |
| `situacao` | `List<SituacaoLicenciamento>` | — | Filtro por situação(ões) |
| `tipo` | `List<TipoLicenciamento>` | — | Filtro por tipo de licenciamento |
| `cidade` | String | — | Filtro por cidade |
| `numero` | String | — | Filtro por número do PPCI |
| `termo` | String | — | Busca textual livre |

**Lógica de seleção:**

```java
// No LicenciamentoRest.listarMinhasSolicitacoesRenovacao():
ped.setRenovacao(true); // flag que diferencia da listagem padrão

if (StringUtils.isEmpty(termo)) {
    return Response.ok(licenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacao(ped)).build();
} else {
    return Response.ok(licenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacaoTermo(ped)).build();
}
```

**Situações retornadas pela listagem:**

```java
// SituacaoLicenciamento.retornaSituacoesMinhasRenovacoes()
Arrays.asList(
    AGUARDANDO_ACEITE_PRPCI,
    AGUARDANDO_ACEITE_RENOVACAO,
    AGUARDANDO_CIENCIA_CIV,
    CIV,
    AGUARDANDO_PAGAMENTO_RENOVACAO,
    EM_VISTORIA_RENOVACAO,
    RECURSO_EM_ANALISE_1_CIV,
    RECURSO_EM_ANALISE_2_CIV
)
```

---

## 5. Fase 2 — Aceite ou Rejeição pelo Cidadão (Anexo D)

O licenciamento está em `AGUARDANDO_ACEITE_RENOVACAO`. O cidadão deve ler e aceitar o **Anexo D de Renovação** antes de confirmar o processo.

### 5.1 Leitura do Anexo D

**Endpoint:**
```
GET /licenciamentos/termo-anexo-d-renovacao/{idLic}
```

**Classe:** `TermoLicenciamentoRN`
**Método:** `retornoCienciaETermoRenovacao(Long idLic)`

Retorna `RetornoCienciaTermoAnexoDDTO` contendo:
- Texto do Anexo D de Renovação
- Status de aceite atual do usuário
- Histórico de aceites anteriores (se houver)
- Dados do APPCI atual (número do pedido, validade, início e fim de vigência)

**DTO de renovação do APPCI:**

```java
// AppciRenovacaoDTO (Lombok @Builder @Getter @Setter)
public class AppciRenovacaoDTO {
    Integer numeroPedido;   // número do pedido do APPCI atual
    String  validade;       // data de validade formatada
    String  inicioVigencia; // início da vigência do alvará
    String  fimVigencia;    // fim da vigência do alvará
}
```

### 5.2 Aceite do Anexo D

**Endpoint:**
```
PUT /licenciamentos/termo-anexo-d-renovacao/{idLic}
```

**Classe:** `TermoLicenciamentoRN`
**Método:** `confirmaInclusaoAnexoDRenovacao(Long idLic)`

Registra o aceite do Anexo D pelo usuário autenticado (via CPF extraído do token OAuth2/OIDC do SOE PROCERGS) e registra o marco `ACEITE_ANEXOD_RENOVACAO` (RN-144).

**Retorno:** `RetornoCienciaTermoAnexoDDTO` atualizado.

### 5.3 Remoção do aceite do Anexo D

**Endpoint:**
```
DELETE /licenciamentos/termo-anexo-d-renovacao/{idLic}
```

**Classe:** `TermoLicenciamentoRN`
**Método:** `removeAceiteAnexoDRenovacao(Long idLic, boolean removerAceite)`

O parâmetro `removerAceite = true` indica remoção explícita (permite que o cidadão reveja os termos antes de confirmar). Enquanto o licenciamento estiver em `AGUARDANDO_ACEITE_RENOVACAO`, o aceite pode ser retirado (RN-144).

### 5.4 Confirmação ou recusa da renovação

Após aceitar o Anexo D, o cidadão confirma ou recusa a renovação. O próximo estado é determinado pela lógica de `LicenciamentoRenovacaoCidadaoRN.getTrocaEstadoAnteriorRenovacao()`:

```java
@Stateless
@SegurancaEnvolvidoInterceptor
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public class LicenciamentoRenovacaoCidadaoRN implements Serializable {

    @Inject
    private VistoriaRN vistoriaRN;

    @Inject
    private AppciRN appciRN;

    @Inject
    @TrocaEstadoLicenciamentoQualifier(
        trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VIGENTE)
    private TrocaEstadoLicenciamentoRN trocaEstadoParaAlvaraVigenteRN;

    @Inject
    @TrocaEstadoLicenciamentoQualifier(
        trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VENCIDO)
    private TrocaEstadoLicenciamentoRN trocaEstadoParaAlvaraVencidoRN;

    @Inject
    @TrocaEstadoLicenciamentoQualifier(
        trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV)
    private TrocaEstadoLicenciamentoRN trocaEstadoParaCIVRN;

    public TrocaEstadoLicenciamentoRN getTrocaEstadoAnteriorRenovacao(Long idLicenciamento) {
        Calendar validadeAlvara = appciRN.consultaDataValidadeAlvara(idLicenciamento);
        VistoriaED ultimaVistoria = vistoriaRN.consultaUltimaVistoriaEncerrada(idLicenciamento);

        if (!Objects.isNull(ultimaVistoria)
                && ultimaVistoria.getStatus().equals(StatusVistoria.REPROVADO)) {
            return trocaEstadoParaCIVRN; // → CIV
        } else {
            if (Calendar.getInstance().after(validadeAlvara)) {
                return trocaEstadoParaAlvaraVencidoRN; // → ALVARA_VENCIDO
            } else {
                return trocaEstadoParaAlvaraVigenteRN; // → ALVARA_VIGENTE
            }
        }
    }
}
```

**Regra de determinação do próximo estado (RN-145):**

| Condição | TrocaEstadoEnum | Próxima situação |
|---|---|---|
| Cidadão confirma + última vistoria `REPROVADO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV` | `CIV` |
| Cidadão recusa/fecha + alvará expirado (`Calendar.now() > validadeAlvara`) | `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VENCIDO` | `ALVARA_VENCIDO` |
| Cidadão recusa/fecha + alvará ainda válido | `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VIGENTE` | `ALVARA_VIGENTE` |
| Cidadão confirma + sem CIV + deve pagar taxa | `AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_PAGAMENTO_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` |
| Cidadão confirma + sem CIV + isenção aprovada | `AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO` | `AGUARDANDO_DISTRIBUICAO_RENOV` |

---

## 6. Fase 3 — Pagamento ou Isenção da Taxa de Vistoria

O licenciamento está em `AGUARDANDO_PAGAMENTO_RENOVACAO`. O cidadão deve quitar a taxa de vistoria ou solicitar isenção.

### 6.1 Listagem de responsáveis para pagamento da renovação

**Endpoint:**
```
GET /licenciamentos/{idLic}/reponsaveis-pagamento-renovacao
```
*(nota: caminho no código usa `reponsaveis` sem o segundo 's' — manter idêntico ao código)*

**Classe:** `LicenciamentoResponsavelPagamentoRN`
**Método:** `listaResponsaveisParaPagamentoRenovacao(Long idLicenciamento)`
**Interceptor:** `@SegurancaEnvolvidoInterceptor`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Implementação real:**

```java
public List<ResponsavelPagamentoDTO> listaResponsaveisParaPagamentoRenovacao(Long idLicenciamento) {
    LicenciamentoED licenciamentoED = licenciamentoRN.consulta(idLicenciamento);
    Map<String, ResponsavelPagamentoDTO> responsaveisMap = new HashMap<>();

    // Apenas RTs com RENOVACAO_APPCI (diferença em relação a listaResponsaveisParaPagamento)
    List<ResponsavelTecnicoED> rts = responsavelTecnicoRN.listaPorLicenciamento(licenciamentoED);
    rts = rts.stream()
             .filter(rt -> rt.getTipoResponsabilidadeTecnica()
                            .equals(TipoResponsabilidadeTecnica.RENOVACAO_APPCI))
             .collect(Collectors.toList());
    rts.forEach(rt -> atualizaResponsaveisMap(getResponsavelPagamentoRt(rt), responsaveisMap));

    // Todos os RUs
    List<ResponsavelUsoED> rus = responsavelUsoRN.listaPorLicenciamento(licenciamentoED);
    rus.forEach(ru -> atualizaResponsaveisMap(getResponsavelPagamentoRu(ru), responsaveisMap));

    // Todos os Proprietários (PF: CPF direto; PJ: CNPJ + CPF do Procurador)
    List<LicenciamentoProprietarioED> proprietarios =
        licenciamentoProprietarioRN.listaPorLicenciamento(licenciamentoED);
    proprietarios.forEach(p -> atualizaResponsaveisMap(
        getResponsavelPagamentoProprietario(p), responsaveisMap));

    return responsaveisMap.values().stream()
           .sorted(Comparator.comparing(ResponsavelPagamentoDTO::getNome))
           .collect(Collectors.toList());
}
```

**Chave de deduplicação:** `cpfCnpj` — o mesmo CPF/CNPJ não é adicionado duas vezes ao mapa.

**DTO de retorno — `ResponsavelPagamentoDTO`:**

| Campo | Tipo | Origem |
|---|---|---|
| `cpfCnpj` | String | CPF do RT/RU/PF ou CNPJ do Proprietário PJ |
| `nome` | String | Nome do responsável |
| `tipo` | `TipoResponsavelPagamento` | `RT`, `RU`, `PROPRIETARIO_PF`, `PROPRIETARIO_PJ` |
| `cpfProcurador` | String | CPF do procurador (somente para `PROPRIETARIO_PJ`) |

### 6.2 Solicitação de isenção de taxa

**Endpoint:**
```
PUT /licenciamentos/{idLic}/solicitacaoIsencao
Authorization: Bearer {token OAuth2 SOE PROCERGS}
@AutorizaEnvolvido
Content-Type: application/json

{
  "solicitacao": true,
  "solicitacaoRenovacao": true
}
```

**Classe:** `LicenciamentoCidadaoRN`
**Método:** `atualizaSolicitacaoIsencao(Long idLic, Boolean solicitacao, Boolean solicitacaoRenovacao)`

O campo `solicitacaoRenovacao = true` diferencia a isenção da renovação da isenção do primeiro licenciamento. Ambos os campos são persistidos separadamente em `TB_LICENCIAMENTO`:
- `IND_SOLICITACAO_ISENCAO` — isenção do licenciamento original
- `IND_SOLICITACAO_ISENCAO_RENOVACAO` — isenção específica da renovação

Registra marco `SOLICITACAO_ISENCAO_RENOVACAO` (RN-147).

### 6.3 Análise da isenção pelo CBMRS

O administrador CBMRS analisa a solicitação de isenção da renovação:

- **Deferida:** Marco `ANALISE_ISENCAO_RENOV_APROVADO` → transição para `AGUARDANDO_DISTRIBUICAO_RENOV`
  via `TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO`
  Classe: `TrocaEstadoLicAguardandoAceiteRenovacaoParaAguardandoDistribuicaoRenovacaoRN` (RN-148)

- **Indeferida:** Marco `ANALISE_ISENCAO_RENOV_REPROVADO` → licenciamento permanece em `AGUARDANDO_PAGAMENTO_RENOVACAO` (RN-148)

### 6.4 Geração e pagamento do boleto

O sistema gera boleto bancário Banrisul para a taxa de vistoria de renovação. Marco registrado: `BOLETO_VISTORIA_RENOVACAO_PPCI`.

O pagamento é confirmado pelo job P13-E (`EJBTimerService.verificaPagamentoBanrisul()`) via arquivo CNAB 240 do Banrisul. Após confirmação:

- Marco: `LIQUIDACAO_VISTORIA_RENOVACAO`
- Transição: `AGUARDANDO_PAGAMENTO_RENOVACAO` → `AGUARDANDO_DISTRIBUICAO_RENOV`
  Via: `TrocaEstadoLicenciamentoAguardandoPagamentoVistoriaRenovParaAguardandoDistribuicaoVistoriaRenovRN`
  Qualifier: `AGUARDANDO_PAGAMENTO_VISTORIA_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` (RN-149)

---

## 7. Fase 4 — Distribuição da Vistoria de Renovação

O licenciamento está em `AGUARDANDO_DISTRIBUICAO_RENOV`. O administrador CBMRS distribui a vistoria para um inspetor.

### 7.1 Transição de estado

**Classe:** `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN`
**Qualifier:** `AGUARDANDO_DISTRIBUICAO_RENOVACAO_PARA_EM_VISTORIA_RENOVACAO`
**Transação:** `@TransactionAttribute(REQUIRED)`

```java
@Override
public LicenciamentoED trocaEstado(Long idLicenciamento) {
    LicenciamentoED licenciamentoED = atualizaSituacaoLicenciamento(idLicenciamento);
    // Registra marco DISTRIBUICAO_VISTORIA_RENOV com TipoResponsavelMarco.BOMBEIROS
    licenciamentoMarcoAdmRN.inclui(TipoMarco.DISTRIBUICAO_VISTORIA_RENOV, licenciamentoED);
    return licenciamentoED;
}

@Override
public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
    return SituacaoLicenciamento.EM_VISTORIA_RENOVACAO;
}
```

- **Marco registrado:** `DISTRIBUICAO_VISTORIA_RENOV`
- **Tipo de responsável do marco:** `TipoResponsavelMarco.BOMBEIROS`
- **Nova situação:** `EM_VISTORIA_RENOVACAO` (RN-150)

---

## 8. Fase 5 — Execução da Vistoria de Renovação

O licenciamento está em `EM_VISTORIA_RENOVACAO`. O inspetor realiza a vistoria presencial com `TipoVistoria.VISTORIA_RENOVACAO`.

### 8.1 Tipo de vistoria específico

A vistoria de renovação é identificada por `TipoVistoria.VISTORIA_RENOVACAO` (valor ordinal `3`). Isso a diferencia das vistorias do P07 (`TipoVistoria.PPCI` = 0) e garante que filtros e queries de banco retornem apenas o tipo correto (RN-151).

### 8.2 Homologação pelo admin CBMRS

O resultado da vistoria é homologado pelo administrador CBMRS. O fluxo interno de vistoria de renovação utiliza a classe:

**`TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN`**
**Qualifier:** `TrocaEstadoVistoriaEnum.EM_APROVACAO_RENOVACAO_PARA_EM_VISTORIA`
**Transação:** `@TransactionAttribute(REQUIRED)`

```java
@Override
public VistoriaED trocaEstado(Long idVistoria) {
    VistoriaED vistoriaED = atualizaStatusVistoria(idVistoria);
    // Registra marco HOMOLOG_VISTORIA_RENOV_INDEFERIDO com TipoResponsavelMarco.BOMBEIROS
    licenciamentoMarcoInclusaoRN.inclui(
        TipoMarco.HOMOLOG_VISTORIA_RENOV_INDEFERIDO,
        vistoriaED.getLicenciamento());
    return vistoriaED;
}

@Override
public StatusVistoria getNovoStatusVistoria() {
    return StatusVistoria.EM_VISTORIA;
}
```

*(Esta classe trata o caso de indeferimento durante a fase de aprovação — a vistoria retorna ao estado `EM_VISTORIA` para reavaliação.)*

### 8.3 Resultado da vistoria

| Resultado | Marco registrado | Próxima ação |
|---|---|---|
| Aprovado | `VISTORIA_RENOVACAO` / `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | Emissão do novo APPCI → Ciência do cidadão |
| Reprovado (CIV) | `VISTORIA_RENOVACAO_CIV` | Licenciamento → `CIV`; cidadão deve corrigir pendências |

---

## 9. Fase 6 — Conclusão: Ciência do Novo APPCI ou CIV de Renovação

### 9.1 Ciência e emissão do novo APPCI

Após vistoria aprovada e homologada, o sistema emite o novo APPCI. O cidadão/RT deve tomar ciência do documento via `TipoLicenciamentoCiencia.APPCI_RENOV`.

**Classe:** `AppciCienciaCidadaoRenovacaoRN`
**Qualifier:** `@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.APPCI_RENOV)`
**Transação:** `@TransactionAttribute(REQUIRED)`

```java
@Stateless
@TransactionAttribute(TransactionAttributeType.REQUIRED)
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.APPCI_RENOV)
public class AppciCienciaCidadaoRenovacaoRN extends LicenciamentoCienciaCidadaoBaseRN
    implements LicenciamentoCienciaCidadaoRN {

    @Inject
    private AppciRN appciRN;

    @Override
    public void alteraLicenciamentoCiencia(LicenciamentoCiencia licenciamentoCiencia) {
        appciRN.altera((AppciED) licenciamentoCiencia);
        // Persiste o APPCI renovado via entityManager.merge()
    }

    @Override
    public boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia licenciamentoCiencia) {
        return true; // Ciência sempre resulta em aprovação (RN-152)
    }

    @Override
    public TipoMarco getTipoMarco(LicenciamentoCiencia licenciamentoCiencia) {
        return TipoMarco.CIENCIA_APPCI_RENOVACAO;
    }

    @Override
    protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;
        // Mesmo em caso de "reprovação" (não aplicável aqui), retorna ALVARA_VIGENTE
    }
}
```

**Sequência de operações na ciência:**
1. `alteraLicenciamentoCiencia()` — persiste o APPCI renovado (`entityManager.merge()`)
2. Marco `CIENCIA_APPCI_RENOVACAO` — registrado com `TipoResponsavelMarco.CIDADAO`
3. Marco `LIBERACAO_RENOV_APPCI` — emissão do novo APPCI com nova data de validade
4. Situação do licenciamento → `ALVARA_VIGENTE` (RN-152)
5. Notificação por e-mail enviada

### 9.2 CIV de Renovação

Se a vistoria foi reprovada, o licenciamento entra em `CIV`. O cidadão toma ciência da CIV com marco `CIENCIA_CIV_RENOVACAO`. Após corrigir as pendências, o processo de renovação pode ser retomado via:

**Classe:** `TrocaEstadoLicenciamentoCivParaAguardandoAceiteVistoriaRenovacaoRN`
**Qualifier:** `CIV_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO`
**Transição:** `CIV` → `AGUARDANDO_ACEITE_RENOVACAO` (RN-153)

```java
@Inject
@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.CIDADAO)
private LicenciamentoMarcoInclusaoRN licenciamentoMarcoInclusaoRN;

@Override
public LicenciamentoED trocaEstado(Long idLicenciamento) {
    return atualizaSituacaoLicenciamento(idLicenciamento);
}

@Override
public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
    return SituacaoLicenciamento.AGUARDANDO_ACEITE_RENOVACAO;
}
```

---

## 10. Regras de Negócio

| ID | Regra | Implementação no código |
|---|---|---|
| **RN-141** | Somente licenciamentos em situação `ALVARA_VIGENTE`, `ALVARA_VENCIDO`, `AGUARDANDO_ACEITE_RENOVACAO` ou `CIV` podem ser editados no processo de renovação. Qualquer outra situação lança `WebApplicationRNException` com HTTP 406 e mensagem `licenciamento.status.editar`. | `LicenciamentoRenovacaoRNVal.validarSituacaoParaEdicao()` |
| **RN-142** | Para solicitar renovação, a lista de RTs do licenciamento não pode estar vazia e deve conter ao menos um RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` cujo CPF corresponda ao usuário logado. Caso contrário, HTTP 406 com `licenciameto.rts.renovacao.invalido` (lista vazia) ou `usuario.sem.permissao.rt.renovacao` (usuário não tem RENOVACAO_APPCI). | `LicenciamentoRenovacaoRNVal.validarResponsaveisTecnicos(List<ResponsavelTecnico> rts, String cpf)` |
| **RN-143** | Alterações no processo de renovação só podem ser realizadas pelo usuário que seja RT com `RENOVACAO_APPCI`, RU, Proprietário PF ou Procurador de Proprietário PJ do licenciamento. Caso contrário, HTTP 406 com `licenciameto.rt.renovacao.sem.permissao`. A verificação usa comparação por CPF: `x.getCpf().equals(cpf)` para RTs/RUs e `x.getCpfCnpj().endsWith(cpf)` para proprietários. | `LicenciamentoRenovacaoRNVal.validarResponsaveisTecnicosRenovacaoAppci(Set<ResponsavelUsoED>, Set<ResponsavelTecnicoED>, Set<LicenciamentoProprietarioED>, String cpf)` |
| **RN-144** | O cidadão deve aceitar o Anexo D da renovação. O aceite é registrado via `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao()` com marco `ACEITE_ANEXOD_RENOVACAO`. O aceite pode ser retirado enquanto o licenciamento estiver em `AGUARDANDO_ACEITE_RENOVACAO`, via `TermoLicenciamentoRN.removeAceiteAnexoDRenovacao(idLic, true)`. | `TermoLicenciamentoRN` (métodos `confirmaInclusaoAnexoDRenovacao` e `removeAceiteAnexoDRenovacao`) |
| **RN-145** | O próximo estado após confirmação da renovação é determinado por `LicenciamentoRenovacaoCidadaoRN.getTrocaEstadoAnteriorRenovacao()`: (1) se a última vistoria encerrada é `REPROVADO` → `CIV`; (2) se não há vistoria reprovada e `Calendar.getInstance().after(validadeAlvara)` → `ALVARA_VENCIDO`; (3) caso contrário → `ALVARA_VIGENTE`. | `LicenciamentoRenovacaoCidadaoRN.getTrocaEstadoAnteriorRenovacao(Long idLicenciamento)` usando `appciRN.consultaDataValidadeAlvara()` e `vistoriaRN.consultaUltimaVistoriaEncerrada()` |
| **RN-146** | Os responsáveis elegíveis para pagamento da taxa de vistoria de renovação são: (a) todos os RTs com `RENOVACAO_APPCI` vinculados, (b) todos os RUs e (c) todos os Proprietários. Diferentemente do pagamento padrão (`listaResponsaveisParaPagamento`), que filtra RTs de execução, a renovação filtra exclusivamente por `RENOVACAO_APPCI`. A lista é deduplicada por CPF/CNPJ e ordenada por nome. | `LicenciamentoResponsavelPagamentoRN.listaResponsaveisParaPagamentoRenovacao()` |
| **RN-147** | A solicitação de isenção de taxa de vistoria de renovação é registrada pelo campo `IND_SOLICITACAO_ISENCAO_RENOVACAO` em `TB_LICENCIAMENTO`, distinto do campo `IND_SOLICITACAO_ISENCAO` do primeiro licenciamento. O endpoint recebe o mapa `{"solicitacao": boolean, "solicitacaoRenovacao": boolean}` e atualiza ambos separadamente. Marco registrado: `SOLICITACAO_ISENCAO_RENOVACAO`. | `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao(Long idLic, Boolean solicitacao, Boolean solicitacaoRenovacao)` |
| **RN-148** | A análise de isenção pelo CBMRS gera marcos distintos: `ANALISE_ISENCAO_RENOV_APROVADO` (deferida → avança para `AGUARDANDO_DISTRIBUICAO_RENOV`) ou `ANALISE_ISENCAO_RENOV_REPROVADO` (indeferida → permanece em `AGUARDANDO_PAGAMENTO_RENOVACAO`). | `TipoMarco` enum + classes de TrocaEstado correspondentes |
| **RN-149** | A confirmação de pagamento do boleto de vistoria de renovação é feita exclusivamente via arquivo CNAB 240 do Banrisul, processado pelo job P13-E. Após confirmação, o sistema registra marco `LIQUIDACAO_VISTORIA_RENOVACAO` e executa a transição `AGUARDANDO_PAGAMENTO_RENOVACAO` → `AGUARDANDO_DISTRIBUICAO_RENOV` via `TrocaEstadoLicenciamentoAguardandoPagamentoVistoriaRenovParaAguardandoDistribuicaoVistoriaRenovRN`. | `PagamentoBoletoRN.verificaPagamentoBanrisul()` (P13-E) + `TrocaEstado...` |
| **RN-150** | A distribuição da vistoria de renovação pelo admin CBMRS executa `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN.trocaEstado()`, que: (a) atualiza situação para `EM_VISTORIA_RENOVACAO` via `atualizaSituacaoLicenciamento()` e (b) registra marco `DISTRIBUICAO_VISTORIA_RENOV` com `TipoResponsavelMarco.BOMBEIROS` via `licenciamentoMarcoAdmRN.inclui()`. | `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN` |
| **RN-151** | A vistoria de renovação é do tipo `TipoVistoria.VISTORIA_RENOVACAO` (ordinal 3). Qualquer query ou filtro de vistoria no contexto de renovação deve usar esse tipo para não retornar vistorias de outros processos (`PPCI` = 0, `PSPCIM` = 1). | `TipoVistoria` enum |
| **RN-152** | A ciência do novo APPCI de renovação via `AppciCienciaCidadaoRenovacaoRN` sempre retorna `isLicenciamentoCienciaAprovado() = true`. O método `getProximoStatusLicenciamentoCienciaReprovado()` retorna `ALVARA_VIGENTE`, pois a ciência é sempre aprovada. O marco registrado é `CIENCIA_APPCI_RENOVACAO`. Após a ciência, o APPCI renovado é persistido via `appciRN.altera((AppciED) licenciamentoCiencia)`. | `AppciCienciaCidadaoRenovacaoRN` |
| **RN-153** | Quando a vistoria de renovação é reprovada (CIV), o cidadão toma ciência da CIV com marco `CIENCIA_CIV_RENOVACAO`. Após a correção das pendências, o processo de renovação pode ser retomado via `TrocaEstadoLicenciamentoCivParaAguardandoAceiteVistoriaRenovacaoRN` (`CIV` → `AGUARDANDO_ACEITE_RENOVACAO`). O marco é registrado com `TipoResponsavelMarco.CIDADAO`. | `TrocaEstadoLicenciamentoCivParaAguardandoAceiteVistoriaRenovacaoRN` |
| **RN-154** | A seção "Minhas Renovações" (`GET /minha-solicitacoes-renovacao`) lista os licenciamentos do usuário autenticado em qualquer das seguintes situações: `AGUARDANDO_ACEITE_PRPCI`, `AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_CIENCIA_CIV`, `CIV`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `EM_VISTORIA_RENOVACAO`, `RECURSO_EM_ANALISE_1_CIV`, `RECURSO_EM_ANALISE_2_CIV`. Lista produzida por `SituacaoLicenciamento.retornaSituacoesMinhasRenovacoes()`. | `SituacaoLicenciamento.retornaSituacoesMinhasRenovacoes()` + `LicenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacao()` |
| **RN-155** | Somente licenciamentos em situação `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` são considerados elegíveis para iniciar renovação. Este conjunto é retornado por `SituacaoLicenciamento.retornaSituacoesRenovacao()` como `Arrays.asList(ALVARA_VIGENTE, ALVARA_VENCIDO)`. | `SituacaoLicenciamento.retornaSituacoesRenovacao()` |
| **RN-156** | A listagem de "Minhas Renovações" usa dois métodos distintos dependendo da presença de `termo`: com termo → `listaMinhaSolicitacoesRenovacaoTermo(ped)`; sem termo → `listaMinhaSolicitacoesRenovacao(ped)`. Em ambos os casos, a flag `ped.setRenovacao(true)` é definida antes da chamada. | `LicenciamentoRest.listarMinhasSolicitacoesRenovacao()` linhas 1799–1804 |
| **RN-157** | O campo `IND_SOLICITACAO_ISENCAO_RENOVACAO` em `TB_LICENCIAMENTO` é independente de `IND_SOLICITACAO_ISENCAO`. O endpoint `PUT /{idLic}/solicitacaoIsencao` recebe ambos os valores no corpo como mapa: `solicitacao.get("solicitacao")` e `solicitacao.get("solicitacaoRenovacao")`. Ambos podem ser definidos simultaneamente sem conflito. | `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao(Long idLic, Boolean solicitacao, Boolean solicitacaoRenovacao)` |
| **RN-158** | Todos os marcos de renovação são registrados via `LicenciamentoMarcoInclusaoRN.inclui(TipoMarco, LicenciamentoED)`, que persiste `DTH_MARCO = SYSTIMESTAMP`, `ID_LICENCIAMENTO`, `DSC_TIPO_MARCO` e `DSC_TIPO_RESPONSAVEL_MARCO` na tabela `TB_LICENCIAMENTO_MARCO`. | `LicenciamentoMarcoInclusaoRN.inclui()` (padrão de todos os marcos) |
| **RN-159** | O EJB `LicenciamentoRenovacaoCidadaoRN` é decorado com `@SegurancaEnvolvidoInterceptor`, que valida que o usuário autenticado (CPF extraído do contexto de segurança do SOE PROCERGS) é um envolvido do licenciamento antes de permitir qualquer operação. | `LicenciamentoRenovacaoCidadaoRN` — anotação `@SegurancaEnvolvidoInterceptor` |
| **RN-160** | Após cada transição de estado relevante no processo de renovação, o sistema envia notificação por e-mail a todos os envolvidos (RT Renovação, RU, Proprietário) via `LicenciamentoCidadaoNotificacaoRN`. O contexto de notificação é `ContextoNotificacaoEnum.RENOVACAO`. | `LicenciamentoCidadaoNotificacaoRN` + `ContextoNotificacaoEnum.RENOVACAO` |

---

## 11. Máquina de Estados do Licenciamento

```
 [ALVARA_VIGENTE]  [ALVARA_VENCIDO]  [CIV] (após vistoria reprovada)
        │                  │               │
        └──────────────────┴───────────────┘
                           │ (solicitar renovação)
                           ▼
              [AGUARDANDO_ACEITE_RENOVACAO]
              "Aguardando aceite da renovação"
                           │
     ┌─────────────────────┼───────────────────────┐
     │                     │                        │
     ▼ (recusar/fechar,    │ (confirmar, sem CIV)   ▼ (recusar/fechar,
     alvará vigente)       │                        alvará vencido)
 [ALVARA_VIGENTE]          │                    [ALVARA_VENCIDO]
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼ (CIV pendente) │ (pagar taxa)   ▼ (isento)
        [CIV]   [AGUARDANDO_PAGAMENTO_RENOVACAO]  [AGUARDANDO_DISTRIBUICAO_RENOV]
                           │                       │
               (pago CNAB) │                       │
                           ▼                       │
              [AGUARDANDO_DISTRIBUICAO_RENOV]       │
                           │                       │
                           └───────────────────────┘
                                      │ (admin distribui para inspetor)
                                      ▼
                           [EM_VISTORIA_RENOVACAO]
                           "Em vistoria de renovação"
                                      │
                    ┌─────────────────┴────────────────┐
                    │ (aprovada)                         │ (reprovada)
                    ▼                                    ▼
              [ALVARA_VIGENTE]                         [CIV]
              (novo APPCI emitido)             (cidadão corrige pendências)
                                                         │
                                              (retomar renovação)
                                                         ▼
                                       [AGUARDANDO_ACEITE_RENOVACAO] (loop)
```

### 11.1 Tabela completa de transições de estado

| Estado Origem | `TrocaEstadoLicenciamentoEnum` | Estado Destino | Classe de Implementação |
|---|---|---|---|
| `ALVARA_VIGENTE` | `ALVARA_VIGENTE_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO` | `TrocaEstadoLicenciamentoAlvaraVigenteParaAguardandoAceiteVistoriaRenovacaoRN` |
| `ALVARA_VENCIDO` | `ALVARA_VENCIDO_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO` | `TrocaEstadoLicenciamentoAlvaraVencidoParaAguardandoAceiteVistoriaRenovacaoRN` |
| `CIV` | `CIV_PARA_AGUARDANDO_ACEITE_VISTORIA_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO` | `TrocaEstadoLicenciamentoCivParaAguardandoAceiteVistoriaRenovacaoRN` |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_PAGAMENTO_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` | `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAguardandoPagamentoRenovacaoRN` |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO` | `AGUARDANDO_DISTRIBUICAO_RENOV` | `TrocaEstadoLicAguardandoAceiteRenovacaoParaAguardandoDistribuicaoRenovacaoRN` |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VIGENTE` | `ALVARA_VIGENTE` | `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAlvaraVigenteRN` |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VENCIDO` | `ALVARA_VENCIDO` | `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAlvaraVencidoRN` |
| `AGUARDANDO_ACEITE_RENOVACAO` | `AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV` | `CIV` | `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaCIVRN` |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | `AGUARDANDO_PAGAMENTO_VISTORIA_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` | `AGUARDANDO_DISTRIBUICAO_RENOV` | `TrocaEstadoLicenciamentoAguardandoPagamentoVistoriaRenovParaAguardandoDistribuicaoVistoriaRenovRN` |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | `AGUARDANDO_DISTRIBUICAO_RENOVACAO_PARA_EM_VISTORIA_RENOVACAO` | `EM_VISTORIA_RENOVACAO` | `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN` |
| `EM_VISTORIA_RENOVACAO` | (via `AppciCienciaCidadaoRenovacaoRN`) | `ALVARA_VIGENTE` | `AppciCienciaCidadaoRenovacaoRN` (ciência APPCI_RENOV) |
| `EM_VISTORIA_RENOVACAO` | (vistoria reprovada) | `CIV` | Fluxo de vistoria reprovada |

---

## 12. Marcos de Auditoria (TipoMarco)

Todos registrados em `TB_LICENCIAMENTO_MARCO` via `LicenciamentoMarcoInclusaoRN.inclui()`.

| Marco (`TipoMarco`) | Evento que o origina | `TipoResponsavelMarco` |
|---|---|---|
| `ACEITE_ANEXOD_RENOVACAO` | Cidadão/RT aceita o Anexo D da renovação | `CIDADAO` |
| `SOLICITACAO_ISENCAO_RENOVACAO` | Cidadão solicita isenção da taxa de vistoria de renovação | `CIDADAO` |
| `ANALISE_ISENCAO_RENOV_APROVADO` | Admin CBMRS defere a isenção de taxa de renovação | `BOMBEIROS` |
| `ANALISE_ISENCAO_RENOV_REPROVADO` | Admin CBMRS indefere a isenção de taxa de renovação | `BOMBEIROS` |
| `BOLETO_VISTORIA_RENOVACAO_PPCI` | Sistema gera boleto bancário para a taxa de vistoria de renovação | `SISTEMA` |
| `LIQUIDACAO_VISTORIA_RENOVACAO` | Pagamento do boleto confirmado via CNAB 240 (job P13-E) | `SISTEMA` |
| `DISTRIBUICAO_VISTORIA_RENOV` | Admin CBMRS distribui vistoria para inspetor | `BOMBEIROS` |
| `ENVIO_VISTORIA_RENOVACAO` | Vistoria de renovação enviada/agendada | `BOMBEIROS` |
| `ACEITE_VISTORIA_RENOVACAO` | Envolvido aceita o resultado da vistoria de renovação | `CIDADAO` |
| `FIM_ACEITES_VISTORIA_RENOVACAO` | Todos os envolvidos aceitaram o resultado da vistoria | `SISTEMA` |
| `VISTORIA_RENOVACAO` | Inspetor registra resultado aprovado da vistoria de renovação | `BOMBEIROS` |
| `VISTORIA_RENOVACAO_CIV` | Inspetor registra resultado reprovado (CIV gerada) | `BOMBEIROS` |
| `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | Admin homologa resultado deferido da vistoria de renovação | `BOMBEIROS` |
| `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` | Admin homologa resultado indeferido / retorna para vistoria | `BOMBEIROS` |
| `CIENCIA_APPCI_RENOVACAO` | Cidadão/RT toma ciência do novo APPCI emitido | `CIDADAO` |
| `CIENCIA_CIV_RENOVACAO` | Cidadão/RT toma ciência da CIV emitida na vistoria reprovada | `CIDADAO` |
| `LIBERACAO_RENOV_APPCI` | Sistema libera novo APPCI com nova data de validade | `SISTEMA` |
| `EMISSAO_DOC_COMPLEMENTAR_RENOV` | Sistema emite documentos complementares do novo APPCI | `SISTEMA` |

---

## 13. Modelo de Dados (Oracle)

### 13.1 Campos específicos de renovação em tabelas existentes

```sql
-- Tabela principal do licenciamento (extensões de renovação)
-- TB_LICENCIAMENTO
IND_SOLICITACAO_ISENCAO_RENOVACAO  CHAR(1) DEFAULT 'N'  -- SimNaoBooleanConverter
-- Demais campos de situação, histórico e identificação já existentes

-- Tabela de situação do licenciamento (enum Oracle como VARCHAR2)
-- TB_LICENCIAMENTO.DSC_SITUACAO valores de renovação:
'AGUARDANDO_ACEITE_RENOVACAO'       -- Aguardando aceite da renovação
'AGUARDANDO_PAGAMENTO_RENOVACAO'    -- Aguardando Pagamento ou isenção da Vistoria da Renovação
'AGUARDANDO_DISTRIBUICAO_RENOV'     -- Aguardando Distribuição de Vistoria da Renovação
'EM_VISTORIA_RENOVACAO'             -- Em vistoria de renovação
```

### 13.2 Tabela de marcos do licenciamento (renovação)

```sql
-- TB_LICENCIAMENTO_MARCO (já existente, apenas valores de renovação)
DSC_TIPO_MARCO VARCHAR2(100)
-- Valores de renovação inseridos:
'ACEITE_ANEXOD_RENOVACAO'
'SOLICITACAO_ISENCAO_RENOVACAO'
'ANALISE_ISENCAO_RENOV_APROVADO'
'ANALISE_ISENCAO_RENOV_REPROVADO'
'BOLETO_VISTORIA_RENOVACAO_PPCI'
'LIQUIDACAO_VISTORIA_RENOVACAO'
'DISTRIBUICAO_VISTORIA_RENOV'
'VISTORIA_RENOVACAO'
'VISTORIA_RENOVACAO_CIV'
'HOMOLOG_VISTORIA_RENOV_DEFERIDO'
'HOMOLOG_VISTORIA_RENOV_INDEFERIDO'
'CIENCIA_APPCI_RENOVACAO'
'CIENCIA_CIV_RENOVACAO'
'LIBERACAO_RENOV_APPCI'
'EMISSAO_DOC_COMPLEMENTAR_RENOV'
```

### 13.3 Tabela de histórico de situação

```sql
-- TB_LICENCIAMENTO_SITUACAO_HIST (já existente)
-- Cada transição de estado do licenciamento durante P14 gera um INSERT:
ID_LICENCIAMENTO      NUMBER       → ID do licenciamento
DSC_SITUACAO_ANTERIOR VARCHAR2(50) → situação de origem (ex.: 'ALVARA_VIGENTE')
DSC_SITUACAO_ATUAL    VARCHAR2(50) → situação de destino (ex.: 'AGUARDANDO_ACEITE_RENOVACAO')
DTH_SITUACAO_ANTERIOR DATE         → obj.getCtrDthAtu() (timestamp da última alteração)
DTH_SITUACAO_ATUAL    TIMESTAMP    → SYSTIMESTAMP
```

### 13.4 Tabela de vistorias (tipo de renovação)

```sql
-- TB_VISTORIA
DSC_TIPO_VISTORIA VARCHAR2(30)
-- Valor específico de renovação:
'VISTORIA_RENOVACAO'  -- ordinal 3 no enum TipoVistoria
```

### 13.5 DTO de renovação do APPCI

O `AppciRenovacaoDTO` transporta dados do APPCI atual para exibição no portal durante o processo de renovação:

```java
// AppciRenovacaoDTO — Lombok @Builder @Getter @Setter
public class AppciRenovacaoDTO {
    Integer numeroPedido;   // TB_APPCI.NUM_PEDIDO
    String  validade;       // TB_APPCI.DAT_VALIDADE (formatada)
    String  inicioVigencia; // TB_APPCI.DAT_INICIO_VIGENCIA (formatada)
    String  fimVigencia;    // TB_APPCI.DAT_FIM_VIGENCIA (formatada)
}
```

### 13.6 Campos Oracle relevantes nas queries de renovação

```sql
-- SimNaoBooleanConverter: campo CHAR(1) — 'S' = true, 'N' = false
-- Usado em TB_LICENCIAMENTO:
IND_SOLICITACAO_ISENCAO_RENOVACAO CHAR(1)
-- Queries Hibernate devem usar String literal "S"/"N", não booleano Java

-- Consulta de elegibilidade para renovação (LicenciamentoBD):
SELECT l.* FROM TB_LICENCIAMENTO l
WHERE l.DSC_SITUACAO IN ('ALVARA_VIGENTE', 'ALVARA_VENCIDO')

-- Consulta para "Minhas Renovações":
SELECT l.* FROM TB_LICENCIAMENTO l
WHERE l.DSC_SITUACAO IN (
    'AGUARDANDO_ACEITE_PRPCI', 'AGUARDANDO_ACEITE_RENOVACAO',
    'AGUARDANDO_CIENCIA_CIV', 'CIV',
    'AGUARDANDO_PAGAMENTO_RENOVACAO', 'EM_VISTORIA_RENOVACAO',
    'RECURSO_EM_ANALISE_1_CIV', 'RECURSO_EM_ANALISE_2_CIV'
)
AND (... filtro de envolvido por CPF ...)
```

---

## 14. API REST — Endpoints JAX-RS

Base path: `/licenciamentos` (contexto JAX-RS configurado no WildFly)

| Método HTTP | Path | Classe | Método Java | Proteção | RNs |
|---|---|---|---|---|---|
| `GET` | `/minha-solicitacoes-renovacao` | `LicenciamentoRest` | `listarMinhasSolicitacoesRenovacao()` | Usuário autenticado SOE | RN-154, RN-156 |
| `GET` | `/termo-anexo-d-renovacao/{idLic}` | `LicenciamentoRest` | `getTermoAnexoDRenovacao()` | Envolvido no licenciamento | RN-144 |
| `PUT` | `/termo-anexo-d-renovacao/{idLic}` | `LicenciamentoRest` | `cadastraTermoAnexoDRenovacao()` | Envolvido no licenciamento | RN-144 |
| `DELETE` | `/termo-anexo-d-renovacao/{idLic}` | `LicenciamentoRest` | `removerAceiteAnexoDRenovacao()` | Envolvido no licenciamento | RN-144 |
| `GET` | `/{idLic}/reponsaveis-pagamento-renovacao` | `LicenciamentoRest` | `listaResponsaveisParaPagamentoRenovacao()` | `@AutorizaEnvolvido` | RN-146 |
| `PUT` | `/{idLic}/solicitacaoIsencao` | `LicenciamentoRest` | `setSolicitacaoIsencao()` | `@AutorizaEnvolvido` | RN-147, RN-157 |
| `GET` | `/minha-solicitacoes-renovacao` | `LicenciamentoRest` | `listaRenovacaoPorTermoEPorUsuarioLogado()` | Usuário autenticado SOE | RN-156 |

### 14.1 Cabeçalhos e convenções JAX-RS

```java
@ApplicationPath("/api")
// Todos os endpoints produzem e consomem application/json

// Autenticação: token Bearer JWT SOE PROCERGS (meu.rs.gov.br)
// CPF do usuário extraído do contexto de segurança:
@Context SecurityContext securityContext;
String cpf = securityContext.getUserPrincipal().getName();

// Anotações de segurança da arquitetura atual:
@AutorizaEnvolvido   // verifica se o usuário é envolvido do licenciamento
@SegurancaEnvolvidoInterceptor  // interceptor CDI que valida envolvimento
```

### 14.2 Parâmetros do endpoint de listagem de renovações

```java
@GET
@Path("/minha-solicitacoes-renovacao")
public Response listarMinhasSolicitacoesRenovacao(
    @QueryParam("ordenar")     @DefaultValue("ctrDthInc") String ordenar,
    @QueryParam("ordem")       @DefaultValue("asc")       String ordem,
    @QueryParam("paginaAtual") @DefaultValue("0")         Integer paginaAtual,
    @QueryParam("tamanho")     @DefaultValue("20")        Integer tamanho,
    @QueryParam("situacao")    List<SituacaoLicenciamento> situacoes,
    @QueryParam("tipo")        List<TipoLicenciamento>     tipos,
    @QueryParam("cidade")      String cidade,
    @QueryParam("numero")      String numero,
    @QueryParam("termo")       String termo
) {
    // PedidoLicenciamentoCidadao ped = BuilderPedido.of()...instance();
    ped.setRenovacao(true);
    if (StringUtils.isEmpty(termo)) {
        return Response.ok(licenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacao(ped)).build();
    } else {
        return Response.ok(licenciamentoCidadaoRN.listaMinhaSolicitacoesRenovacaoTermo(ped)).build();
    }
}
```

---

## 15. Segurança e Autorização

### 15.1 Mecanismo de autenticação

A stack atual utiliza **OAuth2/OIDC Implicit Flow** com o IdP **SOE PROCERGS** (meu.rs.gov.br). O token JWT/OIDC carrega o CPF do usuário autenticado. O frontend Angular usa a biblioteca `angular-oauth2-oidc` para gerenciar o ciclo de vida do token.

### 15.2 Interceptor de segurança

O `@SegurancaEnvolvidoInterceptor` é um interceptor CDI aplicado sobre EJBs como `LicenciamentoRenovacaoCidadaoRN` e `LicenciamentoResponsavelPagamentoRN`. Ele valida, antes de qualquer operação, que o CPF do usuário autenticado está vinculado ao licenciamento como envolvido.

### 15.3 Anotação `@AutorizaEnvolvido`

Anotação JAX-RS aplicada diretamente nos endpoints REST (ex.: `/{idLic}/solicitacaoIsencao`). Verifica que o usuário logado é um envolvido do licenciamento identificado pelo `idLic` do path.

### 15.4 Validações de permissão específicas de renovação

Três validações distintas em `LicenciamentoRenovacaoRNVal`:

```java
// 1. Valida situação do licenciamento
public void validarSituacaoParaEdicao(SituacaoLicenciamento situacao) {
    List<SituacaoLicenciamento> validas = Arrays.asList(
        ALVARA_VENCIDO, ALVARA_VIGENTE, AGUARDANDO_ACEITE_RENOVACAO, CIV);
    if (!validas.contains(situacao)) {
        throw new WebApplicationRNException(
            bundle.getMessage("licenciamento.status.editar"), Response.Status.NOT_ACCEPTABLE);
    }
}

// 2. Valida que RT do usuário é de RENOVACAO_APPCI
public void validarResponsaveisTecnicos(List<ResponsavelTecnico> rts, String cpf) {
    if (rts.isEmpty()) {
        throw new WebApplicationRNException(
            bundle.getMessage("licenciameto.rts.renovacao.invalido"), NOT_ACCEPTABLE);
    }
    Optional<ResponsavelTecnico> findAny = rts.stream()
        .filter(x -> x.getTipoResponsabilidadeTecnica()
                       .equals(TipoResponsabilidadeTecnica.RENOVACAO_APPCI)
                    && x.getCpf().equals(cpf))
        .findAny();
    if (!findAny.isPresent()) {
        throw new WebApplicationRNException(
            bundle.getMessage("usuario.sem.permissao.rt.renovacao"), NOT_ACCEPTABLE);
    }
}

// 3. Valida permissão geral de alteração
public void validarResponsaveisTecnicosRenovacaoAppci(
    Set<ResponsavelUsoED> rus, Set<ResponsavelTecnicoED> rts,
    Set<LicenciamentoProprietarioED> prop, String cpf) {

    Optional<ResponsavelTecnicoED> rt = rts.stream()
        .filter(x -> x.getTipoResponsabilidadeTecnica()
                       .equals(TipoResponsabilidadeTecnica.RENOVACAO_APPCI)
                    && x.getUsuario().getCpf().equals(cpf))
        .findAny();
    Optional<ResponsavelUsoED> ru = rus.stream()
        .filter(x -> x.getUsuario().getCpf().equals(cpf)).findAny();
    Optional<LicenciamentoProprietarioED> pro = prop.stream()
        .filter(x -> x.getProprietario().getCpfCnpj().endsWith(cpf)).findAny();
    Optional<LicenciamentoProprietarioED> proc = prop.stream()
        .filter(x -> x.getProcurador().isPresent()
                  && x.getProcurador().get().getUsuario().getCpf().endsWith(cpf))
        .findAny();

    if (!rt.isPresent() && !ru.isPresent() && !pro.isPresent() && !proc.isPresent()) {
        throw new WebApplicationRNException(
            bundle.getMessage("licenciameto.rt.renovacao.sem.permissao"), NOT_ACCEPTABLE);
    }
}
```

---

## 16. Notificações e E-mails

### 16.1 Templates de e-mail (messages.properties)

| Chave | Conteúdo / Uso |
|---|---|
| `notificacao.email.assunto.RENOVACAO` | `"Atualização da requisição de renovação do licenciamento"` |
| `notificacao.email.template.renovacao.incluido` | Notificação de inclusão de envolvido em renovação |
| `notificacao.email.template.licenciamento.EM_VISTORIA_RENOVACAO` | Notificação de agendamento de vistoria de renovação |
| `notificacao.email.template.licenciamento.vistoria.renovacao.conclusao` | Notificação de conclusão da vistoria de renovação |
| `notificacao.email.template.licenciamento.isencao.renovacao` | Resposta da análise de isenção de taxa de renovação |
| `notificacao.email.template.perda.periodo.renovacao` | Notificação de período de renovação vencido (cidadão não renoveu) |

### 16.2 Contexto de notificação

`ContextoNotificacaoEnum.RENOVACAO` — diferencia notificações de renovação das demais notificações do sistema SOL.

### 16.3 Infraestrutura de envio

E-mails enviados via JavaMail configurado no WildFly via JNDI `java:jboss/mail/Default`. O envio está desacoplado do fluxo principal: as notificações são enfileiradas em `TB_LICENCIAMENTO_NOTIFICACAO` pelo processo de renovação e efetivamente enviadas por SMTP pelo job P13-D (`EJBTimerService.enviarNotificacaoLicenciamento()` — 00:31 diário).

---

## 17. Classes, EJBs e Componentes

### 17.1 Tabela de classes por responsabilidade

| Classe | Pacote | Tipo | Responsabilidade |
|---|---|---|---|
| `LicenciamentoRenovacaoCidadaoRN` | `licenciamentorenovacao` | `@Stateless EJB` | Determina o próximo TrocaEstado baseado na lógica de `appciRN` + `vistoriaRN` |
| `LicenciamentoRenovacaoRNVal` | `licenciamentorenovacao` | CDI Bean | Validações de situação e permissão específicas de renovação |
| `AppciCienciaCidadaoRenovacaoRN` | `licenciamentociencia.appci` | `@Stateless EJB` | Processa a ciência do novo APPCI de renovação (`TipoLicenciamentoCiencia.APPCI_RENOV`) |
| `LicenciamentoResponsavelPagamentoRN` | `licenciamento` | `@Stateless EJB` | Lista responsáveis para pagamento; método `listaResponsaveisParaPagamentoRenovacao()` filtra por `RENOVACAO_APPCI` |
| `TermoLicenciamentoRN` | `termolicenciamento` | `@Stateless EJB` | Gerencia aceite/remoção do Anexo D de Renovação; métodos `confirmaInclusaoAnexoDRenovacao()`, `removeAceiteAnexoDRenovacao()`, `retornoCienciaETermoRenovacao()` |
| `TrocaEstadoLicenciamentoAlvaraVigenteParaAguardandoAceiteVistoriaRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `ALVARA_VIGENTE` → `AGUARDANDO_ACEITE_RENOVACAO`; inject `LicenciamentoMarcoInclusaoRN` com `CIDADAO` |
| `TrocaEstadoLicenciamentoAlvaraVencidoParaAguardandoAceiteVistoriaRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `ALVARA_VENCIDO` → `AGUARDANDO_ACEITE_RENOVACAO`; inject `LicenciamentoMarcoInclusaoRN` com `CIDADAO` |
| `TrocaEstadoLicenciamentoCivParaAguardandoAceiteVistoriaRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `CIV` → `AGUARDANDO_ACEITE_RENOVACAO`; inject `LicenciamentoMarcoInclusaoRN` com `CIDADAO` |
| `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAguardandoPagamentoRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_ACEITE_RENOVACAO` → `AGUARDANDO_PAGAMENTO_RENOVACAO` |
| `TrocaEstadoLicAguardandoAceiteRenovacaoParaAguardandoDistribuicaoRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_ACEITE_RENOVACAO` → `AGUARDANDO_DISTRIBUICAO_RENOV`; herda de `TrocaEstadoLicenciamentoParaAguardandoDistribuicaoVistoriaBaseRN` |
| `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAlvaraVigenteRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_ACEITE_RENOVACAO` → `ALVARA_VIGENTE` (cidadão recusou) |
| `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaAlvaraVencidoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_ACEITE_RENOVACAO` → `ALVARA_VENCIDO` (cidadão recusou, alvará vencido) |
| `TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaCIVRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_ACEITE_RENOVACAO` → `CIV` (havia CIV pendente) |
| `TrocaEstadoLicenciamentoAguardandoDistribuicaoRenovacaoParaEmVistoriaRenovacaoRN` | `licenciamento.trocaestado` | `@Stateless EJB` | `AGUARDANDO_DISTRIBUICAO_RENOV` → `EM_VISTORIA_RENOVACAO`; registra marco `DISTRIBUICAO_VISTORIA_RENOV` com `BOMBEIROS` |
| `TrocaEstadoVistoriaEmAprovacaoRenovacaoParaEmVistoriaRN` | `vistoria` | `@Stateless EJB` | Transição de status de vistoria: `EM_APROVACAO_RENOVACAO` → `EM_VISTORIA`; registra marco `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` com `BOMBEIROS` |
| `AppciRenovacaoDTO` | `dto` | DTO (Lombok) | Dados do APPCI atual para exibição durante renovação: `numeroPedido`, `validade`, `inicioVigencia`, `fimVigencia` |

### 17.2 Padrão CDI Qualifier para seleção de TrocaEstado

O sistema usa CDI Qualifiers para resolver o `TrocaEstadoLicenciamentoRN` correto via injeção:

```java
// Qualifier de seleção de TrocaEstado
@Qualifier
@Retention(RUNTIME)
@Target({TYPE, FIELD, METHOD})
public @interface TrocaEstadoLicenciamentoQualifier {
    TrocaEstadoLicenciamentoEnum trocaEstado();
}

// Cada classe de TrocaEstado é anotada com seu enum específico:
@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV)
public class TrocaEstadoLicenciamentoAguardandoAceiteRenovacaoParaCIVRN extends ... { ... }

// E injetada no LicenciamentoRenovacaoCidadaoRN:
@Inject
@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV)
private TrocaEstadoLicenciamentoRN trocaEstadoParaCIVRN;
```

### 17.3 Padrão de herança das classes TrocaEstado

```
TrocaEstadoLicenciamentoRN (interface)
    └── TrocaEstadoLicenciamentoBaseRN (abstract)
            atualizaSituacaoLicenciamento(Long idLicenciamento):
                1. licenciamentoRN.consulta(idLicenciamento)
                2. LicenciamentoSituacaoHistRN.inclui(hist) — grava histórico
                3. licenciamentoED.setSituacao(getNovaSituacaoLicenciamento())
                4. licenciamentoRN.altera(licenciamentoED) → entityManager.merge()
                5. retorna licenciamentoED atualizado
        └── Cada classe concreta sobrescreve:
              - trocaEstado(Long): lógica adicional (marcos, notificações)
              - getNovaSituacaoLicenciamento(): retorna a situação destino
```

---

## 18. Casos de Teste

| ID | Cenário | Entrada | Resultado Esperado |
|---|---|---|---|
| CT-P14-01 | Iniciar renovação — alvará vigente | Licenciamento `ALVARA_VIGENTE` + RT `RENOVACAO_APPCI` autenticado | Situação → `AGUARDANDO_ACEITE_RENOVACAO`; histórico gravado; e-mail enviado |
| CT-P14-02 | Iniciar renovação — alvará vencido | Licenciamento `ALVARA_VENCIDO` + RT autenticado | Situação → `AGUARDANDO_ACEITE_RENOVACAO` |
| CT-P14-03 | Iniciar renovação sem RT de renovação | Licenciamento sem RT `RENOVACAO_APPCI` | HTTP 406 — `"Para solicitar a renovação do alvará, deve ser adicionado um responsável técnico com tipo de responsabilidade técnica 'Renovação de APPCI'"` |
| CT-P14-04 | Iniciar renovação com usuário sem permissão | Usuário não é RT/RU/Proprietário/Procurador | HTTP 406 — `"Alteração de responsáveis técnicos só pode ser realizada por um responsável técnico de Renovação de APPCI ou proprietário ou responsável pelo uso"` |
| CT-P14-05 | Iniciar renovação em situação inválida | Licenciamento em `EM_ANALISE` | HTTP 406 — `"Situação do licenciamento não pode ser editada"` |
| CT-P14-06 | Aceitar Anexo D | Licenciamento em `AGUARDANDO_ACEITE_RENOVACAO` | Marco `ACEITE_ANEXOD_RENOVACAO` registrado; `RetornoCienciaTermoAnexoDDTO` retornado atualizado |
| CT-P14-07 | Remover aceite do Anexo D | Aceite existente + `removeAceiteAnexoDRenovacao(idLic, true)` | Aceite removido; `RetornoCienciaTermoAnexoDDTO` atualizado com `aceito = false` |
| CT-P14-08 | Confirmar renovação — sem CIV, sem isenção | Última vistoria `APROVADO` + sem isenção aprovada | Situação → `AGUARDANDO_PAGAMENTO_RENOVACAO` |
| CT-P14-09 | Confirmar renovação — isenção deferida | Última vistoria `APROVADO` + isenção aprovada | Situação → `AGUARDANDO_DISTRIBUICAO_RENOV` |
| CT-P14-10 | Confirmar renovação — CIV pendente | Última vistoria = `REPROVADO` | Situação → `CIV` via `AGUARDANDO_ACEITE_RENOVACAO_PARA_CIV` |
| CT-P14-11 | Recusar renovação — alvará vigente | `getTrocaEstadoAnteriorRenovacao()` → validadeAlvara ≥ hoje | Situação → `ALVARA_VIGENTE` via `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VIGENTE` |
| CT-P14-12 | Recusar renovação — alvará vencido | `getTrocaEstadoAnteriorRenovacao()` → `Calendar.now().after(validadeAlvara)` | Situação → `ALVARA_VENCIDO` via `AGUARDANDO_ACEITE_RENOVACAO_PARA_ALVARA_VENCIDO` |
| CT-P14-13 | Pagamento confirmado via CNAB | Job P13-E processa arquivo CNAB 240 Banrisul | Situação → `AGUARDANDO_DISTRIBUICAO_RENOV`; marco `LIQUIDACAO_VISTORIA_RENOVACAO` |
| CT-P14-14 | Admin distribui vistoria de renovação | Admin CBMRS seleciona inspetor | Situação → `EM_VISTORIA_RENOVACAO`; marco `DISTRIBUICAO_VISTORIA_RENOV` com `BOMBEIROS` |
| CT-P14-15 | Ciência do APPCI renovado | Cidadão/RT acessa endpoint de ciência | `isLicenciamentoCienciaAprovado() = true`; marco `CIENCIA_APPCI_RENOVACAO`; situação → `ALVARA_VIGENTE`; marco `LIBERACAO_RENOV_APPCI` |

---

## 19. Comparativo com P03 (Primeira Submissão)

| Aspecto | P03 (Primeira Submissão) | P14 (Renovação) |
|---|---|---|
| **Estado de entrada** | Licenciamento criado (novo) | `ALVARA_VIGENTE` ou `ALVARA_VENCIDO` existente |
| **Análise técnica** | Obrigatória (P04) | Não há — PPCI já aprovado em P03 |
| **Tipo de vistoria** | `TipoVistoria.PPCI` (ordinal 0) | `TipoVistoria.VISTORIA_RENOVACAO` (ordinal 3) |
| **RT obrigatório** | RT de projeto/execução/medidas | Exclusivamente `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` |
| **Aceite de termos** | Não há Anexo D de renovação | Aceite obrigatório do Anexo D via `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao()` |
| **Responsáveis pagamento** | `listaResponsaveisParaPagamento()` — filtra por fase (`EXECUCAO`) | `listaResponsaveisParaPagamentoRenovacao()` — filtra exclusivamente por `RENOVACAO_APPCI` |
| **Ciência de APPCI** | `TipoLicenciamentoCiencia.APPCI` (P08) | `TipoLicenciamentoCiencia.APPCI_RENOV` (`AppciCienciaCidadaoRenovacaoRN`) |
| **Marco de distribuição** | `DISTRIBUICAO_VISTORIA` | `DISTRIBUICAO_VISTORIA_RENOV` |
| **Endpoint de listagem** | `/minhas-solicitacoes` | `/minha-solicitacoes-renovacao` (flag `renovacao = true`) |
| **Isenção de taxa** | `solicitacaoIsencao = true` em `TB_LICENCIAMENTO` | `solicitacaoIsencaoRenovacao = true` em campo separado `IND_SOLICITACAO_ISENCAO_RENOVACAO` |
| **Sequência de situações** | `NOVA → ... → ALVARA_VIGENTE` (longa) | `ALVARA_VIGENTE/VENCIDO → AGUARDANDO_ACEITE_RENOVACAO → ... → ALVARA_VIGENTE` |

---

*Documento gerado em 2026-03-16. Regras de Negócio: RN-141 a RN-160. Referência principal: código-fonte `SOLCBM.BackEnd16-06` — pacotes `com.procergs.solcbm.licenciamentorenovacao`, `com.procergs.solcbm.licenciamento.trocaestado` e `com.procergs.solcbm.licenciamentociencia`.*

---

## 20. Complementos Normativos (RT de Implantação SOL-CBMRS 4ª Ed./2022)

Esta seção acrescenta regras de negócio derivadas da leitura direta da RT de Implantação SOL-CBMRS 4ª Edição/2022. Nenhuma regra anterior (RN-141 a RN-160) é revogada.

---

### RN-P14-N1 — Prazo Mínimo de Antecedência para Solicitação de Renovação

**Base normativa:** item 8.1.2c da RT de Implantação SOL-CBMRS 4ª Ed./2022.

O proprietário/responsável deve solicitar a renovação do APPCI com **antecedência mínima de 2 (dois) meses** antes do vencimento. O sistema aceita solicitações de renovação a partir de **90 dias corridos** antes da data de vencimento do APPCI vigente (janela adequada para a tramitação completa do processo).

**Requisitos de implementação:**

- O endpoint de iniciação da renovação (`PUT /licenciamentos/{idLic}/renovacao` ou equivalente) deve validar, além da situação do licenciamento (RN-141), se a data atual está dentro da janela permitida para solicitação:
  - **Permitido:** `dataVencimentoAppci - 90 dias <= dataAtual <= dataVencimentoAppci`
  - **Alvará já vencido:** sempre permitido (situação `ALVARA_VENCIDO`).
  - **Mais de 90 dias antes:** retornar aviso (não bloqueante) informando que o portal aceitará a solicitação a partir de `[dataVencimento - 90 dias]`.
- O aviso de antecedência mínima de 2 meses (60 dias) é informativo — gerado pelos jobs P13-H (60 dias) e P13-I (30 dias). A solicitação com menos de 60 dias de antecedência é permitida pelo sistema, mas o cidadão recebe aviso de que pode não haver tempo hábil para conclusão antes do vencimento.
- A validação de 90 dias deve ser implementada em `LicenciamentoRenovacaoRNVal.validarJanelaRenovacao(Long idLicenciamento)`.

**Mensagens de interface:**

| Situação | Mensagem exibida |
|---|---|
| Mais de 90 dias antes do vencimento | "A renovação pode ser solicitada a partir de [DD/MM/AAAA]. Você será notificado com antecedência." |
| Entre 90 e 61 dias antes | "Você está dentro do prazo para solicitar a renovação. Inicie o processo para garantir o alvará renovado antes do vencimento." |
| Entre 60 e 1 dia antes | "Atenção: o prazo mínimo recomendado de 2 meses já foi atingido. Inicie a renovação imediatamente." |
| Alvará vencido | "Seu alvará está vencido. Inicie a renovação para regularizar a situação do estabelecimento." |

---

### RN-P14-N2 — Validade do Novo APPCI Calculada Automaticamente

**Base normativa:** itens 6.5.3.1 e 6.5.3.2 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

A nova validade do APPCI emitido ao final da renovação é calculada com base no **tipo de ocupação e grau de risco da edificação no momento da renovação** — não com base nos dados do APPCI anterior.

**Critério de validade:**

| Tipo de ocupação / risco | Validade |
|---|---|
| Grupo F (reunião de público) com risco médio ou alto + locais de elevado risco (ex.: hospitais, shopping centers, estádios) | **2 (dois) anos** |
| Demais edificações | **5 (cinco) anos** |

**Requisitos de implementação:**

- O `AppciRN` (ou equivalente na stack atual: `AppciRN`) deve calcular a validade do novo APPCI com base na classificação da edificação no momento da emissão do APPCI de renovação.
- A classificação de grupo (ex.: Grupo F) e o grau de risco devem ser lidos dos dados do licenciamento/edificação vigentes (tabelas `TB_LICENCIAMENTO`, `TB_EDIFICACAO` ou equivalentes) no momento da emissão.
- O campo `dataValidade` do novo `AppciED` deve ser calculado como: `dataEmissao + 2 anos` ou `dataEmissao + 5 anos`, conforme o critério acima.
- O campo `fimVigencia` do `AppciRenovacaoDTO` deve refletir a nova validade calculada automaticamente.
- A lógica de cálculo deve ser centralizada em um método `calcularValidadeAppciRenovacao(Long idLicenciamento): LocalDate` no `AppciRN`, reutilizável em testes unitários.

**Nota:** A stack atual utiliza `Calendar` para datas. O cálculo deve usar `Calendar.add(Calendar.YEAR, 2)` ou `Calendar.add(Calendar.YEAR, 5)` conforme o tipo de ocupação.

---

### RN-P14-N3 — Dados Pré-preenchidos na Renovação

O wizard de renovação **pré-carrega todos os dados aprovados no APPCI anterior** para reduzir o esforço do cidadão e do RT no preenchimento:

- Responsáveis técnicos vinculados ao licenciamento.
- Responsável pelo uso (RU) e proprietário(s).
- Medidas de segurança contra incêndio cadastradas no PPCI aprovado.
- Características da edificação (área, altura, número de pavimentos, tipo de ocupação).

**Requisitos de implementação:**

- O RT confirma ou atualiza apenas os dados que sofreram alteração desde a última aprovação.
- O sistema deve registrar o **delta de alterações** entre a versão anterior do licenciamento e a versão em renovação. O delta deve ser armazenado na tabela de histórico (`TB_LICENCIAMENTO_SITUACAO_HIST` ou tabela específica `TB_LICENCIAMENTO_RENOVACAO_DELTA`) com os campos alterados, valor anterior e novo valor.
- Campos imutáveis (endereço da edificação, isolamento de riscos) continuam bloqueados — a extinção (P12, RN-P12-N1) é o procedimento para correção desses campos.
- A pré-carga é realizada pelo endpoint `GET /licenciamentos/termo-anexo-d-renovacao/{idLic}`, que já retorna dados do `AppciRenovacaoDTO`. Esse endpoint deve ser estendido para incluir também os dados de responsáveis, características da edificação e medidas de segurança pré-carregados.

---

### RN-P14-N4 — APPCI Vigente Válido até Emissão do Novo

**Base normativa:** item 10.2.1 da RT de Implantação SOL-CBMRS 4ª Ed./2022.

O APPCI atual permanece **válido até seu vencimento** ou até a **emissão do novo APPCI de renovação**, o que ocorrer primeiro. O cidadão e o estabelecimento não ficam sem cobertura durante a tramitação do processo de renovação.

**Requisitos de implementação:**

- O sistema deve exibir **ambos os APPCIs** (o vigente e o em renovação) no portal do cidadão, com status distintos:
  - APPCI vigente: exibido com status `"Válido até DD/MM/AAAA"` enquanto o processo de renovação tramita.
  - APPCI em renovação: exibido com status `"Renovação em andamento"` (com indicação da fase atual do processo).
- O campo `indVersaoVigente = true` permanece no APPCI atual (`AppciED`) até que o novo APPCI de renovação seja emitido e homologado.
- Somente após a ciência do novo APPCI de renovação (`TipoLicenciamentoCiencia.APPCI_RENOV` via `AppciCienciaCidadaoRenovacaoRN`) é que o sistema:
  1. Seta `indVersaoVigente = false` no APPCI antigo.
  2. Seta `indVersaoVigente = true` no novo APPCI emitido.
  3. Transita o licenciamento para `ALVARA_VIGENTE` com a nova data de validade.
- Em caso de vencimento do APPCI durante a tramitação da renovação (job P13-A executa antes da conclusão da renovação), o job **não deve alterar** a situação do licenciamento se este já estiver em uma das situações de renovação (`AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO`). O job P13-A deve excluir essas situações de sua query de detecção (ver RN-121 — complementar com filtro de exclusão de situações de renovação).
- Exibir no dashboard do cidadão um banner informativo: "Seu APPCI está em processo de renovação. O alvará atual permanece válido até [DD/MM/AAAA] ou até a emissão do novo alvará renovado."

---

*Seção 20 adicionada em 2026-03-20. Base normativa: RT de Implantação SOL-CBMRS 4ª Edição/2022 (itens 6.5.3.1, 6.5.3.2, 8.1.2c e 10.2.1).*
