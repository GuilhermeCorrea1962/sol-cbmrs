# Instrucoes de Execucao — Sprint 14: P14 Renovacao de Licenciamento (APPCI)

**Sistema:** SOL — Sistema Online de Licenciamento — CBM-RS
**Sprint:** 14 — Processo P14 (Renovacao de Licenciamento / APPCI)
**Script:** `C:\SOL\infra\scripts\sprint14-deploy.ps1`
**Data de producao:** 2026-04-01
**Regras de Negocio:** RN-141 a RN-160

---

## O que foi implementado nesta Sprint

O processo P14 e o mais complexo do sistema SOL em numero de fases e atores. Ele trata da
**renovacao do Alvara de Prevencao e Protecao Contra Incendio (APPCI)** para estabelecimentos
com alvara vigente ou recentemente vencido. Ao contrario do P03 (primeira submissao), o P14
nao inclui analise tecnica de projeto — o PPCI ja foi aprovado em ciclo anterior — e percorre
um fluxo especifico de seis fases.

### Arquivos modificados

| Arquivo | Modificacao |
|---|---|
| `entity/enums/StatusLicenciamento.java` | +4 status: `AGUARDANDO_ACEITE_RENOVACAO`, `AGUARDANDO_PAGAMENTO_RENOVACAO`, `AGUARDANDO_DISTRIBUICAO_RENOV`, `EM_VISTORIA_RENOVACAO` |
| `entity/enums/TipoMarco.java` | Secao P14 substituida: 2 stubs removidos, 22 marcos reais adicionados |
| `entity/Licenciamento.java` | +campo `isentoTaxaRenovacao` (CHAR 'S'/'N', mapeado via `SimNaoBooleanConverter`) |
| `repository/LicenciamentoRepository.java` | +2 queries JPQL: `findElegiveisParaRenovacao` e `findRenovacoesEmAndamento` |

### Arquivos criados

| Arquivo | Conteudo |
|---|---|
| `dto/RenovacaoRequestDTO.java` | Record reutilizado em todos os endpoints de escrita do P14 |
| `dto/AnexoDRenovacaoDTO.java` | Response do Anexo D (texto, aceite, dtValidadeAppci) |
| `service/RenovacaoService.java` | Servico com 14 metodos cobrindo as 6 fases + helpers |
| `controller/RenovacaoController.java` | 14 endpoints REST do processo P14 |

---

## Maquina de Estados implementada

```
[APPCI_EMITIDO] ou [ALVARA_VENCIDO]
        |
        | POST /renovacao/iniciar  (RN-141, RN-143)
        v
[AGUARDANDO_ACEITE_RENOVACAO]
        |
        |-- PUT  /renovacao/aceitar-anexo-d  (RN-144)
        |-- DELETE /renovacao/aceitar-anexo-d (remover aceite)
        |
        |-- POST /renovacao/confirmar  (RN-145)  -----> [AGUARDANDO_PAGAMENTO_RENOVACAO]
        |-- POST /renovacao/recusar   (RN-145)  -----> [APPCI_EMITIDO] ou [ALVARA_VENCIDO]
        v
[AGUARDANDO_PAGAMENTO_RENOVACAO]
        |
        |-- POST /renovacao/solicitar-isencao  (RN-147)  -- apenas marco
        |
        |-- POST /renovacao/analisar-isencao {deferida:true}  --> [AGUARDANDO_DISTRIBUICAO_RENOV]
        |-- POST /renovacao/analisar-isencao {deferida:false} --> permanece (RN-148)
        |-- POST /renovacao/confirmar-pagamento (admin, testes) -> [AGUARDANDO_DISTRIBUICAO_RENOV]
        v
[AGUARDANDO_DISTRIBUICAO_RENOV]
        |
        | POST /renovacao/distribuir {inspetorId:N}  (RN-150)
        v
[EM_VISTORIA_RENOVACAO]
        |
        | POST /renovacao/registrar-vistoria {vistoriaAprovada:true/false}  (RN-151)
        | (status nao transita aqui -- aguarda homologacao)
        |
        | POST /renovacao/homologar-vistoria {deferida:true}   --> [APPCI_EMITIDO] (nova data)
        | POST /renovacao/homologar-vistoria {deferida:false}  --> [CIV_EMITIDO]
        v
[APPCI_EMITIDO]                         [CIV_EMITIDO]
        |                                      |
        | POST /renovacao/ciencia-appci        | POST /renovacao/ciencia-civ (RN-153)
        | (RN-152, idempotente)                | POST /renovacao/retomar --> loop para
        v                                      |     AGUARDANDO_ACEITE_RENOVACAO
  [RENOVACAO CONCLUIDA]                        v
                                        [AGUARDANDO_ACEITE_RENOVACAO] (2o ciclo)
```

