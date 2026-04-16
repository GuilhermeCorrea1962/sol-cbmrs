# Requisitos P11 — Pagamento e Geração de Boleto
## Stack Java Moderna — Sem Dependência PROCERGS

> Documento de requisitos destinado à equipe de desenvolvimento.
> Stack-alvo: **Spring Boot 3.x · Spring Security · Keycloak (OIDC/OAuth2) · PostgreSQL · Spring Scheduler · Jakarta EE 10 APIs**.
> Nenhuma dependência do SOE PROCERGS, WildFly ou CNAB PROCERGS — todas as responsabilidades equivalentes
> são mapeadas para tecnologias de mercado abertas.

---

## S1 — Visão Geral do Processo

O processo P11 cobre o ciclo completo de **geração, disponibilização e confirmação de pagamento de boleto bancário** vinculado a um licenciamento do SOL. É um processo transversal: é disparado sempre que um licenciamento atinge um dos estados `AGUARDANDO_PAGAMENTO`, `AGUARDANDO_PAGAMENTO_VISTORIA` ou `AGUARDANDO_PAGAMENTO_RENOVACAO`.

### Atores

| Ator | Papel |
|---|---|
| **Cidadão / RT / Proprietário** | Solicita a geração do boleto e efetua o pagamento fora do sistema |
| **Sistema — API** | Calcula o valor da taxa, integra com o gateway bancário, persiste o boleto |
| **Sistema — Job de Vencimento** | Executa a cada 12 horas e marca boletos expirados como VENCIDO |
| **Sistema — Job de Confirmação** | Executa a cada 12 horas; processa o arquivo de retorno bancário CNAB 240, confirma pagamentos liquidados e avança o estado do licenciamento |
| **Banco (Banrisul / substituto)** | Registra o boleto e disponibiliza arquivo de retorno CNAB 240 com eventos de liquidação |

### Subprocessos

O P11 divide-se em dois subprocessos:

| Subprocesso | Gatilho | Responsável |
|---|---|---|
| **P11-A — Geração de Boleto** | Chamada da API pelo frontend quando licenciamento está em AGUARDANDO_PAGAMENTO* | Sistema API |
| **P11-B — Confirmação de Pagamento** | Execução do job CNAB 240 ou chamada administrativa manual | Sistema Job |

### Tipos de Boleto

| `TipoBoleto` | Situação do Licenciamento | Descrição |
|---|---|---|
| `TAXA_ANALISE` | `AGUARDANDO_PAGAMENTO` | Taxa de análise técnica (PPCI) |
| `TAXA_REANALISE` | `AGUARDANDO_PAGAMENTO` | Taxa de reanálise (50% + compensação por UPF) |
| `TAXA_VISTORIA` | `AGUARDANDO_PAGAMENTO_VISTORIA` | Taxa de vistoria presencial |
| `TAXA_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` | Taxa de renovação (baseada em vistoria anterior) |
| `TAXA_UNICA` | `AGUARDANDO_PAGAMENTO` | Taxa única (PSPCIM) |

---

## S2 — Modelo de Dados

### 2.1 Entidade `Boleto`

Tabela: **`sol_boleto`**

```java
@Entity
@Table(name = "sol_boleto")
public class Boleto {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * Nosso número único gerado a partir do ID com dígito verificador.
     * Formato: trunca os 8 dígitos menos significativos do ID e acrescenta DV de 2 dígitos.
     * Armazenado como BIGINT.
     */
    @Column(name = "nosso_numero", nullable = false, unique = true, precision = 38)
    private BigInteger nossoNumero;

    /**
     * Número identificador externo (para o banco).
     * Formato: {id}{sufixo} — sufixo "L" para licenciamento, "C" para instrutor.
     * Max 13 caracteres.
     */
    @Column(name = "seu_numero", length = 13)
    private String seuNumero;

    /** Data de vencimento: data de emissão + 30 dias corridos (configurável via parâmetro). */
    @Column(name = "data_vencimento", nullable = false)
    private LocalDate dataVencimento;

    /** Valor nominal em R$ com 2 casas decimais. */
    @Column(name = "valor_nominal", nullable = false, precision = 19, scale = 2)
    private BigDecimal valorNominal;

    /** Espécie do documento: mapeado pelo enum TipoEspecie (ex: DUPLICATA_MERCANTIL). */
    @Column(name = "tp_especie", length = 2)
    @Enumerated(EnumType.STRING)
    private TipoEspecie especie;

    /** Data e hora de emissão (instante da chamada à API de geração). */
    @Column(name = "data_emissao", nullable = false)
    private LocalDateTime dataEmissao;

    /** Código de barras retornado pelo gateway bancário (44 dígitos). */
    @Column(name = "codigo_barras", length = 44)
    private String codigoBarras;

    /** Linha digitável retornada pelo gateway bancário (47 dígitos). */
    @Column(name = "linha_digitavel", length = 47)
    private String linhaDigitavel;

    /** Beneficiário: entidade CBM-RS cadastrada por município IBGE. Não nulo. */
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_beneficiario", nullable = false)
    private Beneficiario beneficiario;

    /**
     * Origem do boleto: discrimina o tipo de entidade pagadora.
     * Valores: LICENCIAMENTO, INSTRUTOR, FACT, RENOVACAO_INSTRUTOR.
     */
    @Column(name = "tp_origem", length = 30, nullable = false)
    @Enumerated(EnumType.STRING)
    private TipoOrigemBoleto origem;

    /**
     * Situação atual do boleto.
     * EM_ABERTO → VENCIDO (job 12h) ou EM_ABERTO → PAGO (confirmação CNAB).
     */
    @Column(name = "tp_situacao", length = 20, nullable = false)
    @Enumerated(EnumType.STRING)
    private SituacaoBoleto situacao;

    /** Data em que o banco confirmou o pagamento (preenchida via arquivo CNAB 240). */
    @Column(name = "data_pagamento")
    private LocalDate dataPagamento;

    /** Nome do arquivo CNAB 240 que originou a confirmação de pagamento. */
    @Column(name = "nome_arquivo_retorno")
    private String nomeArquivoRetorno;

    // Dados desnormalizados do pagador (copiados no momento da emissão):
    @Column(name = "nome_pagador")            private String nomePagador;
    @Column(name = "cpf_pagador",  length = 11)  private String cpfPagador;
    @Column(name = "cnpj_pagador", length = 14)  private String cnpjPagador;
    @Column(name = "endereco_pagador")        private String enderecoPagador;
    @Column(name = "cidade_pagador")          private String cidadePagador;
    @Column(name = "uf_pagador",   length = 2)   private String ufPagador;
    @Column(name = "cep_pagador",  length = 8)   private String cepPagador;

    // getters e setters omitidos
}
```

### 2.2 Entidade `BoletoLicenciamento`

