SET PAGESIZE 500
SET LINESIZE 200
SET FEEDBACK OFF
SET ECHO OFF
COLUMN table_name   FORMAT A35
COLUMN column_name  FORMAT A40
COLUMN data_type    FORMAT A15
COLUMN data_length  FORMAT 9999
COLUMN nullable     FORMAT A8

SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_LICENCIAMENTO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_USUARIO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_ENDERECO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_ENDERECO_LICENCIAMENTO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_LOCALIZACAO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_RESPONSAVEL_TECNICO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_RESPONSAVEL_USO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_ARQUIVO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_BOLETO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_BOLETO_LICENCIAMENTO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_LICENCIAMENTO_MARCO' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_ROTINA' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_PRPCI' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_APPCI' ORDER BY column_id;
SELECT table_name, column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name = 'CBM_VISTORIA' ORDER BY column_id;

EXIT;
