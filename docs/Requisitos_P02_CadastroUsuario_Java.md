# Requisitos Completos — P02: Cadastro de Usuário / Responsável Técnico (RT)
**Sistema:** SOL/CBM-RS — Sistema Operacional de Licenciamento
**Processo:** P02 — Cadastro de Usuário e Análise de Cadastro
**Stack alvo:** Java moderno (sem dependência PROCERGS)
**Versão:** 1.0 | Data: 2026-03-05

---

## 1. Contexto e Escopo do Processo

O **P02** governa o ciclo de vida completo do cadastro de um usuário/Responsável Técnico (RT) no sistema SOL, desde o preenchimento inicial dos dados pessoais e documentação até a aprovação ou reprovação por um analista do CBM-RS. O processo é dividido em duas grandes jornadas:

1. **Jornada do Usuário (Self-Service):** preenchimento de dados pessoais, endereço, graduações, especializações e upload de documentos obrigatórios; submissão do cadastro para análise.
2. **Jornada do Analista (Back-Office):** listagem de cadastros pendentes de análise, triagem, tomada de análise, decisão (aprovação/reprovação) com justificativa, e notificação automática ao usuário.

### Pré-condições
- O usuário **já existe** no banco de dados com `StatusCadastro = INCOMPLETO`, criado automaticamente durante P01 quando o CPF não foi localizado no sistema.
- O usuário está **autenticado** via JWT emitido pelo IdP da plataforma (substituindo a dependência do IdP PROCERGS — ver P01 moderno).
- O analista possui as permissões adequadas (`VERIFICARCADASTRO_LISTAR`, `VERIFICARCADASTRO_EDITAR`, `VERIFICARCADASTRO_CONSULTAR`) atribuídas via sistema de roles do JWT.

### Tabelas de banco envolvidas
| Tabela | Entidade | Descrição |
|--------|----------|-----------|
| `CBM_USUARIO` | `Usuario` | Dados pessoais e status do RT |
| `CBM_GRADUACAO_USUARIO` | `GraduacaoUsuario` | Graduações e habilitações do RT |
| `CBM_ESPECIALIZACAO_USUARIO` | `EspecializacaoUsuario` | Especializações do RT |
| `CBM_ARQUIVO` | `Arquivo` | Metadados de arquivos (RG, IdProf, Certif.) |
| `CBM_ENDERECO_USUARIO` | `EnderecoUsuario` | Endereços do RT |
| `CBM_ANALISE_CADASTRO` | `AnaliseCadastro` | Registro de análise feita pelo analista |
| `CBM_NOTIFICACAO` | `Notificacao` | Notificações internas e e-mails |

---

## 2. Modelo de Domínio

### 2.1 Enumerações

```java
// Status do cadastro do usuário (campo TP_STATUS em CBM_USUARIO)
public enum StatusCadastro {
    INCOMPLETO(0, "Cadastro incompleto"),
    ANALISE_PENDENTE(1, "Seu cadastro foi enviado para análise."),
    EM_ANALISE(2, "Cadastro em processo de análise"),
    APROVADO(3, "Cadastro aprovado"),
    REPROVADO(4, "Cadastro reprovado");
}

// Status de um registro de análise (campo TP_STATUS em CBM_ANALISE_CADASTRO)
public enum StatusAnalise {
    EM_ANALISE(1, "Em processo de análise"),
    CANCELADO(2, "Cancelado"),
    APROVADO(3, "Cadastro aprovado"),
    REPROVADO(4, "Cadastro reprovado");
}
```

**Mapeamento StatusAnalise → StatusCadastro** (ocorre em `mudarStatusCadastro()`):

| StatusAnalise (entrada) | StatusCadastro resultante | Envia e-mail? |
|------------------------|---------------------------|---------------|
| `EM_ANALISE` | `EM_ANALISE` | Não (notificação interna) |
| `CANCELADO` | `ANALISE_PENDENTE` | Não |
| `APROVADO` | `APROVADO` | **Sim** |
| `REPROVADO` | `REPROVADO` | **Sim** |

### 2.2 Entidades JPA (mapeamento direto do legado)

#### Usuario (`CBM_USUARIO`)
```java
@Entity @Table(name = "CBM_USUARIO")
public class UsuarioEntity {
    @Id @GeneratedValue(strategy = SEQUENCE, generator = "CBM_ID_USUARIO_SEQ")
    @Column(name = "NRO_INT_USUARIO")
    private Long id;

    @NotNull @Column(name = "NOME_USUARIO")
    private String nome;

    @NotNull @Column(name = "TXT_CPF")
    private String cpf;                    // formatado: "000.000.000-00"

    @Column(name = "TXT_RG")
    private String rg;

    @Column(name = "TXT_UF_RG")
    private String estadoEmissor;          // UF do órgão emissor do RG

    @OneToOne(fetch = LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO_RG")
    private ArquivoEntity arquivoRG;       // null até upload

    @NotNull @Column(name = "DT_NASCIMENTO") @Temporal(DATE)
    private Calendar dtNascimento;

    @NotNull @Column(name = "NOME_MAE")
    private String nomeMae;

    @NotNull @Column(name = "TXT_EMAIL")
    private String email;

    @NotNull @Column(name = "TXT_TELEFONE1")
    private String telefone1;

    @Column(name = "TXT_TELEFONE2")
    private String telefone2;

    @Column(name = "TP_STATUS")
    @Enumerated(EnumType.STRING)
    private StatusCadastro status;         // INCOMPLETO ao criar

    @Column(name = "TXT_MENSAGEM_STATUS")
    private String mensagemStatus;         // justificativa de reprovação

    @OneToMany(mappedBy = "usuario", fetch = LAZY)
    private Set<GraduacaoUsuarioEntity> graduacoesUsuario;

    @OneToMany(mappedBy = "usuario", fetch = LAZY)
    private List<EnderecoUsuarioEntity> enderecosUsuario;

    // controle de auditoria (herdado de AppED)
    private Calendar ctrDthInc;            // data de criação
    private Calendar ctrDthAtu;            // data de última atualização (controle de concorrência)
}
```

#### GraduacaoUsuario (`CBM_GRADUACAO_USUARIO`)
```java
@Entity @Table(name = "CBM_GRADUACAO_USUARIO")
public class GraduacaoUsuarioEntity {
    @Id @GeneratedValue(strategy = SEQUENCE, generator = "CBM_ID_GRAD_USUARIO_SEQ")
    @Column(name = "NRO_INT_GRADUACAO_USUARIO")
    private Long id;

    @NotNull @ManyToOne(fetch = LAZY)
    @JoinColumn(name = "NRO_INT_GRADUACAO")
    private GraduacaoEntity graduacao;     // referência à tabela de tipos de graduação

    @NotNull @ManyToOne(fetch = LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioEntity usuario;

    @OneToOne(fetch = LAZY)
    @JoinColumn(name = "NRO_INT_ARQUIVO_ID_PROFIS")
    private ArquivoEntity arquivoIdProfissional;   // null até upload

    @Column(name = "TXT_ID_PROFISSIONAL")
    private String idProfissional;         // número da identidade profissional (ex: CREA)

    @Column(name = "TXT_UF_GRADUACAO")
    private String estadoEmissor;          // UF do conselho emissor
}
```

