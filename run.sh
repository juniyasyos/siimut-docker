#!/usr/bin/env bash
set -euo pipefail

# run.sh — sekali jalan untuk setup & jalanin stack

# ---- Konfigurasi yang bisa dioverride via ENV ----
COMPOSE_BIN="${COMPOSE_BIN:-docker compose}"
SERVICE_APP="${SERVICE_APP:-app}"      # contoh: laravel-app
SERVICE_WEB="${SERVICE_WEB:-web}"      # contoh: laravel-web
SERVICE_DB="${SERVICE_DB:-db-postgress}"         # contoh: siimut-db-postgress
SERVICE_NODE="${SERVICE_NODE:-node}"   # contoh: siimut-node (nama service, bukan container)
NODE_BUILD="${NODE_BUILD:-true}"       # set false untuk skip npm build
CLEAN_NODE_MODULES="${CLEAN_NODE_MODULES:-false}" # true untuk rm -rf node_modules setelah build
# --------------------------------------------------

REBUILD=false
FRESH=false

usage() {
  cat <<EOF
Pemakaian: ./run.sh [opsi]

Opsi:
  --rebuild   Rebuild image sebelum up
  --fresh     down -v sebelum up (hapus data DB)
  -h, --help  Bantuan
Variabel ENV penting:
  COMPOSE_BIN, SERVICE_APP, SERVICE_WEB, SERVICE_DB, SERVICE_NODE,
  NODE_BUILD=[true|false], CLEAN_NODE_MODULES=[true|false]
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' tidak ditemukan." >&2; exit 1; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    --fresh)   FRESH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opsi tidak dikenal: $1" >&2; usage; exit 2 ;;
  esac
done

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

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
if [[ ! -f "$PROJECT_ROOT/.env.docker" ]]; then
  if [[ -f "$PROJECT_ROOT/.env.docker.example" ]]; then
    cp "$PROJECT_ROOT/.env.docker.example" "$PROJECT_ROOT/.env.docker"
  else
    cat > "$PROJECT_ROOT/.env.docker" <<'ENVEOF'
POSTGRES_DB=laravel
POSTGRES_USER=laravel
POSTGRES_PASSWORD=laravel
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=laravel
ENVEOF
  fi
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
  $COMPOSE_BIN down -v || true
fi

echo "[4.5/7] Sinkronkan entrypoint ke build context (jika ada)…"
if [[ -f "$PROJECT_ROOT/docker/entrypoint.sh" ]]; then
  cp "$PROJECT_ROOT/docker/entrypoint.sh" "$PROJECT_ROOT/site/siimut-application/entrypoint.sh"
else
  echo "Warning: docker/entrypoint.sh tidak ditemukan; lewati."
fi

echo "[5/7] Build & up…"
if [[ "$REBUILD" == true ]]; then
  $COMPOSE_BIN build --progress=plain
fi
$COMPOSE_BIN up -d --remove-orphans

echo "[6/7] Inisialisasi Laravel…"
# Tunggu service APP siap
echo "  - Menunggu service '$SERVICE_APP' siap…"
tries=0
until $COMPOSE_BIN exec -T "$SERVICE_APP" php -v >/dev/null 2>&1; do
  tries=$((tries+1)); [[ $tries -gt 30 ]] && { echo "Timeout menunggu '$SERVICE_APP'"; exit 1; }
  sleep 2
done

# Pastikan vendor ada (kepemilikan akan ditangani entrypoint saat user=root)
$COMPOSE_BIN exec -T "$SERVICE_APP" sh -lc 'mkdir -p vendor' || true

# Pastikan vendor terpasang
if ! $COMPOSE_BIN exec -T "$SERVICE_APP" test -f vendor/autoload.php; then
  echo "  - composer install…"
  $COMPOSE_BIN exec -T "$SERVICE_APP" /bin/sh -lc 'export COMPOSER_CACHE_DIR=/tmp/composer-cache COMPOSER_HOME=/tmp/composer-home COMPOSER_TMP_DIR=/tmp; composer install --prefer-dist --no-interaction --no-progress' || true
fi

# Pastikan .env ada
$COMPOSE_BIN exec -T "$SERVICE_APP" php -r 'file_exists(".env") || copy(".env.example", ".env");' || true

# Sinkron DB config lebih awal (sebelum clear cache yang bisa akses DB)
$COMPOSE_BIN exec -T "$SERVICE_APP" /bin/sh -lc 'set -e; \
  set_kv() { k="$1"; v="$2"; if grep -qE "^${k}=.*$" .env; then sed -i "s#^${k}=.*#${k}=${v}#" .env; else echo "${k}=${v}" >> .env; fi; }; \
  set_kv DB_CONNECTION pgsql; \
  set_kv DB_HOST '"$SERVICE_DB"'; \
  set_kv DB_PORT 5423; \
  set_kv DB_DATABASE "${DB_DATABASE:-${POSTGRES_DB:-laravel}}"; \
  set_kv DB_USERNAME "${DB_USERNAME:-${POSTGRES_USER:-laravel}}"; \
  set_kv DB_PASSWORD "${DB_PASSWORD:-${POSTGRES_PASSWORD:-laravel}}"; \
'

# Bersih cache config (hindari MissingAppKey/akses DB dengan host lama)
$COMPOSE_BIN exec -T "$SERVICE_APP" sh -lc 'rm -f bootstrap/cache/config.php bootstrap/cache/services.php || true'
$COMPOSE_BIN exec -T "$SERVICE_APP" sh -lc 'CACHE_DRIVER=file php artisan optimize:clear || true'

# APP_KEY + migrasi + storage link
$COMPOSE_BIN exec -T "$SERVICE_APP" php artisan key:generate --force || true
$COMPOSE_BIN exec -T "$SERVICE_APP" php -r 'if(!preg_match("/^APP_KEY=.+$/m", file_get_contents(".env"))){$k="base64:".base64_encode(random_bytes(32)); $e=file_get_contents(".env"); if(preg_match("/^APP_KEY=.*$/m",$e)){$e=preg_replace("/^APP_KEY=.*$/m","APP_KEY=".$k,$e);}else{$e.="\nAPP_KEY=".$k."\n";} file_put_contents(".env",$e);}'

$COMPOSE_BIN exec -T "$SERVICE_APP" php artisan migrate --force || true
$COMPOSE_BIN exec -T "$SERVICE_APP" php artisan storage:link || true
# Izinkan git bekerja pada bind mount (hindari "dubious ownership")
$COMPOSE_BIN exec -T "$SERVICE_APP" git config --global --add safe.directory /var/www/html || true
$COMPOSE_BIN exec -T "$SERVICE_APP" composer run setup || true

# ---- Bagian Node/npm (sekali jalan) ----
if [[ "$NODE_BUILD" == "true" ]]; then
  echo "[6b/7] Build frontend (npm)…"
  # Gunakan `run --rm` agar tidak butuh service node selalu hidup.
  if $COMPOSE_BIN config --services | grep -qx "$SERVICE_NODE"; then
    # Pastikan direktori build bisa ditulis oleh user Node
    $COMPOSE_BIN run --rm "$SERVICE_NODE" /bin/sh -lc 'mkdir -p public/build/assets && chmod -R 0777 public/build' || true
    $COMPOSE_BIN run --rm "$SERVICE_NODE" npm ci || $COMPOSE_BIN run --rm "$SERVICE_NODE" npm install
    $COMPOSE_BIN run --rm "$SERVICE_NODE" npm run build
    if [[ "$CLEAN_NODE_MODULES" == "true" ]]; then
      $COMPOSE_BIN run --rm "$SERVICE_NODE" /bin/sh -lc 'rm -rf node_modules'
    fi
  else
    echo "  - Warning: service '$SERVICE_NODE' tidak didefinisikan di docker-compose; lewati build frontend."
  fi
else
  echo "[6b/7] Skip build frontend (NODE_BUILD=false)"
fi

# Cache config untuk production
$COMPOSE_BIN exec -T "$SERVICE_APP" sh -lc 'if [ "${APP_ENV:-production}" = "production" ]; then php artisan config:cache || true; fi'

echo
echo "[7/7] Selesai! Aplikasi siap di: http://localhost:8080"
echo "Kontainer: $SERVICE_WEB (web), $SERVICE_APP (php-fpm), $SERVICE_DB (db)$( [[ "$NODE_BUILD" == "true" ]] && echo ", $SERVICE_NODE (npm run)")"
