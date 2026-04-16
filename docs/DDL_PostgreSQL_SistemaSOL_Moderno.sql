-- =============================================================================
-- DDL PostgreSQL — Sistema SOL Modernizado (CBMRS)
-- Migração do schema Oracle P_CBM_SOLCBM_AD para PostgreSQL 16
-- =============================================================================
-- Versão: 1.0 | Data: 2026-03-18
-- Baseado em: DDL Oracle (5058 linhas, ~140 tabelas) + Apresentação SOL (225 pág.)
--
-- Decisões de design aplicadas:
--   1. BIGSERIAL para PKs (sequencial, compatível com Oracle NUMBER(10,0))
--   2. BOOLEAN para colunas IND_* CHAR(1) 'S'/'N'
--   3. TIMESTAMPTZ para timestamps (com fuso horário)
--   4. TEXT para CLOBs; VARCHAR(n) para strings curtas
--   5. INET para endereços IP (substitui VARCHAR2(255))
--   6. Colunas de auditoria padronizadas: criado_em, atualizado_em, etc.
--   7. 10 tabelas CBM_RESULTADO_ATEC_* → 1 tabela resultado_atec
--   8. 11 tabelas CBM_JUSTIFICATIVA_ATEC_* → 1 tabela justificativa_atec
--   9. CBM_TEXTO_FORMATADO inline em vistoria.observacoes
--  10. Tabelas BKP, DATABASECHANGELOG e ARQUIVO_CACHE (BLOB) excluídas
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS sol;
SET search_path TO sol, public;

-- -----------------------------------------------------------------------------
-- Extensões necessárias
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- buscas sem acento

-- =============================================================================
-- BLOCO 1: TABELAS DE REFERÊNCIA / LOOKUP
-- =============================================================================

