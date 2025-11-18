#!/usr/bin/env bash
set -euo pipefail

# run.sh — sekali jalan untuk setup & jalanin stack

# ---- Konfigurasi yang bisa dioverride via ENV ----
COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
SERVICE_WEB="${SERVICE_WEB:-web}"      # shared web server
SERVICE_DB="${SERVICE_DB:-db}"         # nama service DB generic: 'db'
SERVICE_NODE="${SERVICE_NODE:-node}"   # shared node container
NODE_BUILD="${NODE_BUILD:-true}"       # set false untuk skip npm build
CLEAN_NODE_MODULES="${CLEAN_NODE_MODULES:-false}" # true untuk rm -rf node_modules setelah build

# Multi-project configuration
PROJECTS="${PROJECTS:-siimut iam client}"  # space-separated list
declare -A PROJECT_SERVICES=(
  ["siimut"]="app-siimut"
  ["iam"]="app-iam"
  ["client"]="app-client"
)
declare -A PROJECT_DIRS=(
  ["siimut"]="site/siimut-application"
  ["iam"]="site/laravel-iam"
  ["client"]="site/client-iiam"
)
declare -A PROJECT_PORTS=(
  ["siimut"]="8080"
  ["iam"]="8081"
  ["client"]="8082"
)
declare -A PROJECT_NODE_DIRS=(
  ["siimut"]="/var/www/siimut"
  ["iam"]="/var/www/iam"
  ["client"]="/var/www/client"
)
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
  --projects <list>   Pilih projects yang akan di-setup (default: "siimut iam client")
                      Contoh: --projects "siimut iam"
  -h, --help  Bantuan
Variabel ENV penting:
  COMPOSE_BIN, SERVICE_WEB, SERVICE_DB, SERVICE_NODE,
  NODE_BUILD=[true|false], CLEAN_NODE_MODULES=[true|false],
  DB_CHOICE=pgsql|mysql (atau DB_DRIVER),
  PROJECTS="siimut iam client" (atau kombinasi)
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' tidak ditemukan." >&2; exit 1; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    --fresh)   FRESH=true; shift ;;
    --db)      DB_CHOICE="$2"; shift 2 ;;
    --projects) PROJECTS="$2"; shift 2 ;;
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

echo "[2/7] Clone/update project repositories…"
mkdir -p "$PROJECT_ROOT/site"

for proj in $PROJECTS; do
  proj_dir="${PROJECT_DIRS[$proj]}"
  case "$proj" in
    siimut)
      echo "  - Setting up SI-IMUT…"
      if [[ -x "$PROJECT_ROOT/scripts/clone_siimut_application.sh" ]]; then
        "$PROJECT_ROOT/scripts/clone_siimut_application.sh" --dir "$PROJECT_ROOT/site"
      else
        echo "    Warning: clone_siimut_application.sh not found, skipping"
      fi
      ;;
    iam)
      echo "  - Setting up Laravel-IAM…"
      if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -d "$PROJECT_ROOT/$proj_dir/.git" ]]; then
        if [[ -x "$PROJECT_ROOT/scripts/clone_laravel_iam.sh" ]]; then
          "$PROJECT_ROOT/scripts/clone_laravel_iam.sh" --dir "$PROJECT_ROOT/site"
        else
          echo "    Warning: clone_laravel_iam.sh not found. Run: ./scripts/clone_laravel_iam.sh"
        fi
      else
        echo "    ✓ Laravel-IAM already exists"
      fi
      ;;
    client)
      echo "  - Setting up Client-IIAM…"
      if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -d "$PROJECT_ROOT/$proj_dir/.git" ]]; then
        if [[ -x "$PROJECT_ROOT/scripts/clone_client_iiam.sh" ]]; then
          "$PROJECT_ROOT/scripts/clone_client_iiam.sh" --dir "$PROJECT_ROOT/site"
        else
          echo "    Warning: clone_client_iiam.sh not found. Run: ./scripts/clone_client_iiam.sh"
        fi
      else
        echo "    ✓ Client-IIAM already exists"
      fi
      ;;
  esac
done

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
  for proj in $PROJECTS; do
    proj_dir="${PROJECT_DIRS[$proj]}"
    if [[ -d "$PROJECT_ROOT/$proj_dir" ]]; then
      cp "$PROJECT_ROOT/docker/entrypoint.sh" "$PROJECT_ROOT/$proj_dir/entrypoint.sh"
      echo "  - Copied entrypoint to $proj_dir"
    fi
  done
else
  echo "Warning: docker/entrypoint.sh tidak ditemukan; lewati."
fi

echo "[5/7] Build & up…"
if [[ "$REBUILD" == true ]]; then
  dc build --progress=plain
fi
dc up -d --remove-orphans

echo "[6/7] Inisialisasi Laravel untuk semua project…"

