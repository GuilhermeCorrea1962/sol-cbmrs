# Requisitos — P03: Wizard de Nova Solicitação de Licenciamento (PPCI)
**Sistema:** SOL — Sistema Online de Licenciamento / CBM-RS
**Versão do documento:** 1.0
**Data:** 2026-03-06
**Destinatário:** Equipe de desenvolvimento Java
**Stack de referência:** Java EE — JAX-RS · CDI · EJB · JPA/Hibernate · Alfresco · WildFly
**Premissa:** Manutenção integral da arquitetura, padrões e tecnologias já em uso no sistema atual

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica e Padrões Arquiteturais](#2-stack-tecnológica-e-padrões-arquiteturais)
3. [Modelo de Dados (Entidades JPA)](#3-modelo-de-dados-entidades-jpa)
4. [Enumerações e Domínios](#4-enumerações-e-domínios)
5. [Camada de Regras de Negócio — Wizard (Etapas 1 a 7)](#5-camada-de-regras-de-negócio--wizard-etapas-1-a-7)
6. [Regras de Negócio Gerais (RN)](#6-regras-de-negócio-gerais-rn)
7. [Especificação da API REST (JAX-RS)](#7-especificação-da-api-rest-jax-rs)
8. [Segurança e Autorização](#8-segurança-e-autorização)
9. [Gestão de Arquivos (Alfresco)](#9-gestão-de-arquivos-alfresco)
10. [Notificações](#10-notificações)
11. [Auditoria e Histórico](#11-auditoria-e-histórico)
12. [Marcos do Licenciamento](#12-marcos-do-licenciamento)
13. [Requisitos Não Funcionais](#13-requisitos-não-funcionais)
14. [Glossário](#14-glossário)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P03 — **Wizard de Nova Solicitação de Licenciamento** — é o fluxo central do sistema SOL. Permite que o Responsável pelo Uso (RU) ou o Responsável Técnico (RT) inicie uma nova solicitação de licenciamento de segurança contra incêndio para um estabelecimento, percorrendo um formulário guiado de 7 etapas (wizard) com persistência parcial a cada passo.

O processo abrange desde a criação do rascunho até o encaminhamento da solicitação para a fila de análise técnica do CBM-RS, passando pela fase obrigatória de aceites formais de todos os envolvidos.

### 1.2 Atores

| Ator | Papel no P03 |
|---|---|
| **Cidadão (RU — Responsável pelo Uso)** | Inicia a solicitação, preenche dados do estabelecimento, aceita o termo de licenciamento |
| **RT — Responsável Técnico** | Profissional habilitado vinculado à solicitação; revisa e aceita formalmente antes do encaminhamento |
| **Proprietário** | Pessoa física ou jurídica proprietária do imóvel; pode ou não coincidir com o RU; também deve aceitar o termo |
| **Procurador** | Pessoa autorizada a agir em nome do RU ou Proprietário, mediante procuração formal |
| **Sistema (automático)** | Gera número do licenciamento, dispara notificações, cria marcos, encaminha para análise |
| **Analista CBM-RS** | Destinatário final após encaminhamento (atua nos processos P04 em diante) |

### 1.3 Fluxo Macro (BPMN P03)

```
[Início]
   |
   v
[Etapa 1] Tipo de Atividade / Enquadramento
   |
   v
[Etapa 2] Dados do Estabelecimento / Empresa
   |
   v
[Etapa 3] Vincular Responsável Técnico (RT)
   |
   v
[Etapa 4] Endereço / Localização
   |
   v
[Etapa 5] Dados da Edificação (Área, Pavimentos, Características)
   |
   v
[Etapa 6] Upload de Documentos Obrigatórios
   |
   v
[Etapa 7] Revisão, Aceite do Termo e Confirmação
   |
   v
[Sistema] Submissão — situa RASCUNHO → AGUARDANDO_ACEITE
   |
   v
[RT/RU/Proprietário] Aceite individual
   |
   +--[Algum Aceite]--→ AGUARDANDO_ACEITE (aguarda demais)
   |
   +--[Todos Aceitaram]
         |
         +--[Isenção Solicitada]--→ AGUARDANDO_PAGAMENTO
         |
         +--[Inviabilidade Técnica]--→ ANALISE_INVIABILIDADE_PENDENTE
         |
         +--[Padrão]-→ AGUARDANDO_DISTRIBUICAO
                            |
                            v
                    [EM_ANALISE — Processo P04+]
                            |
         +------------------+------------------+
         |                  |                  |
        [CA]              [NCA]              [CIA]
    APPCI emitido     Necessita vistoria   Inviabilidade
    (P11 — ciência)     (P07 — vistoria)   arquivada
```

### 1.4 Ciclo de Vida de Situações Envolvidas no P03

```
RASCUNHO
  └─ (cidadão confirma aceite do termo)
      └─ AGUARDANDO_ACEITE  (aguardando que todos os envolvidos aceitem)
          ├─ (isenção solicitada)
          │   └─ AGUARDANDO_PAGAMENTO
          ├─ (inviabilidade técnica)
          │   └─ ANALISE_INVIABILIDADE_PENDENTE
          └─ (padrão — todos aceitaram, sem pendências)
              └─ AGUARDANDO_DISTRIBUICAO
                  └─ EM_ANALISE  (saída do P03 → entrada P04)
```

---

## 2. Stack Tecnológica e Padrões Arquiteturais

### 2.1 Stack Java EE Atual

| Camada | Tecnologia / Especificação |
|---|---|
| **Servidor de aplicação** | WildFly / JBoss |
| **API REST** | JAX-RS (`@Path`, `@GET`, `@POST`, `@PUT`, `@DELETE`) |
| **Injeção de dependência** | CDI 1.2 (`@Inject`, `@ApplicationScoped`, `@RequestScoped`) |
| **Camada de negócio** | EJB Stateless (`@Stateless`, `@TransactionAttribute`) |
| **Persistência** | JPA 2.1 + Hibernate |
| **Transações** | JTA gerenciado pelo contêiner |
| **Auditoria** | Hibernate Envers (`@Audited`, `@AuditTable`) |
| **Validação** | Bean Validation / JSR-303 (`@NotNull`, `@Size`, etc.) |
| **Armazenamento de arquivos** | Alfresco (campo `identificadorAlfresco` em `ArquivoED`) |
| **Autenticação** | OAuth2/OIDC via SOE PROCERGS / `meu.rs.gov.br` |
| **Segurança de recurso** | Interceptores CDI: `SegurancaEnvolvidoInterceptor`, `@AutorizaEnvolvido`, `@Permissao` |
| **Serialização REST** | Jackson (JSON) |
| **Upload de arquivos** | JAX-RS Multipart (`multipart/form-data`) |
| **Paginação** | `ListaPaginadaRetorno<T>` customizado |

### 2.2 Padrão de Camadas

```
REST Resource          → @Path, JAX-RS
  └─ RN (Regra Negócio) → @Stateless EJB com @TransactionAttribute
      └─ BD (Banco Dados) → JPA/Hibernate queries, DetachedCriteria
          └─ ED (Entidade) → @Entity JPA com @Audited
              └─ DTO        → Objetos de transferência (sem anotações JPA)
```

### 2.3 Padrões de Nomenclatura (a manter)

| Sufixo | Significado | Exemplo |
|---|---|---|
| `ED` | Entity Data — entidade JPA | `LicenciamentoED` |
| `RN` | Regra de Negócio — EJB Stateless | `LicenciamentoCidadaoRN` |
| `BD` | Banco de Dados — acesso a dados | `LicenciamentoBD` |
| `DTO` | Data Transfer Object | `LicenciamentoDTO` |
| `RNVal` | Validações de regra de negócio | `LicenciamentoRNVal` |
| `Rest` | Resource JAX-RS | `LicenciamentoRest` |
| `Builder` | Builder pattern para entidades | `BuilderLicenciamentoED` |
| `Converter` | Converter JPA (AttributeConverter) | `SimNaoBooleanConverter` |

---

## 3. Modelo de Dados (Entidades JPA)

### 3.1 `LicenciamentoED` — Entidade Principal

**Tabela:** `CBM_LICENCIAMENTO`
**Auditoria:** `@Audited` + tabela `CBM_LICENCIAMENTO_AUD`
**Sequência:** `CBM_ID_LICENCIAMENTO_SEQ`

```java
@Entity
@Audited
@Table(name = "CBM_LICENCIAMENTO")
@AuditTable("CBM_LICENCIAMENTO_AUD")
public class LicenciamentoED extends AppED<Long> implements Serializable {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "CBM_ID_LICENCIAMENTO_SEQ")
    @SequenceGenerator(name = "CBM_ID_LICENCIAMENTO_SEQ",
                       sequenceName = "CBM_ID_LICENCIAMENTO_SEQ",
                       allocationSize = 1)
    @Column(name = "NRO_INT_LICENCIAMENTO")
    private Long id;

    // Código público do licenciamento — gerado na submissão
    // Formato: "[Tipo][Sequencial 8d] [Lote 2L] [Versão 3d]"
    // Exemplo: "A 00000361 AA 001"
    // Nulo enquanto RASCUNHO
    @Column(name = "COD_LICENCIAMENTO", unique = true)
    private String numero;

    @Enumerated(EnumType.STRING)
    @Column(name = "TP_LICENCIAMENTO", nullable = false)
    private TipoLicenciamento tipo;

    @Enumerated(EnumType.STRING)
    @Column(name = "TP_SITUACAO", nullable = false)
    private SituacaoLicenciamento situacao;

    @Enumerated(EnumType.STRING)
    @Column(name = "TP_FASE")
    private TipoFaseLicenciamento fase;

    // Passo atual do wizard (1–7). Persiste o progresso entre sessões.
    @Column(name = "NRO_PASSO")
    private Integer passo;

    // Prioridade de análise (gerenciada pelo CBM-RS)
    @Column(name = "NRO_PRIORIDADE")
    private Integer prioridade;

    // Data/hora em que a solicitação foi encaminhada para análise
    @Column(name = "DTH_ENCAMINHAMENTO_ANALISE")
    private Calendar dthEncaminhamentoAnalise;

    // Dias contados na análise anterior (para cálculo de prazos)
    @Column(name = "NRO_DIAS_ANALISE_ANTERIOR")
    private Long diasAnaliseAnterior;

    // Data/hora do ajuste de NCA (Não Conformidade Atendida)
    @Column(name = "DTH_AJUSTE_NCA")
    private Calendar dthAjusteNCA;

    // Indica se inviabilidade técnica foi aprovada pelo CBM-RS
    @Column(name = "IND_INVIABILIDADE_APROVADA")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean inviabilidadeAprovada;

    // Indica se há pedido de isenção de taxa
    @Column(name = "IND_ISENCAO")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean isencao;

    @Enumerated(EnumType.STRING)
    @Column(name = "TP_SITUACAO_ISENCAO")
    private TipoSituacaoIsencao situacaoIsencao;

    @Column(name = "DTH_SOLICITACAO_ISENCAO")
    private Calendar dthSolicitacaoIsencao;

    // Indica se o usuário pode ainda solicitar recurso administrativo
    @Column(name = "IND_RECURSO_BLOQUEADO")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean recursoBloqueado;

    // Indica se é uma reserva de licenciamento
    @Column(name = "IND_RESERVA")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean reserva;

    // --- Relacionamentos ---

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_CARACTERISTICA")
    @Audited
    private CaracteristicaED caracteristica;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LOCALIZACAO")
    @Audited
    private LocalizacaoED localizacao;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_ESPEC_SEGURANCA")
    @Audited
    private EspecificacaoSegurancaED especificacaoSeguranca;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    @Audited
    private Set<ResponsavelTecnicoED> responsaveisTecnicos;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    @Audited
    private Set<ResponsavelUsoED> responsaveisUso;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    @Audited
    private Set<LicenciamentoProprietarioED> licenciamentoProprietarios;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<EstabelecimentoED> estabelecimentos;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    @Audited
    private Set<EspecificacaoRiscoED> especificacoesRisco;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<ElementoGraficoED> elementosGraficos;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<BoletoLicenciamentoED> boletoLicenciamentos;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<AppciED> appcis;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<VistoriaED> vistorias;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    @OrderBy("ctrDthInc ASC")
    private List<LicenciamentoMarcoED> marcos;

    @OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
    private Set<PeriodoSolicitacaoED> periodoSolicitacoes;
}
```

---

### 3.2 `ResponsavelTecnicoED`

**Tabela:** `CBM_RESPONSAVEL_TECNICO`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_RESPONSAVEL_TECNICO_SEQ`
**Interface:** `EnvolvidoED`

Campos relevantes para P03:

| Campo (Java) | Coluna BD | Tipo | Descrição |
|---|---|---|---|
| `id` | `NRO_INT_RT` | Long | Chave primária |
| `licenciamento` | `NRO_INT_LICENCIAMENTO` | FK | Licenciamento ao qual o RT pertence |
| `usuario` | FK para `UsuarioED` | ManyToOne | Usuário do sistema (não auditado) |
| `aceite` | — | Boolean | Aceite do termo de análise (`SimNaoBooleanConverter`) |
| `aceiteVistoria` | — | Boolean | Aceite do termo de vistoria |
| `aceiteAnexoD` | — | Boolean | Aceite do Anexo D (laudo técnico de execução) |
| `dthAceiteAnexoD` | — | Calendar | Timestamp do aceite do Anexo D |
| `tipoResponsabilidadeTecnica` | — | Enum | `PROJETO`, `EXECUCAO`, `PROJETO_EXECUCAO`, `RENOVACAO_APPCI` |
| `arquivos` | tabela `CBM_RESPONSAVEL_ARQUIVO` | ManyToMany com `ArquivoED` | Documentos do RT (ART, RRT, etc.) |
| `consolidadoAnexoD` | — | Boolean | Indica se o Anexo D foi consolidado |
| `dthAceiteVistoria` | — | Calendar | Timestamp do aceite de vistoria |
| `aceiteExtincao` | — | Boolean | Aceite para extinção do licenciamento |
| `dthAceiteExtincao` | — | Calendar | Timestamp do aceite de extinção |
| `solicitanteExtincao` | — | Boolean | Indica se este RT solicitou a extinção |

---

### 3.3 `ResponsavelUsoED`

**Tabela:** `CBM_RESPONSAVEL_USO`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_RESPONSAVEL_USO_SEQ`
**Interface:** `EnvolvidoED`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `licenciamento` | FK `LicenciamentoED` | ManyToOne |
| `usuario` | FK `UsuarioED` | ManyToOne (não auditado) |
| `aceite` | Boolean | Aceite do termo de análise |
| `aceiteVistoria` | Boolean | Aceite do termo de vistoria |
| `procurador` | FK `ProcuradorED` | ManyToOne (opcional) — o procurador é quem assina em nome do RU |
| `dthAceiteVistoria` | Calendar | Timestamp do aceite de vistoria |

---

### 3.4 `LicenciamentoProprietarioED`

**Tabela:** `CBM_LICEN_PROPRI`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_LICEN_PROPRI_SEQ`
**Interface:** `EnvolvidoAceite`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `licenciamento` | FK `LicenciamentoED` | ManyToOne (não auditado) |
| `proprietario` | FK `ProprietarioED` | ManyToOne (não auditado) |
| `procurador` | FK `ProcuradorED` | ManyToOne (opcional) |
| `aceite` | Boolean | Aceite do termo (`SimNaoBooleanConverter`) — `getAceite()` usa `Optional.ofNullable().orElse(false)` |
| `aceiteVistoria` | Boolean | Aceite do termo de vistoria — mesmo padrão |
| `dthAceiteVistoria` | Calendar | Timestamp do aceite de vistoria |

---

### 3.5 `CaracteristicaED`

**Tabela:** `CBM_CARACTERISTICA`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_CARACTERISTICA_SEQ`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `edificacao` | `TipoEdificacao` (enum) | Tipo da edificação |
| `periodoConstrucao` | `TipoPeriodoConstrucao` (enum) | Período de construção |
| `regularizada` | Boolean | Indica regularização formal |
| `arquivo` | FK `ArquivoED` | ManyToOne — arquivo de planta geral |
| `areaConstruida` | Double | Área construída total (m²) |
| `areaProtegida` | Double | Área com proteção contra incêndio (m²) |
| `areaMaiorPopulacao` | Double | Área do pavimento com maior lotação (m²) |
| `areaSubsolo` | Double | Área de subsolo (m²) |
| `pavimAcimaSolo` | Long | Número de pavimentos acima do solo |
| `pavimAbaixoSolo` | Long | Número de pavimentos abaixo do solo (subsolo) |
| `alturaDescendente` | Double | Altura descendente em metros |
| `alturaAscendente` | Double | Altura ascendente em metros (do piso mais alto) |
| `populacaoTotal` | Long | Total de pessoas no estabelecimento |
| `nroPopulacaoPavimMaior` | Long | Pessoas no pavimento de maior lotação |
| `caracteristicaConstrutiva` | `TipoCaracteristicaConstrutiva` (enum) | Classificação construtiva |
| `depositoDescoberto` | `TipoDepositoDescoberto` (enum) | Tipo de depósito a descoberto |
| `unidadeArmazenadora` | `TipoUnidadeArmazenadora` (enum) | Tipo de unidade armazenadora |
| `instalacao` | `TipoInstalacao` (enum) | Tipo de instalação especial |
| `operacao` | `TipoOperacao` (enum) | Tipo de operação |
| `maiorTransformador` | `TipoMaiorTransformador` (enum) | Capacidade do maior transformador |
| `transformado` | `TipoTransformado` (enum) | Tipo de transformado |
| `capacidadeTransformado` | Long | Capacidade em kVA |
| `liquidoIsolante` | `TipoLiquidoIsolante` (enum) | Tipo de líquido isolante |
| `tempoResistenciaFogo` | Integer | Tempo de resistência ao fogo (minutos) |
| `possuiAfastamento` | Boolean | Possui afastamento lateral/frontal/fundos |
| `separacaoHorizontalAreas` | Boolean | Separação horizontal entre áreas |
| `separacaoVerticalAreas` | Boolean | Separação vertical entre áreas |
| `ocupacoes` | `List<OcupacaoED>` | OneToMany — ocupações associadas (não auditada) |

---

### 3.6 `LocalizacaoED`

**Tabela:** `CBM_LOCALIZACAO`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_LOCALIZACAO_SEQ`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `latitudeEndereco` | Double | Latitude do endereço informado |
| `longitudeEndereco` | Double | Longitude do endereço informado |
| `latitudeMapa` | Double | Latitude ajustada no mapa |
| `longitudeMapa` | Double | Longitude ajustada no mapa |
| `isolamentoRisco` | Boolean | Isolamento de risco (`SimNaoBooleanConverter`) |
| `arquivo` | FK `ArquivoED` | Comprovante de endereço (não auditado) |
| `endereco` | FK `EnderecoLicenciamentoED` | Endereço estruturado (não auditado) |
| `enderecoNovo` | FK `EnderecoLicenciamentoNovoED` | Endereço novo (não auditado) |
| `localidade` | String | Localidade/bairro |
| `cep` | String | CEP |
| `complemento` | String | Complemento do endereço |
| `bairro` | String | Bairro |
| `getNomeCidade()` | — | Método: retorna nome do município |
| `getCidade()` | — | Método: retorna objeto cidade |
| `getNroMunicipioIBGE()` | — | Método: retorna código IBGE |
| `getEndereco()` | — | Método: retorna endereço consolidado |

---

### 3.7 `ElementoGraficoED`

**Tabela:** `CBM_ELEMENTO_GRAFICO`
**Auditoria:** não auditada
**Sequência:** `CBM_ID_ELEM_GRAFICO_SEQ`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `licenciamento` | FK `LicenciamentoED` | ManyToOne |
| `arquivo` | FK `ArquivoED` | ManyToOne — arquivo do documento |
| `tipo` | `TipoElementoGrafico` (enum) | Tipo do elemento gráfico (`@Convert`) |
| `descricao` | String (max 120) | Descrição do documento |
| `situacao` | `TipoSituacao` (enum) | `ATIVO` ou `INATIVO` |
| `dataExclusao` | Calendar | Timestamp de exclusão lógica |
| `idUsuarioExclusao` | Long | ID do usuário que excluiu logicamente |
| `historicos` | `Set<ElementoGraficoHistoricoED>` | OneToMany (lazy) — histórico de versões |

---

### 3.8 `ArquivoED`

**Tabela:** `CBM_ARQUIVO`
**Auditoria:** `@Audited`
**Sequência:** `CBM_ID_ARQUIVO_SEQ`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `nomeArquivo` | String (max 120) | Nome original do arquivo |
| `identificadorAlfresco` | String (max 150, `@NotNull`) | **Chave de localização no repositório Alfresco** |
| `md5SGM` | String | Hash MD5 para verificação de integridade |
| `cache` | FK `ArquivoCacheED` | OneToOne (não auditado) — cache local |
| `tipoArquivo` | `TipoArquivo` (enum) | Tipo do arquivo |
| `codigoAutenticacao` | String | Código de autenticação do documento |
| `idMigracaoAlfresco` | String (max 1) | Indicador de migração |
| `dthMigracaoAlfresco` | Calendar | Timestamp da migração |
| `inputStream` | `InputStream` (`@Transient`) | Conteúdo binário — usado apenas em memória (upload/download) |

> **Regra crítica:** Todos os arquivos do sistema são armazenados no Alfresco. O campo `identificadorAlfresco` é o identificador do nó no Alfresco (`nodeRef`). O conteúdo binário nunca é armazenado no banco de dados relacional.

---

### 3.9 `TermoLicenciamentoED`

**Tabela:** `CBM_TERMO_LICENCIAMENTO`
**Sequência:** `CBM_ID_TERMO_LICENCIAMENTO_SEQ`

> Esta entidade armazena o **conteúdo dos termos** (templates) por tipo de envolvido e tipo de licenciamento. Não é um registro de aceite individual — é a fonte do texto que é exibido ao cidadão.

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `termo` | String (max 4000) | Texto do termo |
| `tpEnvolvido` | `TipoEnvolvido` (enum, max 15) | Tipo de envolvido ao qual o termo se aplica (`RT`, `RU`, `AMBOS`, `VISTORIA`, etc.) |
| `tpLicenciamento` | `TipoLicenciamento` (enum, max 40) | Tipo de licenciamento ao qual o termo se aplica |

---

### 3.10 `AppciED`

**Tabela:** `CBM_APPCI`
**Sequência:** `CBM_ID_APPCI_SEQ`
**Interfaces:** `Appci`, `LicenciamentoCiencia`

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `arquivo` | FK `ArquivoED` | ManyToOne — PDF do alvará |
| `localizacao` | FK `LocalizacaoED` | ManyToOne — localização do estabelecimento |
| `licenciamento` | FK `LicenciamentoED` | ManyToOne — licenciamento ao qual pertence |
| `versao` | Integer (`@NotNull`) | Número da versão do APPCI |
| `dataHoraEmissao` | Calendar (`@NotNull`) | Timestamp de emissão |
| `dataValidade` | Calendar (`@NotNull`) | Data de validade |
| `indVersaoVigente` | String (max 1, `@NotNull`) | `"S"` = versão vigente; `"N"` = histórica |
| `dataVigenciaInicio` | Calendar (`@NotNull`) | Início da vigência |
| `dataVigenciaFim` | Calendar | Fim da vigência |
| `dthCiencia` | Calendar | Timestamp em que o cidadão tomou ciência do APPCI |
| `usuarioCiencia` | FK `UsuarioED` | ManyToOne — usuário que tomou ciência |
| `ciencia` | Boolean | Indicador de ciência (`SimNaoBooleanConverter`) |
| `indRenovacao` | String (max 1) | Indicador de renovação |

---

### 3.11 `LicenciamentoMarcoED`

**Tabela:** `CBM_LICENCIAMENTO_MARCO`

Registra eventos importantes (marcos) no ciclo de vida de um licenciamento.

| Campo (Java) | Tipo | Descrição |
|---|---|---|
| `id` | Long | Chave primária |
| `licenciamento` | FK `LicenciamentoED` | ManyToOne |
| `tipo` | `TipoMarco` (enum) | Tipo do marco |
| `ctrDthInc` | Calendar | Timestamp de inclusão |
| `usuario` | FK `UsuarioED` | Usuário responsável |

**Marcos relevantes ao P03:**

| Enum `TipoMarco` | Momento de criação |
|---|---|
| `RASCUNHO_LICENCIAMENTO` | Imediatamente após criação do licenciamento |
| `ACEITE_ANALISE` | Quando cada envolvido aceita o termo |
| `FIM_ACEITES_ANALISE` | Quando **todos** os envolvidos aceitaram |
| `SOLICITACAO_ISENCAO` | Quando isencão é solicitada |

---

## 4. Enumerações e Domínios

### 4.1 `TipoLicenciamento`

```java
public enum TipoLicenciamento {
    CLCB,                 // Comunicação de Ligação Comercial de Baixo Risco
    PSPCIB,               // Plano de Segurança para Pequenas Edificações de Baixo Risco
    PSPCIM,               // Plano de Segurança para Pequenas e Médias Edificações
    PPCI,                 // Plano de Prevenção e Proteção Contra Incêndio
    EVENTO_TEMPORARIO,    // Licença para eventos temporários
    EVENTO_PIROTECNICO,   // Licença para eventos pirotécnicos
    CONSTRUCAO_PROVISORIA // Licença para construção provisória
}
```

> Para o P03, os tipos principais são **PPCI** e **PSPCIM**. Os demais têm fluxos próprios.
>
> Método `containsRenovacao(String descricao)`: filtra apenas `PPCI` (único tipo que possui renovação).

---

### 4.2 `SituacaoLicenciamento`

Estados completos do sistema (33 valores). Os estados relevantes ao P03 estão em **negrito**.

| Valor | Descrição |
|---|---|
| **`RASCUNHO`** | Rascunho — wizard em preenchimento |
| **`AGUARDANDO_ACEITE`** | Aguardando aceites de todos os envolvidos |
| **`AGUARDANDO_PAGAMENTO`** | Aguardando pagamento de taxa ou isenção aprovada |
| `EM_ANALISE` | Em análise técnica pelo CBM-RS |
| `NCA` | Aguardando correção de CIA (Comunicado de Inconformidade na Análise) |
| `EXTINGUIDO` | Licenciamento extinto |
| `ANALISE_ENDERECO_PENDENTE` | Homologação de endereço pendente |
| **`ANALISE_INVIABILIDADE_PENDENTE`** | Em análise de inviabilidade técnica |
| **`AGUARDANDO_DISTRIBUICAO`** | Aguardando distribuição para analista |
| `AGUARDANDO_ENDERECO` | Aguardando correção de endereço |
| `CA` | Certificado de Aprovação emitido |
| `AGUARDANDO_CIENCIA` | Aguardando ciência do CIA pelo cidadão |
| `AGUARDANDO_ACEITE_VISTORIA` | Aguardando aceites de vistoria |
| `AGUARDA_DISTRIBUICAO_VISTORIA` | Aguardando distribuição para vistoriador |
| `AGUARDANDO_PAGAMENTO_VISTORIA` | Aguardando pagamento de taxa de vistoria |
| `EM_VISTORIA` | Em vistoria técnica |
| `AGUARDANDO_CIENCIA_CIV` | Aguardando ciência do CIV pelo cidadão |
| `CIV` | Aguardando correção de CIV (Comunicado de Inconformidade na Vistoria) |
| `ALVARA_VIGENTE` | APPCI em vigor |
| `AGUARDANDO_PRPCI` | Aguardando PrPCI |
| `AGUARDANDO_ACEITE_PRPCI` | Aguardando aceite do PrPCI |
| `AGUARDANDO_FACT` | Aguardando FACT (Formulário de Atendimento e Consulta Técnica) |
| `FACT_VIGENTE` | FACT em vigor |
| `RECURSO_EM_ANALISE_1_CIA` | Recurso em análise — 1ª instância (CIA) |
| `RECURSO_EM_ANALISE_2_CIA` | Recurso em análise — 2ª instância (CIA) |
| `RECURSO_EM_ANALISE_1_CIV` | Recurso em análise — 1ª instância (CIV) |
| `RECURSO_EM_ANALISE_2_CIV` | Recurso em análise — 2ª instância (CIV) |
| `ALVARA_VENCIDO` | APPCI com prazo de validade expirado |
| `AGUARDANDO_ACEITE_RENOVACAO` | Aguardando aceite da vistoria de renovação |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | Aguardando pagamento da vistoria de renovação |
| `AGUARDANDO_DISTRIBUICAO_RENOV` | Aguardando distribuição para vistoria de renovação |
| `EM_VISTORIA_RENOVACAO` | Em vistoria de renovação |
| `AGUARDANDO_ACEITES_EXTINCAO` | Aguardando aceites de extinção |

**Métodos auxiliares (a implementar no enum):**

```java
// Retorna os 6 estados considerados "em análise" para filtros de listagem
public static List<SituacaoLicenciamento> retornaSituacoesEmAnalises()

// Retorna ALVARA_VIGENTE e ALVARA_VENCIDO
public static List<SituacaoLicenciamento> retornaSituacoesRenovacao()

// Retorna os 8 estados de renovação do ponto de vista do cidadão
public static List<SituacaoLicenciamento> retornaSituacoesMinhasRenovacoes()

// Filtra por descrição (ignora acentos)
public static Optional<SituacaoLicenciamento> contains(String descricao)

// Filtra por descrição apenas nos estados de renovação
public static Optional<SituacaoLicenciamento> containsRenovacao(String descricao)
```

---

### 4.3 `TipoFaseLicenciamento`

```java
public enum TipoFaseLicenciamento {
    PROJETO,   // Fase de projeto (licenciamento antes da obra)
    EXECUCAO   // Fase de execução (obra em andamento ou concluída)
}
```

---

### 4.4 `TipoSituacaoIsencao`

```java
public enum TipoSituacaoIsencao {
    SOLICITADA,        // Cidadão solicitou isenção de taxa
    SOLICITADA_RENOV,  // Cidadão solicitou isenção na renovação
    APROVADA,          // Isenção aprovada pelo CBM-RS
    REPROVADA          // Isenção reprovada pelo CBM-RS
}
```

---

### 4.5 `TipoResponsabilidadeTecnica` (RT)

```java
public enum TipoResponsabilidadeTecnica {
    PROJETO,           // RT responsável apenas pelo projeto
    EXECUCAO,          // RT responsável apenas pela execução
    PROJETO_EXECUCAO,  // RT responsável por projeto e execução
    RENOVACAO_APPCI    // RT responsável pela renovação do APPCI
}
```

---

### 4.6 `TipoEnvolvido`

```java
public enum TipoEnvolvido {
    RT,       // Responsável Técnico
    RU,       // Responsável pelo Uso
    AMBOS,    // RT e RU (usado para termos comuns)
    VISTORIA, // Envolvidos em vistoria
    // ... outros conforme necessidade
}
```

---

## 5. Camada de Regras de Negócio — Wizard (Etapas 1 a 7)

O wizard é um formulário multi-etapa com persistência automática do progresso (campo `passo` em `LicenciamentoED`). Todas as operações de escrita devem usar `@TransactionAttribute(TransactionAttributeType.REQUIRED)`.

### 5.1 Criação do Rascunho

**Classe responsável:** `LicenciamentoCidadaoRN` → método `incluir(LicenciamentoDTO)`
**Anotação:** `@Permissao(objeto = "ENVOLVIDOS", acao = "INCLUIR")`

**RN-P03-001 — Estado inicial obrigatório**
- `situacao = SituacaoLicenciamento.RASCUNHO`
- `fase = TipoFaseLicenciamento.PROJETO`
- `passo = 1` (constante `NRO_PASSO`)
- `diasAnaliseAnterior = 0`
- `numero = null` (gerado apenas na submissão)
- `recursoBloqueado = false`

**RN-P03-002 — Identificação do criador**
- O CPF do usuário logado é obtido da sessão OAuth2 (via `CidadaoSessionMB` ou equivalente).
- O sistema deve verificar que o CPF está cadastrado e ativo no sistema antes de criar.

**RN-P03-003 — Fluxo de inclusão (método `incluir`)**

```
1. licenciamentoRNVal.validaLicenciamentoParaInclusao(dto)
2. Cria LicenciamentoED via licenciamentoRN.inclui(ed)
3. licenciamentoSituacaoHistRN.salva(ed, RASCUNHO)
4. ed.setFase(PROJETO)
5. licenciamentoProprietarioRN.incluir(proprietarios, ed)
6. SE tipo == PPCI OU tipo == PSPCIM:
     responsavelTecnicoRN.incluir(rts, ed)
     responsavelUsoRN.incluir(rus, ed)
7. estabelecimentoRN.incluir(estabelecimentos, ed)
8. licenciamentoMarcoRN.criaMarcoPorTipo(ed, TipoMarco.RASCUNHO_LICENCIAMENTO)
9. notificacaoRN.notificaEnvolvidosNovos(ed)
10. return ed.getId()
```

**RN-P03-004 — Persistência parcial entre sessões**
- Se o usuário fechar o navegador, a solicitação é listada em "Meus Licenciamentos" com `situacao = RASCUNHO` e `passo` no último valor salvo.
- O frontend deve consultar `GET /licenciamentos/{id}` ao retomar, restaurando o estado a partir do campo `passo`.

---

### 5.2 Etapa 1 — Seleção do Tipo de Atividade / Enquadramento

**RN-P03-010 — Seleção de tipo**
- O usuário seleciona um valor de `TipoLicenciamento`.
- Para o fluxo P03, os tipos esperados são `PPCI` ou `PSPCIM`.
- O tipo `CLCB`, `EVENTO_TEMPORARIO`, `EVENTO_PIROTECNICO` e `CONSTRUCAO_PROVISORIA` têm fluxos distintos, fora do escopo do P03.
- O tipo **não pode ser alterado** após a submissão do licenciamento.

**RN-P03-011 — Diferença de fluxo por tipo**
- Para `PPCI` e `PSPCIM`: obrigatório vincular RT e RU.
- Para `CLCB`: RT e RU não são exigidos.
- A condição `tipo == PPCI || tipo == PSPCIM` controla os ramos de inclusão de envolvidos no método `incluir`.

**RN-P03-012 — Persistência da Etapa 1**
- Ao avançar: `passo = 2`, campo `tipo` salvo.

---

### 5.3 Etapa 2 — Dados do Estabelecimento / Empresa

**RN-P03-020 — Estabelecimento**
- O estabelecimento é vinculado via `EstabelecimentoED`.
- Um licenciamento pode ter múltiplos estabelecimentos.
- O método `estabelecimentoRN.incluir(estabelecimentos, licenciamentoED)` é chamado na criação.

**RN-P03-021 — Proprietários**
- O proprietário é vinculado via `LicenciamentoProprietarioED` → `ProprietarioED`.
- O método `licenciamentoProprietarioRN.incluir(proprietarios, licenciamentoED)` é chamado na criação.
- Pode haver mais de um proprietário.

**RN-P03-022 — Procurador do RU ou Proprietário**
- Se o RU ou Proprietário atua por procurador, a entidade `ProcuradorED` é vinculada.
- Em `ResponsavelUsoED.procurador` e `LicenciamentoProprietarioED.procurador`.
- O procurador é o responsável pelo aceite em nome do representado.
- O arquivo da procuração é enviado via endpoints específicos (ver §7.5).

**RN-P03-023 — Persistência da Etapa 2**
- Ao avançar: `passo = 3`, `estabelecimentos` e `proprietarios` salvos.

---

### 5.4 Etapa 3 — Vinculação do Responsável Técnico (RT)

**RN-P03-030 — RT obrigatório para PPCI e PSPCIM**
- Para `tipo == PPCI || tipo == PSPCIM`: ao menos um RT deve ser vinculado.
- Implementado no bloco condicional dentro de `incluir()`.

**RN-P03-031 — Busca do RT**
- O RT deve ter cadastro aprovado no sistema (processo P02).
- A busca retorna dados do `UsuarioED` associado ao RT.

**RN-P03-032 — Tipo de responsabilidade técnica**
- Ao vincular, o RT recebe um `TipoResponsabilidadeTecnica`:
  - `PROJETO`: Responsável apenas pelo projeto do PPCI.
  - `EXECUCAO`: Responsável pela execução das medidas.
  - `PROJETO_EXECUCAO`: Responsável pelo projeto e execução.
- O tipo `RENOVACAO_APPCI` é atribuído apenas em processos de renovação (não P03).

**RN-P03-033 — Aceite inicial do RT**
- Ao ser vinculado, `aceite = false`.
- O aceite só é confirmado na etapa pós-submissão (§6.2).

**RN-P03-034 — Arquivo do RT (ART/RRT)**
- O RT deve ter ao menos um arquivo vinculado em `CBM_RESPONSAVEL_ARQUIVO`.
- O upload é feito via `POST /licenciamentos/{idLic}/rt/{idRT}/arquivo`.
- O arquivo é armazenado no Alfresco; apenas o `identificadorAlfresco` é persistido em `ArquivoED`.

**RN-P03-035 — Múltiplos RTs**
- É permitido vincular mais de um RT (ex.: arquiteto + engenheiro).
- Cada RT vinculado precisará aceitar individualmente.

**RN-P03-036 — Persistência da Etapa 3**
- Ao avançar: `passo = 4`, `responsaveisTecnicos` salvos.

---

### 5.5 Etapa 4 — Endereço / Localização

**RN-P03-040 — Entidade de localização**
- A localização é representada por `LocalizacaoED`, que contém:
  - Referência a `EnderecoLicenciamentoED` (endereço estruturado) ou `EnderecoLicenciamentoNovoED`.
  - Coordenadas geográficas (`latitudeEndereco`, `longitudeEndereco`, `latitudeMapa`, `longitudeMapa`).
  - Comprovante de endereço (FK para `ArquivoED`).
- O endpoint `POST /licenciamentos/{idLic}/localizacao/` cria a localização.
- O endpoint `PUT /licenciamentos/{idLic}/localizacao/` altera.

**RN-P03-041 — Comprovante de endereço**
- O cidadão pode fazer upload de um comprovante de endereço via:
  - `POST /licenciamentos/{idLic}/localizacao/{idLocalizacao}/arquivo`
- O arquivo é armazenado no Alfresco.

**RN-P03-042 — Verificação de endereço existente**
- O endpoint `GET /licenciamentos/{idLic}/endereco-existente` verifica se já existe outro licenciamento ativo no mesmo endereço.
- Se existir, o sistema deve alertar o cidadão (não bloqueia, apenas avisa).

**RN-P03-043 — Persistência da Etapa 4**
- Ao avançar: `passo = 5`, `localizacao` salva.

---

### 5.6 Etapa 5 — Dados da Edificação

**RN-P03-050 — Entidade de características**
- A edificação é descrita por `CaracteristicaED`.
- O endpoint `POST /licenciamentos/{idLic}/caracteristicas/` cria.
- O endpoint `PUT /licenciamentos/{idLic}/caracteristicas/{idCaracteristica}` altera.

**RN-P03-051 — Campos obrigatórios de características**

| Campo | Obrigatório | Tipo |
|---|---|---|
| `edificacao` | Sim | `TipoEdificacao` (enum) |
| `periodoConstrucao` | Sim | `TipoPeriodoConstrucao` (enum) |
| `areaConstruida` | Sim | Double (m²) — valor positivo |
| `pavimAcimaSolo` | Sim | Long — mínimo 1 |
| `alturaAscendente` | Sim | Double (metros) |
| `populacaoTotal` | Sim | Long — valor positivo |
| `regularizada` | Sim | Boolean |

**RN-P03-052 — Ocupações**
- As ocupações do estabelecimento são listadas em `List<OcupacaoED>` (OneToMany, não auditada).
- Ao menos uma ocupação deve ser informada.

**RN-P03-053 — Especificações de risco**
- As especificações de risco são armazenadas em `EspecificacaoRiscoED` (OneToMany em `LicenciamentoED`).
- O endpoint `POST /licenciamentos/{idLic}/riscos` cria as especificações.
- O endpoint `PUT /licenciamentos/{idLic}/riscos` altera.

**RN-P03-054 — Medidas de segurança (EspecificacaoSegurancaED)**
- Representa o conjunto de medidas de segurança contra incêndio.
- O endpoint `POST /licenciamentos/{idLic}/medidas-seguranca` cria.
- O endpoint `PUT /licenciamentos/{idLic}/medidas-seguranca/{idEspecSeg}/` altera.
- Documentos complementares e ART/RRT da inviabilidade técnica são gerenciados por sub-endpoints específicos.
- O endpoint `DELETE /licenciamentos/{idLic}/remove-espec-seg-voltar` remove as especificações quando o cidadão volta ao passo anterior.

**RN-P03-055 — Arquivo de planta (Característica)**
- O cidadão pode fazer upload de um arquivo de planta associado à característica:
  - `POST /licenciamentos/{idLic}/caracteristicas/{idCaracteristica}/arquivo`
- O arquivo é armazenado no Alfresco.

**RN-P03-056 — Persistência da Etapa 5**
- Ao avançar: `passo = 6`, `caracteristica`, `especificacaoSeguranca` e `especificacoesRisco` salvos.

---

### 5.7 Etapa 6 — Upload de Documentos Obrigatórios (Elementos Gráficos)

**RN-P03-060 — Entidade de documentos**
- Cada documento é representado por `ElementoGraficoED`, que referencia um `ArquivoED`.
- O arquivo binário é armazenado no Alfresco; apenas `identificadorAlfresco` é persistido.

**RN-P03-061 — Gerenciamento de elementos gráficos**
- `PUT /licenciamentos/{idLic}/elementos-graficos` — cria ou altera a lista de elementos.
- `POST /licenciamentos/{idLic}/elementos-graficos/{id}/arquivo` — faz upload do arquivo.
- `PUT /licenciamentos/{idLic}/elementos-graficos/{id}/arquivo` — substitui arquivo.
- `GET /licenciamentos/{idLic}/elementos-graficos/{idElemGraf}/arquivo` — download do arquivo (retorna `InputStream` do Alfresco, `application/octet-stream`).
- `GET /licenciamentos/{idLic}/elementos-graficos/{id}/arquivo/validar-upload` — valida se o arquivo está disponível para upload.

**RN-P03-062 — Situação do elemento gráfico**
- `situacao = TipoSituacao.ATIVO` ao incluir.
- A exclusão é lógica: `situacao = TipoSituacao.INATIVO`, com preenchimento de `dataExclusao` e `idUsuarioExclusao`.
- O registro histórico é mantido em `ElementoGraficoHistoricoED`.

**RN-P03-063 — Validação de completude antes do avanço**
- Antes de avançar para a Etapa 7, o sistema deve verificar se todos os tipos de `ElementoGrafico` obrigatórios para o `TipoLicenciamento` e o grupo de ocupação estão com `situacao = ATIVO` e com `identificadorAlfresco` preenchido.

**RN-P03-064 — Persistência da Etapa 6**
- Ao avançar: `passo = 7`, `elementosGraficos` salvos.

---

### 5.8 Etapa 7 — Revisão, Aceite do Termo e Confirmação

**RN-P03-070 — Exibição do Termo**
- O texto do termo é obtido via `GET /licenciamentos/{idLic}/termo`.
- A `TermoLicenciamentoRN.get(idLicenciamento)` determina o termo correto:
  1. Verifica se o usuário é RT, RU ou ambos.
  2. Determina o `TipoLicenciamento` do licenciamento.
  3. Consulta `TermoLicenciamentoED` com os critérios `tpEnvolvido` e `tpLicenciamento`.

**RN-P03-071 — Submissão e aceite do termo**
- O endpoint `PUT /licenciamentos/{idLic}/termo` dispara a lógica de `TermoLicenciamentoRN.confirmaAceiteAnalise(idLicenciamento)`.

**RN-P03-072 — Fluxo de `confirmaAceiteAnalise` (TermoLicenciamentoRN)**

```
1. Consulta LicenciamentoED por idLicenciamento
2. Busca lista de RTs (por licenciamento)
3. Busca lista de RUs (por licenciamento)
4. Busca lista de Proprietários (por licenciamento)
5. Aplica Consumer CONFIRMA_ACEITE_ANALISE em cada envolvido logado:
      envolvido.setAceite(true)
6. Marca marco TipoMarco.ACEITE_ANALISE
7. VERIFICA: apenas 1 RT aceitou e demais não?
      SIM → situacao = AGUARDANDO_ACEITE
             (aguarda demais RT/RU/Proprietários)
8. VERIFICA: todos os envolvidos têm aceite == true?
      NÃO → permanece AGUARDANDO_ACEITE
      SIM → continua:
9. Marca marco TipoMarco.FIM_ACEITES_ANALISE
10. VERIFICA condição de transição:
    a) isencao == true → situacao = AGUARDANDO_PAGAMENTO
    b) inviabilidade técnica detectada → situacao = ANALISE_INVIABILIDADE_PENDENTE
    c) padrão → situacao = AGUARDANDO_DISTRIBUICAO
11. Persiste mudança de situação via licenciamentoSituacaoHistRN.salva()
12. Notifica analistas CBM-RS via notificacaoRN
```

**RN-P03-073 — Geração do número do licenciamento**
- O número (`COD_LICENCIAMENTO`) no formato `[Tipo][Sequencial 8d] [Lote 2L] [Versão 3d]` é gerado no momento da submissão.
- A geração é feita por `LicenciamentoNumeroRN` (ou equivalente), usando sequence do banco e lógica de lote.
- O número é único e imutável após a submissão.

**RN-P03-074 — Imutabilidade pós-submissão**
- Após `situacao != RASCUNHO`, nenhum dado da solicitação pode ser alterado pelo cidadão.
- O endpoint `PUT /licenciamentos/{idLic}` verifica a situação e rejeita edições fora do estado de rascunho.
- Exceção: alterações de endereço em situação `AGUARDANDO_ENDERECO` são gerenciadas por fluxo específico.

---

## 6. Regras de Negócio Gerais (RN)

### 6.1 Alteração de Licenciamento (`LicenciamentoCidadaoRN.alterar`)

**Anotação:** `@Permissao(objeto = "ENVOLVIDOS", acao = "ALTERAR")`

**Fluxo:**
```
1. licenciamentoRNVal.validaDTOParaEdicao(dto)
2. licenciamentoRNVal.validaPermissaoEdicaoEnvolvido(dto)
3. licenciamentoRNVal.validaTrocaEnvolvido(dto)
4. Consulta LicenciamentoED existente
5. SE tipo == PPCI OU tipo == PSPCIM:
     responsavelTecnicoRN.alterar(rts, licenciamentoED)
     responsavelUsoRN.alterar(rus, licenciamentoED)
6. licenciamentoProprietarioRN.alterar(proprietarios, licenciamentoED)
7. estabelecimentoRN.alterar(estabelecimentos, licenciamentoED)
8. termoLicenciamentoRN.removerAceitesAnalise(licenciamentoED.getId())
9. licenciamentoED.setPasso(NRO_PASSO)  // volta ao passo 1
10. return toDTO(licenciamentoED)
```

> **Regra crítica:** Qualquer alteração nos envolvidos remove todos os aceites de análise já registrados e reinicia o passo para 1. Isso é necessário pois a mudança de envolvidos invalida os termos já aceitos.

---

### 6.2 Aceite Individual dos Envolvidos (pós-submissão)

**Predicates e Consumers em `TermoLicenciamentoRN`:**

```java
// Confirma aceite de análise:
static final Consumer<EnvolvidoED> CONFIRMA_ACEITE_ANALISE = e -> e.setAceite(true);

// Remove aceite de análise:
static final Consumer<EnvolvidoED> REMOVE_ACEITE_ANALISE = e -> e.setAceite(null);

// Filtra envolvidos com aceite confirmado:
static final Predicate<EnvolvidoED> RETORNA_ACEITE_ANALISE = e ->
    Optional.ofNullable(e.getAceite()).orElse(false);

// Confirma aceite de vistoria:
static final Consumer<EnvolvidoED> CONFIRMA_ACEITE_VISTORIA = e -> {
    e.setAceiteVistoria(true);
    e.setDthAceiteVistoria(Calendar.getInstance());
};
```

**Verificação de aceite total:**
```
todosAceitaram = rts.stream().allMatch(RETORNA_ACEITE_ANALISE)
              && rus.stream().allMatch(RETORNA_ACEITE_ANALISE)
              && proprietarios.stream().allMatch(RETORNA_ACEITE_ANALISE)
```

---

### 6.3 Listagem de Pendentes de Aceite (`listarPendentesDeAceite`)

**Fluxo:**
```
1. Obtém CPF do usuário logado
2. busca RTs com aceite == false por CPF
   → se encontrado: retorna licenciamentos correspondentes
3. busca RUs com aceite == false por CPF
   → se encontrado: retorna licenciamentos correspondentes
4. busca Procuradores com aceite == false por CPF
   → se encontrado: retorna licenciamentos via RUs do procurador
5. nenhum encontrado → lança WebApplicationRNException(NOT_FOUND)
```

---

### 6.4 Controle de Recurso Administrativo (`podeSolicitarRecurso`)

**Constantes em `LicenciamentoCidadaoRN`:**
- `PRAZO_SOLICITAR_RECURSO_1_INSTANCIA = 30` (dias)
- `PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15` (dias)

**Lógica:**
```
SE situacao == NCA:
    busca última AnaliseLicenciamentoTecnicaED com resultado REPROVADO e ciência == true
    SE encontrada:
        SE prazo 1ª instância não expirado E não há recurso em andamento:
            licenciamentoDTO.setPodeSolicitarRecurso1Instancia(true)
        SE prazo 2ª instância não expirado E não há recurso em andamento:
            licenciamentoDTO.setPodeSolicitarRecurso2Instancia(true)
SE situacao == CIV:
    lógica equivalente para CIV
SE recursoBloqueado == true:
    ambas as flags ficam false (usuário editou CIA = bloqueia recurso)
```

---

### 6.5 Isenção de Taxa (`atualizaSolicitacaoIsencao`)

```
SE solicitacaoIsencao == true:
    licenciamento.setDthSolicitacaoIsencao(Calendar.getInstance())
    licenciamento.setSituacaoIsencao(
        isRenovacao ? SOLICITADA_RENOV : SOLICITADA
    )
    licenciamento.setIsencao(true)
    licenciamentoMarcoRN.criaMarcoPorTipo(TipoMarco.SOLICITACAO_ISENCAO)
SE solicitacaoIsencao == false:
    licenciamento.setDthSolicitacaoIsencao(null)
    licenciamento.setSituacaoIsencao(null)
    licenciamento.setIsencao(false)
```

---

### 6.6 Exclusão do Licenciamento

**Endpoint:** `DELETE /licenciamentos/{idLic}`
**Classe:** `LicenciamentoCidadaoExclusaoRN.exclui(idLicenciamento)`
- Aplica-se apenas a licenciamentos em estado `RASCUNHO`.
- Remove todos os relacionamentos antes de excluir o licenciamento.

---

### 6.7 Extinção do Licenciamento

**Endpoint:** `POST /licenciamentos/{idLic}/extinguir`
**Classe:** `LicenciamentoCidadaoExtincaoRN.extingue(idLicenciamento)`
- Aplica-se a licenciamentos em estados pós-submissão.
- Muda situação para `AGUARDANDO_ACEITES_EXTINCAO`.
- Notifica todos os envolvidos.

**Recusa e cancelamento de extinção:**
- `PUT /licenciamentos/{idLic}/recusa-extincao` → reverte a extinção
- `PUT /licenciamentos/{idLic}/cancelar-extincao` → cancela o pedido de extinção

---

## 7. Especificação da API REST (JAX-RS)

**Classe de Resource:** `LicenciamentoRest`
**Base Path:** `/licenciamentos`
**Produces:** `application/json`
**Consumes:** `application/json`
**Autenticação:** OAuth2 Bearer Token (SOE PROCERGS)
**Respostas de erro:** `WebApplicationException` com `Response.Status`

### 7.1 Licenciamento — Consulta e Listagem

#### `GET /licenciamentos/`

Lista os licenciamentos do usuário autenticado.

**QueryParams:**

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---|---|
| `ordenar` | String | `"ctrDthInc"` | Coluna de ordenação |
| `ordem` | String | `"asc"` | `"asc"` ou `"desc"` |
| `paginaAtual` | Integer | `0` | Página atual (0-based) |
| `tamanho` | Integer | `20` | Itens por página |
| `tipo` | `List<TipoLicenciamento>` | — | Filtro por tipo |
| `situacao` | `List<SituacaoLicenciamento>` | — | Filtro por situação |
| `cidade` | String | — | Filtro por cidade |
| `nomeFantasia` | String | — | Filtro por nome fantasia |
| `numero` | String | — | Filtro por número do licenciamento |
| `termo` | String | — | Busca textual genérica |

**Retorno:** `200 OK` → `ListaPaginadaRetorno<LicenciamentoDTO>`

---

#### `GET /licenciamentos/{idLic}`

Retorna o licenciamento completo.

**PathParam:** `idLic` (Long)
**Anotação:** `@AutorizaEnvolvido`
**Retorno:** `200 OK` → `LicenciamentoDTO` (com todos os relacionamentos)
**Erros:** `401`, `403`, `404`, `500`

---

#### `GET /licenciamentos/{idLic}/step`

Retorna o passo atual do wizard.

**Produces:** `text/plain`
**Retorno:** `200 OK` → `Integer`

---

#### `GET /licenciamentos/{idLic}/termo`

Busca o texto do termo do envolvido autenticado para o licenciamento.

**Retorno:** `200 OK` → `TermoLicenciamento` (DTO com texto do termo)

---

#### `GET /licenciamentos/{idLic}/envolvidos`

Retorna a lista de todos os envolvidos (RTs, RUs, Proprietários).

**Retorno:** `200 OK` → lista de envolvidos com seus estados de aceite

---

#### `GET /licenciamentos/{idLic}/endereco-existente`

Verifica se outro licenciamento ativo usa o mesmo endereço.

**Retorno:** `200 OK` → `Boolean`

---

#### `GET /licenciamentos/aceite-pendente`

Busca o primeiro licenciamento com aceite pendente para o usuário autenticado.

**Retorno:** `200 OK` → Header `Location` com ID do licenciamento

---

#### `GET /licenciamentos/licenciamentos-alvara`

Lista licenciamentos com APPCI vigente ou vencido (para renovação).

**QueryParams:** mesmos da listagem principal
**Retorno:** `200 OK` → `ListaPaginadaRetorno<LicenciamentoDTO>`

---

#### `GET /licenciamentos/minha-solicitacoes-renovacao`

Lista as solicitações de renovação do usuário autenticado.

**Retorno:** `200 OK` → `ListaPaginadaRetorno<LicenciamentoDTO>`

---

#### `GET /licenciamentos/{idLic}/rus`

Retorna os responsáveis pelo uso do licenciamento.

**Retorno:** `200 OK` → `List<ResponsavelUsoDTO>`

---

#### `GET /licenciamentos/{idLic}/pagamentos`

Lista os boletos de taxa do licenciamento.

**Retorno:** `200 OK` → `List<BoletoLicenciamentoDTO>`

---

#### `GET /licenciamentos/{idLic}/comprovante-isencao`

Lista os comprovantes de isenção enviados.

**Retorno:** `200 OK` → `List<ComprovanteIsencaoDTO>`

---

#### `GET /licenciamentos/{idLic}/documento-complementar`

Lista os documentos complementares do licenciamento.

**Retorno:** `200 OK` → `List<DocComplementarLicED>` (com `licenciamento` nullificado para evitar ciclo)

---

#### `GET /licenciamentos/historico-aceite-termo/{idLic}`

Retorna histórico de todos os aceites de termo registrados.

**Retorno:** `200 OK` → `List<HistoricoTermoDTO>`

---

#### `GET /licenciamentos/historico-aceite-anexo-d/{idLic}`

Retorna histórico de aceites do Anexo D.

**Retorno:** `200 OK` → `List<HistoricoAnexoDDTO>`

---

#### `GET /licenciamentos/vencimento-appci/{idLic}`

Verifica a data de vencimento do APPCI vigente.

**Retorno:** `200 OK` → `VencimentoAppciDTO`

---

#### `GET /licenciamentos/possui-recurso-pendente/{idLic}`

Verifica se há recurso administrativo pendente.

**Retorno:** `200 OK` → `Boolean`

---

#### `GET /licenciamentos/{idLic}/reponsaveis-pagamento`

Lista responsáveis pelo pagamento da taxa de licenciamento.

**Retorno:** `200 OK` → `List<ResponsavelPagamentoDTO>`

---

#### `GET /licenciamentos/{idLic}/reponsaveis-pagamento-renovacao`

Lista responsáveis pelo pagamento da renovação.

**Retorno:** `200 OK` → `List<ResponsavelPagamentoDTO>`

---

#### `GET /licenciamentos/termo-anexo-d/{idLic}`

Retorna o termo do Anexo D e o estado de ciência do RT.

**Retorno:** `200 OK` → `RetornoCienciaTermoAnexoDDTO`

---

#### `GET /licenciamentos/termo-anexo-d-renovacao/{idLic}`

Retorna o termo do Anexo D para renovação.

**Retorno:** `200 OK` → `RetornoCienciaTermoAnexoDDTO`

---

### 7.2 Licenciamento — Criação e Alteração

#### `POST /licenciamentos/`

Cria um novo licenciamento.

**Anotação:** `@AutorizaEnvolvido`
**Body:** `LicenciamentoDTO`
**Fluxo:** chama `LicenciamentoCidadaoRN.incluir()`
**Retorno:** `201 Created` com Header `Location: /licenciamentos/{id}`

---

#### `PUT /licenciamentos/{idLic}`

Altera dados de um licenciamento em `RASCUNHO`.

**Anotação:** `@AutorizaEnvolvido`
**PathParam:** `idLic` (Long)
**Body:** `LicenciamentoDTO`
**Fluxo:** chama `LicenciamentoCidadaoRN.alterar()`
**Retorno:** `200 OK` → `LicenciamentoDTO` atualizado

---

#### `PUT /licenciamentos/{idLic}/termo`

Confirma o aceite do termo de análise pelo envolvido autenticado (Etapa 7).

**Anotação:** `@AutorizaEnvolvido`
**Fluxo:** chama `TermoLicenciamentoRN.confirmaAceiteAnalise(idLicenciamento)`
**Retorno:** `200 OK`

---

#### `PUT /licenciamentos/{idLic}/solicitacaoIsencao`

Marca ou remove a solicitação de isenção de taxa.

**Anotação:** `@AutorizaEnvolvido`
**Body:** `Map<String, Boolean>` com chaves `"solicitacao"` e `"solicitacaoRenovacao"`
**Fluxo:** chama `LicenciamentoCidadaoRN.atualizaSolicitacaoIsencao()`
**Retorno:** `200 OK`

---

#### `PUT /licenciamentos/{idLic}/bloquear-recurso`

Bloqueia a possibilidade de recurso (ativado quando o cidadão edita durante o período de CIA).

**Fluxo:** `licenciamentoED.setRecursoBloqueado(true)`
**Retorno:** `200 OK`

---

#### `PUT /licenciamentos/{idLic}/recusa-extincao`

Recusa o pedido de extinção.

**Anotação:** `@AutorizaEnvolvido`
**Retorno:** `200 OK`

---

#### `PUT /licenciamentos/{idLic}/cancelar-extincao`

Cancela o pedido de extinção.

**Anotação:** `@AutorizaEnvolvido`
**Retorno:** `200 OK`

---

#### `PUT /licenciamentos/termo-anexo-d/{idLic}`

Registra aceite do Anexo D pelo RT.

**Validações:**
- Usuário logado é RT do licenciamento.
- `tipoResponsabilidadeTecnica` ∈ `{EXECUCAO, PROJETO_EXECUCAO, RENOVACAO_APPCI}`.
- `situacao` ∈ `{CA, CIV, ALVARA_VIGENTE, ALVARA_VENCIDO}`.
- RT ainda não tem `aceiteAnexoD == true`.

**Fluxo:** chama `TermoLicenciamentoRN.confirmaInclusaoAnexoD(idLic)`
**Retorno:** `200 OK` → `RetornoCienciaTermoAnexoDDTO`

---

#### `PUT /licenciamentos/termo-anexo-d-renovacao/{idLic}`

Registra aceite do Anexo D para renovação.

**Validações adicionais:** cancela recursos CIV pendentes antes do aceite.
**Fluxo:** chama `TermoLicenciamentoRN.confirmaInclusaoAnexoDRenovacao(idLic)`
**Retorno:** `200 OK` → `RetornoCienciaTermoAnexoDDTO`

---

### 7.3 Licenciamento — Exclusão e Extinção

#### `DELETE /licenciamentos/{idLic}`

Remove o licenciamento (apenas `RASCUNHO`).

**Anotação:** `@AutorizaEnvolvido`
**Fluxo:** chama `LicenciamentoCidadaoExclusaoRN.exclui(idLicenciamento)`
**Retorno:** `200 OK`

---

#### `DELETE /licenciamentos/termo-anexo-d/{idLic}`

Remove o aceite do Anexo D.

**Fluxo:** `TermoLicenciamentoRN.removeAceiteAnexoD(idLic, verificarUsuarioLogado = true)`
**Retorno:** `200 OK`

---

#### `DELETE /licenciamentos/termo-anexo-d-renovacao/{idLic}`

Remove o aceite do Anexo D de renovação.

**Validações:** RT deve ser do tipo `RENOVACAO_APPCI`.
**Retorno:** `200 OK`

---

#### `POST /licenciamentos/{idLic}/extinguir`

Inicia extinção do licenciamento.

**Anotação:** `@AutorizaEnvolvido`
**Fluxo:** chama `LicenciamentoCidadaoExtincaoRN.extingue(idLicenciamento)`
**Retorno:** `200 OK`

---

### 7.4 Arquivos do Responsável Técnico

Todos os uploads usam `@Consumes("multipart/form-data")` e retornam o ID do arquivo no Header `Location`.
Downloads retornam `@Produces("application/octet-stream")` com `InputStream` do Alfresco.

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/rt/{idRT}/arquivo` | Upload do documento do RT (ART/RRT) |
| `PUT` | `/{idLic}/rt/{idRT}/arquivo/{idArquivo}` | Substituição do documento do RT |
| `GET` | `/{idLic}/rt/{idRT}/arquivo/{idArquivo}` | Download do documento do RT |
| `DELETE` | `/{idLic}/rt/{idRT}/arquivo/{idArquivo}` | Exclusão do documento do RT |

---

### 7.5 Arquivos de Procuração (RU e Proprietário)

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/ru/{cpf}/procurador/arquivo` | Upload procuração do RU |
| `PUT` | `/{idLic}/ru/{cpf}/procurador/arquivo` | Substituição procuração do RU |
| `GET` | `/{idLic}/ru/{cpf}/procurador/arquivo` | Download procuração do RU |
| `POST` | `/{idLic}/proprietario/{cpfCnpj}/procurador/arquivo` | Upload procuração do Proprietário |
| `PUT` | `/{idLic}/proprietario/{cpfCnpj}/procurador/arquivo` | Substituição procuração do Proprietário |
| `GET` | `/{idLic}/proprietario/{cpfCnpj}/procurador/arquivo` | Download procuração do Proprietário |

---

### 7.6 Características

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/caracteristicas/` | Cria característica da edificação |
| `PUT` | `/{idLic}/caracteristicas/{idCaracteristica}` | Altera característica |
| `POST` | `/{idLic}/caracteristicas/{idCaracteristica}/arquivo` | Upload de planta |
| `PUT` | `/{idLic}/caracteristicas/{idCaracteristica}/arquivo` | Substituição de planta |
| `GET` | `/{idLic}/caracteristicas/{idCaracteristica}/arquivo` | Download da planta |

---

### 7.7 Medidas de Segurança (EspecificacaoSeguranca)

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/medidas-seguranca` | Cria especificação de segurança |
| `PUT` | `/{idLic}/medidas-seguranca/{idEspecSeg}/` | Altera especificação |
| `POST` | `/{idLic}/medidas-seguranca/{idEspecSeg}/doc` | Upload de doc complementar (inviabilidade) |
| `PUT` | `/{idLic}/medidas-seguranca/{idEspecSeg}/doc/{idArq}` | Atualiza doc complementar |
| `GET` | `/{idLic}/medidas-seguranca/{idEspecSeg}/doc/{idArq}` | Download doc complementar |
| `DELETE` | `/{idLic}/medidas-seguranca/{idEspecSeg}/doc/{idArq}` | Remove doc complementar |
| `POST` | `/{idLic}/medidas-seguranca/{idEspecSeg}/art` | Upload ART/RRT de inviabilidade |
| `PUT` | `/{idLic}/medidas-seguranca/{idEspecSeg}/art/{idArquivo}` | Atualiza ART/RRT |
| `GET` | `/{idLic}/medidas-seguranca/{idEspecSeg}/art/{idArt}` | Download ART/RRT |
| `DELETE` | `/{idLic}/medidas-seguranca/{idEspecSeg}/art/{idArquivo}` | Remove ART/RRT |
| `DELETE` | `/{idLic}/remove-espec-seg-voltar` | Remove especificações ao voltar passo |

---

### 7.8 Especificações de Risco

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/riscos` | Cria lista de especificações de risco |
| `PUT` | `/{idLic}/riscos` | Altera lista de especificações de risco |

---

### 7.9 Elementos Gráficos

| Método | Endpoint | Descrição |
|---|---|---|
| `PUT` | `/{idLic}/elementos-graficos` | Cria ou altera lista de elementos gráficos |
| `POST` | `/{idLic}/elementos-graficos/{id}/arquivo` | Upload do arquivo do elemento |
| `PUT` | `/{idLic}/elementos-graficos/{id}/arquivo` | Substituição do arquivo |
| `GET` | `/{idLic}/elementos-graficos/{idElemGraf}/arquivo` | Download do arquivo |
| `GET` | `/{idLic}/elementos-graficos/{id}/arquivo/validar-upload` | Validação de disponibilidade de upload |

---

### 7.10 Localização / Endereço

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/localizacao/` | Cria localização. Retorno: headers `Location` e `endereco` |
| `PUT` | `/{idLic}/localizacao/` | Altera localização |
| `POST` | `/{idLic}/localizacao/{idLocalizacao}/arquivo` | Upload de comprovante de endereço |
| `PUT` | `/{idLic}/localizacao/{idLocalizacao}/arquivo` | Substituição de comprovante |
| `GET` | `/{idLic}/localizacao/{idLocalizacao}/arquivo` | Download do comprovante |

---

### 7.11 Boletos e Isenções

| Método | Endpoint | Descrição |
|---|---|---|
| `POST` | `/{idLic}/pagamentos/boleto/` | Gera boleto de taxa de licenciamento |
| `GET` | `/{idLic}/pagamentos/boleto/{idBoletoLic}` | Download/geração do arquivo do boleto |
| `PUT` | `/{idLic}/comprovante-isencao/` | Cria comprovante de isenção |
| `POST` | `/{idLic}/comprovante-isencao/{idComprovante}/arquivo` | Upload do comprovante |
| `DELETE` | `/{idLic}/comprovante-isencao/{idComprovante}` | Remove comprovante |
| `GET` | `/{idLic}/comprovante-isencao/{idComprovante}/arquivo` | Download do comprovante |

---

### 7.12 Documentos Complementares

| Método | Endpoint | Descrição |
|---|---|---|
| `GET` | `/{idLic}/documento-complementar` | Lista documentos complementares |
| `GET` | `/doc-complementar-lic-arquivo/{idDocComplementarLic}` | Download de documento complementar |

---

## 8. Segurança e Autorização

### 8.1 Autenticação

- O sistema usa **OAuth2/OIDC** via SOE PROCERGS (`meu.rs.gov.br`).
- O token Bearer é enviado em cada requisição.
- O usuário logado é obtido via `CidadaoSessionMB` (ou equivalente de sessão CDI).

### 8.2 Anotação `@AutorizaEnvolvido`

Anotação customizada CDI processada pelo interceptor `SegurancaEnvolvidoInterceptor`.

**Comportamento:** Verifica se o CPF do usuário autenticado está vinculado ao licenciamento identificado no `{idLic}` da URL, como:
- Criador da solicitação
- `ResponsavelTecnicoED` com `usuario.cpf == cpfLogado`
- `ResponsavelUsoED` com `usuario.cpf == cpfLogado`
- `LicenciamentoProprietarioED` → `ProprietarioED.cpf == cpfLogado`
- `ProcuradorED.cpf == cpfLogado` (quando atua por procurador)

Se não houver vínculo: lança `WebApplicationRNException(FORBIDDEN)`.

### 8.3 Anotação `@Permissao`

```java
@Permissao(objeto = "ENVOLVIDOS", acao = "INCLUIR")
@Permissao(objeto = "ENVOLVIDOS", acao = "ALTERAR")
@Permissao(objeto = "LAUDO_LICENCIAMENTO", acao = "ALTERAR_EXECUCAO")
```

Controla permissões por objeto e ação dentro do sistema de roles do SOE. Processada por interceptor CDI separado.

### 8.4 Regras de Acesso por Perfil

| Operação | Perfil mínimo exigido |
|---|---|
| Criar licenciamento (`POST /licenciamentos/`) | Cidadão autenticado + `@Permissao(ENVOLVIDOS, INCLUIR)` |
| Alterar licenciamento (`PUT /{idLic}`) | Envolvido + `@Permissao(ENVOLVIDOS, ALTERAR)` |
| Confirmar aceite do termo (`PUT /{idLic}/termo`) | Envolvido (RT ou RU ou Proprietário) |
| Upload de arquivo RT | Envolvido |
| Download de arquivo | Envolvido |
| Aceite Anexo D | RT com `tipoResponsabilidadeTecnica` adequado + `@Permissao(LAUDO_LICENCIAMENTO, ALTERAR_EXECUCAO)` |
| Extinguir | Envolvido + `@AutorizaEnvolvido` |

---

## 9. Gestão de Arquivos (Alfresco)

### 9.1 Modelo

- Todos os arquivos do sistema são armazenados no **Alfresco Content Services** (ECM).
- O banco de dados relacional armazena apenas o `identificadorAlfresco` (nodeRef do Alfresco) na entidade `ArquivoED`.
- O conteúdo binário (bytes) nunca é armazenado no banco relacional.
- O campo `@Transient InputStream inputStream` de `ArquivoED` é usado apenas em memória durante upload/download.

### 9.2 Upload

**Padrão de implementação:**
```
1. Receber arquivo via JAX-RS Multipart (@FormDataParam("arquivo") InputStream inputStream)
2. Criar ArquivoED:
      arquivoED.setNomeArquivo(nomeOriginal)
      arquivoED.setInputStreamArquivo(inputStream)
3. Chamar ArquivoRN.salvar(arquivoED):
      → ArquivoRN faz upload para Alfresco via cliente Alfresco
      → Alfresco retorna o nodeRef (identificadorAlfresco)
      → arquivoED.setIdentificadorAlfresco(nodeRef)
4. Persistir ArquivoED no banco (apenas metadados + identificadorAlfresco)
5. Associar ao ElementoGraficoED, ResponsavelTecnicoED, etc.
6. Retornar HTTP 201 com Location contendo ID do ArquivoED
```

### 9.3 Download

**Padrão de implementação:**
```
1. Buscar ArquivoED no banco por ID
2. Chamar ArquivoRN.download(arquivoED):
      → ArquivoRN busca conteúdo no Alfresco via identificadorAlfresco
      → Retorna InputStream com o conteúdo binário
3. Retornar Response com:
      mediaType: application/octet-stream
      header Content-Disposition: attachment; filename="{nomeArquivo}"
      entity: InputStream
```

### 9.4 Verificação de Integridade

- O campo `md5SGM` em `ArquivoED` armazena o hash MD5 do arquivo.
- Deve ser calculado no upload e verificado no download quando necessário.

### 9.5 Cache de Arquivo

- `ArquivoCacheED` (OneToOne com `ArquivoED`, não auditado) pode armazenar um cache temporário do arquivo localmente.
- Reduz chamadas repetidas ao Alfresco para arquivos frequentemente acessados.

---

## 10. Notificações

### 10.1 Eventos e Destinatários

| Evento (no P03) | Destinatários | Método |
|---|---|---|
| Licenciamento criado (novo envolvido) | Envolvidos recém-adicionados | `notificacaoRN.notificaEnvolvidosNovos(ed)` |
| Envolvido aceitou o termo | Demais envolvidos (RTs, RUs, Proprietários) | `TermoLicenciamentoRN.notificarDemaisEnvolvidos()` |
| Todos aceitaram (AGUARDANDO_DISTRIBUICAO) | Analistas CBM-RS | `notificacaoRN` |
| Recurso bloqueado | — | Controle interno |

### 10.2 Padrão de Implementação

**Método `notificarRts`:**
```java
void notificarRts(
    List<ResponsavelTecnicoED> rts,
    String msg,
    String assunto,
    String templateMsg,
    ContextoNotificacaoEnum contexto
)
```

**Método `notificarDemaisEnvolvidos`:**
```java
void notificarDemaisEnvolvidos(
    List<ResponsavelTecnicoED> rts,
    List<ResponsavelUsoED> rus,
    List<LicenciamentoProprietarioED> proprietarios,
    Email email
)
// Lógica:
// 1. Compila lista de demais envolvidos (RUs, Proprietários, Procuradores)
// 2. Remove os RTs já notificados
// 3. Notifica cada um com o Email
```

---

## 11. Auditoria e Histórico

### 11.1 Hibernate Envers

As seguintes entidades são anotadas com `@Audited` e possuem tabelas de auditoria (`*_AUD`):

| Entidade | Tabela de auditoria |
|---|---|
| `LicenciamentoED` | `CBM_LICENCIAMENTO_AUD` |
| `ResponsavelTecnicoED` | `CBM_RESPONSAVEL_TECNICO_AUD` |
| `ResponsavelUsoED` | `CBM_RESPONSAVEL_USO_AUD` |
| `LicenciamentoProprietarioED` | `CBM_LICEN_PROPRI_AUD` |
| `CaracteristicaED` | `CBM_CARACTERISTICA_AUD` |
| `LocalizacaoED` | `CBM_LOCALIZACAO_AUD` |
| `ArquivoED` | `CBM_ARQUIVO_AUD` |

**Entidades sem auditoria:** `ElementoGraficoED`, `EstabelecimentoED` (rastreados via `ElementoGraficoHistoricoED` manualmente).

### 11.2 Histórico de Situação (`LicenciamentoSituacaoHistRN`)

Toda mudança de `SituacaoLicenciamento` deve ser registrada chamando `licenciamentoSituacaoHistRN.salva(licenciamentoED, situacaoNova)`, que cria um registro em tabela de histórico de situações.

### 11.3 Histórico de Aceites de Termo (`HistoricoTermoED`)

- Consultado via `GET /licenciamentos/historico-aceite-termo/{idLic}`.
- Retornado como `List<HistoricoTermoDTO>`.
- Cada registro contém: envolvido, data/hora do aceite, tipo de envolvido.

### 11.4 Histórico de Aceites do Anexo D (`HistoricoAnexoDED`)

- Consultado via `GET /licenciamentos/historico-aceite-anexo-d/{idLic}`.
- Retornado como `List<HistoricoAnexoDDTO>`.

---

## 12. Marcos do Licenciamento

Os marcos registram eventos importantes no ciclo de vida de cada licenciamento. São criados por `LicenciamentoMarcoRN.criaMarcoPorTipo(licenciamentoED, TipoMarco)`.

**Marcos relevantes ao P03:**

| Marco | Criado quando |
|---|---|
| `RASCUNHO_LICENCIAMENTO` | Licenciamento criado — primeiro `POST /licenciamentos/` |
| `ACEITE_ANALISE` | Cada vez que um envolvido individual aceita o termo |
| `FIM_ACEITES_ANALISE` | Quando todos os envolvidos aceitaram — antes da transição de estado |
| `SOLICITACAO_ISENCAO` | Quando cidadão solicita isenção via `PUT /{idLic}/solicitacaoIsencao` |

Os marcos são ordenados por `ctrDthInc ASC` no relacionamento `List<LicenciamentoMarcoED>` de `LicenciamentoED`.

---

## 13. Requisitos Não Funcionais

### 13.1 Transações

- Todas as operações de escrita em `RN` devem ter `@TransactionAttribute(TransactionAttributeType.REQUIRED)`.
- A transação é gerenciada pelo contêiner WildFly via JTA.
- Operações de leitura podem usar `SUPPORTS` ou `NOT_SUPPORTED` quando não há necessidade de transação.

### 13.2 Desempenho

- Consultas no `LicenciamentoBD` usam `DetachedCriteria` com projeções e `Restrictions` do Hibernate para evitar carregamento desnecessário de dados.
- Relacionamentos `@OneToMany` e `@ManyToOne` devem usar `FetchType.LAZY` para evitar N+1.
- `ListaPaginadaRetorno<T>` implementa paginação com `setMaxResults` e `setFirstResult` no Hibernate.

### 13.3 Segurança

- Toda requisição é autenticada via token OAuth2 emitido pelo SOE PROCERGS.
- O interceptor `SegurancaEnvolvidoInterceptor` valida o vínculo do usuário com o licenciamento antes de qualquer operação sensível.
- Exceções de autorização lançam `WebApplicationRNException(Response.Status.FORBIDDEN)`.
- Exceções de recurso não encontrado lançam `WebApplicationRNException(Response.Status.NOT_FOUND)`.

### 13.4 Serialização

- O Jackson serializa/deserializa os DTOs para JSON.
- Campos `null` devem ser omitidos na serialização (`@JsonInclude(JsonInclude.Include.NON_NULL)`).
- Datas são serializadas como timestamp Unix ou ISO-8601 (conforme configuração Jackson existente).

### 13.5 Paginação

- `ListaPaginadaRetorno<T>` encapsula: lista de conteúdo, página atual, tamanho da página, total de registros, total de páginas.
- Todos os endpoints de listagem implementam este padrão.

### 13.6 Nomeação de Sequências e Tabelas

- Seguir o padrão existente: tabelas com prefixo `CBM_`, sequências com sufixo `_SEQ`.
- Exemplo: `CBM_LICENCIAMENTO` / `CBM_ID_LICENCIAMENTO_SEQ`.

### 13.7 Compatibilidade com o Servidor

- A aplicação deve ser empacotada como `WAR` e implantada no WildFly/JBoss.
- Não utilizar funcionalidades exclusivas de outras implementações de servidor (ex.: recursos Spring Boot).

---

## 14. Glossário

| Termo | Definição |
|---|---|
| **PPCI** | Plano de Prevenção e Proteção Contra Incêndio — documento técnico obrigatório para obtenção do APPCI |
| **PSPCIM** | Plano de Segurança para Pequenas e Médias Edificações — versão simplificada do PPCI |
| **CLCB** | Comunicação de Ligação Comercial de Baixo Risco — tipo simplificado de licenciamento |
| **RT** | Responsável Técnico — engenheiro ou arquiteto legalmente habilitado que assina o PPCI |
| **RU** | Responsável pelo Uso — proprietário ou responsável pela utilização do estabelecimento |
| **APPCI** | Alvará de Prevenção e Proteção Contra Incêndio — documento emitido pelo CBM-RS após aprovação do PPCI |
| **CA** | Certificado de Aprovação — resultado positivo da análise técnica; gera o APPCI |
| **NCA** | Não Conformidade Atendida — aprovação condicionada à realização de vistoria in loco |
| **CIA** | Comunicado de Inconformidade na Análise — pendências identificadas pelo analista que o cidadão deve corrigir |
| **CIV** | Comunicado de Inconformidade na Vistoria — pendências identificadas pelo vistoriador |
| **ART** | Anotação de Responsabilidade Técnica (CREA) — vincula o RT ao projeto |
| **RRT** | Registro de Responsabilidade Técnica (CAU) — equivalente da ART para arquitetos |
| **FACT** | Formulário de Atendimento e Consulta Técnica |
| **PrPCI** | Programa de Prevenção Contra Incêndio |
| **Wizard** | Formulário multi-etapa com navegação passo a passo e persistência parcial |
| **ED** | Entity Data — sufixo das entidades JPA do sistema |
| **RN** | Regra de Negócio — sufixo dos EJBs que implementam lógica de negócio |
| **BD** | Banco de Dados — sufixo dos EJBs que implementam acesso a dados |
| **DTO** | Data Transfer Object — objeto de transferência entre camadas |
| **Alfresco** | Repositório de conteúdo ECM onde os arquivos do sistema são armazenados |
| **nodeRef** | Identificador único de um nó (arquivo) no Alfresco; armazenado como `identificadorAlfresco` |
| **SOE** | Sistema de Autenticação do Estado do RS (PROCERGS) |
| **CDI** | Contexts and Dependency Injection — especificação Java EE para injeção de dependências |
| **JAX-RS** | Java API for RESTful Web Services — especificação Java EE para APIs REST |
| **JPA** | Java Persistence API — especificação Java EE para mapeamento objeto-relacional |
| **EJB** | Enterprise JavaBeans — especificação Java EE para componentes de negócio |
| **JTA** | Java Transaction API — gerenciamento de transações pelo contêiner |
| **Envers** | Módulo do Hibernate para auditoria automática de entidades |
| **SimNaoBooleanConverter** | `AttributeConverter` JPA que mapeia `Boolean` Java para `"S"`/`"N"` no banco |
| **Marco** | Registro de evento significativo no ciclo de vida do licenciamento (`LicenciamentoMarcoED`) |
| **`RASCUNHO`** | Estado inicial do licenciamento — wizard em preenchimento |
| **`AGUARDANDO_ACEITE`** | Estado após submissão — aguardando aceite de todos os envolvidos |
| **`AGUARDANDO_DISTRIBUICAO`** | Estado em que todos aceitaram e a análise ainda não foi atribuída a um analista |
| **`EM_ANALISE`** | Estado em que o analista CBM-RS está revisando a documentação |

---

*Documento produzido com base na análise integral do código-fonte do sistema SOL — backend Java EE (versão 16-06) e BPMN P03. Todas as classes, métodos, endpoints, enumerações e fluxos descritos correspondem à implementação real encontrada no código-fonte.*
