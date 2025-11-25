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
NODE_VOLUME_UID="${NODE_VOLUME_UID:-1000}"
NODE_VOLUME_GID="${NODE_VOLUME_GID:-1000}"
NODE_FIX_PERMISSIONS="${NODE_FIX_PERMISSIONS:-true}"

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
DB_CHOICE="${DB_CHOICE:-mysql}"   # default mysql instead of pgsql
AUTO_DOTENV="${AUTO_DOTENV:-ask}"               # ask | copy | manual

# Database names untuk setiap project
DB_SIIMUT="${DB_SIIMUT:-siimut}"
DB_IAM="${DB_IAM:-laravel_iam}"
DB_CLIENT="${DB_CLIENT:-client_iiam}"

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

fail() {
  local msg="$1"
  echo "Error: ${msg}" >&2
  exit 1
}

# Fungsi bantu: baca nilai dari .env.docker (jika tidak ada gunakan default)
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

run_or_fail() {
  local action="$1"; shift
  "$@" && return 0
  fail "$action"
}

ensure_mysql_database() {
  local db_name="$1"
  local charset="${2:-utf8mb4}"
  local collate="${3:-utf8mb4_unicode_ci}"
  local root_pass
  root_pass="$(env_from_file MYSQL_ROOT_PASSWORD root)"
  local sql
  sql="CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET ${charset} COLLATE ${collate};"
  echo "  - Memastikan database '${db_name}' ada…"
  local attempts=0
  until dc exec -T "$SERVICE_DB" env MYSQL_PWD="$root_pass" mysql -uroot -e "$sql"; do
    attempts=$((attempts+1))
    if (( attempts >= 5 )); then
      fail "Membuat database ${db_name}"
    fi
    echo "    DB belum siap, retry ($attempts)…"
    sleep 2
  done
}

ensure_node_permissions() {
  local node_dir="$1"
  [[ "$NODE_FIX_PERMISSIONS" != "true" ]] && return 0
  echo "    • Fixing permissions in $node_dir"
  run_or_fail "Memperbaiki permission frontend ($node_dir)" \
    dc exec -T -u 0 "$SERVICE_NODE" sh -c "chown -R ${NODE_VOLUME_UID}:${NODE_VOLUME_GID} '$node_dir'"
}

wait_for_mysql_service() {
  local root_pass attempts=0
  root_pass="$(env_from_file MYSQL_ROOT_PASSWORD root)"
  echo "[5.5/7] Menunggu service database siap…"
  until dc exec -T "$SERVICE_DB" env MYSQL_PWD="$root_pass" mysqladmin ping -h 127.0.0.1 -uroot --silent >/dev/null 2>&1; do
    attempts=$((attempts+1))
    if (( attempts > 30 )); then
      fail "Service database tidak bisa dihubungi"
    fi
    sleep 2
  done
  echo "  - Database siap digunakan"
}


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

# Siapkan compose flags - hanya gunakan base compose file (MySQL sudah included)
COMPOSE_FLAGS=( -f "$PROJECT_ROOT/docker-compose.yml" )

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
    local db_user db_pass root_pass
    db_user="${MYSQL_USER:-${DB_USERNAME:-laravel}}"
    db_pass="${MYSQL_PASSWORD:-${DB_PASSWORD:-laravel}}"
    root_pass="${MYSQL_ROOT_PASSWORD:-root}"
    cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
# MySQL Configuration
DB_DRIVER=mysql
MYSQL_ROOT_PASSWORD=${root_pass}
MYSQL_USER=${db_user}
MYSQL_PASSWORD=${db_pass}

# Database names per project
DB_SIIMUT=${DB_SIIMUT}
DB_IAM=${DB_IAM}
DB_CLIENT=${DB_CLIENT}

# Common DB credentials (untuk compatibility)
DB_USER=${db_user}
DB_PASSWORD=${db_pass}
ENVEOF
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
        create_env_docker
      fi ;;
    E|ENV)
      create_env_docker ;;
    M|MANUAL)
      echo "  Mode manual: isi beberapa nilai (biarkan kosong untuk default)."
      read -r -p "  MYSQL_USER (default: laravel): " IN_USER || IN_USER=""
      read -r -p "  MYSQL_PASSWORD (default: laravel): " IN_PASS || IN_PASS=""
      read -r -p "  MYSQL_ROOT_PASSWORD (default: root): " IN_ROOT || IN_ROOT=""
      
      MYSQL_USER=${IN_USER:-laravel}
      MYSQL_PASSWORD=${IN_PASS:-laravel}
      MYSQL_ROOT_PASSWORD=${IN_ROOT:-root}
      
      cat > "$PROJECT_ROOT/.env.docker" <<ENVEOF
# MySQL Configuration
DB_DRIVER=mysql
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# Database names per project
DB_SIIMUT=${DB_SIIMUT}
DB_IAM=${DB_IAM}
DB_CLIENT=${DB_CLIENT}

