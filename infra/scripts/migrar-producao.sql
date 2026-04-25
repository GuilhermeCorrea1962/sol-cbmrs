-- ============================================================
-- migrar-producao.sql  —  SOL CBM-RS
-- Migração P_CBM_SOLCBM_AD  →  SOL (novo sistema)
--
-- Execução (no servidor):
--   sqlplus P_CBM_SOLCBM_AD/GuiGui1267@//localhost:1521/XEPDB1 @migrar-producao.sql
--
-- IMPORTANTE: execute o PASSO 0 (diagnóstico) antes do PASSO 1.
-- Confirme os mapeamentos de status/tipo antes de migrar.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET PAGESIZE 200
SET LINESIZE 200
SET FEEDBACK ON

-- ============================================================
-- PASSO 0 — Diagnóstico: valores distintos de campos enum
--           (execute primeiro para confirmar mapeamentos)
-- ============================================================

PROMPT === PASSO 0: Valores distintos de TP_SITUACAO em CBM_LICENCIAMENTO ===
SELECT TP_SITUACAO, COUNT(*) AS QTD FROM CBM_LICENCIAMENTO GROUP BY TP_SITUACAO ORDER BY 2 DESC;

PROMPT === TP_LICENCIAMENTO em CBM_LICENCIAMENTO ===
SELECT TP_LICENCIAMENTO, COUNT(*) AS QTD FROM CBM_LICENCIAMENTO GROUP BY TP_LICENCIAMENTO ORDER BY 2 DESC;

PROMPT === TP_ARQUIVO em CBM_ARQUIVO (top 30) ===
SELECT TP_ARQUIVO, COUNT(*) AS QTD FROM CBM_ARQUIVO GROUP BY TP_ARQUIVO ORDER BY 2 DESC FETCH FIRST 30 ROWS ONLY;

PROMPT === TP_SITUACAO em CBM_BOLETO ===
SELECT TP_SITUACAO, COUNT(*) AS QTD FROM CBM_BOLETO GROUP BY TP_SITUACAO ORDER BY 2 DESC;

PROMPT === TP_SITUACAO em CBM_ROTINA ===
SELECT TP_SITUACAO, COUNT(*) AS QTD FROM CBM_ROTINA GROUP BY TP_SITUACAO ORDER BY 2 DESC;

PROMPT === Amostras de CBM_LICENCIAMENTO_MARCO.NRO_INT_PARAMETRO_MARCO ===
SELECT pm.NRO_INT_PARAMETRO_MARCO, pm.TXT_DESCRICAO, COUNT(*) AS QTD
FROM CBM_LICENCIAMENTO_MARCO lm
JOIN CBM_PARAMETRO_MARCO pm ON pm.NRO_INT_PARAMETRO_MARCO = lm.NRO_INT_PARAMETRO_MARCO
GROUP BY pm.NRO_INT_PARAMETRO_MARCO, pm.TXT_DESCRICAO
ORDER BY 3 DESC FETCH FIRST 30 ROWS ONLY;

-- ============================================================
-- PASSO 1 — Migração de USUARIO
--           Origem: CBM_USUARIO
--           Destino: SOL.USUARIO
-- ============================================================
PROMPT === PASSO 1: Migrando USUARIO ===

INSERT INTO SOL.USUARIO (
    ID_USUARIO,
    CPF,
    NOME,
    EMAIL,
    TELEFONE,
    TIPO_USUARIO,
    STATUS_CADASTRO,
    ATIVO,
    DT_CRIACAO,
    DT_ATUALIZACAO
)
SELECT
    u.NRO_INT_USUARIO,
    REGEXP_REPLACE(u.TXT_CPF, '[^0-9]', ''),        -- remove pontos/traços do CPF
    u.NOME_USUARIO,
    u.TXT_EMAIL,
    u.TXT_TELEFONE1,
    -- TIPO_USUARIO: no sistema novo é determinado pelo papel no processo.
    -- CBM_USUARIO não tem tipo diretamente; assume CIDADAO como default.
    -- RTs serão identificados pela existência de registro em CBM_RESPONSAVEL_TECNICO.
    CASE
        WHEN EXISTS (
            SELECT 1 FROM CBM_RESPONSAVEL_TECNICO rt
            WHERE rt.NRO_INT_USUARIO = u.NRO_INT_USUARIO AND ROWNUM = 1
        ) THEN 'RT'
        ELSE 'CIDADAO'
    END AS TIPO_USUARIO,
    -- STATUS_CADASTRO: TP_STATUS 1=ativo, outros=inativo/pendente
    CASE u.TP_STATUS
        WHEN 1 THEN 'ATIVO'
        ELSE 'INCOMPLETO'
    END AS STATUS_CADASTRO,
    'S',                                              -- ATIVO = sim
    CAST(u.CTR_DTH_INC AS DATE),
    CAST(u.CTR_DTH_ATU AS DATE)
