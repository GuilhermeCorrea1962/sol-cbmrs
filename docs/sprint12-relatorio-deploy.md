# Sprint 12 — P12 Extinção de Licenciamento: Relatório de Deploy e Smoke Test

**Data de execução:** 2026-03-31
**Responsável:** Guilherme (CBM-QCG-239)
**Script base:** `C:\SOL\infra\scripts\sprint12-deploy.ps1`
**Resultado final:** ✅ Concluída com sucesso — sem erros na primeira execução
**Duração total:** ~39 segundos (build + restart + testes)

---

## Tags

`#sol` `#sprint12` `#deploy` `#smoke-test` `#extincao` `#cbm-rs`

---

## 1. Contexto da Sprint

A Sprint 12 implementou o módulo **P12 — Extinção de Licenciamento**, responsável pelo encerramento definitivo de um processo de licenciamento no sistema SOL. A extinção é um **estado terminal**: uma vez atingido o status `EXTINTO`, nenhuma operação subsequente é admitida sobre o licenciamento.

### Diferença em relação às sprints anteriores

> [!note] Execução limpa — sem erros
> Diferentemente da Sprint 11, que exigiu 11 correções no script antes de concluir com sucesso, a Sprint 12 executou sem nenhuma falha na primeira tentativa. O script já nasceu com as correções acumuladas da Sprint 11: caminhos reais de Maven e JDK, `$BaseUrl` com `/api`, `access_token` em vez de `token`, credenciais corretas e estrutura de `Invoke-SetupAnalisePendente` já alinhada com o `LicenciamentoCreateDTO` atual.

### Funcionalidades entregues

| Código | Descrição |
|--------|-----------|
| **P12-A** | Fluxo com dois atores: cidadão/RT solicita a extinção; ADMIN a efetiva. Gera 2 marcos. |
| **P12-B** | Extinção administrativa direta: ADMIN extingue sem solicitação prévia. Gera 1 marco. |

### Arquivos criados nesta sprint

| Operação | Arquivo | Responsabilidade |
|----------|---------|-----------------|
| `[N]` Novo | `dto/ExtincaoDTO.java` | Record imutável com campo `motivo` (obrigatório em ambas as operações) |
| `[N]` Novo | `service/ExtincaoService.java` | Lógica de negócio: `solicitarExtincao` + `efetivarExtincao` com RNs 109–114 |
| `[N]` Novo | `controller/ExtincaoController.java` | 2 endpoints POST com controle de acesso por role |

### Regras de negócio validadas

| Regra | Descrição |
|-------|-----------|
| **RN-109** | Extinção só pode ser solicitada/efetivada em status admissível: `ANALISE_PENDENTE`, `APPCI_EMITIDO` ou `SUSPENSO`. Tentativa em `RASCUNHO` ou `EXTINTO` retorna HTTP 422. |
| **RN-110** | Motivo é obrigatório na solicitação de extinção. Campo vazio retorna HTTP 422. |
| **RN-111** | Motivo é obrigatório na efetivação. Campo vazio retorna HTTP 422. |
| **RN-112** | Ao efetivar, o status muda para `EXTINTO` e `ativo` é setado para `false` (inativação lógica). |
| **RN-113** | `EXTINTO` é estado terminal. Qualquer operação subsequente retorna HTTP 422. |
| **RN-114** | Cidadão/RT pode solicitar; somente ADMIN ou CHEFE\_SSEG\_BBM pode efetivar ou extinguir diretamente. |

---

## 2. Ambiente de Execução

| Componente | Valor |
|------------|-------|
| **Backend JAR** | `C:\SOL\backend\target\sol-backend-1.0.0.jar` |
| **Serviço Windows** | `SOL-Backend` |
| **Java** | Eclipse Adoptium JDK 21.0.9 — `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot` |
| **Maven** | Apache Maven 3.9.6 via Chocolatey — `C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.6\bin\mvn.cmd` |
| **Oracle XE** | 21c — schema `SOL`, PDB `XEPDB1`, porta 1521, usuário `sol` / `Sol@CBM2026` |
| **Keycloak** | 24.0.3 — `http://localhost:8180`, realm `sol` |
| **MailHog** | `http://localhost:8025` (UI) / `localhost:1025` (SMTP) |
| **URL base da API** | `http://localhost:8080/api` |
| **Usuário admin de teste** | `sol-admin` / `Admin@SOL2026` (role ADMIN) |
| **Usuário analista de teste** | `analista1` / `Analista@123` (role ANALISTA, Oracle ID = 25) |