#### AnaliseCadastro (`CBM_ANALISE_CADASTRO`)
```java
@Entity @Table(name = "CBM_ANALISE_CADASTRO")
public class AnaliseCadastroEntity {
    @Id @GeneratedValue(strategy = SEQUENCE, generator = "CBM_ID_ANALISE_CADASTRO_SEQ")
    @Column(name = "NRO_INT_ANALISE_CADASTRO")
    private Long id;

    @NotNull @OneToOne(fetch = LAZY)
    @JoinColumn(name = "NRO_INT_USUARIO")
    private UsuarioEntity usuario;

    @Column(name = "NOME_USUARIO")
    private String nomeAnalista;           // nome do analista que tomou a análise

    @Column(name = "NRO_INT_USUARIO_SOE")
    private Long idAnalista;               // ID interno do analista no sistema

    @Column(name = "TP_STATUS")
    @Enumerated(EnumType.STRING)
    private StatusAnalise status;

    @Column(name = "TXT_JUSTIFICATIVA")
    private String justificativa;          // obrigatório para REPROVADO

    private Calendar ctrDthAtu;            // controle de concorrência
}
```

### 2.3 DTOs de API

#### UsuarioRequestDTO (criação/atualização)
```json
{
  "nome": "João da Silva",
  "cpf": "123.456.789-00",
  "rg": "1234567",
  "estadoEmissor": "RS",
  "dtNascimento": "1985-06-15",
  "nomeMae": "Maria da Silva",
  "email": "joao@email.com",
  "telefone1": "(51) 99999-0000",
  "telefone2": "(51) 3333-0000",
  "graduacoes": [
    {
      "id": 1,
      "idGraduacaoUsuario": null,
      "descricao": "Engenheiro Civil",
      "idProfissional": "CREA-RS 12345",
      "estadoEmissor": "RS"
    }
  ],
  "enderecos": [
    {
      "cep": "90000-000",
      "logradouro": "Rua Exemplo",
      "numero": "100",
      "complemento": "Apto 1",
      "bairro": "Centro",
      "cidade": "Porto Alegre",
      "estado": "RS"
    }
  ]
}
```

#### UsuarioResponseDTO
```json
{
  "id": 42,
  "nome": "João da Silva",
  "cpf": "123.456.789-00",
  "email": "joao@email.com",
  "status": "INCOMPLETO",
  "mensagemStatus": null,
  "dtNascimento": "1985-06-15",
  "nomeMae": "Maria da Silva",
  "rg": "1234567",
  "estadoEmissor": "RS",
  "telefone1": "(51) 99999-0000",
  "telefone2": "(51) 3333-0000",
  "arquivoRG": { "id": 10, "nomeArquivo": "rg_joao.pdf" },
  "graduacoes": [
    {
      "id": 1,
      "idGraduacaoUsuario": 7,
      "descricao": "Engenheiro Civil",
      "idProfissional": "CREA-RS 12345",
      "estadoEmissor": "RS",
      "arquivoIdProfissional": { "id": 11, "nomeArquivo": "crea_joao.pdf" }
    }
  ],
  "enderecos": [...],
  "ctrDthInc": "2026-01-10T14:30:00",
  "ctrDthAtu": "2026-02-20T09:15:00"
}
```

#### CadastroListagemDTO (para listagem do analista)
```json
{
  "id": 42,
  "nome": "João da Silva",
  "cpf": "123.456.789-00",
  "email": "joao@email.com",
  "status": "ANALISE_PENDENTE",
  "possuiGraduacao": true,
  "ctrDthInc": "2026-01-10T14:30:00",
  "ctrDthAtu": "2026-02-20T09:15:00",
  "idAnalise": null
}
```

#### AnaliseCadastroRequestDTO
```json
{
  "id": 42,
  "status": "EM_ANALISE",
  "ctrDthAtu": "2026-02-20T09:15:00"
}
```

#### AnaliseCadastroUpdateDTO (para decisão final)
```json
{
  "status": "APROVADO",
  "justificativa": "Documentação verificada e aprovada."
}
```

#### AnaliseCadastroResponseDTO
```json
{
  "id": 5,
  "status": "EM_ANALISE",
  "justificativa": null,
  "nomeAnalista": "Analista CBM",
  "ctrDthAtu": "2026-03-01T10:00:00",
  "usuario": { /* UsuarioResponseDTO completo */ }
}
```

#### StatusResponseDTO (retorno de concluirCadastro)
```json
{
  "statusCadastro": "ANALISE_PENDENTE",
  "ctrDthAtu": "2026-03-05T11:30:00",
  "mensagem": "Seu cadastro foi enviado para análise."
}
```

---

## 3. Requisitos Funcionais — Jornada do Usuário

### RF-U-01 — Preencher dados pessoais do cadastro
**Ator:** Usuário (RT) autenticado
**Pré-condição:** Usuário existe com `status = INCOMPLETO`
**Endpoint:** `PUT /v1/usuarios/{id}`
**Autorização:** O próprio usuário (CPF do JWT == CPF do usuário) OU role `USUARIOS_EDITAR`

**Campos obrigatórios (validação `@NotBlank`/`@NotNull`):**
- `nome` — nome completo
- `cpf` — validado por algoritmo módulo 11 (formato `000.000.000-00`)
- `dtNascimento` — data no passado, formato ISO-8601 (`yyyy-MM-dd`)
- `nomeMae` — nome completo da mãe
- `email` — formato RFC 5322 válido
- `telefone1` — mínimo 8 dígitos numéricos

**Campos opcionais:**
- `rg`, `estadoEmissor`, `telefone2`

**Comportamento:**
1. Validar todos os campos.
2. Verificar controle de concorrência: se `ctrDthAtu` do payload divergir do banco **e** `status != INCOMPLETO`, retornar `HTTP 409 Conflict`.
   - **Atenção:** quando `status == INCOMPLETO`, ignorar a verificação de `ctrDthAtu` (usuário ainda está preenchendo o rascunho).
3. Atualizar campos do `UsuarioEntity`.
4. Processar graduações via `alterarGraduacoesUsuario()` (ver RF-U-04).
5. Atualizar `ctrDthAtu = now()`.
6. Retornar `UsuarioResponseDTO` com HTTP 200.

**Erros:**
- `400 Bad Request` — campos obrigatórios ausentes ou inválidos
- `404 Not Found` — usuário não encontrado
- `409 Conflict` — `ctrDthAtu` divergente (apenas quando status ≠ INCOMPLETO)

---

### RF-U-02 — Upload do arquivo RG
**Endpoint:** `POST /v1/usuarios/{id}/arquivo-rg`
**Tipo:** `multipart/form-data`
**Parâmetros:** `arquivo` (binário), `nomeArquivo` (string)
**Autorização:** Próprio usuário OU `USUARIOS_EDITAR`

**Comportamento:**
1. Receber o arquivo binário.
2. Validar tipo MIME: aceitar apenas `application/pdf`, `image/jpeg`, `image/png`.
3. Validar tamanho máximo: **10 MB**.
4. Armazenar o arquivo no repositório de objetos (MinIO/S3) na bucket `solcbm-documentos` com path `usuarios/{id}/rg/{uuid}_{nomeArquivo}`.
5. Persistir metadados em `CBM_ARQUIVO` (`id`, `nomeArquivo`, `contentType`, `tamanho`, `objectKey`).
6. Associar `ArquivoEntity` ao campo `UsuarioEntity.arquivoRG`.
7. Retornar `ArquivoResponseDTO` (`id`, `nomeArquivo`) com HTTP 201.

**Regra de idempotência:** se `UsuarioEntity.arquivoRG` já existir, substituí-lo:
1. Excluir o arquivo antigo do repositório de objetos.
2. Excluir o registro `ArquivoEntity` antigo do banco.
3. Registrar o novo arquivo.

---

### RF-U-03 — Consultar arquivo RG
**Endpoint:** `GET /v1/usuarios/{id}/arquivo-rg`
**Autorização:** Próprio usuário OU `VERIFICARCADASTRO_CONSULTAR`

**Comportamento:**
1. Buscar `UsuarioEntity.arquivoRG`.
2. Se nulo: retornar `HTTP 404`.
3. Gerar URL pré-assinada do MinIO/S3 com expiração de 5 minutos.
4. Retornar redirect `HTTP 302` para a URL pré-assinada, ou retornar o binário com Content-Disposition.

