# Requisitos P08 — Emissão e Aceite do PRPCI
## Stack Atual Java EE (JAX-RS · CDI · JPA/Hibernate · EJB · SOE PROCERGS · Alfresco)

> Documento de requisitos baseado **exclusivamente** no código-fonte real do projeto
> `SOLCBM.BackEnd16-06`. Todos os nomes de classes, métodos, campos, tabelas e enumerações
> correspondem ao código existente sem adaptação.

---

## S1 — Visão Geral do Processo

O processo P08 representa a etapa final do ciclo de licenciamento: a **emissão do PRPCI**
(Plano de Regularização e Proteção Contra Incêndio) e a consequente **liberação do APPCI**
(Alvará de Prevenção e Proteção Contra Incêndio). É o único processo capaz de conduzir o
licenciamento ao estado terminal `ALVARA_VIGENTE`.

O processo se divide em dois sub-fluxos mutuamente exclusivos, determinados pelo tipo de
vistoria realizada no P07:

| Sub-processo | Situação de entrada | Ator principal | Situação de saída |
|---|---|---|---|
| **P08-A — Emissão Normal** | `AGUARDANDO_PRPCI` | Cidadão / RT (Responsável Técnico) | `ALVARA_VIGENTE` |
| **P08-B — Aceite de Renovação** | `AGUARDANDO_ACEITE_PRPCI` | RU / Proprietário (PF ou representante) | `ALVARA_VIGENTE` |

**P08-A** exige que o RT realize o upload do documento PRPCI em formato PDF via
`PrpciCidadaoRN.inclui()`. O sistema cria um `ArquivoED` com referência Alfresco e um
`PrpciED` vinculado ao licenciamento, e em seguida executa a transição de estado
`AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE`.

**P08-B** dispensa upload de documento: a vistoria de renovação já produziu os dados
necessários. O RU ou Proprietário concede o aceite eletrônico via
`PrpciCidadaoRN.aceitePrpci()`. O sistema registra os dados de aceite diretamente na
entidade `VistoriaED` e executa a transição `AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE`.

Ambos os sub-fluxos encerram com o registro dos marcos de auditoria e a disponibilização
do APPCI ao licenciamento.

---

## S2 — Entidades de Domínio (EDs)

### 2.1 PrpciED

```java
// Pacote: com.procergs.solcbm.ed
// Tabela: CBM_PRPCI
// Auditoria: NÃO auditada com @Audited (sem tabela _AUD — verificar)

@Entity
@Table(name = "CBM_PRPCI")
@NamedQueries({
    @NamedQuery(name = "PrpciED.consulta",
        query = "SELECT p FROM PrpciED p "
              + "JOIN FETCH p.arquivo a "
              + "JOIN FETCH p.localizacao l "
              + "LEFT JOIN FETCH p.licenciamento lic "
              + "WHERE p.id = :id")
})
public class PrpciED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "CBM_ID_PRPCI_SEQ")
    @SequenceGenerator(name = "CBM_ID_PRPCI_SEQ",
                       sequenceName = "CBM_ID_PRPCI_SEQ",
                       allocationSize = 1)
    @Column(name = "NRO_INT_PRPCI")
    private Long id;

    /**
     * Arquivo PDF do PRPCI armazenado no Alfresco.
     * TipoArquivo.EDIFICACAO — o campo identificadorAlfresco de ArquivoED
     * contém o nodeRef workspace://SpacesStore/{UUID}.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    private ArquivoED arquivo;

    /**
     * Localização da edificação à época do upload.
     * Copiada de LicenciamentoED.getLocalizacao() no momento da inclusão.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LOCALIZACAO")
    private LocalizacaoED localizacao;

    /**
     * Licenciamento ao qual este PRPCI pertence.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO")
    private LicenciamentoED licenciamento;
}
```

**Campos da tabela CBM_PRPCI:**

| Coluna | Tipo | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_PRPCI` | NUMBER | PK, NOT NULL | Chave primária (sequência) |
| `NRO_INT_ARQUIVO` | NUMBER | FK CBM_ARQUIVO, NOT NULL | Arquivo PDF no Alfresco |
| `NRO_INT_LOCALIZACAO` | NUMBER | FK CBM_LOCALIZACAO | Localização da edificação |
| `NRO_INT_LICENCIAMENTO` | NUMBER | FK CBM_LICENCIAMENTO, NOT NULL | Licenciamento vinculado |

---

### 2.2 ArquivoED

```java
// Pacote: com.procergs.solcbm.ed
// Tabela: CBM_ARQUIVO
// Auditoria: @Audited (Hibernate Envers) → tabela CBM_ARQUIVO_AUD

@Audited
@AuditOverride(forClass = AppED.class)
@Entity
@Table(name = "CBM_ARQUIVO")
public class ArquivoED extends AppED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE,
                    generator = "CBM_ID_ARQUIVO_SEQ")
    @SequenceGenerator(name = "CBM_ID_ARQUIVO_SEQ",
                       sequenceName = "CBM_ID_ARQUIVO_SEQ",
                       allocationSize = 1)
    @Column(name = "NRO_INT_ARQUIVO")
    private Long id;

    /**
     * Nome original do arquivo enviado pelo usuário.
     */
    @Column(name = "NOME_ARQUIVO", length = 120)
    private String nomeArquivo;

    /**
     * NodeRef do Alfresco.
     * Formato: "workspace://SpacesStore/{UUID}"
     * Inicializado com "0" em ArquivoRN.incluirArquivo() e substituído
     * após sincronização com Alfresco via SincronizarArquivoAlfrescoRN.
     * O arquivo binário NUNCA é persistido no banco relacional.
     */
    @Column(name = "TXT_IDENTIFICADOR_ALFRESCO")
    @NotNull
    @Size(max = 150)
    private String identificadorAlfresco;

    /**
     * Hash MD5 para verificação de integridade.
     */
    @Column(name = "TXT_MD5_SGM")
    private String txtMd5Sgm;

    /**
     * Tipo do arquivo — define pasta e metadados no Alfresco.
     * Para PRPCI: TipoArquivo.EDIFICACAO
     */
    @Column(name = "TP_ARQUIVO")
    @Enumerated(EnumType.STRING)
    private TipoArquivo tipoArquivo;

    /**
     * Código de autenticação gerado pelo sistema para validação externa.
     */
    @Column(name = "NRO_CODIGO_AUTENTICACAO")
    private String nroCodigoAutenticacao;

    /**
     * Controle de migração Alfresco (campos legados de migração).
     */
    @Column(name = "ID_MIGRACAO_ALFRESCO")
    private String idMigracaoAlfresco;

    @Column(name = "CTR_DTH_MIGRACAO_ALFRESCO")
    private Calendar ctrDthMigracaoAlfresco;
}
```

**Campos da tabela CBM_ARQUIVO:**

| Coluna | Tipo | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_ARQUIVO` | NUMBER | PK, NOT NULL | Chave primária (sequência) |
| `NOME_ARQUIVO` | VARCHAR2(120) | | Nome original do arquivo |
| `TXT_IDENTIFICADOR_ALFRESCO` | VARCHAR2(150) | NOT NULL | NodeRef Alfresco (identificador do binário) |
| `TXT_MD5_SGM` | VARCHAR2 | | Hash MD5 do conteúdo |
| `TP_ARQUIVO` | VARCHAR2 | | Enum `TipoArquivo` (ex: `EDIFICACAO`) |
| `NRO_CODIGO_AUTENTICACAO` | VARCHAR2 | | Código de autenticação do documento |
| `ID_MIGRACAO_ALFRESCO` | VARCHAR2 | | ID de migração legado |
| `CTR_DTH_MIGRACAO_ALFRESCO` | DATE | | Data da migração legado |

---

### 2.3 AppciED

```java
// Pacote: com.procergs.solcbm.ed
// Tabela: CBM_APPCI
// Usado em P08 como pré-condição do aceite (licenciamento.getAppcis() não pode estar vazio)

@Entity
@Table(name = "CBM_APPCI")
public class AppciED {

    @Id
    @Column(name = "NRO_INT_APPCI")
    private Long id;

    /** Arquivo PDF do APPCI no Alfresco. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    private ArquivoED arquivo;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LOCALIZACAO")
    private LocalizacaoED localizacao;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO")
    private LicenciamentoED licenciamento;

    /** Número de versão do APPCI (incrementado a cada emissão). */
    @Column(name = "NRO_VERSAO")
    private Integer versao;

    /** Data e hora de emissão do APPCI. */
    @Column(name = "DTH_EMISSAO")
    private Calendar dataHoraEmissao;

    /** Data de validade do APPCI. */
    @Column(name = "DT_VALIDADE")
    private Calendar dataValidade;

    /**
     * Indicador da versão vigente.
     * 'S' = versão atual; 'N' = versão histórica.
     * Convertido via SimNaoBooleanConverter em campos Boolean.
     */
    @Column(name = "IND_VERSAO_VIGENTE")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indVersaoVigente;

    /** Datas de vigência para controle de renovação. */
    @Column(name = "DT_VIGENCIA_INICIO")
    private Calendar dataVigenciaInicio;

    @Column(name = "DT_VIGENCIA_FIM")
    private Calendar dataVigenciaFim;

    /**
     * Indicador de APPCI de renovação.
     * 'S' = emitido em fluxo de renovação (P08-B); 'N' = emissão normal (P08-A).
     */
    @Column(name = "IND_RENOVACAO")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indRenovacao;

    /** Ciência do envolvido. */
    @Column(name = "IND_CIENCIA")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean ciencia;
}
```