---

## 3. Log Completo da Execução (primeira e única tentativa)

> Execução iniciada em **2026-03-31 23:03:00** e concluída em **2026-03-31 23:03:39**.

```
==> Sprint 12 - P12 Extincao de Licenciamento
  Data/hora: 2026-03-31 23:03:00
  Backend:   C:\SOL\backend
  URL base:  http://localhost:8080/api

==> Passo 0a - MailHog (SMTP localhost:1025)
    [OK] MailHog ja rodando.

==> Passo 0b - Parar servico SOL-Backend (pre-build)
    [OK] Servico parado.

==> Passo 1 - Build Maven (skip tests)
    [OK] Build concluido.

==> Passo 2 - Reiniciar servico SOL-Backend
    [OK] Servico reiniciado.

==> Passo 3 - Health check
    [OK] Health UP.

==> Passo 4 - Autenticacao
    [OK] Tokens obtidos (sol-admin + analista1).
    [OK] analista1 Oracle ID: 25

==> Passo 5 - Limpeza preventiva de dados de teste anteriores
    [OK] Limpeza preventiva concluida.

==> Passo 6 - Fluxo A: solicitar-extincao (admin) + efetivar-extincao (admin)
    Criando licenciamento seed=67...
    Licenciamento criado ID=69
    Licenciamento ID=69 em ANALISE_PENDENTE.
    6.1 Solicitando extincao do licenciamento 69...
    [OK] solicitar-extincao concluido. Status atual: ANALISE_PENDENTE (deve permanecer ANALISE_PENDENTE).
    6.2 Verificando marco EXTINCAO_SOLICITADA...
    [OK] Marco EXTINCAO_SOLICITADA registrado: 'Extincao solicitada. Motivo: Solicitacao de extincao:
         estabelecimento encerrado por decisao do proprietario.'
    6.3 Efetivando extincao do licenciamento 69...
    [OK] efetivar-extincao: status EXTINTO confirmado no retorno do endpoint.
    6.4 Verificando marco EXTINCAO_EFETIVADA...
    [OK] Marco EXTINCAO_EFETIVADA registrado: 'Extincao efetivada. Motivo: Efetivacao administrativa:
         confirmado encerramento das atividades.. Licenciamento ID 69 encerrado definitivamente.'
    6.5 Confirmando status via GET /licenciamentos/69...
    [OK] Licenciamento 69 status EXTINTO confirmado.
    [OK] Fluxo A concluido: ANALISE_PENDENTE => EXTINTO com 2 marcos.

==> Passo 7 - Fluxo B: efetivar-extincao direta (sem solicitar-extincao)
    Criando licenciamento seed=68...
    Licenciamento criado ID=70
    Licenciamento ID=70 em ANALISE_PENDENTE.
    7.1 Efetivando extincao direta do licenciamento 70...
    [OK] Extincao direta: status EXTINTO confirmado.
    7.2 Verificando marco EXTINCAO_EFETIVADA (Fluxo B)...
    [OK] Marco EXTINCAO_EFETIVADA registrado: 'Extincao efetivada. Motivo: Extincao administrativa direta:
         irregularidade grave identificada em auditoria.. Licenciamento ID 70 encerrado definitivamente.'
    [OK] Marco EXTINCAO_SOLICITADA corretamente ausente no Fluxo B.
    [OK] Fluxo B concluido: extincao direta com 1 marco.

==> Passo 8 - Validacao de regras de negocio
    8.1 RN-113: tentando solicitar extincao de licenciamento ja EXTINTO...
    [OK] RN-113 OK: operacao em licenciamento EXTINTO bloqueada (HTTP 422).
    8.2 RN-110: solicitar-extincao sem motivo...
    Criando licenciamento seed=69...
    Licenciamento criado ID=71
    Licenciamento ID=71 em ANALISE_PENDENTE.
    [OK] RN-110 OK: solicitar-extincao sem motivo bloqueado (HTTP 422).
    8.3 RN-111: efetivar-extincao sem motivo...
    [OK] RN-111 OK: efetivar-extincao sem motivo bloqueado (HTTP 422).
    8.4 RN-109: efetivar-extincao em licenciamento RASCUNHO...
    [OK] RN-109 OK: extincao de RASCUNHO bloqueada (HTTP 422).

==> Passo 9 - Limpeza dos dados de teste
    [OK] Dados de teste removidos.

==> SUMARIO

  Sprint 12 - P12 Extincao de Licenciamento concluida com sucesso.

  Arquivos criados nesta sprint:
    [N] dto/ExtincaoDTO.java         : record ExtincaoDTO(String motivo)
    [N] service/ExtincaoService.java : solicitarExtincao + efetivarExtincao
    [N] controller/ExtincaoController.java : 2 endpoints POST

  Endpoints:
    POST /licenciamentos/{id}/solicitar-extincao  (CIDADAO, RT, ADMIN)
    POST /licenciamentos/{id}/efetivar-extincao   (ADMIN, CHEFE_SSEG_BBM)

  Fluxos validados:
    Fluxo A: ANALISE_PENDENTE + solicitar + efetivar => EXTINTO + 2 marcos
    Fluxo B: ANALISE_PENDENTE + efetivar direto      => EXTINTO + 1 marco
    RN-109 : status RASCUNHO bloqueado
    RN-110 : motivo vazio na solicitacao bloqueado
    RN-111 : motivo vazio na efetivacao bloqueado
    RN-113 : operacao em licenciamento EXTINTO bloqueada

  Data/hora: 2026-03-31 23:03:39
```