---

## Instrucao para o Claude Code no servidor

```
Leia o arquivo C:\SOL\infra\scripts\sprint14-deploy.ps1 e execute-o no servidor.
Se encontrar erros durante a execucao, corrija-os diretamente nos arquivos necessarios
e reexecute ate que o script conclua com sucesso exibindo o SUMARIO final.
```

---

## Detalhamento de cada etapa do script

### Passo 0a — Verificar MailHog

**O que faz:** Testa a disponibilidade do MailHog na porta 8025.

**Por que e necessario:** O `RenovacaoService` envia notificacoes de e-mail a cada transicao
de estado via `EmailService.notificarAsync()`. Se o SMTP nao estiver disponivel, o servico
loga WARN e continua (nao propaga excecao). O MailHog captura esses e-mails localmente
para inspecao sem entrega real.

**O que e esperado:** Resposta JSON com `total >= 0`. Se indisponivel, o passo e ignorado
e o fluxo continua normalmente (comportamento tolerante a falha).

---

### Passo 0b — Parar o servico SOL

**O que faz:** Para o servico Windows `sol-backend` antes do build.

**Por que e necessario:** O JAR em execucao mantem o arquivo bloqueado no Windows. O
Maven nao consegue sobrescrever o `.jar` se o processo esta ativo.

**O que e esperado:** Servico parado sem erro. Se nao existir como servico Windows, a
mensagem INFO informa isso e o script continua.

---

### Passo 1 — Build Maven

**O que faz:** Executa `mvn clean package -DskipTests` no diretorio `C:\SOL\backend`.

**Por que e necessario:** Compila as alteracoes da Sprint 14:
- Novos valores nos enums `StatusLicenciamento` e `TipoMarco`
- Novo campo `isentoTaxaRenovacao` em `Licenciamento.java`
- Novas queries em `LicenciamentoRepository`
- Novos DTOs `RenovacaoRequestDTO` e `AnexoDRenovacaoDTO`
- Novo `RenovacaoService` (14 metodos, 6 fases)
- Novo `RenovacaoController` (14 endpoints REST)

**O que e esperado:** `BUILD SUCCESS` sem erros de compilacao. Se falhar, o script aborta
com `exit 1` — nao adianta continuar sem compilar.

---

### Passo 2 — Iniciar o servico

**O que faz:** Inicia o servico Windows `sol-backend` ou executa o JAR diretamente.

**Por que e necessario:** O novo JAR compilado precisa ser iniciado para que o
Spring Boot aplique as mudancas via `ddl-auto: update`.

**O que e esperado:** Processo iniciado. O health check do Passo 3 confirma quando
o servico esta pronto.

---

### Passo 3 — Health check

**O que faz:** Aguarda ate 60 segundos para o Spring Boot inicializar, testando
`GET /api/actuator/health` a cada 3 segundos (20 tentativas).

**Por que 60 segundos?** O Hibernate `ddl-auto: update` executa DDL no startup:
- Adiciona coluna `ISENTO_TAXA_RENOVACAO CHAR(1)` na tabela `SOL.LICENCIAMENTO`
- Novos valores de enum sao armazenados como VARCHAR2 — nenhuma alteracao de coluna
  necessaria (retrocompativel)

Em Oracle XE com conexao local, esse DDL leva tipicamente 3-10 segundos.

**O que e esperado:** `{"status":"UP"}`. Se nao ficar disponivel em 60s, o script
aborta — indica problema na inicializacao (ver log em `C:\Temp\sol-sprint14-err.log`).

