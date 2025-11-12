-- ===========================================================
-- 👤 INSERÇÃO DE USUÁRIOS NA TABELA dominio.usuario
-- ===========================================================
INSERT INTO dominio.usuario (nome, nome_completo, email)
VALUES
    -- ('diogo.caribe', 'Diogo Caribé', 'diogo.caribe@sema.ba.gov.br'), -- Grupo Superuser
    -- ('paloma.avena', 'Paloma Avena', 'paloma.avena@sema.ba.gov.br'), -- Grupo Editor
    ('renata.jesus', 'Renata Jesus', 'renata.jesus@sema.ba.gov.br'); -- Grupo Editor

-- ===========================================================
-- 🔐 CRIAÇÃO DE USUÁRIOS E REGRAS DE ACESSO AO BANCO
-- ===========================================================

-- Usuário: diogo.caribe (superuser)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'diogo.caribe') THEN
        CREATE ROLE "diogo.caribe" LOGIN PASSWORD 'S3nh@F0rt3!';
    END IF;
END;
$$;

-- Usuário: paloma.avena (editor)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'renata.jesus') THEN
        CREATE ROLE "renata.jesus" LOGIN PASSWORD '123456';
    END IF;
END;
$$;

-- ===========================================================
-- 🧩 CRIAÇÃO DE GRUPO DE SUPERUSUÁRIOS
-- ===========================================================

-- 1️⃣ Criar o grupo de superusuários, se ainda não existir
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = 'grupo_admin'
    ) THEN
        CREATE ROLE grupo_admin WITH
            SUPERUSER
            CREATEDB
            CREATEROLE
            INHERIT;
    END IF;
END;
$$;

-- 2️⃣ Adicionar o usuário diogo.caribe ao grupo
GRANT grupo_admin TO "diogo.caribe";

-- ===========================================================
-- 🧩 CRIAÇÃO DO GRUPO DE EDIÇÃO
-- ===========================================================

-- 1️⃣ Criar o grupo de edição, se ainda não existir
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = 'editor'
    ) THEN
        CREATE ROLE editor WITH
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            INHERIT
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
END;
$$;

-- Permissões de edição na view
GRANT INSERT, UPDATE, DELETE, SELECT
ON TABLE public.vw_restauracao_edit
TO editor;

-- Permissão para edição da tabela log
GRANT INSERT, UPDATE, DELETE, SELECT
ON TABLE public.restauracao_log
TO editor;

-- Permitir SELECT na tabela de máscara
GRANT SELECT
ON TABLE public.mask_restauracao
TO editor;

-- Permitir SELECT na tabela restauracao (necessário para a trigger)
GRANT SELECT
ON TABLE public.restauracao
TO editor;

-- Permitir SELECT na tabela de máscara
GRANT SELECT
ON TABLE dominio.usuario
TO editor;

-- Permissão sobre a sequência usada em restauracao.id
GRANT USAGE, SELECT, UPDATE
ON SEQUENCE public.restauracao_id_seq
TO editor;

-- Permissão edicao da sequencia da restauracao_log_id_seq
GRANT USAGE, SELECT, UPDATE
ON SEQUENCE public.restauracao_log_id_seq
TO editor;

-- Garantir permissão de uso do schema
GRANT USAGE ON SCHEMA public TO editor;
GRANT USAGE ON SCHEMA dominio TO editor;

-- Adicionar o usuário paloma.avena ao grupo editor
GRANT editor TO "paloma.avena";
GRANT editor TO "renata.jesus";

-- ===========================================================
-- 🔧 PERMISSÕES ADICIONAIS DE CONEXÃO AO BANCO
-- ===========================================================

-- Permitir que ambos os usuários possam conectar-se ao banco atual
GRANT CONNECT ON DATABASE restauracao TO "diogo.caribe";
GRANT CONNECT ON DATABASE restauracao TO "paloma.avena";
GRANT CONNECT ON DATABASE restauracao TO "renata.jesus";

-- (opcional) Permitir uso dos schemas principais
GRANT USAGE ON SCHEMA public TO "diogo.caribe";
GRANT USAGE ON SCHEMA public TO "paloma.avena";
GRANT USAGE ON SCHEMA public TO "renata.jesus";
GRANT USAGE ON SCHEMA dominio TO "paloma.avena";
GRANT USAGE ON SCHEMA dominio TO "renata.jesus";
