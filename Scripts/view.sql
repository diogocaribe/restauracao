---------------------------------------------------
-- VIEW EDITÁVEL PARA CAMADA RESTAURAÇÃO
---------------------------------------------------
CREATE OR REPLACE VIEW public.vw_restauracao_edit
AS SELECT r.id,
    r.geom::geometry(MultiPolygon,4674) AS geom,
    r.date,
    r.usuario_id,
    u.nome AS usuario_nome,
    r.url,
    round((st_area(st_transform(r.geom, 5555)) / 10000::double precision)::numeric, 4) AS area_ha
   FROM restauracao r
   LEFT JOIN dominio.usuario u ON u.id = r.usuario_id;


---------------------------------------------------
-- REGRA DE INSERÇÃO
---------------------------------------------------
CREATE OR REPLACE RULE vw_restauracao_edit_insert AS
ON INSERT TO vw_restauracao_edit DO INSTEAD
INSERT INTO restauracao (geom, date, usuario_id, url, area_ha)
VALUES (
    NEW.geom,
    NEW.date,
    NEW.usuario_id,
    NEW.url,
    ROUND(CAST(ST_Area(ST_Transform(NEW.geom, 5555)) / 10000 AS numeric), 4)
)
RETURNING
    id,
    geom::geometry(MultiPolygon, 4674),
    date,
    usuario_id,
    (SELECT nome FROM dominio.usuario WHERE id = usuario_id) AS usuario_nome,
    url,
    area_ha;


---------------------------------------------------
-- REGRA DE ATUALIZAÇÃO
---------------------------------------------------
CREATE OR REPLACE RULE vw_restauracao_edit_update AS
ON UPDATE TO vw_restauracao_edit DO INSTEAD
UPDATE restauracao
SET
    geom = NEW.geom,
    date = NEW.date,
    usuario_id = NEW.usuario_id,
    url = NEW.url,
    area_ha = ROUND(CAST(ST_Area(ST_Transform(NEW.geom, 5555)) / 10000 AS numeric), 4)
WHERE id = OLD.id
RETURNING
    id,
    geom::geometry(MultiPolygon, 4674),
    date,
    usuario_id,
    (SELECT nome FROM dominio.usuario WHERE id = usuario_id) AS usuario_nome,
    url,
    area_ha;


---------------------------------------------------
-- REGRA DE EXCLUSÃO
---------------------------------------------------
CREATE OR REPLACE RULE vw_restauracao_edit_delete AS
ON DELETE TO vw_restauracao_edit DO INSTEAD
DELETE FROM restauracao
WHERE id = OLD.id
RETURNING
    id,
    geom::geometry(MultiPolygon, 4674),
    date,
    usuario_id,
    (SELECT nome FROM dominio.usuario WHERE id = usuario_id) AS usuario_nome,
    url,
    area_ha;

-------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON vw_restauracao_edit TO editor;
