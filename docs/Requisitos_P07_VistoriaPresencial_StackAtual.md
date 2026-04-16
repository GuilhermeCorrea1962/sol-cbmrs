# Requisitos — P07 Vistoria Presencial (Stack Atual Java EE)

**Processo:** P07 — Vistoria Presencial
**Versão:** 1.0
**Data:** 2026-03-10
**Stack:** Java EE · JAX-RS (REST) · CDI · JPA/Hibernate · EJB Stateless · Alfresco (ECM) · SOE PROCERGS (IdP)
**Referência:** código-fonte `SOLCBM.BackEnd16-06` — pacotes `com.procergs.solcbm.*`

---

## 1. Visão Geral

O processo P07 compreende a **vistoria presencial** realizada pelo Corpo de Bombeiros Militar do RS após a aprovação da análise técnica (P04) ou da concessão de isenção de taxa (P06). O processo inicia com o licenciamento no estado `AGUARDA_DISTRIBUICAO_VISTORIA` e termina em um de três caminhos de saída:

| Caminho | Condição | Estado final do licenciamento | Artefato gerado |
|---|---|---|---|
| **Aprovado** | Vistoria aprovada e homologada | `AGUARDANDO_PRPCI` | APPCI (Alvará de Prevenção e Proteção Contra Incêndio) |
| **Reprovado** | Laudo de reprovação + ciência do cidadão | `CIV` | CIV (Comunicado de Inconformidade na Vistoria) |
| **Indeferido (volta)** | ADM não homologa; devolve para correção | `EM_VISTORIA` | — (vistoria retoma) |

Para vistorias de **renovação** (`TipoVistoria.VISTORIA_RENOVACAO`), os caminhos e marcos homólogos existem em paralelo:

| Caminho (renovação) | Estado final | Marco |
|---|---|---|
| Aprovado | `AGUARDANDO_ACEITE_PRPCI` | `HOMOLOG_VISTORIA_RENOV_DEFERIDO` |
| Reprovado | `CIV` (com marco `VISTORIA_RENOVACAO_CIV`) | `CIENCIA_CIV_RENOVACAO` |
| Indeferido | `EM_VISTORIA_RENOVACAO` | `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` |

O processo contempla ainda:

- **Distribuição em lote:** um único request distribui múltiplos licenciamentos (`idLicenciamentos: List<Long>`).
- **Laudo técnico:** upload obrigatório antes da conclusão (laudo principal + ART/RRT + complementares opcionais).
- **Ciência do CIV:** etapa onde o cidadão/RT confirma recebimento do CIV; transiciona licenciamento de `AGUARDANDO_CIENCIA_CIV` → `CIV`.
- **Integração LAI:** pesquisa de satisfação cadastrada no sistema LAI após homologação deferida.
- **Rascunho:** o fiscal pode salvar andamento parcial (status `EM_RASCUNHO`) sem concluir a vistoria.

---

## 2. Camadas e Padrão Arquitetural

O sistema segue o padrão de quatro camadas estabelecido em todos os processos do SOL:

```
REST (@Path + @SOEAuthRest)
    │
    ▼
RN  (@Stateless EJB + @AppInterceptor + @Permissao)
    │
    ▼
BD  (JPA EntityManager — consultas nomeadas e JPQL)
    │
    ▼
ED  (@Entity + @Audited — Hibernate Envers)
```

**Pacotes relevantes para P07:**

| Camada | Pacote | Principais classes |
|---|---|---|
| REST | `com.procergs.solcbm.remote.adm.vistoria` | `AtualizaVistoriaAdmRestImpl`, `ListaVistoriaRestImpl` |
| REST | `com.procergs.solcbm.remote.adm.distribuicao` | `LicenciamentoDistribuicaoVistoriaRest` |
| RN | `com.procergs.solcbm.vistoria` | `VistoriaRN`, `VistoriaConclusaoRN`, `VistoriaHomologacaoAdmRN`, `VistorianteRN` |
| RN | `com.procergs.solcbm.laudovistoria` | `LaudoVistoriaRN` |
| RN | `com.procergs.solcbm.licenciamentovistoria.listagem` | `LicenciamentoDistribuicaoVistoriaRN` |
| RN | `com.procergs.solcbm.appci` | `AppciRN` |
| RN | `com.procergs.solcbm.licenciamentociencia.vistoria` | `CivCienciaCidadaoRN` |
| RN | `com.procergs.solcbm.licenciamentointegracaolai` | `LicenciamentoIntegracaoLaiRN` |
| RN | `com.procergs.solcbm.vistoria.documento` | `VistoriaDocumentoCivRN`, `VistoriaDocumentoAppciRN` |
| ED | `com.procergs.solcbm.ed` | `VistoriaED`, `LaudoVistoriaED`, `AppciED`, `VistorianteED` |

---

## 3. Enumerações

### 3.1 StatusVistoria

Estado interno do registro de vistoria (`CBM_VISTORIA.STATUS`). Persistido como `String` via `@Enumerated(EnumType.STRING)`.

```java
public enum StatusVistoria {
    SOLICITADA,         // Vistoria criada; aguardando distribuição de fiscal
    EM_VISTORIA,        // Fiscal distribuído; vistoria em andamento
    EM_RASCUNHO,        // Fiscal salvou parcialmente sem concluir
    EM_APROVACAO,       // Fiscal concluiu (aprovação); aguardando homologação ADM
    APROVADO,           // ADM homologou deferindo a aprovação; APPCI emitido
    REPROVADO,          // Fiscal concluiu (reprovação); CIV gerado
    EM_REDISTRIBUICAO,  // Redistribuição em andamento (antes do início efetivo)
    CANCELADA           // Vistoria cancelada administrativamente
}
```

### 3.2 TipoVistoria

Identifica o ciclo ao qual a vistoria pertence. Persistido como `Integer` (coluna `TIPO_VISTORIA`).

```java
public enum TipoVistoria {
    VISTORIA_DEFINITIVA(1),   // Primeira vistoria do ciclo de licenciamento
    VISTORIA_PARCIAL(2),      // Vistoria de partes específicas da edificação
    VISTORIA_RENOVACAO(3);    // Vistoria para renovação de APPCI vencido

    private final int valor;

    public static TipoVistoria fromInt(int valor) { /* lookup */ }
}
```

### 3.3 TipoLaudo

Tipo de laudo técnico complementar exigido.

```java
public enum TipoLaudo {
    COMPARTIMENTACAO_DE_AREAS,      // Compartimentação horizontal/vertical
    CONTROLE_DE_MATERIAS,           // Controle de materiais de acabamento e revestimento
    SEGURANCA_ESTRUTURAL,           // Segurança estrutural em situação de incêndio
    ISOLAMENTO_RISCO,               // Isolamento de risco entre áreas
    EQUIPAMENTO_DE_UTILIZACAO       // Laudos de equipamentos específicos
}
```

**Constantes de nome descritivo** (usadas em `LaudoVistoriaRN` para exibição):
```java
public static final String ISOLAMENTO_DE_RISCO = "isolamento de risco";
public static final String SEGURANCA_ESTRUTURAL_EM_INCENDIO = "segurança estrutural em incêndio";
public static final String CONTROLE_DE_MATERIAIS_DE_ACABAMENTO_E_REVESTIMENTO =
    "controle de materiais de acabamento e revestimento";
public static final String COMPARTIMENTACAO_AREA_VERTICAL = "compartimentação vertical";
public static final String COMPARTIMENTACAO_AREA_HORIZONTAL = "compartimentação horizontal";
```

### 3.4 TipoTurnoVistoria

Turno previsto para a realização da vistoria.

```java
public enum TipoTurnoVistoria {
    MANHA(0, "Manhã"),
    TARDE(1, "Tarde"),
    NOITE(2, "Noite"),
    INTEGRAL(3, "Integral");

    private final int codigo;
    private final String descricao;
}
```

### 3.5 TrocaEstadoVistoriaEnum

Enum que identifica qual implementação de `TrocaEstadoVistoriaRN` deve ser injetada via qualificador CDI `@TrocaEstadoVistoriaQualifier`.

```java
public enum TrocaEstadoVistoriaEnum {
    EM_APROVACAO_PARA_EM_VISTORIA,              // Indeferimento → volta para execução
    EM_APROVACAO_PARA_APROVADO,                  // Deferimento → aprovado definitivo
    EM_APROVACAO_RENOVACAO_PARA_EM_VISTORIA,    // Indeferimento de renovação
    EM_APROVACAO_RENOVACAO_PARA_APROVADO         // Deferimento de renovação
}
```

### 3.6 SituacaoLicenciamento — valores relevantes ao P07

Estes valores fazem parte do enum global compartilhado por todos os processos. Os pertinentes ao P07:

```java
// Entrada do P07
AGUARDA_DISTRIBUICAO_VISTORIA,       // Aguardando distribuição de fiscal para vistoria definitiva
AGUARDANDO_DISTRIBUICAO_RENOV,       // Aguardando distribuição de fiscal para vistoria de renovação

// Durante a vistoria
EM_VISTORIA,                         // Vistoria ordinária em execução
EM_VISTORIA_RENOVACAO,               // Vistoria de renovação em execução

// Saídas do P07
AGUARDANDO_PRPCI,                    // Aprovado (vistoria definitiva) → vai para P08
AGUARDANDO_ACEITE_PRPCI,             // Aprovado (renovação) → aguarda aceite
AGUARDANDO_CIENCIA_CIV,              // Reprovado → aguarda ciência do cidadão
CIV                                  // Após ciência; aguardando correção/recurso
```

### 3.7 TipoMarco — marcos registrados em P07