---

### RF-U-04 — Gerenciar graduações do usuário
**Endpoint:** `PUT /v1/usuarios/{id}` (inclusas no body do usuário)
**Lógica de diff para `alterarGraduacoesUsuario()`:**

O algoritmo compara a lista recebida com a lista existente no banco:

1. Para cada `GraduacaoUsuarioEntity` **existente no banco**:
   - Procurar correspondência na lista recebida por `idGraduacaoUsuario` OU por `graduacao.id`.
   - Se **encontrada** e dados diferentes (`estadoEmissor`, `idProfissional` ou `graduacao.id` mudaram): atualizar o registro. Se o ID da graduação mudou (`ed.getId() != graduacao.getIdGraduacaoUsuario()`), excluir o arquivo `arquivoIdProfissional` anterior.
   - Se **não encontrada**: excluir o registro E excluir o arquivo `arquivoIdProfissional` associado.
2. Para cada graduação **nova** na lista recebida (que não encontrou correspondência): criar novo `GraduacaoUsuarioEntity`.

**Campos de cada graduação:**
- `id` (ID do tipo de graduação da tabela `CBM_GRADUACAO`) — obrigatório
- `idGraduacaoUsuario` (ID do vínculo usuário-graduação) — null se nova
- `idProfissional` — número da identidade profissional (ex: CREA-RS 12345)
- `estadoEmissor` — UF do conselho profissional

---

### RF-U-05 — Upload de documento da graduação (identidade profissional)
**Endpoint:** `POST /v1/usuarios/{id}/graduacoes/{idGraduacao}/arquivo`
**Tipo:** `multipart/form-data`
**Autorização:** Próprio usuário OU `USUARIOS_EDITAR`

**Comportamento:** idêntico ao RF-U-02, porém:
- Armazenar em `usuarios/{id}/graduacoes/{idGraduacao}/{uuid}_{nomeArquivo}`.
- Associar ao campo `GraduacaoUsuarioEntity.arquivoIdProfissional`.
- Substituir arquivo existente com as mesmas etapas de idempotência do RF-U-02.

---

### RF-U-06 — Consultar documento da graduação
**Endpoint:** `GET /v1/usuarios/{id}/graduacoes/{idGraduacao}/arquivo`
**Autorização:** Próprio usuário OU `VERIFICARCADASTRO_CONSULTAR`
**Comportamento:** idêntico ao RF-U-03.

---

### RF-U-07 — Gerenciar especializações do usuário
**Endpoints:**
- `POST /v1/usuarios/{id}/especializacoes` — incluir especialização
- `PUT /v1/usuarios/{id}/especializacoes/{idEspec}` — atualizar especialização
- `DELETE /v1/usuarios/{id}/especializacoes/{idEspec}` — remover especialização

**Campos de cada especialização:**
- `id` (ID do tipo de especialização da tabela `CBM_ESPECIALIZACAO`) — obrigatório
- `idEspecializacaoUsuario` — null se nova
- Arquivo de certificado (via endpoint específico)

---

### RF-U-08 — Upload de certificado de especialização
**Endpoint:** `POST /v1/usuarios/{id}/especializacoes/{idEspec}/arquivo`
**Comportamento:** idêntico ao RF-U-05.

---

### RF-U-09 — Consultar certificado de especialização
**Endpoint:** `GET /v1/usuarios/{id}/especializacoes/{idEspec}/arquivo`
**Comportamento:** idêntico ao RF-U-06.

---

### RF-U-10 — Submeter cadastro para análise (concluirCadastro)
**Endpoint:** `PATCH /v1/usuarios/{id}/concluir-cadastro`
**Autorização:** Nenhuma verificação de permissão (equivalente a `@Permissao(desabilitada=true)`). Qualquer usuário autenticado pode chamar este endpoint para seu próprio ID.

**Algoritmo completo:**
```
1. Buscar UsuarioEntity por id.
2. statusResultante = ANALISE_PENDENTE  (assume completo inicialmente)

3. Se usuarioEntity.getArquivoRG() == null:
       statusResultante = INCOMPLETO

4. Para cada GraduacaoUsuarioEntity em graduacoesDoUsuario:
       Se graduacaoUsuario.getArquivoIdProfissional() == null:
           statusResultante = INCOMPLETO

5. usuarioEntity.setStatus(statusResultante)
6. usuarioEntity.setMensagemStatus(null)
7. Persistir (UPDATE)
8. Atualizar ctrDthAtu = now()

9. SEMPRE notificar:
   notificacaoService.notificar(
       usuario,
       mensagem correspondente ao statusResultante,
       ContextoNotificacao.CADASTRO
   )

10. Se statusResultante == ANALISE_PENDENTE:
       instrutorED = buscarInstrutorPorCPF(usuarioEntity.getCpf())
       Se instrutorED != null E
          (instrutorED.getStatus() == APROVADO OR instrutorED.getStatus() == VENCIDO):
              instrutorHistoricoService.incluirEdicao(instrutorED)

11. Retornar StatusResponseDTO {
        statusCadastro: statusResultante,
        ctrDthAtu: usuarioEntity.getCtrDthAtu(),
        mensagem: mensagem do status
    }
    HTTP 200
```

**Mensagens de notificação:**
- `ANALISE_PENDENTE`: `"Seu cadastro foi enviado para análise."`
- `INCOMPLETO`: `"Seu cadastro está incompleto. Verifique os documentos obrigatórios."`

---

### RF-U-11 — Consultar dados do próprio cadastro
**Endpoint:** `GET /v1/usuarios/{cpf}` (por CPF, parâmetro de path)
**Endpoint alternativo:** `GET /v1/usuarios?cpf={cpf}` (por query param)
**Autorização:** Próprio usuário OU `USUARIOS_CONSULTAR`

**Comportamento:**
1. Buscar usuário por CPF.
2. Retornar `UsuarioResponseDTO` completo incluindo graduações, arquivos e endereços.
3. Se não encontrado: retornar `HTTP 404`.

---

### RF-U-12 — Listar tipos de graduação disponíveis
**Endpoint:** `GET /v1/graduacoes`
**Autorização:** Qualquer usuário autenticado

**Retorno:**
```json
[
  { "id": 1, "descricao": "Engenheiro Civil" },
  { "id": 2, "descricao": "Arquiteto" },
  { "id": 3, "descricao": "Engenheiro Elétrico" }
]
```

---

### RF-U-13 — Listar tipos de especialização disponíveis
**Endpoint:** `GET /v1/especializacoes`
**Autorização:** Qualquer usuário autenticado

**Retorno:**
```json
[
  { "id": 1, "descricao": "Sistemas de Sprinklers" },
  { "id": 2, "descricao": "PPCI - Plano de Prevenção" }
]
```

---

### RF-U-14 — Verificar se o RT é válido
**Endpoint:** `GET /v1/usuarios/is-usuario-rt-valido`
**Parâmetro:** Header `Authorization: Bearer {token}` (CPF extraído do JWT)
**Autorização:** Qualquer usuário autenticado

**Lógica:**
```java
// Retorna true se: status == APROVADO E possui ao menos uma graduação
boolean valido = StatusCadastro.APROVADO.equals(usuario.getStatus())
    && !graduacoesDoUsuario.isEmpty();
```

**Retorno:** `{ "valido": true }` — HTTP 200

---

## 4. Requisitos Funcionais — Jornada do Analista

### RF-A-01 — Listar cadastros em análise pelo analista atual
**Endpoint:** `GET /v1/admin/analise-cadastros/em-analise`
**Autorização:** Role `VERIFICARCADASTRO_LISTAR`
**Descrição:** Lista apenas os cadastros que o **analista logado** pegou para análise e ainda estão com `StatusAnalise.EM_ANALISE`.

