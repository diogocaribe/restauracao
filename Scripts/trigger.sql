/* ===================================================================================================
   FUNÇÃO: enforce_mask_rule()
   ---------------------------------------------------------------------------------------------------
   OBJETIVO:
     Esta função é responsável por **garantir que novas geometrias inseridas ou atualizadas**
     na tabela `restauracao` estejam **contidas dentro da máscara espacial de vegetação natural**
     (`mask_restauracao`).  

   FUNCIONAMENTO:
     1. Verifica se a nova geometria (`NEW.geom`) possui interseção com a máscara (`mask_restauracao`);
     2. Se houver interseção, ocorre a operação de diferença simetrica; 
     3. Se não houver interseção, é levantada uma exceção informando que a área esta totalmente na área da mascara
     e a geometria gerada é vazia;

   BENEFÍCIOS:
     🌿 Garante que todas as áreas de restauração estejam dentro dos limites ecológicos definidos;
     🧭 Mantém a coerência espacial entre as camadas do banco;
     🔒 Evita erros de digitação ou inserção acidental de geometrias inválidas.

   OBSERVAÇÕES:
     - CRS (Sistema de Referência de Coordenadas): EPSG:4674 (SIRGAS 2000)
     - A tabela `mask_restauracao` deve existir e conter as áreas válidas para restauração.
     - Recomenda-se o uso em conjunto com a trigger `trg_enforce_mask_rule`
       (BEFORE INSERT OR UPDATE ON restauracao).

   AUTOR: Diogo Caribé
   DATA DE CRIAÇÃO: 06/11/2025
================================================================================================ */

CREATE OR REPLACE FUNCTION mask_rule()
RETURNS TRIGGER SECURITY DEFINER AS
$$
DECLARE
  mask_geom geometry;
  existing_geom geometry;
BEGIN
  -- Seleciona as geometrias onde há intersecção com a mascara
  SELECT ST_Union(m.geom) INTO mask_geom
  FROM mask_restauracao m
  WHERE m.geom && NEW.geom
    AND ST_Intersects(m.geom, NEW.geom);

  IF mask_geom IS NOT NULL THEN
    NEW.geom := ST_Difference(NEW.geom, mask_geom);

	IF ST_IsEmpty(NEW.geom) THEN
      RAISE EXCEPTION 'Geometria inválida: toda a área sobrepõe a máscara';
    END IF;
  END IF;

  -- Normaliza a geometria final (remove geometrias inválidas e força MultiPolygon)
  NEW.geom := ST_Multi(ST_CollectionExtract(ST_MakeValid(NEW.geom), 3));

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- Apagar a trigger
DROP TRIGGER IF EXISTS trg_restauracao_mask ON restauracao;

CREATE TRIGGER trg_restauracao_mask
BEFORE INSERT OR UPDATE ON restauracao
FOR EACH ROW
EXECUTE FUNCTION mask_rule();

/* ===================================================================================================
   TRIGGER: trg_restauracao_intersect
   ---------------------------------------------------------------------------------------------------
   OBJETIVO:
     Esta trigger é executada **antes da inserção** de um novo registro na tabela `restauracao`.
     Ela verifica se a nova geometria (`NEW.geom`) **intersecta** alguma geometria já existente
     na própria tabela. Caso exista interseção, é gerado um erro, impedindo a sobreposição de áreas.

   FUNCIONAMENTO:
     1. Agrega todas as geometrias existentes que intersectam com a nova geometria (`NEW.geom`);
     2. Se houver interseção, levanta uma exceção informando que a área já está cadastrada;
     3. Caso contrário, permite a inserção normalmente.

   BENEFÍCIOS:
     🔹 Garante a integridade espacial da base de restauração;
     🔹 Evita duplicidade e sobreposição de polígonos;
     🔹 Mantém a consistência dos dados no banco de forma automática.

   OBSERVAÇÕES:
     - CRS (Sistema de Referência de Coordenadas): EPSG:4674 (SIRGAS 2000)
     - Necessário que a extensão `postgis` esteja habilitada no banco de dados.
     - Função associada: `fn_restauracao_check_intersect()`

   AUTOR: Diogo Caribé
   DATA DE CRIAÇÃO: 06/11/2025
================================================================================================ */

CREATE OR REPLACE FUNCTION check_intersection_before_insert()
RETURNS TRIGGER SECURITY DEFINER AS
$$
DECLARE
    existing_geom geometry;
