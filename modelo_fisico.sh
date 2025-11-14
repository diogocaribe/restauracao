#!/bin/bash
# set -e

# Caminho absoluto do .env (ajuste se necessário)
ENV_FILE="$(dirname "$0")/.env"

if [ -f "$ENV_FILE" ]; then
    echo "📄 Carregando variáveis do .env..."
    set -a
    . "$ENV_FILE"
    set +a
else
    echo "❌ Arquivo .env não encontrado em $ENV_FILE"
    exit 1
fi

# echo "🔎 Variáveis carregadas do .env:"
# grep -v '^#' "$ENV_FILE"


# --- Carregar variáveis do .env ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exporta senha para o psql
export PGPASSWORD="$PASSWORD"

# --- Diretório dos arquivos SQL ---
SQL_DIR="${ROOT_DIR}/Scripts"
echo "📂 Diretório dos arquivos SQL: $SQL_DIR"

# =========================================================================================
# 🧱 Criar banco, se não existir
# =========================================================================================
EXISTS=$("$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -tAc \
"SELECT 1 FROM pg_database WHERE datname='${DB}'")

if [ "$EXISTS" != "1" ]; then
    echo "🚀 Criando banco de dados '${DB}'..."
    echo "$PSQL_CMD -h $HOST -p $PORT -U $USER -d postgres -c 'CREATE DATABASE $DB;'"
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -c "CREATE DATABASE $DB;"
    echo "🚀 banco de dados '${DB}' criado com SUCESSO!"
else
    echo "✅ Banco '${DB}' já existe."
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB}';"
    
    echo "✅ Apagando banco '${DB}' existente."
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -c \
    "DROP DATABASE ${DB};"
    
    echo "🚀 Criando banco de dados '${DB}'..."
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -c "CREATE DATABASE $DB;"
    echo "🚀 banco de dados '${DB}' criado com SUCESSO!"
fi

# =========================================================================================
# Ativar extensão PostGIS no banco
# =========================================================================================
echo "🚀 Ativando PostGIS no banco '$DB' (se ainda não estiver ativo)..."
"$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
# =========================================================================================
# Caminho do shapefile
SHAPE_FILE="${ROOT_DIR}/dados/cartografia_sistematica.shp"

# Nome da tabela no PostGIS
TABLE_NAME=cartografia_sistematica

# Schema do banco (opcional, default: public)
SCHEMA=articulacao

# Garante que o schema exista
"$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
    -c "CREATE SCHEMA IF NOT EXISTS \"$SCHEMA\";"

# --- Verificação do tamanho da tabela ---
echo "🚀 Carregando shapefile para $SCHEMA.$TABLE_NAME"

# Verifica se a tabela existe
TABELA_EXISTE=$(
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc \
    "SELECT 1 FROM information_schema.tables 
     WHERE table_schema='$SCHEMA' AND table_name='$TABLE_NAME';"
)

if [ "$TABELA_EXISTE" = "1" ]; then
    # Só consulta o tamanho se a tabela existir
    TAM_TABELA=$(
        "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc \
        "SELECT pg_relation_size('$SCHEMA.$TABLE_NAME');"
    )
else
    TAM_TABELA=0
fi

echo "Tamanho em bytes: $TAM_TABELA"

# Se não existir ou estiver com o tamanho mínimo (vazia):
if [ "$TAM_TABELA" -eq 0 ] || [ "$TAM_TABELA" -le 8192 ]; then
    echo "📥 Tabela vazia ou inexistente — importando shapefile..."
    "$SHP2PGSQL_CMD" -D -I -s 4674 -W 'UTF-8' -g geom -c \
        "$SHAPE_FILE" "$SCHEMA.$TABLE_NAME" | \
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB"
else
    echo "✅ Tabela já possui dados (tamanho = $TAM_ARTICULACAO_SISTEMATICA bytes). Nada será carregado."
fi

# =========================================================================================
# Caminho do shapefile
SHAPE_FILE="${ROOT_DIR}/dados/vegetacao_inema_2019.shp"

# Nome da tabela no PostGIS
TABLE_NAME="vegetacao_inema_2019"

# Schema do banco (opcional, default: public)
SCHEMA=public

echo "🔍 Verificando tabela $SCHEMA.$TABLE_NAME ..."

# 1) Verifica se a tabela existe
TABELA_EXISTE=$(
    "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc \
    "SELECT 1 FROM information_schema.tables 
     WHERE table_schema='${SCHEMA}' AND table_name='${TABLE_NAME}';"
)

# 2) Se existir, pega o tamanho real. Se não existir, tamanho = 0
if [ "$TABELA_EXISTE" = "1" ]; then
    TAM_TABELA=$(
        "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tAc \
        "SELECT pg_relation_size('${SCHEMA}.${TABLE_NAME}');"
    )
else
    TAM_TABELA=0
fi

echo "📏 Tamanho atual da tabela $SCHEMA.$TABLE_NAME = ${TAM_TABELA} bytes"

# 3) Regra: tamanho 0 ou menor que 8KB → importa shapefile
if [ "$TAM_TABELA" -eq 0 ] || [ "$TAM_TABELA" -le 8192 ]; then
    echo "📥 Tabela vazia ou inexistente — importando shapefile..."

    "$SHP2PGSQL_CMD" -D -I -s 4674 -W 'UTF-8' -g geom -c \
        "$SHAPE_FILE" "$SCHEMA.$TABLE_NAME" | \
        "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB"

else
    echo "✅ Tabela já possui dados. Importação não será executada."
fi
-- =========================================================================================

# --- Lista dos arquivos SQL ---
SQL_FILES=(
    "epsg_sirgas_2000_albers.sql"
    # "grupo_usuario.sql"
    # "tabela.sql"
    # "trigger.sql"
    # "view.sql"
)

# --- Executar os scripts ---
for FILE in "${SQL_FILES[@]}"; do
    FILE_PATH="${SQL_DIR}/${FILE}"
    if [ -f "$FILE_PATH" ]; then
        # echo "🚀 Executando: $FILE_PATH"
        if [[ "$FILE" == "create_database.sql" ]]; then
            # Usa o banco postgres para criar o novo banco
            "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d postgres -a -f "$FILE_PATH"
        else
            # Usa o banco definido no .env (já criado)
            "$PSQL_CMD" -h "$HOST" -p "$PORT" -U "$USER" -d "$POSTGRES_DB" -a -f "$FILE_PATH"
        fi
    else
        echo "⚠️ Arquivo não encontrado: $FILE_PATH"
    fi
done

echo "🎯 Execução finalizada com sucesso!"