```java
// Distribuição
DISTRIBUICAO_VISTORIA,               // Vistoria distribuída ao fiscal
AGENDAMENTO_PREVISTO_VISTORIA,       // Data prevista registrada

// Conclusão pelo fiscal
VISTORIA_APPCI,                      // Fiscal aprovou (vistoria definitiva)
VISTORIA_CIV,                        // Fiscal reprovou (vistoria definitiva)
VISTORIA_RENOVACAO,                  // Fiscal aprovou (renovação)
VISTORIA_RENOVACAO_CIV,              // Fiscal reprovou (renovação)

// Homologação pelo ADM
HOMOLOG_VISTORIA_DEFERIDO,           // ADM deferiu (aprovação definitiva)
HOMOLOG_VISTORIA_INDEFERIDO,         // ADM indeferiu (devolve para fiscal)
HOMOLOG_VISTORIA_RENOV_DEFERIDO,     // ADM deferiu renovação
HOMOLOG_VISTORIA_RENOV_INDEFERIDO,   // ADM indeferiu renovação

// Ciência dos documentos
CIENCIA_CIV,                         // Cidadão/RT tomou ciência do CIV
CIENCIA_CIV_RENOVACAO,               // Ciência do CIV de renovação
CIENCIA_APPCI                        // Cidadão/RT tomou ciência do APPCI
```

---

## 4. Entidades JPA (Entity Data Objects — ED)

### 4.1 VistoriaED

**Tabela:** `CBM_VISTORIA`
**Pacote:** `com.procergs.solcbm.ed`
**Auditoria:** `@Audited` (Hibernate Envers) → tabela `CBM_VISTORIA_AUD`

| Campo | Tipo Java | Coluna BD | Obrig. | Notas |
|---|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_VISTORIA_SEQ` | Sim | Gerado por sequência |
| `licenciamento` | `LicenciamentoED` | FK `ID_LICENCIAMENTO` | Sim | `@ManyToOne LAZY` |
| `numeroVistoria` | `Integer` | `NRO_VISTORIA` | Não | Sequencial por licenciamento |
| `status` | `StatusVistoria` | `STATUS` (VARCHAR) | Sim | `@Enumerated(STRING)` |
| `dthStatus` | `Calendar` | `DTH_STATUS` | Sim | Data/hora da última transição |
| `arquivo` | `ArquivoED` | FK `ID_ARQUIVO` | Não | Arquivo do documento (CIV ou APPCI) |
| `observacoes` | `TextoFormatadoED` | FK `ID_TEXTO_OBSERVACOES` | Não | Comunicações em CLOB |
| `dthSolicitacao` | `Calendar` | `DTH_SOLICITACAO` | Não | Data/hora de criação |
| `idUsuarioSoe` | `Long` | `ID_USUARIO_SOE` | Não | ID SOE do fiscal aprovador/reprovador |
| `nomeUsuarioSoe` | `String` (max 64) | `NM_USUARIO_SOE` | Não | Nome do fiscal |
| `idUsuarioSoeHomolog` | `Long` | `ID_USUARIO_SOE_HOMOLOG` | Não | ID SOE do ADM homologador |
| `nomeUsuarioSoeHomolog` | `String` (max 64) | `NM_USUARIO_SOE_HOMOLOG` | Não | Nome do ADM |
| `dthHomolog` | `Calendar` | `DTH_HOMOLOG` | Não | Data/hora da homologação |
| `indeferimentoHomolog` | `String` (max 4000) | `DSC_INDEFERI_HOMOLOG` | Não | Motivo do indeferimento |
| `dthRealizacaoVistoria` | `Calendar` | `DTH_REALIZACAO` | Não | Data efetiva da vistoria |
| `dthCiencia` | `Calendar` | `DTH_CIENCIA` | Não | Data/hora da ciência do CIV |
| `usuarioCiencia` | `UsuarioED` | FK `ID_USUARIO_CIENCIA` | Não | Usuário que fez ciência |
| `ciencia` | `Boolean` | `IND_CIENCIA` CHAR(1) S/N | Não | Indica ciência registrada |
| `tipoVistoria` | `TipoVistoria` | `TIPO_VISTORIA` (Integer) | Não | Tipo da vistoria |
| `idUsuarioAceitePrpci` | `Long` | `ID_USUARIO_ACEITE_PRPCI` | Não | Usuário que aceitou o PrPCI |
| `aceitePrpci` | `Boolean` | `IND_ACEITE_PRPCI` CHAR(1) S/N | Não | Indica aceite do PrPCI |
| `dthAceitePrpci` | `Calendar` | `DTH_ACEITE_PRPCI` | Não | Data/hora do aceite do PrPCI |
| `vistoriantes` | `Set<VistorianteED>` | — (`mappedBy="vistoria"`) | Não | Coleção de fiscais |
| `dthPrevistaVistoria` | `Calendar` | `DTH_PREVISTA` | Não | Data prevista agendada |
| `turnoPrevisto` | `TipoTurnoVistoria` | `TURNO_PREVISTO` (Integer) | Não | Turno previsto |
| `dthDistribuicao` | `Calendar` | `DTH_DISTRIBUICAO` | Não | Data/hora da distribuição |
| `appci` | `AppciED` | FK `ID_APPCI` | Não | APPCI gerado após aprovação |

**Named Queries:**
```java
@NamedQuery(
  name = "VistoriaED.consulta",
  query = "SELECT v FROM VistoriaED v "
        + "LEFT JOIN FETCH v.licenciamento l "
        + "LEFT JOIN FETCH v.arquivo a "
        + "LEFT JOIN FETCH v.observacoes o "
        + "WHERE v.id = :id"
)
```

**Interfaces implementadas:**
- `LicenciamentoCiencia` — suporte à operação de ciência (CIV)
- `Status<StatusVistoria>` — contrato para transições de status

### 4.2 LaudoVistoriaED

**Tabela:** `CBM_LAUDO_VISTORIA`
**Auditoria:** `@Audited` → `CBM_LAUDO_VISTORIA_AUD`

| Campo | Tipo Java | Coluna BD | Obrig. | Notas |
|---|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_LAUDO_VISTORIA_SEQ` | Sim | |
| `licenciamento` | `LicenciamentoED` | FK `ID_LICENCIAMENTO` | Sim | |
| `tpLaudo` | `TipoLaudo` | `TP_LAUDO` (VARCHAR) | Sim | `@Enumerated(STRING)` |
| `arquivo` | `ArquivoED` | FK `ID_ARQUIVO` | Não | Arquivo PDF do laudo |
| `artRrts` | `Set<ArquivoED>` | JoinTable `CBM_LAUDO_ART_RRT` | Não | ART/RRTs do responsável |
| `complementares` | `Set<ArquivoED>` | JoinTable `CBM_LAUDO_COMPLEMENTAR` | Não | Documentos complementares |
| `consolidado` | `Boolean` | `IND_CONSOLIDADO` CHAR(1) S/N | Não | Se o laudo está consolidado |
| `vistoria` | `VistoriaED` | FK `ID_VISTORIA` | Não | Associação à vistoria |
| `indRenovacao` | `Boolean` | `IND_RENOVACAO` CHAR(1) S/N | Não | Laudo de renovação |

**Tabelas associativas:**
```sql
CBM_LAUDO_ART_RRT      (ID_LAUDO FK → CBM_LAUDO_VISTORIA, ID_ARQUIVO FK → CBM_ARQUIVO)
CBM_LAUDO_COMPLEMENTAR (ID_LAUDO FK → CBM_LAUDO_VISTORIA, ID_ARQUIVO FK → CBM_ARQUIVO)
```

### 4.3 AppciED

**Tabela:** `CBM_APPCI`
**Auditoria:** `@Audited` → `CBM_APPCI_AUD`

| Campo | Tipo Java | Coluna BD | Obrig. | Notas |
|---|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_APPCI_SEQ` | Sim | |
| `arquivo` | `ArquivoED` | FK `ID_ARQUIVO` | Não | PDF do APPCI no Alfresco |
| `localizacao` | `LocalizacaoED` | FK `ID_LOCALIZACAO` | Não | Endereço do imóvel |
| `licenciamento` | `LicenciamentoED` | FK `ID_LICENCIAMENTO` | Sim | |
| `versao` | `Integer` | `VERSAO` | Sim | Versão sequencial por licenciamento |
| `dataHoraEmissao` | `Calendar` | `DTH_EMISSAO` | Sim | Data/hora de emissão |
| `dataValidade` | `Calendar` | `DATA_VALIDADE` | Sim | Data de validade (12 meses) |
| `indVersaoVigente` | `String` (max 1) | `IND_VERSAO_VIGENTE` | Não | 'S' = vigente / 'N' = supersedida |
| `dataVigenciaInicio` | `Calendar` | `DATA_VIGENCIA_INICIO` | Sim | Início da vigência |
| `dataVigenciaFim` | `Calendar` | `DATA_VIGENCIA_FIM` | Não | Fim da vigência |
| `dthCiencia` | `Calendar` | `DTH_CIENCIA` | Não | Data/hora da ciência do APPCI |
| `usuarioCiencia` | `UsuarioED` | FK `ID_USUARIO_CIENCIA` | Não | Usuário que tomou ciência |
| `ciencia` | `Boolean` | `IND_CIENCIA` CHAR(1) S/N | Não | Indicador de ciência |
| `indRenovacao` | `String` (max 1) | `IND_RENOVACAO` | Não | 'S' = APPCI de renovação |

**Interfaces implementadas:**
- `Appci` — domínio de APPCI
- `LicenciamentoCiencia` — suporte à ciência do APPCI

### 4.4 VistorianteED

**Tabela:** `CBM_VISTORIANTE`
**Auditoria:** `@Audited` → `CBM_VISTORIANTE_AUD`

| Campo | Tipo Java | Coluna BD | Obrig. | Notas |
|---|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_VISTORIANTE_SEQ` | Sim | |
| `vistoria` | `VistoriaED` | FK `ID_VISTORIA` | Sim | Vistoria à qual pertence |
| `idUsuarioSoe` | `Long` | `ID_USUARIO_SOE` | Sim | ID SOE do fiscal designado |

**Padrão Lombok:** `@Builder` — construção fluente:
```java
VistorianteED.builder()
    .vistoria(vistoria)
    .idUsuarioSoe(idSoe)
    .build();
```

### 4.5 ArquivoED (padrão de armazenamento Alfresco)

**Tabela:** `CBM_ARQUIVO`
**Auditoria:** `@Audited`

Entidade de referência usada por `VistoriaED.arquivo`, `LaudoVistoriaED.arquivo`, `AppciED.arquivo`, `LaudoVistoriaED.artRrts` e `LaudoVistoriaED.complementares`.

