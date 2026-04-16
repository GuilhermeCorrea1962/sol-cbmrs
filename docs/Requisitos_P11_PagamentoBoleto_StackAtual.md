# Requisitos P11 — Pagamento e Geração de Boleto
## Stack Atual — Java EE / WildFly / Oracle / SOE PROCERGS

> Documento de requisitos destinado à equipe de desenvolvimento.
> Stack: **Java EE 7 · JAX-RS · CDI · EJB `@Stateless` / `@Singleton` · JPA/Hibernate · Oracle · WildFly/JBoss**.
> Autenticação via **SOE PROCERGS / meu.rs.gov.br** (OAuth2/OIDC). Integração bancária via **serviço intermediário PROCERGS** (Banrisul SOAP encapsulado em REST JWT/JWE). Confirmação de pagamento via **arquivo CNAB 240** depositado em diretório do servidor.

---

## S1 — Visão Geral do Processo

O processo P11 cobre o ciclo completo de **geração, disponibilização e confirmação de pagamento de boleto bancário** vinculado a um licenciamento do SOL. É um processo transversal: é acionado sempre que um licenciamento atinge um dos estados de aguardo de pagamento.

### Subprocessos

| Subprocesso | Gatilho | Responsável |
|---|---|---|
| **P11-A — Geração de Boleto** | Chamada REST pelo frontend quando licenciamento está em estado `AGUARDANDO_PAGAMENTO*` | `BoletoLicenciamentoRN.gerarBoleto` |
| **P11-B — Confirmação de Pagamento** | Job `@Singleton @Startup` (EJBTimerService) que roda a cada 12 horas | `EJBTimerService.verificaPagamentoBanrisul` |

### Atores

| Ator | Identificação no sistema | Papel |
|---|---|---|
| **Cidadão / RT / Proprietário** | `idUsuarioSoe Long` (SOE PROCERGS) | Solicita geração do boleto e efetua pagamento externo |
| **Sistema — JAX-RS** | Backend WildFly | Calcula taxa, integra com PROCERGS/Banrisul, persiste boleto |
| **Sistema — EJBTimerService** | `@Singleton @Startup @Schedule` | Roda jobs de vencimento e confirmação de pagamento CNAB 240 |
| **PROCERGS / Banrisul** | Serviço externo REST + JWT/JWE | Registra o boleto no banco Banrisul e retorna código de barras e linha digitável |

### Estados de Licenciamento Disparadores

O P11-A é acionado quando o licenciamento está nos estados:

| `SituacaoLicenciamento` | Tipo de boleto gerado |
|---|---|
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`, `TAXA_REANALISE` ou `TAXA_UNICA` |
| `AGUARDANDO_PAGAMENTO_VISTORIA` | `TAXA_VISTORIA` |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | `TAXA_RENOVACAO` |

---

## S2 — Modelo de Dados

### 2.1 Entidade `BoletoED`

Tabela Oracle: **`CBM_BOLETO`** | Sequência: **`CBM_ID_BOLETO_SEQ`**

```java
@Entity
@Table(name = "CBM_BOLETO")
@NamedQueries({
    @NamedQuery(name = "BoletoED.consulta",
        query = "select b from BoletoED b join fetch b.beneficiario left join fetch b.pagador where b.id = :id")
})
public class BoletoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "Boleto_SEQ", sequenceName = "CBM_ID_BOLETO_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "Boleto_SEQ")
    @Column(name = "NRO_INT_BOLETO")
    private Long id;

    /** Número único gerado a partir do ID com DV módulo 11. NUMERIC(38). */
    @Column(name = "NRO_NOSSO_NUMERO")
    private BigInteger nossoNumero;

    /** Número externo para o banco. Formato: {id}L (licenciamento) ou {id}C (instrutor). Max 13 chars. */
    @Column(name = "TXT_SEU_NUMERO")
    @Size(max = 13)
    private String seuNumero;

    /** Data de vencimento: data de emissão + 30 dias corridos. */
    @Column(name = "DATA_VENCIMENTO")
    private Calendar dataVencimento;

    /** Valor nominal em R$. */
    @Column(name = "VALOR_NOMINAL")
    private BigDecimal valorNominal;

    /** Espécie do documento — converter: TipoEspecie enum. */
    @Column(name = "TP_ESPECIE")
    private TipoEspecie especie;

    /** Data e hora de emissão do boleto. */
    @Column(name = "DATA_EMISSAO")
    private Calendar dataEmissao;

    /** Código de barras retornado pelo Banrisul/PROCERGS. Max 44 chars. */
    @Column(name = "TXT_CODIGO_BARRAS")
    @Size(max = 44)
    private String codigoBarras;

    /** Linha digitável retornada pelo Banrisul/PROCERGS. Max 47 chars. */
    @Column(name = "TXT_LINHA_DIGITAVEL")
    @Size(max = 47)
    private String linhaDigitavel;

    /** Beneficiário (dados bancários do CBM-RS por município). Não nulo. LAZY. */
    @NotNull
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_BENEFICIARIO")
    private BeneficiarioED beneficiario;

    /** Pagador: usuário SOE (para boletos de instrutor). Nulo para licenciamento (pagador desnormalizado). LAZY. */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioED pagador;

    /** Origem do boleto: LICENCIAMENTO(1), INSTRUTOR(0), FACT(2), RENOVACAO_INSTRUTOR(3). */
    @Column(name = "TP_ORIGEM")
    private TipoOrigemBoleto origem;

    /** Situação atual: EM_ABERTO, VENCIDO ou PAGO. */
    @Column(name = "TP_SITUACAO")
    private SituacaoBoleto situacao;

    /** Data em que o banco confirmou o pagamento (preenchida via CNAB 240). */
    @Column(name = "DATA_PAGAMENTO")
    private Calendar dataPagamento;

    /** Nome do arquivo CNAB 240 que originou a confirmação. */
    @Column(name = "TXT_NOME_ARQUIVO_RETORNO")
    private String nomeArquivoRetorno;

    // Dados desnormalizados do pagador (copiados no momento da emissão):
    @Column(name = "NOME_PAGADOR")           private String nomePagador;
    @Column(name = "TXT_CPF_PAGADOR")        private String cpfPagador;
    @Column(name = "TXT_CNPJ_PAGADOR")       private String cnpjPagador;
    @Column(name = "TXT_ENDERECO_PAGADOR")   private String enderecoPagador;
    @Column(name = "TXT_CIDADE_PAGADOR")     private String cidadePagador;
    @Column(name = "TXT_UF_PAGADOR")         private String ufPagador;
    @Column(name = "TXT_CEP_PAGADOR")        private String cepPagador;
}
```

### 2.2 Entidade `BoletoLicenciamentoED`

Tabela Oracle: **`CBM_BOLETO_LICENCIAMENTO`** | Sequência: **`CBM_ID_BOLETO_LICENC_SEQ`**

```java
@Entity
@Table(name = "CBM_BOLETO_LICENCIAMENTO")
@NamedQueries({
    @NamedQuery(name = "BoletoLicenciamentoED.consulta",
        query = "select b from BoletoLicenciamentoED b join fetch b.licenciamento join fetch b.boleto where b.id = :id")
})
public class BoletoLicenciamentoED extends AppED<Long> {

