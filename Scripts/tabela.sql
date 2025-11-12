CREATE EXTENSION postgis;

CREATE TABLE mask_restauracao as
SELECT id, geom FROM vegeta_inema_2019 vi 
WHERE nivel_1 NOT LIKE 'Áreas antropizadas';

CREATE INDEX ON mask_restauracao USING gist (geom);

CREATE TABLE restauracao (
    id SERIAL PRIMARY KEY,
    geom geometry(MultiPolygon, 4674),
    date DATE,
);

CREATE INDEX ON restauracao USING gist (geom);

ALTER TABLE public.restauracao
ADD COLUMN usuario_id INTEGER,
ADD CONSTRAINT fk_restauracao_usuario
    FOREIGN KEY (usuario_id)
    REFERENCES dominio.usuario (id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
ADD CONSTRAINT chk_restauracao_geom_not_empty
    CHECK (NOT ST_IsEmpty(geom));

ALTER TABLE restauracao
ADD CONSTRAINT geom_not_empty CHECK (NOT ST_IsEmpty(geom));

ALTER TABLE restauracao
ALTER COLUMN geom SET NOT NULL;

ALTER TABLE restauracao
ALTER COLUMN date SET NOT NULL;

ALTER TABLE restauracao
ALTER COLUMN url SET NOT NULL;

-- ===========================================================
-- 🧮 ADICIONAR COLUNA DE ÁREA (ha) NA TABELA restauracao
-- ===========================================================
ALTER TABLE restauracao
ALTER COLUMN area_ha TYPE NUMERIC(12,4)
USING ROUND(area_ha::numeric, 4);

-- ===========================================================
-- 🔁 ATUALIZAR VALORES EXISTENTES COM BASE NA GEOMETRIA
-- ===========================================================
UPDATE restauracao
SET area_ha = ST_Area(ST_Transform(geom, 5555)) / 10000.0;

-- ===========================================================
-- 🔁 DEFINIÇÃO DE ÁREA MÍNIMA MAPEAVEL == 1ha
-- =====================================================
ALTER TABLE restauracao
ADD CONSTRAINT chk_restauracao_area_minima
CHECK (area_ha > 1);

-- ### Criando as tabelas de usuários
CREATE SCHEMA IF NOT EXISTS dominio;
 
CREATE TABLE dominio.usuario (
    id SERIAL PRIMARY KEY,
    nome TEXT UNIQUE NOT NULL,
    nome_completo TEXT,
    email TEXT
);

-- LOG TABELA RESTAURACAO
DROP TABLE restauracao_log;

CREATE TABLE restauracao_log (
    id SERIAL PRIMARY KEY,
    id_registro INTEGER,
    operacao TEXT NOT NULL,
    usuario_id INTEGER NOT NULL,
    data_hora TIMESTAMP DEFAULT now(),
    old_data JSONB,
    new_data JSONB,
    query TEXT,
    CONSTRAINT fk_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES dominio.usuario (id)
        ON UPDATE CASCADE -- Se o id do usuário for alterado há correção automática
);