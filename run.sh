#!/usr/bin/env bash
set -euo pipefail

# run.sh — sekali jalan untuk setup & jalanin stack

# ---- Konfigurasi yang bisa dioverride via ENV ----
COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
SERVICE_APP="${SERVICE_APP:-app}"      # contoh: laravel-app
SERVICE_WEB="${SERVICE_WEB:-web}"      # contoh: laravel-web
SERVICE_DB="${SERVICE_DB:-db}"         # nama service DB generic: 'db'
SERVICE_NODE="${SERVICE_NODE:-node}"   # contoh: siimut-node (nama service, bukan container)
NODE_BUILD="${NODE_BUILD:-true}"       # set false untuk skip npm build
CLEAN_NODE_MODULES="${CLEAN_NODE_MODULES:-false}" # true untuk rm -rf node_modules setelah build
# --------------------------------------------------

REBUILD=false
FRESH=false
DB_CHOICE="${DB_CHOICE:-${DB_DRIVER:-pgsql}}"   # pgsql | mysql
AUTO_DOTENV="${AUTO_DOTENV:-ask}"               # ask | copy | manual

usage() {
  cat <<EOF
Pemakaian: ./run.sh [opsi]

Opsi:
  --rebuild   Rebuild image sebelum up
  --fresh     down -v sebelum up (hapus data DB)
  --db <pgsql|mysql>  Pilih backend database
  -h, --help  Bantuan
Variabel ENV penting:
  COMPOSE_BIN, SERVICE_APP, SERVICE_WEB, SERVICE_DB, SERVICE_NODE,
  NODE_BUILD=[true|false], CLEAN_NODE_MODULES=[true|false],
  DB_CHOICE=pgsql|mysql (atau DB_DRIVER)
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' tidak ditemukan." >&2; exit 1; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    --fresh)   FRESH=true; shift ;;
    --db)      DB_CHOICE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opsi tidak dikenal: $1" >&2; usage; exit 2 ;;
  esac
done

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Siapkan compose flags gabungan (base + override DB)
COMPOSE_FLAGS=( -f "$PROJECT_ROOT/docker-compose.yml" )
case "$DB_CHOICE" in
  pgsql) COMPOSE_FLAGS+=( -f "$PROJECT_ROOT/docker-compose.pgsql.yml" ) ;;
  mysql) COMPOSE_FLAGS+=( -f "$PROJECT_ROOT/docker-compose.mysql.yml" ) ;;
  *) echo "DB pilihan tidak dikenal: $DB_CHOICE (gunakan pgsql|mysql)" >&2; exit 2 ;;
esac

dc() { # wrapper docker compose dengan flags yang konsisten
  $COMPOSE_BIN "${COMPOSE_FLAGS[@]}" "$@"
}

echo "[1/7] Cek dependency…"
require docker
require git
if ! docker compose version >/dev/null 2>&1; then
  echo "Error: 'docker compose' tidak tersedia." >&2; exit 1
fi

echo "[2/7] Clone/update Siimut backend ke ./site/siimut-application…"
mkdir -p "$PROJECT_ROOT/site"
chmod +x "$PROJECT_ROOT/scripts/clone_siimut_application.sh"
"$PROJECT_ROOT/scripts/clone_siimut_application.sh" --dir "$PROJECT_ROOT/site"

echo "[3/7] Siapkan .env.docker…"
AUTO_ENV_DOCKER="${AUTO_ENV_DOCKER:-ask}"   # ask|copy|env|manual
if [[ ! -f "$PROJECT_ROOT/.env.docker" ]]; then
  create_env_docker() {
    local driver="$1"; shift
    if [[ "$driver" == "mysql" ]]; then
      local db_name db_user db_pass root_pass
      db_name="${MYSQL_DATABASE:-${DB_DATABASE:-siimut}}"
      db_user="${MYSQL_USER:-${DB_USERNAME:-siimut}}"
      db_pass="${MYSQL_PASSWORD:-${DB_PASSWORD:-siimut}}"
      root_pass="${MYSQL_ROOT_PASSWORD:-root}"
      cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
DB_DRIVER=mysql
MYSQL_DATABASE=${db_name}
MYSQL_USER=${db_user}
MYSQL_PASSWORD=${db_pass}
MYSQL_ROOT_PASSWORD=${root_pass}

# Mirror untuk aplikasi
DB_DATABASE=${db_name}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}
ENVEOF
    else
      local db_name db_user db_pass
      db_name="${POSTGRES_DB:-${DB_DATABASE:-siimut}}"
      db_user="${POSTGRES_USER:-${DB_USERNAME:-siimut}}"
      db_pass="${POSTGRES_PASSWORD:-${DB_PASSWORD:-siimut}}"
      cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