    @Id
    @SequenceGenerator(name = "BoletoLicenciamento_SEQ",
        sequenceName = "CBM_ID_BOLETO_LICENC_SEQ", allocationSize = 1)
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "BoletoLicenciamento_SEQ")
    @Column(name = "NRO_INT_BOLETO_LICENCIAMENTO")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_LICENCIAMENTO")
    private LicenciamentoED licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "NRO_INT_BOLETO")
    private BoletoED boleto;

    /**
     * Tipo do boleto vinculado.
     * TAXA_ANALISE | TAXA_REANALISE | TAXA_VISTORIA | TAXA_UNICA | TAXA_RENOVACAO | SOLICITACAO_FACT
     */
    @Column(name = "TP_BOLETO")
    private TipoBoleto tipoBoleto;

    /**
     * Valor monetário da taxa de análise em R$ no momento da emissão.
     * Nulo para TAXA_VISTORIA.
     */
    @Column(name = "VALOR_TAXA_ANALISE")
    private BigDecimal valorTaxaAnalise;

    /**
     * Quantidade total de UPFs utilizada no cálculo.
     * Nulo para TAXA_VISTORIA. Usado na compensação de reanálise.
     */
    @Column(name = "QTD_TOTAL_UPF")
    private BigDecimal quantidadeTotalUpf;
}
```

### 2.3 Entidade `BeneficiarioED`

Tabela Oracle: **`CBM_BENEFICIARIO`**

| Coluna | Tipo Oracle | Campo Java | Descrição |
|---|---|---|---|
| `NRO_INT_BENEFICIARIO` | NUMBER(10) PK | `id` | Chave primária |
| `TXT_CODIGO` | VARCHAR2(20) | `codigo` | Código do beneficiário no banco (ex: `"0777.123456-7"`) |
| `NOM_BENEFICIARIO` | VARCHAR2 | `nome` | Nome do CBM-RS |
| `NOM_FANTASIA` | VARCHAR2 | `nomeFantasia` | Nome fantasia |
| `TXT_CPF_CNPJ` | VARCHAR2(14) | `cpfCnpj` | CPF ou CNPJ |
| `TXT_AGENCIA` | VARCHAR2 | `agencia` | Agência bancária |
| `TXT_ENDERECO` | VARCHAR2 | `endereco` | Endereço |
| `TXT_CIDADE` | VARCHAR2 | `cidade` | Cidade |
| `TXT_UF` | CHAR(2) | `uf` | UF |
| `TXT_CEP` | VARCHAR2(8) | `cep` | CEP |
| `NRO_INT_CIDADE` | NUMBER FK | `cidade` | Chave para `CBM_CIDADE` (seleção por município IBGE) |

O beneficiário é selecionado pelo número IBGE do município do endereço do licenciamento, via `CidadeRN.consultaPorNroMunicipioIBGE`.

### 2.4 Entidade `ParametroBoletoED`

Tabela Oracle: **`CBM_PARAMETRO_BOLETO`** | Sequência: **`CBM_ID_PARAMETRO_BOLETO_SEQ`**

| Coluna | Tipo | Descrição |
|---|---|---|
| `NRO_INT_PARAMETRO_BOLETO` | NUMBER(10) PK | Chave primária |
| `TXT_CHAVE` | VARCHAR2(100) NOT NULL | Chave identificadora |
| `TXT_VALOR` | VARCHAR2(100) NOT NULL | Valor string do parâmetro |

Chaves utilizadas (enum `ParametrosBoleto`):

| Chave (`TXT_CHAVE`) | Constante Java | Valor padrão | Descrição |
|---|---|---|---|
| `numero.dias.situacao.vencimento` | `NUMERO_DIAS_VENCIMENTO_BOLETO` | `"2"` | Dias após DATA_VENCIMENTO para marcar boleto como VENCIDO no job |
| `credenciamento.profissionalempresa.valor` | `CREDENCIAMENTO_PROFISSIONALEMPRESA_VALOR` | `"5"` | Número de UPFs para credenciamento |
| `consulta.tecnica.fact.valor` | `CONSULTA_TECNICA_FACT_VALOR` | — | Valor (UPFs) para FACT |
| `upf.valor` | — (tabela `CBM_PARAMETRO_BOLETO`) | `"19.5352"` | Valor unitário da UPF em R$ |

### 2.5 Entidade `LogGeraBoletoED`

Tabela Oracle: **`CBM_LOG_GERA_BOLETO`**

Registra cada tentativa de geração de boleto com resultado (sucesso ou erro), XML de envio/retorno, e vínculo com a entidade geradora (licenciamento, instrutor ou FACT). Gerenciada por `LogGeraBoletoRN` / `LogGeraBoletoBD`.

### 2.6 Enumerações

```java
// com.procergs.solcbm.enumeration.SituacaoBoleto
public enum SituacaoBoleto { EM_ABERTO, VENCIDO, PAGO }

// com.procergs.solcbm.enumeration.TipoBoleto
public enum TipoBoleto {
    TAXA_ANALISE,
    TAXA_REANALISE,
    TAXA_VISTORIA,
    SOLICITACAO_FACT,
    TAXA_UNICA,
    TAXA_RENOVACAO
}

// com.procergs.solcbm.enumeration.TipoOrigemBoleto
public enum TipoOrigemBoleto {
    INSTRUTOR(0, "Instrutor"),
    LICENCIAMENTO(1, "Licenciamento"),
    FACT(2, "Fact"),
    RENOVACAO_INSTRUTOR(3, "Renovação de Instrutor")
}

// com.procergs.solcbm.enumeration.TipoResponsavelPagamento
public enum TipoResponsavelPagamento { RT, RU, PROPRIETARIO_PF, PROPRIETARIO_PJ }