Tabela: **`sol_boleto_licenciamento`** — associação N:1 entre licenciamento e boleto, com metadados do cálculo.

```java
@Entity
@Table(name = "sol_boleto_licenciamento")
public class BoletoLicenciamento {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_licenciamento", nullable = false)
    private Licenciamento licenciamento;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_boleto", nullable = false)
    private Boleto boleto;

    /**
     * Tipo do boleto vinculado ao licenciamento.
     * TAXA_ANALISE | TAXA_REANALISE | TAXA_VISTORIA | TAXA_UNICA | TAXA_RENOVACAO
     */
    @Column(name = "tp_boleto", length = 30, nullable = false)
    @Enumerated(EnumType.STRING)
    private TipoBoleto tipoBoleto;

    /**
     * Valor monetário da taxa de análise em R$ calculado no momento da emissão.
     * Nulo para TAXA_VISTORIA.
     */
    @Column(name = "valor_taxa_analise", precision = 19, scale = 2)
    private BigDecimal valorTaxaAnalise;

    /**
     * Quantidade total de UPFs utilizada no cálculo.
     * Nulo para TAXA_VISTORIA. Usado na compensação de reanálise.
     */
    @Column(name = "qtd_total_upf", precision = 19, scale = 4)
    private BigDecimal quantidadeTotalUpf;

    // getters e setters omitidos
}
```

### 2.3 Entidade `Beneficiario`

Tabela: **`sol_beneficiario`** — dados bancários do beneficiário (CBM-RS por município).

```java
@Entity
@Table(name = "sol_beneficiario")
public class Beneficiario {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Código do beneficiário no banco (ex: "0777.123456-7"). Max 20 caracteres (varchar). */
    @Column(name = "txt_codigo", length = 20, nullable = false)
    private String codigo;

    @Column(name = "nome",             nullable = false) private String nome;
    @Column(name = "nome_fantasia")                      private String nomeFantasia;
    @Column(name = "cpf_cnpj",         length = 14)     private String cpfCnpj;
    @Column(name = "agencia")                            private String agencia;
    @Column(name = "endereco")                           private String endereco;
    @Column(name = "cidade")                             private String cidade;
    @Column(name = "uf",               length = 2)       private String uf;
    @Column(name = "cep",              length = 8)       private String cep;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "id_cidade", nullable = false)
    private Cidade cidade_ibge;

    // getters e setters omitidos
}
```

### 2.4 Entidade `ParametroBoleto`

Tabela: **`sol_parametro_boleto`** — configurações editáveis pelo administrador.

| Chave | Valor padrão | Descrição |
|---|---|---|
| `upf.valor` | `19.5352` | Valor atual da UPF em R$ (Unidade Padrão Fiscal) |
| `credenciamento.profissionalempresa.valor` | `5` | Número de UPFs para credenciamento de profissional/empresa |
| `numero.dias.vencimento.boleto` | `2` | Número de dias após `dataVencimento` para marcar boleto como VENCIDO no job |

### 2.5 Enumerações

```java
public enum SituacaoBoleto { EM_ABERTO, VENCIDO, PAGO }

public enum TipoBoleto {
    TAXA_ANALISE,
    TAXA_REANALISE,
    TAXA_VISTORIA,
    SOLICITACAO_FACT,
    TAXA_UNICA,
    TAXA_RENOVACAO
}

public enum TipoOrigemBoleto {
    INSTRUTOR,
    LICENCIAMENTO,
    FACT,
    RENOVACAO_INSTRUTOR
}

public enum TipoEspecie { DUPLICATA_MERCANTIL /*, outros */ }
```

### 2.6 LogGeraBoletoBD (Auditoria)

Tabela: **`sol_log_gera_boleto`** — registra cada tentativa de geração de boleto para auditoria e diagnóstico de falhas de integração bancária.

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | BIGSERIAL | PK |
| `id_boleto` | BIGINT FK | Referência ao boleto gerado (pode ser nulo em caso de erro) |
| `nosso_numero` | NUMERIC | Nosso número calculado |
| `tp_origem` | VARCHAR | Origem do boleto |
| `dth_tentativa` | TIMESTAMP | Data/hora da tentativa |
| `ind_sucesso` | BOOLEAN | Indica se a integração bancária retornou com sucesso |
| `txt_erro` | TEXT | Mensagem de erro, quando houver |

---

## S3 — Regras de Negócio

### RN-090 — Pré-condição: Situação do Licenciamento

O cidadão só pode solicitar a geração de boleto se o licenciamento estiver em um dos estados permitidos para o tipo de boleto solicitado:

| `TipoBoleto` | `SituacaoLicenciamento` permitida |
|---|---|
| `TAXA_ANALISE` | `AGUARDANDO_PAGAMENTO` |
| `TAXA_REANALISE` | `AGUARDANDO_PAGAMENTO` |
| `TAXA_UNICA` | `AGUARDANDO_PAGAMENTO` |
| `TAXA_VISTORIA` | `AGUARDANDO_PAGAMENTO_VISTORIA` |
| `TAXA_RENOVACAO` | `AGUARDANDO_PAGAMENTO_RENOVACAO` |

Violação: retornar HTTP 400 com mensagem `licenciamento.situacao.operacao.invalida`.

### RN-091 — Cancelamento de Isenção Pendente

Se no momento da geração do boleto o licenciamento possuir `situacaoIsencao = SOLICITADA`, o sistema deve:
1. Definir `licenciamento.isencao = false`
2. Limpar `licenciamento.situacaoIsencao = null`
3. Persistir a alteração no licenciamento antes de prosseguir

Justificativa: ao optar por pagar o boleto, o cidadão abandona implicitamente a solicitação de isenção pendente.

### RN-092 — Reutilização de Boleto Vigente

Antes de emitir um novo boleto, o sistema verifica se existe um boleto anterior para o mesmo licenciamento, mesmo tipo e mesmo pagador (CPF/CNPJ) com situação `EM_ABERTO`.

- **Para TAXA_ANALISE e TAXA_UNICA:** se existir boleto `EM_ABERTO` com o mesmo pagador → rejeitar com HTTP 400 (`boleto.licenciamento.EM_ABERTO`). O cidadão deve pagar o boleto existente ou aguardar seu vencimento.
- **Para TAXA_VISTORIA e TAXA_RENOVACAO:** se existir boleto `EM_ABERTO` → rejeitar com HTTP 400. Somente após vencimento é permitido emitir novo boleto de vistoria/renovação.
- **Para TAXA_REANALISE:** a verificação de boleto anterior não é aplicada (pode gerar novo boleto mesmo com anterior em aberto).

### RN-093 — Cálculo do Valor da Taxa

O valor de cada tipo de boleto é calculado multiplicando a quantidade de UPFs pelo valor unitário da UPF:

**Fórmula geral:** `valorBoleto = qtdUPF × valorUPF`

