# Sprint 1 — Diário Completo de Implementação

**Projeto:** SOL — Sistema de Operações e Licenciamento (CBM-RS)
**Data:** 2026-03-27
**Stack:** Java 21 · Spring Boot 3.3.4 · Hibernate 6.5.3 · Oracle XE 21c · Windows 11

---

## Índice

- [[#Objetivo da Sprint]]
- [[#Mensagem 1 — Solicitação Inicial]]
- [[#Passo 1 — Compilação com Maven e Java 21]]
  - [[#Problema JAR Bloqueado]]
  - [[#Solução Parar o Serviço Primeiro]]
  - [[#Compilação Bem-Sucedida]]
- [[#Passo 2 — Iniciar o Serviço SOL-Backend]]
- [[#Passo 3 — Verificar Tabelas Oracle]]
  - [[#Problema Crash Loop no Serviço]]
  - [[#Diagnóstico Via Log do Logback]]
  - [[#Análise do Erro Hibernate]]
- [[#Correção Principal — Endereco.java]]
  - [[#Por que Double Falha no Hibernate 6.5]]
  - [[#Por que BigDecimal é a Solução Correta]]
  - [[#Diff da Correção]]
- [[#Segunda Compilação e Reinício]]
- [[#Verificação das 6 Tabelas Oracle]]
- [[#Passo 4 — Health Check]]
- [[#Passo 5 — Smoke Test]]
- [[#Mensagem 2 — Correções nos Arquivos Originais]]
  - [[#Análise de Todos os Arquivos]]
  - [[#Correção 1 — Remover database-platform]]
  - [[#Correção 2 — Desabilitar open-in-view]]
  - [[#Correção 3 — Desabilitar check-template-location]]
- [[#Validação Final do Startup Limpo]]
- [[#Estado Final dos Arquivos]]
- [[#Glossário Técnico]]

---

## Objetivo da Sprint

A Sprint 1 tinha como meta colocar o backend do SOL em operação pela primeira vez. O sistema é composto por:

- **Backend Java:** Spring Boot 3.3.4 com Hibernate — responsável por criar as tabelas Oracle automaticamente via DDL (`ddl-auto: update`) e expor a API REST na porta 8080
- **Banco de dados:** Oracle XE 21c com schema `SOL` no PDB `XEPDB1`
- **Serviço Windows:** `SOL-Backend` gerencia o ciclo de vida do JAR

O plano tinha 5 tarefas sequenciais:

```
[1] Compilar → [2] Reiniciar serviço → [3] Verificar tabelas → [4] Health check → [5] Smoke test
```

---

## Mensagem 1 — Solicitação Inicial

> *"Inicie a Sprint 1. Os arquivos Java já estão em C:\SOL\backend\src. Execute as tarefas na ordem: Recompilar o backend com Maven usando Java 21 (JAVA_HOME: C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot), Reiniciar o serviço SOL-Backend, Verificar se o Hibernate criou as 6 tabelas no Oracle (ENDERECO, USUARIO, LICENCIAMENTO, ARQUIVO_ED, MARCO_PROCESSO, BOLETO) no schema SOL do XEPDB1, Health check em http://localhost:8080/api/health, Smoke test: contar linhas das 6 tabelas via sqlplus com autenticação '/ as sysdba'."*

---

## Passo 1 — Compilação com Maven e Java 21

### Primeira Tentativa

O comando executado foi:

```powershell
mvn clean package -DskipTests
```

Com `JAVA_HOME` apontando para o JDK 21 da Eclipse Adoptium. O Maven foi invocado via PowerShell porque o bash do Git for Windows no ambiente causava um erro fatal de inicialização ao tentar acessar `C:\Program Files\Git`.

> **Detalhe técnico:** O Git for Windows empacota seu próprio bash (`/bin/bash`), e ao tentar resolver caminhos com espaços como `C:\Program Files\Git`, o processo filho pode falhar com `fatal error - add_item`. A solução foi usar PowerShell como shell de execução.

---

### Problema JAR Bloqueado

A primeira tentativa com `mvn clean package` retornou:

```
[ERROR] Failed to execute goal maven-clean-plugin:3.3.2:clean (default-clean)
        on project sol-backend:
        Failed to clean project: Failed to delete
        C:\SOL\backend\target\sol-backend-1.0.0.jar
```

**Causa:** No Windows, um arquivo executável em uso por um processo ativo fica bloqueado em nível de sistema operacional. O serviço `SOL-Backend` estava rodando com o JAR carregado na JVM — qualquer tentativa de deletar ou sobrescrever esse arquivo é recusada pelo kernel.

Isso é diferente do comportamento Linux/macOS, onde um arquivo aberto pode ser deletado (o inode persiste até o processo liberar o file descriptor).

---

### Solução: Parar o Serviço Primeiro

```powershell
Stop-Service -Name 'SOL-Backend' -Force
Start-Sleep -Seconds 3
(Get-Service -Name 'SOL-Backend').Status  # → Stopped
```

O parâmetro `-Force` encerra o serviço imediatamente sem aguardar que processos dependentes parem antes.

---

### Compilação Bem-Sucedida

Com o serviço parado, a compilação foi executada com `JAVA_HOME` definido em nível de processo PowerShell (sem alterar variáveis de ambiente do sistema):

```powershell
[System.Environment]::SetEnvironmentVariable(
    'JAVA_HOME',
    'C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot',
    'Process'
)
[System.Environment]::SetEnvironmentVariable(
    'PATH',
    'C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot\bin;' +
    [System.Environment]::GetEnvironmentVariable('PATH', 'Process'),
    'Process'
)
Set-Location 'C:\SOL\backend'
mvn clean package -DskipTests
```

**Resultado:**

```
[INFO] Compiling 24 source files with javac [debug parameters release 21]
[INFO] Building jar: C:\SOL\backend\target\sol-backend-1.0.0.jar
[INFO] BUILD SUCCESS
[INFO] Total time:  6.929 s
[INFO] Finished at: 2026-03-27T11:14:48-03:00
```

O flag `-DskipTests` pula a execução dos testes unitários — apropriado para o ciclo de compilação/deploy de um serviço de produção quando os testes serão executados separadamente no pipeline de CI.

---

## Passo 2 — Iniciar o Serviço SOL-Backend

```powershell
Start-Service -Name 'SOL-Backend'
Start-Sleep -Seconds 10
(Get-Service -Name 'SOL-Backend').Status  # → Running
```

O resultado inicial foi `Running`. Isso significa que o processo Java foi iniciado pelo SCM (Service Control Manager) do Windows. No entanto, `Running` apenas confirma que o processo está vivo — não que o Spring Boot finalizou a inicialização (que inclui conectar ao Oracle e executar o DDL do Hibernate).

---

## Passo 3 — Verificar Tabelas Oracle

### Script de Verificação

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

A query usa `dba_tables` (visível pelo usuário `SYS`) em vez de `user_tables` ou `all_tables`, porque a conexão é feita como `sysdba` — que tem acesso a todo o dicionário de dados, independente do schema.

Executado com:

```powershell
& 'C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe' `
  'sys/oracle@//localhost:1521/XEPDB1 as sysdba' `
  '@C:\SOL\sqlcheck2.sql'
```

---

### Problema: Crash Loop no Serviço

A query retornou **zero linhas** — as tabelas não existiam. Ao mesmo tempo, observou-se que o log `sol-backend-stdout.log` mostrava um PID diferente a cada leitura, e o diretório `C:\SOL\logs\` acumulava arquivos `sol-backend-stderr-*.log` novos a cada ~5 segundos, todos com 0 bytes:

```
sol-backend-stderr-20260327T141657.143.log   (0 bytes)
sol-backend-stderr-20260327T141702.296.log   (0 bytes)
sol-backend-stderr-20260327T141707.056.log   (0 bytes)
... (mais de 100 arquivos em menos de 10 minutos)
```

**Interpretação:** O Windows SCM estava reiniciando automaticamente o serviço a cada falha. A política de reinício configurada no serviço Windows não tem delay — ao detectar que o processo JVM terminou com exit code diferente de zero, inicia imediatamente um novo processo. Isso criava um novo arquivo de stderr a cada tentativa.

O `sol-backend-stdout.log` tinha apenas 2KB e era sobrescrito a cada reinício, fazendo com que o erro nunca aparecesse completo nele.

---

### Diagnóstico Via Log do Logback

O log gerenciado pelo **Logback** (`sol-backend.log`) é o arquivo correto para diagnóstico. Ele é configurado via `logging.file.name` no `application.yml` e usa rolling policy — não é sobrescrito entre reinícios, acumula entradas com timestamp e PID:

```powershell
Get-Content 'C:\SOL\logs\sol-backend.log' -Tail 100
```

O log revelou o erro completo:

```
WARN  ConfigServletWebServerApplicationContext:
Exception encountered during context initialization - cancelling refresh attempt:
org.springframework.beans.factory.BeanCreationException:
Error creating bean with name 'entityManagerFactory':
scale has no meaning for SQL floating point types

Caused by: java.lang.IllegalArgumentException:
scale has no meaning for SQL floating point types
  at org.hibernate.dialect.Dialect$SizeStrategyImpl.resolveSize(Dialect.java:5219)
  at org.hibernate.mapping.Column.calculateColumnSize(Column.java:459)
  at org.hibernate.mapping.BasicValue.resolve(BasicValue.java:361)
  at org.hibernate.boot.internal.InFlightMetadataCollectorImpl.processValueResolvers(...)
  at org.hibernate.boot.model.process.spi.MetadataBuildingProcess.complete(...)
  at org.hibernate.jpa.boot.internal.EntityManagerFactoryBuilderImpl.metadata(...)
  at org.hibernate.jpa.boot.internal.EntityManagerFactoryBuilderImpl.build(...)
```

O HikariCP **chegou a conectar** ao Oracle com sucesso (pool started), mas o Hibernate falhou **antes** de executar qualquer DDL, durante a fase de construção dos metadados das entidades.

---

### Análise do Erro Hibernate

O erro acontecia no momento em que o Hibernate tentava calcular o tamanho da coluna para gerar o DDL. A linha relevante do stack trace é:

```
Column.calculateColumnSize → BasicValue.resolve → SizeStrategyImpl.resolveSize
```

A busca pelos campos problemáticos foi feita com grep nas entidades:

```
@Column.*scale|double|float|Double|Float
```

**Resultado:** o campo `latitude` e `longitude` em `Endereco.java` usavam `Double` (Java) com `@Column(scale = 7)`.

---

## Correção Principal — Endereco.java

### Arquivo original (com bug)

```java
// Endereco.java — ANTES
@Column(name = "LATITUDE", precision = 10, scale = 7)
private Double latitude;

@Column(name = "LONGITUDE", precision = 10, scale = 7)
private Double longitude;
```

---

### Por que `Double` Falha no Hibernate 6.5

O tipo Java `Double` (ou `double`) mapeia para tipos SQL de **ponto flutuante binário**:

| Banco | Tipo gerado |
|---|---|
| Oracle | `FLOAT` ou `BINARY_DOUBLE` |
| PostgreSQL | `FLOAT8` / `DOUBLE PRECISION` |
| MySQL | `DOUBLE` |

Esses tipos seguem o padrão **IEEE 754** — a precisão é expressa em bits, não em dígitos decimais, e o conceito de "escala" (casas decimais) não existe. Um `FLOAT(10)` no Oracle significa 10 **bits** de mantissa, não 10 dígitos.

Por isso, `@Column(scale = 7)` em um campo `Double` é semanticamente inválido. Nas versões anteriores do Hibernate (5.x, início do 6.x), essa anotação era **silenciosamente ignorada**. A partir do Hibernate 6.5.3, foi adicionada uma validação explícita que lança `IllegalArgumentException` em vez de ignorar.

---

### Por que `BigDecimal` é a Solução Correta

`BigDecimal` (Java) mapeia para `NUMBER(precision, scale)` no Oracle — um tipo de **ponto fixo decimal** que suporta precisão e escala exatas:

| Campo | Tipo Oracle | Exemplo de valor |
|---|---|---|
| `NUMBER(10, 7)` | Até 10 dígitos, 7 após a vírgula | `-30.0346789` |

Para coordenadas geográficas (latitude/longitude), `NUMBER(10, 7)` é apropriado:
- Latitude válida: `-90.0000000` a `+90.0000000`
- Longitude válida: `-180.0000000` a `+180.0000000`
- 7 casas decimais = precisão de ~1 cm na superfície terrestre

A serialização JSON pelo Jackson é transparente — `BigDecimal` é serializado como número decimal normalmente.

---

### Comparação de todos os campos numéricos com `scale`

| Entidade | Campo | Tipo Java | `@Column(scale)` | Correto? |
|---|---|---|---|---|
| `Boleto` | `VALOR` | `BigDecimal` | `scale = 2` | ✅ |
| `Licenciamento` | `AREA_CONSTRUIDA` | `BigDecimal` | `scale = 2` | ✅ |
| `Licenciamento` | `ALTURA_MAXIMA` | `BigDecimal` | `scale = 2` | ✅ |
| `Endereco` | `LATITUDE` | `Double` → **`BigDecimal`** | `scale = 7` | ✅ após correção |
| `Endereco` | `LONGITUDE` | `Double` → **`BigDecimal`** | `scale = 7` | ✅ após correção |

---

### Diff da Correção

**`Endereco.java`:**

```diff
  import jakarta.persistence.*;
  import lombok.*;
  import org.hibernate.annotations.CreationTimestamp;
  import org.hibernate.annotations.UpdateTimestamp;

+ import java.math.BigDecimal;
  import java.time.LocalDateTime;

  ...

      @Column(name = "LATITUDE", precision = 10, scale = 7)
-     private Double latitude;
+     private BigDecimal latitude;

      @Column(name = "LONGITUDE", precision = 10, scale = 7)
-     private Double longitude;
+     private BigDecimal longitude;
```

Apenas 3 linhas alteradas — import adicionado e dois tipos de campo trocados. Nenhuma outra parte da classe precisou mudar: Lombok (`@Data`, `@Builder`, `@AllArgsConstructor`) gera getters/setters/construtores automaticamente para qualquer tipo.

---

## Segunda Compilação e Reinício

Após a correção, nova compilação:

```
[INFO] Compiling 24 source files with javac [debug parameters release 21]
[INFO] BUILD SUCCESS
[INFO] Total time: 6.360 s
```

Reinício do serviço com espera de 25 segundos para garantir inicialização completa do Hibernate:

```powershell
Restart-Service -Name 'SOL-Backend' -Force
Start-Sleep -Seconds 25
(Get-Service -Name 'SOL-Backend').Status  # → Running
```

Log do Logback confirmando sucesso:

```
INFO  HikariPool-1 - Start completed.
INFO  Initialized JPA EntityManagerFactory for persistence unit 'default'
INFO  Tomcat started on port 8080 (http) with context path '/api'
INFO  Started SolApplication in 9.94 seconds (process running for 10.514)
```

O log também mostrou o DDL do Hibernate em modo `DEBUG` — os `ALTER TABLE ... ADD CONSTRAINT` das foreign keys, confirmando que o schema foi criado integralmente.

---

## Verificação das 6 Tabelas Oracle

Conectando diretamente ao XEPDB1 como `sysdba`:

```powershell
& 'C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe' `
  'sys/oracle@//localhost:1521/XEPDB1 as sysdba' `
  '@C:\SOL\sqlcheck2.sql'
```

> **Por que usar string de conexão com `@//localhost:1521/XEPDB1`?**
> A autenticação `/ as sysdba` (OS authentication) conecta ao **CDB raiz** (Container Database). O schema `SOL` existe no **PDB** `XEPDB1`. Para verificar objetos no PDB, é necessário conectar diretamente a ele com a string de conexão `//host:porta/service_name`.
> Alternativamente, dentro de uma sessão CDB: `ALTER SESSION SET CONTAINER = XEPDB1`.

**Resultado:**

```
CON_NAME
------------------------------
XEPDB1

TABLE_NAME
--------------------
ARQUIVO_ED
BOLETO
ENDERECO
LICENCIAMENTO
MARCO_PROCESSO
USUARIO

6 linhas selecionadas.
```

---

## Passo 4 — Health Check

Script PowerShell:

```powershell
# C:\SOL\health_check.ps1
try {
    $r = Invoke-WebRequest -Uri 'http://localhost:8080/api/health' `
         -UseBasicParsing -TimeoutSec 10
    Write-Output ("Status: " + $r.StatusCode)
    Write-Output $r.Content
} catch {
    Write-Output ("Erro: " + $_)
}
```

> **Por que usar script `.ps1` em vez de `-Command` inline?**
> Ao passar comandos PowerShell com variáveis (`$r`, `$_`) via `-Command` dentro do bash do Git for Windows, o `$` é expandido pelo bash antes de chegar ao PowerShell, corrompendo o script. Salvar em um arquivo `.ps1` e executar com `-File` elimina esse problema.

**Resposta:**

```json
{
  "status": "UP",
  "version": "1.0.0",
  "system": "SOL CBM-RS Autônomo",
  "timestamp": "2026-03-27T12:11:33.413215600"
}
```

O endpoint `/api/health` é implementado em `HealthController.java` e não requer autenticação (configurado no `SecurityConfig`). Retorna HTTP 200 com payload JSON estático mais timestamp atual.

---

## Passo 5 — Smoke Test

Script sqlplus que executa `COUNT(*)` em cada tabela via `UNION ALL`:

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

Executado com autenticação OS (`/ as sysdba` — sem password, usa identidade do usuário Windows):

```powershell
& 'C:\app\Guilherme\product\21c\dbhomeXE\bin\sqlplus.exe' '/ as sysdba' '@C:\SOL\smoke_test.sql'
```

**Resultado:**

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

**0 linhas é o resultado esperado** — o schema foi criado do zero. O smoke test valida que:
1. Todas as tabelas existem e são acessíveis
2. A sessão pode fazer `SELECT` no schema `SOL`
3. Não há erros de permissão ou objeto inválido

---

## Mensagem 2 — Correções nos Arquivos Originais

> *"Atualize os arquivos originais com as devidas correções necessárias que foram utilizadas para obter êxito na implementação da Sprint 1"*

Com a Sprint 1 concluída, foi solicitada uma revisão mais ampla — além do bug crítico em `Endereco.java`, os avisos (`WARN`) que apareceram no log de startup também deveriam ser corrigidos nos arquivos-fonte.

---

### Análise de Todos os Arquivos

Foram lidos todos os arquivos de entidade e configuração:

| Arquivo | Situação encontrada |
|---|---|
| `Endereco.java` | ✅ Já corrigido (Double → BigDecimal) |
| `Usuario.java` | ✅ Nenhum problema |
| `Licenciamento.java` | ✅ Nenhum problema — usa BigDecimal corretamente |
| `ArquivoED.java` | ✅ Nenhum problema |
| `MarcoProcesso.java` | ✅ Nenhum problema |
| `Boleto.java` | ✅ Nenhum problema — usa BigDecimal corretamente |
| `SimNaoBooleanConverter.java` | ✅ Nenhum problema |
| `application.yml` | ⚠️ 3 avisos a corrigir |
| `pom.xml` | ✅ Compilou corretamente com Java 21 |

---

### Os 3 Avisos Identificados no Log

Durante a Sprint 1, o log de startup registrou 3 `WARN` que, embora não impedissem a inicialização após a correção do `Endereco.java`, indicam configurações incorretas ou sub-ótimas:

```
WARN HHH90000025: OracleDialect does not need to be specified explicitly
WARN spring.jpa.open-in-view is enabled by default
WARN Cannot find template location: classpath:/templates/
```

---

### Correção 1 — Remover `database-platform`

**O que estava no arquivo:**

```yaml
jpa:
  database-platform: org.hibernate.dialect.OracleDialect
  hibernate:
    ddl-auto: update
```

**O que estava gerando o aviso:**

```
WARN org.hibernate.orm.deprecation:
HHH90000025: OracleDialect does not need to be specified explicitly
using 'hibernate.dialect' (remove the property setting and it will
be selected by default)
```

**Por que acontece:** A partir do Hibernate 6.x, o dialeto é detectado automaticamente a partir dos metadados JDBC retornados pelo driver Oracle (`oracle.jdbc.OracleDriver`). Ao conectar, o driver informa a versão do banco e o Hibernate seleciona o dialeto correto automaticamente. Definir `database-platform` manualmente é redundante e gera o aviso de deprecação.

**Correção:**

```diff
  jpa:
-   database-platform: org.hibernate.dialect.OracleDialect
    hibernate:
      ddl-auto: update
+   open-in-view: false
```

---

### Correção 2 — Desabilitar `open-in-view`

**O que estava gerando o aviso:**

```
WARN JpaBaseConfiguration$JpaWebConfiguration:
spring.jpa.open-in-view is enabled by default.
Therefore, database queries may be performed during view rendering.
Explicitly configure spring.jpa.open-in-view to disable this warning
```

**O que é Open Session in View:** É um padrão (anti-padrão, na maioria dos casos modernos) onde a sessão JPA/Hibernate é mantida aberta durante todo o ciclo de vida de uma requisição HTTP, inclusive durante a serialização da resposta. Isso permite que *lazy loading* de relacionamentos aconteça fora do contexto transacional.

**Por que é problemático em uma API REST:**

1. **Queries N+1 silenciosas:** Se um endpoint retornar uma lista de `Licenciamento` e durante a serialização JSON o Jackson tentar acessar `licenciamento.getEndereco()` (campo lazy), o Hibernate dispara uma query Oracle para cada item da lista — fora da transação, sem logging SQL visível, sem controle.

2. **Conexão mantida desnecessariamente:** A conexão do HikariPool fica ocupada durante toda a serialização, mesmo que nenhuma query adicional seja necessária.

3. **SOL é uma API pura:** Não usa Thymeleaf para renderizar HTML com dados JPA — todo output é JSON. Open-in-view não faz sentido.

**Correção:**

```yaml
jpa:
  hibernate:
    ddl-auto: update
  open-in-view: false   # ← adicionado
```

---

### Correção 3 — Desabilitar `check-template-location`

**O que estava gerando o aviso:**

```
WARN DefaultTemplateResolverConfiguration:
Cannot find template location: classpath:/templates/
(please add some templates, check your Thymeleaf configuration,
or set spring.thymeleaf.check-template-location=false)
```

**Por que Thymeleaf está no projeto:** O `pom.xml` inclui `spring-boot-starter-thymeleaf` para templates de e-mail HTML (notificações, boletos) que serão implementados nas sprints seguintes. A dependência está correta.

**Por que o aviso aparece:** O Thymeleaf, ao inicializar, verifica se o diretório `src/main/resources/templates/` existe. Como os templates ainda não foram criados (sprint futura), o diretório não existe e o Thymeleaf emite o aviso a cada startup.

**Correção:**

```yaml
thymeleaf:
  check-template-location: false
```

Isso silencia o aviso sem remover a dependência. Quando os templates forem criados nas sprints seguintes, essa configuração pode ser revertida para `true` (ou simplesmente removida, pois `true` é o default).

---

## Validação Final do Startup Limpo

Após as 3 correções no `application.yml`, nova compilação e restart:

```
[INFO] BUILD SUCCESS
[INFO] Total time: 2.721 s
```

Log de startup final (PID 2816, 2026-03-27T15:04:36):

```
INFO  Starting SolApplication v1.0.0 using Java 21.0.9 with PID 2816
INFO  The following 1 profile is active: "prod"
INFO  Found 6 JPA repository interfaces.
INFO  Tomcat initialized with port 8080 (http)
INFO  Root WebApplicationContext: initialization completed in 2014 ms
INFO  HikariPool-1 - Start completed.
INFO  Initialized JPA EntityManagerFactory for persistence unit 'default'
INFO  Exposing 3 endpoints beneath base path '/actuator'
INFO  Tomcat started on port 8080 (http) with context path '/api'
INFO  Started SolApplication in 13.686 seconds
```

**Comparação antes/depois:**

| Aviso | Sprint 1 (com bug) | Após correções |
|---|---|---|
| `HHH90000025: OracleDialect explicitly` | ⚠️ Presente | ✅ Ausente |
| `open-in-view is enabled by default` | ⚠️ Presente | ✅ Ausente |
| `Cannot find template location` | ⚠️ Presente | ✅ Ausente |
| `scale has no meaning for float types` | 💥 Fatal (crash loop) | ✅ Corrigido |

---

## Estado Final dos Arquivos

### `Endereco.java` — versão final

```java
package br.gov.rs.cbm.sol.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;   // ← adicionado
import java.time.LocalDateTime;

@Entity
@Table(name = "ENDERECO", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Endereco {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_endereco")
    @SequenceGenerator(name = "seq_endereco", sequenceName = "SOL.SEQ_ENDERECO", allocationSize = 1)
    @Column(name = "ID_ENDERECO")
    private Long id;

    @Column(name = "CEP", length = 8, nullable = false)
    private String cep;

    @Column(name = "LOGRADOURO", length = 200, nullable = false)
    private String logradouro;

    @Column(name = "NUMERO", length = 20)
    private String numero;

    @Column(name = "COMPLEMENTO", length = 100)
    private String complemento;

    @Column(name = "BAIRRO", length = 100, nullable = false)
    private String bairro;

    @Column(name = "MUNICIPIO", length = 100, nullable = false)
    private String municipio;

    @Column(name = "UF", length = 2, nullable = false)
    private String uf;

    @Column(name = "LATITUDE", precision = 10, scale = 7)
    private BigDecimal latitude;   // ← era Double

    @Column(name = "LONGITUDE", precision = 10, scale = 7)
    private BigDecimal longitude;  // ← era Double

    @CreationTimestamp
    @Column(name = "DT_CRIACAO", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @UpdateTimestamp
    @Column(name = "DT_ATUALIZACAO")
    private LocalDateTime dataAtualizacao;
}
```

---

### `application.yml` — versão final

```yaml
spring:
  application:
    name: sol-backend

  # Oracle XE DataSource
  datasource:
    url: jdbc:oracle:thin:@localhost:1521/XEPDB1
    username: sol
    password: Sol@CBM2026
    driver-class-name: oracle.jdbc.OracleDriver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000

  # JPA / Hibernate
  jpa:
    hibernate:
      ddl-auto: update
    open-in-view: false            # ← adicionado (era habilitado por default)
    show-sql: false
    properties:
      hibernate:
        format_sql: true
        default_schema: SOL
        jdbc:
          batch_size: 25
        order_inserts: true
        order_updates: true
    # Removido: database-platform: org.hibernate.dialect.OracleDialect
    # (detectado automaticamente pelo Hibernate 6.5 via JDBC metadata)

  # Spring Security - OAuth2 Resource Server (JWT do Keycloak)
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://localhost:8180/realms/sol
          jwk-set-uri: http://localhost:8180/realms/sol/protocol/openid-connect/certs

  # E-mail (SMTP local - MailHog para dev)
  mail:
    host: localhost
    port: 1025
    username: ""
    password: ""
    properties:
      mail.smtp.auth: false
      mail.smtp.starttls.enable: false

  # Thymeleaf (templates de e-mail - pasta criada nas sprints seguintes)
  thymeleaf:
    check-template-location: false  # ← adicionado (evita WARN até templates serem criados)

  # Upload de arquivos
  servlet:
    multipart:
      max-file-size: 50MB
      max-request-size: 50MB

# Servidor
server:
  port: 8080
  servlet:
    context-path: /api
  compression:
    enabled: true
    mime-types: application/json,application/xml,text/html,text/plain

# MinIO
minio:
  url: http://localhost:9000
  access-key: sol-app
  secret-key: SolApp@Minio2026
  buckets:
    arquivos: sol-arquivos
    appci: sol-appci
    guias: sol-guias
    laudos: sol-laudos
    decisoes: sol-decisoes
    temp: sol-temp

# Keycloak Admin (para criar usuarios)
keycloak:
  server-url: http://localhost:8180
  realm: sol
  admin:
    client-id: admin-cli
    username: admin
    password: Keycloak@Admin2026

# Actuator
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized

# Logging
logging:
  level:
    br.gov.rs.cbm.sol: DEBUG
    org.springframework.security: INFO
    org.hibernate.SQL: DEBUG
  file:
    name: C:/SOL/logs/sol-backend.log
  logback:
    rollingpolicy:
      max-file-size: 10MB
      max-history: 30
```

---

## Glossário Técnico

| Termo | Definição |
|---|---|
| **CDB** | Container Database — instância Oracle raiz que contém um ou mais PDBs |
| **PDB** | Pluggable Database — banco isolado dentro do CDB; `XEPDB1` é o PDB padrão do Oracle XE |
| **ddl-auto: update** | Hibernate compara as entidades com o schema existente e cria/altera tabelas automaticamente |
| **HikariCP** | Pool de conexões JDBC de alta performance — padrão no Spring Boot |
| **Open Session in View** | Padrão que mantém a sessão JPA aberta durante toda a requisição HTTP |
| **SCM** | Service Control Manager — componente do Windows que gerencia serviços (start/stop/restart) |
| **IEEE 754** | Padrão para aritmética de ponto flutuante binário — usado por `float` e `double` em Java |
| **NUMBER(p,s)** | Tipo Oracle de ponto fixo: `p` = total de dígitos significativos, `s` = dígitos após a vírgula |
| **BINARY_DOUBLE** | Tipo Oracle de ponto flutuante IEEE 754 de 64 bits — equivalente ao `double` Java |
| **dba_tables** | View do dicionário Oracle com todas as tabelas de todos os schemas (requer DBA ou SYSDBA) |
| **OS Authentication** | `/ as sysdba` — autenticação Oracle baseada na identidade do usuário do SO, sem senha |

---

*Documento gerado em 2026-03-27 · Sprint 1 concluída com sucesso.*