---

### 2.4 Campos de aceite PRPCI na VistoriaED

Os campos abaixo são parte da entidade `VistoriaED` (definida no P07) e dizem respeito
exclusivamente ao P08-B:

```java
// Classe: VistoriaED (com.procergs.solcbm.ed)
// Tabela: CBM_VISTORIA
// Apenas os campos relacionados ao P08 são exibidos

/** ID do usuário que concedeu o aceite (RU, Proprietário ou Procurador). */
@Column(name = "NRO_INT_USUARIO_ACEITE_PRPCI")
private Long idUsuarioAceitePrpci;

/**
 * Flag de aceite do PRPCI.
 * Persistido como CHAR(1): 'S' = aceite concedido, 'N' = não aceito.
 * Mapeado via SimNaoBooleanConverter (AttributeConverter<Boolean, String>).
 * Null enquanto aguarda aceite.
 */
@Column(name = "IND_ACEITE_PRPCI")
@Convert(converter = SimNaoBooleanConverter.class)
private Boolean aceitePrpci;

/** Data e hora em que o aceite foi concedido. */
@Column(name = "DT_ACEITE_PRPCI")
private Calendar dthAceitePrpci;
```

**Setters executados em `PrpciCidadaoRN.aceitePrpci()`:**
```java
vistoriaED.setIdUsuarioAceitePrpci(usuarioRN.getUsuarioLogado().getId());
vistoriaED.setAceitePrpci(true);
vistoriaED.setDthAceitePrpci(Calendar.getInstance());
```

---

### 2.5 LocalizacaoED

```java
// Pacote: com.procergs.solcbm.ed
// Tabela: CBM_LOCALIZACAO
// Auditoria: @Audited → tabela CBM_LOCALIZACAO_AUD

@Audited
@AuditTable(value = "CBM_LOCALIZACAO_AUD")
@Entity
@Table(name = "CBM_LOCALIZACAO")
public class LocalizacaoED {

    @Id
    @Column(name = "NRO_INT_LOCALIZACAO")
    private Long id;

    /** Coordenadas aprovadas / DNE. */
    @Column(name = "NRO_LATITUDE_ENDERECO")
    private Double latitudeEndereco;

    @Column(name = "NRO_LONGITUDE_ENDERECO")
    private Double longitudeEndereco;

    /** Coordenadas ajustadas pelo usuário no mapa. */
    @Column(name = "NRO_LATITUDE_MAPA")
    private Double latitudeMapa;

    @Column(name = "NRO_LONGITUDE_MAPA")
    private Double longitudeMapa;
}
```

---

### 2.6 LicenciamentoED — campos relevantes para P08

```java
// Apenas os campos diretamente acessados no P08

/** Conjunto de APPCIs emitidos para este licenciamento (verificado em P08-B). */
@NotAudited
@OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
@OrderBy("dataValidade")
private Set<AppciED> appcis;

/** Vistorias realizadas (contém os campos de aceite PRPCI no P08-B). */
@NotAudited
@OneToMany(mappedBy = "licenciamento", fetch = FetchType.LAZY)
private Set<VistoriaED> vistorias;

/** Localização principal — copiada para PrpciED no upload. */
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "NRO_INT_LOCALIZACAO")
private LocalizacaoED localizacao;

/** Situação atual — validada antes de qualquer operação P08. */
@Column(name = "TP_SITUACAO")
@Enumerated(EnumType.STRING)
private SituacaoLicenciamento situacao;
```

---

## S3 — Enumerações

### 3.1 SituacaoLicenciamento (valores relevantes para P08)

```java
// Pacote: com.procergs.solcbm.enumeration
// Enum completo tem 42+ valores; abaixo apenas os do ciclo P08

public enum SituacaoLicenciamento {

    // Situações de entrada para P08
    AGUARDANDO_PRPCI("Aguardando PrPCI"),
    AGUARDANDO_ACEITE_PRPCI("Aguardando Aceite PrPCI"),

    // Situação terminal do ciclo de licenciamento
    ALVARA_VIGENTE("APPCI em vigor"),

    // Situação pós-vencimento (fora do escopo direto do P08)
    ALVARA_VENCIDO("APPCI vencido");

    // Nota: AGUARDANDO_ACEITE_PRPCI é incluído em
    // retornaSituacoesMinhasRenovacoes() para listagem das renovações do usuário
}
```

### 3.2 TipoMarco (marcos registrados pelo P08)

```java
// Pacote: com.procergs.solcbm.enumeration
// Enum com 136 valores; abaixo apenas os do P08

public enum TipoMarco {
    // P08-A — upload pelo RT
    UPLOAD_PRPCI,          // Linha 62 do enum
    LIBERACAO_APPCI,       // Linha 52 do enum

    // P08-B — aceite pelo RU/Proprietário
    ACEITE_PRPCI,          // Linha 114 do enum
    LIBERACAO_RENOV_APPCI  // Linha 115 do enum
}
```

**Forma de registro:**
- `licenciamentoMarcoInclusaoRN.inclui(TipoMarco, LicenciamentoED)` — sem arquivo
- `licenciamentoMarcoInclusaoRN.incluiComArquivo(TipoMarco, LicenciamentoED, ArquivoED)` — com arquivo

### 3.3 TipoArquivo

```java
// Pacote: com.procergs.solcbm.enumeration
// Para PRPCI usa-se TipoArquivo.EDIFICACAO

public enum TipoArquivo {

    EDIFICACAO {
        @Override
        public Map<String, Object> getAtributos() {
            Map<String, Object> atributos = new ConcurrentHashMap<>();
            atributos.put("grp:organizacao", "CBM");
            atributos.put("grp:familia", "Documentos de Edificação");
            atributos.put("grp:categoria", "Licenciamento");
            atributos.put("grp:subcategoria", "Documentos");
            atributos.put("grp:sistema", "SOLCBM");
            return atributos;
        }

        @Override
        public String getTypeId() {
            // Valor de PropriedadesEnum.ECM_TYPEID_EDIFICACAO
            return PropriedadesEnum.ECM_TYPEID_EDIFICACAO.getVal();
        }

        @Override
        public String getCaminhoPasta() {
            // Valor de PropriedadesEnum.ECM_PASTA_EDIFICACAO_DOCUMENTOS
            return PropriedadesEnum.ECM_PASTA_EDIFICACAO_DOCUMENTOS.getVal();
        }
    }
    // demais tipos omitidos — não relevantes para P08
}
```

### 3.4 TrocaEstadoLicenciamentoEnum (valores P08)

```java
// Pacote: com.procergs.solcbm.enumeration

public enum TrocaEstadoLicenciamentoEnum {
    // Transições de entrada do P08 (disparadas no final do P07)
    EM_VISTORIA_PARA_AGUARDANDO_PRPCI,           // P07 normal → P08-A
    EM_VISTORIA_PARA_AGUARDANDO_ACEITE_PRPCI,    // P07 renovação → P08-B

    // Transições internas do P08
    AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE,        // P08-A final
    AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE  // P08-B final
}
```

---

## S4 — Regras de Negócio (RNs)

### 4.1 PrpciRN

```java
// Pacote: com.procergs.solcbm.prpci
// Arquivo: PrpciRN.java

@Stateless
@SegurancaEnvolvidoInterceptor
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public class PrpciRN extends AppRN<PrpciED, Long> {

    @Inject
    private PrpciBD prpciBD;

    @Inject
    private ArquivoRN arquivoRN;

    /**
     * Lista os PRPCIs de um licenciamento como DTOs (exibição no frontend).
     * Usado na listagem de documentos do licenciamento.
     *
     * @param idLicenciamento ID do licenciamento
     * @return Lista de PrpciDTO com os arquivos vinculados
     */
    public List<PrpciDTO> listaPorLicenciamento(Long idLicenciamento) { ... }

    /**
     * Lista os PRPCIs de um licenciamento como entidades (uso interno).
     * Usado pelas TrocaEstado para obter o arquivo do primeiro PRPCI.
     *
     * @param idLicenciamento ID do licenciamento
     * @return Lista de PrpciED
     */
    public List<PrpciED> listaEDPorLicenciamento(Long idLicenciamento) { ... }
}
```

### 4.2 PrpciCidadaoRN