onde `valorUPF` é obtido da tabela `sol_parametro_boleto` (chave `upf.valor`).

| Tipo | Cálculo da qtdUPF |
|---|---|
| `TAXA_ANALISE` (PPCI) | Tabela `sol_taxa_licenciamento` filtrada por grupo/subgrupo de ocupação e área |
| `TAXA_ANALISE` (PSPCIM) | Mesmo cálculo de `TAXA_UNICA` |
| `TAXA_UNICA` | Tabela `sol_taxa_licenciamento` — taxa única para o tipo PSPCIM |
| `TAXA_VISTORIA` | Tabela `sol_taxa_licenciamento` — taxa de vistoria; 50% se não for a primeira vistoria e não há APPCI pós-vistoria anterior |
| `TAXA_REANALISE` | 50% da taxa de análise (salvo isenção de reanálise) + compensação por diferença de UPFs entre emissão anterior e atual |
| `TAXA_RENOVACAO` | Taxa de vistoria; 50% se última vistoria encerrada teve status REPROVADO |

**Isenção:** se `licenciamento.isIsento = true`, o valor de `TAXA_VISTORIA` e `TAXA_REANALISE` é R$ 0,00.

**Arredondamento:** `HALF_EVEN` com 2 casas decimais para exibição; 4 casas decimais para cálculos intermediários em UPF.

### RN-094 — Regra dos 50% para TAXA_VISTORIA

O sistema aplica 50% da taxa de vistoria quando:
- O licenciamento já possui ao menos uma vistoria APROVADA ou REPROVADA registrada, **E**
- A última vistoria e a vistoria atual são do mesmo tipo (TipoVistoria), **E**
- Não há APPCI emitido **depois** da data da última vistoria encerrada.

Caso contrário (primeira vistoria, ou troca de tipo, ou APPCI emitido após última vistoria), aplica 100%.

### RN-095 — Compensação na TAXA_REANALISE

Quando o tipo é `TAXA_REANALISE`:
1. Buscar o boleto anterior PAGO mais recente para o mesmo licenciamento (qualquer tipo).
2. Se `qtdUPF_atual > qtdUPF_boleto_anterior`, adicionar ao valor de reanálise a diferença: `(qtdUPF_atual - qtdUPF_anterior) × valorUPF`.
3. Se `qtdUPF_boleto_anterior` for nulo (boleto emitido antes da implementação da regra), preencher retroativamente com o valor calculado atual e persistir.

### RN-096 — Geração do Nosso Número

```
nossoNumero = TRUNCA(id, 8_dígitos_menos_significativos) * 100 + DV
DV = módulo 11 dos 8 dígitos
```

O nosso número deve ser único no banco. O campo `seuNumero` segue o padrão `{id}L` para licenciamento.

### RN-097 — Prazo de Vencimento do Boleto

O prazo padrão é de **30 dias** a partir da data de emissão. O sistema lê o parâmetro configurável `numero.dias.vencimento.boleto` para o job de vencimento (não para a data de vencimento registrada no banco).

Exception historica: em janeiro de 2024, a data de vencimento foi fixada em 2024-01-31 para boletos emitidos naquele mês (implementação de demanda pontual; não replicar na nova versão salvo nova demanda).

### RN-098 — Dados Desnormalizados do Pagador

No momento da geração do boleto, copiar para a entidade `Boleto`:
- Nome, CPF ou CNPJ do pagador
- Endereço formatado: `{logradouro}, {número} / {complemento}, {bairro}` (complemento omitido se nulo)
- Cidade, UF e CEP

Para pagador PJ (Proprietário PJ): usar o CPF do procurador para buscar o endereço; o CNPJ do proprietário é registrado como `cnpj_pagador`.

### RN-099 — Beneficiário por Município

O beneficiário (dados bancários do CBM-RS) é selecionado pelo número IBGE do município do endereço do licenciamento. A consulta é feita na tabela `sol_cidade` → `sol_beneficiario`.

### RN-100 — Marco de Auditoria na Geração

Após gerar o boleto com sucesso, registrar marco no licenciamento com tipo correspondente:

| `TipoBoleto` | `TipoMarco` registrado |
|---|---|
| `TAXA_ANALISE` / `TAXA_REANALISE` / `TAXA_UNICA` | `BOLETO_ATEC` |
| `TAXA_VISTORIA` | `BOLETO_VISTORIA` |
| `TAXA_RENOVACAO` | `BOLETO_VISTORIA_RENOVACAO_PPCI` |

O texto complementar do marco contém o valor nominal do boleto formatado em R$.
Responsável do marco: `CIDADAO`.

### RN-101 — Download do PDF do Boleto

O cidadão pode fazer download do PDF do boleto após a geração. O PDF é gerado a partir de template Jasper (ou equivalente) e contém:
- Dados do beneficiário (nome, nome fantasia, CPF/CNPJ, agência, endereço)
- Dados do pagador (nome, CPF/CNPJ, endereço)
- Código de barras e linha digitável
- Nosso número formatado com 10 dígitos (zero à esquerda)
- Data de vencimento, valor nominal, data de emissão, espécie, aceite = "N"
- Logo Banrisul (ou banco substituto)

Restrição: boleto com `situacao = VENCIDO` não pode ser baixado. Retornar HTTP 400 (`boleto.licenciamento.VENCIDO`).
Restrição: boleto deve pertencer ao licenciamento informado na URL. Retornar HTTP 404 se não pertencer.

### RN-102 — Job de Vencimento (Batch)

Executar a cada **12 horas** (00:00 e 12:00 ou conforme configuração).

Algoritmo:
1. Calcular `dataLimiteVencimento = hoje - numeroDiasVencimentoBoleto` (parâmetro, padrão = 2).
2. Buscar todos os boletos com `situacao = EM_ABERTO` e `dataVencimento <= dataLimiteVencimento`.
3. Para cada boleto encontrado: atualizar `situacao = VENCIDO` e persistir.

O parâmetro `numero.dias.vencimento.boleto` é configurável por administrador.

### RN-103 — Job de Confirmação de Pagamento (CNAB 240)

Executar a cada **12 horas** (00:00 e 12:00 ou conforme configuração).

