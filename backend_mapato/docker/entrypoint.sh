#!/bin/sh
set -e

# storage/ is a persistent named volume in production, mounted AFTER the
# image (with whatever was baked into it at build time, including
# storage/api-docs/) is already built -- so the volume's existing content
# shadows the image's copy. Regenerating here, once the volume is actually
# mounted, is what makes the Swagger docs survive redeploys instead of
# silently 404ing forever after the first deploy that introduced this file.
php artisan l5-swagger:generate || true
php /var/www/html/docker/reorder-swagger-tags.php || true
chown -R www-data:www-data storage/api-docs 2>/dev/null || true

# Redis keeps its data on the storage volume (docker/redis.conf).
mkdir -p storage/redis && chown -R redis:redis storage/redis 2>/dev/null || true
exec supervisord -c /etc/supervisord.conf