| Campo | Tipo Java | Coluna BD | Obrig. | Notas |
|---|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_ARQUIVO_SEQ` | Sim | |
| `nomeArquivo` | `String` (max 120) | `NM_ARQUIVO` | Não | Nome original do arquivo |
| `identificadorAlfresco` | `String` (max 150) | `ID_ALFRESCO` | Sim | NodeRef: `workspace://SpacesStore/{UUID}` |
| `md5SGM` | `String` | `HASH_MD5` | Não | Hash de integridade |
| `arquivoCache` | `ArquivoCacheED` | FK `ID_ARQUIVO_CACHE` | Não | Cache local |
| `tipoArquivo` | `TipoArquivo` | `TIPO_ARQUIVO` | Não | Enum do tipo |
| `codigoAutenticacao` | `String` | `CD_AUTENTICACAO` | Não | Código único de verificação |
| `inputStream` | `InputStream` | `@Transient` | Não | Usado apenas em I/O; nunca persiste |
| `idMigracaoAlfresco` | `String` (max 1) | `IND_MIGRACAO` | Não | Flag de migração |
| `dthMigracaoAlfresco` | `Calendar` | `DTH_MIGRACAO` | Não | Data da migração |

**Regra crítica:** O arquivo binário (bytes) **nunca** é armazenado no banco de dados relacional. O campo `identificadorAlfresco` contém o nodeRef do Alfresco que identifica o nó no repositório ECM. O campo `inputStream` (`@Transient`) é populado temporariamente durante upload/download e não é persistido.

### 4.6 TextoFormatadoED

**Tabela:** `CBM_TEXTO_FORMATADO`

| Campo | Tipo Java | Coluna BD | Notas |
|---|---|---|---|
| `id` | `Long` | PK — `CBM_ID_TEXTO_FORMATADO_SEQ` | |
| `txtClob` | `String` | `TXT_CLOB` (@Lob, NOT NULL) | Texto em formato CLOB — observações, comunicações |

---

## 5. Regras de Negócio (RN — EJB Stateless)

### 5.1 VistoriaRN

**Classe:** `com.procergs.solcbm.vistoria.VistoriaRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@Permissao(desabilitada = true)`, `@TransactionAttribute(SUPPORTS)`
**Herança:** `AppRN<VistoriaED, Long>`

**Métodos:**

| Método | Assinatura resumida | Descrição |
|---|---|---|
| `incluirPorLicenciamento` | `VistoriaED incluirPorLicenciamento(LicenciamentoED)` | Cria registro inicial de vistoria com `status = SOLICITADA` e `dthSolicitacao = now()` |
| `getProximoNumeroVistoria` | `Integer getProximoNumeroVistoria(Long idLicenciamento)` | Calcula `MAX(numeroVistoria) + 1` por licenciamento |
| `listarParaAcao` | `ListaPaginadaRetorno listarParaAcao(VistoriaPesqED)` | Lista vistorias com filtro e paginação (retorna `ItemListagemLicenciamentoVistoriaDTO`) |
| `avancarParaEmVistoria` | `void avancarParaEmVistoria(Long idLicenciamento)` | Transiciona `SOLICITADA → EM_VISTORIA`; seta `dthDistribuicao` |
| `consultaVigentePorLicenciamento` | `VistoriaED consultaVigentePorLicenciamento(Long)` | Retorna a vistoria ativa mais recente de um licenciamento |
| `consultaVistoriaPorLicenciamento` | `VistoriaED consultaVistoriaPorLicenciamento(Long)` | Idem — alternativa para uso em contextos de ciência |
| `populaDadosStatus` | `void populaDadosStatus(VistoriaED, StatusVistoria)` | Define `status` e `dthStatus = Calendar.getInstance()` |
| `altera` | `void altera(VistoriaED)` | Persiste alterações (`EntityManager.merge()`) |
| `consulta` | `VistoriaED consulta(Long id)` | Executa `VistoriaED.consulta` com fetch de licenciamento, arquivo e observações |

### 5.2 VistoriaConclusaoRN

**Classe:** `com.procergs.solcbm.vistoria.VistoriaConclusaoRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@TransactionAttribute(REQUIRED)`

#### 5.2.1 Método `aprova(VistoriaConclusaoDTO dto)`

**Permissão:** `@Permissao(objeto = "VISTORIA", acao = "VISTORIAR")`

**Pré-condições:**
- Vistoria em status `EM_VISTORIA` ou `EM_RASCUNHO`.
- `dto.dataVistoria` não pode ser nula (validado por `VistoriaConclusaoRNVal`).
- Laudo consolidado deve estar vinculado à vistoria.

**Ações executadas (em sequência transacional):**
1. Recupera vistoria pelo `dto.idVistoria`.
2. Registra o usuário SOE autenticado nos campos `idUsuarioSoe` e `nomeUsuarioSoe`.
3. Define `dthRealizacaoVistoria = dto.dataVistoria`.
4. Salva observações/comunicações (cria ou atualiza `TextoFormatadoED`).
5. Chama `VistorianteRN.incluirVistoriantes(dto.vistoriantes, vistoria)` — adiciona os fiscais presentes.
6. Define `status = EM_APROVACAO` e `dthStatus = now()`.
7. Registra marco:
   - `TipoMarco.VISTORIA_APPCI` — se vistoria ordinária.
   - `TipoMarco.VISTORIA_RENOVACAO` — se vistoria de renovação.
8. Conclui a nota/tarefa associada ao licenciamento.

**Saída:** Licenciamento permanece em `EM_VISTORIA` (apenas a vistoria muda para `EM_APROVACAO`); a transição do licenciamento ocorre somente na homologação.

#### 5.2.2 Método `reprova(VistoriaConclusaoDTO dto)`

**Permissão:** `@Permissao(objeto = "VISTORIA", acao = "VISTORIAR")`

**Pré-condições:**
- Vistoria em status `EM_VISTORIA` ou `EM_RASCUNHO`.
- `dto.dataVistoria` não pode ser nula.
- `dto.comunicacoes` (observações de inconformidade) obrigatórias.
- Laudo consolidado vinculado.

**Ações executadas:**
1. Recupera vistoria e registra dados do fiscal (`idUsuarioSoe`, `nomeUsuarioSoe`, `dthRealizacaoVistoria`).
2. Salva observações de inconformidade em `TextoFormatadoED`.
3. Chama `VistorianteRN.incluirVistoriantes()`.
4. Gera documento CIV via `VistoriaDocumentoCivRN.incluirArquivo(licenciamento, vistoria)`.
   - O arquivo PDF do CIV é armazenado no Alfresco; o `ArquivoED` resultante é associado a `vistoria.arquivo`.
5. Define `status = REPROVADO`.
6. Injeta `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoCienciaCivRN` via qualificador CDI e executa a transição:
   - Licenciamento: `EM_VISTORIA → AGUARDANDO_CIENCIA_CIV`.
   - Notificações disparadas: `notificarConclusaoVistoria()` ou `notificarConclusaoVistoriaRenovacao()`.
7. Define `recursoBloqueado = false` no licenciamento (permite interposição de recurso).
8. Registra marco `TipoMarco.VISTORIA_CIV` ou `VISTORIA_RENOVACAO_CIV`.
9. Conclui nota.

### 5.3 VistoriaHomologacaoAdmRN

**Classe:** `com.procergs.solcbm.vistoria.VistoriaHomologacaoAdmRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@TransactionAttribute(REQUIRED)`

#### 5.3.1 Método `defere(Long idVistoria)`

**Permissão:** `@Permissao(objeto = "VISTORIA", acao = "HOMOLOGAR")`

**Pré-condições:**
- Vistoria em status `EM_APROVACAO`.

**Ações executadas:**
1. Recupera vistoria; registra `idUsuarioSoeHomolog`, `nomeUsuarioSoeHomolog`, `dthHomolog = now()`.
2. Injeta `TrocaEstadoVistoriaEmAprovacaoParaAprovadoRN` (via `@TrocaEstadoVistoriaQualifier`) e executa:
   - `vistoria.status = APROVADO`.
3. Para vistoria **definitiva**:
   - Injeta `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpciRN` e executa:
     - `licenciamento.situacao = AGUARDANDO_PRPCI`.
4. Para vistoria de **renovação** (`TipoVistoria.VISTORIA_RENOVACAO`):
   - Injeta `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpciRN`:
     - `licenciamento.situacao = AGUARDANDO_ACEITE_PRPCI`.
5. Consulta APPCI anterior via `AppciRN.consultaUltimoAppci()` e associa ao licenciamento.
6. Chama `LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria(licenciamento)` — integração pesquisa de satisfação.
7. Registra marco `HOMOLOG_VISTORIA_DEFERIDO` (definitiva) ou `HOMOLOG_VISTORIA_RENOV_DEFERIDO` (renovação).
8. Conclui nota.

#### 5.3.2 Método `indefere(VistoriaIndeferimentoDTO dto)`

**Permissão:** `@Permissao(objeto = "VISTORIA", acao = "HOMOLOGAR")`

**Pré-condições:**
- Vistoria em status `EM_APROVACAO`.
- `dto.especificacao` (motivo do indeferimento) obrigatória.

**Ações executadas:**
1. Registra `vistoria.indeferimentoHomolog = dto.especificacao`.
2. Injeta `TrocaEstadoVistoriaEmAprovacaoParaEmVistoriaRN` e executa:
   - `vistoria.status = EM_VISTORIA`.
3. Registra marco `HOMOLOG_VISTORIA_INDEFERIDO` (definitiva) ou `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` (renovação).
4. Conclui nota.

**Efeito:** O licenciamento permanece em `EM_VISTORIA`; o fiscal deve refazer a conclusão.

### 5.4 LaudoVistoriaRN

**Classe:** `com.procergs.solcbm.laudovistoria.LaudoVistoriaRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@Permissao(desabilitada = true)`, `@TransactionAttribute(REQUIRED)`

#### 5.4.1 Método `incluirOuAlterarLaudo(LicenciamentoED, LaudoVistoriaDTO, List<Arquivo>)`