BEGIN
    -- Busca a união das geometrias existentes que intersectam a nova geometria
    SELECT ST_Union(r.geom)
    INTO existing_geom
    FROM restauracao r
    WHERE r.geom && NEW.geom
      AND ST_Intersects(r.geom, NEW.geom)
      AND (TG_OP = 'INSERT' OR r.id <> NEW.id); -- evita auto-interseção no UPDATE

    -- Se encontrar interseções, recorta ou impede o insert/update
    IF existing_geom IS NOT NULL THEN
        RAISE NOTICE 'Geometria intersectou a tabela restauracao';

        NEW.geom := ST_Difference(NEW.geom, existing_geom);

        IF ST_IsEmpty(NEW.geom) THEN
            RAISE EXCEPTION 'A geometria resultante é vazia após o recorte. Operação cancelada.';
        END IF;
    END IF;

    -- Normaliza a geometria final
    NEW.geom := ST_Multi(ST_CollectionExtract(ST_MakeValid(NEW.geom), 3));

    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_insert_restauracao ON restauracao;

CREATE TRIGGER trg_insert_restauracao
BEFORE INSERT OR UPDATE ON restauracao
FOR EACH ROW
EXECUTE FUNCTION check_intersection_before_insert();

/* ===================================================================================================
   TRIGGER: trg_set_usuario_id_restauracao
   ---------------------------------------------------------------------------------------------------
================================================================================================ */

CREATE OR REPLACE FUNCTION set_usuario_id()
RETURNS TRIGGER AS
$$
DECLARE
    v_usuario_id INTEGER;
BEGIN
    -- Tenta encontrar o id do usuário com base no CURRENT_USER (ou SESSION_USER)
    SELECT id INTO v_usuario_id
    FROM dominio.usuario
    WHERE nome = CURRENT_USER
    LIMIT 1;

    -- Caso não encontre, pode deixar nulo ou lançar erro
    IF v_usuario_id IS NULL THEN
        RAISE NOTICE 'Usuário "%" não encontrado em dominio.usuario', CURRENT_USER;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.usuario_id := v_usuario_id;
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.usuario_id := v_usuario_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_usuario_id
BEFORE INSERT OR UPDATE ON restauracao
FOR EACH ROW
EXECUTE FUNCTION set_usuario_id();

/* ===================================================================================================
   TRIGGER: trg_log_operacoes
   ---------------------------------------------------------------------------------------------------
=================================================================================================== */

CREATE OR REPLACE FUNCTION log_restauracao_operacoes()
RETURNS TRIGGER AS
$$
DECLARE
    v_query TEXT;
    v_usuario_id INTEGER;
BEGIN
    -- Captura a consulta SQL executada
    SELECT query INTO v_query
    FROM pg_stat_activity
    WHERE pid = pg_backend_pid();

    -- Tenta obter o id pela variável de sessão (se definida)
    BEGIN
        v_usuario_id := current_setting('dominio.user.id', true)::INTEGER;
    EXCEPTION WHEN others THEN
        v_usuario_id := NULL;
    END;

    -- Se não veio pela sessão, tenta mapear pelo current_user na tabela dominio.usuario
    IF v_usuario_id IS NULL THEN
        SELECT id INTO v_usuario_id
        FROM dominio.usuario
        WHERE nome = current_user
        LIMIT 1;
    END IF;

    -- Se ainda não encontrou, aborta com mensagem clara (evita inserir NULL e violar FK)
    IF v_usuario_id IS NULL THEN
        RAISE EXCEPTION
          'log_restauracao_operacoes: usuario_id nao encontrado. Defina a variavel de sessao ''dominio.user.id'' ou cadastre o usuario "%"/associe-o em dominio.usuario.',
          current_user;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO restauracao_log (id_registro, operacao, usuario_id, new_data, query)
        VALUES (NEW.id, 'INSERT', v_usuario_id, row_to_json(NEW), v_query);

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO restauracao_log (id_registro, operacao, usuario_id, old_data, new_data, query)
        VALUES (OLD.id, 'UPDATE', v_usuario_id, row_to_json(OLD), row_to_json(NEW), v_query);

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO restauracao_log (id_registro, operacao, usuario_id, old_data, query)
        VALUES (OLD.id, 'DELETE', v_usuario_id, row_to_json(OLD), v_query);
    END IF;

    RETURN NULL; -- AFTER trigger: valor retornado é ignorado
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_restauracao ON restauracao;

CREATE TRIGGER trg_log_restauracao
AFTER INSERT OR UPDATE OR DELETE ON restauracao
FOR EACH ROW
EXECUTE FUNCTION log_restauracao_operacoes();

/* ===================================================================================================
   TRIGGER: 
   ---------------------------------------------------------------------------------------------------
=================================================================================================== */