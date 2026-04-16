# Requisitos P09 — Troca de Envolvidos
## Stack Atual Java EE (JAX-RS · CDI · JPA/Hibernate · EJB · SOE PROCERGS · Alfresco)

> Documento de requisitos baseado **exclusivamente** no código-fonte real do projeto
> `SOLCBM.BackEnd16-06`. Todos os nomes de classes, métodos, campos, tabelas e enumerações
> correspondem ao código existente sem adaptação.

---

## S1 — Visão Geral do Processo

O processo P09 — **Troca de Envolvidos** — permite substituir qualquer combinação dos atores
vinculados a um licenciamento ativo: o **Responsável Técnico (RT)**, o **Responsável pelo Uso (RU)**
e/ou os **Proprietários** (pessoa física ou jurídica).

O processo possui **três etapas principais**:

| Etapa | Ator | Descrição |
|---|---|---|
| **Solicitação** | Solicitante (RT, RU ou Proprietário) | Preenche quais envolvidos serão substituídos e por quem, anexa documentos (ART/RRT, procurações) |
| **Autorização** | Cada Proprietário vinculado ao licenciamento | Aprova ou rejeita a troca. A efetivação exige aprovação de **todos** os proprietários |
| **Efetivação** | Sistema SOL Backend | Ao obter todos os aceites, executa a substituição real dos envolvidos nas tabelas de licenciamento |

### Restrições de escopo

- Permitido apenas para licenciamentos do tipo **PPCI** e **PSPCIM** (validado em `TrocaEnvolvidoLicenciamentoRNVal`).
- Bloqueado se já houver uma troca com `situacao = SOLICITADO` para o mesmo licenciamento.
- Bloqueado se o licenciamento estiver em situação `EXTINGUIDO` ou `AGUARDANDO_ACEITES_EXTINCAO`.
- A troca de RT é a mais complexa: depende de uma **matriz de 31 combinações** de tipos de responsabilidade (`TipoResponsabilidadeTecnica`) que define a ação a executar.

### Sub-processos de efetivação

| Sub-processo | Classe | Responsabilidade |
|---|---|---|
| **Efetivação RT** | `ProcessaTrocaRtRN` | Aplica a matriz de combinações de `TipoResponsabilidadeTecnica`; distingue fase PROJETO vs EXECUÇÃO e situação ALVARA_VIGENTE/VENCIDO vs demais |
| **Efetivação RU** | `ProcessaTrocaRuRN` | Remove RUs não presentes na solicitação; atualiza procurador do RU existente |
| **Efetivação Proprietário** | `ProcessaTrocaProprietarioRN` | Sincroniza proprietários (PF e PJ): remove, atualiza dados e inclui novos |

---

## S2 — Entidades de Domínio (EDs)

### 2.1 TrocaEnvolvidoED

Entidade central da solicitação de troca. Uma instância representa uma solicitação completa
(podendo incluir troca de RT, RU e/ou Proprietários simultaneamente).

```java
// Tabela: CBM_TROCA_ENVOLVIDO
@Entity
@Table(name = "CBM_TROCA_ENVOLVIDO")
public class TrocaEnvolvidoED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "SEQ_CBM_TROCA_ENVOLVIDO")
    @SequenceGenerator(name = "SEQ_CBM_TROCA_ENVOLVIDO",
                       sequenceName = "SEQ_CBM_TROCA_ENVOLVIDO", allocationSize = 1)
    @Column(name = "NRO_INT_TROCA_ENVOLVIDO")
    private Long id;

    /** Licenciamento ao qual esta troca se aplica */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO", nullable = false)
    private LicenciamentoED licenciamento;

    /** Usuário SOE que solicitou a troca (RU, RT ou Proprietário) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED usuario;

    /** Indica se há substituição de RT na solicitação */
    @Column(name = "IND_TROCA_RT")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indTrocaRt;

    /** Indica se há substituição de RU na solicitação */
    @Column(name = "IND_TROCA_RU")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indTrocaRu;

    /** Indica se há substituição de Proprietário na solicitação */
    @Column(name = "IND_TROCA_PROPRIETARIO")
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indTrocaProprietario;

    /** Data/hora da criação da solicitação */
    @Column(name = "DTH_CRIACAO", nullable = false)
    private Calendar dthCriacao;

    /** Data/hora do último envio de notificação (reforço) */
    @Column(name = "DTH_COMUNICACAO")
    private Calendar dthComunicacao;

    /** Situação atual da solicitação */
    @Enumerated(EnumType.STRING)
    @Column(name = "SIT_TROCA_ENVOLVIDO", nullable = false)
    private SituacaoTrocaEnvolvido situacao;

    /** Data/hora da última mudança de situação */
    @Column(name = "DTH_SITUACAO")
    private Calendar dthSituacao;
}
```

**Tabela CBM_TROCA_ENVOLVIDO:**

| Coluna | Tipo Oracle | Restrição | Descrição |
|---|---|---|---|
| `NRO_INT_TROCA_ENVOLVIDO` | NUMBER | PK NOT NULL | Chave primária (sequência) |
| `NRO_INT_LICENCIAMENTO` | NUMBER | FK NOT NULL | Licenciamento vinculado |
| `NRO_INT_USUARIO` | NUMBER | FK | Usuário SOE solicitante |
| `IND_TROCA_RT` | CHAR(1) | `'S'/'N'` | Há substituição de RT? |
| `IND_TROCA_RU` | CHAR(1) | `'S'/'N'` | Há substituição de RU? |
| `IND_TROCA_PROPRIETARIO` | CHAR(1) | `'S'/'N'` | Há substituição de Proprietário? |
| `DTH_CRIACAO` | DATE | NOT NULL | Data da criação |
| `DTH_COMUNICACAO` | DATE | | Data do último reforço de notificação |
| `SIT_TROCA_ENVOLVIDO` | VARCHAR2(30) | NOT NULL | Enum `SituacaoTrocaEnvolvido` |
| `DTH_SITUACAO` | DATE | | Data da última mudança de situação |

---

### 2.2 TrocaRTED

Detalha cada RT proposto para entrada (substituição). Um `TrocaEnvolvidoED` pode ter
múltiplos `TrocaRTED` quando há mais de um tipo de responsabilidade técnica a substituir.

```java
// Tabela: CBM_TROCA_RT
@Entity
@Table(name = "CBM_TROCA_RT")
public class TrocaRTED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "SEQ_CBM_TROCA_RT")
    @Column(name = "NRO_INT_TROCA_RT")
    private Long id;

    /** Solicitação de troca pai */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_TROCA_ENVOLVIDO")
    private TrocaEnvolvidoED trocaEnvolvido;

    /** Usuário SOE do novo RT */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED usuario;

    /** Tipo de responsabilidade técnica assumida pelo novo RT */
    @Enumerated(EnumType.STRING)
    @Column(name = "TP_RESPONSABILIDADE")
    private TipoResponsabilidadeTecnica tipoResponsabilidade;

    /**
     * Arquivos ART/RRT do novo RT (armazenados no Alfresco).
     * Um TrocaRTED pode ter múltiplos arquivos (ex: ART de projeto + ART de execução).
     */
    @OneToMany(mappedBy = "trocaRt", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ArquivoED> arquivos = new ArrayList<>();
}
```

---

### 2.3 TrocaRUED

Detalha o RU proposto para entrada.

```java
// Tabela: CBM_TROCA_RU
@Entity
@Table(name = "CBM_TROCA_RU")
public class TrocaRUED {

    @Id
    @Column(name = "NRO_INT_TROCA_RU")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_TROCA_ENVOLVIDO")
    private TrocaEnvolvidoED trocaEnvolvido;

    /** Usuário SOE do novo RU */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED usuario;

    /** Procurador do novo RU (quando representado por terceiro) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO_PROCURADOR")
    private UsuarioED procurador;

    /**
     * Arquivo da procuração do procurador do RU (armazenado no Alfresco).
     * Obrigatório quando procurador != null.
     */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO_PROCURADOR")
    private ArquivoED procuradorArquivo;
}
```

---

### 2.4 TrocaProprietarioED

Detalha cada Proprietário proposto para entrada (PF ou PJ).

```java
// Tabela: CBM_TROCA_PROPRIETARIO
@Entity
@Table(name = "CBM_TROCA_PROPRIETARIO")
public class TrocaProprietarioED {

    @Id
    @Column(name = "NRO_INT_TROCA_PROPRIETARIO")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_TROCA_ENVOLVIDO")
    private TrocaEnvolvidoED trocaEnvolvido;

    /** 'F' = pessoa física; 'J' = pessoa jurídica */
    @Column(name = "TP_PESSOA", length = 1)
    private String tpPessoa;

    /** Usuário SOE do novo proprietário (PF) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED usuario;

    /** CNPJ quando PJ (sem máscara) */
    @Column(name = "TXT_CNPJ", length = 14)
    private String txtCnpj;

    /** Razão social da empresa (PJ) */
    @Column(name = "TXT_RAZAO_SOCIAL", length = 200)
    private String razaoSocial;

    /** Nome fantasia (PJ, opcional) */
    @Column(name = "TXT_NOME_FANTASIA", length = 200)
    private String nomeFantasia;

    /** E-mail para notificações (PJ) */
    @Column(name = "TXT_EMAIL", length = 200)
    private String txtEmail;

    /** Telefone (PJ, opcional) */
    @Column(name = "TXT_TELEFONE", length = 20)
    private String txtTelefone;

    /** Procurador do proprietário */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO_PROCURADOR")
    private UsuarioED procurador;

    /** Arquivo da procuração do proprietário (Alfresco) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO_PROCURADOR")
    private ArquivoED arquivoProcurador;
}
```

---

### 2.5 TrocaAutorizacaoED

Registra a autorização (ou rejeição) de **cada proprietário** individualmente.
A efetivação da troca só ocorre quando **todos** os registros têm `indAutorizado = 'S'`.

