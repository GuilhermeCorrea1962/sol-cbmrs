# Requisitos Completos — P02: Cadastro de Usuário / Responsável Técnico
## Stack Atual (Java EE / WildFly / arqjava4)

**Versão:** 1.0
**Referência de código-fonte:** SOLCBM.BackEnd16-06
**Escopo:** Definição completa de requisitos funcionais, regras de negócio, modelo de dados, contratos REST e configurações de segurança para manutenção ou evolução do processo P02 sem mudança de tecnologia.

---

## 1. Visão Geral do Processo

O Processo P02 cobre o ciclo completo de **cadastro do Responsável Técnico (RT)** no sistema SOL/CBM-RS. É composto por duas jornadas paralelas:

| Jornada | Ator | Descrição |
|---|---|---|
| **J1 — Autoatendimento** | Cidadão (RT) | Preenche dados pessoais, gradações, especializações, endereços e anexa documentos; ao final submete para análise |
| **J2 — Análise back-office** | Analista CBM | Lista cadastros pendentes, assume análise, aprova ou reprova; supervisor (CENTRALADM) pode sobrescrever |

### 1.1 Máquina de Estados do Cadastro (`StatusCadastro`)

```
INCOMPLETO(0)
    │
    ├─[concluirCadastro: doc faltando]──────────────→ INCOMPLETO (permanece)
    │
    └─[concluirCadastro: todos docs presentes]
          │
          ▼
   ANALISE_PENDENTE(1)
          │
          └─[incluirAnaliseCadastro: analista assume]
                │
                ▼
         EM_ANALISE(2)
                │
                ├─[alterarStatus: APROVADO]──→ APROVADO(3)   [envia e-mail]
                ├─[alterarStatus: REPROVADO]─→ REPROVADO(4)  [envia e-mail]
                └─[alterarStatus: CANCELADO]─→ ANALISE_PENDENTE(1) [sem e-mail]
```

**Descrições dos status:**
- `INCOMPLETO(0)` — "Cadastro incompleto"
- `ANALISE_PENDENTE(1)` — "Seu cadastro foi enviado para análise."
- `EM_ANALISE(2)` — "Cadastro em processo de análise"
- `APROVADO(3)` — "Cadastro aprovado"
- `REPROVADO(4)` — "Cadastro reprovado"

### 1.2 Máquina de Estados da Análise (`StatusAnalise`)

```
EM_ANALISE(1) → CANCELADO(2) | APROVADO(3) | REPROVADO(4)
```

---

## 2. Stack Tecnológica

| Camada | Tecnologia |
|---|---|
| Container / Runtime | WildFly 10+ (Java EE 7) |
| API REST | JAX-RS 2.0 via RESTEasy |
| Negócio / Transações | EJB 3.2 — `@Stateless`, `@TransactionAttribute` |
| Injeção de Dependência | CDI 1.2 — `@Inject`, `@PostConstruct` |
| Persistência | JPA 2.1 com Hibernate (consultas por `DetachedCriteria`) |
| Segurança / Autenticação | `@SOEAuthRest` (arqjava4 PROCERGS) |
| Autorização | `@Permissao(objeto, acao)` interceptor (arqjava4 PROCERGS) |
| Sessão do usuário | `SessionMB` / `CidadaoSessionMB` (arqjava4 PROCERGS) |
| Upload de arquivos | `MultipartFormDataInput` (RESTEasy multipart) |
| Mensagens | `MessageProvider` (bundle de mensagens arqjava4) |
| Notificações | `NotificacaoRN` (interno — dispara notificação e opcionalmente e-mail) |
| Logging | SLF4J (`@Inject Logger`) |
| Utilitários | Apache Commons Lang 3 (`StringUtils`) |

---

## 3. Estrutura de Pacotes / Classes Envolvidas

```
com.procergs.solcbm
├── usuario/
│   ├── UsuarioRestImpl.java          ← recurso JAX-RS (@Path("/usuarios"))
│   ├── UsuarioRN.java                ← EJB de regras de negócio
│   ├── UsuarioConclusaoCadastroRN.java ← EJB de conclusão / submissão
│   └── UsuarioBD.java                ← DAO (AppBD)
├── analisecadastro/
│   ├── AnaliseCadastroRestImpl.java  ← recurso JAX-RS (@Path("/adm/analise-cadastros"))
│   ├── AnaliseCadastroRN.java        ← EJB de regras de negócio
│   └── AnaliseCadastroBD.java        ← DAO (AppBD)
├── graduacaousuario/
│   ├── GraduacaoUsuarioRN.java       ← EJB para graduações do usuário
│   └── GraduacaoUsuarioBD.java
├── especializacaousuario/
│   ├── EspecializacaoUsuarioRN.java  ← EJB para especializações do usuário
│   └── EspecializacaoUsuarioBD.java
├── enderecousuario/
│   ├── EnderecoUsuarioRN.java        ← EJB para endereços do usuário
│   └── EnderecoUsuarioBD.java
├── arquivo/
│   └── ArquivoRN.java                ← EJB para upload/download/exclusão de arquivos
├── ed/
│   ├── UsuarioED.java                ← @Entity CBM_USUARIO
│   ├── AnaliseCadastroED.java        ← @Entity CBM_ANALISE_CADASTRO
│   ├── GraduacaoUsuarioED.java       ← @Entity CBM_GRADUACAO_USUARIO
│   ├── EspecializacaoUsuarioED.java  ← @Entity CBM_ESPECIALIZACAO_USUARIO
│   └── EnderecoUsuarioED.java        ← @Entity CBM_ENDERECO_USUARIO
├── remote/ed/
│   ├── Usuario.java                  ← DTO de entrada/saída para usuário
│   ├── Cadastro.java                 ← DTO de listagem de cadastros pendentes
│   ├── AnaliseCadastro.java          ← DTO de análise (entrada/saída)
│   ├── Status.java                   ← DTO retorno de concluirCadastro
│   └── Arquivo.java                  ← DTO de arquivo
└── enumeration/
    ├── StatusCadastro.java
    ├── StatusAnalise.java
    └── TipoArquivo.java
```

---

## 4. Modelo de Dados

### 4.1 Tabela `CBM_USUARIO`

**Classe JPA:** `UsuarioED`
**Sequência:** `CBM_ID_USUARIO_SEQ` (allocationSize = 1)