// com.procergs.solcbm.enumeration.ParametrosBoleto
public enum ParametrosBoleto {
    CREDENCIAMENTO_PROFISSIONALEMPRESA_VALOR("credenciamento.profissionalempresa.valor"),
    VERIFICACAO_JOB_ALFRESCO("verificacao.job.alfresco"),
    NUMERO_DIAS_VENCIMENTO_BOLETO("numero.dias.situacao.vencimento"),
    CONSULTA_TECNICA_FACT_VALOR("consulta.tecnica.fact.valor")
}
```

---

## S3 — Regras de Negócio

### RN-090 — Pré-condição: Situação do Licenciamento

**Implementado em:** `BoletoLicenciamentoRNVal.validaSituacaoLicenciamento`

O boleto só pode ser gerado se a situação do licenciamento for compatível com o tipo solicitado:

| `TipoBoleto` | `SituacaoLicenciamento` exigida |
|---|---|
| `TAXA_VISTORIA` | `AGUARDANDO_PAGAMENTO_VISTORIA` |
| `TAXA_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` |
| `TAXA_ANALISE`, `TAXA_REANALISE`, `TAXA_UNICA` | `AGUARDANDO_PAGAMENTO` |

```java
// BoletoLicenciamentoRNVal.java
public void validaSituacaoLicenciamento(TipoBoleto tipoBoleto, SituacaoLicenciamento situacao) {
    if ((TipoBoleto.TAXA_VISTORIA.equals(tipoBoleto)
            && !SituacaoLicenciamento.AGUARDANDO_PAGAMENTO_VISTORIA.equals(situacao))
        || (TipoBoleto.TAXA_RENOVACAO.equals(tipoBoleto)
            && !SituacaoLicenciamento.AGUARDANDO_PAGAMENTO_RENOVACAO.equals(situacao))) {
        throw new WebApplicationRNException(
            bundle.getMessage("licenciamento.situacao.operacao.invalida"),
            Response.Status.BAD_REQUEST);
    }
}
```

### RN-091 — Cancelamento Automático de Isenção Solicitada

**Implementado em:** `BoletoLicenciamentoRN.gerarBoleto`

Se no momento da geração o licenciamento possuir `situacaoIsencao = SOLICITADA`, o sistema deve:
1. Definir `licenciamentoED.isencao = false`
2. Limpar `licenciamentoED.situacaoIsencao = null`
3. Persistir via `licenciamentoRN.altera(licenciamentoED)`

Justificativa: ao optar por pagar o boleto, o cidadão abandona implicitamente a isenção pendente.

### RN-092 — Verificação de Boleto Vigente Anterior

**Implementado em:** `BoletoLicenciamentoRN.validarBoletoVencido` + `BoletoLicenciamentoRNVal.validaSituacaoBoletoAnteriorParaPagador`

A verificação é aplicada para todos os tipos **exceto** `TAXA_REANALISE`.

Algoritmo:
1. Buscar todos os `BoletoLicenciamentoED` para o mesmo licenciamento, mesmo `id` (quando informado) e mesmo `tipoBoleto`.
2. Para cada boleto encontrado, se o CPF/CNPJ do responsável informado coincide com o `cpfPagador` ou `cnpjPagador` do boleto:
   - Para `TAXA_ANALISE` / `TAXA_UNICA`: se situação for `EM_ABERTO` ou `PAGO` → lançar `WebApplicationRNException(HTTP 400)` com mensagem `boleto.licenciamento.{situacao}`.
   - Para `TAXA_VISTORIA` / `TAXA_RENOVACAO`: se situação for `EM_ABERTO` → lançar `WebApplicationRNException(HTTP 400)` com mensagem `boleto.licenciamento.EM_ABERTO`.

```java
// BoletoLicenciamentoRNVal.java — validaSituacaoBoletoLicenciamento
private void validaSituacaoBoletoLicenciamento(SituacaoBoleto situacaoBoleto) {
    if (!SituacaoBoleto.VENCIDO.equals(situacaoBoleto)) {
        lancaExecaoSituacaoBoleto(situacaoBoleto); // EM_ABERTO ou PAGO bloqueiam
    }
}
// validaSituacaoBoletoVistoria
private void validaSituacaoBoletoVistoria(SituacaoBoleto situacaoBoleto) {
    if (SituacaoBoleto.EM_ABERTO.equals(situacaoBoleto)) {
        lancaExecaoSituacaoBoleto(situacaoBoleto); // apenas EM_ABERTO bloqueia
    }
}
```

### RN-093 — Cálculo do Valor da Taxa

**Implementado em:** `BoletoLicenciamentoRN.getValorTaxa` e métodos auxiliares

**Fórmula geral:** `valorBoleto = round(qtdUPF × valorUPF, 2, HALF_EVEN)`

onde `valorUPF` é obtido de `ValorUPFRN.getValorAtualUPF()` (tabela `CBM_PARAMETRO_BOLETO`, chave `upf.valor`).

| `TipoBoleto` | Cálculo de `qtdUPF` | Isenção |
|---|---|---|
| `TAXA_ANALISE` (PPCI) | `TaxaLicenciamentoRN.calculaTaxaAnaliseLicenciamento(lic)` | Sem isenção |
| `TAXA_ANALISE` (PSPCIM) | `TaxaLicenciamentoRN.calculaTaxaUnicaLicenciamento(lic)` | Sem isenção |
| `TAXA_UNICA` | `TaxaLicenciamentoRN.calculaTaxaUnicaLicenciamento(lic)` | Sem isenção |
| `TAXA_VISTORIA` | `TaxaLicenciamentoRN.calculaTaxaVistoriaLicenciamento(lic)` (com regra 50%) | Se `lic.isIsento` → R$ 0,00 |
| `TAXA_REANALISE` | 50% de TAXA_ANALISE (salvo isenção reanálise) + compensação UPF | Se `lic.isIsento` → R$ 0,00 |
| `TAXA_RENOVACAO` | `calculaTaxaVistoriaLicenciamento` (com regra 50% por reprovação) | Sem isenção |

**Validação adicional:** `BoletoLicenciamentoRNVal.validaTipoBoleto` — `TAXA_REANALISE` exige que `licenciamento.numero` não seja em branco (licenciamento deve ter sido numerado, ou seja, passou pela análise ao menos uma vez).

### RN-094 — Regra dos 50% para TAXA_VISTORIA

**Implementado em:** `BoletoLicenciamentoRN.devePagarMeiaTaxaDeVistoria`

Aplica 50% da taxa de vistoria quando **todas** as seguintes condições são verdadeiras:
1. Existe ao menos uma vistoria com status APROVADO ou REPROVADO (`VistoriaRN.consultaVistoriasPorLicenciamentoAprovadaReprovadas` retorna lista não vazia).
2. A última vistoria encerrada e a vistoria solicitada atualmente são do mesmo `TipoVistoria`.
3. Não existe APPCI emitido **após** a data da última vistoria encerrada (`appciRN.consultaUltimoAppci` → `appci.dataHoraEmissao.after(ultimaVistoria.ctrDthInc)` retorna falso ou appci é nulo).

Caso a condição (3) seja verdadeira (APPCI posterior à última vistoria), taxa é 100%.

### RN-095 — Compensação na TAXA_REANALISE

**Implementado em:** `BoletoLicenciamentoRN.getValorTaxaReanalise` e `getValorCompensacao`

Algoritmo:
1. Calcular `valorBase = TAXA_ANALISE` atual.
2. Verificar `isencaoTaxaReanaliseRN.possuiIsencaoReanalise(lic.getId())`.
3. `valorReanalise = possuiIsencao ? BigDecimal.ZERO : valorBase × 0.5`.
4. Buscar boleto anterior PAGO mais recente: `getBoletoAnterior` — filtra `BoletoLicenciamentoED` por licenciamento e `situacao = PAGO`, ordena por `boleto.id DESC`, pega o primeiro.
5. Se `qtdUPF_atual > qtdUPF_boletoAnterior`: `compensacao = (qtdUPF_atual - qtdUPF_anterior) × valorUPF`.
6. Resultado: `valorReanalise + compensacao`.

Retrocompatibilidade: se `boletoAnterior.quantidadeTotalUpf == null` (emissão antes da implementação da regra), preencher com `qtdUPF_atual` e persistir via `this.altera(boleto)`.

### RN-096 — Regra dos 50% para TAXA_RENOVACAO

**Implementado em:** `BoletoLicenciamentoRN.getValorTaxaRenovacao`

Aplica 50% quando a **última vistoria encerrada** para o licenciamento (`VistoriaRN.consultaUltimaVistoriaEncerrada`) teve `StatusVistoria = REPROVADO`. Caso contrário (aprovada ou sem vistoria anterior), taxa é 100%.

### RN-097 — Geração do Nosso Número e Seu Número

**Implementado em:** `BoletoRN.getNossoNumero` e `BoletoRN.getSeuNumero`

```java
// getNossoNumero
protected BigInteger getNossoNumero(long numeroBase) {
    long numero = BoletoUtils.truncaNumero(numeroBase, 8); // 8 dígitos menos significativos
    int dv = BoletoUtils.getDv((int) numero);              // DV módulo 11
    numero = (numero * 100) + dv;
    return BigInteger.valueOf(numero);
}

