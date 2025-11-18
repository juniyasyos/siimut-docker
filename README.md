# Siimut Docker - Multi Project

Stack Docker untuk menjalankan 3 aplikasi Laravel dengan Caddy dan Postgres.

## Project yang Tersedia
1. **SI-IMUT** - Port 8080 (Aplikasi utama)
2. **Laravel-IAM** - Port 8081 (Identity & Access Management)
3. **Client-IIAM** - Port 8082 (Client Application)

## Prasyarat
- Docker Engine + `docker compose`
- Git

## Setup Awal

### Opsi 1: Setup Otomatis (Recommended)
```bash
# Setup semua project sekaligus
./run.sh

# Atau pilih project tertentu
./run.sh --projects "siimut iam"
./run.sh --projects "siimut"
```

Script ini akan otomatis:
- Clone/update semua repository
- Setup .env untuk setiap project
- Install dependencies (composer & npm)
- Generate APP_KEY
- Run migrations
- Build frontend assets

### Opsi 2: Setup Manual

### Opsi 2: Setup Manual

#### 1. Clone Project Laravel-IAM
```bash
./scripts/clone_laravel_iam.sh
```

#### 2. Clone Project Client-IIAM
```bash
./scripts/clone_client_iiam.sh
```

#### 3. Clone Project SI-IMUT
```bash
./scripts/clone_siimut_application.sh --dir ./site
```

#### 4. Jalankan Semua Project
```bash
docker-compose up -d
```

Akses aplikasi di:
- **SI-IMUT**: http://localhost:8080
- **Laravel-IAM**: http://localhost:8081
- **Client-IIAM**: http://localhost:8082

## Struktur Layanan

### Shared Services
- `web` (Caddy) — **1 instance** melayani semua project di port berbeda
- `node` (Node) — **1 instance** untuk build assets semua project
- `db` (MySQL 8.4) — **1 database server** dengan 3 database terpisah

### Application Containers
- `app-siimut` (PHP-FPM) — Laravel SI-IMUT (Port 8080, DB: siimut)
- `app-iam` (PHP-FPM) — Laravel IAM (Port 8081, DB: laravel_iam)
- `app-client` (PHP-FPM) — Client IIAM (Port 8082, DB: client_iiam)

**Total: 6 containers** (1 Caddy + 3 PHP-FPM + 1 Node + 1 MySQL)

## Variabel Lingkungan Compose
Isi di file `.env.docker` (dibaca oleh `docker-compose.yml`):
- `MYSQL_ROOT_PASSWORD`: Password root MySQL
- `MYSQL_USER`: User untuk semua aplikasi
- `MYSQL_PASSWORD`: Password user MySQL
- `DB_SIIMUT`, `DB_IAM`, `DB_CLIENT`: Nama database per project

Contoh: lihat `.env.docker.example`.

## Perintah Umum

### Manajemen Container
```bash
# Start semua services
docker-compose up -d

# Stop semua services
docker-compose down

# Lihat logs semua services
docker-compose logs -f

# Lihat logs service tertentu
docker-compose logs -f app-siimut
docker-compose logs -f app-iam
docker-compose logs -f app-client
```

### Masuk ke Container
```bash
# Masuk ke container SI-IMUT
docker exec -it siimut-app bash

# Masuk ke container Laravel-IAM
docker exec -it iam-app bash

# Masuk ke container Client-IIAM
docker exec -it client-app bash
```

### Perintah Laravel per Project
```bash
# SI-IMUT
docker exec -it siimut-app php artisan migrate
docker exec -it siimut-app php artisan key:generate

# Laravel-IAM
docker exec -it iam-app php artisan migrate
docker exec -it iam-app php artisan key:generate

# Client-IIAM
docker exec -it client-app php artisan migrate
docker exec -it client-app php artisan key:generate
```

### Build Assets dengan Node (Shared Container)
```bash
# Masuk ke container node
docker exec -it siimut-node sh

# Build SI-IMUT
cd /var/www/siimut
npm install && npm run build

# Build Laravel-IAM
cd /var/www/iam
npm install && npm run build

# Build Client-IIAM
cd /var/www/client
npm install && npm run build
```

## Akses Database

### phpMyAdmin (GUI)
Akses phpMyAdmin di: **http://localhost:8090**

Login credentials:
- **Server**: db
- **Username**: root atau laravel
- **Password**: sesuai `.env.docker` (default: root untuk root, laravel untuk user)

### Dari Host Machine (CLI)
```bash
mysql -h 127.0.0.1 -P 3307 -u laravel -p
# Password: laravel (sesuai .env.docker)

# Atau dengan root
mysql -h 127.0.0.1 -P 3307 -u root -p
# Password: root (sesuai .env.docker)
```

### Dari Container Aplikasi
```bash
# Database sudah dikonfigurasi otomatis via environment variables
docker exec -it siimut-app php artisan db:show
docker exec -it iam-app php artisan db:show
docker exec -it client-app php artisan db:show
```

### Database Per Project
- **SI-IMUT**: database `siimut`
- **Laravel-IAM**: database `laravel_iam`
- **Client-IIAM**: database `client_iiam`

Semua database menggunakan user yang sama (`laravel`) dengan password yang sama, memudahkan manajemen namun tetap terpisah datanya.

## Catatan
- Volume kode:
  - SI-IMUT: `./site/siimut-application:/var/www/html`
  - Laravel-IAM: `./site/laravel-iam:/var/www/html`
  - Client-IIAM: `./site/client-iiam:/var/www/html`
- Setiap project memiliki vendor volume terpisah untuk menghindari konflik
- Build context memakai `docker/php/Dockerfile` yang sama untuk semua project
- DB service name: `db-postgress` (container: `siimut-db-postgress`)
- Setiap project memiliki Caddy instance terpisah dengan port berbeda

## Troubleshooting Cepat
- Port sudah dipakai: ubah mapping port di `docker-compose.yml`
- Migrasi gagal saat awal: jalankan `docker exec -it <container-name> php artisan migrate --force`
- Rebuild image tertentu: `docker-compose build <service-name>`
- Rebuild semua: `docker-compose build --no-cache`
- Bersih total: `docker-compose down -v` (hapus volumes)

## Opsi run.sh (Untuk SI-IMUT)
- `./run.sh --rebuild` : rebuild image sebelum up
- `./run.sh --fresh`   : hapus volumes (data DB) lalu up ulang
