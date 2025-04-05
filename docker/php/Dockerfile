# Stage 1: Instalar dependencias de Composer
FROM composer:latest AS composer_deps

COPY laravel/composer.* /app/
WORKDIR /app
RUN composer install --no-dev --optimize-autoloader --no-scripts

# Stage 2: Instalar dependencias de Node.js
FROM node:20 AS node_deps

WORKDIR /app

# Copiar SOLO los archivos de dependencias primero
COPY laravel/package.json laravel/package-lock.json ./ 

# Instalar dependencias (incluyendo countup.js)
RUN npm ci --production

# Copiar el resto de archivos
COPY laravel/. .

# Construir assets
RUN npm run build

# Stage 3: Construir la imagen final
FROM php:8.3-fpm

# Instalar dependencias del sistema (incluyendo libwebp y libsqlite3)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    libpng-dev \
    libwebp-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    zip \
    curl \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libicu-dev \
    libsqlite3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configurar e instalar extensiones PHP (todo en un solo RUN)
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    && docker-php-ext-install \
    pdo_mysql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    intl \
    opcache \
    pdo_sqlite

# Habilitar opcache
RUN docker-php-ext-enable opcache

# Copiar dependencias de Composer
COPY --from=composer_deps /app/vendor /var/www/vendor

# Copiar assets construidos con Vite desde el stage node_deps
COPY --from=node_deps /app/public/build /var/www/public/build

# Copiar código fuente restante
COPY laravel/. /var/www

# Configurar PHP-FPM
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Directorio de trabajo y permisos
WORKDIR /var/www
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -m appuser && \
    chown -R appuser:appuser /var/www && \
    chmod -R 775 storage bootstrap/cache

USER appuser

EXPOSE 9000
CMD ["php-fpm"]