FROM CBM_USUARIO u
WHERE NOT EXISTS (
    SELECT 1 FROM SOL.USUARIO s WHERE s.ID_USUARIO = u.NRO_INT_USUARIO
);

PROMPT Usuarios inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 2 — Migração de ENDERECO (dos licenciamentos)
--           Origem: CBM_LICENCIAMENTO → CBM_LOCALIZACAO
--                   → CBM_ENDERECO_LICENCIAMENTO
--           Destino: SOL.ENDERECO
-- ============================================================
PROMPT === PASSO 2: Migrando ENDERECO (de licenciamentos) ===

INSERT INTO SOL.ENDERECO (
    ID_ENDERECO,
    CEP,
    LOGRADOURO,
    NUMERO,
    COMPLEMENTO,
    BAIRRO,
    MUNICIPIO,
    UF,
    LATITUDE,
    LONGITUDE,
    DT_CRIACAO,
    DT_ATUALIZACAO
)
SELECT
    loc.NRO_INT_LOCALIZACAO,
    REGEXP_REPLACE(loc.TXT_CEP, '[^0-9]', ''),       -- normaliza CEP para 8 dígitos
    el.TXT_LOGRADOURO,
    TO_CHAR(el.NRO_IMOVEL),                           -- número do imóvel (NUMBER→VARCHAR)
    loc.TXT_COMPLEMENTO,
    COALESCE(loc.TXT_BAIRRO, 'NAO INFORMADO'),
    el.TXT_CIDADE,
    el.SIGLA_UF,
    loc.NRO_LATITUDE_MAPA,
    loc.NRO_LONGITUDE_MAPA,
    CAST(loc.CTR_DTH_INC AS DATE),
    CAST(loc.CTR_DTH_ATU AS DATE)
FROM CBM_LICENCIAMENTO lic
JOIN CBM_LOCALIZACAO loc ON loc.NRO_INT_LOCALIZACAO = lic.NRO_INT_LOCALIZACAO
JOIN CBM_ENDERECO_LICENCIAMENTO el ON el.NRO_INT_ENDERECO_LICENCIAMENTO = loc.NRO_INT_ENDERECO_LICENCIAMENTO
WHERE lic.NRO_INT_LOCALIZACAO IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM SOL.ENDERECO e WHERE e.ID_ENDERECO = loc.NRO_INT_LOCALIZACAO
  );

PROMPT Enderecos inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 3 — Migração de LICENCIAMENTO
--           Origem: CBM_LICENCIAMENTO
--           Destino: SOL.LICENCIAMENTO
--
-- ATENÇÃO: confirme o mapeamento de TP_SITUACAO no PASSO 0
--          antes de executar. Ajuste o CASE abaixo conforme
--          os valores reais encontrados.
-- ============================================================
PROMPT === PASSO 3: Migrando LICENCIAMENTO ===