```java
// Tabela: CBM_TROCA_AUTORIZACAO
@Entity
@Table(name = "CBM_TROCA_AUTORIZACAO")
public class TrocaAutorizacaoED {

    @Id
    @Column(name = "NRO_INT_TROCA_AUTORIZACAO")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_TROCA_ENVOLVIDO")
    private TrocaEnvolvidoED trocaEnvolvido;

    /** 'F' = pessoa física; 'J' = pessoa jurídica */
    @Column(name = "TP_PESSOA", length = 1)
    private String tpPessoa;

    /** Proprietário a quem a autorização pertence */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED usuario;

    /** Procurador do proprietário (quando representado) */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO_PROCURADOR")
    private UsuarioED procurador;

    /** Razão social (quando PJ) */
    @Column(name = "TXT_RAZAO_SOCIAL", length = 200)
    private String razaoSocial;

    /**
     * null = ainda não respondeu; 'S' = autorizou; 'N' = rejeitou
     * SimNaoBooleanConverter: true↔'S', false↔'N', null↔null
     */
    @Column(name = "IND_AUTORIZADO", length = 1)
    @Convert(converter = SimNaoBooleanConverter.class)
    private Boolean indAutorizado;

    /** Data/hora da resposta */
    @Column(name = "DTH_AUTORIZACAO")
    private Calendar dthAutorizacao;
}
```

---

## S3 — Enumerações

### 3.1 SituacaoTrocaEnvolvido

```java
// Arquivo: SituacaoTrocaEnvolvido.java
public enum SituacaoTrocaEnvolvido {

    /** Solicitação criada — aguardando autorizações dos proprietários */
    SOLICITADO,

    /** Todos os proprietários autorizaram — troca efetivada */
    APROVADO,

    /** Pelo menos um proprietário rejeitou */
    REPROVADO,

    /** Solicitante cancelou antes da efetivação */
    CANCELADO
}
```

### 3.2 AcaoTrocaRT

Define as ações possíveis na matriz de combinações de tipos de responsabilidade técnica.

```java
// Arquivo: AcaoTrocaRT.java
public enum AcaoTrocaRT {
    /** Combinação ignorada — nenhuma ação executada */
    IGNORA,
    /** Inclui novo vínculo RT sem remover o existente */
    INCLUI,
    /** Remove o vínculo RT existente */
    REMOVE_RT,
    /** Atualiza apenas o TipoResponsabilidadeTecnica do RT existente */
    ATUALIZA_SOMENTE_TIPO,
    /** Atualiza o tipo E substitui os arquivos ART/RRT pelos da solicitação */
    ATUALIZA_TIPO_SUBSTITUI_ARQUIVOS,
    /** Atualiza o tipo E adiciona os arquivos ART/RRT da solicitação (mantém existentes) */
    ATUALIZA_TIPO_ADICIONA_ARQUIVOS
}
```

### 3.3 TipoMarco — Marcos específicos do P09

```java
// Arquivo: TipoMarco.java (valores relevantes ao P09)
public enum TipoMarco {
    // ...
    /** Marco criado ao solicitar a troca */
    SOLICITA_TROCA_ENVOLVIDO,       // linha ~44
    /** Marco criado quando um proprietário aprova */
    APROVA_TROCA_ENVOLVIDO,
    /** Marco criado quando um proprietário rejeita */
    REPROVA_TROCA_ENVOLVIDO,
    /** Marco criado quando a troca é efetivada (todos aprovaram) */
    REALIZA_TROCA_ENVOLVIDO,
    // ...
}
```

### 3.4 SituacaoLicenciamento — Situações válidas para autorização de troca

Segundo `AutorizacaoTrocaEnvolvidoRNVal`, a autorização só é aceita quando o
licenciamento está em uma das 13 situações da **lista branca**:

```java
// Situações que PERMITEM autorizar a troca (lista branca em AutorizacaoTrocaEnvolvidoRNVal):
EnumSet.of(
    SituacaoLicenciamento.RASCUNHO,
    SituacaoLicenciamento.AGUARDANDO_ACEITE,
    SituacaoLicenciamento.AGUARDANDO_PAGAMENTO,
    SituacaoLicenciamento.ANALISE_INVIABILIDADE_PENDENTE,
    SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO,
    SituacaoLicenciamento.EM_ANALISE,
    SituacaoLicenciamento.AGUARDANDO_PRPCI,
    SituacaoLicenciamento.AGUARDANDO_ACEITE_PRPCI,
    SituacaoLicenciamento.ALVARA_VIGENTE,
    SituacaoLicenciamento.ALVARA_VENCIDO,
    SituacaoLicenciamento.CA,
    SituacaoLicenciamento.AGUARDANDO_DISTRIBUICAO_RENOV,
    SituacaoLicenciamento.CIV
)

// Situações que BLOQUEIAM a solicitação de troca (em SolicitaTrocaEnvolvidoLicenciamentoRN):
EnumSet.of(
    SituacaoLicenciamento.EXTINGUIDO,
    SituacaoLicenciamento.AGUARDANDO_ACEITES_EXTINCAO
)
```

---

## S4 — Regras de Negócio

### RN01 — Tipo de licenciamento deve ser PPCI ou PSPCIM

**Classe:** `TrocaEnvolvidoLicenciamentoRNVal`

```java
// Método: validaTipoLicenciamento()
// Rejeita qualquer tipo diferente de PPCI e PSPCIM.
// Mensagem de erro: "trocaEnvolvido.tipo.licenciamento.invalido"
public void validaTipoLicenciamento(LicenciamentoED licenciamento) {
    TipoLicenciamento tipo = licenciamento.getTipoLicenciamento();
    if (!TipoLicenciamento.PPCI.equals(tipo) && !TipoLicenciamento.PSPCIM.equals(tipo)) {
        throw new SolNegocioException(
            messageProvider.get("trocaEnvolvido.tipo.licenciamento.invalido"));
    }
}
```

### RN02 — Não pode existir outra troca SOLICITADA para o mesmo licenciamento

**Classe:** `SolicitaTrocaEnvolvidoLicenciamentoRN`

```java
// Método: validaTrocaEnvolvidoSolicitadaParaMesmoLicenciamento(Long idLicenciamento)
// Consulta em CBM_TROCA_ENVOLVIDO por SIT_TROCA_ENVOLVIDO = 'SOLICITADO'
// e NRO_INT_LICENCIAMENTO = :idLicenciamento
// Se encontrar, lança SolNegocioException.
// Mensagem: "trocaEnvolvido.solicitacao.existente"
```

### RN03 — Licenciamento não pode estar extinguido ou em processo de extinção

**Classe:** `SolicitaTrocaEnvolvidoLicenciamentoRN`

```java
// Método: validaSituacaoLicenciamento()
// Rejeita quando situacao = EXTINGUIDO ou AGUARDANDO_ACEITES_EXTINCAO.
// Mensagem: "trocaEnvolvido.situacao.licenciamento.invalida"
```

### RN04 — Pelo menos um tipo de envolvido deve ser informado na solicitação

**Classe:** `SolicitaTrocaEnvolvidoLicenciamentoRNVal`

```java
// Método: validaEnvolvidosInformados(TrocaEnvolvidoDTO dto)
// Rejeita se dto.getRts().isEmpty() AND dto.getRus().isEmpty()
//           AND dto.getProprietarios().isEmpty()
// Mensagem: "trocaEnvolvido.envolvidos.obrigatorio"
```

### RN05 — O usuário solicitante deve estar entre os novos envolvidos informados

**Classe:** `SolicitaTrocaEnvolvidoLicenciamentoRNVal`

```java
// Método: validaUsuarioLogadoEntreEnvolvidos(String cpfUsuario, TrocaEnvolvidoDTO dto)
// Consolida CPFs de todos os RTs, RUs, Proprietários e Procuradores da solicitação.
// Verifica se o CPF do usuário logado (token SOE) está presente nessa lista.
// Garante que o solicitante tem interesse legítimo na troca.
// Mensagem: "trocaEnvolvido.usuario.nao.encontrado"
```

### RN06 — Cada proprietário vinculado ao licenciamento deve receber registro de autorização

**Classe:** `SolicitaTrocaEnvolvidoLicenciamentoRN`

```java
// Método: incluiAutorizacoes()
// Para cada LicenciamentoProprietarioED vinculado ao licenciamento,
// cria um TrocaAutorizacaoED com indAutorizado = null (pendente).
// Se o proprietário tem procurador, o procurador é o responsável pela autorização.
// INSERT INTO CBM_TROCA_AUTORIZACAO (NRO_INT_TROCA_ENVOLVIDO, TP_PESSOA,
//   NRO_INT_USUARIO, NRO_INT_USUARIO_PROCURADOR, TXT_RAZAO_SOCIAL, IND_AUTORIZADO)
```

### RN07 — A autorização exige situação SOLICITADO e usuário com autorização pendente

**Classe:** `AutorizacaoTrocaEnvolvidoRNVal`

```java
// Método: validaAutorizacao(TrocaEnvolvidoED, UsuarioED, List<TrocaAutorizacaoED>)
// 1. validaSituacaoTrocaEnvolvido()
//    → TrocaEnvolvidoED.situacao deve ser SOLICITADO
//    → Mensagem: "trocaEnvolvido.situacao.invalida"
// 2. validaSituacaoLicenciamento()
//    → Licenciamento.situacao deve estar na lista branca de 13 situações
//    → Mensagem: "trocaEnvolvido.licenciamento.situacao.invalida"
// 3. validaAutorizacaoPendenteUsuario()
//    → Entre as TrocaAutorizacaoEDs do usuário logado, ao menos uma deve ter
//      indAutorizado = null (ainda não respondeu)
//    → Validação executada por AutorizacaoTrocaEnvolvidoHelper.isUsuarioVinculadoAAutorizacaoPendente()
//    → Mensagem: "trocaEnvolvido.autorizacao.invalida"
```

### RN08 — Efetivação só ocorre quando TODOS os proprietários autorizam

**Classe:** `AutorizacaoTrocaEnvolvidoRN`

```java
// Método: autoriza(Long idTrocaEnvolvido)
// Após gravar indAutorizado='S' e dthAutorizacao=now() para o usuário logado:
//   Busca todos os TrocaAutorizacaoED da troca.
//   Se TODOS possuem indAutorizado = true → chama processaAutorizacaoTodosProprietarios()
//   Caso contrário → aguarda demais proprietários.
// @Permissao(objeto = "LICENCIAMENTO", acao = "AUTORIZAR_MUDANCA_ENVOLVIDOS")
```

### RN09 — Rejeição de um único proprietário cancela a troca inteira

**Classe:** `AutorizacaoTrocaEnvolvidoRN`

```java
// Método: rejeita(Long idTrocaEnvolvido)
// 1. Grava indAutorizado='N' no TrocaAutorizacaoED do proprietário
// 2. Altera TrocaEnvolvidoED.situacao → REPROVADO
// 3. Registra marco REPROVA_TROCA_ENVOLVIDO
// 4. Notifica o solicitante e demais proprietários via NotificacaoRN
// @Permissao(objeto = "LICENCIAMENTO", acao = "AUTORIZAR_MUDANCA_ENVOLVIDOS")
```