DB_DRIVER=pgsql
POSTGRES_DB=${db_name}
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_pass}

# Mirror untuk aplikasi
DB_DATABASE=${db_name}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}
ENVEOF
    fi
  }

  if [[ "$AUTO_ENV_DOCKER" == "ask" ]]; then
    echo "  .env.docker belum ada. Pilih sumber konfigurasi:"
    echo "   [C]opy dari .env.docker.example (jika ada)"
    echo "   [E]nv sekarang (generate dari variabel shell)"
    echo "   [M]anual (tanya satu per satu)"
    read -r -p "  Pilihan (C/e/m) [default C]: " CH || CH="C"
  else
    CH="$AUTO_ENV_DOCKER"
  fi

  case "${CH^^}" in
    C|COPY)
      if [[ -f "$PROJECT_ROOT/.env.docker.example" ]]; then
        cp "$PROJECT_ROOT/.env.docker.example" "$PROJECT_ROOT/.env.docker"
      else
        echo "  .env.docker.example tidak ditemukan; generate dari env."
        create_env_docker "$DB_CHOICE"
      fi ;;
    E|ENV)
      create_env_docker "$DB_CHOICE" ;;
    M|MANUAL)
      echo "  Mode manual: pilih DB driver (pgsql/mysql). Default: $DB_CHOICE"
      read -r -p "  DB driver [${DB_CHOICE}]: " DB_DR_IN || DB_DR_IN=""
      DB_DR_USE=${DB_DR_IN:-$DB_CHOICE}
      if [[ "${DB_DR_USE}" == "mysql" ]]; then
        read -r -p "  MYSQL_DATABASE [${MYSQL_DATABASE:-${DB_DATABASE:-siimut}}]: " IN_DB || IN_DB=""
        read -r -p "  MYSQL_USER [${MYSQL_USER:-${DB_USERNAME:-siimut}}]: " IN_USER || IN_USER=""
        read -r -p "  MYSQL_PASSWORD [${MYSQL_PASSWORD:-${DB_PASSWORD:-siimut}}]: " IN_PASS || IN_PASS=""
        read -r -p "  MYSQL_ROOT_PASSWORD [${MYSQL_ROOT_PASSWORD:-root}]: " IN_ROOT || IN_ROOT=""
        MYSQL_DATABASE=${IN_DB:-${MYSQL_DATABASE:-${DB_DATABASE:-siimut}}}
        MYSQL_USER=${IN_USER:-${MYSQL_USER:-${DB_USERNAME:-siimut}}}
        MYSQL_PASSWORD=${IN_PASS:-${MYSQL_PASSWORD:-${DB_PASSWORD:-siimut}}}
        MYSQL_ROOT_PASSWORD=${IN_ROOT:-${MYSQL_ROOT_PASSWORD:-root}}
        cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
DB_DRIVER=mysql
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

# Mirror untuk aplikasi
DB_DATABASE=${MYSQL_DATABASE}
DB_USERNAME=${MYSQL_USER}
DB_PASSWORD=${MYSQL_PASSWORD}
ENVEOF
      else
        read -r -p "  POSTGRES_DB [${POSTGRES_DB:-${DB_DATABASE:-siimut}}]: " IN_DB || IN_DB=""
        read -r -p "  POSTGRES_USER [${POSTGRES_USER:-${DB_USERNAME:-siimut}}]: " IN_USER || IN_USER=""
        read -r -p "  POSTGRES_PASSWORD [${POSTGRES_PASSWORD:-${DB_PASSWORD:-siimut}}]: " IN_PASS || IN_PASS=""
        POSTGRES_DB=${IN_DB:-${POSTGRES_DB:-${DB_DATABASE:-siimut}}}
        POSTGRES_USER=${IN_USER:-${POSTGRES_USER:-${DB_USERNAME:-siimut}}}
        POSTGRES_PASSWORD=${IN_PASS:-${POSTGRES_PASSWORD:-${DB_PASSWORD:-siimut}}}
        cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
DB_DRIVER=pgsql
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Mirror untuk aplikasi
DB_DATABASE=${POSTGRES_DB}
DB_USERNAME=${POSTGRES_USER}
DB_PASSWORD=${POSTGRES_PASSWORD}
ENVEOF
      fi ;;
    *)
      create_env_docker "$DB_CHOICE" ;;
  esac

  echo "Dibuat: .env.docker"