# Common DB credentials
DB_USER=${MYSQL_USER}
DB_PASSWORD=${MYSQL_PASSWORD}
ENVEOF
      ;;
    *)
      create_env_docker ;;
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

wait_for_mysql_service

echo "[6/7] Inisialisasi Laravel untuk semua project…"

# Function untuk setup satu project Laravel
setup_laravel_project() {
  local proj="$1"
  local service="${PROJECT_SERVICES[$proj]}"
  local proj_dir="${PROJECT_DIRS[$proj]}"
  
  # Tambahkan validasi untuk memastikan nilai $proj sesuai dengan array yang didefinisikan
  if [[ -z "${PROJECT_SERVICES[$proj]}" ]]; then
    fail "Project '$proj' tidak valid atau tidak didefinisikan dalam PROJECT_SERVICES."
  fi
  if [[ -z "${PROJECT_DIRS[$proj]}" ]]; then
    fail "Project '$proj' tidak valid atau tidak didefinisikan dalam PROJECT_DIRS."
  fi
  
  # Tentukan database name berdasarkan project
  local db_name
  case "$proj" in
    siimut) db_name="$DB_SIIMUT" ;;
    iam) db_name="$DB_IAM" ;;
    client) db_name="$DB_CLIENT" ;;
    *) db_name="laravel" ;;
  esac
  
  echo ""
  echo "  ═══ Setting up $proj (${service}) - DB: $db_name ═══"
  
  # Cek apakah direktori project ada
  if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -f "$PROJECT_ROOT/$proj_dir/composer.json" ]]; then
    echo "  ⚠️  $proj_dir tidak ada atau bukan Laravel project, skip."
    return
  fi

  ensure_mysql_database "$db_name"
  
  # Tunggu service siap
  echo "  - Menunggu service '$service' siap…"
  local tries=0
  until dc exec -T "$service" php -v >/dev/null 2>&1; do
    tries=$((tries+1)); [[ $tries -gt 30 ]] && { echo "  ⚠️  Timeout menunggu '$service', skip."; return; }
    sleep 2
  done
  
  # Pastikan vendor ada
  run_or_fail "Membuat direktori vendor untuk $proj" \
    dc exec -T "$service" sh -lc 'mkdir -p vendor'
  
  # Composer install jika perlu dan hapus cache dalam bootstrap
  if ! dc exec -T "$service" test -f vendor/autoload.php; then
    echo "  - Remove cache"
    run_or_fail "Membersihkan cache bootstrap untuk $proj" \
      dc exec -T "$service" /bin/sh -lc 'set -e; export COMPOSER_CACHE_DIR=/tmp/composer-cache COMPOSER_HOME=/tmp/composer-home COMPOSER_TMP_DIR=/tmp; rm -rf ./bootstrap/cache/*'
    echo "  - composer install…"
    run_or_fail "Composer install untuk $proj" \
      dc exec -T "$service" /bin/sh -lc 'set -e; export COMPOSER_CACHE_DIR=/tmp/composer-cache COMPOSER_HOME=/tmp/composer-home COMPOSER_TMP_DIR=/tmp; composer install --prefer-dist --no-interaction --no-progress'
  fi

  # Pastikan .env ada
  if ! dc exec -T "$service" test -f .env; then
    echo "  - .env tidak ditemukan, menyalin dari .env.example"
    run_or_fail "Menyalin file .env untuk $proj" \
      dc exec -T "$service" php -r 'file_exists(".env") || copy(".env.example", ".env");'
  fi
  
  # Sinkron DB config
  echo "  - Sinkronisasi konfigurasi database…"
  dc exec -T "$service" /bin/sh -lc 'set -e; \
  set_kv() { k="$1"; v="$2"; if grep -qE "^${k}=.*$" .env; then sed -i "s#^${k}=.*#${k}=${v}#" .env; else echo "${k}=${v}" >> .env; fi; }; \
  set_kv DB_CONNECTION mysql; \
  set_kv DB_HOST db; \
  set_kv DB_PORT 3306; \
  set_kv DB_DATABASE "'"$db_name"'"; \
  set_kv DB_USERNAME "${MYSQL_USER:-${DB_USER:-laravel}}"; \
  set_kv DB_PASSWORD "${MYSQL_PASSWORD:-${DB_PASSWORD:-laravel}}"; \
  set_kv DEBUGBAR_ENABLED false; \
  set_kv LARAVEL_DEBUGBAR_ENABLED false; \
  '
    
  # APP_KEY + migrasi + storage link
  echo "  - Generate APP_KEY, migrate, storage link…"
  run_or_fail "php artisan key:generate untuk $proj" \
    dc exec -T "$service" php artisan key:generate --force
  dc exec -T "$service" php -r 'if(!preg_match("/^APP_KEY=.+$/m", file_get_contents(".env"))){$k="base64:".base64_encode(random_bytes(32)); $e=file_get_contents(".env"); if(preg_match("/^APP_KEY=.*$/m",$e)){$e=preg_replace("/^APP_KEY=.*$/m","APP_KEY=".$k,$e);}else{$e.="\nAPP_KEY=".$k."\n";} file_put_contents(".env",$e);}'
  
  run_or_fail "php artisan migrate untuk $proj" \
    dc exec -T "$service" php artisan migrate --force
  run_or_fail "php artisan storage:link untuk $proj" \
    dc exec -T "$service" php artisan storage:link --force
  dc exec -T "$service" git config --global --add safe.directory /var/www/html || true
  run_or_fail "Menjalankan composer setup untuk $proj" \
    dc exec -T "$service" /bin/sh -lc 'set -e; if composer run --list --no-ansi 2>/dev/null | grep -q " setup"; then yes | composer run --no-interaction setup; fi'
  
  # Cache config untuk production
  run_or_fail "php artisan config:cache untuk $proj (opsional)" \
    dc exec -T "$service" sh -lc 'if [ "${APP_ENV:-production}" = "production" ]; then php artisan config:cache; fi'
  
  echo "  ✓ $proj setup complete!"
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
    # Tunggu node container siap
    echo "  - Menunggu node container siap…"
    tries=0
    until dc exec -T "$SERVICE_NODE" node --version >/dev/null 2>&1; do
      tries=$((tries+1)); [[ $tries -gt 20 ]] && { echo "  ⚠️  Timeout menunggu node container"; break; }
      sleep 2
    done
    
    for proj in $PROJECTS; do
      proj_dir="${PROJECT_DIRS[$proj]}"
      node_dir="${PROJECT_NODE_DIRS[$proj]}"
      
      if [[ ! -d "$PROJECT_ROOT/$proj_dir" ]] || [[ ! -f "$PROJECT_ROOT/$proj_dir/package.json" ]]; then
        echo "  - $proj: package.json tidak ditemukan, skip build"
        continue
      fi
      
      echo "  - Building $proj…"
      
      # Fix permissions SEBELUM build - jalankan sebagai root
      echo "    • Fixing permissions..."
      dc exec -T -u 0 "$SERVICE_NODE" sh -c "chown -R 1000:1000 $node_dir" || echo "    ⚠️  Warning: tidak bisa fix permission, lanjutkan..."
      
      # Pastikan direktori build bisa ditulis
      echo "    • Preparing build directories..."
      dc exec -T "$SERVICE_NODE" sh -c "cd $node_dir && mkdir -p public/build/assets node_modules" || true
      
      # Install dependencies
      echo "    • Installing npm packages..."
      if dc exec -T "$SERVICE_NODE" sh -c "cd $node_dir && npm ci 2>/dev/null"; then
        echo "      ✓ npm ci berhasil"
      elif dc exec -T "$SERVICE_NODE" sh -c "cd $node_dir && npm install"; then
        echo "      ✓ npm install berhasil"
      else
        echo "    ⚠️  npm install failed for $proj, skip build"
        continue
      fi
      
      # Build assets
      echo "    • Building assets..."
      if dc exec -T "$SERVICE_NODE" sh -c "cd $node_dir && npm run build"; then
        echo "      ✓ npm build berhasil"
      else
        echo "    ⚠️  npm build failed for $proj"
        continue
      fi
      
      if [[ "$CLEAN_NODE_MODULES" == "true" ]]; then
        echo "    • Cleaning node_modules..."
        dc exec -T "$SERVICE_NODE" sh -c "cd $node_dir && rm -rf node_modules" || true
      fi
      
      echo "    ✓ $proj frontend build complete"
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
  case "$proj" in
    siimut) db_name="$DB_SIIMUT" ;;
    iam) db_name="$DB_IAM" ;;
    client) db_name="$DB_CLIENT" ;;
    *) db_name="unknown" ;;
  esac
  echo "  - ${proj^^}: http://localhost:${port} (DB: $db_name)"
done
echo ""
echo "Kontainer aktif: $SERVICE_WEB (web), $SERVICE_DB (db:mysql), $SERVICE_NODE (node)"
echo "PHP-FPM services: $(for p in $PROJECTS; do echo -n "${PROJECT_SERVICES[$p]} "; done)"
echo ""
echo "MySQL Database: localhost:3307 (root password: dari .env.docker)"
echo "  - Database siimut: $DB_SIIMUT"
echo "  - Database iam: $DB_IAM"
echo "  - Database client: $DB_CLIENT"
echo ""
echo "phpMyAdmin: http://localhost:8090"
echo "  - Server: db"
echo "  - Username: root atau laravel"
echo "  - Password: dari .env.docker"