### RN10 — Cancelamento só permitido quando situação for SOLICITADO

**Classe:** `CancelaTrocaEnvolvidoRNVal`

```java
// Método: validaSituacao(TrocaEnvolvidoED troca)
// Rejeita se troca.situacao != SOLICITADO.
// Mensagem: "trocaEnvolvido.cancelamento.situacao.invalida"
```

### RN11 — Cancelamento só pode ser feito pelo próprio solicitante

**Classe:** `TrocaEnvolvidoRNVal`

```java
// Método: validaUsuarioLogadoSolicitante(TrocaEnvolvidoED troca, UsuarioED usuario)
// Verifica se troca.usuario.id == usuario.id (usuário logado é o solicitante).
// Mensagem: "trocaEnvolvido.usuario.nao.solicitante"
```

### RN12 — Reforço de notificação só permitido quando situação for SOLICITADO

**Classe:** `NotificaTrocaEnvolvidoRNVal`

```java
// Método: validaSituacaoSolicitada(TrocaEnvolvidoED troca)
// Rejeita se troca.situacao != SOLICITADO.
// Registra dthComunicacao = now() para rastrear o último envio.
```

### RN13 — Matriz de 31 combinações para efetivação de troca de RT

**Classe:** `ProcessaTrocaRtRN`

A lógica central da efetivação de RT usa uma tabela de combinações entre
`TipoResponsabilidadeTecnica` do novo RT (da solicitação) e o tipo do RT atualmente
vinculado ao licenciamento, definindo a `AcaoTrocaRT` a executar:

```java
// Método: processa(TrocaEnvolvidoED trocaEnvolvido)
// 1. Determina a fase do licenciamento (PROJETO vs EXECUÇÃO)
// 2. Para cada TrocaRTED da solicitação:
//    a. Identifica o TipoResponsabilidadeTecnica do novo RT (tipoRtTroca)
//    b. Localiza o RT atual com o mesmo tipo vinculado ao licenciamento
//    c. Aplica a CombinacaoTrocaRt correspondente (matriz de 31 linhas fase PROJETO)
//    d. Executa a AcaoTrocaRT:
//       - IGNORA: nada é feito
//       - INCLUI: ResponsavelTecnicoRN.inclui(novo RT + tipo + arquivos)
//       - REMOVE_RT: ResponsavelTecnicoRN.remove(RT atual)
//       - ATUALIZA_SOMENTE_TIPO: apenas muda o TipoResponsabilidadeTecnica no BD
//       - ATUALIZA_TIPO_SUBSTITUI_ARQUIVOS: muda tipo + remove ARTs antigas + inclui novas
//       - ATUALIZA_TIPO_ADICIONA_ARQUIVOS: muda tipo + mantém ARTs antigas + inclui novas
// 3. Para ALVARA_VIGENTE/ALVARA_VENCIDO: apenas adiciona RENOVACAO_APPCI se não existe

// Classe CombinacaoTrocaRt:
public class CombinacaoTrocaRt {
    private TipoResponsabilidadeTecnica tipoRtTroca;        // RT da solicitação
    private TipoResponsabilidadeTecnica tipoRtLicenciamento; // RT atual
    private TipoResponsabilidadeTecnica novoTipoRtLicenciamento; // RT resultante
    private AcaoTrocaRT acao;
}
```

### RN14 — Efetivação de troca de RU sincroniza procurador

**Classe:** `ProcessaTrocaRuRN`

```java
// Método: processa(TrocaEnvolvidoED trocaEnvolvido)
// 1. Lista todos os RUs atualmente vinculados ao licenciamento
// 2. Remove RUs que não estão na solicitação
// 3. Para RUs que estão na solicitação:
//    a. Verifica se já existe (mesmo CPF)
//    b. Se existe: atualizaRu() — remove procurador anterior, inclui novo se fornecido
//    c. Se não existe: ResponsavelUsoRN.inclui(novo RU + licenciamento)
// 4. geraProcurador(): cria ProcuradorED com arquivo copiado do TrocaRUED via ArquivoRN
```

### RN15 — Efetivação de troca de Proprietário suporta PF e PJ com procurador

**Classe:** `ProcessaTrocaProprietarioRN`

```java
// Método: processa(TrocaEnvolvidoED trocaEnvolvido)
// 1. Lista todos os proprietários atuais do licenciamento
// 2. Remove proprietários não presentes na solicitação
// 3. Para cada TrocaProprietarioED:
//    a. tpPessoa='F': usa ProprietarioPFRN para localizar/criar
//    b. tpPessoa='J': usa ProprietarioPJRN para localizar/criar; atualiza dados PJ
//    c. Gerencia procurador: remove antigo, inclui novo com arquivo de procuração (Alfresco)
//    d. LicenciamentoProprietarioRN.inclui() para vincular ao licenciamento
```

---

## S5 — Classes Regras de Negócio (RNs)

### 5.1 SolicitaTrocaEnvolvidoLicenciamentoRN — Criação da solicitação

```java
// Pacote: com.procergs.solcbm.trocaenvolvido
// Arquivo: SolicitaTrocaEnvolvidoLicenciamentoRN.java (359 linhas)
@Stateless
public class SolicitaTrocaEnvolvidoLicenciamentoRN {

    // Injeções CDI
    @Inject private DataAtualHelper dataAtualHelper;
    @Inject private CidadaoSessionMB cidadaoSessionMB;  // Sessão SOE PROCERGS
    @Inject private UsuarioRN usuarioRN;
    @Inject private TrocaRTRN trocaRTRN;
    @Inject private TrocaRURN trocaRURN;
    @Inject private TrocaProprietarioRN trocaProprietarioRN;
    @Inject private ArquivoRN arquivoRN;                // Integração Alfresco
    @Inject private NotificaTrocaEnvolvidoRN notificaTrocaEnvolvidoRN;
    @Inject private LicenciamentoRN licenciamentoRN;
    @Inject private TrocaEnvolvidoRN trocaEnvolvidoRN;
    @Inject private TrocaEnvolvidoLicenciamentoRNVal trocaLicRNVal;
    @Inject private SolicitaTrocaEnvolvidoLicenciamentoRNVal solicitaRNVal;
    @Inject private LicenciamentoMarcoInclusaoRN marcoRN;

    /**
     * Ponto de entrada da solicitação de troca.
     * @param dto      Dados da solicitação (novos envolvidos + flags ind*)
     * @param arquivos Arquivos multipart (ART/RRT dos novos RTs, procurações)
     */
    public TrocaEnvolvidoDTO solicita(TrocaEnvolvidoDTO dto, List<ArquivoUpload> arquivos) {
        LicenciamentoED licenciamento = licenciamentoRN.busca(dto.getIdLicenciamento());

        // Validações
        trocaLicRNVal.validaTipoLicenciamento(licenciamento);        // RN01
        validaTrocaEnvolvidoSolicitadaParaMesmoLicenciamento(         // RN02
            dto.getIdLicenciamento());
        validaSituacaoLicenciamento(licenciamento);                   // RN03
        solicitaRNVal.validaEnvolvidosInformados(dto);               // RN04
        solicitaRNVal.validaUsuarioLogadoEntreEnvolvidos(            // RN05
            cidadaoSessionMB.getUsuario().getCpf(), dto);

        // Criação da TrocaEnvolvidoED
        TrocaEnvolvidoED troca = BuilderTrocaEnvolvidoED.create()
            .licenciamento(licenciamento)
            .usuario(cidadaoSessionMB.getUsuario())
            .indTrocaRt(TrocaEnvolvidoHelper.possuiTrocaRT(dto))
            .indTrocaRu(TrocaEnvolvidoHelper.possuiTrocaRU(dto))
            .indTrocaProprietario(TrocaEnvolvidoHelper.possuiTrocaProprietario(dto))
            .situacao(SituacaoTrocaEnvolvido.SOLICITADO)
            .dthCriacao(dataAtualHelper.agora())
            .dthSituacao(dataAtualHelper.agora())
            .build();
        // INSERT INTO CBM_TROCA_ENVOLVIDO ...
        trocaEnvolvidoRN.inclui(troca);

        // Inclui envolvidos da solicitação
        incluiRts(troca, dto.getRts(), arquivos);        // Cria TrocaRTEDs + ArquivoEDs
        incluiRus(troca, dto.getRus(), arquivos);        // Cria TrocaRUEDs
        incluiProprietarios(troca, dto.getProprietarios(), arquivos); // Cria TrocaProprietarioEDs

        // Cria registros de autorização para cada proprietário atual
        incluiAutorizacoes(troca, licenciamento);        // RN06

        // Marco de auditoria
        marcoRN.inclui(licenciamento, TipoMarco.SOLICITA_TROCA_ENVOLVIDO);

        // Notificação aos proprietários
        notificaTrocaEnvolvidoRN.notificaEnvolvidos(licenciamento);

        return BuilderTrocaEnvolvidoDTO.from(troca).build();
    }
}
```

---

### 5.2 AutorizacaoTrocaEnvolvidoRN — Autorização e rejeição pelos proprietários