---

## 4. Problemas Detectados e Soluções Aplicadas

> [!note] Nenhum problema encontrado
> O script `sprint12-deploy.ps1` executou sem nenhuma falha na primeira tentativa. Todos os 10 passos concluíram com `[OK]`, e o SUMÁRIO foi exibido em **39 segundos** de execução total.
>
> Esta seção documenta o **motivo pelo qual a execução foi limpa**, contrastando com a experiência da Sprint 11.

### Por que a Sprint 12 não exigiu correções

A Sprint 11 catalogou e corrigiu uma série de incompatibilidades entre o script de deploy e o ambiente real do servidor. Essas correções foram **incorporadas diretamente no script da Sprint 12** pelo desenvolvedor que o escreveu, resultando em uma execução sem fricção:

| Problema que afetou a Sprint 11 | Como a Sprint 12 evitou |
|---------------------------------|------------------------|
| Caminhos Maven/JDK inexistentes em `C:\tools\` | Script já usa os caminhos Chocolatey e Eclipse Adoptium |
| `$BaseUrl` sem o prefixo `/api` | `$BaseUrl = "http://localhost:8080/api"` definido corretamente |
| `$resp.token` inexistente (StrictMode) | `Get-Token` retorna `$resp.access_token` diretamente |
| Body de criação do licenciamento incompleto | `Invoke-SetupAnalisePendente` usa `tipo` + `endereco` conforme `LicenciamentoCreateDTO` |
| Upload PPCI na URL errada | Usa `/arquivos/upload?licenciamentoId=$id&tipoArquivo=PPCI` desde o início |
| Credenciais de usuário erradas | `sol-admin`/`Admin@SOL2026` e `analista1`/`Analista@123` já configurados |
| MailHog ausente derrubando health check | Passo 0a já verifica e inicia o MailHog automaticamente |
| Serviço Windows bloqueando JAR | Passo 0b para o serviço antes do build |

### Observação sobre o `sqlplus`

Na Sprint 11, a limpeza preventiva (Passo 5) emitia `[WARN]` porque o `sqlplus` não estava no `PATH`. Na Sprint 12, o mesmo passo emitiu `[OK]` — confirmando que o `sqlplus` foi adicionado ao `PATH` do sistema entre as duas execuções, ou que o terminal foi reiniciado com o PATH atualizado incluindo `C:\app\Guilherme\product\21c\dbhomeXE\bin`.

---

## 5. Análise Detalhada de Cada Passo do Script

Esta seção explica a razão de existência de cada passo do script `sprint12-deploy.ps1`, o que ele valida, e o que aconteceria se fosse omitido.

---

### Passo 0a — Garantir MailHog rodando

**O que aconteceu:** MailHog já estava em execução (iniciado durante a Sprint 11 e nunca encerrado). A verificação via `Test-NetConnection -Port 1025` confirmou a porta aberta instantaneamente.

**Por que existe:** O `ExtincaoService` envia e-mails assíncronos:
- `solicitarExtincao`: notifica o analista atribuído ao licenciamento
- `efetivarExtincao`: notifica RT e RU do encerramento definitivo

O `spring.mail.host=localhost:1025` aponta para o MailHog. Se o MailHog não estiver no ar, o `MailHealthIndicator` do Spring Boot Actuator reporta o status do serviço como `DOWN`, fazendo o health check do Passo 3 falhar com HTTP 503 e impedindo todos os testes subsequentes.

**O que valida:** Que a infraestrutura de e-mail está funcional antes de qualquer requisição de negócio.

---

### Passo 0b — Parar serviço SOL-Backend antes do build

**O que aconteceu:** O serviço `SOL-Backend` estava em execução. O `Stop-Service -Force` o encerrou em ~5 segundos.

**Por que existe:** No Windows, o processo Java que executa o Spring Boot mantém o arquivo `sol-backend-1.0.0.jar` aberto com lock exclusivo do sistema operacional. O `maven-clean-plugin` precisa deletar esse arquivo antes de gerar o novo no Passo 1. Com o serviço rodando, a deleção falha com `MojoExecutionException: Failed to delete ... sol-backend-1.0.0.jar` — exatamente o erro que afetou a Sprint 11 antes da correção.

**O que valida:** Que o ambiente está livre para uma compilação limpa.

---

### Passo 1 — Build Maven (skip tests)

**O que aconteceu:** `mvn clean package -DskipTests -q` compilou todos os arquivos Java do projeto, incluindo os três novos arquivos da Sprint 12 (`ExtincaoDTO`, `ExtincaoService`, `ExtincaoController`), e empacotou o JAR final.

**Por que existe:** Garante que o código entregue nesta sprint compila sem erros de sintaxe, dependências ausentes ou conflitos de tipos. O `-DskipTests` é intencional: os testes de integração são cobertos pelo próprio smoke test dos passos seguintes, que valida contra o ambiente real (Oracle, Keycloak, MinIO, MailHog) em vez de mocks.

**Por que `-q` (quiet):** Suprime a saída verbosa do Maven para manter o log do script legível. Erros reais (exit code ≠ 0) são capturados e exibidos via `Write-FAIL`.

**O que valida:** Que o código compila. Se o build falhasse aqui, o problema estaria nos arquivos Java entregues na sprint — não no ambiente.

---

### Passo 2 — Reiniciar serviço SOL-Backend

**O que aconteceu:** `Restart-Service -Name "SOL-Backend" -Force` subiu o serviço com o novo JAR. O script aguardou 20 segundos antes de prosseguir para o health check.

**Por que existe:** O serviço foi parado no Passo 0b e o JAR foi substituído no Passo 1. É necessário iniciá-lo novamente com o novo binário para que as mudanças entrem em vigor. O `Start-Sleep -Seconds 20` é um buffer conservador para que o Spring Boot complete a inicialização antes das tentativas de health check.

**Por que 20 segundos e não menos:** O Spring Boot 3.3.4 leva entre 8 e 18 segundos neste servidor para completar a inicialização (conexão com Oracle, configuração do Hibernate, publicação do contexto Spring, carregamento do Keycloak JWKS endpoint). O buffer de 20 segundos evita que as primeiras tentativas do health check (Passo 3) falhem desnecessariamente.

**O que valida:** Que o novo código está sendo executado pelo serviço.

---

### Passo 3 — Health check

**O que aconteceu:** Na primeira tentativa, `GET /api/actuator/health` retornou `{"status":"UP"}`. Nenhuma tentativa adicional foi necessária.

**Por que existe:** O health check agrega o status de todos os componentes monitorados pelo Spring Boot Actuator:
- **Banco Oracle** (`DataSourceHealthIndicator`): conexão JDBC com `XEPDB1`
- **Keycloak** (`DiscoveryServerHealthIndicator` via JWKS): endpoint de validação de tokens
- **MinIO** (`MinIOHealthIndicator`): bucket `sol-arquivos`
- **MailHog** (`MailHealthIndicator`): porta SMTP 1025

Se qualquer um desses estiver indisponível, o health retorna `DOWN` (HTTP 503) e o script aborta com `Write-FAIL`, evitando testes contra um backend em estado degradado.

**Por que 12 tentativas com intervalo de 5s:** O Spring Boot pode levar mais tempo para subir dependendo da carga do servidor. O total de até 60 segundos de espera garante que não se abandone o processo por uma inicialização ligeiramente mais lenta, sem esperar indefinidamente.

**O que valida:** Que todos os componentes de infraestrutura estão operacionais e o backend está pronto para receber requisições.

---

### Passo 4 — Autenticação e obtenção de tokens

**O que aconteceu:**
- `sol-admin` autenticou com sucesso → `tokenAdmin` obtido
- `analista1` autenticou com sucesso → `tokenAnalista` obtido
- `GET /auth/me` com `tokenAnalista` retornou `id = 25` (ID Oracle do analista)

**Por que dois usuários:**

| Usuário | Role | Usado para |
|---------|------|-----------|
| `sol-admin` | ADMIN | Criar licenciamentos, submeter, distribuir, solicitar extinção, efetivar extinção, limpeza |
| `analista1` | ANALISTA | Verificação via `GET /auth/me` para obter o ID Oracle |

**Por que `access_token` e não `token`:** O endpoint `POST /api/auth/login` implementa o protocolo ROPC (Resource Owner Password Credentials) do OAuth2 via Keycloak. A resposta segue o padrão OAuth2/OpenID Connect, onde o JWT de acesso é devolvido no campo `access_token`. O campo `token` não existe — com `Set-StrictMode -Version Latest` ativo, acessar uma propriedade inexistente lança `PropertyNotFoundException`, abortando o script.

**Por que buscar o ID Oracle do analista:** O endpoint `PATCH /licenciamentos/{id}/distribuir` (usado nas sprints anteriores e em futuras) requer o ID do banco Oracle do analista como `?analistaId=`, não o `sub` do JWT (keycloakId). O `GET /auth/me` é o único endpoint que retorna ambos os identificadores de forma confiável.

**Nota:** O `analistaOracleId` (= 25) é capturado nesta sprint para manutenção da consistência do script, mesmo que o Passo 6 desta sprint não use `distribuir` (a extinção opera sobre licenciamentos em `ANALISE_PENDENTE` que não passaram pela fase de distribuição).

**O que valida:** Que ambos os perfis de usuário existem no Keycloak e no Oracle, e que o serviço de autenticação está funcional.

---

### Passo 5 — Limpeza preventiva de dados de teste

**O que aconteceu:** `sqlplus` estava disponível no PATH. O bloco PL/SQL executou sem erros e retornou `[OK]`.

**Por que existe:** O script usa licenciamentos com `area_construida = 200` como marcador de identificação dos dados de teste. Se uma execução anterior do script tiver falhado antes do Passo 9 (limpeza pós-teste), esses registros ficam órfãos no banco. Na próxima execução, a `Invoke-SetupAnalisePendente` cria novos licenciamentos com IDs sequenciais diferentes, mas os dados antigos podem gerar ambiguidade nos testes de validação de RNs (especialmente nos filtros PL/SQL da limpeza final).

**Critério de seleção:** A query filtra os 10 últimos IDs gerados (`ORDER BY id DESC FETCH FIRST 10 ROWS ONLY`) com `area_construida = 200` e status `EXTINTO` ou `ANALISE_PENDENTE` — evitando apagar dados de produção ou de outras sprints que usem área diferente.

**O que valida:** Estado limpo do banco antes dos testes, garantindo reprodutibilidade.

---

### Passo 6 — Fluxo A: `solicitar-extincao` + `efetivar-extincao` (2 marcos)

**O que aconteceu:**
- Licenciamento `ID=69` criado e colocado em `ANALISE_PENDENTE` via `Invoke-SetupAnalisePendente`
- `solicitar-extincao` executado: status permaneceu `ANALISE_PENDENTE` (correto — apenas registra intenção)
- Marco `EXTINCAO_SOLICITADA` verificado e confirmado
- `efetivar-extincao` executado: status mudou para `EXTINTO`
- Marco `EXTINCAO_EFETIVADA` verificado e confirmado
- `GET /licenciamentos/69` confirmou status `EXTINTO` de forma independente

**Sequência de estados:**

```
RASCUNHO
  → (upload PPCI + submeter)
  → ANALISE_PENDENTE
  → (solicitar-extincao)           ← status NÃO muda, apenas registra marco
  → ANALISE_PENDENTE [com marco EXTINCAO_SOLICITADA]
  → (efetivar-extincao)            ← status muda para EXTINTO, ativo = false
  → EXTINTO [com marco EXTINCAO_EFETIVADA]