**Pré-condições:**
- Licenciamento em estado que permita upload de laudo (geralmente `EM_VISTORIA`).
- Tipo de laudo válido (um dos valores de `TipoLaudo`).

**Ações executadas:**
1. Verifica se já existe laudo do mesmo tipo para o licenciamento (inclui ou altera).
2. Para cada arquivo na lista, cria `ArquivoED` com o `inputStream` e chama `ArquivoRN.incluirArquivo()` — faz upload para o Alfresco e registra o `identificadorAlfresco`.
3. Define campo `consolidado = false` (o laudo consolidado é gerado automaticamente pelo sistema ao concluir a vistoria).
4. Determina `indRenovacao` conforme o tipo de vistoria vigente do licenciamento.
5. Persiste ou atualiza `LaudoVistoriaED`.

#### 5.4.2 Método `atualizaIdLaudoVistoria(LicenciamentoED)`

Associa os laudos mais recentes à última vistoria (`LaudoVistoriaED.vistoria = vistoriaAtual`). Remove laudos desnecessários em caso de vistoria parcial.

#### 5.4.3 Método `consultaPorLicenciamento(LicenciamentoED)`

Retorna lista de todos os `LaudoVistoriaED` do licenciamento para exibição no frontend.

### 5.5 LicenciamentoDistribuicaoVistoriaRN

**Classe:** `com.procergs.solcbm.licenciamentovistoria.listagem.LicenciamentoDistribuicaoVistoriaRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@TransactionAttribute(REQUIRED)`

#### 5.5.1 Método `distribuir(VistoriaOrdinariaDistribuicaoRequest request)`

**Permissão:** `@Permissao(objeto = "DISTRIBUICAOVISTORIA", acao = "DISTRIBUIR")`

**Pré-condições:**
- Lista `request.idLicenciamentos` não vazia.
- Cada licenciamento em `AGUARDA_DISTRIBUICAO_VISTORIA` ou `AGUARDANDO_DISTRIBUICAO_RENOV`.

**Ações executadas para cada licenciamento na lista:**
1. Verifica situação: lança exceção se não for distribuível.
2. Injeta `TrocaEstadoLicenciamentoAguardandoDistribuicaoVistoriaParaEmVistoriaRN` e executa:
   - Licenciamento: `AGUARDA_DISTRIBUICAO_VISTORIA → EM_VISTORIA` (ou `AGUARDANDO_DISTRIBUICAO_RENOV → EM_VISTORIA_RENOVACAO`).
3. Registra na vistoria:
   - `dthPrevistaVistoria = request.dataPrevista`.
   - `turnoPrevisto = request.turnoPrevisto`.
   - `dthDistribuicao = now()`.
4. Chama `VistorianteRN.incluirVistoriantesUsuarioLogado(vistoria)` — adiciona o ADM/distribuidor como vistoriante inicial.
5. Registra marco `DISTRIBUICAO_VISTORIA`.
6. Envia notificação por e-mail:
   - Template: `notificacao.email.template.distribuicaovistoria`
   - Destinatários: RT, RU, Proprietários do licenciamento
   - Conteúdo: dados do endereço, data prevista, turno.

### 5.6 VistorianteRN

**Classe:** `com.procergs.solcbm.vistoria.VistorianteRN`
**Anotações:** `@Stateless`, `@AppInterceptor`, `@Permissao(desabilitada = true)`, `@TransactionAttribute(SUPPORTS)`

| Método | Descrição |
|---|---|
| `incluirVistoriantes(List<UsuarioSoeDTO>, VistoriaED)` | Persiste cada usuário como `VistorianteED`; valida duplicatas; usado na conclusão (fiscal informa quem participou) |
| `removerVistoriantesAntigos(VistoriaED)` | Remove registros anteriores antes de re-incluir (atualização) |
| `incluirVistoriantesUsuarioLogado(VistoriaED)` | Adiciona o usuário autenticado como vistoriante; usado na distribuição |
| `getVistoriantesPorVistoria(Long idVistoria)` | Retorna `List<VistorianteED>` de uma vistoria |

### 5.7 AppciRN

**Classe:** `com.procergs.solcbm.appci.AppciRN`
**Anotações:** `@Stateless`, `@TransactionAttribute(REQUIRED)`

| Método | Descrição |
|---|---|
| `consultaUltimoAppci(Long idLicenciamento, Long idLocalizacao)` | Retorna o APPCI com `indVersaoVigente = 'S'` para o licenciamento e localização informados |
| Geração de versão | Incrementa `versao = MAX(versao) + 1` por licenciamento |
| Cálculo de validade | `dataValidade = dataHoraEmissao + 12 meses` (regra ITCBMRS) |

**Integração com `VistoriaDocumentoAppciRN`:**
- Após a homologação deferida (`VistoriaHomologacaoAdmRN.defere()`), `VistoriaDocumentoAppciRN.incluirArquivo()` gera o PDF do APPCI, armazena no Alfresco e cria o `AppciED` com `indVersaoVigente = 'S'`. A versão anterior (se existir) tem seu `indVersaoVigente` marcado como 'N'.

### 5.8 CivCienciaCidadaoRN

**Classe:** `com.procergs.solcbm.licenciamentociencia.vistoria.CivCienciaCidadaoRN`
**Anotações:** `@Stateless`, `@TransactionAttribute(REQUIRED)`
**Qualificador CDI:** `@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.CIV)`

Este componente implementa a interface `LicenciamentoCienciaRN` que define o padrão polimórfico de ciência em diferentes etapas do licenciamento.

| Método | Descrição |
|---|---|
| `alteraLicenciamentoCiencia(LicenciamentoCiencia)` | Persiste ciência do CIV: `vistoria.ciencia = true`, `dthCiencia = now()`, `usuarioCiencia = usuárioAutenticado` |
| `isLicenciamentoCienciaAprovado()` | Verifica se `vistoria.status == StatusVistoria.APROVADO` — não aplicável aqui, retorna `false` |
| `getTipoMarco()` | Retorna `CIENCIA_CIV` (vistoria definitiva) ou `CIENCIA_CIV_RENOVACAO` (renovação) conforme `tipoVistoria` |
| `getProximoStatusLicenciamentoCienciaReprovado()` | Retorna `SituacaoLicenciamento.CIV` — estado que o licenciamento assume após ciência do CIV |

**Fluxo de ciência:**
1. Cidadão/RT acessa o CIV no portal.
2. Confirma ciência.
3. `CivCienciaCidadaoRN.alteraLicenciamentoCiencia()` executa:
   - Persiste campos de ciência na vistoria.
   - Transiciona licenciamento `AGUARDANDO_CIENCIA_CIV → CIV`.
   - Registra marco `CIENCIA_CIV`.

### 5.9 VistoriaDocumentoCivRN e VistoriaDocumentoAppciRN

**Pacote:** `com.procergs.solcbm.vistoria.documento`

#### VistoriaDocumentoCivRN

```
incluirArquivo(LicenciamentoED licenciamento, VistoriaED vistoria)
  → Delega para DocumentoCivAutenticadoRN.gerar()
    → Gera PDF do CIV com dados do licenciamento e da vistoria
    → Chama ArquivoRN.gerarNumeroAutenticacao() → código único
    → Chama ArquivoRN.incluirArquivo(inputStream) → upload Alfresco
    → Retorna ArquivoED com identificadorAlfresco preenchido
  → Associa arquivo ao vistoria.arquivo
```

#### VistoriaDocumentoAppciRN

```
incluirArquivo(LicenciamentoED licenciamento, AppciED appci)
  → Delega para DocumentoAPPCIAutenticadoRN.gera()
    → Gera PDF do APPCI com dados do licenciamento, localização, validade
    → Chama ArquivoRN.gerarNumeroAutenticacao() → código único
    → Chama ArquivoRN.incluirArquivo(inputStream) → upload Alfresco
    → Retorna ArquivoED com identificadorAlfresco preenchido
  → Associa arquivo ao appci.arquivo
```

### 5.10 LicenciamentoIntegracaoLaiRN

**Classe:** `com.procergs.solcbm.licenciamentointegracaolai.LicenciamentoIntegracaoLaiRN`

#### Método `cadastrarDemandaUnicaVistoria(LicenciamentoED licenciamento)`

Chamado por `VistoriaHomologacaoAdmRN.defere()` após homologação deferida. Registra pesquisa de satisfação no sistema LAI estadual.

**Envolvidos notificados:**
- Responsáveis Técnicos (RT): assunto LAI `LAI_ASSUNTO_VISTORIA_RT`
- Responsáveis de Uso (RU) e Proprietários: assunto LAI `LAI_ASSUNTO_VISTORIA_OUTROS`

**Dados enviados ao LAI:**
- URL de avaliação (retorno do LAI)
- Número do licenciamento (PPCI)
- Endereço do imóvel
- Título padrão: `"SOLCBM - Pesquisa de Satisfação – [número] - Etapa Vistoria - [perfil]"`

---

## 6. Padrão de Transições de Estado (CDI Strategy)

### 6.1 Qualificador `@TrocaEstadoVistoriaQualifier`

Seleciona a implementação correta de transição de status da vistoria.

```java
@Qualifier
@Retention(RUNTIME)
@Target({FIELD, METHOD, PARAMETER, TYPE})
public @interface TrocaEstadoVistoriaQualifier {
    TrocaEstadoVistoriaEnum trocaEstado();
}
```

**Implementações usadas em P07:**

| Qualificador | Transição | Acionado por |
|---|---|---|
| `EM_APROVACAO_PARA_APROVADO` | `EM_APROVACAO → APROVADO` | `VistoriaHomologacaoAdmRN.defere()` |
| `EM_APROVACAO_PARA_EM_VISTORIA` | `EM_APROVACAO → EM_VISTORIA` | `VistoriaHomologacaoAdmRN.indefere()` |
| `EM_APROVACAO_RENOVACAO_PARA_APROVADO` | `EM_APROVACAO → APROVADO` (renovação) | `VistoriaHomologacaoAdmRN.defere()` — branch renovação |
| `EM_APROVACAO_RENOVACAO_PARA_EM_VISTORIA` | `EM_APROVACAO → EM_VISTORIA` (renovação) | `VistoriaHomologacaoAdmRN.indefere()` — branch renovação |