// getSeuNumero — chamado com ID do boleto já persistido
private String getSeuNumero(BoletoED boletoED) {
    return boletoED.getId().toString()
        + (TipoOrigemBoleto.INSTRUTOR.equals(boletoED.getOrigem()) ? "C" : "L");
}
```

O nosso número é gerado **após** o `inclui(boletoED)` (o ID já existe no Oracle via sequence) e atualizado via `altera(boletoED)`.

### RN-098 — Prazo de Vencimento do Boleto

**Implementado em:** `BoletoRN.getDataVencimento`

```java
private Calendar getDataVencimento() {
    GregorianCalendar gregorianCalendar = new GregorianCalendar(TimeZone.getTimeZone("GMT-03:00"));
    // Exceção histórica — não replicar:
    if (gregorianCalendar.get(Calendar.MONTH) == Calendar.JANUARY
            && gregorianCalendar.get(Calendar.YEAR) == 2024) {
        gregorianCalendar.set(2024, Calendar.JANUARY, 31);
        return gregorianCalendar;
    }
    gregorianCalendar.add(Calendar.DAY_OF_MONTH, 30);
    return gregorianCalendar;
}
```

Prazo padrão: **30 dias corridos** a partir da data de emissão, no fuso `GMT-03:00`.

### RN-099 — Desnormalização dos Dados do Pagador

**Implementado em:** `BoletoRN.buildBoletoEDLicenciamento`

No momento da geração, copiar para `BoletoED`:
- `nomePagador`, `cpfPagador` ou `cnpjPagador` (conforme `TipoResponsavelPagamento`).
- Endereço formatado: `"{logradouro}, {número} / {complemento}, {bairro}"` (complemento omitido se nulo).
- `cidadePagador`, `ufPagador`, `cepPagador`.

Para `PROPRIETARIO_PJ`: o endereço é buscado pelo CPF do **procurador** (não do CNPJ da empresa); `cnpjPagador` recebe o CNPJ da empresa, `cpfPagador` fica nulo.

Para PF (RT, RU, PROPRIETARIO_PF): `cpfPagador` recebe o CPF, `cnpjPagador` fica nulo.

O endereço do pagador é obtido via `EnderecoUsuarioRN.listarEnderecosUsuario` — preferência por `TipoEndereco.COMERCIAL`; caso não exista, usa o primeiro da lista.

### RN-100 — Seleção do Beneficiário por Município IBGE

**Implementado em:** `BoletoLicenciamentoRN.registrarBoleto` via `CidadeRN.consultaPorNroMunicipioIBGE`

O beneficiário é obtido pelo campo `localizacao.nroMunicipioIBGE` do licenciamento. A cidade retornada possui referência ao `BeneficiarioED` correspondente àquele município.

### RN-101 — Integração com PROCERGS/Banrisul para Registro do Boleto

**Implementado em:** `BoletoIntegracaoProcergs.registrarBoleto`

Fluxo de integração:
1. Montar XML do título Banrisul (JAXB — `RegistrarTitulo` / `Dados` / `Titulo` / `Pagador` / `Beneficiario`).
2. Serializar XML, codificar em Base64 e encapsular em JSON `{"conteudo": "<base64>"}`.
3. Assinar com **HMAC-SHA256** (nimbus-jose-jwt) e criptografar com **JWE** usando chave simétrica (`DirectEncrypter`, `AES256GCM`).
4. Realizar `POST` HTTP para `PropriedadesEnum.INTEGRACAO_BOLETO_BANRISUL_URL_VIA_PROCERGS`.
5. Receber resposta JSON, decodificar Base64, desserializar XML de retorno Banrisul.
6. Extrair `codigoBarras` e `linhaDigitavel` do XML de retorno e persistir no `BoletoED`.

Código de retorno PROCERGS `3` indica erro — `throw BoletoIntegracaoException`.

Em caso de falha: `logBoletoRN.incluirErro(...)` e relançar como `WebApplicationRNException(HTTP 500, "integracao.boleto.registrar.erro")`.

Em caso de sucesso: `logBoletoRN.incluirSucesso(...)`.

### RN-102 — Marco de Auditoria na Geração do Boleto

**Implementado em:** `BoletoLicenciamentoRN.incluiMarco`

Após geração com sucesso, registrar marco com `TipoResponsavelMarco.CIDADAO`:

| `TipoBoleto` | `TipoMarco` registrado |
|---|---|
| `TAXA_VISTORIA` | `BOLETO_VISTORIA` |
| `TAXA_RENOVACAO` | `BOLETO_VISTORIA_RENOVACAO_PPCI` |
| Demais (`TAXA_ANALISE`, `TAXA_REANALISE`, `TAXA_UNICA`) | `BOLETO_ATEC` |

Texto complementar do marco: valor nominal do boleto formatado em R$ (via `NumberFormatter.formataComRetornoVazio`).

### RN-103 — Download do PDF do Boleto

**Implementado em:** `BoletoLicenciamentoRN.downloadBoleto` → `BoletoRN.gerarPdfBoletoLicenciamento`

Validações:
1. Verificar que o `BoletoLicenciamentoED` pertence ao licenciamento informado (busca por `idBoletoLicenciamento` E `idLicenciamento`). Se não encontrado → `WebApplicationRNException(HTTP 404)`.
2. Se `boleto.situacao == VENCIDO` → `WebApplicationRNException(HTTP 400, "boleto.licenciamento.VENCIDO")`.

Geração do PDF: `FacadeReport.gerarPDF("/reports/boleto.jasper", boletoDTOLicenciamento)`.

Campos do `BoletoDTO` para licenciamento:
- `nossoNumero` = ID com padding de zeros à esquerda (10 dígitos)
- `vencimento`, `valorNominal` (formatado `R$ #,##0.00`), `especie.siglaBoleto`, `emissao`
- `codigoBarras`, `linhaDigitavel` (formatado por `AplicacaoUtil.formatBarCode`)
- `beneficiarioCodigo` = `codigo.substring(codigo.indexOf('.') + 1)`
- `beneficiarioPessoa`, `beneficiarioCpfCnpj`, `beneficiarioNome`, `beneficiarioNomeFantasia`, `beneficiarioAgencia`, `beneficiarioEndereco`, `beneficiarioCidade`, `beneficiarioUf`, `beneficiarioCep`
- `usuarioNome`, `usuarioCpfCnpj` = `cpfPagador` se não vazio, senão `cnpjPagador` (formatado por `AplicacaoUtil.formatDocument`)
- `usuarioEndereco`, `usuarioCidade`, `usuarioUf`, `usuarioCep` = campos desnormalizados do `BoletoED`
- `aceite = "N"`
- `logoBanrisul` = caminho do classpath `reports/img/banrisul-logo.jpg`