**Implementação:**
```java
// Filtrar: idAnalista == usuarioLogado.getId() AND status == EM_ANALISE
AnaliseCadastroFilter filter = new AnaliseCadastroFilter();
filter.setIdAnalista(jwtService.getCurrentUserId());
filter.setStatus(StatusAnalise.EM_ANALISE);
return repository.findAll(filter);
```

**Retorno:** lista de `CadastroListagemDTO` com campo `idAnalise` preenchido.

---

### RF-A-02 — Listar cadastros pendentes de análise (fila geral)
**Endpoint:** `GET /v1/admin/analise-cadastros/pendentes`
**Autorização:** Role `VERIFICARCADASTRO_LISTAR`
**Filtros disponíveis (query params opcionais):**
- `nome` — filtro parcial case-insensitive (ILIKE)
- `cpf` — filtro parcial
- `incluidoDe` / `incluidoAte` — filtro por data de criação
- `possuiGraduacao` — boolean
- `pesquisaRapida` — string genérica que busca em nome, CPF e e-mail simultaneamente
- `page` / `size` — paginação (padrão: 20 registros por página)

**Lógica:** Buscar usuários com `StatusCadastro = ANALISE_PENDENTE` que **não possuem** um `AnaliseCadastroEntity` com `StatusAnalise = EM_ANALISE` associado. (Ou seja, estão aguardando um analista pegar.)

**Retorno:** página de `CadastroListagemDTO` (sem `idAnalise`).

---

### RF-A-03 — Tomar cadastro para análise (iniciar análise)
**Endpoint:** `POST /v1/admin/analise-cadastros`
**Autorização:** Role `VERIFICARCADASTRO_EDITAR`
**Body:** `AnaliseCadastroRequestDTO`

**Algoritmo completo de `incluirAnaliseCadastro()`:**
```
1. Validar body:
   - id obrigatório → 400 se ausente
   - status obrigatório → 400 se ausente
   - status deve ser EM_ANALISE, APROVADO ou REPROVADO → 400 se inválido
   - ctrDthAtu obrigatório → 400 se ausente

2. Buscar UsuarioEntity por id → 400 se não encontrado

3. Verificar concorrência:
   Se usuarioEntity.ctrDthAtu != request.ctrDthAtu → HTTP 409 Conflict

4. Se usuarioEntity.status == ANALISE_PENDENTE:
   a. Criar AnaliseCadastroEntity:
      - idAnalista = usuarioLogado.getId()
      - nomeAnalista = usuarioLogado.getNome()
      - usuario = usuarioEntity
      - status = StatusAnalise.EM_ANALISE
   b. Persistir AnaliseCadastroEntity → retornar idAnalise criado
   c. Notificar usuário (notificação interna, sem e-mail):
      mensagem = "Cadastro em processo de análise"
      contexto = CADASTRO

5. Se request.status != usuarioEntity.status:
   usuarioEntity.setStatus(request.status)
   Persistir usuário

6. Retornar HTTP 201 com header Location: /v1/admin/analise-cadastros/{idAnalise}
```

**Observação:** O passo 4 só cria o `AnaliseCadastroEntity` se o status atual for `ANALISE_PENDENTE`. O passo 5 permite que o analista já passe o usuário para outro status (ex: `EM_ANALISE`) em uma única operação.

---

### RF-A-04 — Consultar análise específica
**Endpoint:** `GET /v1/admin/analise-cadastros/{id}`
**Autorização:** Role `VERIFICARCADASTRO_CONSULTAR`

**Retorno:** `AnaliseCadastroResponseDTO` contendo:
- `id`, `status`, `justificativa`, `nomeAnalista`, `ctrDthAtu`
- `usuario`: `UsuarioResponseDTO` completo (incluindo graduações e documentos)

---

### RF-A-05 — Listar análises de um usuário específico
**Endpoint:** `GET /v1/admin/analise-cadastros?usuarioId={idUsuario}`
**Autorização:** Role `VERIFICARCADASTRO_CONSULTAR`

**Retorno:** lista de `AnaliseCadastroResponseDTO` (histórico de todas as análises do usuário).

---

### RF-A-06 — Atualizar status da análise (decidir)
**Endpoint:** `PUT /v1/admin/analise-cadastros/{id}`
**Autorização:** Role `VERIFICARCADASTRO_EDITAR`
**Body:** `AnaliseCadastroUpdateDTO` (`status`, `justificativa`)

**Algoritmo completo de `alterarStatusAnaliseCadastro()`:**
```
1. Buscar AnaliseCadastroEntity por id → 400 se não encontrado

2. Verificar autorização:
   SE analiseEntity.idAnalista != usuarioLogado.getId()
      E usuarioLogado NÃO tem role CENTRALADM_EDITAR:
          → HTTP 403 Forbidden
   (Somente o analista que tomou a análise ou um super-analista pode alterar)

3. Atualizar AnaliseCadastroEntity:
   analiseEntity.status = request.status
   analiseEntity.justificativa = request.justificativa
   Persistir

4. Executar mudarStatusCadastro(analiseEntity.usuario.id, request):
   Conforme tabela de mapeamento StatusAnalise → StatusCadastro:

   a. Determinar statusCadastro e enviarEmail:
      CANCELADO  → StatusCadastro.ANALISE_PENDENTE | enviarEmail = false
      APROVADO   → StatusCadastro.APROVADO         | enviarEmail = true
      REPROVADO  → StatusCadastro.REPROVADO        | enviarEmail = true

   b. Buscar UsuarioEntity por id
   c. usuarioEntity.setStatus(statusCadastro)
   d. usuarioEntity.setMensagemStatus(request.justificativa)
   e. Persistir usuário

   f. Notificar usuário:
      mensagem = mensagem correspondente ao StatusCadastro
      contexto = CADASTRO
      enviarEmail = conforme determinado acima
      Se enviarEmail: disparar e-mail (via SMTP)

5. Retornar HTTP 200
```

**Validações adicionais:**
- `justificativa` obrigatória quando `status = REPROVADO` → `400` se ausente.
- `status` não pode ser `EM_ANALISE` neste endpoint (só é definido na criação via RF-A-03).

---

## 5. Requisitos Funcionais — Notificações

### RF-N-01 — Enviar notificação interna
**Serviço:** `NotificacaoService.notificar(usuario, mensagem, contexto)`

**Comportamento:**
1. Criar registro em `CBM_NOTIFICACAO` com `lida = false`.
2. Não enviar e-mail neste caso.

### RF-N-02 — Enviar notificação com e-mail
**Serviço:** `NotificacaoService.notificar(usuario, mensagem, contexto, enviarEmail=true, tipoStatus)`

**Comportamento:**
1. Criar registro em `CBM_NOTIFICACAO`.
2. Disparar e-mail via SMTP usando template HTML correspondente ao `tipoStatus`.
3. E-mail destinatário: `usuario.email`.
4. Assunto: `"[SOL/CBM-RS] Atualização do seu cadastro - {tipoStatus}"`.

### RF-N-03 — Listar notificações não lidas
**Endpoint:** `GET /v1/notificacoes/nao-lidas`
**Autorização:** Próprio usuário (CPF do JWT)
**Retorno:** lista de notificações com `lida = false` para o usuário.

### RF-N-04 — Marcar notificação como lida
**Endpoint:** `PUT /v1/notificacoes/{id}`
**Body:** `{ "lida": true }`
**Autorização:** Próprio usuário.

---

## 6. Contratos REST Completos

### 6.1 Endpoints do Usuário (Área Pública/Próprio Usuário)

