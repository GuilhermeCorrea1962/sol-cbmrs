SET PAGESIZE 300
SET LINESIZE 220
SET FEEDBACK OFF
COLUMN constraint_name FORMAT A30
COLUMN column_name     FORMAT A30
COLUMN search_condition FORMAT A200

-- Check constraint que está falhando
SELECT constraint_name, search_condition
FROM all_constraints
WHERE owner = 'SOL'
  AND constraint_type = 'C'
  AND constraint_name = 'SYS_C0095637';

-- Todas as check constraints do schema SOL
SELECT c.table_name, c.constraint_name, c.search_condition
FROM all_constraints c
WHERE c.owner = 'SOL' AND c.constraint_type = 'C'
ORDER BY c.table_name, c.constraint_name;

-- Emails duplicados em CBM_USUARIO
SELECT TXT_EMAIL, COUNT(*) AS QTD
FROM CBM_USUARIO
GROUP BY TXT_EMAIL
HAVING COUNT(*) > 1
ORDER BY 2 DESC
FETCH FIRST 20 ROWS ONLY;

-- Quantos usuários têm email duplicado
SELECT COUNT(*) AS USUARIOS_COM_EMAIL_DUPLICADO
FROM CBM_USUARIO u
WHERE EXISTS (
  SELECT 1 FROM CBM_USUARIO u2
  WHERE u2.TXT_EMAIL = u.TXT_EMAIL
    AND u2.NRO_INT_USUARIO != u.NRO_INT_USUARIO
);

EXIT;