```java
// Pacote: com.procergs.solcbm.prpci
// Arquivo: PrpciCidadaoRN.java
// Contém a lógica de negócio central dos dois sub-processos do P08

@Stateless
@SegurancaEnvolvidoInterceptor
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public class PrpciCidadaoRN {

    @Inject
    private PrpciRN prpciRN;

    @Inject
    private PrpciRNVal prpciRNVal;

    @Inject
    private LicenciamentoRN licenciamentoRN;

    @Inject
    private VistoriaRN vistoriaRN;

    @Inject
    private UsuarioRN usuarioRN;

    @Inject
    @TrocaEstadoLicenciamentoQualifier(
        trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE)
    private TrocaEstadoLicenciamentoRN trocaEstadoLicenciamentoRN;

    @Inject
    @TrocaEstadoLicenciamentoQualifier(
        trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE)
    private TrocaEstadoLicenciamentoRN trocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN;

    // ─── P08-A: Upload de PRPCI pelo RT ──────────────────────────────────────

    /**
     * Processa o upload do documento PRPCI pelo RT.
     *
     * Pré-condições (validadas internamente):
     *   1. Lista de arquivos não é nula/vazia (PrpciRNVal.validaParametro)
     *   2. Licenciamento existe (LicenciamentoRN.consulta)
     *   3. Situação do licenciamento == AGUARDANDO_PRPCI (PrpciRNVal.validaSituacaoLicenciamento)
     *
     * Ações executadas:
     *   1. Para cada Arquivo recebido:
     *      a. ArquivoRN.incluirArquivo(arquivo, TipoArquivo.EDIFICACAO)
     *         → Cria ArquivoED no banco com identificadorAlfresco="0"
     *         → Armazena binário no Alfresco (ECM)
     *         → Atualiza identificadorAlfresco com o nodeRef retornado
     *      b. Cria PrpciED vinculando arquivo, localizacao (do licenciamento) e licenciamento
     *      c. PrpciRN.inclui(prpciED) — persiste via JPA
     *   2. trocaEstadoLicenciamentoRN.trocaEstado(idLicenciamento)
     *      → TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente executa:
     *        - atualizaSituacaoLicenciamento() → ALVARA_VIGENTE
     *        - Marco UPLOAD_PRPCI (com arquivo se houver; sem arquivo caso vazio)
     *        - Marco LIBERACAO_APPCI
     *
     * @param idLicenciamento ID do licenciamento em AGUARDANDO_PRPCI
     * @param arquivos        Lista de Arquivo recebidos via MultipartFormDataInput
     */
    @Permissao(objeto = "PRPCI", acao = "INCLUIR")
    public void inclui(Long idLicenciamento, List<Arquivo> arquivos) { ... }

    // ─── P08-B: Aceite de PRPCI pelo RU/Proprietário ─────────────────────────

    /**
     * Registra o aceite eletrônico do PRPCI pelo RU ou Proprietário.
     *
     * Pré-condições (validadas internamente):
     *   1. Licenciamento existe (LicenciamentoRN.consulta)
     *   2. Situação do licenciamento == AGUARDANDO_ACEITE_PRPCI
     *      (PrpciRNVal.validaSituacaoLicenciamentoRenovacao)
     *   3. Usuário logado tem permissão de aceite:
     *      isRU || isProcuradorRU || isProprietarioPF || isProcuradorProprietario
     *      (PrpciRNVal.validaPermissaoUsuarioRuProp)
     *   4. Licenciamento possui pelo menos 1 APPCI emitido
     *      (!licenciamentoED.getAppcis().isEmpty())
     *   5. Vistoria existe (VistoriaRN.consulta)
     *
     * Ações executadas:
     *   1. vistoriaED.setIdUsuarioAceitePrpci(usuarioRN.getUsuarioLogado().getId())
     *   2. vistoriaED.setAceitePrpci(true)  → persiste como 'S' no BD
     *   3. vistoriaED.setDthAceitePrpci(Calendar.getInstance())
     *   4. trocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN.trocaEstado()
     *      → TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN executa:
     *        - atualizaSituacaoLicenciamento() → ALVARA_VIGENTE
     *        - Marco ACEITE_PRPCI
     *        - Marco LIBERACAO_RENOV_APPCI
     *
     * @param idLicenciamento ID do licenciamento em AGUARDANDO_ACEITE_PRPCI
     * @param idVistoria      ID da vistoria de renovação a ser aceita
     */
    @Permissao(objeto = "PRPCI", acao = "INCLUIR")
    public void aceitePrpci(Long idLicenciamento, Long idVistoria) { ... }

    // ─── Consulta de permissão (GET) ──────────────────────────────────────────

    /**
     * Verifica se o usuário logado pode conceder o aceite de PRPCI.
     * Usado pelo frontend para habilitar/desabilitar o botão de aceite.
     *
     * Retorna true se TODAS as condições forem satisfeitas:
     *   1. Usuário é RU, Procurador de RU, Proprietário PF ou Procurador de Proprietário
     *   2. Situação do licenciamento == AGUARDANDO_ACEITE_PRPCI
     *   3. !licenciamentoED.getAppcis().isEmpty()
     *
     * @param idLicenciamento ID do licenciamento
     * @return true = pode aceitar; false = não pode
     */
    public Boolean verificaPermissoesUsuario(Long idLicenciamento) { ... }
}
```

### 4.3 PrpciRNVal

```java
// Pacote: com.procergs.solcbm.prpci
// Arquivo: PrpciRNVal.java
// Classe de validações; todas as exceções lançam SolCbmException (BusinessException)

@Stateless
public class PrpciRNVal {

    /**
     * RN01 — Valida que a lista de arquivos não está vazia.
     * Disparado em P08-A antes de qualquer criação de entidade.
     *
     * @param arquivos Lista de Arquivo recebida do multipart
     * @throws SolCbmException se lista for nula ou vazia
     */
    public void validaParametro(List<Arquivo> arquivos) { ... }

    /**
     * RN02 — Valida que a situação do licenciamento é AGUARDANDO_PRPCI.
     * Disparado em P08-A para garantir que o licenciamento está na etapa correta.
     *
     * @param situacao SituacaoLicenciamento atual do licenciamento
     * @throws SolCbmException se situação != AGUARDANDO_PRPCI
     */
    public void validaSituacaoLicenciamento(SituacaoLicenciamento situacao) { ... }

    /**
     * RN03 — Valida que a situação do licenciamento é AGUARDANDO_ACEITE_PRPCI.
     * Disparado em P08-B para garantir que é um fluxo de renovação aguardando aceite.
     *
     * @param situacao SituacaoLicenciamento atual do licenciamento
     * @throws SolCbmException se situação != AGUARDANDO_ACEITE_PRPCI
     */
    public void validaSituacaoLicenciamentoRenovacao(SituacaoLicenciamento situacao) { ... }

    /**
     * RN04 — Valida que o usuário tem permissão de aceite (RU ou Proprietário).
     * Disparado em P08-B após consultar os envolvidos do licenciamento.
     *
     * @param hasPermission Resultado de verificaPermissoesUsuario()
     * @throws SolCbmException se false (usuário não é RU/Prop/Procurador)
     */
    public void validaPermissaoUsuarioRuProp(Boolean hasPermission) { ... }
}
```

### 4.4 PrpciBD

```java
// Pacote: com.procergs.solcbm.prpci
// Arquivo: PrpciBD.java
// Implementação Hibernate Criteria (padrão de persistência do projeto)

@Stateless
public class PrpciBD extends AppBD<PrpciED, Long> {

    // Joins configurados no buildCriteria():
    //   - INNER JOIN com arquivo (NRO_INT_ARQUIVO)
    //   - INNER JOIN com localizacao (NRO_INT_LOCALIZACAO)
    //   - LEFT OUTER JOIN com licenciamento (NRO_INT_LICENCIAMENTO)
    //
    // Filtros dinâmicos (Restrictions.eq):
    //   - id
    //   - arquivo
    //   - localizacao
    //   - licenciamento
}
```

---

## S5 — Transições de Estado (TrocaEstado CDI)

### 5.1 TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci

```java
// Arquivo: TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci.java
// Disparado pelo P07 (VistoriaHomologacaoAdmRN) para vistoria definitiva/parcial aprovada

@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.EM_VISTORIA_PARA_AGUARDANDO_PRPCI)
public class TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci
        implements TrocaEstadoLicenciamentoRN {

    @Inject
    private PeriodoSolicitacaoRN periodoSolicitacaoRN;

    @Inject
    private LicenciamentoAdmNotificacaoRN licenciamentoAdmNotificacaoRN;

    @Override
    public LicenciamentoED trocaEstado(Long idLicenciamento) {
        // 1. Atualiza SituacaoLicenciamento → AGUARDANDO_PRPCI
        LicenciamentoED licenciamentoED = atualizaSituacaoLicenciamento(idLicenciamento);

        // 2. Fecha período de solicitação do tipo VISTORIA
        periodoSolicitacaoRN.fecha(licenciamentoED.getId(), TipoPeriodoSolicitacao.VISTORIA);

        // 3. Notifica conclusão da vistoria normal (template: vistoria.conclusao)
        licenciamentoAdmNotificacaoRN.notificarConclusaoVistoria(licenciamentoED);

        return licenciamentoED;
    }

    @Override
    public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
        return SituacaoLicenciamento.AGUARDANDO_PRPCI;
    }
}
```

### 5.2 TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci

```java
// Arquivo: TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci.java
// Disparado pelo P07 (VistoriaHomologacaoAdmRN) para vistoria de renovação aprovada

@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.EM_VISTORIA_PARA_AGUARDANDO_ACEITE_PRPCI)
public class TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci
        implements TrocaEstadoLicenciamentoRN {

    @Inject
    private PeriodoSolicitacaoRN periodoSolicitacaoRN;

    @Inject
    private LicenciamentoAdmNotificacaoRN licenciamentoAdmNotificacaoRN;

    @Override
    public LicenciamentoED trocaEstado(Long idLicenciamento) {
        // 1. Atualiza SituacaoLicenciamento → AGUARDANDO_ACEITE_PRPCI
        LicenciamentoED licenciamentoED = atualizaSituacaoLicenciamento(idLicenciamento);

        // 2. Fecha período de solicitação do tipo VISTORIA
        periodoSolicitacaoRN.fecha(licenciamentoED.getId(), TipoPeriodoSolicitacao.VISTORIA);

        // 3. Notifica conclusão da vistoria de renovação (template diferente do P08-A)
        licenciamentoAdmNotificacaoRN.notificarConclusaoVistoriaRenovacao(licenciamentoED);

        return licenciamentoED;
    }

    @Override
    public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
        return SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI;
    }
}
```