| Coluna | Tipo | Restrição | Campo Java |
|---|---|---|---|
| `NRO_INT_USUARIO` | BIGINT | PK | `id` |
| `TXT_NOME` | VARCHAR | NOT NULL (`@NotNull`) | `nome` |
| `TXT_CPF` | VARCHAR | NOT NULL (`@NotNull`) | `cpf` |
| `TXT_RG` | VARCHAR | nullable | `rg` |
| `TXT_UF_EMISSOR_RG` | VARCHAR | nullable | `estadoEmissor` |
| `NRO_INT_ARQUIVO_RG` | BIGINT | FK → CBM_ARQUIVO, nullable | `arquivoRG` (OneToOne LAZY) |
| `DTH_NASCIMENTO` | DATE | NOT NULL (`@NotNull @Temporal(DATE)`) | `dtNascimento` (Calendar) |
| `TXT_NOME_MAE` | VARCHAR | NOT NULL (`@NotNull`) | `nomeMae` |
| `TXT_EMAIL` | VARCHAR | NOT NULL (`@NotNull`) | `email` |
| `TXT_TELEFONE1` | VARCHAR | NOT NULL (`@NotNull`) | `telefone1` |
| `TXT_TELEFONE2` | VARCHAR | nullable | `telefone2` |
| status | (enum) | nullable | `status` (StatusCadastro) |
| mensagemStatus | VARCHAR | nullable | `mensagemStatus` |
| `CTR_DTH_INC` | TIMESTAMP | gerenciado por AppED | `ctrDthInc` (Calendar) |
| `CTR_DTH_ATU` | TIMESTAMP | gerenciado por AppED | `ctrDthAtu` (Calendar) |

**Relações:**
- `graduacoesUsuario` — `@OneToMany(LAZY)` → `GraduacaoUsuarioED` (Set)
- `enderecosUsuario` — `@OneToMany(LAZY)` → `EnderecoUsuarioED` (List)
- `arquivoRG` — `@OneToOne(LAZY)` → `ArquivoED`

**Named Query:**
```java
@NamedQuery(name = "UsuarioED.consulta",
  query = "select u from UsuarioED u left join fetch u.arquivoRG where u.id = :id")
```

---

### 4.2 Tabela `CBM_GRADUACAO_USUARIO`

**Classe JPA:** `GraduacaoUsuarioED`
**Sequência:** `CBM_ID_GRAD_USUARIO_SEQ` (allocationSize = 1)

| Coluna | Tipo | Restrição | Campo Java |
|---|---|---|---|
| `NRO_INT_GRADUACAO_USUARIO` | BIGINT | PK | `id` |
| `NRO_INT_GRADUACAO` | BIGINT | FK → CBM_GRADUACAO, NOT NULL | `graduacao` (ManyToOne LAZY) |
| `NRO_INT_USUARIO` | BIGINT | FK → CBM_USUARIO, NOT NULL | `usuario` (ManyToOne LAZY) |
| `NRO_INT_ARQUIVO_ID_PROFIS` | BIGINT | FK → CBM_ARQUIVO, nullable | `arquivoIdProfissional` (OneToOne LAZY) |
| `TXT_ID_PROFISSIONAL` | VARCHAR | nullable | `idProfissional` |
| `TXT_UF_GRADUACAO` | VARCHAR | nullable | `estadoEmissor` |

**Named Query:**
```java
@NamedQuery(name = "GraduacaoUsuarioED.consulta",
  query = "select gu from GraduacaoUsuarioED gu join fetch gu.graduacao " +
          "join fetch gu.usuario left join fetch gu.arquivoIdProfissional " +
          "where gu.id = :id")
```

---

### 4.3 Tabela `CBM_ESPECIALIZACAO_USUARIO`

**Classe JPA:** `EspecializacaoUsuarioED`
**Sequência:** `CBM_ID_ESPEC_USUARIO_SEQ` (allocationSize = 1)

| Coluna | Tipo | Restrição | Campo Java |
|---|---|---|---|
| `NRO_INT_ESPEC_USUARIO` | BIGINT | PK | `id` |
| `NRO_INT_ESPECIALIZACAO` | BIGINT | FK → CBM_ESPECIALIZACAO, NOT NULL | `especializacao` (ManyToOne LAZY) |
| `NRO_INT_USUARIO` | BIGINT | FK → CBM_USUARIO, NOT NULL | `usuario` (ManyToOne LAZY) |
| `NRO_INT_ARQUIVO` | BIGINT | FK → CBM_ARQUIVO, nullable | `arquivo` (OneToOne LAZY) |

**Named Query:**
```java
@NamedQuery(name = "EspecializacaoUsuarioED.consulta",
  query = "select eu from EspecializacaoUsuarioED eu join fetch eu.especializacao " +
          "join fetch eu.usuario left join fetch eu.arquivo where eu.id = :id")
```

---

### 4.4 Tabela `CBM_ENDERECO_USUARIO`

**Classe JPA:** `EnderecoUsuarioED`
**Sequência:** `CBM_ID_ENDERECO_USUARIO_SEQ` (allocationSize = 1)

| Coluna | Tipo | Restrição | Campo Java |
|---|---|---|---|
| `NRO_INT_ENDERECO_USUARIO` | BIGINT | PK | `id` |
| `NRO_INT_ENDERECO` | BIGINT | FK → CBM_ENDERECO, nullable | `endereco` (ManyToOne LAZY) |
| `NRO_INT_USUARIO` | BIGINT | FK → CBM_USUARIO, nullable | `usuario` (ManyToOne LAZY) |
| `TP_ENDERECO` | VARCHAR | nullable | `tpEndereco` (TipoEndereco enum) |
| `IND_USAR_RESIDENCIAL` | CHAR(1) | nullable ('S'/'N') | `usarResidencial` (Boolean via `SimNaoBooleanConverter`) |

**Named Query:**
```java
@NamedQuery(name = "EnderecoUsuarioED.consulta",
  query = "select e from EnderecoUsuarioED e join fetch e.endereco " +
          "join fetch e.usuario where e.id = :id")
```

---

### 4.5 Tabela `CBM_ANALISE_CADASTRO`

**Classe JPA:** `AnaliseCadastroED`
**Sequência:** `CBM_ID_ANALISE_CADASTRO_SEQ` (allocationSize = 1)

| Coluna | Tipo | Restrição | Campo Java |
|---|---|---|---|
| `NRO_INT_ANALISE_CADASTRO` | BIGINT | PK | `id` |
| `NRO_INT_USUARIO` | BIGINT | FK → CBM_USUARIO, NOT NULL | `usuario` (OneToOne LAZY) |
| `TXT_NOME_USUARIO` | VARCHAR | nullable | `nomeUsuario` |
| `NRO_INT_ID_USUARIO_SOE` | BIGINT | nullable | `idUsuarioSoe` |
| status | (enum) | nullable | `status` (StatusAnalise) |
| `TXT_JUSTIFICATIVA` | VARCHAR | nullable | `justificativa` |