---

### Passo 4 — Autenticacao

**O que faz:** Obtem token JWT para o usuario `sol-admin` via Keycloak
(`http://localhost:8180/realms/sol`). O token e usado em todos os requests subsequentes.

**Por que e necessario:** Todos os endpoints de renovacao exigem `Bearer {token}`. O
`RenovacaoService` extrai o Keycloak sub do JWT para identificar o usuario e validar
se e RT ou RU do licenciamento (RN-143).

**O que e esperado:** Token JWT retornado com sucesso.

---

### Passo 5 — Setup de dados de teste

**O que faz:**
1. Cria um licenciamento RASCUNHO via `POST /licenciamentos` com o usuario sol-admin
2. Via sqlplus: promove para `STATUS='APPCI_EMITIDO'` com `DT_VALIDADE_APPCI = SYSDATE+365`
3. Via sqlplus: obtem o `ID_RESPONSAVEL_TECNICO` do licenciamento (usado como inspetor)

**Por que via sqlplus?** O pipeline completo P03→P04→P07→P08 levaria dezenas de passos
para chegar a `APPCI_EMITIDO`. O UPDATE direto bypassa o pipeline e cria o estado
de entrada do P14 diretamente, como autorizado para testes de integracao.

**Por que `SYSDATE+365`?** A data futura garante que `dtValidadeAppci >= hoje`, de modo
que ao testar a recusa da renovacao (Passo 16), o rollback correto e para `APPCI_EMITIDO`
(alvara ainda vigente), nao para `ALVARA_VENCIDO`. Isso testa o branch correto do RN-145.

**O que e esperado:** Licenciamento com ID retornado; sqlplus confirma 1 linha atualizada;
`inspetorId` extraido com sucesso (fallback para `1` se nao parsear).

---

### Passo 6 — Iniciar renovacao

**O que faz:** `POST /licenciamentos/{id}/renovacao/iniciar`

**Validacoes executadas pelo servico:**
- RN-141: status deve ser `APPCI_EMITIDO` ou `ALVARA_VENCIDO`
- RN-143: usuario autenticado deve ser RT ou RU do licenciamento

**Transicao:** `APPCI_EMITIDO` → `AGUARDANDO_ACEITE_RENOVACAO`
**Marco registrado:** `INICIO_RENOVACAO`
**E-mail enviado:** RT e RU notificados (via MailHog em testes)

**O que e esperado:** Response com `status: "AGUARDANDO_ACEITE_RENOVACAO"`.

---

### Passo 7 — Aceitar Anexo D

**O que faz:** `PUT /licenciamentos/{id}/renovacao/aceitar-anexo-d`

**O que e o Anexo D?** E o termo de renovacao que o cidadao/RT deve ler e aceitar
antes de confirmar o processo. Contem a declaracao de que as condicoes da edificacao
permanecem em conformidade com o PPCI aprovado anteriormente. RN-144.

**Marco registrado:** `ACEITE_ANEXOD_RENOVACAO`
**Idempotente:** Um segundo aceite nao duplica o marco.

**Resposta esperada:** `AnexoDRenovacaoDTO` com `aceiteRegistrado: true`.

---

### Passo 8 — Confirmar renovacao

**O que faz:** `POST /licenciamentos/{id}/renovacao/confirmar`

**Pre-requisito verificado:** Marco `ACEITE_ANEXOD_RENOVACAO` deve existir. Se o cidadao
tentar confirmar sem aceitar o Anexo D, recebe HTTP 400 com mensagem `RN-144`.

**Transicao:** `AGUARDANDO_ACEITE_RENOVACAO` → `AGUARDANDO_PAGAMENTO_RENOVACAO`

**Por que sempre vai para AGUARDANDO_PAGAMENTO_RENOVACAO?** A escolha entre isenção
e pagamento e feita na Fase 3 — o sistema nao sabe ainda se o cidadao ira solicitar
isenção ou pagar diretamente. O gateway `GW_IsencaoOuPagamento` do BPMN P14
e implementado como dois endpoints distintos na Fase 3.