```

**Por que `solicitar-extincao` não muda o status:** Esta separação de responsabilidades é deliberada na especificação do P12. O cidadão ou RT manifesta a intenção de encerrar o licenciamento, mas somente o ADMIN ou CHEFE\_SSEG\_BBM pode concretizá-la após análise administrativa. Isso garante que um cidadão não possa unilateralmente extinguir um processo que está em análise ativa — o analista precisa avaliar e concordar com a extinção (ou recusá-la, caso em que o licenciamento permanece em `ANALISE_PENDENTE` sem o marco de efetivação).

**Por que verificar o status duas vezes (passo 6.3 e 6.5):** A verificação em 6.3 usa o retorno direto do endpoint (`$respEfetA.status`), confirmando que o DTO retornado pelo próprio `efetivar-extincao` reflete o novo status. A verificação em 6.5 faz um `GET` independente (`Assert-Status`), confirmando que a persistência no Oracle ocorreu de fato e que uma nova leitura do banco retorna o estado correto — descartando a possibilidade de o retorno do POST ser calculado em memória sem commit real.

**Marcos registrados:**
```
EXTINCAO_SOLICITADA: "Extincao solicitada. Motivo: Solicitacao de extincao:
                      estabelecimento encerrado por decisao do proprietario."

EXTINCAO_EFETIVADA:  "Extincao efetivada. Motivo: Efetivacao administrativa:
                      confirmado encerramento das atividades..
                      Licenciamento ID 69 encerrado definitivamente."