```java
// Pacote: com.procergs.solcbm.trocaenvolvido
// Arquivo: AutorizacaoTrocaEnvolvidoRN.java (307 linhas)
@Stateless
@Interceptors(SegurancaEnvolvidoInterceptor.class)
public class AutorizacaoTrocaEnvolvidoRN {

    @Inject private TrocaEnvolvidoRN trocaEnvolvidoRN;
    @Inject private AutorizacaoTrocaEnvolvidoRNVal autorizacaoRNVal;
    @Inject private TrocaAutorizacaoRN trocaAutorizacaoRN;
    @Inject private UsuarioRN usuarioRN;
    @Inject private ResponsavelTecnicoRN responsavelTecnicoRN;
    @Inject private ResponsavelUsoRN responsavelUsoRN;
    @Inject private LicenciamentoProprietarioRN licProprietarioRN;
    @Inject private LicenciamentoMarcoInclusaoRN marcoRN;
    @Inject private NotificacaoRN notificacaoRN;
    @Inject private ProcessaTrocaRtRN processaTrocaRtRN;
    @Inject private ProcessaTrocaRuRN processaTrocaRuRN;
    @Inject private ProcessaTrocaProprietarioRN processaTrocaProprietarioRN;
    @Inject private TrocaEnvolvidoBD trocaEnvolvidoBD;
    @Inject private DataAtualHelper dataAtualHelper;

    /**
     * Proprietário autoriza a troca.
     * Se for o último a autorizar, efetiva a troca imediatamente.
     */
    @Permissao(objeto = "LICENCIAMENTO", acao = "AUTORIZAR_MUDANCA_ENVOLVIDOS")
    public TrocaEnvolvidoDTO autoriza(Long idTrocaEnvolvido) {
        UsuarioED usuarioLogado = cidadaoSessionMB.getUsuario();
        TrocaEnvolvidoED troca = trocaEnvolvidoRN.busca(idTrocaEnvolvido);
        List<TrocaAutorizacaoED> autorizacoes = trocaAutorizacaoRN.lista(idTrocaEnvolvido);

        // Validações RN07
        autorizacaoRNVal.validaAutorizacao(troca, usuarioLogado, autorizacoes);

        // Grava o aceite deste proprietário
        TrocaAutorizacaoED autorizacao = autorizacoes.stream()
            .filter(a -> AutorizacaoTrocaEnvolvidoHelper
                .isUsuarioVinculadoAAutorizacaoPendente(usuarioLogado, a))
            .findFirst()
            .orElseThrow(...);
        autorizacao.setIndAutorizado(true);
        autorizacao.setDthAutorizacao(dataAtualHelper.agora());
        // UPDATE CBM_TROCA_AUTORIZACAO SET IND_AUTORIZADO='S', DTH_AUTORIZACAO=SYSDATE

        // Marco de auditoria
        marcoRN.inclui(troca.getLicenciamento(), TipoMarco.APROVA_TROCA_ENVOLVIDO);

        // Verifica se todos autorizaram — RN08
        boolean todosAutorizaram = autorizacoes.stream()
            .allMatch(a -> Boolean.TRUE.equals(a.getIndAutorizado()));

        if (todosAutorizaram) {
            processaAutorizacaoTodosProprietarios(troca);
        }
        return BuilderTrocaEnvolvidoDTO.from(troca).build();
    }

    /**
     * Proprietário rejeita a troca. Situação vai para REPROVADO. (RN09)
     */
    @Permissao(objeto = "LICENCIAMENTO", acao = "AUTORIZAR_MUDANCA_ENVOLVIDOS")
    public TrocaEnvolvidoDTO rejeita(Long idTrocaEnvolvido) {
        TrocaEnvolvidoED troca = trocaEnvolvidoRN.busca(idTrocaEnvolvido);
        List<TrocaAutorizacaoED> autorizacoes = trocaAutorizacaoRN.lista(idTrocaEnvolvido);
        autorizacaoRNVal.validaAutorizacao(troca, cidadaoSessionMB.getUsuario(), autorizacoes);

        // Grava a rejeição
        // UPDATE CBM_TROCA_AUTORIZACAO SET IND_AUTORIZADO='N', DTH_AUTORIZACAO=SYSDATE
        troca.setSituacao(SituacaoTrocaEnvolvido.REPROVADO);
        troca.setDthSituacao(dataAtualHelper.agora());
        // UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='REPROVADO', DTH_SITUACAO=SYSDATE

        marcoRN.inclui(troca.getLicenciamento(), TipoMarco.REPROVA_TROCA_ENVOLVIDO);
        // Notifica solicitante e todos os proprietários
        notificacaoRN.notifica(...);

        return BuilderTrocaEnvolvidoDTO.from(troca).build();
    }

    /**
     * Efetivação após unanimidade — todos os proprietários autorizaram.
     */
    private void processaAutorizacaoTodosProprietarios(TrocaEnvolvidoED troca) {
        // Executa substituição dos envolvidos
        if (Boolean.TRUE.equals(troca.getIndTrocaRt())) {
            processaTrocaRtRN.processa(troca);           // RN13
        }
        if (Boolean.TRUE.equals(troca.getIndTrocaRu())) {
            processaTrocaRuRN.processa(troca);           // RN14
        }
        if (Boolean.TRUE.equals(troca.getIndTrocaProprietario())) {
            processaTrocaProprietarioRN.processa(troca); // RN15
        }

        troca.setSituacao(SituacaoTrocaEnvolvido.APROVADO);
        troca.setDthSituacao(dataAtualHelper.agora());
        // UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='APROVADO', DTH_SITUACAO=SYSDATE

        marcoRN.inclui(troca.getLicenciamento(), TipoMarco.REALIZA_TROCA_ENVOLVIDO);
        notificacaoRN.notifica(...); // Notifica todos os envolvidos (RT saindo, novo RT, RU, prop)
    }
}
```

---

### 5.3 CancelaTrocaEnvolvidoRN — Cancelamento pelo solicitante

```java
// Pacote: com.procergs.solcbm.trocaenvolvido
// Arquivo: CancelaTrocaEnvolvidoRN.java (61 linhas)
@Stateless
public class CancelaTrocaEnvolvidoRN {

    @Inject private TrocaEnvolvidoRN trocaEnvolvidoRN;
    @Inject private CancelaTrocaEnvolvidoRNVal cancelaRNVal;
    @Inject private TrocaEnvolvidoRNVal trocaRNVal;
    @Inject private UsuarioRN usuarioRN;
    @Inject private LicenciamentoCidadaoNotificacaoRN notificacaoRN;
    @Inject private DataAtualHelper dataAtualHelper;

    /**
     * Cancela a solicitação. Só o solicitante pode cancelar (RN10, RN11).
     */
    public void cancela(Long idTrocaEnvolvido) {
        UsuarioED usuarioLogado = cidadaoSessionMB.getUsuario();
        TrocaEnvolvidoED troca = trocaEnvolvidoRN.busca(idTrocaEnvolvido);

        cancelaRNVal.validaSituacao(troca);                          // RN10
        trocaRNVal.validaUsuarioLogadoSolicitante(troca, usuarioLogado); // RN11

        troca.setSituacao(SituacaoTrocaEnvolvido.CANCELADO);
        troca.setDthSituacao(dataAtualHelper.agora());
        // UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='CANCELADO', DTH_SITUACAO=SYSDATE

        // Notifica proprietários sobre o cancelamento
        notificacaoRN.notifica(troca.getLicenciamento(), ...);
    }
}
```

---

### 5.4 NotificaTrocaEnvolvidoRN — Notificações por e-mail

```java
// Arquivo: NotificaTrocaEnvolvidoRN.java (67 linhas)
@Stateless
public class NotificaTrocaEnvolvidoRN {

    @Inject private NotificacaoRN notificacaoRN;
    @Inject private TrocaEnvolvidoRN trocaEnvolvidoRN;
    @Inject private NotificaTrocaEnvolvidoRNVal notificaRNVal;
    @Inject private DataAtualHelper dataAtualHelper;

    /** Notifica os proprietários do licenciamento sobre nova solicitação de troca */
    public void notificaEnvolvidos(LicenciamentoED licenciamento) {
        // Template: "notificacao.email.template.troca.envolvido.solicitada"
        // Assunto:  "notificacao.assunto.troca.envolvido.solicitada"
        // Destinatários: todos os proprietários do licenciamento
        notificacaoRN.notifica(licenciamento,
            "notificacao.email.template.troca.envolvido.solicitada",
            ContextoNotificacaoEnum.LICENCIAMENTO, ...);
    }

    /**
     * Reforça a notificação (reenvio manual pelo solicitante).
     * Atualiza TrocaEnvolvidoED.dthComunicacao = now().
     */
    public void reforcarSolicitacao(Long idTrocaEnvolvido) {
        TrocaEnvolvidoED troca = trocaEnvolvidoRN.busca(idTrocaEnvolvido);
        notificaRNVal.validaSituacaoSolicitada(troca);   // RN12
        troca.setDthComunicacao(dataAtualHelper.agora());
        // UPDATE CBM_TROCA_ENVOLVIDO SET DTH_COMUNICACAO=SYSDATE
        notificaEnvolvidos(troca.getLicenciamento());
    }
}
```

---

### 5.5 TrocaEnvolvidoBD — Acesso a dados (Hibernate Criteria)

```java
// Arquivo: TrocaEnvolvidoBD.java (146 linhas)
@Stateless
public class TrocaEnvolvidoBD {

    @PersistenceContext
    private EntityManager em;

    /**
     * Lista solicitações de troca com situação SOLICITADO para um conjunto de licenciamentos.
     * Usado para verificar bloqueio em extinção ou edição de licenciamento.
     */
    public List<TrocaEnvolvidoED> listaSolicitadaPorLicenciamentos(List<Long> idLicenciamentos) {
        // SELECT t FROM TrocaEnvolvidoED t
        // WHERE t.licenciamento.id IN (:ids)
        //   AND t.situacao = 'SOLICITADO'
        CriteriaBuilder cb = em.getCriteriaBuilder();
        CriteriaQuery<TrocaEnvolvidoED> cq = cb.createQuery(TrocaEnvolvidoED.class);
        Root<TrocaEnvolvidoED> root = cq.from(TrocaEnvolvidoED.class);
        cq.where(
            root.get("licenciamento").get("id").in(idLicenciamentos),
            cb.equal(root.get("situacao"), SituacaoTrocaEnvolvido.SOLICITADO)
        );
        return em.createQuery(cq).getResultList();
    }

    /**
     * Retorna a última solicitação (qualquer situação) de um licenciamento.
     * Ordenada por id DESC → retorna a mais recente.
     */
    public TrocaEnvolvidoED listaUltimoSolicitadaPorLicenciamento(Long idLicenciamento) {
        // SELECT t FROM TrocaEnvolvidoED t
        // WHERE t.licenciamento.id = :id
        // ORDER BY t.id DESC FETCH FIRST 1 ROW ONLY
        ...
    }

    /**
     * Lista paginada de solicitações do usuário logado.
     */
    public List<TrocaEnvolvidoED> listaPorUsuarioLogado(TrocaEnvolvidoPesqED pesq, UsuarioED usuario) {
        // SELECT t FROM TrocaEnvolvidoED t WHERE t.usuario.id = :idUsuario
        // ORDER BY t.dthCriacao DESC
        // com paginação: setFirstResult / setMaxResults
        ...
    }
}
```

---

## S6 — Endpoints REST

### 6.1 TrocaEnvolvidoRest — Endpoints do Solicitante