# Function untuk setup satu project Laravel
setup_laravel_project() {
  local proj="$1"
  local service="${PROJECT_SERVICES[$proj]}"
  local proj_dir="${PROJECT_DIRS[$proj]}"
  
  echo ""
  echo "  ═══ Setting up $proj (${service}) ═══"
  
  # Cek apakah direktori project ada
  if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -f "$PROJECT_ROOT/$proj_dir/composer.json" ]]; then
    echo "  ⚠️  $proj_dir tidak ada atau bukan Laravel project, skip."
    return
  fi
  
  # Tunggu service siap
  echo "  - Menunggu service '$service' siap…"
  tries=0
  until dc exec -T "$service" php -v >/dev/null 2>&1; do
    tries=$((tries+1)); [[ $tries -gt 30 ]] && { echo "  ⚠️  Timeout menunggu '$service', skip."; return; }
    sleep 2
  done
  
  # Pastikan vendor ada
  dc exec -T "$service" sh -lc 'mkdir -p vendor' || true
  
  # Composer install jika perlu
  if ! dc exec -T "$service" test -f vendor/autoload.php; then
    echo "  - composer install…"
    dc exec -T "$service" /bin/sh -lc 'export COMPOSER_CACHE_DIR=/tmp/composer-cache COMPOSER_HOME=/tmp/composer-home COMPOSER_TMP_DIR=/tmp; composer install --prefer-dist --no-interaction --no-progress' || true
  fi

  # Pastikan .env ada
  if ! dc exec -T "$service" test -f .env; then
    echo "  - .env tidak ditemukan, menyalin dari .env.example"
    dc exec -T "$service" php -r 'file_exists(".env") || copy(".env.example", ".env");' || true
  fi
  
  # Sinkron DB config
  echo "  - Sinkronisasi konfigurasi database…"
  dc exec -T "$service" /bin/sh -lc 'set -e; \
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
  
  # Bersih cache config
  echo "  - Membersihkan cache…"
  dc exec -T "$service" sh -lc 'rm -f bootstrap/cache/config.php bootstrap/cache/services.php || true'
  dc exec -T "$service" sh -lc 'CACHE_DRIVER=file php artisan optimize:clear || true'
  
  # APP_KEY + migrasi + storage link
  echo "  - Generate APP_KEY, migrate, storage link…"
  dc exec -T "$service" php artisan key:generate --force || true
  dc exec -T "$service" php -r 'if(!preg_match("/^APP_KEY=.+$/m", file_get_contents(".env"))){$k="base64:".base64_encode(random_bytes(32)); $e=file_get_contents(".env"); if(preg_match("/^APP_KEY=.*$/m",$e)){$e=preg_replace("/^APP_KEY=.*$/m","APP_KEY=".$k,$e);}else{$e.="\nAPP_KEY=".$k."\n";} file_put_contents(".env",$e);}'
  
  dc exec -T "$service" php artisan migrate --force || echo "  ⚠️  Migration failed for $proj"
  dc exec -T "$service" php artisan storage:link || true
  dc exec -T "$service" git config --global --add safe.directory /var/www/html || true
  dc exec -T "$service" /bin/sh -lc 'yes | composer run --no-interaction setup' || true
  
  # Cache config untuk production
  dc exec -T "$service" sh -lc 'if [ "${APP_ENV:-production}" = "production" ]; then php artisan config:cache || true; fi'
  
  echo "  ✓ $proj setup complete!"
}

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

# Setup semua project
for proj in $PROJECTS; do
  setup_laravel_project "$proj"
done

# ---- Bagian Node/npm (sekali jalan) untuk semua project ----
if [[ "$NODE_BUILD" == "true" ]]; then
  echo ""
  echo "[6b/7] Build frontend (npm) untuk semua project…"
  if dc config --services | grep -qx "$SERVICE_NODE"; then
    for proj in $PROJECTS; do
      proj_dir="${PROJECT_DIRS[$proj]}"
      node_dir="${PROJECT_NODE_DIRS[$proj]}"
      
      if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -f "$PROJECT_ROOT/$proj_dir/package.json" ]]; then
        echo "  - $proj: package.json tidak ditemukan, skip build"
        continue
      fi
      
      echo "  - Building $proj…"
      # Pastikan direktori build bisa ditulis
      dc run --rm "$SERVICE_NODE" /bin/sh -lc "cd $node_dir && mkdir -p public/build/assets && chmod -R 0777 public/build" || true
      dc run --rm "$SERVICE_NODE" /bin/sh -lc "cd $node_dir && (npm ci || npm install)" || echo "    ⚠️  npm install failed for $proj"
      dc run --rm "$SERVICE_NODE" /bin/sh -lc "cd $node_dir && npm run build" || echo "    ⚠️  npm build failed for $proj"
      
      if [[ "$CLEAN_NODE_MODULES" == "true" ]]; then
        dc run --rm "$SERVICE_NODE" /bin/sh -lc "cd $node_dir && rm -rf node_modules"
      fi
    done
  else
    echo "  - Warning: service '$SERVICE_NODE' tidak didefinisikan di docker-compose; lewati build frontend."
  fi
else
  echo "[6b/7] Skip build frontend (NODE_BUILD=false)"
fi

echo
echo "[7/7] Selesai! Semua aplikasi siap:"
for proj in $PROJECTS; do
  port="${PROJECT_PORTS[$proj]}"
  echo "  - ${proj^^}: http://localhost:${port}"
done
echo ""
echo "Kontainer aktif: $SERVICE_WEB (web), $SERVICE_DB (db:$DB_CHOICE), $SERVICE_NODE (node)"
echo "PHP-FPM services: $(for p in $PROJECTS; do echo -n "${PROJECT_SERVICES[$p]} "; done)"