**Named Query:**
```java
@NamedQuery(name = "AnaliseCadastroED.consulta",
  query = "select a from AnaliseCadastroED a join fetch a.usuario where a.id = :id")
```

---

## 5. Contratos REST

### 5.1 Recurso de Usuário — `UsuarioRestImpl`

**Anotações de classe:**
```java
@Path("/usuarios")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@SOEAuthRest
```

| # | Método | Path | Parâmetros | Delegação | Retorno |
|---|---|---|---|---|---|
| 1 | `GET` | `/{cpf}` | `@PathParam("cpf")` | `usuarioRN.consultaPorCpf(cpf)` | `200 Usuario` / `204` se null |
| 2 | `GET` | `/` | `@QueryParam("cpf")` | `usuarioRN.consultaPorCpf(cpf)` | `200 Usuario` / `204` se null |
| 3 | `POST` | `/` | `Usuario` no body | `usuarioRN.incluir(usuario)` | `201 Created` |
| 4 | `PUT` | `/{id}` | `@PathParam("id")`, `Usuario` no body | `usuarioRN.alterar(id, usuario)` | `200 Usuario` |
| 5 | `PATCH` | `/{id}` | `@PathParam("id")` | `usuarioConclusaoCadastroRN.concluirCadastro(id)` | `200 Status` |
| 6 | `GET` | `/isUsuarioRtValido` | — | `usuarioRN.isUsuarioLogadoRtValido()` | `200 boolean` |
| 7 | `GET` | `/{cpf}/credenciamento` | `@PathParam("cpf")` | `analiseInstrutorRN.consultarPorCadastroUsuario(cpf)` | `200` |
| 8 | `POST` | `/{idUsuario}/arquivo-rg` | `@PathParam`, multipart | `usuarioRN.incluirArquivoRG(...)` | `201 Arquivo` |
| 9 | `GET` | `/{idUsuario}/arquivo-rg` | `@PathParam` | `usuarioRN.downloadArquivoRG(idUsuario)` | `200 octet-stream` |
| 10 | `PUT` | `/{idUsuario}/arquivo-rg` | `@PathParam`, multipart | `usuarioRN.alterarArquivoRG(...)` | `200 Arquivo` |
| 11 | `POST` | `/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | `@PathParam`, multipart | `usuarioRN.incluirArquivoDocProfissional(...)` | `201 Arquivo` |
| 12 | `GET` | `/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | `@PathParam` | `usuarioRN.downloadArquivoDocProfissional(...)` | `200 octet-stream` |
| 13 | `PUT` | `/{idUsuario}/graduacoes/{idGraduacao}/arquivo` | `@PathParam`, multipart | `usuarioRN.alterarArquivoDocProfissional(...)` | `200 Arquivo` |
| 14 | `POST` | `/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | `@PathParam`, multipart | `usuarioRN.incluirArquivoEspecializacao(...)` | `201 Arquivo` |
| 15 | `GET` | `/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | `@PathParam` | `usuarioRN.downloadArquivoEspecializacao(...)` | `200 octet-stream` |
| 16 | `PUT` | `/{idUsuario}/especializacoes/{idEspecializacao}/arquivo` | `@PathParam`, multipart | `usuarioRN.alterarArquivoEspecializacao(...)` | `200 Arquivo` |

**Padrão de recebimento de upload (endpoints 8, 10, 11, 13, 14, 16):**
```java
@Consumes(MediaType.MULTIPART_FORM_DATA)
public Response incluirArquivo(@PathParam("idUsuario") long idUsuario,
                               MultipartFormDataInput input) {
    // Extrai InputStream e nomeArquivo do MultipartFormDataInput
}
```

---

### 5.2 Recurso de Análise de Cadastro — `AnaliseCadastroRestImpl`

**Anotações de classe:**
```java
@Path("/adm/analise-cadastros")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@SOEAuthRest
```

| # | Método | Path | Parâmetros | Delegação | Retorno |
|---|---|---|---|---|---|
| 1 | `GET` | `/em-analise` | — | `analiseCadastroRN.listarCadastrosEmAnalise(filtro)` | `200 List<Cadastro>` |
| 2 | `POST` | `/` | `Cadastro` no body | `analiseCadastroRN.incluirAnaliseCadastro(cadastro)` | `201 Created` + `Location: /adm/analise-cadastros/{id}` |
| 3 | `GET` | `/{id}` | `@PathParam("id")` | `analiseCadastroRN.consultaAnaliseCadastro(id)` | `200 AnaliseCadastro` |
| 4 | `PUT` | `/{id}` | `@PathParam("id")`, `AnaliseCadastro` no body | `analiseCadastroRN.alterarStatusAnaliseCadastro(id, body)` | `200` |

**Construção do filtro no endpoint GET /em-analise:**
```java
AnaliseCadastroED filtro = new AnaliseCadastroED();
filtro.setIdUsuarioSoe(Long.parseLong(sessionMB.getUser().getId()));
filtro.setStatus(StatusAnalise.EM_ANALISE);
```

---

## 6. Requisitos Funcionais

### 6.1 RF-U-01 — Criar Cadastro de Usuário