```java
// Interface: TrocaEnvolvidoRest.java
// Implementação: TrocaEnvolvidoRestImpl.java
// @Path("/troca-envolvidos")
// Autenticação: token SOE PROCERGS (Implicit Flow OIDC) via @HeaderParam("Authorization")

@Path("/troca-envolvidos")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface TrocaEnvolvidoRest {

    /**
     * Cria nova solicitação de troca de envolvidos.
     * Content-Type: multipart/form-data
     * Partes do formulário:
     *   - "troca" (application/json): TrocaEnvolvidoDTO
     *   - "arquivo-rt-{idRt}" (application/octet-stream): ART/RRT do RT
     *   - "procurador-ru" (application/octet-stream): procuração do RU (se houver)
     *   - "procurador-proprietario-{idx}" (application/octet-stream): procuração do proprietário
     */
    @POST
    @Consumes(MediaType.MULTIPART_FORM_DATA)
    Response inclui(MultipartFormDataInput form);

    /**
     * Lista solicitações de troca do usuário logado (paginado).
     * @param pagina   Número da página (começa em 0)
     * @param tamanho  Registros por página
     */
    @GET
    Response lista(@QueryParam("pagina") int pagina,
                   @QueryParam("tamanho") int tamanho);

    /**
     * Consulta uma solicitação específica (somente pelo solicitante).
     */
    @GET
    @Path("/{idTrocaEnvolvido}")
    Response consulta(@PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido);

    /**
     * Cancela a solicitação (somente pelo solicitante, status = SOLICITADO).
     */
    @PUT
    @Path("/{idTrocaEnvolvido}/cancelar")
    Response cancela(@PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido);

    /**
     * Lista licenciamentos passíveis de troca (PPCI/PSPCIM).
     * Filtro obrigatório: nroLicenciamento OU (logradouro + uf + cidade + numero).
     */
    @GET
    @Path("/licenciamentos")
    Response listaLicenciamentos(@BeanParam LicenciamentoPesqED pesq);

    /**
     * Consulta um licenciamento antes de solicitar troca.
     * Valida se já existe troca ativa para o licenciamento.
     */
    @GET
    @Path("/licenciamentos/{idLicenciamento}")
    Response consultaLicenciamento(@PathParam("idLicenciamento") Long idLicenciamento);

    /**
     * Reforça o envio de notificação para os proprietários pendentes.
     * Atualiza TrocaEnvolvidoED.dthComunicacao.
     */
    @POST
    @Path("/{idTrocaEnvolvido}/reforcar-solicitacao")
    Response reforcarSolicitacao(@PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido);

    /** Download do arquivo ART/RRT de um RT da solicitação */
    @GET
    @Path("/{idTrocaEnvolvido}/rt/{idRT}/arquivo/{idArquivo}")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    Response downloadArquivoRt(@PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido,
                                @PathParam("idRT") Long idRT,
                                @PathParam("idArquivo") Long idArquivo);

    /** Download da procuração do RU da solicitação */
    @GET
    @Path("/{idTrocaEnvolvido}/ru/{idRU}/procurador/arquivo")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    Response downloadProcuracaoRu(@PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido,
                                   @PathParam("idRU") Long idRU);

    /** Download da procuração de um Proprietário da solicitação */
    @GET
    @Path("/{idTrocaEnvolvido}/proprietario/{idProprietario}/procurador/arquivo")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    Response downloadProcuracaoProprietario(
        @PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido,
        @PathParam("idProprietario") Long idProprietario);

    /**
     * Verifica se já existe um RT com o CPF e tipo de responsabilidade informados
     * vinculado ao licenciamento.
     */
    @GET
    @Path("/licenciamentos/{idLic}/cpf/{cpf}/responsabilidade/{tpResponsabilidade}")
    Response verificaExistenciaRt(@PathParam("idLic") Long idLicenciamento,
                                   @PathParam("cpf") String cpf,
                                   @PathParam("tpResponsabilidade") String tpResponsabilidade);
}
```

**Implementação:**

```java
// TrocaEnvolvidoRestImpl.java
@Path("/troca-envolvidos")
@Stateless
public class TrocaEnvolvidoRestImpl implements TrocaEnvolvidoRest {

    @Inject private ConsultaTrocaEnvolvidoRN consultaTrocaEnvolvidoRN;
    @Inject private ListaTrocaEnvolvidoLicenciamentoRN listaTrocaLicRN;
    @Inject private ConsultaTrocaEnvolvidoLicenciamentoRN consultaTrocaLicRN;
    @Inject private ConsultaArquivoSolicitacaoTrocaEnvolvidoRN consultaArquivoRN;
    @Inject private SolicitaTrocaEnvolvidoLicenciamentoRN solicitaRN;
    @Inject private ListaTrocaEnvolvidoRN listaTrocaRN;
    @Inject private CancelaTrocaEnvolvidoRN cancelaTrocaRN;
    @Inject private ResponsavelTecnicoRN responsavelTecnicoRN;
    @Inject private MultipartFormUtil multipartFormUtil;
    @Inject private NotificaTrocaEnvolvidoRN notificaRN;

    @Override
    public Response inclui(MultipartFormDataInput form) {
        TrocaEnvolvidoDTO dto = multipartFormUtil.extraiDTO(form, "troca", TrocaEnvolvidoDTO.class);
        List<ArquivoUpload> arquivos = multipartFormUtil.extraiArquivos(form);
        TrocaEnvolvidoDTO resultado = solicitaRN.solicita(dto, arquivos);
        return Response.status(Status.CREATED).entity(resultado).build();
    }
    // ...
}
```

---

### 6.2 LicenciamentoTrocaEnvolvidoRest — Endpoints de Autorização (Proprietários)

```java
// Interface: LicenciamentoTrocaEnvolvidoRest.java
// Implementação: LicenciamentoTrocaEnvolvidoRestImpl.java
// @Path("/licenciamentos/{idLic}/troca-envolvidos")
// @AutorizaEnvolvido — todos os endpoints exigem vínculo com o licenciamento

@Path("/licenciamentos/{idLic}/troca-envolvidos")
@Stateless
@Interceptors(SegurancaEnvolvidoInterceptor.class)  // verifica vínculo com o licenciamento
public class LicenciamentoTrocaEnvolvidoRestImpl implements LicenciamentoTrocaEnvolvidoRest {

    @Inject private ConsultaAutorizacaoTrocaEnvolvidoRN consultaAutorizacaoRN;
    @Inject private AutorizacaoTrocaEnvolvidoRN autorizacaoRN;
    @Inject private ConsultaArquivoAutorizacaoTrocaEnvolvidoRN consultaArquivoAutRN;

    /**
     * GET /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/autorizacao
     * Retorna os dados da solicitação + autorizações pendentes do usuário logado.
     * @Permissao(objeto="LICENCIAMENTO", acao="CONSULTAR_AUTORIZACAO_TROCA_ENVOLVIDOS")
     */
    @GET
    @Path("/{idTrocaEnvolvido}/autorizacao")
    public Response consultaAutorizacao(@PathParam("idLic") Long idLic,
                                         @PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido) {
        TrocaEnvolvidoDTO dto = consultaAutorizacaoRN.consultaAutorizacao(idTrocaEnvolvido);
        return Response.ok(dto).build();
    }

    /**
     * PUT /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/autorizar
     * Proprietário (ou procurador) aprova a troca.
     * @Permissao(objeto="LICENCIAMENTO", acao="AUTORIZAR_MUDANCA_ENVOLVIDOS")
     */
    @PUT
    @Path("/{idTrocaEnvolvido}/autorizar")
    public Response autorizar(@PathParam("idLic") Long idLic,
                               @PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido) {
        TrocaEnvolvidoDTO dto = autorizacaoRN.autoriza(idTrocaEnvolvido);
        return Response.ok(dto).build();
    }

    /**
     * PUT /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/rejeitar
     * Proprietário (ou procurador) rejeita a troca.
     * @Permissao(objeto="LICENCIAMENTO", acao="AUTORIZAR_MUDANCA_ENVOLVIDOS")
     */
    @PUT
    @Path("/{idTrocaEnvolvido}/rejeitar")
    public Response rejeitar(@PathParam("idLic") Long idLic,
                              @PathParam("idTrocaEnvolvido") Long idTrocaEnvolvido) {
        TrocaEnvolvidoDTO dto = autorizacaoRN.rejeita(idTrocaEnvolvido);
        return Response.ok(dto).build();
    }

    /** Download ART/RRT de um RT da solicitação (visão do proprietário) */
    @GET
    @Path("/{idTrocaEnvolvido}/rt/{idRT}/arquivo/{idArquivo}")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    public Response downloadArquivoRt(...) { ... }

    /** Download procuração do RU (visão do proprietário) */
    @GET
    @Path("/{idTrocaEnvolvido}/ru/{idRU}/procurador/arquivo")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    public Response downloadProcuracaoRu(...) { ... }

    /** Download procuração de proprietário (visão do proprietário) */
    @GET
    @Path("/{idTrocaEnvolvido}/proprietario/{idProprietario}/procurador/arquivo")
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    public Response downloadProcuracaoProprietario(...) { ... }
}
```

---

## S7 — DTOs e Builders

### 7.1 TrocaEnvolvidoDTO

```java
// Arquivo: TrocaEnvolvidoDTO.java (152 linhas)
public class TrocaEnvolvidoDTO {

    private Long id;
    private Long idLicenciamento;
    private SituacaoTrocaEnvolvido situacao;
    private String descricaoSituacao;        // Label legível para o frontend
    private Calendar dthSituacao;

    /** Flags indicando quais envolvidos estão sendo trocados */
    private Boolean indTrocaRt;
    private Boolean indTrocaRu;
    private Boolean indTrocaProprietario;

    /** Dados resumidos do licenciamento (número, situação, validade APPCI) */
    private RetornoLicenciamentoTrocaEnvolvidoDTO licenciamento;

    /** Usuário SOE solicitante */
    private Usuario usuarioSolicitante;

    /** Novos RTs propostos com arquivos ART/RRT */
    private List<ResponsavelTecnicoTrocaEnvolvido> rts = new ArrayList<>();

    /** Novo RU proposto com procurador */
    private List<ResponsavelUsoTrocaEnvolvido> rus = new ArrayList<>();

    /** Novos proprietários propostos (PF e/ou PJ) com procuradores */
    private List<ProprietarioTrocaEnvolvido> proprietarios = new ArrayList<>();

    /** Autorizações dos proprietários atuais (PENDENTE / APROVADO / REPROVADO) */
    private List<AutorizacaoTrocaEnvolvido> autorizacoes = new ArrayList<>();
}
```

### 7.2 Sub-DTOs de Envolvidos