| Método | Path | Descrição | Auth |
|--------|------|-----------|------|
| `GET` | `/v1/usuarios/{cpf}` | Consultar usuário por CPF (path param) | Próprio / `USUARIOS_CONSULTAR` |
| `GET` | `/v1/usuarios?cpf={cpf}` | Consultar usuário por CPF (query param) | Próprio / `USUARIOS_CONSULTAR` |
| `POST` | `/v1/usuarios` | Criar novo usuário (vindo do P01) | `USUARIOS_INCLUIR` |
| `PUT` | `/v1/usuarios/{id}` | Atualizar dados do usuário + graduações | Próprio / `USUARIOS_EDITAR` |
| `PATCH` | `/v1/usuarios/{id}/concluir-cadastro` | Submeter para análise | Próprio (sem verificação permissão) |
| `GET` | `/v1/usuarios/is-usuario-rt-valido` | Verificar se RT está aprovado e ativo | Autenticado |
| `GET` | `/v1/usuarios/{id}/credenciamento` | Consultar análise de credenciamento | Autenticado |
| `POST` | `/v1/usuarios/{id}/arquivo-rg` | Upload do RG | Próprio / `USUARIOS_EDITAR` |
| `GET` | `/v1/usuarios/{id}/arquivo-rg` | Download/URL do RG | Próprio / `VERIFICARCADASTRO_CONSULTAR` |
| `PUT` | `/v1/usuarios/{id}/arquivo-rg` | Substituir RG | Próprio / `USUARIOS_EDITAR` |
| `POST` | `/v1/usuarios/{id}/graduacoes/{idGraduacao}/arquivo` | Upload doc. graduação | Próprio / `USUARIOS_EDITAR` |
| `GET` | `/v1/usuarios/{id}/graduacoes/{idGraduacao}/arquivo` | Download doc. graduação | Próprio / `VERIFICARCADASTRO_CONSULTAR` |
| `PUT` | `/v1/usuarios/{id}/graduacoes/{idGraduacao}/arquivo` | Substituir doc. graduação | Próprio / `USUARIOS_EDITAR` |
| `POST` | `/v1/usuarios/{id}/especializacoes/{idEspec}/arquivo` | Upload certif. especialização | Próprio / `USUARIOS_EDITAR` |
| `GET` | `/v1/usuarios/{id}/especializacoes/{idEspec}/arquivo` | Download certif. especialização | Próprio / `VERIFICARCADASTRO_CONSULTAR` |
| `PUT` | `/v1/usuarios/{id}/especializacoes/{idEspec}/arquivo` | Substituir certif. especialização | Próprio / `USUARIOS_EDITAR` |

### 6.2 Endpoints do Analista (Área Administrativa)

| Método | Path | Descrição | Auth |
|--------|------|-----------|------|
| `GET` | `/v1/admin/analise-cadastros/em-analise` | Listar análises em andamento do analista logado | `VERIFICARCADASTRO_LISTAR` |
| `GET` | `/v1/admin/analise-cadastros/pendentes` | Listar cadastros aguardando análise (fila) | `VERIFICARCADASTRO_LISTAR` |
| `POST` | `/v1/admin/analise-cadastros` | Tomar cadastro para análise | `VERIFICARCADASTRO_EDITAR` |
| `GET` | `/v1/admin/analise-cadastros/{id}` | Consultar análise específica | `VERIFICARCADASTRO_CONSULTAR` |
| `GET` | `/v1/admin/analise-cadastros?usuarioId={id}` | Listar histórico de análises do usuário | `VERIFICARCADASTRO_CONSULTAR` |
| `PUT` | `/v1/admin/analise-cadastros/{id}` | Aprovar / Reprovar / Cancelar análise | `VERIFICARCADASTRO_EDITAR` |

### 6.3 Endpoints de Referência

| Método | Path | Descrição | Auth |
|--------|------|-----------|------|
| `GET` | `/v1/graduacoes` | Listar tipos de graduação disponíveis | Autenticado |
| `GET` | `/v1/especializacoes` | Listar tipos de especialização disponíveis | Autenticado |

---

## 7. Regras de Negócio

| ID | Regra | Implementação |
|----|-------|---------------|
| **RN-P02-01** | Ao criar usuário (P01), status inicial é sempre `INCOMPLETO` | `UsuarioService.criar()` → `usuario.setStatus(INCOMPLETO)` |
| **RN-P02-02** | Controle de concorrência por `ctrDthAtu` ignorado quando `status == INCOMPLETO` | `UsuarioService.alterar()` |
| **RN-P02-03** | `concluirCadastro()` não exige permissão específica — qualquer RT autenticado pode submeter | `@PermitAll` ou sem `@PreAuthorize` |
| **RN-P02-04** | `concluirCadastro()` avalia: `arquivoRG` presente + `arquivoIdProfissional` de CADA graduação | `UsuarioConclusaoService.concluirCadastro()` |
| **RN-P02-05** | Se qualquer documento obrigatório ausente → `INCOMPLETO`; todos presentes → `ANALISE_PENDENTE` | `UsuarioConclusaoService.concluirCadastro()` |
| **RN-P02-06** | `mensagemStatus` é zerada a cada chamada de `concluirCadastro()` | `usuario.setMensagemStatus(null)` |
| **RN-P02-07** | Notificação SEMPRE enviada em `concluirCadastro()`, independente do status resultante | `notificacaoService.notificar()` após persistência |
| **RN-P02-08** | Se `ANALISE_PENDENTE` e usuário também é instrutor com status `APROVADO` ou `VENCIDO`: registrar histórico | `instrutorHistoricoService.incluirEdicao()` |
| **RN-P02-09** | Upload de arquivo substitui o anterior (idempotência): excluir arquivo antigo do storage e do banco | `ArquivoService.substituir()` |
| **RN-P02-10** | Tipos MIME aceitos para upload: `application/pdf`, `image/jpeg`, `image/png` | Validação no controller |
| **RN-P02-11** | Tamanho máximo de arquivo: 10 MB | `MultipartFile.getSize() > 10_485_760` → 400 |
| **RN-P02-12** | CPF deve ser único no sistema; tentativa de cadastrar CPF duplicado → HTTP 400 com mensagem formatada | `@Column(unique=true)` + `DataIntegrityViolationException` |
| **RN-P02-13** | Apenas o analista que tomou a análise OU usuário com role `CENTRALADM_EDITAR` pode alterar o status | `AnaliseCadastroService.alterarStatus()` |
| **RN-P02-14** | `CANCELADO` devolve o cadastro para `ANALISE_PENDENTE` (não para o usuário); sem envio de e-mail | `mudarStatusCadastro()` |
| **RN-P02-15** | `APROVADO` e `REPROVADO` disparam e-mail ao usuário | `notificacaoService.notificar(..., enviarEmail=true)` |
| **RN-P02-16** | `justificativa` é obrigatória quando `StatusAnalise == REPROVADO` | Validação em `AnaliseCadastroService.alterarStatus()` |
| **RN-P02-17** | `mensagemStatus` do usuário recebe a `justificativa` da análise (tanto aprovação quanto reprovação) | `usuario.setMensagemStatus(justificativa)` |
| **RN-P02-18** | `listarCadastrosEmAnalise()` filtra por `idAnalista == analista_logado` + `status == EM_ANALISE` | Não lista análises de outros analistas |
| **RN-P02-19** | Ao alterar graduações via `alterarGraduacoesUsuario()`: se graduação removida possuía arquivo → excluir arquivo do storage | `GraduacaoUsuarioService.excluirArquivoGraduacao()` |
| **RN-P02-20** | `CadastroListagemDTO.possuiGraduacao` = true se lista de graduações não estiver vazia | `!graduacoesUsuario.isEmpty()` |

---

## 8. Requisitos Não Funcionais