**Endpoint:** `POST /usuarios`
**Classe:** `UsuarioRN.incluir(Usuario)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Campos obrigatórios no body `Usuario`:**

| Campo | Tipo Java | Validação JPA |
|---|---|---|
| `nome` | String | `@NotNull` |
| `cpf` | String | `@NotNull` (formato livre; único por constraint de BD) |
| `dtNascimento` | Calendar | `@NotNull @Temporal(DATE)` |
| `nomeMae` | String | `@NotNull` |
| `email` | String | `@NotNull` |
| `telefone1` | String | `@NotNull` |

**Campos opcionais:**

| Campo | Tipo Java | Observação |
|---|---|---|
| `rg` | String | RG do profissional |
| `estadoEmissor` | String | UF emissora do RG |
| `telefone2` | String | Segundo telefone |
| `graduacoes` | List\<Graduacao\> | Graduações profissionais |
| `especializacoes` | List\<Especializacao\> | Especializações |
| `enderecos` | List\<Endereco\> | Endereços |

**Comportamento:**
1. Define `status = StatusCadastro.INCOMPLETO` no DTO recebido
2. Converte para `UsuarioED` via `BuilderUsuarioED`
3. Persiste `UsuarioED` via `usuarioBD.inclui(ed)`
4. Chama `graduacaoUsuarioRN.incluirGraduacoesUsuario(ed, usuario.getGraduacoes())`
5. Chama `especializacaoUsuarioRN.incluirEspecializacoesUsuario(ed, usuario.getEspecializacoes())`
6. Chama `enderecoUsuarioRN.incluirEnderecosUsuario(ed, usuario.getEnderecos())`
7. Retorna `Usuario` convertido do ED persistido com HTTP 201

**Tratamento de erro de CPF duplicado:**
- `PersistenceException` → verifica causa `ConstraintViolationException`
- Se `constraintName != null && !isEmpty` → HTTP 400 com `bundle.getMessage(USUARIO_CPF_JA_CADASTRADO, cpfFormatado, email)`
- Caso contrário → HTTP 400 com `bundle.getMessage(VIOLACAO_BD)`

---

### 6.2 RF-U-02 — Alterar Cadastro de Usuário

**Endpoint:** `PUT /usuarios/{id}`
**Classe:** `UsuarioRN.alterar(Long id, Usuario usuario)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento:**
1. Busca `UsuarioED` por id (`consulta(id)`)
2. **Verificação de concorrência** (ver RN-P02-01)
3. Atualiza campos do ED: nome, cpf, rg, estadoEmissor, dtNascimento, nomeMae, email, telefone1, telefone2, status
4. Chama `graduacaoUsuarioRN.alterarGraduacoesUsuario(usuarioED, usuario.getGraduacoes())`
5. Chama `especializacaoUsuarioRN.alterarEspecializacoesUsuario(usuarioED, usuario.getEspecializacoes())`
6. Chama `enderecoUsuarioRN.alterarEnderecosUsuario(usuarioED, usuario.getEnderecos())`
7. Persiste via `altera(usuarioED)`
8. Define `usuario.setMensagemStatus("Alterações realizadas com sucesso.")`
9. Retorna `Usuario` com HTTP 200

---

### 6.3 RF-U-03 — Consultar Usuário por CPF

**Endpoints:** `GET /usuarios/{cpf}` e `GET /usuarios?cpf={cpf}`
**Classe:** `UsuarioRN.consultaPorCpf(String cpf)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Retorno (`Usuario` DTO com todos os campos preenchidos):**
- Dados pessoais (nome, cpf, rg, estadoEmissor, dtNascimento, nomeMae, email, telefones)
- `enderecos` via `enderecoUsuarioRN.listarEnderecosUsuario(ed)`
- `status`, `mensagemStatus`
- `graduacoes` via `graduacaoUsuarioRN.listarGraduacoesUsuario(ed)`
- `especializacoes` via `especializacaoUsuarioRN.listarEspecializacoesUsuario(ed)`
- `ctrDthInc`, `ctrDthAtu` (usados para controle de concorrência)
- `arquivoRG` (com id e nomeArquivo; objeto vazio se null)
- `diasParaVencerCredenciamento`, `alertaVencimento`, `dataVencimentoCredenciamento` (via `InstrutorRN`)

> **Nota:** `dtNascimento.set(Calendar.HOUR, 12)` é aplicado como solução para problema de fuso horário.

---

### 6.4 RF-U-04 — Upload de Foto/Documento do RG

**Endpoint:** `POST /usuarios/{idUsuario}/arquivo-rg`
**Tipo:** `multipart/form-data`
**Classe:** `UsuarioRN.incluirArquivoRG(long idUsuario, InputStream, String nomeArquivo)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento:**
1. Busca `UsuarioED` por `idUsuario`
2. Se `usuarioED.getArquivoRG() != null` → lança `WebApplicationRNException` HTTP 400 com `bundle.getMessage(USUARIO_ARQUIVO_ERRO_DUPLICADO)`
3. Persiste arquivo via `arquivoRN.incluirArquivo(inputStream, nomeArquivo, TipoArquivo.USUARIO)`
4. Associa `arquivoED` ao `usuarioED.setArquivoRG(arquivoED)`
5. Persiste alteração via `usuarioBD.altera(usuarioED)`
6. Retorna `Arquivo` (id, nomeArquivo) com HTTP 201

---

### 6.5 RF-U-05 — Download do Documento RG

**Endpoint:** `GET /usuarios/{idUsuario}/arquivo-rg`
**Tipo de resposta:** `application/octet-stream`
**Classe:** `UsuarioRN.downloadArquivoRG(Long idUsuario)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Comportamento:** Busca `UsuarioED`, retorna `arquivoRN.toInputStream(usuarioED.getArquivoRG())`.

---

### 6.6 RF-U-06 — Atualização do Documento RG

**Endpoint:** `PUT /usuarios/{idUsuario}/arquivo-rg`
**Tipo:** `multipart/form-data`
**Classe:** `UsuarioRN.alterarArquivoRG(long idUsuario, InputStream, String nomeArquivo)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento:**
1. Busca `UsuarioED`
2. Obtém `arquivoRG` existente
3. Atualiza `nomeArquivo` e `inputStream` no `ArquivoED`
4. Chama `arquivoRN.alterarArquivo(arquivoRG)` para regravar conteúdo binário
5. Retorna `Arquivo` com HTTP 200

---

### 6.7 RF-U-07 — Upload do Documento Profissional de Graduação

**Endpoint:** `POST /usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo`
**Tipo:** `multipart/form-data`
**Classe:** `UsuarioRN.incluirArquivoDocProfissional(long idUsuario, long idGraduacao, InputStream, String)`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento:**
1. Busca `GraduacaoUsuarioED` via `graduacaoUsuarioRN.consulta(idUsuario, idGraduacao)`
2. Se `graduacaoUsuarioED.getArquivoIdProfissional() != null` → HTTP 400 (duplicado)
3. Persiste arquivo via `arquivoRN.incluirArquivo(..., TipoArquivo.USUARIO)`
4. Associa ao `GraduacaoUsuarioED` e chama `graduacaoUsuarioRN.altera(ed)`
5. Retorna `Arquivo` com HTTP 201

---

### 6.8 RF-U-08 — Download do Documento Profissional de Graduação

**Endpoint:** `GET /usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo`
**Tipo de resposta:** `application/octet-stream`
**Classe:** `UsuarioRN.downloadArquivoDocProfissional(long idUsuario, long idGraduacao)`
**Transação:** `@TransactionAttribute(SUPPORTS)`

