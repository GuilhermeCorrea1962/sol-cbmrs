# Especificação Técnica de Integração — Sistema SOL × Sistema SEI

**Versão:** 1.0
**Data:** 23/03/2026
**Projeto:** Sistema Online de Licenciamento (SOL) — Corpo de Bombeiros Militar do Rio Grande do Sul (CBM-RS)
**Responsável técnico:** Equipe de Desenvolvimento SOL / CBMRS
**Status:** Rascunho para revisão

---

## Referências

- RTCBMRS N.º 01/2024 — Regulamento Técnico de Segurança Contra Incêndio e Pânico do RS
- RT de Implantação SOL, 4.ª Edição — documento interno CBM-RS
- SeiWS.php — documentação da API SOAP do SEI (Módulo de Integração v4.x), disponibilizada pela PROCERGS
- Lei Federal n.º 13.709/2018 (LGPD)
- NBR ISO/IEC 27001:2022 — Segurança da Informação

---

## Sumário

1. Objetivo e Escopo
2. Arquitetura da Integração
3. Autenticação e Configuração
4. Mapeamento de Eventos SOL → Ações SEI
5. Modelo de Dados — Tabela de Rastreabilidade
6. Componente SeiGatewayService (Java Spring Boot 3)
7. Padrão Outbox — Garantia de Entrega
8. Polling de Retorno — Consulta de Andamento SEI
9. Geração de Documentos para o SEI
10. Tipos de Processo SEI (Configuração do SEI-RS)
11. Tratamento de Erros e Resiliência
12. Segurança
13. O Que NÃO É Integrado (e Por Quê)
14. Plano de Implementação da Integração
15. Diagrama de Sequência — Evento APPCI Emitido
16. Configuração do Ambiente de Homologação
17. Escopo Excluído e Justificativas (Documento Formal para Processo Licitatório)

---

## 1. Objetivo e Escopo

### 1.1 Objetivo

Esta especificação técnica descreve a integração entre o Sistema Online de Licenciamento (SOL) do Corpo de Bombeiros Militar do Rio Grande do Sul (CBM-RS) e o Sistema Eletrônico de Informações (SEI), plataforma de gestão documental adotada pelo Governo do Estado do Rio Grande do Sul e operada pela PROCERGS.

A integração tem como finalidade garantir que os eventos relevantes gerados no SOL — protocolos, emissões de documentos técnicos, decisões de recursos, extinções e renovações de licenciamento — produzam automaticamente os correspondentes registros documentais no SEI, preservando a rastreabilidade documental oficial exigida pela legislação estadual e pelos normativos do CBM-RS.

### 1.2 Princípio Fundamental

O SOL é o sistema operacional de serviço: é nele que o Responsável Técnico (RT), o Responsável pelo Uso (RU), os analistas e os inspetores realizam todas as ações do processo de licenciamento. O SEI é o repositório documental oficial do estado: é nele que os documentos gerados pelo processo adquirem validade arquivística e integram o acervo permanente do CBM-RS.

Os dois sistemas são complementares, não substitutos. O SOL não replicará a tramitação interna do SEI; o SEI não controlará o fluxo operacional do SOL. A integração é unidirecional no sentido principal (SOL produz → SEI arquiva), com uma leitura de retorno (polling) limitada ao acompanhamento de processos de recurso.

### 1.3 O Que Esta Especificação Cobre

- Criação automatizada de processos SEI a partir de eventos SOL (protocolos, recursos, renovações).
- Inclusão automática de documentos (PDFs e HTML) em processos SEI existentes.
- Conclusão automática de processos SEI quando o ciclo de vida do licenciamento é encerrado no SOL.
- Garantia de entrega via padrão Transactional Outbox.
- Polling de retorno para acompanhar andamento de processos de recurso.
- Modelo de dados de rastreabilidade.
- Tratamento de erros, resiliência e monitoramento operacional.

### 1.4 O Que Esta Especificação Não Cobre

Os itens abaixo estão explicitamente fora do escopo deste documento. A exclusão de cada um é intencional e fundamentada:

---

**a) Integração com o PROCERGS SOE / meu.rs.gov.br**

Tratada integralmente em `Requisitos_P01_Autenticacao_StackAtual.md` e `Requisitos_P01_Autenticacao_Java.md`. Trata-se de uma integração de **identidade digital** (protocolo OIDC/OAuth2, emissão de tokens JWT, gestão de sessão do usuário), sem nenhuma relação com o ciclo de vida documental gerenciado pelo SEI. Os contratos técnicos são completamente distintos: autenticação usa fluxos OIDC com Keycloak/Gov.br; a integração SEI usa SOAP com API key estática. Unificá-las num mesmo documento criaria ambiguidade sobre fronteiras de responsabilidade.

---

**b) Integração com PROCERGS para boletos bancários**

Tratada integralmente em `Requisitos_P11_PagamentoBoleto_StackAtual.md` e `Requisitos_P11_PagamentoBoleto_JavaModerna.md`. Trata-se de uma integração de **pagamento** (geração de boleto CNAB 240, webhook de confirmação, liquidação PIX), que ocorre antes do SOL gerar qualquer documento destinado ao SEI. O SEI não tem ciência da existência de boletos ou pagamentos — ele recebe apenas documentos técnicos e administrativos após o pagamento já ter sido confirmado pelo SOL. Misturar os dois fluxos prejudicaria a clareza de ambas as especificações.

---

**c) Integração com Alfresco/ECM**

O Alfresco é o repositório **interno do SOL**, onde são armazenados os arquivos enviados pelo cidadão e pelo RT durante o processo de licenciamento (plantas, memoriais descritivos, laudos técnicos em rascunho, fotografias de vistoria). O campo `identificadorAlfresco` (nodeRef) é uma referência interna entre o banco de dados do SOL e o Alfresco — transparente para o SEI. O SEI recebe exclusivamente os **documentos finais** gerados pelo SOL (APPCI em PDF/A, CIA em PDF, decisão de recurso em PDF) — nunca acessa o Alfresco diretamente. A eventual substituição do Alfresco pelo MinIO (conforme proposta de modernização) não altera em nada a integração com o SEI.

---

**d) Tramitação interna dentro do SEI**

Uma vez que o SOL entrega um documento ao SEI, o que ocorre dentro do SEI — quais servidores assinam, para quais unidades o processo tramita, quais despachos são incluídos manualmente — é responsabilidade exclusiva dos servidores do CBM-RS operando diretamente no SEI. O SOL não tem como controlar, nem deve controlar, o comportamento interno de outro sistema sob administração da PROCERGS/CBM-RS. Tentar fazê-lo via API seria frágil (dependente da configuração interna do SEI-RS, sujeita a mudança sem aviso) e contrário ao princípio de separação de responsabilidades. O SOL apenas consulta o resultado via polling (`ConsultarProcedimento`) para saber se processos de recurso foram concluídos — leitura, não controle.

---

**e) Migração de dados históricos do sistema legado para o SEI**

São dois problemas independentes que não devem ser confundidos:

1. A migração dos dados do **SOL legado para o novo banco PostgreSQL do SOL moderno** já está prevista e especificada na Etapa 5 do plano de desenvolvimento (`Apresentacao_Executiva_Modernizacao_SOL.md`).
2. A decisão de **retroativamente criar processos SEI para licenciamentos históricos** é uma decisão administrativa do CBM-RS, não um requisito técnico desta integração. As opções possíveis — não migrar o histórico para o SEI; migrar apenas os processos dos últimos N anos; criar processos SEI apenas para novos licenciamentos a partir do Go-Live — têm custos e implicações distintos e devem ser avaliadas separadamente pela gestão do CBM-RS. Nenhuma dessas opções afeta o funcionamento da integração descrita neste documento para os processos gerados após o Go-Live.

---

---

## 2. Arquitetura da Integração

### 2.1 Visão Geral

```
+--------------------------------------------------+
|                   SOL Backend                    |
|  (Spring Boot 3 / PostgreSQL)                    |
|                                                  |
|  +------------+     Evento de domínio            |
|  | Serviço    |------------------------+         |
|  | P03/P04/   |                        v         |
|  | P07/P08/   |              +------------------+|
|  | P10/P12/   |              | SeiEventListener ||
|  | P14        |              | (Spring Events)  ||
|  +------------+              +--------+---------+|
|                                       |           |
|                              Insere PENDENTE      |
|                                       |           |
|                              +--------v---------+ |
|                              | sol.integracao   | |
|                              | _sei (Outbox)    | |
|                              +--------+---------+ |
|                                       |           |
|                              +--------v---------+ |
|                              | OutboxWorker     | |
|                              | (Scheduler 2min) | |
|                              +--------+---------+ |
|                                       |           |
|                              +--------v---------+ |
|                              | SeiGatewayService| |
|                              +--------+---------+ |
|                                       |           |
+---------------------------------------|----------+
                                        |
                            HTTPS / SOAP 1.1
                                        |
                               +--------v---------+
                               |   SEI SOAP API   |
                               |  (SeiWS.php)     |
                               |  PROCERGS / RS   |
                               +------------------+
```

### 2.2 Componentes da Integração

| Componente | Responsabilidade |
|---|---|
| `SeiProperties` | Lê e valida configurações do `application.yml` (endpoint, credenciais, timeouts) |
| `SeiSoapClient` | Geração e envio de requisições SOAP; parse das respostas XML; timeout e TLS |
| `SeiGatewayService` | Fachada de alto nível; converte objetos de domínio SOL em chamadas SOAP; retry com backoff |
| `SeiEventListener` | Ouve eventos Spring (`@EventListener`); grava registro na outbox em transação atômica |
| `OutboxWorkerJob` | Job agendado (`@Scheduled`); processa registros PENDENTE; chama `SeiGatewayService` |
| `SeiIntegracaoRepository` | Repositório JPA/Spring Data para a tabela `sol.integracao_sei` |
| `SeiPollingJob` | Job diário; consulta `ConsultarProcedimento` para processos de recurso abertos |

### 2.3 Fluxo de Dados Assíncrono

O padrão adotado é o Transactional Outbox (detalhado na seção 7). O objetivo é que nenhuma falha no SEI impeça o SOL de continuar operando. A comunicação é sempre assíncrona: o SOL nunca aguarda resposta do SEI em tempo real durante uma requisição do usuário.

### 2.4 Tecnologias Utilizadas