### 5.3 TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente

```java
// Arquivo: TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente.java
// Disparado por PrpciCidadaoRN.inclui() — fim do P08-A

@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE)
public class TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente
        implements TrocaEstadoLicenciamentoRN {

    @Inject
    private PrpciRN prpciRN;

    @Inject
    private LicenciamentoMarcoInclusaoRN licenciamentoMarcoInclusaoRN;

    @Override
    public LicenciamentoED trocaEstado(Long idLicenciamento) {
        // 1. Obtém PRPCIs já persistidos para usar o arquivo no marco
        List<PrpciED> prpcis = prpciRN.listaEDPorLicenciamento(idLicenciamento);

        // 2. Atualiza SituacaoLicenciamento → ALVARA_VIGENTE
        LicenciamentoED licenciamentoED = atualizaSituacaoLicenciamento(idLicenciamento);

        // 3. Registra marco UPLOAD_PRPCI
        //    Se há PRPCIs: registra com o arquivo do primeiro PRPCI
        //    Se não há:    registra sem arquivo (situação de fallback)
        if (prpcis.isEmpty()) {
            licenciamentoMarcoInclusaoRN.inclui(TipoMarco.UPLOAD_PRPCI, licenciamentoED);
        } else {
            licenciamentoMarcoInclusaoRN.incluiComArquivo(
                TipoMarco.UPLOAD_PRPCI,
                licenciamentoED,
                prpcis.get(0).getArquivo()
            );
        }

        // 4. Registra marco LIBERACAO_APPCI (emissão do APPCI)
        licenciamentoMarcoInclusaoRN.inclui(TipoMarco.LIBERACAO_APPCI, licenciamentoED);

        return licenciamentoED;
    }

    @Override
    public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;
    }
}
```

### 5.4 TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN

```java
// Arquivo: TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN.java
// Disparado por PrpciCidadaoRN.aceitePrpci() — fim do P08-B

@TrocaEstadoLicenciamentoQualifier(
    trocaEstado = TrocaEstadoLicenciamentoEnum.AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE)
public class TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN
        implements TrocaEstadoLicenciamentoRN {

    @Inject
    private LicenciamentoMarcoInclusaoRN licenciamentoMarcoInclusaoRN;

    @Override
    public LicenciamentoED trocaEstado(Long idLicenciamento) {
        // 1. Atualiza SituacaoLicenciamento → ALVARA_VIGENTE
        LicenciamentoED licenciamentoED = atualizaSituacaoLicenciamento(idLicenciamento);

        // 2. Registra marco ACEITE_PRPCI (aceite pelo RU/Proprietário)
        licenciamentoMarcoInclusaoRN.inclui(TipoMarco.ACEITE_PRPCI, licenciamentoED);

        // 3. Registra marco LIBERACAO_RENOV_APPCI (emissão do APPCI de renovação)
        licenciamentoMarcoInclusaoRN.inclui(TipoMarco.LIBERACAO_RENOV_APPCI, licenciamentoED);

        return licenciamentoED;
    }

    @Override
    public SituacaoLicenciamento getNovaSituacaoLicenciamento() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;
    }
}
```

---

## S6 — Endpoints REST

### 6.1 Interface PrpciRest

```java
// Pacote: com.procergs.solcbm.remote
// Arquivo: PrpciRest.java
// Swagger annotations incluídas para documentação da API

@Api(value = "prpci",
     authorizations = {
         @Authorization(value = "LoginCidadão",
             scopes = { @AuthorizationScope(scope = "openid") }),
         @Authorization(value = "Bearer")
     })
public interface PrpciRest {

    /**
     * P08-A — Upload do documento PRPCI pelo RT.
     * Corpo: multipart/form-data, campo "file".
     */
    Response inclui(
        @PathParam("idLic") Long idLicenciamento,
        MultipartFormDataInput formData
    );

    /**
     * P08-B — Aceite eletrônico do PRPCI pelo RU/Proprietário.
     */
    Response aceitePrpci(
        @PathParam("idLic")       Long idLic,
        @PathParam("idVistoria")  Long idVistoria
    );

    /**
     * Consulta se o usuário logado pode conceder o aceite.
     * Retorna Boolean (true/false).
     */
    Response consultaUsuarioAceite(
        @PathParam("idLic") Long idLic
    );
}
```

### 6.2 Implementação PrpciRestImpl

```java
// Pacote: com.procergs.solcbm.remote
// Arquivo: PrpciRestImpl.java

@Path("/prpci")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class PrpciRestImpl implements PrpciRest {

    @Inject
    private PrpciCidadaoRN prpciCidadaoRN;

    // ──────────────────────────────────────────────────────────────────────────
    // Endpoint 1 — PUT /{idLic}
    // P08-A: Upload do documento PRPCI
    // ──────────────────────────────────────────────────────────────────────────
    @Override
    @PUT
    @Path("/{idLic}")
    @AutorizaEnvolvido
    @Consumes(MediaType.MULTIPART_FORM_DATA)
    public Response inclui(
            @PathParam("idLic") final Long idLicenciamento,
            MultipartFormDataInput formData) {

        // Extrai lista de arquivos do multipart usando a chave "file"
        // MultipartFormUtil.getArquivosFromFormDataComNomeArquivo(formData, "file")
        List<Arquivo> arquivos = extrairArquivos(formData);

        prpciCidadaoRN.inclui(idLicenciamento, arquivos);

        return Response.ok().build();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Endpoint 2 — PUT /{idLic}/termo/{idVistoria}/aceite-prpci
    // P08-B: Aceite do PRPCI pelo RU/Proprietário
    // ──────────────────────────────────────────────────────────────────────────
    @Override
    @PUT
    @Path("/{idLic}/termo/{idVistoria}/aceite-prpci")
    @AutorizaEnvolvido
    public Response aceitePrpci(
            @PathParam("idLic")      final Long idLic,
            @PathParam("idVistoria") final Long idVistoria) {

        prpciCidadaoRN.aceitePrpci(idLic, idVistoria);

        return Response.ok().build();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Endpoint 3 — GET /{idLic}/pode-aceite-prpci
    // Consulta se usuário logado pode aceitar o PRPCI
    // ──────────────────────────────────────────────────────────────────────────
    @Override
    @GET
    @Path("/{idLic}/pode-aceite-prpci")
    public Response consultaUsuarioAceite(
            @PathParam("idLic") final Long idLic) {

        Boolean podeAceitar = prpciCidadaoRN.verificaPermissoesUsuario(idLic);

        return Response.ok(podeAceitar).build();
    }
}
```

**Tabela de endpoints REST:**

| Verbo | Path | Anotações de segurança | Corpo | Retorno |
|---|---|---|---|---|
| `PUT` | `/prpci/{idLic}` | `@AutorizaEnvolvido` + `@Permissao(PRPCI/INCLUIR)` | `multipart/form-data` campo `file` | `200 OK` |
| `PUT` | `/prpci/{idLic}/termo/{idVistoria}/aceite-prpci` | `@AutorizaEnvolvido` + `@Permissao(PRPCI/INCLUIR)` | (vazio) | `200 OK` |
| `GET` | `/prpci/{idLic}/pode-aceite-prpci` | (sem `@AutorizaEnvolvido`) | — | `200 OK` + `Boolean` |

---

## S7 — DTOs e Builders

### 7.1 PrpciDTO

```java
// Pacote: com.procergs.solcbm.remote.ed
// Arquivo: PrpciDTO.java

public class PrpciDTO {
    private Arquivo arquivo;   // metadados do arquivo (nome, tipo, identificadorAlfresco)

    public Arquivo getArquivo() { return arquivo; }
    public void setArquivo(Arquivo arquivo) { this.arquivo = arquivo; }
}
```

> A classe `Arquivo` (VO não-JPA) carrega: nome do arquivo, identificador Alfresco e
> metadados necessários para o frontend exibir e baixar o documento.

### 7.2 BuilderPrpciDTO

```java
// Pacote: com.procergs.solcbm.builder
// Arquivo: BuilderPrpciDTO.java
// Builder fluente para PrpciDTO

public class BuilderPrpciDTO {

    private PrpciDTO prpciDTO;

    private BuilderPrpciDTO() {
        this.prpciDTO = new PrpciDTO();
    }

    public static BuilderPrpciDTO of() {
        return new BuilderPrpciDTO();
    }

    public BuilderPrpciDTO arquivo(Arquivo arquivo) {
        this.prpciDTO.setArquivo(arquivo);
        return this;
    }

    public PrpciDTO instance() {
        return this.prpciDTO;
    }
}
```

### 7.3 BuilderPrpciED

```java
// Pacote: com.procergs.solcbm.builder
// Arquivo: BuilderPrpciED.java
// Builder fluente para PrpciED

public class BuilderPrpciED {

    private PrpciED prpciED;

    private BuilderPrpciED() {
        this.prpciED = new PrpciED();
    }

    public static BuilderPrpciED of() {
        return new BuilderPrpciED();
    }

    public BuilderPrpciED id(Long id)                        { ... }
    public BuilderPrpciED arquivo(ArquivoED arquivo)         { ... }
    public BuilderPrpciED localizacao(LocalizacaoED loc)     { ... }
    public BuilderPrpciED licenciamento(LicenciamentoED lic) { ... }

    public PrpciED instance() {
        return this.prpciED;
    }
}
```

### 7.4 PrpciToPrpciRelatorioDTOConverter