---

### 6.9 RF-U-09 — Atualização do Documento Profissional de Graduação

**Endpoint:** `PUT /usuarios/{idUsuario}/graduacoes/{idGraduacao}/arquivo`
**Tipo:** `multipart/form-data`
**Classe:** `UsuarioRN.alterarArquivoDocProfissional(long idUsuario, long idGraduacao, InputStream, String)`
**Transação:** `@TransactionAttribute(REQUIRED)`

---

### 6.10 RF-U-10 — Upload, Download e Atualização de Documento de Especialização

**Endpoints:** `POST|GET|PUT /usuarios/{idUsuario}/especializacoes/{idEspecializacao}/arquivo`
**Classe:** `UsuarioRN.incluir|download|alterarArquivoEspecializacao(...)`
**Comportamento idêntico** ao descrito para graduação (RF-U-07, RF-U-08, RF-U-09), mas operando sobre `EspecializacaoUsuarioED` e o campo `arquivo`.

---

### 6.11 RF-U-11 — Submeter Cadastro para Análise (Conclusão)

**Endpoint:** `PATCH /usuarios/{id}`
**Classe:** `UsuarioConclusaoCadastroRN.concluirCadastro(Long idUsuario)`
**Transação:** `@TransactionAttribute(REQUIRED)`
**Permissão:** `@Permissao(desabilitada = true)` — sem restrição de perfil

**Comportamento:**
1. Inicia com `statusCadastro = StatusCadastro.ANALISE_PENDENTE`
2. Busca `UsuarioED` por `idUsuario`
3. **Se `arquivoRG == null`** → `statusCadastro = INCOMPLETO`
4. Lista todas as `GraduacaoUsuarioED` do usuário; **para cada uma:**
   - Se `arquivoIdProfissional == null` → `statusCadastro = INCOMPLETO`
5. Persiste `status` e limpa `mensagemStatus = null` no `UsuarioED`
6. Chama `notificacaoRN.notificar(usuarioED, statusMessage, ContextoNotificacaoEnum.CADASTRO)` (sem e-mail)
7. Retorna DTO `Status`:
   - `statusCadastro` — status resultante
   - `ctrDthAtu` — nova data de atualização (para sincronização de concorrência)
   - `mensagem` — mensagem do bundle `"usuario.cadastro.status.{statusCadastro}"`
8. **Se `statusCadastro == ANALISE_PENDENTE`:** verifica `InstrutorED` por CPF; se status `APROVADO` ou `VENCIDO`, chama `instrutorHistoricoRN.incluirEdicao(instrutor)`

---

### 6.12 RF-U-12 — Verificar se RT Logado é Válido

**Endpoint:** `GET /usuarios/isUsuarioRtValido`
**Classe:** `UsuarioRN.isUsuarioLogadoRtValido()`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Comportamento:**
- Obtém CPF do usuário logado via `cidadaoSessionMB.getCidadaoED().getCpf()`
- Retorna `true` somente se `status == APROVADO` **E** `graduações não vazias`

---

### 6.13 RF-A-01 — Listar Cadastros em Análise (Visão do Analista)

**Endpoint:** `GET /adm/analise-cadastros/em-analise`
**Classe:** `AnaliseCadastroRN.listarCadastrosEmAnalise(AnaliseCadastroED)`
**Permissão:** `@Permissao(objeto = "VERIFICARCADASTRO", acao = "LISTAR")`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Filtro aplicado automaticamente:**
- `idUsuarioSoe = sessionMB.getUser().getId()` (analista logado)
- `status = StatusAnalise.EM_ANALISE`

**Retorno:** `List<Cadastro>` com campos: id, nome, cpf, email, ctrDthInc, ctrDthAtu, possuiGraduacao, status (StatusCadastro), idAnalise (id de CBM_ANALISE_CADASTRO)

---

### 6.14 RF-A-02 — Assumir Análise de um Cadastro

**Endpoint:** `POST /adm/analise-cadastros`
**Body:** `Cadastro` com campos obrigatórios: `id`, `status` (EM_ANALISE, APROVADO ou REPROVADO), `ctrDthAtu`
**Classe:** `AnaliseCadastroRN.incluirAnaliseCadastro(Cadastro)`
**Permissão:** `@Permissao(objeto = "VERIFICARCADASTRO", acao = "EDITAR")`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento completo (ver RN-P02-05 a RN-P02-09):**
1. Valida presença de `id`, `status`, `ctrDthAtu` → HTTP 400 se algum for null
2. Busca `UsuarioED` por `cadastro.getId()`
3. Verifica `ctrDthAtu` vs BD → HTTP 409 se divergente
4. **Somente se `usuario.status == StatusCadastro.ANALISE_PENDENTE`:**
   - Cria `AnaliseCadastroED`:
     - `usuario = usuarioED`
     - `idUsuarioSoe = Long.parseLong(sessionMB.getUser().getId())`
     - `nomeUsuario = sessionMB.getUser().getNome()`
     - `status = StatusAnalise.EM_ANALISE`
   - Persiste e armazena `idRetorno`
5. Notifica usuário com status `EM_ANALISE` (sem e-mail)
6. Se `usuarioED.status != EM_ANALISE` → atualiza para `StatusCadastro.EM_ANALISE`
7. **Retorno:** HTTP 201 com header `Location: /adm/analise-cadastros/{idRetorno}`

---

### 6.15 RF-A-03 — Consultar Análise por ID

**Endpoint:** `GET /adm/analise-cadastros/{id}`
**Classe:** `AnaliseCadastroRN.consultaAnaliseCadastro(Long id)`
**Permissão:** `@Permissao(objeto = "VERIFICARCADASTRO", acao = "CONSULTAR")`
**Transação:** `@TransactionAttribute(SUPPORTS)`

**Retorno:** `AnaliseCadastro` (id, status, justificativa, usuario, nomeAnalista, ctrDthAtu)

---

### 6.16 RF-A-04 — Alterar Status da Análise (Aprovar / Reprovar / Cancelar)

**Endpoint:** `PUT /adm/analise-cadastros/{id}`
**Body:** `AnaliseCadastro` com `status` e `justificativa`
**Classe:** `AnaliseCadastroRN.alterarStatusAnaliseCadastro(Long id, AnaliseCadastro)`
**Permissão:** `@Permissao(objeto = "VERIFICARCADASTRO", acao = "EDITAR")`
**Transação:** `@TransactionAttribute(REQUIRED)`