INSERT INTO SOL.LICENCIAMENTO (
    ID_LICENCIAMENTO,
    NUMERO_PPCI,
    TIPO,
    STATUS,
    AREA_CONSTRUIDA,
    ALTURA_MAXIMA,
    NUM_PAVIMENTOS,
    TIPO_OCUPACAO,
    USO_PREDOMINANTE,
    ID_ENDERECO,
    ID_RESPONSAVEL_TECNICO,
    ID_RESPONSAVEL_USO,
    ISENTO_TAXA,
    ATIVO,
    DT_CRIACAO,
    DT_ATUALIZACAO
)
SELECT
    lic.NRO_INT_LICENCIAMENTO,
    lic.COD_LICENCIAMENTO,                            -- número formatado (ex: A 00000001 AA 001)
    -- Tipo: ajuste conforme valores reais de TP_LICENCIAMENTO
    CASE
        WHEN UPPER(lic.TP_LICENCIAMENTO) LIKE '%PSPCIM%' THEN 'PSPCIM'
        ELSE 'PPCI'
    END AS TIPO,
    -- Status: AJUSTE este mapeamento conforme resultado do PASSO 0
    CASE UPPER(lic.TP_SITUACAO)
        WHEN 'SOLICITADO'           THEN 'ANALISE_PENDENTE'
        WHEN 'EM_ANALISE'           THEN 'EM_ANALISE'
        WHEN 'APROVADO_TAXA'        THEN 'APROVADO_TAXA'
        WHEN 'AGUARDANDO_PAGAMENTO' THEN 'AGUARDANDO_PAGAMENTO'
        WHEN 'PAGO'                 THEN 'PAGO'
        WHEN 'VISTORIA_PENDENTE'    THEN 'VISTORIA_PENDENTE'
        WHEN 'EM_VISTORIA'          THEN 'EM_VISTORIA'
        WHEN 'APROVADO'             THEN 'APROVADO'
        WHEN 'REPROVADO'            THEN 'REPROVADO'
        WHEN 'EXTINTO'              THEN 'EXTINTO'
        WHEN 'RECURSO'              THEN 'EM_RECURSO'
        ELSE 'ANALISE_PENDENTE'                       -- fallback seguro
    END AS STATUS,
    -- Área construída: vem de CBM_CARACTERISTICA (não disponível sem JOIN adicional)
    -- Preencher NULL por ora; atualizar em passo posterior se necessário
    NULL AS AREA_CONSTRUIDA,
    NULL AS ALTURA_MAXIMA,
    NULL AS NUM_PAVIMENTOS,
    NULL AS TIPO_OCUPACAO,
    NULL AS USO_PREDOMINANTE,
    -- Endereço: usa o ID da LOCALIZACAO (migrado no PASSO 2)
    lic.NRO_INT_LOCALIZACAO AS ID_ENDERECO,
    -- RT ativo do licenciamento
    (SELECT rt.NRO_INT_USUARIO
     FROM CBM_RESPONSAVEL_TECNICO rt
     WHERE rt.NRO_INT_LICENCIAMENTO = lic.NRO_INT_LICENCIAMENTO
       AND rt.IND_ACEITE = 'S'
       AND ROWNUM = 1) AS ID_RESPONSAVEL_TECNICO,
    -- RU ativo do licenciamento
    (SELECT ru.NRO_INT_USUARIO
     FROM CBM_RESPONSAVEL_USO ru
     WHERE ru.NRO_INT_LICENCIAMENTO = lic.NRO_INT_LICENCIAMENTO
       AND ru.IND_ACEITE = 'S'
       AND ROWNUM = 1) AS ID_RESPONSAVEL_USO,
    CASE lic.IND_ISENCAO WHEN 'S' THEN 'S' ELSE 'N' END AS ISENTO_TAXA,
    'S' AS ATIVO,
    CAST(lic.CTR_DTH_INC AS DATE),
    CAST(lic.CTR_DTH_ATU AS DATE)
FROM CBM_LICENCIAMENTO lic
WHERE NOT EXISTS (
    SELECT 1 FROM SOL.LICENCIAMENTO l WHERE l.ID_LICENCIAMENTO = lic.NRO_INT_LICENCIAMENTO
);

PROMPT Licenciamentos inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 4 — Migração de BOLETO
--           Origem: CBM_BOLETO + CBM_BOLETO_LICENCIAMENTO
--           Destino: SOL.BOLETO
-- ============================================================
PROMPT === PASSO 4: Migrando BOLETO ===

INSERT INTO SOL.BOLETO (
    ID_BOLETO,
    NOSSO_NUMERO,
    CODIGO_BARRAS,
    LINHA_DIGITAVEL,
    VALOR,
    DT_EMISSAO,
    DT_VENCIMENTO,
    DT_PAGAMENTO,
    STATUS,
    ID_LICENCIAMENTO,
    DT_CRIACAO,
    DT_ATUALIZACAO
)
SELECT
    b.NRO_INT_BOLETO,
    TO_CHAR(b.NRO_NOSSO_NUMERO),
    b.TXT_CODIGO_BARRAS,
    b.TXT_LINHA_DIGITAVEL,
    b.VALOR_NOMINAL,
    b.DATA_EMISSAO,
    b.DATA_VENCIMENTO,
    CAST(b.DATA_PAGAMENTO AS DATE),
    -- Status: ajuste conforme valores reais de TP_SITUACAO (PASSO 0)
    CASE b.TP_SITUACAO
        WHEN 1 THEN 'PENDENTE'
        WHEN 2 THEN 'PAGO'
        WHEN 3 THEN 'VENCIDO'
        WHEN 4 THEN 'CANCELADO'
        ELSE 'PENDENTE'
    END AS STATUS,
    bl.NRO_INT_LICENCIAMENTO AS ID_LICENCIAMENTO,
    CAST(b.CTR_DTH_INC AS DATE),
    CAST(b.CTR_DTH_ATU AS DATE)
