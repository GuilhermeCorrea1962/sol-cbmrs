# Sprint 11 — P11 Pagamento de Boleto

**Data de criacao:** 2026-03-31
**Sistema:** SOL — Sistema Online de Licenciamento (CBM-RS)
**Sprint:** 11 / Processo: P11 — Pagamento de Boleto

---

## Objetivo

Esta sprint implementa o ciclo completo de pagamento de boleto (guia de recolhimento) no sistema SOL, cobrindo dois fluxos:

- **P11-A** — Fluxo manual: operador gera boleto e confirma o pagamento via endpoint REST.
- **P11-B** — Fluxo automatico: job agendado que detecta e marca como VENCIDO todo boleto PENDENTE que ultrapassou a data de vencimento.

---

## Arquivos alterados/criados

| Arquivo | Tipo | Descricao |
|---|---|---|
| `backend/.../service/BoletoService.java` | Alterado | Adiciona registro de marcos, notificacao por e-mail, parametro `keycloakId` e metodo `vencerBoleto()` para o job |
| `backend/.../controller/BoletoController.java` | Alterado | Adiciona `@AuthenticationPrincipal Jwt` nos endpoints `create` e `confirmarPagamento` |
| `backend/.../service/BoletoJobService.java` | Novo | Job P11-B: `@Scheduled(cron = "0 0 2 * * *")` — executa diariamente as 02:00 |
| `infra/scripts/sprint11-deploy.ps1` | Novo | Script de deploy e smoke test |