### RNF-01 — Stack de tecnologia
```
Java 21 (LTS)
Spring Boot 3.2+
Spring Security 6 (JWT Bearer Token)
Spring Data JPA + Hibernate 6
PostgreSQL 16
Flyway (migrações de banco)
MinIO (armazenamento de arquivos — equivalente ao S3)
Spring Mail (notificações por e-mail)
Testcontainers (testes de integração)
MapStruct (conversão DTO↔Entity)
SpringDoc OpenAPI 2 (documentação Swagger)
```

### RNF-02 — Autorização sem PROCERGS
Substituir `@Permissao(objeto, acao)` + `SessionMB` do arqjava4 por:

```java
// Anotações Spring Security nos métodos de serviço:
@PreAuthorize("hasAuthority('VERIFICARCADASTRO_LISTAR')")
@PreAuthorize("hasAuthority('VERIFICARCADASTRO_EDITAR')")
@PreAuthorize("hasAuthority('VERIFICARCADASTRO_CONSULTAR')")
@PreAuthorize("hasAuthority('CENTRALADM_EDITAR')")
@PreAuthorize("hasAuthority('USUARIOS_EDITAR')")

// Substituir sessionMB.getUser().getId() por:
Authentication auth = SecurityContextHolder.getContext().getAuthentication();
String userId = auth.getName();                  // subject do JWT
String nome = (String) claims.get("name");       // claim do JWT

// Substituir sessionMB.hasPermission("CENTRALADM", "EDITAR") por:
auth.getAuthorities().stream()
    .anyMatch(a -> a.getAuthority().equals("CENTRALADM_EDITAR"))
```

### RNF-03 — Substituição de @SOEAuthRest
`@SOEAuthRest` é um interceptor PROCERGS que valida o token SOE. Substituir por:

```java
// SecurityConfig.java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) {
    return http
        .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/v1/admin/**").hasAnyAuthority("VERIFICARCADASTRO_LISTAR", "VERIFICARCADASTRO_EDITAR")
            .requestMatchers("/v1/**").authenticated()
            .anyRequest().permitAll()
        )
        .build();
}
```

### RNF-04 — Armazenamento de arquivos
Substituir armazenamento interno (PROCERGS) por **MinIO** ou **AWS S3**:

```yaml
# application.yml
minio:
  endpoint: http://localhost:9000
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
  bucket: solcbm-documentos
  presigned-url-expiry-minutes: 5
```

```java
// ArquivoService.java
public String upload(MultipartFile file, String objectKey) {
    minioClient.putObject(PutObjectArgs.builder()
        .bucket(bucket)
        .object(objectKey)
        .stream(file.getInputStream(), file.getSize(), -1)
        .contentType(file.getContentType())
        .build());
    return objectKey;
}

public String gerarUrlPresignada(String objectKey) {
    return minioClient.getPresignedObjectUrl(GetPresignedObjectUrlArgs.builder()
        .bucket(bucket).object(objectKey)
        .method(Method.GET)
        .expiry(expiryMinutes, TimeUnit.MINUTES)
        .build());
}
```

### RNF-05 — Paginação e filtros
Todos os endpoints de listagem devem suportar:
- `page` (0-indexed, padrão: 0)
- `size` (padrão: 20, máximo: 100)
- `sort` (campo e direção: `nome,asc`)

Utilizar `Pageable` do Spring Data.

### RNF-06 — Tratamento de erros
```java
// GlobalExceptionHandler.java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorDTO> handleConstraint(ConstraintViolationException e) {
        // CPF duplicado → HTTP 400 com mensagem formatada
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<ErrorDTO> handleConflict(OptimisticLockingFailureException e) {
        // ctrDthAtu divergente → HTTP 409 Conflict
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorDTO> handleForbidden(AccessDeniedException e) {
        // Sem permissão → HTTP 403
    }

    @ExceptionHandler(EntityNotFoundException.class)
    public ResponseEntity<ErrorDTO> handleNotFound(EntityNotFoundException e) {
        // Entidade não encontrada → HTTP 404
    }
}
```

### RNF-07 — Validação de CPF
```java
@Constraint(validatedBy = CpfValidator.class)
public @interface Cpf { ... }

public class CpfValidator implements ConstraintValidator<Cpf, String> {
    @Override
    public boolean isValid(String cpf, ConstraintValidatorContext ctx) {
        // Remover formatação, aplicar algoritmo módulo 11
        // Rejeitar CPFs com todos os dígitos iguais (111.111.111-11, etc.)
    }
}
```

### RNF-08 — Migrações de banco (Flyway)
```sql
-- V1__create_usuario.sql
CREATE SEQUENCE CBM_ID_USUARIO_SEQ START 1 INCREMENT 1;
CREATE TABLE CBM_USUARIO (
    NRO_INT_USUARIO     BIGINT PRIMARY KEY DEFAULT nextval('CBM_ID_USUARIO_SEQ'),
    NOME_USUARIO        VARCHAR(200) NOT NULL,
    TXT_CPF             VARCHAR(14)  NOT NULL UNIQUE,
    TXT_RG              VARCHAR(20),
    TXT_UF_RG           CHAR(2),
    NRO_INT_ARQUIVO_RG  BIGINT REFERENCES CBM_ARQUIVO(NRO_INT_ARQUIVO),
    DT_NASCIMENTO       DATE NOT NULL,
    NOME_MAE            VARCHAR(200) NOT NULL,
    TXT_EMAIL           VARCHAR(200) NOT NULL,
    TXT_TELEFONE1       VARCHAR(20)  NOT NULL,
    TXT_TELEFONE2       VARCHAR(20),
    TP_STATUS           VARCHAR(20)  NOT NULL DEFAULT 'INCOMPLETO',
    TXT_MENSAGEM_STATUS TEXT,
    CTR_DTH_INC         TIMESTAMP    NOT NULL DEFAULT now(),
    CTR_DTH_ATU         TIMESTAMP    NOT NULL DEFAULT now()
);

-- V2__create_graduacao_usuario.sql
CREATE SEQUENCE CBM_ID_GRAD_USUARIO_SEQ START 1 INCREMENT 1;
CREATE TABLE CBM_GRADUACAO_USUARIO (
    NRO_INT_GRADUACAO_USUARIO  BIGINT PRIMARY KEY DEFAULT nextval('CBM_ID_GRAD_USUARIO_SEQ'),
    NRO_INT_GRADUACAO          BIGINT NOT NULL REFERENCES CBM_GRADUACAO(NRO_INT_GRADUACAO),
    NRO_INT_USUARIO            BIGINT NOT NULL REFERENCES CBM_USUARIO(NRO_INT_USUARIO),
    NRO_INT_ARQUIVO_ID_PROFIS  BIGINT REFERENCES CBM_ARQUIVO(NRO_INT_ARQUIVO),
    TXT_ID_PROFISSIONAL        VARCHAR(50),
    TXT_UF_GRADUACAO           CHAR(2),
    CTR_DTH_INC                TIMESTAMP NOT NULL DEFAULT now(),
    CTR_DTH_ATU                TIMESTAMP NOT NULL DEFAULT now()
);

-- V3__create_analise_cadastro.sql
CREATE SEQUENCE CBM_ID_ANALISE_CADASTRO_SEQ START 1 INCREMENT 1;
CREATE TABLE CBM_ANALISE_CADASTRO (
    NRO_INT_ANALISE_CADASTRO  BIGINT PRIMARY KEY DEFAULT nextval('CBM_ID_ANALISE_CADASTRO_SEQ'),
    NRO_INT_USUARIO           BIGINT NOT NULL REFERENCES CBM_USUARIO(NRO_INT_USUARIO),
    NOME_USUARIO              VARCHAR(200),
    NRO_INT_USUARIO_SOE       BIGINT,
    TP_STATUS                 VARCHAR(20) NOT NULL,
    TXT_JUSTIFICATIVA         TEXT,
    CTR_DTH_INC               TIMESTAMP NOT NULL DEFAULT now(),
    CTR_DTH_ATU               TIMESTAMP NOT NULL DEFAULT now()
);
```