**Comportamento (ver RN-P02-10 a RN-P02-14):**
1. Busca `AnaliseCadastroED` por `id`
2. Verifica autorização (ver RN-P02-11)
3. Atualiza `status` e `justificativa` no `AnaliseCadastroED`
4. Persiste
5. Chama `mudarStatusCadastro(usuario.id, analiseCadastro)`

---

## 7. Regras de Negócio

### RN-P02-01 — Controle de Concorrência na Alteração do Usuário

**Localização:** `UsuarioRN.alterar()` linha 332

```java
if (usuarioED.getStatus() != StatusCadastro.INCOMPLETO
    && usuarioED.getCtrDthAtu() != null
    && usuario.getCtrDthAtu() != null
    && usuarioED.getCtrDthAtu().compareTo(usuario.getCtrDthAtu()) != 0) {
    throw new WebApplicationRNException(
        bundle.getMessage("analise.data_atualizacao.divergente"),
        Response.Status.CONFLICT);  // HTTP 409
}
```

> O controle só é ativado quando `status != INCOMPLETO`. Usuários com cadastro incompleto podem ser alterados sem verificação de versão.

---

### RN-P02-02 — CPF Único por Usuário

**Localização:** `UsuarioRN.processaErroBD()`

- Violação de constraint de banco (CPF duplicado) é capturada como `ConstraintViolationException`
- Retorna HTTP 400 com mensagem específica contendo CPF formatado e e-mail
- Código de bundle: `USUARIO_CPF_JA_CADASTRADO`

---

### RN-P02-03 — Validação de Completude na Submissão

**Localização:** `UsuarioConclusaoCadastroRN.concluirCadastro()`

O status resultante é `ANALISE_PENDENTE` somente se **todas** as condições forem verdadeiras:
- `arquivoRG` está associado ao usuário (não null)
- Para **cada** graduação vinculada ao usuário: `arquivoIdProfissional` está associado (não null)

Se qualquer condição falhar → status permanece/retorna para `INCOMPLETO`.

> **Nota:** Especializações **não** são verificadas para completude — apenas graduações.

---

### RN-P02-04 — Arquivo Único por Entidade (Sem Duplicata)

**Localização:** `UsuarioRN.incluirArquivoRG()`, `incluirArquivoDocProfissional()`, `incluirArquivoEspecializacao()`

- Se já existe arquivo vinculado à entidade → HTTP 400 com `bundle.getMessage(USUARIO_ARQUIVO_ERRO_DUPLICADO)`
- Para atualização deve-se usar os endpoints `PUT` correspondentes

---

### RN-P02-05 — Validação de Campos na Abertura de Análise

**Localização:** `AnaliseCadastroRN.incluirAnaliseCadastro()`

Campos obrigatórios no `Cadastro` recebido:
- `id` (ID do usuário) — null → HTTP 400
- `status` — deve ser `EM_ANALISE`, `APROVADO` ou `REPROVADO` — null → HTTP 400
- `ctrDthAtu` — timestamp de controle de concorrência — null → HTTP 400

---

### RN-P02-06 — Controle de Concorrência na Abertura de Análise

**Localização:** `AnaliseCadastroRN.incluirAnaliseCadastro()`

```java
if (ed.getCtrDthAtu().compareTo(cadastro.getCtrDthAtu()) != 0) {
    throw new WebApplicationRNException(..., Response.Status.CONFLICT); // HTTP 409
}
```

Garante que o analista está vendo a versão mais atualizada do cadastro antes de assumir.

---

### RN-P02-07 — Registro de Análise Criado Somente para ANALISE_PENDENTE

**Localização:** `AnaliseCadastroRN.incluirAnaliseCadastro()`

- O registro em `CBM_ANALISE_CADASTRO` só é criado se `usuario.status == StatusCadastro.ANALISE_PENDENTE`
- Para cadastros já em `EM_ANALISE` (re-abertura), não cria novo registro de análise
- Em ambos os casos a notificação é enviada e o status pode ser atualizado

---

### RN-P02-08 — Vinculação da Análise ao Analista Logado

**Localização:** `AnaliseCadastroRN.incluirAnaliseCadastro()`

```java
analiseED.setIdUsuarioSoe(Long.parseLong(sessionMB.getUser().getId()));
analiseED.setNomeUsuario(sessionMB.getUser().getNome());
```

O ID SOE e o nome do analista são obtidos do contexto de sessão e armazenados na análise.

---

### RN-P02-09 — Notificação ao Usuário na Abertura de Análise

**Localização:** `AnaliseCadastroRN.incluirAnaliseCadastro()`

- Envia notificação interna ao usuário com status `EM_ANALISE`
- **Não envia e-mail** neste momento
- Atualiza `usuario.status` para `EM_ANALISE` se ainda não estiver nesse status

---

### RN-P02-10 — Autorização para Alterar Status da Análise

**Localização:** `AnaliseCadastroRN.alterarStatusAnaliseCadastro()`

```java
boolean isAnalista = analiseED.getIdUsuarioSoe().toString()
    .equals(sessionMB.getUser().getId());
boolean isSupervisor = sessionMB.hasPermission("CENTRALADM", "EDITAR");

if (!isAnalista && !isSupervisor) {
    throw new WebApplicationRNException(Response.Status.FORBIDDEN); // HTTP 403
}
```

Apenas o **analista que assumiu** a análise ou um usuário com **permissão CENTRALADM/EDITAR** pode alterar o status.

---

### RN-P02-11 — Mapeamento de Status de Análise para Status de Cadastro

**Localização:** `AnaliseCadastroRN.mudarStatusCadastro()`

| `StatusAnalise` (entrada) | `StatusCadastro` (resultado) | Envia E-mail |
|---|---|---|
| `CANCELADO` | `ANALISE_PENDENTE` | Não |
| `APROVADO` | `APROVADO` | Sim |
| `REPROVADO` | `REPROVADO` | Sim |
| `EM_ANALISE` | `EM_ANALISE` | Não |

**Após mudança de status:**
- `usuario.mensagemStatus = analiseCadastro.getJustificativa()`
- Chama: `notificacaoRN.notificar(usuario, mensagem, CADASTRO, enviarEmail, statusCadastro.name())`

---

### RN-P02-12 — Algoritmo de Diff para Graduações

**Localização:** `GraduacaoUsuarioRN.alterarGraduacoesUsuario()`