**O que e esperado:** `status: "AGUARDANDO_PAGAMENTO_RENOVACAO"`.

---

### Passo 9 — Solicitar isencao

**O que faz:** `POST /licenciamentos/{id}/renovacao/solicitar-isencao`

**Por que existe?** Em P14, a taxa de vistoria de renovacao pode ser isenta se o
estabelecimento atender criterios previstos na RTCBMRS 01/2024. O cidadao solicita
a isencao e o CBMRS analisa. E distinta da isencao do primeiro licenciamento
(`IND_SOLICITACAO_ISENCAO`), por isso existe o campo separado
`IND_SOLICITACAO_ISENCAO_RENOVACAO` (RN-147).

**Marco registrado:** `SOLICITACAO_ISENCAO_RENOVACAO`
**Status nao transita:** o licenciamento permanece em `AGUARDANDO_PAGAMENTO_RENOVACAO`
ate a analise do admin (Passo 10).

**O que e esperado:** Response com `status: "AGUARDANDO_PAGAMENTO_RENOVACAO"` e marco
registrado.

---

### Passo 10 — Deferir isencao

**O que faz:** `POST /licenciamentos/{id}/renovacao/analisar-isencao` com `{"deferida": true}`

**Perfil exigido:** `ADMIN` ou `CHEFE_SSEG_BBM`

**RN-148:**
- Deferida: `isentoTaxaRenovacao = true`; marco `ANALISE_ISENCAO_RENOV_APROVADO`;
  status → `AGUARDANDO_DISTRIBUICAO_RENOV` (pula pagamento)
- Indeferida: `isentoTaxaRenovacao = false`; marco `ANALISE_ISENCAO_RENOV_REPROVADO`;
  status permanece `AGUARDANDO_PAGAMENTO_RENOVACAO` (cidadao deve pagar boleto)

O Passo 10 testa o branch de deferimento. O endpoint `confirmar-pagamento` (nao testado
aqui) testa o branch de pagamento para homologacao.

**O que e esperado:** `status: "AGUARDANDO_DISTRIBUICAO_RENOV"`.

---

### Passo 11 — Distribuir vistoria

**O que faz:** `POST /licenciamentos/{id}/renovacao/distribuir` com `{"inspetorId": N}`

**Perfil exigido:** `ADMIN` ou `CHEFE_SSEG_BBM`

**O que faz internamente (RN-150):**
1. Valida status `AGUARDANDO_DISTRIBUICAO_RENOV`
2. Busca o Usuario pelo `inspetorId`
3. Define `licenciamento.inspetor = usuario`
4. Transita status → `EM_VISTORIA_RENOVACAO`
5. Registra marco `DISTRIBUICAO_VISTORIA_RENOV`

**Por que o inspetor e o proprio RT nos testes?** Em producao, o inspetor e um
Usuario com perfil `INSPETOR` distinto do RT. Nos testes, usamos o ID do RT
(sol-admin) como inspetor para evitar a necessidade de criar um usuario adicional.
O servico nao valida o perfil do inspetor — apenas que o usuario existe no banco.

**O que e esperado:** `status: "EM_VISTORIA_RENOVACAO"`.

---

### Passo 12 — Registrar vistoria aprovada

**O que faz:** `POST /licenciamentos/{id}/renovacao/registrar-vistoria` com
`{"vistoriaAprovada": true}`

**Perfil exigido:** `INSPETOR`, `ADMIN` ou `CHEFE_SSEG_BBM`

**RN-151:** Tipo de vistoria = `VISTORIA_RENOVACAO` (ordinal 3). O marco registrado
e `VISTORIA_RENOVACAO` (aprovada) ou `VISTORIA_RENOVACAO_CIV` (reprovada).

**Importante:** O status NAO transita neste passo — permanece `EM_VISTORIA_RENOVACAO`.
A transicao so ocorre na homologacao (Passo 13), que e o ato formal do CBMRS.
Este design separa a responsabilidade do inspetor (registrar o resultado) da do
administrador (homologar oficialmente), fiel ao BPMN P14.

**O que e esperado:** Response com status ainda `EM_VISTORIA_RENOVACAO` e marco
`VISTORIA_RENOVACAO` registrado.