### 6.2 Qualificador `@TrocaEstadoLicenciamentoQualifier`

Seleciona a implementação correta de transição de situação do licenciamento.

**Implementações usadas em P07:**

| Classe de Implementação | De → Para | Acionado por |
|---|---|---|
| `TrocaEstadoLicenciamentoAguardandoDistribuicaoVistoriaParaEmVistoriaRN` | `AGUARDA_DISTRIBUICAO_VISTORIA → EM_VISTORIA` | `LicenciamentoDistribuicaoVistoriaRN.distribuir()` |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoCienciaCivRN` | `EM_VISTORIA → AGUARDANDO_CIENCIA_CIV` | `VistoriaConclusaoRN.reprova()` |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpciRN` | `EM_VISTORIA → AGUARDANDO_PRPCI` | `VistoriaHomologacaoAdmRN.defere()` (definitiva) |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpciRN` | `EM_VISTORIA → AGUARDANDO_ACEITE_PRPCI` | `VistoriaHomologacaoAdmRN.defere()` (renovação) |

### 6.3 Qualificador `@LicenciamentoCienciaQualifier`

Seleciona a implementação correta de ciência conforme o contexto.

```java
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.CIV)
// → Injeta CivCienciaCidadaoRN
```

---

## 7. API REST — Endpoints

### 7.1 AtualizaVistoriaAdmRestImpl

**Classe:** `com.procergs.solcbm.remote.adm.vistoria.AtualizaVistoriaAdmRestImpl`
**Anotações de classe:** `@Path("/adm/vistoria")`, `@SOEAuthRest`, `@Produces(APPLICATION_JSON)`, `@Consumes(APPLICATION_JSON)`

| Método HTTP | Path | Corpo de entrada | Retorno | RN invocada | Descrição |
|---|---|---|---|---|---|
| `PUT` | `/{idVistoria}/aprovar` | `VistoriaConclusaoRequest` | `Long` (idVistoria) | `VistoriaConclusaoRN.aprova()` | Fiscal conclui vistoria com aprovação; muda status → `EM_APROVACAO` |
| `PUT` | `/{idVistoria}/reprovar` | `VistoriaConclusaoRequest` | `Long` (idVistoria) | `VistoriaConclusaoRN.reprova()` | Fiscal conclui com reprovação; gera CIV; muda licenciamento → `AGUARDANDO_CIENCIA_CIV` |
| `PUT` | `/{idVistoria}/indeferir` | `VistoriaIndeferimentoRequest` | `Long` (idVistoria) | `VistoriaHomologacaoAdmRN.indefere()` | ADM indefere; devolve vistoria → `EM_VISTORIA` |
| `PUT` | `/{idVistoria}/deferir` | — (sem corpo) | `Long` (idVistoria) | `VistoriaHomologacaoAdmRN.defere()` | ADM defere; muda licenciamento → `AGUARDANDO_PRPCI` ou `AGUARDANDO_ACEITE_PRPCI`; gera APPCI; integra LAI |

**Conversores intermediários:**

- `VistoriaConclusaoRequestToDTOConverter` — converte `VistoriaConclusaoRequest` (string de data) → `VistoriaConclusaoDTO` (Calendar).
- `VistoriaIndeferimentoRequestToDTOConverter` — converte `VistoriaIndeferimentoRequest` → `VistoriaIndeferimentoDTO`.

### 7.2 ListaVistoriaRestImpl

**Classe:** `com.procergs.solcbm.remote.adm.vistoria.ListaVistoriaRestImpl`
**Anotações de classe:** `@Path("/adm/licenciamentos/vistorias")`, `@SOEAuthRest`

| Método HTTP | Path | Query params | Retorno | Filtro aplicado |
|---|---|---|---|---|
| `GET` | `/distribuidas` | `ordenar`, `ordem`, `paginaAtual`, `tamanho` | `ListaPaginadaRetorno<ItemListagemLicenciamentoVistoriaDTO>` | Licenciamentos em `AGUARDA_DISTRIBUICAO_VISTORIA` ou `AGUARDANDO_DISTRIBUICAO_RENOV` |
| `GET` | `/solicitadas` | Idem | `ListaPaginadaRetorno<ItemListagemLicenciamentoVistoriaDTO>` | Vistorias com status `SOLICITADA` ainda não distribuídas |
| `GET` | `/aprovadas` | Idem | `ListaPaginadaRetorno<ItemListagemLicenciamentoVistoriaDTO>` | Vistorias com status `EM_APROVACAO` aguardando homologação |

### 7.3 LicenciamentoDistribuicaoVistoriaRest

**Anotações de classe:** `@Path("/adm/distribuicao/vistoria")`, `@SOEAuthRest`

| Método HTTP | Path | Corpo de entrada | Retorno | RN invocada |
|---|---|---|---|---|
| `PUT` | `/distribuir` | `VistoriaOrdinariaDistribuicaoRequest` | HTTP 200 OK | `LicenciamentoDistribuicaoVistoriaRN.distribuir()` |

### 7.4 Endpoints do cidadão/RT (LicenciamentoVistoriaRest)

Baseado nos campos do DTO `LicenciamentoVistoriaDTO` e nos métodos identificados:

| Método HTTP | Path | Descrição |
|---|---|---|
| `GET` | `/licenciamento-vistoria/{idLic}` | Retorna `LicenciamentoVistoriaDTO` com vistoria vigente, laudos e situação |
| `PUT` | `/licenciamento-vistoria/{idLic}/laudo` (multipart) | Upload de laudo técnico (principal + ART/RRT + complementares); chama `LaudoVistoriaRN.incluirOuAlterarLaudo()` |
| `PUT` | `/licenciamento-vistoria/{idLic}/termo/{idVistoria}` | Ciência do cidadão/RT sobre data prevista; chama `CivCienciaCidadaoRN.alteraLicenciamentoCiencia()` (ou equivalente de ciência genérica) |

---

## 8. DTOs (Data Transfer Objects)

### 8.1 VistoriaConclusaoRequest (entrada REST)

```java
// Pacote: com.procergs.solcbm.remote.ed
public class VistoriaConclusaoRequest {
    private Long idVistoria;
    private TextoFormatado comunicacoes;   // Observações de inconformidade ou aprovação
    private String dataVistoria;           // Data em formato string → convertida para Calendar
    private List<UsuarioSoeDTO> vistoriantes; // Fiscais presentes na vistoria
}
```

### 8.2 VistoriaConclusaoDTO (uso interno entre camadas REST → RN)

```java
public class VistoriaConclusaoDTO {
    private Long idVistoria;
    private TextoFormatado comunicacoes;
    private Calendar dataVistoria;         // Já convertido para Calendar
    private List<UsuarioSoeDTO> vistoriantes;
}
```

### 8.3 VistoriaIndeferimentoRequest (entrada REST)

```java
public class VistoriaIndeferimentoRequest {
    private Long idVistoria;
    private String especificacao;          // Motivo do indeferimento pelo ADM
}
```

### 8.4 VistoriaIndeferimentoDTO (uso interno)

```java
public class VistoriaIndeferimentoDTO {
    private Long idVistoria;
    private String especificacao;
}
```

### 8.5 VistoriaOrdinariaDistribuicaoRequest (entrada REST — distribuição)

```java
public class VistoriaOrdinariaDistribuicaoRequest {
    private List<Long> idLicenciamentos;   // IDs dos licenciamentos a distribuir em lote
    private Calendar dataPrevista;         // Data prevista para realização
    private TipoTurnoVistoria turnoPrevisto; // MANHA, TARDE, NOITE ou INTEGRAL
}
```

### 8.6 LicenciamentoVistoriaDTO (retorno de consulta)

```java
public class LicenciamentoVistoriaDTO {
    private Long id;                           // ID da vistoria
    private List<ResponsavelTecnico> rts;      // Responsáveis técnicos do licenciamento
    private List<LaudoVistoriaDTO> laudos;     // Laudos anexados
    private StatusVistoria status;             // Status atual da vistoria
    private List<BoletoLicenciamento> boletos; // Boletos de pagamento
    private SituacaoLicenciamento situacaoLicenciamento;
    private TipoVistoria tipo;                 // Tipo da vistoria
    private Boolean possuiRecursoPendente;     // Se há recurso em análise
}
```

### 8.7 LaudoVistoriaDTO

```java
public class LaudoVistoriaDTO {
    private Long id;
    private TipoLaudo tipo;
    private Arquivo arquivo;               // Arquivo principal do laudo
    private List<Arquivo> artRrts;         // ART/RRTs
    private List<Arquivo> complementares;  // Documentos complementares
}
```

### 8.8 ItemListagemLicenciamentoVistoriaDTO (listagem paginada ADM)

Retornado pelas listagens de vistorias solicitadas, distribuídas e aprovadas:
```java
public class ItemListagemLicenciamentoVistoriaDTO {
    private Long idLicenciamento;
    private String numeroPpci;
    private String enderecoEstabelecimento;
    private SituacaoLicenciamento situacao;
    private StatusVistoria statusVistoria;
    private Calendar dthDistribuicao;
    private Calendar dthPrevistaVistoria;
    private TipoTurnoVistoria turnoPrevisto;
    private TipoVistoria tipoVistoria;
}
```

---

## 9. Segurança

### 9.1 Autenticação — `@SOEAuthRest`

Todos os endpoints REST do P07 são protegidos pela anotação `@SOEAuthRest`, que intercepta cada requisição e valida o token OAuth2/OIDC emitido pelo **SOE PROCERGS** (IdP estadual — portal meu.rs.gov.br). O usuário autenticado é disponibilizado via `UsuarioSoeLogadoProducer`, que disponibiliza o `UsuarioSoe` no contexto CDI para uso nas RNs.

### 9.2 Autorização — `@Permissao`

O interceptor `@AppInterceptor` aplica verificação de permissões antes de cada método anotado com `@Permissao`.

| Objeto | Ação | Método protegido | Quem executa |
|---|---|---|---|
| `VISTORIA` | `VISTORIAR` | `VistoriaConclusaoRN.aprova()` e `reprova()` | Fiscal CBM-RS |
| `VISTORIA` | `HOMOLOGAR` | `VistoriaHomologacaoAdmRN.defere()` e `indefere()` | ADM CBM-RS |
| `DISTRIBUICAOVISTORIA` | `DISTRIBUIR` | `LicenciamentoDistribuicaoVistoriaRN.distribuir()` | ADM CBM-RS |

Os demais métodos das RNs que atuam em P07 são chamados com `@Permissao(desabilitada = true)` — não exigem verificação de permissão específica (apenas autenticação SOE é suficiente, ou são chamados internamente por outras RNs).

### 9.3 `@AutorizaEnvolvido` e `SegurancaEnvolvidoInterceptor`

Para operações executadas pelo cidadão/RT (ciência do CIV, consulta de vistoria), o sistema valida via `@AutorizaEnvolvido` que o usuário autenticado está vinculado ao licenciamento como RT ou RU antes de permitir a operação.

---

## 10. Integração com Alfresco

Todos os documentos binários gerados ou anexados no P07 são armazenados no Alfresco ECM. O banco de dados relacional armazena apenas referências (nodeRef).

### 10.1 Documentos armazenados no P07

| Documento | Campo em ED | Quem gera | Quando |
|---|---|---|---|
| CIV (PDF) | `VistoriaED.arquivo` | `VistoriaDocumentoCivRN.incluirArquivo()` | Na reprovação pelo fiscal |
| APPCI (PDF) | `AppciED.arquivo` | `VistoriaDocumentoAppciRN.incluirArquivo()` | Na homologação deferida |
| Laudo técnico (PDF) | `LaudoVistoriaED.arquivo` | `LaudoVistoriaRN.incluirOuAlterarLaudo()` | Upload pelo fiscal |
| ART/RRT (PDF) | `LaudoVistoriaED.artRrts` | Idem | Upload pelo fiscal |
| Documentos complementares | `LaudoVistoriaED.complementares` | Idem | Upload pelo fiscal |

### 10.2 Padrão de persistência de arquivo

```
1. Receber arquivo (inputStream) na camada REST (multipart/form-data)
2. Criar ArquivoED com nomeArquivo e inputStream preenchidos
3. Chamar ArquivoRN.incluirArquivo(arquivoED)
   → Faz upload do inputStream para Alfresco
   → Obtém o nodeRef retornado pelo Alfresco
   → Persiste ArquivoED com identificadorAlfresco = nodeRef
   → inputStream é descartado (campo @Transient)