else
  echo ".env.docker sudah ada — dilewati"
fi

# Hindari override APP_KEY dari environment compose
if grep -qE '^APP_KEY=' "$PROJECT_ROOT/.env.docker"; then
  echo "[3b/7] Menonaktifkan APP_KEY di .env.docker (hindari override)"
  # sed GNU & BSD kompatibel
  tmp="$(mktemp)"; awk 'BEGIN{done=0} {if(!done && $0 ~ /^APP_KEY=/){print "# APP_KEY moved to app .env"; done=1} else print $0}' "$PROJECT_ROOT/.env.docker" > "$tmp" && mv "$tmp" "$PROJECT_ROOT/.env.docker"
fi

if [[ "$FRESH" == true ]]; then
  echo "[4/7] Fresh start: docker compose down -v…"
  dc down -v || true
fi

echo "[4.5/7] Sinkronkan entrypoint ke build context (jika ada)…"
if [[ -f "$PROJECT_ROOT/docker/entrypoint.sh" ]]; then
  cp "$PROJECT_ROOT/docker/entrypoint.sh" "$PROJECT_ROOT/site/siimut-application/entrypoint.sh"
else
  echo "Warning: docker/entrypoint.sh tidak ditemukan; lewati."
fi

echo "[5/7] Build & up…"
if [[ "$REBUILD" == true ]]; then
  dc build --progress=plain
fi
dc up -d --remove-orphans

echo "[6/7] Inisialisasi Laravel…"
# Tunggu service APP siap
echo "  - Menunggu service '$SERVICE_APP' siap…"
tries=0
until dc exec -T "$SERVICE_APP" php -v >/dev/null 2>&1; do
  tries=$((tries+1)); [[ $tries -gt 30 ]] && { echo "Timeout menunggu '$SERVICE_APP'"; exit 1; }
  sleep 2
done

# Pastikan vendor ada (kepemilikan akan ditangani entrypoint saat user=root)
dc exec -T "$SERVICE_APP" sh -lc 'mkdir -p vendor' || true

# Pastikan vendor terpasang
if ! dc exec -T "$SERVICE_APP" test -f vendor/autoload.php; then
  echo "  - composer install…"
  dc exec -T "$SERVICE_APP" /bin/sh -lc 'export COMPOSER_CACHE_DIR=/tmp/composer-cache COMPOSER_HOME=/tmp/composer-home COMPOSER_TMP_DIR=/tmp; composer install --prefer-dist --no-interaction --no-progress' || true
fi