```java
// Pacote: com.procergs.solcbm.converter.licenciamento
// Arquivo: PrpciToPrpciRelatorioDTOConverter.java
// Usado para geração de relatórios com múltiplos PRPCIs

public class PrpciToPrpciRelatorioDTOConverter {

    /**
     * Converte lista de PrpciDTO em PrPciRelatorioDTO para uso em relatórios.
     *
     * @param prpcis Lista de PrpciDTO do licenciamento
     * @return PrPciRelatorioDTO com nomes dos arquivos ordenados alfabeticamente
     */
    public PrPciRelatorioDTO converte(List<PrpciDTO> prpcis) {
        // Extrai nomes seguros via LicenciamentoNomeArquivoHelper.getNomeSafe()
        // Ordena os nomes alfabeticamente
        // Monta e retorna PrPciRelatorioDTO
    }
}
```

### 7.5 PrPciRelatorioDTO

```java
// Usado em geração de relatório/APPCI; contém lista de nomes de arquivos PRPCI.

public class PrPciRelatorioDTO {
    private List<String> arquivos; // nomes dos arquivos, ordenados alfabeticamente
}
```

---

## S8 — Segurança e Controle de Acesso

### 8.1 Camadas de segurança aplicadas ao P08

| Camada | Mecanismo | Classe/Anotação | Descrição |
|---|---|---|---|
| Camada REST | `@AutorizaEnvolvido` | `SegurancaEnvolvidoInterceptor` | Valida que o usuário autenticado é um envolvido (RT, RU, Prop) no licenciamento informado no path |
| Camada RN | `@Permissao(objeto, acao)` | `PermissaoInterceptor` | Verifica se o perfil do usuário tem a permissão `PRPCI/INCLUIR` no sistema de controle de acesso SOE |
| Camada RN | `@SegurancaEnvolvidoInterceptor` | CDI Interceptor na classe | Interceptor de classe aplicado a `PrpciRN` e `PrpciCidadaoRN` |
| Negócio P08-B | `verificaPermissoesUsuario()` | `PrpciCidadaoRN` | Validação programática de papéis: `isRU || isProcuradorRU || isProprietarioPF || isProcuradorProprietario` |

### 8.2 @Permissao no P08

```java
// PrpciCidadaoRN.inclui() — P08-A
@Permissao(objeto = "PRPCI", acao = "INCLUIR")
public void inclui(Long idLicenciamento, List<Arquivo> arquivos) { ... }

// PrpciCidadaoRN.aceitePrpci() — P08-B
@Permissao(objeto = "PRPCI", acao = "INCLUIR")
public void aceitePrpci(Long idLicenciamento, Long idVistoria) { ... }
```

> Ambos os sub-processos usam `acao = "INCLUIR"`. A diferenciação entre P08-A e P08-B
> é feita pela **situação do licenciamento** e pela **validação de papel do envolvido**,
> não pela ação de permissão.

### 8.3 Autorização de envolvidos (P08-B)

A validação no método `verificaPermissoesUsuario()` percorre os envolvidos do licenciamento
e verifica se o usuário logado (via `UsuarioRN.getUsuarioLogado()`) se enquadra em um dos
quatro papéis autorizados:

| Papel | Verificação |
|---|---|
| Responsável pelo Uso (RU) | `isRU(licenciamento, usuarioLogado)` |
| Procurador do RU | `isProcuradorRU(licenciamento, usuarioLogado)` |
| Proprietário Pessoa Física | `isProprietarioPF(licenciamento, usuarioLogado)` |
| Procurador do Proprietário | `isProcuradorProprietario(licenciamento, usuarioLogado)` |

A verificação final retorna `true` somente se:
1. Um dos quatro papéis é satisfeito
2. `licenciamento.getSituacao() == SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI`
3. `!licenciamento.getAppcis().isEmpty()`

---

## S9 — Integração com Alfresco (ECM)

### 9.1 Responsabilidade do ArquivoRN

O armazenamento do binário PDF do PRPCI é gerenciado por `ArquivoRN.incluirArquivo()`,
chamado dentro de `PrpciCidadaoRN.inclui()` para cada arquivo recebido:

```
PrpciCidadaoRN.inclui()
  └─ ArquivoRN.incluirArquivo(arquivo, TipoArquivo.EDIFICACAO)
       ├─ Cria ArquivoED no banco com identificadorAlfresco = "0" (valor provisório)
       ├─ Envia o binário ao Alfresco ECM
       │    └─ Atributos de classificação (TipoArquivo.EDIFICACAO.getAtributos()):
       │         grp:organizacao  = "CBM"
       │         grp:familia      = "Documentos de Edificação"
       │         grp:categoria    = "Licenciamento"
       │         grp:subcategoria = "Documentos"
       │         grp:sistema      = "SOLCBM"
       │    └─ typeId: PropriedadesEnum.ECM_TYPEID_EDIFICACAO
       │    └─ Pasta: PropriedadesEnum.ECM_PASTA_EDIFICACAO_DOCUMENTOS
       └─ Recebe nodeRef retornado: "workspace://SpacesStore/{UUID}"
            └─ Atualiza ArquivoED.identificadorAlfresco com o nodeRef real
```

### 9.2 Sincronização assíncrona

Existe `SincronizarArquivoAlfrescoRN` para cenários de sincronização retroativa
do campo `identificadorAlfresco` em registros com valor "0" (envios que falharam
na primeira tentativa ou migração de legado).

### 9.3 Acesso ao binário

O frontend acessa o arquivo PRPCI via endpoint de download de arquivos,
informando o `identificadorAlfresco` (nodeRef) obtido a partir do `PrpciDTO.arquivo`.
O backend recupera o binário do Alfresco usando o nodeRef e retorna como stream.

---

## S10 — Notificações por E-mail

As notificações do P08 são disparadas pelas transições de entrada (P07→P08),
**antes** do P08 propriamente começar:

### 10.1 Notificação de conclusão de vistoria normal (→ P08-A)

```java
// Classe: LicenciamentoAdmNotificacaoRN
// Disparado em: TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci.trocaEstado()

@Permissao(objeto = "VISTORIA", acao = "VISTORIAR")
public void notificarConclusaoVistoria(LicenciamentoED licenciamentoED) {
    String mensagem = bundle.getMessage(
        "notificacao.email.template.licenciamento.vistoria.conclusao");
    notificarEnvolvidos(licenciamentoED,
        "notificacao.assunto.vistoria.conclusao", mensagem);
}
```

**Chave de template:** `notificacao.email.template.licenciamento.vistoria.conclusao`
**Destinatários:** Envolvidos do licenciamento (RT, RU, Proprietário)

### 10.2 Notificação de conclusão de vistoria de renovação (→ P08-B)

```java
// Disparado em: TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci.trocaEstado()

@Permissao(objeto = "VISTORIA", acao = "VISTORIAR")
public void notificarConclusaoVistoriaRenovacao(LicenciamentoED licenciamentoED) {
    String mensagem = bundle.getMessage(
        "notificacao.email.template.licenciamento.vistoria.renovacao.conclusao");
    notificarEnvolvidosRenovacao(licenciamentoED,
        "notificacao.assunto.vistoria.renovacao.conclusao", mensagem);
}
```

**Chave de template:** `notificacao.email.template.licenciamento.vistoria.renovacao.conclusao`
**Destinatários:** Envolvidos do licenciamento no contexto de renovação

> Não foram identificadas notificações disparadas **dentro** do P08 (após upload ou aceite).
> As notificações relevantes ocorrem na transição P07→P08.

---

## S11 — Máquinas de Estado

### 11.1 SituacaoLicenciamento — transições do P08

```
         ┌──────────────────────────────────────────────────────────────────┐
         │                      CICLO P08 — PRPCI                           │
         └──────────────────────────────────────────────────────────────────┘

  [P07 — VistoriaHomologacaoAdmRN]
  GW_TipoVistoria:
    DEFINITIVA / PARCIAL ──────────────────┐
    RENOVACAO ─────────────────────────┐   │
                                       │   │
                                       ▼   ▼
  ┌──────────────────────────┐   ┌──────────────────┐
  │ AGUARDANDO_ACEITE_PRPCI  │   │ AGUARDANDO_PRPCI │
  │  (Telas: aceite RU/Prop) │   │  (Telas: upload  │
  │                          │   │   documento RT)  │
  └────────────┬─────────────┘   └────────┬─────────┘
               │                          │
               │ PrpciCidadaoRN           │ PrpciCidadaoRN
               │ .aceitePrpci()           │ .inclui()
               │                          │
               │ TrocaEstado:             │ TrocaEstado:
               │ AGUARD_ACEITE_PRPCI      │ AGUARDANDO_PRPCI
               │ →ALVARA_VIGENTE          │ →ALVARA_VIGENTE
               │                          │
               │  Marcos:                 │  Marcos:
               │  ACEITE_PRPCI            │  UPLOAD_PRPCI (+arquivo)
               │  LIBERACAO_RENOV_APPCI   │  LIBERACAO_APPCI
               │                          │
               └──────────────┬───────────┘
                              ▼
               ┌──────────────────────────┐
               │      ALVARA_VIGENTE      │
               │  [Estado terminal do     │
               │   ciclo de licenciamento]│
               └──────────────────────────┘
```

### 11.2 VistoriaED — campo aceitePrpci (P08-B)