4. Associar ArquivoED persistido à entidade destino
   (VistoriaED.arquivo, LaudoVistoriaED.arquivo, etc.)
```

### 10.3 Formato do identificadorAlfresco

```
workspace://SpacesStore/{UUID}
Exemplo: workspace://SpacesStore/3f7a2b91-e4c0-4a8d-b235-9d1c47f803aa
```

---

## 11. Notificações por E-mail

As notificações são disparadas pela classe `LicenciamentoAdmNotificacaoRN` e pelos métodos internos das classes de TrocaEstado.

| Evento | Método de notificação | Destinatários |
|---|---|---|
| Distribuição da vistoria | Template `distribuicaovistoria` | RT, RU, Proprietários |
| Reprovação (CIV emitido) | `notificarConclusaoVistoria()` | RT, RU, Proprietários |
| Reprovação de renovação | `notificarConclusaoVistoriaRenovacao()` | RT, RU, Proprietários |
| Pesquisa de satisfação (após deferimento) | `cadastrarDemandaUnicaVistoria()` via LAI | RT (assunto `LAI_ASSUNTO_VISTORIA_RT`), RU/Proprietários (assunto `LAI_ASSUNTO_VISTORIA_OUTROS`) |

---

## 12. Máquinas de Estado

### 12.1 StatusVistoria — diagrama de transições

```
               [VistoriaRN.incluirPorLicenciamento()]
                             │
                             ▼
                        SOLICITADA
                             │
                             │ [LicenciamentoDistribuicaoVistoriaRN.distribuir()]
                             ▼
                        EM_VISTORIA ◄────────────────────────────────────────────────┐
                             │                                                        │
                             │ [Fiscal salva parcialmente]                           │ [VistoriaHomologacaoAdmRN
                             ├────────────────────────────►  EM_RASCUNHO             │  .indefere()]
                             │                                     │                 │
                             │◄────────────────────────────────────┘                 │
                             │                                                        │
                             │ [VistoriaConclusaoRN.aprova()]                        │
                             ├────────────────────────────►  EM_APROVACAO ──────────►┘
                             │                                     │
                             │                                     │ [VistoriaHomologacaoAdmRN.defere()]
                             │                                     ▼
                             │                                APROVADO
                             │
                             │ [VistoriaConclusaoRN.reprova()]
                             └────────────────────────────►  REPROVADO
                                                               (CIV gerado)
```

### 12.2 SituacaoLicenciamento — transições em P07

```
AGUARDA_DISTRIBUICAO_VISTORIA
    │
    └──► [distribuir()] ──────────────────► EM_VISTORIA
                                                │
                            ┌───────────────────┼───────────────────────┐
                            │                   │                       │
              [reprova()]   │       [defere()]  │     [defere() renov.] │
                            ▼                   ▼                       ▼
               AGUARDANDO_CIENCIA_CIV  AGUARDANDO_PRPCI   AGUARDANDO_ACEITE_PRPCI
                            │
                  [ciência] │
                            ▼
                           CIV

AGUARDANDO_DISTRIBUICAO_RENOV
    │
    └──► [distribuir()] ──► EM_VISTORIA_RENOVACAO
                                (mesmo fluxo acima com marcos de renovação)
```

### 12.3 Tabela de marcos por evento

| Evento | Marco registrado | Classe responsável |
|---|---|---|
| Distribuição de fiscal | `DISTRIBUICAO_VISTORIA` | `LicenciamentoDistribuicaoVistoriaRN` |
| Fiscal conclui (aprovação definitiva) | `VISTORIA_APPCI` | `VistoriaConclusaoRN.aprova()` |
| Fiscal conclui (reprovação definitiva) | `VISTORIA_CIV` | `VistoriaConclusaoRN.reprova()` |
| Fiscal conclui (aprovação renovação) | `VISTORIA_RENOVACAO` | `VistoriaConclusaoRN.aprova()` |
| Fiscal conclui (reprovação renovação) | `VISTORIA_RENOVACAO_CIV` | `VistoriaConclusaoRN.reprova()` |
| ADM defere homologação (definitiva) | `HOMOLOG_VISTORIA_DEFERIDO` | `VistoriaHomologacaoAdmRN.defere()` |
| ADM indefere homologação (definitiva) | `HOMOLOG_VISTORIA_INDEFERIDO` | `VistoriaHomologacaoAdmRN.indefere()` |
| ADM defere homologação (renovação) | `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | `VistoriaHomologacaoAdmRN.defere()` |
| ADM indefere homologação (renovação) | `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` | `VistoriaHomologacaoAdmRN.indefere()` |
| Cidadão toma ciência do CIV | `CIENCIA_CIV` | `CivCienciaCidadaoRN` |
| Cidadão toma ciência do CIV (renovação) | `CIENCIA_CIV_RENOVACAO` | `CivCienciaCidadaoRN` |
| Cidadão toma ciência do APPCI | `CIENCIA_APPCI` | RN de ciência do APPCI |

---

## 13. Auditoria — Hibernate Envers

As entidades principais do P07 são anotadas com `@Audited` (Hibernate Envers), gerando tabelas de histórico automaticamente:

| Entidade | Tabela principal | Tabela de auditoria |
|---|---|---|
| `VistoriaED` | `CBM_VISTORIA` | `CBM_VISTORIA_AUD` |
| `LaudoVistoriaED` | `CBM_LAUDO_VISTORIA` | `CBM_LAUDO_VISTORIA_AUD` |
| `AppciED` | `CBM_APPCI` | `CBM_APPCI_AUD` |
| `VistorianteED` | `CBM_VISTORIANTE` | `CBM_VISTORIANTE_AUD` |
| `ArquivoED` | `CBM_ARQUIVO` | `CBM_ARQUIVO_AUD` |

As tabelas `_AUD` armazenam cada versão do registro com os campos `REV` (revisão), `REVTYPE` (0=INSERT, 1=UPDATE, 2=DELETE) e todos os campos da entidade conforme o estado no momento da operação.

---

## 14. DDL (Esquema de Banco de Dados)