### RNF-09 — Testes obrigatórios
| Tipo | Cobertura mínima |
|------|------------------|
| Unitários (Mockito) | Toda lógica de `*Service.java` (70% de cobertura) |
| Integração (Testcontainers) | Todos os endpoints REST + banco de dados real |
| Cenários obrigatórios | `concluirCadastro()` — INCOMPLETO, ANALISE_PENDENTE, com/sem instrutor |
| Cenários obrigatórios | `alterarStatusAnaliseCadastro()` — todos os StatusAnalise de entrada |
| Cenários obrigatórios | Upload/download de arquivos com MinIO real (via Testcontainers) |
| Cenários obrigatórios | `ctrDthAtu` divergente → HTTP 409 |
| Cenários obrigatórios | Analista tentando alterar análise de outro → HTTP 403 |

---

## 9. Matriz de Autorização

| Operação | RT (próprio) | Analista | Super-Analista |
|----------|:------------:|:--------:|:--------------:|
| Preencher dados pessoais | ✅ | ✅ `USUARIOS_EDITAR` | ✅ |
| Upload de documentos | ✅ | ✅ | ✅ |
| Submeter para análise | ✅ (sem permissão específica) | ✅ | ✅ |
| Consultar próprio cadastro | ✅ | ✅ `USUARIOS_CONSULTAR` | ✅ |
| Listar cadastros pendentes | ❌ | ✅ `VERIFICARCADASTRO_LISTAR` | ✅ |
| Tomar cadastro para análise | ❌ | ✅ `VERIFICARCADASTRO_EDITAR` | ✅ |
| Consultar análise | ❌ | ✅ `VERIFICARCADASTRO_CONSULTAR` | ✅ |
| Aprovar/Reprovar (própria) | ❌ | ✅ (somente a que tomou) | ✅ |
| Aprovar/Reprovar (de outro) | ❌ | ❌ → HTTP 403 | ✅ `CENTRALADM_EDITAR` |

---

## 10. Estrutura de Projeto Recomendada

```
src/main/java/br/gov/rs/cbm/sol/
├── config/
│   ├── SecurityConfig.java          # Spring Security + JWT
│   ├── MinioConfig.java             # Cliente MinIO
│   └── FlywayConfig.java
├── domain/
│   ├── entity/
│   │   ├── UsuarioEntity.java
│   │   ├── GraduacaoUsuarioEntity.java
│   │   ├── AnaliseCadastroEntity.java
│   │   ├── ArquivoEntity.java
│   │   └── EnderecoUsuarioEntity.java
│   └── enums/
│       ├── StatusCadastro.java
│       └── StatusAnalise.java
├── dto/
│   ├── request/
│   │   ├── UsuarioRequestDTO.java
│   │   ├── AnaliseCadastroRequestDTO.java
│   │   └── AnaliseCadastroUpdateDTO.java
│   └── response/
│       ├── UsuarioResponseDTO.java
│       ├── CadastroListagemDTO.java
│       ├── AnaliseCadastroResponseDTO.java
│       └── StatusResponseDTO.java
├── repository/
│   ├── UsuarioRepository.java       # JpaRepository + Specification
│   ├── GraduacaoUsuarioRepository.java
│   └── AnaliseCadastroRepository.java
├── service/
│   ├── UsuarioService.java          # CRUD + concluirCadastro
│   ├── GraduacaoUsuarioService.java # diff algorithm
│   ├── AnaliseCadastroService.java  # análise workflow
│   ├── ArquivoService.java          # MinIO upload/download
│   └── NotificacaoService.java      # notificações + e-mail
├── controller/
│   ├── UsuarioController.java       # /v1/usuarios/**
│   ├── AnaliseCadastroController.java  # /v1/admin/analise-cadastros/**
│   └── NotificacaoController.java   # /v1/notificacoes/**
├── mapper/
│   ├── UsuarioMapper.java           # MapStruct
│   └── AnaliseCadastroMapper.java
└── exception/
    ├── GlobalExceptionHandler.java
    └── BusinessException.java
```

---

## 11. Diagrama de Estados do Cadastro

```
                    ┌─────────────────────────────────────────────┐
                    │              CICLO DE VIDA                  │
                    └─────────────────────────────────────────────┘

   [P01 cria usuário]
          │
          ▼
   ┌─────────────┐    concluirCadastro()          ┌──────────────────┐
   │  INCOMPLETO │   (docs incompletos)  ──────►  │  INCOMPLETO      │
   │  (inicial)  │                                │  (loop até       │
   └──────┬──────┘                                │   completar)     │
          │ concluirCadastro()                     └──────────────────┘
          │ (todos os docs presentes)
          ▼
   ┌──────────────────┐
   │  ANALISE_PENDENTE │ ◄─── CANCELADO (volta aqui)
   └────────┬─────────┘
            │ incluirAnaliseCadastro()
            │ (analista pega da fila)
            ▼
   ┌──────────────────┐
   │   EM_ANALISE     │
   └────────┬─────────┘
            │ alterarStatusAnaliseCadastro()
            ├──────────────┬──────────────────┐
            ▼              ▼                  ▼
      ┌──────────┐  ┌──────────┐       ┌──────────────────┐
      │ APROVADO │  │REPROVADO │       │ ANALISE_PENDENTE  │
      │ (e-mail) │  │ (e-mail) │       │ (retorno por      │
      └──────────┘  └──────────┘       │  CANCELADO)       │
                                        └──────────────────┘
```

---

## 12. Dependências Maven

```xml
<dependencies>
    <!-- Spring Boot Starters -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-mail</artifactId>
    </dependency>

    <!-- Banco de dados -->
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-core</artifactId>
    </dependency>

    <!-- MinIO (armazenamento de arquivos) -->
    <dependency>
        <groupId>io.minio</groupId>
        <artifactId>minio</artifactId>
        <version>8.5.7</version>
    </dependency>

    <!-- Mapeamento -->
    <dependency>
        <groupId>org.mapstruct</groupId>
        <artifactId>mapstruct</artifactId>
        <version>1.5.5.Final</version>
    </dependency>

    <!-- Documentação -->
    <dependency>
        <groupId>org.springdoc</groupId>
        <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
        <version>2.3.0</version>
    </dependency>

    <!-- Testes -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>postgresql</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>minio</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```


---

## 13. Novos Requisitos — Atualização v2.1 (25/03/2026)

> **Origem:** Documentação Hammer Sprint 02 (ID2701, Demandas 27–29) e análise de impacto de 25/03/2026.  
> **Referência:** `Impacto_Novos_Requisitos_P01_P14.md` — seção P02.

---

### RN-P02-N1 — Renomear Botão "Salvar" para "Enviar" no Formulário de Cadastro 🟠 P02-M1

**Prioridade:** Alta  
**Origem:** IDI2701 / Demanda 27 — Sprint 02 Hammer

**Descrição:** O botão que submete o formulário de cadastro de usuário externo para análise do CBM deve ser renomeado de **"Salvar"** para **"Enviar"**. A mudança é semântica e de grande importância para o usuário: "Salvar" sugere persistência local e editabilidade posterior, enquanto "Enviar" comunica claramente que o formulário está sendo encaminhado para revisão do CBM.

**Mudança no BPMN:**
- `J1_T03` (UserTask) — renomear label de *"Cidadão salva formulário e envia para análise"* para *"Cidadão preenche e **envia** formulário para análise"*.

**Mudança no Frontend Angular:**

```html
<!-- ANTES (cadastro-usuario.component.html) -->
<button mat-raised-button color="primary" (click)="onSalvar()">
  Salvar
</button>

<!-- DEPOIS -->
<button mat-raised-button color="primary" (click)="onEnviar()">
  Enviar
</button>
```

