# =========================
# Stage 1: base system
# =========================
FROM php:8.4-fpm-alpine AS base

ARG UID=1000
ARG GID=1000
ARG APP_ENV=production          # production|local
ARG ENABLE_XDEBUG=false         # true|false
ARG TZ=Asia/Jakarta

RUN apk add --no-cache \
      tzdata bash git shadow ca-certificates unzip \
      icu-dev oniguruma-dev libzip-dev zlib-dev \
      libpng-dev libjpeg-turbo-dev freetype-dev \
      libxml2-dev postgresql-dev \
      linux-headers \ 
      $PHPIZE_DEPS \
      vim \
  && cp /usr/share/zoneinfo/${TZ} /etc/localtime && echo "${TZ}" > /etc/timezone \
  && docker-php-ext-configure intl \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" \
       intl mbstring pdo pdo_mysql pdo_pgsql pgsql zip gd \
       bcmath exif pcntl sockets opcache \
  && pecl install igbinary \
  && docker-php-ext-enable igbinary \
  && pecl install redis \
  && docker-php-ext-enable redis \
  && if [ "$ENABLE_XDEBUG" = "true" ]; then pecl install xdebug && docker-php-ext-enable xdebug ; fi \
  && apk del --no-network $PHPIZE_DEPS


COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# non-root
RUN addgroup -g ${GID} www && adduser -D -G www -u ${UID} www \
  && usermod -aG www-data www || true \
  && usermod -u ${UID} www-data || true && groupmod -g ${GID} www-data || true

WORKDIR /var/www/html

# =========================
# Stage 2: deps (composer install - optional)
# =========================
FROM base AS deps

# Salin composer manifest untuk cache layer yang baik
# (lock file ada di repo Anda jadi aman untuk disalin bersama)
COPY composer.json ./

ENV COMPOSER_CACHE_DIR=/tmp/composer-cache

RUN set -eux; \
    if [ -f composer.json ]; then \
      echo ">> composer.json found"; \
      # Di stage deps belum ada source code lengkap -> hindari eksekusi script artisan
      if [ "$APP_ENV" = "production" ]; then \
        composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader; \
      else \
        composer install --prefer-dist --no-interaction --no-progress --no-scripts; \
      fi; \
    else \
      echo '>> composer.json not found. Skipping deps stage (this is OK for a fresh repo).'; \
    fi \
  && rm -rf "$COMPOSER_CACHE_DIR"

# Pastikan direktori vendor selalu ada agar COPY dari stage ini tidak gagal
RUN mkdir -p /var/www/html/vendor

# =========================
# Stage 3: app (final)
# =========================
FROM base AS app

ENV APP_ENV=${APP_ENV}
ENV PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

RUN set -eux; \
  { \
    echo "memory_limit=512M"; \
    echo "upload_max_filesize=64M"; \
    echo "post_max_size=64M"; \
    echo "max_execution_time=120"; \
    echo "date.timezone=${TZ}"; \
  } > /usr/local/etc/php/conf.d/laravel.ini; \
  { \
    echo "opcache.enable=1"; \
    echo "opcache.enable_cli=0"; \
    echo "opcache.jit=1255"; \
    echo "opcache.jit_buffer_size=64M"; \
    echo "opcache.memory_consumption=192"; \
    echo "opcache.interned_strings_buffer=16"; \
    echo "opcache.max_accelerated_files=100000"; \
    echo "opcache.revalidate_freq=0"; \
    echo "opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \
  } > /usr/local/etc/php/conf.d/opcache.ini; \
  { \
    echo "redis.serializer=igbinary"; \
    echo "session.serialize_handler=php_serialize"; \
  } > /usr/local/etc/php/conf.d/redis.ini; \
  sed -ri 's|^;?pm\.max_children =.*|pm.max_children = 20|' /usr/local/etc/php-fpm.d/www.conf && \
  sed -ri 's|^;?pm\.start_servers =.*|pm.start_servers = 4|' /usr/local/etc/php-fpm.d/www.conf && \
  sed -ri 's|^;?pm\.min_spare_servers =.*|pm.min_spare_servers = 2|' /usr/local/etc/php-fpm.d/www.conf && \
  sed -ri 's|^;?pm\.max_spare_servers =.*|pm.max_spare_servers = 8|' /usr/local/etc/php-fpm.d/www.conf && \
  sed -ri 's|^;?clear_env =.*|clear_env = no|' /usr/local/etc/php-fpm.d/www.conf

# vendor dari stage deps (selalu ada karena kita buatkan direktori kosong di stage deps)
COPY --from=deps /var/www/html/vendor ./vendor

# source code
COPY . .

RUN set -eux; \
    if [ -f composer.json ]; then \
      if [ "$APP_ENV" = "production" ]; then \
        composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader; \
      else \
        composer install --prefer-dist --no-interaction --no-progress --no-scripts; \
      fi; \
    else \
      echo '>> composer.json still not found after COPY . .  — periksa build context / struktur proyekmu.'; \
    fi


RUN chown -R www:www storage bootstrap/cache \
 && chmod -R ug+rwX storage bootstrap/cache

USER www
EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD php -r "exit(extension_loaded('pdo_pgsql')?0:1);"

# Runtime bootstrap script to auto-prepare the app
# Note: this expects `entrypoint.sh` to exist inside the build context
# (i.e., inside `./site/siimut-application`). Our root-level run.sh copies it before build.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh && chown www:www /usr/local/bin/entrypoint.sh
USER www

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