```sql
-- Sequências
CREATE SEQUENCE CBM_ID_VISTORIA_SEQ       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CBM_ID_LAUDO_VISTORIA_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CBM_ID_APPCI_SEQ          START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CBM_ID_VISTORIANTE_SEQ    START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CBM_ID_ARQUIVO_SEQ        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CBM_ID_TEXTO_FORMATADO_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- Tabela de Arquivo (nodeRef Alfresco)
CREATE TABLE CBM_ARQUIVO (
    ID                    NUMBER(19)    NOT NULL,
    NM_ARQUIVO            VARCHAR2(120),
    ID_ALFRESCO           VARCHAR2(150) NOT NULL,  -- nodeRef workspace://SpacesStore/{UUID}
    HASH_MD5              VARCHAR2(64),
    ID_ARQUIVO_CACHE      NUMBER(19),
    TIPO_ARQUIVO          VARCHAR2(50),
    CD_AUTENTICACAO       VARCHAR2(100),
    IND_MIGRACAO          CHAR(1),
    DTH_MIGRACAO          TIMESTAMP,
    CONSTRAINT PK_CBM_ARQUIVO PRIMARY KEY (ID)
);

-- Tabela de Texto Formatado (CLOB)
CREATE TABLE CBM_TEXTO_FORMATADO (
    ID       NUMBER(19)    NOT NULL,
    TXT_CLOB CLOB          NOT NULL,
    CONSTRAINT PK_CBM_TEXTO_FORMATADO PRIMARY KEY (ID)
);

-- Tabela principal de Vistoria
CREATE TABLE CBM_VISTORIA (
    ID                       NUMBER(19)     NOT NULL,
    ID_LICENCIAMENTO         NUMBER(19)     NOT NULL,
    NRO_VISTORIA             NUMBER(5),
    STATUS                   VARCHAR2(30)   NOT NULL,
    DTH_STATUS               TIMESTAMP      NOT NULL,
    ID_ARQUIVO               NUMBER(19),                  -- CIV ou último APPCI do ciclo
    ID_TEXTO_OBSERVACOES     NUMBER(19),
    DTH_SOLICITACAO          TIMESTAMP,
    ID_USUARIO_SOE           NUMBER(19),
    NM_USUARIO_SOE           VARCHAR2(64),
    ID_USUARIO_SOE_HOMOLOG   NUMBER(19),
    NM_USUARIO_SOE_HOMOLOG   VARCHAR2(64),
    DTH_HOMOLOG              TIMESTAMP,
    DSC_INDEFERI_HOMOLOG     VARCHAR2(4000),
    DTH_REALIZACAO           TIMESTAMP,
    DTH_CIENCIA              TIMESTAMP,
    ID_USUARIO_CIENCIA       NUMBER(19),
    IND_CIENCIA              CHAR(1)        CHECK (IND_CIENCIA IN ('S','N')),
    TIPO_VISTORIA            NUMBER(2),
    ID_USUARIO_ACEITE_PRPCI  NUMBER(19),
    IND_ACEITE_PRPCI         CHAR(1)        CHECK (IND_ACEITE_PRPCI IN ('S','N')),
    DTH_ACEITE_PRPCI         TIMESTAMP,
    DTH_PREVISTA             TIMESTAMP,
    TURNO_PREVISTO           NUMBER(1),
    DTH_DISTRIBUICAO         TIMESTAMP,
    ID_APPCI                 NUMBER(19),
    CONSTRAINT PK_CBM_VISTORIA PRIMARY KEY (ID),
    CONSTRAINT FK_VISTORIA_LICENCIAMENTO
        FOREIGN KEY (ID_LICENCIAMENTO) REFERENCES CBM_LICENCIAMENTO(ID),
    CONSTRAINT FK_VISTORIA_ARQUIVO
        FOREIGN KEY (ID_ARQUIVO) REFERENCES CBM_ARQUIVO(ID),
    CONSTRAINT FK_VISTORIA_TEXTO
        FOREIGN KEY (ID_TEXTO_OBSERVACOES) REFERENCES CBM_TEXTO_FORMATADO(ID),
    CONSTRAINT FK_VISTORIA_APPCI
        FOREIGN KEY (ID_APPCI) REFERENCES CBM_APPCI(ID)
);

-- Tabela de Vistoriantes
CREATE TABLE CBM_VISTORIANTE (
    ID              NUMBER(19)  NOT NULL,
    ID_VISTORIA     NUMBER(19)  NOT NULL,
    ID_USUARIO_SOE  NUMBER(19)  NOT NULL,
    CONSTRAINT PK_CBM_VISTORIANTE PRIMARY KEY (ID),
    CONSTRAINT FK_VISTORIANTE_VISTORIA
        FOREIGN KEY (ID_VISTORIA) REFERENCES CBM_VISTORIA(ID)
);

-- Tabela de Laudo de Vistoria
CREATE TABLE CBM_LAUDO_VISTORIA (
    ID               NUMBER(19)  NOT NULL,
    ID_LICENCIAMENTO NUMBER(19)  NOT NULL,
    TP_LAUDO         VARCHAR2(50) NOT NULL,
    ID_ARQUIVO       NUMBER(19),
    IND_CONSOLIDADO  CHAR(1)     CHECK (IND_CONSOLIDADO IN ('S','N')),
    ID_VISTORIA      NUMBER(19),
    IND_RENOVACAO    CHAR(1)     CHECK (IND_RENOVACAO IN ('S','N')),
    CONSTRAINT PK_CBM_LAUDO_VISTORIA PRIMARY KEY (ID),
    CONSTRAINT FK_LAUDO_LICENCIAMENTO
        FOREIGN KEY (ID_LICENCIAMENTO) REFERENCES CBM_LICENCIAMENTO(ID),
    CONSTRAINT FK_LAUDO_ARQUIVO
        FOREIGN KEY (ID_ARQUIVO) REFERENCES CBM_ARQUIVO(ID),
    CONSTRAINT FK_LAUDO_VISTORIA
        FOREIGN KEY (ID_VISTORIA) REFERENCES CBM_VISTORIA(ID)
);

-- Tabelas associativas de Laudo
CREATE TABLE CBM_LAUDO_ART_RRT (
    ID_LAUDO    NUMBER(19) NOT NULL,
    ID_ARQUIVO  NUMBER(19) NOT NULL,
    CONSTRAINT PK_CBM_LAUDO_ART_RRT PRIMARY KEY (ID_LAUDO, ID_ARQUIVO),
    CONSTRAINT FK_LAUDO_ART_LAUDO
        FOREIGN KEY (ID_LAUDO) REFERENCES CBM_LAUDO_VISTORIA(ID),
    CONSTRAINT FK_LAUDO_ART_ARQUIVO
        FOREIGN KEY (ID_ARQUIVO) REFERENCES CBM_ARQUIVO(ID)
);

CREATE TABLE CBM_LAUDO_COMPLEMENTAR (
    ID_LAUDO    NUMBER(19) NOT NULL,
    ID_ARQUIVO  NUMBER(19) NOT NULL,
    CONSTRAINT PK_CBM_LAUDO_COMPLEMENTAR PRIMARY KEY (ID_LAUDO, ID_ARQUIVO),
    CONSTRAINT FK_LAUDO_COMP_LAUDO
        FOREIGN KEY (ID_LAUDO) REFERENCES CBM_LAUDO_VISTORIA(ID),
    CONSTRAINT FK_LAUDO_COMP_ARQUIVO
        FOREIGN KEY (ID_ARQUIVO) REFERENCES CBM_ARQUIVO(ID)
);

-- Tabela de APPCI
CREATE TABLE CBM_APPCI (
    ID                   NUMBER(19)   NOT NULL,
    ID_ARQUIVO           NUMBER(19),
    ID_LOCALIZACAO       NUMBER(19),
    ID_LICENCIAMENTO     NUMBER(19)   NOT NULL,
    VERSAO               NUMBER(5)    NOT NULL,
    DTH_EMISSAO          TIMESTAMP    NOT NULL,
    DATA_VALIDADE        DATE         NOT NULL,
    IND_VERSAO_VIGENTE   CHAR(1)      CHECK (IND_VERSAO_VIGENTE IN ('S','N')),
    DATA_VIGENCIA_INICIO DATE         NOT NULL,
    DATA_VIGENCIA_FIM    DATE,
    DTH_CIENCIA          TIMESTAMP,
    ID_USUARIO_CIENCIA   NUMBER(19),
    IND_CIENCIA          CHAR(1)      CHECK (IND_CIENCIA IN ('S','N')),
    IND_RENOVACAO        CHAR(1)      CHECK (IND_RENOVACAO IN ('S','N')),
    CONSTRAINT PK_CBM_APPCI PRIMARY KEY (ID),
    CONSTRAINT FK_APPCI_ARQUIVO
        FOREIGN KEY (ID_ARQUIVO) REFERENCES CBM_ARQUIVO(ID),
    CONSTRAINT FK_APPCI_LICENCIAMENTO
        FOREIGN KEY (ID_LICENCIAMENTO) REFERENCES CBM_LICENCIAMENTO(ID)
);

-- Tabelas de auditoria (geradas automaticamente pelo Hibernate Envers)
-- CBM_VISTORIA_AUD       — histórico de CBM_VISTORIA
-- CBM_LAUDO_VISTORIA_AUD — histórico de CBM_LAUDO_VISTORIA
-- CBM_APPCI_AUD          — histórico de CBM_APPCI
-- CBM_VISTORIANTE_AUD    — histórico de CBM_VISTORIANTE
-- CBM_ARQUIVO_AUD        — histórico de CBM_ARQUIVO
-- (campos: REV NUMBER, REVTYPE NUMBER(1), + campos da entidade)

-- Índices de performance
CREATE INDEX IDX_VISTORIA_LICENCIAMENTO  ON CBM_VISTORIA(ID_LICENCIAMENTO);
CREATE INDEX IDX_VISTORIA_STATUS         ON CBM_VISTORIA(STATUS);
CREATE INDEX IDX_VISTORIANTE_VISTORIA    ON CBM_VISTORIANTE(ID_VISTORIA);
CREATE INDEX IDX_LAUDO_LICENCIAMENTO     ON CBM_LAUDO_VISTORIA(ID_LICENCIAMENTO);
CREATE INDEX IDX_LAUDO_VISTORIA          ON CBM_LAUDO_VISTORIA(ID_VISTORIA);
CREATE INDEX IDX_APPCI_LICENCIAMENTO     ON CBM_APPCI(ID_LICENCIAMENTO);
CREATE INDEX IDX_APPCI_VIGENTE           ON CBM_APPCI(ID_LICENCIAMENTO, IND_VERSAO_VIGENTE);
```

---

## 15. Resumo de Referências Cruzadas

### 15.1 Fluxo completo — vistoria ordinária aprovada

```
1. LicenciamentoDistribuicaoVistoriaRN.distribuir()
   PUT /adm/distribuicao/vistoria/distribuir
   [VistoriaED status: SOLICITADA → EM_VISTORIA]
   [LicenciamentoED: AGUARDA_DISTRIBUICAO_VISTORIA → EM_VISTORIA]
   [Marco: DISTRIBUICAO_VISTORIA]
   [VistorianteED criado com usuário distribuidor]
   [Notificação e-mail: RT + RU + Proprietários]

2. LaudoVistoriaRN.incluirOuAlterarLaudo()
   PUT /licenciamento-vistoria/{idLic}/laudo (multipart)
   [LaudoVistoriaED criado + upload Alfresco]
   [Nenhuma transição de estado]

3. VistoriaConclusaoRN.aprova()
   PUT /adm/vistoria/{idVistoria}/aprovar
   [VistoriaED status: EM_VISTORIA → EM_APROVACAO]
   [idUsuarioSoe, nomeUsuarioSoe, dthRealizacaoVistoria registrados]
   [VistorianteED atualizado com fiscais presentes]
   [Marco: VISTORIA_APPCI]
   [LicenciamentoED permanece: EM_VISTORIA]

4. VistoriaHomologacaoAdmRN.defere()
   PUT /adm/vistoria/{idVistoria}/deferir
   [VistoriaED status: EM_APROVACAO → APROVADO]
   [LicenciamentoED: EM_VISTORIA → AGUARDANDO_PRPCI]
   [AppciED criado; VistoriaDocumentoAppciRN gera PDF → Alfresco]
   [Marco: HOMOLOG_VISTORIA_DEFERIDO]
   [LicenciamentoIntegracaoLaiRN.cadastrarDemandaUnicaVistoria()]
   [VistoriaED.appci = novo AppciED]
```