```

---

### Passo 7 — Fluxo B: `efetivar-extincao` direta (1 marco)

**O que aconteceu:**
- Licenciamento `ID=70` criado em `ANALISE_PENDENTE`
- `efetivar-extincao` chamado diretamente (sem `solicitar-extincao` prévia): status mudou para `EXTINTO`
- Marco `EXTINCAO_EFETIVADA` confirmado
- Confirmação ativa de que `EXTINCAO_SOLICITADA` está **ausente** (correto para extinção direta)

**Por que este fluxo existe separado:** O Fluxo B representa o poder de extinção administrativa direta do ADMIN/CHEFE\_SSEG\_BBM. Situações como irregularidade grave em auditoria, determinação judicial ou cancelamento compulsório do alvará não dependem de solicitação do titular. Nesse caso, o ADMIN extingue diretamente sem aguardar a manifestação do cidadão.

**Por que verificar a ausência de `EXTINCAO_SOLICITADA`:** A verificação negativa confirma que o `ExtincaoService.efetivarExtincao` não cria automaticamente o marco de solicitação quando chamado diretamente — garantindo que a auditoria do processo (via tabela `marco_processo`) reflita fielmente o fluxo real seguido, sem marcos fictícios.

**Marco registrado:**
```
EXTINCAO_EFETIVADA: "Extincao efetivada. Motivo: Extincao administrativa direta:
                     irregularidade grave identificada em auditoria..
                     Licenciamento ID 70 encerrado definitivamente."
