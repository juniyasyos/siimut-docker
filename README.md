# Siimut Docker

Stack Docker untuk menjalankan backend Laravel Siimut dengan Caddy dan Postgres.

## Prasyarat
- Docker Engine + `docker compose`
- Git

## Sekali Jalan (Disarankan)
Jalankan script berikut dari root repo:

```
./run.sh
```

Apa yang dilakukan:
- Clone/update backend ke `./site/siimut-application`
- Membuat `.env.docker` jika belum ada (pakai default aman)
- Menjalankan `docker compose up -d` dan inisialisasi Laravel (key, migrate, storage link)

Opsi:
- `./run.sh --rebuild` : rebuild image sebelum up
- `./run.sh --fresh`   : hapus volumes (data DB) lalu up ulang

Aplikasi akan tersedia di: http://localhost:8080

## Struktur Layanan
- `web` (Caddy) — reverse proxy + static, listen port `8080`
- `app` (PHP-FPM) — menjalankan Laravel
- `db-postgress` (Postgres 16) — database

## Variabel Lingkungan Compose
Isi di file `.env.docker` (dibaca oleh `docker-compose.yml`):
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`: kredensial DB
- Mirror opsional: `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`

Contoh: lihat `.env.docker.example`.

## Perintah Umum
- Start: `docker compose up -d`
- Stop: `docker compose down`
- Logs: `docker compose logs -f`
- Masuk app: `docker compose exec app bash`

## Catatan
- Volume kode: `./site/siimut-application:/var/www/html`
- Build context `app`: `./site/siimut-application` memakai `docker/php/Dockerfile`
- DB service name: `db-postgress` (container: `siimut-db-postgress`)
- Caddy melayani dokumen root `public/` dan meneruskan PHP ke `app:9000`

## Troubleshooting Cepat
- Port 8080 dipakai: ubah mapping port di `docker-compose.yml`
- Migrasi gagal saat awal: jalankan `docker compose exec -T app php artisan migrate --force`
- Bersih total: `./run.sh --fresh`