---

### Passo 13 — Homologar vistoria deferida

**O que faz:** `POST /licenciamentos/{id}/renovacao/homologar-vistoria` com
`{"deferida": true}`

**Perfil exigido:** `ADMIN` ou `CHEFE_SSEG_BBM`

**O que faz internamente (RN-152):**
1. Valida status `EM_VISTORIA_RENOVACAO`
2. Calcula nova `dtValidadeAppci = hoje + 5 anos`
3. Atualiza `licenciamento.dtValidadeAppci`
4. Transita status → `APPCI_EMITIDO`
5. Registra marco `HOMOLOG_VISTORIA_RENOV_DEFERIDO`
6. Registra marco `LIBERACAO_RENOV_APPCI` com a nova data de validade
7. Notifica RT e RU por e-mail

**Por que 5 anos?** A RTCBMRS 01/2024 define validade de 5 anos para edificacoes
Classe A e 2 anos para Classe B. O servico usa 5 anos como padrao configuravel
(`ANOS_VALIDADE_APPCI_RENOVADO = 5`). Ajuste por classe sera implementado em sprint
futura quando o campo `classeEdificacao` for adicionado a `Licenciamento`.

**O que e esperado:** `status: "APPCI_EMITIDO"` com `dtValidadeAppci` aproximadamente
5 anos no futuro.

---

### Passo 14 — Ciencia do novo APPCI

**O que faz:** `POST /licenciamentos/{id}/renovacao/ciencia-appci`

**Perfil:** `CIDADAO`, `RT`, `ADMIN` ou `CHEFE_SSEG_BBM`

**RN-152:** O cidadao/RT formaliza o recebimento do novo APPCI. Operacao idempotente
(nao duplica o marco se chamada mais de uma vez). Marcos registrados:
- `CIENCIA_APPCI_RENOVACAO`
- `RENOVACAO_CONCLUIDA`

**O que e esperado:** Response com `status: "APPCI_EMITIDO"` e marcos registrados.

---

### Passo 15 — Verificar estado final via sqlplus

**O que faz:** Consulta direta no banco Oracle para confirmar:
- `STATUS = 'APPCI_EMITIDO'`
- `DT_VALIDADE_APPCI` aproximadamente 5 anos no futuro
- Todos os marcos do P14 presentes na `SOL.MARCO_PROCESSO`

**Por que via sqlplus e nao via API?** E uma verificacao de integridade de segunda
camada — confirma que as escritas JPA realmente persistiram no banco Oracle, sem
depender da camada de servico para interpretar os dados.

**O que e esperado:** STATUS APPCI_EMITIDO, data de validade futura, marcos
`CIENCIA_APPCI_RENOVACAO` e `LIBERACAO_RENOV_APPCI` presentes.

---

### Passo 16 — Testar caminho de recusa (RN-145)

**O que faz:**
1. Cria segundo licenciamento
2. Promove para `ALVARA_VENCIDO` com `DT_VALIDADE_APPCI = SYSDATE-30` (passado)
3. Inicia renovacao → `AGUARDANDO_ACEITE_RENOVACAO`
4. Recusa renovacao via `POST /renovacao/recusar`

**RN-145 — logica de rollback no `recusarRenovacao`:**
- Se `dtValidadeAppci >= hoje` → status volta para `APPCI_EMITIDO`
- Se `dtValidadeAppci < hoje` → status volta para `ALVARA_VENCIDO`

Como o segundo licenciamento tem data no passado (`SYSDATE-30`), o rollback correto
e `ALVARA_VENCIDO`. Este passo verifica que a logica de rollback esta correta.

**O que e esperado:** `status: "ALVARA_VENCIDO"` apos a recusa.

---

### Passo 17 — Limpeza

**O que faz:** Remove todos os dados de teste criados durante a sprint via sqlplus,
em ordem de dependencia de FK:
1. `SOL.MARCO_PROCESSO` (FK -> LICENCIAMENTO)
2. `SOL.ARQUIVO_ED` (FK -> LICENCIAMENTO)
3. `SOL.BOLETO` (FK -> LICENCIAMENTO)
4. `SOL.LICENCIAMENTO`