```
VistoriaED.aceitePrpci (IND_ACEITE_PRPCI no BD: CHAR(1)):

  null  ──────────────────────────────────────────►  'S' (true)
  (antes do aceite P08-B)     PrpciCidadaoRN          (aceite concedido)
                              .aceitePrpci()
                              setAceitePrpci(true)
                              setIdUsuarioAceitePrpci(usuarioLogado.getId())
                              setDthAceitePrpci(Calendar.getInstance())
```

### 11.3 Marcos de auditoria do P08

| Ordem | Marco | Sub-processo | Forma de registro | Tem arquivo? |
|---|---|---|---|---|
| 1 | `UPLOAD_PRPCI` | P08-A | `incluiComArquivo()` se há PRPCI; `inclui()` se vazio | Sim (1.º PRPCI) |
| 2 | `LIBERACAO_APPCI` | P08-A | `inclui()` | Não |
| 3 | `ACEITE_PRPCI` | P08-B | `inclui()` | Não |
| 4 | `LIBERACAO_RENOV_APPCI` | P08-B | `inclui()` | Não |

Todos registrados via `LicenciamentoMarcoInclusaoRN`:
- `inclui(TipoMarco, LicenciamentoED)` — sem arquivo
- `incluiComArquivo(TipoMarco, LicenciamentoED, ArquivoED)` — com arquivo

---

## S12 — Regras de Negócio Consolidadas

| Código | Onde | Regra |
|---|---|---|
| **RN01** | `PrpciRNVal.validaParametro()` | A lista de arquivos enviada pelo RT não pode ser nula ou vazia. |
| **RN02** | `PrpciRNVal.validaSituacaoLicenciamento()` | Para o upload (P08-A), a situação do licenciamento deve ser exatamente `AGUARDANDO_PRPCI`. |
| **RN03** | `PrpciRNVal.validaSituacaoLicenciamentoRenovacao()` | Para o aceite (P08-B), a situação do licenciamento deve ser exatamente `AGUARDANDO_ACEITE_PRPCI`. |
| **RN04** | `PrpciRNVal.validaPermissaoUsuarioRuProp()` | Para o aceite (P08-B), o usuário logado deve ser RU, Procurador de RU, Proprietário PF ou Procurador de Proprietário do licenciamento. |
| **RN05** | `PrpciCidadaoRN.aceitePrpci()` | O licenciamento deve possuir ao menos 1 APPCI emitido (`!licenciamento.getAppcis().isEmpty()`) antes de permitir o aceite. |
| **RN06** | `PrpciCidadaoRN.inclui()` | Para cada arquivo recebido, é criado um `ArquivoED` (via `ArquivoRN`) e um `PrpciED` separado. Um licenciamento pode ter múltiplos PRPCIs. |
| **RN07** | `TrocaEstado.AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE` | O marco `UPLOAD_PRPCI` é registrado com o arquivo do primeiro PRPCI da lista; se a lista estiver vazia, registra sem arquivo (fallback). |
| **RN08** | `TrocaEstado.AGUARDANDO_PRPCI_PARA_ALVARA_VIGENTE` | Após o upload, dois marcos são registrados na mesma transação: `UPLOAD_PRPCI` e `LIBERACAO_APPCI`. |
| **RN09** | `TrocaEstado.AGUARDANDO_ACEITE_PRPCI_PARA_ALVARA_VIGENTE` | Após o aceite, dois marcos são registrados na mesma transação: `ACEITE_PRPCI` e `LIBERACAO_RENOV_APPCI`. |
| **RN10** | `TrocaEstado.EM_VISTORIA_PARA_AGUARDANDO_PRPCI` | A transição do P07 para o P08-A fecha o `PeriodoSolicitacao` do tipo `VISTORIA` via `PeriodoSolicitacaoRN.fecha()`. |
| **RN11** | `TrocaEstado.EM_VISTORIA_PARA_AGUARDANDO_ACEITE_PRPCI` | A transição do P07 para o P08-B também fecha o `PeriodoSolicitacao` do tipo `VISTORIA`. |
| **RN12** | `SegurancaEnvolvidoInterceptor` / `@AutorizaEnvolvido` | O usuário que chama qualquer endpoint do P08 deve ser um envolvido no licenciamento informado. |
| **RN13** | `ArquivoED.identificadorAlfresco` | O binário do PRPCI NUNCA é persistido no banco relacional. O campo `identificadorAlfresco` (nodeRef) é o único vínculo entre o banco e o Alfresco. |
| **RN14** | `TipoArquivo.EDIFICACAO` | Arquivos PRPCI são classificados no Alfresco com os atributos: `grp:familia=Documentos de Edificação`, `grp:categoria=Licenciamento`, `grp:subcategoria=Documentos`. |
| **RN15** | `PrpciCidadaoRN.verificaPermissoesUsuario()` | Consulta de permissão retorna `false` se: situação ≠ `AGUARDANDO_ACEITE_PRPCI` OU APPCIs ausentes OU usuário não é RU/Prop. |

---

## S13 — Fluxos Completos

### Fluxo P08-A — Emissão Normal (AGUARDANDO_PRPCI → ALVARA_VIGENTE)

```
Pré-condição: LicenciamentoED.situacao == AGUARDANDO_PRPCI
              (Transição anterior: P07 VistoriaHomologacaoAdmRN deferiu vistoria definitiva/parcial)

1. Usuário (RT ou Cidadão) acessa a tela de upload no frontend Angular

2. Usuário seleciona arquivo(s) PDF e submete o formulário

3. Frontend envia:
   PUT /api/prpci/{idLicenciamento}
   Headers:
     Authorization: Bearer <token_SOE_PROCERGS>
     Content-Type:  multipart/form-data
   Body:
     file = <binário PDF>

4. PrpciRestImpl.inclui() recebe a requisição:
   a. @AutorizaEnvolvido: SegurancaEnvolvidoInterceptor verifica que o usuário
      é um envolvido no licenciamento {idLicenciamento}
   b. MultipartFormUtil.getArquivosFromFormDataComNomeArquivo(formData, "file")
      extrai a lista de arquivos do multipart
   c. Chama PrpciCidadaoRN.inclui(idLicenciamento, arquivos)

5. PrpciCidadaoRN.inclui() executa:
   a. @Permissao(PRPCI/INCLUIR): PermissaoInterceptor valida o perfil do usuário
   b. PrpciRNVal.validaParametro(arquivos) → RN01
   c. LicenciamentoRN.consulta(idLicenciamento) → obtém LicenciamentoED
   d. PrpciRNVal.validaSituacaoLicenciamento(licenciamentoED.getSituacao()) → RN02
   e. Para cada Arquivo em arquivos:
      i.  ArquivoRN.incluirArquivo(arquivo, TipoArquivo.EDIFICACAO)
          - Cria ArquivoED (identificadorAlfresco = "0")
          - Persiste ArquivoED via JPA (INSERT CBM_ARQUIVO)
          - Envia binário ao Alfresco ECM
          - Recebe nodeRef: "workspace://SpacesStore/{UUID}"
          - Atualiza ArquivoED.identificadorAlfresco = nodeRef (UPDATE CBM_ARQUIVO)
      ii. BuilderPrpciED.of()
              .arquivo(arquivoED)
              .localizacao(licenciamentoED.getLocalizacao())
              .licenciamento(licenciamentoED)
              .instance() → PrpciED
      iii. PrpciRN.inclui(prpciED) → INSERT CBM_PRPCI
   f. trocaEstadoLicenciamentoRN.trocaEstado(idLicenciamento)
      ► TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente executa:
        i.   prpciRN.listaEDPorLicenciamento(idLicenciamento) → List<PrpciED>
        ii.  atualizaSituacaoLicenciamento(idLicenciamento)
             UPDATE CBM_LICENCIAMENTO SET TP_SITUACAO='ALVARA_VIGENTE' WHERE ...
        iii. Se prpcis não vazio:
               licenciamentoMarcoInclusaoRN.incluiComArquivo(
                   UPLOAD_PRPCI, licenciamentoED, prpcis.get(0).getArquivo())
             Senão:
               licenciamentoMarcoInclusaoRN.inclui(UPLOAD_PRPCI, licenciamentoED)
        iv.  licenciamentoMarcoInclusaoRN.inclui(LIBERACAO_APPCI, licenciamentoED)

6. PrpciRestImpl retorna Response.ok() → HTTP 200

Estado final: LicenciamentoED.situacao == ALVARA_VIGENTE
Marcos registrados: UPLOAD_PRPCI, LIBERACAO_APPCI
```

---

### Fluxo P08-B — Aceite de Renovação (AGUARDANDO_ACEITE_PRPCI → ALVARA_VIGENTE)