Algoritmo:
1. Ler todos os arquivos presentes no diretório de entrada (configurável por propriedade).
2. Para cada arquivo:
   a. Se arquivo vazio: marcar como processado e mover para diretório de processados.
   b. Parsear as linhas do arquivo no formato CNAB 240 (Banrisul).
   c. Para cada registro do tipo **liquidação** (código de movimento = "06"):
      - Buscar `Boleto` pelo `nossoNumero` (campo `NossoNumero` do registro CNAB).
      - Se não encontrado: adicionar erro à lista e continuar.
      - Se situação já é `PAGO`: ignorar (idempotente).
      - Atualizar: `situacao = PAGO`, `dataPagamento = dtPagamento do registro`, `nomeArquivoRetorno = nome do arquivo`.
      - Persistir o boleto (nova transação por boleto, para isolar falhas).
      - Despachar processamento pós-pagamento conforme `TipoOrigemBoleto`:
        - `LICENCIAMENTO`: chamar `PagamentoBoletoLicenciamentoService.atualizaStatusAposBoletoPago(idBoleto)`
        - `FACT`: chamar `PagamentoBoletoFactService.processaPagamentoFact(idBoleto)`
        - `INSTRUTOR`: chamar `InstrutorService.atualizaStatusAposBoletoPago(boleto, isNovoCadastro=true)`
        - `RENOVACAO_INSTRUTOR`: chamar `InstrutorService.atualizaStatusAposBoletoPago(boleto, isNovoCadastro=false)`
   d. Se houve erros ao processar qualquer boleto: enviar e-mail de alerta para destinatário configurado.
3. Mover arquivo para diretório de processados somente se todos os registros foram processados sem erro.

### RN-104 — Atualização de Estado do Licenciamento Após Pagamento

Após confirmação de pagamento de boleto com origem `LICENCIAMENTO`, avançar o estado do licenciamento conforme tabela:

| `SituacaoLicenciamento` atual | `TipoBoleto` | Próximo estado | Marco registrado |
|---|---|---|---|
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE` (PSPCIM, endereço novo) | `ANALISE_ENDERECO_PENDENTE` | `LIQUIDACAO_TAXA_UNICA` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE` (PSPCIM, sem endereço novo) | `AGUARDANDO_DISTRIBUICAO` | `LIQUIDACAO_TAXA_UNICA` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE` (PPCI, endereço novo) | `ANALISE_ENDERECO_PENDENTE` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE` (PPCI, inviabilidade técnica pendente) | `ANALISE_INVIABILIDADE_PENDENTE` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_ANALISE` (PPCI, caso geral) | `AGUARDANDO_DISTRIBUICAO` | `LIQUIDACAO_ATEC` |
| `AGUARDANDO_PAGAMENTO` | `TAXA_REANALISE` | (mesma lógica de TAXA_ANALISE acima) | (idem) |
| `AGUARDANDO_PAGAMENTO_VISTORIA` | `TAXA_VISTORIA` | `AGUARDANDO_DISTRIBUICAO_VISTORIA` | `LIQUIDACAO_VISTORIA` |
| `AGUARDANDO_PAGAMENTO_RENOVACAO` | `TAXA_RENOVACAO` | `AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO` | `LIQUIDACAO_VISTORIA_RENOVACAO` |

O texto complementar do marco contém o valor nominal do boleto formatado em R$.
Responsável do marco: `SISTEMA`.

"Endereço novo" é determinado pelo helper `LicenciamentoEnderecoNovoHelper.isEnderecoNovo()`.
"Inviabilidade técnica pendente" é determinado verificando se existe medida de segurança com inviabilidade técnica sem aprovação.

### RN-105 — Consistência: Boleto Pertence ao Licenciamento

Toda operação de consulta, download ou associação de boleto com licenciamento deve verificar que o `BoletoLicenciamento` relaciona exatamente o boleto e o licenciamento informados. Retornar HTTP 404 se a associação não existir.

### RN-106 — Relatório de Arrecadação

O sistema deve suportar a geração de relatório de arrecadação (PDF e CSV) com as seguintes regras:
- Intervalo máximo de 31 dias entre data inicial e data final.
- Agrupar por: número do batalhão, descrição do batalhão, cidade responsável pela arrecadação, cidade de origem.
- Totais por grupo e total geral (montante).
- Filtrar por tipo de origem: Instrutor (0), Licenciamento (1), PPCI (2), PSPCIM (3), PSPCIB (4), CLCB (5), Evento Temporário (6).
- Requer permissão `VALORESARRECADADOS:CONSULTAR`.

---

## S4 — Endpoints da API REST

### 4.1 Gerar Boleto

```
POST /api/licenciamentos/{idLicenciamento}/boletos
Content-Type: application/json
Authorization: Bearer {JWT Keycloak}

{
  "tipo": "TAXA_ANALISE",
  "responsavel": {
    "tipo": "RT",
    "cpfCnpj": "12345678901",
    "nome": "João da Silva",
    "cpfProcurador": null
  }
}
```

**Response 201 Created:**
```json
{
  "id": 42,
  "boleto": {
    "id": 100,
    "nossoNumero": "1234567890",
    "codigoBarras": "...",
    "linhaDigitavel": "...",
    "dataVencimento": "2026-04-12",
    "valorNominal": 158.50,
    "situacao": "EM_ABERTO"
  }
}
```

**Erros possíveis:**
- `400 Bad Request`: situação do licenciamento inválida (RN-090), boleto em aberto já existe (RN-092), tipo de boleto inválido (RN-093)
- `404 Not Found`: licenciamento não encontrado, pagador não encontrado
- `500 Internal Server Error`: falha na integração bancária (RN-096 / gateway)

### 4.2 Listar Boletos do Licenciamento

```
GET /api/licenciamentos/{idLicenciamento}/boletos
Authorization: Bearer {JWT Keycloak}
```

**Response 200 OK:** array de `BoletoLicenciamentoDTO`.

### 4.3 Download PDF do Boleto

```
GET /api/licenciamentos/{idLicenciamento}/boletos/{idBoletoLicenciamento}/pdf
Authorization: Bearer {JWT Keycloak}
```

**Response 200 OK:** `application/pdf` — conteúdo do PDF do boleto.
**Erros:** `400` se VENCIDO (RN-101), `404` se não encontrado.

### 4.4 Consultar Valor da Taxa (Preview)

```
GET /api/licenciamentos/{idLicenciamento}/boletos/valor?tipo=TAXA_ANALISE
Authorization: Bearer {JWT Keycloak}
```

**Response 200 OK:**
```json
{ "valorNominal": 158.50, "quantidadeTotalUpf": 8.12 }
```

### 4.5 Endpoint Administrativo: Verificar Pagamento Manual

```
POST /api/admin/boletos/verificar-pagamento
Authorization: Bearer {JWT Keycloak — perfil ADMIN}
Content-Type: application/json