```java
// Interfaces de dados dos envolvidos na solicitação

public interface ResponsavelTecnicoTrocaEnvolvido {
    String getCpf();                                // CPF do novo RT
    List<ArquivoTrocaEnvolvido> getArquivos();      // ART/RRT (nodeRef Alfresco)
    TipoResponsabilidadeTecnica getTipoResponsabilidadeTecnica();
}

public interface ResponsavelUsoTrocaEnvolvido {
    String getCpf();                                // CPF do novo RU
    ProcuradorTrocaEnvolvido getProcurador();       // Procurador (opcional)
}

public interface ProprietarioTrocaEnvolvido {
    String getCpf();                                // CPF (PF) ou null (PJ)
    String getCnpj();                               // CNPJ (PJ) ou null (PF)
    String getRazaoSocial();
    String getNomeFantasia();
    String getEmail();
    String getTelefone();
    ProcuradorTrocaEnvolvido getProcurador();       // Procurador (opcional)
}

public interface AutorizacaoTrocaEnvolvido {
    Long getId();
    String getTpPessoa();
    Usuario getUsuario();                           // Proprietário
    ProcuradorTrocaEnvolvido getProcurador();
    String getRazaoSocial();
    Boolean getIndAutorizado();                     // null=pendente, true=aprovou, false=rejeitou
    Calendar getDthAutorizacao();
}

public interface ProcuradorTrocaEnvolvido {
    String getCpf();
    ArquivoTrocaEnvolvido getArquivo();             // Procuração (Alfresco)
}
```

### 7.3 RetornoLicenciamentoTrocaEnvolvidoDTO

```java
// Dados do licenciamento exibidos ao solicitante antes de confirmar a troca
public class RetornoLicenciamentoTrocaEnvolvidoDTO {
    private String numero;               // Número do licenciamento
    private String descricaoSituacao;    // Situação legível
    private Calendar validadeAppci;      // Validade do APPCI (se existir)
    // demais campos do licenciamento
}
```

### 7.4 Builders

| Builder | Entidade/DTO construído |
|---|---|
| `BuilderTrocaEnvolvidoED` | `TrocaEnvolvidoED` |
| `BuilderTrocaEnvolvidoDTO` | `TrocaEnvolvidoDTO` |
| `BuilderTrocaEnvolvidoListaDTO` | `TrocaEnvolvidoListaDTO` |
| `BuilderTrocaRTED` | `TrocaRTED` |
| `BuilderTrocaRUED` | `TrocaRUED` |
| `BuilderTrocaProprietarioED` | `TrocaProprietarioED` |
| `BuilderTrocaAutorizacaoED` | `TrocaAutorizacaoED` |
| `BuilderRetornoLicenciamentoTrocaEnvolvidoDTO` | `RetornoLicenciamentoTrocaEnvolvidoDTO` |
| `BuilderResponsavelTecnicoTrocaEnvolvido` | `ResponsavelTecnicoTrocaEnvolvido` |
| `BuilderResponsavelUsoTrocaEnvolvido` | `ResponsavelUsoTrocaEnvolvido` |
| `BuilderProprietarioTrocaEnvolvido` | `ProprietarioTrocaEnvolvido` |
| `BuilderProcuradorTrocaEnvolvido` | `ProcuradorTrocaEnvolvido` |
| `BuilderAutorizacaoTrocaEnvolvido` | `AutorizacaoTrocaEnvolvido` |

---

## S8 — Conversores (ED → DTO)

| Converter | Origem → Destino |
|---|---|
| `TrocaEnvolvidoEDToTrocaEnvolvidoListaDTOConverter` | `TrocaEnvolvidoED` → `TrocaEnvolvidoListaDTO` |
| `TrocaRTToResponsavelTecnicoTrocaEnvolvidoConverter` | `TrocaRTED` → `ResponsavelTecnicoTrocaEnvolvido` |
| `TrocaRUToResponsavelUsoTrocaEnvolvidoConverter` | `TrocaRUED` → `ResponsavelUsoTrocaEnvolvido` |
| `TrocaProprietarioToProprietarioTrocaEnvolvidoConverter` | `TrocaProprietarioED` → `ProprietarioTrocaEnvolvido` |
| `TrocaAutorizacaoToAutorizacaoTrocaEnvolvidoConverter` | `TrocaAutorizacaoED` → `AutorizacaoTrocaEnvolvido` |
| `LicenciamentoEDToRetornoLicenciamentoTrocaEnvolvidoSituacaoDTOConverter` | `LicenciamentoED` → `RetornoLicenciamentoTrocaEnvolvidoDTO` (situação) |
| `LicenciamentoEDToRetornoLicenciamentoTrocaEnvolvidoDescSituacaoDTOConverter` | `LicenciamentoED` → `RetornoLicenciamentoTrocaEnvolvidoDTO` (desc. situação) |

---

## S9 — Segurança e Controle de Acesso

### Camadas de segurança

| Camada | Mecanismo | Onde aplica |
|---|---|---|
| Autenticação | SOE PROCERGS — token JWT (Implicit Flow OIDC) | Todos os endpoints |
| Vínculo com licenciamento | `@AutorizaEnvolvido` + `SegurancaEnvolvidoInterceptor` | `LicenciamentoTrocaEnvolvidoRestImpl` (todos os endpoints de autorização) |
| Permissão funcional | `@Permissao(objeto, acao)` | `AutorizacaoTrocaEnvolvidoRN` e `ConsultaAutorizacaoTrocaEnvolvidoRN` |
| Propriedade da solicitação | `TrocaEnvolvidoRNVal.validaUsuarioLogadoSolicitante()` | `CancelaTrocaEnvolvidoRN.cancela()` |
| Autorização pendente | `AutorizacaoTrocaEnvolvidoHelper.isUsuarioVinculadoAAutorizacaoPendente()` | `AutorizacaoTrocaEnvolvidoRN.autoriza/rejeita()` |

### Permissões declaradas

| `@Permissao(objeto, acao)` | Método | Descrição |
|---|---|---|
| `"LICENCIAMENTO"`, `"AUTORIZAR_MUDANCA_ENVOLVIDOS"` | `AutorizacaoTrocaEnvolvidoRN.autoriza()` e `rejeita()` | Autorizar ou rejeitar a troca |
| `"LICENCIAMENTO"`, `"CONSULTAR_AUTORIZACAO_TROCA_ENVOLVIDOS"` | `ConsultaAutorizacaoTrocaEnvolvidoRN.consultaAutorizacao()` | Consultar pendências de autorização |

---

## S10 — Integração com Alfresco ECM

Os documentos do processo P09 (ART/RRT dos RTs, procurações de RU e Proprietários)
são armazenados no Alfresco. O padrão é o mesmo do restante do sistema SOL:

```
Fluxo de gravação (durante SolicitaTrocaEnvolvidoLicenciamentoRN.solicita()):

1. TrocaEnvolvidoRestImpl.inclui() recebe partes do multipart (arquivos binários)
2. ArquivoRN.incluir(InputStream, nomeArquivo, TipoArquivo, LicenciamentoED)
   → INSERT INTO CBM_ARQUIVO (NOME_ARQUIVO, TXT_IDENTIFICADOR_ALFRESCO='0', TP_ARQUIVO, ...)
   → POST para Alfresco CMIS AtomPub → retorna nodeRef
   → UPDATE CBM_ARQUIVO SET TXT_IDENTIFICADOR_ALFRESCO = 'workspace://SpacesStore/{UUID}'
3. ArquivoED retornado é vinculado ao TrocaRTED (para ART/RRT)
   ou ao TrocaRUED.procuradorArquivo / TrocaProprietarioED.arquivoProcurador (para procurações)

Tipos de arquivo usados:
   ART/RRT do RT:    TipoArquivo.EDIFICACAO  (grp:familia="Documentos de Edificação")
   Procurações:      TipoArquivo.EDIFICACAO  (mesma família)

Fluxo de leitura (download via endpoints /arquivo e /procurador/arquivo):
1. ConsultaArquivoSolicitacaoTrocaEnvolvidoRN (ou ConsultaArquivoAutorizacaoTrocaEnvolvidoRN)
   localiza o ArquivoED pelo ID
2. ArquivoRN consulta o nodeRef em TXT_IDENTIFICADOR_ALFRESCO
3. Chama cliente Alfresco CMIS com o nodeRef → obtém InputStream do binário
4. REST retorna Response com MediaType.APPLICATION_OCTET_STREAM e header Content-Disposition
```

---

## S11 — Helpers e Utilitários

### TrocaEnvolvidoHelper

```java
// Arquivo: TrocaEnvolvidoHelper.java (47 linhas)
public class TrocaEnvolvidoHelper {

    /** Retorna true se o DTO contém pelo menos um RT a ser trocado */
    public static boolean possuiTrocaRT(TrocaEnvolvidoDTO dto) {
        return dto.getRts() != null && !dto.getRts().isEmpty();
    }

    /** Retorna true se o DTO contém pelo menos um RU a ser trocado */
    public static boolean possuiTrocaRU(TrocaEnvolvidoDTO dto) {
        return dto.getRus() != null && !dto.getRus().isEmpty();
    }

    /** Retorna true se o DTO contém pelo menos um Proprietário a ser trocado */
    public static boolean possuiTrocaProprietario(TrocaEnvolvidoDTO dto) {
        return dto.getProprietarios() != null && !dto.getProprietarios().isEmpty();
    }
}
```

### AutorizacaoTrocaEnvolvidoHelper

```java
// Arquivo: AutorizacaoTrocaEnvolvidoHelper.java (24 linhas)
public class AutorizacaoTrocaEnvolvidoHelper {

    /**
     * Verifica se o usuário logado está vinculado a um registro de autorização
     * que ainda não foi respondido (indAutorizado == null).
     * Considera tanto o proprietário direto quanto seu procurador.
     */
    public static boolean isUsuarioVinculadoAAutorizacaoPendente(
            UsuarioED usuarioLogado, TrocaAutorizacaoED autorizacao) {
        if (autorizacao.getIndAutorizado() != null) return false; // já respondeu
        boolean isProprietario = autorizacao.getUsuario() != null &&
            autorizacao.getUsuario().getId().equals(usuarioLogado.getId());
        boolean isProcurador = autorizacao.getProcurador() != null &&
            autorizacao.getProcurador().getId().equals(usuarioLogado.getId());
        return isProprietario || isProcurador;
    }
}
```

---

## S12 — Máquina de Estados e Marcos de Auditoria

### Máquina de estados da TrocaEnvolvidoED

