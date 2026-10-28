FROM php:8.5.12-fpm-alpine

RUN apk add --no-cache libzip-dev icu-dev oniguruma-dev nginx supervisor \
 && docker-php-ext-install pdo_mysql mbstring zip bcmath intl \
 && rm -rf /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-req=php

COPY . .
RUN composer dump-autoload --optimize \
 && chown -R www-data:www-data storage bootstrap/cache

COPY docker/nginx-prod.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/php-fpm-pool.conf /usr/local/etc/php-fpm.d/zzz-pool-override.conf
COPY docker/opcache-prod.ini /usr/local/etc/php/conf.d/zz-opcache-prod.ini
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
# storage/ is a persistent named volume in production, mounted at container
# start -- after the build, so anything baked into storage/ at build time
# (like Swagger's generated api-docs.json) gets shadowed by the volume's
# existing content. Regenerating in the entrypoint, once the real volume is
# mounted, is what actually survives redeploys instead of 404ing forever.
ENTRYPOINT ["/entrypoint.sh"]
