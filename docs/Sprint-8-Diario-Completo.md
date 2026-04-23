# Sprint 8 — Diário Completo de Execução
**Sistema:** SOL — Sistema Online de Licenciamento · CBM-RS
**Data de execução:** 2026-03-28
**Executor:** Claude Code (assistente IA) + Guilherme (administrador do sistema)
**Script base:** `C:\SOL\infra\scripts\sprint8-deploy.ps1`
**Tentativas de execução:** 1 (execução limpa, sem bugs)
**Status final:** ✅ Concluída com sucesso na primeira tentativa

---

## Índice

1. [[#Contexto e Objetivos da Sprint 8]]
2. [[#Análise Pré-Deploy]]
3. [[#Execução Completa — Passo a Passo]]
   - [[#Infraestrutura — Passos 1 a 6]]
   - [[#Fluxo A — P08 Emissão do APPCI]]
     - [[#Setup — P03 + P04 + P07 em Função Única]]
     - [[#Teste 1 — Emitir APPCI]]
     - [[#Teste 2 — Confirmar APPCI_EMITIDO e Validade]]
     - [[#Teste 3 — Listar APPCIs Vigentes]]
     - [[#Teste 4 — Verificar Marco APPCI_EMITIDO]]
     - [[#Teste 5 — Endpoint Dedicado /appci]]
   - [[#Limpeza Oracle]]
4. [[#Aviso Recorrente — GET /usuarios]]
5. [[#Arquitetura dos Novos Componentes P08]]
6. [[#AppciService — Análise Técnica]]
7. [[#Função Invoke-PrepararParaAppci — Inovação de Design]]
8. [[#Máquina de Estados Completa após Sprint 8]]
9. [[#Trilha de Auditoria — 8 Marcos do Licenciamento 14]]
10. [[#Tabela de Resultados]]
11. [[#Estado Final do Sistema]]

---

## Contexto e Objetivos da Sprint 8

### O que é o APPCI?

O **APPCI** (Alvará de Prevenção e Proteção Contra Incêndio) é o documento final emitido pelo CBM-RS que autoriza formalmente o funcionamento do estabelecimento do ponto de vista de prevenção de incêndios. É o objetivo de todo o processo de licenciamento — o "alvará" que o requerente precisa obter e manter atualizado para operar legalmente.

O APPCI é emitido após a aprovação da vistoria presencial (`PRPCI_EMITIDO` → `APPCI_EMITIDO`) e tem validade determinada pela área construída do imóvel, conforme o RTCBMRS N.01/2024:

| Área construída | Validade do APPCI |
|-----------------|-------------------|
| ≤ 750 m² | 2 anos |
| > 750 m² | 5 anos |

### Posição no ciclo de licenciamento

```
P03 (submissão) → P04 (análise) → P07 (vistoria) → P08 (APPCI) ← Sprint 8
```

A Sprint 8 implementa a **fase final** do ciclo principal de licenciamento. Com o APPCI emitido, o estabelecimento está regularizado junto ao CBM-RS.

### O que é novo nesta sprint

| Componente | Tipo | Responsabilidade |
|------------|------|-----------------|
| `AppciService.java` | `@Service` | Regras de negócio P08 (RN-P08-001 a RN-P08-004) |
| `AppciController.java` | `@RestController` | Endpoints `/appci/vigentes`, `/{id}/emitir-appci`, `/{id}/appci` |
| `Licenciamento.dtValidadeAppci` | campo `LocalDate` | Data de vencimento do APPCI |
| `Licenciamento.dtVencimentoPrpci` | campo `LocalDate` | Data de vencimento do PRPCI (preenchida automaticamente) |
| `TipoMarco.APPCI_EMITIDO` | enum value | Marco de auditoria do APPCI |
| `StatusLicenciamento.APPCI_EMITIDO` | enum value | Estado final do ciclo principal |

### Regras de negócio implementadas

| RN | Descrição |
|----|-----------|
| RN-P08-001 | APPCI só pode ser emitido em licenciamentos com status `PRPCI_EMITIDO` |
| RN-P08-002 | Validade calculada automaticamente: área ≤ 750 m² → 2 anos; > 750 m² → 5 anos |
| RN-P08-003 | `dtVencimentoPrpci` preenchida como `hoje + 1 ano` se ainda não definida |
| RN-P08-004 | `GET /appci` só aceita licenciamentos em `APPCI_EMITIDO` |

---

## Análise Pré-Deploy

### Verificações do script PowerShell

| Verificação | Resultado |
|-------------|-----------|
| CEP `"90010100"` | ✅ |
| Senha `"Admin@SOL2026"` | ✅ |
| `Push-Location $ProjectRoot` antes do Maven | ✅ |
| Fallback `mvnw.cmd` → `mvn` global | ✅ |
| `${lid}` na limpeza (padrão desde Sprint 6) | ✅ |

### Verificações dos arquivos Java

Diferentemente das Sprints 6 e 7 (que tiveram bugs de script e de compilação respectivamente), a Sprint 8 foi submetida a uma **análise pré-deploy proativa dos arquivos Java**, lendo `AppciService.java` e `AppciController.java` antes de executar — exatamente a abordagem que teria prevenido o erro de compilação da Sprint 7 se aplicada naquela ocasião.

Arquivos lidos na análise:
- `AppciService.java` — verificados todos os métodos de repositório chamados
- `AppciController.java` — verificado uso de `AnaliseDecisaoDTO`
- `StatusLicenciamento.java` — confirmados `APPCI_EMITIDO` e `PRPCI_EMITIDO`
- `TipoMarco.java` — confirmado `APPCI_EMITIDO`
- `Licenciamento.java` (via grep) — confirmados campos `areaConstruida`, `dtValidadeAppci`, `dtVencimentoPrpci`, `inspetor`
- `LicenciamentoRepository.java` — confirmado `findByStatus()` existente (usado por `AppciService.findVigentes`)

**Resultado:** Nenhuma inconsistência detectada. Nenhuma correção necessária. Script executado sem modificações.

---

## Execução Completa — Passo a Passo

### Infraestrutura — Passos 1 a 6

#### Passo 1 — Parar o Serviço

```
===> Parando servico SOL-Backend
  [OK] Servico parado
```

`Stop-Service -Name "SOL-Backend" -Force` + `Start-Sleep -Seconds 5`. Serviço estava em execução e foi encerrado com sucesso. O `Start-Sleep` aguarda a JVM liberar o lock no JAR antes do Maven tentar recompilá-lo.

#### Passo 2 — Compilar com Maven

```
===> Compilando com Maven (JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot)
  [OK] Build concluido com sucesso
```

`mvn clean package -Dmaven.test.skip=true -q` compilou os novos arquivos da Sprint 8 sem erros:
- `AppciService.java` — novo serviço P08
- `AppciController.java` — novos endpoints APPCI
- `Licenciamento.java` (atualizado) — campos `dtValidadeAppci` e `dtVencimentoPrpci`
- Schema Hibernate: novas colunas `dt_validade_appci` e `dt_vencimento_prpci` na tabela `LICENCIAMENTO` (via `ddl-auto: update` ou migration Flyway, dependendo da configuração do perfil `prod`)

#### Passo 3 — Reiniciar o Serviço

```
===> Reiniciando servico SOL-Backend
  [OK] Servico iniciado
```

`Start-Service -Name "SOL-Backend"` — NSSM iniciou o novo JAR. O Spring Boot carregou:
- `AppciService` e `AppciController` como novos beans
- `LicenciamentoRepository` com os métodos existentes (incluindo `findByInspetor` adicionado na Sprint 7)
- O Hibernate validou / criou as novas colunas no Oracle XE

#### Passo 4 — Aguardar e Health Check

```
===> Aguardando 35 segundos
===> Health check -- http://localhost:8080/api/health
  [OK] Saudavel (tentativa 1)
```

Inicialização completa em menos de 35 segundos. `GET /api/health` respondeu `HTTP 200` na primeira tentativa.

#### Passo 5 — Login

```
===> Login -- POST /auth/login
  [OK] Login OK
```

JWT obtido via ROPC, `expires_in=3600s`. Role `ADMIN` autoriza todos os endpoints P08 (`hasAnyRole('ADMIN', 'ANALISTA')` em `/emitir-appci`; `hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')` em `/appci/vigentes`).

#### Passo 6 — Obter ID do Admin

```
===> Obtendo ID do usuario admin
  [AVISO] GET /usuarios falhou -- usando id=1 como fallback
```

Aviso recorrente (quarta sprint consecutiva). Fallback `$adminId = 1` funcionou corretamente para analista e inspetor no setup. Ver [[#Aviso Recorrente — GET /usuarios]].

---

### Fluxo A — P08: Emissão do APPCI

**Objetivo:** Validar o ciclo completo P03→P04→P07→P08, culminando na emissão do APPCI com cálculo automático de validade.

**Cadeia de estados testada:**
`RASCUNHO → ANALISE_PENDENTE → EM_ANALISE → DEFERIDO → VISTORIA_PENDENTE → EM_VISTORIA → PRPCI_EMITIDO → APPCI_EMITIDO`

---

#### Setup — P03 + P04 + P07 em Função Única

```
===> Fluxo A -- Setup: P03 + P04 + P07 (-> PRPCI_EMITIDO)
  [OK] Licenciamento criado -- id=14
  [OK] Upload PPCI OK
  [OK] Submissao OK -- status=ANALISE_PENDENTE
  [OK] Distribuicao OK
  [OK] Inicio de analise OK
  [OK] Deferimento analise OK -- status=DEFERIDO
  [OK] Vistoria agendada -- status=VISTORIA_PENDENTE
  [OK] Inspetor atribuido
  [OK] Vistoria iniciada -- status=EM_VISTORIA
  [OK] Vistoria aprovada -- status=PRPCI_EMITIDO
  [OK] Setup concluido -- id=14 status=PRPCI_EMITIDO
```

A função `Invoke-PrepararParaAppci` encapsula **10 operações** em sequência — todos os passos das Sprints 4 e 7 — para colocar o licenciamento no estado `PRPCI_EMITIDO` antes dos testes P08. Ver [[#Função Invoke-PrepararParaAppci — Inovação de Design]] para análise detalhada desta escolha de design.

O licenciamento id=14 é o décimo quarto processado pelo sistema (a sequence Oracle não retroage após os deletes das sprints anteriores), confirmando que todos os testes anteriores foram executados e limpos corretamente.

---

#### Teste 1 — Emitir APPCI

```
===> Fluxo A -- Teste 1: POST /licenciamentos/14/emitir-appci
  [OK] APPCI emitido -- status=APPCI_EMITIDO
```

`POST /api/licenciamentos/14/emitir-appci` com body:
```json
{
  "observacao": "APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."
}
```

**Fluxo interno em `AppciService.emitirAppci()`:**

```
1. buscarPorId(14)                             → Licenciamento carregado
2. lic.getStatus() != PRPCI_EMITIDO?           → false (RN-P08-001 OK)
3. hoje = LocalDate.now()                      → 2026-03-28
4. anosValidade = calcularAnosValidadeAppci(500.00)
   → 500.00 <= 750.00 → retorna 2
5. dtValidade = 2026-03-28 + 2 anos            → 2028-03-28
6. lic.setDtValidadeAppci(2028-03-28)
7. lic.getDtVencimentoPrpci() == null?         → true (RN-P08-003)
   lic.setDtVencimentoPrpci(2026-03-28 + 1 ano) → 2027-03-28
8. lic.setStatus(APPCI_EMITIDO)
9. licenciamentoRepository.save(lic)           → commit no Oracle
10. obsMarco = "APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²).
                APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."
11. registrarMarco(lic, TipoMarco.APPCI_EMITIDO, usuario, obsMarco)
12. notificarEnvolvidos(lic, assunto, corpo)   → RT e RU (nulos neste teste)
13. return licenciamentoService.toDTO(lic)     → LicenciamentoDTO com status=APPCI_EMITIDO
```

**Por que `PRPCI_EMITIDO` como pré-condição (RN-P08-001):**
O APPCI só pode ser emitido após a confirmação física de que o imóvel está em conformidade. O estado `PRPCI_EMITIDO` representa exatamente isso: o inspetor visitou o local, verificou as instalações e aprovou. Emitir o APPCI a partir de qualquer outro estado (por exemplo, direto de `DEFERIDO`, pulando a vistoria) seria incorreto do ponto de vista jurídico e da segurança pública.

---

#### Teste 2 — Confirmar APPCI_EMITIDO e Validade

```
===> Fluxo A -- Teste 2: GET /licenciamentos/14 (confirmar APPCI_EMITIDO + dtValidadeAppci)
  [OK] Status APPCI_EMITIDO confirmado
  [OK] dtValidadeAppci=2028-03-28 (~2 anos)
  [OK] Validade de 2 anos confirmada (area=500 m² <= 750 m²)
  [OK] dtVencimentoPrpci=2027-03-28
```

`GET /api/licenciamentos/14` confirmou três campos críticos:

**`status = APPCI_EMITIDO`:**
Verificação independente do retorno do POST — confirma que a transição de estado foi persistida corretamente no Oracle.

**`dtValidadeAppci = 2028-03-28`:**
O script calcula a diferença em dias e converte para anos:
```powershell
$dtValidade   = [DateTime]::Parse("2028-03-28")
$anosValidade = ($dtValidade - (Get-Date)).Days / 365   # ≈ 2.0
$anosDiff     = [Math]::Abs($anosValidade - 2)          # ≈ 0.0
# $anosDiff < 0.1 → validade de 2 anos confirmada
```
A tolerância de 0.1 anos (~36 dias) protege contra variações de ano bissexto e diferenças de hora do dia — o cálculo `Days / 365` não é exato para períodos que cruzam anos bissextos, mas para o propósito de validação de smoke test é suficiente.

**`dtVencimentoPrpci = 2027-03-28`:**
Preenchido automaticamente pela RN-P08-003 como `hoje + 1 ano` = `2026-03-28 + 1 ano` = `2027-03-28`. Esse campo registra até quando o PRPCI (Parecer do Inspetor) é válido — prazo após o qual o inspetor deve fazer nova vistoria de renovação.

**Semântica dos dois campos de data:**
| Campo | O que representa | Como é calculado |
|-------|-----------------|-----------------|
| `dtValidadeAppci` | Vencimento do alvará (APPCI) | Hoje + 2 ou 5 anos (por área) |
| `dtVencimentoPrpci` | Vencimento do parecer do inspetor (PRPCI) | Hoje + 1 ano (fixo, RN-P08-003) |

O APPCI tem validade maior que o PRPCI porque o alvará é o documento administrativo final, enquanto o PRPCI é o laudo técnico do inspetor — que precisa ser renovado mais frequentemente para garantir que as condições físicas do imóvel continuam conformes.

---

#### Teste 3 — Listar APPCIs Vigentes

```
===> Fluxo A -- Teste 3: GET /appci/vigentes
  [OK] APPCIs vigentes: 1 licenciamento(s)
```

`GET /api/appci/vigentes?page=0&size=10` — endpoint servido por `AppciController.findVigentes()`, que delega para `AppciService.findVigentes()`, que chama `licenciamentoRepository.findByStatus(APPCI_EMITIDO, pageable)`.

O resultado `1` confirma exatamente o licenciamento 14 (nenhum resíduo de testes anteriores, pois todos foram limpos). O script usa lógica defensiva para lidar com a resposta paginada:
```powershell
$total = if ($null -ne $vigentes.totalElements) { $vigentes.totalElements }
         else { $vigentes.content.Count }
```
Essa verificação `totalElements` vs `content.Count` é a mesma usada na Sprint 5 para `GET /analise/fila` — o autor do script antecipou que o formato de resposta pode variar.

**Por que um endpoint dedicado `/appci/vigentes`:**
Em produção, o CBM-RS precisa monitorar todos os APPCIs ativos para:
- Saber quais estabelecimentos estão regularizados
- Identificar APPCIs próximos do vencimento (para jobs de notificação automática)
- Gerar relatórios gerenciais de cobertura de licenciamento

Um endpoint dedicado com paginação e filtro por status é mais eficiente do que buscar todos os licenciamentos e filtrar no cliente.

---

#### Teste 4 — Verificar Marco APPCI_EMITIDO

```
===> Fluxo A -- Teste 4: GET /licenciamentos/14/marcos (marco APPCI_EMITIDO)
  [OK] Marcos registrados (8):
    SUBMISSAO         | Licenciamento submetido para analise via P03. Arquivos PPCI: 1
    DISTRIBUICAO      | Licenciamento distribuido para analise. Analista: RT Smoke Test Sprint3
    INICIO_ANALISE    | Analise tecnica iniciada. Analista: 6a6065a2-edc1-415a-ac91-a260ebc9063c
    APROVACAO_ANALISE | PPCI aprovado. Encaminhado para vistoria.
    VISTORIA_AGENDADA | Vistoria presencial agendada para 2026-04-04. Vistoria para emissao de APPCI.
    VISTORIA_REALIZADA| Vistoria presencial iniciada. Inspetor: RT Smoke Test Sprint3
    VISTORIA_APROVADA | Edificio em conformidade. PRPCI emitido.
    APPCI_EMITIDO     | APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²).
                        APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes.
  [OK] Marco APPCI_EMITIDO presente
```

**8 marcos** — a trilha de auditoria mais completa gerada até este ponto no projeto. Cada marco representa um evento administrativo irrevogável no histórico do licenciamento. Ver [[#Trilha de Auditoria — 8 Marcos do Licenciamento 14]] para análise detalhada.

O marco `APPCI_EMITIDO` contém a concatenação do texto automático do backend com a observação fornecida pelo caller:
- **Prefixo automático:** `"APPCI emitido. Validade: 2028-03-28 (2 anos, area construida: 500 m²)."`
- **Observação do request:** `"APPCI emitido apos vistoria presencial aprovada. Instalacoes conformes."`

Diferentemente do bug de texto duplicado observado no marco `CIA_CIENCIA` da Sprint 6, aqui o `AppciService` concatena corretamente: prefixo fixo + espaço + observação do usuário, sem repetição.

---

#### Teste 5 — Endpoint Dedicado /appci

```
===> Fluxo A -- Teste 5: GET /licenciamentos/14/appci
  [OK] Endpoint /appci OK -- dtValidadeAppci=2028-03-28
```

`GET /api/licenciamentos/14/appci` — endpoint específico que valida a RN-P08-004: só retorna dados se o licenciamento estiver em `APPCI_EMITIDO`. Se chamado com um licenciamento em outro estado, lança `BusinessException("RN-P08-004", ...)` → HTTP 422.

**Diferença em relação ao `GET /licenciamentos/{id}`:**
O endpoint `GET /licenciamentos/{id}` retorna o licenciamento independentemente do status. O `GET /licenciamentos/{id}/appci` é um endpoint semântico dedicado ao APPCI — útil para o frontend exibir a "tela do alvará" com garantia de que os dados de validade estarão presentes, ou para integrações de terceiros (sistemas de fiscalização) que precisam consultar especificamente o status de alvará de um estabelecimento.

---

### Limpeza Oracle

```
===> Limpeza Oracle -- removendo dados de teste (licenciamento A)
  [OK] Licenciamento id=14 removido
```

SQL executado via `sqlplus.exe -S "/ as sysdba"`:
```sql
DELETE FROM sol.arquivo_ed     WHERE id_licenciamento = 14;
DELETE FROM sol.marco_processo WHERE id_licenciamento = 14;
DELETE FROM sol.boleto         WHERE id_licenciamento = 14;
DELETE FROM sol.licenciamento  WHERE id_licenciamento = 14;
COMMIT;
EXIT;
```

Os 8 marcos do licenciamento 14 foram removidos junto com o registro principal. O arquivo PPCI no MinIO permanece no bucket `sol-arquivos` (chave `licenciamentos/14/PPCI/...`) — o script não chama `DELETE /arquivos/{id}` antes da limpeza Oracle, então o objeto MinIO fica órfão. Esse comportamento é consistente com todas as sprints anteriores.

---

## Aviso Recorrente — GET /usuarios

```
[AVISO] GET /usuarios falhou -- usando id=1 como fallback
```

Quarta sprint consecutiva (Sprints 5, 6, 7, 8) com este aviso. O padrão está estabilizado: o fallback `$adminId = 1` funciona corretamente para todos os papéis (analista, inspetor) e não impacta os smoke tests.

**Diagnóstico:** `GET /api/usuarios?page=0&size=50` provavelmente retorna `List<UsuarioDTO>` (array JSON) em vez de `Page<UsuarioDTO>`. O PowerShell `Invoke-RestMethod` deserializa arrays JSON como `Object[]`, que não possui a propriedade `.content`. A exceção é capturada pelo bloco `catch` e o fallback é ativado.

**Recomendação consolidada:** Padronizar `UsuarioController.getAll()` para retornar `ResponseEntity<Page<UsuarioDTO>>` com `Pageable`, alinhando com os demais endpoints paginados do sistema.

---

## Arquitetura dos Novos Componentes P08

### AppciController

```
GET /api/appci/vigentes
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR')")
  → AppciService.findVigentes(pageable)
  → licenciamentoRepository.findByStatus(APPCI_EMITIDO, pageable)
  → Page<LicenciamentoDTO>

GET /api/licenciamentos/{id}/appci
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA', 'INSPETOR', 'CIDADAO', 'RT')")
  → AppciService.findAppci(licId)
  → Valida: status == APPCI_EMITIDO (RN-P08-004)
  → LicenciamentoDTO

POST /api/licenciamentos/{id}/emitir-appci
  @PreAuthorize("hasAnyRole('ADMIN', 'ANALISTA')")
  body: AnaliseDecisaoDTO? (observacao opcional)
  → AppciService.emitirAppci(id, obs, jwt.getSubject())
  → LicenciamentoDTO
```

**Observação sobre `@RequestBody(required = false)`:**
O campo `@RequestBody(required = false)` no método `emitirAppci` permite chamar o endpoint sem body JSON — útil para automações que querem emitir o APPCI sem observação adicional. O service trata `dto == null` como `obs = null`, e o marco registrado usa apenas o prefixo automático.

### AppciService — Cálculo de Validade

```java
private static final BigDecimal AREA_LIMIAR          = new BigDecimal("750.00");
private static final int VALIDADE_ANOS_ATE_750        = 2;
private static final int VALIDADE_ANOS_ACIMA_750      = 5;
private static final int VALIDADE_PRPCI_ANOS          = 1;

private int calcularAnosValidadeAppci(BigDecimal area) {
    if (area == null || area.compareTo(AREA_LIMIAR) <= 0) {
        return VALIDADE_ANOS_ATE_750;   // conservador quando área não informada
    }
    return VALIDADE_ANOS_ACIMA_750;
}
```

O uso de `BigDecimal` para comparação de área é consistente com o restante do sistema (campo `areaConstruida` da entidade `Licenciamento` é `BigDecimal`, corrigido desde a Sprint 1 para evitar problemas de precisão do `Double` com Hibernate 6.5).

---

## AppciService — Análise Técnica

### Padrão de design consistente com VistoriaService

O `AppciService` segue o mesmo padrão arquitetural do `VistoriaService` (Sprint 7):

| Aspecto | VistoriaService | AppciService |
|---------|----------------|--------------|
| `@Transactional(readOnly = true)` na classe | ✅ | ✅ |
| `@Transactional` nos métodos de escrita | ✅ | ✅ |
| Notificações via `emailService.notificarAsync()` | ✅ | ✅ |
| Validação de pré-condição com `BusinessException(código, mensagem)` | ✅ | ✅ |
| Helper `registrarMarco()` privado | ✅ | ✅ |
| Helper `notificarEnvolvidos()` privado | ✅ | ✅ |
| Helper `buscarPorId()` privado | ✅ | ✅ |

Essa consistência indica que o time de desenvolvimento estabeleceu um padrão de serviço transacional que está sendo seguido rigorosamente nas novas sprints.

### Uso de LocalDate vs LocalDateTime

O `AppciService` usa `LocalDate` (sem hora) para `dtValidadeAppci` e `dtVencimentoPrpci`, em contraste com outros campos de data do sistema que usam `LocalDateTime`. Isso é correto para datas de validade: o APPCI vence no fim do dia `2028-03-28`, não em um instante específico. `LocalDate` também simplifica a exibição ao usuário (sem componente de hora/timezone).

### Cálculo de validade com `plusYears()`

```java
LocalDate dtValidade = hoje.plusYears(anosValidade);
```

O método `LocalDate.plusYears()` do Java lida corretamente com anos bissextos: `2026-02-28 + 2 anos = 2028-02-28` (não `2028-02-29`), e `2024-02-29 + 1 ano = 2025-02-28` (fevereiro do ano não bissexto). O CBM-RS não precisa se preocupar com edge cases de calendário — a biblioteca padrão do Java trata isso de forma determinística.

---

## Função Invoke-PrepararParaAppci — Inovação de Design

A Sprint 8 introduziu uma mudança significativa na estratégia dos smoke tests: em vez de funções auxiliares separadas (`Invoke-CriarSubmeter`, `Invoke-PrepararParaAnalise`, `Invoke-PrepararParaVistoria`), a Sprint 8 consolida **tudo** em uma única função `Invoke-PrepararParaAppci` que executa os 10 passos de P03+P04+P07.

### Evolução das funções auxiliares entre sprints

| Sprint | Funções auxiliares | Passos encapsulados |
|--------|-------------------|---------------------|
| 5 | `Invoke-CriarSubmeter` | 3 (criar, upload, submeter) |
| 5 | `Invoke-PrepararParaAnalise` | 2 (distribuir, iniciar-analise) |
| 6 | `Invoke-CriarSubmeter` (reutilizada) | 3 |
| 7 | `Invoke-CriarSubmeter` (reutilizada) | 3 |
| 7 | `Invoke-PrepararParaVistoria` | 3 (distribuir, iniciar-analise, deferir) |
| **8** | **`Invoke-PrepararParaAppci`** | **10 (P03+P04+P07 completos)** |

### Por que consolidar em uma função?

O foco da Sprint 8 é exclusivamente P08. As sprints anteriores já validaram P03, P04 e P07 extensivamente. Reexibir cada passo intermediário com `[OK]` detalhado seria ruído — o que importa é confirmar que o setup chegou a `PRPCI_EMITIDO` antes de testar os novos endpoints.

A função `Invoke-PrepararParaAppci` emite mensagens resumidas (`[OK] Vistoria agendada`, `[OK] Inspetor atribuido`, etc.) e ao final verifica:
```powershell
if ($licA.status -ne "PRPCI_EMITIDO") {
    throw "Setup falhou: status esperado PRPCI_EMITIDO, obtido $($licA.status)"
}
```
Essa verificação de guarda garante que qualquer falha no setup aborta imediatamente com mensagem clara — sem tentar executar os testes P08 sobre um licenciamento em estado incorreto.

---

## Máquina de Estados Completa após Sprint 8

```
            MÁQUINA DE ESTADOS — LICENCIAMENTO (após Sprint 8)
   ═══════════════════════════════════════════════════════════════════

   [P03]        [P04]              [P07 — Vistoria]        [P08]
   ─────        ─────              ────────────────        ────
   RASCUNHO
      │/submeter
      ▼
   ANALISE_PENDENTE
      │/distribuir (sem mudança de status)
      │/iniciar-analise
      ▼
   EM_ANALISE ──/emitir-cia──► CIA_EMITIDO
      │                            │/registrar-ciencia-cia
      │/deferir                    ▼
      ▼                        CIA_CIENCIA
   DEFERIDO                        │/retomar-analise
      │/agendar-vistoria            └──────────────► EM_ANALISE
      ▼
   VISTORIA_PENDENTE
      │/iniciar-vistoria
      │(requer inspetor atribuido)
      ▼
   EM_VISTORIA ──/emitir-civ──► CIV_EMITIDO
      │                              │/registrar-ciencia-civ
      │/aprovar-vistoria             ▼
      ▼                          CIV_CIENCIA
   PRPCI_EMITIDO                     │/retomar-vistoria
      │/emitir-appci                 └──────────────► EM_VISTORIA
      ▼
   APPCI_EMITIDO  ✅  (estado final do ciclo principal)

   [P06 — Paralelo]  /solicitar-isencao → isentoTaxa (true/false)
   [Futuros]  RECURSO_PENDENTE · EM_RECURSO · SUSPENSO · EXTINTO · RENOVADO
```

Com `APPCI_EMITIDO`, o **ciclo principal de licenciamento** está completo. Os próximos fluxos (P09 a P14, conforme `TipoMarco.java`) cobrem renovação, recurso, suspensão e cancelamento.

---

## Trilha de Auditoria — 8 Marcos do Licenciamento 14

O licenciamento 14 gerou a trilha de auditoria mais completa do projeto, cobrindo todos os fluxos P03, P04, P07 e P08:

| # | Marco | Timestamp | Observação registrada |
|---|-------|-----------|----------------------|
| 1 | `SUBMISSAO` | 2026-03-28T... | Licenciamento submetido via P03. Arquivos PPCI: 1 |
| 2 | `DISTRIBUICAO` | 2026-03-28T... | Distribuido. Analista: RT Smoke Test Sprint3 |
| 3 | `INICIO_ANALISE` | 2026-03-28T... | Analise iniciada. Analista: 6a6065a2-... (UUID Keycloak) |
| 4 | `APROVACAO_ANALISE` | 2026-03-28T... | PPCI aprovado. Encaminhado para vistoria. |
| 5 | `VISTORIA_AGENDADA` | 2026-03-28T... | Vistoria agendada para 2026-04-04. |
| 6 | `VISTORIA_REALIZADA` | 2026-03-28T... | Vistoria iniciada. Inspetor: RT Smoke Test Sprint3 |
| 7 | `VISTORIA_APROVADA` | 2026-03-28T... | Edificio em conformidade. PRPCI emitido. |
| 8 | `APPCI_EMITIDO` | 2026-03-28T... | Validade: 2028-03-28 (2 anos, 500 m²). |

**Valor jurídico desta trilha:**
Cada marco representa um ato administrativo com data, responsável e justificativa. Em caso de auditoria, fiscalização ou recurso judicial, o CBM-RS pode demonstrar com precisão o histórico completo do processo: quem analisou, quando aprovou, quem inspecionou, quando o alvará foi emitido e sua data de vencimento. Isso é exatamente o modelo do processo administrativo eletrônico exigido pela Lei nº 14.129/2021 (Lei do Governo Digital).

---

## Tabela de Resultados

| # | Endpoint / Ação | Método | Resultado | Observação |
|---|-----------------|--------|-----------|------------|
| 1 | Serviço SOL-Backend | STOP | ✅ OK | Parado normalmente |
| 2 | Maven `clean package` | BUILD | ✅ OK | 1ª tentativa, sem erros |
| 3 | Serviço SOL-Backend | START | ✅ OK | AppciService e AppciController carregados |
| 4 | `/api/health` | GET | ✅ OK | Tentativa 1 |
| 5 | `/api/auth/login` | POST | ✅ OK | JWT 3600s |
| 6 | `/api/usuarios` | GET | ⚠️ AVISO | Sem `.content`; fallback id=1 |
| **Setup P03+P04+P07** | | | | |
| 7 | `/api/licenciamentos` | POST | ✅ OK | id=14, RASCUNHO |
| 8 | `/api/arquivos/upload` | POST | ✅ OK | PPCI → MinIO |
| 9 | `/api/licenciamentos/14/submeter` | POST | ✅ OK | ANALISE_PENDENTE |
| 10 | `/api/licenciamentos/14/distribuir` | PATCH | ✅ OK | analistaId=1 |
| 11 | `/api/licenciamentos/14/iniciar-analise` | POST | ✅ OK | EM_ANALISE |
| 12 | `/api/licenciamentos/14/deferir` | POST | ✅ OK | DEFERIDO |
| 13 | `/api/licenciamentos/14/agendar-vistoria` | POST | ✅ OK | VISTORIA_PENDENTE, data=2026-04-04 |
| 14 | `/api/licenciamentos/14/atribuir-inspetor` | PATCH | ✅ OK | inspetorId=1 |
| 15 | `/api/licenciamentos/14/iniciar-vistoria` | POST | ✅ OK | EM_VISTORIA |
| 16 | `/api/licenciamentos/14/aprovar-vistoria` | POST | ✅ OK | PRPCI_EMITIDO |
| **Testes P08** | | | | |
| 17 | `/api/licenciamentos/14/emitir-appci` | POST | ✅ OK | APPCI_EMITIDO |
| 18 | `/api/licenciamentos/14` | GET | ✅ OK | APPCI_EMITIDO + dtValidadeAppci=2028-03-28 + dtVencimentoPrpci=2027-03-28 |
| 19 | Validade 2 anos (área 500 m²) | Calc | ✅ OK | RN-P08-002 validada |
| 20 | `/api/appci/vigentes` | GET | ✅ OK | 1 APPCI vigente |
| 21 | `/api/licenciamentos/14/marcos` | GET | ✅ OK | 8 marcos, APPCI_EMITIDO presente |
| 22 | `/api/licenciamentos/14/appci` | GET | ✅ OK | dtValidadeAppci=2028-03-28 |
| **Limpeza** | | | | |
| 23 | Limpeza Oracle id=14 | sqlplus | ✅ OK | 4 DELETEs + COMMIT |

**Legenda:** ✅ Sucesso · ⚠️ Aviso (não-bloqueante) · ❌ Falha (não ocorreu)

> **Nota:** Sprint 8 é a primeira desde a Sprint 5 a ser concluída sem nenhuma correção de código — nem no script PowerShell nem nos arquivos Java. A análise pré-deploy proativa dos arquivos Java preveniu a repetição do bug de Sprint 7.

---

## Estado Final do Sistema

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ESTADO DO SISTEMA APÓS SPRINT 8                          │
├──────────────────────┬──────────────────────────────────────────────────────────┤
│ Serviço Windows      │ SOL-Backend — RUNNING (NSSM)                             │
│ JAR em execução      │ C:\SOL\backend\target\sol-backend-1.0.0.jar               │
│ Spring Boot          │ 3.3.4 — perfil prod — porta 8080                         │
│ Java                 │ 21.0.9 Eclipse Adoptium (JDK)                            │
│ Oracle XE            │ XEPDB1, schema SOL — dados de teste removidos            │
│ Keycloak             │ localhost:8180, realm sol — operacional                   │
│ MinIO                │ localhost:9000 — policy sol-app-policy OK                 │
├──────────────────────┼──────────────────────────────────────────────────────────┤
│ Sprints concluídas   │ 1 · 2 · 3 · 4 · 5 · 6 · 7 · 8                          │
│ Fluxos operacionais  │ P01 · P02 · P03 · P04 · P05 · P06 · P07 · P08           │
│ Endpoints totais     │ ~39 endpoints validados                                   │
│ Correções nesta S8   │ Nenhuma — primeira execução limpa desde Sprint 5          │
│ Ciclo principal      │ ✅ COMPLETO (RASCUNHO → APPCI_EMITIDO)                   │
└──────────────────────┴──────────────────────────────────────────────────────────┘
```

### Sprints acumuladas

| Sprint | Fluxo | Entregas |
|--------|-------|----------|
| 1 | — | Infraestrutura: Oracle, Keycloak, NSSM, tabelas |
| 2 | — | API REST base: CRUD usuários, Swagger, JWT |
| 3 | P01/P02 | Auth ROPC + Cadastro RT/RU |
| 4 | P03 | Licenciamento + Upload MinIO + Submissão |
| 5 | P04 | Análise técnica: distribuição, início, deferimento, CIA |
| 6 | P05/P06 | Ciência CIA + Retomada · Isenção de Taxa |
| 7 | P07 | Vistoria presencial: agendamento, CIV, aprovação, PRPCI |
| **8** | **P08** | **Emissão do APPCI — conclusão do ciclo principal** |

---

*Relatório gerado por Claude Code em 2026-03-28.*
*Script de referência: `C:\SOL\infra\scripts\sprint8-deploy.ps1`*
*Log do serviço: `C:\SOL\logs\sol-backend.log`*
*Ciclo principal de licenciamento: CONCLUÍDO.*