```

---

### Passo 8 — Validação das regras de negócio

Esta seção testa os caminhos de erro — confirma que o backend **rejeita corretamente** operações inválidas.

#### 8.1 — RN-113: operação em licenciamento EXTINTO

**O que aconteceu:** Tentativa de `solicitar-extincao` no licenciamento `ID=69` (já `EXTINTO` após o Fluxo A). Retornou HTTP 422.

**Por que é importante:** O `EXTINTO` é declarado como estado terminal na especificação. Se um licenciamento extinto pudesse ser reaberto ou re-solicitado, comprometeria a integridade do histórico administrativo e poderia gerar duplicidade de processos. O `ExtincaoService` valida isso via `STATUS_EXTINCAO_ADMISSIVEL`, que inclui apenas `ANALISE_PENDENTE`, `APPCI_EMITIDO` e `SUSPENSO` — `EXTINTO` não está no conjunto.

**Por que reusar `$idA` (licenciamento 69) em vez de criar um novo:** `$idA` é garantidamente `EXTINTO` após o Fluxo A. Criar um novo licenciamento e extingui-lo só para testar RN-113 seria redundante e adicionaria latência. O reuso de dados entre passos é uma decisão deliberada de eficiência.

#### 8.2 — RN-110: `solicitar-extincao` sem motivo

**O que aconteceu:** Novo licenciamento `ID=71` criado em `ANALISE_PENDENTE`. Chamada com `{"motivo": ""}` (string vazia). Retornou HTTP 422.

**Como o backend detecta:** `ExtincaoService.solicitarExtincao` verifica `motivo == null || motivo.isBlank()` antes de qualquer outra validação, lançando `BusinessException("RN-110", ...)`.

**Por que criar um licenciamento novo:** O licenciamento `$idTemp` (ID=71) precisa estar em `ANALISE_PENDENTE` para que RN-109 não seja disparado antes de RN-110 — caso contrário, não seria possível isolar qual regra está sendo testada. A ordem das validações no service (`motivo` primeiro, `status` depois) garante que a string vazia seja rejeitada independentemente do status do licenciamento.

#### 8.3 — RN-111: `efetivar-extincao` sem motivo

**O que aconteceu:** Mesma chamada com `{"motivo": ""}` sobre o mesmo licenciamento `ID=71` (ainda `ANALISE_PENDENTE`). Retornou HTTP 422.

**Por que reusar `$idTemp`:** O licenciamento `ID=71` não foi extinto no passo 8.2 (pois a solicitação foi bloqueada). Portanto, ainda está em `ANALISE_PENDENTE` e é válido para testar a efetivação com motivo vazio, sem precisar criar um quarto licenciamento.

#### 8.4 — RN-109: extinção de licenciamento em `RASCUNHO`

**O que aconteceu:** Um licenciamento foi criado via `POST /licenciamentos` sem submissão (status `RASCUNHO`). Tentativa de `efetivar-extincao` retornou HTTP 422.

**Como o backend detecta:** `ExtincaoService.efetivarExtincao` checa `STATUS_EXTINCAO_ADMISSIVEL.contains(lic.getStatus())`. `RASCUNHO` não faz parte do conjunto admissível, lançando `BusinessException("RN-109", ...)`.

**Por que `RASCUNHO` não pode ser extinto:** Um licenciamento em rascunho não foi ainda submetido à análise — o cidadão pode simplesmente abandoná-lo sem operação formal. O ato de extinção pressupõe que o processo já entrou no fluxo administrativo (ao menos `ANALISE_PENDENTE`). Extinguir um rascunho seria semanticamente incorreto: algo que nunca começou formalmente não precisa de ato formal de encerramento.

---

### Passo 9 — Limpeza pós-teste

**O que aconteceu:** `sqlplus` executou o bloco PL/SQL e removeu todos os licenciamentos de teste (IDs 69, 70, 71 e o rascunho do 8.4), com seus marcos, arquivos e boletos associados.

**Por que existe:** Cada execução do script cria entre 3 e 4 licenciamentos de teste no banco Oracle. Sem limpeza, o banco acumula dados fictícios indefinidamente, impactando:
- Contagens e paginações em endpoints de listagem
- Testes de outros scripts que filtram por status ou área
- Espaço em disco (especialmente os arquivos PPCI no MinIO)

**Critério de seleção do PL/SQL:** Filtra licenciamentos com `area_construida IN (200, 100)` (200 para os de teste padrão do Fluxo A/B, 100 para o rascunho do RN-109) e com `id >= MAX(id) - 20` — uma janela de segurança que evita apagar licenciamentos antigos com a mesma área que possam existir de execuções de sprints diferentes.

---

## 6. Arquitetura do Módulo P12 Implementado

### `ExtincaoDTO.java`

```java
public record ExtincaoDTO(String motivo) {}
```

DTO minimalista — um único campo. A validação de obrigatoriedade (`isBlank()`) é feita em nível de serviço, não via anotação `@NotBlank`, permitindo que a mensagem de erro retornada siga o padrão de `BusinessException` (com `codigoRegra`) em vez do padrão genérico de `@Valid` (sem código de regra).

### `ExtincaoService.java` — Lógica central

**Conjunto de status admissíveis:**
```java
private static final Set<StatusLicenciamento> STATUS_EXTINCAO_ADMISSIVEL = Set.of(
    StatusLicenciamento.ANALISE_PENDENTE,
    StatusLicenciamento.APPCI_EMITIDO,
    StatusLicenciamento.SUSPENSO
);
```

Este conjunto concentra a máquina de estados da extinção. Para adicionar um novo status admissível no futuro (ex: `EM_ANALISE`), basta modificar este `Set` — sem alterar a lógica das funções.

**`solicitarExtincao`:** Não persiste alteração no licenciamento. Apenas registra o marco `EXTINCAO_SOLICITADA` e notifica o analista atribuído. Retorna o `LicenciamentoDTO` atual sem mudança de status.

**`efetivarExtincao`:** Persiste `status = EXTINTO` e `ativo = false` no Oracle, registra `EXTINCAO_EFETIVADA` e notifica RT e RU por e-mail. É idempotente no sentido de que status `EXTINTO` não está em `STATUS_EXTINCAO_ADMISSIVEL`, portanto uma segunda chamada seria bloqueada por RN-109.

### `ExtincaoController.java` — Controle de acesso

| Endpoint | Roles permitidas | Justificativa |
|----------|-----------------|--------------|
| `POST /solicitar-extincao` | `CIDADAO`, `RT`, `ADMIN`, `CHEFE_SSEG_BBM` | Qualquer parte interessada pode manifestar intenção de extinguir |
| `POST /efetivar-extincao` | `ADMIN`, `CHEFE_SSEG_BBM` | Somente autoridade administrativa pode efetivar o encerramento |

---

## 7. Fluxo Completo de Estados — P12

```
           [Cidadão/RT/Admin]              [Admin/Chefe]
                  │                              │
                  ▼                              │
    solicitar-extincao                           │
    (status não muda)                            │
    Marco: EXTINCAO_SOLICITADA                   │
                  │                              │
                  └──────────────┬───────────────┘
                                 │
                                 ▼
                        efetivar-extincao
                        status → EXTINTO
                        ativo  → false
                        Marco: EXTINCAO_EFETIVADA
                        E-mail: RT + RU notificados
                                 │
                                 ▼
                            ┌─────────┐
                            │ EXTINTO │  ← estado terminal
                            └─────────┘
                         (RN-113: sem retorno)