**Por que e necessario?** Os licenciamentos de teste ocupam sequencias do Oracle e
poluem as listagens do sistema. A limpeza ao final garante que o banco fique no
estado pre-sprint.

**O que e esperado:** 0 licenciamentos restantes dos IDs de teste.

---

## Endpoints implementados (resumo)

| Metodo | Endpoint | Perfil | Fase | RN |
|---|---|---|---|---|
| GET | `/licenciamentos/renovacao/elegiveis` | CIDADAO/RT/ADMIN | -- | RN-155 |
| GET | `/licenciamentos/renovacao/em-andamento` | CIDADAO/RT/ADMIN | -- | RN-154 |
| POST | `/licenciamentos/{id}/renovacao/iniciar` | CIDADAO/RT/ADMIN | 1 | RN-141,143 |
| GET | `/licenciamentos/{id}/renovacao/anexo-d` | CIDADAO/RT/ADMIN | 2 | RN-144 |
| PUT | `/licenciamentos/{id}/renovacao/aceitar-anexo-d` | CIDADAO/RT/ADMIN | 2 | RN-144 |
| DELETE | `/licenciamentos/{id}/renovacao/aceitar-anexo-d` | CIDADAO/RT/ADMIN | 2 | RN-144 |
| POST | `/licenciamentos/{id}/renovacao/confirmar` | CIDADAO/RT/ADMIN | 2 | RN-145 |
| POST | `/licenciamentos/{id}/renovacao/recusar` | CIDADAO/RT/ADMIN | 2 | RN-145 |
| POST | `/licenciamentos/{id}/renovacao/solicitar-isencao` | CIDADAO/RT/ADMIN | 3 | RN-147 |
| POST | `/licenciamentos/{id}/renovacao/analisar-isencao` | ADMIN | 3 | RN-148 |
| POST | `/licenciamentos/{id}/renovacao/confirmar-pagamento` | ADMIN | 3 | RN-149 |
| POST | `/licenciamentos/{id}/renovacao/distribuir` | ADMIN | 4 | RN-150 |
| POST | `/licenciamentos/{id}/renovacao/registrar-vistoria` | INSPETOR/ADMIN | 5 | RN-151 |
| POST | `/licenciamentos/{id}/renovacao/homologar-vistoria` | ADMIN | 5 | RN-152,153 |
| POST | `/licenciamentos/{id}/renovacao/ciencia-appci` | CIDADAO/RT/ADMIN | 6A | RN-152 |
| POST | `/licenciamentos/{id}/renovacao/ciencia-civ` | CIDADAO/RT/ADMIN | 6B | RN-153 |
| POST | `/licenciamentos/{id}/renovacao/retomar` | CIDADAO/RT/ADMIN | 6B | RN-153 |

---

## Marcos de auditoria registrados (TipoMarco — P14)

| Marco | Evento | Fase |
|---|---|---|
| `INICIO_RENOVACAO` | Inicio do processo de renovacao | 1 |
| `ACEITE_ANEXOD_RENOVACAO` | Cidadao aceita o Anexo D | 2 |
| `REMOCAO_ACEITE_ANEXOD_RENOVACAO` | Cidadao remove o aceite do Anexo D | 2 |
| `RENOVACAO_CANCELADA` | Cidadao recusa a renovacao | 2 |
| `SOLICITACAO_ISENCAO_RENOVACAO` | Cidadao solicita isencao da taxa | 3 |
| `ANALISE_ISENCAO_RENOV_APROVADO` | Admin defere isencao | 3 |
| `ANALISE_ISENCAO_RENOV_REPROVADO` | Admin indefere isencao | 3 |
| `LIQUIDACAO_VISTORIA_RENOVACAO` | Pagamento do boleto confirmado | 3 |
| `DISTRIBUICAO_VISTORIA_RENOV` | Admin distribui vistoria para inspetor | 4 |
| `VISTORIA_RENOVACAO` | Inspetor registra vistoria aprovada | 5 |
| `VISTORIA_RENOVACAO_CIV` | Inspetor registra vistoria reprovada | 5 |
| `HOMOLOG_VISTORIA_RENOV_DEFERIDO` | Admin homologa deferimento | 5 |
| `HOMOLOG_VISTORIA_RENOV_INDEFERIDO` | Admin homologa indeferimento | 5 |
| `LIBERACAO_RENOV_APPCI` | Novo APPCI emitido com nova data de validade | 5 |
| `CIENCIA_APPCI_RENOVACAO` | Cidadao toma ciencia do novo APPCI | 6A |
| `RENOVACAO_CONCLUIDA` | Processo de renovacao encerrado com sucesso | 6A |
| `CIENCIA_CIV_RENOVACAO` | Cidadao toma ciencia da CIV | 6B |