### RN-104 — Job de Vencimento de Boletos

**Implementado em:** `BoletoSituacaoBatchRN.atualizaSituacao`

```java
@Schedule(hour = "12/12", info = "Verificação de situação de boletos executada 12:00 e 24:00",
          persistent = false)
public void atualizaSituacao() {
    Calendar dataLimiteVencimento = calculaDataLimiteVencimento();
    // Busca todos BoletoED com situacao=EM_ABERTO e dataVencimento <= dataLimite
    List<BoletoED> boletos = boletoRN.lista(
        BuilderBoletoED.of().dataVencimento(dataLimiteVencimento)
                            .situacao(SituacaoBoleto.EM_ABERTO).instance());
    boletos.forEach(boleto -> {
        boleto.setSituacao(SituacaoBoleto.VENCIDO);
        boletoRN.altera(boleto);
    });
}

private Calendar calculaDataLimiteVencimento() {
    ParametroBoletoED param = parametroBoletoRN.consultarPorChave(
        ParametrosBoleto.NUMERO_DIAS_VENCIMENTO_BOLETO.getChave()); // "numero.dias.situacao.vencimento"
    int dias = param != null ? Integer.valueOf(param.getValor()) : 2; // default 2
    return DataUtil.somarDias(AplicacaoUtil.removeTime(dataAtualHelper.getDataAtual()), -dias);
}
```

Execução: `@Schedule(hour = "12/12")` — a cada 12 horas (00:00 e 12:00). `persistent = false`.

### RN-105 — Job de Confirmação de Pagamento (CNAB 240)

**Implementado em:** `EJBTimerService.verificaPagamentoBanrisul` + `PagamentoBoletoRN.processaRetorno` + `ParserCnab240`

```java
@Schedule(minute = "0", hour = "*/12", persistent = false)
public void verificaPagamentoBanrisul() {
    String caminhoOrigem  = PropriedadesEnum.CAMINHO_ARQUIVO_ENTRADA_BANRISUL.getVal();
    String caminhoDestino = PropriedadesEnum.CAMINHO_ARQUIVO_PROCESSADOS_BANRISUL.getVal();
    // ...
}
```

Algoritmo detalhado:
1. Validar existência dos diretórios `caminhoOrigem` e `caminhoDestino` (lançar `RuntimeException` se nulos ou inexistentes).
2. Listar todos os arquivos em `caminhoOrigem`.
3. Para cada arquivo:
   a. Se tamanho = 0 bytes → mover para destino e continuar.
   b. Ler todas as linhas do arquivo via `Scanner`.
   c. Invocar `ParserCnab240.processaLinhasArquivo(linhas, nomeArquivo)` → `List<RetornoPagamentoBanrisulDTO>`.
   d. Para cada `RetornoPagamentoBanrisulDTO`:
      - Invocar `PagamentoBoletoRN.processaRetorno(nomeArquivo, retorno, erros)` **em nova transação** (`@TransactionAttribute(REQUIRES_NEW)`).
   e. Mover arquivo para `caminhoDestino` se não houve erros novos.
4. Se a lista `erros` não estiver vazia → `EmailService.enviarEmailErro(erros)`.

### RN-106 — Processamento de Registro CNAB Liquidado

**Implementado em:** `PagamentoBoletoRN.processaRetorno`

```java
private static final String COD_MOVIMENTO_LIQUIDACAO = "06";

@TransactionAttribute(TransactionAttributeType.REQUIRES_NEW)
public void processaRetorno(String nomeArquivoRetorno, RetornoPagamentoBanrisulDTO retorno, List<String> erros) {
    if (!COD_MOVIMENTO_LIQUIDACAO.equals(retorno.getCodMovimento())) {
        return; // ignora registros que não são liquidação
    }
    BoletoED boletoED = buscaBoleto(retorno, nomeArquivoRetorno);
    liquidaBoleto(retorno, boletoED, nomeArquivoRetorno);
    // despacha pós-pagamento por origem:
    switch (boletoED.getOrigem()) {
        case INSTRUTOR:
            instrutorRN.atualizaStatusAposBoletoPago(boletoED, true); break;
        case RENOVACAO_INSTRUTOR:
            instrutorRN.atualizaStatusAposBoletoPago(boletoED, false); break;
        case FACT:
            pagamentoBoletoFactRN.processaPagamentoFact(boletoED.getId()); break;
        case LICENCIAMENTO:
            pagamentoBoletoLicenciamentoRN.atualizaStatusAposBoletoPago(boletoED.getId()); break;
    }
}

private void liquidaBoleto(RetornoPagamentoBanrisulDTO retorno, BoletoED boletoED, String nomeArquivoRetorno) {
    pagamentoBoletoRNVal.validar(retorno, boletoED, nomeArquivoRetorno);
    // validar: valorPago == valorNominal; situacao != PAGO (senão RuntimeException)
    boletoED.setDataPagamento(retorno.getDtPagamento());
    boletoED.setSituacao(SituacaoBoleto.PAGO);
    boletoED.setNomeArquivoRetorno(nomeArquivoRetorno);
    boletoRN.altera(boletoED);
}
```

Busca por `nossoNumero`: `boletoRN.lista(BuilderBoletoED.of().nossoNumero(new BigInteger(retorno.getNossoNumero())).instance())`. Se não encontrado ou duplicado → `RuntimeException` adicionada à lista de erros.

### RN-107 — Validações do Retorno Bancário

**Implementado em:** `PagamentoBoletoRNVal.validar`

1. **Valor pago ≠ valor nominal:** `boletoED.valorNominal.doubleValue() != retorno.valorPago.doubleValue()` → lançar `RuntimeException` com mensagem detalhada contendo os dois valores formatados.
2. **Boleto já pago:** `boletoED.situacao == PAGO` → lançar `RuntimeException` com mensagem de rejeição (idempotência por exceção, não silenciosa).

### RN-108 — Atualização de Estado do Licenciamento Após Pagamento

**Implementado em:** `PagamentoBoletoLicenciamentoRN.atualizaStatusAposBoletoPago`

Busca `BoletoLicenciamentoED` pelo `idBoleto`. Se não encontrado para o licenciamento → retorna `false` (erro registrado pelo chamador). Caso contrário, decide transição por `situacaoAtual × tipoBoleto`:

| `SituacaoLicenciamento` atual | `TipoBoleto` | `TrocaEstadoLicenciamentoEnum` invocada | `TipoMarco` registrado |
|---|---|---|---|
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`/`TAXA_REANALISE` (PSPCIM, endereço novo) | `AGUARDANDO_PAGAMENTO_PARA_ANALISE_ENDERECO_PENDENTE` | `LIQUIDACAO_TAXA_UNICA` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`/`TAXA_REANALISE` (PSPCIM, geral) | `AGUARDANDO_PAGAMENTO_PARA_AGUARDANDO_DISTRIBUICAO` | `LIQUIDACAO_TAXA_UNICA` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`/`TAXA_REANALISE` (PPCI, endereço novo) | `AGUARDANDO_PAGAMENTO_PARA_ANALISE_ENDERECO_PENDENTE` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`/`TAXA_REANALISE` (PPCI, inviabilidade pendente) | `AGUARDANDO_PAGAMENTO_PARA_ANALISE_INVIABILIDADE_PENDENTE` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE`/`TAXA_REANALISE` (PPCI, geral) | `AGUARDANDO_PAGAMENTO_PARA_AGUARDANDO_DISTRIBUICAO` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO_VISTORIA` | `TAXA_VISTORIA` | `AGUARDANDO_PAGAMENTO_VISTORIA_PARA_AGUARDANDO_DISTRIBUICAO_VISTORIA` | `LIQUIDACAO_VISTORIA` |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | `TAXA_RENOVACAO` | `AGUARDANDO_PAGAMENTO_VISTORIA_RENOVACAO_PARA_AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` | `LIQUIDACAO_VISTORIA_RENOVACAO` |

"Endereço novo" → `LicenciamentoEnderecoNovoHelper.isEnderecoNovo(licenciamento)`.
"Inviabilidade pendente" → `MedidaSegurancaRN.existeMedidaSegurancaComInviabilidadeTecnicaSemAprovacao(licenciamento)`.

Responsável do marco: `TipoResponsavelMarco.SISTEMA`. Texto complementar: valor nominal formatado em R$.

Idempotência: se `SituacaoLicenciamento` atual não é nenhum dos `AGUARDANDO_PAGAMENTO*`, retorna `true` sem alterar nada.

---

## S4 — Endpoints JAX-RS

Classe: **`LicenciamentoRest`** (`@Path("/licenciamentos")`)

### 4.1 Gerar Boleto

```
POST /licenciamentos/{idLic}/pagamentos/boleto/
Content-Type: application/json
Authorization: Bearer {token SOE PROCERGS}
Anotação de segurança: @AutorizaEnvolvido

Body:
{
  "tipo": "TAXA_ANALISE",
  "id": null,
  "responsavel": {
    "tipo": "RT",
    "cpfCnpj": "12345678901",
    "nome": "João da Silva",
    "cpfProcurador": null
  }
}
```

Implementação:
```java
@POST
@Path("/{idLic}/pagamentos/boleto/")
@AutorizaEnvolvido
public Response gerarBoleto(
        @PathParam("idLic") final Long idLicenciamento,
        final BoletoLicenciamento boletoLicenciamento) {
    return Response.status(Response.Status.CREATED)
        .entity(boletoLicenciamentoRN.gerarBoleto(idLicenciamento, boletoLicenciamento))
        .build();
}
```

**Response 201:** `BoletoLicenciamento` serializado em JSON com:
- `id` (ID do `BoletoLicenciamentoED`)
- `boleto.id`, `boleto.nossoNumero`, `boleto.codigoBarras`, `boleto.linhaDigitavel`, `boleto.dataVencimento`, `boleto.valorNominal`, `boleto.situacao`

**Erros:** `400` (RN-090, RN-092, RN-093), `403` (não envolvido), `500` (falha PROCERGS/Banrisul).

### 4.2 Download PDF do Boleto

```
GET /licenciamentos/{idLic}/pagamentos/boleto/{idBoletoLic}
Accept: application/octet-stream
Authorization: Bearer {token SOE}
Anotação de segurança: @AutorizaEnvolvido
```

```java
@GET
@Path("/{idLic}/pagamentos/boleto/{idBoletoLic}")
@Produces("application/octet-stream")
@AutorizaEnvolvido
public Response downloadBoleto(
        @PathParam("idLic") final Long idLicenciamento,
        @PathParam("idBoletoLic") final Long idBoletoLic) {
    return Response.ok(
        boletoLicenciamentoRN.downloadBoleto(idLicenciamento, idBoletoLic)).build();
}
```

**Response 200:** stream binário PDF. **Erros:** `400` boleto VENCIDO, `404` não encontrado.

### 4.3 Listar Pagamentos do Licenciamento

```
GET /licenciamentos/{idLic}/pagamentos
Authorization: Bearer {token SOE}
Anotação: @AutorizaEnvolvido
```

**Response 200:** `List<BoletoLicenciamento>` — todos os boletos vinculados ao licenciamento.

### 4.4 Listar Responsáveis para Pagamento

```
GET /licenciamentos/{idLic}/reponsaveis-pagamento
Authorization: Bearer {token SOE}
Anotação: @AutorizaEnvolvido
```

**Response 200:** `List<ResponsavelPagamentoDTO>` — RTs (filtrados por fase de execução quando `TipoFaseLicenciamento.EXECUCAO`), RUs e Proprietários, deduplicados por CPF/CNPJ, ordenados por nome.

```java
// ResponsavelPagamentoDTO:
{
  "tipo": "RT",          // TipoResponsavelPagamento
  "cpfCnpj": "...",
  "nome": "...",
  "cpfProcurador": null  // preenchido apenas para PROPRIETARIO_PJ
}
```

### 4.5 Listar Responsáveis para Pagamento de Renovação

```
GET /licenciamentos/{idLic}/reponsaveis-pagamento-renovacao
Authorization: Bearer {token SOE}
Anotação: @AutorizaEnvolvido
```