Para cada `GraduacaoUsuarioED` existente no banco:
1. Busca correspondente na lista enviada: compara por `idGraduacaoUsuario` **OU** `graduacao.id`
2. **Se encontrado:**
   - Verifica se houve mudança em: `estadoEmissor`, `idProfissional` ou `graduacao.id`
   - Se mudou: chama `compararGraduacoes()` que cria novo `GraduacaoUsuarioED` com o mesmo ID mas campos atualizados
   - Remove da lista de entrada
3. **Se não encontrado:** exclui o registro e exclui arquivo vinculado (`arquivoIdProfissional`)
4. Itens remanescentes na lista de entrada (não encontrados no banco) são inseridos via `incluirGraduacoesUsuario()`

**Regra de arquivo no diff:**
- Se `idGraduacaoUsuario` difere do `ed.getId()` → o arquivo do ED original é excluído antes da atualização
- Se `idGraduacaoUsuario == ed.getId()` → o arquivo existente é mantido

---

### RN-P02-13 — Graduações com ID Null São Ignoradas

**Localização:** `GraduacaoUsuarioRN.incluirGraduacoesUsuario()`

```java
graduacoes.stream()
    .filter(graduacao -> graduacao.getId() != null)
    .collect(...)
```

Graduações sem ID de tipo (`graduacao.id == null`) são filtradas antes da inserção.

---

### RN-P02-14 — Verificação de RT Válido

**Localização:** `UsuarioRN.isUsuarioRTAprovado(String cpf)`

```java
return StatusCadastro.APROVADO.equals(ed.getStatus())
    && !graduacaoUsuarioRN.listarGraduacoesUsuario(ed).isEmpty();
```

Um RT é considerado válido somente quando: cadastro `APROVADO` **E** pelo menos uma graduação vinculada.

---

## 8. Modelo de DTOs (Objetos Remotos)

### 8.1 `Usuario` (remote DTO)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do usuário |
| `nome` | String | Nome completo |
| `cpf` | String | CPF |
| `rg` | String | RG |
| `estadoEmissor` | String | UF emissora do RG |
| `dtNascimento` | Calendar | Data de nascimento |
| `nomeMae` | String | Nome da mãe |
| `email` | String | E-mail |
| `telefone1` | String | Telefone principal |
| `telefone2` | String | Telefone secundário |
| `arquivoRG` | Arquivo | Metadados do arquivo do RG |
| `graduacoes` | List\<Graduacao\> | Lista de graduações |
| `especializacoes` | List\<Especializacao\> | Lista de especializações |
| `enderecos` | List\<Endereco\> | Lista de endereços |
| `status` | StatusCadastro | Status atual do cadastro |
| `mensagemStatus` | String | Mensagem associada ao status |
| `ctrDthInc` | Calendar | Data de criação |
| `ctrDthAtu` | Calendar | Data de última atualização (controle de concorrência) |
| `diasParaVencerCredenciamento` | Integer | (lido de InstrutorED) |
| `alertaVencimento` | Boolean | (lido de InstrutorED) |
| `dataVencimentoCredenciamento` | String | Formatada como dd/MM/yyyy |

### 8.2 `Cadastro` (remote DTO — listagem/abertura de análise)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do usuário |
| `nome` | String | Nome do usuário |
| `cpf` | String | CPF |
| `email` | String | E-mail |
| `ctrDthInc` | Calendar | Data de criação |
| `ctrDthAtu` | Calendar | Data de atualização (controle de concorrência) |
| `possuiGraduacao` | Boolean | Indica se tem graduação vinculada |
| `status` | StatusCadastro | Status do cadastro |
| `idAnalise` | Long | ID do registro de análise (CBM_ANALISE_CADASTRO) |

### 8.3 `AnaliseCadastro` (remote DTO — análise)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID da análise |
| `status` | StatusAnalise | Status da análise |
| `justificativa` | String | Justificativa da decisão |
| `usuario` | Usuario | Usuário analisado |
| `nomeAnalista` | String | Nome do analista que assumiu |
| `ctrDthAtu` | Calendar | Data de atualização |

### 8.4 `Status` (retorno de concluirCadastro)

| Campo | Tipo | Descrição |
|---|---|---|
| `statusCadastro` | StatusCadastro | Status resultante |
| `ctrDthAtu` | Calendar | Nova data de atualização |
| `mensagem` | String | Mensagem do bundle |

### 8.5 `Arquivo` (metadados de arquivo)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do arquivo |
| `nomeArquivo` | String | Nome original do arquivo |

### 8.6 `Graduacao` (DTO de graduação do usuário)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | Long | ID do tipo de graduação (CBM_GRADUACAO) |
| `descricao` | String | Descrição da graduação |
| `idGraduacaoUsuario` | Long | ID do vínculo (CBM_GRADUACAO_USUARIO) |
| `idProfissional` | String | Número do registro profissional |
| `estadoEmissor` | String | UF de emissão |
| `arquivoIdProfissional` | Arquivo | Metadados do comprovante |

---

## 9. Modelo de Segurança / Permissões

### 9.1 Autenticação

Todos os recursos REST usam `@SOEAuthRest` — anotação da plataforma arqjava4 (PROCERGS) que:
- Valida token SSO do IdP Estadual (PROCERGS SOE)
- Disponibiliza `SessionMB.getUser()` com: `id` (SOE ID), `nome`, permissões

### 9.2 Autorização por Operação

| Método/Operação | Objeto | Ação |
|---|---|---|
| `listarCadastrosEmAnalise` | `VERIFICARCADASTRO` | `LISTAR` |
| `incluirAnaliseCadastro` | `VERIFICARCADASTRO` | `EDITAR` |
| `alterarStatusAnaliseCadastro` | `VERIFICARCADASTRO` | `EDITAR` |
| `consultaAnaliseCadastro` | `VERIFICARCADASTRO` | `CONSULTAR` |
| `consultarPorCadastro` | `VERIFICARCADASTRO` | `CONSULTAR` |
| `concluirCadastro` | — | `@Permissao(desabilitada = true)` |

### 9.3 Permissão de Supervisor

O perfil `CENTRALADM` com ação `EDITAR` permite que supervisores alterem análises abertas por outros analistas (contorna a restrição RN-P02-10).

---

## 10. Padrões de Implementação a Manter

### 10.1 Padrão EJB + BD

```java
@Stateless
@TransactionAttribute(TransactionAttributeType.REQUIRED)
public class XxxRN extends AppRN<XxxED, Long> {

    @Inject
    XxxBD xxxBD;

    @PostConstruct
    public void initBD() {
        setBD(xxxBD);  // Conecta BD ao AppRN pai
    }
}
```