- **SOL Backend:** Spring Boot 3.x, Spring Data JPA, Spring Scheduler, Spring Events
- **Geração de SOAP:** Jakarta XML Web Services (JAX-WS RI) ou Apache CXF — a decisão de implementação é da equipe de desenvolvimento
- **Geração de PDFs:** Thymeleaf (template HTML) + Flying Saucer (conversão HTML → PDF/A-1b)
- **Banco de dados:** PostgreSQL 15+
- **HTTP/TLS:** Spring WebClient ou OkHttp para chamada SOAP sobre HTTPS

---

## 3. Autenticação e Configuração

### 3.1 Cadastro do SOL no SEI-RS

Antes de qualquer desenvolvimento, o CBM-RS deverá solicitar à PROCERGS/SEI-RS o cadastro do SOL como sistema integrador. Esse cadastro é realizado no painel de administração do SEI (menu Administração → Sistemas) e gera:

- **SiglaSistema:** identificador único do sistema integrador, por exemplo `SOL_CBMRS`
- **IdentificacaoServico:** chave de API estática (GUID ou string gerada pelo SEI) que autentica cada chamada SOAP

Esses dois valores, junto ao ID da unidade administrativa do CBM-RS no SEI, são os únicos credenciais da integração. Não há sessão, token OAuth ou certificado adicional para o sistema integrador.

### 3.2 Identificação da Unidade CBM-RS no SEI

O SEI-RS identifica cada unidade administrativa por um ID numérico (`IdUnidade`). O CBM-RS deverá solicitar à PROCERGS o ID da unidade de protocolo onde os processos de licenciamento serão criados. Esse ID é fixo e deve ser configurado conforme a seção 3.3 abaixo.

### 3.3 Configuração via application.yml

```yaml
sei:
  endpoint: https://sei.rs.gov.br/sei/ws/SeiWS.php
  sigla-sistema: SOL_CBMRS
  identificacao-servico: ${SEI_API_KEY}
  id-unidade-protocolo: "110000167"
  # ID da unidade de protocolo do CBM-RS no SEI-RS (valor a confirmar com PROCERGS)
  tipo-procedimento-licenciamento: "100000150"
  # Código do tipo "Licenciamento PPCI - CBM-RS" no SEI-RS (a ser criado — ver seção 10)
  tipo-procedimento-recurso: "100000151"
  tipo-procedimento-renovacao: "100000152"
  tipo-procedimento-extincao: "100000153"
  id-serie-ppci: "200000201"
  # Códigos das séries (tipos de documento) — a serem criados pelo admin SEI-RS (ver seção 10)
  id-serie-cia: "200000202"
  id-serie-appci: "200000203"
  id-serie-laudo-vistoria: "200000204"
  id-serie-civ: "200000205"
  id-serie-decisao-recurso: "200000206"
  id-serie-extincao: "200000207"
  timeout-ms: 10000
  retry-max: 3
  retry-delay-ms: 2000
```

Todos os valores numéricos acima são exemplos. Os valores reais deverão ser substituídos após o cadastro efetuado pela PROCERGS/SEI-RS.

### 3.4 Variável de Ambiente SEI_API_KEY

A chave `IdentificacaoServico` nunca deve ser armazenada no código-fonte, em arquivos versionados ou no banco de dados. Ela deve ser injetada exclusivamente via variável de ambiente `SEI_API_KEY`, gerenciada pelo operador de infraestrutura (Kubernetes Secret, Vault ou equivalente).

```bash
# Exemplo de injeção no container
export SEI_API_KEY="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 3.5 Classe SeiProperties

```java
@ConfigurationProperties(prefix = "sei")
@Validated
public record SeiProperties(
    @NotBlank String endpoint,
    @NotBlank String siglaSistema,
    @NotBlank String identificacaoServico,
    @NotBlank String idUnidadeProtocolo,
    @NotBlank String tipoProcedimentoLicenciamento,
    @NotBlank String tipoProcedimentoRecurso,
    @NotBlank String tipoProcedimentoRenovacao,
    @NotBlank String tipoProcedimentoExtincao,
    @NotBlank String idSeriePpci,
    @NotBlank String idSerieCia,
    @NotBlank String idSerieAppci,
    @NotBlank String idSerieLaudoVistoria,
    @NotBlank String idSerieCiv,
    @NotBlank String idSerieDecisaoRecurso,
    @NotBlank String idSerieExtincao,
    int timeoutMs,
    int retryMax,
    int retryDelayMs
) {}
```

---

## 4. Mapeamento de Eventos SOL → Ações SEI

A tabela a seguir lista todos os eventos do SOL que geram ações no SEI, com o processo de origem, o momento exato do disparo, a ação correspondente no SEI e a operação WSDL utilizada.

| # | Evento SOL | Processo | Momento do Disparo | Ação no SEI | Operação WSDL |
|---|---|---|---|---|---|
| 01 | PPCI_PROTOCOLADO | P03 / P11 | Após confirmação de pagamento ou deferimento de isenção | Cadastra interessado (RU); cria processo SEI tipo "Licenciamento PPCI — CBM-RS" | `IncluirOuAtualizarContato` + `GerarProcedimento` |
| 02 | CIA_EMITIDA | P04 | Ao gerar CIA (Comunicado de Inconformidade na Análise) | Inclui PDF do CIA no processo SEI | `IncluirDocumento` (tipo R, PDF Base64) |
| 03 | PPCI_DEFERIDO | P04 | Ao deferir o PPCI pelo analista | Inclui documento de deferimento no processo SEI | `IncluirDocumento` (tipo G, HTML) |
| 04 | CA_EMITIDO | P07 | Ao emitir Comunicado de Aprovação na vistoria | Inclui PDF do laudo de aprovação de vistoria no processo SEI | `IncluirDocumento` (tipo R, PDF Base64) |
| 05 | CIV_EMITIDO | P07 | Ao emitir CIV (Comunicado de Inconformidade na Vistoria) | Inclui PDF do CIV no processo SEI | `IncluirDocumento` (tipo R, PDF Base64) |
| 06 | APPCI_EMITIDO | P08 | Ao emitir o APPCI (Alvará de Prevenção e Proteção Contra Incêndio) | Inclui PDF do APPCI no processo SEI; conclui o processo SEI de licenciamento | `IncluirDocumento` + `ConcluirProcesso` |
| 07 | RECURSO_INTERPOSTO | P10 | Ao protocolar recurso administrativo pelo RT/RU | Cria processo SEI tipo "Recurso Administrativo PPCI — CBM-RS"; vincula ao processo de licenciamento de origem | `GerarProcedimento` (com `ProcedimentoRelacionado`) |
| 08 | DECISAO_RECURSO_1A_INSTANCIA | P10 | Ao registrar decisão do CHEFE_SSEG_BBM | Inclui PDF da decisão de primeira instância no processo de recurso do SEI | `IncluirDocumento` (tipo R, PDF Base64) |
| 09 | DECISAO_RECURSO_2A_INSTANCIA | P10 | Ao registrar acórdão da Junta de 3 Oficiais | Inclui PDF do acórdão; conclui o processo SEI de recurso | `IncluirDocumento` + `ConcluirProcesso` |
| 10 | EXTINCAO_REGISTRADA | P12 | Ao registrar extinção do licenciamento (pelo cidadão ou pelo admin) | Inclui termo de extinção em HTML no processo SEI; conclui o processo SEI | `IncluirDocumento` (tipo G, HTML) + `ConcluirProcesso` |
| 11 | RENOVACAO_PROTOCOLADA | P14 | Ao protocolar renovação de licenciamento | Cria processo SEI tipo "Renovação APPCI — CBM-RS"; vincula ao processo de licenciamento de origem | `GerarProcedimento` (com `ProcedimentoRelacionado`) |
| 12 | RENOVACAO_APPCI_EMITIDO | P14 | Ao emitir novo APPCI após conclusão da renovação | Inclui PDF do APPCI renovado no processo de renovação do SEI; conclui processo de renovação | `IncluirDocumento` + `ConcluirProcesso` |

### 4.1 Notas sobre o Mapeamento

**Evento 01 (PPCI_PROTOCOLADO):** O processo SEI só é criado após a quitação do boleto (ou deferimento de isenção via P06), pois antes disso o protocolo não está definitivamente registrado. O número do processo SEI gerado é armazenado em `sol.integracao_sei.numero_processo_sei` e em `sol.licenciamento.numero_processo_sei` para referência futura em todos os outros eventos do mesmo licenciamento.

**Eventos 02, 04, 05 (CIA, CA, CIV):** Esses eventos podem ocorrer múltiplas vezes em um mesmo licenciamento (ex.: múltiplos CIVs em rounds de vistoria). Cada ocorrência gera um novo registro na outbox e um novo documento no SEI. O campo `tipo_evento` é não único por `licenciamento_id`.

**Evento 07 (RECURSO_INTERPOSTO):** O campo `ProcedimentoRelacionado` da operação `GerarProcedimento` deve ser preenchido com o ID do processo de licenciamento original (já armazenado em `integracao_sei` com tipo `PPCI_PROTOCOLADO`).

**Evento 11 (RENOVACAO_PROTOCOLADA):** Segue a mesma lógica do evento 07 — o processo de renovação no SEI é vinculado ao processo de licenciamento original.

---

## 5. Modelo de Dados — Tabela de Rastreabilidade

### 5.1 DDL PostgreSQL

```sql
-- Schema da aplicação SOL
CREATE TABLE sol.integracao_sei (
    id                    BIGSERIAL PRIMARY KEY,
    licenciamento_id      BIGINT NOT NULL REFERENCES sol.licenciamento(id),
    tipo_evento           VARCHAR(60) NOT NULL,
    -- Valores possíveis: PPCI_PROTOCOLADO, CIA_EMITIDA, PPCI_DEFERIDO,
    -- CA_EMITIDO, CIV_EMITIDO, APPCI_EMITIDO, RECURSO_INTERPOSTO,
    -- DECISAO_RECURSO_1A_INSTANCIA, DECISAO_RECURSO_2A_INSTANCIA,
    -- EXTINCAO_REGISTRADA, RENOVACAO_PROTOCOLADA, RENOVACAO_APPCI_EMITIDO
    numero_processo_sei   VARCHAR(30),
    -- Número formatado do processo SEI, ex: 10357.000001/2025-01
    -- Preenchido apenas para eventos que criam processo (GerarProcedimento)
    id_procedimento_sei   VARCHAR(30),
    -- ID interno (numérico) do procedimento no SEI
    -- Chave usada para IncluirDocumento, ConcluirProcesso, etc.
    id_documento_sei      VARCHAR(30),
    -- ID interno do documento incluído no SEI (quando aplicável)
    -- Preenchido para eventos IncluirDocumento
    status                VARCHAR(20) NOT NULL DEFAULT 'PENDENTE',
    -- Estados: PENDENTE, ENVIADO, ERRO, IGNORADO
    -- IGNORADO: para eventos que o SOL decidiu não enviar (ex: licenciamento cancelado antes de protocolo)
    tentativas            INT NOT NULL DEFAULT 0,
    dt_criacao            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dt_envio              TIMESTAMPTZ,
    -- Preenchida quando status muda para ENVIADO
    dt_ultimo_erro        TIMESTAMPTZ,
    -- Preenchida na última tentativa com falha
    mensagem_erro         TEXT,
    -- Mensagem do SOAP Fault ou exceção Java, para diagnóstico
    payload_json          JSONB
    -- Snapshot do payload enviado ao SEI (dados do domínio SOL)
    -- Útil para diagnóstico e re-envio manual sem precisar recriar o contexto
);