FROM CBM_BOLETO b
JOIN CBM_BOLETO_LICENCIAMENTO bl ON bl.NRO_INT_BOLETO = b.NRO_INT_BOLETO
WHERE EXISTS (
    SELECT 1 FROM SOL.LICENCIAMENTO l WHERE l.ID_LICENCIAMENTO = bl.NRO_INT_LICENCIAMENTO
)
AND NOT EXISTS (
    SELECT 1 FROM SOL.BOLETO sb WHERE sb.ID_BOLETO = b.NRO_INT_BOLETO
);

PROMPT Boletos inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 5 — Migração de MARCO_PROCESSO
--           Origem: CBM_LICENCIAMENTO_MARCO + CBM_PARAMETRO_MARCO
--           Destino: SOL.MARCO_PROCESSO
-- ============================================================
PROMPT === PASSO 5: Migrando MARCO_PROCESSO ===

INSERT INTO SOL.MARCO_PROCESSO (
    ID_MARCO_PROCESSO,
    TIPO_MARCO,
    OBSERVACAO,
    ID_LICENCIAMENTO,
    ID_USUARIO,
    DT_MARCO
)
SELECT
    lm.NRO_INT_LIC_MARCO,
    -- TIPO_MARCO: mapeado a partir da descrição do parâmetro
    -- AJUSTE conforme resultado do PASSO 0 (descrições reais de CBM_PARAMETRO_MARCO)
    CASE
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%SOLICIT%'      THEN 'SOLICITACAO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%ANALISE%'      THEN 'ANALISE_INICIADA'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%APROVAD%'      THEN 'APROVACAO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%REPROVAD%'     THEN 'REPROVACAO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%VISTORI%'      THEN 'VISTORIA'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%RECURS%'       THEN 'RECURSO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%EXTINCT%'
          OR UPPER(pm.TXT_DESCRICAO) LIKE '%EXTIN%'        THEN 'EXTINCAO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%RENOV%'        THEN 'RENOVACAO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%BOLETO%'
          OR UPPER(pm.TXT_DESCRICAO) LIKE '%PAGTO%'
          OR UPPER(pm.TXT_DESCRICAO) LIKE '%PGTO%'         THEN 'PAGAMENTO'
        WHEN UPPER(pm.TXT_DESCRICAO) LIKE '%NOTIF%'        THEN 'NOTIFICACAO'
        ELSE 'OBSERVACAO'
    END AS TIPO_MARCO,
    lm.TXT_DESCRICAO || CASE WHEN lm.TXT_COMPLEMENTAR IS NOT NULL
                              THEN ' | ' || lm.TXT_COMPLEMENTAR ELSE '' END AS OBSERVACAO,
    lm.NRO_INT_LICENCIAMENTO,
    lm.NRO_INT_USUARIO_RESP,
    CAST(lm.DTH_MARCO AS DATE)
FROM CBM_LICENCIAMENTO_MARCO lm
JOIN CBM_PARAMETRO_MARCO pm ON pm.NRO_INT_PARAMETRO_MARCO = lm.NRO_INT_PARAMETRO_MARCO
WHERE EXISTS (
    SELECT 1 FROM SOL.LICENCIAMENTO l WHERE l.ID_LICENCIAMENTO = lm.NRO_INT_LICENCIAMENTO
)
AND NOT EXISTS (
    SELECT 1 FROM SOL.MARCO_PROCESSO m WHERE m.ID_MARCO_PROCESSO = lm.NRO_INT_LIC_MARCO
);

PROMPT Marcos inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 6 — Migração de ARQUIVO_ED
--           Origem: CBM_ARQUIVO (apenas arquivos de licenciamentos migrados)
--           ATENÇÃO: no sistema original arquivos não têm FK direta
--           para licenciamento. Migra somente os vinculados via
--           CBM_PRPCI ou CBM_APPCI (documentos principais).
-- ============================================================
PROMPT === PASSO 6: Migrando ARQUIVO_ED (PRPCI + APPCI) ===

INSERT INTO SOL.ARQUIVO_ED (
    ID_ARQUIVO_ED,
    NOME_ARQUIVO,
    IDENTIFICADOR_ALFRESCO,
    TIPO_ARQUIVO,
    ID_LICENCIAMENTO,
    DT_UPLOAD
)
-- Arquivos de PRPCI
SELECT
    a.NRO_INT_ARQUIVO,
    a.NOME_ARQUIVO,
    a.TXT_IDENTIFICADOR_ALFRESCO,
    'PRPCI' AS TIPO_ARQUIVO,
    p.NRO_INT_LICENCIAMENTO,
    CAST(a.CTR_DTH_INC AS DATE)