```
SolicitaTrocaEnvolvidoLicenciamentoRN.solicita()
                │
                ▼
          SOLICITADO ──────────────────────────────────────────────────────────┐
                │                                                              │
    Cada proprietário responde via                                     CancelaTrocaEnvolvidoRN.cancela()
    AutorizacaoTrocaEnvolvidoRN                                                │
                │                                                              ▼
   ┌────────────┴─────────────────┐                                       CANCELADO
   │ Todos os proprietários       │ Qualquer proprietário
   │ autorizaram (todos 'S')      │ rejeitou ('N')
   ▼                              ▼
APROVADO                      REPROVADO
   │                              │
efetivaçao dos envolvidos     Nenhuma alteração nos envolvidos
ProcessaTrocaRtRN             Situação licenciamento NÃO muda
ProcessaTrocaRuRN
ProcessaTrocaProprietarioRN
```

### Marcos de Auditoria (TipoMarco) registrados no P09

| Evento | Marco | Registrado em |
|---|---|---|
| Solicitação criada | `SOLICITA_TROCA_ENVOLVIDO` | `SolicitaTrocaEnvolvidoLicenciamentoRN.solicita()` |
| Proprietário aprovou | `APROVA_TROCA_ENVOLVIDO` | `AutorizacaoTrocaEnvolvidoRN.autoriza()` |
| Proprietário rejeitou | `REPROVA_TROCA_ENVOLVIDO` | `AutorizacaoTrocaEnvolvidoRN.rejeita()` |
| Troca efetivada | `REALIZA_TROCA_ENVOLVIDO` | `AutorizacaoTrocaEnvolvidoRN.processaAutorizacaoTodosProprietarios()` |

---

## S13 — Fluxo Completo Passo a Passo

### Fluxo A — Troca efetivada (todos os proprietários autorizam)

```
PASSO 1 — Solicitante (RT, RU ou Proprietário) acessa a tela de Troca de Envolvidos

PASSO 2 — Frontend Angular busca licenciamentos passíveis de troca
  GET /troca-envolvidos/licenciamentos?nroLicenciamento=XXXXX
  → ListaTrocaEnvolvidoLicenciamentoRN.lista() valida filtro obrigatório (RNVal)
  → Retorna List<RetornoLicenciamentoTrocaEnvolvidoDTO>

PASSO 3 — Frontend consulta o licenciamento selecionado
  GET /troca-envolvidos/licenciamentos/{idLicenciamento}
  → ConsultaTrocaEnvolvidoLicenciamentoRN.consulta() verifica:
     a. Tipo PPCI ou PSPCIM (RN01)
     b. Não há troca SOLICITADO ativa (RN02)
  → Retorna RetornoLicenciamentoTrocaEnvolvidoDTO (com validade APPCI, situação, etc.)

PASSO 4 — Solicitante preenche o formulário de troca:
  - Informa novos RTs com CPF + TipoResponsabilidadeTecnica + upload ART/RRT
  - Informa novo RU (opcional) com CPF + eventual procurador + upload procuração
  - Informa novos Proprietários (opcional) com dados PF/PJ + eventual procurador

  O solicitante também pode verificar RT específico:
  GET /troca-envolvidos/licenciamentos/{idLic}/cpf/{cpf}/responsabilidade/{tipo}
  → ResponsavelTecnicoRN.consultaResponsavelTenicoLicenciamento()

PASSO 5 — Solicitante submete a solicitação
  POST /troca-envolvidos  (Content-Type: multipart/form-data)
  Partes: json "troca" + arquivos "arquivo-rt-*" + "procurador-ru" + "procurador-proprietario-*"

PASSO 6 — Backend executa SolicitaTrocaEnvolvidoLicenciamentoRN.solicita():
  6a. TrocaEnvolvidoLicenciamentoRNVal.validaTipoLicenciamento()         — RN01
  6b. validaTrocaEnvolvidoSolicitadaParaMesmoLicenciamento()             — RN02
  6c. validaSituacaoLicenciamento()                                      — RN03
  6d. solicitaRNVal.validaEnvolvidosInformados()                         — RN04
  6e. solicitaRNVal.validaUsuarioLogadoEntreEnvolvidos()                 — RN05
  6f. INSERT INTO CBM_TROCA_ENVOLVIDO (situacao=SOLICITADO)
  6g. Para cada novo RT: ArquivoRN.incluir() (Alfresco) → INSERT INTO CBM_ARQUIVO
      + INSERT INTO CBM_TROCA_RT
  6h. Para novo RU (se informado): INSERT INTO CBM_TROCA_RU
      + procuração: ArquivoRN.incluir() (Alfresco) → INSERT INTO CBM_ARQUIVO
  6i. Para novos Proprietários: INSERT INTO CBM_TROCA_PROPRIETARIO
      + procuração: ArquivoRN.incluir() (Alfresco) → INSERT INTO CBM_ARQUIVO
  6j. Para cada proprietário atual do licenciamento:
      INSERT INTO CBM_TROCA_AUTORIZACAO (IND_AUTORIZADO=null)            — RN06
  6k. Marco: INSERT INTO CBM_MARCO_LICENCIAMENTO (TP_MARCO=SOLICITA_TROCA_ENVOLVIDO)
  6l. Notificação: e-mail para cada proprietário do licenciamento
  → HTTP 201 Created com TrocaEnvolvidoDTO

PASSO 7 — Proprietário 1 recebe e-mail e acessa o sistema
  GET /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/autorizacao
  → ConsultaAutorizacaoTrocaEnvolvidoRN.consultaAutorizacao() (RN07 validações)
  → Retorna TrocaEnvolvidoDTO com autorizacoes[] e dados de RTs/RUs/Proprietários propostos
  → Proprietário pode baixar ART/RRT e procurações para análise

PASSO 8 — Proprietário 1 aprova
  PUT /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/autorizar
  8a. AutorizacaoTrocaEnvolvidoRNVal.validaAutorizacao() — RN07 completo
  8b. UPDATE CBM_TROCA_AUTORIZACAO SET IND_AUTORIZADO='S', DTH_AUTORIZACAO=SYSDATE
  8c. INSERT INTO CBM_MARCO_LICENCIAMENTO (TP_MARCO=APROVA_TROCA_ENVOLVIDO)
  8d. Verifica se todos aprovaram: NÃO (Proprietário 2 ainda pendente)
  → HTTP 200 com TrocaEnvolvidoDTO atualizado

PASSO 9 — Proprietário 2 aprova (último proprietário)
  PUT /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/autorizar
  9a. Mesmas validações e gravação do PASSO 8
  9b. INSERT INTO CBM_MARCO_LICENCIAMENTO (APROVA_TROCA_ENVOLVIDO)
  9c. Todos aprovaram → processaAutorizacaoTodosProprietarios()           — RN08:
      9c.1 ProcessaTrocaRtRN.processa(): aplica matriz 31 combinações     — RN13
           → Atualiza tabelas de ResponsavelTecnicoED do licenciamento
           → Copia/substitui ArquivoEDs de ART/RRT conforme AcaoTrocaRT
      9c.2 ProcessaTrocaRuRN.processa(): sincroniza RU                    — RN14
           → Remove RU antigo, inclui novo, atualiza procurador
      9c.3 ProcessaTrocaProprietarioRN.processa(): sincroniza proprietários — RN15
           → Remove/atualiza/inclui proprietários PF e PJ
      9c.4 UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='APROVADO'
      9c.5 INSERT INTO CBM_MARCO_LICENCIAMENTO (REALIZA_TROCA_ENVOLVIDO)
      9c.6 Notifica: e-mail para TODOS os envolvidos (RT saindo, novo RT, RU, Proprietários)
  → HTTP 200 com TrocaEnvolvidoDTO (situacao=APROVADO)
```

---

### Fluxo B — Troca reprovada (um proprietário rejeita)

```
PASSOS 1–8: idênticos ao Fluxo A até a resposta do primeiro proprietário

PASSO 9 — Proprietário 2 rejeita
  PUT /licenciamentos/{idLic}/troca-envolvidos/{idTrocaEnvolvido}/rejeitar
  9a. AutorizacaoTrocaEnvolvidoRNVal.validaAutorizacao() — RN07
  9b. UPDATE CBM_TROCA_AUTORIZACAO SET IND_AUTORIZADO='N', DTH_AUTORIZACAO=SYSDATE
  9c. UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='REPROVADO'    — RN09
  9d. INSERT INTO CBM_MARCO_LICENCIAMENTO (REPROVA_TROCA_ENVOLVIDO)
  9e. Notificação: e-mail ao solicitante e demais proprietários
  → Nenhum envolvido foi alterado — tudo permanece como antes
  → HTTP 200 com TrocaEnvolvidoDTO (situacao=REPROVADO)
```

---

### Fluxo C — Cancelamento pelo solicitante

```
PASSOS 1–6: troca criada com status SOLICITADO

PASSO 7 — Solicitante muda de ideia e cancela
  PUT /troca-envolvidos/{idTrocaEnvolvido}/cancelar
  7a. TrocaEnvolvidoRN.busca(idTrocaEnvolvido)
  7b. CancelaTrocaEnvolvidoRNVal.validaSituacao()          — RN10: deve ser SOLICITADO
  7c. TrocaEnvolvidoRNVal.validaUsuarioLogadoSolicitante() — RN11: deve ser o criador
  7d. UPDATE CBM_TROCA_ENVOLVIDO SET SIT_TROCA_ENVOLVIDO='CANCELADO'
  7e. Notificação: e-mail aos proprietários sobre o cancelamento
  → HTTP 200

PASSO 8 — Solicitante pode reforçar notificação antes de cancelar (opcional)
  POST /troca-envolvidos/{idTrocaEnvolvido}/reforcar-solicitacao
  → NotificaTrocaEnvolvidoRNVal.validaSituacaoSolicitada()  — RN12
  → UPDATE CBM_TROCA_ENVOLVIDO SET DTH_COMUNICACAO=SYSDATE
  → Reenvio de e-mail para proprietários
```

---

## S14 — DDL Oracle