### 15.2 Fluxo completo — vistoria ordinária reprovada

```
1. LicenciamentoDistribuicaoVistoriaRN.distribuir()
   (idem aprovação)

2. LaudoVistoriaRN.incluirOuAlterarLaudo()
   (idem aprovação)

3. VistoriaConclusaoRN.reprova()
   PUT /adm/vistoria/{idVistoria}/reprovar
   [VistoriaED status: EM_VISTORIA → REPROVADO]
   [VistoriaDocumentoCivRN.incluirArquivo() → CIV gerado e salvo no Alfresco]
   [VistoriaED.arquivo = ArquivoED do CIV]
   [LicenciamentoED: EM_VISTORIA → AGUARDANDO_CIENCIA_CIV]
   [Marco: VISTORIA_CIV]
   [Notificação e-mail conclusão de vistoria]

4. CivCienciaCidadaoRN.alteraLicenciamentoCiencia()
   (cidadão/RT confirma ciência no portal)
   [VistoriaED.ciencia = true; dthCiencia = now()]
   [LicenciamentoED: AGUARDANDO_CIENCIA_CIV → CIV]
   [Marco: CIENCIA_CIV]
```

### 15.3 Fluxo — indeferimento na homologação (volta para fiscal)

```
1–3. (distribuição, laudo, conclusão com aprovação — idem acima)

4. VistoriaHomologacaoAdmRN.indefere()
   PUT /adm/vistoria/{idVistoria}/indeferir
   [VistoriaED.indeferimentoHomolog = motivo]
   [VistoriaED status: EM_APROVACAO → EM_VISTORIA]
   [LicenciamentoED permanece: EM_VISTORIA]
   [Marco: HOMOLOG_VISTORIA_INDEFERIDO]

5. Fiscal revisa e reconclui:
   → VistoriaConclusaoRN.aprova() ou reprova() novamente
```

---

## 16. Regras de Negócio Normativas — RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª Ed/2022

As regras a seguir complementam as RNs originais do processo P07 com base nas normas vigentes. Não substituem nenhuma regra já documentada.

---

### RN-P07-N1: Laudos Técnicos Obrigatórios para Solicitação de Vistoria

**Referência normativa:** item 6.4.3 da RT de Implantação SOL-CBMRS 4ª Ed/2022; Anexo "L" da RTCBMRS N.º 05 Parte 1.1/2016.

O wizard de solicitação de vistoria deve exigir o upload dos laudos técnicos obrigatórios, conforme tipologia e ocupação da edificação. Os laudos previstos no Anexo "L" são:

| Código | Descrição |
|---|---|
| M.1 | Laudo Técnico de Compartimentação Horizontal e/ou Vertical |
| M.2 | Laudo Técnico de Isolamento de Riscos |
| M.3 | Laudo Técnico de Segurança Estrutural em Incêndio |
| M.4 | Laudo Técnico de Controle de Materiais de Acabamento e Revestimento |
| M.5 | Laudo Técnico de Equipamentos de Utilização de Público |

**Comportamento do sistema:**

- O sistema determina automaticamente quais laudos são obrigatórios com base no tipo de edificação e na ocupação registrados no PPCI.
- O botão "Solicitar Vistoria" permanece desabilitado enquanto houver laudo obrigatório pendente de upload.
- Cada laudo enviado recebe registro de data/hora e identificador do RT que realizou o upload.
- Laudos facultativos podem ser incluídos opcionalmente pelo RT, sem bloqueio de fluxo.

**Impacto nos dados:** novos registros na tabela de documentos vinculados ao licenciamento, com campo `tp_laudo` discriminando o código M.1 a M.5 e o campo `obrigatorio` calculado por regra de negócio.

---

### RN-P07-N2: Termo de Responsabilidade das Saídas de Emergência (Anexo D)

**Referência normativa:** item 6.4.4 da RT de Implantação SOL-CBMRS 4ª Ed/2022; Anexo D da RTCBMRS N.º 11 Parte 01/2016.

Durante a solicitação de vistoria, o sistema deve apresentar ao RT a seguinte pergunta obrigatória:

> "A edificação possui portas de correr, enrolar ou gradil de segurança patrimonial localizadas junto à porta final da saída de emergência?"

**Respostas e consequências:**

| Resposta | Ação do sistema |
|---|---|
| **NÃO** | Prossegue para a etapa seguinte normalmente. |
| **SIM** | Exibe o Termo de Responsabilidade das Saídas de Emergência (Anexo D da RTCBMRS N.º 11 Parte 01/2016) em tela. O RT deve aceitar digitalmente o termo para prosseguir. Sem aceite, o botão "Solicitar Vistoria" permanece desabilitado. |

**Impacto nos dados:** campos `ind_possui_porta_correr_emergencia`, `ind_aceite_anexo_d` e `dt_aceite_anexo_d` registrados na entidade de vistoria (tabela `sol.vistoria`).

---

### RN-P07-N3: Prazo para Solicitar Re-vistoria após CIV

**Referência normativa:** item 6.4.8.1 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

Após a emissão do CIV (estado `CIV`), o RT deve protocolar a solicitação de nova vistoria em até **30 (trinta) dias corridos**.

**Comportamento do sistema:**

- O prazo é calculado a partir da data de ciência do CIV registrada em `VistoriaED.dthCiencia`.
- O sistema envia lembretes automáticos por e-mail ao RT e ao RU nos seguintes momentos:
  - D+15 (quinze dias após a ciência): lembrete informativo.
  - D+25 (vinte e cinco dias após a ciência): lembrete de urgência.
- Ao atingir D+30 sem que a nova vistoria tenha sido solicitada, o sistema executa automaticamente a transição do licenciamento para o estado `SUSPENSO`.
- A transição automática para `SUSPENSO` é registrada como marco de auditoria com o motivo "prazo_revistoria_expirado".

**Dependência:** esta regra requer o novo estado `SUSPENSO` no enum `tp_situacao_licenciamento` (DDL Bloco 18.1) e a transição `AGUARD_CORRECAO_CIV → SUSPENSO` (DDL Bloco 18.11).

---

### RN-P07-N4: Re-vistoria Verifica Somente os Itens do CIV

**Referência normativa:** item 6.4.8.3 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

Na re-vistoria, o fiscal do CBMRS verifica **somente** os itens apontados no CIV anterior.

**Comportamento do sistema:**

- Ao iniciar a re-vistoria, o sistema exibe ao fiscal a lista de itens de inconformidade registrados no CIV correspondente, destacando-os como "itens a verificar".
- Os demais itens da vistoria original aparecem marcados como "aprovados na vistoria anterior — não reavaliados".
- O sistema impede o lançamento de novos itens de reprovação que não constem no CIV original, salvo quando o fiscal registrar fundamentação explícita para nova constatação.
- O laudo da re-vistoria deve referenciar o identificador do CIV originador.
- É de inteira responsabilidade do proprietário e do RT manter as demais medidas de segurança nas mesmas condições aprovadas anteriormente; o sistema exibe alerta informativo nesse sentido no início da tela de re-vistoria.

---

### RN-P07-N5: Interdição Imediata por Risco à Vida

**Referência normativa:** item 6.4.8.4 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

Durante a vistoria presencial, se o fiscal constatar situação de **iminente risco à vida ou integridade física**, deve acionar imediatamente o recurso de interdição disponível na interface de campo (tablet).

**Comportamento do sistema ao confirmar a interdição:**

1. Registra marco de interdição (total ou parcial) com timestamp preciso (`TIMESTAMPTZ`) no licenciamento.
2. Envia notificação push imediata aos seguintes destinatários:
   - Chefe da Seção de Segurança Contra Incêndio do BBM responsável (`CHEFE_SSEG_BBM`).
   - Comando do Pelotão do fiscal atuante.
3. Bloqueia o licenciamento para operações normais (campo `recurso_bloqueado = true` ou equivalente de interdição), impedindo edições pelo cidadão/RT até resolução.
4. Registra evento de auditoria com: identificador do fiscal, coordenadas GPS (quando disponíveis), tipo de interdição (total/parcial) e descrição da situação constatada.

**Interface:** o botão "Interditar — Risco Iminente" deve ser exibido com destaque visual (cor vermelha, ícone de alerta) e exigir confirmação em dois passos para evitar acionamento acidental.

---

### RN-P07-N6: Suspensão Automática após 2 Anos sem Movimentação com CA/CIV

**Referência normativa:** item 6.4.8.2 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

O PPCI que não for movimentado por **2 (dois) anos** a partir da data de emissão do Comunicado de Análise (CA) ou do CIV passa automaticamente para a condição de **SUSPENSO**.

**Comportamento do sistema:**

- Um job automático (rotina agendada) verifica diariamente os licenciamentos nos estados `AGUARD_CORRECAO_CIA` e `AGUARD_VISTORIA` com data de última movimentação inferior ao limite de 2 anos.
- Ao identificar o prazo expirado, o sistema executa a transição para `SUSPENSO` e registra o marco correspondente.
- O licenciamento retorna ao estado anterior (`AGUARD_CORRECAO_CIA`, `AGUARD_CORRECAO_CIV` ou `AGUARD_VISTORIA`) assim que o proprietário, o responsável pelo uso (RU) ou o RT realize qualquer movimentação registrada no sistema.
- A reativação também é registrada como marco de auditoria.

**Dependência:** esta regra requer o novo estado `SUSPENSO` (DDL Bloco 18.1) e as transições correspondentes (DDL Bloco 18.11).