-- Tipos de domínio (categorias de lookup)
CREATE TABLE sol.tipo_dominio (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          BIGINT          NOT NULL UNIQUE,
    descricao       VARCHAR(400)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Domínios (valores lookup genéricos)
CREATE TABLE sol.dominio (
    id              BIGSERIAL       PRIMARY KEY,
    tipo_dominio_id BIGINT          NOT NULL REFERENCES sol.tipo_dominio(id),
    codigo          BIGINT          NOT NULL,
    descricao       VARCHAR(400)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT,
    UNIQUE (tipo_dominio_id, codigo)
);

-- Parâmetros gerais do sistema
CREATE TABLE sol.parametro_geral (
    id              BIGSERIAL       PRIMARY KEY,
    chave           VARCHAR(255)    NOT NULL UNIQUE,
    valor           VARCHAR(4000)   NOT NULL,
    descricao       VARCHAR(500),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Parâmetros de boleto
CREATE TABLE sol.parametro_boleto (
    id              BIGSERIAL       PRIMARY KEY,
    chave           VARCHAR(255)    NOT NULL UNIQUE,
    valor           VARCHAR(4000)   NOT NULL,
    descricao       VARCHAR(500),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Parâmetros de marcos de processo
CREATE TABLE sol.parametro_marco (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          VARCHAR(60)     NOT NULL UNIQUE,
    descricao       VARCHAR(500)    NOT NULL,
    visibilidade    VARCHAR(30)     NOT NULL,   -- PÚBLICO | BOMBEIROS
    responsavel     VARCHAR(30)     NOT NULL,
    tipo_processo   VARCHAR(40),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Parâmetros NCS (Não-Conformidades)
CREATE TABLE sol.parametro_ncs (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          VARCHAR(60)     NOT NULL UNIQUE,
    descricao       VARCHAR(500)    NOT NULL,
    tipo_entidade   VARCHAR(20)     NOT NULL,   -- ELEGRAF|GERAL|ISRISC|MEDSEG|OCUPAC|PROPRI|RISCO|RT|RU|TEDIF
    ativo           BOOLEAN         NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Normas técnicas (ABNT, etc.)
CREATE TABLE sol.norma (
    id              BIGSERIAL       PRIMARY KEY,
    descricao       VARCHAR(500)    NOT NULL,
    codigo          VARCHAR(50),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Catálogo de riscos específicos
CREATE TABLE sol.risco (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          SMALLINT        NOT NULL,
    descricao       VARCHAR(500)    NOT NULL,
    tipo            SMALLINT        NOT NULL,
    tipo_licenciamento VARCHAR(40),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- CNAE (Classificação Nacional de Atividades Econômicas)
CREATE TABLE sol.cnae (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          VARCHAR(20)     NOT NULL UNIQUE,
    descricao       VARCHAR(500)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Valor da UPF por ano/período
CREATE TABLE sol.valor_upf (
    ano_base        SMALLINT        NOT NULL,
    data_inicial    DATE            NOT NULL,
    data_final      DATE            NOT NULL,
    valor           NUMERIC(7,4)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT,
    PRIMARY KEY (ano_base, data_inicial, data_final)
);

-- Tabela de taxas (em UPF) por área × altura × risco × tipo licenciamento
CREATE TABLE sol.taxa_licenciamento (
    id              BIGSERIAL       PRIMARY KEY,
    tipo_area       SMALLINT        NOT NULL,
    tipo_altura     SMALLINT        NOT NULL,
    tipo_risco      SMALLINT        NOT NULL,
    tipo_licenciamento SMALLINT     NOT NULL,
    tipo_taxa       SMALLINT        NOT NULL,
    valor_upf       NUMERIC(6,2)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Termos de responsabilidade configuráveis por tipo de envolvido/licenciamento
CREATE TABLE sol.termo_licenciamento (
    id              BIGSERIAL       PRIMARY KEY,
    tipo_envolvido  VARCHAR(15)     NOT NULL,
    tipo_licenciamento VARCHAR(40),
    texto           VARCHAR(4000)   NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Períodos de solicitação (abertura/fechamento do sistema para novos processos)
CREATE TABLE sol.periodo_solicitacao (
    id              BIGSERIAL       PRIMARY KEY,
    tipo            VARCHAR(30)     NOT NULL,
    inicio          TIMESTAMPTZ     NOT NULL,
    fim             TIMESTAMPTZ     NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Permissões de envolvidos (RBAC aplicativo)
CREATE TABLE sol.permissao_envolvido (
    id              BIGSERIAL       PRIMARY KEY,
    papel           VARCHAR(30)     NOT NULL,
    sistema         VARCHAR(255)    NOT NULL,
    objeto          VARCHAR(255)    NOT NULL,
    acao            VARCHAR(255)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- =============================================================================
-- BLOCO 2: HIERARQUIA MILITAR
-- =============================================================================

CREATE TABLE sol.batalhao (
    id              BIGSERIAL       PRIMARY KEY,
    codigo          VARCHAR(30)     NOT NULL UNIQUE,
    descricao       VARCHAR(255)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.companhia (
    id              BIGSERIAL       PRIMARY KEY,
    batalhao_id     BIGINT          NOT NULL REFERENCES sol.batalhao(id),
    codigo          VARCHAR(30)     NOT NULL UNIQUE,
    descricao       VARCHAR(255)    NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.pelotao (
    id              BIGSERIAL       PRIMARY KEY,
    companhia_id    BIGINT          NOT NULL REFERENCES sol.companhia(id),
    numero_codigo   VARCHAR(30)     NOT NULL,
    unidade_atendimento VARCHAR(255),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.cidade (
    id              BIGSERIAL       PRIMARY KEY,
    batalhao_id     BIGINT          REFERENCES sol.batalhao(id),
    nome            VARCHAR(100)    NOT NULL,
    uf              CHAR(2)         NOT NULL DEFAULT 'RS',
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- =============================================================================
-- BLOCO 3: USUÁRIOS E ARQUIVOS
-- =============================================================================

-- Arquivo (metadados — binário armazenado no MinIO)
CREATE TABLE sol.arquivo (
    id                  BIGSERIAL       PRIMARY KEY,
    nome_original       VARCHAR(255)    NOT NULL,
    content_type        VARCHAR(100),
    tamanho_bytes       BIGINT,
    objeto_key          VARCHAR(500),               -- caminho no MinIO
    codigo_autenticacao VARCHAR(40)     UNIQUE,      -- para QR code / validação
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Usuários do sistema (perfil local complementar ao IdP)
CREATE TABLE sol.usuario (
    id                  BIGSERIAL       PRIMARY KEY,
    nome                VARCHAR(66)     NOT NULL,
    cpf                 VARCHAR(16)     NOT NULL UNIQUE,
    rg                  VARCHAR(15),
    uf_rg               CHAR(2),
    arquivo_rg_id       BIGINT          REFERENCES sol.arquivo(id),
    data_nascimento     DATE            NOT NULL,
    nome_mae            VARCHAR(66)     NOT NULL,
    email               VARCHAR(64)     NOT NULL,
    telefone1           VARCHAR(16)     NOT NULL,
    telefone2           VARCHAR(16),
    status              SMALLINT        NOT NULL DEFAULT 0,  -- 0=INCOMPLETO, 1=ATIVO, 2=BLOQUEADO
    mensagem_status     VARCHAR(1024),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (nome, nome_mae)
);

-- =============================================================================
-- BLOCO 4: TÉCNICO — EDIFICAÇÃO
-- =============================================================================

-- Especificações de segurança (conjunto de medidas para uma edificação)
CREATE TABLE sol.especificacao_seguranca (
    id              BIGSERIAL       PRIMARY KEY,
    descricao       VARCHAR(500),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Características da edificação
CREATE TABLE sol.caracteristica (
    id                      BIGSERIAL       PRIMARY KEY,
    area_total              NUMERIC(12,2),
    area_construida         NUMERIC(12,2),
    altura_edificacao       NUMERIC(8,2),
    numero_pavimentos       SMALLINT,
    numero_subsolos         SMALLINT,
    populacao_fixa          INTEGER,
    populacao_flutuante     INTEGER,
    especificacao_seguranca_id BIGINT       REFERENCES sol.especificacao_seguranca(id),
    criado_em               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em           TIMESTAMPTZ,
    ip_criacao              INET,
    ip_atualizacao          INET,
    criado_por              BIGINT,
    atualizado_por          BIGINT
);

-- Ocupação (tipo de atividade/uso da edificação)
CREATE TABLE sol.ocupacao (
    id                      BIGSERIAL       PRIMARY KEY,
    cnae_id                 BIGINT          REFERENCES sol.cnae(id),
    caracteristica_id       BIGINT          REFERENCES sol.caracteristica(id),
    descricao               VARCHAR(255),
    carga_incendio          NUMERIC(10,2),
    grau_risco              VARCHAR(20),
    determina_seguranca     BOOLEAN         NOT NULL DEFAULT FALSE,
    tipo_subsolo            VARCHAR(30),
    criado_em               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em           TIMESTAMPTZ,
    ip_criacao              INET,
    ip_atualizacao          INET,
    criado_por              BIGINT,
    atualizado_por          BIGINT
);

-- Auditoria de ocupação (Envers)
CREATE TABLE sol.ocupacao_aud (
    id              BIGINT          NOT NULL,
    rev             BIGINT          NOT NULL,
    rev_type        SMALLINT,
    cnae_id         BIGINT,
    descricao       VARCHAR(255),
    carga_incendio  NUMERIC(10,2),
    grau_risco      VARCHAR(20),
    PRIMARY KEY (id, rev)
);

-- Medidas de segurança
CREATE TABLE sol.medida_seguranca (
    id              BIGSERIAL       PRIMARY KEY,
    descricao       VARCHAR(500)    NOT NULL,
    tipo_formulario VARCHAR(30),
    chave_nc        VARCHAR(60),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Medida × Norma
CREATE TABLE sol.medida_seg_norma (
    medida_seguranca_id BIGINT      NOT NULL REFERENCES sol.medida_seguranca(id),
    norma_id            BIGINT      NOT NULL REFERENCES sol.norma(id),
    tipo_construcao     VARCHAR(30),
    PRIMARY KEY (medida_seguranca_id, norma_id)
);

-- Especificação de risco (instância de risco em um licenciamento)
CREATE TABLE sol.especificacao_risco (
    id              BIGSERIAL       PRIMARY KEY,
    risco_id        BIGINT          NOT NULL REFERENCES sol.risco(id),
    descricao       VARCHAR(500),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Localização georreferenciada da edificação
CREATE TABLE sol.localizacao (
    id                      BIGSERIAL       PRIMARY KEY,
    logradouro              VARCHAR(255),
    numero                  VARCHAR(20),
    complemento             VARCHAR(100),
    bairro                  VARCHAR(100),
    municipio               VARCHAR(100),
    uf                      CHAR(2)         DEFAULT 'RS',
    cep                     VARCHAR(10),
    lat_endereco            NUMERIC(10,7),
    lon_endereco            NUMERIC(10,7),
    lat_mapa                NUMERIC(10,7),
    lon_mapa                NUMERIC(10,7),
    isolamento_risco        BOOLEAN         NOT NULL DEFAULT FALSE,
    arquivo_comprovante_id  BIGINT          REFERENCES sol.arquivo(id),
    criado_em               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em           TIMESTAMPTZ,
    ip_criacao              INET,
    ip_atualizacao          INET,
    criado_por              BIGINT,
    atualizado_por          BIGINT
);

-- =============================================================================
-- BLOCO 5: PROCESSO PRINCIPAL — LICENCIAMENTO
-- =============================================================================

CREATE TABLE sol.licenciamento (
    id                          BIGSERIAL       PRIMARY KEY,
    codigo                      VARCHAR(20)     UNIQUE,     -- ex.: A 00000361 AA 001
    tipo_licenciamento          VARCHAR(25)     NOT NULL,
    situacao                    VARCHAR(30)     NOT NULL,
    fase                        VARCHAR(30),
    passo                       SMALLINT        NOT NULL DEFAULT 1,   -- passo do wizard
    prioridade                  SMALLINT        NOT NULL DEFAULT 5,
    caracteristica_id           BIGINT          REFERENCES sol.caracteristica(id),
    especificacao_seguranca_id  BIGINT          REFERENCES sol.especificacao_seguranca(id),
    localizacao_id              BIGINT          REFERENCES sol.localizacao(id),
    isencao                     BOOLEAN         NOT NULL DEFAULT FALSE,
    situacao_isencao            VARCHAR(30),
    inviabilidade_aprovada      BOOLEAN         NOT NULL DEFAULT FALSE,
    recurso_bloqueado           BOOLEAN         NOT NULL DEFAULT FALSE,
    reserva                     BOOLEAN         NOT NULL DEFAULT FALSE,
    dth_encaminhamento_analise  TIMESTAMPTZ,
    dias_analise_anterior       INTEGER,
    dth_ajuste_nca              TIMESTAMPTZ,
    criado_em                   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em               TIMESTAMPTZ,
    ip_criacao                  INET,
    ip_atualizacao              INET,
    criado_por                  BIGINT          REFERENCES sol.usuario(id),
    atualizado_por              BIGINT          REFERENCES sol.usuario(id)
);

CREATE INDEX idx_licenciamento_codigo ON sol.licenciamento(codigo);
CREATE INDEX idx_licenciamento_situacao ON sol.licenciamento(situacao);
CREATE INDEX idx_licenciamento_tipo ON sol.licenciamento(tipo_licenciamento);

-- Auditoria de licenciamento (Envers)
CREATE TABLE sol.licenciamento_aud (
    id                  BIGINT      NOT NULL,
    rev                 BIGINT      NOT NULL,
    rev_type            SMALLINT,
    codigo              VARCHAR(20),
    tipo_licenciamento  VARCHAR(25),
    situacao            VARCHAR(30),
    fase                VARCHAR(30),
    passo               SMALLINT,
    PRIMARY KEY (id, rev)
);

-- Histórico de situações do licenciamento
CREATE TABLE sol.licenciamento_sit_hist (
    id              BIGSERIAL       PRIMARY KEY,
    licenciamento_id BIGINT         NOT NULL REFERENCES sol.licenciamento(id),
    situacao_atual  VARCHAR(30)     NOT NULL,
    situacao_anterior VARCHAR(30),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    ip_criacao      INET,
    criado_por      BIGINT          REFERENCES sol.usuario(id)
);

-- Marcos do licenciamento (linha do tempo)
CREATE TABLE sol.licenciamento_marco (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    data_marco          TIMESTAMPTZ     NOT NULL,
    descricao           VARCHAR(500)    NOT NULL,
    complemento         VARCHAR(500),
    visibilidade        VARCHAR(20)     NOT NULL,   -- PÚBLICO | BOMBEIROS
    responsavel         VARCHAR(30),
    nome_responsavel    VARCHAR(64),
    parametro_marco_id  BIGINT          REFERENCES sol.parametro_marco(id),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Fila de notificações por e-mail
CREATE TABLE sol.licenciamento_notificacao (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          REFERENCES sol.licenciamento(id),
    identificador       UUID            NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    destinatario        VARCHAR(255)    NOT NULL,
    assunto             VARCHAR(255),
    mensagem            TEXT,
    tipo_envio          VARCHAR(30),
    situacao            VARCHAR(30),
    erro                TEXT,
    rotina_id           BIGINT,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ
);

-- Notificações in-app (120 chars)
CREATE TABLE sol.notificacao (
    id              BIGSERIAL       PRIMARY KEY,
    usuario_id      BIGINT          NOT NULL REFERENCES sol.usuario(id),
    licenciamento_id BIGINT         REFERENCES sol.licenciamento(id),
    mensagem        VARCHAR(120)    NOT NULL,
    contexto        SMALLINT,
    lida            BOOLEAN         NOT NULL DEFAULT FALSE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Contagem de solicitações de análise por licenciamento
CREATE TABLE sol.solicitacao_analise (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    numero_solicitacao  BIGINT          NOT NULL,
    data_solicitacao    TIMESTAMPTZ     NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Log de erros de sistema
CREATE TABLE sol.log_erro (
    id              BIGSERIAL       PRIMARY KEY,
    identificador   UUID            NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    descricao       VARCHAR(500),
    detalhe         TEXT,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Log de chamadas PROCERGS para geração de boleto
CREATE TABLE sol.log_gera_boleto (
    id              BIGSERIAL       PRIMARY KEY,
    xml_requisicao  TEXT,
    xml_resposta    TEXT,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Rotinas/Jobs automáticos (log de execução)
CREATE TABLE sol.rotina (
    id              BIGSERIAL       PRIMARY KEY,
    id_rotina       SMALLINT        NOT NULL,
    descricao       VARCHAR(500),
    inicio          TIMESTAMPTZ,
    fim             TIMESTAMPTZ,
    situacao        SMALLINT,       -- 0=OK, 1=ERRO
    erro            VARCHAR(4000),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Notas internas por licenciamento
CREATE TABLE sol.nota (
    id              BIGSERIAL       PRIMARY KEY,
    licenciamento_id BIGINT         NOT NULL REFERENCES sol.licenciamento(id),
    texto           TEXT            NOT NULL,
    usuario_soe_id  BIGINT,         -- ID do usuário interno (SOE)
    ativo           BOOLEAN         NOT NULL DEFAULT TRUE,
    data_conclusao  TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.nota_historico (
    id          BIGSERIAL       PRIMARY KEY,
    nota_id     BIGINT          NOT NULL REFERENCES sol.nota(id),
    texto       TEXT            NOT NULL,
    criado_em   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    criado_por  BIGINT
);

-- =============================================================================
-- BLOCO 6: ENVOLVIDOS
-- =============================================================================

-- Proprietário (pessoa física ou jurídica)
CREATE TABLE sol.proprietario (
    id              BIGSERIAL       PRIMARY KEY,
    cpf             VARCHAR(16),
    cnpj            VARCHAR(16),
    tipo_pessoa     CHAR(1)         NOT NULL,    -- F=física, J=jurídica
    nome            VARCHAR(66),
    razao_social    VARCHAR(64),
    nome_fantasia   VARCHAR(64),
    email           VARCHAR(64),
    telefone        VARCHAR(16),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT,
    CONSTRAINT chk_proprietario_cpf_cnpj CHECK (
        (tipo_pessoa = 'F' AND cpf IS NOT NULL) OR
        (tipo_pessoa = 'J' AND cnpj IS NOT NULL)
    )
);

CREATE INDEX idx_proprietario_cpf ON sol.proprietario(tipo_pessoa, cpf) WHERE tipo_pessoa = 'F';
CREATE INDEX idx_proprietario_cnpj ON sol.proprietario(tipo_pessoa, cnpj) WHERE tipo_pessoa = 'J';

-- Procurador (representante legal do proprietário)
CREATE TABLE sol.procurador (
    id                  BIGSERIAL       PRIMARY KEY,
    usuario_id          BIGINT          REFERENCES sol.usuario(id),
    arquivo_procuracao_id BIGINT        REFERENCES sol.arquivo(id),
    aceite              BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_vistoria     BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_extincao     BOOLEAN         NOT NULL DEFAULT FALSE,
    solicitante_extincao BOOLEAN        NOT NULL DEFAULT FALSE,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Proprietário × Licenciamento
CREATE TABLE sol.licenciamento_proprietario (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    proprietario_id     BIGINT          NOT NULL REFERENCES sol.proprietario(id),
    procurador_id       BIGINT          REFERENCES sol.procurador(id),
    aceite              BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_vistoria     BOOLEAN         NOT NULL DEFAULT FALSE,
    data_aceite_vistoria TIMESTAMPTZ,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Responsável Técnico (engenheiro/arquiteto credenciado)
CREATE TABLE sol.responsavel_tecnico (
    id                      BIGSERIAL       PRIMARY KEY,
    licenciamento_id        BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    usuario_id              BIGINT          REFERENCES sol.usuario(id),
    tipo_responsabilidade   VARCHAR(35)     NOT NULL,
    aceite                  BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_vistoria         BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_anexod           BOOLEAN         NOT NULL DEFAULT FALSE,
    data_aceite_anexod      TIMESTAMPTZ,
    consolidado_anexod      BOOLEAN         NOT NULL DEFAULT FALSE,
    aceite_extincao         BOOLEAN         NOT NULL DEFAULT FALSE,
    solicitante_extincao    BOOLEAN         NOT NULL DEFAULT FALSE,
    criado_em               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em           TIMESTAMPTZ,
    ip_criacao              INET,
    ip_atualizacao          INET,
    criado_por              BIGINT,
    atualizado_por          BIGINT
);

-- Auditoria RT (Envers)
CREATE TABLE sol.responsavel_tecnico_aud (
    id                  BIGINT      NOT NULL,
    rev                 BIGINT      NOT NULL,
    rev_type            SMALLINT,
    tipo_responsabilidade VARCHAR(35),
    aceite              BOOLEAN,
    aceite_vistoria     BOOLEAN,
    PRIMARY KEY (id, rev)
);

-- Responsável pelo Uso (proprietário/gestor do estabelecimento)
CREATE TABLE sol.responsavel_uso (
    id              BIGSERIAL       PRIMARY KEY,
    licenciamento_id BIGINT         NOT NULL REFERENCES sol.licenciamento(id),
    usuario_id      BIGINT          REFERENCES sol.usuario(id),
    procurador_id   BIGINT          REFERENCES sol.procurador(id),
    aceite          BOOLEAN         NOT NULL DEFAULT FALSE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Auditoria RU (Envers)
CREATE TABLE sol.responsavel_uso_aud (
    id          BIGINT      NOT NULL,
    rev         BIGINT      NOT NULL,
    rev_type    SMALLINT,
    aceite      BOOLEAN,
    PRIMARY KEY (id, rev)
);

-- Arquivos dos responsáveis (habilitações, ART, RRT)
CREATE TABLE sol.responsavel_arquivo (
    id                  BIGSERIAL       PRIMARY KEY,
    responsavel_tecnico_id BIGINT       NOT NULL REFERENCES sol.responsavel_tecnico(id),
    arquivo_id          BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    tipo_arquivo        VARCHAR(30),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Auditoria responsavel_arquivo (Envers)
CREATE TABLE sol.responsavel_arquivo_aud (
    id          BIGINT      NOT NULL,
    rev         BIGINT      NOT NULL,
    rev_type    SMALLINT,
    arquivo_id  BIGINT,
    PRIMARY KEY (id, rev)
);

-- =============================================================================
-- BLOCO 7: ANÁLISE TÉCNICA
-- =============================================================================

CREATE TABLE sol.analise_lic_tecnica (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    usuario_soe_id      BIGINT,         -- analista (ID no SOE/Keycloak)
    situacao            VARCHAR(30)     NOT NULL,
    data_inicio         TIMESTAMPTZ,
    data_conclusao      TIMESTAMPTZ,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- CONSOLIDAÇÃO: Substitui 10 tabelas CBM_RESULTADO_ATEC_*
CREATE TABLE sol.resultado_atec (
    id                  BIGSERIAL       PRIMARY KEY,
    analise_id          BIGINT          NOT NULL REFERENCES sol.analise_lic_tecnica(id),
    tipo_entidade       VARCHAR(20)     NOT NULL,   -- ELEGRAF|GERAL|ISRISC|MEDSEG|OCUPAC|PROPRI|RISCO|RT|RU|TEDIF
    entidade_id         BIGINT          NOT NULL,   -- FK polimórfica (verificada na camada de aplicação)
    status              VARCHAR(30)     NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (analise_id, tipo_entidade, entidade_id)
);

-- CONSOLIDAÇÃO: Substitui 11 tabelas CBM_JUSTIFICATIVA_ATEC_*
CREATE TABLE sol.justificativa_atec (
    id                  BIGSERIAL       PRIMARY KEY,
    resultado_id        BIGINT          NOT NULL REFERENCES sol.resultado_atec(id),
    parametro_ncs_id    BIGINT          NOT NULL REFERENCES sol.parametro_ncs(id),
    justificativa       TEXT            NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (resultado_id, parametro_ncs_id)
);

-- Justificativas NCS por endereço
CREATE TABLE sol.justificativa_ncs_endereco (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    parametro_ncs_id    BIGINT          NOT NULL REFERENCES sol.parametro_ncs(id),
    justificativa       TEXT            NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (licenciamento_id, parametro_ncs_id)
);

-- Justificativas NCS de isenção
CREATE TABLE sol.justificativa_ncs_isencao (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    parametro_ncs_id    BIGINT          NOT NULL REFERENCES sol.parametro_ncs(id),
    justificativa       TEXT            NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (licenciamento_id, parametro_ncs_id)
);

-- =============================================================================
-- BLOCO 8: VISTORIA
-- =============================================================================

CREATE TABLE sol.vistoria (
    id                          BIGSERIAL       PRIMARY KEY,
    licenciamento_id            BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    numero_vistoria             SMALLINT        NOT NULL DEFAULT 1,
    status                      VARCHAR(30)     NOT NULL,
    data_status                 TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    arquivo_id                  BIGINT          REFERENCES sol.arquivo(id),       -- planta/documento da vistoria
    data_solicitacao            TIMESTAMPTZ,
    usuario_soe_id              BIGINT,         -- inspetor (ID SOE)
    nome_usuario_soe            VARCHAR(64),
    usuario_soe_homolog_id      BIGINT,         -- quem homologou
    nome_usuario_soe_homolog    VARCHAR(64),
    data_homologacao            TIMESTAMPTZ,
    motivo_indeferimento        VARCHAR(4000),
    observacoes                 TEXT,           -- inline (substitui CBM_TEXTO_FORMATADO)
    data_realizacao             TIMESTAMPTZ,
    ciencia                     BOOLEAN         NOT NULL DEFAULT FALSE,
    data_ciencia                TIMESTAMPTZ,
    usuario_ciencia_id          BIGINT          REFERENCES sol.usuario(id),
    tipo_vistoria               SMALLINT        NOT NULL DEFAULT 0,
    usuario_aceite_prpci_id     BIGINT          REFERENCES sol.usuario(id),
    data_aceite_prpci           TIMESTAMPTZ,
    aceite_prpci                BOOLEAN,
    data_prevista               TIMESTAMPTZ,
    turno_previsto              VARCHAR(30),
    data_distribuicao           TIMESTAMPTZ,
    appci_id                    BIGINT,         -- FK definida após criar tabela appci
    criado_em                   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em               TIMESTAMPTZ,
    ip_criacao                  INET,
    ip_atualizacao              INET,
    criado_por                  BIGINT,
    atualizado_por              BIGINT
);

-- Inspetores atribuídos à vistoria
CREATE TABLE sol.vistoriante (
    id              BIGSERIAL       PRIMARY KEY,
    vistoria_id     BIGINT          NOT NULL REFERENCES sol.vistoria(id),
    usuario_soe_id  BIGINT          NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Laudos de vistoria (RT insere antes/após vistoria)
CREATE TABLE sol.laudo_vistoria (
    id              BIGSERIAL       PRIMARY KEY,
    licenciamento_id BIGINT         NOT NULL REFERENCES sol.licenciamento(id),
    vistoria_id     BIGINT          REFERENCES sol.vistoria(id),
    arquivo_id      BIGINT          REFERENCES sol.arquivo(id),
    tipo_laudo      VARCHAR(30)     NOT NULL,
    consolidado     BOOLEAN         NOT NULL DEFAULT FALSE,
    renovacao       BOOLEAN         NOT NULL DEFAULT FALSE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- ART/RRT vinculada ao laudo
CREATE TABLE sol.laudo_art_rrt (
    laudo_id        BIGINT          NOT NULL REFERENCES sol.laudo_vistoria(id),
    arquivo_id      BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    PRIMARY KEY (laudo_id, arquivo_id)
);

-- Laudos complementares
CREATE TABLE sol.laudo_complementar (
    laudo_id        BIGINT          NOT NULL REFERENCES sol.laudo_vistoria(id),
    arquivo_id      BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    PRIMARY KEY (laudo_id, arquivo_id)
);

-- =============================================================================
-- BLOCO 9: BOLETO E PAGAMENTO
-- =============================================================================

CREATE TABLE sol.boleto (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          REFERENCES sol.licenciamento(id),
    fact_id             BIGINT,         -- FK para fact (definida após criar tabela fact)
    responsavel_id      BIGINT          REFERENCES sol.usuario(id),
    tipo_boleto         VARCHAR(30),
    situacao            VARCHAR(30),
    valor               NUMERIC(15,2),
    data_emissao        TIMESTAMPTZ,
    data_vencimento     TIMESTAMPTZ,
    data_pagamento      TIMESTAMPTZ,
    linha_digitavel     VARCHAR(255),
    codigo_barras       VARCHAR(255),
    log_gera_boleto_id  BIGINT          REFERENCES sol.log_gera_boleto(id),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- =============================================================================
-- BLOCO 10: APPCI E PRPCI
-- =============================================================================

CREATE TABLE sol.appci (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    arquivo_id          BIGINT          REFERENCES sol.arquivo(id),
    data_emissao        TIMESTAMPTZ,
    data_validade       TIMESTAMPTZ,    -- emissão + 5 anos (vistoria) ou 2 anos (PrPCI)
    codigo_autenticacao VARCHAR(40)     UNIQUE,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- Adicionar FK de vistoria → appci (circular, criada após ambas as tabelas)
ALTER TABLE sol.vistoria
    ADD CONSTRAINT fk_vistoria_appci
    FOREIGN KEY (appci_id) REFERENCES sol.appci(id);

CREATE TABLE sol.prpci (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    vistoria_id         BIGINT          REFERENCES sol.vistoria(id),
    arquivo_id          BIGINT          REFERENCES sol.arquivo(id),
    localizacao_id      BIGINT          REFERENCES sol.localizacao(id),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

-- =============================================================================
-- BLOCO 11: RECURSO ADMINISTRATIVO
-- =============================================================================

CREATE TABLE sol.recurso (
    id                      BIGSERIAL       PRIMARY KEY,
    licenciamento_id        BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    tipo_recurso            CHAR(1)         NOT NULL,   -- C=CIA, V=CIV, etc.
    instancia               SMALLINT        NOT NULL,   -- 1 ou 2
    situacao                VARCHAR(30)     NOT NULL,
    tipo_solicitacao        CHAR(1),                    -- T=Total, P=Parcial
    fundamentacao_legal     VARCHAR(4000),
    arquivo_cia_civ_id      BIGINT          REFERENCES sol.arquivo(id),
    usuario_soe_id          BIGINT,
    criado_em               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em           TIMESTAMPTZ,
    ip_criacao              INET,
    ip_atualizacao          INET,
    criado_por              BIGINT,
    atualizado_por          BIGINT
);

CREATE TABLE sol.recurso_arquivo (
    recurso_id      BIGINT          NOT NULL REFERENCES sol.recurso(id),
    arquivo_id      BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    PRIMARY KEY (recurso_id, arquivo_id)
);

CREATE TABLE sol.recurso_marco (
    id                  BIGSERIAL       PRIMARY KEY,
    recurso_id          BIGINT          NOT NULL REFERENCES sol.recurso(id),
    data_marco          TIMESTAMPTZ     NOT NULL,
    descricao           VARCHAR(500)    NOT NULL,
    complemento         VARCHAR(500),
    visibilidade        VARCHAR(20)     NOT NULL,
    responsavel         VARCHAR(30),
    valor_nominal       NUMERIC(15,2),
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE sol.avalista_recurso (
    id              BIGSERIAL       PRIMARY KEY,
    recurso_id      BIGINT          NOT NULL REFERENCES sol.recurso(id),
    usuario_soe_id  BIGINT          NOT NULL,
    nome_usuario    VARCHAR(64),
    voto            VARCHAR(20),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- =============================================================================
-- BLOCO 12: TROCA DE ENVOLVIDOS
-- =============================================================================

CREATE TABLE sol.troca_envolvido (
    id                  BIGSERIAL       PRIMARY KEY,
    licenciamento_id    BIGINT          NOT NULL REFERENCES sol.licenciamento(id),
    usuario_solicitante_id BIGINT       NOT NULL REFERENCES sol.usuario(id),
    troca_rt            BOOLEAN         NOT NULL DEFAULT FALSE,
    troca_ru            BOOLEAN         NOT NULL DEFAULT FALSE,
    troca_proprietario  BOOLEAN         NOT NULL DEFAULT FALSE,
    data_criacao        TIMESTAMPTZ     NOT NULL,
    data_comunicacao    TIMESTAMPTZ     NOT NULL,
    situacao            VARCHAR(30)     NOT NULL,
    data_situacao       TIMESTAMPTZ,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

CREATE TABLE sol.troca_autorizacao (
    id                          BIGSERIAL       PRIMARY KEY,
    troca_envolvido_id          BIGINT          NOT NULL REFERENCES sol.troca_envolvido(id),
    tipo_pessoa                 CHAR(1)         NOT NULL,
    usuario_id                  BIGINT          REFERENCES sol.usuario(id),
    usuario_procurador_id       BIGINT          REFERENCES sol.usuario(id),
    razao_social                VARCHAR(64),
    autorizado                  BOOLEAN,
    data_autorizacao            TIMESTAMPTZ,
    criado_em                   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em               TIMESTAMPTZ,
    ip_criacao                  INET,
    ip_atualizacao              INET,
    criado_por                  BIGINT,
    atualizado_por              BIGINT
);

CREATE TABLE sol.troca_rt (
    id                  BIGSERIAL       PRIMARY KEY,
    troca_envolvido_id  BIGINT          NOT NULL REFERENCES sol.troca_envolvido(id),
    usuario_id          BIGINT          NOT NULL REFERENCES sol.usuario(id),
    tipo_responsabilidade VARCHAR(35)   NOT NULL,
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT,
    UNIQUE (troca_envolvido_id, usuario_id)
);

CREATE TABLE sol.troca_rt_arquivo (
    troca_rt_id     BIGINT          NOT NULL REFERENCES sol.troca_rt(id),
    arquivo_id      BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    PRIMARY KEY (troca_rt_id, arquivo_id)
);

CREATE TABLE sol.troca_ru (
    id                          BIGSERIAL       PRIMARY KEY,
    troca_envolvido_id          BIGINT          NOT NULL REFERENCES sol.troca_envolvido(id),
    usuario_id                  BIGINT          NOT NULL REFERENCES sol.usuario(id),
    usuario_procurador_id       BIGINT          REFERENCES sol.usuario(id),
    arquivo_procuracao_id       BIGINT          REFERENCES sol.arquivo(id),
    criado_em                   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em               TIMESTAMPTZ,
    ip_criacao                  INET,
    ip_atualizacao              INET,
    criado_por                  BIGINT,
    atualizado_por              BIGINT,
    UNIQUE (troca_envolvido_id, usuario_id)
);

CREATE TABLE sol.troca_proprietario (
    id                          BIGSERIAL       PRIMARY KEY,
    troca_envolvido_id          BIGINT          NOT NULL REFERENCES sol.troca_envolvido(id),
    tipo_pessoa                 CHAR(1)         NOT NULL,
    usuario_id                  BIGINT          REFERENCES sol.usuario(id),
    cnpj                        VARCHAR(16),
    razao_social                VARCHAR(64),
    nome_fantasia               VARCHAR(64),
    email                       VARCHAR(64),
    telefone                    VARCHAR(16),
    usuario_procurador_id       BIGINT          REFERENCES sol.usuario(id),
    arquivo_procuracao_id       BIGINT          REFERENCES sol.arquivo(id),
    criado_em                   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em               TIMESTAMPTZ,
    ip_criacao                  INET,
    ip_atualizacao              INET,
    criado_por                  BIGINT,
    atualizado_por              BIGINT,
    UNIQUE (troca_envolvido_id, tipo_pessoa, usuario_id, cnpj)
);

-- =============================================================================
-- BLOCO 13: FACT (Formulário de Atendimento e Consulta Técnica)
-- =============================================================================

CREATE TABLE sol.fact (
    id                  BIGSERIAL       PRIMARY KEY,
    numero              VARCHAR(20)     UNIQUE,     -- ex.: F000003712021
    licenciamento_id    BIGINT          REFERENCES sol.licenciamento(id),   -- nulo se avulso
    batalhao_id         BIGINT          REFERENCES sol.batalhao(id),
    tipo_solicitacao    VARCHAR(20)     NOT NULL,   -- REQUERIMENTO | CONSULTA_TECNICA
    situacao            VARCHAR(30)     NOT NULL,
    objeto              TEXT,                       -- rich text
    despacho            TEXT,                       -- resposta do analista
    usuario_soe_id      BIGINT,                     -- analista interno
    criado_em           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em       TIMESTAMPTZ,
    ip_criacao          INET,
    ip_atualizacao      INET,
    criado_por          BIGINT,
    atualizado_por      BIGINT
);

CREATE TABLE sol.fact_arquivo (
    fact_id         BIGINT          NOT NULL REFERENCES sol.fact(id),
    arquivo_id      BIGINT          NOT NULL REFERENCES sol.arquivo(id),
    PRIMARY KEY (fact_id, arquivo_id)
);

-- Solicitante do FACT (vínculo com usuário externo)
CREATE TABLE sol.solicitante (
    id          BIGSERIAL       PRIMARY KEY,
    fact_id     BIGINT          NOT NULL REFERENCES sol.fact(id),
    usuario_id  BIGINT          NOT NULL REFERENCES sol.usuario(id),
    criado_em   TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Aceite de envolvidos ao FACT
CREATE TABLE sol.fact_aceite_rt (
    id              BIGSERIAL       PRIMARY KEY,
    usuario_id      BIGINT          REFERENCES sol.usuario(id),
    fact_id         VARCHAR(120),   -- pode ser número ou referência
    aceite          BOOLEAN,
    procurador_id   BIGINT          REFERENCES sol.procurador(id),
    recurso_id      BIGINT          REFERENCES sol.recurso(id),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.fact_aceite_ru (
    id              BIGSERIAL       PRIMARY KEY,
    usuario_id      BIGINT          REFERENCES sol.usuario(id),
    fact_id         VARCHAR(120),
    aceite          BOOLEAN,
    procurador_id   BIGINT          REFERENCES sol.procurador(id),
    recurso_id      BIGINT          REFERENCES sol.recurso(id),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.fact_aceite_proprietario (
    id              BIGSERIAL       PRIMARY KEY,
    usuario_id      BIGINT          REFERENCES sol.usuario(id),
    fact_id         BIGINT          REFERENCES sol.fact(id),
    proprietario_id BIGINT          REFERENCES sol.proprietario(id),
    recurso_id      BIGINT          REFERENCES sol.recurso(id),
    aceite          BOOLEAN,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- Boleto FK para FACT
ALTER TABLE sol.boleto
    ADD CONSTRAINT fk_boleto_fact
    FOREIGN KEY (fact_id) REFERENCES sol.fact(id);

-- =============================================================================
-- BLOCO 14: INSTRUTORES E TREINAMENTOS (módulo acessório)
-- =============================================================================

CREATE TABLE sol.instrutor (
    id              BIGSERIAL       PRIMARY KEY,
    usuario_id      BIGINT          REFERENCES sol.usuario(id),
    nome            VARCHAR(66),
    cpf             VARCHAR(16),
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

CREATE TABLE sol.treinamento_instrutor (
    id              BIGSERIAL       PRIMARY KEY,
    instrutor_id    BIGINT          NOT NULL REFERENCES sol.instrutor(id),
    arquivo_id      BIGINT          REFERENCES sol.arquivo(id),
    tipo_treinamento SMALLINT       NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ,
    ip_criacao      INET,
    ip_atualizacao  INET,
    criado_por      BIGINT,
    atualizado_por  BIGINT
);

-- =============================================================================
-- BLOCO 15: AUDITORIA (Spring Data Envers)
-- =============================================================================

-- REVINFO com campos customizados
CREATE TABLE sol.revinfo (
    rev             BIGSERIAL       PRIMARY KEY,
    rev_timestamp   BIGINT          NOT NULL,
    usuario_id      BIGINT,
    ip_address      INET
);

-- =============================================================================
-- BLOCO 16: ÍNDICES ADICIONAIS DE PERFORMANCE
-- =============================================================================

CREATE INDEX idx_licenciamento_marco_lic  ON sol.licenciamento_marco(licenciamento_id);
CREATE INDEX idx_licenciamento_notif_lic  ON sol.licenciamento_notificacao(licenciamento_id);
CREATE INDEX idx_licenciamento_notif_sit  ON sol.licenciamento_notificacao(situacao);
CREATE INDEX idx_notificacao_usuario      ON sol.notificacao(usuario_id, lida);
CREATE INDEX idx_responsavel_tecnico_lic  ON sol.responsavel_tecnico(licenciamento_id);
CREATE INDEX idx_responsavel_uso_lic      ON sol.responsavel_uso(licenciamento_id);
CREATE INDEX idx_vistoria_lic             ON sol.vistoria(licenciamento_id);
CREATE INDEX idx_vistoria_status          ON sol.vistoria(status);
CREATE INDEX idx_analise_lic              ON sol.analise_lic_tecnica(licenciamento_id);
CREATE INDEX idx_resultado_atec_analise   ON sol.resultado_atec(analise_id);
CREATE INDEX idx_resultado_atec_tipo      ON sol.resultado_atec(tipo_entidade);
CREATE INDEX idx_recurso_lic              ON sol.recurso(licenciamento_id);
CREATE INDEX idx_boleto_lic               ON sol.boleto(licenciamento_id);
CREATE INDEX idx_boleto_situacao          ON sol.boleto(situacao);
CREATE INDEX idx_fact_lic                 ON sol.fact(licenciamento_id);
CREATE INDEX idx_fact_situacao            ON sol.fact(situacao);
CREATE INDEX idx_troca_lic                ON sol.troca_envolvido(licenciamento_id);
CREATE INDEX idx_usuario_email            ON sol.usuario(email);

-- =============================================================================
-- BLOCO 17: COMENTÁRIOS DE DOCUMENTAÇÃO
-- =============================================================================

COMMENT ON TABLE sol.licenciamento IS 'Processo principal de licenciamento PPCI/PSPCIM. Controla o ciclo completo desde submissão até emissão de APPCI.';
COMMENT ON COLUMN sol.licenciamento.codigo IS 'Número público do licenciamento: [Tipo][Seq 8d][Lote 2L][Versão 3d]. Ex.: A 00000361 AA 001';
COMMENT ON COLUMN sol.licenciamento.passo IS 'Passo atual do wizard de submissão (1–8)';
COMMENT ON COLUMN sol.licenciamento.recurso_bloqueado IS 'Licenciamento bloqueado por recurso pendente (RN-089)';

COMMENT ON TABLE sol.resultado_atec IS 'Consolidação das 10 tabelas CBM_RESULTADO_ATEC_* do Oracle. Discriminador: tipo_entidade.';
COMMENT ON TABLE sol.justificativa_atec IS 'Consolidação das 11 tabelas CBM_JUSTIFICATIVA_ATEC_* do Oracle.';
COMMENT ON TABLE sol.vistoria IS 'Vistoria presencial. Campo observacoes (TEXT) substitui a tabela CBM_TEXTO_FORMATADO do Oracle.';
COMMENT ON TABLE sol.appci IS 'Alvará de Prevenção e Proteção Contra Incêndio. Validade: 5 anos após vistoria; 2 anos após PrPCI.';
COMMENT ON TABLE sol.rotina IS 'Log de execução dos jobs automáticos (Spring Scheduler + ShedLock).';
COMMENT ON TABLE sol.arquivo IS 'Metadados de arquivos. Binário armazenado no MinIO (objeto_key = path no bucket).';
COMMENT ON TABLE sol.revinfo IS 'Tabela de revisões do Hibernate Envers. Customizada com usuario_id e ip_address.';

-- =============================================================================
-- BLOCO 18 — CORREÇÕES NORMATIVAS (RTCBMRS N.º 01/2024 + RT SOL 4ª Ed/2022)
-- =============================================================================

-- 18.1 Adicionar estado SUSPENSO ao ENUM de situação
-- (item 6.3.7.2.3: suspenso após 6 meses sem movimentação com CIA)
-- (item 6.4.8.2: suspenso após 2 anos sem movimentação com CA/CIV)
ALTER TYPE sol.tp_situacao_licenciamento ADD VALUE IF NOT EXISTS 'SUSPENSO';

-- 18.2 Tabela de feriados para cálculo de dias úteis
-- (item 12.1: prazo de recurso em dias úteis — não corridos)
CREATE TABLE sol.feriado (
    data        DATE PRIMARY KEY,
    descricao   VARCHAR(100) NOT NULL,
    abrangencia VARCHAR(20) NOT NULL CHECK (abrangencia IN ('FEDERAL','ESTADUAL_RS','MUNICIPAL')),
    municipio   VARCHAR(80)  -- preenchido apenas quando abrangencia = 'MUNICIPAL'
);

-- 18.3 Função: calcular dias úteis entre duas datas
CREATE OR REPLACE FUNCTION sol.dias_uteis(
    p_inicio DATE,
    p_fim    DATE,
    p_municipio VARCHAR(80) DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_dias INTEGER := 0;
    v_data DATE := p_inicio + 1;
BEGIN
    WHILE v_data <= p_fim LOOP
        IF EXTRACT(DOW FROM v_data) NOT IN (0, 6)  -- não é fim de semana
           AND NOT EXISTS (
               SELECT 1 FROM sol.feriado
               WHERE data = v_data
                 AND (abrangencia IN ('FEDERAL','ESTADUAL_RS')
                      OR (abrangencia = 'MUNICIPAL' AND municipio = p_municipio))
           )
        THEN
            v_dias := v_dias + 1;
        END IF;
        v_data := v_data + 1;
    END LOOP;
    RETURN v_dias;
END;
$$ LANGUAGE plpgsql STABLE;

-- 18.4 Função: data-limite em dias úteis (para recurso)
CREATE OR REPLACE FUNCTION sol.data_limite_uteis(
    p_inicio    DATE,
    p_dias_uteis INTEGER,
    p_municipio  VARCHAR(80) DEFAULT NULL
) RETURNS DATE AS $$
DECLARE
    v_data DATE := p_inicio;
    v_uteis INTEGER := 0;
BEGIN
    WHILE v_uteis < p_dias_uteis LOOP
        v_data := v_data + 1;
        IF EXTRACT(DOW FROM v_data) NOT IN (0, 6)
           AND NOT EXISTS (
               SELECT 1 FROM sol.feriado
               WHERE data = v_data
                 AND (abrangencia IN ('FEDERAL','ESTADUAL_RS')
                      OR (abrangencia = 'MUNICIPAL' AND municipio = p_municipio))
           )
        THEN
            v_uteis := v_uteis + 1;
        END IF;
    END LOOP;
    RETURN v_data;
END;
$$ LANGUAGE plpgsql STABLE;

-- 18.5 Versão normativa vigente no protocolo de cada licenciamento
-- (item 4.3.3 RTCBMRS N.º 01/2024: norma aplicável é a vigente na data do protocolo)
ALTER TABLE sol.licenciamento
    ADD COLUMN IF NOT EXISTS versao_norma_protocolo VARCHAR(40)
        NOT NULL DEFAULT 'RTCBMRS-01-2024';

-- 18.6 Campos imutáveis do Passo 2 — flag de "primeiro envio"
-- (item 6.3.2.1 RT Implantação SOL: endereço e isolamento não podem ser alterados após primeiro envio)
ALTER TABLE sol.licenciamento
    ADD COLUMN IF NOT EXISTS dt_primeiro_envio TIMESTAMPTZ;

-- Trigger que impede alteração de campos imutáveis após primeiro envio
CREATE OR REPLACE FUNCTION sol.fn_proteger_campos_passo2()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.dt_primeiro_envio IS NOT NULL THEN
        -- Se já foi enviado, bloquear campos imutáveis
        IF NEW.localizacao_id IS DISTINCT FROM OLD.localizacao_id THEN
            RAISE EXCEPTION 'Campo imutável: localizacao_id não pode ser alterado após o primeiro envio do PPCI (RT Implantação SOL, item 6.3.2.1)';
        END IF;
        IF NEW.ind_isolamento_riscos IS DISTINCT FROM OLD.ind_isolamento_riscos THEN
            RAISE EXCEPTION 'Campo imutável: ind_isolamento_riscos não pode ser alterado após o primeiro envio do PPCI (RT Implantação SOL, item 6.3.2.1)';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proteger_campos_passo2
    BEFORE UPDATE ON sol.licenciamento
    FOR EACH ROW EXECUTE FUNCTION sol.fn_proteger_campos_passo2();

-- 18.7 Função: calcular validade do APPCI por tipo de ocupação
-- (item 6.5.3.1: 2 anos para grupo F risco médio/alto e elevado risco)
-- (item 6.5.3.2: 5 anos para demais edificações)
CREATE OR REPLACE FUNCTION sol.calcular_validade_appci(
    p_tp_ocupacao_predominante VARCHAR(10),
    p_tp_risco                 VARCHAR(10),
    p_ind_elevado_risco        BOOLEAN DEFAULT FALSE
) RETURNS INTERVAL AS $$
BEGIN
    IF p_ind_elevado_risco = TRUE THEN
        RETURN INTERVAL '2 years';
    END IF;
    IF p_tp_ocupacao_predominante LIKE 'F%'
       AND p_tp_risco IN ('MEDIO', 'ALTO') THEN
        RETURN INTERVAL '2 years';
    END IF;
    RETURN INTERVAL '5 years';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 18.8 Campo Anexo D na tabela de vistoria
-- (item 6.4.4 RT Implantação SOL: Termo de Responsabilidade das Saídas de Emergência)
ALTER TABLE sol.vistoria
    ADD COLUMN IF NOT EXISTS ind_possui_porta_correr_emergencia BOOLEAN,
    ADD COLUMN IF NOT EXISTS ind_aceite_anexo_d                 BOOLEAN,
    ADD COLUMN IF NOT EXISTS dt_aceite_anexo_d                  TIMESTAMPTZ;

-- 18.9 PrPCI — upload obrigatório antes do download do APPCI
-- (item 6.5.1 RT Implantação SOL)
CREATE TABLE IF NOT EXISTS sol.prpci (
    id                        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appci_id                  BIGINT NOT NULL UNIQUE REFERENCES sol.appci(id),
    arquivo_id                BIGINT REFERENCES sol.arquivo(id),
    -- Componentes obrigatórios (item 6.5.1.1)
    ind_memorial_descritivo   BOOLEAN NOT NULL DEFAULT FALSE,
    ind_memoria_calculo        BOOLEAN NOT NULL DEFAULT FALSE,
    ind_certificacoes          BOOLEAN NOT NULL DEFAULT FALSE,
    ind_relatorio_ensaios      BOOLEAN NOT NULL DEFAULT FALSE,
    ind_especificacoes_tecnicas BOOLEAN NOT NULL DEFAULT FALSE,
    ind_certificados_treinamento BOOLEAN NOT NULL DEFAULT FALSE,
    ind_plano_emergencia       BOOLEAN NOT NULL DEFAULT FALSE,
    ind_laudos_tecnicos        BOOLEAN NOT NULL DEFAULT FALSE,
    criado_em                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    criado_por                 BIGINT REFERENCES sol.usuario(id)
);

-- 18.10 Tabela de feriados — dados iniciais (feriados federais e estaduais RS)
INSERT INTO sol.feriado (data, descricao, abrangencia) VALUES
    ('2025-01-01', 'Confraternização Universal',          'FEDERAL'),
    ('2025-04-18', 'Sexta-feira Santa',                   'FEDERAL'),
    ('2025-04-20', 'Páscoa',                              'FEDERAL'),
    ('2025-04-21', 'Tiradentes',                          'FEDERAL'),
    ('2025-05-01', 'Dia do Trabalhador',                  'FEDERAL'),
    ('2025-06-19', 'Corpus Christi',                      'FEDERAL'),
    ('2025-09-07', 'Independência do Brasil',             'FEDERAL'),
    ('2025-09-20', 'Proclamação da República Rio Grande do Sul', 'ESTADUAL_RS'),
    ('2025-10-12', 'Nossa Senhora Aparecida',             'FEDERAL'),
    ('2025-11-02', 'Finados',                             'FEDERAL'),
    ('2025-11-15', 'Proclamação da República',            'FEDERAL'),
    ('2025-11-20', 'Consciência Negra',                   'FEDERAL'),
    ('2025-12-25', 'Natal',                               'FEDERAL'),
    ('2026-01-01', 'Confraternização Universal',          'FEDERAL'),
    ('2026-04-03', 'Sexta-feira Santa',                   'FEDERAL'),
    ('2026-04-21', 'Tiradentes',                          'FEDERAL'),
    ('2026-05-01', 'Dia do Trabalhador',                  'FEDERAL'),
    ('2026-06-04', 'Corpus Christi',                      'FEDERAL'),
    ('2026-09-07', 'Independência do Brasil',             'FEDERAL'),
    ('2026-09-20', 'Proclamação da República Rio Grande do Sul', 'ESTADUAL_RS'),
    ('2026-10-12', 'Nossa Senhora Aparecida',             'FEDERAL'),
    ('2026-11-02', 'Finados',                             'FEDERAL'),
    ('2026-11-15', 'Proclamação da República',            'FEDERAL'),
    ('2026-11-20', 'Consciência Negra',                   'FEDERAL'),
    ('2026-12-25', 'Natal',                               'FEDERAL')
ON CONFLICT DO NOTHING;

-- 18.11 Transições válidas incluindo SUSPENSO
INSERT INTO sol.transicao_situacao_valida (de, para) VALUES
    ('AGUARD_CORRECAO_CIA', 'SUSPENSO'),   -- 6 meses sem movimentação
    ('AGUARD_CORRECAO_CIV', 'SUSPENSO'),   -- 30 dias sem solicitar re-vistoria
    ('AGUARD_VISTORIA',     'SUSPENSO'),   -- 2 anos sem movimentação com CA
    ('SUSPENSO', 'AGUARD_CORRECAO_CIA'),   -- reativação
    ('SUSPENSO', 'AGUARD_CORRECAO_CIV'),   -- reativação
    ('SUSPENSO', 'AGUARD_VISTORIA')        -- reativação
ON CONFLICT DO NOTHING;

-- 18.12 Perfil CHEFE_SSEG_BBM — adicionado ao sistema de papéis
-- (item 13.2.1 RT Implantação SOL: prerrogativa de alterar ordem de análise)
-- (item 12.1.4 RT Implantação SOL: julga recursos de 1ª instância)
INSERT INTO sol.tipo_papel (codigo, descricao) VALUES
    ('CHEFE_SSEG_BBM', 'Chefe da Seção de Segurança Contra Incêndio do BBM — pode alterar prioridade de fila e julgar recursos de 1ª instância'),
    ('MEMBRO_JUNTA_RECURSO', 'Membro da Junta de 2ª Instância para julgamento de recursos administrativos')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- FIM DO DDL
-- =============================================================================
-- Tabelas Oracle NÃO migradas (excluídas intencionalmente):
--   CBM_*_BKP_* / CBM_*_08022022 / CBM_*_18032022  → backups pontuais históricos
--   CBM_ARQUIVO_CACHE (BLOB)                         → substituído por MinIO
--   CBM_TEXTO_FORMATADO                              → inline em sol.vistoria.observacoes
--   DATABASECHANGELOG / DATABASECHANGELOGLOCK        → substituído por Flyway
-- =============================================================================