**Response 200:** Mesma estrutura, mas RTs filtrados apenas com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI`.

### 4.6 Endpoint Administrativo: Verificação Manual de Pagamento

```
GET /admin/verificar-pagamento-banrisul
Authorization: Bearer {token SOE — perfil ADMIN}
Servlet: VerificaPagamentoBanrisulServlet
```

Permite ao administrador acionar manualmente a verificação de retorno bancário fora do ciclo do job.

---

## S5 — Segurança

### 5.1 Autenticação

- Todos os endpoints exigem token do **SOE PROCERGS** (meu.rs.gov.br).
- O identificador do usuário no sistema é `idUsuarioSoe Long` — obtido do token via CDI `@SessionScoped`.
- O interceptor `@SegurancaEnvolvidoInterceptor` (aplicado via anotação na classe `BoletoLicenciamentoRN`) verifica que o usuário autenticado é um dos envolvidos no licenciamento antes de executar operações sensíveis.
- A anotação `@AutorizaEnvolvido` no JAX-RS garante a mesma verificação no nível do endpoint REST.

### 5.2 Controle de Permissões (RBAC)

| Operação | Anotação `@Permissao` | Objeto / Ação |
|---|---|---|
| Gerar boleto | `@Permissao(objeto = "PAGAMENTOS", acao = "INCLUIR")` | `BoletoLicenciamentoRN.gerarBoleto` |
| Excluir boleto por licenciamento | `@Permissao(objeto = "PAGAMENTOS", acao = "EXCLUIR")` | `BoletoLicenciamentoRN.excluirPorLicenciamento` |
| Listar relatório de arrecadação | `@Permissao(objeto = "VALORESARRECADADOS", acao = "CONSULTAR")` | `BoletoRN.listarRelatorio` / `listarCSV` |
| Job de confirmação | `@Permissao(desabilitada = true)` | `PagamentoBoletoRN` — sem verificação de permissão |
| Job de vencimento | `@Permissao(desabilitada = true)` | `BoletoSituacaoBatchRN` |

---

## S6 — Integração Bancária (PROCERGS / Banrisul)

### 6.1 Fluxo de Registro do Boleto

```
BoletoLicenciamentoRN
    └── BoletoRN.registrarBoletoLicenciamento
            └── BoletoRN.registraBoleto
                    └── BoletoIntegracaoProcergs.registrarBoleto
                            1. Montar XML Banrisul (JAXB)
                            2. Base64 + JSON {"conteudo": "<base64>"}
                            3. Assinar HMAC-SHA256 (nimbus-jose-jwt)
                            4. Criptografar JWE AES-256-GCM
                            5. POST HTTP para PropriedadesEnum.INTEGRACAO_BOLETO_BANRISUL_URL_VIA_PROCERGS
                            6. Deserializar resposta JSON → Base64 → XML retorno Banrisul
                            7. Extrair codigoBarras e linhaDigitavel
                            8. Retornar BoletoED atualizado
```

### 6.2 Propriedades de Configuração (PropriedadesEnum)

| Constante `PropriedadesEnum` | Descrição |
|---|---|
| `INTEGRACAO_BOLETO_BANRISUL_URL_VIA_PROCERGS` | URL do serviço intermediário PROCERGS |
| `CAMINHO_ARQUIVO_ENTRADA_BANRISUL` | Diretório de entrada dos arquivos CNAB 240 |
| `CAMINHO_ARQUIVO_PROCESSADOS_BANRISUL` | Diretório de destino após processamento |
| `EMAIL_DESTINATARIO_ERRO_JOB` | E-mail do destinatário de alertas de falha no job |
| `AMBIENTE` | Identificador do ambiente (dev/hom/prod) — usado no corpo do e-mail de erro |
| `INTEGRACAO_WORKLOAD_ATIVA` | Boolean — quando `"true"`, todos os jobs `@Schedule` são abortados no início |

### 6.3 Modelo XML Banrisul (JAXB)

O XML de envio é composto pelos elementos do pacote `com.procergs.solcbm.boleto.integracao.banrisul.model`:

| Classe | Elemento XML | Descrição |
|---|---|---|
| `Dados` | `<Dados>` | Raiz do XML de retorno do Banrisul |
| `Titulo` | `<Titulo>` | Dados do título (nosso número, vencimento, valor, espécie) |
| `Pagador` | `<Pagador>` | Dados do pagador (nome, CPF/CNPJ, endereço) |
| `Beneficiario` | `<Beneficiario>` | Dados do beneficiário (código, nome, agência) |
| `Instrucoes` | `<Instrucoes>` | Instruções de cobrança |
| `Juros` | `<Juros>` | Taxa de juros após vencimento |
| `PagParcial` | `<PagParcial>` | Controle de pagamento parcial |
| `Ocorrencia` | `<Ocorrencia>` | Códigos de ocorrência CNAB |

### 6.4 Parser CNAB 240

Classe: `ParserCnab240` (pacote `com.procergs.solcbm.boleto.integracao.banrisul.arquivo`).

Responsável por ler as linhas do arquivo de retorno Banrisul no formato CNAB 240 e retornar `List<RetornoPagamentoBanrisulDTO>` com os campos:
- `codMovimento` — código do movimento (ex: `"06"` para liquidação)
- `nossoNumero` — número do boleto gerado pelo SOL
- `dtPagamento` — data de pagamento no banco
- `valorPago` — valor pago

---

## S7 — Relatório de Arrecadação

**Implementado em:** `BoletoRN.listarRelatorio` (PDF) e `BoletoRN.listarCSV`

Requer permissão `VALORESARRECADADOS:CONSULTAR`.

### 7.1 Parâmetros da Pesquisa

| Campo | Tipo | Restrição |
|---|---|---|
| `dataInicio` | `Date` | — |
| `dataFim` | `Date` | Máximo 31 dias de intervalo após `dataInicio` |
| `tipoOrigem` | String | `"0"` a `"6"` conforme tabela abaixo |

| Código `tipoOrigem` | Descrição |
|---|---|
| `"0"` | Instrutor |
| `"1"` | Licenciamento |
| `"2"` | PPCI |
| `"3"` | PSPCIM |
| `"4"` | PSPCIB |
| `"5"` | CLCB |
| `"6"` | Evento Temporário |

### 7.2 Estrutura do Retorno

| Campo DTO | Coluna Oracle (consulta nativa) | Descrição |
|---|---|---|
| `nroBatalhao` | aux[0] `BigDecimal` | Número do batalhão |
| `descricaoBatalhao` | aux[1] `String` | Nome do batalhão |
| `cidadeResponsavelRecadacao` | aux[2] `String` | Cidade do responsável pela arrecadação |
| `cidadeResponsavelTotal` | aux[3] `String` | Total da cidade responsável |
| `cidadeOrigem` | aux[4] `String` | Cidade de origem do licenciamento |
| `qTDBoleto` | aux[6] `BigDecimal` | Quantidade de boletos |
| `valorArrecadadoResponsavel` | aux[7] `BigDecimal` | Valor arrecadado pelo responsável |
| `valorRecadacao` | aux[8] `BigDecimal` | Valor total de arrecadação |
| `valorRecadadoBatalhao` | aux[9] `BigDecimal` | Valor arrecadado pelo batalhão |

Montante total (`WrapperRelatorioPesquisaDTO.montante`) = soma dos `valorRecadacao` de todos os registros.

Intervalo inválido (> 31 dias): log de erro, retorna `null`.

---

## S8 — Estrutura de Camadas

```
JAX-RS (REST)
  LicenciamentoRest              @Path("/licenciamentos")
    └── POST /{idLic}/pagamentos/boleto/
    └── GET  /{idLic}/pagamentos/boleto/{idBoletoLic}
    └── GET  /{idLic}/pagamentos
    └── GET  /{idLic}/reponsaveis-pagamento
    └── GET  /{idLic}/reponsaveis-pagamento-renovacao

EJB @Stateless (Regras de Negócio)
  BoletoLicenciamentoRN          — orquestração P11-A (gerarBoleto, downloadBoleto, listaPorLicenciamento)
  BoletoRN                       — CRUD BoletoED, nosso número, PDF, relatório arrecadação
  LicenciamentoResponsavelPagamentoRN — lista responsáveis para pagamento
  PagamentoBoletoLicenciamentoRN — transição de estado após pagamento (P11-B)
  PagamentoBoletoRN              — processamento de retorno CNAB (dispatch por origem)
  BoletoSituacaoBatchRN          — job @Schedule de vencimento de boletos
  ValorUPFRN                     — leitura do valor da UPF

