-- ============================================================
-- comparar-schemas.sql
-- Execução: sqlplus P_CBM_SOLCBM_AD/GuiGui1267@//localhost:1521/XEPDB1 @comparar-schemas.sql
-- Propósito: inspecionar tabelas do SOL original para avaliar
--            viabilidade de migração para o schema SOL novo.
-- ============================================================

SET PAGESIZE 300
SET LINESIZE 220
SET FEEDBACK OFF
SET ECHO OFF
COLUMN owner          FORMAT A25
COLUMN table_name     FORMAT A35
COLUMN column_name    FORMAT A35
COLUMN data_type      FORMAT A20
COLUMN nullable       FORMAT A8
COLUMN num_rows       FORMAT 999999999

PROMPT
PROMPT ============================================================
PROMPT  1. TABELAS DO USUARIO P_CBM_SOLCBM_AD (schema producao)
PROMPT ============================================================
SELECT table_name, num_rows
FROM user_tables
ORDER BY table_name;

PROMPT
PROMPT ============================================================
PROMPT  2. COLUNAS DAS TABELAS-CHAVE DO SOL ORIGINAL
PROMPT     (Busca por nomes similares aos do novo sistema)
PROMPT ============================================================

PROMPT
PROMPT --- TABELA: similar a LICENCIAMENTO / PPCI ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%LICEN%'
       OR table_name LIKE '%PPCI%'
       OR table_name LIKE '%PROCESSO%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT --- TABELA: similar a USUARIO / PESSOA ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%USUAR%'
       OR table_name LIKE '%PESSOA%'
       OR table_name LIKE '%CIDADAO%'
       OR table_name LIKE '%RESPONSAVEL%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT --- TABELA: similar a ENDERECO ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%ENDER%'
       OR table_name LIKE '%LOCALIZ%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT --- TABELA: similar a ARQUIVO / DOCUMENTO ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%ARQUI%'
       OR table_name LIKE '%DOCUM%'
       OR table_name LIKE '%ALFRESCO%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT --- TABELA: similar a BOLETO / TAXA / FINANCEIRO ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%BOLETO%'
       OR table_name LIKE '%TAXA%'
       OR table_name LIKE '%FINANC%'
       OR table_name LIKE '%PAGTO%'
       OR table_name LIKE '%PAGAMENTO%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT --- TABELA: similar a MARCO / HISTORICO / LOG ---
SELECT table_name, column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name IN (
    SELECT table_name FROM user_tables
    WHERE table_name LIKE '%MARCO%'
       OR table_name LIKE '%HISTOR%'
       OR table_name LIKE '%TRAMIT%'
       OR table_name LIKE '%LOG%'
       OR table_name LIKE '%ANDAMENTO%'
)
ORDER BY table_name, column_id;

PROMPT
PROMPT ============================================================
PROMPT  3. CONTAGEM DE REGISTROS NAS TABELAS ENCONTRADAS
PROMPT ============================================================
-- Gera e executa COUNTs dinamicamente
BEGIN
  FOR t IN (SELECT table_name FROM user_tables ORDER BY table_name) LOOP
    EXECUTE IMMEDIATE 'SELECT ''' || t.table_name || ''', COUNT(*) FROM ' || t.table_name
      INTO :dummy; -- placeholder; use abaixo
  END LOOP;
END;
/

-- Abordagem estática mais simples: lista num_rows (pode estar desatualizado)
SELECT table_name,
       NVL(num_rows, -1) AS num_rows_estatistica,
       last_analyzed
FROM user_tables
ORDER BY table_name;

PROMPT
PROMPT ============================================================
PROMPT  4. SEQUENCES EXISTENTES
PROMPT ============================================================
SELECT sequence_name, last_number, increment_by
FROM user_sequences
ORDER BY sequence_name;

PROMPT
PROMPT ============================================================
PROMPT  5. OUTROS SCHEMAS COM TABELAS DO SOL (acesso cruzado)
PROMPT ============================================================
SELECT DISTINCT owner, COUNT(*) AS qtd_tabelas
FROM all_tables
WHERE owner NOT IN ('SYS','SYSTEM','MDSYS','CTXSYS','XDB','WMSYS','DBSNMP',
                    'ORDSYS','ORDPLUGINS','OUTLN','APEX_PUBLIC_USER','ANONYMOUS',
                    'AUDSYS','GSMADMIN_INTERNAL','GGSYS','OJVMSYS','ORDDATA',
                    'LBACSYS','REMOTE_SCHEDULER_AGENT','DVSYS','DVF',
                    'SYS$UMF','APPQOSSYS','DBSFWUSER')
GROUP BY owner
ORDER BY owner;

EXIT;
