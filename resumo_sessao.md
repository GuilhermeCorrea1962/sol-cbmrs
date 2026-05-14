# Resumo da Sessão — SOL CBM-RS
**Data:** 2026-05-14

---

## 1. Migração de Dados Oracle (CONCLUÍDA)

### O que foi feito
- Executado o script `infra/scripts/migrar-licenciamento-final.sql` para migrar dados da produção legada para o novo schema Oracle XE 21c (XEPDB1, schema `SOL`).
- O `COMMIT` final foi problemático via pipe do PowerShell (ORA-02185: `COMMIT; EXIT;` enviados na mesma linha). Solução: usar backtick-n do PowerShell (`"COMMIT`nEXIT"`) para separar os comandos.
- Commit correspondente: `d0679a2`.

### Contagens finais verificadas (todas corretas)
| Tabela | Registros |
|---|---|
| USUARIO | 56.963 |
| ENDERECO | 57.749 |
| LICENCIAMENTO | 57.749 |
| BOLETO | 127.566 |
| MARCO_PROCESSO | 2.357.839 |
| ARQUIVO_ED | 100.543 |
| ROTINA_EXECUCAO | 4.526 |

---

## 2. Bug de Paginação no Componente de Licenciamentos (EM ANDAMENTO)

### Sintoma
O seletor "itens por página" (5/10/20) do `mat-paginator` na tela de licenciamentos não tinha efeito — a página sempre carregava com 10 itens independentemente da seleção.

### Causa raiz identificada
O `mat-paginator` estava dentro de um bloco `@if (!loading() && licenciamentos().length > 0)`, fazendo com que fosse **destruído e recriado** a cada carregamento. Ao ser recriado, ele perdia o estado de `pageSize` e emitia um evento `page` com os valores padrão, sobrescrevendo a seleção do usuário.

### Fix 1 (commit `b9c588e`)
- Alterado o `@if` de `!loading() && licenciamentos().length > 0` para `totalElements() > 0` — o paginator permanece vivo após o primeiro carregamento.
- Adicionado `[disabled]="loading()"` no paginator para bloquear interação durante carga.
- Tabela recebe `[style.opacity]` e `[style.pointer-events]` para feedback visual durante recarregamento.
- `sol-loading` alterado para mostrar apenas no carregamento inicial (`loading() && totalElements() === 0`).

### Fix 2 (commit `d0679a2`) — não confirmado pelo usuário
- Convertido `pageSize` e `currentPage` de propriedades simples para `signal()` para garantir reatividade e detecção de mudanças pelo Angular.
- Removido `[disabled]` do paginator (conflitava com o `[pageSize]` binding).
- Adicionado `console.log` diagnóstico no `onPage()` para rastrear eventos.

**Status:** Deploy realizado, aguardando confirmação do usuário de que o bug foi resolvido.

---

## 3. Recuperação do Ambiente Servidor (Windows Reinstalado)

O servidor `CBM-QCG-239` foi reinstalado e o ambiente SOL precisou ser recuperado do zero. Foi feita uma análise de lacunas completa.

### 3.1 Oracle XE 21c

#### Problema de conectividade Easy Connect
- `sqlnet.ora` (`C:\OracleXE21c\homes\OraDB21Home2\network\admin\sqlnet.ora`) continha apenas:
  ```
  SQLNET.AUTHENTICATION_SERVICES= (NTS)
  ```
- Faltava a linha `NAMES.DIRECTORY_PATH= (EZCONNECT, TNSNAMES)`, impedindo o uso da sintaxe `//host:port/service`.

#### Decisão
Adicionar a linha ao `sqlnet.ora`:
```
NAMES.DIRECTORY_PATH= (EZCONNECT, TNSNAMES)
```
O arquivo final deve ficar:
```
SQLNET.AUTHENTICATION_SERVICES= (NTS)
NAMES.DIRECTORY_PATH= (EZCONNECT, TNSNAMES)
```
**Status:** Arquivo aberto no Notepad no servidor, aguardando o usuário salvar.

#### Problema de `@` na senha via linha de comando
A senha `Sol@CBM2026` contém `@`, que o SQL*Plus interpreta como início do alias TNS, quebrando o parsing.
- **Workaround confirmado:** usar `sqlplus /nolog` e depois `CONNECT sol/"Sol@CBM2026"@//CBM-QCG-239:1521/xepdb1` dentro do SQL*Plus.
- Conectividade ao Oracle XEPDB1 confirmada via screenshot.

#### tnsnames.ora
- Contém apenas entrada para `XE` (CDB). Falta entrada para `XEPDB1`.
- **Decisão:** Adicionar alias `XEPDB1` apontando para `CBM-QCG-239:1521`.
- **Status:** Pendente (após fix do sqlnet.ora).

---

## 4. Tarefas Pendentes (Checklist de Recuperação do Ambiente)

| # | Tarefa | Status |
|---|---|---|
| 1 | Editar `sqlnet.ora` — adicionar `NAMES.DIRECTORY_PATH= (EZCONNECT, TNSNAMES)` | **EM ANDAMENTO** (arquivo aberto no Notepad) |
| 2 | Editar `tnsnames.ora` — adicionar alias `XEPDB1` → `CBM-QCG-239:1521` | Pendente |
| 3 | Testar Easy Connect: `sqlplus sol/"Sol@CBM2026"@XEPDB1` | Pendente |
| 4 | Instalar MinIO — `.\infra\scripts\03-minio.ps1` | Pendente |
| 5 | Criar buckets MinIO — `.\infra\scripts\07-minio-buckets.ps1` | Pendente |
| 6 | Instalar MailHog — `.\infra\scripts\08.5-mailhog.ps1` | Pendente |
| 7 | Verificar NSSM — `nssm version`; registrar SOL-Backend, SOL-Nginx, SOL-Keycloak | Pendente |
| 8 | Build frontend produção — `npm run build:prod` em `C:\SOL\frontend` | Pendente |
| 9 | Verificação completa — `.\infra\scripts\08-verify-all.ps1` | Pendente |
| 10 | Confirmar fix de paginação — testar seleção de 20 itens/página na lista de licenciamentos | Pendente |

---

## 5. Decisões e Restrições de Segurança (Permanecem em Vigor)

- **Não alterar dados do Oracle** sem antes explicar o que será alterado.
- **Preservar backups** antes de modificar arquivos de configuração.
- **Antes de alterar ou apagar qualquer coisa:** explicar claramente, criar backup, identificar dependências.

---

## 6. Informações de Configuração do Ambiente

### Credenciais e Portas (conforme `README-infra.md`)
| Serviço | Porta | Usuário / Senha |
|---|---|---|
| Nginx | 80 | — |
| SOL Backend | 8080 | JWT via Keycloak |
| Keycloak | 8180 | admin / `Keycloak@Admin2026` |
| Oracle XE | 1521 | sol / `Sol@CBM2026` |
| MinIO API | 9000 | sol-app / `SolApp@Minio2026` |
| MinIO Console | 9001 | solminio / `MinIO@SOL2026` |

### Serviços Windows (NSSM)
`SOL-Backend`, `SOL-Nginx`, `SOL-Keycloak`, `SOL-MinIO`

### Buckets MinIO esperados
`sol-arquivos`, `sol-appci`, `sol-guias`, `sol-laudos`, `sol-decisoes`, `sol-temp`

---

## 7. Branch de Desenvolvimento

Todas as alterações de código desta sessão estão no branch:
```
claude/review-sol-setup-597qi
```
Commits relevantes: `b9c588e` (Fix 1 paginação), `d0679a2` (Fix 2 paginação + migração).