> Os tres arquivos Java foram gravados simultaneamente em `C:\SOL\` (local) e `Y:\` (servidor via SMB).

---

## O que foi implementado

### BoletoService.java — alteracoes

**Novas dependencias injetadas:**
- `UsuarioRepository` — para resolver o operador a partir do `keycloakId` do JWT
- `MarcoProcessoRepository` — para persistir marcos de processo
- `LicenciamentoService` — ja injetado para acesso ao licenciamento
- `EmailService` — para notificacao assincrona de RT e RU

**Metodo `create(Long licenciamentoId, String keycloakId)`:**
- Assinatura alterada: adicionado parametro `keycloakId`
- Apos salvar o boleto, registra o marco `BOLETO_GERADO` com observacao contendo valor e data de vencimento
- Envia e-mail ao RT e ao RU notificando a emissao do boleto (valor + vencimento)
- Regras de negocio preservadas: RN-090 (sem PENDENTE duplicado) e RN-091 (isento nao gera boleto)

**Metodo `confirmarPagamento(Long boletoId, LocalDate dataPagamento, String keycloakId)`:**
- Assinatura alterada: adicionado parametro `keycloakId`
- Define `usuarioConfirmacao` no boleto a partir do keycloakId
- Se `dataPagamento` posterior ao vencimento:
  - Status: `VENCIDO`
  - Marco: `BOLETO_VENCIDO`
  - E-mail: aviso de pagamento em atraso
- Caso contrario:
  - Status: `PAGO`
  - Marco: `PAGAMENTO_CONFIRMADO`
  - E-mail: confirmacao de pagamento

**Metodo novo `vencerBoleto(Boleto boleto)`:**
- Chamado pelo job P11-B
- Transicao `PENDENTE -> VENCIDO`
- Registra marco `BOLETO_VENCIDO` com observacao da data do vencimento automatico
- Envia e-mail ao RT e RU comunicando o vencimento e orientando a gerar novo boleto

### BoletoController.java — alteracoes

**Endpoint `POST /boletos/licenciamento/{licenciamentoId}`:**
- Adicionado parametro `@AuthenticationPrincipal Jwt jwt`
- Passa `jwt.getSubject()` (sub do Keycloak) para `boletoService.create(...)`

**Endpoint `PATCH /boletos/{boletoId}/confirmar-pagamento`:**
- Adicionado parametro `@AuthenticationPrincipal Jwt jwt`
- Passa `jwt.getSubject()` para `boletoService.confirmarPagamento(...)`

### BoletoJobService.java — novo

```java
@Scheduled(cron = "0 0 2 * * *")
public void vencerBoletosExpirados()
```

- Executa todos os dias as 02:00 (horario do servidor)
- Busca via `BoletoRepository.findBoletosVencidos(LocalDate.now())` todos os boletos com `status = PENDENTE` e `dtVencimento < hoje`
- Para cada boleto encontrado: chama `boletoService.vencerBoleto(boleto)` em transacao individual
- Loga: contagem de boletos processados, ID de cada boleto vencido, erros individuais sem abortar o loop
- `@EnableScheduling` ja estava habilitado em `SolApplication.java` — nenhuma configuracao adicional necessaria

---

## Endpoints REST envolvidos

| Metodo | Endpoint | Papel | Descricao |
|---|---|---|---|
| `GET` | `/boletos/licenciamento/{id}` | Autenticado | Lista boletos de um licenciamento |
| `POST` | `/boletos/licenciamento/{id}` | ADMIN, ANALISTA, INSPETOR | Gera novo boleto (P11-A passo 1) |
| `PATCH` | `/boletos/{id}/confirmar-pagamento` | ADMIN, ANALISTA | Confirma pagamento manual (P11-A passo 2) |

**Parametro opcional em `confirmar-pagamento`:**
```
?dataPagamento=2026-04-15   (formato ISO: yyyy-MM-dd)
```
Se omitido, usa `LocalDate.now()`.

---

## Regras de negocio implementadas

| Codigo | Regra | Onde |
|---|---|---|
| RN-090 | Nao pode existir boleto PENDENTE ativo para o mesmo licenciamento | `create()` |
| RN-091 | Licenciamento isento de taxa nao gera boleto | `create()` |
| RN-095 | Confirmacao de pagamento exige que o boleto esteja PENDENTE | `confirmarPagamento()` |
| — | Pagamento apos vencimento registra status VENCIDO (nao PAGO) | `confirmarPagamento()` |
| — | Job vence automaticamente boletos expirados diariamente as 02:00 | `BoletoJobService` |

---

## Transicoes de estado do boleto

```
             create()
  [novo]  ----------->  PENDENTE
                            |
          confirmarPagamento(dataDentroDoVencimento)
                            |
                           PAGO

  PENDENTE -----------------> VENCIDO
             - confirmarPagamento(dataAposVencimento)
             - BoletoJobService (job automatico)
```

---

## Marcos de processo registrados

| Marco | Quando |
|---|---|
| `BOLETO_GERADO` | Ao criar um boleto via `create()` |
| `PAGAMENTO_CONFIRMADO` | Ao confirmar pagamento dentro do prazo |
| `BOLETO_VENCIDO` | Ao confirmar pagamento apos vencimento OU ao executar o job P11-B |

---

## Como executar no servidor

### Pre-requisitos

1. Servico `SOL-Backend` em execucao (ou parado — o script reinicia automaticamente)
2. Oracle XE acessivel em `localhost:1521/XEPDB1`
3. `sqlplus` disponivel no PATH (para limpeza dos dados de teste) — opcional
4. Maven em `C:\tools\maven\bin\mvn.cmd`
5. JDK 21 em `C:\tools\jdk21`

### Comando de execucao

No servidor (via Claude Code ou terminal local):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
C:\SOL\infra\scripts\sprint11-deploy.ps1
```

### Passos executados pelo script

