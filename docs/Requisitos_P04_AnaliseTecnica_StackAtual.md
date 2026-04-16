# Requisitos P04 — Análise Técnica de Licenciamento (ATEC)
## Stack Atual — Java EE / WildFly / Alfresco / SOE PROCERGS

**Processo:** P04 — Análise Técnica Administrativa (ATEC)
**Entrada:** Licenciamento na situação `AGUARDANDO_DISTRIBUICAO`
**Saída A (aprovação):** Situação `CA` (PPCI) ou `ALVARA_VIGENTE` (PSPCIM) — documento CA/APPCI emitido e autenticado
**Saída B (reprovação):** Situação `AGUARDANDO_CIENCIA` — documento CIA emitido e autenticado
**Versão:** 1.0 — 2026-03-09

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica Atual](#2-stack-tecnológica-atual)
3. [Modelo de Dados](#3-modelo-de-dados)
4. [Enumerações](#4-enumerações)
5. [Regras de Negócio por Etapa](#5-regras-de-negócio-por-etapa)
   - 5.1 Distribuição da Análise
   - 5.2 Registro de Resultados por Item
   - 5.3 Emissão de CIA (Reprovação)
   - 5.4 Emissão de CA (Aprovação — envio para homologação)
   - 5.5 Homologação pelo Coordenador
   - 5.6 Cancelamento Administrativo
6. [Padrão Strategy de Resultados](#6-padrão-strategy-de-resultados)
7. [Geração de Documentos PDF](#7-geração-de-documentos-pdf)
8. [API REST (JAX-RS)](#8-api-rest-jax-rs)
9. [Segurança e Controle de Acesso](#9-segurança-e-controle-de-acesso)
10. [Auditoria](#10-auditoria)
11. [Notificações e Marcos](#11-notificações-e-marcos)
12. [Tratamento de Erros](#12-tratamento-de-erros)

---

## 1. Visão Geral do Processo

O Processo P04 representa a **Análise Técnica de Licenciamento (ATEC)** realizada pelos analistas do CBM-RS. É o processo central de avaliação do PPCI (Plano de Prevenção e Proteção Contra Incêndio) ou PSPCIM submetido pelo Responsável Técnico (RT) no P03.

### 1.1 Fluxo resumido

```
[AGUARDANDO_DISTRIBUICAO]
         |
         v
  [Coordenador distribui para Analista]
         |
         v
     [EM_ANALISE]  <------ (Indeferimento de homologação)
         |
         +---> Analista registra resultados por item (11 tipos)
         |
         +----> indeferir (CIA): algum item REPROVADO ou outraInconformidade preenchida
         |           |
         |           v
         |     status analise: REPROVADO
         |     Gera CIA PDF autenticado (Alfresco)
         |     Marco: ATEC_CIA
         |     Licenciamento: [AGUARDANDO_CIENCIA] --> (P05 - Ciência/Recurso)
         |
         +----> deferir (CA): todos os itens APROVADOS, sem outraInconformidade
                     |
                     v
               status analise: EM_APROVACAO
               Marco: ATEC_CA (PPCI) / ATEC_APPCI (PSPCIM)
                     |
                     v
         [Coordenador homologa — /adm/analise-tecnica-hom]
                     |
                     +----> deferir:
                     |        status analise: APROVADO
                     |        Gera CA ou APPCI PDF autenticado (Alfresco)
                     |        Marco: HOMOLOG_ATEC_DEFERIDO / HOMOLOG_ATEC_APPCI
                     |        Licenciamento: [CA] (PPCI) / [ALVARA_VIGENTE] (PSPCIM)
                     |
                     +----> indeferir:
                              status analise: EM_ANALISE (volta ao analista)
                              indeferimentoHomolog: justificativa
                              Marco: HOMOLOG_ATEC_INDEFERIDO

[Cancelamento Administrativo]
         |
         v
     status: CANCELADA
     Licenciamento volta a: [AGUARDANDO_DISTRIBUICAO]
```

### 1.2 Atores envolvidos

| Ator | Papel |
|---|---|
| Coordenador CBM-RS | Distribui análises, cancela distribuições, homologa resultado |
| Analista CBM-RS | Executa a análise técnica, registra resultados por item, emite CIA ou envia para CA |
| Sistema SOL | Transições de estado, geração de documentos PDF, registro de marcos, notificações |

### 1.3 Tipos de licenciamento suportados

| `TipoLicenciamento` | Descrição | Documento na aprovação |
|---|---|---|
| `PPCI` | Plano de Prevenção e Proteção Contra Incêndio | CA (Certificado de Aprovação) |
| `PSPCIM` | Plano Simplificado de Proteção Contra Incêndio em Meios | APPCI + Documento Complementar |

---

## 2. Stack Tecnológica Atual

| Camada | Tecnologia |
|---|---|
| Linguagem | Java 8 (EE) |
| Servidor de aplicação | WildFly / JBoss (Jakarta EE) |
| API REST | JAX-RS (`@Path`, `@GET`, `@PUT`, `@POST`) |
| Camada de negócio | EJB `@Stateless` + CDI `@Inject` |
| Interceptores | `@AppInterceptor` (logging, controle transacional) |
| Persistência | JPA/Hibernate + Criteria API (`DetachedCriteria`) |
| Banco de dados | Oracle ou PostgreSQL (relacional) |
| Armazenamento de arquivos | Alfresco ECM (`identificadorAlfresco` = nodeRef) |
| Autenticação/Autorização | SOE PROCERGS / meu.rs.gov.br (`SessionMB`, `@Permissao`) |
| Auditoria | Hibernate Envers (`@Audited`) |
| Conversão booleana no BD | `SimNaoBooleanConverter` (`Boolean` Java ↔ `'S'/'N'` no BD) |
| Transações | `@TransactionAttribute(TransactionAttributeType.REQUIRED)` |

### 2.1 Padrão de camadas do módulo ATEC

```
[REST - JAX-RS]
    AnaliseLicenciamentoTecnicaConclusaoRest
    AnaliseLicenciamentoTecnicaConsultaRest
    AnaliseLicenciamentoTecnicaDocumentoRest
    AnaliseLicenciamentoTecnicaHomRest
    AnaliseLicenciamentoTecnicaCancelamentoAdmRest
          |
          v
[RN - @Stateless EJB]
    AnaliseLicenciamentoTecnicaDistribuicaoRN    ← distribuição
    AnaliseLicenciamentoTecnicaCARN              ← emissão CA (analista)
    AnaliseLicenciamentoTecnicaCIARN             ← emissão CIA (analista)
    AnaliseLicenciamentoTecnicaHomRN             ← homologação (coordenador)
    AnaliseLicenciamentoTecnicaResultadoRN       ← consulta com resultados
    AnaliseLicenciamentoTecnicaConsultaRN        ← listagens e analistas disponíveis
    AnaliseLicenciamentoTecnicaDocumentoRN       ← geração de PDFs
    AnaliseLicenciamentoTecnicaRN                ← CRUD base
    ResultadoAnaliseTecnicaSalvarRN              ← salvar resultado por item
    ResultadoAnaliseTecnicaExclusaoRN            ← excluir resultado por item
    AnaliseLicenciamentoTecnicaCancelamentoAdmRN ← cancelamento administrativo
          |
    [RNVal - Validações]
    AnaliseLicenciamentoTecnicaRNVal
    AnaliseLicenciamentoTecnicaDistribuicaoRNVal
    AnaliseLicenciamentoTecnicaCARNVal
    AnaliseLicenciamentoTecnicaCIARNVal
    AnaliseLicenciamentoTecnicaDocumentoRNVal
          |
          v
[BD - Hibernate Criteria]
    AnaliseLicenciamentoTecnicaBD
          |
          v
[ED - @Entity @Audited]
    AnaliseLicenciamentoTecnicaED
    ResultadoAtecED (abstrata) + subclasses (11 tipos)
    JustificativaNcsED
    JustificativaAtecOutraMedidaSegurancaED
    ArquivoED
```

---

## 3. Modelo de Dados

### 3.1 Entidade principal — `AnaliseLicenciamentoTecnicaED`

Anotações: `@Entity`, `@Audited`, `@Table(name = "CBM_ANALISE_LIC_TECNICA")`

Implementa: `LicenciamentoCiencia`, `Status`

| Campo Java | Coluna BD | Tipo JPA | Restrições | Descrição |
|---|---|---|---|---|
| `id` | `ID` | `@Id @GeneratedValue` | NOT NULL PK | Identificador sequencial |
| `licenciamento` | `ID_LICENCIAMENTO` | `@ManyToOne` | NOT NULL | Referência ao `LicenciamentoED` |
| `numeroAnalise` | `NUMERO_ANALISE` | `@Column` | NOT NULL | Número ordinal da análise (1, 2, 3…) por licenciamento |
| `status` | `STATUS` | `@Enumerated(STRING)` | NOT NULL | `StatusAnaliseLicenciamentoTecnica` |
| `idUsuarioSoe` | `ID_USUARIO_SOE` | `@Column` | NOT NULL | ID do analista no SOE PROCERGS |
| `nomeUsuarioSoe` | `NOME_USUARIO_SOE` | `@Column(length=64)` | NOT NULL | Nome do analista (snapshot do SOE) |
| `dthStatus` | `DTH_STATUS` | `@Column` | NOT NULL | Timestamp da última mudança de status |
| `outraInconformidade` | `OUTRA_INCONFORMIDADE` | `@Column(length=4000)` | NULL | Texto livre de inconformidade não enquadrada em item |
| `justificativaAntecipacao` | `JUSTIFICATIVA_ANTECIPACAO` | `@Column(length=4000)` | NULL | Justificativa de antecipação da análise |
| `arquivo` | `ID_ARQUIVO` | `@ManyToOne` | NULL | Referência ao `ArquivoED` do documento gerado (CIA ou CA) |
| `ciencia` | `CIENCIA` | `@Convert(SimNaoBooleanConverter)` | NOT NULL DEFAULT 'N' | Se o responsável tomou ciência do resultado |
| `dthCiencia` | `DTH_CIENCIA` | `@Column` | NULL | Timestamp da ciência |
| `usuarioCiencia` | `ID_USUARIO_CIENCIA` | `@ManyToOne` | NULL | Usuário que tomou ciência |
| `idUsuarioSoeHomolog` | `ID_USUARIO_SOE_HOMOLOG` | `@Column` | NULL | ID do coordenador homologador no SOE |
| `nomeUsuarioSoeHomolog` | `NOME_USUARIO_SOE_HOMOLOG` | `@Column(length=64)` | NULL | Nome do homologador |
| `dthHomolog` | `DTH_HOMOLOG` | `@Column` | NULL | Timestamp da homologação |
| `indeferimentoHomolog` | `INDEFERIMENTO_HOMOLOG` | `@Column(length=4000)` | NULL | Justificativa de indeferimento da homologação |

**Coleções de resultados** (`@OneToMany(mappedBy="analiseLicenciamentoTecnica", fetch=LAZY)`):

| Campo Java | Entidade filha | Tipo de item analisado |
|---|---|---|
| `resultadosRTED` | `ResultadoAtecRTED` | Responsável Técnico |
| `resultadosRUED` | `ResultadoAtecRUED` | Responsável pelo Uso |
| `resultadosProprietarioED` | `ResultadoAtecProprietarioED` | Proprietário |
| `resultadosIsolamentoRiscoED` | `ResultadoAtecIsolamentoRiscoED` | Isolamento de risco |
| `resultadosTipoEdificacaoED` | `ResultadoAtecTipoEdificacaoED` | Tipo de edificação |
| `resultadosOcupacaoED` | `ResultadoAtecOcupacaoED` | Ocupação (CNAE) |
| `resultadosMedidaSegurancaED` | `ResultadoAtecMedidaSegurancaED` | Medidas de segurança |
| `resultadosGeralED` | `ResultadoAtecGeralED` | Itens gerais do PPCI |
| `resultadosElementoGraficoED` | `ResultadoAtecElementoGraficoED` | Elementos gráficos |
| `resultadosRiscoED` | `ResultadoAtecRiscoED` | Riscos específicos |
| `justificativaAtecOutraMedidaSegurancaED` | `JustificativaAtecOutraMedidaSegurancaED` | Outras medidas (texto livre) |

**Auditoria:** tabela `CBM_ANALISE_LIC_TECNICA_AUD` (Hibernate Envers).

---

### 3.2 Entidade abstrata — `ResultadoAtecED`

Anotação: `@MappedSuperclass`

Base para todas as 10 entidades de resultado. Campos herdados por todas as subclasses:

| Campo Java | Coluna BD | Tipo JPA | Restrições | Descrição |
|---|---|---|---|---|
| `id` | `ID` | `@Id @GeneratedValue` | NOT NULL PK | Identificador sequencial |
| `analiseLicenciamentoTecnica` | `ID_ANALISE_TECNICA` | `@ManyToOne` | NOT NULL | FK para `AnaliseLicenciamentoTecnicaED` |
| `status` | `STATUS` | `@Enumerated(STRING)` | NOT NULL | `StatusResultadoAtec` (`APROVADO` / `REPROVADO`) |

Cada subclasse concreta é anotada com `@Entity @Audited @Table(name = "CBM_RESULTADO_ATEC_XXX")` e adiciona campos específicos do domínio do item.

---

### 3.3 Entidades de resultado por tipo de item

| Entidade | Tabela | `TipoItemAnaliseTecnica` |
|---|---|---|
| `ResultadoAtecRTED` | `CBM_RESULTADO_ATEC_RT` | `RT` |
| `ResultadoAtecRUED` | `CBM_RESULTADO_ATEC_RU` | `RU` |
| `ResultadoAtecProprietarioED` | `CBM_RESULTADO_ATEC_PROPRIETARIO` | `PROPRIETARIO` |
| `ResultadoAtecIsolamentoRiscoED` | `CBM_RESULTADO_ATEC_ISOL_RISCO` | `ISOLAMENTO_RISCO` |
| `ResultadoAtecTipoEdificacaoED` | `CBM_RESULTADO_ATEC_TIPO_EDIF` | `TIPO_EDIFICACAO` |
| `ResultadoAtecOcupacaoED` | `CBM_RESULTADO_ATEC_OCUPACAO` | `OCUPACAO` |
| `ResultadoAtecMedidaSegurancaED` | `CBM_RESULTADO_ATEC_MED_SEG` | `MEDIDA_SEGURANCA` |
| `ResultadoAtecGeralED` | `CBM_RESULTADO_ATEC_GERAL` | `GERAL` |
| `ResultadoAtecElementoGraficoED` | `CBM_RESULTADO_ATEC_ELEM_GRAF` | `ELEMENTO_GRAFICO` |
| `ResultadoAtecRiscoED` | `CBM_RESULTADO_ATEC_RISCO_ESP` | `RISCO_ESPECIFICO` |

Cada entidade de resultado possui ainda uma coleção `@OneToMany` de `JustificativaNcsED`, carregada apenas quando `status = REPROVADO`.

---

### 3.4 Entidade — `JustificativaAtecOutraMedidaSegurancaED`

Armazena justificativas para o item `MEDIDA_SEGURANCA_OUTRA` (texto livre, não enquadrado nas medidas padrão).

| Campo Java | Coluna BD | Tipo | Restrições |
|---|---|---|---|
| `id` | `ID` | `@Id @GeneratedValue` | NOT NULL PK |
| `analiseLicenciamentoTecnica` | `ID_ANALISE_TECNICA` | `@ManyToOne` | NOT NULL FK |
| `descricao` | `DESCRICAO` | `@Column(length=4000)` | NOT NULL |

---

### 3.5 Entidade — `ArquivoED`

Representa o documento PDF gerado (CIA, CA, APPCI). O binário **nunca vai para o banco relacional**.

| Campo Java | Coluna BD | Tipo | Restrições | Descrição |
|---|---|---|---|---|
| `id` | `ID` | `@Id @GeneratedValue` | NOT NULL PK | Identificador |
| `nomeArquivo` | `NOME_ARQUIVO` | `@Column` | NOT NULL | Nome lógico do arquivo (ex.: `cia_analise_tecnica.pdf`) |
| `identificadorAlfresco` | `IDENTIFICADOR_ALFRESCO` | `@Column(length=150)` | NOT NULL | nodeRef do Alfresco onde o binário está armazenado |
| `tipoArquivo` | `TIPO_ARQUIVO` | `@Enumerated(STRING)` | NOT NULL | `TipoArquivo` enum (ex.: `EDIFICACAO`) |
| `codigoAutenticacao` | `CODIGO_AUTENTICACAO` | `@Column` | NULL | Código de autenticidade do documento |

> **Regra de arquitetura:** o arquivo binário é armazenado exclusivamente no Alfresco via `ArquivoRN`. O campo `identificadorAlfresco` armazena o nodeRef retornado pelo Alfresco, que é usado posteriormente para download. A classe `ArquivoRN` expõe `incluirArquivo(BuilderArquivoED)` e `toInputStream(ArquivoED)`.

---

### 3.6 Relacionamentos resumidos

```
LicenciamentoED (1) ----< (N) AnaliseLicenciamentoTecnicaED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecRTED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecRUED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecProprietarioED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecIsolamentoRiscoED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecTipoEdificacaoED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecOcupacaoED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecMedidaSegurancaED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecGeralED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecRiscoED
AnaliseLicenciamentoTecnicaED (1) ----< (N) ResultadoAtecElementoGraficoED
AnaliseLicenciamentoTecnicaED (1) ----< (N) JustificativaAtecOutraMedidaSegurancaED
ResultadoAtecXxxED (1) ----< (N) JustificativaNcsED [apenas quando status=REPROVADO]
AnaliseLicenciamentoTecnicaED (N) ----> (1) ArquivoED [nullable — CIA ou CA]
```

---

## 4. Enumerações

### 4.1 `StatusAnaliseLicenciamentoTecnica`

Enum: `com.procergs.solcbm.enumeration.StatusAnaliseLicenciamentoTecnica`

| Valor | Descrição | Transições permitidas |
|---|---|---|
| `EM_ANALISE` | Análise em progresso pelo analista designado | → `EM_APROVACAO` (`salvarAnaliseCA`), → `REPROVADO` (`salvarAnaliseCIA`), → `CANCELADA` (`cancela`) |
| `EM_APROVACAO` | Aguardando homologação do coordenador | → `APROVADO` (`deferir`), → `EM_ANALISE` (`indeferir`) |
| `APROVADO` | Homologação deferida — CA/APPCI emitido | Estado terminal desta análise |
| `REPROVADO` | CIA emitida — aguardando ciência do RT | Estado terminal desta análise |
| `CANCELADA` | Cancelada administrativamente | Estado terminal — licenciamento volta a `AGUARDANDO_DISTRIBUICAO` |
| `EM_REDISTRIBUICAO` | Redistribuída a outro analista (reservado) | → `EM_ANALISE` |

### 4.2 `StatusResultadoAtec`

Enum: `com.procergs.solcbm.enumeration.StatusResultadoAtec`

| Valor | Descrição |
|---|---|
| `APROVADO` | Item analisado está em conformidade |
| `REPROVADO` | Item analisado possui inconformidade — exige ao menos uma `JustificativaNcs` |

### 4.3 `TipoItemAnaliseTecnica`

Enum: `com.procergs.solcbm.enumeration.TipoItemAnaliseTecnica`

| Valor | Descrição |
|---|---|
| `RT` | Responsável Técnico |
| `RU` | Responsável pelo Uso |
| `PROPRIETARIO` | Proprietário |
| `TIPO_EDIFICACAO` | Tipo de edificação |
| `OCUPACAO` | Ocupação predominante (CNAE) |
| `ISOLAMENTO_RISCO` | Isolamento de risco entre unidades/ocupações |
| `GERAL` | Itens gerais do PPCI |
| `MEDIDA_SEGURANCA` | Medidas de segurança previstas em norma CBM-RS |
| `MEDIDA_SEGURANCA_OUTRA` | Outras medidas de segurança (texto livre) |
| `RISCO_ESPECIFICO` | Riscos específicos da edificação |
| `ELEMENTO_GRAFICO` | Elementos gráficos do projeto (plantas, cortes, etc.) |

### 4.4 `TipoEdificacao` — impacto no P04

| Valor | Impacto |
|---|---|
| `A_CONSTRUIR` | Gera CA novo (`ca_nova_analise_tecnica.pdf`) via `DocumentoCaNovaAnaliseAutenticadoRN` |
| qualquer outro | Gera CA existente (`ca_existente_analise_tecnica.pdf`) via `DocumentoCaExistenteAnaliseAutenticadoRN` |

### 4.5 `SituacaoLicenciamento` — situações relevantes ao P04

| Valor | Contexto no P04 |
|---|---|
| `AGUARDANDO_DISTRIBUICAO` | Pré-condição de entrada — `validarSituacaoParaDistribuicao()` aceita este valor |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | Pré-condição alternativa (renovação) — também aceita em `validarSituacaoParaDistribuicao()` |
| `EM_ANALISE` | Estado do licenciamento durante a análise técnica |
| `AGUARDANDO_CIENCIA` | Pós-CIA — aguardando ciência do RT/RU |
| `CA` | Certificado de Aprovação emitido (PPCI) |
| `ALVARA_VIGENTE` | APPCI emitido e vigente (PSPCIM) |

### 4.6 `TipoMarco` — marcos gerados no P04

| Valor | Momento de geração | RN geradora |
|---|---|---|
| `DISTRIBUICAO_ANALISE` | Distribuição do licenciamento | `AnaliseLicenciamentoTecnicaDistribuicaoRN` |
| `ATEC_CA` | Analista envia para homologação (PPCI) | `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` |
| `ATEC_APPCI` | Analista envia para homologação (PSPCIM) | `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` |
| `ATEC_CIA` | Analista emite CIA | `AnaliseLicenciamentoTecnicaCIARN.salvarAnaliseCIA()` |
| `HOMOLOG_ATEC_DEFERIDO` | Coordenador defere (PPCI) | `AnaliseLicenciamentoTecnicaHomRN.deferir()` |
| `HOMOLOG_ATEC_APPCI` | Coordenador defere (PSPCIM) | `AnaliseLicenciamentoTecnicaHomRN.deferir()` |
| `EMISSAO_DOC_COMPLEMENTAR` | Documento complementar emitido (PSPCIM) | `AnaliseLicenciamentoTecnicaHomRN.deferir()` |
| `HOMOLOG_ATEC_INDEFERIDO` | Coordenador indefere | `AnaliseLicenciamentoTecnicaHomRN.indeferir()` |
| `CANCELA_DISTRIBUICAO_ANALISE` | Cancelamento administrativo | `AnaliseLicenciamentoTecnicaCancelamentoAdmRN.cancela()` |

---

## 5. Regras de Negócio por Etapa

### 5.1 Distribuição da Análise

**Classe:** `AnaliseLicenciamentoTecnicaDistribuicaoRN` (`@Stateless @AppInterceptor`)

**Método principal:** `incluir(List<AnaliseLicenciamentoTecnicaDTO> analises)`

**Permissão:** `@Permissao(objeto = "DISTRIBUICAOANALISE", acao = "DISTRIBUIR")`

**Fluxo de execução** (por item da lista):

```
analises.forEach(analise -> {
  1. consultaLicenciamentoValido(analise.getIdLicenciamento())
  2. consultaBatalhaoValido(analise.getIdUsuarioSoe())
  3. validaCidadeMesmoBatalhao(batalhaoUsuario, licenciamentoED.getLocalizacao())
  4. distribuirLicenciamento(analise, licenciamentoED)
  5. trocaEstadoLicAguardandoDistribuicaoParaEmAnaliseRN.trocaEstado(licenciamentoED.getId())
})
```

**Regras de validação** — classe `AnaliseLicenciamentoTecnicaDistribuicaoRNVal`:

| Código | Método | Regra |
|---|---|---|
| RN-P04-D01 | `validarSituacaoParaDistribuicao(SituacaoLicenciamento)` | A situação do licenciamento deve ser `AGUARDANDO_DISTRIBUICAO` ou `AGUARDANDO_DISTRIBUICAO_RENOV`. Caso contrário lança `WebApplicationRNException` com mensagem `licenciamento.distribuicao.status` e HTTP 406. |
| RN-P04-D02 | `validarBatalhao(Optional<Long> batalhaoUsuario)` | O analista designado deve ter um batalhão CBM-RS associado. Se `Optional` vazio, lança `WebApplicationRNException` com `analisetecnica.usuario.batalhao.naoencontrado` e HTTP 406. |
| RN-P04-D03 | `validarCidadeDoLicenciamento(CidadeED cidadeED)` | O batalhão do analista deve cobrir a cidade do licenciamento — verificado via `CidadeRN.consultaPorBatalhaoENroIBGE(batalhao, nroMunicipioIBGE)`. Se `CidadeED` nulo (cidade não encontrada no batalhão), lança `WebApplicationRNException` com `licenciamento.distribuicao.batalhao` e HTTP 406. |

**Regras de execução** — método `distribuirLicenciamento(...)`:

| Código | Regra |
|---|---|
| RN-P04-D04 | Consultar a última `AnaliseLicenciamentoTecnicaED` não cancelada via `analiseLicenciamentoTecnicaConsultaRN.consultaUltimaAnalisePorLicenciamento(licenciamentoED)`. Se existir, `numeroAnalise = ultimaAnalise.getNumeroAnalise() + 1`. Se não existir (primeira análise), `numeroAnalise = 1`. |
| RN-P04-D05 | Definir `analise.setStatus(StatusAnaliseLicenciamentoTecnica.EM_ANALISE)`. |
| RN-P04-D06 | Criar `AnaliseLicenciamentoTecnicaED` via `BuilderAnaliseLicenciamentoTecnicaED.of().toED(analise).ciencia(false).licenciamento(licenciamentoED).instance()` e persistir via `analiseLicenciamentoTecnicaRN.inclui(...)`. |
| RN-P04-D07 | Transitar o licenciamento de `AGUARDANDO_DISTRIBUICAO` para `EM_ANALISE` via `trocaEstadoLicAguardandoDistribuicaoParaEmAnaliseRN.trocaEstado(idLicenciamento)`. Qualificador: `@TrocaEstadoLicenciamentoQualifier(trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_DISTRIBUICAO_PARA_EM_ANALISE)`. |

**Consultas de apoio** — classe `AnaliseLicenciamentoTecnicaConsultaRN`:

| Método | Permissão | Descrição |
|---|---|---|
| `licenciamentosPendentesDeDistribuicao(LicenciamentoPesqED ped)` | `@Permissao("DISTRIBUICAOANALISE", "LISTAR")` | Lista paginada de `LicenciamentoDistribuicaoDTO` com situação `AGUARDANDO_DISTRIBUICAO`. Retorna: número PPCI, razão social, ocupação predominante, área construída, dias na fila, nome do último analista. Usa `BuilderLicenciamentoDistribuicaoDTO`. |
| `listaAnalistasBatalhaoUsuarioLogado()` | `@Permissao("DISTRIBUICAOANALISE", "LISTAR")` | Lista `AnalistaDisponivelDTO` dos analistas do batalhão do coordenador logado. Consulta batalhão via `UsuarioSoeRN.getNumeroBatalhaoUsuarioLogado()`. Para cada analista: total de licenciamentos em análise, área em m² por tipo. Ordenado por `areaEmAnalise ASC`. |
| `listaLicenciamentosEmAnalisePorUsuario(AnaliseLicenciamentoTecnicaPesqED ped)` | `@Permissao("DISTRIBUICAOANALISE", "CONSULTAR")` | Lista até 20 licenciamentos em `EM_ANALISE` de um analista específico. |

**DTO de entrada:** `AnaliseLicenciamentoTecnicaDTO` com campos:
- `idLicenciamento` (Long)
- `idUsuarioSoe` (Long) — ID do analista no SOE
- `nomeUsuarioSoe` (String) — nome do analista (snapshot)

**DTO de resposta — `AnalistaDisponivelDTO`:**
- `usuarioSoe` (UsuarioSoeDTO): dados do analista
- `areaEmAnalise` (Double): soma das áreas construídas dos licenciamentos em análise
- `totalLicenciamentosEmAnalise` (Integer)
- `totaisTipoLicenciamento` (List\<TotalTipoLicenciamento\>): breakdown por `TipoLicenciamento`

---

### 5.2 Registro de Resultados por Item

**Classe principal:** `ResultadoAnaliseTecnicaSalvarRN` (`@Stateless @AppInterceptor`)

**Método salvar resultado:** `salvarResultado(ResultadoAtecDTO resultadoAtecDTO)`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

**Fluxo de execução:**

```java
public Long salvarResultado(ResultadoAtecDTO resultadoAtecDTO) {
  ResultadoAnaliseTecnicaStrategy strategy =
      resultadoAnaliseTecnicaStrategyResolver.getStrategy(resultadoAtecDTO.getTipoItemAnaliseTecnica());

  // RN-P04-R01: valida que item pertence ao licenciamento da análise do usuário logado
  analiseLicenciamentoTecnicaRN.validaIsAnaliseAssociadaUsuarioItem(resultadoAtecDTO, strategy.getSubqueryLicenciamento());

  // RN-P04-R02: validação específica da strategy
  strategy.validar(resultadoAtecDTO);

  // RN-P04-R03: justificativa obrigatória para REPROVADO
  if (StatusResultadoAtec.REPROVADO.equals(resultadoAtecDTO.getStatusResultadoAtec())) {
    justificativaNcsRNVal.validarJustificativaReprovacao(resultadoAtecDTO.getJustificativas());
  }

  ResultadoAtecED resultadoED = strategy.consulta(resultadoAtecDTO);
  if (resultadoED != null) {
    resultadoAtecDTO.setId(resultadoED.getId());
    return altera(resultadoAtecDTO, strategy); // exclui justif. anteriores e inclui novas
  }
  return inclui(resultadoAtecDTO, strategy); // inclui resultado e justificativas
}
```

**Regras de validação:**

| Código | Origem | Regra |
|---|---|---|
| RN-P04-R01 | `AnaliseLicenciamentoTecnicaRN.validaIsAnaliseAssociadaUsuarioItem(...)` | O `idAnaliseTecnica` do DTO deve pertencer a um licenciamento cujo item analisado (`idItemAnalisado`) corresponde ao tipo informado, e o `idUsuarioSoe` deve ser o do usuário logado (`sessionMB.getUser().getId()`), e o status da análise deve ser `EM_ANALISE`. Caso falhe, HTTP 406. |
| RN-P04-R02 | `strategy.validar(resultadoAtecDTO)` | Cada strategy implementa validação própria do tipo de item. |
| RN-P04-R03 | `JustificativaNcsRNVal.validarJustificativaReprovacao(List<JustificativaNcs>)` | Se `statusResultadoAtec = REPROVADO`, a lista `justificativas` não pode ser nula nem vazia. |

**Regra de upsert (RN-P04-R04):**
- Se `strategy.consulta(resultadoAtecDTO)` retorna não-nulo: **alterar** — excluir justificativas antigas (`strategy.excluirJustificativas(id)`) e incluir novas
- Se retorna nulo: **incluir** novo resultado com as justificativas

**Regra de justificativas (RN-P04-R05):**
- Justificativas só são incluídas quando `StatusResultadoAtec.REPROVADO` e lista não vazia. Itens aprovados não possuem justificativas.

**DTO de entrada — `ResultadoAtecDTO`:**

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do resultado (preenchido internamente no caso de alteração) |
| `idAnaliseTecnica` | Long | ID da `AnaliseLicenciamentoTecnicaED` |
| `idItemAnalisado` | Long | ID do item específico sendo analisado |
| `tipoItemAnaliseTecnica` | `TipoItemAnaliseTecnica` | Tipo do item |
| `statusResultadoAtec` | `StatusResultadoAtec` | `APROVADO` ou `REPROVADO` |
| `justificativas` | `List<JustificativaNcs>` | Lista de justificativas (obrigatório quando REPROVADO) |

---

**Método salvar outra inconformidade:**

`AnaliseLicenciamentoTecnicaRN.salvarInconformidade(Long idAnaliseTecnica, String inconformidade)`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

| Código | Regra |
|---|---|
| RN-P04-R06 | Consulta `AnaliseLicenciamentoTecnicaED` pelo ID. |
| RN-P04-R07 | Valida via `analiseLicenciamentoTecnicaRNVal.validarAnaliseDoUsuarioLogado(ed.getIdUsuarioSoe())` que o analista logado é o dono da análise (HTTP 403 se não for). |
| RN-P04-R08 | Atualiza `ed.setOutraInconformidade(inconformidade)` e persiste via `altera(ed)`. |

---

**Método salvar outras medidas de segurança:**

`ResultadoAnaliseTecnicaSalvarRN.salvarResultadoOutrasMedidas(ResultadoAtecDTO resultadoAtecDTO)`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

| Código | Regra |
|---|---|
| RN-P04-R09 | Consulta `AnaliseLicenciamentoTecnicaED` e valida que o analista logado é o dono. |
| RN-P04-R10 | Valida que `status = EM_ANALISE` via `analiseLicenciamentoTecnicaRNVal.validarSituacaoEmAnalise(ed.getStatus())`. HTTP 406 se não estiver. |
| RN-P04-R11 | Exclui todas as `JustificativaAtecOutraMedidaSegurancaED` anteriores via `justificativaAtecOutraMedidaSegurancaRN.exclui(resultadoAtecDTO)`. |
| RN-P04-R12 | Inclui as novas via `justificativaAtecOutraMedidaSegurancaRN.inclui(resultadoAtecDTO)`. |

---

**Método excluir resultado individual:**

`ResultadoAnaliseTecnicaExclusaoRN.excluir(ResultadoAtecDTO resultadoAtecDTO)`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

| Código | Regra |
|---|---|
| RN-P04-R13 | Valida que a análise pertence ao usuário logado. |
| RN-P04-R14 | Valida que a análise está em `EM_ANALISE`. |
| RN-P04-R15 | Exclui justificativas do resultado via `strategy.excluirJustificativas(id)`. |
| RN-P04-R16 | Exclui o `ResultadoAtecED` via `strategy.excluir(resultadoAtecDTO)`. |

**Método excluir outras medidas:**

`ResultadoAnaliseTecnicaExclusaoRN.excluirOutrasMedidas(ResultadoAtecDTO resultadoAtecDTO)`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

Valida analista logado e status `EM_ANALISE`; exclui todas as `JustificativaAtecOutraMedidaSegurancaED` da análise.

---

### 5.3 Emissão de CIA (Reprovação)

**Classe:** `AnaliseLicenciamentoTecnicaCIARN` (`@Stateless @AppInterceptor`)

**Método principal:** `salvarAnaliseCIA(Long idAnaliseTecnica): Long`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

**Fluxo de execução:**

```java
public Long salvarAnaliseCIA(Long idAnaliseTecnica) {
  AnaliseLicenciamentoTecnicaED analiseTecnicaEd = analiseLicenciamentoTecnicaRN.consulta(idAnaliseTecnica);
  getAnaliseLicenciamentoTecnicaCIARNVal().validarInclusaoCIA(analiseTecnicaEd);  // validações
  atualizarReprovacaoAnalise(analiseTecnicaEd);                                    // status + gera CIA PDF
  resultadoAnaliseTecnicaExclusaoRN.excluirResultados(analiseTecnicaEd);          // limpa resultados
  atualizarLicenciamentoCIA(analiseTecnicaEd);                                    // marco + troca estado
  analiseTecnicaEd.getResultadosElementoGraficoED()
      .forEach(elementoGraficoHistoricoRN::incluiHistoricoElementoGrafico);       // histórico gráfico
  desbloquearLicenciamentoParaRecurso(analiseTecnicaEd.getLicenciamento());       // libera recurso
  return analiseTecnicaEd.getId();
}
```

**Regras de validação** — `AnaliseLicenciamentoTecnicaCIARNVal.validarInclusaoCIA(ed)`:

| Código | Regra |
|---|---|
| RN-P04-CIA01 | `analiseLicenciamentoTecnicaRNVal.validarAnaliseDoUsuarioLogado(ed.getIdUsuarioSoe())` — analista logado deve ser o dono da análise. HTTP 403 se não for. |
| RN-P04-CIA02 | Para cada `TipoItemAnaliseTecnica` em `TipoItemAnaliseTecnica.values()`: `strategy.validaQuantidadeItensAnalisados(analiseED)`. Todos os tipos de item obrigatórios devem ter pelo menos um resultado registrado. |
| RN-P04-CIA03 | Se `StringUtils.isBlank(ed.getOutraInconformidade())`: verifica via `strategy.possuiItensReprovado(analiseED)` se há algum item REPROVADO em qualquer tipo. Se nenhum item está reprovado e o campo livre também está vazio, lança `WebApplicationRNException` com `analisetecnica.status.naoreprovada` (HTTP 406). |

**Regras de execução:**

| Código | Método | Regra |
|---|---|---|
| RN-P04-CIA04 | `atualizarReprovacaoAnalise(ed)` | Define `ed.setStatus(StatusAnaliseLicenciamentoTecnica.REPROVADO)`. |
| RN-P04-CIA05 | `atualizarReprovacaoAnalise(ed)` | Define `ed.setDthStatus(dataAtualHelper.getDataAtual())`. |
| RN-P04-CIA06 | `atualizarReprovacaoAnalise(ed)` | Gera CIA PDF autenticado via `analiseLicenciamentoTecnicaDocumentoRN.incluirDocumentoCIA(ed)` e vincula ao campo `ed.setArquivo(arquivoED)`. Ver seção 7. |
| RN-P04-CIA07 | `atualizarReprovacaoAnalise(ed)` | Persiste as alterações da análise via `analiseLicenciamentoTecnicaRN.altera(ed)`. |
| RN-P04-CIA08 | `resultadoAnaliseTecnicaExclusaoRN.excluirResultados(ed)` | Remove todos os `ResultadoAtecED` de todos os tipos — os resultados são registros temporários; o CIA é o documento permanente. |
| RN-P04-CIA09 | `atualizarLicenciamentoCIA(ed)` | Registra marco `TipoMarco.ATEC_CIA` no licenciamento, vinculado ao arquivo CIA via `licenciamentoMarcoAdmRN.incluiComArquivo(ATEC_CIA, licenciamento, arquivo)`. |
| RN-P04-CIA10 | `atualizarLicenciamentoCIA(ed)` | Transita licenciamento de `EM_ANALISE` para `AGUARDANDO_CIENCIA` via `trocaEstadoLicenciamentoEmAnaliseParaAguardandoCienciaRN.trocaEstado(idLicenciamento)`. Qualificador: `TrocaEstadoLicenciamentoEnum.EM_ANALISE_PARA_AGUARDANDO_CIENCIA`. |
| RN-P04-CIA11 | `desbloquearLicenciamentoParaRecurso(licenciamento)` | Define `licenciamento.setRecursoBloqueado(false)` e persiste via `licenciamentoRN.altera(licenciamento)`. Libera ao RT a possibilidade de interpor recurso após ciência. |
| RN-P04-CIA12 | `elementoGraficoHistoricoRN.incluiHistoricoElementoGrafico(...)` | Para cada `ResultadoAtecElementoGraficoED` da análise: registra histórico do elemento gráfico (rastreia versões do projeto gráfico analisadas). |

---

### 5.4 Emissão de CA — Envio para Homologação

**Classe:** `AnaliseLicenciamentoTecnicaCARN` (`@Stateless @AppInterceptor`)

**Método principal:** `salvarAnaliseCA(Long idAnaliseTecnica): Long`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "ANALISAR")`

**Fluxo de execução:**

```java
public Long salvarAnaliseCA(Long idAnaliseTecnica) {
  AnaliseLicenciamentoTecnicaED analiseTecnicaED = analiseLicenciamentoTecnicaRN.consulta(idAnaliseTecnica);
  getAnaliseLicenciamentoTecnicaCARNVal().validarAnaliseCA(analiseTecnicaED); // validações
  incluirNotaEMarcoLicenciamento(analiseTecnicaED);                          // nota + marco
  analiseTecnicaED.setStatus(StatusAnaliseLicenciamentoTecnica.EM_APROVACAO);
  analiseTecnicaED.setDthStatus(dataAtualHelper.getDataAtual());
  analiseTecnicaED.setOutraInconformidade(null);                             // limpa campo livre
  AnaliseLicenciamentoTecnicaED saved = analiseLicenciamentoTecnicaRN.altera(analiseTecnicaED);
  saved.getResultadosElementoGraficoED()
       .forEach(elementoGraficoHistoricoRN::incluiHistoricoElementoGrafico);
  return saved.getId();
}
```

> **Atenção:** o CA definitivo (PDF autenticado) **não é gerado nesta etapa**. Ele é gerado apenas na homologação (`AnaliseLicenciamentoTecnicaHomRN.deferir()`). Neste passo, o analista apenas coloca a análise em `EM_APROVACAO`.

**Regras de validação** — `AnaliseLicenciamentoTecnicaCARNVal.validarAnaliseCA(ed)`:

| Código | Origem | Regra |
|---|---|---|
| RN-P04-CA01 | `analiseLicenciamentoTecnicaRNVal.validarAnaliseDoUsuarioLogado(ed.getIdUsuarioSoe())` | Analista logado deve ser o dono da análise. HTTP 403. |
| RN-P04-CA02 | `analiseLicenciamentoTecnicaRNVal.validarContemInconformidades(ed)` | O campo `outraInconformidade` deve estar em branco (`StringUtils.isBlank`). Se preenchido, lança `WebApplicationRNException` com `analisetecnica.status.inconformidades` (HTTP 406). |
| RN-P04-CA03 | `validarItensPreenchidos(analiseED)` | Para cada `TipoItemAnaliseTecnica`: `strategy.validaQuantidadeItensAnalisados(analiseED)`. Todos os tipos obrigatórios devem ter resultado registrado. |
| RN-P04-CA04 | `validarItensAprovados(analiseED)` | Para cada `TipoItemAnaliseTecnica`: `strategy.validaItensAprovados(analiseED)`. Não deve haver nenhum item `REPROVADO`. |

**Regras de execução** — `incluirNotaEMarcoLicenciamento(ed)`:

| Código | Regra |
|---|---|
| RN-P04-CA05 | Conclui a nota de trabalho do licenciamento via `notaRN.concluirNota(licenciamento.getId())`. |
| RN-P04-CA06 | Se `TipoLicenciamento.PPCI`: registra marco `TipoMarco.ATEC_CA` via `licenciamentoMarcoAdmRN.inclui(ATEC_CA, licenciamento)`. |
| RN-P04-CA07 | Se `TipoLicenciamento.PSPCIM`: registra marco `TipoMarco.ATEC_APPCI` via `licenciamentoMarcoAdmRN.inclui(ATEC_APPCI, licenciamento)`. |
| RN-P04-CA08 | Registra histórico dos elementos gráficos (idem RN-P04-CIA12). |

**Download de rascunho CA (sem persistência):**

`AnaliseLicenciamentoTecnicaDocumentoRN.downloadRascunhoCA(Long idAnaliseTecnica): InputStream`

Retorna PDF de rascunho sem código de autenticação. Controle de acesso via `analiseLicenciamentoTecnicaDocumentoRNVal.validaPermissoes()` (aceita `ANALISAR` ou `HOMOLOGAR`).

---

### 5.5 Homologação pelo Coordenador

**Classe:** `AnaliseLicenciamentoTecnicaHomRN` (`@Stateless @AppInterceptor`)

#### 5.5.1 Consulta de análises pendentes de homologação

**Método:** `listaAnalisePendentesHomologacao(AnaliseLicenciamentoTecnicaPesqED ped): ListaPaginadaRetorno<LicenciamentoAnaliseTecnica>`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "HOMOLOGAR")`

| Regra | Descrição |
|---|---|
| RN-P04-H00a | Filtra análises com `status = EM_APROVACAO`. |
| RN-P04-H00b | Filtra pelas cidades IBGE do batalhão do coordenador logado via `licenciamentoAdmRN.getCidadesIBGEUsuarioLogado()`. |
| RN-P04-H00c | Ordenação sem prioridade (`setOrdernarPorPrioridade(false)`). |

**Consulta análise com resultados:**

`consultaComResultados(AnaliseLicenciamentoTecnicaED ed): AnaliseLicenciamentoTecnicaDTO`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "HOMOLOGAR")`

Delega para `analiseLicenciamentoTecnicaResultadoRN.efetuaConsultaComResultados(ed)` que retorna o DTO completo com:
- Todos os resultados por tipo de item
- Nome do analista anterior (se `numeroAnalise > 1`)
- ID do arquivo CIA anterior (se havia `status = REPROVADO` na análise anterior)
- ID da última inviabilidade (se houve análise de inviabilidade)
- `indeferimentoHomolog`: justificativa de indeferimento anterior

#### 5.5.2 Deferir homologação

**Método:** `deferir(Long idAnaliseTecnica): Long`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "HOMOLOGAR")`

**Fluxo de execução:**

```java
public Long deferir(Long idAnaliseTecnica) {
  ArquivoED arquivoED = null;
  ArquivoED arquivoDocComplementarED = null;
  AnaliseLicenciamentoTecnicaED analise = consulta(idAnaliseTecnica);
  LicenciamentoED licenciamento = analise.getLicenciamento();

  // Atualiza análise
  analise.setStatus(StatusAnaliseLicenciamentoTecnica.APROVADO);
  analise.setIndeferimentoHomolog(null);
  analise.setDthHomolog(dataAtualHelper.getDataAtual());

  // Gera documentos conforme tipo de licenciamento
  if (licenciamento.getTipo() == TipoLicenciamento.PPCI) {
    arquivoED = analiseLicenciamentoTecnicaDocumentoRN.incluirDocumentoCA(licenciamento);
  } else if (licenciamento.getTipo() == TipoLicenciamento.PSPCIM) {
    arquivoED = analiseLicenciamentoTecnicaDocumentoRN.incluirDocumentoAPPCI(analise);
    arquivoDocComplementarED = analiseLicenciamentoTecnicaDocumentoRN.incluirDocumentoComplementarAnalise(analise);
  }

  analise.setArquivo(arquivoED);
  alterarAnaliseHomologada(analise); // preenche dados do homologador e persiste
  getResultadoAnaliseTecnicaExclusaoRN().excluirResultados(analise); // remove resultados

  // Marcos e transição de estado
  if (licenciamento.getTipo() == TipoLicenciamento.PPCI) {
    licenciamentoMarcoAdmRN.incluiComArquivo(TipoMarco.HOMOLOG_ATEC_DEFERIDO, licenciamento, arquivoED);
    trocaEstadoLicenciamentoEmAnaliseParaCARN.trocaEstado(licenciamento.getId()); // → CA
  } else if (licenciamento.getTipo() == TipoLicenciamento.PSPCIM) {
    licenciamentoMarcoAdmRN.incluiComArquivo(TipoMarco.HOMOLOG_ATEC_APPCI, licenciamento, arquivoED);
    licenciamentoMarcoInclusaoRN.incluiComArquivo(TipoMarco.EMISSAO_DOC_COMPLEMENTAR, licenciamento, arquivoDocComplementarED);
    trocaEstadoLicenciamentoEmAnaliseParaAlvaraVigente.trocaEstado(licenciamento.getId()); // → ALVARA_VIGENTE
  }

  licenciamentoAdmRN.ativarRecurso(licenciamento);

  if (analise.getLicenciamento().getSituacao().equals(SituacaoLicenciamento.CA)) {
    integracaoLAI.cadastrarDemandaUnicaAnalise(analise.getLicenciamento());
  }

  return analise.getId();
}
```

**Regras de execução detalhadas:**

| Código | Regra |
|---|---|
| RN-P04-H01 | `analise.setStatus(APROVADO)`, `setIndeferimentoHomolog(null)`, `setDthHomolog(now())`. |
| RN-P04-H02 | `alterarAnaliseHomologada(analise)` — preenche `nomeUsuarioSoeHomolog` e `idUsuarioSoeHomolog` via `sessionMB.getUser()`, e persiste via `altera(analise)`. |
| RN-P04-H03 | **PPCI:** `incluirDocumentoCA(licenciamento)` verifica `TipoEdificacao`: se `A_CONSTRUIR` → `DocumentoCaNovaAnaliseAutenticadoRN.gerar(idLicenciamento, codigoAutenticacao)` → arquivo `ca_nova_analise_tecnica.pdf`; caso contrário → `DocumentoCaExistenteAnaliseAutenticadoRN.gerar(...)` → arquivo `ca_existente_analise_tecnica.pdf`. |
| RN-P04-H04 | **PSPCIM:** `incluirDocumentoAPPCI(analise)` — gera APPCI via `DocumentoAnaliseAPPCIAutenticadoRN.gerar(idAnalise, codigoAutenticacao)` → arquivo `appci_analise_tecnica.pdf`. Calcula validade via `CalculoValidadeAppciRN.getPrazoValidadeEmAnos(idLicenciamento)`. Cria entidade `AppciED` via `FactoryAppci.criar(licenciamento, validade, arquivo, AppciED.class)`, define `appciED.setCiencia(false)` e persiste via `appciRN.inclui(appciED)`. |
| RN-P04-H05 | **PSPCIM:** `incluirDocumentoComplementarAnalise(analise)` — gera documento complementar via `DocumentoComplementarAutenticadoRN.gera(licenciamento, codigoAutenticacao)` → arquivo `DocComplementar.pdf`. Cria `AppciDocComplementarED` via `FactoryAppci.criar(...)` e persiste via `appciDocComplementarRN.inclui(...)`. |
| RN-P04-H06 | Armazenar ambos os arquivos gerados via `ArquivoRN.incluirArquivo(BuilderArquivoED...)` — nodeRef retornado pelo Alfresco é salvo em `ArquivoED.identificadorAlfresco`. |
| RN-P04-H07 | Excluir todos os resultados via `ResultadoAnaliseTecnicaExclusaoRN.excluirResultados(analise)`. |
| RN-P04-H08 | **PPCI:** marco `HOMOLOG_ATEC_DEFERIDO` + transição para `CA` (`TrocaEstadoLicenciamentoEnum.EM_ANALISE_PARA_CA`). |
| RN-P04-H09 | **PSPCIM:** marco `HOMOLOG_ATEC_APPCI` + marco `EMISSAO_DOC_COMPLEMENTAR` + transição para `ALVARA_VIGENTE` (`TrocaEstadoLicenciamentoEnum.EM_ANALISE_PARA_ALVARA_VIGENTE`). |
| RN-P04-H10 | `licenciamentoAdmRN.ativarRecurso(licenciamento)` — habilita interposição de recurso. |
| RN-P04-H11 | Se `licenciamento.getSituacao() == SituacaoLicenciamento.CA` após a transição: `integracaoLAI.cadastrarDemandaUnicaAnalise(licenciamento)` — cadastra demanda no sistema LAI (Lei de Acesso à Informação). |

#### 5.5.3 Indeferir homologação

**Método:** `indeferir(Long idAnaliseTecnica, String justificativa): Long`

**Permissão:** `@Permissao(objeto = "ANALISETECNICA", acao = "HOMOLOGAR")`

**Fluxo de execução:**

```java
public Long indeferir(Long idAnaliseTecnica, String justificativa) {
  AnaliseLicenciamentoTecnicaED analise = consulta(idAnaliseTecnica);
  LicenciamentoED licenciamento = analise.getLicenciamento();

  analise.setStatus(StatusAnaliseLicenciamentoTecnica.EM_ANALISE); // volta ao analista
  analise.setIndeferimentoHomolog(justificativa);
  analise.setDthHomolog(dataAtualHelper.getDataAtual());
  analise.setDthStatus(dataAtualHelper.getDataAtual());

  alterarAnaliseHomologada(analise);

  licenciamentoMarcoAdmRN.inclui(TipoMarco.HOMOLOG_ATEC_INDEFERIDO, licenciamento);
  notaRN.concluirNota(licenciamento.getId());
  return analise.getId();
}
```

| Código | Regra |
|---|---|
| RN-P04-H12 | `status = EM_ANALISE` — a análise retorna ao analista designado. O licenciamento permanece em `EM_ANALISE` (não há mudança de situação). |
| RN-P04-H13 | `indeferimentoHomolog = justificativa` — preenchido e visível ao analista na consulta da análise. |
| RN-P04-H14 | Registra marco `HOMOLOG_ATEC_INDEFERIDO`. |
| RN-P04-H15 | Conclui nota via `notaRN.concluirNota(licenciamento.getId())`. |

---

### 5.6 Cancelamento Administrativo

**Classe:** `AnaliseLicenciamentoTecnicaCancelamentoAdmRN` (`@Stateless @AppInterceptor`)

**Método principal:** `cancela(Long idAnaliseTecnica): Long`

**Permissão:** `@Permissao(objeto = "DISTRIBUICAOANALISE", acao = "CANCELAR")`

**Fluxo de execução:**

```java
public Long cancela(Long idAnaliseTecnica) {
  AnaliseLicenciamentoTecnicaED ed = analiseLicenciamentoTecnicaRN.consulta(idAnaliseTecnica);
  // RN-P04-C01: valida cidade/batalhão
  Long nroMunicipio = ed.getLicenciamento().getLocalizacao().getNroMunicipioIBGE();
  // [validação via CidadeRN]

  ed.setStatus(StatusAnaliseLicenciamentoTecnica.CANCELADA);
  ed.setDthStatus(dataAtualHelper.getDataAtual());
  analiseLicenciamentoTecnicaRN.altera(ed);
  resultadoAnaliseTecnicaExclusaoRN.excluirResultados(ed);
  notaRN.concluirNota(ed.getLicenciamento().getId());
  trocaEstadoEmAnaliseParaAguardandoDistribuicaoRN.trocaEstado(ed.getLicenciamento().getId());
  return ed.getId();
}
```

| Código | Regra |
|---|---|
| RN-P04-C01 | Valida que o coordenador logado tem competência sobre a cidade do licenciamento (mesmo batalhão). |
| RN-P04-C02 | Define `status = CANCELADA`, `dthStatus = now()` e persiste. |
| RN-P04-C03 | Exclui todos os resultados registrados via `ResultadoAnaliseTecnicaExclusaoRN.excluirResultados(ed)`. |
| RN-P04-C04 | Conclui nota de trabalho via `notaRN.concluirNota(idLicenciamento)`. |
| RN-P04-C05 | Transita licenciamento de `EM_ANALISE` para `AGUARDANDO_DISTRIBUICAO` via qualificador `TrocaEstadoLicenciamentoEnum.EM_ANALISE_PARA_AGUARDANDO_DISTRIBUICAO`. |

---

## 6. Padrão Strategy de Resultados

### 6.1 Interface `ResultadoAnaliseTecnicaStrategy`

Todas as 11 implementations seguem esta interface (implícita — não necessariamente declarada explicitamente em Java 8, mas deve ser extraída para a nova versão):

```java
public interface ResultadoAnaliseTecnicaStrategy {
    TipoItemAnaliseTecnica getTipoItem();

    // Subquery HQL que retorna o ID do licenciamento pelo ID do item analisado
    // Usado para validar vínculo analise ↔ item ↔ licenciamento
    String getSubqueryLicenciamento();

    // Validação específica do tipo de item
    void validar(ResultadoAtecDTO dto);

    // Consulta resultado existente para (idAnaliseTecnica, idItemAnalisado)
    ResultadoAtecED consulta(ResultadoAtecDTO dto);

    // Inclui novo ResultadoAtecED
    ResultadoAtecED incluir(ResultadoAtecDTO dto);

    // Edita ResultadoAtecED existente
    ResultadoAtecED editar(ResultadoAtecDTO dto);

    // Inclui justificativas de NCS vinculadas ao resultado
    void incluirJustificativas(List<JustificativaNcs> justificativas, ResultadoAtecED resultado);

    // Exclui justificativas vinculadas ao resultado
    void excluirJustificativas(Long idResultado);

    // Exclui o ResultadoAtecED (e suas justificativas)
    void excluir(ResultadoAtecDTO dto);

    // Valida quantidade mínima de itens analisados (para CA e CIA)
    void validaQuantidadeItensAnalisados(AnaliseLicenciamentoTecnicaED analise);

    // Valida que todos os itens do tipo estão APROVADOS (para CA)
    void validaItensAprovados(AnaliseLicenciamentoTecnicaED analise);

    // Verifica se existe ao menos um item REPROVADO (para CIA)
    boolean possuiItensReprovado(AnaliseLicenciamentoTecnicaED analise);

    // Lista inconformidades para compor documento CIA
    List<InconformidadeDTO> listaInconformidades(AnaliseLicenciamentoTecnicaED analise);

    // Popula resultados no DTO de consulta
    void popularResultados(AnaliseLicenciamentoTecnicaED analise, AnaliseLicenciamentoTecnicaDTO dto);
}
```

### 6.2 `ResultadoAnaliseTecnicaStrategyResolver`

Componente CDI que centraliza a resolução da strategy por tipo:

```java
// Injetado nos RNs via @Inject
@Inject
protected ResultadoAnaliseTecnicaStrategyResolver resultadoAnaliseTecnicaStrategyResolver;

// Uso
ResultadoAnaliseTecnicaStrategy strategy =
    resultadoAnaliseTecnicaStrategyResolver.getStrategy(tipoItemAnaliseTecnica);
```

### 6.3 Implementações concretas

| Classe | Tipo | Qualificador CDI |
|---|---|---|
| `ResultadoAnaliseTecnicaRTStrategy` | `RT` | `@ResultadoAnaliseTecnicaQualifier(tipo=RT)` |
| `ResultadoAnaliseTecnicaRUStrategy` | `RU` | `@ResultadoAnaliseTecnicaQualifier(tipo=RU)` |
| `ResultadoAnaliseTecnicaProprietarioStrategy` | `PROPRIETARIO` | idem |
| `ResultadoAnaliseTecnicaTipoEdificacaoStrategy` | `TIPO_EDIFICACAO` | idem |
| `ResultadoAnaliseTecnicaOcupacaoStrategy` | `OCUPACAO` | idem |
| `ResultadoAnaliseTecnicaIsolamentoRiscoStrategy` | `ISOLAMENTO_RISCO` | idem |
| `ResultadoAnaliseTecnicaGeralStrategy` | `GERAL` | idem |
| `ResultadoAnaliseTecnicaMedidaSegurancaStrategy` | `MEDIDA_SEGURANCA` | idem |
| `ResultadoAnaliseTecnicaMedSegurancaOutraStrategy` | `MEDIDA_SEGURANCA_OUTRA` | idem |
| `ResultadoAnaliseTecnicaRiscoEspecificoStrategy` | `RISCO_ESPECIFICO` | idem |
| `ResultadoAnaliseTecnicaElementoGraficoStrategy` | `ELEMENTO_GRAFICO` | idem |

Qualificador: `@ResultadoAnaliseTecnicaQualifier` (anotação customizada localizada em `resultado/annotation/`).

### 6.4 Ordenação das inconformidades no CIA

A ordenação das inconformidades no documento CIA é definida pela constante:

```java
// AnaliseLicenciamentoTecnicaDocumentoRN
private static final List<TipoItemAnaliseTecnica> TIPO_ITENS_ORDENADOS = Arrays.asList(
    RT, RU, PROPRIETARIO, TIPO_EDIFICACAO, OCUPACAO, ISOLAMENTO_RISCO, GERAL,
    MEDIDA_SEGURANCA, MEDIDA_SEGURANCA_OUTRA, RISCO_ESPECIFICO, ELEMENTO_GRAFICO
);
```

Dentro de cada tipo, as inconformidades são ordenadas por `InconformidadeDTOComparator` (por `nomeItemAnalise` ASC e `ordemExibicao` ASC).

Se `outraInconformidade` não for nulo, é adicionada ao final com categoria "Demais inconformidades":

```java
if (StringUtils.isNotEmpty(analise.getOutraInconformidade())) {
    inconformidades.add(BuilderInconformidadeDTO.of()
        .tipoItemAnalise("Demais inconformidades")
        .justificativa(analise.getOutraInconformidade())
        .instance());
}
```

---

## 7. Geração de Documentos PDF

Toda geração de PDF segue o padrão:
1. `ArquivoRN.gerarNumeroAutenticacao()` — gera código único de autenticidade
2. `DocumentoXxxRN.gerar(...)` — produz `InputStream` com o PDF
3. `ArquivoRN.incluirArquivo(BuilderArquivoED.of()...)` — faz upload no Alfresco, cria `ArquivoED` com `identificadorAlfresco` = nodeRef

### 7.1 Documentos do P04

| Documento | Arquivo lógico | Classe de geração | Momento |
|---|---|---|---|
| Rascunho CIA | (em memória) | `DocumentoCiaAnaliseRascunhoRN` | `GET /rascunho-cia` |
| CIA definitivo | `cia_analise_tecnica.pdf` | `DocumentoCiaAnaliseAutenticadoRN` | `salvarAnaliseCIA()` |
| Rascunho CA (nova) | (em memória) | `DocumentoCaNovaAnaliseRascunhoRN` | `GET /rascunho-ca` |
| Rascunho CA (existente) | (em memória) | `DocumentoCaExistenteAnaliseRascunhoRN` | `GET /rascunho-ca` |
| CA novo | `ca_nova_analise_tecnica.pdf` | `DocumentoCaNovaAnaliseAutenticadoRN` | `deferir()` se PPCI + A_CONSTRUIR |
| CA existente | `ca_existente_analise_tecnica.pdf` | `DocumentoCaExistenteAnaliseAutenticadoRN` | `deferir()` se PPCI + outro |
| APPCI | `appci_analise_tecnica.pdf` | `DocumentoAnaliseAPPCIAutenticadoRN` | `deferir()` se PSPCIM |
| Documento complementar | `DocComplementar.pdf` | `DocumentoComplementarAutenticadoRN` | `deferir()` se PSPCIM |
| Rascunho APPCI PSPCIM | (em memória) | `DocumentoAnaliseAPPCIRascunhoRN` | `GET /rascunho-appci-pspcim` |

### 7.2 Lógica de seleção do CA

```java
// AnaliseLicenciamentoTecnicaDocumentoRN.incluirDocumentoCA(LicenciamentoED licenciamento)
if (TipoEdificacao.A_CONSTRUIR.equals(licenciamento.getCaracteristica().getEdificacao())) {
    return incluirCANovo(licenciamento.getId());
}
return incluirCAExistente(licenciamento.getId());
```

Qualificador CDI para injeção das implementações:
```java
@Inject
@DocumentoCaQualifier(tipoDocumentoCa = TipoDocumentoCa.NOVO)
private DocumentoCaRascunhoRN documentoCaNovaAnaliseRascunhoRN;

@Inject
@DocumentoCaQualifier(tipoDocumentoCa = TipoDocumentoCa.EXISTENTE)
private DocumentoCaExistenteAnaliseRascunhoRN documentoCaExistenteAnaliseRascunhoRN;
```

### 7.3 Criação do APPCI (PSPCIM)

```java
// AnaliseLicenciamentoTecnicaDocumentoRN.incluirAPPCINovo(Long idAnalise)
Integer validade = calculoValidadeAppciRN.getPrazoValidadeEmAnos(licenciamento.getId());
AppciED appciED = FactoryAppci.criar(licenciamento, validade, arquivoED, AppciED.class);
appciED.setCiencia(false);
appciRN.inclui(appciED);
```

### 7.4 Criação do Documento Complementar (PSPCIM)

```java
// AnaliseLicenciamentoTecnicaDocumentoRN.incluirDocComplementar(Long idAnalise)
Integer validade = calculoValidadeAppciRN.getPrazoValidadeEmAnos(licenciamento.getId());
ArquivoED arquivoED = arquivoRN.incluirArquivo(...);
appciDocComplementarRN.inclui(FactoryAppci.criar(licenciamento, validade, arquivoED, AppciDocComplementarED.class));
```

### 7.5 Constante de nomes de arquivo

```java
// AnaliseLicenciamentoTecnicaDocumentoRN
public static final String CIA                         = "cia_analise_tecnica.pdf";
private static final String CA_EXISTENTE               = "ca_existente_analise_tecnica.pdf";
public static final String CA_NOVA                     = "ca_nova_analise_tecnica.pdf";
public static final String APPCI                       = "appci_analise_tecnica.pdf";
public static final String NOME_DOCUMENTO_COMPLEMENTAR = "DocComplementar.pdf";
```

---

## 8. API REST (JAX-RS)

Todos os endpoints estão sob o path base `/adm` (administração interna CBM-RS) e exigem autenticação SOE.

### 8.1 Endpoints de Distribuição

**Classe REST:** `AnaliseLicenciamentoTecnicaDistribuicaoRest` (path base: `/adm/distribuicao-analise`)

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `GET` | `/adm/distribuicao-analise/pendentes?paginaAtual=0&tamanho=20` | Lista licenciamentos em `AGUARDANDO_DISTRIBUICAO` | `AnaliseLicenciamentoTecnicaConsultaRN.licenciamentosPendentesDeDistribuicao()` | `DISTRIBUICAOANALISE:LISTAR` |
| `GET` | `/adm/distribuicao-analise/analistas` | Lista analistas disponíveis do batalhão | `AnaliseLicenciamentoTecnicaConsultaRN.listaAnalistasBatalhaoUsuarioLogado()` | `DISTRIBUICAOANALISE:LISTAR` |
| `GET` | `/adm/distribuicao-analise/analistas-fact` | Lista analistas FACT do batalhão | `AnaliseLicenciamentoTecnicaConsultaRN.listaAnalistasAnaliseFactBatalhaoUsuarioLogado()` | `DISTRIBUICAOANALISE:LISTAR` |
| `GET` | `/adm/distribuicao-analise/analistas-recurso` | Lista analistas para recurso | `AnaliseLicenciamentoTecnicaConsultaRN.listaAnalistasRecursoBatalhaoUsuarioLogado()` | `DISTRIBUICAOANALISE:LISTAR` |
| `GET` | `/adm/distribuicao-analise/analistas-por-usuario/{idUsuario}` | Lista análises de um analista | `AnaliseLicenciamentoTecnicaConsultaRN.listaLicenciamentosEmAnalisePorUsuario()` | `DISTRIBUICAOANALISE:CONSULTAR` |
| `POST` | `/adm/distribuicao-analise` | Distribui licenciamentos para analistas | `AnaliseLicenciamentoTecnicaDistribuicaoRN.incluir()` | `DISTRIBUICAOANALISE:DISTRIBUIR` |

### 8.2 Endpoints de Análise (Analista)

**Classe REST:** `AnaliseLicenciamentoTecnicaConsultaRest` (path base: `/adm/analise-tecnica`)

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `GET` | `/adm/analise-tecnica/pendentes?paginaAtual=0&tamanho=20` | Lista análises em `EM_ANALISE` do analista logado | `AnaliseLicenciamentoTecnicaConsultaRN.listarAnalisesPorUsuarioLogado()` | `ANALISETECNICA:LISTAR` |
| `GET` | `/adm/analise-tecnica/{id}` | Consulta análise completa com resultados | `AnaliseLicenciamentoTecnicaResultadoRN.consultaComResultados()` | `ANALISETECNICA:ANALISAR` |

**Classe REST:** `AnaliseLicenciamentoTecnicaConclusaoRest` (path base: `/adm/analise-tecnica`)

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/deferir` | Envia para homologação (CA) | `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` | `ANALISETECNICA:ANALISAR` |
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/indeferir` | Emite CIA (reprovação) | `AnaliseLicenciamentoTecnicaCIARN.salvarAnaliseCIA()` | `ANALISETECNICA:ANALISAR` |

### 8.3 Endpoints de Documentos

**Classe REST:** `AnaliseLicenciamentoTecnicaDocumentoRest` (path base: `/adm/analise-tecnica`)

| Método | Path | Operação | RN | Content-Type |
|---|---|---|---|---|
| `GET` | `/adm/analise-tecnica/{idAnaliseTecnica}/rascunho-cia` | Download rascunho CIA PDF | `AnaliseLicenciamentoTecnicaDocumentoRN.downloadRascunhoCIA()` | `application/octet-stream` |
| `GET` | `/adm/analise-tecnica/{idAnaliseTecnica}/rascunho-ca` | Download rascunho CA PDF | `AnaliseLicenciamentoTecnicaDocumentoRN.downloadRascunhoCA()` | `application/octet-stream` |
| `GET` | `/adm/analise-tecnica/{idAnalise}/rascunho-appci-pspcim` | Download rascunho APPCI (PSPCIM) | `DocumentoAnaliseAPPCIRascunhoRN` | `application/octet-stream` |

### 8.4 Endpoints de Resultados por Item

**Classe REST:** (não identificada explicitamente, mas inferida dos RNs)

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/resultado` | Salva (inclui ou altera) resultado de um item | `ResultadoAnaliseTecnicaSalvarRN.salvarResultado()` | `ANALISETECNICA:ANALISAR` |
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/resultado/outras-medidas` | Salva outras medidas de segurança | `ResultadoAnaliseTecnicaSalvarRN.salvarResultadoOutrasMedidas()` | `ANALISETECNICA:ANALISAR` |
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/inconformidade` | Salva texto de outra inconformidade | `AnaliseLicenciamentoTecnicaRN.salvarInconformidade()` | `ANALISETECNICA:ANALISAR` |
| `DELETE` | `/adm/analise-tecnica/{idAnaliseTecnica}/resultado/{idResultado}` | Remove resultado individual | `ResultadoAnaliseTecnicaExclusaoRN.excluir()` | `ANALISETECNICA:ANALISAR` |
| `DELETE` | `/adm/analise-tecnica/{idAnaliseTecnica}/resultado/outras-medidas` | Remove outras medidas | `ResultadoAnaliseTecnicaExclusaoRN.excluirOutrasMedidas()` | `ANALISETECNICA:ANALISAR` |

### 8.5 Endpoints de Homologação (Coordenador)

**Classe REST:** `AnaliseLicenciamentoTecnicaHomRest` (path base: `/adm/analise-tecnica-hom`)

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `GET` | `/adm/analise-tecnica-hom/pendentes?paginaAtual=0&tamanho=20` | Lista análises em `EM_APROVACAO` | `AnaliseLicenciamentoTecnicaHomRN.listaAnalisePendentesHomologacao()` | `ANALISETECNICA:HOMOLOGAR` |
| `GET` | `/adm/analise-tecnica-hom/{id}` | Consulta análise completa para revisão | `AnaliseLicenciamentoTecnicaHomRN.consultaComResultados()` | `ANALISETECNICA:HOMOLOGAR` |
| `PUT` | `/adm/analise-tecnica-hom/{idAnaliseTecnica}/deferir` | Defere homologação — gera CA/APPCI | `AnaliseLicenciamentoTecnicaHomRN.deferir()` | `ANALISETECNICA:HOMOLOGAR` |
| `PUT` | `/adm/analise-tecnica-hom/{idAnaliseTecnica}/indeferir` | Indefere homologação (body: texto plano) | `AnaliseLicenciamentoTecnicaHomRN.indeferir()` | `ANALISETECNICA:HOMOLOGAR` |

### 8.6 Endpoints de Cancelamento

**Classe REST:** `AnaliseLicenciamentoTecnicaCancelamentoAdmRest`

| Método | Path | Operação | RN | Permissão |
|---|---|---|---|---|
| `PUT` | `/adm/analise-tecnica/{idAnaliseTecnica}/cancelar` | Cancela distribuição de análise | `AnaliseLicenciamentoTecnicaCancelamentoAdmRN.cancela()` | `DISTRIBUICAOANALISE:CANCELAR` |

### 8.7 Padrão de respostas

Todos os endpoints retornam `javax.ws.rs.core.Response`:

| Situação | HTTP | Body |
|---|---|---|
| Sucesso (escrita) | 200 OK | ID da análise (`Long`) ou lista de resultados |
| Sucesso (download) | 200 OK | `InputStream` com `Content-Type: application/octet-stream` |
| Erro de validação de negócio | 406 Not Acceptable | Mensagem do bundle de i18n |
| Não autorizado (analista errado) | 403 Forbidden | Mensagem do bundle |
| Não encontrado | 404 Not Found | Vazio |

---

## 9. Segurança e Controle de Acesso

### 9.1 Autenticação via SOE PROCERGS

A autenticação é realizada pelo Identity Provider SOE PROCERGS (meu.rs.gov.br) via OAuth2/OIDC (Implicit Flow). O frontend Angular usa `angular-oauth2-oidc`. O backend Java EE recebe o token e o valida via filtro de segurança WildFly integrado ao SOE.

O usuário logado é acessado em qualquer `@Stateless` EJB via:
```java
@Inject
private SessionMB sessionMB;

// Uso
String idUsuario = sessionMB.getUser().getId();
String nomeUsuario = sessionMB.getUser().getNome();
Long batalhao = sessionMB.getUser().getBatalhao(); // claim customizada
```

O batalhão do usuário é obtido via `UsuarioSoeRN`:
```java
Optional<Long> batalhao = usuarioSoeRN.getNumeroBatalhaoUsuario(idUsuarioSoe);
Optional<Long> batalhaoLogado = usuarioSoeRN.getNumeroBatalhaoUsuarioLogado();
```

### 9.2 Autorização via `@Permissao`

A anotação `@Permissao(objeto, acao)` é interceptada por `@AppInterceptor` e delega para o framework `arqjava4` de segurança PROCERGS. O framework verifica se o usuário autenticado possui a combinação `objeto:acao` em seu perfil SOE.

| `objeto` | `acao` | Perfil CBM-RS |
|---|---|---|
| `ANALISETECNICA` | `LISTAR` | Analista |
| `ANALISETECNICA` | `ANALISAR` | Analista |
| `ANALISETECNICA` | `HOMOLOGAR` | Coordenador |
| `DISTRIBUICAOANALISE` | `LISTAR` | Coordenador |
| `DISTRIBUICAOANALISE` | `CONSULTAR` | Coordenador |
| `DISTRIBUICAOANALISE` | `DISTRIBUIR` | Coordenador |
| `DISTRIBUICAOANALISE` | `CANCELAR` | Coordenador |
| `VISTORIA` | `VISTORIAR` | Vistoriador (uso em listagem de analistas de vistoria) |

**`@Permissao(desabilitada = true)`:** indica que o método não exige verificação de permissão (acesso interno sem controle SOE).

### 9.3 Validação de ownership (analista ↔ análise)

Implementado em `AnaliseLicenciamentoTecnicaRNVal.validarAnaliseDoUsuarioLogado(Long idUsuarioSoe)`:

```java
public void validarAnaliseDoUsuarioLogado(Long idUsuarioSoe) {
  if (!idUsuarioSoe.equals(Long.valueOf(sessionMB.getUser().getId()))) {
    throw new WebApplicationRNException(
        bundle.getMessage("analisetecnica.usuario.naoautorizado"),
        Response.Status.FORBIDDEN);
  }
}
```

Chamado em: `salvarResultado`, `salvarResultadoOutrasMedidas`, `salvarInconformidade`, `salvarAnaliseCA`, `salvarAnaliseCIA`, `excluir`, `excluirOutrasMedidas`.

### 9.4 Validação de competência territorial (coordenador)

Implementado via `CidadeRN.consultaPorBatalhaoENroIBGE(batalhao, nroMunicipioIBGE)`. O batalhão do coordenador é obtido via `UsuarioSoeRN`. Esta verificação garante que coordenadores só podem distribuir ou cancelar análises de licenciamentos cujas cidades pertencem ao seu batalhão.

---

## 10. Auditoria

### 10.1 Hibernate Envers

As entidades anotadas com `@Audited` geram tabelas `_AUD` automaticamente via Hibernate Envers:

| Entidade auditada | Tabela `_AUD` |
|---|---|
| `AnaliseLicenciamentoTecnicaED` | `CBM_ANALISE_LIC_TECNICA_AUD` |
| `ResultadoAtecRTED` | `CBM_RESULTADO_ATEC_RT_AUD` |
| `ResultadoAtecRUED` | `CBM_RESULTADO_ATEC_RU_AUD` |
| `ResultadoAtecProprietarioED` | `CBM_RESULTADO_ATEC_PROPRIETARIO_AUD` |
| demais `ResultadoAtecXxxED` | respectivas tabelas `_AUD` |
| `JustificativaAtecOutraMedidaSegurancaED` | respectiva `_AUD` |

Colunas padrão do Envers em cada tabela `_AUD`: `REV`, `REVTYPE`, `REVEND`.

### 10.2 Histórico de elementos gráficos

`ElementoGraficoHistoricoRN.incluiHistoricoElementoGrafico(ResultadoAtecElementoGraficoED)` é chamado em:
- `AnaliseLicenciamentoTecnicaCIARN.salvarAnaliseCIA()` — antes da exclusão dos resultados
- `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` — ao enviar para homologação

Permite rastrear quais versões do projeto gráfico (plantas, cortes) foram avaliadas em cada análise.

---

## 11. Notificações e Marcos

### 11.1 `LicenciamentoMarcoInclusaoRN`

Injetado com qualificador `@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.BOMBEIROS)`:

```java
@Inject
@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.BOMBEIROS)
private LicenciamentoMarcoInclusaoRN licenciamentoMarcoAdmRN;
```

Métodos utilizados:
- `inclui(TipoMarco tipoMarco, LicenciamentoED licenciamento)` — marco sem arquivo
- `incluiComArquivo(TipoMarco tipoMarco, LicenciamentoED licenciamento, ArquivoED arquivo)` — marco com arquivo vinculado

### 11.2 Tabela completa de marcos por etapa

| Etapa | Marco | Método | Tem arquivo? |
|---|---|---|---|
| Distribuição | `DISTRIBUICAO_ANALISE` | `AnaliseLicenciamentoTecnicaDistribuicaoRN.incluir()` | Não |
| Envio CA — PPCI | `ATEC_CA` | `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` | Não |
| Envio CA — PSPCIM | `ATEC_APPCI` | `AnaliseLicenciamentoTecnicaCARN.salvarAnaliseCA()` | Não |
| CIA | `ATEC_CIA` | `AnaliseLicenciamentoTecnicaCIARN.salvarAnaliseCIA()` | Sim (CIA PDF) |
| Homolog. deferida PPCI | `HOMOLOG_ATEC_DEFERIDO` | `AnaliseLicenciamentoTecnicaHomRN.deferir()` | Sim (CA PDF) |
| Homolog. deferida PSPCIM | `HOMOLOG_ATEC_APPCI` | `AnaliseLicenciamentoTecnicaHomRN.deferir()` | Sim (APPCI PDF) |
| Doc. complementar PSPCIM | `EMISSAO_DOC_COMPLEMENTAR` | `AnaliseLicenciamentoTecnicaHomRN.deferir()` | Sim (doc. compl. PDF) |
| Homolog. indeferida | `HOMOLOG_ATEC_INDEFERIDO` | `AnaliseLicenciamentoTecnicaHomRN.indeferir()` | Não |
| Cancelamento | `CANCELA_DISTRIBUICAO_ANALISE` | `AnaliseLicenciamentoTecnicaCancelamentoAdmRN.cancela()` | Não |

---

## 12. Tratamento de Erros

### 12.1 Exceção de domínio

**Classe:** `WebApplicationRNException`

Estende `RuntimeException` e carrega um `Response.Status` do JAX-RS. É capturada pelo `@Provider ExceptionMapper` do framework PROCERGS e convertida para a resposta HTTP adequada.

```java
// Lançamento típico
throw new WebApplicationRNException(
    bundle.getMessage("chave.da.mensagem"),
    Response.Status.NOT_ACCEPTABLE
);

// Sem mensagem (apenas status)
throw new WebApplicationRNException(Response.Status.NOT_ACCEPTABLE);
```

### 12.2 Internacionalização (i18n)

Mensagens de erro são recuperadas via:

```java
@Inject
private MessageProvider bundle;

bundle.getMessage("chave.da.mensagem"); // retorna String do bundle de i18n
```

### 12.3 Tabela de mensagens de erro do P04

| Chave | Situação | HTTP |
|---|---|---|
| `licenciamento.distribuicao.status` | Licenciamento não está em `AGUARDANDO_DISTRIBUICAO` ou `AGUARDANDO_DISTRIBUICAO_RENOV` | 406 |
| `licenciamento.distribuicao.batalhao` | Cidade do licenciamento não pertence ao batalhão do analista | 406 |
| `analisetecnica.usuario.batalhao.naoencontrado` | Analista não possui batalhão cadastrado no SOE | 406 |
| `analisetecnica.usuario.naoautorizado` | Analista logado não é o designado para a análise | 403 |
| `analisetecnica.status.inconformidades` | Tentativa de CA com `outraInconformidade` preenchida | 406 |
| `analisetecnica.status.naoreprovada` | Tentativa de CIA sem itens reprovados nem `outraInconformidade` | 406 |
| `analisetecnica.status.inconformidades` | Tentativa de CA com itens `REPROVADO` | 406 |
| `operador.sem.batalhao` | Coordenador logado não possui batalhão associado | 400 |

> **Nota:** a chave `analisetecnica.status.inconformidades` é usada tanto para "outraInconformidade preenchida" quanto para "itens reprovados no CA". As mensagens de validação de quantidade de itens analisados e de justificativa de NCS obrigatória são implementadas diretamente em cada strategy e em `JustificativaNcsRNVal`.

---

## Apêndice A — Diagrama de transições de estado

### `AnaliseLicenciamentoTecnicaED.status`

```
           [incluir — distribuirLicenciamento()]
                          |
                          v
              [ EM_ANALISE ] <------ (indeferir — HomRN)
              /                \
   [salvarAnaliseCIA()]       [salvarAnaliseCA()]
       |                           |
       v                           v
  [ REPROVADO ]           [ EM_APROVACAO ]
   (terminal)             /             \
                   [deferir()]      [indeferir()]
                       |
                       v
                  [ APROVADO ]
                   (terminal)

  [ EM_ANALISE ] --[cancela()]---> [ CANCELADA ] (terminal)
```

### `LicenciamentoED.situacao` no contexto P04

```
[AGUARDANDO_DISTRIBUICAO] ou [AGUARDANDO_DISTRIBUICAO_RENOV]
         |
         v  trocaEstado: AGUARDANDO_DISTRIBUICAO_PARA_EM_ANALISE
    [EM_ANALISE]
         |
         +---> CIA --> trocaEstado: EM_ANALISE_PARA_AGUARDANDO_CIENCIA
         |             [AGUARDANDO_CIENCIA] --> P05
         |
         +---> CA + deferir (PPCI) --> trocaEstado: EM_ANALISE_PARA_CA
         |                             [CA]
         |
         +---> CA + deferir (PSPCIM) --> trocaEstado: EM_ANALISE_PARA_ALVARA_VIGENTE
         |                              [ALVARA_VIGENTE]
         |
         +---> Cancelamento --> trocaEstado: EM_ANALISE_PARA_AGUARDANDO_DISTRIBUICAO
                                [AGUARDANDO_DISTRIBUICAO]
```

---

## Apêndice B — DTOs de Consulta

### `AnaliseLicenciamentoTecnicaDTO`

DTO principal de retorno de análise para o frontend:

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID da análise técnica |
| `idLicenciamento` | Long | ID do licenciamento |
| `idUsuarioSoe` | Long | ID do analista no SOE |
| `nomeUsuarioSoe` | String | Nome do analista |
| `numeroAnalise` | Integer | Número da análise (1, 2, 3…) |
| `status` | `StatusAnaliseLicenciamentoTecnica` | Estado atual da análise |
| `justificativaAntecipacao` | String | Justificativa de antecipação |
| `licenciamento` | `LicenciamentoDTO` | DTO completo do licenciamento |
| `nomeUltimoAnalista` | String | Nome do analista da análise anterior |
| `dataVencimento` | Date | Data de vencimento do prazo de análise |
| `inconformidade` | String | Texto de outra inconformidade |
| `indeferimentoHomolog` | String | Motivo de indeferimento (coordenador) |
| `idUltimaCia` | Long | ID do arquivo CIA da análise anterior |
| `idUltimaInviabilidade` | Long | ID do arquivo de inviabilidade anterior |

### `LicenciamentoAnaliseTecnica`

DTO para listagem paginada (estende `LicenciamentoAnaliseDTO`):

| Campo | Tipo | Descrição |
|---|---|---|
| `qtdEstabelecimentosPrincipais` | Long | Quantidade de estabelecimentos principais |
| `hora` | String | Horário da análise/vistoria |
| `numeroLicenciamento` | String | Número formatado do PPCI |
| `nomeAnalista` | String | Nome do analista |
| `indeferimentoHomolog` | String | Motivo de indeferimento |

### `AnalistaDisponivelDTO`

DTO para listagem de analistas disponíveis:

| Campo | Tipo | Descrição |
|---|---|---|
| `usuarioSoe` | `UsuarioSoeDTO` | Dados do analista (id, nome) |
| `areaEmAnalise` | Double | Soma em m² dos licenciamentos em análise |
| `totalLicenciamentosEmAnalise` | Integer | Total de licenciamentos em análise |
| `totaisTipoLicenciamento` | `List<TotalTipoLicenciamento>` | Breakdown por tipo de licenciamento |

Classe interna `TotalTipoLicenciamento`:
- `tipo`: `TipoLicenciamento`
- `total`: `long`

Ordenação da lista: por `areaEmAnalise ASC` (permite distribuição balanceada da carga).

### `LicenciamentoDistribuicaoDTO`

DTO para listagem de pendentes de distribuição:

| Campo (relevante) | Descrição |
|---|---|
| `razaoSocial` | Razão social do estabelecimento principal |
| `ocupacaoPredominante` | Ocupação CNAE que determina medidas de segurança |
| `qtdDiasAnalise` | Dias desde a entrada na fila |
| `nomeUltimoAnalista` | Analista da última análise (se houve análise anterior) |
| `numeroAnalise` | Número da última análise (0 se primeira vez) |
| `reserva` | Flag de licenciamento reserva |

---

## Apêndice C — Estrutura de pacotes atual (backend)

```
com.procergs.solcbm
└── analiselicenciamentotecnica
    ├── AnaliseLicenciamentoTecnicaBD.java
    ├── AnaliseLicenciamentoTecnicaCancelamentoAdmRN.java
    ├── AnaliseLicenciamentoTecnicaCARN.java
    ├── AnaliseLicenciamentoTecnicaCARNVal.java
    ├── AnaliseLicenciamentoTecnicaCIARN.java
    ├── AnaliseLicenciamentoTecnicaCIARNVal.java
    ├── AnaliseLicenciamentoTecnicaConsultaRN.java
    ├── AnaliseLicenciamentoTecnicaDistribuicaoRN.java
    ├── AnaliseLicenciamentoTecnicaDistribuicaoRNVal.java
    ├── AnaliseLicenciamentoTecnicaDocumentoRN.java
    ├── AnaliseLicenciamentoTecnicaDocumentoRNVal.java
    ├── AnaliseLicenciamentoTecnicaHomRN.java
    ├── AnaliseLicenciamentoTecnicaResultadoRN.java
    ├── AnaliseLicenciamentoTecnicaRN.java
    ├── AnaliseLicenciamentoTecnicaRNVal.java
    ├── InconformidadeDTOComparator.java
    ├── ResultadoAnaliseTecnicaExclusaoRN.java
    ├── ResultadoAnaliseTecnicaSalvarRN.java
    ├── documento/
    │   ├── DocumentoAPPCIAnaliseAutenticadoRN.java
    │   ├── DocumentoAPPCIAnaliseBaseRN.java
    │   ├── DocumentoAPPCIAnaliseRascunhoRN.java
    │   ├── DocumentoCaExistenteAnaliseAutenticadoRN.java
    │   ├── DocumentoCaExistenteAnaliseBaseRN.java
    │   ├── DocumentoCaExistenteAnaliseRascunhoRN.java
    │   ├── DocumentoCaNovaAnaliseAutenticadoRN.java
    │   ├── DocumentoCaNovaAnaliseBaseRN.java
    │   ├── DocumentoCaNovaAnaliseRascunhoRN.java
    │   ├── DocumentoCiaAnaliseAutenticadoRN.java
    │   ├── DocumentoCiaAnaliseBaseRN.java
    │   └── DocumentoCiaAnaliseRascunhoRN.java
    └── resultado/
        ├── annotation/
        │   ├── ResultadoAnaliseTecnicaQualifier.java
        │   └── ResultadoAnaliseTecnicaQualifierImpl.java
        ├── ResultadoAnaliseTecnicaElementoGraficoStrategy.java
        ├── ResultadoAnaliseTecnicaGeralStrategy.java
        ├── ResultadoAnaliseTecnicaIsolamentoRiscoStrategy.java
        ├── ResultadoAnaliseTecnicaMedidaSegurancaStrategy.java
        ├── ResultadoAnaliseTecnicaMedSegurancaOutraStrategy.java
        ├── ResultadoAnaliseTecnicaOcupacaoStrategy.java
        ├── ResultadoAnaliseTecnicaProprietarioStrategy.java
        ├── ResultadoAnaliseTecnicaRiscoEspecificoStrategy.java
        ├── ResultadoAnaliseTecnicaRTStrategy.java
        ├── ResultadoAnaliseTecnicaRUStrategy.java
        ├── ResultadoAnaliseTecnicaStrategy.java           ← interface
        ├── ResultadoAnaliseTecnicaStrategyResolver.java
        └── ResultadoAnaliseTecnicaTipoEdificacaoStrategy.java
```