EJB @Singleton @Startup
  EJBTimerService                — jobs @Schedule: verificaPagamentoBanrisul (12h), notificações (00:01), faturamento (1º do mês)

Validação
  BoletoLicenciamentoRNVal       — validações de situação e boleto anterior
  PagamentoBoletoRNVal           — validações do retorno CNAB

Integração
  BoletoIntegracaoProcergs       — registro do boleto via PROCERGS/Banrisul (REST + JWT/JWE + XML JAXB)
  ParserCnab240                  — parse de arquivo CNAB 240 de retorno bancário

DAO
  BoletoBD                       — queries Oracle para BoletoED
  BoletoLicenciamentoBD          — queries Oracle para BoletoLicenciamentoED
  ParametroBoletoBD              — queries Oracle para ParametroBoletoED
  LogGeraBoletoBD                — inserção de log de geração de boleto

Entidades (JPA)
  BoletoED                       — CBM_BOLETO / CBM_ID_BOLETO_SEQ
  BoletoLicenciamentoED          — CBM_BOLETO_LICENCIAMENTO / CBM_ID_BOLETO_LICENC_SEQ
  BeneficiarioED                 — CBM_BENEFICIARIO
  ParametroBoletoED              — CBM_PARAMETRO_BOLETO / CBM_ID_PARAMETRO_BOLETO_SEQ
  LogGeraBoletoED                — CBM_LOG_GERA_BOLETO
```

---

## S9 — Notificações por E-mail

**Implementado em:** `EJBTimerService.enviarEmailErro` via `EmailService`

Quando o job de confirmação CNAB encontra erros ao processar registros:
- Assunto: `"Sistema SOLCBM - Arquivo de retorno do Banrisul com problemas"`
- Corpo HTML com data/hora formatada (`dd/MM/yyyy HH:mm:ss`), ambiente (`PropriedadesEnum.AMBIENTE`) e lista de erros.
- Destinatário: `PropriedadesEnum.EMAIL_DESTINATARIO_ERRO_JOB`.

Chamada:
```java
emailService.destinatarios(PropriedadesEnum.EMAIL_DESTINATARIO_ERRO_JOB.getVal())
            .assunto(assunto).mensagem(mensagem).enviar();
emailService.clearEmail();
```

---

## S10 — Controle de Execução dos Jobs (WorkloadGuard)

**Implementado em:** `PropriedadesEnum.INTEGRACAO_WORKLOAD_ATIVA`

Todos os métodos `@Schedule` do `EJBTimerService` verificam a propriedade `INTEGRACAO_WORKLOAD_ATIVA` no início:

```java
if (Boolean.valueOf(PropriedadesEnum.INTEGRACAO_WORKLOAD_ATIVA.getVal())) {
    logger.info("Integracao Workload ainda está ativa — abortando job.");
    return;
}
```

Quando `"true"`, nenhum job é executado. Isso permite desabilitar os jobs durante a transição de ambiente sem redeployment. Quando migração completa, o `if` pode ser removido.

---

## S11 — Máquina de Estados do Boleto

```
[Criado]
    │
    ▼
EM_ABERTO ──── Job 12h (dataVencimento + N dias) ────► VENCIDO
    │
    └─── Retorno CNAB código "06" (liquidação) ────► PAGO
```

- `EM_ABERTO → VENCIDO`: job `BoletoSituacaoBatchRN.atualizaSituacao` — marcação em lote.
- `EM_ABERTO → PAGO`: job `EJBTimerService.verificaPagamentoBanrisul` — via arquivo CNAB 240.
- `VENCIDO → PAGO`: **não previsto** — se o cidadão pagar um boleto vencido, o arquivo CNAB chegará, mas `PagamentoBoletoRNVal.validarSituacaoPaga` verificará somente se já está PAGO, não se está VENCIDO. O sistema aceitará o pagamento de boleto VENCIDO (sem rejeição por situação).

---

## S12 — Rastreabilidade de Requisitos

| ID | Classe / Método no código-fonte | Descrição |
|---|---|---|
| RN-090 | `BoletoLicenciamentoRNVal.validaSituacaoLicenciamento` | Pré-condição de situação do licenciamento |
| RN-091 | `BoletoLicenciamentoRN.gerarBoleto` (bloco `TipoSituacaoIsencao.SOLICITADA`) | Cancelamento automático de isenção solicitada |
| RN-092 | `BoletoLicenciamentoRN.validarBoletoVencido` + `BoletoLicenciamentoRNVal.validaSituacaoBoletoAnteriorParaPagador` | Verificação de boleto vigente anterior |
| RN-093 | `BoletoLicenciamentoRN.getValorTaxa` | Cálculo do valor por tipo de boleto |
| RN-094 | `BoletoLicenciamentoRN.devePagarMeiaTaxaDeVistoria` | Regra dos 50% para taxa de vistoria |
| RN-095 | `BoletoLicenciamentoRN.getValorTaxaReanalise` + `getValorCompensacao` | Compensação na reanálise |
| RN-096 | `BoletoLicenciamentoRN.getValorTaxaRenovacao` | Regra dos 50% para taxa de renovação |
| RN-097 | `BoletoRN.getNossoNumero` / `BoletoRN.getSeuNumero` | Geração de nosso número e seu número |
| RN-098 | `BoletoRN.getDataVencimento` | Prazo de 30 dias e fuso GMT-03:00 |
| RN-099 | `BoletoRN.buildBoletoEDLicenciamento` | Desnormalização dos dados do pagador |
| RN-100 | `BoletoLicenciamentoRN.registrarBoleto` via `CidadeRN.consultaPorNroMunicipioIBGE` | Seleção do beneficiário por município IBGE |
| RN-101 | `BoletoIntegracaoProcergs.registrarBoleto` | Integração REST JWT/JWE PROCERGS/Banrisul |
| RN-102 | `BoletoLicenciamentoRN.incluiMarco` | Marco de auditoria na geração |
| RN-103 | `BoletoLicenciamentoRN.downloadBoleto` + `BoletoRN.gerarPdfBoletoLicenciamento` | Download do PDF do boleto |
| RN-104 | `BoletoSituacaoBatchRN.atualizaSituacao` @Schedule 12h | Job de vencimento de boletos |
| RN-105 | `EJBTimerService.verificaPagamentoBanrisul` @Schedule 12h | Job de confirmação CNAB 240 |
| RN-106 | `PagamentoBoletoRN.processaRetorno` (`COD_MOVIMENTO_LIQUIDACAO = "06"`) | Processamento de registro CNAB liquidado |
| RN-107 | `PagamentoBoletoRNVal.validar` | Validações do retorno bancário (valor + duplicidade) |
| RN-108 | `PagamentoBoletoLicenciamentoRN.atualizaStatusAposBoletoPago` | Transição de estado do licenciamento após pagamento |