-- Índices
CREATE INDEX idx_integracao_sei_licenciamento
    ON sol.integracao_sei(licenciamento_id);

CREATE INDEX idx_integracao_sei_status_pendente
    ON sol.integracao_sei(status)
    WHERE status = 'PENDENTE';

CREATE INDEX idx_integracao_sei_tipo_evento
    ON sol.integracao_sei(tipo_evento);

CREATE INDEX idx_integracao_sei_id_procedimento
    ON sol.integracao_sei(id_procedimento_sei)
    WHERE id_procedimento_sei IS NOT NULL;

-- Comentários de tabela e colunas (boas práticas de DBA)
COMMENT ON TABLE sol.integracao_sei IS
    'Outbox de integração entre o SOL e o Sistema SEI. '
    'Cada linha representa um evento SOL que deve gerar uma ação no SEI. '
    'O worker de outbox processa registros com status PENDENTE.';

COMMENT ON COLUMN sol.integracao_sei.payload_json IS
    'Snapshot do payload enviado ou a enviar ao SEI. '
    'Não deve conter dados sensíveis além do necessário (LGPD).';
```

### 5.2 Coluna de Referência Rápida na Tabela de Licenciamento

Para facilitar consultas operacionais, recomenda-se adicionar à tabela `sol.licenciamento` as seguintes colunas:

```sql
ALTER TABLE sol.licenciamento
    ADD COLUMN numero_processo_sei   VARCHAR(30),
    ADD COLUMN id_procedimento_sei   VARCHAR(30);

COMMENT ON COLUMN sol.licenciamento.numero_processo_sei IS
    'Número do processo SEI criado para este licenciamento. '
    'Preenchido após o evento PPCI_PROTOCOLADO ser enviado com sucesso ao SEI.';
```

Isso evita joins frequentes com `sol.integracao_sei` em operações de consulta rápida.

### 5.3 Regra de Idempotência

Antes de criar qualquer registro na outbox, o `SeiEventListener` deve verificar se já existe um registro com o mesmo `licenciamento_id` e `tipo_evento` com status `ENVIADO`. Se existir, o evento é silenciosamente ignorado (não duplicado). Se existir com status `ERRO`, o worker de outbox tentará novamente automaticamente. Se não existir, o registro é criado com status `PENDENTE`.

---

## 6. Componente SeiGatewayService (Java Spring Boot 3)

### 6.1 Visão Geral da Classe

O `SeiGatewayService` é o único ponto de contato do SOL com a API SOAP do SEI. Ele encapsula toda a complexidade de geração de XML SOAP, parsing de respostas e retry. Nenhuma outra classe do SOL chama o SEI diretamente.

```java
package br.gov.cbmrs.sol.integracao.sei;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Base64;
import java.util.concurrent.Callable;

@Service
@Slf4j
@RequiredArgsConstructor
public class SeiGatewayService {

    private final SeiSoapClient soapClient;
    private final SeiProperties props;

    /**
     * Cria processo SEI do tipo "Licenciamento PPCI" (ou outro tipo configurado)
     * e retorna o número formatado e o ID interno do procedimento.
     *
     * Operação SOAP: GerarProcedimento
     *
     * Mapeamento de campos GerarProcedimento:
     *   SiglaSistema         = props.siglaSistema()
     *   IdentificacaoServico = props.identificacaoServico()
     *   IdUnidade            = props.idUnidadeProtocolo()
     *   ProcedimentoFormatado = null (SEI gera automaticamente)
     *   Tipo.IdTipoProcedimento = tipoProcedimento (parametro)
     *   Especificacao        = especificacao (ex: "Edificacao: Rua X, n 100, Porto Alegre")
     *   Descricao            = descricao    (ex: "PPCI - Processo de Licenciamento 2025")
     *   Interessados[0].Nome = nomeInteressado
     *   Interessados[0].SiglaContato = cpfCnpjInteressado (formatado sem pontos/tracos)
     *   NivelAcesso          = "0" (publico) ou "1" (restrito) — a definir com CBM-RS
     *   Assunto.CodigoEstruturado = assunto da tabela de assuntos SEI-RS (a configurar)
     */
    public SeiProcedimentoResult criarProcesso(
            String tipoProcedimento,
            String nomeInteressado,
            String cpfCnpjInteressado,
            String descricao,
            String especificacao,
            String idProcedimentoRelacionado) {

        return comRetry(() -> {
            log.info("SEI | GerarProcedimento | tipo={} | interessado={} | relacionado={}",
                tipoProcedimento, cpfCnpjInteressado, idProcedimentoRelacionado);

            String xmlRequest = soapClient.buildGerarProcedimento(
                props.siglaSistema(),
                props.identificacaoServico(),
                props.idUnidadeProtocolo(),
                tipoProcedimento,
                nomeInteressado,
                cpfCnpjInteressado,
                descricao,
                especificacao,
                idProcedimentoRelacionado
            );

            String xmlResponse = soapClient.enviar(xmlRequest);

            SeiProcedimentoResult result = soapClient.parseGerarProcedimento(xmlResponse);
            log.info("SEI | GerarProcedimento | OK | numeroProcedimento={} | idProcedimento={}",
                result.numeroProcedimento(), result.idProcedimento());
            return result;

        }, "GerarProcedimento tipo=" + tipoProcedimento);
    }

    /**
     * Inclui documento PDF externo (tipo R = recebido) em processo SEI existente.
     * O PDF e enviado codificado em Base64 no campo Conteudo do envelope SOAP.
     *
     * Operacao SOAP: IncluirDocumento
     *
     * Mapeamento de campos IncluirDocumento (documento externo):
     *   Documento.Tipo           = "R" (recebido/externo)
     *   Documento.IdSerie        = idSerie (ex: props.idSerieAppci())
     *   Documento.Descricao      = descricao
     *   Documento.NomeArquivo    = nomeArquivo (ex: "APPCI-00000361.pdf")
     *   Documento.Conteudo       = Base64.encode(pdfBytes)
     *   Documento.IdProcedimento = idProcedimento
     *
     * Retorna o ID interno do documento criado no SEI.
     */
    public String incluirDocumentoPdf(
            String idProcedimento,
            String idSerie,
            String descricao,
            byte[] pdfBytes,
            String nomeArquivo) {

        return comRetry(() -> {
            log.info("SEI | IncluirDocumento(PDF) | idProcedimento={} | arquivo={} | tamanho={}b",
                idProcedimento, nomeArquivo, pdfBytes.length);

            String base64 = Base64.getEncoder().encodeToString(pdfBytes);

            String xmlRequest = soapClient.buildIncluirDocumentoExterno(
                props.siglaSistema(),
                props.identificacaoServico(),
                props.idUnidadeProtocolo(),
                idProcedimento,
                idSerie,
                descricao,
                nomeArquivo,
                base64
            );

            String xmlResponse = soapClient.enviar(xmlRequest);
            String idDocumento = soapClient.parseIncluirDocumento(xmlResponse);

            log.info("SEI | IncluirDocumento(PDF) | OK | idDocumento={}", idDocumento);
            return idDocumento;

        }, "IncluirDocumento(PDF) proc=" + idProcedimento);
    }

    /**
     * Inclui documento HTML interno (tipo G = gerado) em processo SEI existente.
     * Utilizado para documentos gerados pelo proprio SEI com template HTML.
     *
     * Mapeamento de campos IncluirDocumento (documento gerado):
     *   Documento.Tipo           = "G" (gerado/interno)
     *   Documento.IdSerie        = idSerie
     *   Documento.Descricao      = descricao
     *   Documento.Conteudo       = htmlContent (nao e Base64, e string HTML direta)
     *   Documento.IdProcedimento = idProcedimento
     *
     * Retorna o ID interno do documento criado.
     */
    public String incluirDocumentoHtml(
            String idProcedimento,
            String idSerie,
            String descricao,
            String htmlContent) {

        return comRetry(() -> {
            log.info("SEI | IncluirDocumento(HTML) | idProcedimento={} | serie={}",
                idProcedimento, idSerie);

            String xmlRequest = soapClient.buildIncluirDocumentoGerado(
                props.siglaSistema(),
                props.identificacaoServico(),
                props.idUnidadeProtocolo(),
                idProcedimento,
                idSerie,
                descricao,
                htmlContent
            );

            String xmlResponse = soapClient.enviar(xmlRequest);
            String idDocumento = soapClient.parseIncluirDocumento(xmlResponse);

            log.info("SEI | IncluirDocumento(HTML) | OK | idDocumento={}", idDocumento);
            return idDocumento;

        }, "IncluirDocumento(HTML) proc=" + idProcedimento);
    }

    /**
     * Cadastra ou atualiza contato (interessado) no SEI.
     * Deve ser chamado antes de GerarProcedimento para garantir que o
     * cpfCnpj ja exista como contato cadastrado no SEI-RS.
     *
     * Operacao SOAP: IncluirOuAtualizarContato
     *
     * Mapeamento:
     *   Contato.SiglaContato = cpfCnpj (sem pontos/tracos/barra)
     *   Contato.Nome         = nome
     *   Contato.Email        = email (pode ser null)
     *   Contato.IdTipoContato = "2" (pessoa fisica) ou "3" (pessoa juridica)
     *                           determinado pelo tamanho do cpfCnpj
     */
    public void sincronizarContato(String cpfCnpj, String nome, String email) {

        comRetry(() -> {
            log.info("SEI | IncluirOuAtualizarContato | cpfCnpj={}*** | nome={}",
                cpfCnpj.substring(0, 3), nome);

            String tipoContato = cpfCnpj.replaceAll("\\D", "").length() == 11 ? "2" : "3";
            String sigla = cpfCnpj.replaceAll("\\D", "");

            String xmlRequest = soapClient.buildIncluirOuAtualizarContato(
                props.siglaSistema(),
                props.identificacaoServico(),
                sigla,
                nome,
                email,
                tipoContato
            );

            soapClient.enviar(xmlRequest);
            log.info("SEI | IncluirOuAtualizarContato | OK");
            return null;

        }, "IncluirOuAtualizarContato cpfCnpj=" + cpfCnpj.substring(0, 3) + "***");
    }