FROM CBM_PRPCI p
JOIN CBM_ARQUIVO a ON a.NRO_INT_ARQUIVO = p.NRO_INT_ARQUIVO
WHERE EXISTS (
    SELECT 1 FROM SOL.LICENCIAMENTO l WHERE l.ID_LICENCIAMENTO = p.NRO_INT_LICENCIAMENTO
)
AND NOT EXISTS (
    SELECT 1 FROM SOL.ARQUIVO_ED ae WHERE ae.ID_ARQUIVO_ED = a.NRO_INT_ARQUIVO
)
UNION ALL
-- Arquivos de APPCI
SELECT
    a.NRO_INT_ARQUIVO,
    a.NOME_ARQUIVO,
    a.TXT_IDENTIFICADOR_ALFRESCO,
    'APPCI' AS TIPO_ARQUIVO,
    ap.NRO_INT_LICENCIAMENTO,
    CAST(a.CTR_DTH_INC AS DATE)
FROM CBM_APPCI ap
JOIN CBM_ARQUIVO a ON a.NRO_INT_ARQUIVO = ap.NRO_INT_ARQUIVO
WHERE EXISTS (
    SELECT 1 FROM SOL.LICENCIAMENTO l WHERE l.ID_LICENCIAMENTO = ap.NRO_INT_LICENCIAMENTO
)
AND NOT EXISTS (
    SELECT 1 FROM SOL.ARQUIVO_ED ae WHERE ae.ID_ARQUIVO_ED = a.NRO_INT_ARQUIVO
);

PROMPT Arquivos inseridos: &SQL.ROWCOUNT

-- ============================================================
-- PASSO 7 — Atualizar SEQUENCES do schema SOL
--           Garante que próximas inserções não conflitem
-- ============================================================
PROMPT === PASSO 7: Atualizando sequences SOL ===

DECLARE
    v_max NUMBER;
BEGIN
    SELECT NVL(MAX(ID_USUARIO), 0) + 1000      INTO v_max FROM SOL.USUARIO;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_USUARIO RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_USUARIO → ' || v_max);

    SELECT NVL(MAX(ID_ENDERECO), 0) + 1000     INTO v_max FROM SOL.ENDERECO;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_ENDERECO RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_ENDERECO → ' || v_max);

    SELECT NVL(MAX(ID_LICENCIAMENTO), 0) + 1000 INTO v_max FROM SOL.LICENCIAMENTO;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_LICENCIAMENTO RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_LICENCIAMENTO → ' || v_max);

    SELECT NVL(MAX(ID_BOLETO), 0) + 1000       INTO v_max FROM SOL.BOLETO;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_BOLETO RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_BOLETO → ' || v_max);

    SELECT NVL(MAX(ID_MARCO_PROCESSO), 0) + 1000 INTO v_max FROM SOL.MARCO_PROCESSO;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_MARCO_PROCESSO RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_MARCO_PROCESSO → ' || v_max);

    SELECT NVL(MAX(ID_ARQUIVO_ED), 0) + 1000   INTO v_max FROM SOL.ARQUIVO_ED;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE SOL.SEQ_ARQUIVO_ED RESTART START WITH ' || v_max;
    DBMS_OUTPUT.PUT_LINE('SEQ_ARQUIVO_ED → ' || v_max);
END;
/

-- ============================================================
-- PASSO 8 — Validação final
-- ============================================================
PROMPT === PASSO 8: Validação — contagem final ===

SELECT 'SOL.USUARIO'        AS TABELA, COUNT(*) AS REGISTROS FROM SOL.USUARIO        UNION ALL
SELECT 'SOL.ENDERECO',                 COUNT(*)              FROM SOL.ENDERECO        UNION ALL
SELECT 'SOL.LICENCIAMENTO',            COUNT(*)              FROM SOL.LICENCIAMENTO   UNION ALL
SELECT 'SOL.BOLETO',                   COUNT(*)              FROM SOL.BOLETO          UNION ALL
SELECT 'SOL.MARCO_PROCESSO',           COUNT(*)              FROM SOL.MARCO_PROCESSO  UNION ALL
SELECT 'SOL.ARQUIVO_ED',               COUNT(*)              FROM SOL.ARQUIVO_ED;

PROMPT
PROMPT === Migração concluída. Revise os contadores acima. ===
PROMPT === Execute COMMIT somente após validar os dados.    ===
PROMPT

-- COMMIT;   ← descomente após validar

EXIT;