# Pastikan .env ada, dengan pilihan interaktif
if ! dc exec -T "$SERVICE_APP" test -f .env; then
  echo "[6a/7] .env tidak ditemukan di app container."

  # Fungsi bantu: baca nilai dari .env.docker
  env_from_file() {
    local key="$1"; local def="$2"; local file="$PROJECT_ROOT/.env.docker"
    if [[ -f "$file" ]]; then
      local line
      line=$(grep -E "^${key}=" "$file" | tail -n1 | sed -E 's/^[^=]+=//') || true
      if [[ -n "$line" ]]; then printf '%s' "$line"; else printf '%s' "$def"; fi
    else
      printf '%s' "$def"
    fi
  }

  # Default kredensial berdasar pilihan DB
  if [[ "$DB_CHOICE" == "mysql" ]]; then
    DEF_DB_NAME="$(env_from_file MYSQL_DATABASE "${DB_DATABASE:-laravel}")"; [[ -z "$DEF_DB_NAME" ]] && DEF_DB_NAME="laravel"
    DEF_DB_USER="$(env_from_file MYSQL_USER "${DB_USERNAME:-laravel}")";    [[ -z "$DEF_DB_USER" ]] && DEF_DB_USER="laravel"
    DEF_DB_PASS="$(env_from_file MYSQL_PASSWORD "${DB_PASSWORD:-laravel}")"; [[ -z "$DEF_DB_PASS" ]] && DEF_DB_PASS="laravel"
    DEF_DB_PORT=3306
  else
    DEF_DB_NAME="$(env_from_file POSTGRES_DB "${DB_DATABASE:-laravel}")";    [[ -z "$DEF_DB_NAME" ]] && DEF_DB_NAME="laravel"
    DEF_DB_USER="$(env_from_file POSTGRES_USER "${DB_USERNAME:-laravel}")"; [[ -z "$DEF_DB_USER" ]] && DEF_DB_USER="laravel"
    DEF_DB_PASS="$(env_from_file POSTGRES_PASSWORD "${DB_PASSWORD:-laravel}")"; [[ -z "$DEF_DB_PASS" ]] && DEF_DB_PASS="laravel"
    DEF_DB_PORT=5432
  fi

  if [[ "$AUTO_DOTENV" == "ask" ]]; then
    echo "  Pilihan: [C]opy dari .env.example, [M]anual isi kredensial (default: C)"
    read -r -p "  Buat .env sekarang? (C/m): " CHOICE || CHOICE="C"
  else
    CHOICE="$AUTO_DOTENV"
  fi

  case "${CHOICE^^}" in
    M|MANUAL)
      echo "  Mode manual: isi beberapa nilai (biarkan kosong untuk default)."
      read -r -p "  APP_NAME (default: Laravel): " APP_NAME_IN || APP_NAME_IN=""
      read -r -p "  APP_URL (default: http://localhost:8080): " APP_URL_IN || APP_URL_IN=""
      # DB settings
      if [[ "$DB_CHOICE" == "mysql" ]]; then
        read -r -p "  DB_HOST (default: db): " DB_HOST_IN || DB_HOST_IN=""
        read -r -p "  DB_PORT (default: $DEF_DB_PORT): " DB_PORT_IN || DB_PORT_IN=""
      else
        read -r -p "  DB_HOST (default: db): " DB_HOST_IN || DB_HOST_IN=""
        read -r -p "  DB_PORT (default: $DEF_DB_PORT): " DB_PORT_IN || DB_PORT_IN=""
      fi
      read -r -p "  DB_DATABASE (default: $DEF_DB_NAME): " DB_NAME_IN || DB_NAME_IN=""
      read -r -p "  DB_USERNAME (default: $DEF_DB_USER): " DB_USER_IN || DB_USER_IN=""
      read -r -p "  DB_PASSWORD (default: $DEF_DB_PASS): " DB_PASS_IN || DB_PASS_IN=""

      APP_NAME_VAL=${APP_NAME_IN:-Laravel}
      APP_URL_VAL=${APP_URL_IN:-http://localhost:8080}
      DB_HOST_VAL=${DB_HOST_IN:-db}
      DB_PORT_VAL=${DB_PORT_IN:-$DEF_DB_PORT}
      DB_NAME_VAL=${DB_NAME_IN:-$DEF_DB_NAME}
      DB_USER_VAL=${DB_USER_IN:-$DEF_DB_USER}
      DB_PASS_VAL=${DB_PASS_IN:-$DEF_DB_PASS}

      # Buat .env dari example jika ada, lalu set nilai
      if dc exec -T "$SERVICE_APP" test -f .env.example; then
        dc exec -T "$SERVICE_APP" cp .env.example .env || true
      else
        dc exec -T "$SERVICE_APP" sh -lc 'touch .env'
      fi
      dc exec -T "$SERVICE_APP" /bin/sh -lc '
        set -e;
        set_kv() { k="$1"; v="$2"; if grep -qE "^${k}=.*$" .env; then sed -i "s#^${k}=.*#${k}=${v}#" .env; else echo "${k}=${v}" >> .env; fi; };
        set_kv APP_NAME '"$APP_NAME_VAL"';
        set_kv APP_URL '"$APP_URL_VAL"';
        if [ '"$DB_CHOICE"' = mysql ]; then set_kv DB_CONNECTION mysql; else set_kv DB_CONNECTION pgsql; fi;
        set_kv DB_HOST '"$DB_HOST_VAL"';
        set_kv DB_PORT '"$DB_PORT_VAL"';
        set_kv DB_DATABASE '"$DB_NAME_VAL"';
        set_kv DB_USERNAME '"$DB_USER_VAL"';
        set_kv DB_PASSWORD '"$DB_PASS_VAL"';
      '
      ;;
    C|COPY|*)
      echo "  Menyalin .env.example ke .env"
      dc exec -T "$SERVICE_APP" php -r 'file_exists(".env") || copy(".env.example", ".env");' || true
      ;;
  esac
fi