{ "idBoleto": 100 }
```

Permite ao administrador forçar a verificação de pagamento de um boleto específico fora do ciclo do job.

---

## S5 — Segurança

### 5.1 Autenticação e Autorização

- Todos os endpoints exigem token JWT emitido pelo Keycloak.
- O subject do JWT (`sub`) é o UUID do usuário no Keycloak (substitui o `idUsuarioSoe Long` do sistema atual).
- Mapeamento de permissões:

| Operação | Role/Permissão Keycloak |
|---|---|
| Gerar boleto | `PAGAMENTOS:INCLUIR` ou role `RT`, `PROPRIETARIO` |
| Excluir boleto | `PAGAMENTOS:EXCLUIR` |
| Download PDF | Autenticado + envolvido no licenciamento |
| Relatório arrecadação | `VALORESARRECADADOS:CONSULTAR` |
| Endpoint admin | Role `ADMIN_CBM` |

- O interceptor de segurança (`SegurancaEnvolvidoInterceptor`) deve validar que o usuário autenticado é um dos envolvidos no licenciamento antes de permitir operações de geração e download.

### 5.2 Controle de Acesso por Envolvido

Apenas usuários que são envolvidos ativos no licenciamento (RT, proprietário, procurador) podem gerar boletos para esse licenciamento. O check deve ser feito no service, não apenas no controller.

---

## S6 — Integração Bancária

### 6.1 Adaptador de Integração (Substituição do PROCERGS)

No sistema atual, a integração com o banco Banrisul é feita via `BoletoIntegracaoProcergs` (chamada HTTP para serviço intermediário da PROCERGS que encapsula o web service SOAP do Banrisul).

Na nova versão, o adaptador deve ser substituído por um dos seguintes padrões:
- **Integração direta via REST com o Banrisul** (API PIX/boleto Banrisul, caso disponível contratualmente)
- **Integração via gateway de pagamento de mercado** (ex: Juno, PagSeguro, Gerencianet/Efí, banco parceiro com API REST)
- **Adaptador próprio SOAP** se o contrato com o Banrisul exigir manutenção do protocolo

Independentemente da escolha, o contrato interno da interface deve ser:

```java
public interface GatewayBoleto {
    /**
     * Registra o boleto no banco e retorna código de barras e linha digitável.
     * @throws GatewayBoletoException em caso de falha na integração
     */
    BoletoRegistradoDTO registrar(BoletoRegistroDTO dados) throws GatewayBoletoException;
}
```

A implementação concreta é injetada por Spring (`@Primary` ou `@Qualifier`), permitindo troca sem alteração do service.

### 6.2 Formato CNAB 240 — Parser

O arquivo de retorno do Banrisul segue o padrão CNAB 240. O sistema deve:
1. Implementar `ParserCnab240` que lê as linhas e extrai registros de detalhe.
2. Filtrar apenas registros com **código de movimento = "06"** (liquidação).
3. Extrair: `nossoNumero`, `dataPagamento`, `valorPago`.
4. Retornar lista de `RetornoPagamentoDTO`.

Na nova versão, o parser deve ser mantido independente da integração de registro (pode haver futuro banco diferente do Banrisul com formato diferente). Usar interface:

```java
public interface ParserRetornoBancario {
    List<RetornoPagamentoDTO> parse(List<String> linhas, String nomeArquivo);
}
```

### 6.3 Propriedades de Configuração

```yaml
# application.yml
sol:
  boleto:
    cnab:
      diretorio-entrada: /opt/solcbm/retorno/banrisul/entrada/
      diretorio-processados: /opt/solcbm/retorno/banrisul/processados/
    gateway:
      url: https://api.banco.exemplo.com/boleto
      client-id: ${GATEWAY_CLIENT_ID}
      client-secret: ${GATEWAY_CLIENT_SECRET}
    email:
      destinatario-erro-job: ti@cbm.rs.gov.br
    upf:
      valor: 19.5352
```

Usar `@ConfigurationProperties` para injeção typesafe.

---

## S7 — Geração de PDF do Boleto

### 7.1 Motor de Relatório

Na nova versão, substituir o JasperReports (`facadeReport.gerarPDF`) por:
- **JasperReports mantido** (via `jasperreports` + `jasperreports-fonts`), ou
- **iText / OpenPDF** para geração programática, ou
- **Thymeleaf + Flying Saucer (xhtmlrenderer)** para template HTML → PDF

O template deve incluir todos os campos listados em RN-101.

### 7.2 Conteúdo do PDF

```
+------------------------------------------------------------+
| [Logo Banco]    BOLETO BANCÁRIO         [Código Beneficiário] |
| Beneficiário: {nome} / {nomeFantasia}                       |
| CNPJ: {cpfCnpj}     Agência: {agencia}                      |
| Endereço: {endereco}, {cidade} - {uf}   CEP: {cep}          |
|                                                              |
| Nosso Número: {nossoNumero 10 dígitos}                       |
| Número Documento: {seuNumero}                                |
| Vencimento: {dataVencimento}   Espécie: {especie}   Aceite: N|
| Emissão: {dataEmissao}                                       |
|                                                              |
| Pagador: {nomePagador}   CPF/CNPJ: {cpfCnpj}                |
| Endereço: {enderecoPagador}, {cidadePagador}-{uf} CEP:{cep} |
|                                                              |
| Valor: R$ {valorNominal}                                     |
|                                                              |
| [Código de barras visual]                                    |
| {linhaDigitavel}                                             |
+------------------------------------------------------------+
```

---

## S8 — Regras de Transição de Estado do Licenciamento

### 8.1 Máquina de Estados Relevante ao P11

```
AGUARDANDO_PAGAMENTO
    │
    ├─► [pagamento confirmado, PPCI, endereço novo] ──► ANALISE_ENDERECO_PENDENTE
    ├─► [pagamento confirmado, PPCI, inviabilidade] ──► ANALISE_INVIABILIDADE_PENDENTE
    └─► [pagamento confirmado, caso geral]           ──► AGUARDANDO_DISTRIBUICAO

AGUARDANDO_PAGAMENTO_VISTORIA
    └─► [pagamento confirmado, TAXA_VISTORIA] ──► AGUARDANDO_DISTRIBUICAO_VISTORIA

AGUARDANDO_PAGAMENTO_RENOVACAO
    └─► [pagamento confirmado, TAXA_RENOVACAO] ──► AGUARDANDO_DISTRIBUICAO_VISTORIA_RENOVACAO
```

### 8.2 Idempotência

Se o licenciamento já não está em `AGUARDANDO_PAGAMENTO*` quando o job processa o retorno bancário, o sistema deve **ignorar silenciosamente** a transição de estado (o pagamento foi registrado no boleto, mas o estado do licenciamento não é alterado novamente). Isso garante idempotência em caso de reprocessamento de arquivos.

---

## S9 — Jobs Agendados

### 9.1 Job de Vencimento de Boletos

```java
@Component
public class BoletoVencimentoJob {

    @Scheduled(cron = "0 0 0,12 * * *")  // 00:00 e 12:00
    @Transactional
    public void atualizaSituacao() {
        int diasTolerancia = parametroService.getInt("numero.dias.vencimento.boleto", 2);
        LocalDate dataLimite = LocalDate.now().minusDays(diasTolerancia);
        List<Boleto> vencidos = boletoRepository
            .findBySituacaoAndDataVencimentoBefore(SituacaoBoleto.EM_ABERTO, dataLimite);
        vencidos.forEach(b -> b.setSituacao(SituacaoBoleto.VENCIDO));
        boletoRepository.saveAll(vencidos);
    }
}
```

### 9.2 Job de Processamento CNAB 240

```java
@Component
public class BoletoConfirmacaoJob {

