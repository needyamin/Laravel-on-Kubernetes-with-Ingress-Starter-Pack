# Multi-stage Dockerfile for Laravel (PHP-FPM) + Nginx via Supervisor
# Usage:
#   docker build -t yourrepo/laravel-app:latest .
#   # Push to a registry accessible by your cluster
#   # Update image in k8s/deployment.yaml

# --- Dependencies Stage ---
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock /app/
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist --optimize-autoloader
COPY . /app
RUN composer dump-autoload --optimize

# --- Build Frontend (optional) ---
# Uncomment if you have a Node-based build
# FROM node:20-alpine AS frontend
# WORKDIR /app
# COPY package.json package-lock.json* pnpm-lock.yaml* yarn.lock* /app/
# RUN npm ci
# COPY . /app
# RUN npm run build

# --- Runtime Stage ---
FROM php:8.3-fpm-alpine

# System deps
RUN apk add --no-cache         nginx supervisor git bash icu-dev oniguruma-dev libzip-dev libpng-dev libjpeg-turbo-dev freetype-dev         curl postgresql-dev mysql-client mariadb-connector-c-dev

# PHP extensions commonly used by Laravel
RUN docker-php-ext-configure gd --with-freetype --with-jpeg &&         docker-php-ext-install -j$(nproc) pdo pdo_mysql pdo_pgsql mbstring exif pcntl gd intl zip bcmath opcache

# Configure PHP
COPY .docker/php.ini /usr/local/etc/php/conf.d/php.ini

# Copy app
WORKDIR /var/www/html
COPY --from=vendor /app /var/www/html

# Nginx config
RUN mkdir -p /run/nginx /var/log/supervisor /etc/nginx/conf.d
COPY .docker/nginx.conf /etc/nginx/nginx.conf
COPY .docker/default.conf /etc/nginx/conf.d/default.conf

# Supervisor config
COPY .docker/supervisord.conf /etc/supervisord.conf

# Permissions for Laravel storage/bootstrap
RUN addgroup -g 1000 www && adduser -G www -g www -s /bin/sh -D www &&         chown -R www:www /var/www/html &&         mkdir -p /var/www/html/storage /var/www/html/bootstrap/cache &&         chown -R www:www /var/www/html/storage /var/www/html/bootstrap/cache

USER www

# Optimize Laravel (ignores if artisan missing in minimal builds)
RUN php artisan config:cache || true &&         php artisan route:cache || true &&         php artisan view:cache || true

EXPOSE 8080
# Supervisor runs php-fpm and nginx together
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