# Sinkron DB config lebih awal (sebelum clear cache yang bisa akses DB)
dc exec -T "$SERVICE_APP" /bin/sh -lc 'set -e; \
  set_kv() { k="$1"; v="$2"; if grep -qE "^${k}=.*$" .env; then sed -i "s#^${k}=.*#${k}=${v}#" .env; else echo "${k}=${v}" >> .env; fi; }; \
  if [ "$DB_CHOICE" = "mysql" ]; then \
    set_kv DB_CONNECTION mysql; \
    set_kv DB_HOST '"$SERVICE_DB"'; \
    set_kv DB_PORT 3306; \
    set_kv DB_DATABASE "${MYSQL_DATABASE:-${DB_DATABASE:-laravel}}"; \
    set_kv DB_USERNAME "${MYSQL_USER:-${DB_USERNAME:-laravel}}"; \
    set_kv DB_PASSWORD "${MYSQL_PASSWORD:-${DB_PASSWORD:-laravel}}"; \
  else \
    set_kv DB_CONNECTION pgsql; \
    set_kv DB_HOST '"$SERVICE_DB"'; \
    set_kv DB_PORT 5432; \
    set_kv DB_DATABASE "${POSTGRES_DB:-${DB_DATABASE:-laravel}}"; \
    set_kv DB_USERNAME "${POSTGRES_USER:-${DB_USERNAME:-laravel}}"; \
    set_kv DB_PASSWORD "${POSTGRES_PASSWORD:-${DB_PASSWORD:-laravel}}"; \
  fi; \
'

# Bersih cache config (hindari MissingAppKey/akses DB dengan host lama)
dc exec -T "$SERVICE_APP" sh -lc 'rm -f bootstrap/cache/config.php bootstrap/cache/services.php || true'
dc exec -T "$SERVICE_APP" sh -lc 'CACHE_DRIVER=file php artisan optimize:clear || true'

# APP_KEY + migrasi + storage link
dc exec -T "$SERVICE_APP" php artisan key:generate --force || true
dc exec -T "$SERVICE_APP" php -r 'if(!preg_match("/^APP_KEY=.+$/m", file_get_contents(".env"))){$k="base64:".base64_encode(random_bytes(32)); $e=file_get_contents(".env"); if(preg_match("/^APP_KEY=.*$/m",$e)){$e=preg_replace("/^APP_KEY=.*$/m","APP_KEY=".$k,$e);}else{$e.="\nAPP_KEY=".$k."\n";} file_put_contents(".env",$e);}'

dc exec -T "$SERVICE_APP" php artisan migrate --force || true
dc exec -T "$SERVICE_APP" php artisan storage:link || true
# Izinkan git bekerja pada bind mount (hindari "dubious ownership")
dc exec -T "$SERVICE_APP" git config --global --add safe.directory /var/www/html || true
# Paksa jalankan setup meskipun APP_ENV=production dengan mengonfirmasi prompt artisan
dc exec -T "$SERVICE_APP" /bin/sh -lc 'yes | composer run --no-interaction setup' || true

# ---- Bagian Node/npm (sekali jalan) ----
if [[ "$NODE_BUILD" == "true" ]]; then
  echo "[6b/7] Build frontend (npm)…"
  # Gunakan `run --rm` agar tidak butuh service node selalu hidup.
  if dc config --services | grep -qx "$SERVICE_NODE"; then
    # Pastikan direktori build bisa ditulis oleh user Node
    dc run --rm "$SERVICE_NODE" /bin/sh -lc 'mkdir -p public/build/assets && chmod -R 0777 public/build' || true
    dc run --rm "$SERVICE_NODE" npm ci || dc run --rm "$SERVICE_NODE" npm install
    dc run --rm "$SERVICE_NODE" npm run build
    if [[ "$CLEAN_NODE_MODULES" == "true" ]]; then
      dc run --rm "$SERVICE_NODE" /bin/sh -lc 'rm -rf node_modules'
    fi
  else
    echo "  - Warning: service '$SERVICE_NODE' tidak didefinisikan di docker-compose; lewati build frontend."
  fi
else
  echo "[6b/7] Skip build frontend (NODE_BUILD=false)"
fi

# Cache config untuk production
dc exec -T "$SERVICE_APP" sh -lc 'if [ "${APP_ENV:-production}" = "production" ]; then php artisan config:cache || true; fi'

echo
echo "[7/7] Selesai! Aplikasi siap di: http://localhost:8080"
echo "Kontainer: $SERVICE_WEB (web), $SERVICE_APP (php-fpm), $SERVICE_DB (db:$DB_CHOICE)$( [[ "$NODE_BUILD" == "true" ]] && echo ", $SERVICE_NODE (npm run)")"