```
Pré-condição: LicenciamentoED.situacao == AGUARDANDO_ACEITE_PRPCI
              (Transição anterior: P07 VistoriaHomologacaoAdmRN deferiu vistoria de renovação)

1. Usuário (RU ou Proprietário) acessa a tela de aceite no frontend Angular

2. Frontend consulta permissão:
   GET /api/prpci/{idLicenciamento}/pode-aceite-prpci
   Headers: Authorization: Bearer <token_SOE_PROCERGS>
   ► PrpciCidadaoRN.verificaPermissoesUsuario(idLic)
     Retorna true se: (papel válido) AND (situação correta) AND (APPCI existe)
   Frontend exibe botão "Aceitar PRPCI" somente se retornar true

3. Usuário clica "Aceitar" e confirma

4. Frontend envia:
   PUT /api/prpci/{idLicenciamento}/termo/{idVistoria}/aceite-prpci
   Headers: Authorization: Bearer <token_SOE_PROCERGS>
   Content-Type: application/json

5. PrpciRestImpl.aceitePrpci() recebe a requisição:
   a. @AutorizaEnvolvido: SegurancaEnvolvidoInterceptor verifica envolvimento
   b. Chama PrpciCidadaoRN.aceitePrpci(idLic, idVistoria)

6. PrpciCidadaoRN.aceitePrpci() executa:
   a. @Permissao(PRPCI/INCLUIR): PermissaoInterceptor valida o perfil
   b. LicenciamentoRN.consulta(idLicenciamento) → obtém LicenciamentoED
   c. PrpciRNVal.validaSituacaoLicenciamentoRenovacao(situacao) → RN03
   d. Boolean hasPermission = verificaPermissoesUsuario(idLicenciamento)
      → isRU || isProcuradorRU || isProprietarioPF || isProcuradorProprietario
   e. PrpciRNVal.validaPermissaoUsuarioRuProp(hasPermission) → RN04
   f. Valida !licenciamentoED.getAppcis().isEmpty() → RN05
   g. VistoriaRN.consulta(idVistoria) → obtém VistoriaED
   h. Atualiza VistoriaED:
      vistoriaED.setIdUsuarioAceitePrpci(usuarioRN.getUsuarioLogado().getId())
      vistoriaED.setAceitePrpci(true)         → persiste 'S' em IND_ACEITE_PRPCI
      vistoriaED.setDthAceitePrpci(Calendar.getInstance())
      UPDATE CBM_VISTORIA SET IND_ACEITE_PRPCI='S',
             NRO_INT_USUARIO_ACEITE_PRPCI=..., DT_ACEITE_PRPCI=... WHERE ...
   i. trocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN
          .trocaEstado(idLicenciamento)
      ► TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN executa:
        i.  atualizaSituacaoLicenciamento(idLicenciamento)
            UPDATE CBM_LICENCIAMENTO SET TP_SITUACAO='ALVARA_VIGENTE' WHERE ...
        ii. licenciamentoMarcoInclusaoRN.inclui(ACEITE_PRPCI, licenciamentoED)
        iii.licenciamentoMarcoInclusaoRN.inclui(LIBERACAO_RENOV_APPCI, licenciamentoED)

7. PrpciRestImpl retorna Response.ok() → HTTP 200

Estado final: LicenciamentoED.situacao == ALVARA_VIGENTE
Campos atualizados em VistoriaED: aceitePrpci='S', idUsuarioAceitePrpci, dthAceitePrpci
Marcos registrados: ACEITE_PRPCI, LIBERACAO_RENOV_APPCI
```

---

## S14 — DDL Oracle

```sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Sequência da tabela CBM_PRPCI
-- ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE CBM_ID_PRPCI_SEQ
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;


-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela CBM_ARQUIVO — metadados dos arquivos binários (armazenados no Alfresco)
-- O binário NUNCA é persistido no banco relacional.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE CBM_ID_ARQUIVO_SEQ
    START WITH 1
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE TABLE CBM_ARQUIVO (
    NRO_INT_ARQUIVO               NUMBER        NOT NULL,
    NOME_ARQUIVO                  VARCHAR2(120),
    TXT_IDENTIFICADOR_ALFRESCO    VARCHAR2(150) NOT NULL,
    TXT_MD5_SGM                   VARCHAR2(255),
    TP_ARQUIVO                    VARCHAR2(50),
    NRO_CODIGO_AUTENTICACAO       VARCHAR2(255),
    ID_MIGRACAO_ALFRESCO          VARCHAR2(255),
    CTR_DTH_MIGRACAO_ALFRESCO     DATE,
    -- colunas de auditoria AppED (padrão do projeto)
    NRO_INT_USUARIO_INC           NUMBER,
    DTH_INCLUSAO                  DATE,
    NRO_INT_USUARIO_ALT           NUMBER,
    DTH_ALTERACAO                 DATE,
    CONSTRAINT PK_CBM_ARQUIVO PRIMARY KEY (NRO_INT_ARQUIVO)
);

-- Tabela de auditoria Hibernate Envers
CREATE TABLE CBM_ARQUIVO_AUD (
    NRO_INT_ARQUIVO               NUMBER        NOT NULL,
    REV                           NUMBER        NOT NULL,
    REVTYPE                       NUMBER(2),
    NOME_ARQUIVO                  VARCHAR2(120),
    TXT_IDENTIFICADOR_ALFRESCO    VARCHAR2(150),
    TXT_MD5_SGM                   VARCHAR2(255),
    TP_ARQUIVO                    VARCHAR2(50),
    NRO_CODIGO_AUTENTICACAO       VARCHAR2(255),
    CONSTRAINT PK_CBM_ARQUIVO_AUD PRIMARY KEY (NRO_INT_ARQUIVO, REV)
);


-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela CBM_PRPCI — documentos PRPCI vinculados a licenciamentos
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE CBM_PRPCI (
    NRO_INT_PRPCI         NUMBER NOT NULL,
    NRO_INT_ARQUIVO       NUMBER NOT NULL,
    NRO_INT_LOCALIZACAO   NUMBER,
    NRO_INT_LICENCIAMENTO NUMBER NOT NULL,
    CONSTRAINT PK_CBM_PRPCI              PRIMARY KEY (NRO_INT_PRPCI),
    CONSTRAINT FK_PRPCI_ARQUIVO          FOREIGN KEY (NRO_INT_ARQUIVO)
                                         REFERENCES CBM_ARQUIVO (NRO_INT_ARQUIVO),
    CONSTRAINT FK_PRPCI_LOCALIZACAO      FOREIGN KEY (NRO_INT_LOCALIZACAO)
                                         REFERENCES CBM_LOCALIZACAO (NRO_INT_LOCALIZACAO),
    CONSTRAINT FK_PRPCI_LICENCIAMENTO    FOREIGN KEY (NRO_INT_LICENCIAMENTO)
                                         REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO)
);

CREATE INDEX IDX_PRPCI_LICENCIAMENTO
    ON CBM_PRPCI (NRO_INT_LICENCIAMENTO);


-- ─────────────────────────────────────────────────────────────────────────────
-- Colunas de aceite PRPCI na tabela CBM_VISTORIA (existente — P07)
-- Executar como ALTER TABLE se a tabela foi criada sem estas colunas
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE CBM_VISTORIA
    ADD NRO_INT_USUARIO_ACEITE_PRPCI  NUMBER;          -- FK implícita CBM_USUARIO

ALTER TABLE CBM_VISTORIA
    ADD IND_ACEITE_PRPCI               CHAR(1)          -- 'S'/'N' (SimNaoBooleanConverter)
    CONSTRAINT CHK_VISTORIA_ACEITE_PRPCI CHECK (IND_ACEITE_PRPCI IN ('S', 'N'));

ALTER TABLE CBM_VISTORIA
    ADD DT_ACEITE_PRPCI                DATE;            -- Data/hora do aceite


-- ─────────────────────────────────────────────────────────────────────────────
-- Tabela CBM_APPCI — APPCIs emitidos (verificada em P08-B para validar existência)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE CBM_APPCI (
    NRO_INT_APPCI         NUMBER        NOT NULL,
    NRO_INT_ARQUIVO       NUMBER,
    NRO_INT_LOCALIZACAO   NUMBER,
    NRO_INT_LICENCIAMENTO NUMBER        NOT NULL,
    NRO_VERSAO            NUMBER,
    DTH_EMISSAO           DATE,
    DT_VALIDADE           DATE,
    IND_VERSAO_VIGENTE    CHAR(1)       CONSTRAINT CHK_APPCI_VIGENTE
                                        CHECK (IND_VERSAO_VIGENTE IN ('S','N')),
    DT_VIGENCIA_INICIO    DATE,
    DT_VIGENCIA_FIM       DATE,
    IND_RENOVACAO         CHAR(1)       CONSTRAINT CHK_APPCI_RENOVACAO
                                        CHECK (IND_RENOVACAO IN ('S','N')),
    IND_CIENCIA           CHAR(1)       CONSTRAINT CHK_APPCI_CIENCIA
                                        CHECK (IND_CIENCIA IN ('S','N')),
    CONSTRAINT PK_CBM_APPCI              PRIMARY KEY (NRO_INT_APPCI),
    CONSTRAINT FK_APPCI_ARQUIVO          FOREIGN KEY (NRO_INT_ARQUIVO)
                                         REFERENCES CBM_ARQUIVO (NRO_INT_ARQUIVO),
    CONSTRAINT FK_APPCI_LOCALIZACAO      FOREIGN KEY (NRO_INT_LOCALIZACAO)
                                         REFERENCES CBM_LOCALIZACAO (NRO_INT_LOCALIZACAO),
    CONSTRAINT FK_APPCI_LICENCIAMENTO    FOREIGN KEY (NRO_INT_LICENCIAMENTO)
                                         REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO)
);

CREATE INDEX IDX_APPCI_LICENCIAMENTO
    ON CBM_APPCI (NRO_INT_LICENCIAMENTO);
```

---

## S15 — Rastreabilidade: Código-Fonte → Requisito