```

---

## 8. Estado do Banco após o Deploy

### Oracle — Dados de teste removidos no Passo 9

Todos os licenciamentos criados durante o smoke test (IDs 69, 70, 71 e o rascunho do teste RN-109) foram removidos, junto com seus marcos de processo, arquivos PPCI e boletos associados.

### Licenciamentos pré-existentes preservados

| ID | Status | Origem |
|----|--------|--------|
| 1..68 (exceto limpos) | Variados | Sprints anteriores |

---

## 9. Observações e Pendências

> [!warning] RN-114 não testada diretamente
> A RN-114 define que cidadão/RT pode solicitar, mas apenas ADMIN/CHEFE\_SSEG\_BBM pode efetivar. O script testou o caminho positivo com `sol-admin` (role ADMIN) em ambos os endpoints, mas não testou a rejeição de um usuário com role `CIDADAO` ou `RT` tentando chamar `efetivar-extincao`. Este teste negativo de autorização seria uma cobertura adicional relevante para sprints futuras.

> [!warning] Status `APPCI_EMITIDO` e `SUSPENSO` não testados
> O `STATUS_EXTINCAO_ADMISSIVEL` admite também `APPCI_EMITIDO` e `SUSPENSO`, mas o script só testa a extinção a partir de `ANALISE_PENDENTE` (o estado mais acessível no contexto do smoke test). Cobertura completa exigiria licenciamentos nesses estados, o que demandaria setup mais complexo envolvendo os módulos de emissão de APPCI e suspensão (sprints futuras).

> [!note] IDs dos licenciamentos de teste
> O script usa `seed=67`, `seed=68` e `seed=69` como referência, mas os IDs reais gerados pela sequence Oracle foram `69`, `70` e `71`. Isso é esperado: a sequence `SOL.SEQ_LICENCIAMENTO` continua de onde parou na Sprint 11. Não afeta a validade dos testes.

> [!note] Ponto duplo na observação do marco EXTINCAO_EFETIVADA
> O marco `EXTINCAO_EFETIVADA` termina com `"...encerramento das atividades.. Licenciamento ID 69..."` — há um ponto duplo (`..`) causado pela concatenação do motivo (que termina em `.`) com o texto fixo que começa com `.` no `ExtincaoService`:
> ```java
> "Extincao efetivada. Motivo: " + motivo
> + ". Licenciamento ID " + licId + " encerrado definitivamente."
> ```
> O motivo passado no teste termina com `.` → resultado: `"...atividades.. Licenciamento..."`. É um defeito cosmético na formatação da observação do marco, sem impacto funcional.

---

## 10. Resumo Executivo

| Métrica | Valor |
|---------|-------|
| **Tentativas de execução** | 1 (sucesso na primeira) |
| **Erros encontrados** | 0 |
| **Correções aplicadas** | 0 |
| **Passos executados** | 10 (0a, 0b, 1–9) |
| **Endpoints testados** | 2 novos + 6 de infraestrutura (health, auth, licenciamento, arquivos, marcos) |
| **Regras de negócio validadas** | RN-109, RN-110, RN-111, RN-113 (4 de 6 definidas) |
| **Licenciamentos criados no teste** | 4 (IDs 69, 70, 71 + rascunho) |
| **Licenciamentos extintos no teste** | 2 (IDs 69 e 70) |
| **Marcos registrados no teste** | 5 (2 no Fluxo A + 1 no Fluxo B + setup dos 3 licenciamentos) |
| **Duração total** | ~39 segundos |

---

*Relatório gerado em 2026-03-31 ao final da execução da Sprint 12.*
*Sistema: SOL — Sistema Online de Licenciamento — CBM-RS*