    /**
     * Conclui um processo no SEI na unidade de protocolo do CBM-RS.
     *
     * Operacao SOAP: ConcluirProcesso
     *
     * Mapeamento:
     *   IdUnidade      = props.idUnidadeProtocolo()
     *   IdProcedimento = idProcedimento
     */
    public void concluirProcesso(String idProcedimento) {

        comRetry(() -> {
            log.info("SEI | ConcluirProcesso | idProcedimento={}", idProcedimento);

            String xmlRequest = soapClient.buildConcluirProcesso(
                props.siglaSistema(),
                props.identificacaoServico(),
                props.idUnidadeProtocolo(),
                idProcedimento
            );

            soapClient.enviar(xmlRequest);
            log.info("SEI | ConcluirProcesso | OK");
            return null;

        }, "ConcluirProcesso proc=" + idProcedimento);
    }

    /**
     * Consulta dados e andamento de processo SEI.
     * Utilizado pelo job de polling (secao 8) para detectar mudancas de estado.
     *
     * Operacao SOAP: ConsultarProcedimento
     *
     * Retorna objeto com: numeroProcedimento, situacao, unidadesAberto,
     * ultimoAndamento (data + descricao), listagem de documentos.
     */
    public SeiProcedimentoInfo consultarProcedimento(String idProcedimento) {

        return comRetry(() -> {
            log.debug("SEI | ConsultarProcedimento | idProcedimento={}", idProcedimento);

            String xmlRequest = soapClient.buildConsultarProcedimento(
                props.siglaSistema(),
                props.identificacaoServico(),
                props.idUnidadeProtocolo(),
                idProcedimento,
                "S", // SinRetornarAssuntos
                "S", // SinRetornarInteressados
                "N", // SinRetornarObservacoes
                "S", // SinRetornarAndamentoGeracao
                "S"  // SinRetornarAndamentoConclucao
            );

            String xmlResponse = soapClient.enviar(xmlRequest);
            return soapClient.parseConsultarProcedimento(xmlResponse);

        }, "ConsultarProcedimento proc=" + idProcedimento);
    }

    /**
     * Executa a operacao com retry exponencial.
     * Lanca SeiIntegracaoException apos esgotadas as tentativas.
     */
    private <T> T comRetry(Callable<T> operacao, String descricaoOperacao) {
        int tentativas = 0;
        Exception ultimaExcecao = null;

        while (tentativas < props.retryMax()) {
            try {
                return operacao.call();
            } catch (Exception e) {
                tentativas++;
                ultimaExcecao = e;
                log.warn("SEI | Falha na operacao '{}' | tentativa {}/{} | erro: {}",
                    descricaoOperacao, tentativas, props.retryMax(), e.getMessage());

                if (tentativas < props.retryMax()) {
                    try {
                        Thread.sleep(props.retryDelayMs() * (long) tentativas);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        throw new SeiIntegracaoException("Retry interrompido", ie);
                    }
                }
            }
        }

        throw new SeiIntegracaoException(
            "Operacao SEI '" + descricaoOperacao + "' falhou apos " + props.retryMax() + " tentativas",
            ultimaExcecao
        );
    }
}
```

### 6.2 Records de Resultado

```java
// Resultado da operacao GerarProcedimento
public record SeiProcedimentoResult(
    String numeroProcedimento,   // ex: "10357.000001/2025-01"
    String idProcedimento        // ex: "12345" (ID interno SEI)
) {}

// Resultado da operacao ConsultarProcedimento
public record SeiProcedimentoInfo(
    String numeroProcedimento,
    String situacao,             // "Aberto" | "Concluido"
    String ultimoAndamentoData,
    String ultimoAndamentoDescricao,
    boolean estaAberto
) {}

