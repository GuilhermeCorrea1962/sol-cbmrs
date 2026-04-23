# Sprint 1 — Implementação e Diagnóstico do Backend SOL

**Data:** 2026-03-27
**Sistema:** SOL — Sistema de Operações e Licenciamento (CBM-RS)
**Ambiente:** Windows 11 Pro, Oracle XE 21c, Java 21, Spring Boot 3.3.4

---

## Índice

- [[#Visão Geral]]
- [[#Pré-requisitos do Ambiente]]
- [[#Tarefa 1 — Compilação com Maven e Java 21]]
- [[#Tarefa 2 — Gerenciamento do Serviço Windows]]
- [[#Problema 1 — Crash Loop do Backend]]
- [[#Diagnóstico do Erro Hibernate]]
- [[#Correção — BigDecimal em Endereco.java]]
- [[#Tarefa 3 — Verificação das Tabelas Oracle]]
- [[#Tarefa 4 — Health Check]]
- [[#Tarefa 5 — Smoke Test]]
- [[#Resultado Final]]
- [[#Lições Aprendidas]]

---

## Visão Geral

A Sprint 1 teve como objetivo colocar o backend do SOL em operação pela primeira vez, validando a compilação, a criação automática do schema Oracle pelo Hibernate e a disponibilidade da API.

O fluxo planejado era simples, mas revelou um bug de compatibilidade entre a versão do Hibernate (6.5.3.Final) e as anotações JPA nas entidades. O processo de diagnóstico e correção está documentado integralmente abaixo.

---

## Pré-requisitos do Ambiente

| Componente | Detalhe |
|---|---|
| Java | Eclipse Adoptium JDK 21.0.9 |
| JAVA_HOME | `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot` |
| Maven | Embutido no projeto (`mvnw` ou `mvn` no PATH) |
| Oracle XE | 21c Express Edition, porta 1521 |
| PDB alvo | `XEPDB1` |
| Schema da aplicação | `SOL` |
| sqlplus | `C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe` |
| Serviço Windows | `SOL-Backend` |
| JAR gerado | `C:\SOL\backend\target\sol-backend-1.0.0.jar` |
| Log Logback | `C:\SOL\logs\sol-backend.log` |
| Log stdout do serviço | `C:\SOL\logs\sol-backend-stdout.log` |

---

## Tarefa 1 — Compilação com Maven e Java 21

### Objetivo

Recompilar o projeto Maven garantindo o uso do Java 21, gerando o JAR de produção em `target/`.

### Problema inicial — JAR bloqueado pelo serviço em execução

A primeira tentativa de compilação com `mvn clean package -DskipTests` falhou porque o `clean` não conseguiu deletar o JAR existente:

```
[ERROR] Failed to execute goal maven-clean-plugin:3.3.2:clean:
Failed to delete C:\SOL\backend\target\sol-backend-1.0.0.jar
```

**Causa:** o serviço `SOL-Backend` estava em execução e mantinha o arquivo JAR aberto (lock do sistema operacional Windows).

**Solução:** parar o serviço antes de compilar.

```powershell
Stop-Service -Name 'SOL-Backend' -Force
```

### Compilação bem-sucedida

Com o serviço parado, a compilação foi executada via PowerShell com `JAVA_HOME` configurado explicitamente:

```powershell
[System.Environment]::SetEnvironmentVariable('JAVA_HOME',
  'C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot', 'Process')
[System.Environment]::SetEnvironmentVariable('PATH',
  'C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot\bin;' +
  [System.Environment]::GetEnvironmentVariable('PATH','Process'), 'Process')
Set-Location 'C:\SOL\backend'
mvn clean package -DskipTests
```

**Resultado:**

```
[INFO] Compiling 24 source files with javac [debug parameters release 21]
[INFO] BUILD SUCCESS
[INFO] Total time: 6.929 s
[INFO] Finished at: 2026-03-27T11:14:48-03:00
```

> 24 classes compiladas com target `release 21` em menos de 7 segundos.

---

## Tarefa 2 — Gerenciamento do Serviço Windows

### Estrutura do serviço

O backend é gerenciado como um serviço Windows chamado `SOL-Backend`. Os comandos básicos são:

```powershell
# Parar
Stop-Service -Name 'SOL-Backend' -Force

# Iniciar
Start-Service -Name 'SOL-Backend'

# Reiniciar
Restart-Service -Name 'SOL-Backend' -Force

# Verificar status
(Get-Service -Name 'SOL-Backend').Status
```

### Comportamento esperado na inicialização

Após `Start-Service`, o Spring Boot precisa de ~10-25 segundos para:
1. Inicializar o contexto Spring
2. Conectar ao HikariCP (pool de conexões Oracle)
3. Executar o DDL automático do Hibernate (`ddl-auto: update`)
4. Subir o Tomcat na porta 8080

---

## Problema 1 — Crash Loop do Backend

### Sintoma

Após o primeiro start do serviço, o backend entrou em **crash loop** — reiniciando automaticamente a cada ~5 segundos. Isso foi identificado por:

1. **Múltiplos arquivos de log stderr** criados em sequência:
   ```
   sol-backend-stderr-20260327T141657.143.log  (0 bytes)
   sol-backend-stderr-20260327T141702.296.log  (0 bytes)
   sol-backend-stderr-20260327T141707.056.log  (0 bytes)
   ... (mais de 100 arquivos em menos de 10 minutos)
   ```

2. **PID diferente** a cada leitura do log `sol-backend-stdout.log` — cada leitura mostrava um novo processo iniciando.

3. O log `sol-backend-stdout.log` (2KB apenas) era sobrescrito a cada reinício, cortando o conteúdo antes do erro.

### Investigação

O arquivo de log correto para diagnóstico era o **log do Logback** (`sol-backend.log`), não o stdout do serviço. O Logback acumula entradas de múltiplas execuções sem sobrescrever.

```powershell
Get-Content 'C:\SOL\logs\sol-backend.log' -Tail 100
```

---

## Diagnóstico do Erro Hibernate

### Stack trace completo

```
WARN  ConfigServletWebServerApplicationContext :
Exception encountered during context initialization - cancelling refresh attempt:
org.springframework.beans.factory.BeanCreationException:
Error creating bean with name 'entityManagerFactory':
scale has no meaning for SQL floating point types

Caused by: java.lang.IllegalArgumentException:
scale has no meaning for SQL floating point types
  at org.hibernate.dialect.Dialect$SizeStrategyImpl.resolveSize(Dialect.java:5219)
  at org.hibernate.mapping.Column.calculateColumnSize(Column.java:459)
  at org.hibernate.mapping.BasicValue.resolve(BasicValue.java:361)
  ...
```

### Causa raiz

O **Hibernate 6.5** introduziu uma validação mais estrita das anotações `@Column`. Em versões anteriores, era aceito usar `precision` e `scale` em qualquer campo numérico. A partir da 6.5, isso lança `IllegalArgumentException` para tipos de ponto flutuante SQL (`FLOAT`, `DOUBLE`, `REAL`), pois esses tipos **não possuem escala definida pelo usuário** — a precisão é determinada pelo hardware.

### Campo problemático identificado

Em `Endereco.java`, os campos de coordenadas geográficas usavam `Double` (Java) com `scale` definido:

```java
// ANTES — INCORRETO para Hibernate 6.5+
@Column(name = "LATITUDE", precision = 10, scale = 7)
private Double latitude;

@Column(name = "LONGITUDE", precision = 10, scale = 7)
private Double longitude;
```

O tipo `Double` mapeia para `FLOAT` ou `DOUBLE PRECISION` no Oracle — um tipo de ponto flutuante binário que **não tem conceito de escala decimal**. A anotação `scale = 7` é semanticamente inválida para esse tipo.

### Por que os outros campos não causaram erro?

Os demais campos com `precision` e `scale` no projeto usavam `BigDecimal`, que é correto:

| Entidade | Campo | Tipo Java | Correto? |
|---|---|---|---|
| `Boleto` | `VALOR` | `BigDecimal` | ✅ |
| `Licenciamento` | `AREA_CONSTRUIDA` | `BigDecimal` | ✅ |
| `Licenciamento` | `ALTURA_MAXIMA` | `BigDecimal` | ✅ |
| `Endereco` | `LATITUDE` | `Double` | ❌ Bug |
| `Endereco` | `LONGITUDE` | `Double` | ❌ Bug |

`BigDecimal` mapeia para `NUMBER(precision, scale)` no Oracle — um tipo de ponto fixo que suporta escala exata. `Double` não.

---

## Correção — BigDecimal em Endereco.java

### Arquivo alterado

`C:\SOL\backend\src\main\java\br\gov\rs\cbm\sol\entity\Endereco.java`

### Diff da correção

```diff
+ import java.math.BigDecimal;
  import java.time.LocalDateTime;

  ...

  @Column(name = "LATITUDE", precision = 10, scale = 7)
- private Double latitude;
+ private BigDecimal latitude;

  @Column(name = "LONGITUDE", precision = 10, scale = 7)
- private Double longitude;
+ private BigDecimal longitude;
```

### Impacto da mudança

- **No banco:** Hibernate criará a coluna como `NUMBER(10,7)` em vez de `FLOAT` — armazenamento de precisão exata para coordenadas GPS (ex: `-30.0346789`).
- **Na API:** Serialização JSON permanece transparente — Jackson serializa `BigDecimal` como número decimal normalmente.
- **Compatibilidade Lombok:** `@Data`, `@Builder`, `@AllArgsConstructor` continuam funcionando sem alteração.

### Recompilação após correção

```
[INFO] Compiling 24 source files with javac [debug parameters release 21]
[INFO] BUILD SUCCESS
[INFO] Total time: 6.360 s
```

---

## Tarefa 3 — Verificação das Tabelas Oracle

### Confirmação via log do Hibernate

Após reiniciar o serviço com o JAR corrigido, o log mostrou o DDL sendo executado:

```
INFO  HikariPool-1 - Start completed.
INFO  Initialized JPA EntityManagerFactory for persistence unit 'default'
INFO  Tomcat started on port 8080 (http) with context path '/api'
INFO  Started SolApplication in 9.94 seconds
```

O Hibernate também logou os `ALTER TABLE` das foreign keys (com `show-sql: false` no `application.yml` o DDL ainda aparece no log em nível `DEBUG`).

### Script sqlplus de verificação

```sql
-- C:\SOL\sqlcheck2.sql
SET PAGESIZE 50 FEEDBACK ON HEADING ON VERIFY OFF
SHOW CON_NAME;
SELECT table_name
  FROM dba_tables
 WHERE owner = 'SOL'
   AND table_name IN (
     'ENDERECO','USUARIO','LICENCIAMENTO',
     'ARQUIVO_ED','MARCO_PROCESSO','BOLETO'
   )
 ORDER BY table_name;
EXIT;
```

Executado com:

```powershell
& 'C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe' `
  'sys/oracle@//localhost:1521/XEPDB1 as sysdba' `
  '@C:\SOL\sqlcheck2.sql'
```

### Resultado

```
CON_NAME
------------------------------
XEPDB1

TABLE_NAME
--------------------------------------------------------------------------------
ARQUIVO_ED
BOLETO
ENDERECO
LICENCIAMENTO
MARCO_PROCESSO
USUARIO

6 linhas selecionadas.
```

> Todas as 6 tabelas criadas com sucesso no schema `SOL` do PDB `XEPDB1`.

---

## Tarefa 4 — Health Check

### Endpoint

```
GET http://localhost:8080/api/health
```

### Script de verificação

```powershell
# C:\SOL\health_check.ps1
$r = Invoke-WebRequest -Uri 'http://localhost:8080/api/health' `
     -UseBasicParsing -TimeoutSec 10
Write-Output ("Status: " + $r.StatusCode)
Write-Output $r.Content
```

### Resposta

```
Status: 200
{
  "status": "UP",
  "version": "1.0.0",
  "system": "SOL CBM-RS Autônomo",
  "timestamp": "2026-03-27T12:11:33.413215600"
}
```

> HTTP 200 — aplicação operacional.

---

## Tarefa 5 — Smoke Test

### Objetivo

Confirmar que todas as 6 tabelas estão acessíveis e respondem a queries, mesmo que vazias.

### Script sqlplus

```sql
-- C:\SOL\smoke_test.sql
SET PAGESIZE 50 FEEDBACK OFF HEADING ON VERIFY OFF LINESIZE 50
ALTER SESSION SET CONTAINER=XEPDB1;
SELECT 'ENDERECO'       AS tabela, COUNT(*) AS linhas FROM SOL.ENDERECO       UNION ALL
SELECT 'USUARIO'        AS tabela, COUNT(*) AS linhas FROM SOL.USUARIO         UNION ALL
SELECT 'LICENCIAMENTO'  AS tabela, COUNT(*) AS linhas FROM SOL.LICENCIAMENTO   UNION ALL
SELECT 'ARQUIVO_ED'     AS tabela, COUNT(*) AS linhas FROM SOL.ARQUIVO_ED      UNION ALL
SELECT 'MARCO_PROCESSO' AS tabela, COUNT(*) AS linhas FROM SOL.MARCO_PROCESSO  UNION ALL
SELECT 'BOLETO'         AS tabela, COUNT(*) AS linhas FROM SOL.BOLETO;
EXIT;
```

Executado com autenticação `/ as sysdba` (OS authentication):

```powershell
& 'C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe' '/ as sysdba' '@C:\SOL\smoke_test.sql'
```

### Resultado

```
TABELA           LINHAS
--------------   ------
ENDERECO              0
USUARIO               0
LICENCIAMENTO         0
ARQUIVO_ED            0
MARCO_PROCESSO        0
BOLETO                0
```

> 0 linhas em todas as tabelas — **esperado** para um schema recém-criado. O importante é que as queries executaram sem erro.

---

## Resultado Final

| # | Tarefa | Resultado |
|---|---|---|
| 1 | Recompilar Maven/Java 21 | ✅ BUILD SUCCESS — 24 fontes, 6.9s |
| 2 | Reiniciar SOL-Backend | ✅ Running (após correção do bug) |
| 3 | 6 tabelas Oracle criadas | ✅ 6/6 confirmadas no XEPDB1 |
| 4 | Health check | ✅ HTTP 200 `{"status":"UP"}` |
| 5 | Smoke test — contagem | ✅ 6 tabelas acessíveis, 0 linhas |

---

## Lições Aprendidas

### 1. Hibernate 6.5 é mais estrito com tipos numéricos

A migração do Hibernate 6.x trouxe validações que antes eram silenciosas. `@Column(scale = N)` em um campo `double`/`float` era ignorado nas versões anteriores — na 6.5 lança exceção na inicialização. **Regra prática:** use `BigDecimal` para qualquer campo monetário ou que precise de escala decimal exata; use `Double` apenas quando a precisão IEEE 754 for suficiente e sem `scale`.

### 2. O log correto para diagnóstico de startup é o Logback, não o stdout do serviço

O `sol-backend-stdout.log` é sobrescrito a cada reinício do serviço Windows. Para diagnosticar erros de inicialização, o arquivo `sol-backend.log` (gerenciado pelo Logback com rolling policy) acumula entradas de múltiplas execuções e é muito mais útil.

### 3. Parar o serviço antes de recompilar no Windows

No Windows, um JAR em execução fica bloqueado pelo processo. O `mvn clean` falha ao tentar deletar o arquivo. O fluxo correto é sempre: **stop → compile → start**.

### 4. Conectar ao XEPDB1 com string de conexão explícita

`/ as sysdba` conecta ao CDB raiz. Para verificar objetos no PDB `XEPDB1`, usar:
```
sys/oracle@//localhost:1521/XEPDB1 as sysdba
```
Ou, dentro de uma sessão CDB, executar:
```sql
ALTER SESSION SET CONTAINER = XEPDB1;
```

---

## Configuração de Referência

### application.yml (trecho relevante)

```yaml
spring:
  datasource:
    url: jdbc:oracle:thin:@localhost:1521/XEPDB1
    username: sol
    password: Sol@CBM2026
    driver-class-name: oracle.jdbc.OracleDriver

  jpa:
    database-platform: org.hibernate.dialect.OracleDialect
    hibernate:
      ddl-auto: update
    properties:
      hibernate:
        default_schema: SOL

server:
  port: 8080
  servlet:
    context-path: /api

logging:
  file:
    name: C:/SOL/logs/sol-backend.log
```

### Entidades JPA da Sprint 1

```
br.gov.rs.cbm.sol.entity
├── Endereco.java       → tabela ENDERECO
├── Usuario.java        → tabela USUARIO
├── Licenciamento.java  → tabela LICENCIAMENTO
├── ArquivoED.java      → tabela ARQUIVO_ED
├── MarcoProcesso.java  → tabela MARCO_PROCESSO
└── Boleto.java         → tabela BOLETO
```

---

*Documento gerado em 2026-03-27 após conclusão da Sprint 1.*