```typescript
// ANTES
onSalvar(): void {
  this.cadastroService.salvarCadastro(this.form.value).subscribe(...);
}

// DEPOIS
onEnviar(): void {
  this.cadastroService.enviarParaAnalise(this.form.value).subscribe(...);
}
```

**Mudança no Backend:** Nenhuma alteração de contrato de API necessária — o endpoint mantém o mesmo path e payload. Apenas a label do botão muda.

**Critérios de Aceitação:**
- [ ] CA-P02-N1a: O botão exibe o texto "Enviar" no formulário de cadastro externo
- [ ] CA-P02-N1b: A funcionalidade de submissão permanece idêntica (formulário enviado para análise do CBM)
- [ ] CA-P02-N1c: Nenhuma regressão no fluxo de cadastro J1 e J2

---

### RN-P02-N2 — Formulário de Cadastro Externo em Abas por Tipo de Perfil 🟠 P02-M2

**Prioridade:** Alta  
**Origem:** Demanda 28 — Sprint 02 Hammer

**Descrição:** O formulário de cadastro de usuário externo deve ser reestruturado em **abas distintas por tipo de perfil**, exibindo apenas os campos relevantes para o tipo selecionado. O formulário linear atual exibe campos irrelevantes e confunde usuários.

**Tipos de perfil com abas próprias:**
1. **Responsável Técnico (RT)** — dados profissionais + registro CREA/CAU + documentos técnicos
2. **Responsável pelo Uso (RU)** — dados do responsável pela edificação
3. **Proprietário** — dados do proprietário do imóvel
4. **Instrutor de Brigadistas** — dados de credenciamento e especialização

**Mudança no fluxo BPMN:**
- `J1_T01` (UserTask — "Cidadão preenche dados pessoais") divide-se em duas etapas sequenciais:
  1. *Seleção do tipo de perfil* — dropdown `TipoPerfil`
  2. *Preenchimento do formulário específico* — exibido com base no tipo selecionado

**Implementação Frontend:**

```typescript
// cadastro-usuario.component.ts
export class CadastroUsuarioComponent {
  tipoPerfil: TipoPerfil | null = null;
  
  get formularioAtivo(): FormGroup {
    switch(this.tipoPerfil) {
      case TipoPerfil.RT:          return this.formRT;
      case TipoPerfil.RU:          return this.formRU;
      case TipoPerfil.PROPRIETARIO: return this.formProprietario;
      case TipoPerfil.INSTRUTOR:   return this.formInstrutor;
      default:                     return this.formBase;
    }
  }
}
```

```html
<!-- Template com estrutura de abas -->
<mat-tab-group *ngIf="tipoPerfil" [selectedIndex]="tabIndex">
  <mat-tab label="Dados Pessoais">
    <!-- campos comuns a todos os perfis -->
  </mat-tab>
  <mat-tab label="Dados Profissionais" *ngIf="tipoPerfil === 'RT'">
    <!-- campos específicos do RT: CREA/CAU, especialidade, etc. -->
  </mat-tab>
  <mat-tab label="Credenciamento" *ngIf="tipoPerfil === 'INSTRUTOR'">
    <!-- campos específicos do instrutor -->
  </mat-tab>
  <mat-tab label="Documentos">
    <!-- documentos exigidos variam por perfil -->
  </mat-tab>
</mat-tab-group>
```

**Validações por perfil no Backend:**

```java
// CadastroUsuarioValidator.java
public void validar(CadastroUsuarioRequest req) {
    switch (req.getTipoPerfil()) {
        case RT:
            validarRT(req); // exige CREA/CAU, especialidade, documentos técnicos
            break;
        case INSTRUTOR:
            validarInstrutor(req); // exige certificado, área de atuação
            break;
        case RU:
        case PROPRIETARIO:
            validarBasico(req); // apenas dados pessoais e endereço
            break;
    }
}
```

**Modelo de dados — campo novo:**
```sql
ALTER TABLE cbm_usuario ADD COLUMN tp_perfil VARCHAR(30)
  CHECK (tp_perfil IN ('RT','RU','PROPRIETARIO','INSTRUTOR'));
```

**Critérios de Aceitação:**
- [ ] CA-P02-N2a: Ao selecionar o tipo de perfil, o formulário exibe apenas os campos relevantes para aquele tipo
- [ ] CA-P02-N2b: O backend valida os campos obrigatórios de acordo com o `tp_perfil` enviado
- [ ] CA-P02-N2c: Tentativa de cadastro de RT sem CREA/CAU retorna erro de validação 422
- [ ] CA-P02-N2d: Formulário de Proprietário não exige campos técnicos

---

### RN-P02-N3 — Exibir Histórico de Credenciamentos Vencidos (Instrutores) 🟡 P02-M3

**Prioridade:** Média  
**Origem:** Demanda 29 — Sprint 02 Hammer

**Descrição:** Instrutores de brigadistas devem visualizar não apenas seus credenciamentos ativos, mas também os **credenciamentos expirados**, com data de vencimento, situação e botão de renovação.

**Mudança no Fluxo (J1 — Instrutor autenticado):**

Após login do instrutor, na tela de perfil, adicionar bloco "Histórico de Credenciamentos" com duas abas:
- **Ativos** — credenciamentos com `dt_validade >= CURRENT_DATE`
- **Vencidos** — credenciamentos com `dt_validade < CURRENT_DATE`, com opção de renovação

**Novo Endpoint REST:**

```
GET /api/v1/instrutores/{id}/credenciamentos?situacao=TODOS
```

| Parâmetro | Valores | Default |
|-----------|---------|---------|
| `situacao` | `ATIVOS`, `VENCIDOS`, `TODOS` | `ATIVOS` |

**Response:**
```json
{
  "credenciamentos": [
    {
      "id": "uuid",
      "tipo": "BRIGADISTA_NIVEL_1",
      "dtEmissao": "2022-01-15",
      "dtValidade": "2024-01-15",
      "situacao": "VENCIDO",
      "podeRenovar": true
    }
  ]
}
```

**Índice de banco de dados (performance):**
```sql
-- Necessário para consultas de validade em tabelas com muitos registros
CREATE INDEX IF NOT EXISTS idx_credenciamento_dt_validade
  ON cbm_credenciamento(dt_validade);
CREATE INDEX IF NOT EXISTS idx_credenciamento_id_usuario
  ON cbm_credenciamento(id_usuario);
```

**Critérios de Aceitação:**
- [ ] CA-P02-N3a: Instrutor autenticado visualiza aba "Ativos" e aba "Vencidos" na tela de credenciamentos
- [ ] CA-P02-N3b: Credenciamentos vencidos exibem data de vencimento e botão "Renovar"
- [ ] CA-P02-N3c: `GET /instrutores/{id}/credenciamentos?situacao=VENCIDOS` retorna apenas os vencidos
- [ ] CA-P02-N3d: O índice `idx_credenciamento_dt_validade` está criado no banco

---

### Resumo das Mudanças P02 — v2.1

| ID | Tipo | Descrição | Prioridade |
|----|------|-----------|-----------|
| P02-M1 | RN-P02-N1 | Renomear botão "Salvar" → "Enviar" no cadastro externo | 🟠 Alta |
| P02-M2 | RN-P02-N2 | Formulário em abas por tipo de perfil (RT / RU / Proprietário / Instrutor) | 🟠 Alta |
| P02-M3 | RN-P02-N3 | Histórico de credenciamentos vencidos para instrutores | 🟡 Média |

---

*Atualizado em 25/03/2026 — v2.1*  
*Fonte: Análise de Impacto `Impacto_Novos_Requisitos_P01_P14.md` + Documentação Hammer Sprints 02–04*