| Passo | Acao | Criterio de sucesso |
|---|---|---|
| 1 | Build Maven (`mvn clean package -DskipTests`) | Exit code 0 |
| 2 | Restart servico `SOL-Backend` | Servico reiniciado |
| 3 | Health check (`/actuator/health`) | `status: UP` em ate 60s |
| 4 | Autenticacao | Tokens JWT para `admin` e `analista1` obtidos |
| 5 | Limpeza preventiva SQL | Dados de testes anteriores removidos |
| 6 | **Fluxo A** — PAGO | Ver abaixo |
| 7 | **Fluxo B** — VENCIDO | Ver abaixo |
| 8 | RN-091 aviso | Verificacao manual indicada |
| 9 | Limpeza pos-teste | Dados removidos do banco |

### Detalhamento Fluxo A (Passo 6)

1. Cria licenciamento com `isentoTaxa=false` e `areaConstruida=300`
2. Faz upload de PDF minimo
3. Submete, distribui e inicia analise (estado `EM_ANALISE`)
4. `POST /boletos/licenciamento/{id}` — espera status `PENDENTE` no retorno
5. Verifica marco `BOLETO_GERADO` em `/licenciamentos/{id}/marcos`
6. `PATCH /boletos/{boletoId}/confirmar-pagamento?dataPagamento=<hoje>` — espera status `PAGO`
7. Verifica marco `PAGAMENTO_CONFIRMADO`
8. Tenta gerar segundo boleto — espera HTTP 400/422 (RN-090)

### Detalhamento Fluxo B (Passo 7)

1. Cria segundo licenciamento e coloca em `EM_ANALISE`
2. Gera boleto — espera status `PENDENTE`
3. Verifica marco `BOLETO_GERADO`
4. `PATCH /boletos/{boletoId}/confirmar-pagamento?dataPagamento=<hoje+35dias>` — espera status `VENCIDO` (data apos vencimento de 30 dias)
5. Verifica marco `BOLETO_VENCIDO`
6. Tenta confirmar novamente o mesmo boleto VENCIDO — espera HTTP 400/422 (RN-095)

---

## Verificacao manual do job P11-B

O job `BoletoJobService.vencerBoletosExpirados()` executa automaticamente as 02:00. Para forcar a execucao em teste:

**Opcao 1 — via banco (simular boleto vencido):**
```sql
-- Cria boleto com vencimento no passado
UPDATE sol.boleto
SET dt_vencimento = SYSDATE - 1
WHERE id = <id_do_boleto>;
```
Aguardar o job executar as 02:00 ou reiniciar o servico e aguardar (o Spring dispara na proxima janela do cron).

**Opcao 2 — via logs:**
```
grep "[P11-B]" C:\SOL\logs\sol-backend.log
```
Saida esperada apos execucao:
```
[P11-B] Processando 1 boleto(s) expirado(s) em 2026-04-01.
[P11-B] Boleto ID 42 vencido (licenciamento ID 65).
[P11-B] Conclusao: 1 vencido(s), 0 erro(s).
```

---

## Numeracao das regras de negocio de P11

De acordo com o documento `Requisitos_P11_PagamentoBoleto_StackAtual.md`:

- RN-090 a RN-108 cobrem o processo P11 completo
- Esta sprint implementa: RN-090, RN-091, RN-095 (comportamento central do ciclo de vida do boleto)
- As demais RNs (integracao PROCERGS/CNAB 240, geracao de PDF da guia, multa por atraso) sao marcadas como `stub` no `calcularTaxa()` e serao implementadas em sprint futura

---

## Notas tecnicas

- `LicenciamentoService` esta injetado no `BoletoService` para futuras verificacoes de estado do licenciamento (ex.: bloquear geracao de boleto se licenciamento cancelado). Nesta sprint o campo e declarado mas nao utilizado diretamente nos metodos — sem impacto em runtime.
- O metodo `vencerBoleto()` e `@Transactional` para garantir atomicidade: se a gravacao do marco falhar, o status do boleto tambem e revertido.
- O loop do job captura excecoes por boleto individualmente: um erro em um boleto nao interrompe o processamento dos demais.
- Emails sao enviados via `EmailService.notificarAsync()` — nao bloqueiam a transacao principal.