---

## Decisoes de design (Spring Boot vs Oracle EE)

### 1. APPCI_EMITIDO = ALVARA_VIGENTE
O sistema Oracle usa `ALVARA_VIGENTE` como nome do status. Na stack Spring Boot, o
equivalente e `APPCI_EMITIDO` (historicamente nomeado assim desde o P08). O P14
aceita `APPCI_EMITIDO` como entrada valida (RN-141), mantendo consistencia interna.

### 2. TipoResponsabilidadeTecnica nao implementado
O Oracle EE exige RT com `TipoResponsabilidadeTecnica.RENOVACAO_APPCI` (RN-142).
Na stack Spring Boot, a validacao foi simplificada para verificar se o usuario
autenticado e o `responsavelTecnico` ou `responsavelUso` do licenciamento (por ID).
A validacao por tipo de responsabilidade tecnica sera adicionada quando o campo
`tipoResponsabilidadeTecnica` for incluido na entidade `ResponsavelTecnico`.

### 3. Homologar = transitar diretamente para APPCI_EMITIDO
No Oracle EE, a ciencia do cidadao (via `AppciCienciaCidadaoRenovacaoRN`) e que
dispara a transicao final para `ALVARA_VIGENTE`. Na stack Spring Boot, `homologarVistoria`
ja faz a transicao para `APPCI_EMITIDO` com o novo APPCI. O endpoint `ciencia-appci`
registra apenas o marco de ciencia (idempotente), sem nova transicao de status.
Isso simplifica o fluxo sem perder a rastreabilidade.

### 4. Validade do novo APPCI: 5 anos (constante configuravel)
A RTCBMRS 01/2024 define 5 anos (Classe A) ou 2 anos (Classe B). A constante
`ANOS_VALIDADE_APPCI_RENOVADO = 5` no `RenovacaoService` sera parametrizada por
classe de edificacao em sprint futura, quando o campo `classeEdificacao` for adicionado.

### 5. Pagamento via CNAB 240 (P13-E) nao implementado nesta sprint
O endpoint `confirmar-pagamento` e fornecido apenas para testes/homologacao.
Em producao, o pagamento do boleto de vistoria de renovacao sera confirmado
exclusivamente pelo job P13-E via arquivo CNAB 240 do Banrisul (RN-149).

---

## Estado do projeto apos Sprint 14

| Processo | BPMN | Req. Stack Atual | Req. Java Moderna | Implementado |
|---|---|---|---|---|
| P01 Login | completo | completo | completo | completo |
| P02 Cadastro RT | completo | completo | completo | completo |
| P03 Wizard PPCI | completo | completo | completo | completo |
| P04 Analise Tecnica | completo | completo | completo | completo |
| P05 Ciencia Recurso | completo | completo | completo | completo |
| P06 Isencao Taxa | completo | completo | completo | completo |
| P07 Vistoria | completo | completo | completo | completo |
| P08 PRPCI/APPCI | completo | completo | completo | completo |
| P09 Troca Envolvidos | completo | completo | completo | completo |
| P10 Recurso CIA/CIV | completo | completo | completo | completo |
| P11 Pagamento Boleto | completo | completo | completo | completo |
| P12 Extincao | completo | completo | completo | **Sprint 12 -- OK** |
| P13 Jobs Automaticos | completo | completo | completo | **Sprint 13 -- OK** |
| P14 Renovacao | completo | completo | pendente | **Sprint 14 -- esta sprint** |