// Excecao customizada para falhas de integracao com o SEI
public class SeiIntegracaoException extends RuntimeException {
    public SeiIntegracaoException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

---

## 7. Padrão Outbox — Garantia de Entrega

### 7.1 Conceito

O padrão Transactional Outbox garante que eventos de domínio do SOL sejam entregues ao SEI mesmo se o SEI estiver offline no momento do evento, se o processo SOL sofrer crash após a transação de banco, ou se a rede estiver indisponível.

O princípio é simples: ao invés de chamar o SEI diretamente dentro da transação do SOL, o SOL insere um registro na tabela `sol.integracao_sei` (a "outbox") dentro da mesma transação do banco. Um job separado (o "worker") lê periodicamente essa tabela e faz as chamadas ao SEI de forma assíncrona.

### 7.2 Fluxo Detalhado

```
Transacao do banco SOL (atomica):
  1. Servico de dominio persiste mudanca de estado
     (ex: APPCI criado em sol.appci)
  2. SeiEventListener.onEvent() insere registro
     em sol.integracao_sei com status='PENDENTE'
  3. COMMIT (ambas as operacoes confirmadas juntas)
  4. SOL retorna HTTP 200 ao frontend

Fora da transacao (job agendado, a cada 2 minutos):
  5. OutboxWorkerJob busca registros PENDENTE
  6. Para cada registro:
     a. Chama SeiGatewayService com dados do payload_json
     b. Se sucesso: atualiza status='ENVIADO', salva idDocumentoSei, dt_envio=NOW()
     c. Se falha: incrementa tentativas, atualiza dt_ultimo_erro, mensagem_erro
     d. Se tentativas >= 3: status permanece 'ERRO' (sem novo retry automatico)
  7. Log de execucao do job
```

### 7.3 SeiEventListener

```java
@Component
@RequiredArgsConstructor
public class SeiEventListener {

    private final SeiIntegracaoRepository repository;
    private final ObjectMapper objectMapper;

    @EventListener
    @Transactional
    // Executado dentro da transacao do servico de dominio que publicou o evento
    public void onAppciEmitido(AppciEmitidoEvent event) {
        SeiIntegracaoEntity registro = SeiIntegracaoEntity.builder()
            .licenciamentoId(event.licenciamentoId())
            .tipoEvento("APPCI_EMITIDO")
            .status(StatusIntegracaoSei.PENDENTE)
            .payloadJson(toJson(event))
            .build();
        repository.save(registro);
    }

    @EventListener
    @Transactional
    public void onCiaEmitida(CiaEmitidaEvent event) {
        // padrao identico
    }

    // ... demais eventos mapeados na secao 4

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            return "{}";
        }
    }
}
```

### 7.4 OutboxWorkerJob

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxWorkerJob {

    private final SeiIntegracaoRepository repository;
    private final SeiGatewayService gateway;
    private final SeiEventProcessador processador;

    @Scheduled(fixedDelay = 120_000) // a cada 2 minutos
    @Transactional
    public void processarPendentes() {
        List<SeiIntegracaoEntity> pendentes = repository.buscarPendentesParaProcessar(20);
        log.info("SEI | OutboxWorker | {} registros pendentes encontrados", pendentes.size());

        for (SeiIntegracaoEntity registro : pendentes) {
            try {
                processador.processar(registro);
                registro.setStatus(StatusIntegracaoSei.ENVIADO);
                registro.setDtEnvio(Instant.now());
                repository.save(registro);
            } catch (SeiIntegracaoException e) {
                registro.setTentativas(registro.getTentativas() + 1);
                registro.setDtUltimoErro(Instant.now());
                registro.setMensagemErro(e.getMessage());
                if (registro.getTentativas() >= 3) {
                    registro.setStatus(StatusIntegracaoSei.ERRO);
                    log.error("SEI | OutboxWorker | Registro {} marcado como ERRO apos 3 tentativas",
                        registro.getId());
                    // TODO: notificar administrador por e-mail
                }
                repository.save(registro);
            }
        }
    }
}
```

### 7.5 SQL do Job de Busca de Pendentes

```sql
-- Busca registros pendentes para o worker processar
-- Condição dt_ultimo_erro: aguarda 5 minutos entre tentativas do mesmo registro
SELECT *
FROM sol.integracao_sei
WHERE status = 'PENDENTE'
  AND tentativas < 3
  AND (
      dt_ultimo_erro IS NULL
      OR dt_ultimo_erro < NOW() - INTERVAL '5 minutes'
  )
ORDER BY dt_criacao ASC
LIMIT 20;
```

### 7.6 Garantias e Limitações

| Garantia | Descricao |
|---|---|
| At-least-once delivery | Um evento pode gerar mais de uma tentativa; o SEI pode receber a chamada mais de uma vez se a resposta de sucesso se perder (idempotência deve ser verificada) |
| Durabilidade | O registro na outbox é durável: sobrevive a restart do servidor SOL |
| Isolamento | Falha no SEI não afeta a transação de negócio do SOL |
| Ordenação | Registros são processados em ordem de `dt_criacao` por `licenciamento_id`; porém, não há garantia absoluta de ordem entre licenciamentos distintos |
| Limitação | O mesmo `tipo_evento` por `licenciamento_id` pode ser enviado duplicado se o worker processar duas vezes antes do COMMIT da atualização de status. Mitigação: índice único parcial ou lock de linha |

---

## 8. Polling de Retorno — Consulta de Andamento SEI

### 8.1 Motivação

O SEI não disponibiliza webhooks ou qualquer mecanismo de push. Portanto, o SOL não pode ser notificado automaticamente quando um servidor do CBM-RS realiza um despacho, uma assinatura ou qualquer outra ação diretamente no SEI. Para o processo de Recurso Administrativo (P10), pode ser relevante saber se o processo de recurso SEI foi concluído manualmente por um servidor.

### 8.2 Escopo do Polling

O polling é aplicado exclusivamente a processos SEI do tipo "Recurso Administrativo PPCI" que estejam com status `ENVIADO` na outbox (ou seja, já foram criados no SEI) e cujo licenciamento correspondente ainda esteja em estado de recurso ativo no SOL.

O polling não é aplicado a processos de licenciamento principal (o SOL controla o ciclo de vida) nem a processos de renovação (idem).

### 8.3 SeiPollingJob

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class SeiPollingJob {

    private final SeiIntegracaoRepository repository;
    private final SeiGatewayService gateway;
    private final RecursoService recursoService;

    @Scheduled(cron = "0 0 7 * * *") // Diariamente as 07:00
    public void verificarProcessosRecursoAbertos() {
        log.info("SEI | PollingJob | Iniciando verificacao de processos de recurso abertos");

        List<SeiIntegracaoEntity> recursosAbertos =
            repository.buscarRecursosEnviadosComProcedimentoAberto();

        for (SeiIntegracaoEntity registro : recursosAbertos) {
            try {
                SeiProcedimentoInfo info =
                    gateway.consultarProcedimento(registro.getIdProcedimentoSei());

                if (!info.estaAberto()) {
                    log.info("SEI | PollingJob | Processo {} concluido no SEI — notificando SOL",
                        info.numeroProcedimento());
                    recursoService.notificarProcessoSeiConcluido(
                        registro.getLicenciamentoId(),
                        info.ultimoAndamentoData(),
                        info.ultimoAndamentoDescricao()
                    );
                }
            } catch (SeiIntegracaoException e) {
                log.warn("SEI | PollingJob | Erro ao consultar processo {} | erro: {}",
                    registro.getIdProcedimentoSei(), e.getMessage());
            }
        }

        log.info("SEI | PollingJob | Concluido | {} processos verificados", recursosAbertos.size());
    }
}
```

### 8.4 SQL de Suporte ao Polling

```sql
-- Busca processos de recurso que foram enviados ao SEI e ainda nao foram concluidos no SOL
SELECT i.*
FROM sol.integracao_sei i
JOIN sol.licenciamento l ON l.id = i.licenciamento_id
WHERE i.tipo_evento = 'RECURSO_INTERPOSTO'
  AND i.status = 'ENVIADO'
  AND i.id_procedimento_sei IS NOT NULL
  AND l.status_recurso IN ('RECURSO_ATIVO', 'AGUARDANDO_DECISAO_2A_INSTANCIA');
```

### 8.5 Comportamento ao Detectar Conclusão

Se o polling detectar que o processo de recurso SEI foi concluído manualmente por um servidor (fora do fluxo normal SOL), o SOL apenas registra a informação no log e no histórico de andamentos do licenciamento. O SOL não altera automaticamente o status do recurso com base nessa informação — a decisão permanece com o operador. O objetivo é apenas auditoria e alerta.

---

## 9. Geração de Documentos para o SEI

### 9.1 Estratégia de Geração

Todos os documentos enviados ao SEI como PDF são gerados internamente pelo SOL. Não há dependência do SEI para a geração de documentos. O SOL possui os dados completos do licenciamento e gera os documentos no momento do evento, antes de armazená-los na outbox.

### 9.2 Stack de Geração de PDF

```
Template Thymeleaf (HTML + CSS)
        |
        v
Thymeleaf TemplateEngine (Spring Boot)
        |
        v (HTML renderizado)
Flying Saucer (org.xhtmlrenderer)
        |
        v (PDF/A-1b)
byte[] — armazenado temporariamente em memoria
        |
        v
Payload JSONB na outbox (Base64)
  OU
Referencia ao nodeRef Alfresco (se o ECM for intermediario)
```

### 9.3 Documentos e Seus Templates

| Documento | Template Thymeleaf | Formato SEI | Observacao |
|---|---|---|---|
| APPCI | `templates/sei/appci.html` | Tipo R (PDF) | Inclui QR Code de verificacao, assinatura digital Gov.br do RT |
| CIA | `templates/sei/cia.html` | Tipo R (PDF) | Lista os itens reprovados com referencias normativas |
| Laudo de Vistoria (CA) | `templates/sei/laudo-aprovacao.html` | Tipo R (PDF) | Inclui foto da edificacao, geolocalização, assinatura do inspetor |
| CIV | `templates/sei/civ.html` | Tipo R (PDF) | Lista nao-conformidades da vistoria |
| Decisao de Recurso | `templates/sei/decisao-recurso.html` | Tipo G (HTML) | Votacao da Junta (3 oficiais), fundamentacao |
| Acórdão 2.ª Instância | `templates/sei/acordao.html` | Tipo G (HTML) | Documento formal da decisao da Junta |
| Termo de Extinção | `templates/sei/extincao.html` | Tipo G (HTML) | Registro formal de extinção, motivo, responsavel |

### 9.4 Conformidade PDF/A-1b

Todos os PDFs enviados ao SEI devem ser gerados no formato PDF/A-1b (ISO 19005-1), conforme exigência para arquivamento de longo prazo em sistemas documentais do governo. O Flying Saucer com iText 2.x suporta esse formato diretamente. A equipe de desenvolvimento deve validar a conformidade com ferramenta como veraPDF.

### 9.5 Tamanho Máximo

O SEI possui limite de tamanho para documentos enviados via SOAP (verificar com PROCERGS — tipicamente 10 MB). Laudos de vistoria com fotos devem ter imagens comprimidas antes da inclusão no PDF para não ultrapassar esse limite.

---

## 10. Tipos de Processo SEI (Configuração do SEI-RS)

### 10.1 Pré-requisito de Configuração

Para que a integração funcione, o administrador do SEI-RS (PROCERGS ou administrador local CBM-RS com permissão de configuração) deve criar previamente os tipos de processo e os tipos de documento (séries) listados a seguir. Essa atividade deve ocorrer na Fase 0 do plano de implementação (seção 14).

### 10.2 Tipos de Processo (TipoProcedimento)

| Codigo SEI (a definir) | Nome no SEI | Descricao | Nivel de Acesso Padrao |
|---|---|---|---|
| A definir | Licenciamento PPCI — CBM-RS | Processo principal de licenciamento de segurança contra incêndio e pânico em edificações | Restrito |
| A definir | Recurso Administrativo PPCI — CBM-RS | Recurso interposto em 1.ª ou 2.ª instância contra decisão de licenciamento do CBM-RS | Restrito |
| A definir | Renovação APPCI — CBM-RS | Renovação de Alvará de Prevenção e Proteção Contra Incêndio | Restrito |
| A definir | Extinção de Licenciamento — CBM-RS | Extinção de processo de licenciamento ativo por solicitação ou de ofício | Restrito |

Os códigos numéricos gerados pelo SEI ao criar esses tipos devem ser informados ao CBM-RS para configuração nas variáveis da seção 3.3.

### 10.3 Tipos de Documento (Série)

| Nome no SEI | Tipo | Formato Enviado pelo SOL | Uso |
|---|---|---|---|
| PPCI — Plano de Prevenção e Proteção Contra Incêndio | Externo (R) | PDF/A-1b em Base64 | Formulário PPCI submetido pelo RT via wizard P03 |
| CIA — Comunicado de Inconformidade na Análise | Externo (R) | PDF/A-1b em Base64 | Comunicado gerado pelo analista em P04 |
| APPCI — Alvará de Prevenção e Proteção Contra Incêndio | Externo (R) | PDF/A-1b em Base64 | Alvará gerado pelo SOL em P08 |
| Laudo de Vistoria Presencial | Externo (R) | PDF/A-1b em Base64 | Laudo emitido pelo inspetor em P07 (CA) |
| CIV — Comunicado de Inconformidade na Vistoria | Externo (R) | PDF/A-1b em Base64 | Comunicado emitido pelo inspetor em P07 |
| Decisão de Recurso Administrativo — 1.ª Instância | Interno (G) | HTML | Decisão do CHEFE_SSEG_BBM em P10 |
| Acórdão de Recurso Administrativo — 2.ª Instância | Interno (G) | HTML | Acórdão da Junta de 3 Oficiais em P10 |
| Termo de Extinção de Licenciamento | Interno (G) | HTML | Registro formal de extinção em P12 |
| Deferimento de PPCI | Interno (G) | HTML | Documento de deferimento da análise técnica em P04 |

### 10.4 Assuntos (Tabela de Assuntos SEI-RS)

O campo `Assunto.CodigoEstruturado` da operação `GerarProcedimento` exige um código da tabela de assuntos configurada no SEI-RS. O CBM-RS deve solicitar à PROCERGS o código de assunto correspondente a "Prevenção e Combate a Incêndio" ou equivalente na taxonomia do SEI-RS, ou solicitar a criação de um código específico para o CBM-RS.

---

## 11. Tratamento de Erros e Resiliência

### 11.1 Cenários de Falha e Resposta

| Cenário | Comportamento do SOL | Comportamento da Outbox |
|---|---|---|
| SEI fora do ar (timeout, conexão recusada) | SOL continua operando normalmente; usuário não é afetado | Registro permanece PENDENTE; worker tenta novamente em 2 minutos |
| SEI retorna SOAP Fault (erro de negócio) | Idem | Worker incrementa tentativas; loga mensagem_erro com payload completo |
| SEI retorna código HTTP 5xx | Idem | Idem |
| SEI retorna código HTTP 4xx (credenciais, parâmetro inválido) | Log de alerta imediato — provavelmente erro de configuração | Após 3 tentativas, status = ERRO; alerta administrador |
| Processo SEI não encontrado ao incluir documento | Worker detecta, verifica se deve recriar o processo | Dependendo da regra de negócio, pode criar novo registro PPCI_PROTOCOLADO |
| Duplicata (mesmo evento enviado duas vezes) | O SEI pode criar dois documentos idênticos — aceitável para documentos; não aceitável para processos | O SeiEventListener verifica existência com status ENVIADO antes de criar novo registro PENDENTE |
| Timeout de rede durante upload de PDF grande | SeiSoapClient tem timeout configurado (10 segundos); conexão é encerrada | Retry automático — PDF é re-enviado na próxima tentativa |

### 11.2 Alerta Automático para Administrador

Quando um registro atinge status `ERRO` (3 tentativas esgotadas), o `OutboxWorkerJob` deve:

1. Registrar log ERROR com todos os detalhes do registro.
2. Enviar e-mail de alerta para o endereço configurado em `sol.admin.email` com:
   - ID do registro na outbox
   - `licenciamento_id`
   - `tipo_evento`
   - Mensagem de erro da última tentativa
   - Link para o dashboard administrativo

3. Se o registro permanece com status `ERRO` por mais de 24 horas, enviar novo alerta.

### 11.3 Dashboard de Monitoramento

A tabela `sol.integracao_sei` deve ser exposta por um endpoint protegido por perfil `ADMIN_SEI`:

```
GET /api/admin/sei/integracao?status=ERRO&page=0&size=20
GET /api/admin/sei/integracao/{id}
POST /api/admin/sei/integracao/{id}/reprocessar  # Redefine status para PENDENTE, zera tentativas
POST /api/admin/sei/integracao/{id}/ignorar       # Define status IGNORADO
```

Esse dashboard permite que o administrador SOL monitore a saúde da integração sem precisar acessar o banco de dados diretamente.

### 11.4 Circuito de Retry e Backoff

O retry dentro do `SeiGatewayService.comRetry()` usa backoff linear (delay × número da tentativa). O retry do `OutboxWorkerJob` usa intervalo de 5 minutos entre tentativas (controlado pela condição `dt_ultimo_erro`). Isso significa:

- Tentativa 1: imediata (quando o worker roda pela primeira vez)
- Tentativa 2: mínimo 5 minutos depois
- Tentativa 3: mínimo 10 minutos depois
- Após tentativa 3: status = ERRO, sem retry automático (requer intervenção manual via dashboard)

---

## 12. Segurança

### 12.1 Proteção da API Key

- A `IdentificacaoServico` (API key do SEI) é armazenada exclusivamente como variável de ambiente `SEI_API_KEY`.
- A variável nunca aparece em: código-fonte, arquivos versionados (`.git`), logs de aplicação, dumps de banco de dados, ou payloads de API expostas ao frontend.
- Em ambientes Kubernetes, utilizar Secret com acesso restrito ao namespace do SOL.
- Rotação da API key: em caso de comprometimento, solicitar nova chave à PROCERGS e atualizar o Secret sem redeploy do código.

### 12.2 Comunicação Segura

- Toda comunicação com o endpoint SEI é realizada exclusivamente via HTTPS (TLS 1.2 ou superior).
- O certificado SSL do servidor SEI-RS deve ser validado (não usar `trustAllCerts` em produção).
- Se o SEI-RS disponibilizar lista de CAs permitidas, configurar o `SSLContext` do cliente HTTP do SOL para aceitar apenas essas CAs.
- Se o SEI-RS permitir restrição por IP de origem, solicitar a inclusão do IP do servidor SOL em produção na whitelist do SEI-RS.

### 12.3 Política de Logging

- Logs de chamadas ao SEI registram apenas: tipo de operação, ID do procedimento (quando disponível), status HTTP/SOAP, duração da chamada e timestamp.
- O conteúdo dos PDFs (bytes Base64) nunca é logado — pode conter dados pessoais (nome, CPF, endereço, planta da edificação).
- O `payload_json` armazenado na outbox contém apenas os campos necessários para reprocessamento — deve ser revisado para excluir dados sensíveis além do mínimo necessário.
- Logs de erro incluem a mensagem do SOAP Fault, mas não o envelope SOAP completo (que conteria a API key em texto claro nos headers).

### 12.4 Conformidade LGPD

- O SEI recebe apenas os dados necessários para a criação do processo: nome e CPF/CNPJ do RU/RT, descrição da edificação, município.
- Dados médicos, financeiros, de vulnerabilidade social ou quaisquer dados sensíveis (artigo 5.º, inciso II, da LGPD) não são transmitidos ao SEI.
- O campo `Especificacao` do processo SEI deve conter apenas a identificação da edificação (logradouro, número, município) — não deve incluir dados pessoais adicionais além dos já exigidos pelo processo administrativo.
- O CBM-RS deve incluir a integração SOL–SEI no Registro de Atividades de Tratamento (RAT) do RIPD (Relatório de Impacto à Proteção de Dados Pessoais), com indicação da base legal (artigo 7.º, inciso III — cumprimento de obrigação legal ou regulatória).

### 12.5 Controle de Acesso Interno

- O endpoint de dashboard administrativo (`/api/admin/sei/*`) requer perfil `ADMIN_SEI` no Keycloak.
- O `OutboxWorkerJob` e o `SeiPollingJob` são jobs internos — não expostos via HTTP.
- A tabela `sol.integracao_sei` no PostgreSQL deve ter acesso de escrita apenas para o usuário de serviço da aplicação SOL; analistas com acesso read-only ao banco podem consultar, mas não modificar registros.

---

## 13. O Que NÃO É Integrado (e Por Quê)

A tabela a seguir documenta as atividades e funcionalidades do SOL que permanecem exclusivamente no SOL, sem espelho no SEI, com a justificativa técnica e de negócio.

| Funcionalidade SOL | Processo | Motivo para NÃO Integrar |
|---|---|---|
| Wizard de preenchimento do PPCI | P03 | O SEI não possui capacidade de formulário interativo. O PPCI é preenchido e validado no SOL; apenas o PDF final assinado vai ao SEI |
| Pagamento de boleto (GRU/BANRISUL) | P11 | Integração com PROCERGS/BANRISUL é independente do SEI. Comprovante de pagamento é dado de negócio do SOL; não tem valor documental independente no SEI |
| Emissão e consulta de boleto | P11 | Idem acima |
| Jobs automáticos (suspensão, alerta de prazo) | P13 | O SEI não é notificado de eventos intermediários de prazo. O SOL controla prazos internamente. O SEI reflete apenas eventos de estado final (deferimento, extinção, conclusão de recurso) |
| Upload de anexos técnicos (plantas, ART, memorial) | P03 | Anexos técnicos ficam no Alfresco (ECM do SOL). O SEI recebe apenas o documento gerado e assinado, não os anexos brutos de projeto |
| Ciência de recurso (prazo D+30) | P05 | O prazo de ciência é processado pelo SOL internamente. Não gera documento no SEI — é uma notificação administrativa, não um documento arquivístico |
| Troca de envolvidos (RT, RU, proprietário) | P09 | Alteração de cadastro de envolvidos é dado operacional do SOL. Não gera documento formal no SEI (a menos que a gestão decida criar um tipo de documento específico — não previsto nesta versão) |
| Análise técnica detalhada (critério por critério) | P04 | O processo de análise tramita internamente no SOL. Apenas o documento final (CIA ou deferimento) vai ao SEI |
| Vistoria em tablet (fotos, geolocalização) | P07 | A coleta de dados da vistoria é operacional. Apenas o laudo final (CA ou CIV) vai ao SEI |
| Suspensão automática de APPCI vencido | P13 | Evento de suspensão é operacional. Se a gestão decidir registrar sobrestamento no SEI, pode ser implementado futuramente com `SobrestarProcesso` — não está no escopo desta versão |
| Assinatura digital do RT via Gov.br | P03 | A assinatura é realizada no SOL (integração Gov.br). O PDF já chega assinado ao momento de envio ao SEI, como documento externo — o SEI não realiza nova assinatura |
| Renovação: análise técnica e vistoria | P14 | O processo interno de análise e vistoria da renovação tramita no SOL. Apenas o evento de protocolo (início) e o APPCI renovado (conclusão) vão ao SEI |

---

## 14. Plano de Implementação da Integração

### 14.1 Fase 0 — Pré-requisitos (responsabilidade CBM-RS e PROCERGS)

Esta fase não envolve desenvolvimento de software. Deve ser concluída antes do início da Fase 1.

| Atividade | Responsável | Prazo Sugerido |
|---|---|---|
| Solicitar cadastro do SOL como sistema integrador no SEI-RS | CBM-RS (TI) junto à PROCERGS | Mês 1 |
| Receber SiglaSistema e IdentificacaoServico da PROCERGS | CBM-RS (TI) | Mês 1 |
| Confirmar ID da unidade de protocolo CBM-RS no SEI | CBM-RS (TI) / PROCERGS | Mês 1 |
| Solicitar criação dos 4 tipos de processo no SEI-RS (seção 10.2) | CBM-RS (Administração) | Mês 1 |
| Solicitar criação dos 9 tipos de documento/série no SEI-RS (seção 10.3) | CBM-RS (Administração) | Mês 1 |
| Solicitar acesso ao ambiente de homologação do SEI-RS | CBM-RS (TI) / PROCERGS | Mês 1 |
| Receber os códigos numéricos dos tipos de processo e série criados | CBM-RS (TI) / PROCERGS | Mês 1–2 |
| Atualizar `application-homolog.yml` com os códigos recebidos | Equipe de desenvolvimento | Após recebimento |

### 14.2 Fase 1 — Infraestrutura Base + Evento P03

Foco: infraestrutura técnica da integração e o evento mais importante (criação do processo SEI ao protocolar PPCI).

| Entregável | Descricao |
|---|---|
| `SeiProperties` | Classe de configuração tipada |
| `SeiSoapClient` | Cliente SOAP com suporte a timeout, TLS e logging |
| `SeiGatewayService` | Métodos `criarProcesso` e `sincronizarContato` |
| `SeiIntegracaoEntity` + `SeiIntegracaoRepository` | Entidade JPA e repositório Spring Data |
| Migração Flyway: `sol.integracao_sei` | Script DDL de criação da tabela |
| `SeiEventListener` para `PpciProtocoladoEvent` | Listener do primeiro evento |
| `OutboxWorkerJob` (v1) | Worker básico de outbox |
| Testes de integração com WireMock (mock SOAP) | Cobertura do fluxo end-to-end em CI |

### 14.3 Fase 2 — Eventos P04 e P07

| Entregável | Descricao |
|---|---|
| Templates Thymeleaf para CIA e Laudo de Vistoria | `templates/sei/cia.html`, `templates/sei/laudo-aprovacao.html` |
| `SeiGatewayService.incluirDocumentoPdf()` | Método de inclusão de PDF |
| Listeners para `CiaEmitidaEvent`, `PpciDeferidoEvent`, `CaEmitidoEvent`, `CivEmitidoEvent` | 4 novos listeners |
| Templates Thymeleaf para deferimento e CIV | `templates/sei/deferimento.html`, `templates/sei/civ.html` |
| Testes de geração PDF/A-1b (validação com veraPDF) | Garantia de conformidade |

### 14.4 Fase 3 — Eventos P08 e P10

| Entregável | Descricao |
|---|---|
| Template APPCI com QR Code | `templates/sei/appci.html` |
| Listeners para `AppciEmitidoEvent`, `RecursoInterpostoEvent`, `DecisaoRecurso1aInstanciaEvent`, `DecisaoRecurso2aInstanciaEvent` | 4 novos listeners |
| `SeiGatewayService.concluirProcesso()` | Método de conclusão de processo |
| Lógica de vinculação `ProcedimentoRelacionado` em `GerarProcedimento` | Para processos de recurso |
| Dashboard administrativo v1 (read-only) | Endpoint `/api/admin/sei/integracao` |

### 14.5 Fase 4 — Eventos P12 e P14

| Entregável | Descricao |
|---|---|
| Listeners para `ExtincaoRegistradaEvent`, `RenovacaoProtocoladaEvent`, `RenovacaoAppciEmitidoEvent` | 3 novos listeners |
| Templates para termo de extinção e renovação | `templates/sei/extincao.html` |
| Dashboard administrativo v2 (reprocessamento, ignorar) | Endpoints POST `/reprocessar` e `/ignorar` |
| Alerta por e-mail para registros em status ERRO | Integração com serviço de e-mail SOL |

### 14.6 Fase 5 — Polling, Monitoramento e Hardening

| Entregável | Descricao |
|---|---|
| `SeiPollingJob` | Job diário de consulta de processos de recurso abertos |
| `SeiGatewayService.consultarProcedimento()` | Método de consulta |
| Alerta automático por e-mail (erros persistentes > 24h) | Escalonamento de alertas |
| Runbook operacional | Documento de procedimentos para operadores SOL (fora do escopo desta especificação) |
| Validação de conformidade PDF/A-1b em CI | Integração do veraPDF no pipeline |

---

## 15. Diagrama de Sequência — Evento APPCI Emitido

O evento APPCI Emitido é o mais relevante da integração: representa a conclusão do processo de licenciamento e a emissão do documento legal que autoriza o funcionamento da edificação. O diagrama abaixo mostra o fluxo completo.

```
Servidor SOL     SOL Backend        Banco PostgreSQL    Job Scheduler    SEI SOAP API
(navegador)      (Spring Boot)      (PostgreSQL)        (OutboxWorker)   (PROCERGS)
     |                |                    |                  |               |
     | [1] POST       |                    |                  |               |
     | /api/appci/    |                    |                  |               |
     | emitir/{id}    |                    |                  |               |
     |--------------->|                    |                  |               |
     |                | [2] Valida regras  |                  |               |
     |                | (PrPCI uploaded,   |                  |               |
     |                | taxas quitadas,    |                  |               |
     |                | análise aprovada)  |                  |               |
     |                |                    |                  |               |
     |                | [3] Gera PDF APPCI |                  |               |
     |                | (Thymeleaf +       |                  |               |
     |                | Flying Saucer)     |                  |               |
     |                |                    |                  |               |
     |                | [4] BEGIN TRANSACTION                 |               |
     |                |                    |                  |               |
     |                | INSERT sol.appci   |                  |               |
     |                |------------------->|                  |               |
     |                |                    |                  |               |
     |                | UPDATE sol.        |                  |               |
     |                | licenciamento      |                  |               |
     |                | status=DEFERIDO    |                  |               |
     |                |------------------->|                  |               |
     |                |                    |                  |               |
     |                | INSERT             |                  |               |
     |                | sol.integracao_sei |                  |               |
     |                | (APPCI_EMITIDO,    |                  |               |
     |                |  status=PENDENTE,  |                  |               |
     |                |  payload=PDF+meta) |                  |               |
     |                |------------------->|                  |               |
     |                |                    |                  |               |
     |                | [5] COMMIT         |                  |               |
     |                |------------------->|                  |               |
     |                |                    |                  |               |
     | [6] HTTP 200   |                    |                  |               |
     | (APPCI emitido)|                    |                  |               |
     |<---------------|                    |                  |               |
     |                |                    |                  |               |
     .                .                    .                  .               .
     . (aprox. 2 min depois)               .                  .               .
     .                .                    .                  .               .
     |                |                    |                  |               |
     |                |          [7] SELECT pendentes         |               |
     |                |                    |<-----------------|               |
     |                |                    |                  |               |
     |                |       Retorna registro APPCI_EMITIDO  |               |
     |                |                    |----------------->|               |
     |                |                    |                  |               |
     |                |   [8] SeiGatewayService.incluirDocumentoPdf()         |
     |                |                    |        IncluirDocumento (SOAP)   |
     |                |                    |                  |-------------->|
     |                |                    |                  |               |
     |                |                    |                  |  [9] Retorna  |
     |                |                    |                  |  idDocumento  |
     |                |                    |                  |<--------------|
     |                |                    |                  |               |
     |                |   [10] SeiGatewayService.concluirProcesso()           |
     |                |                    |        ConcluirProcesso (SOAP)   |
     |                |                    |                  |-------------->|
     |                |                    |                  |               |
     |                |                    |                  | [11] Confirma |
     |                |                    |                  |<--------------|
     |                |                    |                  |               |
     |                | [12] UPDATE        |                  |               |
     |                | integracao_sei     |                  |               |
     |                | status=ENVIADO,    |                  |               |
     |                | idDocumentoSei=X,  |                  |               |
     |                | dtEnvio=NOW()      |                  |               |
     |                |                    |<-----------------|               |
     |                |                    | COMMIT           |               |
     |                |                    |----------------->|               |
     |                |                    |                  |               |
     | (log auditoria: APPCI enviado ao SEI, processo concluido)              |
```

### 15.1 Notas sobre o Diagrama

- Os passos [1]–[6] ocorrem dentro de uma única requisição HTTP síncrona do usuário. O usuário recebe o retorno em milissegundos, independentemente do SEI.
- Os passos [7]–[12] ocorrem assincronamente, tipicamente em até 2 minutos após a confirmação ao usuário.
- Se o SEI estiver fora do ar no passo [8], o worker registra o erro e tentará novamente na próxima execução (2 minutos depois). O APPCI já foi emitido no SOL — o usuário não é afetado.
- O `idProcedimentoSei` utilizado no passo [10] (`ConcluirProcesso`) foi obtido no evento `PPCI_PROTOCOLADO` (quando o processo foi criado no SEI) e está armazenado em `sol.integracao_sei` daquele evento anterior.

---

## 16. Configuração do Ambiente de Homologação

### 16.1 Ambiente de Homologação do SEI-RS

O SEI-RS mantém um ambiente de homologação separado do ambiente de produção. O CBM-RS deve solicitar à PROCERGS o URL do endpoint de homologação (`SeiWS.php` de homologação) e as credenciais de teste correspondentes.

Recomenda-se que a integração seja desenvolvida e validada integralmente no ambiente de homologação antes de qualquer ativação em produção.

### 16.2 Profiles Spring Boot

A separação entre ambientes é feita por profiles Spring Boot:

```yaml
# application-homolog.yml
sei:
  endpoint: https://hom.sei.rs.gov.br/sei/ws/SeiWS.php
  sigla-sistema: SOL_CBMRS_HOM
  identificacao-servico: ${SEI_API_KEY_HOM}
  # demais propriedades com valores de homologação

# application-prod.yml
sei:
  endpoint: https://sei.rs.gov.br/sei/ws/SeiWS.php
  sigla-sistema: SOL_CBMRS
  identificacao-servico: ${SEI_API_KEY}
  # demais propriedades com valores de produção
```

Ativação via variável de ambiente:
```bash
# Homologação
export SPRING_PROFILES_ACTIVE=homolog

# Produção
export SPRING_PROFILES_ACTIVE=prod
```

### 16.3 Testes Automatizados com Mock SOAP

Para o pipeline de CI/CD (onde não há acesso ao SEI-RS de homologação), utilizar WireMock ou SoapUI Mock Service para simular o endpoint SOAP do SEI:

```java
// Exemplo de teste de integração com WireMock
@SpringBootTest
@WireMockTest(httpPort = 8089)
class SeiGatewayServiceIntegrationTest {

    @Test
    void deveIncluirDocumentoPdfComSucesso() {
        // Stub SOAP response
        stubFor(post(urlEqualTo("/sei/ws/SeiWS.php"))
            .withRequestBody(containing("IncluirDocumento"))
            .willReturn(aResponse()
                .withStatus(200)
                .withBody(carregarFixture("sei/incluir-documento-response-ok.xml"))));

        // Executa
        String idDocumento = gateway.incluirDocumentoPdf(
            "12345", props.idSerieAppci(),
            "APPCI 00000361", pdfBytes, "APPCI-00000361.pdf"
        );

        assertThat(idDocumento).isEqualTo("98765");
        verify(postRequestedFor(urlEqualTo("/sei/ws/SeiWS.php"))
            .withRequestBody(containing("SOL_CBMRS")));
    }
}
```

### 16.4 Checklist de Validação Pré-Go-Live

Antes de ativar a integração em produção, verificar:

| Item | Verificado |
|---|---|
| Endpoint de produção do SEI-RS confirmado com PROCERGS | [ ] |
| API key de produção armazenada em Kubernetes Secret (não em arquivo) | [ ] |
| Tipos de processo e série criados no SEI-RS de produção | [ ] |
| Teste de `GerarProcedimento` com PPCI real em homologação | [ ] |
| Teste de `IncluirDocumento` (PDF) com APPCI real em homologação | [ ] |
| Teste de `ConcluirProcesso` em homologação | [ ] |
| Validação de PDF/A-1b com veraPDF em todos os templates | [ ] |
| Dashboard administrativo funcionando com perfil ADMIN_SEI | [ ] |
| Job `OutboxWorkerJob` testado com SEI simulado fora do ar | [ ] |
| Alerta por e-mail de registros ERRO configurado e testado | [ ] |
| Logs revisados para ausência de dados sensíveis | [ ] |
| Inclusão da integração no RAT/RIPD do CBM-RS (LGPD) | [ ] |
| Runbook operacional entregue para a equipe de operações | [ ] |

---

---

## 17. Escopo Excluído e Justificativas (Documento Formal para Processo Licitatório)

Esta seção constitui o registro formal e definitivo dos limites do escopo desta integração. Destina-se especificamente ao uso no processo licitatório de contratação da empresa responsável pelo desenvolvimento do SOL moderno, estabelecendo com precisão o que **não** integra o objeto contratual descrito nesta especificação, e as razões técnicas e normativas de cada exclusão.

A empresa contratada não poderá alegar omissão de escopo ou solicitar aditivos contratuais fundamentados nos itens abaixo, pois cada um está aqui explicitamente delimitado, justificado e atribuído a responsável.

---

### 17.1 Integrações com Outros Sistemas — Fora do Escopo desta Especificação

#### 17.1.1 Integração SOL — PROCERGS SOE / meu.rs.gov.br (Autenticação)

| Campo | Conteúdo |
|---|---|
| **Descrição do item excluído** | Autenticação e autorização de usuários (cidadãos, RTs, servidores) via OIDC/OAuth2 com o provedor de identidade PROCERGS SOE / meu.rs.gov.br |
| **Protocolo técnico** | OpenID Connect (OIDC) / OAuth2 — fluxo Implicit e Authorization Code com PKCE |
| **Motivo da exclusão** | Trata-se de uma integração de identidade digital, completamente independente do ciclo documental gerenciado pelo SEI. Os contratos técnicos são distintos: OIDC para autenticação; SOAP com API key para o SEI. Unificar ambos numa mesma especificação geraria ambiguidade de responsabilidade contratual |
| **Onde está especificado** | `Requisitos_P01_Autenticacao_StackAtual.md` (stack atual) e `Requisitos_P01_Autenticacao_Java.md` (stack moderna) |
| **Responsável pela implementação** | Empresa contratada — item de escopo de P01, não desta integração |
| **Responsável pela configuração no provedor** | CBM-RS / PROCERGS — cadastro do SOL como client OIDC no SOE |

---

#### 17.1.2 Integração SOL — PROCERGS / BANRISUL (Pagamento de Boletos)

| Campo | Conteúdo |
|---|---|
| **Descrição do item excluído** | Geração de boletos bancários GRU/BANRISUL, confirmação de pagamento via arquivo de retorno CNAB 240, integração com PIX PROCERGS |
| **Protocolo técnico** | API PROCERGS para boletos + CNAB 240 (arquivo batch) + webhook de liquidação |
| **Motivo da exclusão** | Integração de pagamento independente do SEI. O SEI não tem ciência da existência de boletos ou pagamentos — recebe documentos técnicos e administrativos somente após o pagamento já ter sido processado e confirmado internamente pelo SOL. A mistura dos dois fluxos prejudicaria a clareza de ambas as especificações e dificultaria a atribuição de responsabilidades em caso de falha |
| **Onde está especificado** | `Requisitos_P11_PagamentoBoleto_StackAtual.md` e `Requisitos_P11_PagamentoBoleto_JavaModerna.md` |
| **Responsável pela implementação** | Empresa contratada — item de escopo de P11 |
| **Responsável pela configuração no provedor** | CBM-RS / PROCERGS — cadastro do SOL como sistema gerador de boletos |

---

#### 17.1.3 Integração SOL — Alfresco (ECM / Repositório de Arquivos)

| Campo | Conteúdo |
|---|---|
| **Descrição do item excluído** | Armazenamento e recuperação de arquivos enviados por cidadãos e RTs (plantas, memoriais descritivos, ART/RRT, laudos em rascunho, fotografias de vistoria) no ECM Alfresco |
| **Tecnologia** | Alfresco Community/Enterprise — API CMIS ou API REST Alfresco; campo `identificadorAlfresco` (nodeRef) no banco do SOL |
| **Motivo da exclusão** | O Alfresco é o repositório interno do SOL. O SEI nunca acessa o Alfresco diretamente. O SEI recebe exclusivamente os documentos finais gerados pelo SOL (PDFs assinados de APPCI, CIA, laudos de vistoria, decisões de recurso) — nunca os arquivos brutos de projeto. A integração Alfresco é transparente para o SEI. A eventual substituição do Alfresco pelo MinIO ou outro ECM (prevista na proposta de modernização) não altera em nada o comportamento desta integração |
| **Onde está tratado** | Campo `identificadorAlfresco` em `ArquivoED` (código-fonte `SOLCBM.BackEnd16-06`); DDL campo `identificador_alfresco` em `sol.arquivo` |
| **Responsável pela implementação** | Empresa contratada — integração interna do SOL |
| **Decisão de migração do ECM** | CBM-RS / gestão do projeto — decisão administrativa sobre manter Alfresco ou migrar para MinIO |

---

#### 17.1.4 Integração SOL — CREA-RS / CAU-BR (Validação de RT)

| Campo | Conteúdo |
|---|---|
| **Descrição do item excluído** | Consulta às bases do CREA-RS e CAU-BR para validação da situação do registro profissional do Responsável Técnico no momento do cadastro (P02) e da submissão do PPCI (P03) |
| **Motivo da exclusão** | Integração com conselhos profissionais independente do SEI. Não produz documentos arquivísticos — é uma validação operacional de negócio. Especificada nos requisitos de P02 e P03 |
| **Onde está especificado** | `Requisitos_P02_CadastroUsuario_StackAtual.md` e `Requisitos_P03_SubmissaoPPCI_StackAtual.md` |
| **Responsável pela implementação** | Empresa contratada — item de escopo de P02/P03 |

---

### 17.2 Aspectos do SEI Não Controlados pelo SOL

#### 17.2.1 Tramitação Interna no SEI

| Campo | Conteúdo |
|---|---|
| **Descrição** | Despachos, encaminhamentos entre unidades, assinaturas de documentos por servidores, criação de blocos de assinatura, sobrestamento manual, conclusão manual de processos — todas as ações realizadas por servidores do CBM-RS diretamente na interface do SEI |
| **Motivo da exclusão** | O SOL não tem como controlar, e não deve controlar, o comportamento interno de outro sistema sob administração da PROCERGS e do CBM-RS. Tentar fazê-lo via API tornaria o SOL frágil: dependente da configuração interna do SEI-RS, sujeita a mudança a qualquer momento pela PROCERGS sem aviso prévio ao CBM-RS. O princípio arquitetural desta integração é: **o SOL entrega, o SEI administra**. O SOL apenas consulta o resultado final via polling (seção 8) |
| **Consequência contratual** | A empresa contratada não desenvolverá nenhuma funcionalidade no SOL para controlar ou direcionar o fluxo interno de processos no SEI. Qualquer customização de workflow dentro do SEI é responsabilidade da PROCERGS e do CBM-RS, fora do objeto desta contratação |

---

#### 17.2.2 Assinatura Digital de Documentos no SEI por Usuários Externos

| Campo | Conteúdo |
|---|---|
| **Descrição** | Fluxo de assinatura de documentos por cidadãos, RTs ou proprietários diretamente dentro do SEI, via módulo de Acesso Externo do SEI ou integração SEI + Gov.br |
| **Motivo da exclusão** | A assinatura digital do RT e do RU é realizada no próprio SOL (integração Gov.br no SOL). O documento chega ao SEI já assinado, como documento externo em PDF/A. O SEI não realiza nova assinatura — apenas arquiva. A habilitação do módulo Gov.br no SEI-RS (mod-sei-assinar-govbr) é uma decisão de infraestrutura da PROCERGS, fora do escopo do desenvolvimento do SOL |
| **Consequência contratual** | A empresa contratada não desenvolverá nenhuma funcionalidade de redirecionamento de usuários para assinatura no SEI |

---

### 17.3 Migração de Dados Históricos

#### 17.3.1 Migração do SOL Legado para o Novo Banco de Dados SOL

| Campo | Conteúdo |
|---|---|
| **Descrição** | Extração, transformação e carga (ETL) dos dados do sistema SOL legado (Oracle + Alfresco) para o novo banco PostgreSQL do SOL moderno |
| **Status** | Prevista e especificada na Etapa 5 do plano de modernização (`Apresentacao_Executiva_Modernizacao_SOL.md`) |
| **Relação com a integração SEI** | Nenhuma. A migração histórica para o PostgreSQL SOL não implica envio de dados históricos ao SEI |

---

#### 17.3.2 Retroalimentação do SEI com Licenciamentos Históricos

| Campo | Conteúdo |
|---|---|
| **Descrição** | Criação retroativa de processos SEI para licenciamentos já concluídos antes do Go-Live da integração |
| **Motivo da exclusão** | Decisão administrativa do CBM-RS, não requisito técnico desta integração. As opções possíveis são: (a) não migrar o histórico para o SEI — licenciamentos anteriores ao Go-Live ficam apenas no banco SOL; (b) migrar seletivamente os processos dos últimos N anos por meio de script ETL pontual; (c) criar processos SEI apenas para novos licenciamentos a partir do Go-Live. Cada opção tem custo e implicações distintos que dependem de decisão da gestão do CBM-RS. Nenhuma dessas opções afeta o funcionamento da integração para processos gerados após o Go-Live |
| **Consequência contratual** | A empresa contratada não executará migração retroativa de dados para o SEI. Caso o CBM-RS decida realizar tal migração futuramente, ela deverá ser objeto de aditivo ou novo processo licitatório específico |

---

### 17.4 Matriz de Responsabilidades — Escopo Excluído

A tabela abaixo consolida os itens excluídos, indicando o responsável por cada um para fins de clareza no processo licitatório.

| Item Excluído | Responsável pela Decisão | Responsável pela Implementação | Documento de Referência |
|---|---|---|---|
| Autenticação OIDC / SOE PROCERGS | CBM-RS / PROCERGS | Empresa contratada (escopo P01) | `Requisitos_P01_*` |
| Pagamento de boletos / CNAB 240 | CBM-RS / PROCERGS | Empresa contratada (escopo P11) | `Requisitos_P11_*` |
| ECM Alfresco / MinIO | CBM-RS (decisão de infraestrutura) | Empresa contratada (escopo P03) | Código-fonte SOL legado |
| Validação CREA-RS / CAU-BR | CBM-RS | Empresa contratada (escopo P02/P03) | `Requisitos_P02_*`, `Requisitos_P03_*` |
| Tramitação interna no SEI | CBM-RS / PROCERGS | Fora do objeto (responsabilidade PROCERGS) | — |
| Assinatura externa via SEI | CBM-RS / PROCERGS | Fora do objeto (módulo PROCERGS) | — |
| Migração legado → PostgreSQL SOL | CBM-RS | Empresa contratada (Etapa 5) | `Apresentacao_Executiva_Modernizacao_SOL.md` |
| Migração histórica → SEI | CBM-RS (decisão administrativa) | Fora do objeto (aditivo futuro se decidido) | — |

---

### 17.5 Critério de Interpretação de Escopo em Caso de Dúvida

Na eventualidade de divergência de interpretação sobre se determinada funcionalidade está ou não incluída nesta especificação, aplica-se o seguinte critério:

> **Uma funcionalidade está NO escopo desta especificação se, e somente se, ela está explicitamente descrita nas seções 1 a 16 deste documento.**

Qualquer funcionalidade não descrita nestas seções, mesmo que relacionada ao SEI ou a sistemas externos, é considerada **fora do escopo** e não pode ser exigida da empresa contratada sem o devido aditivo contratual, precedido de especificação técnica complementar aprovada pelo CBM-RS.

Este critério aplica-se inclusive a funcionalidades que possam ser tecnicamente viáveis com a API SOAP do SEI (como `SobrestarProcesso`, `GerarBloco`, acesso externo automatizado), mas que não estão descritas neste documento. A viabilidade técnica não implica inclusão no escopo contratual.

---

*Fim do documento. Versão 1.1 — 23/03/2026.*
*Elaborado com base no código-fonte do SOL (SOLCBM.BackEnd16-06 e SOLCBM.FrontEnd16-06), na documentação SeiWS.php e nos requisitos levantados nas sessões de análise do projeto SOL-CBM-RS.*
