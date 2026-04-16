# Requisitos P05 — Ciência do CIA/CIV e Recurso Administrativo
## Stack Atual (Java EE — sem alterações tecnológicas)

**Projeto:** Sistema SOL — Corpo de Bombeiros Militar do Rio Grande do Sul (CBM-RS)
**Processo:** P05 — Ciência do CIA/CIV e Recurso Administrativo
**Versão:** Stack atual — JAX-RS, CDI, EJB, JPA/Hibernate, Alfresco, WildFly/JBoss
**Data:** 2026-03-09

---

## Sumário

1. [Visão Geral e Escopo](#1-visão-geral-e-escopo)
2. [Stack Tecnológica](#2-stack-tecnológica)
3. [Modelo de Domínio — Entidades JPA](#3-modelo-de-domínio--entidades-jpa)
4. [Interfaces de Domínio](#4-interfaces-de-domínio)
5. [Enumerações](#5-enumerações)
6. [Qualificador CDI de Ciência](#6-qualificador-cdi-de-ciência)
7. [Camada de Negócio — Ciência do CIA/CIV](#7-camada-de-negócio--ciência-do-ciaciv)
8. [Camada de Negócio — Recurso Administrativo](#8-camada-de-negócio--recurso-administrativo)
9. [Camada de Negócio — Análise pelo Colegiado](#9-camada-de-negócio--análise-pelo-colegiado)
10. [Job de Ciência Automática](#10-job-de-ciência-automática)
11. [Camada de Acesso a Dados (BD)](#11-camada-de-acesso-a-dados-bd)
12. [Camada REST (JAX-RS)](#12-camada-rest-jax-rs)
13. [Segurança — @Permissao e SessionMB](#13-segurança--permissao-e-sessionmb)
14. [Armazenamento de Arquivos — Alfresco](#14-armazenamento-de-arquivos--alfresco)
15. [Marcos e Trilha de Auditoria](#15-marcos-e-trilha-de-auditoria)
16. [Transições de Estado](#16-transições-de-estado)
17. [Validações — RecursoRNVal](#17-validações--recursoRNVal)
18. [Tabelas do Banco de Dados](#18-tabelas-do-banco-de-dados)
19. [Fluxos de Negócio Detalhados](#19-fluxos-de-negócio-detalhados)
20. [Estrutura de Pacotes](#20-estrutura-de-pacotes)

---

## 1. Visão Geral e Escopo

O processo P05 abrange duas sub-jornadas interdependentes do ciclo de vida de um licenciamento PPCI:

### Sub-jornada A — Ciência do CIA/CIV

Após a emissão de um Comunicado de Inconformidade na Análise (CIA) ou Comunicado de Inconformidade na Vistoria (CIV), o cidadão (RT, RU ou Proprietário) deve tomar ciência formal do documento. A ciência pode ocorrer de duas formas:

- **Manual:** o cidadão acessa o sistema e confirma a ciência através de um endpoint REST.
- **Automática:** um job EJB Timer (`@Schedule`) verifica periodicamente se já se passaram 30 dias sem ciência manual e, em caso positivo, registra a ciência automaticamente em nome do sistema.

Tipos de ciência suportados (`TipoLicenciamentoCiencia`):

| Tipo | Documento | Entidade alvo | Próxima situação (reprovado) |
|---|---|---|---|
| `ATEC` | CIA de análise técnica | `AnaliseLicenciamentoTecnicaED` | `NCA` |
| `INVIABILIDADE` | CIA de análise de inviabilidade | `AnaliseLicInviabilidadeED` | `NCA` |
| `CIV` | CIV de vistoria | `VistoriaED` | `CIV` |
| `APPCI` | APPCI vigente | `AppciED` | N/A (sempre aprovado → `ALVARA_VIGENTE`) |
| `APPCI_RENOV` | APPCI renovação | `AppciED` | N/A (sempre aprovado → `ALVARA_VIGENTE`) |

### Sub-jornada B — Recurso Administrativo

Após ciência de CIA ou CIV (e apenas em caso de reprovação), o cidadão pode interpor recurso administrativo contestando a decisão do CBM-RS. O recurso possui:

- **1ª instância:** prazo de 30 dias após a ciência do CIA/CIV.
- **2ª instância:** prazo de 15 dias após a ciência da resposta da 1ª instância. Cabível somente se a 1ª instância foi indeferida (total ou parcialmente).

O processo interno de análise do recurso pelo CBM-RS envolve distribuição, análise individual (1ª instância) ou por colegiado (2ª instância), emissão de despacho e geração de PDF autenticado via JasperReports + Alfresco.

Após a análise, o cidadão deve tomar ciência da resposta. Se não houver ciência manual, o job automático registra a ciência após o prazo configurado.

---

## 2. Stack Tecnológica

| Componente | Tecnologia | Notas |
|---|---|---|
| Linguagem | Java EE (JDK 8+) | |
| Servidor | WildFly / JBoss | |
| Backend REST | JAX-RS (RESTEasy) | `@Path`, `@GET`, `@POST`, `@PUT`, `@DELETE` |
| Injeção de dependência | CDI (`javax.inject`) | `@Inject`, `@Qualifier` |
| Componentes de negócio | EJB (`@Stateless`) | `@TransactionAttribute` |
| Persistência | JPA / Hibernate | `@Entity`, `@SequenceGenerator`, `@NamedQuery` |
| Auditoria de campos | Campos `ctrDthInc`, `ctrDthAtu`, `ctrUsuInc` (AppED) | |
| Conversores JPA | `SimNaoBooleanConverter` (`Boolean` ↔ `'S'/'N'`) | |
| Jobs automáticos | EJB Timer (`@Schedule`) | `persistent=false` |
| Armazenamento de arquivos | Alfresco (campo `identificadorAlfresco`) | `ArquivoRN.incluirArquivo()` |
| Geração de relatórios | JasperReports | `DocumentoRelatorioAnaliseRecursoRN` |
| Segurança | `@Permissao(objeto, acao)` + `SessionMB` | Framework arqjava4 |
| Autenticação | SOE PROCERGS / meu.rs.gov.br (OAuth2/OIDC) | |
| Lombok | `@Getter`, `@Setter`, `@Builder`, `@AllArgsConstructor`, `@NoArgsConstructor` | |

---

## 3. Modelo de Domínio — Entidades JPA

### 3.1 RecursoED

```java
package com.procergs.solcbm.ed;

@Builder
@Getter @Setter
@Entity
@AllArgsConstructor @NoArgsConstructor
@Table(name = "CBM_RECURSO")
@NamedQueries(value = {
    @NamedQuery(name = "RecursoED.consulta",
        query = "select r from RecursoED r join fetch r.licenciamentoED where r.id = :id")
})
public class RecursoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "Recurso_SEQ", sequenceName = "CBM_ID_RECURSO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "Recurso_SEQ")
    @Column(name = "NRO_INT_RECURSO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO")
    @OneToOne(fetch = FetchType.LAZY)
    private LicenciamentoED licenciamentoED;

    @NotNull
    @Column(name = "NRO_INSTANCIA")
    private Integer instancia;                       // 1 = 1ª instância, 2 = 2ª instância

    @NotNull
    @Column(name = "TP_SITUACAO")
    @Enumerated                                       // ordinal
    private SituacaoRecurso situacao;

    @NotNull
    @Column(name = "TP_RECURSO")
    @Enumerated                                       // ordinal
    private TipoRecurso tipoRecurso;

    @NotNull
    @Column(name = "TP_SOLICITACAO")
    @Enumerated                                       // ordinal
    private TipoSolicitacaoRecurso tipoSolicitacao;

    @Column(name = "TXT_FUNDAMENTACAO_LEGAL")
    private String fundamentacaoLegal;

    @Column(name = "DTH_ENVIO_ANALISE")
    private LocalDateTime dataEnvioAnalise;           // preenchido ao concluir aceites

    @JoinColumn(name = "NRO_INT_ARQUIVO_CIA_CIV")
    @ManyToOne(fetch = FetchType.LAZY)
    private ArquivoED arquivoCiaCivED;               // CIA ou CIV contestado

    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idUsuarioSoe;                        // analista designado (preenchido na distribuição)

    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoProprietarioED> solicitacaoProprietarios;

    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoResponsavelTecnicoED> solicitacaoResponsaveisTecnicos;

    @OneToMany(mappedBy = "recursoED", fetch = FetchType.LAZY)
    private Set<SolicitacaoResponsavelUsuarioED> solicitacaoResponsaveisUso;
}
```

**Campos de controle herdados de AppED:**

| Campo | Coluna | Descrição |
|---|---|---|
| `ctrDthInc` | `CTR_DTH_INC` | Data/hora de inclusão |
| `ctrDthAtu` | `CTR_DTH_ATU` | Data/hora de atualização |
| `ctrUsuInc` | `CTR_USU_INC` | ID do usuário que incluiu |
| `ctrUsuAtu` | `CTR_USU_ATU` | ID do usuário que atualizou |
| `ctrNroIpInc` | `CTR_NRO_IP_INC` | IP de inclusão |

---

### 3.2 AnaliseRecursoED

```java
@Builder @AllArgsConstructor @NoArgsConstructor
@Getter @Setter
@Entity
@Table(name = "CBM_ANALISE_RECURSO")
@NamedQueries(value = {
    @NamedQuery(name = "AnaliseRecursoED.consulta",
        query = "select ar from AnaliseRecursoED ar join fetch ar.recursoED where ar.id = :id")
})
public class AnaliseRecursoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "AnaliseRecurso_SEQ", sequenceName = "CBM_ID_ANALISE_RECURSO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "AnaliseRecurso_SEQ")
    @Column(name = "NRO_INT_ANALISE_RECURSO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_RECURSO")
    @OneToOne(fetch = FetchType.LAZY)
    private RecursoED recursoED;

    @Column(name = "TP_STATUS")
    @Enumerated                                       // ordinal — StatusRecurso
    private StatusRecurso status;                     // decisão final: DEFERIDO_TOTAL, DEFERIDO_PARCIAL, INDEFERIDO

    @Column(name = "TXT_DESPACHO")
    private String despacho;                          // texto do parecer/decisão

    @NotNull
    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idUsuarioSoe;                        // analista que concluiu

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "DTH_CIENCIA_ATEC")
    private Calendar dthCienciaAtec;                 // data/hora da ciência da resposta

    @Column(name = "NRO_INT_USUARIO_CIENCIA")
    private Long idUsuarioCiencia;                    // ID do usuário que tomou ciência

    @Column(name = "IND_CIENCIA")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean ciencia;                          // false = aguardando ciência; true = ciência registrada

    @OneToOne
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    private ArquivoED arquivo;                        // PDF do relatório de análise (Alfresco)

    @NotNull
    @Column(name = "TP_SITUACAO")
    @Enumerated(EnumType.STRING)
    private SituacaoAnaliseRecursoEnum situacao;      // EM_ANALISE, AGUARDANDO_AVALIACAO_COLEGIADO, ANALISE_CONCLUIDA

    @Column(name = "CTR_DTH_CONCLUSAO_ANALISE")
    @Temporal(TemporalType.TIMESTAMP)
    private Calendar dataConclusaoAnalise;
}
```

---

### 3.3 RecursoMarcoED

```java
@Builder @Getter @Setter
@Entity
@Table(name = "CBM_RECURSO_MARCO")
@AllArgsConstructor @NoArgsConstructor
@NamedQueries(value = {
    @NamedQuery(name = "RecursoMarcoED.consulta",
        query = "select r from RecursoMarcoED r join fetch r.recursoED "
              + "left join fetch r.parametroMarco left join fetch r.usuarioED where r.id = :id")
})
public class RecursoMarcoED extends AppED<Long> implements Serializable {

    @Id
    @SequenceGenerator(name = "RECURSO_MARCO_SEQ", sequenceName = "CBM_ID_RECURSO_MARCO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "RECURSO_MARCO_SEQ")
    @Column(name = "NRO_INT_RECURSO_MARCO")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_RECURSO")
    private RecursoED recursoED;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_PARAMETRO_MARCO")
    private ParametroMarcoED parametroMarco;          // parâmetro configurável de marco

    @Column(name = "DTH_MARCO")
    @NotNull
    private Calendar dthMarco;

    @Column(name = "TXT_DESCRICAO")
    @NotNull
    @Size(max = 100)
    private String descricao;

    @Column(name = "COD_TP_VISIBILIDADE")
    @NotNull
    @Enumerated(EnumType.ORDINAL)
    private TipoVisibilidadeMarco visibilidade;       // PUBLICO, BOMBEIROS

    @Column(name = "NRO_INT_ARQUIVO")
    private Long arquivoId;                           // ID do arquivo associado ao marco

    @Column(name = "TXT_TITULO_ARQUIVO")
    private String tituloArquivo;

    @Column(name = "TP_RESPONSAVEL")
    @NotNull
    @Enumerated(EnumType.STRING)
    private TipoResponsavelMarco tipoResponsavel;     // CIDADAO, SISTEMA, BOMBEIROS

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO_RESP")
    private UsuarioED usuarioED;                      // usuário local (se disponível)

    @Column(name = "NRO_INT_USUARIO_SOE_RESP")
    private Long usuarioSoeId;                        // ID no SOE PROCERGS

    @Column(name = "NOME_RESPONSAVEL")
    private String usuarioSoeNome;                    // "SOLCBM" para ações do sistema

    @Column(name = "VALOR_NOMINAL")
    private BigDecimal valorNominal;

    @Column(name = "TXT_COMPLEMENTAR")
    @Size(max = 255)
    private String textoComplementar;
}
```

---

### 3.4 RecursoArquivoED

```java
@Builder @Getter @Setter
@Entity
@AllArgsConstructor @NoArgsConstructor
@Table(name = "CBM_RECURSO_ARQUIVO")
@NamedQueries(value = {
    @NamedQuery(name = "RecursoArquivoED.consulta",
        query = "select ra from RecursoArquivoED ra join fetch ra.recursoED where ra.id = :id")
})
public class RecursoArquivoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "RecursoArquivo_SEQ", sequenceName = "CBM_ID_RECURSO_ARQUIVO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "RecursoArquivo_SEQ")
    @Column(name = "NRO_INT_RECURSO_ARQUIVO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_RECURSO")
    @OneToOne(fetch = FetchType.LAZY)
    private RecursoED recursoED;

    @NotNull
    @JoinColumn(name = "NRO_INT_ARQUIVO")
    @OneToOne(fetch = FetchType.LAZY)
    private ArquivoED arquivoED;                      // arquivo anexado ao recurso (documentos do cidadão)
}
```

---

### 3.5 AvalistaRecursoED

```java
@Builder @AllArgsConstructor @NoArgsConstructor
@Getter @Setter
@Entity
@Table(name = "CBM_AVALISTA_RECURSO")
@NamedQueries(value = {
    @NamedQuery(name = "AvalistaRecursoED.consulta",
        query = "select av from AvalistaRecursoED av join fetch av.analiseRecursoED where av.id = :id")
})
public class AvalistaRecursoED extends AppED<Long> implements Serializable {

    @Id
    @SequenceGenerator(name = "AvalistaRecurso_SEQ", sequenceName = "CBM_ID_AVALISTA_RECURSO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "AvalistaRecurso_SEQ")
    @Column(name = "NRO_INT_AVALISTA_RECURSO")
    private Long id;

    @NotNull
    @JoinColumn(name = "NRO_INT_ANALISE_RECURSO")
    @ManyToOne(fetch = FetchType.LAZY)
    private AnaliseRecursoED analiseRecursoED;        // análise à qual este avalistapertence

    @NotNull
    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idUsuarioSoe;                        // ID do avalistaSOE

    @Column(name = "IND_ACEITE")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean aceite;                           // false = votou contra; true = concordou; null = não votou

    @Column(name = "TXT_JUSTIFICATIVA")
    @Size(max = 4000)
    private String justificativaNaoConcordo;          // texto da discordância
}
```

---

## 4. Interfaces de Domínio

### 4.1 Ciencia

```java
package com.procergs.solcbm.ed;

public interface Ciencia {

    Calendar getDthCiencia();
    void setDthCiencia(Calendar dthCiencia);

    UsuarioED getUsuarioCiencia();
    void setUsuarioCiencia(UsuarioED usuarioCiencia);

    Boolean getCiencia();
    void setCiencia(Boolean ciencia);

    default boolean possuiCiencia() {
        return Boolean.TRUE.equals(getCiencia());
    }
}
```

**Notas de implementação:**
- `getCiencia()` retorna `null` quando ainda não houve ciência, `Boolean.TRUE` quando confirmada.
- O método `possuiCiencia()` usa `Boolean.TRUE.equals()` para ser null-safe.
- `UsuarioED` referencia o usuário local do sistema. Para ciência automática, não é preenchido (somente `idUsuarioCiencia` via campo direto na entidade concreta).

### 4.2 LicenciamentoCiencia

```java
package com.procergs.solcbm.ed;

public interface LicenciamentoCiencia extends Licenciamento, Ciencia {

    ArquivoED getArquivo();        // retorna o CIA ou CIV associado
    void setArquivo(ArquivoED arquivo);
}
```

**Implementadores:**
- `AnaliseLicenciamentoTecnicaED` — implementa para `TipoLicenciamentoCiencia.ATEC`
- `AnaliseLicInviabilidadeED` — implementa para `TipoLicenciamentoCiencia.INVIABILIDADE`
- `VistoriaED` — implementa para `TipoLicenciamentoCiencia.CIV`
- `AppciED` — implementa para `TipoLicenciamentoCiencia.APPCI` e `APPCI_RENOV`

### 4.3 LicenciamentoCienciaRN (interface de comportamento)

```java
package com.procergs.solcbm.licenciamentociencia;

public interface LicenciamentoCienciaRN {
    void alteraLicenciamentoCiencia(LicenciamentoCiencia licenciamentoCiencia);
    boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia licenciamentoCiencia);
    TipoMarco getTipoMarco(LicenciamentoCiencia licenciamentoCiencia);
}
```

### 4.4 LicenciamentoCienciaCidadaoRN (interface para ciência manual)

```java
package com.procergs.solcbm.licenciamentociencia;

public interface LicenciamentoCienciaCidadaoRN extends LicenciamentoCienciaRN {
    void efetuarCiencia(LicenciamentoCiencia licenciamentoCiencia);
}
```

### 4.5 LicenciamentoCienciaAutomaticaRN (interface para ciência automática)

```java
package com.procergs.solcbm.licenciamentociencia;

public interface LicenciamentoCienciaAutomaticaRN extends LicenciamentoCienciaRN {
    void efetuaCienciaAutomatica(Calendar dataLimite);
    List<LicenciamentoCiencia> listarPendentesDeCiencia(Calendar dataLimite);
}
```

---

## 5. Enumerações

### 5.1 TipoLicenciamentoCiencia

```java
package com.procergs.solcbm.enumeration;

public enum TipoLicenciamentoCiencia {
    ATEC,           // Análise Técnica — CIA de análise técnica
    INVIABILIDADE,  // Análise de Inviabilidade — CIA de inviabilidade
    CIV,            // Vistoria — CIV
    APPCI,          // APPCI vigente (nova emissão)
    APPCI_RENOV     // APPCI renovação
}
```

**Uso:** este enum é o atributo do `@LicenciamentoCienciaQualifier`, resolvendo qual implementação de ciência CDI injetar.

### 5.2 SituacaoRecurso

```java
@Getter @AllArgsConstructor
public enum SituacaoRecurso {
    AGUARDANDO_APROVACAO_ENVOLVIDOS("E"),  // aceites pendentes de RT/RU/Proprietário
    AGUARDANDO_DISTRIBUICAO("D"),           // aceites concluídos, aguardando analista
    ANALISE_CONCLUIDA("C"),                 // despacho emitido, aguardando ciência
    EM_ANALISE("A"),                        // analista designado e analisando
    CANCELADO("CA"),                        // cancelado
    RASCUNHO("R");                          // não enviado

    private String descricao;
}
```

**Persistência:** `@Enumerated` (ordinal) na coluna `TP_SITUACAO`.

### 5.3 TipoRecurso

```java
@Getter @AllArgsConstructor
public enum TipoRecurso {
    CORRECAO_DE_ANALISE("A"),   // recurso contra CIA (análise técnica ou inviabilidade)
    CORRECAO_DE_VISTORIA("V");  // recurso contra CIV (vistoria)

    private String descricao;
}
```

**Persistência:** `@Enumerated` (ordinal) na coluna `TP_RECURSO`.

### 5.4 TipoSolicitacaoRecurso

```java
@Getter @AllArgsConstructor
public enum TipoSolicitacaoRecurso {
    INTEGRAL("I"),  // solicita anulação total da decisão
    PARCIAL("P");   // solicita revisão de itens específicos

    private String tipo;
}
```

**Persistência:** `@Enumerated` (ordinal) na coluna `TP_SOLICITACAO`.

### 5.5 StatusRecurso (resultado da análise)

```java
@Getter @AllArgsConstructor
public enum StatusRecurso {
    DEFERIDO_TOTAL("T"),    // recurso integralmente acolhido
    DEFERIDO_PARCIAL("P"),  // recurso parcialmente acolhido
    INDEFERIDO("I");        // recurso negado

    private String status;
}
```

**Persistência:** `@Enumerated` (ordinal) na coluna `TP_STATUS` de `AnaliseRecursoED`.

### 5.6 SituacaoAnaliseRecursoEnum

```java
public enum SituacaoAnaliseRecursoEnum {
    EM_ANALISE,                        // analista preenchendo parecer
    AGUARDANDO_AVALIACAO_COLEGIADO,    // enviado para votação do colegiado
    ANALISE_CONCLUIDA                  // despacho emitido
}
```

**Persistência:** `@Enumerated(EnumType.STRING)` na coluna `TP_SITUACAO` de `AnaliseRecursoED`.

### 5.7 TipoMarco — valores relevantes ao P05

```java
// Marcos de ciência de CIA/CIV (no licenciamento)
CIENCIA_CIA_ATEC,
CIENCIA_CA_ATEC,
CIENCIA_CIA_INVIABILIDADE,
CIENCIA_CA_INVIABILIDADE,
CIENCIA_CIV,
CIENCIA_CIV_RENOVACAO,
CIENCIA_APPCI,
CIENCIA_APPCI_RENOVACAO,

// Marcos de ciência automática de CIA/CIV (no licenciamento)
CIENCIA_AUTO_CIA_ATEC,
CIENCIA_AUTO_CA_ATEC,
CIENCIA_AUTO_CIA_INVIABILIDADE,
CIENCIA_AUTO_CA_INVIABILIDADE,
CIENCIA_AUTO_CIV,

// Marcos do recurso
ENVIO_RECURSO_ANALISE,
DISTRIBUICAO_ANALISE_RECURSO,
CANCELA_DISTRIBUICAO_ANALISE_RECURSO,
ANALISE_RECURSO_COLEGIADO,        // avalista do colegiado votou
FIM_ANALISE_RECURSO_COLEGIADO,    // todos avalistasvotaram
ENVIO_PARA_COLEGIADO,             // analista enviou ao colegiado
RESPOSTA_RECURSO,                 // despacho 1ª instância
RESPOSTA_RECURSO_2,               // despacho 2ª instância
CIENCIA_RECURSO,                  // ciência da resposta (manual ou automática)
DOCUMENTO_CIA_CIV_CANCELADO,      // CIA/CIV anulado (recurso DEFERIDO_TOTAL + INTEGRAL)
EXCLUSAO_MEMBRO_JUNTA_TECNICA     // avalista removido do colegiado
```

### 5.8 TipoResponsavelMarco

```java
public enum TipoResponsavelMarco {
    CIDADAO,    // ação do RT, RU ou Proprietário
    SISTEMA,    // ação automática do job
    BOMBEIROS   // ação do analista/coordenador CBM-RS
}
```

### 5.9 TipoVisibilidadeMarco

```java
public enum TipoVisibilidadeMarco {
    PUBLICO,    // visível para todos (cidadão e CBM-RS)
    BOMBEIROS   // visível apenas para CBM-RS
}
```

---

## 6. Qualificador CDI de Ciência

```java
package com.procergs.solcbm.qualifier;

@Target({ TYPE, FIELD, PARAMETER })
@Retention(RetentionPolicy.RUNTIME)
@Qualifier
public @interface LicenciamentoCienciaQualifier {
    TipoLicenciamentoCiencia tipoLicenciamentoCiencia();
}
```

**Mapeamento de implementações:**

| `tipoLicenciamentoCiencia` | Implementação (cidadão) | Implementação (automática) |
|---|---|---|
| `ATEC` | `AnaliseLicenciamentoTecnicaCienciaCidadaoRN` | `AnaliseLicenciamentoTecnicaCienciaAutomaticaRN` |
| `INVIABILIDADE` | `AnaliseLicInviabilidadeCienciaCidadaoRN` | `AnaliseLicInviabilidadeCienciaAutomaticaRN` |
| `CIV` | `CivCienciaCidadaoRN` | `CivCienciaAutomaticaRN` |
| `APPCI` | `AppciCienciaCidadaoRN` | — (sem automática) |
| `APPCI_RENOV` | `AppciCienciaCidadaoRenovacaoRN` | — (sem automática) |

---

## 7. Camada de Negócio — Ciência do CIA/CIV

### 7.1 Hierarquia de classes

```
LicenciamentoCienciaRN (interface)
├── LicenciamentoCienciaCidadaoRN (interface)
│   └── LicenciamentoCienciaCidadaoBaseRN (abstract)
│       ├── AnaliseLicenciamentoTecnicaCienciaCidadaoRN  (@ATEC)
│       ├── AnaliseLicInviabilidadeCienciaCidadaoRN      (@INVIABILIDADE)
│       ├── CivCienciaCidadaoRN                          (@CIV)
│       ├── AppciCienciaCidadaoRN                        (@APPCI)
│       └── AppciCienciaCidadaoRenovacaoRN               (@APPCI_RENOV)
└── LicenciamentoCienciaAutomaticaRN (interface)
    └── LicenciamentoCienciaAutomaticaBaseRN (abstract)
        ├── AnaliseLicenciamentoTecnicaCienciaAutomaticaRN  (@ATEC)
        ├── AnaliseLicInviabilidadeCienciaAutomaticaRN      (@INVIABILIDADE)
        └── CivCienciaAutomaticaRN                          (@CIV)
```

### 7.2 LicenciamentoCienciaBaseRN (classe base abstrata)

```java
package com.procergs.solcbm.licenciamentociencia;

public abstract class LicenciamentoCienciaBaseRN {

    @Inject
    private LicenciamentoRN licenciamentoRN;

    @Inject
    private DataAtualHelper dataAtualHelper;

    protected abstract boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc);
    protected abstract SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado();

    protected void atualizarLicenciamento(LicenciamentoCiencia lc) {
        if (!isLicenciamentoCienciaAprovado(lc)) {
            if (lc.getLicenciamento().getSituacao().equals(SituacaoLicenciamento.EXTINGUIDO)) {
                licenciamentoRN.atualizarComSituacao(lc.getLicenciamento(), SituacaoLicenciamento.EXTINGUIDO);
            } else {
                licenciamentoRN.atualizarComSituacao(lc.getLicenciamento(),
                    getProximoStatusLicenciamentoCienciaReprovado());
            }
        }
        // Se aprovado: a transição de estado para CA/ALVARA_VIGENTE ocorre
        // em outro ponto do fluxo (fora da ciência em si).
    }

    protected void aplicarCienciaBase(Ciencia ciencia) {
        ciencia.setCiencia(true);
        ciencia.setDthCiencia(dataAtualHelper.getDataAtual());
    }
}
```

### 7.3 LicenciamentoCienciaCidadaoBaseRN (ciência manual)

```java
package com.procergs.solcbm.licenciamentociencia;

public abstract class LicenciamentoCienciaCidadaoBaseRN
        extends LicenciamentoCienciaBaseRN implements LicenciamentoCienciaCidadaoRN {

    @Inject
    @LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.CIDADAO)
    private LicenciamentoMarcoInclusaoRN licenciamentoMarcoCidadaoRN;

    @Inject
    protected UsuarioRN usuarioRN;

    @Override
    public void efetuarCiencia(LicenciamentoCiencia licenciamentoCiencia) {
        UsuarioED usuarioED = usuarioRN.getUsuarioLogado();

        // 1. Aplica ciência com dados do usuário logado
        aplicarCienciaBase(licenciamentoCiencia);
        licenciamentoCiencia.setUsuarioCiencia(usuarioED);

        // 2. Persiste na entidade específica (AnaliseLicenciamentoTecnicaED, VistoriaED, etc.)
        alteraLicenciamentoCiencia(licenciamentoCiencia);

        // 3. Atualiza situação do licenciamento (NCA, CIV, etc.)
        atualizarLicenciamento(licenciamentoCiencia);

        // 4. Registra marco no licenciamento (TipoResponsavelMarco.CIDADAO)
        licenciamentoMarcoCidadaoRN.incluiComArquivo(
            getTipoMarco(licenciamentoCiencia),
            licenciamentoCiencia.getLicenciamento(),
            licenciamentoCiencia.getArquivo());
    }
}
```

### 7.4 LicenciamentoCienciaAutomaticaBaseRN (ciência automática)

```java
package com.procergs.solcbm.licenciamentociencia;

public abstract class LicenciamentoCienciaAutomaticaBaseRN
        extends LicenciamentoCienciaBaseRN implements LicenciamentoCienciaAutomaticaRN {

    @Inject
    @LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.SISTEMA)
    private LicenciamentoMarcoInclusaoRN licenciamentoMarcoSistemaRN;

    @Override
    public void efetuaCienciaAutomatica(Calendar dataLimite) {
        listarPendentesDeCiencia(dataLimite).forEach(this::efetuarCienciaAutomatica);
    }

    protected void efetuarCienciaAutomatica(LicenciamentoCiencia licenciamentoCiencia) {
        // 1. Aplica ciência (sem usuário, apenas data)
        aplicarCienciaBase(licenciamentoCiencia);

        // 2. Persiste na entidade específica
        alteraLicenciamentoCiencia(licenciamentoCiencia);

        // 3. Atualiza situação do licenciamento
        atualizarLicenciamento(licenciamentoCiencia);

        // 4. Registra marco no licenciamento (TipoResponsavelMarco.SISTEMA)
        licenciamentoMarcoSistemaRN.incluiComArquivo(
            getTipoMarco(licenciamentoCiencia),
            licenciamentoCiencia.getLicenciamento(),
            licenciamentoCiencia.getArquivo());
    }
}
```

### 7.5 Implementações concretas de ciência

#### AnaliseLicenciamentoTecnicaCienciaCidadaoRN

```java
@Stateless
@AppInterceptor
@TransactionAttribute(TransactionAttributeType.REQUIRED)
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.ATEC)
public class AnaliseLicenciamentoTecnicaCienciaCidadaoRN
        extends LicenciamentoCienciaCidadaoBaseRN implements LicenciamentoCienciaCidadaoRN {

    @Inject
    private AnaliseLicenciamentoTecnicaBD analiseLicenciamentoTecnicaBD;

    @Override
    public void alteraLicenciamentoCiencia(LicenciamentoCiencia lc) {
        analiseLicenciamentoTecnicaBD.altera((AnaliseLicenciamentoTecnicaED) lc);
    }

    @Override
    public boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc) {
        return StatusAnaliseLicenciamentoTecnica.APROVADO
            .equals(((AnaliseLicenciamentoTecnicaED) lc).getStatus());
    }

    @Override
    public TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
        return isLicenciamentoCienciaAprovado(lc)
            ? TipoMarco.CIENCIA_CA_ATEC
            : TipoMarco.CIENCIA_CIA_ATEC;
    }

    @Override
    protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.NCA;
    }
}
```

#### AnaliseLicenciamentoTecnicaCienciaAutomaticaRN

```java
@Stateless
@TransactionAttribute(TransactionAttributeType.REQUIRED)
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.ATEC)
public class AnaliseLicenciamentoTecnicaCienciaAutomaticaRN
        extends LicenciamentoCienciaAutomaticaBaseRN implements LicenciamentoCienciaAutomaticaRN {

    @Inject
    private AnaliseLicenciamentoTecnicaBD analiseLicenciamentoTecnicaBD;

    @Override
    public void alteraLicenciamentoCiencia(LicenciamentoCiencia lc) {
        analiseLicenciamentoTecnicaBD.altera((AnaliseLicenciamentoTecnicaED) lc);
    }

    @Override
    public boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc) {
        return StatusAnaliseLicenciamentoTecnica.APROVADO
            .equals(((AnaliseLicenciamentoTecnicaED) lc).getStatus());
    }

    @Override
    public TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
        return isLicenciamentoCienciaAprovado(lc)
            ? TipoMarco.CIENCIA_AUTO_CA_ATEC
            : TipoMarco.CIENCIA_AUTO_CIA_ATEC;
    }

    @Override
    public List<LicenciamentoCiencia> listarPendentesDeCiencia(Calendar dataLimite) {
        return analiseLicenciamentoTecnicaBD.listarPendentesDeCiencia(dataLimite).stream()
            .map(a -> (LicenciamentoCiencia) a).collect(Collectors.toList());
    }

    @Override
    protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.NCA;
    }
}
```

#### AnaliseLicInviabilidadeCienciaCidadaoRN

Estrutura idêntica à ATEC, com:
- Qualificador: `TipoLicenciamentoCiencia.INVIABILIDADE`
- Cast: `(AnaliseLicInviabilidadeED)`
- `isAprovado`: `StatusAnaliseLicenciamentoInviabilidade.APROVADO`
- `getTipoMarco`: `CIENCIA_CA_INVIABILIDADE` / `CIENCIA_CIA_INVIABILIDADE`
- `getProximoStatus`: `SituacaoLicenciamento.NCA`

#### CivCienciaCidadaoRN

```java
@Stateless
@TransactionAttribute(TransactionAttributeType.REQUIRED)
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.CIV)
public class CivCienciaCidadaoRN extends LicenciamentoCienciaCidadaoBaseRN {

    @Inject VistoriaRN vistoriaRN;

    @Override
    public void alteraLicenciamentoCiencia(LicenciamentoCiencia lc) {
        vistoriaRN.altera((VistoriaED) lc);
    }

    @Override
    public boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc) {
        return StatusVistoria.APROVADO.equals(((VistoriaED) lc).getStatus());
    }

    @Override
    public TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
        // Diferencia vistoria definitiva de renovação
        TipoVistoria tipoVistoria = lc.getLicenciamento().getVistorias() != null
            && !lc.getLicenciamento().getVistorias().isEmpty()
            ? lc.getLicenciamento().getVistorias().stream().findFirst()
                .orElse(new VistoriaED()).getTipoVistoria()
            : TipoVistoria.VISTORIA_DEFINITIVA;

        return TipoVistoria.VISTORIA_RENOVACAO.equals(tipoVistoria)
            ? TipoMarco.CIENCIA_CIV_RENOVACAO
            : TipoMarco.CIENCIA_CIV;
    }

    @Override
    protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.CIV;
    }
}
```

#### CivCienciaAutomaticaRN

```java
@Stateless
@TransactionAttribute(TransactionAttributeType.REQUIRED)
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.CIV)
public class CivCienciaAutomaticaRN extends LicenciamentoCienciaAutomaticaBaseRN {

    @Inject VistoriaRN vistoriaRN;

    @Override
    public TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
        return TipoMarco.CIENCIA_AUTO_CIV;  // não diferencia renovação na versão automática
    }

    @Override
    public List<LicenciamentoCiencia> listarPendentesDeCiencia(Calendar dataLimite) {
        return vistoriaRN.lista(BuilderVistoriaED.of()
            .ciencia(false)
            .dthStatus(dataLimite)
            .status(StatusVistoria.REPROVADO)
            .instance())
            .stream().map(v -> (LicenciamentoCiencia) v).collect(Collectors.toList());
        // Busca vistórias com ciencia=false e dthStatus <= dataLimite e status=REPROVADO
    }

    @Override
    protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.CIV;
    }
}
```

#### AppciCienciaCidadaoRN e AppciCienciaCidadaoRenovacaoRN

```java
// APPCI normal
@LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.APPCI)
public class AppciCienciaCidadaoRN extends LicenciamentoCienciaCidadaoBaseRN {
    @Inject AppciRN appciRN;

    @Override public void alteraLicenciamentoCiencia(LicenciamentoCiencia lc) {
        appciRN.altera((AppciED) lc);
    }
    @Override public boolean isLicenciamentoCienciaAprovado(LicenciamentoCiencia lc) {
        return true;  // APPCI nunca tem CIA — ciência sempre leva a ALVARA_VIGENTE
    }
    @Override public TipoMarco getTipoMarco(LicenciamentoCiencia lc) {
        return TipoMarco.CIENCIA_APPCI;
    }
    @Override protected SituacaoLicenciamento getProximoStatusLicenciamentoCienciaReprovado() {
        return SituacaoLicenciamento.ALVARA_VIGENTE;  // nunca acionado pois isAprovado=true
    }
}

// APPCI renovação — estrutura idêntica, qualificador APPCI_RENOV, marco CIENCIA_APPCI_RENOVACAO
```

---

## 8. Camada de Negócio — Recurso Administrativo

### 8.1 RecursoRN (@Stateless)

Principais injeções:
```java
@Inject private RecursoBD recursoBD;
@Inject private AnaliseRecursoRN analiseRecursoRN;
@Inject private MessageProvider bundle;
@Inject private AnaliseLicenciamentoTecnicaCidadaoRN analiseLicenciamentoTecnicaCidadaoRN;
@Inject private AnaliseLicInviabilidadeRN analiseLicInviabilidadeRN;
// ... (mais de 20 dependências injetadas)
```

Constantes relevantes (em `LicenciamentoCidadaoRN`):
```java
private static final Integer PRAZO_SOLICITAR_RECURSO_1_INSTANCIA = 30;  // dias
private static final Integer PRAZO_SOLICITAR_RECURSO_2_INSTANCIA = 15;  // dias
```

Em `AnaliseRecursoAdmRN`:
```java
private static final Integer RECURSO_1_INSTANCIA      = 1;
private static final Integer RECURSO_2_INSTANCIA      = 2;
private static final String  NOME_RESPONSAVEL_SISTEMA = "SOLCBM";
```

**Principais métodos expostos:**

| Método | Descrição |
|---|---|
| `registra(RecursoDTO dto)` | Registra novo recurso (com validação e aceites) |
| `consultarPorId(Long id)` | Consulta recurso por ID |
| `alterarRecurso(Long id, RecursoDTO dto)` | Realiza aceite de envolvido |
| `salvarRecurso(Long id, RecursoDTO dto)` | Salva rascunho do recurso |
| `lista(RecursoMinhasSolitacaoesPesED ped)` | Lista recursos do cidadão logado |
| `listaRecurosPortermo(RecursoMinhasSolitacaoesPesED ped)` | Busca por termo |
| `consultarHistoricoRecurso(Long id)` | Retorna marcos do recurso |
| `cancelarRecurso(Long id)` | Cancela recurso (pelo cidadão) |
| `cancelar(Long id)` | Cancela recurso (endpoint alternativo) |
| `recusar(Long id)` | Recusa aceite de envolvido |
| `habilitarEdicao(Long id)` | Reabilita recurso para edição |
| `consultaPorRecurso(Long recursoId)` | Consulta por ID do recurso |
| `listaPorIds(List<Long> ids)` | Lista recursos por lista de IDs |
| `consultarSolicitacao(Long id)` | Consulta com dados completos (adm) |
| `toDTO(RecursoED recursoED)` | Converte entidade para DTO |
| `listarTodos(RecursoPesqED ped)` | Lista todos recursos (admin) |

### 8.2 RecursoRNVal (validações)

```java
package com.procergs.solcbm.recurso;

public class RecursoRNVal {

    @Inject private MessageProvider bundle;

    public void valida(RecursoDTO recursoDto) {
        boolean valid = true;

        if (recursoDto.getTipoSolicitacao() == null) valid = false;
        if (recursoDto.getTipoRecurso() == null) valid = false;
        if (recursoDto.getInstancia() == null
            || recursoDto.getInstancia() <= 0
            || recursoDto.getInstancia() > 2) valid = false;
        if (StringUtils.isBlank(recursoDto.getFundamentacaoLegal())) valid = false;
        if (recursoDto.getIdLicenciamento() == null) valid = false;
        if (recursoDto.getIdArquivoCiaCiv() == null) valid = false;

        // Ao menos um envolvido por CPF deve ser informado
        if ((recursoDto.getCpfRts() == null || recursoDto.getCpfRts().isEmpty())
            && (recursoDto.getCpfRus() == null || recursoDto.getCpfRus().isEmpty())
            && (recursoDto.getCpfProprietarios() == null || recursoDto.getCpfProprietarios().isEmpty())) {
            throw new WebApplicationRNException(
                bundle.getMessage("troca.envolvido.licenciamento.envolvidos.naoInformados"),
                Response.Status.BAD_REQUEST);
        }

        if (!valid) {
            throw new WebApplicationRNException(
                bundle.getMessage("campos.obrigatorio.nao.preenchido"),
                Response.Status.BAD_REQUEST);
        }
    }
}
```

**Regras de negócio consolidadas do `RecursoRN`:**

| Código | Regra |
|---|---|
| RN-P05-R01 | `tipoSolicitacao`, `tipoRecurso`, `instancia` (1 ou 2), `fundamentacaoLegal`, `idLicenciamento` e `idArquivoCiaCiv` são obrigatórios |
| RN-P05-R02 | Pelo menos um CPF de envolvido (RT, RU ou Proprietário) deve ser informado |
| RN-P05-R03 | Prazo para 1ª instância: 30 dias a partir da ciência do CIA/CIV |
| RN-P05-R04 | Prazo para 2ª instância: 15 dias a partir da ciência da resposta da 1ª instância |
| RN-P05-R05 | 2ª instância cabe apenas se a 1ª foi `INDEFERIDO` ou `DEFERIDO_PARCIAL` |
| RN-P05-R06 | `arquivoCiaCivED` deve corresponder a um CIA/CIV válido associado ao licenciamento |
| RN-P05-R07 | Ao registrar, a situação do recurso é `AGUARDANDO_APROVACAO_ENVOLVIDOS` |

### 8.3 Aceite dos envolvidos

**Fluxo implementado em `RecursoRN.alterarRecurso(Long id, RecursoDTO dto)`:**

| Código | Regra |
|---|---|
| RN-P05-A01 | Apenas envolvidos listados no recurso (por CPF) podem confirmar aceite |
| RN-P05-A02 | Um aceite confirmado não pode ser desfeito |
| RN-P05-A03 | Quando todos os envolvidos confirmam aceite: `situacao = AGUARDANDO_DISTRIBUICAO`, `dataEnvioAnalise = now()` |
| RN-P05-A04 | Marco `ENVIO_RECURSO_ANALISE` e/ou `FIM_ACEITES_RECURSO_ANALISE` são registrados ao concluir aceites |
| RN-P05-A05 | Se qualquer envolvido recusar: `RecursoRN.recusar(id)` → `situacao = CANCELADO` |

### 8.4 Cancelamento

| Código | Regra |
|---|---|
| RN-P05-RC01 | `cancelarRecurso(id)` ou `cancelar(id)` → `situacao = CANCELADO` |
| RN-P05-RC02 | Após distribuição (`EM_ANALISE`), cancelamento requer perfil `DISTRIBUICAOANALISE/CANCELAR` |
| RN-P05-RC03 | `habilitarEdicao(id)` reabilita recurso para edição pelo cidadão |

---

## 9. Camada de Negócio — Análise pelo Colegiado

### 9.1 AnaliseRecursoAdmRN (@Stateless, @AppInterceptor)

**Constantes:**
```java
private static final Integer RECURSO_1_INSTANCIA      = 1;
private static final Integer RECURSO_2_INSTANCIA      = 2;
private static final String  NOME_RESPONSAVEL_SISTEMA = "SOLCBM";
```

**Análise 1ª instância — `analisarRecurso(AnaliseRecursoDTO dto)`:**
```
@Permissao(objeto="ANALISERECURSO", acao="ANALISAR")
```

1. Busca `RecursoED` por `dto.recursoId`. Se não encontrado: HTTP 404.
2. Valida: `dto.despacho != null && !blank`, `dto.decisao != null`. Se inválido: HTTP 400.
3. Executa `deferimentoTotal1Instancia(recursoED, dto)`:
   - Se `tipoSolicitacao == INTEGRAL && decisao == DEFERIDO_TOTAL`:
     - Para `CORRECAO_DE_VISTORIA`: cria nova `VistoriaED` com `status=EM_VISTORIA`, `numeroVistoria = atual + 1`; atualiza licenciamento para `AGUARDANDO_DISTRIBUICAO_RENOV` (renovação) ou `AGUARDA_DISTRIBUICAO_VISTORIA` (definitiva).
     - Para `CORRECAO_DE_ANALISE`: cancela `AnaliseLicenciamentoTecnicaED` (status `CANCELADA`) ou `AnaliseLicInviabilidadeED` (status `CANCELADO`); licenciamento → `AGUARDANDO_DISTRIBUICAO`.
     - Marco `DOCUMENTO_CIA_CIV_CANCELADO` no recurso e no licenciamento.
   - Caso contrário: `atualizarSituacaoLicenciamento(recursoED)` → `NCA` (análise) ou `CIV` (vistoria).
4. Cria `AnaliseRecursoED`:
   ```java
   AnaliseRecursoED.builder()
       .recursoED(recursoED)
       .despacho(dto.getDespacho())
       .idUsuarioSoe(Long.parseLong(sessionMB.getUser().getId()))
       .status(dto.getDecisao())
       .situacao(SituacaoAnaliseRecursoEnum.ANALISE_CONCLUIDA)
       .ciencia(false)
       .build();
   analiseRecursoED.setCtrDthInc(dataAtualHelper.getDataAtual());
   analiseRecursoED.setDataConclusaoAnalise(dataAtualHelper.getDataAtual());
   inclui(analiseRecursoED);
   ```
5. `recursoED.setSituacao(SituacaoRecurso.ANALISE_CONCLUIDA)` → `recursoRN.altera(recursoED)`.
6. Marco `RESPOSTA_RECURSO` no recurso (TipoResponsavelMarco.BOMBEIROS) e no licenciamento.
7. `geraRelatorioAnalise(analiseRecursoED)` → gera PDF JasperReports, salva no Alfresco, vincula a `analiseRecursoED.arquivo`.

**Análise 2ª instância — `analisarSegundaInstancia(AnaliseRecursoDTO dto)`:**

Similar à 1ª instância, mas:
- Usa `AnaliseRecursoED` já existente (criado pelo colegiado).
- Executa `deferimentoTotal2Instancia()` (mesma lógica do 1ª).
- `analiseRecurso.setSituacao(ANALISE_CONCLUIDA)`, `setDataConclusaoAnalise(now())`.
- Marco `RESPOSTA_RECURSO_2`.

**Regras de negócio do `deferimentoTotal1Instancia`:**

| Código | Regra |
|---|---|
| RN-P05-G01 | Se `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_VISTORIA`: nova vistoria é criada, CIA/CIV não é cancelado |
| RN-P05-G02 | Se `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_ANALISE`: CIA/CIV é cancelado, licenciamento volta para distribuição |
| RN-P05-G03 | Nos demais casos: licenciamento retorna para `NCA` (análise) ou `CIV` (vistoria) |
| RN-P05-G04 | `AnaliseRecursoED.ciencia` é inicializado como `false` (pendente de ciência) |
| RN-P05-G05 | PDF de análise é gerado automaticamente via JasperReports e vinculado ao `AnaliseRecursoED` |

### 9.2 AvalistaRecursoAdmRN (@Stateless, @AppInterceptor) — Colegiado (2ª instância)

**`criarColegiado(AnaliseRecursoColegiadoDTO dto)`:**
```
@Permissao(objeto="ANALISERECURSO", acao="ANALISAR")
```

Validações:
- `dto.recursoId != null`
- `dto.usuariosSoeId != null && !empty`
- `dto.usuariosSoeId.size() <= 2` (máximo 2 avalistaes)
- `recursoED.instancia == 2` (somente para 2ª instância)

Fluxo:
1. Cria `AnaliseRecursoED` com `situacao = AGUARDANDO_AVALIACAO_COLEGIADO`, `idUsuarioSoe = analista logado`.
2. Cria um `AvalistaRecursoED` por `usuarioSoeId` com `aceite = false`.
3. Marco `ENVIO_PARA_COLEGIADO` no recurso e no licenciamento.

**`concordoColegiado(Long recursoId)`:**
```
@Permissao(objeto="ANALISERECURSO", acao="ANALISAR")
```
1. Busca avalistaedo usuário logado na lista de avalistaes.
2. `avalista.setAceite(true)`.
3. Marco `ANALISE_RECURSO_COLEGIADO` (TipoResponsavelMarco.BOMBEIROS).
4. Se todos os avalistaes concordaram: marco `FIM_ANALISE_RECURSO_COLEGIADO` (TipoResponsavelMarco.SISTEMA).

**`naoConcordoJuntaTecnica(Long recursoId, AvalistaRecursoDTO dto)`:**
1. `avalista.setAceite(false)`, `avalista.setJustificativaNaoConcordo(dto.getJustificativaNaoConcordo())`.
2. Marco `ANALISE_RECURSO_COLEGIADO`.

**`removerAvalista(Long idAvalista)`:**
1. Busca `AvalistaRecursoED` por ID.
2. Exclui da base.
3. Marco `EXCLUSAO_MEMBRO_JUNTA_TECNICA` (TipoResponsavelMarco.SISTEMA, usuarioSoeNome="SOLCBM").

### 9.3 Ciência da resposta do recurso — `AnaliseRecursoRN.alterar(AnaliseRecursoED)`

```java
@Permissao(desabilitada = true)
public Long alterar(AnaliseRecursoED analiseRecursoED) {
    analiseRecursoED.setDthCienciaAtec(Calendar.getInstance());
    analiseRecursoED.setIdUsuarioCiencia(usuarioRN.getUsuarioLogado().getId());
    analiseRecursoED.setCiencia(true);

    altera(analiseRecursoED);  // persiste via BD

    RecursoMarcoED recursoMarcoED = RecursoMarcoED.builder()
        .recursoED(analiseRecursoED.getRecursoED())
        .dthMarco(Calendar.getInstance())
        .tipoResponsavel(TipoResponsavelMarco.CIDADAO)
        .tituloArquivo(analiseRecursoED.getArquivo().getNomeArquivo())
        .usuarioED(usuarioRN.getUsuarioLogado())
        .visibilidade(TipoVisibilidadeMarco.PUBLICO)
        .build();
    recursoMarcoED.setCtrUsuInc(usuarioRN.getUsuarioLogado().getId());

    recursoMarcoRN.inclui(TipoMarco.CIENCIA_RECURSO, recursoMarcoED);

    LicenciamentoED licenciamentoED = BuilderLicenciamentoED.of()
        .id(analiseRecursoED.getRecursoED().getLicenciamentoED().getId()).instance();
    licenciamentoMarcoCidadaoRN.inclui(TipoMarco.CIENCIA_RECURSO, licenciamentoED);

    return analiseRecursoED.getId();
}
```

### 9.4 RecursoAdmRN (@Stateless, @AppInterceptor) — Distribuição

**`distribuirRecurso(RecursoDistribuicaoAnaliseDTO dto)`:**
```
@Permissao(objeto="DISTRIBUICAOANALISE", acao="DISTRIBUIR")
```
1. Lista `RecursoED` por `dto.recursoId` (lista de IDs).
2. Para cada recurso: `setIdUsuarioSoe(dto.usuarioSoeId)`, `setSituacao(EM_ANALISE)`.
3. Marco `DISTRIBUICAO_ANALISE_RECURSO` no recurso e no licenciamento.

**`cancelarDistribuicaoRecurso(Long recursotId)`:**
```
@Permissao(objeto="DISTRIBUICAOANALISE", acao="CANCELAR")
```
1. `recursoED.setIdUsuarioSoe(null)`, `setSituacao(AGUARDANDO_DISTRIBUICAO)`.
2. Se instância 2: exclui todos `AvalistaRecursoED` e `AnaliseRecursoED` do recurso.
3. Marco `CANCELA_DISTRIBUICAO_ANALISE_RECURSO`.

---

## 10. Job de Ciência Automática

### 10.1 LicenciamentoCienciaBatchRN (@Stateless)

```java
@Stateless
@AppInterceptor
@Permissao(desabilitada = true)
public class LicenciamentoCienciaBatchRN {

    public static final int DIAS_PERIODO_VERIFICACAO = -30;  // -30 dias = 30 dias atrás

    @Inject @LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.INVIABILIDADE)
    private LicenciamentoCienciaAutomaticaRN analiseLicInviabilidadeCienciaAutomaticaRN;

    @Inject @LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.ATEC)
    private LicenciamentoCienciaAutomaticaRN analiseLicenciamentoTecnicaCienciaAutomaticaRN;

    @Inject @LicenciamentoCienciaQualifier(tipoLicenciamentoCiencia = TipoLicenciamentoCiencia.CIV)
    private LicenciamentoCienciaAutomaticaRN civCienciaAutomaticaRN;

    @Inject
    private RecursoCienciaAutomaticaRN recursoCienciaAutomaticaRN;

    @Inject private EmailService emailService;
    @Inject private DataAtualHelper dataAtualHelper;

    @Schedule(hour = "12/12",
              info = "Verificação de ciência automática do licenciamento executada 12:00 e 24:00",
              persistent = false)
    public void efetuaCienciaAutomatica() {
        try {
            if (!BatchUtil.isServerEnabled(logger)) {
                return;  // Proteção de ambiente (não executa em ambiente não habilitado)
            }

            Calendar dataLimite = calculaDataLimiteCienciaAutomatica();
            // dataLimite = dataAtual + (-30 dias) = 30 dias atrás

            analiseLicInviabilidadeCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite);
            analiseLicenciamentoTecnicaCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite);
            civCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite);
            recursoCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite);

        } catch (Exception e) {
            logger.error("Problema na rotina de verificação da ciência automática", e);
            enviarEmailErro(e);
            // Envia e-mail para PropriedadesEnum.EMAIL_DESTINATARIO_ERRO_JOB
        }
    }

    protected Calendar calculaDataLimiteCienciaAutomatica() {
        return DataUtil.somarDias(dataAtualHelper.getDataAtual(), DIAS_PERIODO_VERIFICACAO);
    }
}
```

**Regras do job:**

| Código | Regra |
|---|---|
| RN-P05-J01 | O job executa duas vezes por dia: às 12:00 e às 24:00 (hora do servidor) |
| RN-P05-J02 | `persistent = false` significa que o timer não é persistido no BD do servidor — reinicialização cancela o timer |
| RN-P05-J03 | O job processa ciência de inviabilidade, análise técnica e CIV em sequência |
| RN-P05-J04 | `dataLimite = dataAtual - 30 dias`: processa apenas licenciamentos cuja ciência deveria ter sido registrada há pelo menos 30 dias |
| RN-P05-J05 | Em caso de erro em qualquer tipo, o bloco try-catch envia e-mail de alerta e não interrompe o servidor |
| RN-P05-J06 | `BatchUtil.isServerEnabled()` garante que o job não execute em ambientes desabilitados (ex.: ambiente de teste) |

### 10.2 RecursoCienciaAutomaticaRN (ciência da resposta do recurso)

```java
public class RecursoCienciaAutomaticaRN {

    private static final String NOME_RESPONSAVEL_SISTEMA = "SOLCBM";

    @Inject AnaliseRecursoBD analiseRecursoBD;
    @Inject DataAtualHelper dataAtualHelper;
    @Inject RecursoMarcoRN recursoMarcoRN;

    @Inject
    @LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.SISTEMA)
    LicenciamentoMarcoInclusaoRN licenciamentoMarcoSistemaRN;

    public void efetuaCienciaAutomatica(Calendar dataLimite) {
        List<AnaliseRecursoED> pendentes = analiseRecursoBD.listarPendentesDeCiencia(dataLimite);
        pendentes.forEach(this::efetuarCiencia);
    }

    private void efetuarCiencia(AnaliseRecursoED analiseRecursoED) {
        // 1. Registra ciência automática
        analiseRecursoED.setCiencia(true);
        analiseRecursoED.setDthCienciaAtec(dataAtualHelper.getDataAtual());
        analiseRecursoBD.altera(analiseRecursoED);

        // 2. Marco no recurso (SISTEMA)
        RecursoMarcoED recursoMarcoED = RecursoMarcoED.builder()
            .recursoED(analiseRecursoED.getRecursoED())
            .dthMarco(Calendar.getInstance())
            .tipoResponsavel(TipoResponsavelMarco.SISTEMA)
            .usuarioSoeNome(NOME_RESPONSAVEL_SISTEMA)
            .tituloArquivo(analiseRecursoED.getArquivo().getNomeArquivo())
            .visibilidade(TipoVisibilidadeMarco.PUBLICO)
            .build();
        recursoMarcoRN.inclui(TipoMarco.CIENCIA_RECURSO, recursoMarcoED);

        // 3. Marco no licenciamento (SISTEMA)
        licenciamentoMarcoSistemaRN.inclui(
            TipoMarco.CIENCIA_RECURSO,
            analiseRecursoED.getRecursoED().getLicenciamentoED());
    }
}
```

---

## 11. Camada de Acesso a Dados (BD)

### 11.1 AnaliseRecursoBD

Métodos necessários:

| Método | Query / Lógica |
|---|---|
| `consultaPorRecurso(RecursoPesqED ped)` | Lista análises conforme filtros |
| `consultaPorRecurso(Long recursoId)` | Busca `AnaliseRecursoED` pelo ID do recurso |
| `consultaPorRecursos(List<Long> ids)` | Busca lista de análises por IDs de recurso |
| `consultaPorRecursos(Long recursoId)` | Alias para `consultaPorRecurso(Long)` |
| `consultaAnalisePrimeiraInstancia(ArquivoED arquivo)` | Busca análise da 1ª instância por arquivo CIA/CIV |
| `consultaRecursoParaTaxa(RecursoPesqED ped)` | Lista para cálculo de taxa |
| `listarPendentesDeCiencia(Calendar dataLimite)` | Busca `AnaliseRecursoED` com `ciencia = false` (ou `'N'`) e `dataConclusaoAnalise <= dataLimite` e `situacao = ANALISE_CONCLUIDA` |
| `altera(AnaliseRecursoED ed)` | Persiste alterações |

**JPQL de exemplo para `listarPendentesDeCiencia`:**
```sql
SELECT ar FROM AnaliseRecursoED ar
WHERE ar.ciencia = false
  AND ar.situacao = 'ANALISE_CONCLUIDA'
  AND ar.dataConclusaoAnalise <= :dataLimite
```

### 11.2 RecursoBD

| Método | Descrição |
|---|---|
| `listaRecursos(RecursoPesqED ped)` | Lista paginada para distribuição |
| `listaRecursoAnalise(RecursoPesqED ped, UserED usuario)` | Lista para analista específico |
| `listarRecursosComFiltro(RecursoPesqED ped)` | Lista com múltiplos filtros (adm) |
| `recursosEmAnaliseAnalista(List<Long> idsAnalistas)` | Recursos em análise por lista de analistas |
| `recursosEmAnaliseAnalista(Long usuarioSoeID, int limite)` | Recursos em análise por analista (c/ limite) |

### 11.3 RecursoMarcoBD

| Método | Descrição |
|---|---|
| `consultaMarcosPorRecurso(RecursoED recursoED)` | Lista todos marcos de um recurso |

---

## 12. Camada REST (JAX-RS)

### 12.1 RecursoRest — `@Path("/recursos")`

| Método HTTP | Path | Corpo | Resposta | Descrição |
|---|---|---|---|---|
| `POST` | `/recursos` | `RecursoDTO` | `201 + RecursoResponseDTO` | Registra novo recurso |
| `GET` | `/recursos/{recursoId}` | — | `200 + RecursoResponseDTO` | Consulta recurso por ID |
| `PUT` | `/recursos/{recursoId}` | `RecursoDTO` | `200 + RecursoResponseDTO` | Aceite de envolvido |
| `PUT` | `/recursos/{recursoId}/salvar` | `RecursoDTO` | `200 + RecursoResponseDTO` | Salva rascunho |
| `GET` | `/recursos/listar` | QP (abaixo) | `200 + Lista paginada` | Lista recursos do cidadão |
| `GET` | `/recursos/historico/{recursoId}` | — | `200 + HistoricoDTO` | Marcos do recurso |
| `DELETE` | `/recursos/cancelar-recurso/{recursoId}` | — | `200` | Cancela recurso (v1) |
| `DELETE` | `/recursos/{recursoId}/cancelar` | — | `200` | Cancela recurso (v2) |
| `PUT` | `/recursos/{recursoId}/recusar` | — | `200` | Recusa aceite |
| `PUT` | `/recursos/{recursoId}/habilitar-edicao` | — | `200` | Reabilita para edição |

**Query parameters do `/recursos/listar`:**
- `ordenar` (default: `ctrDthInc`)
- `ordem` (default: `desc`)
- `paginaAtual` (default: `0`)
- `tamanho` (default: `20`)
- `numeroLicenciamento`
- `situacoes` (`List<SituacaoRecurso>`)
- `tipoRecurso` (`List<TipoRecurso>`)
- `recursoId`
- `termo` (quando preenchido, usa busca textual)

### 12.2 RecursoArquivoRest — `@Path("/recurso-arquivos")`

| Método | Path | Notas |
|---|---|---|
| `POST` | `/recurso-arquivos/{recursoId}/upload` | `multipart/form-data` — anexo do recurso |
| `GET` | `/recurso-arquivos/{recursoId}` | Lista arquivos do recurso |
| `GET` | `/recurso-arquivos/download/{idArquivo}` | Download binário do arquivo |
| `DELETE` | `/recurso-arquivos/{arquivoId}` | Remove arquivo do recurso |
| `GET` | `/recurso-arquivos/download-analise/{idRecurso}` | Download do PDF de análise (relatório) |

### 12.3 RecursoAdmRestImpl — `@Path("adm/recursos")` + `@SOEAuthRest`

| Método | Path | Parâmetros | Descrição |
|---|---|---|---|
| `GET` | `/adm/recursos/listar` | `ordenar, ordem, paginaAtual, tamanho, instancia, tipoRecurso, numeroLicenciamento, situacaoRecurso, logradouro, cidade, nomeSolicitante, dataInicioSolicitacao, dataFimSolicitacao` | Lista recursos com filtros (adm) |
| `GET` | `/adm/recursos/marcos/{recursoId}` | — | Marcos do recurso (adm) |
| `PUT` | `/adm/recursos/reserva/{idLic}` | — | Alterna flag de reserva do licenciamento |

**Regras da listagem adm:**
- Ao menos um filtro deve ser informado (`validarAoMenosUmFiltroInformado()`).
- Se `dataInicio > dataFim`: HTTP 400.
- Usuário com `RECURSO/LISTAR` vê todos; sem essa permissão, filtra pelo batalhão do usuário logado.
- Com `ANALISERECURSO/LISTARPELOTAO`: filtra pelo pelotão.

### 12.4 RecursoAnaliseRestImpl — `@Path("/adm/recurso-analise")` + `@SOEAuthRest`

| Método | Path | Corpo / QP | Descrição |
|---|---|---|---|
| `GET` | `/adm/recurso-analise/distribuicao-listar` | `paginaAtual, tamanho, instancia, tipoRecurso, situacaoRecurso` | Lista para distribuição |
| `GET` | `/adm/recurso-analise/pendentes-listar` | `paginaAtual, tamanho, instancia, tipoRecurso, situacaoRecurso` | Lista pendentes para analista |
| `GET` | `/adm/recurso-analise/recurso-analistas` | — | Analistas com qtd de processos |
| `PUT` | `/adm/recurso-analise/distribuicoes-recurso` | `RecursoDistribuicaoAnaliseDTO` | Distribui para analista |
| `PUT` | `/adm/recurso-analise/{recursotId}/cancelar-distribuicao` | — | Cancela distribuição |
| `GET` | `/adm/recurso-analise/{recursoId}` | — | Consulta recurso (adm) |
| `GET` | `/adm/recurso-analise/consulta-analise/{recursoId}` | — | Consulta análise do recurso |
| `GET` | `/adm/recurso-analise/busca-analista/{usuarioSoeID}` | — | Análises de um analista específico |
| `POST` | `/adm/recurso-analise` | `AnaliseRecursoDTO` | Analisa 1ª instância |
| `POST` | `/adm/recurso-analise/segunda-instancia` | `AnaliseRecursoDTO` | Analisa 2ª instância |
| `GET` | `/adm/recurso-analise/analistas-disponivel` | `codBatalhao` | Analistas disponíveis por batalhão |
| `GET` | `/adm/recurso-analise/historico/{recursoId}` | — | Histórico do recurso |
| `GET` | `/adm/recurso-analise/recurso/{recursoId}` | — | Consulta análise por ID do recurso |
| `POST` | `/adm/recurso-analise/colegiado` | `AnaliseRecursoColegiadoDTO` | Cria colegiado (2ª instância) |
| `PUT` | `/adm/recurso-analise/recurso/{recursoId}` | — | Avalistataconcorda |
| `DELETE` | `/adm/recurso-analise/remover-avalista/{idAvalista}` | — | Remove avalista |
| `PUT` | `/adm/recurso-analise/avalista-nao-concordo/{recursoId}` | `AvalistaRecursoDTO` | Avalistasdiscorda |

**DTOs relevantes:**

| DTO | Campos principais |
|---|---|
| `RecursoDTO` | `idLicenciamento, idArquivoCiaCiv, instancia, tipoRecurso, tipoSolicitacao, fundamentacaoLegal, cpfRts[], cpfRus[], cpfProprietarios[]` |
| `RecursoResponseDTO` | `id, licenciamento, tipoRecurso, tipoSolicitacao, instancia, situacao, rts[], rus[], proprietarios[], arquivosRecurso[], recursoDecisao, fundamentacaoLegal, numeroSequencial, reserva` |
| `AnaliseRecursoDTO` | `recursoId, despacho, decisao (StatusRecurso)` |
| `AnaliseRecursoResponseDTO` | `id, despacho, decisao, recursoDTO, colegiado (AvalistaRecursoDTO[])` |
| `AnaliseRecursoColegiadoDTO` | `recursoId, usuariosSoeId[] (máx 2)` |
| `RecursoDistribuicaoAnaliseDTO` | `recursoId[] (lista), usuarioSoeId` |
| `AvalistaRecursoDTO` | `id, usuarioSoe, batalhao, aceite, justificativaNaoConcordo` |

---

## 13. Segurança — @Permissao e SessionMB

O sistema usa o framework `arqjava4` com a anotação `@Permissao(objeto, acao)` interceptada pelo `AppInterceptor`.

### 13.1 Mapa de permissões do P05

| Objeto | Ação | Quem usa |
|---|---|---|
| `DISTRIBUICAOANALISE` | `DISTRIBUIR` | Coordenador — distribuir recursos e listar para distribuição |
| `DISTRIBUICAOANALISE` | `CANCELAR` | Coordenador — cancelar distribuição |
| `DISTRIBUICAOANALISE` | `CONSULTAR` | Coordenador/Analista — listar análises por analista |
| `ANALISERECURSO` | `ANALISAR` | Analista/Coordenador — analisar, criar colegiado, concorda/discorda |
| `ANALISERECURSO` | `LISTAR` | Analista — listar recursos em análise |
| `ANALISERECURSO` | `LISTARPELOTAO` | Analista — filtra por pelotão (subset do batalhão) |
| `RECURSO` | `CONSULTAR` | Analista/Coordenador — consultar recurso, marcos, histórico |
| `RECURSO` | `LISTAR` | Administrador — listar todos recursos sem restrição de batalhão |
| `RESERVADEPPCI` | `RESERVAR` | Analista/Coordenador — alterar flag de reserva |

### 13.2 Uso de SessionMB

`SessionMB` é injetado via CDI nos EJBs administrativos para obter dados do usuário SOE autenticado:

```java
@Inject private SessionMB sessionMB;

// Obtém ID do usuário logado
Long.parseLong(sessionMB.getUser().getId())

// Obtém nome do usuário logado
sessionMB.getUser().getNome()

// Verifica permissão
sessionMB.hasPermission("RECURSO", "LISTAR")
```

### 13.3 Anotação @SOEAuthRest

```java
@SOEAuthRest
```

Aplicada nos endpoints `/adm/*`, garante que apenas usuários autenticados via SOE PROCERGS com perfil administrativo acessem os recursos.

---

## 14. Armazenamento de Arquivos — Alfresco

O sistema usa Alfresco como ECM (Enterprise Content Management). Todo arquivo binário é armazenado no Alfresco, e apenas a referência (nodeRef = `identificadorAlfresco`) é persistida no banco relacional via `ArquivoED`.

### 14.1 ArquivoED (campos relevantes)

| Campo | Coluna | Tipo | Descrição |
|---|---|---|---|
| `id` | `NRO_INT_ARQUIVO` | `Long` | PK |
| `identificadorAlfresco` | `IDENTIFICADOR_ALFRESCO` | `String` (max 150) `@NotNull` | nodeRef no Alfresco |
| `nomeArquivo` | `NOME_ARQUIVO` | `String` | Nome original do arquivo |
| `codigoAutenticacao` | `CODIGO_AUTENTICACAO` | `String` | Código para verificação de autenticidade |
| `tipo` | `TP_ARQUIVO` | `TipoArquivo` enum | `EDIFICACAO`, etc. |

### 14.2 ArquivoRN — operações principais

```java
// Incluir arquivo no Alfresco e persiste ArquivoED
ArquivoED arquivoED = arquivoRN.incluirArquivo(ArquivoED arquivo);
// Internamente: faz upload para Alfresco, obtém nodeRef, seta identificadorAlfresco, persiste

// Obter conteúdo do Alfresco como InputStream
InputStream stream = arquivoRN.toInputStream(ArquivoED arquivo);
// Internamente: chama Alfresco com identificadorAlfresco, retorna stream

// Gerar código de autenticação único
String codigo = arquivoRN.gerarNumeroAutenticacao();
```

### 14.3 Geração de relatório de análise

```java
// Em AnaliseRecursoAdmRN.geraRelatorioAnalise(AnaliseRecursoED ed)

String numeroAutenticacao = arquivoRN.gerarNumeroAutenticacao();
InputStream relatorio = documentoRelatorioAnaliseRecursoRN.gera(
    AnaliseRecursoRelatorioDTO.builder()
        .tipoSolicitacao(...)
        .tipoDecisao("Deferido Total" | "Deferido Parcial" | "Indeferido")
        .numeroPPCI(...)
        .envolvidos(...)
        .fundamentacaoLegal(unescapeHTML(recurso.getFundamentacaoLegal()))
        .docsAnexados(recurso.getArquivosRecurso())
        .despacho(unescapeHTML(ed.getDespacho()))
        .instancia(recurso.getInstancia().toString())
        .tipo("Correção de CIA" | "Correção de CIV")
        .numeroAutenticacao(numeroAutenticacao)
        .logoCBM(reportPathHelper.getLogoCBM())
        .logoRS(reportPathHelper.getLogoRS())
        .dataAtual(...)
        .dataHoraAssinatura(...)
        .build());

ArquivoED arquivoED = BuilderArquivoED.of()
    .inputStream(relatorio)
    .nomeArquivo("ca_analise_recurso_" + ed.getRecursoED().getInstancia() + "_instancia.pdf")
    .codigoAutenticacao(numeroAutenticacao)
    .tipo(TipoArquivo.EDIFICACAO)
    .instance();

ArquivoED arquivoSalvo = arquivoRN.incluirArquivo(arquivoED);
ed.setArquivo(arquivoSalvo);
altera(ed);  // persiste referência no AnaliseRecursoED
```

**Observação:** o campo `unescapeHTML()` trata o conteúdo HTML do despacho (vem do editor de texto rico do frontend), convertendo `<strong>` para `<b>` e desfazendo escape HTML.

---

## 15. Marcos e Trilha de Auditoria

### 15.1 RecursoMarcoRN

```java
public class RecursoMarcoRN {
    public void inclui(TipoMarco tipoMarco, RecursoMarcoED recursoMarcoED);
    // Persiste o marco com o TipoMarco especificado e os dados já preenchidos em recursoMarcoED
}
```

### 15.2 LicenciamentoMarcoInclusaoRN (qualificado por TipoResponsavelMarco)

```java
@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.CIDADAO)
LicenciamentoMarcoInclusaoRN licenciamentoMarcoCidadaoRN;

@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.SISTEMA)
LicenciamentoMarcoInclusaoRN licenciamentoMarcoSistemaRN;

@LicenciamentoMarcoQualifier(tipoResponsavel = TipoResponsavelMarco.BOMBEIROS)
LicenciamentoMarcoInclusaoRN licenciamentoMarcoAdmRN;

// Métodos disponíveis:
void inclui(TipoMarco tipoMarco, LicenciamentoED licenciamentoED);
void incluiComArquivo(TipoMarco tipoMarco, LicenciamentoED licenciamentoED, ArquivoED arquivo);
void incluiComTextoComplementar(TipoMarco tipoMarco, LicenciamentoED licenciamentoED, String texto);
```

### 15.3 ParametroMarcoED e ParametroMarcoRN

O sistema usa uma tabela de configuração de marcos (`ParametroMarcoED`) para definir:
- Descrição legível do marco
- Visibilidade padrão

```java
Optional<ParametroMarcoED> parametroMarcoED =
    parametroMarcoRN.consultaPorChave(TipoMarco.RESPOSTA_RECURSO.name());

if (parametroMarcoED.isPresent()) {
    LicenciamentoMarcoED licenciamentoMarcoED = BuilderLicenciamentoMarcoED.of()
        .licenciamento(licenciamentoED)
        .tipoResponsavel(TipoResponsavelMarco.BOMBEIROS)
        .parametroMarco(parametroMarcoED.get())
        .descricao(parametroMarcoED.get().getValor())
        .visibilidade(parametroMarcoED.get().getVisibilidade())
        .dthMarco(Calendar.getInstance())
        .idUsuarioSoeResp(Long.valueOf(sessionMB.getUser().getId()))
        .nomeResponsavel(sessionMB.getUser().getNome())
        .instance();
    licenciamentoMarcoRN.inclui(licenciamentoMarcoED);
}
```

---

## 16. Transições de Estado

### 16.1 SituacaoLicenciamento — transições do P05

| De | Para | Gatilho | Condição |
|---|---|---|---|
| `AGUARDANDO_CIENCIA` | `NCA` | Ciência de CIA (ATEC) | `AnaliseLicenciamentoTecnicaED.status == REPROVADO` |
| `AGUARDANDO_CIENCIA` | `CA` | Ciência de CIA (ATEC) | `status == APROVADO` |
| `AGUARDANDO_CIENCIA` | `NCA` | Ciência de CIA (INVIABILIDADE) | `AnaliseLicInviabilidadeED.status == REPROVADO` |
| `AGUARDANDO_CIENCIA` | `CA` | Ciência de CIA (INVIABILIDADE) | `status == APROVADO` |
| `AGUARDANDO_CIENCIA_CIV` | `CIV` | Ciência de CIV | `VistoriaED.status == REPROVADO` |
| `AGUARDANDO_CIENCIA_CIV` | `ALVARA_VIGENTE` | Ciência de CIV | `status == APROVADO` |
| `(qualquer)` | `ALVARA_VIGENTE` | Ciência de APPCI | `isAprovado() == true` (sempre) |
| `NCA` | `RECURSO_EM_ANALISE_1_CIA` | Aceites do recurso completos | `instancia=1, tipoRecurso=CORRECAO_DE_ANALISE` |
| `CIV` | `RECURSO_EM_ANALISE_1_CIV` | Aceites do recurso completos | `instancia=1, tipoRecurso=CORRECAO_DE_VISTORIA` |
| `RECURSO_EM_ANALISE_1_CIA` | `RECURSO_EM_ANALISE_2_CIA` | Aceites 2ª instância completos | `instancia=2, tipo=CIA` |
| `RECURSO_EM_ANALISE_1_CIV` | `RECURSO_EM_ANALISE_2_CIV` | Aceites 2ª instância completos | `instancia=2, tipo=CIV` |
| `RECURSO_EM_ANALISE_*` | `AGUARDANDO_DISTRIBUICAO` | `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_ANALISE` | CIA/CIV cancelado |
| `RECURSO_EM_ANALISE_*` | `AGUARDA_DISTRIBUICAO_VISTORIA` ou `AGUARDANDO_DISTRIBUICAO_RENOV` | `DEFERIDO_TOTAL + INTEGRAL + CORRECAO_DE_VISTORIA` | Nova vistoria criada |
| `RECURSO_EM_ANALISE_*` | `NCA` | `INDEFERIDO` ou `DEFERIDO_PARCIAL` (análise) | Após análise concluída |
| `RECURSO_EM_ANALISE_*` | `CIV` | `INDEFERIDO` ou `DEFERIDO_PARCIAL` (vistoria) | Após análise concluída |

### 16.2 SituacaoRecurso — transições

```
RASCUNHO
  └─→ AGUARDANDO_APROVACAO_ENVOLVIDOS  [ao submeter o recurso]
        ├─→ AGUARDANDO_DISTRIBUICAO    [todos aceites == true]
        │     ├─→ EM_ANALISE           [coordenador distribui ao analista]
        │     │     └─→ ANALISE_CONCLUIDA  [despacho emitido e PDF gerado]
        │     │           (aguarda ciência manual ou automática)
        │     └─→ CANCELADO            [cancelamento após distribuição (admin)]
        ├─→ CANCELADO                  [envolvido recusa aceite]
        └─→ CANCELADO                  [cidadão cancela antes da distribuição]
```

### 16.3 SituacaoAnaliseRecursoEnum — transições

```
(criada ao distribuir 1ª instância ou criar colegiado 2ª instância)

EM_ANALISE
  ├─→ AGUARDANDO_AVALIACAO_COLEGIADO  [2ª instância: enviado ao colegiado]
  └─→ ANALISE_CONCLUIDA              [despacho emitido]

AGUARDANDO_AVALIACAO_COLEGIADO
  └─→ ANALISE_CONCLUIDA              [analista conclui após votação do colegiado]
```

---

## 17. Validações — RecursoRNVal

Campos do `RecursoDTO` validados antes do registro:

| Campo | Validação | Erro |
|---|---|---|
| `tipoSolicitacao` | Not null | HTTP 400 — campos obrigatórios |
| `tipoRecurso` | Not null | HTTP 400 — campos obrigatórios |
| `instancia` | Not null, entre 1 e 2 | HTTP 400 — campos obrigatórios |
| `fundamentacaoLegal` | Not blank | HTTP 400 — campos obrigatórios |
| `idLicenciamento` | Not null | HTTP 400 — campos obrigatórios |
| `idArquivoCiaCiv` | Not null | HTTP 400 — campos obrigatórios |
| `cpfRts / cpfRus / cpfProprietarios` | Pelo menos um não vazio | HTTP 400 — envolvidos não informados |

**Prazos validados em `RecursoRN.registra()`:**
- 1ª instância: máximo de 30 dias após `dthCiencia` do CIA/CIV.
- 2ª instância: máximo de 15 dias após `dthCienciaAtec` da análise da 1ª instância.

**Validações do colegiado em `AvalistaRecursoAdmRN.criarColegiado()`:**
- `recursoId != null`
- `usuariosSoeId != null && !isEmpty`
- `usuariosSoeId.size() <= 2` (máximo 2 avalistaes)
- `recursoED.instancia == 2`

**Validação da análise em `AnaliseRecursoAdmRN.analisarRecurso()`:**
- `despacho != blank`
- `decisao != null`

---

## 18. Tabelas do Banco de Dados

### 18.1 Mapeamento de tabelas existentes

| Tabela | Entidade | Sequence | Notas |
|---|---|---|---|
| `CBM_RECURSO` | `RecursoED` | `CBM_ID_RECURSO_SEQ` | PK: `NRO_INT_RECURSO` |
| `CBM_ANALISE_RECURSO` | `AnaliseRecursoED` | `CBM_ID_ANALISE_RECURSO_SEQ` | PK: `NRO_INT_ANALISE_RECURSO` |
| `CBM_RECURSO_MARCO` | `RecursoMarcoED` | `CBM_ID_RECURSO_MARCO_SEQ` | PK: `NRO_INT_RECURSO_MARCO` |
| `CBM_RECURSO_ARQUIVO` | `RecursoArquivoED` | `CBM_ID_RECURSO_ARQUIVO_SEQ` | PK: `NRO_INT_RECURSO_ARQUIVO` |
| `CBM_AVALISTA_RECURSO` | `AvalistaRecursoED` | `CBM_ID_AVALISTA_RECURSO_SEQ` | PK: `NRO_INT_AVALISTA_RECURSO` |

### 18.2 Colunas detalhadas de CBM_RECURSO

| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| `NRO_INT_RECURSO` | `NUMBER` | PK, NOT NULL | ID gerado por sequence |
| `NRO_INT_LICENCIAMENTO` | `NUMBER` | NOT NULL, FK → CBM_LICENCIAMENTO | Licenciamento contestado |
| `NRO_INSTANCIA` | `NUMBER(1)` | NOT NULL | 1 ou 2 |
| `TP_SITUACAO` | `NUMBER` | NOT NULL | ordinal de `SituacaoRecurso` |
| `TP_RECURSO` | `NUMBER` | NOT NULL | ordinal de `TipoRecurso` |
| `TP_SOLICITACAO` | `NUMBER` | NOT NULL | ordinal de `TipoSolicitacaoRecurso` |
| `TXT_FUNDAMENTACAO_LEGAL` | `CLOB` | nullable | Texto de justificativa |
| `DTH_ENVIO_ANALISE` | `TIMESTAMP` | nullable | Preenchido ao concluir aceites |
| `NRO_INT_ARQUIVO_CIA_CIV` | `NUMBER` | nullable, FK → CBM_ARQUIVO | CIA ou CIV contestado |
| `NRO_INT_USUARIO_SOE` | `NUMBER` | nullable | ID do analista no SOE |
| `CTR_DTH_INC` | `TIMESTAMP` | NOT NULL | Data de criação |
| `CTR_DTH_ATU` | `TIMESTAMP` | nullable | Data de atualização |
| `CTR_USU_INC` | `NUMBER` | NOT NULL | ID do usuário criador |
| `CTR_USU_ATU` | `NUMBER` | nullable | ID do último atualizador |
| `CTR_NRO_IP_INC` | `VARCHAR2` | nullable | IP de criação |

### 18.3 Colunas detalhadas de CBM_ANALISE_RECURSO

| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| `NRO_INT_ANALISE_RECURSO` | `NUMBER` | PK, NOT NULL | ID gerado por sequence |
| `NRO_INT_RECURSO` | `NUMBER` | NOT NULL, FK → CBM_RECURSO | Recurso analisado (1:1) |
| `TP_STATUS` | `NUMBER` | nullable | ordinal de `StatusRecurso` |
| `TXT_DESPACHO` | `CLOB` | nullable | Despacho/parecer |
| `NRO_INT_USUARIO_SOE` | `NUMBER` | NOT NULL | Analista que concluiu |
| `DTH_CIENCIA_ATEC` | `TIMESTAMP` | nullable | Data da ciência da resposta |
| `NRO_INT_USUARIO_CIENCIA` | `NUMBER` | nullable | ID do usuário que tomou ciência |
| `IND_CIENCIA` | `CHAR(1)` | nullable (`S`/`N`) | Indica se houve ciência |
| `NRO_INT_ARQUIVO` | `NUMBER` | nullable, FK → CBM_ARQUIVO | PDF do relatório |
| `TP_SITUACAO` | `VARCHAR2(40)` | NOT NULL | STRING de `SituacaoAnaliseRecursoEnum` |
| `CTR_DTH_CONCLUSAO_ANALISE` | `TIMESTAMP` | nullable | Data de conclusão da análise |

### 18.4 Colunas detalhadas de CBM_AVALISTA_RECURSO

| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| `NRO_INT_AVALISTA_RECURSO` | `NUMBER` | PK | ID gerado por sequence |
| `NRO_INT_ANALISE_RECURSO` | `NUMBER` | NOT NULL, FK → CBM_ANALISE_RECURSO | Análise do colegiado |
| `NRO_INT_USUARIO_SOE` | `NUMBER` | NOT NULL | ID do avalistano SOE |
| `IND_ACEITE` | `CHAR(1)` | nullable (`S`/`N`) | Voto do avalista |
| `TXT_JUSTIFICATIVA` | `VARCHAR2(4000)` | nullable | Justificativa do voto contrário |

---

## 19. Fluxos de Negócio Detalhados

### 19.1 Fluxo completo de Ciência Manual do CIA (ATEC)

```
[Frontend] Cidadão clica em "Confirmar Ciência" na tela do CIA
    ↓
[REST] POST /ciencia/{idLicenciamento}/confirmar  (ou endpoint equivalente no LicenciamentoRest)
    ↓
[RN] LicenciamentoCienciaCidadaoBaseRN.efetuarCiencia(AnaliseLicenciamentoTecnicaED)
    1. usuarioED = usuarioRN.getUsuarioLogado()
    2. analise.setCiencia(true)
    3. analise.setDthCiencia(dataAtualHelper.getDataAtual())
    4. analise.setUsuarioCiencia(usuarioED)
    5. alteraLicenciamentoCiencia(analise)
       └─ analiseLicenciamentoTecnicaBD.altera(analise)  [persiste no BD]
    6. atualizarLicenciamento(analise):
       └─ se reprovado: licenciamentoRN.atualizarComSituacao(lic, SituacaoLicenciamento.NCA)
    7. licenciamentoMarcoCidadaoRN.incluiComArquivo(CIENCIA_CIA_ATEC, licenciamento, analise.getArquivo())
    ↓
[BD] CBM_ANALISE_LICENCIAMENTO_TECNICA atualizado (IND_CIENCIA='S', DTH_CIENCIA=now())
[BD] CBM_LICENCIAMENTO atualizado (TP_SITUACAO='NCA')
[BD] CBM_LICENCIAMENTO_MARCO inserido (CIENCIA_CIA_ATEC, CIDADAO)
```

### 19.2 Fluxo completo de Ciência Automática do CIA (ATEC)

```
[EJB Timer] @Schedule(hour="12/12") → LicenciamentoCienciaBatchRN.efetuaCienciaAutomatica()
    │
    ├─ dataLimite = dataAtual - 30 dias
    │
    └─ analiseLicenciamentoTecnicaCienciaAutomaticaRN.efetuaCienciaAutomatica(dataLimite)
           ↓
       listarPendentesDeCiencia(dataLimite)
           └─ analiseLicenciamentoTecnicaBD.listarPendentesDeCiencia(dataLimite)
              [busca AnaliseLicenciamentoTecnicaED com ciencia=false e dthStatus <= dataLimite]
           ↓
       Para cada AnaliseLicenciamentoTecnicaED pendente:
           efetuarCienciaAutomatica(analise)
               1. analise.setCiencia(true)
               2. analise.setDthCiencia(dataAtualHelper.getDataAtual())
                  (sem setUsuarioCiencia — automático)
               3. alteraLicenciamentoCiencia(analise) → BD
               4. atualizarLicenciamento(analise) → SituacaoLicenciamento.NCA
               5. licenciamentoMarcoSistemaRN.incluiComArquivo(CIENCIA_AUTO_CIA_ATEC, lic, arquivo)
```

### 19.3 Fluxo completo de Recurso Administrativo (1ª instância)

```
[Frontend] Cidadão preenche formulário de recurso
    ↓
[REST] POST /recursos  { RecursoDTO }
    ↓
[RN] RecursoRN.registra(dto)
    1. RecursoRNVal.valida(dto)  [campos obrigatórios + pelo menos 1 envolvido]
    2. Verifica prazo: 30 dias da ciência
    3. Cria RecursoED { situacao = AGUARDANDO_APROVACAO_ENVOLVIDOS }
    4. Cria SolicitacaoResponsavelTecnicoED/ResponsavelUsuarioED/ProprietarioED por CPF
    5. Registra marcos iniciais

[Envolvidos] Cada envolvido confirma aceite:
    ↓
[REST] PUT /recursos/{recursoId}  { aceite: true }
    ↓
[RN] RecursoRN.alterarRecurso(id, dto)
    1. Registra aceite do envolvido
    2. Se todos confirmaram:
       a. recurso.situacao = AGUARDANDO_DISTRIBUICAO
       b. recurso.dataEnvioAnalise = now()
       c. Marcos: ENVIO_RECURSO_ANALISE, FIM_ACEITES_RECURSO_ANALISE

[Coordenador] Distribui recurso ao analista:
    ↓
[REST] PUT /adm/recurso-analise/distribuicoes-recurso  { RecursoDistribuicaoAnaliseDTO }
    ↓
[RN] RecursoAdmRN.distribuirRecurso(dto)
    1. recurso.idUsuarioSoe = dto.usuarioSoeId
    2. recurso.situacao = EM_ANALISE
    3. Marco: DISTRIBUICAO_ANALISE_RECURSO

[Analista] Emite despacho:
    ↓
[REST] POST /adm/recurso-analise  { AnaliseRecursoDTO }
    ↓
[RN] AnaliseRecursoAdmRN.analisarRecurso(dto)
    1. Valida despacho e decisão
    2. deferimentoTotal1Instancia(): trata caso DEFERIDO_TOTAL + INTEGRAL
    3. Cria AnaliseRecursoED { ciencia=false, situacao=ANALISE_CONCLUIDA }
    4. recurso.situacao = ANALISE_CONCLUIDA
    5. Marco: RESPOSTA_RECURSO
    6. geraRelatorioAnalise() → PDF → Alfresco → AnaliseRecursoED.arquivo

[Cidadão] Toma ciência da resposta:
    ↓
[REST] (endpoint de ciência da análise de recurso)
    ↓
[RN] AnaliseRecursoRN.alterar(analiseRecursoED)
    1. analise.dthCienciaAtec = Calendar.getInstance()
    2. analise.idUsuarioCiencia = usuarioRN.getUsuarioLogado().getId()
    3. analise.ciencia = true
    4. Persiste
    5. Marco CIENCIA_RECURSO no recurso (CIDADAO)
    6. Marco CIENCIA_RECURSO no licenciamento (CIDADAO)
    ↓
    [Se INDEFERIDO e dentro de 15 dias: cidadão pode interpor 2ª instância]
```

### 19.4 Fluxo de 2ª instância (Colegiado)

```
[Coordenador] Cria colegiado com até 2 avalistaes:
    ↓
[REST] POST /adm/recurso-analise/colegiado  { AnaliseRecursoColegiadoDTO }
    ↓
[RN] AvalistaRecursoAdmRN.criarColegiado(dto)
    1. Valida: instancia=2, max 2 avalistaes, recursoId preenchido
    2. Cria AnaliseRecursoED { situacao=AGUARDANDO_AVALIACAO_COLEGIADO }
    3. Cria AvalistaRecursoED por usuarioSoeId com aceite=false
    4. Marco: ENVIO_PARA_COLEGIADO

[Avalista 1] Concorda:
    ↓
[REST] PUT /adm/recurso-analise/recurso/{recursoId}
    ↓
[RN] AnaliseRecursoAdmRN.concordoColegiado(recursoId)
    1. avalista.setAceite(true)
    2. Marco: ANALISE_RECURSO_COLEGIADO (individual)
    3. Se todos concordaram: Marco FIM_ANALISE_RECURSO_COLEGIADO (SISTEMA)

[Avalista 2] Concorda ou discorda:
    ↓ concorda → PUT /adm/recurso-analise/recurso/{recursoId}
    ↓ discorda → PUT /adm/recurso-analise/avalista-nao-concordo/{recursoId}

[Analista] Emite despacho final:
    ↓
[REST] POST /adm/recurso-analise/segunda-instancia  { AnaliseRecursoDTO }
    ↓
[RN] AnaliseRecursoAdmRN.analisarSegundaInstancia(dto)
    1. deferimentoTotal2Instancia(): mesma lógica da 1ª
    2. analise.situacao = ANALISE_CONCLUIDA
    3. recurso.situacao = ANALISE_CONCLUIDA
    4. Marco: RESPOSTA_RECURSO_2
    5. geraRelatorioAnalise() → PDF → Alfresco
```

---

## 20. Estrutura de Pacotes

```
com.procergs.solcbm
├── ed/
│   ├── Ciencia.java                          (interface)
│   ├── LicenciamentoCiencia.java             (interface)
│   ├── RecursoED.java
│   ├── AnaliseRecursoED.java
│   ├── RecursoMarcoED.java
│   ├── RecursoArquivoED.java
│   └── AvalistaRecursoED.java
│
├── enumeration/
│   ├── TipoLicenciamentoCiencia.java
│   ├── SituacaoRecurso.java
│   ├── TipoRecurso.java
│   ├── TipoSolicitacaoRecurso.java
│   ├── StatusRecurso.java
│   ├── StatusRecursoAnalise.java
│   └── SituacaoAnaliseRecursoEnum.java
│
├── qualifier/
│   └── LicenciamentoCienciaQualifier.java    (@Qualifier CDI)
│
├── licenciamentociencia/
│   ├── LicenciamentoCienciaRN.java           (interface)
│   ├── LicenciamentoCienciaCidadaoRN.java    (interface)
│   ├── LicenciamentoCienciaAutomaticaRN.java (interface)
│   ├── LicenciamentoCienciaBaseRN.java       (abstract)
│   ├── LicenciamentoCienciaCidadaoBaseRN.java(abstract)
│   ├── LicenciamentoCienciaAutomaticaBaseRN.java (abstract)
│   ├── LicenciamentoCienciaBatchRN.java      (@Stateless, @Schedule)
│   ├── analise/
│   │   ├── AnaliseLicenciamentoTecnicaCienciaCidadaoRN.java  (@Stateless, @ATEC)
│   │   ├── AnaliseLicenciamentoTecnicaCienciaAutomaticaRN.java (@Stateless, @ATEC)
│   │   ├── AnaliseLicInviabilidadeCienciaCidadaoRN.java      (@Stateless, @INVIABILIDADE)
│   │   └── AnaliseLicInviabilidadeCienciaAutomaticaRN.java   (@Stateless, @INVIABILIDADE)
│   ├── vistoria/
│   │   ├── CivCienciaCidadaoRN.java          (@Stateless, @CIV)
│   │   └── CivCienciaAutomaticaRN.java       (@Stateless, @CIV)
│   └── appci/
│       ├── AppciCienciaCidadaoRN.java        (@Stateless, @APPCI)
│       └── AppciCienciaCidadaoRenovacaoRN.java (@Stateless, @APPCI_RENOV)
│
├── recurso/
│   ├── RecursoRN.java                        (@Stateless — principal)
│   ├── RecursoRNVal.java                     (validações)
│   ├── RecursoBD.java                        (DAO)
│   ├── RecursoMarcoRN.java                   (marcos do recurso)
│   ├── RecursoMarcoBD.java                   (DAO de marcos)
│   ├── RecursoArquivoRN.java                 (arquivos do recurso)
│   ├── RecursoArquivoBD.java                 (DAO de arquivos)
│   ├── RecursoCienciaAutomaticaRN.java       (ciência automática da resposta)
│   └── adm/
│       ├── RecursoAdmRN.java                 (@Stateless — distribuição)
│       ├── RecursoMarcoAdmRN.java            (@Stateless — marcos adm)
│       └── SolicitantanteRecursoBD.java      (DAO de solicitantes)
│
├── analiserecurso/
│   ├── AnaliseRecursoRN.java                 (@Stateless — ciência da resposta)
│   ├── AnaliseRecursoAdmRN.java              (@Stateless — análise pelo CBM-RS)
│   └── AnaliseRecursoBD.java                 (DAO)
│
├── avalistaanaliserecurso/
│   ├── AvalistaRecursoAdmRN.java             (@Stateless — colegiado)
│   └── AvalistaRecursoBD.java                (DAO)
│
├── ped/
│   ├── RecursoPesqED.java                    (filtros de pesquisa — adm)
│   ├── RecursoMinhasSolitacaoesPesED.java    (filtros — cidadão)
│   └── MinhasSolicitacoesRecursoPesqED.java  (alias)
│
├── remote/
│   ├── RecursoRest.java                      (@Path("/recursos"))
│   ├── RecursoArquivoRest.java               (@Path("/recurso-arquivos"))
│   └── adm/
│       ├── AvalistaRecursoRest.java          (interface)
│       ├── AvalistaRecursoRestImpl.java      (implementação)
│       └── recurso/
│           ├── RecursoAdmRest.java           (interface — @Path("adm/recursos"))
│           ├── RecursoAdmRestImpl.java       (implementação)
│           ├── RecursoAnaliseRest.java       (interface — @Path("/adm/recurso-analise"))
│           └── RecursoAnaliseRestImpl.java   (implementação)
│
├── remote/ed/
│   ├── RecursoDTO.java
│   ├── RecursoResponseDTO.java
│   ├── AnaliseRecursoDTO.java
│   ├── AnaliseRecursoResponseDTO.java
│   ├── AnaliseRecursoColegiadoDTO.java
│   ├── RecursoDistribuicaoAnaliseDTO.java
│   ├── AvalistaRecursoDTO.java
│   ├── RecursoArquivoDTO.java
│   ├── RecursoAnalise.java
│   ├── EstabelecimentoRecursoDTO.java
│   └── LicenciamentoRecursoDTO.java
│
├── dto/
│   ├── RecursoMarcoDTO.java
│   ├── RecursoAnaliseAnalistaDTO.java
│   ├── AnaliseRecursoRelatorioDTO.java
│   └── recurso/
│       ├── RecursoDecisaoDTO.java
│       ├── RecursoPendenteDTO.java
│       └── ProcessosAnalistaRecursoDTO.java
│
├── builder/
│   ├── BuilderMinhasSolicitacoesRecursoED.java
│   └── recursoAdm/
│       ├── BuilderRecursoAnalise.java
│       └── BuilderRecursoAnaliseED.java
│
├── licenciamento/
│   └── DocumentoRelatorioAnaliseRecursoRN.java  (geração PDF JasperReports)
│
└── licenciamentointegracaolai/
    └── lai/soapclient/generated/
        ├── CadastraRecurso.java             (integração LAI — Lei de Acesso à Informação)
        ├── CadastraRecursoResponse.java
        ├── ObtemDadosRecurso.java
        └── ObtemDadosRecursoResponse.java
```

---

## Observações Finais

1. **SimNaoBooleanConverter:** todos os campos `Boolean` em entidades do P05 que são persistidos como `'S'`/`'N'` (e não `true`/`false`) usam `@Convert(converter = SimNaoBooleanConverter.class)`. São eles: `AnaliseRecursoED.ciencia` e `AvalistaRecursoED.aceite`.

2. **@Enumerated sem EnumType:** quando `@Enumerated` é usado sem especificar `EnumType`, o padrão é `EnumType.ORDINAL`. Isso significa que o ordinal do enum (0, 1, 2...) é salvo no banco. Alterar a ordem dos valores ou adicionar novos valores no meio de um enum pode quebrar a consistência dos dados.

3. **Integração LAI:** o pacote `licenciamentointegracaolai` indica que recursos interpostos devem ser registrados também no sistema da Lei de Acesso à Informação (LAI) via SOAP. Esta integração deve ser preservada no ciclo de vida do recurso.

4. **Nota (auditoria):** o método `notaRN.concluirNota(idLicenciamento)` é chamado em vários pontos da análise de recurso. Isso indica que existe um sistema de notas internas (pendências) associadas ao licenciamento que são fechadas quando a análise avança.

5. **@AppInterceptor:** aplicado em todos os `@Stateless` do domínio administrativo. Este interceptor CDI é responsável por cross-cutting concerns como logging, rastreamento e possivelmente controle transacional adicional do framework arqjava4.

6. **Campo `reserva`:** o campo `reserva` em `LicenciamentoED` pode ser alternado via `PUT /adm/recursos/reserva/{idLic}`. Indica que o processo está "reservado" para alguma finalidade interna do CBM-RS.

7. **Visibilidade dos marcos:** marcos com `TipoVisibilidadeMarco.BOMBEIROS` são visíveis apenas para analistas/coordenadores do CBM-RS. Marcos com `TipoVisibilidadeMarco.PUBLICO` são visíveis para o cidadão também.