```sql
-- Sequência principal
CREATE SEQUENCE SEQ_CBM_TROCA_ENVOLVIDO START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CBM_TROCA_RT        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CBM_TROCA_RU        START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CBM_TROCA_PROPRIETARIO START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_CBM_TROCA_AUTORIZACAO  START WITH 1 INCREMENT BY 1 NOCACHE;

-- Tabela principal da solicitação
CREATE TABLE CBM_TROCA_ENVOLVIDO (
    NRO_INT_TROCA_ENVOLVIDO  NUMBER        NOT NULL,
    NRO_INT_LICENCIAMENTO    NUMBER        NOT NULL,
    NRO_INT_USUARIO          NUMBER,
    IND_TROCA_RT             CHAR(1 CHAR)  CHECK (IND_TROCA_RT IN ('S','N')),
    IND_TROCA_RU             CHAR(1 CHAR)  CHECK (IND_TROCA_RU IN ('S','N')),
    IND_TROCA_PROPRIETARIO   CHAR(1 CHAR)  CHECK (IND_TROCA_PROPRIETARIO IN ('S','N')),
    DTH_CRIACAO              DATE          NOT NULL,
    DTH_COMUNICACAO          DATE,
    SIT_TROCA_ENVOLVIDO      VARCHAR2(30)  NOT NULL
        CHECK (SIT_TROCA_ENVOLVIDO IN ('SOLICITADO','APROVADO','REPROVADO','CANCELADO')),
    DTH_SITUACAO             DATE,
    CONSTRAINT PK_CBM_TROCA_ENVOLVIDO PRIMARY KEY (NRO_INT_TROCA_ENVOLVIDO),
    CONSTRAINT FK_TROCA_ENV_LIC  FOREIGN KEY (NRO_INT_LICENCIAMENTO)
        REFERENCES CBM_LICENCIAMENTO (NRO_INT_LICENCIAMENTO),
    CONSTRAINT FK_TROCA_ENV_USR  FOREIGN KEY (NRO_INT_USUARIO)
        REFERENCES CBM_USUARIO (NRO_INT_USUARIO)
);

-- Tabela de RTs da solicitação
CREATE TABLE CBM_TROCA_RT (
    NRO_INT_TROCA_RT          NUMBER       NOT NULL,
    NRO_INT_TROCA_ENVOLVIDO   NUMBER       NOT NULL,
    NRO_INT_USUARIO           NUMBER,
    TP_RESPONSABILIDADE       VARCHAR2(40),
    CONSTRAINT PK_CBM_TROCA_RT PRIMARY KEY (NRO_INT_TROCA_RT),
    CONSTRAINT FK_TROCA_RT_ENV FOREIGN KEY (NRO_INT_TROCA_ENVOLVIDO)
        REFERENCES CBM_TROCA_ENVOLVIDO (NRO_INT_TROCA_ENVOLVIDO),
    CONSTRAINT FK_TROCA_RT_USR FOREIGN KEY (NRO_INT_USUARIO)
        REFERENCES CBM_USUARIO (NRO_INT_USUARIO)
);

-- Tabela de RUs da solicitação
CREATE TABLE CBM_TROCA_RU (
    NRO_INT_TROCA_RU          NUMBER       NOT NULL,
    NRO_INT_TROCA_ENVOLVIDO   NUMBER       NOT NULL,
    NRO_INT_USUARIO           NUMBER,
    NRO_INT_USUARIO_PROCURADOR NUMBER,
    NRO_INT_ARQUIVO_PROCURADOR NUMBER,
    CONSTRAINT PK_CBM_TROCA_RU PRIMARY KEY (NRO_INT_TROCA_RU),
    CONSTRAINT FK_TROCA_RU_ENV FOREIGN KEY (NRO_INT_TROCA_ENVOLVIDO)
        REFERENCES CBM_TROCA_ENVOLVIDO (NRO_INT_TROCA_ENVOLVIDO),
    CONSTRAINT FK_TROCA_RU_USR FOREIGN KEY (NRO_INT_USUARIO)
        REFERENCES CBM_USUARIO (NRO_INT_USUARIO)
);

-- Tabela de Proprietários da solicitação
CREATE TABLE CBM_TROCA_PROPRIETARIO (
    NRO_INT_TROCA_PROPRIETARIO NUMBER      NOT NULL,
    NRO_INT_TROCA_ENVOLVIDO    NUMBER      NOT NULL,
    TP_PESSOA                  CHAR(1 CHAR) CHECK (TP_PESSOA IN ('F','J')),
    NRO_INT_USUARIO            NUMBER,
    TXT_CNPJ                   VARCHAR2(14 CHAR),
    TXT_RAZAO_SOCIAL           VARCHAR2(200 CHAR),
    TXT_NOME_FANTASIA           VARCHAR2(200 CHAR),
    TXT_EMAIL                  VARCHAR2(200 CHAR),
    TXT_TELEFONE               VARCHAR2(20 CHAR),
    NRO_INT_USUARIO_PROCURADOR NUMBER,
    NRO_INT_ARQUIVO_PROCURADOR NUMBER,
    CONSTRAINT PK_CBM_TROCA_PROPRIETARIO PRIMARY KEY (NRO_INT_TROCA_PROPRIETARIO),
    CONSTRAINT FK_TROCA_PROP_ENV FOREIGN KEY (NRO_INT_TROCA_ENVOLVIDO)
        REFERENCES CBM_TROCA_ENVOLVIDO (NRO_INT_TROCA_ENVOLVIDO)
);

-- Tabela de autorizações (uma por proprietário por solicitação)
CREATE TABLE CBM_TROCA_AUTORIZACAO (
    NRO_INT_TROCA_AUTORIZACAO  NUMBER      NOT NULL,
    NRO_INT_TROCA_ENVOLVIDO    NUMBER      NOT NULL,
    TP_PESSOA                  CHAR(1 CHAR) CHECK (TP_PESSOA IN ('F','J')),
    NRO_INT_USUARIO            NUMBER,
    NRO_INT_USUARIO_PROCURADOR NUMBER,
    TXT_RAZAO_SOCIAL           VARCHAR2(200 CHAR),
    IND_AUTORIZADO             CHAR(1 CHAR) CHECK (IND_AUTORIZADO IN ('S','N')),
    DTH_AUTORIZACAO            DATE,
    CONSTRAINT PK_CBM_TROCA_AUTORIZACAO PRIMARY KEY (NRO_INT_TROCA_AUTORIZACAO),
    CONSTRAINT FK_TROCA_AUT_ENV FOREIGN KEY (NRO_INT_TROCA_ENVOLVIDO)
        REFERENCES CBM_TROCA_ENVOLVIDO (NRO_INT_TROCA_ENVOLVIDO)
);

-- Índices de performance
CREATE INDEX IDX_TROCA_ENV_LIC ON CBM_TROCA_ENVOLVIDO (NRO_INT_LICENCIAMENTO);
CREATE INDEX IDX_TROCA_ENV_USR ON CBM_TROCA_ENVOLVIDO (NRO_INT_USUARIO);
CREATE INDEX IDX_TROCA_ENV_SIT ON CBM_TROCA_ENVOLVIDO (SIT_TROCA_ENVOLVIDO);
CREATE INDEX IDX_TROCA_RT_ENV  ON CBM_TROCA_RT (NRO_INT_TROCA_ENVOLVIDO);
CREATE INDEX IDX_TROCA_RU_ENV  ON CBM_TROCA_RU (NRO_INT_TROCA_ENVOLVIDO);
CREATE INDEX IDX_TROCA_PROP_ENV ON CBM_TROCA_PROPRIETARIO (NRO_INT_TROCA_ENVOLVIDO);
CREATE INDEX IDX_TROCA_AUT_ENV ON CBM_TROCA_AUTORIZACAO (NRO_INT_TROCA_ENVOLVIDO);
```

---

## S15 — Rastreabilidade: Código-Fonte → Requisito

| Arquivo Java (código-fonte real) | Seção neste documento |
|---|---|
| `TrocaEnvolvidoED.java` | S2.1 |
| `TrocaRTED.java` | S2.2 |
| `TrocaRUED.java` | S2.3 |
| `TrocaProprietarioED.java` | S2.4 |
| `TrocaAutorizacaoED.java` | S2.5 |
| `SituacaoTrocaEnvolvido.java` | S3.1 |
| `AcaoTrocaRT.java` | S3.2 |
| `TipoMarco.java` (valores P09) | S3.3 |
| `SituacaoLicenciamento.java` (lista branca) | S3.4 |
| `TrocaEnvolvidoLicenciamentoRNVal.java` | RN01 (S4) |
| `SolicitaTrocaEnvolvidoLicenciamentoRN.java` | RN02, RN03, RN06 (S4), S5.1 |
| `SolicitaTrocaEnvolvidoLicenciamentoRNVal.java` | RN04, RN05 (S4) |
| `AutorizacaoTrocaEnvolvidoRNVal.java` | RN07 (S4) |
| `AutorizacaoTrocaEnvolvidoRN.java` | RN08, RN09 (S4), S5.2 |
| `CancelaTrocaEnvolvidoRNVal.java` | RN10 (S4) |
| `TrocaEnvolvidoRNVal.java` | RN11 (S4) |
| `NotificaTrocaEnvolvidoRNVal.java` | RN12 (S4) |
| `ProcessaTrocaRtRN.java` + `CombinacaoTrocaRt.java` | RN13 (S4) |
| `ProcessaTrocaRuRN.java` | RN14 (S4) |
| `ProcessaTrocaProprietarioRN.java` | RN15 (S4) |
| `CancelaTrocaEnvolvidoRN.java` | S5.3 |
| `NotificaTrocaEnvolvidoRN.java` | S5.4 |
| `TrocaEnvolvidoBD.java` | S5.5 |
| `TrocaEnvolvidoRest.java` + `TrocaEnvolvidoRestImpl.java` | S6.1 |
| `LicenciamentoTrocaEnvolvidoRest.java` + `LicenciamentoTrocaEnvolvidoRestImpl.java` | S6.2 |
| `TrocaEnvolvidoDTO.java` | S7.1 |
| `ResponsavelTecnicoTrocaEnvolvido` (interface) | S7.2 |
| `ResponsavelUsoTrocaEnvolvido` (interface) | S7.2 |
| `ProprietarioTrocaEnvolvido` (interface) | S7.2 |
| `AutorizacaoTrocaEnvolvido` (interface) | S7.2 |
| `RetornoLicenciamentoTrocaEnvolvidoDTO.java` | S7.3 |
| Builder classes (13 builders) | S7.4 |
| Converter classes (7 conversores) | S8 |
| `SegurancaEnvolvidoInterceptor` + `@AutorizaEnvolvido` + `@Permissao` | S9 |
| `ArquivoRN.java` (Alfresco) | S10 |
| `TrocaEnvolvidoHelper.java` | S11 |
| `AutorizacaoTrocaEnvolvidoHelper.java` | S11 |