| Arquivo-fonte | Classe/Enum/Método | Requisito coberto |
|---|---|---|
| `PrpciED.java` | `PrpciED` (@Entity CBM_PRPCI) | S2.1 — Entidade principal P08 |
| `ArquivoED.java` | `ArquivoED.identificadorAlfresco` | S2.2 — Integração Alfresco (nodeRef) |
| `AppciED.java` | `AppciED` (@Entity CBM_APPCI) | S2.3 — Pré-condição P08-B (APPCI existente) |
| `VistoriaED.java` | `aceitePrpci`, `idUsuarioAceitePrpci`, `dthAceitePrpci` | S2.4 — Registro do aceite P08-B |
| `LocalizacaoED.java` | `LocalizacaoED` (@Entity CBM_LOCALIZACAO) | S2.5 — Localização copiada para PrpciED |
| `LicenciamentoED.java` | `getAppcis()`, `getSituacao()`, `getLocalizacao()` | S2.6 — Campos acessados no P08 |
| `SituacaoLicenciamento.java` | `AGUARDANDO_PRPCI`, `AGUARDANDO_ACEITE_PRPCI`, `ALVARA_VIGENTE` | S3.1 — Máquina de estados |
| `TipoMarco.java` | `UPLOAD_PRPCI`, `LIBERACAO_APPCI`, `ACEITE_PRPCI`, `LIBERACAO_RENOV_APPCI` | S3.2 — Marcos de auditoria |
| `TipoArquivo.java` | `TipoArquivo.EDIFICACAO` + `getAtributos()` | S3.3 — Classificação Alfresco |
| `TrocaEstadoLicenciamentoEnum.java` | 4 valores P08 | S3.4 — Identificadores de transição |
| `PrpciRN.java` | `listaPorLicenciamento()`, `listaEDPorLicenciamento()` | S4.1 — Consultas de listagem |
| `PrpciCidadaoRN.java` | `inclui()` | S4.2 + S13 — P08-A: upload + transição de estado |
| `PrpciCidadaoRN.java` | `aceitePrpci()` | S4.2 + S13 — P08-B: aceite + transição de estado |
| `PrpciCidadaoRN.java` | `verificaPermissoesUsuario()` | S8.3 — Verificação de papéis |
| `PrpciRNVal.java` | `validaParametro()` | RN01 |
| `PrpciRNVal.java` | `validaSituacaoLicenciamento()` | RN02 |
| `PrpciRNVal.java` | `validaSituacaoLicenciamentoRenovacao()` | RN03 |
| `PrpciRNVal.java` | `validaPermissaoUsuarioRuProp()` | RN04 |
| `PrpciBD.java` | `PrpciBD` (Criteria Hibernate) | S4.4 — Persistência |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoPrpci.java` | `trocaEstado()` | S5.1 — Transição P07→P08-A |
| `TrocaEstadoLicenciamentoEmVistoriaParaAguardandoAceitePrpci.java` | `trocaEstado()` | S5.2 — Transição P07→P08-B |
| `TrocaEstadoLicenciamentoAguardandoPrpciParaAlvaraVigente.java` | `trocaEstado()` | S5.3 — Transição P08-A final |
| `TrocaEstadoLicenciamentoAguardandoAceitePrpciParaAlvaraVigenteRN.java` | `trocaEstado()` | S5.4 — Transição P08-B final |
| `PrpciRest.java` | Interface Swagger | S6.1 — Contrato REST |
| `PrpciRestImpl.java` | `inclui()` (PUT /{idLic}) | S6.2 — Endpoint P08-A |
| `PrpciRestImpl.java` | `aceitePrpci()` (PUT /{idLic}/termo/{idVistoria}/aceite-prpci) | S6.2 — Endpoint P08-B |
| `PrpciRestImpl.java` | `consultaUsuarioAceite()` (GET /{idLic}/pode-aceite-prpci) | S6.2 — Endpoint consulta |
| `PrpciDTO.java` | `PrpciDTO` | S7.1 — DTO de resposta |
| `BuilderPrpciDTO.java` | Builder fluente | S7.2 — Construção de DTO |
| `BuilderPrpciED.java` | Builder fluente | S7.3 — Construção de entidade |
| `PrpciToPrpciRelatorioDTOConverter.java` | `converte()` | S7.4 — Conversão para relatório |
| `LicenciamentoAdmNotificacaoRN.java` | `notificarConclusaoVistoria()` | S10.1 — Notificação P07→P08-A |
| `LicenciamentoAdmNotificacaoRN.java` | `notificarConclusaoVistoriaRenovacao()` | S10.2 — Notificação P07→P08-B |

---

## S16 — Regras de Negócio Normativas — RT de Implantação SOL-CBMRS 4ª Ed/2022

As regras a seguir complementam as RNs originais do processo P08 com base nas normas vigentes. Não substituem nenhuma regra já documentada.

---

### RN-P08-N1: Upload Obrigatório do PrPCI antes do Download do APPCI

**Referência normativa:** item 6.5.1 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

Por ocasião do acesso ao APPCI no SOL, o RT deve realizar o upload do **Projeto de Prevenção e Proteção Contra Incêndio — PrPCI** em formato PDF. O botão "Baixar APPCI" permanece desabilitado até que todos os componentes obrigatórios do PrPCI tenham sido enviados.

**Componentes obrigatórios do PrPCI (item 6.5.1.1):**

| Letra | Componente |
|---|---|
| a | Memoriais descritivos |
| b | Memórias de cálculo |
| c | Certificações |
| d | Relatórios técnicos de ensaios e especificações técnicas dos produtos e sistemas empregados |
| e | Certificados de treinamento |
| f | Plano de emergência (quando previsto no PPCI) |
| g | Laudos técnicos |
| h | ART/RRT de projeto, execução e dos laudos |
| i | Orientações ao proprietário sobre manutenções periódicas |
| j | Plantas baixas, cortes e detalhamentos necessários para correto dimensionamento |

**Comportamento do sistema:**

- Cada componente é marcado individualmente com flag booleano (`ind_memorial_descritivo`, `ind_memoria_calculo`, etc.) na tabela `sol.prpci` (DDL Bloco 18.9).
- O sistema só libera o botão "Baixar APPCI" quando todos os indicadores obrigatórios estiverem marcados como `true`.
- O upload do arquivo PDF principal (campo `arquivo_id`) é registrado com referência ao armazenamento de objetos (MinIO/Alfresco).
- O RT pode realizar os uploads em múltiplas sessões; o estado de preenchimento é preservado entre acessos.
- Após o upload completo, o sistema registra marco de auditoria `UPLOAD_PRPCI` com data/hora e identificador do RT.

**Impacto nos dados:** tabela `sol.prpci` (criada no DDL Bloco 18.9), com chave estrangeira para `sol.appci`.

---

### RN-P08-N2: Validade do APPCI Calculada Automaticamente

**Referência normativa:** itens 6.5.3.1 e 6.5.3.2 da RT de Implantação SOL-CBMRS 4ª Ed/2022; item 5.3.1 da RTCBMRS N.º 01/2024.

O sistema calcula automaticamente a validade do APPCI no momento da emissão, com base no tipo de ocupação predominante e no grau de risco da edificação:

| Critério | Validade |
|---|---|
| Locais de elevado risco de incêndio e sinistro (item 5.3.1 da RTCBMRS N.º 01/2024) | **2 (dois) anos** |
| Edificações do grupo "F" com grau de risco **médio** ou **alto** | **2 (dois) anos** |
| Demais edificações sujeitas a PPCI | **5 (cinco) anos** |

**Comportamento do sistema:**

- A função `sol.calcular_validade_appci()` (DDL Bloco 18.7) é invocada na geração do APPCI para determinar o intervalo de validade aplicável.
- A data de vencimento é exibida na tela de emissão do APPCI, antes da confirmação pelo operador/RT.
- O sistema exibe alerta destacado: "Solicite a renovação com pelo menos 2 meses de antecedência (até [data-limite de renovação]).", onde a data-limite é calculada como `dt_vencimento_appci - 2 meses`.
- A data de vencimento é armazenada no campo correspondente da entidade `AppciED`/tabela `sol.appci`.

**Impacto nos dados:** campo de validade e data de vencimento na tabela `sol.appci`; função `sol.calcular_validade_appci()` (DDL Bloco 18.7).

---

### RN-P08-N3: APPCI Somente Emitido após Quitação de Todas as Taxas e Multas

**Referência normativa:** item 6.5.3.3 da RT de Implantação SOL-CBMRS 4ª Ed/2022.

A emissão do APPCI é condicionada à quitação integral de todas as taxas e multas devidas pelo licenciamento.

**Comportamento do sistema:**

- Antes de liberar o botão "Emitir APPCI" (sub-fluxo P08-A) ou "Confirmar Aceite" (sub-fluxo P08-B), o sistema verifica automaticamente a situação financeira do licenciamento.
- A verificação consulta os boletos vinculados (`sol.boleto`) e confirma que todos os boletos em situação `ABERTO` ou `VENCIDO` encontram-se quitados (`PAGO`).
- Caso existam débitos pendentes, o sistema exibe mensagem bloqueante: "Existem taxas ou multas não quitadas associadas a este licenciamento. O APPCI não pode ser emitido até a regularização financeira completa."
- O operador de administração pode consultar o extrato financeiro do licenciamento a partir da mesma tela de emissão.
- Após a quitação, o sistema detecta automaticamente a mudança de situação dos boletos (via integração PROCERGS/CNAB 240) e desbloqueia a emissão sem necessidade de ação manual do operador.

---

*Documento gerado para o Projeto SOL — CBM-RS. Baseado integralmente no código-fonte
`SOLCBM.BackEnd16-06`. Stack: WildFly/JBoss · Java EE 7 · JAX-RS · CDI · JPA/Hibernate
· EJB @Stateless · SOE PROCERGS (meu.rs.gov.br) · Alfresco ECM · Oracle DB.*