### 10.2 Padrão de DAO com DetachedCriteria

```java
public class XxxBD extends AppBD<XxxED, Long> {

    @Override
    public DetachedCriteria montaCriterios(XxxED ed) {
        DetachedCriteria dc = DetachedCriteria.forClass(XxxED.class);
        if (ed.getCampo() != null) {
            dc.add(Restrictions.eq("campo", ed.getCampo()));
        }
        return dc;
    }
}
```

### 10.3 Padrão REST com Resposta de Localização

```java
@POST
public Response criar(DtoEntrada dto) {
    Long id = rn.incluir(dto);
    URI location = uriInfo.getAbsolutePathBuilder().path(String.valueOf(id)).build();
    return Response.created(location).build();
}
```

### 10.4 Tratamento de Erro Padronizado

```java
// Lançar exceção com status HTTP específico:
throw new WebApplicationRNException(mensagem, Response.Status.BAD_REQUEST);
throw new WebApplicationRNException(Response.Status.FORBIDDEN);
throw new WebApplicationRNException(Response.Status.CONFLICT);
```

### 10.5 Upload de Arquivo via RESTEasy Multipart

```java
@POST
@Consumes(MediaType.MULTIPART_FORM_DATA)
public Response upload(@PathParam("id") long id,
                       MultipartFormDataInput input) {
    Map<String, List<InputPart>> parts = input.getFormDataMap();
    // extrair InputStream e filename dos parts
}
```

---

## 11. Dependências e Configurações

### 11.1 Dependências Maven Relevantes

```xml
<!-- Java EE 7 (provided pelo WildFly) -->
<dependency>
    <groupId>javax</groupId>
    <artifactId>javaee-api</artifactId>
    <version>7.0</version>
    <scope>provided</scope>
</dependency>

<!-- RESTEasy Multipart (provided pelo WildFly) -->
<dependency>
    <groupId>org.jboss.resteasy</groupId>
    <artifactId>resteasy-multipart-provider</artifactId>
    <scope>provided</scope>
</dependency>

<!-- arqjava4 PROCERGS (interno) -->
<dependency>
    <groupId>com.procergs</groupId>
    <artifactId>arqjava4</artifactId>
    <!-- versão interna PROCERGS -->
</dependency>

<!-- Hibernate (ORM) -->
<dependency>
    <groupId>org.hibernate</groupId>
    <artifactId>hibernate-core</artifactId>
    <scope>provided</scope>
</dependency>

<!-- Apache Commons Lang -->
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-lang3</artifactId>
</dependency>

<!-- SLF4J -->
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <scope>provided</scope>
</dependency>
```

### 11.2 Configuração de Datasource (WildFly)

- JNDI: conforme `persistence.xml` do projeto (`java:jboss/datasources/solcbmDS` ou equivalente)
- Dialeto: PostgreSQL (baseado no uso de `SEQUENCE` nas entidades)

---

## 12. Sumário de Requisitos

### 12.1 Requisitos Funcionais

| ID | Nome | Ator | Endpoint |
|---|---|---|---|
| RF-U-01 | Criar cadastro de usuário | Cidadão | `POST /usuarios` |
| RF-U-02 | Alterar cadastro de usuário | Cidadão | `PUT /usuarios/{id}` |
| RF-U-03 | Consultar usuário por CPF | Sistema/Cidadão | `GET /usuarios/{cpf}` ou `?cpf=` |
| RF-U-04 | Upload do documento RG | Cidadão | `POST /usuarios/{id}/arquivo-rg` |
| RF-U-05 | Download do documento RG | Sistema | `GET /usuarios/{id}/arquivo-rg` |
| RF-U-06 | Atualização do documento RG | Cidadão | `PUT /usuarios/{id}/arquivo-rg` |
| RF-U-07 | Upload do comprovante de graduação | Cidadão | `POST /usuarios/{id}/graduacoes/{g}/arquivo` |
| RF-U-08 | Download do comprovante de graduação | Sistema | `GET /usuarios/{id}/graduacoes/{g}/arquivo` |
| RF-U-09 | Atualização do comprovante de graduação | Cidadão | `PUT /usuarios/{id}/graduacoes/{g}/arquivo` |
| RF-U-10 | Upload/download/atualização de especialização | Cidadão | `POST|GET|PUT /usuarios/{id}/especializacoes/{e}/arquivo` |
| RF-U-11 | Submeter cadastro para análise | Cidadão | `PATCH /usuarios/{id}` |
| RF-U-12 | Verificar se RT logado é válido | Sistema | `GET /usuarios/isUsuarioRtValido` |
| RF-A-01 | Listar cadastros em análise | Analista | `GET /adm/analise-cadastros/em-analise` |
| RF-A-02 | Assumir análise de cadastro | Analista | `POST /adm/analise-cadastros` |
| RF-A-03 | Consultar análise por ID | Analista | `GET /adm/analise-cadastros/{id}` |
| RF-A-04 | Alterar status da análise | Analista/Supervisor | `PUT /adm/analise-cadastros/{id}` |

### 12.2 Regras de Negócio

| ID | Nome |
|---|---|
| RN-P02-01 | Controle de concorrência na alteração do usuário (ctrDthAtu → HTTP 409) |
| RN-P02-02 | CPF único por usuário (ConstraintViolationException → HTTP 400) |
| RN-P02-03 | Validação de completude na submissão (arquivoRG + arquivos de graduação) |
| RN-P02-04 | Arquivo único por entidade — proibida duplicata (HTTP 400) |
| RN-P02-05 | Campos obrigatórios na abertura de análise (id, status, ctrDthAtu → HTTP 400) |
| RN-P02-06 | Controle de concorrência na abertura de análise (ctrDthAtu → HTTP 409) |
| RN-P02-07 | Registro de análise criado somente quando status = ANALISE_PENDENTE |
| RN-P02-08 | Análise vinculada ao analista logado (idUsuarioSoe, nomeUsuario do SessionMB) |
| RN-P02-09 | Notificação interna ao usuário na abertura de análise (sem e-mail) |
| RN-P02-10 | Somente o analista responsável ou CENTRALADM pode alterar a análise (→ HTTP 403) |
| RN-P02-11 | Mapeamento StatusAnalise → StatusCadastro com controle de envio de e-mail |
| RN-P02-12 | Algoritmo de diff para graduações (inserir, atualizar, excluir por comparação) |
| RN-P02-13 | Graduações com id null são ignoradas no insert |
| RN-P02-14 | RT válido = status APROVADO + pelo menos uma graduação vinculada |