    @Scheduled(cron = "0 0 0,12 * * *")  // 00:00 e 12:00
    public void verificaPagamento() {
        Path dirEntrada = Path.of(config.getDiretorioEntrada());
        Path dirProcessados = Path.of(config.getDiretorioProcessados());

        try (Stream<Path> arquivos = Files.list(dirEntrada)) {
            arquivos.filter(Files::isRegularFile).forEach(arquivo -> {
                List<String> erros = new ArrayList<>();
                boolean processado = processarArquivo(arquivo, erros);
                if (!erros.isEmpty()) {
                    emailService.enviarAlertaErro(erros);
                }
                if (processado) {
                    Files.move(arquivo, dirProcessados.resolve(arquivo.getFileName()),
                               StandardCopyOption.REPLACE_EXISTING);
                }
            });
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void processarRegistro(RetornoPagamentoDTO retorno, String nomeArquivo, List<String> erros) {
        // Busca boleto, atualiza situação, despacha para o serviço correspondente
    }
}
```

**Importante:** cada registro CNAB deve ser processado em transação independente (`REQUIRES_NEW`) para que falhas em um registro não afetem os demais.

---

## S10 — Notificações por E-mail

### 10.1 Alerta de Falha no Job CNAB

Quando o job de confirmação encontra erros ao processar um ou mais registros, enviar e-mail para o destinatário configurado (`sol.boleto.email.destinatario-erro-job`) com:
- Assunto: `"Sistema SOL — Arquivo de retorno bancário com problemas"`
- Corpo HTML com a data/hora da falha, o ambiente e a lista de erros detalhados.

### 10.2 Notificação ao Cidadão (Opcional)

Após confirmação de pagamento, pode ser enviado e-mail ao RT e ao proprietário informando que o pagamento foi recebido e o licenciamento avançou de estado. Usar `Spring Mail` com template `Thymeleaf`. Esta funcionalidade é opcional na primeira versão.

---

## S11 — Estrutura de Camadas

```
controller/
  BoletoLicenciamentoController.java   — @RestController, validação de entrada, chamada ao service
service/
  BoletoLicenciamentoService.java      — orquestração, cálculo de valor, geração de boleto
  PagamentoBoletoLicenciamentoService.java — atualização de estado pós-pagamento
  BoletoService.java                   — CRUD do Boleto, nosso número, PDF
  BoletoVencimentoJob.java             — @Scheduled vencimento
  BoletoConfirmacaoJob.java            — @Scheduled CNAB 240
repository/
  BoletoRepository.java                — Spring Data JPA
  BoletoLicenciamentoRepository.java
  BeneficiarioRepository.java
  ParametroBoletoRepository.java
integration/
  GatewayBoleto.java                   — interface do adaptador bancário
  BanrisulGatewayAdapter.java          — implementação concreta
  ParserRetornoBancario.java           — interface do parser CNAB
  ParserCnab240.java                   — implementação para Banrisul
model/
  Boleto.java
  BoletoLicenciamento.java
  Beneficiario.java
  ParametroBoleto.java
dto/
  BoletoLicenciamentoRequestDTO.java
  BoletoLicenciamentoResponseDTO.java
  RetornoPagamentoDTO.java
  BoletoRegistroDTO.java
  BoletoRegistradoDTO.java
```

---

## S12 — Migrações de Banco de Dados (Flyway)

```sql
-- V11_001__create_sol_boleto.sql
CREATE TABLE sol_boleto (
    id                    BIGSERIAL PRIMARY KEY,
    nosso_numero          NUMERIC(38)   NOT NULL UNIQUE,
    seu_numero            VARCHAR(13),
    data_vencimento       DATE          NOT NULL,
    valor_nominal         NUMERIC(19,2) NOT NULL,
    tp_especie            VARCHAR(2),
    data_emissao          TIMESTAMP     NOT NULL,
    codigo_barras         VARCHAR(44),
    linha_digitavel       VARCHAR(47),
    id_beneficiario       BIGINT        NOT NULL REFERENCES sol_beneficiario(id),
    tp_origem             VARCHAR(30)   NOT NULL,
    tp_situacao           VARCHAR(20)   NOT NULL DEFAULT 'EM_ABERTO',
    data_pagamento        DATE,
    nome_arquivo_retorno  TEXT,
    nome_pagador          TEXT,
    cpf_pagador           VARCHAR(11),
    cnpj_pagador          VARCHAR(14),
    endereco_pagador      TEXT,
    cidade_pagador        TEXT,
    uf_pagador            CHAR(2),
    cep_pagador           VARCHAR(8),
    created_at            TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- V11_002__create_sol_boleto_licenciamento.sql
CREATE TABLE sol_boleto_licenciamento (
    id                    BIGSERIAL PRIMARY KEY,
    id_licenciamento      BIGINT        NOT NULL REFERENCES sol_licenciamento(id),
    id_boleto             BIGINT        NOT NULL REFERENCES sol_boleto(id),
    tp_boleto             VARCHAR(30)   NOT NULL,
    valor_taxa_analise    NUMERIC(19,2),
    qtd_total_upf         NUMERIC(19,4),
    created_at            TIMESTAMP     NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_boleto_lic_licenciamento ON sol_boleto_licenciamento(id_licenciamento);

-- V11_003__create_sol_parametro_boleto.sql
CREATE TABLE sol_parametro_boleto (
    id        BIGSERIAL   PRIMARY KEY,
    chave     VARCHAR(100) NOT NULL UNIQUE,
    valor     VARCHAR(100) NOT NULL
);
INSERT INTO sol_parametro_boleto (chave, valor) VALUES
    ('upf.valor', '19.5352'),
    ('credenciamento.profissionalempresa.valor', '5'),
    ('numero.dias.vencimento.boleto', '2');

-- V11_004__create_sol_log_gera_boleto.sql
CREATE TABLE sol_log_gera_boleto (
    id            BIGSERIAL PRIMARY KEY,
    id_boleto     BIGINT    REFERENCES sol_boleto(id),
    nosso_numero  NUMERIC(38),
    tp_origem     VARCHAR(30),
    dth_tentativa TIMESTAMP NOT NULL DEFAULT NOW(),
    ind_sucesso   BOOLEAN   NOT NULL DEFAULT FALSE,
    txt_erro      TEXT
);
```

---

## S13 — Testes

### 13.1 Testes Unitários

| Classe | Cenários obrigatórios |
|---|---|
| `BoletoLicenciamentoServiceTest` | Geração TAXA_ANALISE, TAXA_VISTORIA, TAXA_REANALISE, TAXA_RENOVACAO; bloqueio por boleto EM_ABERTO; cancelamento isenção pendente |
| `BoletoVencimentoJobTest` | Boletos com data anterior ao limite marcados VENCIDO; boletos EM_ABERTO dentro do prazo não alterados |
| `BoletoConfirmacaoJobTest` | Registro liquidação (código 06) confirmado; código diferente de 06 ignorado; boleto não encontrado gera erro; idempotência (boleto já PAGO ignorado) |
| `ParserCnab240Test` | Parsing de linhas de cabeçalho, detalhe e trailer; extração correta de nossoNumero e data |
| `PagamentoBoletoLicenciamentoServiceTest` | Todos os caminhos de RN-104; idempotência quando estado não é AGUARDANDO_PAGAMENTO* |

### 13.2 Testes de Integração

- Testar o endpoint `POST /api/licenciamentos/{id}/boletos` com banco PostgreSQL real (Testcontainers).
- Verificar que após confirmação de pagamento o estado do licenciamento é atualizado corretamente.
- Verificar que o job de vencimento altera somente boletos além do prazo.

---

## S14 — Pontos de Atenção para a Equipe

1. **Gateway bancário:** a interface `GatewayBoleto` deve ser projetada para facilitar a troca de banco sem afetar o resto do sistema. O Banrisul é o banco atual; futuras licitações podem resultar em mudança.

2. **Diretório de arquivos CNAB:** em ambiente de contêiner (Kubernetes/Docker), os diretórios de entrada e processados devem ser montados como volumes persistentes. Não usar caminhos hardcoded.

3. **UPF:** o valor da UPF é atualizado periodicamente por decreto estadual. O parâmetro `upf.valor` deve ser editável pelo administrador sem deploy.

4. **Compensação de reanálise (RN-095):** a lógica de retroativamente preencher `qtdUPF` do boleto anterior (quando nulo) deve ser mantida para compatibilidade com dados históricos migrados.

5. **Identidade do usuário:** no sistema atual, o identificador do pagador é `idUsuarioSoe Long`. Na nova versão, usar o `sub` UUID do token Keycloak. A migração deve mapear os IDs antigos para os novos UUIDs.

6. **NossoNumero:** a fórmula atual (trunca 8 dígitos + DV módulo 11) é específica do Banrisul. Se houver troca de banco, revisar a geração do nosso número.

7. **Processamento independente por boleto:** cada boleto do arquivo CNAB deve ser processado em transação separada (`REQUIRES_NEW`). Falha em um não deve bloquear os demais.

8. **Segurança do endpoint administrativo:** o endpoint de verificação manual deve exigir autenticação com role elevado e ser protegido contra uso indevido.

---

## S15 — Rastreabilidade de Requisitos

| ID | Fonte no sistema atual | Descrição |
|---|---|---|
| RN-090 | `BoletoLicenciamentoRNVal.validaSituacaoLicenciamento` | Pré-condição de situação do licenciamento |
| RN-091 | `BoletoLicenciamentoRN.gerarBoleto` (cancelamento isenção) | Cancelamento automático de isenção solicitada |
| RN-092 | `BoletoLicenciamentoRN.validarBoletoVencido` + `BoletoLicenciamentoRNVal` | Verificação de boleto vigente anterior |
| RN-093 | `BoletoLicenciamentoRN.getValorTaxa` | Cálculo de valor por tipo de boleto |
| RN-094 | `BoletoLicenciamentoRN.devePagarMeiaTaxaDeVistoria` | Regra dos 50% na taxa de vistoria |
| RN-095 | `BoletoLicenciamentoRN.getValorTaxaReanalise` + `getValorCompensacao` | Compensação na reanálise |
| RN-096 | `BoletoRN.getNossoNumero` / `getSeuNumero` | Geração de nosso número e seu número |
| RN-097 | `BoletoRN.getDataVencimento` + `BoletoSituacaoBatchRN` | Prazo de vencimento e job de atualização |
| RN-098 | `BoletoRN.buildBoletoEDLicenciamento` | Desnormalização dos dados do pagador |
| RN-099 | `BoletoLicenciamentoRN.registrarBoleto` via `CidadeRN` | Seleção de beneficiário por município |
| RN-100 | `BoletoLicenciamentoRN.incluiMarco` | Marco de auditoria na geração |
| RN-101 | `BoletoLicenciamentoRN.downloadBoleto` + `BoletoRN.gerarPdfBoletoLicenciamento` | Download do PDF |
| RN-102 | `BoletoSituacaoBatchRN.atualizaSituacao` | Job de vencimento |
| RN-103 | `EJBTimerService.verificaPagamentoBanrisul` + `PagamentoBoletoRN` | Job de confirmação CNAB 240 |
| RN-104 | `PagamentoBoletoLicenciamentoRN.atualizaStatusAposBoletoPago` | Transição de estado após pagamento |
| RN-105 | `BoletoLicenciamentoRN.validarBoletoPertenceLicenciamento` | Verificação de vínculo boleto-licenciamento |
| RN-106 | `BoletoRN.listarRelatorio` / `listarCSV` | Relatório de arrecadação |


---

## Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 02 (Demandas 20, 23) e Sprint 04 (Oportunidade A1).  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P11.

---

### RN-P11-N1 — Emissão de Boletos para CNPJ (Pessoa Jurídica) 🟠 P11-M1

**Prioridade:** Alta  
**Origem:** Demanda 20 — Sprint 02 Hammer

**Descrição:** O sistema deve suportar geração de boletos vinculados a **CNPJ** para entidades jurídicas que realizam licenciamentos, além dos boletos já vinculados a CPF.

**Mudança no gateway de geração de boleto (P11-A):**

```java
// BoletoService.java — gerarBoleto()
public Boleto gerarBoleto(Licenciamento lic, BigDecimal valor) {
    Envolvido pagador = lic.getPagadorPrincipal();
    
    BoletoRequest request = BoletoRequest.builder()
        .valor(valor)
        .vencimento(LocalDate.now().plusDays(3))
        .build();
    
    if (pagador.isCnpj()) {
        // Entidade jurídica: CNPJ como sacado
        request.setSacadoCnpj(pagador.getNrCnpj());
        request.setSacadoRazaoSocial(pagador.getNmRazaoSocial());
    } else {
        // Pessoa física: CPF como sacado
        request.setSacadoCpf(pagador.getNrCpf());
        request.setSacadoNome(pagador.getNmPessoa());
    }
    
    return banrisulApiClient.emitirBoleto(request);
}
```

**Validação de CNPJ no frontend:**
```typescript
// pagamento.component.ts
validarCnpj(cnpj: string): boolean {
    return this.cnpjValidator.validate(cnpj);
}
```

**Mudança no contrato da API Banrisul:**
- O campo `sacado` deve aceitar `cpf` (11 dígitos) ou `cnpj` (14 dígitos)
- Verificar com a equipe de integração Banrisul se o contrato atual suporta CNPJ

**DDL:**
```sql
ALTER TABLE cbm_boleto
    ADD COLUMN nr_cnpj_sacado VARCHAR(14),
    ADD COLUMN nm_razao_social_sacado VARCHAR(200);
-- Constraint: deve ter CPF ou CNPJ, não ambos
ALTER TABLE cbm_boleto
    ADD CONSTRAINT chk_sacado_cpf_ou_cnpj
        CHECK ((nr_cpf_sacado IS NOT NULL) != (nr_cnpj_sacado IS NOT NULL));
```

**Critérios de Aceitação:**
- [ ] CA-P11-N1a: Boleto pode ser emitido com CNPJ como sacado para pessoa jurídica
- [ ] CA-P11-N1b: CNPJ inválido retorna erro de validação 422 no frontend
- [ ] CA-P11-N1c: Boleto não pode ter CPF e CNPJ simultaneamente (constraint de banco)
- [ ] CA-P11-N1d: PDF do boleto exibe CNPJ e razão social quando sacado é PJ

---

### RN-P11-N2 — Botão de Cópia do Número do Processo 🟡 P11-M2

**Prioridade:** Média  
**Origem:** Demanda 23 — Sprint 02 Hammer

**Descrição:** O número do processo deve ser **copiável para a área de transferência** em todas as telas onde aparece (dashboard, histórico, pagamento, marcos).

**Componente Angular reutilizável:**

```typescript
@Component({
    selector: 'app-copy-to-clipboard',
    template: `
        <span class="process-number">{{ texto }}</span>
        <button mat-icon-button 
                (click)="copiar()" 
                [matTooltip]="copiado ? 'Copiado!' : 'Copiar número'"
                aria-label="Copiar número do processo">
            <mat-icon>{{ copiado ? 'check' : 'content_copy' }}</mat-icon>
        </button>
    `
})
export class CopyToClipboardComponent {
    @Input() texto: string = '';
    copiado = false;

    async copiar(): Promise<void> {
        await navigator.clipboard.writeText(this.texto);
        this.copiado = true;
        setTimeout(() => this.copiado = false, 2000);
    }
}
```

**Uso em templates:**
```html
<!-- Em qualquer tela que exibe número de processo -->
<app-copy-to-clipboard [texto]="licenciamento.nrProtocolo" />
```

**Telas onde deve aparecer:** Dashboard (lista de processos), Detalhes do licenciamento, Tela de pagamento, Consulta de marcos, Relatório de histórico.

**Critérios de Aceitação:**
- [ ] CA-P11-N2a: Ícone de cópia aparece ao lado do número do processo em todas as telas listadas
- [ ] CA-P11-N2b: Clicar no ícone copia o número para a área de transferência
- [ ] CA-P11-N2c: Ícone muda para "check" por 2 segundos após a cópia (confirmação visual)
- [ ] CA-P11-N2d: Funciona sem degradação em Chrome, Firefox e Edge (Clipboard API)

---

### RN-P11-N3 — Webhook para Confirmação de Pagamento em Tempo Real 🟠 P11-M3

**Prioridade:** Alta  
**Origem:** Oportunidade A1 — Análise de Racionalização

**Descrição:** Implementar endpoint de **webhook** para receber confirmação de pagamento do Banrisul em tempo real (< 5 segundos), reduzindo a latência atual de até 12 horas (job CNAB 240) para segundos. O job CNAB 240 é mantido como **fallback diário** de reconciliação.

**Novo endpoint webhook:**

```java
@RestController
@RequestMapping("/webhook")
public class PagamentoBoletoWebhookRS {

    @PostMapping("/pagamento-banrisul")
    public ResponseEntity<Void> confirmarPagamento(
        @RequestHeader("X-Banrisul-Signature") String signature,
        @RequestBody PagamentoWebhookPayload payload) {
        
        // 1. Verificar assinatura HMAC-SHA256
        if (!webhookSecurityService.verificarAssinatura(payload, signature)) {
            log.warn("Assinatura inválida no webhook Banrisul: {}", signature);
            return ResponseEntity.status(401).build();
        }
        
        // 2. Processar confirmação de pagamento
        pagamentoBoletoService.confirmarPagamentoPorWebhook(
            payload.getNrBoleto(), payload.getDtPagamento(), payload.getValorPago());
        
        return ResponseEntity.ok().build();
    }
}
```

**Verificação de assinatura:**
```java
// WebhookSecurityService.java
public boolean verificarAssinatura(PagamentoWebhookPayload payload, String signature) {
    String expectedSignature = HmacUtils.hmacSha256Hex(
        webhookSecret, objectMapper.writeValueAsString(payload));
    return MessageDigest.isEqual(
        expectedSignature.getBytes(), signature.getBytes());
}
```

**Mudança no fluxo P11:**
- **Antes:** Apenas job CNAB 240 a cada 12 horas confirma pagamentos
- **Depois:** Webhook confirma em tempo real (< 5s) + job CNAB 240 mantido 1×/dia às 23h para reconciliação

**Proteção contra duplicidade:**
```java
public void confirmarPagamentoPorWebhook(String nrBoleto, LocalDateTime dtPagamento, BigDecimal valor) {
    Boleto boleto = boletoRepository.findByNrBoleto(nrBoleto).orElseThrow();
    
    if (boleto.isFgPago()) {
        log.info("Webhook recebido para boleto já confirmado: {}. Ignorando.", nrBoleto);
        return; // idempotência
    }
    
    boleto.setFgPago(true);
    boleto.setDtPagamento(dtPagamento);
    boletoRepository.save(boleto);
    
    // Avançar o licenciamento
    licenciamentoService.processarPagamentoConfirmado(boleto.getIdLicenciamento());
}
```

**Critérios de Aceitação:**
- [ ] CA-P11-N3a: Endpoint `POST /webhook/pagamento-banrisul` recebe e processa confirmações do Banrisul
- [ ] CA-P11-N3b: Assinatura HMAC-SHA256 é verificada antes de processar (signature inválida → 401)
- [ ] CA-P11-N3c: Pagamento confirmado por webhook avança o licenciamento em < 5 segundos
- [ ] CA-P11-N3d: Webhook duplicado para boleto já confirmado é ignorado (idempotência)
- [ ] CA-P11-N3e: Job CNAB 240 reduzido para 1×/dia às 23h como reconciliação

---

### Resumo das Mudanças P11 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P11-M1 | RN-P11-N1 | Suporte a CNPJ na emissão de boletos (pessoa jurídica) | 🟠 Alta |
| P11-M3 | RN-P11-N3 | Webhook de confirmação de pagamento em tempo real | 🟠 Alta |
| P11-M2 | RN-P11-N2 | Componente de cópia do número do processo em todas as telas | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 02–04*
