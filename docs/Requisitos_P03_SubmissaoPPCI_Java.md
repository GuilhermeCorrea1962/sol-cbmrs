# Requisitos — P03: Wizard de Nova Solicitação de Licenciamento (PPCI)
**Sistema:** SOL — Sistema Online de Licenciamento / CBM-RS
**Versão do documento:** 1.0
**Data:** 2026-03-06
**Destinatário:** Equipe de desenvolvimento Java (nova versão)
**Stack de referência:** Java 21 + Spring Boot 3.x + PostgreSQL (sem dependência da PROCERGS/SOE)

---

## Sumário

1. [Visão Geral do Processo](#1-visão-geral-do-processo)
2. [Stack Tecnológica Recomendada](#2-stack-tecnológica-recomendada)
3. [Premissas e Substituições em Relação ao Sistema Atual](#3-premissas-e-substituições-em-relação-ao-sistema-atual)
4. [Modelo de Dados](#4-modelo-de-dados)
5. [Enumerações e Domínios](#5-enumerações-e-domínios)
6. [Regras de Negócio — Wizard (Etapas 1 a 7)](#6-regras-de-negócio--wizard-etapas-1-a-7)
7. [Regras de Negócio Gerais](#7-regras-de-negócio-gerais)
8. [Especificação da API REST](#8-especificação-da-api-rest)
9. [Segurança e Autorização](#9-segurança-e-autorização)
10. [Gestão de Arquivos e Documentos](#10-gestão-de-arquivos-e-documentos)
11. [Notificações](#11-notificações)
12. [Auditoria e Histórico](#12-auditoria-e-histórico)
13. [Requisitos Não Funcionais](#13-requisitos-não-funcionais)
14. [Glossário](#14-glossário)

---

## 1. Visão Geral do Processo

### 1.1 Descrição

O processo P03 — **Wizard de Nova Solicitação de Licenciamento** — é o processo central do sistema SOL. Ele permite que o Responsável Técnico (RT) ou o Responsável pelo Uso (RU) inicie uma nova solicitação de licenciamento de segurança contra incêndio para um estabelecimento, percorrendo um fluxo guiado de 7 etapas (wizard).

O processo abrange desde a criação do rascunho até o encaminhamento para análise técnica pelo CBM-RS, passando pelo aceite obrigatório do Responsável Técnico.

### 1.2 Atores

| Ator | Papel |
|---|---|
| **Cidadão (RU — Responsável pelo Uso)** | Inicia a solicitação, preenche dados do estabelecimento, aceita o termo de licenciamento |
| **RT — Responsável Técnico** | Profissional habilitado (engenheiro/arquiteto) vinculado à solicitação; deve revisar e aceitar formalmente |
| **Proprietário** | Pessoa física ou jurídica proprietária do imóvel; pode ou não coincidir com o RU |
| **Sistema (automático)** | Gera número do licenciamento, dispara notificações, encaminha para análise |
| **Analista CBM-RS** | Recebe a solicitação após submissão (não faz parte do P03, mas é destinatário final) |

### 1.3 Fluxo Macro (BPMN P03)

```
[Início] → Etapa 1 → Etapa 2 → Etapa 3 → Etapa 4 → Etapa 5 → Etapa 6 → Etapa 7
         → [Submissão] → [RT aceita?]
                            ├─ Não → [Solicitação Recusada]
                            └─ Sim → [Aguarda Análise ADM]
                                         ├─ CA  → [APPCI Emitido]
                                         ├─ NCA → [Encaminha para Vistoria — P07]
                                         └─ CIA → [Arquivado / Inviabilidade]
```

### 1.4 Estados do Licenciamento no P03

```
RASCUNHO
  └─ (cidadão submete + RT aceita)
      └─ AGUARDANDO_ANALISE
          └─ EM_ANALISE
              ├─ APROVADO    (CA  — gera APPCI)
              ├─ REPROVADO   (CIA — inviabilidade)
              └─ PENDENTE_VISTORIA  (NCA — vai para P07)
```

---

## 2. Stack Tecnológica Recomendada

| Camada | Tecnologia |
|---|---|
| **Linguagem** | Java 21 (LTS) |
| **Framework principal** | Spring Boot 3.3.x |
| **API REST** | Spring MVC (substituindo JAX-RS) |
| **Persistência** | Spring Data JPA + Hibernate 6.x |
| **Banco de dados** | PostgreSQL 16 |
| **Migrations de BD** | Flyway |
| **Segurança / IdP** | Spring Security 6 + Keycloak 24 (OIDC/OAuth2) |
| **Mapeamento DTO** | MapStruct 1.5 |
| **Redução de boilerplate** | Lombok |
| **Armazenamento de arquivos** | MinIO (S3-compatible) ou AWS S3 |
| **Validação** | Jakarta Bean Validation 3 (Hibernate Validator) |
| **Notificações por e-mail** | Spring Mail + Jakarta Mail |
| **Documentação de API** | SpringDoc OpenAPI 3 (Swagger UI) |
| **Testes** | JUnit 5 + Mockito + Testcontainers |
| **Build** | Maven 3.9 |

---

## 3. Premissas e Substituições em Relação ao Sistema Atual

| Componente atual (PROCERGS) | Substituto na nova versão | Observação |
|---|---|---|
| SOE PROCERGS / meu.rs.gov.br (IdP OAuth2) | **Keycloak** (self-hosted) | Mantém OIDC/OAuth2; tokens JWT emitidos pelo Keycloak |
| Autenticação via CPF no SOE | Login via CPF + senha no Keycloak | Keycloak suporta atributo customizado CPF |
| `CidadaoSessionMB` (EJB Session Bean) | **Spring Security Context** (`SecurityContextHolder`) | Usuário logado via JWT claims |
| JAX-RS Resources | **Spring MVC `@RestController`** | Mesmos endpoints, mesma semântica REST |
| CDI Beans (`@Inject`) | **Spring Beans (`@Service`, `@Component`)** | Injeção de dependências via Spring |
| JPA/EJB Entities (`@Stateless`) | **Spring Data JPA Repositories** | `JpaRepository<T, ID>` |
| JNDI / Datasource JBoss | **Spring Boot `application.yml`** datasource | Pool gerenciado pelo HikariCP |
| Arquivos no filesystem local | **MinIO / S3** via `spring-cloud-aws` | Armazenamento de objetos com presigned URLs |
| Hibernate Envers (auditoria) | **Hibernate Envers** (mantido) | Compatível com Hibernate 6 |
| EJB Timers (agendamento) | **Spring `@Scheduled`** ou Quartz | Para tarefas periódicas (vencimentos, prazos) |
| Wildfly/JBoss | **Spring Boot Embedded Tomcat / JAR** | Deploy como JAR executável |

---

## 4. Modelo de Dados

### 4.1 Entidade Principal: `Licenciamento`

```java
@Entity
@Table(name = "licenciamento")
@Audited  // Hibernate Envers
public class Licenciamento {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_licenciamento")
    @SequenceGenerator(name = "seq_licenciamento", sequenceName = "seq_licenciamento", allocationSize = 1)
    private Long id;

    // Número público do licenciamento, gerado na submissão
    // Formato: "[TipoLetra] [Sequencial 8 dígitos] [Lote AA] [Versão 3 dígitos]"
    // Exemplo: "A 00000361 AA 001"
    @Column(name = "numero", unique = true)
    private String numero;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo", nullable = false)
    private TipoLicenciamento tipo;         // PPCI, PSPCIM

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao", nullable = false)
    private SituacaoLicenciamento situacao; // ver enum §5

    @Enumerated(EnumType.STRING)
    @Column(name = "fase")
    private FaseLicenciamento fase;         // PROJETO, IMPLANTACAO, OPERACAO

    // Passo atual do wizard (1–7). Persiste o progresso do cidadão.
    @Column(name = "passo_wizard")
    private Integer passoWizard;

    // Data/hora em que a solicitação foi encaminhada para análise
    @Column(name = "dth_encaminhamento_analise")
    private LocalDateTime dataEncaminhamentoAnalise;

    // Indicador de isenção de taxa
    @Column(name = "isento")
    private Boolean isento = false;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_isencao")
    private SituacaoIsencao situacaoIsencao; // PENDENTE, APROVADA, REPROVADA

    @Column(name = "dth_solicitacao_isencao")
    private LocalDateTime dataSolicitacaoIsencao;

    // Metadados de auditoria
    @Column(name = "dth_criacao", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @Column(name = "dth_atualizacao")
    private LocalDateTime dataAtualizacao;

    @Column(name = "usuario_criacao", nullable = false, updatable = false)
    private String usuarioCriacao; // CPF ou identificador do criador

    // --- Relacionamentos ---

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ResponsavelTecnico> responsaveisTecnicos = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ResponsavelUso> responsaveisUso = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Proprietario> proprietarios = new ArrayList<>();

    @OneToOne(cascade = CascadeType.ALL, orphanRemoval = true)
    @JoinColumn(name = "id_localizacao")
    private Localizacao localizacao;

    @OneToOne(cascade = CascadeType.ALL, orphanRemoval = true)
    @JoinColumn(name = "id_caracteristica")
    private Caracteristica caracteristica;

    @OneToOne(cascade = CascadeType.ALL, orphanRemoval = true)
    @JoinColumn(name = "id_espec_seguranca")
    private EspecificacaoSeguranca especificacaoSeguranca;

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<EspecificacaoRisco> especificacoesRisco = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ElementoGrafico> elementosGraficos = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<DocumentoComplementar> documentosComplementares = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL)
    @OrderBy("dataHora DESC")
    private List<LicenciamentoHistorico> historico = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL)
    private List<Appci> appcis = new ArrayList<>();

    @OneToOne(mappedBy = "licenciamento")
    private TermoLicenciamento termoLicenciamento;
}
```

### 4.2 Entidade: `ResponsavelTecnico`

```java
@Entity
@Table(name = "responsavel_tecnico")
@Audited
public class ResponsavelTecnico {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "cpf", nullable = false, length = 11)
    private String cpf;             // apenas dígitos

    @Column(name = "nome", nullable = false)
    private String nome;

    @Column(name = "email", nullable = false)
    private String email;

    @Column(name = "telefone")
    private String telefone;

    @Column(name = "registro_conselho")   // ex: CREA-RS 12345/D
    private String registroConselho;

    @Column(name = "tipo_conselho")       // CREA, CAU, CFT...
    private String tipoConselho;

    // Aceite do RT à solicitação (Etapa pós-submissão)
    @Column(name = "aceite")
    private Boolean aceite = false;

    @Column(name = "dth_aceite")
    private LocalDateTime dataAceite;

    // Se o RT atua por procurador, referência ao arquivo de procuração
    @Column(name = "id_arquivo_procuracao")
    private String idArquivoProcuracao;  // chave no storage (MinIO/S3)

    // Arquivo ART/RRT do RT (vínculo técnico com o projeto)
    @Column(name = "id_arquivo_art")
    private String idArquivoArt;
}
```

### 4.3 Entidade: `ResponsavelUso`

```java
@Entity
@Table(name = "responsavel_uso")
@Audited
public class ResponsavelUso {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "cpf_cnpj", nullable = false, length = 14)
    private String cpfCnpj;

    @Column(name = "nome_razao_social", nullable = false)
    private String nomeRazaoSocial;

    @Column(name = "email", nullable = false)
    private String email;

    @Column(name = "telefone")
    private String telefone;

    @Column(name = "aceite")
    private Boolean aceite = false;

    @Column(name = "dth_aceite")
    private LocalDateTime dataAceite;

    @Column(name = "id_arquivo_procuracao")
    private String idArquivoProcuracao;
}
```

### 4.4 Entidade: `Proprietario`

```java
@Entity
@Table(name = "proprietario")
@Audited
public class Proprietario {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "cpf_cnpj", nullable = false, length = 14)
    private String cpfCnpj;

    @Column(name = "nome_razao_social", nullable = false)
    private String nomeRazaoSocial;

    @Column(name = "tipo_pessoa", nullable = false)  // FISICA, JURIDICA
    @Enumerated(EnumType.STRING)
    private TipoPessoa tipoPessoa;

    @Column(name = "email")
    private String email;

    @Column(name = "telefone")
    private String telefone;

    @Column(name = "aceite")
    private Boolean aceite = false;

    @Column(name = "dth_aceite")
    private LocalDateTime dataAceite;

    @Column(name = "id_arquivo_procuracao")
    private String idArquivoProcuracao;
}
```

### 4.5 Entidade: `Localizacao`

```java
@Entity
@Table(name = "localizacao")
@Audited
public class Localizacao {

    @Id
    @GeneratedValue(...)
    private Long id;

    @Column(name = "cep", nullable = false, length = 8)
    private String cep;

    @Column(name = "logradouro", nullable = false)
    private String logradouro;

    @Column(name = "numero")
    private String numero;          // pode ser "S/N"

    @Column(name = "complemento")
    private String complemento;

    @Column(name = "bairro", nullable = false)
    private String bairro;

    @Column(name = "cidade", nullable = false)
    private String cidade;

    @Column(name = "uf", nullable = false, length = 2)
    private String uf;

    @Column(name = "ibge_municipio", length = 7)
    private String codigoIbge;

    @Column(name = "latitude")
    private Double latitude;

    @Column(name = "longitude")
    private Double longitude;

    // Nome fantasia do estabelecimento neste endereço
    @Column(name = "nome_fantasia")
    private String nomeFantasia;

    // CNPJ/CPF do estabelecimento (pode diferir do proprietário)
    @Column(name = "cnpj_cpf_estabelecimento", length = 14)
    private String cnpjCpfEstabelecimento;
}
```

### 4.6 Entidade: `Caracteristica`

Armazena as características físicas e de uso da edificação.

```java
@Entity
@Table(name = "caracteristica")
@Audited
public class Caracteristica {

    @Id
    @GeneratedValue(...)
    private Long id;

    // Tipo/grupo de ocupação (ex: A-1, B-1, C-1, D-1... conforme IN CBM-RS)
    @Column(name = "grupo_ocupacao", nullable = false)
    private String grupoOcupacao;

    // Descrição da atividade principal exercida no estabelecimento
    @Column(name = "descricao_atividade", nullable = false)
    private String descricaoAtividade;

    // Área total construída em m²
    @Column(name = "area_total_m2", nullable = false, precision = 12, scale = 2)
    private BigDecimal areaTotalM2;

    // Número de pavimentos
    @Column(name = "num_pavimentos", nullable = false)
    private Integer numPavimentos;

    // Altura máxima em metros (piso mais alto acima do nível de saída)
    @Column(name = "altura_maxima_m", precision = 7, scale = 2)
    private BigDecimal alturaMaximaM;

    // Capacidade de lotação (número de pessoas)
    @Column(name = "capacidade_lotacao")
    private Integer capacidadeLotacao;

    // Indicador de subsolo
    @Column(name = "possui_subsolo")
    private Boolean possuiSubsolo = false;

    // Indicador de cobertura (telhado / cobertura vegetal)
    @Column(name = "tipo_cobertura")
    private String tipoCobertura;

    // Arquivos de plantas/projetos associados à característica
    // (referências de chaves no storage externo — MinIO/S3)
    @ElementCollection
    @CollectionTable(name = "caracteristica_arquivo",
                     joinColumns = @JoinColumn(name = "id_caracteristica"))
    @Column(name = "id_arquivo")
    private List<String> idArquivos = new ArrayList<>();
}
```

### 4.7 Entidade: `EspecificacaoSeguranca`

```java
@Entity
@Table(name = "especificacao_seguranca")
@Audited
public class EspecificacaoSeguranca {

    @Id
    @GeneratedValue(...)
    private Long id;

    // Sistemas de prevenção obrigatórios (conforme legislação CBM-RS)
    // Exemplos: "SPRINKLER", "HIDRANTE", "EXTINTORES", "ALARME", "SAIDA_EMERGENCIA"
    @ElementCollection
    @CollectionTable(name = "espec_seg_sistema",
                     joinColumns = @JoinColumn(name = "id_especificacao"))
    @Column(name = "sistema")
    private List<String> sistemasPrevenção = new ArrayList<>();

    // Observações livres do RT sobre as medidas adotadas
    @Column(name = "observacoes", columnDefinition = "TEXT")
    private String observacoes;
}
```

### 4.8 Entidade: `ElementoGrafico`

Representa um documento técnico (planta, memorial, projeto) anexado à solicitação.

```java
@Entity
@Table(name = "elemento_grafico")
@Audited
public class ElementoGrafico {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    // Tipo do documento (ex: PLANTA_BAIXA, CORTE, FACHADA, MEMORIAL_DESCRITIVO)
    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_elemento", nullable = false)
    private TipoElementoGrafico tipoElemento;

    @Column(name = "nome_arquivo", nullable = false)
    private String nomeArquivo;

    @Column(name = "id_arquivo_storage", nullable = false)
    private String idArquivoStorage; // chave no MinIO/S3

    @Column(name = "tamanho_bytes")
    private Long tamanhoBytes;

    @Column(name = "mime_type", length = 100)
    private String mimeType;

    @Column(name = "dth_upload", nullable = false)
    private LocalDateTime dataUpload;
}
```

### 4.9 Entidade: `TermoLicenciamento`

Registra o aceite formal do cidadão ao Termo de Responsabilidade de Licenciamento.

```java
@Entity
@Table(name = "termo_licenciamento")
@Audited
public class TermoLicenciamento {

    @Id
    @GeneratedValue(...)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false, unique = true)
    private Licenciamento licenciamento;

    // Quem aceitou o termo (CPF do cidadão)
    @Column(name = "cpf_aceitante", nullable = false)
    private String cpfAceitante;

    @Column(name = "dth_aceite", nullable = false)
    private LocalDateTime dataAceite;

    // Texto do termo na versão vigente (snapshot imutável)
    @Column(name = "texto_termo", columnDefinition = "TEXT", nullable = false)
    private String textoTermo;

    // IP de origem do aceite (para auditoria)
    @Column(name = "ip_origem")
    private String ipOrigem;
}
```

### 4.10 Entidade: `LicenciamentoHistorico`

Rastreia todas as mudanças de situação do licenciamento.

```java
@Entity
@Table(name = "licenciamento_historico")
public class LicenciamentoHistorico {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_anterior")
    private SituacaoLicenciamento situacaoAnterior;

    @Enumerated(EnumType.STRING)
    @Column(name = "situacao_nova", nullable = false)
    private SituacaoLicenciamento situacaoNova;

    @Column(name = "dth_mudanca", nullable = false)
    private LocalDateTime dataMudanca;

    @Column(name = "usuario_responsavel", nullable = false)
    private String usuarioResponsavel; // CPF ou "SISTEMA"

    @Column(name = "observacao", columnDefinition = "TEXT")
    private String observacao;
}
```

### 4.11 Entidade: `Appci`

Representa o Alvará de Prevenção e Proteção Contra Incêndio emitido ao final do processo.

```java
@Entity
@Table(name = "appci")
@Audited
public class Appci {

    @Id
    @GeneratedValue(...)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @Column(name = "versao", nullable = false)
    private Integer versao;

    @Column(name = "dth_emissao", nullable = false)
    private LocalDateTime dataEmissao;

    @Column(name = "data_validade", nullable = false)
    private LocalDate dataValidade;

    // S = versão vigente, N = versão histórica
    @Column(name = "versao_vigente", nullable = false, length = 1)
    private String versaoVigente = "S";

    @Column(name = "id_arquivo_pdf")
    private String idArquivoPdf;    // chave MinIO/S3 do PDF do APPCI

    // Data/hora em que o cidadão tomou ciência do APPCI
    @Column(name = "dth_ciencia")
    private LocalDateTime dataCiencia;

    @Column(name = "cpf_ciencia")
    private String cpfCiencia;      // CPF de quem tomou ciência
}
```

---

## 5. Enumerações e Domínios

### 5.1 `TipoLicenciamento`

```java
public enum TipoLicenciamento {
    PPCI,    // Plano de Prevenção e Proteção Contra Incêndio (regra geral)
    PSPCIM   // Plano de Segurança para Pequenas e Médias Edificações
             // (simplificado, para edificações de menor porte/risco)
}
```

### 5.2 `SituacaoLicenciamento`

```java
public enum SituacaoLicenciamento {
    RASCUNHO,                   // Criado, wizard em preenchimento
    AGUARDANDO_ACEITE_RT,       // Submetido, aguardando aceite formal do RT
    AGUARDANDO_ANALISE,         // RT aceitou, aguarda abertura de análise
    EM_ANALISE,                 // Analista CBM-RS está analisando
    PENDENTE_AJUSTE,            // CIA emitido — cidadão deve corrigir e reenviar
    APROVADO,                   // CA — análise aprovada, APPCI gerado
    PENDENTE_VISTORIA,          // NCA — aprovado com ressalvas, exige vistoria in loco
    REPROVADO,                  // Análise reprovada definitivamente
    CANCELADO,                  // Cancelado pelo próprio cidadão (só em RASCUNHO)
    EXTINTO                     // Extinto por iniciativa do CBM-RS ou do titular
}
```

### 5.3 `FaseLicenciamento`

```java
public enum FaseLicenciamento {
    PROJETO,      // PPCI em fase de projeto (antes da obra/implantação)
    IMPLANTACAO,  // Obra em andamento
    OPERACAO      // Estabelecimento em operação, com APPCI vigente
}
```

### 5.4 `TipoElementoGrafico`

```java
public enum TipoElementoGrafico {
    PLANTA_BAIXA,
    CORTE,
    FACHADA,
    PLANTA_LOCALIZACAO,
    PLANTA_SITUACAO,
    MEMORIAL_DESCRITIVO,
    LAUDO_TECNICO,
    ART_RRT,            // Anotação de Responsabilidade Técnica / Registro de Responsabilidade Técnica
    OUTRO
}
```

### 5.5 `TipoPessoa`

```java
public enum TipoPessoa {
    FISICA,
    JURIDICA
}
```

### 5.6 `SituacaoIsencao`

```java
public enum SituacaoIsencao {
    PENDENTE,
    APROVADA,
    REPROVADA
}
```

---

## 6. Regras de Negócio — Wizard (Etapas 1 a 7)

O wizard é uma operação multi-step com persistência parcial. O sistema salva o progresso a cada etapa concluída (campo `passoWizard`). O cidadão pode fechar e retomar de onde parou.

### 6.1 Criação do Rascunho

**Quando:** Antes da Etapa 1, ao clicar em "Nova Solicitação".

**RN-P03-001 — Estado inicial**
- Um novo `Licenciamento` é criado com `situacao = RASCUNHO`, `passoWizard = 1`, `fase = PROJETO`.
- O campo `numero` fica nulo até a submissão.
- O `usuarioCriacao` é o CPF do usuário autenticado (extraído do JWT).

**RN-P03-002 — Vínculo obrigatório com o usuário**
- O usuário que cria a solicitação é automaticamente vinculado como `ResponsavelUso` principal.
- Se o usuário autenticado for um RT cadastrado no sistema, pode criar a solicitação em nome do RU, mas deve informar o CPF/CNPJ do RU.

**RN-P03-003 — Persistência da sessão**
- A cada transição de etapa, o backend persiste o estado parcial.
- O frontend consulta `GET /licenciamentos/{id}` ao carregar cada etapa para garantir consistência.
- Se o usuário fechar o navegador, ao retornar encontrará a solicitação listada em "Meus Licenciamentos" com situação `RASCUNHO`.

---

### 6.2 Etapa 1 — Seleção do Tipo de Atividade / Enquadramento

**RN-P03-010 — Seleção de tipo**
- O cidadão seleciona o tipo de licenciamento: `PPCI` ou `PSPCIM`.
- O tipo não pode ser alterado após a submissão.

**RN-P03-011 — Enquadramento PSPCIM**
- O PSPCIM é aplicável apenas a edificações com área total inferior a 750 m² **e** que se enquadrem nos grupos de ocupação permitidos pelo CBM-RS (a ser definido via tabela de configuração).
- Caso o cidadão selecione PSPCIM e posteriormente informe área acima do limite, o sistema deve alertar e sugerir migração para PPCI.

**RN-P03-012 — Persistência**
- Ao concluir a Etapa 1: `passoWizard = 2`, `tipo` salvo.

---

### 6.3 Etapa 2 — Dados do Estabelecimento / Empresa

**RN-P03-020 — Dados obrigatórios do estabelecimento**
- Campos obrigatórios: `nomeFantasia`, `cnpjCpfEstabelecimento`.
- Se pessoa jurídica: CNPJ com 14 dígitos, validado pelo algoritmo de dígitos verificadores.
- Se pessoa física: CPF com 11 dígitos, validado pelo algoritmo de dígitos verificadores.

**RN-P03-021 — Dados do Responsável pelo Uso (RU)**
- O RU deve ser informado com: CPF/CNPJ, nome/razão social, e-mail, telefone.
- O e-mail do RU receberá notificações do processo.
- Pode haver mais de um RU (ex: condomínio com múltiplos responsáveis), porém um deles é designado o principal.

**RN-P03-022 — Dados do Proprietário**
- O proprietário do imóvel pode ou não ser o mesmo que o RU.
- Se for o mesmo, o sistema deve oferecer opção "Proprietário é o mesmo que o Responsável pelo Uso" para pré-preencher os campos.
- Campos obrigatórios do proprietário: CPF/CNPJ, nome/razão social.

**RN-P03-023 — Procuração**
- Se o RU ou proprietário não puder assinar diretamente, pode designar um procurador.
- Neste caso, é obrigatório o upload do arquivo de procuração (PDF, máx. 10 MB).
- O aceite do termo de licenciamento deverá ser feito pelo procurador.

**RN-P03-024 — Persistência**
- Ao concluir a Etapa 2: `passoWizard = 3`, `responsaveisUso` e `proprietarios` salvos.

---

### 6.4 Etapa 3 — Vinculação do Responsável Técnico (RT)

**RN-P03-030 — RT obrigatório para PPCI**
- Para o tipo `PPCI`, é obrigatório vincular ao menos um RT com cadastro aprovado no sistema.
- Para `PSPCIM`, o RT é obrigatório apenas se a legislação estadual vigente assim o exigir (parâmetro configurável).

**RN-P03-031 — Busca do RT**
- O cidadão busca o RT pelo CPF ou pelo número de registro no conselho profissional (CREA, CAU, CFT).
- O sistema consulta o cadastro interno de RTs aprovados (`StatusCadastroRT = APROVADO`).
- Se o RT não estiver cadastrado no SOL, o sistema informa ao cidadão que o RT precisa se cadastrar primeiro (processo P02).

**RN-P03-032 — Dados exibidos do RT**
- Após localizar o RT, exibir: nome, conselho + número de registro, especialidade.
- O cidadão confirma o vínculo.

**RN-P03-033 — Múltiplos RTs**
- É permitido vincular mais de um RT (ex: arquiteto + engenheiro).
- Cada RT vinculado precisará aceitar a solicitação individualmente.

**RN-P03-034 — ART/RRT do RT**
- Após vincular o RT, é obrigatório o upload da ART ou RRT (Anotação/Registro de Responsabilidade Técnica) correspondente ao projeto.
- Formatos aceitos: PDF. Tamanho máximo: 10 MB.
- O arquivo deve ser classificado como `TipoElementoGrafico.ART_RRT`.

**RN-P03-035 — Persistência**
- Ao concluir a Etapa 3: `passoWizard = 4`, `responsaveisTecnicos` salvos, arquivos ART/RRT armazenados.

---

### 6.5 Etapa 4 — Endereço / Localização

**RN-P03-040 — Campos obrigatórios de endereço**
- Obrigatórios: CEP, logradouro, bairro, cidade, UF.
- Número do imóvel: aceitar "S/N" para imóveis sem numeração.
- Complemento: opcional.

**RN-P03-041 — Preenchimento automático via CEP**
- Ao informar o CEP válido, o sistema deve consultar a API de CEPs (ViaCEP ou similar) e preencher automaticamente logradouro, bairro, cidade e UF.
- O cidadão pode editar os campos preenchidos automaticamente.

**RN-P03-042 — Geolocalização**
- O sistema pode oferecer captura de coordenadas geográficas (latitude/longitude) via integração com serviço de geocodificação.
- Campo opcional; não bloqueia o avanço.

**RN-P03-043 — UF restrita**
- O sistema deve aceitar endereços de qualquer UF (o PPCI pode ser para estabelecimento em outro estado com análise CBM-RS, conforme regras internas).
- Porém, deve exibir alerta se UF diferente de "RS".

**RN-P03-044 — Persistência**
- Ao concluir a Etapa 4: `passoWizard = 5`, `localizacao` salva.

---

### 6.6 Etapa 5 — Dados da Edificação

**RN-P03-050 — Grupo de ocupação**
- O campo `grupoOcupacao` deve ser selecionado a partir de uma lista padronizada conforme a Instrução Normativa (IN) do CBM-RS.
- Exemplos de grupos: A (Residencial), B (Serviços de Hospedagem), C (Comércio), D (Serviços Profissionais), E (Educacional), F (Local de Reunião de Público), G (Serviços Automotivos), H (Serviços de Saúde), I (Industrial), J (Depósito), M (Shopping / Misto).
- Esta lista deve ser mantida em tabela de domínio (`grupo_ocupacao`), editável por administradores do sistema.

**RN-P03-051 — Área total construída**
- Campo numérico, obrigatório, maior que zero.
- Unidade: m² (metros quadrados), com precisão de duas casas decimais.
- Não pode ser zero ou negativo.

**RN-P03-052 — Número de pavimentos**
- Campo inteiro, obrigatório, maior que zero.
- Inclui pavimentos acima e abaixo do nível do terreno.

**RN-P03-053 — Altura máxima**
- Campo numérico, obrigatório para PPCI, com precisão de duas casas decimais.
- Representa a altura do piso mais alto em relação ao nível do acesso de saída (critério de enquadramento para exigências construtivas).

**RN-P03-054 — Subsolo**
- Indicador booleano. Se `possuiSubsolo = true`, habilitar campo "Área de subsolo (m²)".

**RN-P03-055 — Capacidade de lotação**
- Campo inteiro, obrigatório para grupos de ocupação classificados como "local de reunião de público" (grupos E, F).
- Opcional para demais grupos.

**RN-P03-056 — Consistência com tipo de licenciamento**
- Se `tipo = PSPCIM` e `areaTotalM2 > 750`, emitir alerta e bloquear avanço até que o cidadão mude para `PPCI` ou corrija a área.

**RN-P03-057 — Persistência**
- Ao concluir a Etapa 5: `passoWizard = 6`, `caracteristica` e `especificacaoSeguranca` salvos.

---

### 6.7 Etapa 6 — Upload de Documentos Obrigatórios

**RN-P03-060 — Lista de documentos obrigatórios**
- Os documentos exigidos dependem do tipo de licenciamento (`PPCI` ou `PSPCIM`) e do grupo de ocupação.
- A lista de documentos obrigatórios deve ser mantida em tabela de configuração (`documento_exigido`), com os campos: tipo de licenciamento, grupo de ocupação, tipo de elemento gráfico, obrigatório (boolean).
- Exemplos para PPCI padrão:

| Documento | Tipo | Obrigatório |
|---|---|---|
| Planta baixa (todos os pavimentos) | PLANTA_BAIXA | Sim |
| Planta de situação / localização | PLANTA_SITUACAO | Sim |
| Corte(s) | CORTE | Sim |
| Memorial descritivo das medidas de segurança | MEMORIAL_DESCRITIVO | Sim |
| ART/RRT do projeto | ART_RRT | Sim |
| Laudo técnico (quando aplicável) | LAUDO_TECNICO | Condicional |

**RN-P03-061 — Formatos e limites**
- Formatos aceitos: PDF, DWG, DXF, PNG, JPG, JPEG.
- Tamanho máximo por arquivo: 50 MB.
- Tamanho máximo total da solicitação: 200 MB.

**RN-P03-062 — Upload multipart**
- Cada documento é enviado individualmente via `POST` multipart.
- O sistema armazena o arquivo no storage externo (MinIO/S3) e registra a referência (`idArquivoStorage`) no banco de dados.
- O upload não deve travar a UI; deve ser assíncrono com indicador de progresso.

**RN-P03-063 — Substituição de documento**
- O cidadão pode substituir um documento já enviado enquanto a solicitação estiver em `RASCUNHO`.
- A substituição apaga o arquivo anterior do storage e cria um novo registro.

**RN-P03-064 — Validação de completude**
- Ao tentar avançar para a Etapa 7, o sistema valida se todos os documentos marcados como obrigatórios foram anexados.
- Se faltarem documentos, exibir lista dos pendentes e bloquear o avanço.

**RN-P03-065 — Persistência**
- Ao concluir a Etapa 6: `passoWizard = 7`, `elementosGraficos` salvos.

---

### 6.8 Etapa 7 — Revisão, Aceite e Confirmação

**RN-P03-070 — Resumo da solicitação**
- A Etapa 7 exibe um resumo consolidado de todos os dados informados nas etapas anteriores.
- Permite navegar de volta a qualquer etapa para corrigir informações (o wizard deve suportar navegação não-linear enquanto em `RASCUNHO`).

**RN-P03-071 — Exibição do Termo de Licenciamento**
- O sistema apresenta o texto integral do Termo de Responsabilidade de Licenciamento.
- O texto do termo deve ser carregado de tabela de configuração (`texto_termo`), com controle de versão.
- O cidadão deve marcar o checkbox "Li e aceito os termos" antes de submeter.

**RN-P03-072 — Submissão**
- Ao clicar em "Confirmar e Enviar":
  1. O sistema valida todos os campos obrigatórios de todas as etapas.
  2. Cria o registro de `TermoLicenciamento` (snapshot do texto, CPF do aceitante, IP de origem, data/hora).
  3. Muda a situação do licenciamento: `RASCUNHO` → `AGUARDANDO_ACEITE_RT`.
  4. Notifica cada RT vinculado por e-mail (ver §11).
  5. Retorna ao cidadão a confirmação com o número provisório da solicitação.

**RN-P03-073 — Número do licenciamento**
- O número definitivo no formato `[Tipo][Sequencial][Lote][Versão]` é gerado **na submissão**.
- O sequencial é gerado por sequence do banco de dados (atômica, sem gaps).
- Formato detalhado:
  - `[Tipo]`: letra que representa o tipo de atividade, definida por tabela de domínio.
  - `[Sequencial]`: 8 dígitos com zero à esquerda (ex: `00000361`).
  - `[Lote]`: código alfabético de 2 letras (ex: `AA`), incrementa conforme regra de lote.
  - `[Versão]`: 3 dígitos com zero à esquerda (ex: `001`). Inicialmente sempre `001`.
- Exemplo: `A 00000361 AA 001`.

**RN-P03-074 — Imutabilidade pós-submissão**
- Após a submissão, o cidadão **não pode alterar** nenhum dado da solicitação.
- Qualquer correção deve ser solicitada via CIA (Comunicado de Inconformidade na Análise) — processo gerenciado pelo analista CBM-RS.

---

## 7. Regras de Negócio Gerais

### 7.1 Aceite do RT (pós-submissão)

**RN-P03-080 — Notificação do RT**
- Após a submissão pelo cidadão, cada RT vinculado recebe e-mail com link para revisar e aceitar a solicitação.
- O RT acessa via autenticação no sistema e visualiza os dados da solicitação.

**RN-P03-081 — Prazo de aceite**
- O RT tem prazo de **X dias** para aceitar ou recusar (parâmetro configurável, padrão: 10 dias úteis).
- Se o prazo expirar sem aceite, o sistema pode: (a) notificar novamente o RT e o cidadão, ou (b) cancelar automaticamente a solicitação (conforme regra de negócio a ser confirmada com CBM-RS).

**RN-P03-082 — Aceite do RT**
- O RT acessa o detalhe da solicitação, revisa os documentos e clica em "Aceitar".
- O sistema registra: `aceite = true`, `dataAceite = now()`, no registro de `ResponsavelTecnico`.
- Se houver múltiplos RTs, **todos** devem aceitar antes que a solicitação avance.

**RN-P03-083 — Recusa do RT**
- O RT pode recusar, informando um motivo (texto obrigatório).
- A situação muda para `CANCELADO` (ou estado equivalente de "recusado pelo RT").
- O cidadão é notificado por e-mail do motivo da recusa.
- O cidadão pode iniciar uma nova solicitação, corrigindo o problema indicado.

**RN-P03-084 — Verificação de aceite total**
- O sistema avança a situação para `AGUARDANDO_ANALISE` apenas quando **todos** os RTs tiverem `aceite = true`.
- A verificação ocorre automaticamente após cada aceite individual.

### 7.2 Cancelamento pelo Cidadão

**RN-P03-090 — Cancelamento em rascunho**
- O cidadão pode cancelar uma solicitação com situação `RASCUNHO` a qualquer momento.
- O cancelamento é imediato, sem necessidade de confirmação do CBM-RS.
- Os arquivos no storage são excluídos (ou marcados para exclusão diferida).
- A situação muda para `CANCELADO`.

**RN-P03-091 — Cancelamento após submissão**
- Após a submissão (`situacao != RASCUNHO`), o cancelamento requer justificativa e pode precisar de aprovação do CBM-RS (fluxo de extinção — processo separado).

### 7.3 Regras de Autorização

**RN-P03-100 — Acesso à solicitação**
- Apenas usuários vinculados à solicitação (criador/RU, RTs vinculados, proprietários vinculados) podem visualizá-la.
- Administradores do CBM-RS têm acesso irrestrito para leitura.
- Analistas do CBM-RS têm acesso à solicitação a partir do momento em que ela chega para análise.

**RN-P03-101 — Edição em rascunho**
- Apenas o criador da solicitação (ou usuário com papel `ADMIN`) pode editar uma solicitação em `RASCUNHO`.

**RN-P03-102 — Escopo por usuário**
- O endpoint `GET /licenciamentos` retorna apenas as solicitações do usuário autenticado (como criador, RT, RU ou proprietário).
- Administradores podem aplicar filtros adicionais sem restrição de usuário.

---

## 8. Especificação da API REST

**Base URL:** `/api/v1`
**Autenticação:** Bearer Token JWT (emitido pelo Keycloak)
**Content-Type padrão:** `application/json`
**Erros:** RFC 7807 Problem Details (`application/problem+json`)

### 8.1 Licenciamento — CRUD

#### `POST /licenciamentos`
Cria um novo licenciamento no estado `RASCUNHO`.

**Autorização:** Usuário autenticado com papel `CIDADAO` ou `RT`.

**Request Body:**
```json
{
  "tipo": "PPCI"
}
```

**Response:** `201 Created`
```json
{
  "id": 1234,
  "numero": null,
  "situacao": "RASCUNHO",
  "tipo": "PPCI",
  "fase": "PROJETO",
  "passoWizard": 1,
  "dataCriacao": "2026-03-06T10:00:00Z"
}
```

---

#### `GET /licenciamentos`
Lista os licenciamentos do usuário autenticado, com paginação e filtros.

**Query Parameters:**

| Parâmetro | Tipo | Padrão | Descrição |
|---|---|---|---|
| `pagina` | int | 0 | Número da página (0-based) |
| `tamanho` | int | 20 | Itens por página (máx. 100) |
| `ordenar` | string | `dataCriacao` | Campo de ordenação |
| `ordem` | string | `desc` | `asc` ou `desc` |
| `situacao` | string[] | — | Filtrar por situações (múltiplos) |
| `tipo` | string | — | Filtrar por tipo (`PPCI`, `PSPCIM`) |
| `cidade` | string | — | Filtrar por cidade |
| `termo` | string | — | Busca textual em número/nome fantasia |

**Response:** `200 OK`
```json
{
  "conteudo": [ { /* LicenciamentoResumoDTO */ } ],
  "pagina": 0,
  "tamanho": 20,
  "totalElementos": 45,
  "totalPaginas": 3
}
```

---

#### `GET /licenciamentos/{id}`
Retorna o licenciamento completo, incluindo todos os relacionamentos.

**Response:** `200 OK` — `LicenciamentoDetalheDTO` (objeto completo com RT, RU, localização, documentos, etc.)

**Erros:**
- `404 Not Found` — licenciamento não existe.
- `403 Forbidden` — usuário não é envolvido nesta solicitação.

---

#### `PUT /licenciamentos/{id}`
Atualiza dados de um licenciamento em `RASCUNHO`. Persiste o progresso do wizard.

**Autorização:** Apenas o criador do licenciamento.

**Request Body:** `LicenciamentoEdicaoDTO` (campos opcionais; apenas os informados são atualizados)
```json
{
  "passoWizard": 3,
  "localizacao": {
    "cep": "90040060",
    "logradouro": "Av. Borges de Medeiros",
    "numero": "1501",
    "bairro": "Centro Histórico",
    "cidade": "Porto Alegre",
    "uf": "RS"
  }
}
```

**Validações:**
- Retorna `409 Conflict` se `situacao != RASCUNHO`.
- Retorna `422 Unprocessable Entity` se campos obrigatórios da etapa indicada não forem informados.

**Response:** `200 OK` — `LicenciamentoDetalheDTO` atualizado.

---

#### `DELETE /licenciamentos/{id}`
Cancela um licenciamento em `RASCUNHO`.

**Autorização:** Apenas o criador.

**Validações:**
- Retorna `409 Conflict` se `situacao != RASCUNHO`.

**Response:** `204 No Content`

**Efeitos colaterais:**
- Situação muda para `CANCELADO`.
- Arquivos associados são marcados para exclusão no storage.

---

### 8.2 Submissão do Licenciamento

#### `POST /licenciamentos/{id}/submeter`
Submete a solicitação ao final da Etapa 7 (cidadão aceita o termo).

**Autorização:** Criador do licenciamento.

**Request Body:**
```json
{
  "textoTermoConfirmado": true,
  "ipOrigem": "189.xxx.xxx.xxx"
}
```

**Validações (sequenciais):**
1. `situacao == RASCUNHO` — senão `409`.
2. Todos os campos obrigatórios de todas as etapas preenchidos — senão `422` com lista de campos faltantes.
3. Ao menos um RT vinculado com arquivo ART/RRT enviado — senão `422`.
4. Todos os documentos obrigatórios enviados — senão `422` com lista de tipos faltantes.
5. `textoTermoConfirmado == true` — senão `422`.

**Efeitos colaterais (em transação):**
1. Gera `numero` do licenciamento via sequence.
2. Cria registro de `TermoLicenciamento` (snapshot do texto + CPF + IP + timestamp).
3. Muda `situacao` para `AGUARDANDO_ACEITE_RT`.
4. Registra no `LicenciamentoHistorico`.
5. Envia e-mail a cada RT vinculado (async, fora da transação).

**Response:** `200 OK`
```json
{
  "id": 1234,
  "numero": "A 00000361 AA 001",
  "situacao": "AGUARDANDO_ACEITE_RT",
  "mensagem": "Solicitação enviada com sucesso. Aguardando aceite do Responsável Técnico."
}
```

---

### 8.3 Aceite do RT

#### `POST /licenciamentos/{id}/rt/{idRt}/aceitar`
O RT aceita formalmente sua vinculação à solicitação.

**Autorização:** Usuário autenticado deve ser o RT identificado por `idRt`.

**Validações:**
- `situacao == AGUARDANDO_ACEITE_RT` — senão `409`.
- O CPF do usuário autenticado deve corresponder ao CPF do RT `idRt` — senão `403`.

**Efeitos colaterais:**
1. Define `responsavelTecnico.aceite = true`, `dataAceite = now()`.
2. Verifica se **todos** os RTs aceitaram.
3. Se sim: muda `situacao` para `AGUARDANDO_ANALISE`; registra no histórico; notifica analistas CBM-RS (async).
4. Se não: aguarda demais RTs.

**Response:** `200 OK`
```json
{
  "mensagem": "Aceite registrado com sucesso.",
  "todosAceitaram": true,
  "situacaoAtual": "AGUARDANDO_ANALISE"
}
```

---

#### `POST /licenciamentos/{id}/rt/{idRt}/recusar`
O RT recusa a vinculação à solicitação.

**Autorização:** Usuário autenticado deve ser o RT identificado por `idRt`.

**Request Body:**
```json
{
  "motivo": "Não fui contratado para este projeto. CPF incorreto."
}
```

**Validações:**
- `situacao == AGUARDANDO_ACEITE_RT` — senão `409`.
- `motivo` obrigatório (mín. 10 caracteres).

**Efeitos colaterais:**
1. Muda `situacao` para `CANCELADO`.
2. Registra motivo no histórico.
3. Notifica o criador da solicitação por e-mail.

**Response:** `200 OK`

---

### 8.4 Gestão de Responsáveis Técnicos

#### `POST /licenciamentos/{id}/responsaveis-tecnicos`
Vincula um RT à solicitação (durante a Etapa 3).

**Request Body:**
```json
{
  "cpf": "12345678901"
}
```

**Validações:**
- RT deve estar cadastrado no SOL com `statusCadastro = APROVADO`.
- RT não pode estar duplicado na mesma solicitação.

**Response:** `201 Created` — dados do RT vinculado.

---

#### `DELETE /licenciamentos/{id}/responsaveis-tecnicos/{idRt}`
Remove um RT da solicitação (apenas em `RASCUNHO`).

**Response:** `204 No Content`

---

### 8.5 Upload e Gestão de Arquivos

#### `POST /licenciamentos/{id}/documentos`
Faz upload de um documento e associa ao licenciamento.

**Autorização:** Criador do licenciamento; solicitação em `RASCUNHO`.

**Content-Type:** `multipart/form-data`

**Form Fields:**

| Campo | Tipo | Descrição |
|---|---|---|
| `arquivo` | file | Arquivo a ser enviado |
| `tipo` | string | Valor de `TipoElementoGrafico` |
| `idResponsavelTecnico` | long | (Opcional) ID do RT ao qual o arquivo pertence (para ART/RRT) |

**Validações:**
- Tamanho máximo por arquivo: 50 MB.
- Formatos aceitos: `application/pdf`, `image/png`, `image/jpeg`, `image/dwg`.
- Tipo deve ser um valor válido de `TipoElementoGrafico`.

**Efeitos colaterais:**
1. Faz upload do arquivo para o MinIO/S3.
2. Cria registro de `ElementoGrafico` com a chave de storage retornada.

**Response:** `201 Created`
```json
{
  "id": 99,
  "tipo": "PLANTA_BAIXA",
  "nomeArquivo": "planta_baixa_ppci.pdf",
  "tamanhoBytes": 2097152,
  "dataUpload": "2026-03-06T14:30:00Z"
}
```

---

#### `GET /licenciamentos/{id}/documentos/{idDocumento}/download`
Retorna uma URL pré-assinada (presigned URL) para download direto do arquivo do storage.

**Response:** `200 OK`
```json
{
  "url": "https://storage.cbmrs.gov.br/sol/...",
  "expiraEm": "2026-03-06T15:30:00Z"
}
```

> A URL pré-assinada tem validade de 1 hora. O frontend faz o download diretamente do storage, sem passar pelo backend, evitando sobrecarga.

---

#### `DELETE /licenciamentos/{id}/documentos/{idDocumento}`
Remove um documento (apenas em `RASCUNHO`).

**Efeitos colaterais:**
1. Remove o arquivo do storage.
2. Remove o registro de `ElementoGrafico`.

**Response:** `204 No Content`

---

### 8.6 Consulta de Dados de Domínio

#### `GET /dominios/grupos-ocupacao`
Retorna a lista de grupos de ocupação disponíveis para seleção na Etapa 5.

**Response:** `200 OK`
```json
[
  { "codigo": "A-1", "descricao": "Residencial unifamiliar" },
  { "codigo": "B-1", "descricao": "Hotel / Hospedagem" },
  ...
]
```

---

#### `GET /dominios/documentos-exigidos`
Retorna os documentos exigidos por tipo de licenciamento e grupo de ocupação.

**Query Parameters:** `tipo` (PPCI | PSPCIM), `grupoOcupacao` (opcional)

**Response:** `200 OK`
```json
[
  { "tipoDocumento": "PLANTA_BAIXA", "descricao": "Planta baixa", "obrigatorio": true },
  { "tipoDocumento": "ART_RRT", "descricao": "ART ou RRT", "obrigatorio": true },
  ...
]
```

---

#### `GET /dominios/texto-termo`
Retorna o texto vigente do Termo de Responsabilidade de Licenciamento.

**Response:** `200 OK`
```json
{
  "versao": "2026.1",
  "texto": "..."
}
```

---

#### `GET /responsaveis-tecnicos/buscar`
Busca um RT cadastrado no sistema para vinculação.

**Query Parameters:** `cpf` OU `registroConselho`

**Response:** `200 OK`
```json
{
  "id": 500,
  "nome": "João da Silva",
  "cpf": "12345678901",
  "tipoConselho": "CREA",
  "registroConselho": "CREA-RS 12345/D",
  "statusCadastro": "APROVADO"
}
```

**Erros:**
- `404 Not Found` — RT não encontrado ou não aprovado.

---

### 8.7 Listagem de Licenciamentos do Usuário

#### `GET /meus-licenciamentos`
Atalho que retorna apenas os licenciamentos onde o usuário autenticado é criador, RT, RU ou proprietário.

Equivalente a `GET /licenciamentos` com filtro implícito pelo usuário autenticado.

---

## 9. Segurança e Autorização

### 9.1 Autenticação

- Toda requisição deve conter o header `Authorization: Bearer {jwt_token}`.
- O JWT é emitido pelo **Keycloak** após login do usuário.
- O backend valida o token via Spring Security com `spring-boot-starter-oauth2-resource-server`.
- A chave pública do Keycloak é obtida via JWKS endpoint configurado em `application.yml`.

**Configuração Spring Security:**
```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwk-set-uri: https://auth.cbmrs.gov.br/realms/sol/protocol/openid-connect/certs
```

### 9.2 Extração do Usuário Autenticado

O CPF do usuário é extraído do claim `cpf` do JWT:

```java
@Component
public class UsuarioAutenticadoService {

    public String getCpfUsuario() {
        JwtAuthenticationToken auth = (JwtAuthenticationToken)
            SecurityContextHolder.getContext().getAuthentication();
        return auth.getToken().getClaimAsString("cpf");
    }
}
```

### 9.3 Papéis (Roles) no Keycloak

| Role | Descrição |
|---|---|
| `ROLE_CIDADAO` | Cidadão (RU/Proprietário): pode criar e acompanhar solicitações |
| `ROLE_RT` | Responsável Técnico: pode ser vinculado e aceitar solicitações |
| `ROLE_ANALISTA_CBM` | Analista CBM-RS: acesso de leitura a solicitações para análise |
| `ROLE_ADMIN` | Administrador do sistema: acesso completo |

### 9.4 Regras de Acesso por Endpoint

| Endpoint | Roles permitidos |
|---|---|
| `POST /licenciamentos` | CIDADAO, RT, ADMIN |
| `GET /licenciamentos/{id}` | Envolvidos na solicitação, ANALISTA_CBM, ADMIN |
| `PUT /licenciamentos/{id}` | Criador da solicitação, ADMIN |
| `DELETE /licenciamentos/{id}` | Criador da solicitação, ADMIN |
| `POST /licenciamentos/{id}/submeter` | Criador da solicitação |
| `POST /licenciamentos/{id}/rt/{idRt}/aceitar` | RT vinculado (cpf == jwt.cpf) |
| `POST /licenciamentos/{id}/rt/{idRt}/recusar` | RT vinculado (cpf == jwt.cpf) |
| `POST /licenciamentos/{id}/documentos` | Criador da solicitação, ADMIN |
| `DELETE /licenciamentos/{id}/documentos/{idDoc}` | Criador da solicitação, ADMIN |
| `GET /dominios/**` | Qualquer usuário autenticado |
| `GET /responsaveis-tecnicos/buscar` | CIDADAO, RT, ADMIN |

### 9.5 Interceptor de Validação de Envolvimento

Implementar um `@Aspect` (AOP) ou `HandlerInterceptor` que, para endpoints com `{id}` de licenciamento, verifique se o CPF do usuário autenticado está vinculado à solicitação (como criador, RT, RU ou proprietário):

```java
@Component
public class EnvolvidoAuthorizationInterceptor implements HandlerInterceptor {

    @Override
    public boolean preHandle(HttpServletRequest request, ...) {
        Long idLicenciamento = extrairIdDaUrl(request);
        String cpfUsuario = usuarioAutenticadoService.getCpfUsuario();
        String role = obterPapelPrincipal();

        if ("ROLE_ADMIN".equals(role) || "ROLE_ANALISTA_CBM".equals(role)) return true;

        boolean isEnvolvido = licenciamentoService.isEnvolvido(idLicenciamento, cpfUsuario);
        if (!isEnvolvido) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        return true;
    }
}
```

---

## 10. Gestão de Arquivos e Documentos

### 10.1 Storage Externo (MinIO / S3)

- Os arquivos **nunca** são armazenados no sistema de arquivos do servidor de aplicação.
- Utilizar MinIO (self-hosted, S3-compatible) ou AWS S3.
- Cada arquivo é identificado por uma chave única no formato:
  ```
  licenciamentos/{idLicenciamento}/documentos/{uuid}.{extensao}
  ```

### 10.2 Serviço de Storage

```java
public interface StorageService {

    /**
     * Armazena o arquivo e retorna a chave de storage.
     */
    String armazenar(MultipartFile arquivo, String chave);

    /**
     * Gera URL pré-assinada para download (validade: 1 hora).
     */
    String gerarUrlDownload(String chave);

    /**
     * Remove o arquivo do storage.
     */
    void remover(String chave);

    /**
     * Verifica se o arquivo existe.
     */
    boolean existe(String chave);
}
```

### 10.3 Validação de Conteúdo

- Validar o tipo real do arquivo pelo magic number (primeiros bytes), não apenas pela extensão.
- Rejeitar arquivos com conteúdo malicioso ou que não correspondam ao tipo declarado.
- Para PDFs: verificar se o arquivo é um PDF válido antes de armazenar.

### 10.4 Limpeza de Arquivos Órfãos

- Quando um licenciamento é `CANCELADO`, todos os arquivos associados devem ser removidos do storage.
- Implementar job periódico (`@Scheduled`) para identificar e remover arquivos órfãos (chaves no storage sem registro correspondente no BD).

---

## 11. Notificações

### 11.1 Eventos e Destinatários

| Evento | Destinatário | Canal |
|---|---|---|
| Licenciamento submetido | Cada RT vinculado | E-mail |
| RT aceitou | Criador (RU) | E-mail |
| RT recusou | Criador (RU) | E-mail |
| Todos os RTs aceitaram | Analistas CBM-RS (grupo) | E-mail |
| CIA emitido (ajuste necessário) | RT + RU | E-mail |
| Licenciamento aprovado (CA) | RT + RU | E-mail |
| Licenciamento reprovado | RT + RU | E-mail |

### 11.2 Implementação

- Usar Spring Mail com templates (Thymeleaf recomendado para templates HTML).
- O envio de e-mail deve ser **assíncrono** (método anotado com `@Async`, fora da transação principal).
- Manter tabela `notificacao_email` com status de envio (`PENDENTE`, `ENVIADO`, `ERRO`) para reprocessamento em caso de falha.

```java
@Service
public class NotificacaoService {

    @Async
    public void notificarRtSubmissao(ResponsavelTecnico rt, Licenciamento lic) {
        EmailDTO email = EmailDTO.builder()
            .destinatario(rt.getEmail())
            .assunto("Nova solicitação de PPCI aguarda seu aceite — " + lic.getNumero())
            .template("email/rt-aceite-solicitado")
            .variavel("nomeRt", rt.getNome())
            .variavel("numeroLicenciamento", lic.getNumero())
            .variavel("linkAceite", gerarLink(lic.getId(), rt.getId()))
            .build();
        emailSender.enviar(email);
    }
}
```

### 11.3 Templates de E-mail

Os templates devem ser mantidos em `src/main/resources/templates/email/` e devem incluir:
- Logotipo do CBM-RS
- Número e tipo da solicitação
- Link direto para a ação requerida no sistema
- Contato de suporte do CBM-RS

---

## 12. Auditoria e Histórico

### 12.1 Auditoria via Hibernate Envers

- Todas as entidades principais devem ser anotadas com `@Audited` do Hibernate Envers.
- Isso cria automaticamente tabelas de auditoria com sufixo `_aud` (ex: `licenciamento_aud`).
- A tabela `revinfo` registra o autor e timestamp de cada revisão.

**Configuração:**
```yaml
spring:
  jpa:
    properties:
      org.hibernate.envers.audit_table_suffix: _aud
      org.hibernate.envers.revision_field_name: rev
      org.hibernate.envers.revision_type_field_name: rev_tipo
      org.hibernate.envers.store_data_at_delete: true
```

**Customizar `RevisionEntity` para incluir o CPF do usuário:**
```java
@Entity
@RevisionEntity(UsuarioRevisionListener.class)
@Table(name = "revinfo")
public class UsuarioRevisionEntity extends DefaultRevisionEntity {
    @Column(name = "cpf_usuario")
    private String cpfUsuario;
}
```

### 12.2 Histórico de Situação

- A tabela `licenciamento_historico` (§4.10) mantém registro manual de cada transição de situação.
- Este histórico é exibido ao usuário na interface como "linha do tempo" da solicitação.
- Cada entrada inclui: situação anterior, situação nova, data/hora, responsável, observação.

---

## 13. Requisitos Não Funcionais

### 13.1 Desempenho

| Requisito | Valor-alvo |
|---|---|
| Tempo de resposta para GET de listagem | < 500 ms (p95) |
| Tempo de resposta para GET de detalhe | < 800 ms (p95) |
| Tempo de resposta para submissão | < 2 s (p95) |
| Upload de arquivo (50 MB) | < 30 s (conexão 10 Mbps) |
| Concorrência mínima suportada | 100 usuários simultâneos |

### 13.2 Escalabilidade

- A aplicação deve ser stateless (sem estado de sessão no servidor).
- O estado da sessão do usuário é mantido pelo JWT.
- Deve suportar execução em múltiplas instâncias atrás de load balancer.

### 13.3 Disponibilidade

- Disponibilidade mínima de 99,5% em horário comercial.
- Janelas de manutenção planejadas fora do horário de pico.

### 13.4 Segurança

- Todas as comunicações via HTTPS (TLS 1.2+).
- Tokens JWT com expiração máxima de 1 hora.
- Refresh tokens gerenciados pelo Keycloak.
- Rate limiting nos endpoints de upload (máx. 10 uploads/min por usuário).
- Validação de content-type por magic number nos uploads.
- Headers de segurança obrigatórios: `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`.

### 13.5 Observabilidade

- Logs estruturados em JSON (via Logback + Logstash encoder).
- Rastreamento de requisições com `traceId` propagado (via Spring Cloud Sleuth ou Micrometer Tracing).
- Métricas expostas via `/actuator/metrics` (Micrometer + Prometheus).
- Health checks em `/actuator/health`.

### 13.6 Compatibilidade de API

- Versionamento via path (`/api/v1/...`).
- Documentação automática via SpringDoc OpenAPI disponível em `/swagger-ui.html`.
- Manter retrocompatibilidade dentro da mesma versão major.

### 13.7 Migrations de Banco de Dados

- Todas as alterações de schema via Flyway.
- Scripts localizados em `src/main/resources/db/migration/`.
- Nomenclatura: `V{versao}__{descricao_snake_case}.sql` (ex: `V1__create_licenciamento.sql`).
- Proibido alterar scripts de migration já aplicados em produção.

---

## 14. Glossário

| Termo | Definição |
|---|---|
| **PPCI** | Plano de Prevenção e Proteção Contra Incêndio — documento técnico obrigatório para obtenção do APPCI |
| **PSPCIM** | Plano de Segurança para Pequenas e Médias edificações — versão simplificada do PPCI |
| **RT** | Responsável Técnico — engenheiro ou arquiteto legalmente habilitado que assina o PPCI |
| **RU** | Responsável pelo Uso — proprietário ou responsável pela utilização do estabelecimento |
| **APPCI** | Alvará de Prevenção e Proteção Contra Incêndio — documento emitido pelo CBM-RS após aprovação do PPCI |
| **CA** | Conformidade Atendida — resultado positivo da análise técnica, que gera o APPCI |
| **NCA** | Não Conformidade Atendida — aprovação condicionada à realização de vistoria in loco |
| **CIA** | Comunicado de Inconformidade na Análise — notificação de pendências que o cidadão deve corrigir |
| **ART** | Anotação de Responsabilidade Técnica (CREA) — documento que vincula o RT ao projeto |
| **RRT** | Registro de Responsabilidade Técnica (CAU) — equivalente da ART para arquitetos |
| **Wizard** | Formulário multi-etapa com navegação passo a passo |
| **RASCUNHO** | Estado inicial de uma solicitação, ainda em preenchimento pelo cidadão |
| **Raia** | Participante (swimlane) no diagrama BPMN |
| **IdP** | Identity Provider — servidor de identidade que emite tokens de autenticação |
| **OIDC** | OpenID Connect — protocolo de autenticação sobre OAuth 2.0 |
| **JWT** | JSON Web Token — token portável de autenticação/autorização |
| **MinIO** | Servidor de armazenamento de objetos compatível com S3, auto-hospedado |
| **Presigned URL** | URL temporária com assinatura criptográfica para acesso direto a um objeto no storage |
| **Flyway** | Ferramenta de controle de versão de schema de banco de dados |
| **Envers** | Módulo do Hibernate para auditoria automática de entidades |
| **MapStruct** | Biblioteca Java para mapeamento automático entre DTOs e entidades via geração de código |

---



---

## 15. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprints 01–04 (ID1501, Demandas 3, 4, 7, 19, 22) e normas RTCBMRS N.º 01/2024 e RT de Implantação SOL-CBMRS 4ª ed./2022.  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P03.

---

### RN-P03-N1 — Alerta Obrigatório de Imutabilidade no Passo 2 (Localização) 🔴 P03-M1

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** ID1501 + RT de Implantação SOL-CBMRS item 6.3.2.1

**Descrição:** Os campos do Passo 2 (endereço, CEP, coordenadas GPS e isolamento de risco) **não podem ser alterados após o primeiro envio do PPCI**. O sistema deve exibir um modal de confirmação com texto normativo exato antes de salvar o Passo 2, e bloquear edição posterior.

**Mudança no fluxo — Gateway após UserTask `P03_T02` (Etapa 2 — Localização):**

```
P03_T02 — Usuário preenche Passo 2
        │
        ▼
[GW] PPCI já possui número de protocolo?
        │
   ┌────┴───────────────────────────────────────┐
   │ SIM                                        │ NÃO
   │ Campos do Passo 2 em modo                  │ Exibir ModalAlertaPasso2
   │ somente leitura (bypass)                   │
   │                                            ▼
   │                               Usuário clica "Confirmar"  ou  "Voltar"
   │                                     │                         │
   │                                     ▼                         ▼
   │                               Salva e avança             Retorna ao
   │                               para Passo 3               Passo 2 sem salvar
   └────────────────────────────────────┘
```

**Texto exato do modal (normativo — não alterar):**

> *"Realize o correto preenchimento do passo 2. Comunicamos que as informações preenchidas no passo 2 não poderão ser editadas após o PPCI ser encaminhado ao CBMRS. Havendo necessidade de alterações das informações preenchidas no passo 2 após o PPCI ser encaminhado ao CBMRS, o processo deverá ser extinto e protocolado novo PPCI, sem aproveitamento das taxas já pagas."*

**Componente Angular:**

```typescript
@Component({ selector: 'app-modal-alerta-passo2', ... })
export class ModalAlertaPasso2Component {
  readonly TEXTO_NORMATIVO = `Realize o correto preenchimento do passo 2...`; // texto completo

  confirmar(): void { this.dialogRef.close(true); }
  voltar(): void { this.dialogRef.close(false); }
}
```

**Constraint no banco — bloquear UPDATE após primeiro envio:**

```sql
-- PostgreSQL: trigger de imutabilidade
CREATE OR REPLACE FUNCTION check_passo2_immutable()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.dt_primeiro_envio IS NOT NULL THEN
    IF NEW.nr_cep       <> OLD.nr_cep       OR
       NEW.ds_logradouro <> OLD.ds_logradouro OR
       NEW.nr_numero     <> OLD.nr_numero     OR
       NEW.nr_latitude   <> OLD.nr_latitude   OR
       NEW.nr_longitude  <> OLD.nr_longitude THEN
      RAISE EXCEPTION 'Campos do Passo 2 são imutáveis após o primeiro envio do PPCI (RT de Implantação SOL item 6.3.2.1)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_passo2_immutable
BEFORE UPDATE ON cbm_licenciamento_endereco
FOR EACH ROW EXECUTE FUNCTION check_passo2_immutable();
```

**Critérios de Aceitação:**
- [ ] CA-P03-N1a: Ao avançar do Passo 2 pela primeira vez, o modal de alerta é exibido com o texto normativo exato
- [ ] CA-P03-N1b: Botão "Confirmar" salva os dados e avança para o Passo 3
- [ ] CA-P03-N1c: Botão "Voltar" retorna ao Passo 2 sem salvar nenhuma alteração
- [ ] CA-P03-N1d: PPCI que já possui número de protocolo exibe o Passo 2 em modo somente leitura (sem modal)
- [ ] CA-P03-N1e: UPDATE de campo do Passo 2 via API após `dt_primeiro_envio IS NOT NULL` retorna erro 422
- [ ] CA-P03-N1f: O trigger `trg_passo2_immutable` rejeita UPDATE direto no banco

---

### RN-P03-N2 — Edição do Passo 1 por Usuários Externos em Estado Editável 🟠 P03-M2

**Prioridade:** Alta  
**Origem:** Demanda 3 — Sprint 02 Hammer

**Descrição:** Permitir edição limitada do Passo 1 (envolvidos: RT, RU, Proprietário) após o envio inicial, desde que o processo ainda esteja nos estados `RASCUNHO` ou `AGUARDANDO_ACEITE`.

**Regras:**
- Edição permitida em: `RASCUNHO`, `AGUARDANDO_ACEITE`
- Edição bloqueada (somente leitura) em: `EM_ANALISE`, `AGUARDANDO_CORRECAO_CIA`, qualquer estado posterior
- **Não é possível trocar o RT** enquanto o processo estiver em análise — usar P09 para isso
- Ao salvar edição do Passo 1, **todos os aceites pendentes são invalidados** e o ciclo de aceites reinicia

**Novo Endpoint:**
```
PUT /api/v1/licenciamentos/{id}/envolvidos
Authorization: Bearer {jwt}
```

```java
@PutMapping("/{id}/envolvidos")
@PreAuthorize("hasRole('RT') and @licenciamentoSecurity.isEnvolvido(#id, authentication)")
public ResponseEntity<Void> atualizarEnvolvidos(
    @PathVariable UUID id,
    @Valid @RequestBody EnvolvidosRequest request) {
    licenciamentoService.atualizarEnvolvidos(id, request);
    return ResponseEntity.noContent().build();
}
```

```java
// LicenciamentoService.atualizarEnvolvidos()
public void atualizarEnvolvidos(UUID id, EnvolvidosRequest req) {
    Licenciamento lic = buscarOuLancar(id);
    if (!List.of(StatusLicenciamento.RASCUNHO, StatusLicenciamento.AGUARDANDO_ACEITE)
             .contains(lic.getStatus())) {
        throw new BusinessException("Envolvidos só podem ser editados em RASCUNHO ou AGUARDANDO_ACEITE");
    }
    // invalida todos os aceites pendentes
    aceiteService.invalidarTodos(id);
    // atualiza envolvidos
    envolvidoRepository.updateEnvolvidos(id, req);
    // reinicia ciclo de aceites
    aceiteService.iniciarCicloAceites(id);
}
```

**Critérios de Aceitação:**
- [ ] CA-P03-N2a: RT pode editar os envolvidos do Passo 1 quando o licenciamento está em `RASCUNHO`
- [ ] CA-P03-N2b: RT pode editar os envolvidos do Passo 1 quando em `AGUARDANDO_ACEITE`
- [ ] CA-P03-N2c: Tentativa de edição em `EM_ANALISE` retorna 422 com mensagem de erro
- [ ] CA-P03-N2d: Após salvar edição do Passo 1, os aceites pendentes são invalidados e o ciclo reinicia
- [ ] CA-P03-N2e: Troca de RT via Passo 1 em `EM_ANALISE` retorna erro orientando a usar o processo P09

---

### RN-P03-N3 — Campo de Número de Assentos para Edificações do Grupo F 🟡 P03-M3

**Prioridade:** Média  
**Origem:** Demanda 7 — Sprint 02 Hammer

**Descrição:** Para edificações com ocupação classificada como **Grupo F** (locais de reunião de público), adicionar campo obrigatório **"Número de assentos"** na Etapa 3 (Características da Edificação).

**Campo condicional:**
```typescript
// edificacao-caracteristicas.component.ts
get exibeAssentos(): boolean {
  return this.form.get('tpGrupoOcupacao')?.value === 'F';
}
```

**Validação Backend:**
```java
// LicenciamentoCaracteristicaValidator.java
if (GrupoOcupacao.F.equals(req.getTpGrupoOcupacao())) {
    if (req.getNrAssentos() == null || req.getNrAssentos() <= 0) {
        throw new ValidationException("nr_assentos", 
            "Número de assentos é obrigatório para edificações do Grupo F");
    }
}
```

**DDL:**
```sql
ALTER TABLE cbm_licenciamento_caracteristica
  ADD COLUMN nr_assentos INTEGER;

COMMENT ON COLUMN cbm_licenciamento_caracteristica.nr_assentos
  IS 'Obrigatório para Grupo F (locais de reunião de público)';
```

**Critérios de Aceitação:**
- [ ] CA-P03-N3a: Campo "Número de assentos" aparece na Etapa 3 quando `tp_grupo_ocupacao = 'F'`
- [ ] CA-P03-N3b: O campo é obrigatório para Grupo F — submissão sem ele retorna 422
- [ ] CA-P03-N3c: O campo não aparece para outros grupos de ocupação

---

### RN-P03-N4 — Novas Classes de Risco e Tipos de Risco na Etapa 5 🟡 P03-M4

**Prioridade:** Média  
**Origem:** Demanda 4 — Sprint 02 Hammer

**Descrição:** A Etapa 5 (Riscos Específicos) deve incluir **classes de risco** associadas a cada tipo de risco, com impacto no cálculo automático da validade do APPCI. O risco "armazenamento de GLP" deve ser exibido com contextualização em múltiplas telas.

**Mudança no modelo de dados:**
```sql
-- Nova tabela de classificação de riscos
CREATE TABLE cbm_classificacao_risco (
    id BIGSERIAL PRIMARY KEY,
    tp_risco_especifico VARCHAR(50) NOT NULL,
    tp_classe_risco VARCHAR(20) NOT NULL
        CHECK (tp_classe_risco IN ('BAIXO','MEDIO','ALTO','ELEVADO')),
    ds_descricao TEXT,
    fg_exibe_contexto BOOLEAN DEFAULT FALSE
);

-- Referência na tabela de riscos do licenciamento
ALTER TABLE cbm_licenciamento_risco
    ADD COLUMN id_classificacao_risco BIGINT
    REFERENCES cbm_classificacao_risco(id);
```

**Impacto no cálculo de validade do APPCI (ver também P13-M4):**
```java
// AppciValidadeCalculadoraRN.java
public int calcularAnosValidade(Licenciamento lic) {
    boolean grupoFRiscoAltoPlusMedio = 
        GrupoOcupacao.F.equals(lic.getTpGrupoOcupacao()) &&
        List.of(ClasseRisco.MEDIO, ClasseRisco.ALTO, ClasseRisco.ELEVADO)
            .contains(lic.getClasseRiscoMaxima());
    return grupoFRiscoAltoPlusMedio ? 2 : 5;
}
```

**Critérios de Aceitação:**
- [ ] CA-P03-N4a: Dropdown de "Classe de Risco" aparece na Etapa 5 para riscos habilitados
- [ ] CA-P03-N4b: Risco "Armazenamento de GLP" exibe aviso contextual nas telas relevantes
- [ ] CA-P03-N4c: A classe de risco selecionada influencia o cálculo de validade do APPCI gerado

---

### RN-P03-N5 — Campo de Upload de Pranchas de Fachadas na Etapa 6 🟢 P03-M5

**Prioridade:** Baixa  
**Origem:** Demanda 19 — Sprint 02 Hammer

**Descrição:** Na Etapa 6 (Upload de Documentos), adicionar campo específico para upload de **pranchas de fachadas**, além dos campos existentes de plantas baixas e outros documentos técnicos.

**Tipos de arquivo aceitos:** PDF, DWG, PNG, JPG (máx. 50MB por arquivo)

**Novo tipo de documento:**
```java
public enum TpDocumentoLicenciamento {
    PLANTA_BAIXA,
    MEMORIAL_DESCRITIVO,
    RRT_ART,
    PRANCHA_FACHADA,  // NOVO
    DOCUMENTO_COMPLEMENTAR
}
```

**Armazenamento:** MinIO / S3 — pasta `licenciamentos/{id}/documentos/fachadas/`

**Critérios de Aceitação:**
- [ ] CA-P03-N5a: Campo de upload de pranchas de fachadas aparece na Etapa 6
- [ ] CA-P03-N5b: Formatos aceitos: PDF, DWG, PNG, JPG
- [ ] CA-P03-N5c: Arquivo armazenado no path correto no MinIO/S3

---

### RN-P03-N6 — QR Code de Autenticação no APPCI 🟡 P03-M6

**Prioridade:** Média  
**Origem:** Demanda 22 / DAS IDI2201 — Sprint 04 Hammer

**Descrição:** O documento APPCI (emitido ao final do P04 e do P14) deve incluir **QR Code** no canto superior direito, com URL de autenticação baseada no `nr_autenticacao` do banco de dados.

**Especificação do QR Code:**
- **Tipo:** QRCode (não Code128, não DataMatrix)
- **Posição:** canto superior direito do documento
- **URL:** `https://solcbm.rs.gov.br/solcbm/autenticacao?id={nr_autenticacao}`
- **Biblioteca:** `barcode4j` (JAR já disponível no classpath)
- **Renderização:** somente quando `nr_autenticacao IS NOT NULL`

**Modificação no `.jrxml` do relatório APPCI:**
```xml
<!-- Adicionar no template JasperReports APPCI.jrxml -->
<componentElement>
  <reportElement x="450" y="5" width="100" height="100"
    isRemoveLineWhenBlank="true"
    printWhenExpression="$F{nrAutenticacao} != null"/>
  <jr:BarcodeComponent 
    xmlns:jr="http://jasperreports.sourceforge.net/jasperreports/components"
    type="QRCode"
    moduleWidth="2.0">
    <jr:codeExpression>
      <![CDATA["https://solcbm.rs.gov.br/solcbm/autenticacao?id=" + $F{nrAutenticacao}]]>
    </jr:codeExpression>
  </jr:BarcodeComponent>
</componentElement>
```

**Nota:** A URL deve usar o parâmetro `APP_URL_BASE` do RF-27 do P01, não hard-coded.

**Critérios de Aceitação:**
- [ ] CA-P03-N6a: APPCI gerado com `nr_autenticacao` preenchido contém QR Code legível
- [ ] CA-P03-N6b: QR Code aponta para `solcbm.rs.gov.br/solcbm/autenticacao?id={nr_autenticacao}`
- [ ] CA-P03-N6c: APPCI sem `nr_autenticacao` não exibe QR Code (sem espaço em branco residual)
- [ ] CA-P03-N6d: QR Code está posicionado no canto superior direito do documento

---

### RN-P03-N7 — Reanálise Deve Verificar Apenas os Itens da CIA Anterior 🔴 P03-M7

**Prioridade:** CRÍTICA — obrigatória por norma  
**Origem:** Norma C2 / RT de Implantação SOL-CBMRS item 6.3.7.2.2

**Descrição:** A partir da 2ª análise, o sistema deve encaminhar o PPCI para reanálise restringindo o escopo aos **itens reprovados na CIA anterior**. Analisar novamente todos os itens em uma reanálise é vedado pela norma.

**Mudança na transição para `AGUARDANDO_DISTRIBUICAO`:**

```java
// LicenciamentoTrocaEstadoRN.java
public void transicionarParaAguardandoDistribuicao(Licenciamento lic) {
    lic.setStatus(StatusLicenciamento.AGUARDANDO_DISTRIBUICAO);
    
    if (lic.getNrAnalise() != null && lic.getNrAnalise() > 1) {
        // Marcar que esta é uma reanálise restrita
        lic.setFgReanaliseRestritaCia(true);
        // Referência à CIA vigente para filtro posterior
        lic.setIdCiaVigente(ciaService.buscarCiaVigente(lic.getId()).getId());
    }
    
    marcoService.registrar(lic, TipoMarco.ENCAMINHADO_REANALISE,
        "Reanálise restrita aos itens da CIA N.º " + lic.getNrCiaVigente());
}
```

**Filtro na distribuição (P04):**
```
Se nr_analise > 1:
  → Carregar apenas itens reprovados da CIA vigente
  → Exibir na interface do analista somente esses itens
Se nr_analise == 1:
  → Fluxo normal: todos os itens
```

**Critérios de Aceitação:**
- [ ] CA-P03-N7a: 2ª análise em diante: o analista visualiza apenas os itens reprovados na CIA anterior
- [ ] CA-P03-N7b: Marco registra "Reanálise restrita aos itens da CIA N.º X"
- [ ] CA-P03-N7c: 1ª análise não é afetada — exibe todos os itens normalmente
- [ ] CA-P03-N7d: Tentativa de avaliar item não listado na CIA via API retorna 422

---

### Resumo das Mudanças P03 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P03-M1 | RN-P03-N1 | Alerta de imutabilidade do Passo 2 + bloqueio de edição (OBRIGATÓRIO) | 🔴 Crítica |
| P03-M7 | RN-P03-N7 | Reanálise restrita aos itens da CIA anterior (OBRIGATÓRIO) | 🔴 Crítica |
| P03-M2 | RN-P03-N2 | Edição do Passo 1 por usuários externos em estados editáveis | 🟠 Alta |
| P03-M3 | RN-P03-N3 | Campo "Número de assentos" obrigatório para Grupo F | 🟡 Média |
| P03-M4 | RN-P03-N4 | Classes de risco e novos tipos de risco na Etapa 5 | 🟡 Média |
| P03-M6 | RN-P03-N6 | QR Code de autenticação no APPCI emitido | 🟡 Média |
| P03-M5 | RN-P03-N5 | Upload de pranchas de fachadas na Etapa 6 | 🟢 Baixa |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 01–04 + Normas RTCBMRS*

*Documento produzido com base na análise do código-fonte do sistema SOL (backend Java EE e frontend Angular, versão de 16/06) e do PDF de apresentação do sistema (225 páginas). Para dúvidas ou complementações, consultar os arquivos de referência do projeto.*
